import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/localization/locale_controller.dart';
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
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    // Try exact (best-aligned to the user's chosen time). If the user
    // never granted SCHEDULE_EXACT_ALARM — the OS throws
    // `exact_alarms_not_permitted` on Android 12+ — we fall back to the
    // inexact-while-idle mode so the notification still fires, just
    // within the OS's batching window (~15 min in Doze). Before today
    // that exception used to be caught by the outer try/catch and the
    // alarm vanished silently; the reminder looked saved but the OS
    // never had it.
    Future<void> attempt(AndroidScheduleMode mode) {
      return _plugin.zonedSchedule(
        reminder.notificationId,
        // H08: default titles are stored as English keys; translate at
        // schedule time so the tray notification follows the UI language.
        reminder.title.tr,
        body,
        scheduled,
        details,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: reminder.id,
      );
    }

    try {
      await attempt(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (e) {
      if (e.code == 'exact_alarms_not_permitted') {
        AppLogger.warning(
          'Exact alarms denied for reminder ${reminder.id} — falling back '
          'to inexactAllowWhileIdle. The notification will still fire, '
          'just within the OS doze batching window.',
          tag: 'LocalNotif',
        );
        try {
          await attempt(AndroidScheduleMode.inexactAllowWhileIdle);
        } catch (e2, st2) {
          AppLogger.warning(
            'Inexact fallback also failed for ${reminder.id}: $e2',
            tag: 'LocalNotif',
          );
          if (kDebugMode) debugPrint('$st2');
        }
      } else {
        AppLogger.warning(
          'Failed to schedule reminder ${reminder.id}: $e',
          tag: 'LocalNotif',
        );
      }
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
        return 'Time to capture a new lesion in skeen.'.tr;
      case ReminderType.rescan:
        return 'Re-scan the lesion you wanted to monitor.'.tr;
      case ReminderType.selfExamination:
        return 'Take five minutes for a head-to-toe self-examination.'.tr;
    }
  }
}
