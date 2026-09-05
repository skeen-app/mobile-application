import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/application/marker_detector.dart';
import 'package:skeen/features/detection/application/patch_sampler.dart';
import 'package:skeen/features/detection/application/pose_estimator.dart';
import 'package:skeen/features/detection/domain/camera_intrinsics.dart';
import 'package:skeen/features/detection/domain/capture_standard.dart';
import 'package:skeen/features/detection/domain/color_calibration.dart';
import 'package:skeen/features/detection/domain/fiducial_marker.dart';
import 'package:skeen/features/detection/domain/homography.dart';
import 'package:skeen/features/detection/domain/luma_frame.dart';
import 'package:skeen/features/detection/domain/roi_frame_metrics.dart';
import 'package:skeen/features/detection/domain/skin_plane_pose.dart';

/// WP-4 — colour and luma calibration against the marker's printed patches.
///
/// The renderer is physical: every surface has a linear reflectance, the
/// illuminant is a per-channel multiplier, and the sensor encodes sRGB. That
/// is exactly the model the calibration inverts, so the acceptance — the
/// same subject reads the same under tungsten, fluorescent and daylight — is
/// a real test of the maths, not of a lookup.
class _Illuminant {
  const _Illuminant(this.name, this.r, this.g, this.b, {this.intensity = 1});
  final String name;
  final double r, g, b, intensity;
}

const _daylight = _Illuminant('daylight', 1.0, 1.0, 1.0);
const _tungsten = _Illuminant('tungsten', 1.25, 1.0, 0.70);
const _fluorescent = _Illuminant('fluorescent', 0.92, 1.12, 0.90);
const _dim = _Illuminant('dim daylight', 1.0, 1.0, 1.0, intensity: 0.55);

/// Linear reflectance of the "subject": a medium skin, red-dominant as real
/// skin is, but inside the colour gate's tolerance under neutral light.
const _skin = [0.42, 0.33, 0.28];
const _ink = [0.03, 0.03, 0.03];
const _paper = [0.90, 0.90, 0.90];

class _Scene {
  const _Scene(this.frame, this.pose);
  final LumaFrame frame;
  final SkinPlanePose pose;
}

/// Renders the card (code + patches) on skin under [light], fronto-parallel
/// at [distanceMm], and returns the frame with its ground-truth pose.
_Scene _render(_Illuminant light, {double distanceMm = 130}) {
  const w = 640, h = 360;
  const f = 800.0, cx = w / 2, cy = h / 2;
  final marker = FiducialMarker.study;
  final half = marker.sideMm / 2;
  final quiet = half + marker.cellMm * marker.quietZoneCells;

  Offset project(double x, double y) =>
      Offset(f * x / distanceMm + cx, f * y / distanceMm + cy);
  final corners = [
    project(-half, -half),
    project(half, -half),
    project(half, half),
    project(-half, half),
  ];
  final inv = homographyFromPoints(
    [
      Offset(-half, -half),
      Offset(half, -half),
      Offset(half, half),
      Offset(-half, half),
    ],
    corners,
  )!
      .inverse()!;

  bool inPatch(ColorPatch p, double x, double y) =>
      (x - p.centreMm.dx).abs() <= p.sideMm / 2 &&
      (y - p.centreMm.dy).abs() <= p.sideMm / 2;

  final luma = Uint8List(w * h);
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var refl = _skin;
      final p = inv.apply(x + 0.5, y + 0.5)!;
      if (p.dx.abs() <= half && p.dy.abs() <= half) {
        final col = ((p.dx + half) / marker.cellMm).floor();
        final row = ((p.dy + half) / marker.cellMm).floor();
        refl = marker.isCellWhite(row, col) ? _paper : _ink;
      } else if (p.dx.abs() <= quiet && p.dy.abs() <= quiet) {
        refl = _paper;
      } else if (inPatch(marker.greyPatch, p.dx, p.dy)) {
        refl = const [0.18, 0.18, 0.18];
      } else if (inPatch(marker.whitePatch, p.dx, p.dy)) {
        refl = const [0.90, 0.90, 0.90];
      }
      final lin = [
        refl[0] * light.r * light.intensity,
        refl[1] * light.g * light.intensity,
        refl[2] * light.b * light.intensity,
      ];
      final r = linearToSrgb(lin[0]).round();
      final g = linearToSrgb(lin[1]).round();
      final b = linearToSrgb(lin[2]).round();
      final i = y * w + x;
      rgb[i * 3] = r;
      rgb[i * 3 + 1] = g;
      rgb[i * 3 + 2] = b;
      luma[i] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    }
  }

  final frame = LumaFrame(
    luma: luma,
    width: w,
    height: h,
    capturedAt: DateTime(2026, 9, 4),
    scaleToFull: 1,
    zoom: 1,
    rgb: rgb,
  );
  final pose = estimatePose(
    corners: corners,
    intrinsics: const CameraIntrinsics(
      focalPx: f,
      principalX: cx,
      principalY: cy,
      frameWidth: w,
      frameHeight: h,
    ),
    detectedAt: frame.capturedAt,
    detectionMs: 0,
  )!;
  return _Scene(frame, pose);
}

