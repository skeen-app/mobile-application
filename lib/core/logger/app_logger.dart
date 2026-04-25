import 'dart:developer' as developer;

/// A simple, globally accessible terminal logger utility.
/// Uses `dart:developer`'s log function so output appears neatly in IDE
/// consoles without polluting standard stdout excessively.
class AppLogger {
  const AppLogger._();

  static void info(String message, {String? tag}) {
    developer.log(
      '[INFO] $message',
      name: tag ?? 'SkeenApp',
      level: 800, // INFO level
      time: DateTime.now(),
    );
  }

  static void warning(String message, {String? tag}) {
    developer.log(
      '[WARNING] $message',
      name: tag ?? 'SkeenApp',
      level: 900, // WARNING level
      time: DateTime.now(),
    );
  }

  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      '[ERROR] $message',
      name: tag ?? 'SkeenApp',
      level: 1000, // SEVERE level
      time: DateTime.now(),
      error: error,
      stackTrace: stackTrace,
    );
  }
}
