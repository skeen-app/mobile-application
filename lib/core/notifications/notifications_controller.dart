import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/application/auth_controller.dart'
    show sharedPreferencesProvider;
import '../../features/reminders/domain/reminder.dart';
import 'notification_entity.dart';
import 'notifications_storage.dart';

/// Snapshot of the activity log for the UI. Items are always sorted
/// newest-first.
@immutable
class NotificationsState {
  const NotificationsState({
    required this.items,
  });

  final List<NotificationEntity> items;

  int get unreadCount => items.where((e) => !e.isRead).length;

  static const NotificationsState empty = NotificationsState(items: []);
}

/// Centralised activity recorder.
///
/// Each `recordX` method appends a new [NotificationEntity], trims the
/// list to [NotificationsStorage.maxItems] (FIFO), persists, and pushes
/// the new entity onto [bannerStream] so the in-app banner host can
/// surface it on top of whatever screen the user happens to be on.
class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(this._storage)
      : super(NotificationsState(items: _storage.readAll()));

  final NotificationsStorage _storage;
  final Uuid _uuid = const Uuid();

  final StreamController<NotificationEntity> _bannerController =
      StreamController<NotificationEntity>.broadcast();

  /// Stream of *freshly recorded* entities. The host widget listens to
  /// this and slides the banner in. Note: pre-existing rows hydrated from
  /// storage do NOT replay on this stream — only new ones.
  Stream<NotificationEntity> get bannerStream => _bannerController.stream;

  // ── Recording API ────────────────────────────────────────────────────

  void recordPasswordChanged() {
    _push(
      type: NotificationType.passwordChanged,
      title: 'Password reset requested',
      subtitle: "We've sent reset instructions to your email.",
    );
  }

  void recordScanCompleted({
    required String scanId,
    String? bodyRegion,
  }) {
    _push(
      type: NotificationType.scanCompleted,
      title: 'Scan saved',
      subtitle: bodyRegion != null
          ? 'Captured a new lesion on your $bodyRegion.'
          : 'A new lesion was captured.',
      payload: {'scanId': scanId},
    );
  }

  void recordPredictionReady({
    required String scanId,
    required String label,
    required double confidence,
  }) {
    final pct = (confidence * 100).clamp(0, 100).toStringAsFixed(0);
    _push(
      type: NotificationType.predictionReady,
      title: 'Prediction ready',
      subtitle: '$label · $pct% confidence',
      payload: {'scanId': scanId},
    );
  }

  void recordHighRiskDetected({
    required String scanId,
    required String label,
    required double confidence,
  }) {
    final pct = (confidence * 100).clamp(0, 100).toStringAsFixed(0);
    _push(
      type: NotificationType.highRiskDetected,
      title: 'High-risk pattern detected',
      subtitle: '$label · $pct%. Clinical review recommended.',
      payload: {'scanId': scanId},
    );
  }

  void recordProfileEdited({required List<String> fields}) {
    final pretty = fields.map(_humaniseField).toList();
    final summary = pretty.length <= 1
        ? pretty.join('')
        : '${pretty.take(pretty.length - 1).join(', ')} and ${pretty.last}';
    _push(
      type: NotificationType.profileEdited,
      title: 'Profile updated',
      subtitle: pretty.isEmpty ? null : 'Changed $summary.',
    );
  }

  void recordAvatarUpdated() {
    _push(
      type: NotificationType.avatarUpdated,
      title: 'Profile photo updated',
      subtitle: 'Your new avatar is now live.',
    );
  }

  void recordScanSyncedToCloud({required String scanId}) {
    _push(
      type: NotificationType.scanSyncedToCloud,
      title: 'Scan backed up',
      subtitle: 'Your scan was uploaded to your private cloud.',
      payload: {'scanId': scanId},
    );
  }

  void recordScanDeleted({String? bodyRegion, bool pendingCloudDelete = false}) {
    _push(
      type: NotificationType.scanSyncedToCloud,
      title: pendingCloudDelete
          ? 'Scan deletion queued'
          : 'Scan deleted',
      subtitle: pendingCloudDelete
          ? 'The cloud copy will be removed once you are back online.'
          : (bodyRegion == null
              ? 'The scan was permanently removed.'
              : 'Removed the lesion on your $bodyRegion.'),
    );
  }

  /// Reserved for the OTA pipeline — wired but not currently triggered.
  /// Surface it from the OTA orchestration layer when it lands.
  void recordModelUpdateInstalled({required String version}) {
    _push(
      type: NotificationType.modelUpdateInstalled,
      title: 'AI model updated',
      subtitle: 'Version $version is now active on your device.',
    );
  }

  void recordReminderCheckup({required DateTime at}) {
    _push(
      type: NotificationType.reminderCheckup,
      title: 'Checkup reminder set',
      subtitle: 'You will be nudged to scan around this date.',
    );
  }

  /// Surfaced when a scheduled reminder actually *fires* (post-reconcile
  /// at app boot, or via the OS notification-tap callback). Distinct copy
  /// from "reminder set" so the activity log reads as a real event.
  void recordReminderFired({required Reminder reminder}) {
    final title = switch (reminder.type) {
      ReminderType.newScan => 'Time to scan a new mole',
      ReminderType.rescan => 'Time to re-scan your mole',
      ReminderType.selfExamination => 'Time for a self-examination',
    };
    _push(
      type: NotificationType.reminderCheckup,
      title: title,
      subtitle: reminder.note,
      payload: {
        if (reminder.scanId != null) 'scanId': reminder.scanId!,
      },
    );
  }

  // ── Read-state / lifecycle ───────────────────────────────────────────

  Future<void> markAllRead() async {
    if (state.items.every((e) => e.isRead)) return;
    final next = state.items.map((e) => e.markRead()).toList(growable: false);
    state = NotificationsState(items: next);
    await _storage.writeAll(next);
  }

  Future<void> remove(String id) async {
    final next = state.items.where((e) => e.id != id).toList(growable: false);
    if (next.length == state.items.length) return;
    state = NotificationsState(items: next);
    await _storage.writeAll(next);
  }

  Future<void> clearAll() async {
    state = NotificationsState.empty;
    await _storage.clear();
  }

  // ── Internals ────────────────────────────────────────────────────────

  void _push({
    required NotificationType type,
    required String title,
    String? subtitle,
    Map<String, dynamic> payload = const {},
  }) {
    final entity = NotificationEntity(
      id: _uuid.v4(),
      type: type,
      title: title,
      subtitle: subtitle,
      createdAt: DateTime.now(),
      payload: payload,
    );
    final merged = <NotificationEntity>[entity, ...state.items];
    final trimmed = merged.length > NotificationsStorage.maxItems
        ? merged.sublist(0, NotificationsStorage.maxItems)
        : merged;
    state = NotificationsState(items: trimmed);
    // Persist async — fire and forget. Even if the write fails the
    // in-memory state already reflects the change so the UI stays
    // consistent for this session.
    unawaited(_storage.writeAll(trimmed));
    if (!_bannerController.isClosed) {
      _bannerController.add(entity);
    }
  }

  String _humaniseField(String raw) {
    switch (raw) {
      case 'name':
        return 'first name';
      case 'lastName':
        return 'last name';
      case 'phone':
        return 'phone';
      default:
        return raw;
    }
  }

  @override
  void dispose() {
    _bannerController.close();
    super.dispose();
  }
}

final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return NotificationsController(NotificationsStorage(prefs));
});

/// Convenience accessors so callsites don't need to read the provider
/// twice or import the controller class.
extension NotificationsRefShortcut on Ref {
  NotificationsController get notifications =>
      read(notificationsControllerProvider.notifier);
}

extension NotificationsWidgetRefShortcut on WidgetRef {
  NotificationsController get notifications =>
      read(notificationsControllerProvider.notifier);
}