/// The ROI colour the metrics pipeline would report for bare skin.
ColorCast _skinCastUnder(_Illuminant light) => ColorCast(
      rMean: linearToSrgb(_skin[0] * light.r * light.intensity),
      gMean: linearToSrgb(_skin[1] * light.g * light.intensity),
      bMean: linearToSrgb(_skin[2] * light.b * light.intensity),
    );

double _skinLumaUnder(_Illuminant light) {
  final c = _skinCastUnder(light);
  return 0.299 * c.rMean + 0.587 * c.gMean + 0.114 * c.bMean;
}

void main() {
  group('card geometry', () {
    test('patches sit outside the quiet zone and clear the target disc', () {
      final m = FiducialMarker.study;
      final quietRight = m.sideMm / 2 + m.cellMm * m.quietZoneCells;
      expect(m.greyPatch.centreMm.dx - m.patchSideMmSide / 2,
          greaterThanOrEqualTo(quietRight + FiducialMarker.patchGapMm - 1e-9));

      // The disc spans y ∈ [centre − r, centre + r] above the marker; the
      // patch column spans y ∈ [−9, 9]. They must not overlap.
      final discBottom = TargetDisc.centreMm().dy + TargetDisc.diameterMm / 2;
      final patchTop = m.greyPatch.centreMm.dy - m.patchSideMmSide / 2;
      expect(discBottom, lessThan(patchTop));
      // …and the patches never enter the disc horizontally either.
      expect(m.greyPatch.centreMm.dx - m.patchSideMmSide / 2,
          greaterThan(TargetDisc.diameterMm / 2));
    });

    test('grey above white, same column, 8 mm each', () {
      final m = FiducialMarker.study;
      expect(m.greyPatch.sideMm, 8.0);
      expect(m.whitePatch.sideMm, 8.0);
      expect(m.greyPatch.centreMm.dx, m.whitePatch.centreMm.dx);
      expect(m.greyPatch.centreMm.dy, lessThan(m.whitePatch.centreMm.dy));
      expect(m.greyPatch.reflectance, 0.18);
      expect(m.whitePatch.reflectance, 0.90);
    });
  });

  group('sRGB transfer', () {
    test('round-trips', () {
      for (final v in [0.0, 12.0, 118.0, 200.0, 255.0]) {
        expect(linearToSrgb(srgbToLinear(v)), closeTo(v, 0.01));
      }
    });

    test('18% grey encodes near 118, as printed references do', () {
      expect(linearToSrgb(0.18), closeTo(118, 1.5));
    });
  });

  group('patch reading', () {
    test('reads both patches from a rendered card', () {
      final s = _render(_daylight);
      final r = samplePatches(frame: s.frame, pose: s.pose);

      expect(r.isValid, isTrue, reason: r.invalidReason);
      expect(r.greyLuma, closeTo(118, 3));
      expect(r.whiteLuma, closeTo(linearToSrgb(0.9), 3));
      for (final c in r.greyLinear) {
        expect(c, closeTo(0.18, 0.01));
      }
    });

    test('a frame without a colour plane yields no calibration, with reason',
        () {
      final s = _render(_daylight);
      final bare = LumaFrame(
        luma: s.frame.luma,
        width: s.frame.width,
        height: s.frame.height,
        capturedAt: s.frame.capturedAt,
        scaleToFull: 1,
        zoom: 1,
      );
      final r = samplePatches(frame: bare, pose: s.pose);

      expect(r.isValid, isFalse);
      expect(r.invalidReason, 'no colour plane');
      expect(ColorCalibration.fromReading(r), isNull);
    });

    test('a clipped white patch is rejected, not used', () {
      final s = _render(const _Illuminant('blown', 1.3, 1.3, 1.3));
      final r = samplePatches(frame: s.frame, pose: s.pose);

      expect(r.isValid, isFalse);
      expect(r.invalidReason, 'white patch clipped');
    });

    test('a patch under a shadow edge is rejected as non-uniform', () {
      final s = _render(_daylight);
      // Darken the left half of the frame hard: the grey patch straddles it.
      final grey = s.pose.project(
        FiducialMarker.study.greyPatch.centreMm.dx,
        FiducialMarker.study.greyPatch.centreMm.dy,
      )!;
      final luma = Uint8List.fromList(s.frame.luma);
      final rgb = Uint8List.fromList(s.frame.rgb!);
      for (var y = 0; y < s.frame.height; y++) {
        for (var x = 0; x < grey.dx.round(); x++) {
          final i = y * s.frame.width + x;
          luma[i] = (luma[i] * 0.4).round();
          for (var c = 0; c < 3; c++) {
            rgb[i * 3 + c] = (rgb[i * 3 + c] * 0.4).round();
          }
        }
      }
      final shadowed = LumaFrame(
        luma: luma,
        width: s.frame.width,
        height: s.frame.height,
        capturedAt: s.frame.capturedAt,
        scaleToFull: 1,
        zoom: 1,
        rgb: rgb,
      );
      final r = samplePatches(frame: shadowed, pose: s.pose);

      expect(r.isValid, isFalse);
      expect(r.invalidReason, 'grey patch not uniform');
    });
  });

  group('calibration — the acceptance', () {
    test('the grey patch reads 18% under every illuminant by construction',
        () {
      for (final light in [_daylight, _tungsten, _fluorescent, _dim]) {
        final s = _render(light);
        final cal = ColorCalibration.fromReading(
          samplePatches(frame: s.frame, pose: s.pose),
        )!;
        expect(cal.reflectanceOf(cal.greyLuma), closeTo(0.18, 0.18 * 0.05),
            reason: light.name);
      }
    });

    test('the same skin reads the same reflectance (±5%) under tungsten, '
        'fluorescent, daylight and dim light', () {
      final readings = <String, double>{};
      for (final light in [_daylight, _tungsten, _fluorescent, _dim]) {
        final s = _render(light);
        final cal = ColorCalibration.fromReading(
          samplePatches(frame: s.frame, pose: s.pose),
        )!;
        readings[light.name] = cal.reflectanceOf(_skinLumaUnder(light));
      }

      final values = readings.values.toList();
      final mean = values.reduce((a, b) => a + b) / values.length;
      for (final e in readings.entries) {
        expect(e.value, closeTo(mean, mean * 0.05),
            reason: '${e.key}: $readings');
      }
      // And it is a reflectance, not a brightness: the raw luma varied by
      // far more than that across these lights.
      final rawLumas = [_daylight, _tungsten, _fluorescent, _dim]
          .map(_skinLumaUnder)
          .toList();
      final rawSpread =
          (rawLumas.reduce(math.max) - rawLumas.reduce(math.min)) /
              rawLumas.reduce(math.max);
      expect(rawSpread, greaterThan(0.2));
    });

    test('white balance: a tungsten cast fails raw and passes corrected',
        () {
      final s = _render(_tungsten);
      final cal = ColorCalibration.fromReading(
        samplePatches(frame: s.frame, pose: s.pose),
      )!;
      final raw = _skinCastUnder(_tungsten);
      final corrected = cal.correct(raw);
      final reference = _skinCastUnder(_daylight);

      expect(raw.isNeutral, isFalse, reason: 'tungsten shifts the skin red');
      expect(corrected.isNeutral, isTrue);
      expect(corrected.rMean, closeTo(reference.rMean, 3));
      expect(corrected.gMean, closeTo(reference.gMean, 3));
      expect(corrected.bMean, closeTo(reference.bMean, 3));
    });

    test('white balance is invariant to intensity', () {
      final bright = ColorCalibration.fromReading(samplePatches(
        frame: _render(_daylight).frame,
        pose: _render(_daylight).pose,
      ))!;
      final dim = ColorCalibration.fromReading(samplePatches(
        frame: _render(_dim).frame,
        pose: _render(_dim).pose,
      ))!;
      for (var c = 0; c < 3; c++) {
        expect(bright.gains[c], closeTo(1.0, 0.02));
        expect(dim.gains[c], closeTo(1.0, 0.02));
      }
    });

    test('the tracker pipeline: detection → pose → patches → calibration',
        () {
      // End to end on the rendered card: the detector finds the code, the
      // pose places the patches, and the reading is valid.
      final s = _render(_fluorescent);
      final d = detectMarker(s.frame)!;
      final pose = estimatePose(
        corners: d.corners,
        intrinsics: s.pose.intrinsics,
        detectedAt: s.frame.capturedAt,
        detectionMs: d.elapsedMs,
      )!;
      final r = samplePatches(frame: s.frame, pose: pose);

      expect(r.isValid, isTrue, reason: r.invalidReason);
      final cal = ColorCalibration.fromReading(r)!;
      expect(cal.gains[1] / cal.gains[0], closeTo(0.92 / 1.12, 0.03),
          reason: 'gains invert the fluorescent green');
    });
  });
}

extension on FiducialMarker {
  double get patchSideMmSide => FiducialMarker.patchSideMm;
}
