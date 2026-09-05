import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/application/anchor_smoother.dart';
import 'package:skeen/features/detection/application/readiness_evaluator.dart';
import 'package:skeen/features/detection/domain/camera_intrinsics.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';
import 'package:skeen/features/detection/domain/capture_stability.dart';
import 'package:skeen/features/detection/domain/display_mapping.dart';
import 'package:skeen/features/detection/domain/lesion_anchor.dart';
import 'package:skeen/features/detection/domain/luma_frame.dart';
import 'package:skeen/features/detection/domain/ports.dart';
import 'package:skeen/features/detection/domain/roi_frame_metrics.dart';
import 'package:skeen/features/detection/domain/roi_metrics_calculator.dart';
import 'package:skeen/features/detection/domain/skin_plane_pose.dart';

/// WP-2c (glare where it is) and WP-2d (reticle on the lesion): the parts
/// that are geometry, tested as geometry. What the painters draw is a direct
/// function of these values.
const _bounds = RoiBounds(left: 0, top: 0, width: 240, height: 240);

void main() {
  group('glare map (WP-2c)', () {
    test('locates a highlight in the cell map and the centroid', () {
      // Blown disc in the top-left quadrant of the ROI, skin elsewhere.
      final metrics = computeRoiMetrics(
        bounds: _bounds,
        luma: (x, y) {
          final dx = x - 60, dy = y - 60;
          return dx * dx + dy * dy <= 20 * 20 ? 255 : 130;
        },
      );

      const n = RoiFrameMetrics.glareGridSize;
      expect(metrics.glareCells, hasLength(n * n));
      // Cells around (60,60)/240 ≈ (0.25, 0.25) → cell (2,2) are hot…
      expect(metrics.glareCells[2 * n + 2],
          greaterThan(RoiFrameMetrics.glareCellVisible));
      // …the opposite quadrant is clean.
      expect(metrics.glareCells[6 * n + 6], 0);
      expect(metrics.glareCentroid, isNotNull);
      expect(metrics.glareCentroid!.dx, closeTo(0.25, 0.03));
      expect(metrics.glareCentroid!.dy, closeTo(0.25, 0.03));
    });

    test('a clean frame has an all-zero map and no centroid', () {
      final metrics = computeRoiMetrics(bounds: _bounds, luma: (x, y) => 140);

      expect(metrics.glareCells.every((c) => c == 0), isTrue);
      expect(metrics.glareCentroid, isNull);
    });

    test('the map is independent of skin tone', () {
      for (final skin in [200, 120, 55]) {
        final metrics = computeRoiMetrics(
          bounds: _bounds,
          luma: (x, y) => (x > 180 && y > 180) ? 255 : skin,
        );
        const n = RoiFrameMetrics.glareGridSize;
        expect(metrics.glareCells[7 * n + 7], greaterThan(0.9),
            reason: 'skin $skin');
        expect(metrics.glareCells[0], 0, reason: 'skin $skin');
      }
    });
  });

  group('sensor → display mapping', () {
    test('90° mounting turns the landscape frame upright', () {
      // Stream top-left (0,0) → screen top-right; stream +x → screen down.
      expect(roiToDisplay(const Offset(0, 0), 90), const Offset(1, 0));
      expect(roiToDisplay(const Offset(1, 0), 90), const Offset(1, 1));
      expect(roiToDisplay(const Offset(0, 1), 90), const Offset(0, 0));
      expect(roiToDisplay(const Offset(0.5, 0.5), 90), const Offset(0.5, 0.5));
    });

    test('every mounting round-trips', () {
      for (final o in [0, 90, 180, 270]) {
        const p = Offset(0.2, 0.7);
        final back = displayToRoi(roiToDisplay(p, o), o);
        expect(back.dx, closeTo(p.dx, 1e-12), reason: '$o');
        expect(back.dy, closeTo(p.dy, 1e-12), reason: '$o');
      }
    });

    test('the same function maps lesion and glare, so they stay coherent',
        () {
      // A highlight to the stream-right of the lesion must land to the
      // screen-below of it on a 90° mount — both go through one mapping.
      const lesion = Offset(0.4, 0.5);
      const glare = Offset(0.7, 0.5);
      final l = roiToDisplay(lesion, 90);
      final g = roiToDisplay(glare, 90);
      expect(g.dy, greaterThan(l.dy));
      expect(g.dx, closeTo(l.dx, 1e-12));
    });
  });

  group('AnchorSmoother (WP-2d)', () {
    late DateTime clock;
    AnchorSmoother build() {
      clock = DateTime(2026, 9, 4, 12);
      return AnchorSmoother(clock: () => clock);
    }

    test('the first measurement snaps, later ones blend', () {
      final s = build();
      s.measure(centre: const Offset(0.3, 0.3), diameterFraction: 0.4, at: clock);
      expect(s.current!.centre, const Offset(0.3, 0.3));
      expect(s.current!.predicted, isFalse);

      s.measure(centre: const Offset(0.5, 0.5), diameterFraction: 0.4, at: clock);
      expect(s.current!.centre.dx, closeTo(0.4, 1e-9), reason: 'alpha 0.5');

      // Converges: a steady target is reached within a few frames.
      for (var i = 0; i < 6; i++) {
        s.measure(centre: const Offset(0.5, 0.5), diameterFraction: 0.4, at: clock);
      }
      expect(s.current!.centre.dx, closeTo(0.5, 0.01));
    });

    test('a stale anchor disappears rather than lingering', () {
      final s = build();
      s.measure(centre: const Offset(0.5, 0.5), diameterFraction: 0.4, at: clock);
      clock = clock.add(const Duration(milliseconds: LesionAnchor.staleAfterMs + 1));

      expect(s.current, isNull);
    });

    test('a camera rotation carries the ring across the ROI', () {
      // Stream 640×480, f = 800, ROI = centred 240 px square. Yaw the camera
      // by 0.05 rad about y: image points move by ≈ f·θ = 40 px, i.e. a
      // sixth of the ROI side.
      final s = build();
      s.measure(centre: const Offset(0.5, 0.5), diameterFraction: 0.4, at: clock);
      const k = CameraIntrinsics(
        focalPx: 800,
        principalX: 320,
        principalY: 240,
        frameWidth: 640,
        frameHeight: 480,
      );
      final roi = const CaptureRoi(sideFraction: 0.5).boundsIn(640, 480);
      final r = Vec3.rodrigues([0, 0.05, 0]);

      s.predict(rotationTransposed: Vec3.transpose(r), intrinsics: k, roi: roi);

      final a = s.current!;
      expect(a.predicted, isTrue);
      expect((a.centre.dx - 0.5).abs(), closeTo(40 / 240, 0.01));
      expect(a.centre.dy, closeTo(0.5, 0.005));
      expect(a.diameterFraction, 0.4, reason: 'size is not a rotation');
    });

    test('a measurement after prediction is authoritative again', () {
      final s = build();
      s.measure(centre: const Offset(0.5, 0.5), diameterFraction: 0.4, at: clock);
      const k = CameraIntrinsics(
        focalPx: 800, principalX: 320, principalY: 240,
        frameWidth: 640, frameHeight: 480,
      );
      final roi = const CaptureRoi(sideFraction: 0.5).boundsIn(640, 480);
      s.predict(
        rotationTransposed: Vec3.transpose(Vec3.rodrigues([0, 0.05, 0])),
        intrinsics: k,
        roi: roi,
      );
      expect(s.current!.predicted, isTrue);

      s.measure(centre: const Offset(0.5, 0.5), diameterFraction: 0.4, at: clock);

      expect(s.current!.predicted, isFalse);
    });

    test('prediction without an anchor is a no-op', () {
      final s = build();
      const k = CameraIntrinsics(
        focalPx: 800, principalX: 320, principalY: 240,
        frameWidth: 640, frameHeight: 480,
      );
      s.predict(
        rotationTransposed: Vec3.transpose(Vec3.rodrigues([0, 0.05, 0])),
        intrinsics: k,
        roi: const CaptureRoi(sideFraction: 0.5).boundsIn(640, 480),
      );
      expect(s.current, isNull);
    });
  });

  group('evaluator wiring', () {
    test('a centroid measurement surfaces as the readiness anchor', () async {
      final camera = _FakeCamera();
      final sensor = _FakeSensor();
      final evaluator = ReadinessEvaluator(
        camera: camera,
        stabilitySensor: sensor,
        clock: () => DateTime(2026, 9, 4, 12),
      );
      await evaluator.start();

      camera.emit(RoiFrameMetrics(
        luma: 140,
        sharpnessRaw: 1000,
        glareFraction: 0,
        colorCast: ColorCast.neutral,
        lesionFillFraction: 0.45,
        lesionCentroid: const Offset(0.55, 0.48),
        sampleCount: 2000,
      ));
      await Future<void>.delayed(Duration.zero);

      final r = evaluator.current;
      expect(r.anchor, isNotNull);
      expect(r.anchor!.centre, const Offset(0.55, 0.48));
      expect(r.anchor!.diameterFraction, 0.45);
      expect(r.metrics.lesionCentroid, const Offset(0.55, 0.48));

      await evaluator.dispose();
    });

    test('no centroid ⇒ no anchor, never a default centre', () async {
      final camera = _FakeCamera();
      final evaluator = ReadinessEvaluator(
        camera: camera,
        stabilitySensor: _FakeSensor(),
        clock: () => DateTime(2026, 9, 4, 12),
      );
      await evaluator.start();

      camera.emit(RoiFrameMetrics(
        luma: 140,
        sharpnessRaw: 1000,
        glareFraction: 0,
        colorCast: ColorCast.neutral,
        lesionFillFraction: -1,
        sampleCount: 2000,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(evaluator.current.anchor, isNull);

      await evaluator.dispose();
    });

    test('without intrinsics the gyroscope does not move the ring', () async {
      // No pose tracker ⇒ no focal length ⇒ smoothing only. The ring must
      // not be pushed by an assumed f.
      final camera = _FakeCamera();
      final sensor = _FakeSensor();
      final evaluator = ReadinessEvaluator(
        camera: camera,
        stabilitySensor: sensor,
        clock: () => DateTime(2026, 9, 4, 12),
      );
      await evaluator.start();
      camera.emit(RoiFrameMetrics(
        luma: 140,
        sharpnessRaw: 1000,
        glareFraction: 0,
        colorCast: ColorCast.neutral,
        lesionFillFraction: 0.45,
        lesionCentroid: const Offset(0.5, 0.5),
        sampleCount: 2000,
      ));
      await Future<void>.delayed(Duration.zero);

      final t0 = DateTime(2026, 9, 4, 12);
      sensor.emitVelocity(AngularVelocity(x: 0, y: 1, z: 0, at: t0));
      sensor.emitVelocity(AngularVelocity(
          x: 0, y: 1, z: 0, at: t0.add(const Duration(milliseconds: 50))));
      await Future<void>.delayed(Duration.zero);

      expect(evaluator.current.anchor!.centre, const Offset(0.5, 0.5));
      expect(evaluator.current.anchor!.predicted, isFalse);

      await evaluator.dispose();
    });
  });

  test('math sanity: a yaw of θ moves the optical axis by f·tan θ', () {
    // Guards the conjugate-homography step both the tracker and the
    // smoother rely on.
    const k = CameraIntrinsics(
      focalPx: 800, principalX: 320, principalY: 240,
      frameWidth: 640, frameHeight: 480,
    );
    final kM = Matrix3([800, 0, 320, 0, 800, 240, 0, 0, 1]);
    final rT = Vec3.transpose(Vec3.rodrigues([0, 0.1, 0]));
    final conj = kM.multiply(Matrix3(rT)).multiply(kM.inverse()!);
    final moved = conj.apply(k.principalX, k.principalY)!;

    expect((moved.dx - 320).abs(), closeTo(800 * math.tan(0.1), 0.5));
    expect(moved.dy, closeTo(240, 0.5));
  });
}

// ──────────────────────────────────────────────────────────────────────
// Fakes — hand written, matching the repo's mock-framework-free style.
// ──────────────────────────────────────────────────────────────────────

class _FakeCamera implements ScanCameraServicePort {
  final StreamController<RoiFrameMetrics> _metrics =
      StreamController<RoiFrameMetrics>.broadcast();

  void emit(RoiFrameMetrics m) => _metrics.add(m);

  @override
  Stream<RoiFrameMetrics> get metrics => _metrics.stream;

  @override
  Stream<LumaFrame> get detectionFrames => const Stream.empty();

  @override
  int get sensorOrientationDegrees => 90;

  @override
  CaptureRoi get roi => const CaptureRoi(sideFraction: 0.5);

  @override
  void setRoi(CaptureRoi roi) {}

  @override
  Size? get previewFrameSize => const Size(640, 480);

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
  Future<void> dispose() async => _metrics.close();
}

class _FakeSensor implements StabilitySensorPort {
  final StreamController<double> _speeds = StreamController<double>.broadcast();
  final StreamController<AngularVelocity> _velocity =
      StreamController<AngularVelocity>.broadcast();

  void emitVelocity(AngularVelocity v) => _velocity.add(v);

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
