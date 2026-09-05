import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';
import 'package:skeen/features/detection/domain/capture_scale.dart';
import 'package:skeen/features/detection/domain/roi_frame_metrics.dart';
import 'package:skeen/features/detection/domain/roi_metrics_calculator.dart';

/// Equity tests for the lesion segmentation.
///
/// The estimator this replaced thresholded on absolute darkness and required
/// an absolute 10-level contrast. Because reflectance is multiplicative, that
/// guard is roughly four times stricter on Fitzpatrick V–VI than on I–II: on
/// dark skin the blob failed to segment, `fill` came back unknown, and the
/// fail-closed rule kept the shutter locked forever. Participants with dark
/// skin could not complete the guided arm at all.
///
/// The contract these tests pin: **the same lesion/skin reflectance ratio
/// must produce the same answer at every base skin tone.**
const _bounds = RoiBounds(left: 0, top: 0, width: 240, height: 240);

/// Synthetic dermatology frame.
///
/// Everything is expressed as a *ratio* of the base skin luma, because that
/// is how real reflectance works: a lesion reflecting 60% of what the
/// surrounding skin reflects looks like `skin * 0.6` under any illumination
/// and on any skin tone.
LumaSampler _frame({
  required int skin,
  double lesionRatio = 1.0,
  double lesionDiameter = 0,
  double lesionCentreX = 0.5,
  double lesionCentreY = 0.5,
  double hairRatio = 0.45,
  double hairWidthFraction = 0,
  double hairCentreX = 0.5,
  double Function(double nx)? illumination,
}) {
  final cx = _bounds.left + lesionCentreX * _bounds.width;
  final cy = _bounds.top + lesionCentreY * _bounds.height;
  final lesionRadius = lesionDiameter * _bounds.width / 2;
  final hairHalfWidth = hairWidthFraction * _bounds.width / 2;
  final hairX = _bounds.left + hairCentreX * _bounds.width;

  return (x, y) {
    var value = skin.toDouble();

    if (lesionRadius > 0) {
      final dx = x - cx;
      final dy = y - cy;
      if (dx * dx + dy * dy <= lesionRadius * lesionRadius) {
        value = skin * lesionRatio;
      }
    }

    // Hair runs the full height of the ROI: long, thin, and — when centred —
    // perfectly placed to fool a centroid-based filter, which is exactly why
    // the shape filter has to be the thing that rejects it.
    if (hairHalfWidth > 0 && (x - hairX).abs() <= hairHalfWidth) {
      value = skin * hairRatio;
    }

    if (illumination != null) {
      final nx = (x - _bounds.left) / _bounds.width;
      value *= illumination(nx);
    }

    return value.round().clamp(0, 255);
  };
}

RoiFrameMetrics _measure(LumaSampler luma) =>
    computeRoiMetrics(bounds: _bounds, luma: luma);

/// The three tones used throughout, chosen to span the range the study will
/// actually see. They are reflectance levels, not Fitzpatrick numbers — the
/// point is that the estimator never learns which one it is looking at.
const int kLightSkin = 200;
const int kMediumSkin = 120;
const int kDarkSkin = 55;

