import '../../domain/body_region.dart';
import '../../domain/lesion_summary.dart';

/// In-memory placeholder for the patient's recorded lesion scans.
///
/// Will be replaced by a Drift/SQLite-backed implementation once the
/// Detection-context save flow lands. Kept here so the home dashboard can
/// already render a real list and so the dot map and region counts derive
/// from the same source of truth.
class LesionSummaryRepository {
  LesionSummaryRepository();

  // Seeded sample matching the Figma reference (6 moles: 1 head, 3 chest, 2 legs).
  // Coordinates are normalized against the body silhouette SVG (58×165 viewBox).
  static const List<LesionSummary> _seed = [
    LesionSummary(
      id: 'demo-head-1',
      region: BodyRegion.head,
      status: LesionStatus.needsAttention,
      relativePosition: (x: 23 / 58, y: 19 / 165),
    ),
    LesionSummary(
      id: 'demo-chest-1',
      region: BodyRegion.chest,
      status: LesionStatus.needsAttention,
      relativePosition: (x: 19 / 58, y: 38 / 165),
    ),
    LesionSummary(
      id: 'demo-chest-2',
      region: BodyRegion.chest,
      status: LesionStatus.needsAttention,
      relativePosition: (x: 27 / 58, y: 56 / 165),
    ),
    LesionSummary(
      id: 'demo-chest-3',
      region: BodyRegion.chest,
      status: LesionStatus.stable,
      relativePosition: (x: 29 / 58, y: 45 / 165),
    ),
    LesionSummary(
      id: 'demo-leg-1',
      region: BodyRegion.leftLeg,
      status: LesionStatus.stable,
      relativePosition: (x: 18 / 58, y: 104 / 165),
    ),
    LesionSummary(
      id: 'demo-leg-2',
      region: BodyRegion.rightLeg,
      status: LesionStatus.needsAttention,
      relativePosition: (x: 41 / 58, y: 105 / 165),
    ),
  ];

  Future<List<LesionSummary>> findAll() async {
    return List.unmodifiable(_seed);
  }
}
