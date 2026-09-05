import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/application/marker_detector.dart';
import 'package:skeen/features/detection/application/pose_estimator.dart';
import 'package:skeen/features/detection/application/pose_tracker.dart';
import 'package:skeen/features/detection/domain/camera_intrinsics.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';
import 'package:skeen/features/detection/domain/capture_stability.dart';
import 'package:skeen/features/detection/domain/capture_standard.dart';
import 'package:skeen/features/detection/domain/luma_frame.dart';
import 'package:skeen/features/detection/domain/pose_readiness.dart';
import 'package:skeen/features/detection/domain/ports.dart';
import 'package:skeen/features/detection/domain/roi_frame_metrics.dart';
import 'package:skeen/features/detection/domain/skin_plane_pose.dart';
import 'package:skeen/features/detection/application/readiness_evaluator.dart';

/// WP-3 — the physical gate. Every axis fail-closed; thresholds from
/// `capture_standard.dart`.
const _k = CameraIntrinsics(
  focalPx: 800,
  principalX: 320,
  principalY: 180,
  frameWidth: 640,
  frameHeight: 360,
);

/// Stream ROI for a 640×360 stream at the study's box fraction: 0.55 of the
/// short side ⇒ 198 px ⇒ target 16.5 px/mm.
final _roi = const CaptureRoi(sideFraction: 0.55).boundsIn(640, 360);

/// A pose with the target disc on the optical axis at the distance that puts
/// the scale at [ratio] × target, tilted by [tiltDeg] about the **disc**
/// (so the local tilt there equals [tiltDeg]).
SkinPlanePose _pose({double ratio = 1.0, double tiltDeg = 0}) {
  final target = targetPxPerMm(_roi.width.toDouble());
  final distance = _k.focalPx / (target * ratio);
  final disc = TargetDisc.centreMm();
  final th = tiltDeg * math.pi / 180;
  final c = math.cos(th), s = math.sin(th);
  Offset project(double x, double y) {
    final py = y - disc.dy; // plane coordinates re-based on the disc centre
    final zc = py * s + distance;
    return Offset(
      _k.focalPx * x / zc + _k.principalX,
      _k.focalPx * (py * c) / zc + _k.principalY,
    );
  }

  const h = 15.0;
  return estimatePose(
    corners: [project(-h, -h), project(h, -h), project(h, h), project(-h, h)],
    intrinsics: _k,
    detectedAt: DateTime(2026, 9, 4, 12),
    detectionMs: 0,
  )!;
}

/// The lesion centroid, ROI-normalized, for a lesion sitting [offsetRadii]
/// disc radii to the right of the disc centre.
Offset _lesionAt(SkinPlanePose pose, double offsetRadii) {
  final disc = TargetDisc.centreMm();
  final px = pose.project(
    disc.dx + offsetRadii * TargetDisc.diameterMm / 2,
    disc.dy,
  )!;
  return Offset(
    (px.dx - _roi.left) / _roi.width,
    (px.dy - _roi.top) / _roi.height,
  );
}

