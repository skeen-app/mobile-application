import 'package:flutter/material.dart';

import 'capture_scale.dart';
import 'capture_stability.dart';
import 'roi_frame_metrics.dart';

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
  ///
  /// The hint used to read "hold the camera ~15 cm above the lesion". No
  /// device measures that distance at macro range, so the copy now describes
  /// the framing the user can verify on screen. See [CaptureScale].
  static const CaptureQuality initial = CaptureQuality(
    level: CaptureQualityLevel.acceptable,
    label: 'Calibrating…',
    hint: 'Frame the mole inside the guide box',
    brightness: 0,
  );

  bool get canCapture =>
      level == CaptureQualityLevel.good ||
      level == CaptureQualityLevel.excellent;
}

/// Individual readiness check item for the on-screen checklist overlay.
@immutable
class ReadinessItem {
  const ReadinessItem({
    required this.label,
    required this.passed,
    required this.hint,
  });

  final String label;
  final bool passed;
  final String hint;
}

/// Composite value object over every capture-quality signal, all of them
/// measured **inside the guide box** (see [CaptureRoi]):
///   • [lighting]  — mean ROI luma bucketed by [CaptureQuality]
///   • [focus]     — Laplacian variance, normalized per-device by
///                   `SharpnessCalibrator`
///   • [glareOk]   — share of clipped (specular) pixels under the cap
///   • [colorCast] — per-channel means; a shifted white balance degrades a
///                   chromatic classifier's input
///   • [stability] — gyroscope angular speed, measured not inferred
///   • [scale]     — lesion size relative to the guide box; replaces the
///                   old distance readout, which no device could measure
///
/// [isReady] is the study's independent variable: it gates the shutter, so
/// every term in it must be a real measurement. Signals that could not be
/// measured report "unknown" and hold the gate **shut** rather than
/// defaulting to pass.
@immutable
class CaptureReadiness {
  const CaptureReadiness({
    required this.lighting,
    required this.focus,
    this.glareOk = true,
    this.colorCast = ColorCast.neutral,
    this.stability = CaptureStability.unknown,
    this.scale = const CaptureScale.unknown(),
    this.gatingSignals = true,
  });

  final CaptureQuality lighting;

  /// True when normalized sharpness clears its threshold.
  final bool focus;

  /// True when specular clipping is under [RoiFrameMetrics.maxGlareFraction].
  final bool glareOk;

  final ColorCast colorCast;
  final CaptureStability stability;
  final CaptureScale scale;

  /// False on surfaces that do not measure the full signal set (the AR
  /// screen, which has no ROI metric pipeline). Those surfaces keep the
  /// legacy two-term gate instead of being blocked by signals they never
  /// populate — and, being unmeasured, those signals are also never shown.
  final bool gatingSignals;

  bool get colorNeutral => colorCast.isNeutral;

  /// Every hard condition. Used to gate the shutter and to arm auto-capture.
  bool get isReady {
    if (!lighting.canCapture || !focus) return false;
    if (!gatingSignals) return true;
    return glareOk && colorNeutral && stability.isSteady && scale.isAcceptable;
  }

  List<ReadinessItem> get checklist => [
        ReadinessItem(
          label: 'Lighting',
          passed: lighting.canCapture,
          hint: lighting.hint,
        ),
        ReadinessItem(
          label: 'Focus',
          passed: focus,
          hint: focus
              ? 'Focus is locked — hold steady'
              : 'Hold still and let autofocus settle',
        ),
        if (gatingSignals) ...[
          ReadinessItem(
            label: 'Glare',
            passed: glareOk,
            hint: glareOk
                ? 'No glare on the skin'
                : 'Turn off the flash or tilt away from the light',
          ),
          ReadinessItem(
            label: 'Colour',
            passed: colorNeutral,
            hint: colorNeutral
                ? 'Colour looks neutral'
                : 'Move to more neutral light — daylight works best',
          ),
          ReadinessItem(
            label: 'Steady',
            passed: stability.isSteady,
            hint: stability.isSteady
                ? 'Holding steady'
                : 'Hold the phone still',
          ),
          ReadinessItem(
            label: 'Framing',
            passed: scale.isAcceptable,
            hint: switch (scale.advice) {
              ScaleAdvice.ok => 'The mole fills the box well',
              ScaleAdvice.moveCloser =>
                'Move closer until the mole fills the box',
              ScaleAdvice.moveAway => 'Move back — the mole overflows the box',
              ScaleAdvice.tooCloseToFocus =>
                'Too close to focus — move back a little',
              ScaleAdvice.unknown => 'Point the camera at the mole',
            },
          ),
        ],
      ];

  int get passedCount => checklist.where((i) => i.passed).length;

  static const CaptureReadiness initializing = CaptureReadiness(
    lighting: CaptureQuality.initial,
    focus: false,
  );
}
