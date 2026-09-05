import 'package:flutter/material.dart';

import 'capture_scale.dart';
import 'capture_stability.dart';
import 'color_calibration.dart';
import 'lesion_anchor.dart';
import 'pose_readiness.dart';
import 'roi_frame_metrics.dart';
import 'skin_plane_pose.dart';

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
    this.pose,
    this.anchor,
    this.metrics = RoiFrameMetrics.empty,
    this.poseReadiness = PoseReadiness.absent,
    this.colorCalibration,
  });

  final CaptureQuality lighting;

  /// True when normalized sharpness clears its threshold.
  final bool focus;

  /// True when specular clipping is under [RoiFrameMetrics.maxGlareFraction].
  final bool glareOk;

  final ColorCast colorCast;
  final CaptureStability stability;
  final CaptureScale scale;

  /// Camera pose relative to the skin plane, resolved from the fiducial
  /// marker; null when no marker is in view, the pose is stale, or the device
  /// cannot report intrinsics. Carried here from WP-1 so overlays and
  /// telemetry can consume it; it joins [isReady] in WP-3.
  final SkinPlanePose? pose;

  /// Where the lesion is on screen right now, smoothed and carried forward by
  /// the gyroscope between measurements. The reticle sits on this.
  final LesionAnchor? anchor;

  /// The marker-based gate: scale, local tilt and centring. From WP-3 this
  /// is the term that replaces the fill-based [scale] in [isReady] — the
  /// standard is metric now, the same px/mm for every lesion whatever its
  /// size. [scale] stays for the reticle and telemetry.
  final PoseReadiness poseReadiness;

  /// Ground-truth calibration from the marker's patches, when they were
  /// readable on the current pose's frame. When present, [colorCast] is the
  /// white-balanced colour and [skinReferenceReflectance] is available.
  final ColorCalibration? colorCalibration;

  bool get colorCalibrated => colorCalibration != null;

  /// The reference skin's reflectance relative to the 18% grey patch, or
  /// null without a calibration or without a segmented reference. This is
  /// the equity analysis's stratification variable: a property of the
  /// skin, not of the light that happened to be on.
  double? get skinReferenceReflectance {
    final cal = colorCalibration;
    if (cal == null || metrics.skinReferenceLuma <= 0) return null;
    return cal.reflectanceOf(metrics.skinReferenceLuma);
  }

  /// The raw ROI measurements behind this vector. The overlay reads the
  /// glare map from here to shade the reflection where it actually is.
  final RoiFrameMetrics metrics;

  /// False on surfaces that do not measure the full signal set (the AR
  /// screen, which has no ROI metric pipeline). Those surfaces keep the
  /// legacy two-term gate instead of being blocked by signals they never
  /// populate — and, being unmeasured, those signals are also never shown.
  final bool gatingSignals;

  bool get colorNeutral => colorCast.isNeutral;

  /// Every hard condition. Used to gate the shutter and to arm auto-capture.
  ///
  /// Fail-closed throughout: no marker pose, a stale one, or no segmented
  /// lesion all leave this false.
  bool get isReady {
    if (!lighting.canCapture || !focus) return false;
    if (!gatingSignals) return true;
    return glareOk &&
        colorNeutral &&
        stability.isSteady &&
        poseReadiness.isReady;
  }

  /// The highest-priority failing signal, or null when everything passes.
  ///
  /// The order is a sequence the user can follow: light on the lesion, the
  /// card in view, no reflection, the right distance, level, centred, hold
  /// still, let it focus, then colour. Shared by the overlay's arbiter and
  /// the tests so the coaching order is defined once.
  String? get failingKey {
    if (!lighting.canCapture) return 'lighting';
    if (gatingSignals) {
      if (!poseReadiness.hasPose) return 'marker';
      if (!glareOk) return 'glare';
      if (!poseReadiness.scaleOk) return 'scale';
      if (!poseReadiness.tiltOk) return 'tilt';
      if (!poseReadiness.centredOk) return 'centre';
      if (!stability.isSteady) return 'stability';
    }
    if (!focus) return 'focus';
    if (gatingSignals && !colorNeutral) return 'color';
    return null;
  }

  /// Coaching keys most to least urgent; `ready` last.
  static const List<String> coachingPriority = [
    'lighting',
    'marker',
    'glare',
    'scale',
    'tilt',
    'centre',
    'stability',
    'focus',
    'color',
    'ready',
  ];

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
            label: 'Marker',
            passed: poseReadiness.hasPose,
            hint: poseReadiness.hasPose
                ? 'Marker in view'
                : 'Show the marker card next to the mole',
          ),
          ReadinessItem(
            label: 'Scale',
            passed: poseReadiness.scaleOk,
            hint: switch (poseReadiness.advice) {
              PoseAdvice.moveCloser => 'Move closer until the disc fills the box',
              PoseAdvice.moveAway => 'Move back until the disc fits the box',
              _ => 'Scale is on target',
            },
          ),
          ReadinessItem(
            label: 'Tilt',
            passed: poseReadiness.tiltOk,
            hint: poseReadiness.tiltOk
                ? 'Looking straight down at the disc'
                : 'Level the phone until the ring closes',
          ),
          ReadinessItem(
            label: 'Centred',
            passed: poseReadiness.centredOk,
            hint: switch (poseReadiness.advice) {
              PoseAdvice.findLesion => 'Bring the mole inside the disc',
              PoseAdvice.centreLesion => 'Centre the mole in the disc',
              _ => 'Mole centred in the disc',
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