void main() {
  final now = DateTime(2026, 9, 4, 12);

  group('PoseReadiness.evaluate', () {
    test('no pose ⇒ absent, closed, "show the marker"', () {
      final r = PoseReadiness.evaluate(pose: null, roi: _roi, now: now);

      expect(r.hasPose, isFalse);
      expect(r.isReady, isFalse);
      expect(r.advice, PoseAdvice.showMarker);
    });

    test('a stale pose is treated as no pose', () {
      final pose = _pose();
      final later = now.add(const Duration(milliseconds: SkinPlanePose.staleAfterMs + 1));

      final r = PoseReadiness.evaluate(
        pose: pose,
        roi: _roi,
        now: later,
        lesionCentroidRoi: _lesionAt(pose, 0),
      );

      expect(r.hasPose, isFalse);
      expect(r.isReady, isFalse);
    });

    test('on target, level and centred ⇒ ready', () {
      final pose = _pose();
      final r = PoseReadiness.evaluate(
        pose: pose,
        roi: _roi,
        now: now,
        lesionCentroidRoi: _lesionAt(pose, 0.05),
      );

      expect(r.scaleRatio, closeTo(1.0, 0.03));
      expect(r.localTiltDeg, lessThan(1.5));
      expect(r.centreOffset, closeTo(0.05, 0.03));
      expect(r.isReady, isTrue);
      expect(r.advice, PoseAdvice.ok);
    });

    test('scale: ±15% passes, beyond fails with the right direction', () {
      for (final ratio in [0.86, 1.0, 1.14]) {
        final pose = _pose(ratio: ratio);
        final r = PoseReadiness.evaluate(
          pose: pose, roi: _roi, now: now, lesionCentroidRoi: _lesionAt(pose, 0),
        );
        expect(r.scaleOk, isTrue, reason: 'ratio $ratio');
      }
      final far = _pose(ratio: 0.8);
      final rFar = PoseReadiness.evaluate(
        pose: far, roi: _roi, now: now, lesionCentroidRoi: _lesionAt(far, 0),
      );
      expect(rFar.scaleOk, isFalse);
      expect(rFar.advice, PoseAdvice.moveCloser);

      final near = _pose(ratio: 1.2);
      final rNear = PoseReadiness.evaluate(
        pose: near, roi: _roi, now: now, lesionCentroidRoi: _lesionAt(near, 0),
      );
      expect(rNear.scaleOk, isFalse);
      expect(rNear.advice, PoseAdvice.moveAway);
    });

    test('tilt: 12° at the disc is the limit; 25° closes the gate', () {
      final ok = _pose(tiltDeg: 10);
      final rOk = PoseReadiness.evaluate(
        pose: ok, roi: _roi, now: now, lesionCentroidRoi: _lesionAt(ok, 0),
      );
      expect(rOk.tiltOk, isTrue);

      final bad = _pose(tiltDeg: 25);
      final rBad = PoseReadiness.evaluate(
        pose: bad, roi: _roi, now: now, lesionCentroidRoi: _lesionAt(bad, 0),
      );
      expect(rBad.localTiltDeg, closeTo(25, 3));
      expect(rBad.tiltOk, isFalse);
      expect(rBad.isReady, isFalse);
      expect(rBad.advice, PoseAdvice.levelPhone);
    });

    test('scale is evaluated at the disc, not at the marker', () {
      // Rotating about the disc leaves the disc's depth unchanged and moves
      // the marker away. The gate must follow the disc: that is where the
      // lesion — and the crop — are.
      final pose = _pose(tiltDeg: 25);
      final disc = TargetDisc.centreMm();
      final target = targetPxPerMm(_roi.width.toDouble());

      expect(pose.pxPerMmAt(disc.dx, disc.dy) / target, closeTo(1.0, 0.05));
      expect(pose.pxPerMm / target, lessThan(0.9),
          reason: 'the marker itself is farther away');
      expect(pose.pxPerMmAt(0, 0), closeTo(pose.pxPerMm, 0.01),
          reason: 'at the marker centre the two agree');
    });

    test('advice order: scale before tilt before centring', () {
      const scaleThenTilt = PoseReadiness(
        hasPose: true, scaleRatio: 0.7, localTiltDeg: 30, centreOffset: 0.9,
      );
      const tiltThenCentre = PoseReadiness(
        hasPose: true, scaleRatio: 1.0, localTiltDeg: 30, centreOffset: 0.9,
      );
      const centreOnly = PoseReadiness(
        hasPose: true, scaleRatio: 1.0, localTiltDeg: 3, centreOffset: 0.9,
      );
      expect(scaleThenTilt.advice, PoseAdvice.moveCloser);
      expect(tiltThenCentre.advice, PoseAdvice.levelPhone);
      expect(centreOnly.advice, PoseAdvice.centreLesion);
    });

    test('centring: within 0.2 radii passes; beyond, "centre the mole"', () {
      final pose = _pose();
      final inside = PoseReadiness.evaluate(
        pose: pose, roi: _roi, now: now, lesionCentroidRoi: _lesionAt(pose, 0.15),
      );
      expect(inside.centredOk, isTrue);

      final outside = PoseReadiness.evaluate(
        pose: pose, roi: _roi, now: now, lesionCentroidRoi: _lesionAt(pose, 0.4),
      );
      expect(outside.centreOffset, closeTo(0.4, 0.05));
      expect(outside.centredOk, isFalse);
      expect(outside.advice, PoseAdvice.centreLesion);
    });

    test('no segmented lesion ⇒ not centred, "bring the mole inside"', () {
      final r = PoseReadiness.evaluate(pose: _pose(), roi: _roi, now: now);

      expect(r.hasPose, isTrue);
      expect(r.centreOffset, isNull);
      expect(r.centredOk, isFalse);
      expect(r.isReady, isFalse);
      expect(r.advice, PoseAdvice.findLesion);
    });

    test('the target px/mm follows the crop resolution', () {
      // Same physical pose, coarser stream ⇒ fewer px/mm are needed.
      final pose = _pose();
      final coarse = const CaptureRoi(sideFraction: 0.55).boundsIn(320, 180);
      final r = PoseReadiness.evaluate(pose: pose, roi: coarse, now: now);

      // The pose is still 16.5 px/mm, but the target is now half of that.
      expect(r.scaleRatio, closeTo(2.0, 0.06));
      expect(r.advice, PoseAdvice.moveAway);
    });
  });

  group('evaluator integration', () {
    late DateTime clock;

    test('the marker pose and the segmented lesion open the physical gate',
        () async {
      clock = DateTime(2026, 9, 4, 12);
      final camera = _FakeCamera();
      final sensor = _FakeSensor();
      final pose = _pose();
      final tracker = PoseTracker(
        camera: camera,
        stabilitySensor: sensor,
        intrinsics: _FakeIntrinsics(),
        clock: () => clock,
        detect: (_) async => MarkerDetection(
          corners: pose.markerCorners,
          rotation: 0,
          hammingErrors: 0,
          elapsedMs: 5,
        ),
      );
      final evaluator = ReadinessEvaluator(
        camera: camera,
        stabilitySensor: sensor,
        poseTracker: tracker,
        clock: () => clock,
      );
      await evaluator.start();

      // Sharpness reference + steady hand, as the existing gates need.
      for (var i = 0; i < 10; i++) {
        clock = clock.add(const Duration(milliseconds: 330));
        camera.emitMetrics(RoiFrameMetrics(
          luma: 140,
          sharpnessRaw: 4000,
          glareFraction: 0,
          colorCast: ColorCast.neutral,
          lesionFillFraction: 0.45,
          lesionCentroid: _lesionAt(pose, 0.05),
          sampleCount: 2000,
        ));
        await Future<void>.delayed(Duration.zero);
      }
      sensor.emitSpeed(0.02);
      await Future<void>.delayed(Duration.zero);

      expect(evaluator.current.isReady, isFalse,
          reason: 'no marker yet ⇒ closed');
      expect(evaluator.current.failingKey, 'marker');

      camera.emitFrame(LumaFrame(
        luma: Uint8List(640 * 360),
        width: 640,
        height: 360,
        capturedAt: clock,
        scaleToFull: 1,
        zoom: 1,
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final r = evaluator.current;
      expect(r.poseReadiness.hasPose, isTrue);
      expect(r.poseReadiness.scaleOk, isTrue, reason: '${r.poseReadiness}');
      expect(r.poseReadiness.tiltOk, isTrue);
      expect(r.poseReadiness.centredOk, isTrue);
      expect(r.isReady, isTrue);
      expect(r.failingKey, isNull);

      // Cover the marker: the pose goes stale and the gate closes.
      clock = clock.add(const Duration(milliseconds: SkinPlanePose.staleAfterMs + 1));
      expect(evaluator.current.isReady, isFalse);
      expect(evaluator.current.failingKey, 'marker');

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
  final StreamController<LumaFrame> _frames =
      StreamController<LumaFrame>.broadcast();

  void emitMetrics(RoiFrameMetrics m) => _metrics.add(m);
  void emitFrame(LumaFrame f) => _frames.add(f);

  @override
  Stream<RoiFrameMetrics> get metrics => _metrics.stream;

  @override
  Stream<LumaFrame> get detectionFrames => _frames.stream;

  @override
  int get sensorOrientationDegrees => 90;

  @override
  CaptureRoi get roi => const CaptureRoi(sideFraction: 0.55);

  @override
  void setRoi(CaptureRoi roi) {}

  @override
  Size? get previewFrameSize => const Size(640, 360);

  @override
  bool get isReady => true;

  @override
  Future<bool> hasCamera() async => true;

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
  Future<void> dispose() async {
    await _metrics.close();
    await _frames.close();
  }
}

class _FakeSensor implements StabilitySensorPort {
  final StreamController<double> _speeds = StreamController<double>.broadcast();
  final StreamController<AngularVelocity> _velocity =
      StreamController<AngularVelocity>.broadcast();

  void emitSpeed(double v) => _speeds.add(v);

  @override
  Stream<double> get angularSpeed => _speeds.stream;

  @override
  Stream<AngularVelocity> get angularVelocity => _velocity.stream;

  @override
  Future<bool> isAvailable({Duration timeout = const Duration(seconds: 2)}) async =>
      true;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _FakeIntrinsics implements CameraIntrinsicsPort {
  @override
  Future<CameraIntrinsics?> read({
    required int frameWidth,
    required int frameHeight,
  }) async =>
      _k;
}
