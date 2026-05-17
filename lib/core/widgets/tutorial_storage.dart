import 'package:shared_preferences/shared_preferences.dart';

/// Thin SharedPreferences wrapper — tracks whether the post-registration
/// tutorial has been completed (or skipped) so it only shows once per user.
class TutorialStorage {
  TutorialStorage._();

  static const _prefix = 'tutorial_completed_';

  /// Returns `true` if the tutorial was already shown for [userId].
  static Future<bool> isCompleted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$userId') ?? false;
  }

  /// Persists the tutorial as done for [userId] — will not show again
  /// for this account, but a fresh registration will see it.
  static Future<void> markCompleted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$userId', true);
  }
}
