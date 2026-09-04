import 'dart:math' as math;

import 'capture_roi.dart';
import 'roi_frame_metrics.dart';

/// Reads the luma (0–255) of one pixel of the source frame.
typedef LumaSampler = int Function(int x, int y);

/// Reads the colour of one pixel of the source frame.
typedef RgbSampler = RgbPixel Function(int x, int y);

class RgbPixel {
  const RgbPixel(this.r, this.g, this.b);
  final int r;
  final int g;
  final int b;
}

/// Computes every readiness metric over a rectangular region, given plain
/// pixel accessors.
///
/// Deliberately free of any camera or platform type: the pixel-format work
/// (YUV420 on Android, BGRA on iOS) stays in the camera service, and this —
/// the part with the actual arithmetic and the edge cases — is testable with
/// synthetic frames.
///
/// All metrics come from a single grid pass over the same pixels, so the
/// whole vector describes one instant. That matters for the gate: the
/// previous split streams could pair a luma reading from one frame with a
/// sharpness reading from another.
RoiFrameMetrics computeRoiMetrics({
  required RoiBounds bounds,
  required LumaSampler luma,
  RgbSampler? rgb,
  int targetSamples = 48,
}) {
  if (bounds.width < 3 || bounds.height < 3) return RoiFrameMetrics.empty;

  final stepX = math.max(1, bounds.width ~/ targetSamples);
  final stepY = math.max(1, bounds.height ~/ targetSamples);

  // Inset by one pixel so the Laplacian's 4-neighbourhood never reads
  // outside the region.
  final firstY = bounds.top + 1;
  final lastY = bounds.bottom - 1;
  final firstX = bounds.left + 1;
  final lastX = bounds.right - 1;
  if (lastX <= firstX || lastY <= firstY) return RoiFrameMetrics.empty;

  final gridW = ((lastX - firstX) + stepX - 1) ~/ stepX;
  final gridH = ((lastY - firstY) + stepY - 1) ~/ stepY;
  if (gridW < 3 || gridH < 3) return RoiFrameMetrics.empty;

  var sumLuma = 0;
  var glareCount = 0;
  var sumR = 0, sumG = 0, sumB = 0;
  final grid = List<int>.filled(gridW * gridH, 0);
  final laplacian = RunningVariance();

  for (var gy = 0; gy < gridH; gy++) {
    final y = firstY + gy * stepY;
    for (var gx = 0; gx < gridW; gx++) {
      final x = firstX + gx * stepX;
      final centre = luma(x, y);
      grid[gy * gridW + gx] = centre;
      sumLuma += centre;
      if (centre >= RoiFrameMetrics.glareLumaCutoff) glareCount++;

      // 4-neighbour Laplacian on *adjacent* pixels. The grid decimates where
      // we measure, never what we measure: sampling the neighbours at the
      // grid step instead would low-pass the very high-frequency content
      // this operator exists to detect.
      final lap = (4 * centre -
              luma(x, y - 1) -
              luma(x, y + 1) -
              luma(x - 1, y) -
              luma(x + 1, y))
          .abs()
          .toDouble();
      laplacian.add(lap);

      if (rgb != null) {
        final pixel = rgb(x, y);
        sumR += pixel.r;
        sumG += pixel.g;
        sumB += pixel.b;
      }
    }
  }

  final count = grid.length;
  final meanLuma = sumLuma / count;

  final colorCast = rgb == null
      ? ColorCast.neutral
      : ColorCast(
          rMean: sumR / count,
          gMean: sumG / count,
          bMean: sumB / count,
        );

  final blob = _findLesionBlob(grid: grid, gridW: gridW, gridH: gridH);

  return RoiFrameMetrics(
    luma: meanLuma,
    sharpnessRaw: laplacian.value,
    glareFraction: glareCount / count,
    colorCast: colorCast,
    lesionFillFraction: blob.fillFraction,
    skinReferenceLuma: blob.skinReference,
    lesionRelativeContrast: blob.relativeContrast,
    sampleCount: count,
  );
}

// ──────────────────────────────────────────────────────────────────────
// Lesion segmentation
// ──────────────────────────────────────────────────────────────────────

/// Minimum **relative** deviation from the reference skin tone for a sample
/// to be considered part of a lesion.
///
/// This constant replaces an absolute one (10 luma levels), and the change is
/// the whole point of this pass. Reflectance is multiplicative — a lesion
/// reflecting 85% of what the surrounding skin reflects produces an absolute
/// gap of 30 levels on skin at luma 200 but only 8 levels on skin at luma 55.
/// An absolute guard is therefore roughly four times stricter on Fitzpatrick
/// V–VI than on I–II: the blob failed to segment, `fill` came back unknown,
/// and the fail-closed rule kept the shutter locked. Participants with dark
/// skin simply could not complete the guided arm, which is both an equity
/// failure and a source of differential dropout that would bias the study.
///
/// 0.10 sits well above sensor noise (1–2% of signal at normal exposure) on
/// every skin tone, and below the contrast of even faint or amelanotic
/// lesions (typically 15% and up; pigmented naevi are commonly 30–60%).
const double kMinRelativeContrast = 0.10;

