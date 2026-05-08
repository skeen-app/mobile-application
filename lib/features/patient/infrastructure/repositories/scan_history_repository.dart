import '../../../../core/logger/app_logger.dart';
import '../../../detection/domain/lesion_analysis.dart';
import '../../../detection/domain/ports.dart';
import '../../../detection/domain/scan_remote.dart';
import '../../../detection/infrastructure/scans_api.dart';
import '../../../detection/infrastructure/secure_lesion_repository.dart';
import '../../domain/body_region.dart';
import '../../domain/risk_level.dart';
import '../../domain/scan_history_entry.dart';

/// Read-side port for the scan history list.
abstract class ScanHistoryRepository {
  Future<List<ScanHistoryEntry>> findAll();
}

/// Cloud-first repository that merges results from `/api/v1/scans` with
/// any local rows still pending upload. Both sources are deduped by id —
/// when the backend already has the row we trust the cloud copy because
/// it can include the signed download URL.
class HttpScanHistoryRepository implements ScanHistoryRepository {
  HttpScanHistoryRepository({
    required this.api,
    required this.localRepository,
    required this.tokenReader,
    required this.patientId,
  });

  final ScansApi api;
  final LesionRepositoryPort localRepository;
  final String? Function() tokenReader;
  final String patientId;

  @override
  Future<List<ScanHistoryEntry>> findAll() async {
    if (localRepository is SecureLesionRepository) {
      await (localRepository as SecureLesionRepository).initialize();
    }
    // Locally queued deletions must vanish from the UI immediately even
    // though the cloud copy is still around — otherwise the row would
    // reappear after every refresh until the orchestrator drains.
    final pendingDeletion =
        (await localRepository.findPendingDeletionIds()).toSet();

    final remote = (await _fetchRemote())
        .where((s) => !pendingDeletion.contains(s.id))
        .toList();
    final pending = await _fetchLocalPending(
      excludingRemoteIds: remote.map((s) => s.id).toSet(),
    );
    final all = <ScanHistoryEntry>[
      ...remote.map(_remoteToEntry),
      ...pending.map(_localToEntry),
    ];
    all.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    return all;
  }

  Future<List<ScanRemote>> _fetchRemote() async {
    final token = tokenReader();
    if (token == null) return const [];
    try {
      return await api.listScans(token: token);
    } catch (e) {
      AppLogger.warning('History: cloud fetch failed, returning empty: $e',
          tag: 'History');
      return const [];
    }
  }

  Future<List<LesionAnalysis>> _fetchLocalPending({
    required Set<String> excludingRemoteIds,
  }) async {
    if (localRepository is SecureLesionRepository) {
      await (localRepository as SecureLesionRepository).initialize();
    }
    final all = await localRepository.findByPatient(patientId);
    return all.where((a) => !excludingRemoteIds.contains(a.id)).toList();
  }

  ScanHistoryEntry _remoteToEntry(ScanRemote r) {
    return ScanHistoryEntry(
      id: r.id,
      bodyPartLabel: _displayLabel(r.bodyPartLabel, r.bodyRegion),
      region: _slugToRegion(r.bodyRegion),
      riskLevel: _riskFromString(r.riskLevel),
      scannedAt: r.capturedAt,
      thumbnailUrl: r.imageDownloadUrl,
    );
  }

  ScanHistoryEntry _localToEntry(LesionAnalysis a) {
    final region = _slugToRegion(a.bodyRegion);
    return ScanHistoryEntry(
      id: a.id,
      bodyPartLabel: a.bodyRegion ?? region.displayLabel,
      region: region,
      riskLevel: _riskFromWarning(a.result.warningLevel.name),
      scannedAt: a.capturedAt,
      pendingSync: true,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  static String _displayLabel(String? bodyPart, String? region) {
    if (bodyPart != null && bodyPart.isNotEmpty) return bodyPart;
    return _slugToRegion(region).displayLabel;
  }

  static BodyRegion _slugToRegion(String? slug) {
    final lower = (slug ?? '').toLowerCase();
    if (lower.contains('head') || lower.contains('scalp') ||
        lower.contains('cheek') || lower.contains('neck')) {
      return BodyRegion.head;
    }
    if (lower.contains('chest') || lower.contains('abdomen')) {
      return BodyRegion.chest;
    }
    if (lower.contains('back')) return BodyRegion.back;
    if (lower.contains('leftarm') || lower.contains('left arm')) {
      return BodyRegion.leftArm;
    }
    if (lower.contains('rightarm') || lower.contains('right arm')) {
      return BodyRegion.rightArm;
    }
    if (lower.contains('leftleg') || lower.contains('left leg')) {
      return BodyRegion.leftLeg;
    }
    if (lower.contains('rightleg') || lower.contains('right leg')) {
      return BodyRegion.rightLeg;
    }
    return BodyRegion.chest;
  }

  static RiskLevel _riskFromString(String slug) {
    switch (slug) {
      case 'high':
        return RiskLevel.high;
      case 'medium':
        return RiskLevel.medium;
      case 'low':
      default:
        return RiskLevel.low;
    }
  }

  static RiskLevel _riskFromWarning(String warning) {
    switch (warning) {
      case 'alert':
        return RiskLevel.high;
      case 'caution':
        return RiskLevel.medium;
      case 'reassuring':
      default:
        return RiskLevel.low;
    }
  }
}

/// Empty repository used only when no user is signed in. Kept as the
/// default binding so the screen renders a clean empty-state at boot.
class EmptyScanHistoryRepository implements ScanHistoryRepository {
  const EmptyScanHistoryRepository();
  @override
  Future<List<ScanHistoryEntry>> findAll() async => const [];
}

extension on BodyRegion {
  String get displayLabel {
    switch (this) {
      case BodyRegion.head:
        return 'Head';
      case BodyRegion.chest:
        return 'Chest';
      case BodyRegion.leftArm:
        return 'Left Arm';
      case BodyRegion.rightArm:
        return 'Right Arm';
      case BodyRegion.back:
        return 'Back';
      case BodyRegion.leftLeg:
        return 'Left Leg';
      case BodyRegion.rightLeg:
        return 'Right Leg';
    }
  }
}
