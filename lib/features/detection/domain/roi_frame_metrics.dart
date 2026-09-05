import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// Mean per-channel colour of the ROI, and how far off-neutral it is.
///
/// The classifier is chromatic — the benign/malignant boundary leans on
/// pigment colour — so a frame shot under tungsten (red-shifted) or
/// fluorescent (green-shifted) light is a degraded input even when it is
/// perfectly sharp and well exposed. This measures that directly instead of
/// trusting the camera's auto white balance to have got it right.
@immutable
class ColorCast {
  const ColorCast({
    required this.rMean,
    required this.gMean,
    required this.bMean,
  });

  /// Per-channel means over the ROI, each 0–255.
  final double rMean;
  final double gMean;
  final double bMean;

  static const ColorCast neutral =
      ColorCast(rMean: 128, gMean: 128, bMean: 128);

  /// Largest single-channel departure from the average channel level, as a
  /// fraction of that average. 0 = perfectly neutral grey.
  ///
  /// Returns 0 for a black ROI: with no signal there is no cast to report,
  /// and the luma gate already rejects that frame.
  double get relativeDeviation {
    final mean = (rMean + gMean + bMean) / 3.0;
    if (mean <= 0) return 0;
    final maxDelta = math.max(
      (rMean - mean).abs(),
      math.max((gMean - mean).abs(), (bMean - mean).abs()),
    );
    return maxDelta / mean;
  }

  /// Maximum tolerated deviation. Skin under mixed daylight sits well under
  /// 0.10; a visible tungsten or fluorescent cast pushes one channel past
  /// 0.20. 0.18 rejects the casts that matter while leaving normal skin
  /// tones — which are themselves red-dominant — comfortably inside.
  static const double maxRelativeDeviation = 0.18;

  bool get isNeutral => relativeDeviation <= maxRelativeDeviation;

  /// Which way the cast leans, for the coaching copy. Null when neutral.
  ColorCastDirection? get direction {
    if (isNeutral) return null;
    final mean = (rMean + gMean + bMean) / 3.0;
    if (mean <= 0) return null;
    final dr = (rMean - mean).abs();
    final dg = (gMean - mean).abs();
    final db = (bMean - mean).abs();
    if (dr >= dg && dr >= db) {
      return rMean > mean ? ColorCastDirection.warm : ColorCastDirection.cool;
    }
    if (dg >= db) return ColorCastDirection.green;
    return bMean > mean ? ColorCastDirection.cool : ColorCastDirection.warm;
  }

  @override
  String toString() => 'ColorCast(r=${rMean.toStringAsFixed(1)}, '
      'g=${gMean.toStringAsFixed(1)}, b=${bMean.toStringAsFixed(1)}, '
      'dev=${relativeDeviation.toStringAsFixed(3)})';
}

enum ColorCastDirection { warm, cool, green }

/// One frame's worth of raw measurements, all taken **inside the ROI**.
///
/// Everything here is a measurement, never a default: a field that could not
/// be measured is reported as such (see [lesionFillFraction]) rather than
/// filled with a plausible-looking constant.
@immutable
class RoiFrameMetrics {
  const RoiFrameMetrics({
    required this.luma,
    required this.sharpnessRaw,
    required this.glareFraction,
    required this.colorCast,
    required this.lesionFillFraction,
    required this.sampleCount,
    this.skinReferenceLuma = 0,
    this.lesionRelativeContrast = 0,
    this.lesionCentroid,
    this.glareCells = const [],
    this.glareCentroid,
  });

  /// Mean luma over the ROI, 0–255.
  final double luma;

  /// Laplacian variance over the ROI. **Un-normalized** on purpose: the
  /// absolute value is hardware dependent, so the normalization happens in
  /// `SharpnessCalibrator` against what this device has actually achieved.
  final double sharpnessRaw;

  /// Share of ROI pixels at or above [glareLumaCutoff], i.e. blown-out
  /// specular highlights. 0–1.
  final double glareFraction;

  final ColorCast colorCast;

  /// Estimated lesion diameter as a fraction of the ROI side, 0–1.
  /// Negative when no blob could be segmented (uniform skin, no lesion in
  /// frame) — callers must treat that as "unknown", never as "fine".
  final double lesionFillFraction;

  /// Number of pixels actually sampled. Zero means the frame was unusable
  /// and every other field should be ignored.
  final int sampleCount;

  /// Median luma of the peripheral ring — the reference skin tone the lesion
  /// was measured against. Persisted per capture so the equity analysis can
  /// stratify by the skin tone the app actually saw, instead of relying on a
  /// self-reported Fitzpatrick type alone.
  final double skinReferenceLuma;

  /// Signed contrast of the lesion against that reference, as a fraction of
  /// it. Negative for a pigmented lesion, positive for a hypopigmented one.
  /// This is the quantity the segmentation thresholds on, so recording it
  /// makes the gate's decision auditable after the fact.
  final double lesionRelativeContrast;

  /// Centroid of the segmented lesion, normalized 0–1 **within the ROI** the
  /// metrics were measured over. Null when no blob was segmented. Produced by
  /// the same tone-invariant segmentation as [lesionFillFraction], so it
  /// carries no Fitzpatrick bias — see `roi_metrics_calculator.dart`.
  final Offset? lesionCentroid;

  /// Fraction of clipped samples per cell of a [glareGridSize]² map over the
  /// ROI, row-major. Lets the overlay shade the reflection **where it is**.
  /// Empty when the frame was unusable.
  final List<double> glareCells;

  /// Centroid of the clipped samples, ROI-normalized; null when none.
  final Offset? glareCentroid;

  /// Cells per side of [glareCells]. 8 is coarse enough to be cheap and fine
  /// enough that a highlight over the lesion is drawn on the lesion.
  static const int glareGridSize = 8;

  /// A cell whose share of clipped samples is at or above this is shaded.
  /// Well under the 2% whole-ROI cap: the map shows the reflection before it
  /// grows large enough to close the gate, which is the point of showing it.
  static const double glareCellVisible = 0.15;

  bool get hasLesionEstimate => lesionFillFraction >= 0;

  /// A pixel this bright is clipped: no detail survives in it.
  static const int glareLumaCutoff = 250;

  /// Above this share of clipped pixels the specular highlight is eating the
  /// lesion itself. 2% of the ROI is roughly a highlight you can see; below
  /// that it is usually a stray pixel or sensor noise.
  static const double maxGlareFraction = 0.02;

  bool get isGlareAcceptable => glareFraction <= maxGlareFraction;

  static const RoiFrameMetrics empty = RoiFrameMetrics(
    luma: 0,
    sharpnessRaw: 0,
    glareFraction: 0,
    colorCast: ColorCast.neutral,
    lesionFillFraction: -1,
    sampleCount: 0,
  );

  Map<String, dynamic> toJson() => {
        'luma': luma,
        'sharpness_raw': sharpnessRaw,
        'glare_fraction': glareFraction,
        'color_r': colorCast.rMean,
        'color_g': colorCast.gMean,
        'color_b': colorCast.bMean,
        'color_relative_deviation': colorCast.relativeDeviation,
        'lesion_fill_fraction': lesionFillFraction,
        'skin_reference_luma': skinReferenceLuma,
        'lesion_relative_contrast': lesionRelativeContrast,
        'lesion_centroid_x': lesionCentroid?.dx,
        'lesion_centroid_y': lesionCentroid?.dy,
        'glare_centroid_x': glareCentroid?.dx,
        'glare_centroid_y': glareCentroid?.dy,
        'sample_count': sampleCount,
      };
}
