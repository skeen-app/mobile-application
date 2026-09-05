import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/application/hint_arbiter.dart';
import 'package:skeen/features/detection/domain/capture_quality.dart';
import 'package:skeen/features/detection/domain/capture_scale.dart';
import 'package:skeen/features/detection/domain/capture_stability.dart';
import 'package:skeen/features/detection/domain/pose_readiness.dart';
import 'package:skeen/features/detection/domain/roi_frame_metrics.dart';

void main() {
  group('CaptureScale', () {
    test('an unmeasured scale is not acceptable', () {
      // The central rule: no measurement must never read as a passing one.
      const scale = CaptureScale.unknown();

      expect(scale.isKnown, isFalse);
      expect(scale.isAcceptable, isFalse);
      expect(scale.advice, ScaleAdvice.unknown);
    });

    test('a negative fill stays unknown', () {
      final scale = CaptureScale.fromFill(-1);

      expect(scale.advice, ScaleAdvice.unknown);
      expect(scale.isAcceptable, isFalse);
    });

    test('buckets a measured fill', () {
      expect(CaptureScale.fromFill(0.10).advice, ScaleAdvice.moveCloser);
      expect(CaptureScale.fromFill(0.50).advice, ScaleAdvice.ok);
      expect(CaptureScale.fromFill(0.90).advice, ScaleAdvice.moveAway);
    });

    test('boundaries are inclusive of the acceptable band', () {
      expect(
        CaptureScale.fromFill(CaptureScale.minFillFraction).advice,
        ScaleAdvice.ok,
      );
      expect(
        CaptureScale.fromFill(CaptureScale.maxFillFraction).advice,
        ScaleAdvice.ok,
      );
      expect(
        CaptureScale.fromFill(CaptureScale.minFillFraction - 0.001).advice,
        ScaleAdvice.moveCloser,
      );
      expect(
        CaptureScale.fromFill(CaptureScale.maxFillFraction + 0.001).advice,
        ScaleAdvice.moveAway,
      );
    });

    test('cannotFocus outranks an otherwise fine framing', () {
      final scale = CaptureScale.fromFill(0.5, cannotFocus: true);

      expect(scale.advice, ScaleAdvice.tooCloseToFocus);
      expect(scale.isAcceptable, isFalse);
    });

    test('cannotFocus still reports even with no blob', () {
      final scale = CaptureScale.fromFill(-1, cannotFocus: true);

      expect(scale.advice, ScaleAdvice.tooCloseToFocus);
    });
  });

  group('CaptureStability', () {
    test('an unknown reading is not steady', () {
      // A device with no gyroscope must hold the gate shut, not sail through.
      expect(CaptureStability.unknown.isKnown, isFalse);
      expect(CaptureStability.unknown.isSteady, isFalse);
    });

    test('resting hand tremor is steady', () {
      const stability = CaptureStability(angularSpeed: 0.03);

      expect(stability.isSteady, isTrue);
    });

    test('exactly at the threshold is steady, just over is not', () {
      expect(
        const CaptureStability(
          angularSpeed: CaptureStability.steadyThreshold,
        ).isSteady,
        isTrue,
      );
      expect(
        const CaptureStability(
          angularSpeed: CaptureStability.steadyThreshold + 0.001,
        ).isSteady,
        isFalse,
      );
    });

    test('a deliberate sweep is not steady', () {
      const stability = CaptureStability(angularSpeed: 1.2);

      expect(stability.isSteady, isFalse);
    });
  });

  group('CaptureReadiness gate', () {
    CaptureReadiness build({
      double luma = 140,
      bool focus = true,
      bool glareOk = true,
      ColorCast cast = ColorCast.neutral,
      CaptureStability stability = const CaptureStability(angularSpeed: 0.02),
      CaptureScale? scale,
      PoseReadiness poseReadiness = const PoseReadiness(
        hasPose: true,
        scaleRatio: 1.0,
        localTiltDeg: 3,
        centreOffset: 0.1,
      ),
    }) =>
        CaptureReadiness(
          lighting: CaptureQuality.fromBrightness(luma),
          focus: focus,
          glareOk: glareOk,
          colorCast: cast,
          stability: stability,
          scale: scale ?? CaptureScale.fromFill(0.5),
          poseReadiness: poseReadiness,
        );

    test('opens only when every signal passes', () {
      expect(build().isReady, isTrue);
    });

    test('any single failing signal keeps it shut', () {
      expect(build(luma: 20).isReady, isFalse, reason: 'too dark');
      expect(build(luma: 250).isReady, isFalse, reason: 'too bright');
      expect(build(focus: false).isReady, isFalse, reason: 'soft');
      expect(build(glareOk: false).isReady, isFalse, reason: 'glare');
      expect(
        build(cast: const ColorCast(rMean: 220, gMean: 140, bMean: 90))
            .isReady,
        isFalse,
        reason: 'colour cast',
      );
      expect(
        build(stability: const CaptureStability(angularSpeed: 0.9)).isReady,
        isFalse,
        reason: 'shake',
      );
      expect(
        build(poseReadiness: PoseReadiness.absent).isReady,
        isFalse,
        reason: 'no marker pose',
      );
      expect(
        build(
          poseReadiness: const PoseReadiness(
            hasPose: true,
            scaleRatio: 1.0,
            localTiltDeg: 25,
            centreOffset: 0.1,
          ),
        ).isReady,
        isFalse,
        reason: 'tilted 25°',
      );
    });

    test('lesion size no longer gates — the standard is metric', () {
      // A 2 mm lesion at the target px/mm is a small blob in the crop, and
      // that is correct: same px/mm for every lesion, whatever its size.
      expect(build(scale: CaptureScale.fromFill(0.05)).isReady, isTrue);
    });

    test('unmeasured signals hold the gate shut', () {
      expect(
        build(stability: CaptureStability.unknown).isReady,
        isFalse,
        reason: 'no gyroscope reading yet',
      );
      expect(
        build(
          poseReadiness: const PoseReadiness(
            hasPose: true,
            scaleRatio: 1.0,
            localTiltDeg: 3,
            centreOffset: null,
          ),
        ).isReady,
        isFalse,
        reason: 'no lesion segmented yet',
      );
    });

    test('the initial state is never ready', () {
      expect(CaptureReadiness.initializing.isReady, isFalse);
    });

    test('a surface without the full vector keeps the two-term gate', () {
      // The AR screen has no ROI pipeline. It must not be blocked by signals
      // it never populates — and correspondingly must not display them.
      const partial = CaptureReadiness(
        lighting: CaptureQuality(
          level: CaptureQualityLevel.excellent,
          label: 'ok',
          hint: 'ok',
          brightness: 140,
        ),
        focus: true,
        gatingSignals: false,
      );

      expect(partial.isReady, isTrue);
      expect(partial.scale.isKnown, isFalse);
      expect(
        partial.checklist.map((i) => i.label),
        ['Lighting', 'Focus'],
        reason: 'unmeasured signals must not be shown',
      );
    });

    test('the full checklist covers every gating signal', () {
      expect(
        build().checklist.map((i) => i.label),
        [
          'Lighting', 'Focus', 'Glare', 'Colour', 'Steady',
          'Marker', 'Scale', 'Tilt', 'Centred',
        ],
      );
    });

    test('coaching order: light, card, glare, distance, level, centre, '
        'still, focus, colour', () {
      expect(build().failingKey, isNull);
      expect(build(luma: 20, poseReadiness: PoseReadiness.absent).failingKey,
          'lighting');
      expect(build(poseReadiness: PoseReadiness.absent, glareOk: false)
          .failingKey, 'marker');
      expect(build(glareOk: false).failingKey, 'glare');
      expect(
        build(
          poseReadiness: const PoseReadiness(
            hasPose: true, scaleRatio: 0.7, localTiltDeg: 30, centreOffset: 0.9,
          ),
        ).failingKey,
        'scale',
      );
      expect(
        build(
          poseReadiness: const PoseReadiness(
            hasPose: true, scaleRatio: 1.0, localTiltDeg: 30, centreOffset: 0.9,
          ),
        ).failingKey,
        'tilt',
      );
      expect(
        build(
          poseReadiness: const PoseReadiness(
            hasPose: true, scaleRatio: 1.0, localTiltDeg: 3, centreOffset: 0.9,
          ),
        ).failingKey,
        'centre',
      );
      expect(build(stability: CaptureStability.unknown).failingKey,
          'stability');
      expect(build(focus: false).failingKey, 'focus');
    });

    test('no user-facing copy promises a distance', () {
      // Nothing on this path measures centimetres. Pinned so a future edit
      // cannot quietly reintroduce a fabricated number.
      final copy = [
        for (final item in build(scale: CaptureScale.fromFill(0.05)).checklist)
          '${item.label} ${item.hint}',
        CaptureQuality.initial.hint,
      ].join(' ').toLowerCase();

      expect(copy, isNot(contains('cm')));
      expect(copy, isNot(contains('centimet')));
    });
  });

  group('HintArbiter', () {
    HintArbiter build() => HintArbiter(
          priority: const ['lighting', 'glare', 'scale', 'focus', 'ready'],
          resolvedKey: 'ready',
          initial: 'scale',
          settleMs: 1500,
        );

    test('a higher-priority problem pre-empts immediately', () {
      final arbiter = build();

      arbiter.update(failing: 'lighting', dtMs: 16);

      expect(arbiter.active, 'lighting');
    });

    test('a lower-priority problem waits out the settle window', () {
      final arbiter = build();

      arbiter.update(failing: 'focus', dtMs: 500);
      expect(arbiter.active, 'scale', reason: 'too soon to swap');

      arbiter.update(failing: 'focus', dtMs: 900);
      expect(arbiter.active, 'scale');

      arbiter.update(failing: 'focus', dtMs: 200);
      expect(arbiter.active, 'focus');
    });

    test('the all-clear also waits, so flicker never flashes ready', () {
      final arbiter = build();

      arbiter.update(failing: null, dtMs: 500);
      expect(arbiter.active, 'scale');

      // The problem comes back before the settle completes.
      arbiter.update(failing: 'scale', dtMs: 100);
      arbiter.update(failing: null, dtMs: 500);
      expect(arbiter.active, 'scale', reason: 'timer restarted');

      arbiter.update(failing: null, dtMs: 1100);
      expect(arbiter.active, 'ready');
    });

    test('a persistent problem holds the line', () {
      final arbiter = build();

      for (var i = 0; i < 100; i++) {
        arbiter.update(failing: 'scale', dtMs: 100);
      }

      expect(arbiter.active, 'scale');
      expect(arbiter.satisfiedMs, 0);
    });

    test('a stalled frame pump cannot jump the hysteresis', () {
      final arbiter = build();

      arbiter.update(failing: 'focus', dtMs: 999999);

      expect(arbiter.active, 'scale', reason: 'dt clamped to 1000ms');
    });

    test('an unregistered key never pre-empts', () {
      final arbiter = build();

      arbiter.update(failing: 'mystery', dtMs: 100);

      expect(arbiter.active, 'scale');
    });
  });
}
