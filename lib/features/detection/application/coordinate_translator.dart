import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../domain/ar_geometry.dart';
import '../domain/ports.dart';

/// Aspect-ratio-aware 3D coordinate bridge using the "Center of Interest"
/// anchoring strategy.
///
/// Since the TFLite model is a classifier (no bounding boxes), the user
/// centers the lesion inside the AR target ring. The raycast origin is
/// determined by:
///
///   1. **Default:** viewport center (0.5, 0.5) — the lesion is centered
///      by UX design.
///   2. **Refined:** if enabled, a fast contrast-based centroid finder
///      locates the darkest blob within the center region of the captured
///      image and uses that as the raycast origin instead.
///
/// The pipeline:
///   capture → (optional centroid refinement) → normalize to screen →
///   hit-test against AR plane → create WorldAnchor → per-frame projection
class CoordinateTranslator {
  const CoordinateTranslator(this._session);

  final ArSessionPort _session;

  /// Find the centroid of the darkest region within the center crop of the
  /// captured image. Returns normalized [0,1] coordinates relative to the
  /// full image, or null if no distinct dark blob is found.
  ///
  /// Runs in a separate isolate via `compute()` to avoid blocking the
  /// AR render thread.
  Future<Offset?> findLesionCentroid(Uint8List jpegBytes) async {
    try {
      final result = await compute(_findDarkCentroid, jpegBytes);
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('Centroid finder failed: $e');
      return null;
    }
  }

  /// Hit-test the center of interest against the AR skin plane.
  ///
  /// [interestPoint] is in normalized screen coordinates [0,1]×[0,1].
  /// Defaults to (0.5, 0.5) — viewport center — when no centroid was found.
  Future<WorldAnchor?> hitTestCenterOfInterest({
    Offset interestPoint = const Offset(0.5, 0.5),
  }) {
    return _session.hitTest(interestPoint);
  }

  /// Full pipeline: optionally refine the interest point via centroid,
  /// then hit-test for an AR anchor.
  ///
  /// If [capturedBytes] is provided and centroid refinement succeeds, the
  /// refined point is used. Otherwise falls back to viewport center.
  Future<WorldAnchor?> anchorAtCenterOfInterest({
    Uint8List? capturedBytes,
  }) async {
    Offset interestPoint = const Offset(0.5, 0.5);

    // Optional: refine via dark-spot centroid
    if (capturedBytes != null) {
      final centroid = await findLesionCentroid(capturedBytes);
      if (centroid != null) {
        interestPoint = centroid;
        if (kDebugMode) {
          debugPrint(
            'Centroid refinement: (${centroid.dx.toStringAsFixed(3)}, '
            '${centroid.dy.toStringAsFixed(3)})',
          );
        }
      }
    }

    return hitTestCenterOfInterest(interestPoint: interestPoint);
  }

  /// Per-frame projection: world anchor → screen pixel offset.
  ///
  /// The native `projectToScreen` returns normalized [0,1] coords (sx, sy).
  /// We convert to preview-widget pixels.
  Future<Offset?> anchorToScreen(
    WorldAnchor anchor, {
    required Size previewSize,
  }) async {
    final norm = await _session.projectToScreen(anchor);
    if (norm == null) return null;

    return Offset(
      (norm.dx * previewSize.width).clamp(0, previewSize.width),
      (norm.dy * previewSize.height).clamp(0, previewSize.height),
    );
  }
}

/// Top-level function for `compute()`. Finds the centroid of the darkest
/// region within the center 60% of the image.
///
/// Algorithm:
///   1. Decode + grayscale the image
///   2. Extract the center 60% region (where the target ring is)
///   3. Apply Otsu-style thresholding to find dark pixels
///   4. Compute the centroid of all dark pixels
///   5. Return normalized coordinates relative to the full image
Offset? _findDarkCentroid(Uint8List jpegBytes) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) return null;

  final gray = img.grayscale(decoded);
  final w = gray.width;
  final h = gray.height;

  // Center 60% crop bounds
  final cropMarginX = (w * 0.2).round();
  final cropMarginY = (h * 0.2).round();
  final cropW = w - 2 * cropMarginX;
  final cropH = h - 2 * cropMarginY;

  if (cropW <= 0 || cropH <= 0) return null;

  // Pass 1: find mean and min luminance in the crop region
  double sum = 0;
  int count = 0;
  int minLum = 255;
  const step = 2; // sample every 2nd pixel for speed

  for (var y = cropMarginY; y < cropMarginY + cropH; y += step) {
    for (var x = cropMarginX; x < cropMarginX + cropW; x += step) {
      final lum = gray.getPixel(x, y).luminance.round();
      sum += lum;
      count++;
      if (lum < minLum) minLum = lum;
    }
  }

  if (count == 0) return null;
  final meanLum = sum / count;

  // Threshold: pixels darker than (mean + darkest) / 2 are "lesion"
  final threshold = ((meanLum + minLum) / 2).round();

  // Pass 2: compute weighted centroid of dark pixels
  double cx = 0, cy = 0;
  int darkCount = 0;

  for (var y = cropMarginY; y < cropMarginY + cropH; y += step) {
    for (var x = cropMarginX; x < cropMarginX + cropW; x += step) {
      final lum = gray.getPixel(x, y).luminance.round();
      if (lum <= threshold) {
        // Weight by how dark the pixel is (darker = more weight)
        final weight = max(1, threshold - lum);
        cx += x * weight;
        cy += y * weight;
        darkCount += weight;
      }
    }
  }

  if (darkCount < 10) {
    // Not enough dark pixels — no distinct lesion found
    return null;
  }

  // Normalize to [0, 1]
  final normX = (cx / darkCount) / w;
  final normY = (cy / darkCount) / h;

  // Only use the centroid if it's within a reasonable region (not edge)
  if (normX < 0.15 || normX > 0.85 || normY < 0.15 || normY > 0.85) {
    return null; // Centroid too far from center — likely noise
  }

  return Offset(normX.clamp(0, 1), normY.clamp(0, 1));
}
