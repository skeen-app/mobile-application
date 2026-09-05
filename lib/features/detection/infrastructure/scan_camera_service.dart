import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import '../domain/capture_roi.dart';
import '../domain/luma_frame.dart';
import '../domain/ports.dart';
import '../domain/roi_frame_metrics.dart';
import '../domain/roi_metrics_calculator.dart';

/// Infrastructure wrapper around the `camera` plugin scoped to the scan
/// flow. Owns the [CameraController] lifecycle and exposes a throttled
/// stream of ROI measurements that the readiness gate turns into blocking
/// capture guidance.
class ScanCameraService implements ScanCameraServicePort {
  ScanCameraService();

  CameraController? _controller;
  bool _isStreaming = false;
  DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
  // Re-created by [initialize] when a previous [dispose] closed it — see
  // the note there. Not `final` for that reason only.
  StreamController<RoiFrameMetrics> _metricsController =
      StreamController<RoiFrameMetrics>.broadcast();
  StreamController<LumaFrame> _detectionController =
      StreamController<LumaFrame>.broadcast();

  CaptureRoi _roi = CaptureRoi.full;
  DateTime _lastDetectionFrame = DateTime.fromMillisecondsSinceEpoch(0);
  int _sensorOrientation = 90;
  double _zoom = 1.0;

  /// Detection frames are emitted at this cadence — every 3rd frame at
  /// 30 fps. The detector runs in a worker isolate and drops frames while
  /// busy, so this is an upper bound, not a promise.
  static const int detectionCadenceMs = 100;

  /// Longest side of the downsampled luma frame handed to the detector.
  /// 320 keeps a 30 mm marker at ~60 px across at 20 cm — five times the
  /// detector's minimum — at a quarter of the pixels of the full stream.
  static const int detectionMaxWidth = 320;

  CameraController? get controller => _controller;
  @override
  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Stream of ROI measurements, throttled to ~3 Hz to keep the main isolate
  /// responsive while still feeling live.
  ///
  /// One stream rather than the previous separate brightness/sharpness pair:
  /// the gate evaluates the whole vector at once, and independently throttled
  /// streams could mix readings from different frames.
  @override
  Stream<RoiFrameMetrics> get metrics => _metricsController.stream;

  @override
  CaptureRoi get roi => _roi;

  @override
  void setRoi(CaptureRoi roi) => _roi = roi;

  @override
  Size? get previewFrameSize => _controller?.value.previewSize;

  @override
  Stream<LumaFrame> get detectionFrames => _detectionController.stream;

  @override
  int get sensorOrientationDegrees => _sensorOrientation;

