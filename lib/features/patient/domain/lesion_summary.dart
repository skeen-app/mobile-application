import 'body_region.dart';

/// Triage state of a recorded lesion as surfaced to the patient on the home
/// dashboard. The clinical (5-class) label lives on `LesionAnalysis`; this
/// status is the user-facing reduction to two buckets.
enum LesionStatus {
  needsAttention,
  stable,
}

/// Lightweight projection of a `LesionAnalysis` for the home body map.
///
/// Only carries what the dashboard renders (a dot on the silhouette and the
/// per-group counts). The clinical entity remains in the Detection /
/// LesionHistory aggregate.
class LesionSummary {
  const LesionSummary({
    required this.id,
    required this.region,
    required this.status,
    required this.relativePosition,
  });

  final String id;
  final BodyRegion region;
  final LesionStatus status;

  /// Position relative to the body figure SVG (0..1 on each axis).
  /// `(0,0)` is top-left of the silhouette bounding box.
  final ({double x, double y}) relativePosition;
}
