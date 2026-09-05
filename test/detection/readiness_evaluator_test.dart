import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/application/readiness_evaluator.dart';
import 'package:skeen/features/detection/domain/capture_quality.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';
import 'package:skeen/features/detection/domain/capture_stability.dart';
import 'package:skeen/features/detection/domain/capture_scale.dart';
import 'package:skeen/features/detection/domain/luma_frame.dart';
import 'package:skeen/features/detection/domain/ports.dart';
import 'package:skeen/features/detection/domain/roi_frame_metrics.dart';

RoiFrameMetrics _metrics({
  double luma = 140,
  double sharpnessRaw = 1000,
  double glareFraction = 0,
  ColorCast cast = ColorCast.neutral,
  double fill = 0.5,
}) =>
    RoiFrameMetrics(
      luma: luma,
      sharpnessRaw: sharpnessRaw,
      glareFraction: glareFraction,
      colorCast: cast,
      lesionFillFraction: fill,
      sampleCount: 2000,
    );

void main() {
  late _FakeCamera camera;
  late _FakeStabilitySensor sensor;
  late DateTime clock;

  ReadinessEvaluator build() {
    camera = _FakeCamera();
    sensor = _FakeStabilitySensor();
    clock = DateTime(2026, 1, 1);
    return ReadinessEvaluator(
      camera: camera,
      stabilitySensor: sensor,
      clock: () => clock,
    );
  }

  /// Lets the broadcast streams deliver.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Advances the clock, emits one frame, and lets the evaluator process it.
  ///
  /// The await matters: the metrics stream delivers asynchronously, so a
  /// loop that emits N frames and then advances the clock N times would have
  /// every listener run at the FINAL clock value and observe dt == 0.
  Future<void> tick(RoiFrameMetrics m, {int advanceMs = 330}) async {
    clock = clock.add(Duration(milliseconds: advanceMs));
    camera.emit(m);
    await settle();
  }

  group('subscription lifecycle', () {
    test('start() cancels the previous subscriptions before re-subscribing',
        () async {
      // The leak: the scan screens call start() again on every app resume,
      // and the old code just reassigned the fields. After three resumes each
      // camera frame was processed three times and the readiness stream fired
      // three duplicate events per frame.
      final evaluator = build();
      await evaluator.start();
      await evaluator.start();
      await evaluator.start();

      final seen = <CaptureReadiness>[];
      final sub = evaluator.readiness.listen(seen.add);

      camera.emit(_metrics());
      await settle();

      expect(seen.length, 1, reason: 'one frame must produce one evaluation');

      await sub.cancel();
      await evaluator.dispose();
    });

    test('a restarted evaluator still receives events', () async {
      final evaluator = build();
      await evaluator.start();
      await evaluator.start();

      final seen = <CaptureReadiness>[];
      final sub = evaluator.readiness.listen(seen.add);

      camera.emit(_metrics());
      sensor.emit(0.02);
      await settle();

      expect(seen, isNotEmpty);

      await sub.cancel();
      await evaluator.dispose();
    });

    test('start() re-baselines the sharpness reference', () async {
      final evaluator = build();
      await evaluator.start();
      for (var i = 0; i < 10; i++) {
        camera.emit(_metrics(sharpnessRaw: 5000));
      }
      await settle();
      expect(evaluator.calibrator.isCalibrating, isFalse);

      await evaluator.start();

      expect(evaluator.calibrator.isCalibrating, isTrue);
      expect(evaluator.calibrator.sampleCount, 0);

      await evaluator.dispose();
    });

    test('stop() releases the motion sensor', () async {
      final evaluator = build();
      await evaluator.start();
      expect(sensor.startCalls, 1);

      await evaluator.stop();

      expect(sensor.stopCalls, 1);
      await evaluator.dispose();
    });
  });

  group('no fabricated distance', () {
    test('scale stays unknown until a lesion is actually segmented', () async {
      final evaluator = build();
      await evaluator.start();

      // Uniform skin: the calculator reports no blob.
      camera.emit(_metrics(fill: -1));
      await settle();

      expect(evaluator.current.scale.advice, ScaleAdvice.unknown);
      expect(evaluator.current.scale.isAcceptable, isFalse);
      expect(
        evaluator.current.isReady,
        isFalse,
        reason: 'the gate must not open on an unmeasured signal',
      );

      await evaluator.dispose();
    });

    test('a measured fill produces actionable advice', () async {
      final evaluator = build();
      await evaluator.start();

      camera.emit(_metrics(fill: 0.08));
      await settle();
      expect(evaluator.current.scale.advice, ScaleAdvice.moveCloser);

      camera.emit(_metrics(fill: 0.92));
      await settle();
      expect(evaluator.current.scale.advice, ScaleAdvice.moveAway);

      await evaluator.dispose();
    });
  });

  group('minimum focus distance inference', () {
    test('sustained softness with a large lesion reads as too close',
        () async {
      final evaluator = build();
      await evaluator.start();

      // Build a sharpness reference first.
      for (var i = 0; i < 10; i++) {
        await tick(_metrics(sharpnessRaw: 4000));
      }
      expect(evaluator.current.focus, isTrue);

      // Now the frame goes soft and stays soft for over three seconds while
      // the lesion fills half the box.
      for (var i = 0; i < 12; i++) {
        await tick(_metrics(sharpnessRaw: 500, fill: 0.5));
      }

      expect(evaluator.current.focus, isFalse);
      expect(evaluator.current.scale.advice, ScaleAdvice.tooCloseToFocus);

      await evaluator.dispose();
    });

    test('sustained softness with a tiny lesion does NOT say move back',
        () async {
      // Being unable to focus on something far away is a distance problem in
      // the other direction. Telling that user to move further back would be
      // actively wrong.
      final evaluator = build();
      await evaluator.start();

      for (var i = 0; i < 10; i++) {
        await tick(_metrics(sharpnessRaw: 4000));
      }
      for (var i = 0; i < 12; i++) {
        await tick(_metrics(sharpnessRaw: 500, fill: 0.05));
      }

      expect(evaluator.current.scale.advice, ScaleAdvice.moveCloser);

      await evaluator.dispose();
    });

    test('brief softness is not mistaken for a focus limit', () async {
      final evaluator = build();
      await evaluator.start();

      for (var i = 0; i < 10; i++) {
        await tick(_metrics(sharpnessRaw: 4000));
      }
      // Under a second of hunting.
      for (var i = 0; i < 2; i++) {
        await tick(_metrics(sharpnessRaw: 500, fill: 0.5));
      }

      expect(evaluator.current.scale.advice, ScaleAdvice.ok);

      await evaluator.dispose();
    });

    test('the warm-up period is not counted as a focus failure', () async {
      final evaluator = build();
      await evaluator.start();

      // Only three samples: still calibrating, and a long time passes.
      for (var i = 0; i < 3; i++) {
        await tick(_metrics(sharpnessRaw: 4000, fill: 0.5), advanceMs: 2000);
      }

      expect(evaluator.calibrator.isCalibrating, isTrue);
      expect(evaluator.current.scale.advice, ScaleAdvice.ok);

      await evaluator.dispose();
    });
  });

  group('signal wiring', () {
    test('glare and colour cast reach the readiness vector', () async {
      final evaluator = build();
      await evaluator.start();

      camera.emit(_metrics(
        glareFraction: 0.10,
        cast: const ColorCast(rMean: 220, gMean: 140, bMean: 90),
      ));
      await settle();

      expect(evaluator.current.glareOk, isFalse);
      expect(evaluator.current.colorNeutral, isFalse);

      await evaluator.dispose();
    });

    test('the gyroscope drives stability, not the image', () async {
      final evaluator = build();
      await evaluator.start();

      camera.emit(_metrics());
      await settle();
      expect(
        evaluator.current.stability.isKnown,
        isFalse,
        reason: 'no image-derived fallback may stand in for the sensor',
      );

      sensor.emit(0.02);
      await settle();
      expect(evaluator.current.stability.isSteady, isTrue);

      sensor.emit(0.9);
      await settle();
      expect(evaluator.current.stability.isSteady, isFalse);

      await evaluator.dispose();
    });

    test('every image signal green still needs a marker pose', () async {
      // WP-3: without a pose tracker there is no marker pose, and the
      // physical gate is fail-closed. The image signals alone cannot open it.
      final evaluator = build();
      await evaluator.start();

      for (var i = 0; i < 10; i++) {
        await tick(_metrics(sharpnessRaw: 4000));
      }
      sensor.emit(0.02);
      await settle();

      expect(evaluator.current.isReady, isFalse);
      expect(evaluator.current.failingKey, 'marker');
      expect(evaluator.current.poseReadiness.hasPose, isFalse);

      await evaluator.dispose();
    });
  });
}

