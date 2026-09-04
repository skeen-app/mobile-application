import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'capture_crop_config.dart';

/// Side of the on-screen guide square, in the preview widget's logical
/// pixels, for a preview whose shorter side is [previewShortestSide].
///
/// Single source of truth: the overlay draws this box, and
/// [CaptureRoi.fromPreviewGeometry] converts the same value into the region
/// the metrics are measured over. If they drifted apart the user would be
/// coached on a region other than the one they are framing.
double resolveGuideBoxSide(double previewShortestSide) {
  if (previewShortestSide <= 0) return kGuideBoxLogicalPx;
  if (!kGuideCropEnabled) return kGuideBoxLogicalPx;
  return (previewShortestSide * kGuideCropRatio)
      .clamp(120.0, previewShortestSide);
}

/// The region of the camera frame that readiness metrics are measured over —
/// i.e. the part of the frame the user actually sees inside the on-screen
/// guide box.
///
/// Why this exists: metrics used to be computed over the **whole** frame, so
/// a textured background could read "sharp" while the lesion itself was
/// blurred, and a bright wall behind a shadowed arm could read "well lit".
/// For a study that claims the guidance improves image quality, every number
/// shown to the user has to describe the region that reaches the model.
///
/// The ROI is stored as a single [sideFraction] — the side of a centred
/// square expressed as a fraction of the frame's **shorter** side. That form
/// is deliberate: it is invariant under the 90° rotation between the camera
/// sensor's landscape buffer and the portrait display, so the same value maps
/// correctly onto the `CameraImage` planes without tracking orientation.
@immutable
class CaptureRoi {
  const CaptureRoi({required this.sideFraction});

  /// Side of the centred ROI square as a fraction (0, 1] of the frame's
  /// shorter side.
  final double sideFraction;

  /// Whole-frame ROI. Used before the first layout pass resolves the real
  /// geometry, and by surfaces that do not draw a guide box.
  static const CaptureRoi full = CaptureRoi(sideFraction: 1.0);

  /// The historical fixed fraction, for the two surfaces that genuinely
  /// cannot derive the real mapping:
  ///
  ///  • the AR screen, where ARCore owns the camera and the CPU frame's
  ///    dimensions are never reported to Dart;
  ///  • the gallery upload, where there is no preview geometry at all.
  ///
  /// Named so it is greppable and so nobody mistakes it for a derived value.
  /// The plain-camera path — the study's capture surface — never uses it.
  const CaptureRoi.unverifiedGuideFraction()
      : sideFraction = kGuideCropRatio;

  /// Smallest ROI we will measure over. Below this the sample count gets too
  /// small for the variance estimate to be stable.
  static const double minSideFraction = 0.05;

  /// Derives the ROI from the **real** preview↔frame mapping instead of a
  /// blind constant.
  ///
  /// [widgetSize] is the preview widget's box, [frameSize] the camera frame
  /// **in display orientation** (see [displayFrameSize]), and [guideBoxSide]
  /// the side of the on-screen guide square in the same logical pixels as
  /// [widgetSize].
  ///
  /// The preview renders with `BoxFit.cover`, so the frame is scaled by
  /// `max(widgetW/frameW, widgetH/frameH)` and centre-cropped. Dividing the
  /// guide box side by that scale converts it back into frame pixels; over
  /// the frame's shorter side that yields the fraction the ROI spans.
  ///
  /// Degenerate inputs (zero-sized widget or frame, non-positive box) fall
  /// back to [full] rather than producing a bogus region.
  factory CaptureRoi.fromPreviewGeometry({
    required Size widgetSize,
    required Size frameSize,
    required double guideBoxSide,
  }) {
    if (widgetSize.width <= 0 ||
        widgetSize.height <= 0 ||
        frameSize.width <= 0 ||
        frameSize.height <= 0 ||
        guideBoxSide <= 0) {
      return full;
    }

    final coverScale = math.max(
      widgetSize.width / frameSize.width,
      widgetSize.height / frameSize.height,
    );
    if (coverScale <= 0 || !coverScale.isFinite) return full;

    final sideInFramePx = guideBoxSide / coverScale;
    final fraction = sideInFramePx / frameSize.shortestSide;
    if (!fraction.isFinite) return full;

    return CaptureRoi(
      sideFraction: fraction.clamp(minSideFraction, 1.0),
    );
  }

  /// Converts the camera plugin's `previewSize` — always reported in the
  /// sensor's landscape orientation — into the portrait display orientation
  /// the preview widget lays out in. Mirrors what `_FittedPreview` does when
  /// it builds its aspect box, so both derive from one convention.
  static Size displayFrameSize(Size sensorPreviewSize) =>
      Size(sensorPreviewSize.height, sensorPreviewSize.width);

  /// Pixel bounds of the ROI inside an image of [imageWidth]×[imageHeight].
  ///
  /// Always centred and always at least 1×1 so callers can loop without
  /// guarding for an empty region.
  RoiBounds boundsIn(int imageWidth, int imageHeight) {
    final shortest = math.min(imageWidth, imageHeight);
    final side = (shortest * sideFraction).round().clamp(1, shortest);
    return RoiBounds(
      left: ((imageWidth - side) ~/ 2).clamp(0, math.max(0, imageWidth - 1)),
      top: ((imageHeight - side) ~/ 2).clamp(0, math.max(0, imageHeight - 1)),
      width: side.clamp(1, imageWidth),
      height: side.clamp(1, imageHeight),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaptureRoi && other.sideFraction == sideFraction;

  @override
  int get hashCode => sideFraction.hashCode;

  @override
  String toString() =>
      'CaptureRoi(${(sideFraction * 100).toStringAsFixed(1)}% of short side)';
}

/// Integer pixel rectangle produced by [CaptureRoi.boundsIn].
@immutable
class RoiBounds {
  const RoiBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      other is RoiBounds &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'RoiBounds($left, $top, $width×$height)';
}
