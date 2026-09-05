import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../domain/fiducial_marker.dart';
import '../domain/homography.dart';
import '../domain/luma_frame.dart';

/// One detected marker.
@immutable
class MarkerDetection {
  const MarkerDetection({
    required this.corners,
    required this.rotation,
    required this.hammingErrors,
    required this.elapsedMs,
  });

  /// Corners in the input frame's pixel coordinates, ordered from the
  /// marker's **canonical** top-left, clockwise. Canonical, not as-seen:
  /// the code's rotation is resolved so the plane frame is stable however
  /// the card is turned on the skin.
  final List<Offset> corners;

  /// Quarter turns clockwise the marker was seen rotated by.
  final int rotation;

  final int hammingErrors;

  /// Detector wall time for this frame. Persisted so the Dart-vs-native
  /// decision is made on field numbers.
  final int elapsedMs;

  Offset get centre => Offset(
        (corners[0].dx + corners[1].dx + corners[2].dx + corners[3].dx) / 4,
        (corners[0].dy + corners[1].dy + corners[2].dy + corners[3].dy) / 4,
      );

  /// Scales the corners into another coordinate frame.
  MarkerDetection scaled(double s) => MarkerDetection(
        corners: [for (final c in corners) Offset(c.dx * s, c.dy * s)],
        rotation: rotation,
        hammingErrors: hammingErrors,
        elapsedMs: elapsedMs,
      );
}

/// Detector parameters. Defaults tuned for a 320–640 px wide luma plane.
@immutable
class MarkerDetectorConfig {
  const MarkerDetectorConfig({
    this.thresholdWindow = 31,
    this.thresholdOffset = 8,
    this.minSidePx = 12,
    this.maxAreaFraction = 0.5,
    this.maxSideRatio = 3.0,
  });

  /// Side of the local-mean window for adaptive thresholding, in pixels.
  /// About a marker cell or two at the expected scale: large enough that a
  /// cell interior is compared against its surroundings, small enough that
  /// slow illumination gradients (and skin tone itself) do not register.
  final int thresholdWindow;

  /// A pixel must be this much darker than its local mean to be "ink".
  final int thresholdOffset;

  /// Smallest quad side accepted. Below this the 6×6 cell grid has under
  /// two pixels per cell and the decode is noise.
  final int minSidePx;

  /// Largest component considered, as a fraction of the frame.
  final double maxAreaFraction;

  /// Longest/shortest quad side. 3.0 admits tilts up to ~70°, well beyond
  /// anything the gate will accept, without admitting arbitrary streaks.
  final double maxSideRatio;
}

/// Finds the study marker in a luma frame.
///
/// Pure Dart on purpose: no native dependency means no correlation with
/// device tier, and the whole pipeline is testable against synthetic frames.
/// Pipeline: adaptive threshold → dark connected components → convex hull →
/// quadrilateral → unwarp the 6×6 cell grid → decode → dictionary match
/// with rotation → corners re-ordered to the canonical frame.
///
/// Top-level so it can run inside a worker isolate.
MarkerDetection? detectMarker(
  LumaFrame frame, {
  FiducialMarker marker = FiducialMarker.study,
  MarkerDetectorConfig config = const MarkerDetectorConfig(),
}) {
  final sw = Stopwatch()..start();
  final w = frame.width;
  final h = frame.height;
  if (w < 16 || h < 16 || frame.luma.length < w * h) return null;

  final dark = _adaptiveThreshold(frame.luma, w, h, config);
  final candidates = _darkComponents(dark, w, h, config);

  MarkerDetection? best;
  for (final component in candidates) {
    final quad = _quadFromComponent(component, w, h, config);
    if (quad == null) continue;

    final decoded = _decode(frame.luma, w, h, quad, marker);
    if (decoded == null) continue;

    final rotation = marker.matchRotation(decoded.code);
    if (rotation == null) continue;

    final errors = FiducialMarker.hamming(
      decoded.code,
      marker.rotations[rotation],
    );
    // Canonical top-left sits at seen-corner index `rotation`.
    final canonical = [
      for (var i = 0; i < 4; i++) quad[(i + rotation) % 4],
    ];

    final candidate = MarkerDetection(
      corners: canonical,
      rotation: rotation,
      hammingErrors: errors,
      elapsedMs: 0,
    );
    if (best == null ||
        errors < best.hammingErrors ||
        (errors == best.hammingErrors &&
            _area(candidate.corners) > _area(best.corners))) {
      best = candidate;
    }
  }

  sw.stop();
  if (best == null) return null;
  return MarkerDetection(
    corners: best.corners,
    rotation: best.rotation,
    hammingErrors: best.hammingErrors,
    elapsedMs: sw.elapsedMilliseconds,
  );
}

