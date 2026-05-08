import 'dart:typed_data';
import 'dart:ui';

import 'ar_geometry.dart';
import 'inference_result.dart';
import 'lesion_analysis.dart';

/// Outbound port for the on-device TFLite classifier. Implementations live
/// in `infrastructure/` (real `tflite_flutter` runtime, web mock, test
/// double) — the application layer depends only on this interface.
abstract class InferenceServicePort {
  Future<void> load();
  Future<InferenceResult> classify(Uint8List jpegBytes);
  Future<void> dispose();
}

/// Outbound port for the native AR session (ARKit + LiDAR on iOS,
/// ARCore + Depth on Android). The Dart side never speaks to platform
/// channels directly.
abstract class ArSessionPort {
  /// Whether the device exposes a usable depth sensor. Drives the route
  /// decision between AR-enabled and the plain camera fallback.
  Future<ArCapabilities> probeCapabilities();

  /// Begins the AR session and starts streaming depth + tracking state.
  /// Idempotent; safe to call when already started.
  Future<void> start();
  Future<void> stop();

  /// Stream of depth-to-skin readings sampled at the screen-center pixel.
  /// Throttled by the platform to ~10 Hz to keep the UI thread responsive.
  Stream<CaptureDistance> get distance;

  /// Hit-test the screen point against the detected skin plane and return
  /// a stable anchor in world space, or null if no plane is hit.
  Future<WorldAnchor?> hitTest(Offset normalizedScreenPoint);

  /// Project a world anchor back into screen-space pixel coordinates so an
  /// overlay widget can be positioned over it on each frame. Returns null
  /// when the anchor is behind the camera or off-screen.
  Future<Offset?> projectToScreen(WorldAnchor anchor);

  /// Capture a JPEG of the current AR frame for inference. Honors flash
  /// and zoom set via [setFlash] / [setZoom].
  Future<Uint8List?> captureFrame();

  Future<void> setFlash(bool on);
  Future<void> setZoom(double zoom);
}

/// Outbound port for camera-level operations (flash, zoom, image streams).
/// Separate from [ArSessionPort] because the camera plugin (`camera`) and
/// the AR session (`skeen.detection/ar`) are independent subsystems —
/// flash/zoom must work even when AR is unavailable.
abstract class ScanCameraServicePort {
  Future<void> initialize();
  bool get isReady;

  /// Brightness (Y-plane mean 0–255) stream, throttled ~3 Hz.
  Stream<double> get brightness;

  /// Sharpness (Laplacian variance normalized 0–1) stream, throttled ~3 Hz.
  Stream<double> get sharpness;

  /// Physical torch LED on the device.
  Future<void> setFlash(bool on);

  /// Digital zoom.
  Future<void> setZoom(double level);
  Future<double> getMaxZoom();

  /// Lock/unlock AE+AF for stable capture.
  Future<void> lockExposure();
  Future<void> unlockExposure();

  /// Capture + center-crop to 1:1 + JPEG encode. Returns null on failure.
  Future<Uint8List?> captureStandardized();

  /// Restart the image stream after capture so brightness/sharpness
  /// streams resume emitting (they are paused during takePicture).
  Future<void> restartSampling();

  Future<void> dispose();
}

/// Encapsulates platform AR feature availability. Returned by
/// [ArSessionPort.probeCapabilities] so the router can decide which scan
/// surface to mount.
class ArCapabilities {
  const ArCapabilities({
    required this.hasArSupport,
    required this.hasDepthSensor,
  });

  final bool hasArSupport;
  final bool hasDepthSensor;

  bool get canRunArBridge => hasArSupport && hasDepthSensor;

  static const ArCapabilities none =
      ArCapabilities(hasArSupport: false, hasDepthSensor: false);
}

/// Encrypted persistence boundary for [LesionAnalysis] aggregates.
/// The repository owns the AES-256 key (via secure storage) and the SQLite
/// table; callers never see ciphertext.
abstract class LesionRepositoryPort {
  Future<void> initialize();
  Future<void> save(LesionAnalysis analysis, {Uint8List? jpegBytes});
  Future<List<LesionAnalysis>> findByPatient(String patientId);
  Future<LesionAnalysis?> findById(String id, {bool includeImage = false});
  Future<void> delete(String id);

  /// Patches the body region on an already-saved analysis. The body
  /// region picker fires post-capture, so the row needs an in-place
  /// update instead of a full re-save. Re-flips ``pendingUpload`` to
  /// ``true`` so the next sync uploads the updated value.
  Future<void> updateBodyRegion(String id, String? bodyRegion);

  /// Records pending cloud upload (future feature). Schema-ready.
  Future<List<LesionAnalysis>> findPendingUpload();
  Future<void> markUploaded(String id);
}
