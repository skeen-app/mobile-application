import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/auth_failure.dart';
import '../domain/login_request.dart';
import '../domain/registered_user.dart';
import '../domain/registration_request.dart';
import '../infrastructure/auth_api.dart';
import '../infrastructure/token_storage.dart';
import 'auth_state.dart';

/// Must be overridden in `main.dart` after `SharedPreferences.getInstance()`.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a resolved instance.',
  );
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(ref.watch(sharedPreferencesProvider));
});

final authApiProvider = Provider<AuthApi>((ref) {
  final api = AuthApi();
  ref.onDispose(api.dispose);
  return api;
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    api: ref.watch(authApiProvider),
    storage: ref.watch(tokenStorageProvider),
  )..hydrate();
});

class AuthController extends StateNotifier<AuthState> {
  AuthController({required AuthApi api, required TokenStorage storage})
      : _api = api,
        _storage = storage,
        super(const AuthState.idle());

  final AuthApi _api;
  final TokenStorage _storage;

  void hydrate() {
    final token = _storage.readToken();
    final user = _storage.readUser();
    if (token != null) {
      state = AuthState(
        status: AuthStatus.authenticated,
        token: token,
        user: user,
      );
    }
  }

  Future<bool> register(RegistrationRequest request) async {
    state = state.copyWith(status: AuthStatus.submitting);
    try {
      final response = await _api.register(request);
      final user =
          response.user ??
          RegisteredUser(
            id: 'local',
            name: request.name.trim(),
            lastName: request.lastName.trim(),
            dni: request.dni,
            email: request.email.trim(),
            phone: request.phone,
          );

      await _storage.saveToken(response.token);
      await _storage.saveUser(user);

      state = AuthState(
        status: AuthStatus.authenticated,
        token: response.token,
        user: user,
      );
      return true;
    } on AuthFailure catch (failure) {
      state = state.copyWith(status: AuthStatus.failure, failure: failure);
      return false;
    } catch (_) {
      state = state.copyWith(
        status: AuthStatus.failure,
        failure: const NetworkFailure(),
      );
      return false;
    }
  }

  Future<bool> login(LoginRequest request) async {
    state = state.copyWith(status: AuthStatus.submitting);
    try {
      final response = await _api.login(request);
      await _storage.saveToken(response.token);
      if (response.user != null) {
        await _storage.saveUser(response.user!);
      }
      state = AuthState(
        status: AuthStatus.authenticated,
        token: response.token,
        user: response.user ?? _storage.readUser(),
      );
      return true;
    } on AuthFailure catch (failure) {
      state = state.copyWith(status: AuthStatus.failure, failure: failure);
      return false;
    } catch (_) {
      state = state.copyWith(
        status: AuthStatus.failure,
        failure: const NetworkFailure(),
      );
      return false;
    }
  }

  /// Local-first logout: invokes the (placeholder) backend revoke, then
  /// always clears persisted credentials so the device returns to anon state.
  Future<void> signOut() async {
    final token = state.token;
    if (token != null) {
      await _api.logout(token: token);
    }
    await _storage.clear();
    state = const AuthState.idle();
  }
}
