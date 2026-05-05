import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/ar_geometry.dart';
import '../domain/ports.dart';

/// Dart-side facade over the native AR session (ARKit + LiDAR on iOS,
/// ARCore Depth API on Android). Native code lives in:
///
///   • iOS:     `ios/Runner/SkeenArPlugin.swift`
///   • Android: `android/app/src/main/kotlin/.../SkeenArPlugin.kt`
///
/// All channel I/O is funneled through this class so the application layer
/// only depends on the [ArSessionPort] abstraction.
///
/// On platforms without AR support (web, desktop, older mobile devices),
/// every method is a graceful no-op and [probeCapabilities] reports
/// `none` — the router falls back to the plain camera scan screen.
class ArSessionService implements ArSessionPort {
  ArSessionService();

  static const _method = MethodChannel('skeen.detection/ar');
  static const _distanceEvents =
      EventChannel('skeen.detection/ar/distance');

  StreamSubscription<dynamic>? _distanceSub;
  final StreamController<CaptureDistance> _distanceController =
      StreamController<CaptureDistance>.broadcast();

  bool get _isPlatformSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  @override
  Stream<CaptureDistance> get distance => _distanceController.stream;

  @override
  Future<ArCapabilities> probeCapabilities() async {
    if (!_isPlatformSupported) return ArCapabilities.none;
    try {
      final result = await _method.invokeMapMethod<String, dynamic>(
        'probeCapabilities',
      );
      if (result == null) return ArCapabilities.none;
      return ArCapabilities(
        hasArSupport: result['hasArSupport'] as bool? ?? false,
        hasDepthSensor: result['hasDepthSensor'] as bool? ?? false,
      );
    } on MissingPluginException {
      // Native side not registered yet — treat as "no AR" so the fallback
      // camera screen kicks in. This keeps the app usable even when the
      // native plugin hasn't been integrated for a given platform build.
      return ArCapabilities.none;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('AR probe failed: $e');
      return ArCapabilities.none;
    }
  }

  @override
  Future<void> start() async {
    if (!_isPlatformSupported) return;
    try {
      await _method.invokeMethod<void>('start');
      _distanceSub ??= _distanceEvents
          .receiveBroadcastStream()
          .listen(_onDistanceEvent, onError: _onDistanceError);
    } on MissingPluginException {
      // No-op when the native side isn't wired in for this build.
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('AR start failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    await _distanceSub?.cancel();
    _distanceSub = null;
    if (!_isPlatformSupported) return;
    try {
      await _method.invokeMethod<void>('stop');
    } on MissingPluginException {
      // ignore
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('AR stop failed: $e');
    }
  }

  @override
  Future<WorldAnchor?> hitTest(Offset normalizedScreenPoint) async {
    if (!_isPlatformSupported) return null;
    try {
      final result = await _method.invokeMapMethod<String, dynamic>(
        'hitTest',
        {'x': normalizedScreenPoint.dx, 'y': normalizedScreenPoint.dy},
      );
      if (result == null) return null;
      return WorldAnchor.fromJson(result);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('AR hitTest failed: $e');
      return null;
    }
  }

  @override
  Future<Offset?> projectToScreen(WorldAnchor anchor) async {
    if (!_isPlatformSupported) return null;
    try {
      final result = await _method.invokeMapMethod<String, dynamic>(
        'projectToScreen',
        anchor.toJson(),
      );
      if (result == null) return null;
      final visible = result['visible'] as bool? ?? true;
      if (!visible) return null;
      return Offset(
        (result['sx'] as num).toDouble(),
        (result['sy'] as num).toDouble(),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<Uint8List?> captureFrame() async {
    if (!_isPlatformSupported) return null;
    try {
      return await _method.invokeMethod<Uint8List>('captureFrame');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('AR captureFrame failed: $e');
      return null;
    }
  }

  @override
  Future<void> setFlash(bool on) async {
    if (!_isPlatformSupported) return;
    try {
      await _method.invokeMethod<void>('setFlash', {'on': on});
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  @override
  Future<void> setZoom(double zoom) async {
    if (!_isPlatformSupported) return;
    try {
      await _method.invokeMethod<void>('setZoom', {'zoom': zoom});
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  void _onDistanceEvent(dynamic event) {
    if (event is Map) {
      final cm = (event['cm'] as num?)?.toDouble();
      final estimated = event['estimated'] as bool? ?? false;
      if (cm == null || cm.isNaN) {
        _distanceController.add(const CaptureDistance.unknown());
      } else if (estimated) {
        _distanceController.add(CaptureDistance.estimated(cm));
      } else {
        _distanceController.add(CaptureDistance.cm(cm));
      }
    }
  }

  void _onDistanceError(Object error) {
    if (kDebugMode) debugPrint('Distance stream error: $error');
    _distanceController.add(const CaptureDistance.unknown());
  }

  Future<void> dispose() async {
    await stop();
    await _distanceController.close();
  }
}
