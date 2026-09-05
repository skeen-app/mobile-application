import 'dart:ui';

import 'skin_plane_pose.dart';

/// Direct linear transform for a 4-point planar homography.
///
/// Solves the 8×8 system for `h11…h32` with `h33 = 1`, mapping [src] to
/// [dst]. Exactly four correspondences — the marker's corners — so the
/// system is square and Gaussian elimination with partial pivoting is all
/// that is needed. Returns null when the points are degenerate (three
/// collinear, or a repeated point).
///
/// Shared by the detector (unit cell grid → image, to sample the code) and
/// the pose estimator (plane millimetres → image), so both use one definition
/// of what a homography is.
Matrix3? homographyFromPoints(List<Offset> src, List<Offset> dst) {
  if (src.length != 4 || dst.length != 4) return null;

  // Row-major 8×9 augmented matrix.
  final a = List<double>.filled(8 * 9, 0);
  for (var i = 0; i < 4; i++) {
    final x = src[i].dx, y = src[i].dy;
    final u = dst[i].dx, v = dst[i].dy;
    final r0 = (2 * i) * 9;
    a[r0 + 0] = x;
    a[r0 + 1] = y;
    a[r0 + 2] = 1;
    a[r0 + 6] = -u * x;
    a[r0 + 7] = -u * y;
    a[r0 + 8] = u;
    final r1 = (2 * i + 1) * 9;
    a[r1 + 3] = x;
    a[r1 + 4] = y;
    a[r1 + 5] = 1;
    a[r1 + 6] = -v * x;
    a[r1 + 7] = -v * y;
    a[r1 + 8] = v;
  }

  final h = _solve(a, 8);
  if (h == null) return null;
  return Matrix3([h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1.0]);
}

/// Gaussian elimination with partial pivoting on an n×(n+1) augmented
/// row-major matrix. Returns null if singular.
List<double>? _solve(List<double> a, int n) {
  final cols = n + 1;
  for (var col = 0; col < n; col++) {
    // Pivot.
    var pivot = col;
    var best = a[col * cols + col].abs();
    for (var r = col + 1; r < n; r++) {
      final v = a[r * cols + col].abs();
      if (v > best) {
        best = v;
        pivot = r;
      }
    }
    if (best < 1e-12) return null;
    if (pivot != col) {
      for (var c = 0; c < cols; c++) {
        final tmp = a[col * cols + c];
        a[col * cols + c] = a[pivot * cols + c];
        a[pivot * cols + c] = tmp;
      }
    }
    // Eliminate below.
    final p = a[col * cols + col];
    for (var r = col + 1; r < n; r++) {
      final f = a[r * cols + col] / p;
      if (f == 0) continue;
      for (var c = col; c < cols; c++) {
        a[r * cols + c] -= f * a[col * cols + c];
      }
    }
  }
  // Back-substitute.
  final x = List<double>.filled(n, 0);
  for (var r = n - 1; r >= 0; r--) {
    var s = a[r * cols + n];
    for (var c = r + 1; c < n; c++) {
      s -= a[r * cols + c] * x[c];
    }
    x[r] = s / a[r * cols + r];
  }
  return x;
}
