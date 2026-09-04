import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';
import 'package:skeen/features/detection/domain/roi_frame_metrics.dart';
import 'package:skeen/features/detection/domain/roi_metrics_calculator.dart';

/// Synthetic frame: a flat background with an optional dark disc, so blob
/// geometry is known analytically rather than eyeballed.
LumaSampler _frame({
  required int background,
  int? discLuma,
  double discDiameterFraction = 0,
  required RoiBounds bounds,
  int? textureAmplitude,
  int blurRadius = 0,
}) {
  final cx = bounds.left + bounds.width / 2;
  final cy = bounds.top + bounds.height / 2;
  final radius = discDiameterFraction * bounds.width / 2;

  return (x, y) {
    if (discLuma != null && radius > 0) {
      final dx = x - cx;
      final dy = y - cy;
      if (dx * dx + dy * dy <= radius * radius) return discLuma;
    }
    if (textureAmplitude != null) {
      // Deterministic pseudo-random texture. Real detail is aperiodic: a
      // strictly periodic pattern (a checkerboard) produces a CONSTANT
      // Laplacian response, whose variance is zero by definition, so it
      // would not exercise the metric at all.
      //
      // [blurRadius] > 0 averages the texture over a neighbourhood, which is
      // what defocus does — the high-frequency content collapses.
      int noise(int px, int py) {
        final h = (px * 73856093) ^ (py * 19349663);
        return (h.abs() % (2 * textureAmplitude)) - textureAmplitude;
      }

      if (blurRadius <= 0) {
        return (background + noise(x, y)).clamp(0, 255);
      }
      var sum = 0;
      var n = 0;
      for (var dy = -blurRadius; dy <= blurRadius; dy++) {
        for (var dx = -blurRadius; dx <= blurRadius; dx++) {
          sum += noise(x + dx, y + dy);
          n++;
        }
      }
      return (background + (sum / n).round()).clamp(0, 255);
    }
    return background;
  };
}

