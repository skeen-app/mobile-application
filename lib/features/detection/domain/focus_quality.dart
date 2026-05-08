import 'package:flutter/foundation.dart';

/// Value object describing how sharp the current camera frame is, derived
/// from Laplacian variance of a sparse Y-plane subsample. Lives in the
/// domain layer so it can be composed into [CaptureReadiness] without
/// pulling camera or platform deps.
///
/// Sharpness score is a normalized 0–1 value. The threshold was empirically
/// tuned for dermatology macro photography at ~15 cm: values below 0.45
/// correlate with visible motion blur or out-of-focus frames.
@immutable
class FocusQuality {
  const FocusQuality({
    required this.sharpness,
  });

  /// Normalized sharpness score (0 = fully blurred, 1 = razor-sharp).
  final double sharpness;

  /// Minimum sharpness for a clinically usable capture.
  static const double sharpThreshold = 0.45;

  bool get isSharp => sharpness >= sharpThreshold;

  String get label {
    if (sharpness < 0.25) return 'Very blurry';
    if (sharpness < sharpThreshold) return 'Slightly blurry';
    if (sharpness < 0.7) return 'Good focus';
    return 'Excellent focus';
  }

  String get hint {
    if (isSharp) return 'Focus is locked — hold steady';
    return 'Hold the phone still and let autofocus settle';
  }

  /// Initial state shown before the first frame is sampled.
  static const FocusQuality initial = FocusQuality(sharpness: 0);
}
