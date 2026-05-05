import 'dart:ui';

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
///   2. **Refined:** a fast contrast-based centroid finder (run during
///      InferenceService) locates the darkest blob within the center region
///      of the captured image and provides that as the raycast origin instead.
///
/// The pipeline:
///   capture → (optional centroid refinement) → normalize to screen →
///   hit-test against AR plane → create WorldAnchor → per-frame projection
class CoordinateTranslator {
  const CoordinateTranslator(this._session);

  final ArSessionPort _session;

  /// Hit-test the center of interest against the AR skin plane.
  ///
  /// [interestPoint] is in normalized screen coordinates [0,1]×[0,1].
  /// Defaults to (0.5, 0.5) — viewport center — when no centroid was found.
  Future<WorldAnchor?> anchorAtCenterOfInterest({
    Offset interestPoint = const Offset(0.5, 0.5),
  }) {
    return _session.hitTest(interestPoint);
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
