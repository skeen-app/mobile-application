import 'package:flutter/foundation.dart';

import 'capture_quality.dart';
import 'capture_roi.dart';
import 'capture_scale.dart';
import 'capture_stability.dart';
import 'capture_standard.dart';
import 'color_calibration.dart';
import 'device_eligibility.dart';
import 'roi_frame_metrics.dart';
import 'skin_plane_pose.dart';

/// Which arm of the paired study produced a capture.
enum CaptureCondition {
  /// Camera with no guidance, no gate and no auto-shutter — the comparator
  /// for the native-camera arm.
  control,

  /// Full guidance: ROI metrics, blocking gate, auto-capture.
  guided,
}

extension CaptureConditionX on CaptureCondition {
  String get slug => switch (this) {
        CaptureCondition.control => 'control',
        CaptureCondition.guided => 'guided',
      };

  bool get showsGuidance => this == CaptureCondition.guided;
}

/// What fired the shutter.
enum CaptureTrigger {
  /// The user tapped it.
  manual,

  /// The gate held green long enough for the auto-shutter to fire. This is
  /// the mechanism the study expects to remove finger-tremor blur, so it is
  /// recorded per capture rather than inferred from the condition.
  automatic,
}

extension CaptureTriggerX on CaptureTrigger {
  String get slug =>
      this == CaptureTrigger.manual ? 'manual' : 'automatic';
}

/// How the pipeline resolved after the shutter fired.
enum CaptureOutcome { saved, rejectedNotSkin, failed }

extension CaptureOutcomeX on CaptureOutcome {
  String get slug => switch (this) {
        CaptureOutcome.saved => 'saved',
        CaptureOutcome.rejectedNotSkin => 'rejected_not_skin',
        CaptureOutcome.failed => 'failed',
      };
}

/// One row of experimental data: the full readiness vector at the instant the
/// shutter fired, plus the arm, the participant and how the capture resolved.
///
/// This exists so thresholds stop being arguments. Every constant in
/// [CaptureReadiness] was chosen from reasoning about optics and hand tremor;
/// with these rows the team can correlate each metric against the
/// dermatologists' quality judgements and re-derive the cut-offs from data.
///
/// It is written to a **sidecar** store, never into `LesionAnalysis`: the
/// clinical record and the experimental instrumentation have different
/// lifetimes, different consent and different retention.
@immutable
class CaptureTelemetryRecord {
  const CaptureTelemetryRecord({
    required this.id,
    required this.participantId,
    required this.condition,
    required this.trigger,
    required this.outcome,
    required this.capturedAt,
    required this.metrics,
    required this.roiSideFraction,
    required this.sharpnessNormalized,
    required this.sharpnessObservedMax,
    required this.sharpnessCalibrating,
    required this.stability,
    required this.scale,
    required this.lightingPassed,
    required this.focusPassed,
    required this.glarePassed,
    required this.colorPassed,
    required this.stabilityPassed,
    required this.scalePassed,
    required this.wasReady,
    this.analysisId,
    this.markerDetected = false,
    this.markerType,
    this.pxPerMm,
    this.pxPerMmMarker,
    this.pxPerMmTarget,
    this.scaleRatio,
    this.tiltDeg,
    this.tiltGlobalDeg,
    this.centreOffset,
    this.poseAgeMs,
    this.detectMs,
    this.gateMarker = false,
    this.gateTilt = false,
    this.gateCentre = false,
    this.colorCalibrated = false,
    this.colorCalibration,
    this.skinReferenceReflectance,
  });

  final String id;
  final String participantId;
  final CaptureCondition condition;
  final CaptureTrigger trigger;
  final CaptureOutcome outcome;
  final DateTime capturedAt;

  /// Raw ROI measurements at the shutter instant.
  final RoiFrameMetrics metrics;

  /// The ROI these metrics were measured over, so an analyst can tell how
  /// much of the frame each number describes.
  final double roiSideFraction;

