import 'package:flutter/material.dart';

/// Coarse buckets describing how usable a live camera frame is for clinical
/// inference. Drives the on-screen guidance the user sees while framing a
/// mole, and gates whether the capture button shows an "excellent" badge.
enum CaptureQualityLevel {
  poor,
  acceptable,
  good,
  excellent,
}

/// Pure value object derived from a sampled luminance reading. No camera or
/// Flutter dependencies in the scoring itself — kept inside the Detection
/// domain so it can be unit-tested without a device.
@immutable
class CaptureQuality {
  const CaptureQuality({
    required this.level,
    required this.label,
    required this.hint,
    required this.brightness,
  });

  /// Brightness is the mean of the Y plane (0–255) of the most recent frame.
  final double brightness;
  final CaptureQualityLevel level;
  final String label;
  final String hint;

  /// Maps a luminance reading to a quality bucket using thresholds tuned for
  /// dermatology smartphone photography (well-lit indoor light ~ 100–180).
  factory CaptureQuality.fromBrightness(double brightness) {
    if (brightness < 55) {
      return CaptureQuality(
        level: CaptureQualityLevel.poor,
        label: 'Low light',
        hint: 'Move to a brighter spot — natural light works best',
        brightness: brightness,
      );
    }
    if (brightness < 85) {
      return CaptureQuality(
        level: CaptureQualityLevel.acceptable,
        label: 'Dim',
        hint: 'A bit more light will improve the analysis',
        brightness: brightness,
      );
    }
    if (brightness > 225) {
      return CaptureQuality(
        level: CaptureQualityLevel.acceptable,
        label: 'Too bright',
        hint: 'Avoid direct sun or flash glare on the skin',
        brightness: brightness,
      );
    }
    if (brightness > 195) {
      return CaptureQuality(
        level: CaptureQualityLevel.good,
        label: 'Good lighting',
        hint: 'Hold steady and center the mole inside the ring',
        brightness: brightness,
      );
    }
    return CaptureQuality(
      level: CaptureQualityLevel.excellent,
      label: 'Excellent',
      hint: 'Great framing — tap the shutter when you are ready',
      brightness: brightness,
    );
  }

  /// Initial state shown before the first frame is sampled.
  static const CaptureQuality initial = CaptureQuality(
    level: CaptureQualityLevel.acceptable,
    label: 'Calibrating…',
    hint: 'Hold the camera ~15 cm above the lesion',
    brightness: 0,
  );

  bool get canCapture =>
      level == CaptureQualityLevel.good ||
      level == CaptureQualityLevel.excellent;
}