  @override
  Future<bool> hasCamera() async {
    try {
      final cameras = await availableCameras();
      return cameras.isNotEmpty;
    } catch (e) {
      if (kDebugMode) debugPrint('Camera probe failed: $e');
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    // This service is provider-scoped (not auto-disposed) while the scan
    // screens call [dispose] on every background transition and
    // re-initialize on resume. A closed broadcast controller can never emit
    // again, so without this the metrics stream went silent
    // for the rest of the process — and since the plain-camera surface now
    // promotes `mapping → ready` off a readiness event, a capture rejected
    // after a background/resume cycle could never re-open the shutter.
    if (_metricsController.isClosed) {
      _metricsController = StreamController<RoiFrameMetrics>.broadcast();
    }
    if (_detectionController.isClosed) {
      _detectionController = StreamController<LumaFrame>.broadcast();
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras available on this device');
    }
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _sensorOrientation = back.sensorOrientation;

    final controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await controller.initialize();
    await controller.setFocusMode(FocusMode.auto);
    await controller.setExposureMode(ExposureMode.auto);
    _controller = controller;

    await _startSampling();
  }

  Future<void> _startSampling() async {
    final controller = _controller;
    if (controller == null || _isStreaming) return;
    _isStreaming = true;
    try {
      await controller.startImageStream(_onImage);
    } catch (e) {
      _isStreaming = false;
      if (kDebugMode) debugPrint('Image stream failed: $e');
    }
  }

  void _onImage(CameraImage image) {
    final now = DateTime.now();
    // The detector rides on the SAME stream as the metrics, at its own
    // (faster) cadence. Opening a second image stream would double the
    // camera's work and let the two drift out of sync.
    _maybeEmitDetectionFrame(image, now);

    if (now.difference(_lastSample).inMilliseconds < 320) return;
    _lastSample = now;

    if (image.planes.isEmpty || image.width < 8 || image.height < 8) return;

    // Every metric is measured over this region only — the part of the frame
    // the user sees inside the guide box. Whole-frame sampling let a textured
    // background read as "sharp" while the lesion was blurred, and a bright
    // wall behind a shadowed limb read as "well lit".
    final bounds = _roi.boundsIn(image.width, image.height);

    try {
      final measured = image.format.group == ImageFormatGroup.bgra8888
          ? _measureBgra(image, bounds)
          : _measureYuv(image, bounds);
      if (measured.sampleCount > 0 && !_metricsController.isClosed) {
        _metricsController.add(measured);
      }
    } catch (e) {
      // A malformed frame must not kill the stream the gate depends on.
      if (kDebugMode) debugPrint('ROI metric sampling failed: $e');
    }
  }

  /// Packs a downsampled luma plane for the marker detector.
  ///
  /// Skipped entirely when nobody is listening, so the plain-camera path
  /// pays nothing for it until a pose tracker subscribes.
  void _maybeEmitDetectionFrame(CameraImage image, DateTime now) {
    if (!_detectionController.hasListener || _detectionController.isClosed) {
      return;
    }
    if (now.difference(_lastDetectionFrame).inMilliseconds <
        detectionCadenceMs) {
      return;
    }
    if (image.planes.isEmpty || image.width < 16 || image.height < 16) return;
    _lastDetectionFrame = now;

    final step = math.max(1, (image.width / detectionMaxWidth).ceil());
    final w = image.width ~/ step;
    final h = image.height ~/ step;
    if (w < 16 || h < 16) return;

    final plane = image.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final out = Uint8List(w * h);
    // Colour at the same resolution, for the marker's reference patches.
    Uint8List? rgb = Uint8List(w * h * 3);

    try {
      if (image.format.group == ImageFormatGroup.bgra8888) {
        for (var y = 0; y < h; y++) {
          final srcRow = (y * step) * rowStride;
          for (var x = 0; x < w; x++) {
            final i = srcRow + (x * step) * 4;
            if (i + 2 >= bytes.length) break;
            final o = y * w + x;
            out[o] = (0.299 * bytes[i + 2] +
                    0.587 * bytes[i + 1] +
                    0.114 * bytes[i])
                .round();
            rgb[o * 3] = bytes[i + 2];
            rgb[o * 3 + 1] = bytes[i + 1];
            rgb[o * 3 + 2] = bytes[i];
          }
        }
      } else {
        final pixelStride = plane.bytesPerPixel ?? 1;
        final hasChroma = image.planes.length >= 3;
        if (!hasChroma) rgb = null;
        final uBytes = hasChroma ? image.planes[1].bytes : null;
        final vBytes = hasChroma ? image.planes[2].bytes : null;
        final uvRowStride = hasChroma ? image.planes[1].bytesPerRow : 0;
        final uvPixelStride =
            hasChroma ? (image.planes[1].bytesPerPixel ?? 1) : 0;
        for (var y = 0; y < h; y++) {
          final sy = y * step;
          final srcRow = sy * rowStride;
          for (var x = 0; x < w; x++) {
            final sx = x * step;
            final i = srcRow + sx * pixelStride;
            if (i >= bytes.length) break;
            final o = y * w + x;
            final luma = bytes[i];
            out[o] = luma;
            if (rgb != null) {
              final uv = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;
              if (uv >= 0 && uv < uBytes!.length && uv < vBytes!.length) {
                final u = uBytes[uv] - 128;
                final v = vBytes[uv] - 128;
                rgb[o * 3] = (luma + 1.402 * v).round().clamp(0, 255);
                rgb[o * 3 + 1] =
                    (luma - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
                rgb[o * 3 + 2] = (luma + 1.772 * u).round().clamp(0, 255);
              } else {
                rgb[o * 3] = luma;
                rgb[o * 3 + 1] = luma;
                rgb[o * 3 + 2] = luma;
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Detection frame packing failed: $e');
      return;
    }

    _detectionController.add(LumaFrame(
      luma: out,
      width: w,
      height: h,
      capturedAt: now,
      scaleToFull: step.toDouble(),
      zoom: _zoom,
      rgb: rgb,
    ));
  }

  /// BGRA8888 (iOS). Colour is directly addressable. Luma uses the Rec. 601
  /// weights instead of the green channel as a stand-in, so it lands on the
  /// same 0-255 scale as the YUV path's Y plane and one set of thresholds
  /// applies to both platforms.
  RoiFrameMetrics _measureBgra(CameraImage image, RoiBounds bounds) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    const pixelStride = 4;

    return computeRoiMetrics(
      bounds: bounds,
      luma: (x, y) {
        final i = y * rowStride + x * pixelStride;
        if (i < 0 || i + 2 >= bytes.length) return 0;
        return (0.299 * bytes[i + 2] +
                0.587 * bytes[i + 1] +
                0.114 * bytes[i])
            .round();
      },
      rgb: (x, y) {
        final i = y * rowStride + x * pixelStride;
        if (i < 0 || i + 2 >= bytes.length) return const RgbPixel(0, 0, 0);
        return RgbPixel(bytes[i + 2], bytes[i + 1], bytes[i]);
      },
    );
  }

  /// YUV420 (Android). Luma comes from plane 0; colour is reconstructed from
  /// the half-resolution chroma planes with the Rec. 601 inverse, which is
  /// what makes the white-balance check possible on this platform at all.
  RoiFrameMetrics _measureYuv(CameraImage image, RoiBounds bounds) {
    final yPlane = image.planes[0];
    final yBytes = yPlane.bytes;
    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 1;

    int lumaAt(int x, int y) {
      final i = y * yRowStride + x * yPixelStride;
      return (i >= 0 && i < yBytes.length) ? yBytes[i] : 0;
    }

    if (image.planes.length < 3) {
      // Luma-only buffer. Report the cast as neutral rather than inventing
      // channel means: we have no evidence of a cast, so that check passes
      // while every other metric stays a real measurement.
      return computeRoiMetrics(bounds: bounds, luma: lumaAt);
    }

    final uBytes = image.planes[1].bytes;
    final vBytes = image.planes[2].bytes;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    RgbPixel rgbAt(int x, int y) {
      final luma = lumaAt(x, y);
      final uvIndex = (y >> 1) * uvRowStride + (x >> 1) * uvPixelStride;
      if (uvIndex < 0 ||
          uvIndex >= uBytes.length ||
          uvIndex >= vBytes.length) {
        return RgbPixel(luma, luma, luma);
      }
      final u = uBytes[uvIndex] - 128;
      final v = vBytes[uvIndex] - 128;
      return RgbPixel(
        (luma + 1.402 * v).round().clamp(0, 255),
        (luma - 0.344136 * u - 0.714136 * v).round().clamp(0, 255),
        (luma + 1.772 * u).round().clamp(0, 255),
      );
    }

    return computeRoiMetrics(bounds: bounds, luma: lumaAt, rgb: rgbAt);
  }

  /// Re-start the image stream after capture so the metrics stream resumes
  /// emitting. Safe to call multiple times.
  ///
  /// Includes a brief cooldown because the camera hardware needs a moment
  /// after `takePicture()` before it can accept `startImageStream()` again.
  @override
  Future<void> restartSampling() async {
    // Brief cooldown for camera hardware readiness after takePicture
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Retry once if the first attempt fails (platform timing edge case)
    try {
      await _startSampling();
    } catch (e) {
      if (kDebugMode) debugPrint('Restart sampling retry after error: $e');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _startSampling();
    }
  }

  Future<void> focusAt(Offset normalized) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFocusPoint(normalized);
      await controller.setExposurePoint(normalized);
    } catch (e) {
      if (kDebugMode) debugPrint('Focus tap failed: $e');
    }
  }

  /// Lock auto-exposure and auto-focus to stabilize image before capture.
  @override
  Future<void> lockExposure() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setExposureMode(ExposureMode.locked);
      await controller.setFocusMode(FocusMode.locked);
    } catch (e) {
      if (kDebugMode) debugPrint('AE/AF lock failed: $e');
    }
  }

  /// Unlock auto-exposure and auto-focus after capture.
  @override
  Future<void> unlockExposure() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFocusMode(FocusMode.auto);
    } catch (e) {
      if (kDebugMode) debugPrint('AE/AF unlock failed: $e');
    }
  }

