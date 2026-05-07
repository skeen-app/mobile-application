import 'dart:async';

import '../domain/ar_geometry.dart';
import '../domain/capture_quality.dart';
import '../domain/focus_quality.dart';
import '../domain/ports.dart';

/// Combines brightness, sharpness, and distance streams into a single
/// [CaptureReadiness] stream. Lives in `application/` because it composes
/// infrastructure (camera service) with domain value objects.
///
/// Stability is derived from successive sharpness readings — if the last
/// N readings stay within a tolerance band, the phone is considered stable.
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
  bool _isStable = false;

  // Stability tracking: last N sharpness readings. Tightened so the gate
  // unlocks fast — a 3-sample window at ~3 Hz lands ≈600 ms instead of
  // ~1.5 s, which felt like the app had hung.
  static const int _stabilityWindowSize = 3;
  static const double _stabilityTolerance = 0.18;
  final List<double> _recentSharpness = [];
  DateTime _lastStableCheck = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<CaptureReadiness> get readiness => _readinessController.stream;

  CaptureReadiness get current => CaptureReadiness(
        lighting: _lighting,
        focus: _focus.isSharp,
        distance: _distance.isInAcceptableRange,
        isStable: _isStable,
      );

  void start({Stream<CaptureDistance>? distanceStream}) {
    _brightnessSub = _camera.brightness.listen((b) {
      _lighting = CaptureQuality.fromBrightness(b);
      _emit();
    });

    _sharpnessSub = _camera.sharpness.listen((s) {
      _focus = FocusQuality(sharpness: s);
      _updateStability(s);
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

  void _updateStability(double sharpness) {
    _recentSharpness.add(sharpness);
    if (_recentSharpness.length > _stabilityWindowSize) {
      _recentSharpness.removeAt(0);
    }

    final now = DateTime.now();
    if (now.difference(_lastStableCheck).inMilliseconds < 150) return;
    _lastStableCheck = now;

    // First two samples are enough to "feel" stable — once the user has
    // held the phone for ~half a second the focus search has typically
    // settled. Tight tolerance is reserved for the final sharpness pass.
    if (_recentSharpness.length < _stabilityWindowSize) {
      _isStable = _recentSharpness.length >= 2 && sharpness > 0.05;
      return;
    }

    final mean =
        _recentSharpness.reduce((a, b) => a + b) / _recentSharpness.length;
    _isStable = _recentSharpness
        .every((v) => (v - mean).abs() < _stabilityTolerance);
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
