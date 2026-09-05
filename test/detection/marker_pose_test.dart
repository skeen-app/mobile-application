import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/application/marker_detector.dart';
import 'package:skeen/features/detection/application/pose_estimator.dart';
import 'package:skeen/features/detection/domain/camera_intrinsics.dart';
import 'package:skeen/features/detection/domain/fiducial_marker.dart';
import 'package:skeen/features/detection/domain/homography.dart';
import 'package:skeen/features/detection/domain/luma_frame.dart';
import 'package:skeen/features/detection/domain/skin_plane_pose.dart';

/// WP-1 — detector + pose estimator against synthetic frames with known
/// ground truth. The renderer projects the marker through an exact
/// `K [r1 r2 t]` so corners, px/mm and tilt are all known analytically.
///
/// Equity applies here too: the detector is run over the three base skin
/// tones (luma 200 / 120 / 55) and must behave identically. A detector that
/// found the card more easily on light skin would bias the guided arm just
/// as surely as the old blob estimator did.
const int kLightSkin = 200;
const int kMediumSkin = 120;
const int kDarkSkin = 55;

/// A rendered scene with its ground truth.
class _Scene {
  const _Scene({
    required this.frame,
    required this.intrinsics,
    required this.cornersGt,
    required this.tiltDegGt,
    required this.pxPerMmGt,
  });

  final LumaFrame frame;
  final CameraIntrinsics intrinsics;

  /// Ground-truth corners of the rendered square (TL, TR, BR, BL in the
  /// *render's* plane frame), full-frame pixels.
  final List<Offset> cornersGt;
  final double tiltDegGt;
  final double pxPerMmGt;
}

/// Renders the marker on skin under a known pose.
///
/// The plane is rotated by [tiltDeg] about the camera's X axis and placed at
/// [distanceMm] along the optical axis (plus an optional lateral offset).
/// [renderBits] lets a test rotate the code on the card.
_Scene _render({
  required int skin,
  double tiltDeg = 0,
  double distanceMm = 150,
  double focalPx = 800,
  int width = 640,
  int height = 360,
  double offsetXmm = 0,
  double offsetYmm = 0,
  int? renderBits,
  bool withMarker = true,
  int noiseAmplitude = 3,
}) {
  final marker = FiducialMarker(
    bits: renderBits ?? FiducialMarker.study.bits,
    sideMm: FiducialMarker.study.sideMm,
  );
  final cx = width / 2, cy = height / 2;
  final theta = tiltDeg * math.pi / 180;
  final c = math.cos(theta), s = math.sin(theta);

  // R = Rx(theta): plane X stays horizontal, plane Y tips toward the camera.
  // Columns r1 = (1,0,0), r2 = (0,c,s). Camera frame: x right, y down,
  // z forward.
  final t = [offsetXmm, offsetYmm, distanceMm];
  Offset project(double xMm, double yMm) {
    final xc = xMm + t[0];
    final yc = yMm * c + t[1];
    final zc = yMm * s + t[2];
    return Offset(focalPx * xc / zc + cx, focalPx * yc / zc + cy);
  }

  final half = marker.sideMm / 2;
  final cornersGt = [
    project(-half, -half),
    project(half, -half),
    project(half, half),
    project(-half, half),
  ];

  // Inverse map for rendering: image → plane via the exact homography.
  final hom = homographyFromPoints(
    [
      Offset(-half, -half),
      Offset(half, -half),
      Offset(half, half),
      Offset(-half, half),
    ],
    cornersGt,
  )!;
  final inv = hom.inverse()!;

  final quiet = half + marker.cellMm * marker.quietZoneCells;
  final luma = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var value = skin;
      if (withMarker) {
        final p = inv.apply(x + 0.5, y + 0.5);
        if (p != null) {
          final px = p.dx, py = p.dy;
          if (px.abs() <= half && py.abs() <= half) {
            final col = ((px + half) / marker.cellMm).floor();
            final row = ((py + half) / marker.cellMm).floor();
            value = marker.isCellWhite(row, col) ? 235 : 30;
          } else if (px.abs() <= quiet && py.abs() <= quiet) {
            value = 235;
          }
        }
      }
      // Deterministic sensor-like noise.
      final n = ((x * 73856093) ^ (y * 19349663)).abs() %
              (2 * noiseAmplitude + 1) -
          noiseAmplitude;
      luma[y * width + x] = (value + n).clamp(0, 255);
    }
  }

  // Ground-truth scale at the origin for a tilt about X: horizontal f/d,
  // vertical f·cosθ/d, geometric mean (f/d)·√cosθ.
  final pxPerMmGt = (focalPx / distanceMm) * math.sqrt(c);

  return _Scene(
    frame: LumaFrame(
      luma: luma,
      width: width,
      height: height,
      capturedAt: DateTime(2026, 9, 4),
      scaleToFull: 1.0,
      zoom: 1.0,
    ),
    intrinsics: CameraIntrinsics(
      focalPx: focalPx,
      principalX: cx,
      principalY: cy,
      frameWidth: width,
      frameHeight: height,
    ),
    cornersGt: cornersGt,
    tiltDegGt: tiltDeg,
    pxPerMmGt: pxPerMmGt,
  );
}