  final double sharpnessNormalized;
  final double sharpnessObservedMax;
  final bool sharpnessCalibrating;

  final CaptureStability stability;
  final CaptureScale scale;

  /// Per-signal gate states. Kept as explicit booleans rather than recomputed
  /// at analysis time, so a later threshold change cannot silently rewrite
  /// what the app actually did to the participant.
  final bool lightingPassed;
  final bool focusPassed;
  final bool glarePassed;
  final bool colorPassed;
  final bool stabilityPassed;
  final bool scalePassed;
  final bool wasReady;

  /// Links back to the saved scan. Null when the capture was rejected or
  /// failed — those rows are kept deliberately: a guidance arm that produces
  /// fewer rejections is itself a result.
  final String? analysisId;

  // ── Spatial registration (WP-5) — recorded in BOTH arms ──────────────
  //
  // The card is present in the control arm too (blinding), and the pose
  // tracker runs there as well, so these describe the control captures
  // just the same. That is what makes the continuous secondary outcomes —
  // px/mm variance, tilt distribution — comparable across arms.

  /// A valid, non-stale pose existed at the shutter instant.
  final bool markerDetected;
  final MarkerType? markerType;

  /// Scale at the target disc (what the crop has), stream px per mm.
  final double? pxPerMm;

  /// Scale at the marker centre (the WP-1 validation quantity).
  final double? pxPerMmMarker;

  /// The target for this device's crop.
  final double? pxPerMmTarget;
  final double? scaleRatio;

  /// Local tilt at the disc — the gated quantity.
  final double? tiltDeg;

  /// Normal vs. optical axis.
  final double? tiltGlobalDeg;

  /// Lesion-to-disc-centre distance in disc radii.
  final double? centreOffset;

  final int? poseAgeMs;
  final int? detectMs;
  final bool gateMarker;
  final bool gateTilt;
  final bool gateCentre;

  final bool colorCalibrated;
  final ColorCalibration? colorCalibration;
  final double? skinReferenceReflectance;

  /// Builds a record from a readiness snapshot, so call sites cannot forget
  /// a field or let the stored vector drift from what the gate evaluated.
  factory CaptureTelemetryRecord.fromSnapshot({
    required String id,
    required String participantId,
    required CaptureCondition condition,
    required CaptureTrigger trigger,
    required CaptureOutcome outcome,
    required CaptureReadiness readiness,
    required RoiFrameMetrics metrics,
    required CaptureRoi roi,
    required double sharpnessNormalized,
    required double sharpnessObservedMax,
    required bool sharpnessCalibrating,
    DateTime? capturedAt,
    String? analysisId,
    double? roiSidePx,
  }) {
    final at = capturedAt ?? DateTime.now();
    final pose = readiness.pose;
    final gate = readiness.poseReadiness;
    final disc = TargetDisc.centreMm();
    final cal = readiness.colorCalibration;
    return CaptureTelemetryRecord(
      id: id,
      participantId: participantId,
      condition: condition,
      trigger: trigger,
      outcome: outcome,
      capturedAt: at,
      metrics: metrics,
      roiSideFraction: roi.sideFraction,
      sharpnessNormalized: sharpnessNormalized,
      sharpnessObservedMax: sharpnessObservedMax,
      sharpnessCalibrating: sharpnessCalibrating,
      stability: readiness.stability,
      scale: readiness.scale,
      lightingPassed: readiness.lighting.canCapture,
      focusPassed: readiness.focus,
      glarePassed: readiness.glareOk,
      colorPassed: readiness.colorNeutral,
      stabilityPassed: readiness.stability.isSteady,
      // From WP-3 the scale gate is the marker's px/mm, not the fill.
      scalePassed: readiness.poseReadiness.scaleOk,
      wasReady: readiness.isReady,
      analysisId: analysisId,
      markerDetected: gate.hasPose,
      markerType: gate.hasPose ? pose?.markerType : null,
      pxPerMm: pose?.pxPerMmAt(disc.dx, disc.dy),
      pxPerMmMarker: pose?.pxPerMm,
      pxPerMmTarget: roiSidePx == null ? null : targetPxPerMm(roiSidePx),
      scaleRatio: gate.scaleRatio,
      tiltDeg: gate.localTiltDeg,
      tiltGlobalDeg: pose?.tiltDeg,
      centreOffset: gate.centreOffset,
      poseAgeMs: pose?.ageAt(at),
      detectMs: pose?.detectionMs,
      gateMarker: gate.hasPose,
      gateTilt: gate.tiltOk,
      gateCentre: gate.centredOk,
      colorCalibrated: cal != null,
      colorCalibration: cal,
      skinReferenceReflectance: readiness.skinReferenceReflectance,
    );
  }

