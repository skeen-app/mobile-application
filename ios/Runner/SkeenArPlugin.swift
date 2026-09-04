import ARKit
import AVFoundation
import Flutter
import RealityKit
import UIKit

/// Bridges the Detection bounded context's ArSessionPort to ARKit / RealityKit.
///
/// Architecture:
///   • A single shared `ARSession` lives on the plugin.
///   • `SkeenArView` (a Flutter PlatformView built on `ARView`) renders the
///     camera feed using that shared session — same model as the Android
///     `ArCoreView` + `Session` pairing.
///   • Anchors created by hitTest are kept in `anchors[id]` and refreshed
///     via the ARSessionDelegate so projectToScreen always uses the latest
///     tracked transform — this is what makes the popup stick to the skin.
///   • Flash uses the back-camera AVCaptureDevice torch (ARKit shares the
///     same hardware, so the torch turns on while the session is running).
@objc class SkeenArPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
    ARSessionDelegate
{

    let session = ARSession()
    private var distanceSink: FlutterEventSink?
    private var sampleTimer: Timer?
    private var hasLidar = false
    private var anchors: [String: ARAnchor] = [:]
    weak var hostView: ARView?
    private var lastViewportSize: CGSize = UIScreen.main.bounds.size

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = SkeenArPlugin()
        plugin.session.delegate = plugin

        let methodChannel = FlutterMethodChannel(
            name: "skeen.detection/ar",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(plugin, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: "skeen.detection/ar/distance",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(plugin)

        let factory = SkeenArViewFactory(plugin: plugin)
        registrar.register(factory, withId: "skeen.detection/ar_view")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "probeCapabilities":
            result(probeCapabilities())
        case "start":
            start()
            result(nil)
        case "stop":
            stop()
            result(nil)
        case "hitTest":
            let args = call.arguments as? [String: Any]
            let x = (args?["x"] as? Double) ?? 0.5
            let y = (args?["y"] as? Double) ?? 0.5
            result(hitTest(nx: x, ny: y))
        case "projectToScreen":
            let args = call.arguments as? [String: Any] ?? [:]
            result(projectToScreen(args: args))
        case "anchorState":
            let id = (call.arguments as? [String: Any])?["id"] as? String
            result(["state": anchors[id ?? ""] != nil ? "TRACKING" : "NONE",
                    "exists": anchors[id ?? ""] != nil])
        case "captureFrame":
            result(captureFrame())
        case "setFlash":
            let on = ((call.arguments as? [String: Any])?["on"] as? Bool) ?? false
            setTorch(on: on)
            result(nil)
        case "setZoom":
            result(nil)
        case "removeAnchor":
            if let id = (call.arguments as? [String: Any])?["id"] as? String,
               let a = anchors.removeValue(forKey: id) {
                session.remove(anchor: a)
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func probeCapabilities() -> [String: Any] {
        let arSupported = ARWorldTrackingConfiguration.isSupported
        let lidar = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        hasLidar = lidar
        return ["hasArSupport": arSupported, "hasDepthSensor": lidar]
    }

    private func start() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if hasLidar &&
            ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        startDepthSampling()
    }

    private func stop() {
        sampleTimer?.invalidate()
        sampleTimer = nil
        anchors.values.forEach { session.remove(anchor: $0) }
        anchors.removeAll()
        session.pause()
    }

    // ── Depth sampling ────────────────────────────────────────────────

    private func startDepthSampling() {
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            guard let self = self,
                  let frame = self.session.currentFrame else { return }
            let cm = self.sampleCenterDistanceCm(frame: frame)
            let estimated = !self.hasLidar
            // `brightness` + `tracking` complete the ArFrameInfo contract on
            // the Dart side. ArSessionService._onDistanceEvent only emits an
            // ArFrameInfo when at least one of them is present, so while this
            // payload carried just {cm, estimated} the frameInfo stream never
            // fired on iOS: ArScanScreen kept `_tracking == "UNKNOWN"`, its
            // ready-streak never accumulated and the scene-mapping phase
            // never completed. Both keys use the SAME scale/vocabulary as the
            // Android plugin — see the two helpers below.
            self.distanceSink?([
                "cm": cm,
                "estimated": estimated,
                "brightness": self.sampleMeanLuma(frame: frame),
                "tracking": self.trackingStateName(frame.camera.trackingState)
            ])
        }
    }

    /// Mean luminance of the frame, on the **0–255 mean-Y scale**.
    ///
    /// Scale contract: the Dart thresholds in `CaptureQuality.fromBrightness`
    /// (55 / 85 / 195 / 225) were tuned against the mean of the Y (luma)
    /// plane — the same quantity `ScanCameraService._onImage` computes for
    /// the plain-camera path. This therefore averages the luma plane
    /// directly and deliberately does NOT use ARKit's
    /// `lightEstimate.ambientIntensity` (lux, ~0–2000+) or a normalized
    /// pixel-intensity ratio: those sit on different scales and would
    /// systematically miscoach the user.
    ///
    /// Sampled on a ~32×32 grid — the same density as the Android camera
    /// path — so the 10 Hz timer stays cheap.
    private func sampleMeanLuma(frame: ARFrame) -> Double {
        let buffer = frame.capturedImage
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        // Plane 0 of the biplanar YCbCr buffer ARKit hands back is the
        // full-resolution luma plane.
        guard CVPixelBufferGetPlaneCount(buffer) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
        else { return Double.nan }

        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        guard width > 0, height > 0 else { return Double.nan }

        let stepX = max(1, width / 32)
        let stepY = max(1, height / 32)
        let luma = base.assumingMemoryBound(to: UInt8.self)

        var sum = 0
        var count = 0
        var y = 0
        while y < height {
            let row = y * rowStride
            var x = 0
            while x < width {
                sum += Int(luma[row + x])
                count += 1
                x += stepX
            }
            y += stepY
        }
        guard count > 0 else { return Double.nan }

        let mean = Double(sum) / Double(count)
        // Video-range buffers pack luma into 16…235. Rescale those to the
        // full 0…255 span so the value stays comparable with the Android
        // reading regardless of which format the session negotiated.
        let isVideoRange = CVPixelBufferGetPixelFormatType(buffer)
            == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        guard isVideoRange else { return mean }
        return min(255.0, max(0.0, (mean - 16.0) * 255.0 / 219.0))
    }

    /// Maps ARKit's tracking state onto the **ARCore vocabulary** the Dart
    /// side already speaks: `ArFrameInfo.isTracking` compares against the
    /// literal `"TRACKING"`, and the Android plugin emits
    /// `com.google.ar.core.TrackingState.name()`.
    ///
    ///   ARKit `.normal`       → `"TRACKING"` (ARCore TRACKING — usable)
    ///   ARKit `.limited(_)`   → `"PAUSED"`   (ARCore PAUSED — session alive
    ///                                         but the pose isn't reliable
    ///                                         yet: initializing, excessive
    ///                                         motion, insufficient features)
    ///   ARKit `.notAvailable` → `"STOPPED"`  (ARCore STOPPED — no pose)
    ///
    /// Sharing one vocabulary keeps the readiness gate in `ar_scan_screen`
    /// free of per-platform branches.
    private func trackingStateName(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal:
            return "TRACKING"
        case .limited:
            return "PAUSED"
        case .notAvailable:
            return "STOPPED"
        @unknown default:
            return "UNKNOWN"
        }
    }

    private func sampleCenterDistanceCm(frame: ARFrame) -> Double {
        guard let depth = frame.sceneDepth?.depthMap else { return Double.nan }
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        let w = CVPixelBufferGetWidth(depth)
        let h = CVPixelBufferGetHeight(depth)
        guard let base = CVPixelBufferGetBaseAddress(depth) else { return Double.nan }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depth)
        let row = base.advanced(by: (h / 2) * bytesPerRow)
        let value = row.assumingMemoryBound(to: Float32.self)[w / 2]
        if value.isNaN || value <= 0 { return Double.nan }
        return Double(value) * 100.0
    }

    // ── Hit-test / projection ─────────────────────────────────────────

    private func hitTest(nx: Double, ny: Double) -> [String: Any]? {
        guard let frame = session.currentFrame else { return nil }
        let viewport = lastViewportSize
        let point = CGPoint(x: CGFloat(nx) * viewport.width,
                            y: CGFloat(ny) * viewport.height)

        // Prefer a view-aligned raycast when the ARView is mounted (more
        // accurate; uses the actual rendered camera intrinsics).
        if let view = hostView {
            if let q = view.makeRaycastQuery(from: point,
                                             allowing: .estimatedPlane,
                                             alignment: .any) {
                if let r = view.session.raycast(q).first {
                    return registerAnchor(transform: r.worldTransform)
                }
            }
        }
        // Fallback to frame-level raycastQuery.
        let q = frame.raycastQuery(from: point,
                                   allowing: .estimatedPlane,
                                   alignment: .any)
        if let r = session.raycast(q).first {
            return registerAnchor(transform: r.worldTransform)
        }
        return nil
    }

    private func registerAnchor(transform: simd_float4x4) -> [String: Any] {
        let id = "anchor-\(Int(Date().timeIntervalSince1970 * 1_000_000))"
        let anchor = ARAnchor(name: id, transform: transform)
        anchors[id] = anchor
        session.add(anchor: anchor)
        return poseToMap(transform: transform, id: id)
    }

    private func projectToScreen(args: [String: Any]) -> [String: Any]? {
        guard let frame = session.currentFrame else { return nil }
        let world: SIMD3<Float>
        if let id = args["id"] as? String, let a = anchors[id] {
            let t = a.transform
            world = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        } else {
            world = SIMD3<Float>(
                Float((args["tx"] as? Double) ?? 0),
                Float((args["ty"] as? Double) ?? 0),
                Float((args["tz"] as? Double) ?? 0)
            )
        }

        // Use ARView projection when available — accounts for the actual
        // rendered viewport rather than the screen.
        if let view = hostView {
            if let pt = view.project(world) {
                let bounds = view.bounds.size
                let inFront = !pt.x.isNaN && !pt.y.isNaN
                let visibleX = pt.x >= 0 && pt.x <= bounds.width
                let visibleY = pt.y >= 0 && pt.y <= bounds.height
                return [
                    "visible": inFront && visibleX && visibleY,
                    "sx": Double(pt.x / bounds.width),
                    "sy": Double(pt.y / bounds.height)
                ]
            }
        }

        let viewport = lastViewportSize
        let projected = frame.camera.projectPoint(
            world,
            orientation: .portrait,
            viewportSize: viewport
        )
        let visibleX = projected.x >= 0 && projected.x <= viewport.width
        let visibleY = projected.y >= 0 && projected.y <= viewport.height
        // ARKit returns CGPoint(NaN,NaN) when behind camera in some versions.
        let inFront = !projected.x.isNaN && !projected.y.isNaN
        return [
            "visible": inFront && visibleX && visibleY,
            "sx": Double(projected.x / viewport.width),
            "sy": Double(projected.y / viewport.height)
        ]
    }

    // ── Torch ─────────────────────────────────────────────────────────

    private func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Ignore — camera plugin path will still drive the torch.
        }
    }

    private func captureFrame() -> FlutterStandardTypedData? {
        guard let frame = session.currentFrame else { return nil }
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let ui = UIImage(cgImage: cg, scale: 1, orientation: .right)
        guard let jpeg = ui.jpegData(compressionQuality: 0.92) else { return nil }
        return FlutterStandardTypedData(bytes: jpeg)
    }

    // ── Helpers ───────────────────────────────────────────────────────

    private func poseToMap(transform: simd_float4x4, id: String) -> [String: Any] {
        let t = SIMD3<Float>(transform.columns.3.x,
                             transform.columns.3.y,
                             transform.columns.3.z)
        let q = simd_quatf(transform)
        return [
            "id": id,
            "tx": Double(t.x), "ty": Double(t.y), "tz": Double(t.z),
            "qx": Double(q.imag.x), "qy": Double(q.imag.y),
            "qz": Double(q.imag.z), "qw": Double(q.real)
        ]
    }

    func setHostView(_ view: ARView?) {
        hostView = view
        if let v = view { lastViewportSize = v.bounds.size }
    }

    // ── ARSessionDelegate ─────────────────────────────────────────────

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for updated in anchors {
            if let name = updated.name, self.anchors[name] != nil {
                self.anchors[name] = updated
            }
        }
    }

    // ── EventChannel ──────────────────────────────────────────────────

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        distanceSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        distanceSink = nil
        return nil
    }
}

// MARK: - PlatformView (RealityKit ARView)

class SkeenArViewFactory: NSObject, FlutterPlatformViewFactory {
    private weak var plugin: SkeenArPlugin?
    init(plugin: SkeenArPlugin) {
        self.plugin = plugin
        super.init()
    }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        return SkeenArView(frame: frame, plugin: plugin)
    }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

class SkeenArView: NSObject, FlutterPlatformView {
    private let arView: ARView
    private weak var plugin: SkeenArPlugin?

    init(frame: CGRect, plugin: SkeenArPlugin?) {
        // .nonAR fallback isn't useful here; .cameraMode passes camera through.
        self.arView = ARView(frame: frame, cameraMode: .ar,
                             automaticallyConfigureSession: false)
        self.plugin = plugin
        super.init()
        if let p = plugin {
            arView.session = p.session
            p.setHostView(arView)
        }
    }

    func view() -> UIView { arView }
}
