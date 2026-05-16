import 'body_region.dart';
import 'risk_level.dart';

/// Where a scan currently lives relative to the cloud.
///
///   • [synced]    — the row was uploaded; nothing to flag.
///   • [pending]   — local-only, queued for upload (offline / awaiting
///                   the next sync tick). Surfaces as a "Pending" badge.
///   • [notSynced] — captured with cloud sync disabled by the user. Will
///                   never leave the device on its own. Surfaces as a
///                   distinct "Not synced" badge so the user understands
///                   it's a permanent state, not a transient queue.
enum ScanSyncStatus { synced, pending, notSynced }

/// A single entry in the patient's scan history.
///
/// Mirrors the future `GET /me/scan-history` payload — when the endpoint
/// ships the only thing that needs to change is the repository implementation
/// (mock → HTTP). The presentation layer is built against this contract.
class ScanHistoryEntry {
  const ScanHistoryEntry({
    required this.id,
    required this.bodyPartLabel,
    required this.region,
    required this.riskLevel,
    required this.scannedAt,
    this.thumbnailUrl,
    this.syncStatus = ScanSyncStatus.synced,
  });

  /// Stable identifier — Firestore doc id once the backend lands.
  final String id;

  /// Human-readable label of the precise body part shown in the card title
  /// (e.g. "Upper Back", "Left Leg", "Right Forearm"). Distinct from
  /// [region] so we can show specific copy without expanding the enum.
  final String bodyPartLabel;

  /// Coarse anatomical region — used by the filter sheet (collapses to the
  /// home-dashboard `head/chest/legs` aggregate via `region.group`).
  final BodyRegion region;

  final RiskLevel riskLevel;

  final DateTime scannedAt;

  /// Cloud Storage URL of the captured photo. `null` while the upload is
  /// pending or for entries seeded before the photo pipeline existed.
  final String? thumbnailUrl;

  /// Cloud sync state of this row — drives whether the card shows a
  /// "Pending" badge (queued for upload), "Not synced" badge (user opted
  /// out of cloud sync), or no badge at all (already uploaded).
  final ScanSyncStatus syncStatus;
}
