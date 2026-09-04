import 'dart:async';

import '../domain/capture_quality.dart';
import '../domain/capture_scale.dart';
import '../domain/capture_stability.dart';
import '../domain/ports.dart';
import '../domain/roi_frame_metrics.dart';
import 'sharpness_calibrator.dart';

/// Folds the ROI metric stream and the gyroscope into a single
/// [CaptureReadiness] — the value that gates the shutter.
///
/// Two things changed here and both are about honesty:
///
///  1. **No fabricated distance.** This class used to set
///     `_distance = CaptureDistance.cm(15)` whenever no depth stream was
///     supplied, which on the plain-camera path was always. The UI then told
///     the user they were at the right distance, and the chip sat green,
///     on the strength of a constant. In a tool going into clinical
///     validation that is not a shortcut, it is fabricated data. Distance is
///     now expressed as [CaptureScale] — how much of the guide box the
///     lesion fills — which is genuinely measured from the preview.
///
///  2. **Unmeasured means blocked, not passed.** Every signal that has no
///     reading reports "unknown", and unknown keeps [CaptureReadiness.isReady]
///     false. The gate never opens on an assumption.
class ReadinessEvaluator {
  ReadinessEvaluator({
    required ScanCameraServicePort camera,
    required StabilitySensorPort stabilitySensor,
    SharpnessCalibrator? calibrator,
    DateTime Function()? clock,
  })  : _camera = camera,
        _stabilitySensor = stabilitySensor,
        _now = clock ?? DateTime.now,
        calibrator = calibrator ?? SharpnessCalibrator();

  final ScanCameraServicePort _camera;
  final StabilitySensorPort _stabilitySensor;

  /// Injectable so the multi-second "cannot focus" rule can be exercised in
  /// a test without the test actually taking multiple seconds.
  final DateTime Function() _now;

  /// Exposed so the capture path can persist the calibration state alongside
  /// each shot — the thresholds have to be re-derivable from field data.
  final SharpnessCalibrator calibrator;

  final StreamController<CaptureReadiness> _readinessController =
      StreamController<CaptureReadiness>.broadcast();

  StreamSubscription<RoiFrameMetrics>? _metricsSub;
  StreamSubscription<double>? _stabilitySub;

  CaptureQuality _lighting = CaptureQuality.initial;
  CaptureStability _stability = CaptureStability.unknown;
  CaptureScale _scale = const CaptureScale.unknown();
  RoiFrameMetrics _metrics = RoiFrameMetrics.empty;
  bool _glareOk = true;

  DateTime? _lastMetricAt;
  int _unsharpMs = 0;

  /// How long the frame must stay soft before we conclude the phone is inside
  /// its lens' minimum focus distance rather than merely hunting. Autofocus
  /// on a phone settles well inside a second; three seconds of continuous
  /// softness is not the autofocus still working.
  static const int unfocusableSustainMs = 3000;

  Stream<CaptureReadiness> get readiness => _readinessController.stream;

  /// Last raw measurement, for capture telemetry.
  RoiFrameMetrics get lastMetrics => _metrics;

  CaptureReadiness get current => CaptureReadiness(
        lighting: _lighting,
        focus: calibrator.isSharp,
        glareOk: _glareOk,
        colorCast: _metrics.colorCast,
        stability: _stability,
        scale: _scale,
      );

  /// Subscribes to the sensor streams.
  ///
  /// Cancels any previous subscriptions first. The scan screens call this
  /// again on every app resume, and the old implementation just reassigned
  /// the fields — so each resume added another live listener to the same
  /// broadcast streams and every frame was processed once per resume, with
  /// the readiness stream emitting duplicates at a multiplied rate.
  Future<void> start() async {
    await _cancelSubscriptions();

    // A new camera session says nothing about the previous scene's peak
    // sharpness, so the normalization reference restarts with it.
    calibrator.reset();
    _lastMetricAt = null;
    _unsharpMs = 0;
    _scale = const CaptureScale.unknown();
    _stability = CaptureStability.unknown;

    await _stabilitySensor.start();

    _metricsSub = _camera.metrics.listen(_onMetrics);
    _stabilitySub = _stabilitySensor.angularSpeed.listen((speed) {
      _stability = CaptureStability(angularSpeed: speed);
      _emit();
    });
  }

  void _onMetrics(RoiFrameMetrics metrics) {
    final now = _now();
    final dtMs = _lastMetricAt == null
        ? 0
        : now.difference(_lastMetricAt!).inMilliseconds.clamp(0, 1000);
    _lastMetricAt = now;

    _metrics = metrics;
    _lighting = CaptureQuality.fromBrightness(metrics.luma);
    _glareOk = metrics.isGlareAcceptable;
    calibrator.add(metrics.sharpnessRaw);

    // Track how long the frame has refused to come into focus. Only counted
    // once the calibrator has a reference, otherwise the warm-up period
    // itself would look like a focus failure.
    if (calibrator.isCalibrating) {
      _unsharpMs = 0;
    } else if (calibrator.isSharp) {
      _unsharpMs = 0;
    } else {
      _unsharpMs += dtMs;
    }

    // "Can't focus" only means "too close" when the lesion is not also tiny
    // in frame. A small blob that won't sharpen is a user standing too far
    // back, and telling them to move further away would be actively wrong.
    final tooSmall = metrics.hasLesionEstimate &&
        metrics.lesionFillFraction < CaptureScale.minFillFraction;
    final cannotFocus = _unsharpMs >= unfocusableSustainMs && !tooSmall;

    _scale = CaptureScale.fromFill(
      metrics.lesionFillFraction,
      cannotFocus: cannotFocus,
    );

    _emit();
  }

  void _emit() {
    if (!_readinessController.isClosed) {
      _readinessController.add(current);
    }
  }

  Future<void> _cancelSubscriptions() async {
    await _metricsSub?.cancel();
    await _stabilitySub?.cancel();
    _metricsSub = null;
    _stabilitySub = null;
  }

  Future<void> stop() async {
    await _cancelSubscriptions();
    await _stabilitySensor.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _readinessController.close();
  }
}