  Map<String, dynamic> toJson() => {
        // Discriminator: the sidecar holds more than one row shape.
        'kind': 'capture',
        'id': id,
        'participant_id': participantId,
        'condition': condition.slug,
        'trigger': trigger.slug,
        'outcome': outcome.slug,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'analysis_id': analysisId,
        'roi_side_fraction': roiSideFraction,
        ...metrics.toJson(),
        'sharpness_normalized': sharpnessNormalized,
        'sharpness_observed_max': sharpnessObservedMax,
        'sharpness_calibrating': sharpnessCalibrating,
        'angular_speed': stability.isKnown ? stability.angularSpeed : null,
        'scale_advice': scale.advice.name,
        'scale_fill_fraction': scale.isKnown ? scale.fillFraction : null,
        'gate_lighting': lightingPassed,
        'gate_focus': focusPassed,
        'gate_glare': glarePassed,
        'gate_color': colorPassed,
        'gate_stability': stabilityPassed,
        'gate_scale': scalePassed,
        'gate_ready': wasReady,
        // ── Spatial registration (WP-5) ──
        'marker_detected': markerDetected,
        'marker_type': markerType?.slug,
        'px_per_mm': pxPerMm,
        'px_per_mm_marker': pxPerMmMarker,
        'px_per_mm_target': pxPerMmTarget,
        'scale_ratio': scaleRatio,
        'tilt_deg': tiltDeg,
        'tilt_global_deg': tiltGlobalDeg,
        'centre_offset': centreOffset,
        'pose_age_ms': poseAgeMs,
        'detect_ms': detectMs,
        'gate_marker': gateMarker,
        'gate_tilt': gateTilt,
        'gate_centre': gateCentre,
        'color_calibrated': colorCalibrated,
        'gray_patch_luma': colorCalibration?.greyLuma,
        'white_patch_luma': colorCalibration?.whiteLuma,
        'wb_gain_r': colorCalibration?.gains[0],
        'wb_gain_g': colorCalibration?.gains[1],
        'wb_gain_b': colorCalibration?.gains[2],
        'skin_reference_reflectance': skinReferenceReflectance,
      };
}

/// A start-of-session device capability check.
///
/// Written for **every** session, eligible or not: the eligible rows are the
/// denominator that makes the exclusion rate interpretable, and without them
/// an analyst cannot tell "no exclusions" from "the check never ran".
@immutable
class DeviceEligibilityRecord {
  const DeviceEligibilityRecord({
    required this.id,
    required this.participantId,
    required this.condition,
    required this.checkedAt,
    required this.eligibility,
  });

  final String id;
  final String participantId;
  final CaptureCondition condition;
  final DateTime checkedAt;
  final DeviceEligibility eligibility;

  Map<String, dynamic> toJson() => {
        'kind': 'eligibility',
        'id': id,
        'participant_id': participantId,
        'condition': condition.slug,
        'checked_at': checkedAt.toUtc().toIso8601String(),
        'eligible': eligibility.isEligible,
        'missing': [
          for (final requirement in eligibility.missing) requirement.slug,
        ],
      };
}
