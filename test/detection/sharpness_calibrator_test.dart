import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/application/sharpness_calibrator.dart';

void main() {
  group('warm-up', () {
    test('an empty calibrator is calibrating and never sharp', () {
      final calibrator = SharpnessCalibrator();

      expect(calibrator.isCalibrating, isTrue);
      expect(calibrator.normalized, 0);
      expect(calibrator.isSharp, isFalse);
      expect(calibrator.observedMax, 0);
    });

    test('the first sample cannot score 1.0 just by being first', () {
      // Without the warm-up requirement any single reading is trivially its
      // own maximum, so the very first frame would report perfect focus and
      // the gate would open on nothing.
      final calibrator = SharpnessCalibrator(minSamples: 5);
      calibrator.add(5000);

      expect(calibrator.isCalibrating, isTrue);
      expect(calibrator.normalized, 0);
      expect(calibrator.isSharp, isFalse);
    });

    test('scores once the window has enough samples', () {
      final calibrator = SharpnessCalibrator(minSamples: 5);
      for (var i = 0; i < 5; i++) {
        calibrator.add(1000);
      }

      expect(calibrator.isCalibrating, isFalse);
      expect(calibrator.normalized, 1.0);
      expect(calibrator.isSharp, isTrue);
    });
  });

  group('the blank-wall guard', () {
    test('a flat scene never reports sharp, however consistent it is', () {
      // THE failure mode pure relative scoring cannot see: every frame has
      // variance ~2, so the ratio to the max is a flawless 1.0 for a frame
      // with no detail whatsoever.
      final calibrator = SharpnessCalibrator(minUsableVariance: 25);
      for (var i = 0; i < 50; i++) {
        calibrator.add(2);
      }

      expect(calibrator.observedMax, 2);
      expect(calibrator.isCalibrating, isTrue);
      expect(calibrator.normalized, 0);
      expect(calibrator.isSharp, isFalse);
    });

    test('all-zero input yields 0, not NaN', () {
      final calibrator = SharpnessCalibrator();
      for (var i = 0; i < 20; i++) {
        calibrator.add(0);
      }

      expect(calibrator.normalized, 0);
      expect(calibrator.normalized.isNaN, isFalse);
      expect(calibrator.isSharp, isFalse);
    });

    test('clears the floor once real detail appears', () {
      final calibrator = SharpnessCalibrator(minUsableVariance: 25);
      for (var i = 0; i < 10; i++) {
        calibrator.add(2);
      }
      expect(calibrator.isCalibrating, isTrue);

      calibrator.add(800);

      expect(calibrator.isCalibrating, isFalse);
      expect(calibrator.normalized, 1.0);
    });
  });

  group('hardware independence', () {
    test('two devices at their own best both score 1.0', () {
      // The whole point of dropping the /2000 constant: a phone peaking at
      // 400 and one peaking at 6000 must mean the same thing to the gate.
      final modest = SharpnessCalibrator();
      final flagship = SharpnessCalibrator();
      for (var i = 0; i < 10; i++) {
        modest.add(400);
        flagship.add(6000);
      }

      expect(modest.normalized, flagship.normalized);
      expect(modest.isSharp, isTrue);
      expect(flagship.isSharp, isTrue);
    });

    test('the same relative softness fails on both', () {
      final modest = SharpnessCalibrator();
      final flagship = SharpnessCalibrator();
      for (var i = 0; i < 10; i++) {
        modest.add(400);
        flagship.add(6000);
      }
      // Half of each device's own peak — below the 0.60 threshold.
      modest.add(200);
      flagship.add(3000);

      expect(modest.normalized, closeTo(0.5, 0.001));
      expect(flagship.normalized, closeTo(0.5, 0.001));
      expect(modest.isSharp, isFalse);
      expect(flagship.isSharp, isFalse);
    });
  });

  group('threshold boundary', () {
    test('exactly at the threshold counts as sharp', () {
      final calibrator = SharpnessCalibrator();
      for (var i = 0; i < 10; i++) {
        calibrator.add(1000);
      }
      calibrator.add(1000 * SharpnessCalibrator.sharpThreshold);

      expect(calibrator.normalized,
          closeTo(SharpnessCalibrator.sharpThreshold, 1e-9));
      expect(calibrator.isSharp, isTrue);
    });

    test('just under the threshold does not', () {
      final calibrator = SharpnessCalibrator();
      for (var i = 0; i < 10; i++) {
        calibrator.add(1000);
      }
      calibrator.add(1000 * (SharpnessCalibrator.sharpThreshold - 0.01));

      expect(calibrator.isSharp, isFalse);
    });
  });

  group('sliding window', () {
    test('retains at most windowSize samples', () {
      final calibrator = SharpnessCalibrator(windowSize: 10);
      for (var i = 0; i < 50; i++) {
        calibrator.add(100);
      }

      expect(calibrator.sampleCount, 10);
    });

    test('a stale peak drops out so the reference re-baselines', () {
      // Walking from a detailed forearm to a smooth cheek must not leave an
      // unreachable maximum in place, or focus can never pass again.
      final calibrator = SharpnessCalibrator(windowSize: 5, minSamples: 3);
      calibrator.add(10000);
      for (var i = 0; i < 4; i++) {
        calibrator.add(500);
      }
      expect(calibrator.observedMax, 10000);
      expect(calibrator.isSharp, isFalse);

      // One more sample pushes the 10000 out of the window.
      calibrator.add(500);

      expect(calibrator.observedMax, 500);
      expect(calibrator.normalized, 1.0);
      expect(calibrator.isSharp, isTrue);
    });
  });

  group('malformed input', () {
    test('negative and non-finite readings are treated as zero', () {
      final calibrator = SharpnessCalibrator();
      for (var i = 0; i < 10; i++) {
        calibrator.add(1000);
      }

      calibrator.add(double.nan);
      expect(calibrator.normalized, 0);

      calibrator.add(double.infinity);
      expect(calibrator.normalized, 0);
      expect(calibrator.observedMax, 1000);

      calibrator.add(-5);
      expect(calibrator.normalized, 0);
    });
  });

  test('reset drops the window', () {
    final calibrator = SharpnessCalibrator();
    for (var i = 0; i < 20; i++) {
      calibrator.add(1000);
    }
    expect(calibrator.isCalibrating, isFalse);

    calibrator.reset();

    expect(calibrator.sampleCount, 0);
    expect(calibrator.isCalibrating, isTrue);
    expect(calibrator.normalized, 0);
  });
}
