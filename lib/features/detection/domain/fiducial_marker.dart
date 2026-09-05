import 'dart:ui';

import 'package:flutter/foundation.dart';

/// A printed reference patch of known reflectance next to the code.
@immutable
class ColorPatch {
  const ColorPatch({
    required this.centreMm,
    required this.sideMm,
    required this.reflectance,
  });

  /// Centre in the marker's plane frame (mm, X right, Y down).
  final Offset centreMm;
  final double sideMm;

  /// Nominal diffuse reflectance of the printed patch, 0–1.
  final double reflectance;
}

/// The study's fiducial marker: a 4×4 binary code inside a 1-cell black
/// border, printed at a known physical size and placed on the skin next to
/// the lesion.
///
/// This is the only metric reference in the scene. Everything the AR layer
/// reports as a physical quantity — px/mm, tilt, the plane the overlays are
/// registered to — is resolved from the four corners of this square, so its
/// real-world dimensions must be exact (see the 1:1 print check in the
/// protocol PDF).
///
/// **Single source of truth.** [bits] drives the detector's dictionary match
/// AND the printable artwork. If the two ever came from different places the
/// printed card and the app could silently disagree, and the failure would
/// look like "marker never detected" with nothing in the logs to say why.
///
/// The code is ArUco-style (same cell layout as `DICT_4X4_*`, so the standard
/// literature on detection applies) but it is **not** claimed to coincide
/// with a specific OpenCV dictionary id. It was chosen by exhaustive search
/// for rotational robustness: every rotation is ≥10 bits from every other,
/// ≥8 from all-black and all-white, and no row or column is uniform. A
/// 1-bit read error therefore cannot be confused with a rotation.
@immutable
class FiducialMarker {
  const FiducialMarker({
    required this.bits,
    required this.sideMm,
    this.quietZoneCells = 1,
  });

  /// 16 data bits, row-major, MSB = top-left cell. 1 = white cell.
  final int bits;

  /// Physical side of the black border's outer edge, in millimetres.
  final double sideMm;

  /// White margin around the border required by the spec, in cells.
  final int quietZoneCells;

  /// Data cells per side.
  static const int dataCells = 4;

  /// Cells per side including the 1-cell black border.
  static const int cellsPerSide = dataCells + 2;

  /// Physical size of one cell.
  double get cellMm => sideMm / cellsPerSide;

  /// The card the study prints. 30 mm gives ~200 px across the marker at a
  /// typical macro working distance on a 720p stream — comfortably above the
  /// ~12 px minimum the detector needs per side, with margin for a phone
  /// that streams at lower resolution.
  static const FiducialMarker study = FiducialMarker(
    bits: 0xED41,
    sideMm: 30.0,
  );

  // ── Reference patches (WP-4) ────────────────────────────────────────
  //
  // Two squares to the marker's right, outside its quiet zone: 18% grey and
  // white. 8 mm keeps ≥50 px across a patch at the target scale, enough for
  // the 5×5 sampling grid to sit well inside the print. Their column runs
  // alongside the code, so the target disc above the code never overlaps
  // them — verified by test, not by eye.

  static const double patchSideMm = 8.0;
  static const double patchGapMm = 3.0;

  /// Horizontal centre of the patch column.
  double get _patchColumnX =>
      sideMm / 2 + cellMm * quietZoneCells + patchGapMm + patchSideMm / 2;

  /// 18% grey, above the marker's midline.
  ColorPatch get greyPatch => ColorPatch(
        centreMm: Offset(_patchColumnX, -(patchSideMm / 2 + 1)),
        sideMm: patchSideMm,
        reflectance: 0.18,
      );

  /// White, below the midline.
  ColorPatch get whitePatch => ColorPatch(
        centreMm: Offset(_patchColumnX, patchSideMm / 2 + 1),
        sideMm: patchSideMm,
        reflectance: 0.90,
      );

  /// Bit at data row [r], column [c] (0-based, top-left origin).
  int bitAt(int r, int c) => (bits >> (15 - (r * dataCells + c))) & 1;

  /// True when the full 6×6 cell at [row], [col] — including the border — is
  /// white. Used by the renderer (artwork, test fixtures) and mirrors the
  /// decoder's layout exactly.
  bool isCellWhite(int row, int col) {
    if (row <= 0 ||
        col <= 0 ||
        row >= cellsPerSide - 1 ||
        col >= cellsPerSide - 1) {
      return false;
    }
    return bitAt(row - 1, col - 1) == 1;
  }

  /// The code rotated 90° clockwise, as it reads when the marker is seen
  /// rotated. Detection compares against all four.
  static int rotateClockwise(int code) {
    var out = 0;
    for (var r = 0; r < dataCells; r++) {
      for (var c = 0; c < dataCells; c++) {
        // Rotated cell (r, c) came from original (dataCells-1-c, r).
        final srcR = dataCells - 1 - c;
        final srcC = r;
        final bit = (code >> (15 - (srcR * dataCells + srcC))) & 1;
        out |= bit << (15 - (r * dataCells + c));
      }
    }
    return out;
  }

  /// The four orientations of [bits], index = number of clockwise quarter
  /// turns.
  List<int> get rotations {
    final out = <int>[bits];
    for (var i = 0; i < 3; i++) {
      out.add(rotateClockwise(out.last));
    }
    return out;
  }

  static int hamming(int a, int b) {
    var x = a ^ b;
    var n = 0;
    while (x != 0) {
      x &= x - 1;
      n++;
    }
    return n;
  }

  /// Largest number of misread bits still accepted as this marker. With
  /// rotations ≥10 apart, 1 leaves a wide margin against confusing a
  /// corrupted read with a rotated one.
  static const int maxHammingErrors = 1;

  /// Matches a decoded 16-bit read against this marker.
  /// Returns the rotation index (0–3) that matched, or null.
  int? matchRotation(int decoded) {
    final rots = rotations;
    int? best;
    var bestDistance = maxHammingErrors + 1;
    for (var i = 0; i < rots.length; i++) {
      final d = hamming(decoded, rots[i]);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }
}
