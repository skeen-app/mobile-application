import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'notification_entity.dart';

/// SharedPreferences-backed persistence for the in-app activity log.
///
/// Stores a JSON array of [NotificationEntity], capped at [maxItems] (FIFO
/// — the oldest is dropped when the cap is hit). Reads return newest-first
/// so the UI can render directly.
class NotificationsStorage {
  NotificationsStorage(this._prefs);

  static const _kStorageKey = 'core.notifications.v1';
  static const int maxItems = 20;

  final SharedPreferences _prefs;

  List<NotificationEntity> readAll() {
    final raw = _prefs.getString(_kStorageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => NotificationEntity.fromJson(m.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeAll(List<NotificationEntity> items) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_kStorageKey, encoded);
  }

  Future<void> clear() async {
    await _prefs.remove(_kStorageKey);
  }
}