void main() {
  const bounds = RoiBounds(left: 0, top: 0, width: 200, height: 200);

  group('guards', () {
    test('a region too small to hold a Laplacian returns empty', () {
      final metrics = computeRoiMetrics(
        bounds: const RoiBounds(left: 0, top: 0, width: 2, height: 2),
        luma: (x, y) => 120,
      );

      expect(metrics.sampleCount, 0);
      expect(metrics, RoiFrameMetrics.empty);
    });
  });

  group('luma', () {
    test('is the mean over the region', () {
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 137, bounds: bounds),
      );

      expect(metrics.luma, closeTo(137, 0.001));
      expect(metrics.sampleCount, greaterThan(100));
    });

    test('describes the ROI, not the frame around it', () {
      // Dark region inside a blazing white frame. Whole-frame sampling used
      // to report this as well lit; ROI sampling reports what the user is
      // actually photographing.
      const roi = RoiBounds(left: 400, top: 400, width: 100, height: 100);
      final metrics = computeRoiMetrics(
        bounds: roi,
        luma: (x, y) =>
            (x >= 400 && x < 500 && y >= 400 && y < 500) ? 30 : 250,
      );

      expect(metrics.luma, closeTo(30, 0.001));
    });
  });

  group('glare', () {
    test('is zero on a normally exposed region', () {
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 140, bounds: bounds),
      );

      expect(metrics.glareFraction, 0);
      expect(metrics.isGlareAcceptable, isTrue);
    });

    test('counts only pixels at or above the clipping cutoff', () {
      // Exactly at the cutoff counts; one below does not.
      final at = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: RoiFrameMetrics.glareLumaCutoff,
            bounds: bounds),
      );
      final below = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: RoiFrameMetrics.glareLumaCutoff - 1,
            bounds: bounds),
      );

      expect(at.glareFraction, 1.0);
      expect(below.glareFraction, 0.0);
    });

    test('a specular highlight over ~5% of the ROI fails the check', () {
      // A blown disc covering ~5% of the region area.
      final diameter = 2 * math.sqrt(0.05 / math.pi);
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(
          background: 140,
          discLuma: 255,
          discDiameterFraction: diameter,
          bounds: bounds,
        ),
      );

      expect(metrics.glareFraction, closeTo(0.05, 0.01));
      expect(metrics.isGlareAcceptable, isFalse);
    });

    test('a pinprick highlight stays under the cap', () {
      final diameter = 2 * math.sqrt(0.005 / math.pi);
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(
          background: 140,
          discLuma: 255,
          discDiameterFraction: diameter,
          bounds: bounds,
        ),
      );

      expect(metrics.glareFraction, lessThan(RoiFrameMetrics.maxGlareFraction));
      expect(metrics.isGlareAcceptable, isTrue);
    });
  });

  group('colour cast', () {
    test('reports neutral when no colour sampler is supplied', () {
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 140, bounds: bounds),
      );

      expect(metrics.colorCast.isNeutral, isTrue);
    });

    test('a grey region is neutral', () {
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 140, bounds: bounds),
        rgb: (x, y) => const RgbPixel(140, 140, 140),
      );

      expect(metrics.colorCast.relativeDeviation, closeTo(0, 0.001));
      expect(metrics.colorCast.isNeutral, isTrue);
      expect(metrics.colorCast.direction, isNull);
    });

    test('typical skin stays inside the tolerance', () {
      // Red-dominant but not cast: this must not be flagged, or the gate
      // would never open on human skin.
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 150, bounds: bounds),
        rgb: (x, y) => const RgbPixel(170, 150, 140),
      );

      expect(metrics.colorCast.relativeDeviation, lessThan(0.18));
      expect(metrics.colorCast.isNeutral, isTrue);
    });

    test('a tungsten cast is rejected and named warm', () {
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 150, bounds: bounds),
        rgb: (x, y) => const RgbPixel(220, 140, 90),
      );

      expect(metrics.colorCast.relativeDeviation, greaterThan(0.18));
      expect(metrics.colorCast.isNeutral, isFalse);
      expect(metrics.colorCast.direction, ColorCastDirection.warm);
    });

    test('a fluorescent green cast is rejected and named green', () {
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 150, bounds: bounds),
        rgb: (x, y) => const RgbPixel(120, 200, 120),
      );

      expect(metrics.colorCast.isNeutral, isFalse);
      expect(metrics.colorCast.direction, ColorCastDirection.green);
    });

    test('a black region reports no cast rather than dividing by zero', () {
      const cast = ColorCast(rMean: 0, gMean: 0, bMean: 0);

      expect(cast.relativeDeviation, 0);
      expect(cast.relativeDeviation.isNaN, isFalse);
      expect(cast.direction, isNull);
    });
  });

  group('sharpness (raw Laplacian variance)', () {
    test('is zero on a flat region', () {
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 140, bounds: bounds),
      );

      expect(metrics.sharpnessRaw, closeTo(0, 0.001));
    });

    test('is large on a detailed region', () {
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 140, textureAmplitude: 60, bounds: bounds),
      );

      expect(metrics.sharpnessRaw, greaterThan(1000));
    });

    test('collapses when the same scene is defocused', () {
      // The property the focus gate actually depends on: the SAME scene,
      // blurred, must score materially lower.
      final sharp = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 140, textureAmplitude: 60, bounds: bounds),
      );
      final blurred = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(
          background: 140,
          textureAmplitude: 60,
          blurRadius: 3,
          bounds: bounds,
        ),
      );

      expect(blurred.sharpnessRaw, lessThan(sharp.sharpnessRaw * 0.25));
    });

    test('a uniformly periodic pattern is a known blind spot', () {
      // Documented, not accidental: the metric is the VARIANCE of the
      // Laplacian response, so a pattern whose every pixel produces the same
      // response scores zero however crisp it looks. Real skin texture is
      // aperiodic, which is why this is acceptable — but it is worth pinning
      // so nobody "fixes" the metric by chasing this case.
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: (x, y) => ((x + y) % 2 == 0) ? 200 : 80,
      );

      expect(metrics.sharpnessRaw, closeTo(0, 0.001));
    });

    test('is never negative through floating-point cancellation', () {
      final variance = RunningVariance();
      for (var i = 0; i < 1000; i++) {
        variance.add(1e6);
      }

      expect(variance.value, greaterThanOrEqualTo(0));
    });
  });

  group('lesion fill fraction', () {
    test('recovers the diameter of a known disc', () {
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(
          background: 180,
          discLuma: 60,
          discDiameterFraction: 0.5,
          bounds: bounds,
        ),
      );

      expect(metrics.hasLesionEstimate, isTrue);
      expect(metrics.lesionFillFraction, closeTo(0.5, 0.05));
    });

    test('reports unknown on uniform skin instead of inventing a lesion', () {
      // The critical honesty case: a mean-derived threshold always finds
      // *some* darker pixels, so without a contrast guard this would report
      // a lesion in every frame.
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 150, bounds: bounds),
      );

      expect(metrics.hasLesionEstimate, isFalse);
      expect(metrics.lesionFillFraction, -1);
    });

    test('a uniformly dark region has nothing to segment', () {
      // Underexposure is not a lesion filling the box.
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(background: 20, bounds: bounds),
      );

      expect(metrics.hasLesionEstimate, isFalse);
    });

    test('a bright lesion on a dark field IS a lesion', () {
      // This expectation used to be inverted, and that inversion was part of
      // the same bias: a hypopigmented lesion — or any lesion lighter than
      // the surrounding skin — was treated as an invalid frame. Segmentation
      // is by contrast against the local skin now, in either direction.
      // See lesion_segmentation_test.dart for the tone-invariance contract.
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(
          background: 40,
          discLuma: 150,
          discDiameterFraction: 0.5,
          bounds: bounds,
        ),
      );

      expect(metrics.hasLesionEstimate, isTrue);
      expect(metrics.lesionFillFraction, closeTo(0.5, 0.05));
      expect(metrics.lesionRelativeContrast, greaterThan(0));
    });

    test('a large disc reads as overflowing the box', () {
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(
          background: 190,
          discLuma: 50,
          discDiameterFraction: 0.95,
          bounds: bounds,
        ),
      );

      expect(metrics.hasLesionEstimate, isTrue);
      expect(metrics.lesionFillFraction, greaterThan(0.80));
    });

    test('a speck reads as too small', () {
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(
          background: 190,
          discLuma: 40,
          discDiameterFraction: 0.12,
          bounds: bounds,
        ),
      );

      expect(metrics.hasLesionEstimate, isTrue);
      expect(metrics.lesionFillFraction, lessThan(0.25));
    });

    test('a lesion filling the whole box reports at most 1.0', () {
      // The peripheral ring is thin precisely so that a lesion this large
      // still leaves a majority of the ring on skin — otherwise the
      // reference would become the lesion and the user would get no
      // "move back" coaching at the moment they most need it.
      final metrics = computeRoiMetrics(
        bounds: bounds,
        luma: _frame(
          background: 200,
          discLuma: 60,
          discDiameterFraction: 1.0,
          bounds: bounds,
        ),
      );

      expect(metrics.hasLesionEstimate, isTrue);
      expect(metrics.lesionFillFraction, lessThanOrEqualTo(1.0));
      expect(metrics.lesionFillFraction, greaterThan(0.80));
    });
  });
}
