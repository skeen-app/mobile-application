import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:skeen/features/detection/domain/capture_crop_config.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';
import 'package:skeen/features/detection/infrastructure/capture_cropper.dart';

/// Encodes a solid-color [w]×[h] JPEG so we can assert crop geometry on the
/// decoded output.
Uint8List _jpeg(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(120, 90, 70));
  return Uint8List.fromList(img.encodeJpg(image));
}

/// One device geometry: a laid-out preview widget over a sensor of a given
/// aspect, plus the captured image the pipeline receives.
class _Geometry {
  const _Geometry({
    required this.name,
    required this.widget,
    required this.sensorPreview,
    required this.captureW,
    required this.captureH,
  });

  final String name;

  /// Preview widget box, logical pixels.
  final Size widget;

  /// `previewSize` as the camera plugin reports it — sensor landscape.
  final Size sensorPreview;

  /// Dimensions of the standardized capture that reaches the cropper.
  final int captureW;
  final int captureH;
}

void main() {
  const cropper = ImageCaptureCropper();

  // Three aspect ratios that real handsets actually ship. The old blind
  // constant was tuned for one of them.
  const geometries = [
    _Geometry(
      name: '4:3',
      widget: Size(350, 500),
      sensorPreview: Size(1280, 960),
      captureW: 960,
      captureH: 1280,
    ),
    _Geometry(
      name: '16:9',
      widget: Size(350, 500),
      sensorPreview: Size(1280, 720),
      captureW: 720,
      captureH: 1280,
    ),
    _Geometry(
      name: '20:9',
      widget: Size(350, 500),
      sensorPreview: Size(1600, 720),
      captureW: 720,
      captureH: 1600,
    ),
  ];

  group('one derivation feeds the box, the metrics and the crop', () {
    for (final g in geometries) {
      test('${g.name}: the cropped region is the region the guide box '
          'covers', () async {
        if (!kGuideCropEnabled) {
          markTestSkipped('cropping disabled');
          return;
        }

        // 1. The box the overlay draws.
        final boxSide = resolveGuideBoxSide(g.widget.shortestSide);

        // 2. The ROI the readiness metrics are measured over — derived from
        //    the real preview↔frame mapping.
        final roi = CaptureRoi.fromPreviewGeometry(
          widgetSize: g.widget,
          frameSize: CaptureRoi.displayFrameSize(g.sensorPreview),
          guideBoxSide: boxSide,
        );

        // 3. The region the cropper actually cuts for the models.
        final outcome = await cropper.crop(
          _jpeg(g.captureW, g.captureH),
          roi: roi,
        );
        expect(outcome.applied, isTrue);
        final cropped = img.decodeImage(outcome.bytes)!;

        // Independently recompute what the on-screen box maps to, from the
        // geometry alone — so this asserts the mapping, not just that three
        // call sites share a variable.
        final frame = CaptureRoi.displayFrameSize(g.sensorPreview);
        final coverScale = math.max(
          g.widget.width / frame.width,
          g.widget.height / frame.height,
        );
        final expectedFraction = (boxSide / coverScale) / frame.shortestSide;
        final captureShortSide = math.min(g.captureW, g.captureH);

        expect(
          cropped.width / captureShortSide,
          closeTo(expectedFraction, 0.01),
          reason: '${g.name}: crop must span the box\'s share of the frame',
        );
        expect(cropped.width, cropped.height,
            reason: 'the analysed region stays square');
      });
    }

    test('the crop tracks the aspect ratio instead of a constant', () {
      // The regression this closes: a single hard-coded fraction cannot be
      // correct for every sensor. Derived from the real mapping, the fraction
      // genuinely differs between these devices — so a shared constant was
      // wrong for at least two of the three.
      final fractions = <String, double>{};
      for (final g in geometries) {
        final roi = CaptureRoi.fromPreviewGeometry(
          widgetSize: g.widget,
          frameSize: CaptureRoi.displayFrameSize(g.sensorPreview),
          guideBoxSide: resolveGuideBoxSide(g.widget.shortestSide),
        );
        fractions[g.name] = roi.sideFraction;
      }

      final spread = fractions.values.reduce(math.max) -
          fractions.values.reduce(math.min);
      expect(spread, greaterThan(0.02),
          reason: 'these geometries genuinely disagree: $fractions');

      // And at least one of them is materially off the old constant.
      final worst = fractions.values
          .map((f) => (f - kGuideCropRatio).abs())
          .reduce(math.max);
      expect(worst, greaterThan(0.02),
          reason: 'the old blind $kGuideCropRatio misses by $worst');
    });
  });

  group('crop mechanics', () {
    test('emits a centred square and reports the fractions it spans',
        () async {
      final outcome = await cropper.crop(
        _jpeg(100, 200),
        roi: const CaptureRoi(sideFraction: 0.5),
      );

      final decoded = img.decodeImage(outcome.bytes)!;
      // Short side 100 → side 50.
      expect(decoded.width, 50);
      expect(decoded.height, 50);
      expect(outcome.fracX, closeTo(0.5, 0.001));
      expect(outcome.fracY, closeTo(0.25, 0.001));
      expect(outcome.applied, isTrue);
    });

    test('a full ROI spans the whole short side', () async {
      final outcome = await cropper.crop(
        _jpeg(120, 200),
        roi: CaptureRoi.full,
      );

      final decoded = img.decodeImage(outcome.bytes)!;
      expect(decoded.width, 120);
      expect(decoded.height, 120);
    });

    test('undecodable bytes fail open, untouched', () async {
      final garbage = Uint8List.fromList(List<int>.filled(32, 9));

      final outcome = await cropper.crop(
        garbage,
        roi: const CaptureRoi(sideFraction: 0.5),
      );

      expect(outcome.applied, isFalse);
      // Equal, not identical: the bytes travel back across the isolate port.
      expect(outcome.bytes, equals(garbage));
      expect(outcome.fracX, 1.0);
      expect(outcome.fracY, 1.0);
    });

    test('the crop bounds match what the metrics pipeline measured',
        () async {
      // Same CaptureRoi, same boundsIn — the property that makes "what you
      // frame" equal "what gets measured" equal "what gets analysed".
      const roi = CaptureRoi(sideFraction: 0.42);
      final bounds = roi.boundsIn(720, 1280);

      final outcome = await cropper.crop(_jpeg(720, 1280), roi: roi);
      final decoded = img.decodeImage(outcome.bytes)!;

      expect(decoded.width, bounds.width);
      expect(decoded.height, bounds.height);
    });
  });
}
