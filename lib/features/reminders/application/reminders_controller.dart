import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/notifications/notifications_controller.dart';
import '../../auth/application/auth_controller.dart' show sharedPreferencesProvider;
import '../domain/reminder.dart';
import '../infrastructure/local_notification_service.dart';
import '../infrastructure/reminders_storage.dart';

/// Owns the in-memory list of [Reminder]s + the OS notification scheduler.
///
/// CRUD methods write through both [RemindersStorage] (persistent) and
/// [LocalNotificationService] (system alarms). [reconcile] is invoked at
/// app start: walks every reminder whose `scheduledAt` is in the past,
/// records it in the in-app activity log, and either marks one-time
/// fired or rolls recurring slots forward by their interval.
class RemindersController extends StateNotifier<List<Reminder>> {
  RemindersController({
    required this.storage,
    required this.scheduler,
    required this.notifications,
  }) : super(storage.readAll()) {
    // Reconcile asynchronously so app startup isn't blocked. Any past-due
    // reminders surface in the activity log within the first second.
    Future.microtask(reconcile);
    // Tick once per minute so a reminder that fires while the user has
    // the app in foreground surfaces an in-app banner alongside the OS
    // notification (reconcile records fired reminders → the
    // NotificationsController emits on its banner stream → the host
    // overlay slides the card down).
    //
    // 1-min granularity is intentional — reminders are not second-
    // critical and shorter intervals would burn battery without UX gain.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => reconcile());
  }

  final RemindersStorage storage;
  final LocalNotificationService scheduler;
  final NotificationsController notifications;
  final Uuid _uuid = const Uuid();
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    _tick = null;
    super.dispose();
  }

  // ── Read helpers ────────────────────────────────────────────────────

  /// Earliest *future* reminder, regardless of type. Drives the profile
  /// "Next Checkup" tile.
  Reminder? get nextUpcoming {
    final now = DateTime.now();
    final upcoming = state.where((r) => r.scheduledAt.isAfter(now)).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  // ── CRUD ────────────────────────────────────────────────────────────

  Future<Reminder> create({
    required ReminderType type,
    required DateTime scheduledAt,
    required ReminderRepeat repeat,
    String? scanId,
    String? title,
    String? note,
  }) async {
    final reminder = Reminder(
      id: _uuid.v4(),
      type: type,
      scanId: scanId,
      scheduledAt: scheduledAt,
      repeat: repeat,
      title: title ?? _defaultTitle(type, scanId: scanId),
      note: note,
      createdAt: DateTime.now(),
    );
    state = [...state, reminder];
    await storage.writeAll(state);
    // Make sure POST_NOTIFICATIONS and (on Android 12+) SCHEDULE_EXACT_ALARM
    // are granted BEFORE we hand the alarm to the OS. Without this the
    // schedule call throws `exact_alarms_not_permitted` and the scheduler
    // catches it silently — which is exactly the symptom the user hit:
    // the reminder list shows the entry but no notification ever fires.
    //
    // `requestPermissions` is idempotent: it's a no-op the second time.
    // We don't gate `schedule` on the boolean because the scheduler now
    // falls back to inexact mode when exact is denied — better an
    // imprecise notification than none at all.
    await scheduler.requestPermissions();
    await scheduler.schedule(reminder);
    notifications.recordReminderCheckup(at: scheduledAt);
    AppLogger.info('Reminder created: ${reminder.id}', tag: 'Reminders');
    return reminder;
  }

  Future<void> update(Reminder updated) async {
    state = state.map((r) => r.id == updated.id ? updated : r).toList();
    await storage.writeAll(state);
    await scheduler.schedule(updated);
  }

  Future<void> remove(String id) async {
    final target = state.firstWhere(
      (r) => r.id == id,
      orElse: () => throw StateError('reminder not found'),
    );
    state = state.where((r) => r.id != id).toList();
    await storage.writeAll(state);
    await scheduler.cancel(target.notificationId);
  }

  /// Cancels every reminder whose ``scanId`` matches the deleted scan.
  /// Called from the triage delete flow so a removed lunar doesn't
  /// leave dangling alarms that would crash on tap.
  Future<void> removeForScan(String scanId) async {
    final orphans = state.where((r) => r.scanId == scanId).toList();
    if (orphans.isEmpty) return;
    state = state.where((r) => r.scanId != scanId).toList();
    await storage.writeAll(state);
    for (final r in orphans) {
      await scheduler.cancel(r.notificationId);
    }
    AppLogger.info(
      'Cancelled ${orphans.length} reminder(s) tied to scan $scanId',
      tag: 'Reminders',
    );
  }

  // ── Reconciliation ─────────────────────────────────────────────────

  /// Walks past-due reminders, surfaces them in the activity log and,
  /// for recurring slots, advances ``scheduledAt`` to the next valid
  /// occurrence and re-schedules the OS alarm.
  Future<void> reconcile() async {
    final now = DateTime.now();
    final next = <Reminder>[];
    var changed = false;

    for (final r in state) {
      if (r.fired || r.scheduledAt.isAfter(now)) {
        next.add(r);
        continue;
      }

      // Past-due: record + advance/mark fired.
      _recordFired(r);
      changed = true;

      switch (r.repeat) {
        case ReminderRepeat.none:
          next.add(r.copyWith(fired: true));
        case ReminderRepeat.monthly:
          final advanced = r.copyWith(
            scheduledAt: _advance(r.scheduledAt, months: 1, now: now),
          );
          await scheduler.schedule(advanced);
          next.add(advanced);
        case ReminderRepeat.quarterly:
          final advanced = r.copyWith(
            scheduledAt: _advance(r.scheduledAt, months: 3, now: now),
          );
          await scheduler.schedule(advanced);
          next.add(advanced);
      }
    }

    if (changed) {
      state = next;
      await storage.writeAll(state);
    }
  }

  /// Roll the scheduledAt forward by [months] until it lies in the future.
  /// Required because a phone left off for several months would otherwise
  /// dump dozens of "fired" entries into the activity log on reboot.
  DateTime _advance(DateTime from, {required int months, required DateTime now}) {
    var candidate = DateTime(
      from.year,
      from.month + months,
      from.day,
      from.hour,
      from.minute,
    );
    while (!candidate.isAfter(now)) {
      candidate = DateTime(
        candidate.year,
        candidate.month + months,
        candidate.day,
        candidate.hour,
        candidate.minute,
      );
    }
    return candidate;
  }

  void _recordFired(Reminder r) {
    notifications.recordReminderFired(reminder: r);
  }

  String _defaultTitle(ReminderType type, {String? scanId}) {
    switch (type) {
      case ReminderType.newScan:
        return 'Scan a new mole';
      case ReminderType.rescan:
        return 'Re-scan a previous mole';
      case ReminderType.selfExamination:
        return 'Self-examination';
    }
  }
}

final localNotificationServiceProvider =
    Provider<LocalNotificationService>((ref) {
  return LocalNotificationService();
});

final remindersStorageProvider = Provider<RemindersStorage>((ref) {
  return RemindersStorage(ref.watch(sharedPreferencesProvider));
});

final remindersControllerProvider =
    StateNotifierProvider<RemindersController, List<Reminder>>((ref) {
  return RemindersController(
    storage: ref.watch(remindersStorageProvider),
    scheduler: ref.watch(localNotificationServiceProvider),
    notifications: ref.read(notificationsControllerProvider.notifier),
  );
});