/// Thickness of the peripheral ring used to estimate the reference skin tone,
/// as a fraction of the ROI side.
///
/// Thin on purpose. The ring has to stay *outside* the lesion even when the
/// lesion fills the whole guide box: at 0.08 a disc spanning the entire box
/// still leaves ~59% of the ring on surrounding skin, so the median — which
/// only needs a majority — reports skin rather than lesion. A fatter ring
/// would be quieter but would start reading the lesion as the reference, and
/// then a too-close user would get no "move back" coaching at all.
const double kAnnulusBandFraction = 0.08;

/// Smallest component, in grid cells, that counts as a lesion rather than
/// sampling noise.
const int kMinBlobCells = 4;

/// A component must be reasonably centred to be the lesion the user is
/// framing. Expressed as the maximum offset of its centroid from the ROI
/// centre, normalized to the ROI side.
///
/// This is what rejects a shadow cast across part of the frame: a shadow
/// enters from one side, so its centroid is displaced, while a lesion — even
/// one overflowing the box — stays centred by the framing UX.
const double kBlobMaxCentroidOffset = 0.25;

/// Aspect ratio above which a component is a candidate hair.
const double kHairMinElongation = 3.0;

/// Mean width, in grid cells, below which an elongated component is a hair
/// rather than a long lesion. Hairs are curvilinear and a couple of pixels
/// wide; a lesion of the same length is far thicker.
const double kHairMaxThicknessCells = 2.5;

/// Above this share of the ROI the "blob" is the whole region — not a lesion
/// sitting in a field of skin.
const double kMaxBlobAreaFraction = 0.95;

/// Outcome of the segmentation pass.
class _BlobResult {
  const _BlobResult({
    required this.fillFraction,
    required this.skinReference,
    required this.relativeContrast,
  });

  const _BlobResult.none(this.skinReference)
      : fillFraction = -1,
        relativeContrast = 0;

  final double fillFraction;
  final double skinReference;
  final double relativeContrast;
}

/// Segments the lesion by **local contrast against the surrounding skin**,
/// not by absolute darkness.
///
/// Steps:
///  1. Estimate the reference skin tone as the median of a thin peripheral
///     ring. Median, not mean, so a few hairs or a lesion edge intruding into
///     the ring cannot move it.
///  2. Build two candidate masks — samples darker than the reference by more
///     than [kMinRelativeContrast], and samples lighter by the same relative
///     margin. Two masks rather than a polarity decision so that a
///     hypopigmented or amelanotic lesion on dark skin is found by exactly
///     the same mechanism as a pigmented one on light skin.
///  3. Label connected components, discard hairs and specks, and keep only
///     components centred in the ROI.
///  4. Report the largest survivor as an equivalent-circle diameter.
///
/// Because both the reference and the threshold scale with the skin tone, the
/// entire criterion is invariant to the base tone: the same lesion/skin
/// reflectance ratio yields the same answer on Fitzpatrick I and VI.
_BlobResult _findLesionBlob({
  required List<int> grid,
  required int gridW,
  required int gridH,
}) {
  final band = math.max(1, (math.min(gridW, gridH) * kAnnulusBandFraction).round());
  if (gridW <= 2 * band + 1 || gridH <= 2 * band + 1) {
    return const _BlobResult.none(0);
  }

  // ── 1. Reference skin tone from the peripheral ring ────────────────
  final ring = <int>[];
  for (var gy = 0; gy < gridH; gy++) {
    final onHorizontalBand = gy < band || gy >= gridH - band;
    for (var gx = 0; gx < gridW; gx++) {
      final onVerticalBand = gx < band || gx >= gridW - band;
      if (onHorizontalBand || onVerticalBand) {
        ring.add(grid[gy * gridW + gx]);
      }
    }
  }
  if (ring.isEmpty) return const _BlobResult.none(0);

  final reference = _median(ring);
  // A pitch-black region carries no reference to compare against; relative
  // contrast is undefined and we say so rather than guessing.
  if (reference <= 0) return const _BlobResult.none(0);

  // ── 2. Relative-contrast masks, both polarities ────────────────────
  final darkCut = reference * (1 - kMinRelativeContrast);
  final lightCut = reference * (1 + kMinRelativeContrast);

  final mask = List<int>.filled(grid.length, 0); // 0 none, 1 dark, 2 light
  for (var i = 0; i < grid.length; i++) {
    final value = grid[i];
    // Clipped samples carry no information — they are glare, which has its
    // own gate — so they never contribute to a lesion.
    if (value >= RoiFrameMetrics.glareLumaCutoff) continue;
    if (value <= darkCut) {
      mask[i] = 1;
    } else if (value >= lightCut) {
      mask[i] = 2;
    }
  }

  // ── 3 & 4. Components, filtering, selection ────────────────────────
  _Component? best;
  for (final polarity in const [1, 2]) {
    for (final component in _components(mask, gridW, gridH, polarity)) {
      if (!_isPlausibleLesion(component, gridW, gridH)) continue;
      if (best == null || component.area > best.area) best = component;
    }
  }

  if (best == null) return _BlobResult.none(reference);

  final areaFraction = best.area / grid.length;
  if (areaFraction > kMaxBlobAreaFraction) return _BlobResult.none(reference);

  final blobValues = [for (final i in best.cells) grid[i]];
  final blobMedian = _median(blobValues);

  // area = πd²/4 over a unit square ⇒ d = 2√(area/π)
  final diameter = 2.0 * math.sqrt(areaFraction / math.pi);

  return _BlobResult(
    fillFraction: diameter.clamp(0.0, 1.0),
    skinReference: reference,
    relativeContrast: (blobMedian - reference) / reference,
  );
}

