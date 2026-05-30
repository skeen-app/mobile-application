/// Centralized API configuration shared by all infrastructure services.
///
/// The base URL is injected at build time via `--dart-define-from-file`.
/// Two env files ship with the repo:
///
///   • `env.json`        — committed, points at the production Cloud Run.
///   • `env.local.json`  — gitignored, optional per-machine override
///                         (Android emulator → `http://10.0.2.2:8000/api/v1`).
///
/// How to run:
///   ```
///   flutter run --dart-define-from-file=env.json         # prod backend
///   flutter run --dart-define-from-file=env.local.json   # local backend
///   ```
///
/// VSCode users get this for free via `.vscode/launch.json` (pick the
/// "skeen (dev — env.local.json)" or "skeen (prod — env.json)" config
/// from   the Run-and-Debug panel).
///
/// If `SKEEN_API_URL` is missing at build time the default falls back to
/// `http://localhost:8000/api/v1` so the failure surfaces immediately as
/// a connection error on first request instead of silently shipping the
/// prod URL into every build.
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'SKEEN_API_URL',
    defaultValue: 'http://localhost:8000/api/v1',
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
