import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Register the Detection context's AR-AI bridge plugin (ARKit + LiDAR).
    SkeenArPlugin.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "SkeenArPlugin")!)

    // Pinhole intrinsics for the marker-based pose (WP-1): the back wide
    // camera's horizontal field of view. The Dart side converts it to a
    // focal length in pixels for the stream it is measuring.
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SkeenCameraIntrinsics")!
    let intrinsics = FlutterMethodChannel(
      name: "skeen.detection/camera_intrinsics",
      binaryMessenger: registrar.messenger()
    )
    intrinsics.setMethodCallHandler { call, result in
      guard call.method == "read" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let device = AVCaptureDevice.default(
        .builtInWideAngleCamera, for: .video, position: .back
      ) else {
        result(nil)
        return
      }
      let fov = Double(device.activeFormat.videoFieldOfView)
      result(fov > 0 ? ["horizontalFovDeg": fov] : nil)
    }
  }
}
