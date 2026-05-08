import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_controller.dart' show sharedPreferencesProvider;

/// Per-device privacy preferences. Today only one knob: cloud sync of
/// captured lesion scans.
///
/// Default is **opt-in ON** — the user is told what it does up-front in
/// the privacy & security screen and can flip it off any time. When OFF,
/// the scan still saves locally (encrypted) but never uploads.
class PrivacySettings {
  const PrivacySettings({required this.cloudSyncEnabled});

  final bool cloudSyncEnabled;

  PrivacySettings copyWith({bool? cloudSyncEnabled}) =>
      PrivacySettings(cloudSyncEnabled: cloudSyncEnabled ?? this.cloudSyncEnabled);

  static const PrivacySettings defaults =
      PrivacySettings(cloudSyncEnabled: true);
}

class PrivacySettingsController extends StateNotifier<PrivacySettings> {
  PrivacySettingsController(this._prefs) : super(PrivacySettings.defaults) {
    _hydrate();
  }

  final SharedPreferences _prefs;
  static const _kCloudSync = 'privacy.cloud_sync_enabled';

  void _hydrate() {
    final stored = _prefs.getBool(_kCloudSync);
    if (stored != null) {
      state = state.copyWith(cloudSyncEnabled: stored);
    }
  }

  Future<void> setCloudSyncEnabled(bool value) async {
    state = state.copyWith(cloudSyncEnabled: value);
    await _prefs.setBool(_kCloudSync, value);
  }
}

final privacySettingsProvider =
    StateNotifierProvider<PrivacySettingsController, PrivacySettings>((ref) {
  return PrivacySettingsController(ref.watch(sharedPreferencesProvider));
});
