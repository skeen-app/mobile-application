import 'package:shared_preferences/shared_preferences.dart';

/// Thin SharedPreferences wrapper — tracks whether the post-registration
/// tutorial has been completed (or skipped) so it only shows once.
class TutorialStorage {
  TutorialStorage._();

  static const _key = 'tutorial_completed';

  /// Returns `true` if the tutorial was already shown on this device.
  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  /// Persists the tutorial as done — will not show again.
  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
