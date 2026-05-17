import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translations.dart';

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale>((ref) {
  return LocaleController();
});

class LocaleController extends StateNotifier<Locale> {
  LocaleController() : super(Locale('es')) {
    _init();
  }

  static LocaleController? _instance;
  static LocaleController get instance => _instance!;

  Future<void> _init() async {
    _instance = this;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('languageCode');
    if (saved != null) {
      state = Locale(saved);
    } else {
      final osLocale = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      if (osLocale == 'en') {
        state = Locale('en');
        await prefs.setString('languageCode', 'en');
      } else {
        state = Locale('es');
        await prefs.setString('languageCode', 'es');
      }
    }
  }

  Future<void> toggleLanguage() async {
    final newLocale = state.languageCode == 'en' ? Locale('es') : Locale('en');
    state = newLocale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', newLocale.languageCode);
  }

  String translate(String key) {
    final map = state.languageCode == 'en' ? enTranslations : esTranslations;
    // If the exact key is not found, return the original key so the UI doesn't break
    return map[key] ?? key;
  }
}

extension StringTranslationExt on String {
  /// Translates the string based on the current active locale.
  String get tr {
    try {
      return LocaleController.instance.translate(this);
    } catch (_) {
      return this;
    }
  }
}
