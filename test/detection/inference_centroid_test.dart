import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:skeen/features/detection/infrastructure/tflite_inference_service.dart';

/// WP-0 — end-to-end check that the popup anchor produced by the inference
/// preprocessing step is tone-invariant.
///
/// This runs the real [preprocessCapture] on encoded JPEGs, exactly as the
/// isolate does on device, so it covers JPEG decode, the `image` package's
/// luminance, the ROI remap and the segmenter together.
///
/// Fixtures are parameterized by *reflectance ratio*, never by absolute
/// luma, matching the equity suite for the readiness gate.
const int kLightSkin = 200;
const int kMediumSkin = 120;
const int kDarkSkin = 55;

/// Square capture, as the guide-box crop produces: skin field with a
/// lesion disc of the given reflectance ratio at a known position.
Uint8List _capture({
  required int skin,
  double lesionRatio = 1.0,
  double lesionDiameter = 0,
  double centreX = 0.5,
  double centreY = 0.5,
  int side = 320,
}) {
  final image = img.Image(width: side, height: side);
  final cx = centreX * side;
  final cy = centreY * side;
  final r = lesionDiameter * side / 2;
  final lesion = (skin * lesionRatio).round().clamp(0, 255);

  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final v = (r > 0 && dx * dx + dy * dy <= r * r) ? lesion : skin;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  // Quality 100 keeps ring artefacts from the codec below the relative
  // contrast floor; the on-device crop is encoded at 92 and still clears it.
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

void main() {
  test('the popup anchor lands on the lesion at every skin tone', () {
    final found = <int, PreprocessResult>{};
    for (final skin in [kLightSkin, kMediumSkin, kDarkSkin]) {
      found[skin] = preprocessCapture(_capture(
        skin: skin,
        lesionRatio: 0.6,
        lesionDiameter: 0.3,
        centreX: 0.62,
        centreY: 0.40,
      ));
    }

    for (final entry in found.entries) {
      final c = entry.value.centroid;
      expect(c, isNotNull, reason: 'skin ${entry.key} lost the centroid');
      expect(c!.dx, closeTo(0.62, 0.03), reason: 'skin ${entry.key}');
      expect(c.dy, closeTo(0.40, 0.03), reason: 'skin ${entry.key}');
    }

    final xs = found.values.map((r) => r.centroid!.dx).toList();
    final ys = found.values.map((r) => r.centroid!.dy).toList();
    expect(xs.reduce(math.max) - xs.reduce(math.min), lessThan(0.02),
        reason: 'anchor must not depend on the base tone');
    expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(0.02));
  });

  test('THE REGRESSION: a faint lesion on dark skin keeps its anchor', () {
    // Ratio 0.85 on skin 55 is an absolute gap of ~8 levels — under the old
    // 10-level guard, so the old estimator returned null and the popup fell
    // back to the viewport centre for exactly these participants.
    final dark = preprocessCapture(_capture(
      skin: kDarkSkin,
      lesionRatio: 0.85,
      lesionDiameter: 0.4,
      centreX: 0.45,
      centreY: 0.55,
    ));
    final light = preprocessCapture(_capture(
      skin: kLightSkin,
      lesionRatio: 0.85,
      lesionDiameter: 0.4,
      centreX: 0.45,
      centreY: 0.55,
    ));

    expect(dark.centroid, isNotNull);
    expect(light.centroid, isNotNull);
    expect(dark.centroid!.dx, closeTo(light.centroid!.dx, 0.02));
    expect(dark.centroid!.dy, closeTo(light.centroid!.dy, 0.02));
  });

  test('a hypopigmented lesion on dark skin is anchored too', () {
    final result = preprocessCapture(_capture(
      skin: kDarkSkin,
      lesionRatio: 1.6,
      lesionDiameter: 0.3,
      centreX: 0.58,
      centreY: 0.58,
    ));

    expect(result.centroid, isNotNull);
    expect(result.centroid!.dx, closeTo(0.58, 0.03));
    expect(result.centroid!.dy, closeTo(0.58, 0.03));
  });

  test('uniform skin yields no centroid — the popup falls back explicitly',
      () {
    for (final skin in [kLightSkin, kMediumSkin, kDarkSkin]) {
      final result = preprocessCapture(_capture(skin: skin));

      expect(result.centroid, isNull, reason: 'skin $skin');
    }
  });

  test('the tensor path is untouched: 224² float32 with raw 0–255 values', () {
    final result = preprocessCapture(_capture(skin: kMediumSkin));

    expect(result.inputMax, greaterThan(1.5),
        reason: 'no accidental normalization');
    expect(result.inputMin, greaterThanOrEqualTo(0));
    expect(result.inputMax, lessThanOrEqualTo(255));
  });
}