// ──────────────────────────────────────────────────────────────────────
// 1. Adaptive threshold
// ──────────────────────────────────────────────────────────────────────

/// Marks pixels darker than their local mean by [MarkerDetectorConfig
/// .thresholdOffset]. Local, not global: a global threshold would either
/// swallow dark skin as "ink" or lose the marker under a shadow. The marker's
/// black border is always darker than the white quiet zone around it,
/// whatever the skin tone or the lighting.
Uint8List _adaptiveThreshold(
  Uint8List luma,
  int w,
  int h,
  MarkerDetectorConfig config,
) {
  // Summed-area table, (w+1)×(h+1), Int32 is ample (255 × 1e6 ≈ 2.5e8).
  final sw = w + 1;
  final integral = Int32List(sw * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0;
    final rowBase = y * w;
    final outBase = (y + 1) * sw;
    final prevBase = y * sw;
    for (var x = 0; x < w; x++) {
      rowSum += luma[rowBase + x];
      integral[outBase + x + 1] = integral[prevBase + x + 1] + rowSum;
    }
  }

  final half = config.thresholdWindow ~/ 2;
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - half);
    final y1 = math.min(h, y + half + 1);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - half);
      final x1 = math.min(w, x + half + 1);
      final area = (x1 - x0) * (y1 - y0);
      final sum = integral[y1 * sw + x1] -
          integral[y0 * sw + x1] -
          integral[y1 * sw + x0] +
          integral[y0 * sw + x0];
      final mean = sum / area;
      if (luma[y * w + x] < mean - config.thresholdOffset) {
        out[y * w + x] = 1;
      }
    }
  }
  return out;
}

// ──────────────────────────────────────────────────────────────────────
// 2. Connected components
// ──────────────────────────────────────────────────────────────────────

class _Component {
  _Component();
  final List<int> pixels = [];
  int minX = 1 << 30, maxX = -1, minY = 1 << 30, maxY = -1;

  int get boxW => maxX - minX + 1;
  int get boxH => maxY - minY + 1;
}

/// 4-connected labelling of ink pixels, keeping only components whose
/// bounding box could plausibly be a marker.
List<_Component> _darkComponents(
  Uint8List dark,
  int w,
  int h,
  MarkerDetectorConfig config,
) {
  final seen = Uint8List(w * h);
  final found = <_Component>[];
  final stack = <int>[];
  final maxArea = (w * h * config.maxAreaFraction).round();
  final minBox = config.minSidePx;

  for (var start = 0; start < dark.length; start++) {
    if (dark[start] == 0 || seen[start] != 0) continue;

    final component = _Component();
    seen[start] = 1;
    stack.add(start);
    var overflow = false;

    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w;
      final y = i ~/ w;
      component.pixels.add(i);
      if (x < component.minX) component.minX = x;
      if (x > component.maxX) component.maxX = x;
      if (y < component.minY) component.minY = y;
      if (y > component.maxY) component.maxY = y;
      if (component.pixels.length > maxArea) {
        overflow = true;
        // Keep draining so its pixels are marked seen, but stop storing.
      }

      if (x > 0) _visit(stack, seen, dark, i - 1);
      if (x < w - 1) _visit(stack, seen, dark, i + 1);
      if (y > 0) _visit(stack, seen, dark, i - w);
      if (y < h - 1) _visit(stack, seen, dark, i + w);
    }

    if (overflow) continue;
    if (component.boxW < minBox || component.boxH < minBox) continue;
    // A marker border is a ring: its pixel count is well below its box area
    // but not tiny. Reject solid blobs (fill > 0.9) and wisps (fill < 0.15).
    final fill = component.pixels.length / (component.boxW * component.boxH);
    if (fill > 0.9 || fill < 0.15) continue;
    found.add(component);
  }
  return found;
}

