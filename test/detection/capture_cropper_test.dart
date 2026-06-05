import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:skeen/features/detection/domain/capture_crop_config.dart';
import 'package:skeen/features/detection/infrastructure/capture_cropper.dart';

/// Encodes a solid-color [w]×[h] JPEG so we can assert crop geometry on the
/// decoded output.
Uint8List _jpeg(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(120, 90, 70));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  const cropper = ImageCaptureCropper();

  test('centeredFraction crops a centered square of ratio × shorter side',
      () async {
    // Skip unless the experiment is in its default configuration, so the
    // numeric expectations stay valid if someone flips the flags.
    if (!kGuideCropEnabled ||
        kGuideCropStrategy != CropStrategy.centeredFraction) {
      markTestSkipped('crop disabled or non-default strategy');
      return;
    }

    // Portrait 100×200. Shorter side = 100 → side = round(100 * ratio).
    final bytes = _jpeg(100, 200);

    final outcome =
        await cropper.crop(bytes, previewSize: const Size(400, 800));
    expect(outcome.applied, isTrue);

    final expectedSide = (100 * kGuideCropRatio).round();
    final decoded = img.decodeImage(outcome.bytes)!;
    expect(decoded.width, expectedSide);
    expect(decoded.height, expectedSide);

    // Per-axis fractions used to remap the centroid back to full frame.
    expect(outcome.fracX, closeTo(expectedSide / 100, 1e-9));
    expect(outcome.fracY, closeTo(expectedSide / 200, 1e-9));
  });

  test('centroid remap: centered crop keeps a centered lesion centered', () {
    // The controller remaps with full = 0.5 + (cropNorm - 0.5) * frac.
    double remap(double cropNorm, double frac) =>
        (0.5 + (cropNorm - 0.5) * frac).clamp(0.0, 1.0);

    // A lesion dead-center in the crop is dead-center in the full frame.
    expect(remap(0.5, 0.55), closeTo(0.5, 1e-9));

    // A lesion at the crop's right edge maps inward by half the crop span.
    // frac=0.5 → crop spans the central 50%, so cropNorm 1.0 → 0.75 full.
    expect(remap(1.0, 0.5), closeTo(0.75, 1e-9));
    expect(remap(0.0, 0.5), closeTo(0.25, 1e-9));
  });
}
