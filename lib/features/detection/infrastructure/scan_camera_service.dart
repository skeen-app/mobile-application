import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Infrastructure wrapper around the `camera` plugin scoped to the AR scan
/// flow. Owns the [CameraController] lifecycle and exposes a throttled
/// luminance stream that the presentation layer turns into quality guidance.
class ScanCameraService {
  ScanCameraService();

  CameraController? _controller;
  bool _isStreaming = false;
  DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
  final StreamController<double> _brightnessController =
      StreamController<double>.broadcast();

  CameraController? get controller => _controller;
  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Stream of mean Y-plane brightness (0–255), throttled to ~3 Hz to keep
  /// the main isolate responsive while still feeling live to the user.
  Stream<double> get brightness => _brightnessController.stream;

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

    // Sparse subsample: ~1024 samples spread across the plane keeps the work
    // tiny regardless of resolution.
    const samples = 1024;
    final step = bytes.length ~/ samples;
    if (step <= 0) return;
    var sum = 0;
    var count = 0;
    for (var i = 0; i < bytes.length; i += step) {
      sum += bytes[i];
      count++;
    }
    final mean = sum / count;
    if (!_brightnessController.isClosed) {
      _brightnessController.add(mean);
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
  }
}