void main() {
  group('invariance to base skin tone', () {
    test('a pigmented lesion is measured identically on light, medium and '
        'dark skin', () {
      final results = <int, RoiFrameMetrics>{};
      for (final skin in [kLightSkin, kMediumSkin, kDarkSkin]) {
        results[skin] = _measure(_frame(
          skin: skin,
          lesionRatio: 0.6,
          lesionDiameter: 0.5,
        ));
      }

      for (final entry in results.entries) {
        expect(entry.value.hasLesionEstimate, isTrue,
            reason: 'skin ${entry.key} produced no blob');
        expect(entry.value.lesionFillFraction, closeTo(0.5, 0.05),
            reason: 'skin ${entry.key}');
        expect(
          CaptureScale.fromFill(entry.value.lesionFillFraction).advice,
          ScaleAdvice.ok,
          reason: 'skin ${entry.key} must reach the same gate decision',
        );
      }

      // The measured fills must agree with each other, not merely each fall
      // inside a loose band.
      final fills = results.values.map((m) => m.lesionFillFraction).toList();
      final spread = fills.reduce(math.max) - fills.reduce(math.min);
      expect(spread, lessThan(0.02),
          reason: 'fill must not depend on the base tone');
    });

    test('the relative contrast reported is the same at every tone', () {
      for (final skin in [kLightSkin, kMediumSkin, kDarkSkin]) {
        final metrics = _measure(_frame(
          skin: skin,
          lesionRatio: 0.6,
          lesionDiameter: 0.5,
        ));

        expect(metrics.lesionRelativeContrast, closeTo(-0.4, 0.03),
            reason: 'skin $skin');
        expect(metrics.skinReferenceLuma, closeTo(skin.toDouble(), 1.0),
            reason: 'the reference must report the actual skin tone');
      }
    });

    test('THE REGRESSION: a faint lesion on dark skin that the old absolute '
        'guard would have rejected', () {
      // 15% relative contrast — faint but clinically real.
      const ratio = 0.85;

      final light = _measure(
          _frame(skin: kLightSkin, lesionRatio: ratio, lesionDiameter: 0.5));
      final dark = _measure(
          _frame(skin: kDarkSkin, lesionRatio: ratio, lesionDiameter: 0.5));

      // What the old absolute guard (>= 10 luma levels) actually saw:
      final lightAbsoluteGap = kLightSkin - (kLightSkin * ratio);
      final darkAbsoluteGap = kDarkSkin - (kDarkSkin * ratio);
      expect(lightAbsoluteGap, greaterThan(10),
          reason: 'the old guard passed on light skin');
      expect(darkAbsoluteGap, lessThan(10),
          reason: 'the old guard FAILED on dark skin — the bug being fixed');

      // The new estimator finds both, and finds them equally.
      expect(light.hasLesionEstimate, isTrue);
      expect(dark.hasLesionEstimate, isTrue);
      expect(dark.lesionFillFraction,
          closeTo(light.lesionFillFraction, 0.02));
    });

    test('a hypopigmented lesion on dark skin is found by the same path', () {
      // Light lesion on dark skin: the old "darkest pixel" estimator could
      // not represent this case at all.
      final metrics = _measure(_frame(
        skin: kDarkSkin,
        lesionRatio: 1.6,
        lesionDiameter: 0.5,
      ));

      expect(metrics.hasLesionEstimate, isTrue);
      expect(metrics.lesionFillFraction, closeTo(0.5, 0.05));
      expect(metrics.lesionRelativeContrast, greaterThan(0),
          reason: 'a lighter-than-skin lesion reports positive contrast');
    });

    test('framing advice is tone-independent across the whole band', () {
      // The same physical framing must give the same coaching on every tone,
      // or the guided arm would push participants to different distances
      // depending on their skin.
      for (final skin in [kLightSkin, kMediumSkin, kDarkSkin]) {
        final tooSmall = _measure(
            _frame(skin: skin, lesionRatio: 0.6, lesionDiameter: 0.12));
        final justRight = _measure(
            _frame(skin: skin, lesionRatio: 0.6, lesionDiameter: 0.5));
        final tooBig = _measure(
            _frame(skin: skin, lesionRatio: 0.6, lesionDiameter: 0.95));

        expect(CaptureScale.fromFill(tooSmall.lesionFillFraction).advice,
            ScaleAdvice.moveCloser,
            reason: 'skin $skin');
        expect(CaptureScale.fromFill(justRight.lesionFillFraction).advice,
            ScaleAdvice.ok,
            reason: 'skin $skin');
        expect(CaptureScale.fromFill(tooBig.lesionFillFraction).advice,
            ScaleAdvice.moveAway,
            reason: 'skin $skin');
      }
    });
  });

  group('centroid (WP-0 — anchors the AR popup)', () {
    test('recovers a known off-centre position identically at every tone', () {
      // The popup used to be anchored by a "darkest pixel + absolute guard"
      // estimator that dropped the centroid on dark skin, so the label fell
      // back to the viewport centre exactly for the participants the thesis
      // is about. Same segmenter now, same contract: identical on all tones.
      final centroids = <int, Offset>{};
      for (final skin in [kLightSkin, kMediumSkin, kDarkSkin]) {
        final metrics = _measure(_frame(
          skin: skin,
          lesionRatio: 0.6,
          lesionDiameter: 0.3,
          lesionCentreX: 0.62,
          lesionCentreY: 0.40,
        ));

        expect(metrics.lesionCentroid, isNotNull, reason: 'skin $skin');
        centroids[skin] = metrics.lesionCentroid!;
        expect(metrics.lesionCentroid!.dx, closeTo(0.62, 0.03),
            reason: 'skin $skin');
        expect(metrics.lesionCentroid!.dy, closeTo(0.40, 0.03),
            reason: 'skin $skin');
      }

      final xs = centroids.values.map((c) => c.dx).toList();
      final ys = centroids.values.map((c) => c.dy).toList();
      expect(xs.reduce(math.max) - xs.reduce(math.min), lessThan(0.02));
      expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(0.02));
    });

    test('a faint lesion on dark skin still yields a centroid', () {
      // The specific case the old estimator lost (absolute gap of 8 < 10).
      final metrics = _measure(_frame(
        skin: kDarkSkin,
        lesionRatio: 0.85,
        lesionDiameter: 0.4,
        lesionCentreX: 0.45,
        lesionCentreY: 0.55,
      ));

      expect(metrics.lesionCentroid, isNotNull);
      expect(metrics.lesionCentroid!.dx, closeTo(0.45, 0.03));
      expect(metrics.lesionCentroid!.dy, closeTo(0.55, 0.03));
    });

    test('is null when nothing was segmented — never a default centre', () {
      final metrics = _measure(_frame(skin: kMediumSkin));

      expect(metrics.lesionCentroid, isNull);
    });

    test('a hypopigmented lesion is anchored by the same path', () {
      final metrics = _measure(_frame(
        skin: kDarkSkin,
        lesionRatio: 1.6,
        lesionDiameter: 0.3,
        lesionCentreX: 0.58,
        lesionCentreY: 0.58,
      ));

      expect(metrics.lesionCentroid, isNotNull);
      expect(metrics.lesionCentroid!.dx, closeTo(0.58, 0.03));
      expect(metrics.lesionCentroid!.dy, closeTo(0.58, 0.03));
    });
  });

  group('nothing to segment', () {
    test('uniform skin reports unknown at every tone', () {
      // No lesion is not the same as a small lesion, and must never be
      // reported as one — the fail-closed rule depends on this.
      for (final skin in [kLightSkin, kMediumSkin, kDarkSkin]) {
        final metrics = _measure(_frame(skin: skin));

        expect(metrics.hasLesionEstimate, isFalse, reason: 'skin $skin');
        expect(CaptureScale.fromFill(metrics.lesionFillFraction).isAcceptable,
            isFalse);
      }
    });

    test('a black region reports unknown rather than dividing by zero', () {
      final metrics = _measure(_frame(skin: 0));

      expect(metrics.hasLesionEstimate, isFalse);
      expect(metrics.lesionFillFraction.isNaN, isFalse);
    });

    test('contrast just under the relative floor is not a lesion', () {
      for (final skin in [kLightSkin, kDarkSkin]) {
        final metrics = _measure(_frame(
          skin: skin,
          lesionRatio: 1 - (kMinRelativeContrast * 0.5),
          lesionDiameter: 0.5,
        ));

        expect(metrics.hasLesionEstimate, isFalse, reason: 'skin $skin');
      }
    });
  });

  group('hair rejection', () {
    test('a centred hair alone is not a lesion', () {
      // Centred on purpose: its centroid sits dead centre, so only the shape
      // filter can reject it.
      for (final skin in [kLightSkin, kDarkSkin]) {
        final metrics = _measure(_frame(
          skin: skin,
          hairWidthFraction: 0.02,
        ));

        expect(metrics.hasLesionEstimate, isFalse, reason: 'skin $skin');
      }
    });

    test('a hair beside a lesion does not disturb the measurement', () {
      for (final skin in [kLightSkin, kDarkSkin]) {
        final clean = _measure(
            _frame(skin: skin, lesionRatio: 0.6, lesionDiameter: 0.35));
        final withHair = _measure(_frame(
          skin: skin,
          lesionRatio: 0.6,
          lesionDiameter: 0.35,
          hairWidthFraction: 0.02,
          hairCentreX: 0.30,
        ));

        expect(withHair.hasLesionEstimate, isTrue, reason: 'skin $skin');
        expect(withHair.lesionFillFraction,
            closeTo(clean.lesionFillFraction, 0.02),
            reason: 'skin $skin — the hair must not inflate the blob');
      }
    });

    test('a thick round lesion is never mistaken for a hair', () {
      final metrics = _measure(
          _frame(skin: kDarkSkin, lesionRatio: 0.6, lesionDiameter: 0.5));

      expect(metrics.hasLesionEstimate, isTrue);
    });
  });

  group('shadow rejection', () {
    test('a smooth illumination gradient is not a lesion', () {
      // The reference is the ring median, which lands mid-gradient, so
      // neither half clears the relative threshold near the centre; and what
      // does clear it is displaced off-centre and rejected.
      for (final skin in [kLightSkin, kDarkSkin]) {
        final metrics = _measure(_frame(
          skin: skin,
          illumination: (nx) => 1.33 - 0.66 * nx,
        ));

        expect(metrics.hasLesionEstimate, isFalse, reason: 'skin $skin');
      }
    });

    test('a hard-edged shadow entering from one side is not a lesion', () {
      for (final skin in [kLightSkin, kDarkSkin]) {
        final metrics = _measure(_frame(
          skin: skin,
          illumination: (nx) => nx < 0.4 ? 0.6 : 1.0,
        ));

        expect(metrics.hasLesionEstimate, isFalse, reason: 'skin $skin');
      }
    });

    test('a lesion under a uniformly dimmer light is still measured', () {
      // A shadow covering the whole ROI scales the reference with it, so the
      // relative criterion is untouched. This is the pay-off of measuring
      // against the local skin rather than an absolute level.
      final lit = _measure(
          _frame(skin: kMediumSkin, lesionRatio: 0.6, lesionDiameter: 0.5));
      final shaded = _measure(_frame(
        skin: kMediumSkin,
        lesionRatio: 0.6,
        lesionDiameter: 0.5,
        illumination: (_) => 0.5,
      ));

      expect(shaded.hasLesionEstimate, isTrue);
      expect(shaded.lesionFillFraction,
          closeTo(lit.lesionFillFraction, 0.02));
    });
  });

  group('glare is not a lesion', () {
    test('a blown highlight is excluded from the light-lesion mask', () {
      final metrics = computeRoiMetrics(
        bounds: _bounds,
        luma: (x, y) {
          final dx = x - (_bounds.left + _bounds.width / 2);
          final dy = y - (_bounds.top + _bounds.height / 2);
          final r = 0.3 * _bounds.width / 2;
          return (dx * dx + dy * dy <= r * r) ? 255 : kMediumSkin;
        },
      );

      expect(metrics.glareFraction, greaterThan(0));
      expect(metrics.hasLesionEstimate, isFalse,
          reason: 'clipped pixels carry no lesion information');
    });
  });
}
