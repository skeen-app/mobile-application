import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import '../domain/ports.dart';

/// Infrastructure wrapper around the `camera` plugin scoped to the AR scan
/// flow. Owns the [CameraController] lifecycle and exposes throttled
/// luminance + sharpness streams that the presentation layer turns into
/// quality guidance for assisted capture.
class ScanCameraService implements ScanCameraServicePort {
  ScanCameraService();

  CameraController? _controller;
  bool _isStreaming = false;
  DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
  final StreamController<double> _brightnessController =
      StreamController<double>.broadcast();
  final StreamController<double> _sharpnessController =
      StreamController<double>.broadcast();

  CameraController? get controller => _controller;
  @override
  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Stream of mean Y-plane brightness (0–255), throttled to ~3 Hz to keep
  /// the main isolate responsive while still feeling live to the user.
  @override
  Stream<double> get brightness => _brightnessController.stream;

  /// Stream of sharpness scores (0–1), derived from Laplacian variance on
  /// a sparse Y-plane subsample. Same throttle cadence as brightness.
  @override
  Stream<double> get sharpness => _sharpnessController.stream;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras available on this device');
    }
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
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
    if (now.difference(_lastSample).inMilliseconds < 320) return;
    _lastSample = now;

    final plane = image.planes.first;
    final bytes = plane.bytes;
    if (bytes.isEmpty) return;

    // ── Brightness: sparse subsample ~1024 samples ──────────────────
    const samples = 1024;
    final step = bytes.length ~/ samples;
    if (step <= 0) return;
    var sum = 0;
    var count = 0;
    for (var i = 0; i < bytes.length; i += step) {
      sum += bytes[i];
      count++;
    }
    final meanBrightness = sum / count;
    if (!_brightnessController.isClosed) {
      _brightnessController.add(meanBrightness);
    }

    // ── Sharpness: Laplacian variance on sparse grid ────────────────
    // Use a 3×3 Laplacian kernel approximation on a sparse grid of the
    // Y plane. The variance of the Laplacian output correlates with focus
    // sharpness — higher variance = sharper image.
    final width = plane.bytesPerRow;
    final height = bytes.length ~/ width;
    if (width < 3 || height < 3) return;

    const gridStep = 8; // sample every 8th pixel for speed
    var lapSum = 0.0;
    var lapSumSq = 0.0;
    var lapCount = 0;
    for (var y = 1; y < height - 1; y += gridStep) {
      for (var x = 1; x < width - 1; x += gridStep) {
        final center = bytes[y * width + x];
        final top = bytes[(y - 1) * width + x];
        final bottom = bytes[(y + 1) * width + x];
        final left = bytes[y * width + (x - 1)];
        final right = bytes[y * width + (x + 1)];
        final laplacian = (4 * center - top - bottom - left - right).abs();
        lapSum += laplacian;
        lapSumSq += laplacian * laplacian;
        lapCount++;
      }
    }
    if (lapCount > 0) {
      final mean = lapSum / lapCount;
      final variance = (lapSumSq / lapCount) - (mean * mean);
      // Normalize variance to 0–1 range. Empirically, dermatology macro
      // photos at ~15 cm produce variance 200–2000+ for sharp frames.
      final normalized = (variance / 2000.0).clamp(0.0, 1.0);
      if (!_sharpnessController.isClosed) {
        _sharpnessController.add(normalized);
      }
    }
  }

  /// Re-start the image stream after capture so brightness/sharpness
  /// streams resume emitting. Safe to call multiple times.
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
  @override
  Future<void> setZoom(double level) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setZoomLevel(level);
    } catch (e) {
      if (kDebugMode) debugPrint('Zoom failed: $e');
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
      if (kDebugMode) debugPrint('Flash toggle failed: $e');
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
    await _brightnessController.close();
    await _sharpnessController.close();
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
