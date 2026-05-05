import ARKit
import Flutter
import UIKit

/// Bridges the Detection bounded context's ArSessionPort to ARKit + LiDAR.
///
/// Surfaces:
///   • probeCapabilities — reports AR + LiDAR availability
///   • EventChannel("…/distance") — cm-to-skin readings sampled from the
///     ARFrame.sceneDepth.depthMap at the screen-center pixel (~10 Hz).
///   • hitTest / projectToScreen — for Coordinate Translator anchor logic
///
/// The camera preview itself is owned by the existing `camera` Flutter
/// plugin so the AR overlay can sit on top of the same surface as the
/// fallback. ARSession runs in parallel for depth + tracking only.
@objc class SkeenArPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private let session = ARSession()
    private var distanceSink: FlutterEventSink?
    private var sampleTimer: Timer?
    private var hasLidar = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = SkeenArPlugin()
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
        case "captureFrame":
            // Camera plugin owns the preview surface; the Dart controller
            // pulls the JPEG from CameraController.takePicture instead.
            result(nil)
        case "setFlash":
            result(nil)
        case "setZoom":
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func probeCapabilities() -> [String: Any] {
        let arSupported = ARWorldTrackingConfiguration.isSupported
        let lidar = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        hasLidar = lidar
        return [
            "hasArSupport": arSupported,
            "hasDepthSensor": lidar
        ]
    }

    private func start() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
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
        session.pause()
    }

    private func startDepthSampling() {
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            guard let self = self,
                  let frame = self.session.currentFrame else { return }
            let cm = self.sampleCenterDistanceCm(frame: frame)
            let estimated = !self.hasLidar
            self.distanceSink?(["cm": cm, "estimated": estimated])
        }
    }

    /// Reads the depth value at the center pixel of `sceneDepth.depthMap`.
    /// LiDAR returns meters; we convert to centimeters before pushing.
    private func sampleCenterDistanceCm(frame: ARFrame) -> Double {
        guard let depth = frame.sceneDepth?.depthMap else {
            return Double.nan
        }
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        let width = CVPixelBufferGetWidth(depth)
        let height = CVPixelBufferGetHeight(depth)
        let cx = width / 2
        let cy = height / 2
        guard let base = CVPixelBufferGetBaseAddress(depth) else {
            return Double.nan
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depth)
        let row = base.advanced(by: cy * bytesPerRow)
        let value = row.assumingMemoryBound(to: Float32.self)[cx]
        if value.isNaN || value <= 0 { return Double.nan }
        return Double(value) * 100.0
    }

    private func hitTest(nx: Double, ny: Double) -> [String: Any]? {
        guard let frame = session.currentFrame else { return nil }
        let viewport = UIScreen.main.bounds.size
        let point = CGPoint(x: CGFloat(nx) * viewport.width,
                            y: CGFloat(ny) * viewport.height)
        let raycastQuery = frame.raycastQuery(
            from: point,
            allowing: .estimatedPlane,
            alignment: .any
        )
        let results = session.raycast(raycastQuery)
        guard let first = results.first else { return nil }
        let t = first.worldTransform
        let translation = simd_make_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let q = simd_quatf(t)
        return [
            "id": "hit-\(Int(Date().timeIntervalSince1970 * 1000))",
            "tx": Double(translation.x),
            "ty": Double(translation.y),
            "tz": Double(translation.z),
            "qx": Double(q.imag.x),
            "qy": Double(q.imag.y),
            "qz": Double(q.imag.z),
            "qw": Double(q.real)
        ]
    }

    private func projectToScreen(args: [String: Any]) -> [String: Any]? {
        guard let frame = session.currentFrame else { return nil }
        let tx = (args["tx"] as? Double) ?? 0
        let ty = (args["ty"] as? Double) ?? 0
        let tz = (args["tz"] as? Double) ?? 0
        let world = SIMD3<Float>(Float(tx), Float(ty), Float(tz))
        let viewport = UIScreen.main.bounds.size
        let projected = frame.camera.projectPoint(
            world,
            orientation: .portrait,
            viewportSize: viewport
        )
        let inFront = frame.camera.transform.columns.3.z - world.z != 0
        return [
            "visible": inFront,
            "sx": Double(projected.x / viewport.width),
            "sy": Double(projected.y / viewport.height)
        ]
    }

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