void _visit(List<int> stack, Uint8List seen, Uint8List dark, int i) {
  if (seen[i] != 0 || dark[i] == 0) return;
  seen[i] = 1;
  stack.add(i);
}

// ──────────────────────────────────────────────────────────────────────
// 3. Convex hull → quadrilateral
// ──────────────────────────────────────────────────────────────────────

/// Reduces a component to a clockwise quad (starting at the corner nearest
/// the image origin), or null if it does not look like one.
List<Offset>? _quadFromComponent(
  _Component c,
  int w,
  int h,
  MarkerDetectorConfig config,
) {
  // Only boundary pixels can be hull vertices: sub-sample the interior away
  // for large components to keep the sort cheap.
  final step = math.max(1, c.pixels.length ~/ 4000);
  final points = <Offset>[];
  for (var i = 0; i < c.pixels.length; i += step) {
    final p = c.pixels[i];
    points.add(Offset((p % w).toDouble(), (p ~/ w).toDouble()));
  }
  // Always include the extreme pixels so sub-sampling cannot shave a corner.
  for (final p in c.pixels) {
    final x = p % w, y = p ~/ w;
    if (x == c.minX || x == c.maxX || y == c.minY || y == c.maxY) {
      points.add(Offset(x.toDouble(), y.toDouble()));
    }
  }

  final hull = _convexHull(points);
  if (hull.length < 4) return null;

  // Farthest pair → diagonal; then the farthest point from that line on
  // each side → the other two corners. Then polish each corner in turn by
  // the vertex that maximises the quad's area.
  var i0 = 0, i2 = 0;
  var bestD = -1.0;
  for (var i = 0; i < hull.length; i++) {
    for (var j = i + 1; j < hull.length; j++) {
      final d = (hull[i] - hull[j]).distanceSquared;
      if (d > bestD) {
        bestD = d;
        i0 = i;
        i2 = j;
      }
    }
  }
  int? i1, i3;
  var best1 = 0.0, best3 = 0.0;
  for (var i = 0; i < hull.length; i++) {
    if (i == i0 || i == i2) continue;
    final s = _signedDistance(hull[i0], hull[i2], hull[i]);
    if (s > best1) {
      best1 = s;
      i1 = i;
    } else if (-s > best3) {
      best3 = -s;
      i3 = i;
    }
  }
  if (i1 == null || i3 == null) return null;

  final idx = [i0, i1, i2, i3];
  for (var pass = 0; pass < 2; pass++) {
    for (var k = 0; k < 4; k++) {
      var bestArea = -1.0;
      var bestIdx = idx[k];
      for (var i = 0; i < hull.length; i++) {
        final trial = List<int>.from(idx)..[k] = i;
        if (trial.toSet().length < 4) continue;
        final area = _area([for (final t in trial) hull[t]]);
        if (area > bestArea) {
          bestArea = area;
          bestIdx = i;
        }
      }
      idx[k] = bestIdx;
    }
  }

  var quad = [for (final i in idx) hull[i]];
  quad = _orderClockwise(quad);

  // Geometry sanity.
  final sides = [
    for (var i = 0; i < 4; i++) (quad[(i + 1) % 4] - quad[i]).distance,
  ];
  final shortest = sides.reduce(math.min);
  final longest = sides.reduce(math.max);
  if (shortest < config.minSidePx) return null;
  if (longest / shortest > config.maxSideRatio) return null;
  if (!_isConvex(quad)) return null;
  for (final p in quad) {
    if (p.dx < 0 || p.dy < 0 || p.dx >= w || p.dy >= h) return null;
  }
  return quad;
}

