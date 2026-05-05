/// Centralized API configuration shared by all infrastructure services.
///
/// The base URL is overrideable at build time via `--dart-define=SKEEN_API_URL=...`.
/// Notes for local development:
///  - Android emulator → use `http://10.0.2.2:8000/api/v1`
///  - iOS simulator / Web / desktop → `http://localhost:8000/api/v1` works
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'SKEEN_API_URL',
    defaultValue: 'http://192.168.1.55:8000/api/v1',
  );

  static Uri uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized');
  }

  static const Duration defaultTimeout = Duration(seconds: 15);

  static const Map<String, String> jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
}
