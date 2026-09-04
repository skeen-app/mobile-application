import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';

/// The ROI is what makes every other metric honest: measure the wrong region
/// and the numbers describe a background the user is not photographing.
void main() {
  group('fromPreviewGeometry', () {
    test('derives the fraction from the cover scale, not a constant', () {
      // Portrait widget 350×500 over a 720×1280 display-oriented frame.
      // cover scale = max(350/720, 500/1280) = 0.4861 (width-driven).
      // 192.5 logical px box ÷ 0.4861 = 396 frame px over a 720 short side.
      final roi = CaptureRoi.fromPreviewGeometry(
        widgetSize: const Size(350, 500),
        frameSize: const Size(720, 1280),
        guideBoxSide: 192.5,
      );

      expect(roi.sideFraction, closeTo(0.55, 0.001));
    });

    test('tracks the frame aspect — a different sensor moves the fraction',
        () {
      // Same widget and same box, but a 4:3 frame instead of 16:9. The cover
      // scale is now height-driven, so the box covers a different share of
      // the frame. A hard-coded 0.55 would have been wrong here.
      final roi = CaptureRoi.fromPreviewGeometry(
        widgetSize: const Size(350, 500),
        frameSize: const Size(960, 1280),
        guideBoxSide: 192.5,
      );

      // cover = max(350/960, 500/1280) = 0.3906 → 492.8 px over 960 = 0.513
      expect(roi.sideFraction, closeTo(0.513, 0.002));
      expect(roi.sideFraction, isNot(closeTo(0.55, 0.01)));
    });

    test('clamps a box larger than the frame to the whole short side', () {
      final roi = CaptureRoi.fromPreviewGeometry(
        widgetSize: const Size(350, 500),
        frameSize: const Size(720, 1280),
        guideBoxSide: 5000,
      );

      expect(roi.sideFraction, 1.0);
    });

    test('never returns a degenerate ROI for a degenerate input', () {
      for (final bad in [
        (const Size(0, 500), const Size(720, 1280), 200.0),
        (const Size(350, 500), const Size(0, 0), 200.0),
        (const Size(350, 500), const Size(720, 1280), 0.0),
        (const Size(350, 500), const Size(720, 1280), -10.0),
      ]) {
        final roi = CaptureRoi.fromPreviewGeometry(
          widgetSize: bad.$1,
          frameSize: bad.$2,
          guideBoxSide: bad.$3,
        );
        expect(roi, CaptureRoi.full, reason: 'input $bad');
      }
    });

    test('holds a floor so the sample count stays viable', () {
      final roi = CaptureRoi.fromPreviewGeometry(
        widgetSize: const Size(350, 500),
        frameSize: const Size(720, 1280),
        guideBoxSide: 0.01,
      );

      expect(roi.sideFraction, CaptureRoi.minSideFraction);
    });
  });

  group('boundsIn', () {
    test('centres the square on the frame', () {
      const roi = CaptureRoi(sideFraction: 0.5);
      final bounds = roi.boundsIn(640, 480);

      // Short side 480 → side 240, centred.
      expect(bounds.width, 240);
      expect(bounds.height, 240);
      expect(bounds.left, 200);
      expect(bounds.top, 120);
      expect(bounds.right, 440);
      expect(bounds.bottom, 360);
    });

    test('is rotation invariant — the sensor buffer is landscape', () {
      // The same ROI applied to the portrait and landscape framings of one
      // sensor must describe the same physical square, which is why the
      // fraction is expressed over the short side.
      const roi = CaptureRoi(sideFraction: 0.5);
      final landscape = roi.boundsIn(640, 480);
      final portrait = roi.boundsIn(480, 640);

      expect(landscape.width, portrait.width);
      expect(landscape.height, portrait.height);
      expect(landscape.left, portrait.top);
      expect(landscape.top, portrait.left);
    });

    test('full ROI spans the whole short side', () {
      final bounds = CaptureRoi.full.boundsIn(640, 480);

      expect(bounds.width, 480);
      expect(bounds.height, 480);
      expect(bounds.top, 0);
      expect(bounds.left, 80);
    });

    test('never produces an empty region on a tiny frame', () {
      const roi = CaptureRoi(sideFraction: 0.05);
      final bounds = roi.boundsIn(4, 4);

      expect(bounds.width, greaterThanOrEqualTo(1));
      expect(bounds.height, greaterThanOrEqualTo(1));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.top, greaterThanOrEqualTo(0));
    });
  });

  test('displayFrameSize swaps the sensor landscape reading', () {
    expect(
      CaptureRoi.displayFrameSize(const Size(1280, 720)),
      const Size(720, 1280),
    );
  });
}