double _maxCornerError(List<Offset> got, List<Offset> expected) {
  var worst = 0.0;
  for (var i = 0; i < 4; i++) {
    worst = math.max(worst, (got[i] - expected[i]).distance);
  }
  return worst;
}

SkinPlanePose _poseOf(_Scene scene, MarkerDetection d) => estimatePose(
      corners: d.corners,
      intrinsics: scene.intrinsics,
      detectedAt: scene.frame.capturedAt,
      detectionMs: d.elapsedMs,
    )!;

void main() {
  group('FiducialMarker code', () {
    test('rotations are mutually far apart and far from solid', () {
      final rots = FiducialMarker.study.rotations;
      expect(rots.toSet().length, 4);
      for (var i = 0; i < 4; i++) {
        for (var j = i + 1; j < 4; j++) {
          expect(FiducialMarker.hamming(rots[i], rots[j]),
              greaterThanOrEqualTo(10));
        }
        expect(FiducialMarker.hamming(rots[i], 0), greaterThanOrEqualTo(8));
        expect(
            FiducialMarker.hamming(rots[i], 0xFFFF), greaterThanOrEqualTo(8));
      }
    });

    test('four clockwise turns are the identity', () {
      var code = FiducialMarker.study.bits;
      for (var i = 0; i < 4; i++) {
        code = FiducialMarker.rotateClockwise(code);
      }
      expect(code, FiducialMarker.study.bits);
    });

    test('a one-bit error still matches; two do not', () {
      final m = FiducialMarker.study;
      expect(m.matchRotation(m.bits ^ 0x0001), 0);
      expect(m.matchRotation(m.bits ^ 0x0003), isNull);
    });
  });

  group('detection', () {
    test('finds the marker fronto-parallel with sub-2px corners', () {
      final scene = _render(skin: kMediumSkin);

      final d = detectMarker(scene.frame);

      expect(d, isNotNull);
      expect(d!.rotation, 0);
      expect(d.hammingErrors, 0);
      expect(_maxCornerError(d.corners, scene.cornersGt), lessThan(2.0));
    });

    test('finds it identically on light, medium and dark skin', () {
      // The detector must not be a second Fitzpatrick filter.
      final errors = <int, double>{};
      for (final skin in [kLightSkin, kMediumSkin, kDarkSkin]) {
        final scene = _render(skin: skin, tiltDeg: 10);
        final d = detectMarker(scene.frame);

        expect(d, isNotNull, reason: 'skin $skin');
        expect(d!.hammingErrors, 0, reason: 'skin $skin');
        errors[skin] = _maxCornerError(d.corners, scene.cornersGt);
        expect(errors[skin], lessThan(2.0), reason: 'skin $skin');
      }
      final spread = errors.values.reduce(math.max) - errors.values.reduce(math.min);
      expect(spread, lessThan(1.0),
          reason: 'corner accuracy must not depend on skin tone');
    });

    test('resolves the card\'s rotation to a canonical corner order', () {
      final bits = FiducialMarker.study.bits;
      var rendered = bits;
      for (var k = 0; k < 4; k++) {
        final scene = _render(skin: kMediumSkin, renderBits: rendered);
        final d = detectMarker(scene.frame);

        expect(d, isNotNull, reason: 'rotation $k');
        expect(d!.rotation, k, reason: 'rotation $k');
        // Canonical TL is the render corner k quarter-turns clockwise.
        final expected = [
          for (var i = 0; i < 4; i++) scene.cornersGt[(i + k) % 4],
        ];
        expect(_maxCornerError(d.corners, expected), lessThan(2.0),
            reason: 'rotation $k');

        rendered = FiducialMarker.rotateClockwise(rendered);
      }
    });

    test('works across the 10–20 cm working range', () {
      for (final d in [100.0, 150.0, 200.0]) {
        final scene = _render(skin: kDarkSkin, distanceMm: d);
        final det = detectMarker(scene.frame);
        expect(det, isNotNull, reason: 'distance $d mm');
        expect(_maxCornerError(det!.corners, scene.cornersGt), lessThan(2.0),
            reason: 'distance $d mm');
      }
    });

    test('still detects on a half-resolution luma plane', () {
      // 320×180 at 20 cm: the marker is ~60 px across.
      final scene = _render(
        skin: kMediumSkin,
        distanceMm: 200,
        focalPx: 400,
        width: 320,
        height: 180,
      );
      final d = detectMarker(scene.frame);

      expect(d, isNotNull);
      expect(_maxCornerError(d!.corners, scene.cornersGt), lessThan(1.5));
    });

    test('returns null when there is no marker', () {
      for (final skin in [kLightSkin, kDarkSkin]) {
        final scene = _render(skin: skin, withMarker: false);
        expect(detectMarker(scene.frame), isNull, reason: 'skin $skin');
      }
    });

    test('tolerates strong tilt', () {
      final scene = _render(skin: kMediumSkin, tiltDeg: 35);
      final d = detectMarker(scene.frame);

      expect(d, isNotNull);
      expect(_maxCornerError(d!.corners, scene.cornersGt), lessThan(2.5));
    });
  });

  group('pose', () {
    test('px/mm within 2% fronto-parallel', () {
      final scene = _render(skin: kMediumSkin);
      final pose = _poseOf(scene, detectMarker(scene.frame)!);

      expect(pose.pxPerMm, closeTo(scene.pxPerMmGt, scene.pxPerMmGt * 0.02));
      expect(pose.tiltDeg, lessThan(3.0));
    });

    test('px/mm within 5% and tilt within ±3° across known tilts', () {
      for (final tilt in [5.0, 12.0, 20.0, 25.0]) {
        final scene = _render(skin: kMediumSkin, tiltDeg: tilt);
        final pose = _poseOf(scene, detectMarker(scene.frame)!);

        expect(pose.pxPerMm, closeTo(scene.pxPerMmGt, scene.pxPerMmGt * 0.05),
            reason: 'tilt $tilt°');
        expect(pose.tiltDeg, closeTo(tilt, 3.0), reason: 'tilt $tilt°');
      }
    });

    test('pose is the same on every skin tone', () {
      final tilts = <double>[];
      final scales = <double>[];
      for (final skin in [kLightSkin, kMediumSkin, kDarkSkin]) {
        final scene = _render(skin: skin, tiltDeg: 12, distanceMm: 130);
        final pose = _poseOf(scene, detectMarker(scene.frame)!);
        tilts.add(pose.tiltDeg);
        scales.add(pose.pxPerMm);
      }
      expect(tilts.reduce(math.max) - tilts.reduce(math.min), lessThan(1.0));
      expect(scales.reduce(math.max) - scales.reduce(math.min),
          lessThan(scales.first * 0.02));
    });

    test('px/mm tracks distance', () {
      final near = _render(skin: kMediumSkin, distanceMm: 100);
      final far = _render(skin: kMediumSkin, distanceMm: 200);
      final pNear = _poseOf(near, detectMarker(near.frame)!);
      final pFar = _poseOf(far, detectMarker(far.frame)!);

      expect(pNear.pxPerMm / pFar.pxPerMm, closeTo(2.0, 0.1));
    });

    test('the plane→image map projects the marker corners back', () {
      final scene = _render(skin: kMediumSkin, tiltDeg: 15, offsetXmm: 12);
      final pose = _poseOf(scene, detectMarker(scene.frame)!);
      const half = 15.0;

      expect((pose.project(-half, -half)! - scene.cornersGt[0]).distance,
          lessThan(2.5));
      expect((pose.project(half, half)! - scene.cornersGt[2]).distance,
          lessThan(2.5));
    });

    test('a pose goes stale after 400 ms', () {
      final scene = _render(skin: kMediumSkin);
      final pose = _poseOf(scene, detectMarker(scene.frame)!);
      final t0 = scene.frame.capturedAt;

      expect(pose.isStaleAt(t0.add(const Duration(milliseconds: 399))), isFalse);
      expect(pose.isStaleAt(t0.add(const Duration(milliseconds: 401))), isTrue);
    });

    test('no intrinsics ⇒ no pose, never a default tilt', () {
      final scene = _render(skin: kMediumSkin);
      final d = detectMarker(scene.frame)!;
      final pose = estimatePose(
        corners: d.corners,
        intrinsics: const CameraIntrinsics(
          focalPx: 0,
          principalX: 320,
          principalY: 180,
          frameWidth: 640,
          frameHeight: 360,
        ),
        detectedAt: scene.frame.capturedAt,
        detectionMs: 0,
      );

      expect(pose, isNull);
    });
  });

  group('cost', () {
    test('per-frame detector time on this host (proxy for the Dart-vs-native '
        'decision)', () {
      final scene = _render(skin: kMediumSkin, tiltDeg: 8);
      final half = _render(
        skin: kMediumSkin,
        tiltDeg: 8,
        focalPx: 400,
        width: 320,
        height: 180,
      );

      int bench(LumaFrame f) {
        detectMarker(f); // warm-up
        final sw = Stopwatch()..start();
        const runs = 20;
        for (var i = 0; i < runs; i++) {
          detectMarker(f);
        }
        return (sw.elapsedMicroseconds / runs / 1000).round();
      }

      final full = bench(scene.frame);
      final small = bench(half.frame);
      // ignore: avoid_print
      print('detectMarker: 640×360 ≈ $full ms/frame, 320×180 ≈ $small ms/frame (host)');

      // Generous ceiling so CI never flakes; the printed number is the
      // deliverable.
      expect(full, lessThan(500));
    });
  });
}
