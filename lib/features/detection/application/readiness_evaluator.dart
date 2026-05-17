import 'dart:async';

import '../domain/ar_geometry.dart';
import '../domain/capture_quality.dart';
import '../domain/focus_quality.dart';
import '../domain/ports.dart';

/// Combines brightness, sharpness, and distance streams into a single
/// [CaptureReadiness] stream. Lives in `application/` because it composes
/// infrastructure (camera service) with domain value objects.
///
/// The redesigned capture UX surfaces three indicators — lighting, focus
/// and distance — so the evaluator no longer tracks a separate
/// "stability" signal. Autofocus settling is already implicit in the
/// focus boolean (sharpness above its threshold) and the extra fourth
/// chip was making the camera screen feel busy without adding signal.
class ReadinessEvaluator {
  ReadinessEvaluator({
    required ScanCameraServicePort camera,
  }) : _camera = camera;

  final ScanCameraServicePort _camera;

  final StreamController<CaptureReadiness> _readinessController =
      StreamController<CaptureReadiness>.broadcast();

  StreamSubscription<double>? _brightnessSub;
  StreamSubscription<double>? _sharpnessSub;
  StreamSubscription<CaptureDistance>? _distanceSub;

  CaptureQuality _lighting = CaptureQuality.initial;
  FocusQuality _focus = FocusQuality.initial;
  CaptureDistance _distance = const CaptureDistance.unknown();

  Stream<CaptureReadiness> get readiness => _readinessController.stream;

  CaptureDistance get currentDistance => _distance;

  CaptureReadiness get current => CaptureReadiness(
        lighting: _lighting,
        focus: _focus.isSharp,
        distance: _distance.isInAcceptableRange,
      );

  void start({Stream<CaptureDistance>? distanceStream}) {
    _brightnessSub = _camera.brightness.listen((b) {
      _lighting = CaptureQuality.fromBrightness(b);
      _emit();
    });

    _sharpnessSub = _camera.sharpness.listen((s) {
      _focus = FocusQuality(sharpness: s);
      _emit();
    });

    if (distanceStream != null) {
      _distanceSub = distanceStream.listen((d) {
        _distance = d;
        _emit();
      });
    } else {
      // When no AR distance sensor, assume distance is acceptable
      // (user must self-coach based on visual overlay).
      _distance = const CaptureDistance.cm(CaptureDistance.sweetSpotCm);
    }
  }

  void _emit() {
    if (!_readinessController.isClosed) {
      _readinessController.add(current);
    }
  }

  Future<void> dispose() async {
    await _brightnessSub?.cancel();
    await _sharpnessSub?.cancel();
    await _distanceSub?.cancel();
    await _readinessController.close();
  }
}
