import '../../../../core/logger/app_logger.dart';
import '../../../detection/domain/lesion_analysis.dart';
import '../../../detection/domain/ports.dart';
import '../../../detection/domain/scan_remote.dart';
import '../../../detection/infrastructure/scans_api.dart';
import '../../../detection/infrastructure/secure_lesion_repository.dart';
import '../../domain/body_region.dart';
import '../../domain/lesion_summary.dart';

/// Read-side projection used by the home dashboard body map (dots +
/// per-group counts). Cloud-first, falls back to merging local pending
/// rows so the dot for a fresh capture appears immediately even offline.
class LesionSummaryRepository {
  LesionSummaryRepository({
    required this.api,
    required this.localRepository,
    required this.tokenReader,
    required this.patientId,
  });

  final ScansApi api;
  final LesionRepositoryPort localRepository;
  final String? Function() tokenReader;
  final String patientId;

  Future<List<LesionSummary>> findAll() async {
    if (localRepository is SecureLesionRepository) {
      await (localRepository as SecureLesionRepository).initialize();
    }
    final pendingDeletion =
        (await localRepository.findPendingDeletionIds()).toSet();
    final remote = (await _fetchRemote())
        .where((s) => !pendingDeletion.contains(s.id))
        .toList();

    // Same cache-on-fetch trick as the history repo: rehydrate the local
    // DB so a tap on a body-map dot — which routes through the detail
    // screen's findById — works after a session purge.
    for (final r in remote) {
      try {
        await localRepository.upsertCloudSnapshot(r);
      } catch (e) {
        AppLogger.warning(
          'LesionSummary: failed to cache cloud snapshot ${r.id}: $e',
          tag: 'LesionSummary',
        );
      }
    }

    final pending = await _fetchLocalPending(
      excludingRemoteIds: remote.map((s) => s.id).toSet(),
    );
    return [
      ...remote.map(_remoteToSummary),
      ...pending.map(_localToSummary),
    ];
  }

  Future<List<ScanRemote>> _fetchRemote() async {
    final token = tokenReader();
    if (token == null) return const [];
    try {
      return await api.listScans(token: token);
    } catch (e) {
      AppLogger.warning('LesionSummary: cloud fetch failed: $e',
          tag: 'LesionSummary');
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

  LesionSummary _remoteToSummary(ScanRemote r) {
    final region = _slugToRegion(_preferLabel(r.bodyRegion, r.bodyPartLabel));
    final pos = (r.relativePositionX != null && r.relativePositionY != null)
        ? (x: r.relativePositionX!, y: r.relativePositionY!)
        : _defaultPositionFor(region);
    return LesionSummary(
      id: r.id,
      region: region,
      status: _statusFromRisk(r.riskLevel),
      relativePosition: pos,
    );
  }

  LesionSummary _localToSummary(LesionAnalysis a) {
    final region = _slugToRegion(a.bodyRegion);
    return LesionSummary(
      id: a.id,
      region: region,
      status: _statusFromWarning(a.result.warningLevel.name),
      relativePosition: _defaultPositionFor(region, seed: a.id.hashCode),
    );
  }

  /// The picked label ("Head", "Left Arm", …) is the user's authoritative
  /// choice and is what [SecureLesionRepository.upsertCloudSnapshot] caches
  /// locally; the slug is a lossy projection that some rows may be missing
  /// (older scans, or a backend that didn't echo `body_region` back).
  /// Prefer the explicit label so a scan tagged "Head" never collapses to
  /// the chest default.
  static String? _preferLabel(String? slug, String? label) {
    if (label != null && label.trim().isNotEmpty) return label;
    return slug;
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

  static LesionStatus _statusFromRisk(String slug) {
    return slug == 'high' || slug == 'medium'
        ? LesionStatus.needsAttention
        : LesionStatus.stable;
  }

  static LesionStatus _statusFromWarning(String warning) {
    switch (warning) {
      case 'alert':
      case 'caution':
        return LesionStatus.needsAttention;
      default:
        return LesionStatus.stable;
    }
  }

  /// Falls back to a region-centroid + small scatter when the backend
  /// didn't store a relative position (older scans). Scatter is seeded
  /// off the row id so the same scan always lands on the same dot.
  static ({double x, double y}) _defaultPositionFor(
    BodyRegion region, {
    int? seed,
  }) {
    final rng = (seed ?? DateTime.now().microsecondsSinceEpoch).abs();
    double scatter(int low, int high) {
      final range = high - low;
      if (range <= 0) return low.toDouble();
      return (low + (rng % range)).toDouble();
    }

    switch (region) {
      case BodyRegion.head:
        return (x: scatter(20, 26) / 58, y: scatter(15, 22) / 165);
      case BodyRegion.chest:
        return (x: scatter(24, 32) / 58, y: scatter(40, 60) / 165);
      case BodyRegion.back:
        return (x: scatter(24, 32) / 58, y: scatter(40, 78) / 165);
      case BodyRegion.leftArm:
        return (x: scatter(8, 16) / 58, y: scatter(45, 90) / 165);
      case BodyRegion.rightArm:
        return (x: scatter(42, 50) / 58, y: scatter(45, 90) / 165);
      case BodyRegion.leftLeg:
        return (x: scatter(20, 26) / 58, y: scatter(95, 145) / 165);
      case BodyRegion.rightLeg:
        return (x: scatter(34, 40) / 58, y: scatter(95, 145) / 165);
    }
  }
}