// ──────────────────────────────────────────────────────────────────────
// Fakes — hand written, matching the repo's mock-framework-free style.
// ──────────────────────────────────────────────────────────────────────

class _FakeCamera implements ScanCameraServicePort {
  final StreamController<RoiFrameMetrics> _metrics =
      StreamController<RoiFrameMetrics>.broadcast();
  CaptureRoi _roi = CaptureRoi.full;

  void emit(RoiFrameMetrics m) => _metrics.add(m);

  @override
  Stream<RoiFrameMetrics> get metrics => _metrics.stream;

  @override
  CaptureRoi get roi => _roi;

  @override
  void setRoi(CaptureRoi roi) => _roi = roi;

  @override
  Size? get previewFrameSize => const Size(1280, 720);

  @override
  bool get isReady => true;

  @override
  Future<bool> hasCamera() async => true;

  @override
  Stream<LumaFrame> get detectionFrames => const Stream.empty();

  @override
  int get sensorOrientationDegrees => 90;

  @override
  Future<void> initialize() async {}

  @override
  Future<Uint8List?> captureStandardized() async => null;

  @override
  Future<void> restartSampling() async {}

  @override
  Future<void> lockExposure() async {}

  @override
  Future<void> unlockExposure() async {}

  @override
  Future<void> setFlash(bool on) async {}

  @override
  Future<void> setZoom(double level) async {}

  @override
  Future<double> getMaxZoom() async => 5.0;

  @override
  Future<void> dispose() async => _metrics.close();
}

class _FakeStabilitySensor implements StabilitySensorPort {
  final StreamController<double> _speeds =
      StreamController<double>.broadcast();
  int startCalls = 0;
  int stopCalls = 0;

  void emit(double v) => _speeds.add(v);

  @override
  Stream<double> get angularSpeed => _speeds.stream;

  @override
  Stream<AngularVelocity> get angularVelocity => const Stream.empty();

  @override
  Future<bool> isAvailable({Duration timeout = const Duration(seconds: 2)}) async =>
      true;

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<void> stop() async => stopCalls++;
}
