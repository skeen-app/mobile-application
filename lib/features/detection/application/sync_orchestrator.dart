import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/notifications/notifications_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/privacy_settings.dart';
import '../domain/lesion_analysis.dart';
import '../domain/ports.dart';
import '../infrastructure/secure_lesion_repository.dart';
import '../infrastructure/scans_api.dart';
import 'providers.dart';

/// Orchestrates the offline-first scan upload pipeline.
///
/// Triggers:
///   • App boot — `start()` runs once, attempts a sync immediately.
///   • Foreground resume — `start()` re-triggers via the lifecycle observer
///     wired in `main.dart`.
///   • Connectivity restored — internal listener on the Connectivity stream.
///   • Manual — `syncNow()` after a successful capture.
///
/// Each pending [LesionAnalysis] is sent through the 3-step contract on
/// [ScansApi]: create doc → PUT image to signed URL → confirm upload.
/// Failures keep the local row marked `pending_upload=1` so the next
/// trigger retries it.
class SyncOrchestrator {
  SyncOrchestrator({
    required this.repository,
    required this.api,
    required this.tokenReader,
    required this.patientIdReader,
    required this.cloudSyncEnabledReader,
    this.notifications,
  });

  final LesionRepositoryPort repository;
  final ScansApi api;
  final String? Function() tokenReader;
  // Resolves the current authenticated user id at call time. Returning
  // null means "no active session" — the orchestrator must not touch the
  // local database in that state (would risk uploading a stale row from
  // a previous user under a different token).
  final String? Function() patientIdReader;
  final bool Function() cloudSyncEnabledReader;
  final NotificationsController? notifications;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _running = false;
  DateTime _lastRunAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Wires the connectivity listener and runs the first attempt.
  Future<void> start() async {
    _connSub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.any(_isOnline)) {
        unawaited(syncNow(reason: 'connectivity-restored'));
      }
    });
    await syncNow(reason: 'start');
  }

  Future<void> stop() async {
    await _connSub?.cancel();
    _connSub = null;
  }

  /// Pulls every `pending_upload=1` row and pushes it through the API.
  /// Idempotent — concurrent calls collapse via [_running].
  Future<int> syncNow({String reason = 'manual'}) async {
    if (_running) return 0;
    if (!cloudSyncEnabledReader()) {
      AppLogger.info(
        'SyncOrchestrator: cloud sync disabled by user — skipping ($reason)',
        tag: 'Sync',
      );
      return 0;
    }
    final token = tokenReader();
    if (token == null) {
      AppLogger.info('SyncOrchestrator: no token, skipping ($reason)', tag: 'Sync');
      return 0;
    }
    final patientId = patientIdReader();
    if (patientId == null) {
      AppLogger.info(
        'SyncOrchestrator: no current patient, skipping ($reason)',
        tag: 'Sync',
      );
      return 0;
    }
    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.any(_isOnline)) {
      AppLogger.info('SyncOrchestrator: offline, skipping ($reason)', tag: 'Sync');
      return 0;
    }
    // Light debounce: don't hammer the API on rapid foreground events.
    final now = DateTime.now();
    if (now.difference(_lastRunAt).inSeconds < 5 && reason != 'manual') {
      return 0;
    }
    _lastRunAt = now;
    _running = true;
    var uploaded = 0;
    try {
      final pending = await repository.findPendingUpload(patientId);
      if (pending.isEmpty) {
        AppLogger.info('SyncOrchestrator: nothing to upload ($reason)', tag: 'Sync');
        return 0;
      }
      AppLogger.info(
        'SyncOrchestrator: ${pending.length} pending scans (trigger=$reason)',
        tag: 'Sync',
      );
      for (final analysis in pending) {
        final ok = await uploadOne(analysis);
        if (ok) uploaded += 1;
      }

      // Drain any rows the user marked for deletion while offline. Each
      // iteration either fully removes the row (on success / 404) or
      // leaves it queued for the next run.
      final pendingDeletionIds = await repository.findPendingDeletionIds();
      for (final id in pendingDeletionIds) {
        try {
          final ok = await api.deleteScan(token: token, scanId: id);
          if (ok) {
            await repository.delete(id);
            AppLogger.info('SyncOrchestrator: drained delete for $id',
                tag: 'Sync');
          }
        } catch (e) {
          AppLogger.warning(
            'SyncOrchestrator: pending delete failed for $id — $e',
            tag: 'Sync',
          );
        }
      }
    } catch (e, st) {
      AppLogger.error('SyncOrchestrator: run failed', tag: 'Sync', error: e, stackTrace: st);
    } finally {
      _running = false;
    }
    return uploaded;
  }

  /// Push a single scan to the cloud now — used by the capture flow to
  /// upload the freshly captured row before the user can navigate (or
  /// log out) and lose it. Returns true on success and writes the
  /// follow-up bookkeeping (`markUploaded`, activity-log entry).
  ///
  /// No-ops when the session is gone or cloud sync is disabled. Does NOT
  /// take the running-lock — safe to call concurrently with [syncNow].
  Future<bool> uploadOne(LesionAnalysis analysis) async {
    if (!cloudSyncEnabledReader()) return false;
    final token = tokenReader();
    if (token == null) return false;

    final ok = await _doUpload(analysis, token);
    if (ok) {
      await repository.markUploaded(analysis.id);
      notifications?.recordScanSyncedToCloud(scanId: analysis.id);
    }
    return ok;
  }

  Future<bool> _doUpload(LesionAnalysis analysis, String token) async {
    try {
      final fullRecord = await _loadWithImage(analysis.id);
      if (fullRecord == null) return false;

      final risk = _riskSlugFor(analysis);
      final payload = api.toCreatePayload(
        fullRecord,
        bodyRegionSlug: _bodyRegionSlug(fullRecord.bodyRegion),
        bodyPartLabel: fullRecord.bodyRegion,
        riskLevelSlug: risk,
        relativePositionX:
            _autoPositionX(fullRecord.bodyRegion, fullRecord.id),
        relativePositionY:
            _autoPositionY(fullRecord.bodyRegion, fullRecord.id),
        hasImage: fullRecord.imageBytes != null && fullRecord.imageBytes!.isNotEmpty,
      );
      final created = await api.createScan(token: token, payload: payload);

      if (created.uploadUrl != null && fullRecord.imageBytes != null) {
        final uploaded = await api.uploadImage(
          uploadUrl: created.uploadUrl!,
          bytes: fullRecord.imageBytes!,
        );
        if (!uploaded) return false;
        if (created.objectPath != null) {
          await api.confirmImageUpload(
            token: token,
            scanId: analysis.id,
            objectPath: created.objectPath!,
          );
        }
      }
      AppLogger.info('SyncOrchestrator: uploaded ${analysis.id}', tag: 'Sync');
      return true;
    } catch (e, st) {
      AppLogger.warning(
        'SyncOrchestrator: upload failed for ${analysis.id} — $e',
        tag: 'Sync',
      );
      if (kDebugMode) debugPrint('$st');
      return false;
    }
  }

  Future<LesionAnalysis?> _loadWithImage(String id) async {
    return repository.findById(id, includeImage: true);
  }

  String _riskSlugFor(LesionAnalysis a) {
    switch (a.result.warningLevel.name) {
      case 'alert':
        return 'high';
      case 'caution':
        return 'medium';
      case 'reassuring':
      default:
        return 'low';
    }
  }

  String? _bodyRegionSlug(String? label) {
    if (label == null) return null;
    final l = label.toLowerCase();
    if (l.contains('head') || l.contains('scalp') || l.contains('cheek')) return 'head';
    if (l.contains('neck')) return 'neck';
    if (l.contains('chest') || l.contains('thorax')) return 'chest';
    if (l.contains('abdomen') || l.contains('belly')) return 'abdomen';
    if (l.contains('back')) return 'back';
    if (l.contains('left arm') || l.contains('left forearm') ||
        l.contains('left shoulder') || l.contains('left elbow')) {
      return 'leftArm';
    }
    if (l.contains('right arm') || l.contains('right forearm') ||
        l.contains('right shoulder') || l.contains('right elbow')) {
      return 'rightArm';
    }
    if (l.contains('left leg') || l.contains('left thigh') || l.contains('left calf')) {
      return 'leftLeg';
    }
    if (l.contains('right leg') || l.contains('right thigh') || l.contains('right calf')) {
      return 'rightLeg';
    }
    return null;
  }

  // Distribute moles along the limb instead of stacking them at the
  // anatomical centroid. The scatter is seeded off the (stable) scan id so
  // the same scan ALWAYS lands at the same dot — both before sync (local
  // projection) and after (cloud read), and across re-syncs when the user
  // re-tags. Coordinates are normalized against the 58×165 silhouette grid
  // the body map renders against.
  double? _autoPositionX(String? label, String scanId) {
    final region = _bodyRegionSlug(label);
    if (region == null) return null;
    final seed = scanId.hashCode;
    switch (region) {
      case 'head':
        return 23 / 58;
      case 'neck':
        return 26 / 58;
      case 'chest':
      case 'abdomen':
      case 'back':
        return 28 / 58;
      case 'leftArm':
        return _scatter(8, 14, seed) / 58;
      case 'rightArm':
        return _scatter(44, 50, seed) / 58;
      case 'leftLeg':
        return _scatter(20, 26, seed) / 58;
      case 'rightLeg':
        return _scatter(34, 40, seed) / 58;
    }
    return null;
  }

  double? _autoPositionY(String? label, String scanId) {
    final region = _bodyRegionSlug(label);
    if (region == null) return null;
    // Decorrelate the Y seed from X so dots don't fall on a diagonal.
    final seed = scanId.hashCode ^ 0x9E3779B9;
    switch (region) {
      case 'head':
        return 18 / 165;
      case 'neck':
        return 30 / 165;
      case 'chest':
        return _scatter(40, 60, seed).toDouble() / 165;
      case 'abdomen':
        return _scatter(60, 78, seed).toDouble() / 165;
      case 'back':
        return _scatter(40, 78, seed).toDouble() / 165;
      case 'leftArm':
      case 'rightArm':
        return _scatter(45, 90, seed).toDouble() / 165;
      case 'leftLeg':
      case 'rightLeg':
        return _scatter(95, 145, seed).toDouble() / 165;
    }
    return null;
  }

  int _scatter(int low, int high, int seed) {
    final range = high - low;
    if (range <= 0) return low;
    return low + (seed.abs() % range);
  }

  bool _isOnline(ConnectivityResult r) =>
      r == ConnectivityResult.wifi ||
      r == ConnectivityResult.mobile ||
      r == ConnectivityResult.ethernet ||
      r == ConnectivityResult.vpn;
}

