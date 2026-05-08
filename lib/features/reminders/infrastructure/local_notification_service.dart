import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/logger/app_logger.dart';
import '../domain/reminder.dart';

/// Thin facade over `flutter_local_notifications`. Handles plugin init,
/// timezone bootstrap, permission requests, and scheduling/cancelling
/// OS-level alarms tied to [Reminder] ids.
class LocalNotificationService {
  static const _channelId = 'skeen.reminders';
  static const _channelName = 'Reminders';
  static const _channelDescription =
      'Scheduled reminders for skin scans and self-examinations.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize({
    void Function(int, String?)? onTap,
  }) async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (e) {
      AppLogger.warning(
        'Could not detect local timezone — falling back to UTC: $e',
        tag: 'LocalNotif',
      );
      tz.setLocalLocation(tz.UTC);
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (resp) {
        if (onTap == null) return;
        onTap(resp.id ?? 0, resp.payload);
      },
    );
    _initialized = true;
  }

  /// Asks the OS for permission to fire alarms. Idempotent. Returns
  /// `true` when granted (or already granted).
  Future<bool> requestPermissions() async {
    final notifResult = await Permission.notification.request();
    final granted = notifResult.isGranted ||
        notifResult.isLimited ||
        notifResult.isProvisional;
    if (!granted) return false;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestExactAlarmsPermission();
      await android?.requestNotificationsPermission();
    }
    return true;
  }

  Future<bool> isPermissionGranted() async {
    final status = await Permission.notification.status;
    return status.isGranted ||
        status.isLimited ||
        status.isProvisional;
  }

  /// Schedules an OS notification at [reminder.scheduledAt]. Replaces any
  /// existing schedule for the same id (cancels first). Recurring slots
  /// schedule only the *next* occurrence — the controller advances after
  /// each fire (see [RemindersController.reconcile]).
  Future<void> schedule(Reminder reminder) async {
    if (!_initialized) await initialize();
    await _plugin.cancel(reminder.notificationId);
    if (reminder.scheduledAt.isBefore(DateTime.now()) && !reminder.fired) {
      // Past-due: don't bother the OS — the controller will reconcile on
      // boot and either record + reschedule (recurring) or mark fired.
      return;
    }

    final scheduled = tz.TZDateTime.from(reminder.scheduledAt, tz.local);
    final body = _bodyFor(reminder);

    try {
      await _plugin.zonedSchedule(
        reminder.notificationId,
        reminder.title,
        body,
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: reminder.id,
      );
    } catch (e, st) {
      AppLogger.warning(
        'Failed to schedule reminder ${reminder.id}: $e',
        tag: 'LocalNotif',
      );
      if (kDebugMode) debugPrint('$st');
    }
  }

  Future<void> cancel(int notificationId) async {
    await _plugin.cancel(notificationId);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  String _bodyFor(Reminder r) {
    switch (r.type) {
      case ReminderType.newScan:
        return 'Time to capture a new lesion in skeen.';
      case ReminderType.rescan:
        return 'Re-scan the lesion you wanted to monitor.';
      case ReminderType.selfExamination:
        return 'Take five minutes for a head-to-toe self-examination.';
    }
  }
}