  /// Capture + standardize: take picture, center-crop to 1:1, encode as
  /// JPEG bytes. The resulting image is standardized for model input
  /// regardless of device camera resolution or aspect ratio.
  @override
  Future<Uint8List?> captureStandardized() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    if (_isStreaming) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
      _isStreaming = false;
    }
    try {
      final file = await controller.takePicture();
      final raw = await file.readAsBytes();

      // Center-crop to 1:1 in an isolate to keep UI responsive.
      final result = await compute(_centerCropJpeg, raw);

      // Auto-restart the image stream so readiness overlay keeps updating.
      await restartSampling();

      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('Capture failed: $e');
      // Still try to restart sampling even on failure.
      await restartSampling();
      return null;
    }
  }

  /// Legacy capture without standardization (for fallback compatibility).
  Future<XFile?> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    if (_isStreaming) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
      _isStreaming = false;
    }
    try {
      return await controller.takePicture();
    } catch (e) {
      if (kDebugMode) debugPrint('Capture failed: $e');
      return null;
    }
  }

  /// Set the zoom level. Called by pinch gesture handler.
  ///
  /// Clamps the request to the device's actual [getMinZoomLevel] /
  /// [getMaxZoomLevel] window — some phones (Motorola edge, Pixel
  /// wide-angle stacks) report a min above 1.0 or a max below the value
  /// the controller is happy to accept, and passing a value outside the
  /// window throws a PlatformException that used to vanish into the
  /// silent catch below.
  @override
  Future<void> setZoom(double level) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final min = await controller.getMinZoomLevel();
      final max = await controller.getMaxZoomLevel();
      final clamped = level.clamp(min, max);
      await controller.setZoomLevel(clamped);
      _zoom = clamped;
    } catch (e, st) {
      if (kDebugMode) debugPrint('Zoom failed at $level: $e\n$st');
    }
  }

  /// Toggle flash mode (physical torch LED).
  @override
  Future<void> setFlash(bool on) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    } catch (e) {
      if (kDebugMode) debugPrint('Flash toggle (torch) failed: $e');
      if (on) {
        // Fallback for Android devices that throw when setting torch during active streams
        try {
          await controller.setFlashMode(FlashMode.always);
        } catch (e2) {
          if (kDebugMode) debugPrint('Flash toggle fallback (always) failed: $e2');
        }
      }
    }
  }

  /// Get the maximum zoom level supported by the device camera.
  @override
  Future<double> getMaxZoom() async {
    final controller = _controller;
    if (controller == null) return 5.0;
    try {
      return (await controller.getMaxZoomLevel()).clamp(1.0, 8.0);
    } catch (_) {
      return 5.0;
    }
  }

  @override
  Future<void> dispose() async {
    if (_isStreaming) {
      try {
        await _controller?.stopImageStream();
      } catch (_) {}
      _isStreaming = false;
    }
    await _controller?.dispose();
    _controller = null;
    await _metricsController.close();
    await _detectionController.close();
  }
}

/// Top-level function for `compute()`. Decodes the JPEG, center-crops to
/// 1:1 aspect ratio (uses the shorter dimension), re-encodes as JPEG.
Uint8List _centerCropJpeg(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;

  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final left = (decoded.width - side) ~/ 2;
  final top = (decoded.height - side) ~/ 2;

  final cropped = img.copyCrop(decoded,
      x: left, y: top, width: side, height: side);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
}