/// Rejects components that are not the lesion the user is framing: sampling
/// specks, hairs, and anything off-centre (a shadow entering from one side).
bool _isPlausibleLesion(_Component c, int gridW, int gridH) {
  if (c.area < kMinBlobCells) return false;

  final boxW = c.maxGx - c.minGx + 1;
  final boxH = c.maxGy - c.minGy + 1;
  final major = math.max(boxW, boxH).toDouble();
  final minor = math.max(1, math.min(boxW, boxH)).toDouble();
  final elongation = major / minor;
  final thickness = c.area / major;

  // Hair: long, thin and curvilinear. Both conditions are required so that a
  // genuinely elongated lesion — which is thick along its whole length — is
  // not discarded with it.
  if (elongation >= kHairMinElongation &&
      thickness <= kHairMaxThicknessCells) {
    return false;
  }

  final centroidX = c.sumGx / c.area / gridW;
  final centroidY = c.sumGy / c.area / gridH;
  if ((centroidX - 0.5).abs() > kBlobMaxCentroidOffset) return false;
  if ((centroidY - 0.5).abs() > kBlobMaxCentroidOffset) return false;

  return true;
}

class _Component {
  _Component(int gx, int gy)
      : minGx = gx,
        maxGx = gx,
        minGy = gy,
        maxGy = gy;

  int area = 0;
  int minGx;
  int maxGx;
  int minGy;
  int maxGy;
  int sumGx = 0;
  int sumGy = 0;
  final List<int> cells = [];

  void add(int gx, int gy, int index) {
    area++;
    sumGx += gx;
    sumGy += gy;
    cells.add(index);
    if (gx < minGx) minGx = gx;
    if (gx > maxGx) maxGx = gx;
    if (gy < minGy) minGy = gy;
    if (gy > maxGy) maxGy = gy;
  }
}

/// 4-connected labelling over the grid, for one mask polarity. The grid is at
/// most a few thousand cells, so an explicit-stack flood fill is well inside
/// the per-frame budget at the ~3 Hz sampling cadence.
List<_Component> _components(List<int> mask, int gridW, int gridH, int label) {
  final seen = List<bool>.filled(mask.length, false);
  final found = <_Component>[];
  final stack = <int>[];

  for (var start = 0; start < mask.length; start++) {
    if (seen[start] || mask[start] != label) continue;

    final component = _Component(start % gridW, start ~/ gridW);
    seen[start] = true;
    stack.add(start);

    while (stack.isNotEmpty) {
      final index = stack.removeLast();
      final gx = index % gridW;
      final gy = index ~/ gridW;
      component.add(gx, gy, index);

      if (gx > 0) _push(stack, seen, mask, label, index - 1);
      if (gx < gridW - 1) _push(stack, seen, mask, label, index + 1);
      if (gy > 0) _push(stack, seen, mask, label, index - gridW);
      if (gy < gridH - 1) _push(stack, seen, mask, label, index + gridW);
    }

    found.add(component);
  }

  return found;
}

void _push(
  List<int> stack,
  List<bool> seen,
  List<int> mask,
  int label,
  int index,
) {
  if (seen[index] || mask[index] != label) return;
  seen[index] = true;
  stack.add(index);
}

double _median(List<int> values) {
  final sorted = List<int>.from(values)..sort();
  return sorted[sorted.length ~/ 2].toDouble();
}

/// Population variance of a stream of values, accumulated without retaining
/// them. Used for the Laplacian variance that backs the focus signal.
class RunningVariance {
  double _sum = 0;
  double _sumSq = 0;
  int _n = 0;

  void add(double v) {
    _sum += v;
    _sumSq += v * v;
    _n++;
  }

  int get count => _n;

  double get value {
    if (_n == 0) return 0;
    final mean = _sum / _n;
    final variance = (_sumSq / _n) - (mean * mean);
    // Floating-point cancellation can push a near-zero variance negative.
    return variance.isFinite ? math.max(0.0, variance) : 0.0;
  }
}
