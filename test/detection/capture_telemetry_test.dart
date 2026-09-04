import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/domain/capture_quality.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';
import 'package:skeen/features/detection/domain/capture_scale.dart';
import 'package:skeen/features/detection/domain/capture_stability.dart';
import 'package:skeen/features/detection/domain/capture_telemetry.dart';
import 'package:skeen/features/detection/domain/roi_frame_metrics.dart';

/// The telemetry row is the study's raw data. If a field is missing or drifts
/// from what the gate actually evaluated, the thresholds can never be
/// re-derived from the dermatologists' judgements.
void main() {
  final metrics = RoiFrameMetrics(
    luma: 143.5,
    sharpnessRaw: 3200,
    glareFraction: 0.004,
    colorCast: const ColorCast(rMean: 172, gMean: 150, bMean: 141),
    lesionFillFraction: 0.48,
    skinReferenceLuma: 151.0,
    lesionRelativeContrast: -0.38,
    sampleCount: 2304,
  );

  final readiness = CaptureReadiness(
    lighting: CaptureQuality.fromBrightness(143.5),
    focus: true,
    glareOk: true,
    colorCast: metrics.colorCast,
    stability: const CaptureStability(angularSpeed: 0.04),
    scale: CaptureScale.fromFill(0.48),
  );

  CaptureTelemetryRecord build({
    CaptureCondition condition = CaptureCondition.guided,
    CaptureTrigger trigger = CaptureTrigger.automatic,
    CaptureOutcome outcome = CaptureOutcome.saved,
    CaptureReadiness? withReadiness,
    String? analysisId = 'scan-1',
  }) =>
      CaptureTelemetryRecord.fromSnapshot(
        id: 'rec-1',
        participantId: 'P014',
        condition: condition,
        trigger: trigger,
        outcome: outcome,
        readiness: withReadiness ?? readiness,
        metrics: metrics,
        roi: const CaptureRoi(sideFraction: 0.55),
        sharpnessNormalized: 0.82,
        sharpnessObservedMax: 3900,
        sharpnessCalibrating: false,
        capturedAt: DateTime.utc(2026, 3, 3, 12, 30),
        analysisId: analysisId,
      );

  test('rows are self-describing so one file can hold both shapes', () {
    expect(build().toJson()['kind'], 'capture');
  });

  test('carries the equity-audit fields', () {
    // The skin tone the app measured and the contrast it segmented on. Needed
    // to check, after the fact, that the gate behaved equivalently across
    // Fitzpatrick types instead of taking it on trust.
    final json = build().toJson();

    expect(json['skin_reference_luma'], isNotNull);
    expect(json['lesion_relative_contrast'], isNotNull);
  });

  test('carries the full readiness vector', () {
    final json = build().toJson();

    for (final key in [
      'luma',
      'sharpness_raw',
      'sharpness_normalized',
      'sharpness_observed_max',
      'sharpness_calibrating',
      'glare_fraction',
      'color_r',
      'color_g',
      'color_b',
      'color_relative_deviation',
      'angular_speed',
      'scale_advice',
      'scale_fill_fraction',
      'lesion_fill_fraction',
      'roi_side_fraction',
      'sample_count',
    ]) {
      expect(json.containsKey(key), isTrue, reason: 'missing $key');
      expect(json[key], isNotNull, reason: '$key must carry a value');
    }
  });

  test('records the arm, the participant and how the shutter fired', () {
    final guided = build().toJson();
    expect(guided['condition'], 'guided');
    expect(guided['trigger'], 'automatic');
    expect(guided['participant_id'], 'P014');

    final control = build(
      condition: CaptureCondition.control,
      trigger: CaptureTrigger.manual,
    ).toJson();
    expect(control['condition'], 'control');
    expect(control['trigger'], 'manual');
  });

  test('mirrors the per-signal gate states the app actually applied', () {
    // Stored as booleans rather than recomputed later, so a future threshold
    // change cannot rewrite the history of what the user was shown.
    final json = build().toJson();

    expect(json['gate_lighting'], isTrue);
    expect(json['gate_focus'], isTrue);
    expect(json['gate_glare'], isTrue);
    expect(json['gate_color'], isTrue);
    expect(json['gate_stability'], isTrue);
    expect(json['gate_scale'], isTrue);
    expect(json['gate_ready'], isTrue);
  });

  test('a blocked vector is recorded as blocked', () {
    final blocked = CaptureReadiness(
      lighting: CaptureQuality.fromBrightness(20),
      focus: false,
      glareOk: false,
      colorCast: const ColorCast(rMean: 220, gMean: 140, bMean: 90),
      stability: const CaptureStability(angularSpeed: 0.9),
      scale: CaptureScale.fromFill(0.05),
    );

    final json = build(withReadiness: blocked).toJson();

    expect(json['gate_ready'], isFalse);
    expect(json['gate_lighting'], isFalse);
    expect(json['gate_glare'], isFalse);
    expect(json['gate_stability'], isFalse);
    expect(json['gate_scale'], isFalse);
    expect(json['scale_advice'], 'moveCloser');
  });

  test('keeps rejected and failed attempts, which never reach a scan', () {
    // A guidance arm that produces fewer unusable frames is itself the
    // result being measured, so these rows must exist.
    final rejected = build(
      outcome: CaptureOutcome.rejectedNotSkin,
      analysisId: null,
    ).toJson();

    expect(rejected['outcome'], 'rejected_not_skin');
    expect(rejected['analysis_id'], isNull);

    final failed =
        build(outcome: CaptureOutcome.failed, analysisId: null).toJson();
    expect(failed['outcome'], 'failed');
  });

  test('an unmeasured signal serializes as null, never as a plausible value',
      () {
    final unmeasured = CaptureReadiness(
      lighting: CaptureQuality.fromBrightness(143.5),
      focus: true,
      stability: CaptureStability.unknown,
      scale: const CaptureScale.unknown(),
    );

    final json = build(withReadiness: unmeasured).toJson();

    expect(json['angular_speed'], isNull);
    expect(json['scale_fill_fraction'], isNull);
    expect(json['scale_advice'], 'unknown');
    expect(json['gate_ready'], isFalse);
  });

  test('timestamps are UTC ISO-8601 so rows from any device collate', () {
    final json = build().toJson();

    expect(json['captured_at'], '2026-03-03T12:30:00.000Z');
  });
}
