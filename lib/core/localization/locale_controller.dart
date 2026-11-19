import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
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

  /// Public read of the active language code (`es` / `en`) for code
  /// outside the widget tree (PDF builder, notification payloads).
  String get languageCode => state.languageCode;

  String translate(String key) {
    final map = state.languageCode == 'en' ? enTranslations : esTranslations;
    // If the exact key is not found, return the original key so the UI doesn't break
    return map[key] ?? key;
  }
}

/// Active language code, falling back to Spanish (the app default) when
/// the controller has not been created yet.
String currentLanguageCode() {
  try {
    return LocaleController.instance.languageCode;
  } catch (_) {
    return 'es';
  }
}

/// H08: dates follow the active UI language ("16 de noviembre de 2026" /
/// "November 16, 2026"). Falls back to ISO-like text if the intl symbols
/// for the locale are not loaded.
String formatLongDate(DateTime at) {
  try {
    return DateFormat.yMMMMd(currentLanguageCode()).format(at);
  } catch (_) {
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-'
        '${at.day.toString().padLeft(2, '0')}';
  }
}

/// Abbreviated date ("16 nov 2026" / "Nov 16, 2026").
String formatShortDate(DateTime at) {
  try {
    return DateFormat.yMMMd(currentLanguageCode()).format(at);
  } catch (_) {
    return formatLongDate(at);
  }
}

/// Short month + year header ("noviembre 2026" / "November 2026").
String formatMonthYear(DateTime at) {
  try {
    return DateFormat.yMMMM(currentLanguageCode()).format(at);
  } catch (_) {
    return '${at.year}-${at.month.toString().padLeft(2, '0')}';
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
