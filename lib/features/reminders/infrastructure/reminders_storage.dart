import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/reminder.dart';

/// SharedPreferences-backed JSON list. We don't bother with SQLite — the
/// realistic upper bound here is a handful of recurring slots.
class RemindersStorage {
  RemindersStorage(this._prefs);

  static const _kKey = 'reminders.v1';
  final SharedPreferences _prefs;

  List<Reminder> readAll() {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => Reminder.fromJson(m.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeAll(List<Reminder> items) async {
    final encoded = jsonEncode(items.map((r) => r.toJson()).toList());
    await _prefs.setString(_kKey, encoded);
  }

  Future<void> clear() async {
    await _prefs.remove(_kKey);
  }
}