final scansApiProvider = Provider<ScansApi>((ref) {
  final api = ScansApi();
  ref.onDispose(api.dispose);
  return api;
});

final syncOrchestratorProvider = Provider<SyncOrchestrator>((ref) {
  final orchestrator = SyncOrchestrator(
    repository: ref.watch(lesionRepositoryProvider),
    api: ref.watch(scansApiProvider),
    tokenReader: () => ref.read(authControllerProvider).token?.value,
    patientIdReader: () => ref.read(authControllerProvider).user?.id,
    cloudSyncEnabledReader: () =>
        ref.read(privacySettingsProvider).cloudSyncEnabled,
    notifications: ref.read(notificationsControllerProvider.notifier),
  );
  ref.onDispose(orchestrator.stop);
  return orchestrator;
});

/// Pending upload counter — surfaces the "pending sync" badge on the home
/// dashboard so the user knows their offline scans are queued. Watches
/// the auth state so the badge resets to zero on sign-out and rebinds to
/// the new user's queue after a fresh login.
final pendingScanCountProvider = FutureProvider<int>((ref) async {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) return 0;
  final repo = ref.watch(lesionRepositoryProvider);
  if (repo is SecureLesionRepository) {
    await repo.initialize();
  }
  final pending = await repo.findPendingUpload(user.id);
  return pending.length;
});
