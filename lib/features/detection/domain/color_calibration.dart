import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'roi_frame_metrics.dart';

/// sRGB transfer functions. The camera stream is gamma-encoded; ratios of
/// reflectance only hold in linear light, so every calibration step
/// linearises first and re-encodes at the end.
double srgbToLinear(double encoded) {
  final c = (encoded / 255.0).clamp(0.0, 1.0);
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double linearToSrgb(double linear) {
  final c = linear.clamp(0.0, 1.0);
  final v = c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
  return (v * 255.0).clamp(0.0, 255.0);
}

/// Rec. 709 luma of a linear RGB triple.
double linearLuma(List<double> rgb) =>
    0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];

/// What the camera saw on the marker's two reference patches.
///
/// Sampled on the same frame the pose came from, so the reading and the
/// pose describe one instant. Invalid readings say why: the reason is
/// recorded, and the calibration simply does not exist for that frame.
@immutable
class PatchReading {
  const PatchReading({
    required this.greyLinear,
    required this.whiteLinear,
    required this.greyLuma,
    required this.whiteLuma,
    this.invalidReason,
  });

  const PatchReading.invalid(String reason)
      : greyLinear = const [0, 0, 0],
        whiteLinear = const [0, 0, 0],
        greyLuma = 0,
        whiteLuma = 0,
        invalidReason = reason;

  /// Mean linear RGB (0–1) over the grey patch.
  final List<double> greyLinear;

  /// Mean linear RGB (0–1) over the white patch.
  final List<double> whiteLinear;

  /// Mean encoded luma (0–255) of each patch, for telemetry and sanity.
  final double greyLuma;
  final double whiteLuma;

  final String? invalidReason;

  bool get isValid => invalidReason == null;

  /// A patch whose samples spread more than this (encoded luma std-dev) is
  /// not a flat reference: a shadow edge, a finger, a specular highlight.
  static const double maxPatchStdDev = 12.0;

  /// The white patch must not clip, or the reference is meaningless.
  static const double maxWhiteLuma = 250.0;

  /// The grey patch must carry signal above the sensor's noise floor.
  static const double minGreyLuma = 15.0;
}

/// Ground-truth colour and luma calibration from the marker's patches.
///
/// Before this, the colour gate could only check that the ROI's channels
/// were *relatively* balanced, and `skinReferenceLuma` was a relative
/// number that depended on exposure. With an 18% grey patch in the frame:
///
///  • **White balance** has a reference: per-channel gains that make the
///    grey patch grey, applied to the ROI's measured colour before the cast
///    check. A tungsten or fluorescent cast is now corrected against a
///    known neutral, not just flagged.
///  • **Luma has a physical anchor**: any encoded luma can be expressed as
///    reflectance relative to the 18% patch. The skin reference stops being
///    "brightness under whatever light was on" and becomes an estimate of
///    the skin's reflectance — the quantity the equity analysis actually
///    wants to stratify by, comparable across sessions and lighting.
///
/// Only ever built from a valid [PatchReading]. No patches ⇒ no
/// calibration ⇒ the relative checks stay in force and telemetry records
/// `color_calibrated: false`. Never an estimate.
@immutable
class ColorCalibration {
  const ColorCalibration({
    required this.gains,
    required this.greyLumaLinear,
    required this.greyLuma,
    required this.whiteLuma,
  });

  /// Per-channel multipliers in linear light that neutralise the grey
  /// patch (r, g, b).
  final List<double> gains;

  /// Linear luma of the grey patch as seen — the anchor for reflectance.
  final double greyLumaLinear;

  /// Encoded luma of each patch, for telemetry.
  final double greyLuma;
  final double whiteLuma;

  /// Nominal reflectance of the reference patches on the printed card.
  static const double greyReflectance = 0.18;
  static const double whiteReflectance = 0.90;

  static ColorCalibration? fromReading(PatchReading r) {
    if (!r.isValid) return null;
    final g = r.greyLinear;
    if (g.any((v) => v <= 0)) return null;
    final mean = (g[0] + g[1] + g[2]) / 3.0;
    final gains = [mean / g[0], mean / g[1], mean / g[2]];
    final lumaLinear = linearLuma(g);
    if (lumaLinear <= 0 || !gains.every((v) => v.isFinite)) return null;
    return ColorCalibration(
      gains: gains,
      greyLumaLinear: lumaLinear,
      greyLuma: r.greyLuma,
      whiteLuma: r.whiteLuma,
    );
  }

  /// The ROI's measured colour with the white-balance gains applied, in
  /// linear light, re-encoded. Its `relativeDeviation` is then a cast
  /// against ground truth.
  ColorCast correct(ColorCast measured) {
    final lin = [
      srgbToLinear(measured.rMean) * gains[0],
      srgbToLinear(measured.gMean) * gains[1],
      srgbToLinear(measured.bMean) * gains[2],
    ];
    return ColorCast(
      rMean: linearToSrgb(lin[0]),
      gMean: linearToSrgb(lin[1]),
      bMean: linearToSrgb(lin[2]),
    );
  }

  /// Reflectance implied by an encoded luma, relative to the 18% patch.
  double reflectanceOf(double encodedLuma) =>
      srgbToLinear(encodedLuma) / greyLumaLinear * greyReflectance;

  Map<String, dynamic> toJson() => {
        'wb_gain_r': gains[0],
        'wb_gain_g': gains[1],
        'wb_gain_b': gains[2],
        'gray_patch_luma': greyLuma,
        'white_patch_luma': whiteLuma,
      };

  @override
  String toString() => 'ColorCalibration(gains '
      '${gains.map((g) => g.toStringAsFixed(3)).join('/')}, '
      'grey ${greyLuma.toStringAsFixed(1)}, white ${whiteLuma.toStringAsFixed(1)})';
}
