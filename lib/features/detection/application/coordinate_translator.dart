import 'dart:ui';

import '../domain/ar_geometry.dart';
import '../domain/ports.dart';

/// Pure-Dart bridge that turns a 2D pixel-space [BoundingBox] (today fed
/// by the on-screen reticle, tomorrow by a real detector) into a 3D
/// [WorldAnchor] on the detected skin plane via the [ArSessionPort].
///
/// Lives in `application/` because it composes a domain port with pure
/// math — it has no platform calls of its own. Keeping it as a separate
/// service lets us swap the AR session for a test double in unit tests.
class CoordinateTranslator {
  const CoordinateTranslator(this._session);

  final ArSessionPort _session;

  /// Hit-test the bbox center against the AR plane and return an anchor.
  /// Null if no plane was hit (e.g. session lost tracking, center pointed
  /// at empty space). Callers should fall back to "no anchor" mode and
  /// still surface the inference result without spatial positioning.
  Future<WorldAnchor?> bboxToAnchor(BoundingBox bbox) {
    return _session.hitTest(bbox.normalizedCenter);
  }

  /// Per-frame projection used by the floating diagnosis label to stay
  /// "stuck" to the lesion as the user moves the phone. The label widget
  /// reads this on every frame tick and animates its `Positioned` offset.
  Future<Offset?> anchorToScreen(WorldAnchor anchor) {
    return _session.projectToScreen(anchor);
  }
}
