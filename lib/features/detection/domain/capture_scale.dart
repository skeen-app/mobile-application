import 'package:flutter/foundation.dart';

/// What the user should do about framing distance.
enum ScaleAdvice {
  /// No lesion blob could be segmented, so we say nothing. Never treated as
  /// "acceptable" — the gate stays closed until there is a measurement.
  unknown,

  /// The lesion is a small speck inside the guide box — move in.
  moveCloser,

  /// The lesion fills the guide box well.
  ok,

  /// The lesion overflows the guide box — its border is being clipped.
  moveAway,

  /// The frame will not come into focus at any point, which on a phone means
  /// the subject is inside the lens' minimum focus distance.
  tooCloseToFocus,
}

/// Replaces the old centimetre readout.
///
/// The app previously told the user to hold the phone "10–20 cm" away and
/// showed a distance chip, but no device in the fleet measures distance at
/// macro range: ARCore Depth bottoms out around half a metre, LiDAR around
/// 25 cm, and the plain-camera path simply hard-coded 15 cm. Showing a number
/// nobody measured is not defensible in a tool under clinical validation.
///
/// What *is* measurable from the live preview is **relative scale**: how much
/// of the guide box the lesion occupies. That is also the quantity that
/// actually matters — the classifier wants the lesion dominant in frame —
/// and it is expressed in terms the user can act on without a ruler.
@immutable
class CaptureScale {
  const CaptureScale({
    required this.fillFraction,
    required this.advice,
  });

  const CaptureScale.unknown()
      : fillFraction = -1,
        advice = ScaleAdvice.unknown;

  /// Lesion diameter as a fraction of the guide box side. Negative when
  /// unknown.
  final double fillFraction;

  final ScaleAdvice advice;

  /// Below this the lesion is too small in frame: after the guide-box crop
  /// and the resize to 224², a lesion under a quarter of the box survives as
  /// a few dozen pixels and the surrounding skin dominates the tensor.
  static const double minFillFraction = 0.25;

  /// Above this the lesion touches the guide box edge, so the crop clips its
  /// border — and the border is exactly what the asymmetry/irregularity cues
  /// live in.
  static const double maxFillFraction = 0.80;

  /// Only [ok] opens the gate. [unknown] deliberately does NOT: a missing
  /// measurement must not read as a passing one.
  bool get isAcceptable => advice == ScaleAdvice.ok;

  /// True when there is something meaningful to show the user.
  bool get isKnown => advice != ScaleAdvice.unknown;

  /// Classifies a measured fill fraction.
  ///
  /// [cannotFocus] is supplied by the evaluator when sharpness has stayed
  /// below par for long enough that the only remaining explanation is the
  /// lens minimum focus distance. It outranks the fill buckets because
  /// "move away so it can focus" is the actionable instruction in that case.
  factory CaptureScale.fromFill(
    double fillFraction, {
    bool cannotFocus = false,
  }) {
    if (fillFraction < 0) {
      // No blob. If the frame also refuses to focus we can still tell the
      // user something useful.
      return cannotFocus
          ? const CaptureScale(
              fillFraction: -1,
              advice: ScaleAdvice.tooCloseToFocus,
            )
          : const CaptureScale.unknown();
    }
    if (cannotFocus) {
      return CaptureScale(
        fillFraction: fillFraction,
        advice: ScaleAdvice.tooCloseToFocus,
      );
    }
    if (fillFraction < minFillFraction) {
      return CaptureScale(
        fillFraction: fillFraction,
        advice: ScaleAdvice.moveCloser,
      );
    }
    if (fillFraction > maxFillFraction) {
      return CaptureScale(
        fillFraction: fillFraction,
        advice: ScaleAdvice.moveAway,
      );
    }
    return CaptureScale(fillFraction: fillFraction, advice: ScaleAdvice.ok);
  }

  @override
  String toString() =>
      'CaptureScale(${(fillFraction * 100).toStringAsFixed(0)}%, $advice)';
}