/// Andrew's monotone chain. Returns the hull counter-clockwise in y-down
/// image coordinates.
List<Offset> _convexHull(List<Offset> input) {
  final pts = List<Offset>.from(input)
    ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  if (pts.length < 3) return pts;

  double cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

  final lower = <Offset>[];
  for (final p in pts) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Offset>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

double _signedDistance(Offset a, Offset b, Offset p) {
  final d = b - a;
  final len = d.distance;
  if (len < 1e-9) return 0;
  return ((p.dx - a.dx) * d.dy - (p.dy - a.dy) * d.dx) / len;
}

double _area(List<Offset> q) {
  var s = 0.0;
  for (var i = 0; i < q.length; i++) {
    final a = q[i], b = q[(i + 1) % q.length];
    s += a.dx * b.dy - b.dx * a.dy;
  }
  return s.abs() / 2;
}

/// Sorts corners clockwise (in y-down image space) around their centroid,
/// starting from the one nearest the image origin.
List<Offset> _orderClockwise(List<Offset> q) {
  final cx = q.fold(0.0, (s, p) => s + p.dx) / q.length;
  final cy = q.fold(0.0, (s, p) => s + p.dy) / q.length;
  final sorted = List<Offset>.from(q)
    ..sort((a, b) => math
        .atan2(a.dy - cy, a.dx - cx)
        .compareTo(math.atan2(b.dy - cy, b.dx - cx)));
  var start = 0;
  var bestSum = double.infinity;
  for (var i = 0; i < sorted.length; i++) {
    final s = sorted[i].dx + sorted[i].dy;
    if (s < bestSum) {
      bestSum = s;
      start = i;
    }
  }
  return [for (var i = 0; i < 4; i++) sorted[(start + i) % 4]];
}

bool _isConvex(List<Offset> q) {
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4], c = q[(i + 2) % 4];
    final z = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
    final s = z > 0 ? 1 : (z < 0 ? -1 : 0);
    if (s == 0) return false;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
}

// ──────────────────────────────────────────────────────────────────────
// 4. Decode
// ──────────────────────────────────────────────────────────────────────

class _Decoded {
  const _Decoded(this.code);
  final int code;
}

/// Unwarps the 6×6 cell grid through a homography and reads each cell at
/// its centre. Border cells must read black; the inner 4×4 becomes the code.
_Decoded? _decode(
  Uint8List luma,
  int w,
  int h,
  List<Offset> quad,
  FiducialMarker marker,
) {
  const n = FiducialMarker.cellsPerSide;
  final unit = [
    const Offset(0, 0),
    Offset(n.toDouble(), 0),
    Offset(n.toDouble(), n.toDouble()),
    Offset(0, n.toDouble()),
  ];
  final hom = homographyFromPoints(unit, quad);
  if (hom == null) return null;

  final samples = List<int>.filled(n * n, 0);
  var lo = 255, hi = 0;
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      final p = hom.apply(c + 0.5, r + 0.5);
      if (p == null) return null;
      final v = _bilinear(luma, w, h, p.dx, p.dy);
      samples[r * n + c] = v;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
  }
  // A real marker has both inks; a flat patch is not one.
  if (hi - lo < 40) return null;
  final cut = (lo + hi) / 2;

  var borderErrors = 0;
  var code = 0;
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      final white = samples[r * n + c] > cut;
      final isBorder = r == 0 || c == 0 || r == n - 1 || c == n - 1;
      if (isBorder) {
        if (white) borderErrors++;
      } else {
        final dr = r - 1, dc = c - 1;
        if (white) code |= 1 << (15 - (dr * FiducialMarker.dataCells + dc));
      }
    }
  }
  // One border cell may be lost to a specular highlight; more means this is
  // not a bordered code.
  if (borderErrors > 1) return null;
  return _Decoded(code);
}

int _bilinear(Uint8List luma, int w, int h, double x, double y) {
  final x0 = x.floor().clamp(0, w - 1);
  final y0 = y.floor().clamp(0, h - 1);
  final x1 = (x0 + 1).clamp(0, w - 1);
  final y1 = (y0 + 1).clamp(0, h - 1);
  final fx = (x - x0).clamp(0.0, 1.0);
  final fy = (y - y0).clamp(0.0, 1.0);
  final a = luma[y0 * w + x0], b = luma[y0 * w + x1];
  final c = luma[y1 * w + x0], d = luma[y1 * w + x1];
  final top = a + (b - a) * fx;
  final bottom = c + (d - c) * fx;
  return (top + (bottom - top) * fy).round();
}
