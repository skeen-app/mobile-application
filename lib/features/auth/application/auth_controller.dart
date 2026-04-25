import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/auth_failure.dart';
import '../domain/login_request.dart';
import '../domain/registered_user.dart';
import '../domain/registration_request.dart';
import '../infrastructure/auth_api.dart';
import '../infrastructure/token_storage.dart';
import '../../../core/logger/app_logger.dart';
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
    AppLogger.info('Hydrating auth state from storage', tag: 'AuthController');
    final token = _storage.readToken();
    final user = _storage.readUser();
    if (token != null) {
      AppLogger.info('Hydrated successfully for user: ${user?.email}', tag: 'AuthController');
      state = AuthState(
        status: AuthStatus.authenticated,
        token: token,
        user: user,
      );
    } else {
      AppLogger.info('No stored session found', tag: 'AuthController');
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

      AppLogger.info('Registration successful, state updated', tag: 'AuthController');
      state = AuthState(
        status: AuthStatus.authenticated,
        token: response.token,
        user: user,
      );
      return true;
    } on AuthFailure catch (failure) {
      AppLogger.warning('Registration failed (AuthFailure): $failure', tag: 'AuthController');
      state = state.copyWith(status: AuthStatus.failure, failure: failure);
      return false;
    } catch (e, stack) {
      AppLogger.error('Registration failed (NetworkFailure)', tag: 'AuthController', error: e, stackTrace: stack);
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
      AppLogger.info('Login successful, state updated', tag: 'AuthController');
      state = AuthState(
        status: AuthStatus.authenticated,
        token: response.token,
        user: response.user ?? _storage.readUser(),
      );
      return true;
    } on AuthFailure catch (failure) {
      AppLogger.warning('Login failed (AuthFailure): $failure', tag: 'AuthController');
      state = state.copyWith(status: AuthStatus.failure, failure: failure);
      return false;
    } catch (e, stack) {
      AppLogger.error('Login failed (NetworkFailure)', tag: 'AuthController', error: e, stackTrace: stack);
      state = state.copyWith(
        status: AuthStatus.failure,
        failure: const NetworkFailure(),
      );
      return false;
    }
  }

  /// Revokes the session both server-side (Firebase refresh tokens) and
  /// locally. After this call the router's auth-guard redirects any
  /// protected location back to the onboarding screen, so the device cannot
  /// re-enter authenticated routes via the back stack.
  ///
  /// Local clean-up always runs, even when the remote revoke fails — a
  /// failed network call must not strand the user in a half-signed-out
  /// state on this device.
  Future<void> signOut() async {
    AppLogger.info('Signing out', tag: 'AuthController');
    final token = state.token;
    if (token != null) {
      await _api.logout(token: token);
    }
    await _storage.clear();
    state = const AuthState.idle();
    AppLogger.info('Sign out complete', tag: 'AuthController');
  }

  /// Uploads a profile photo via the backend and updates the local user
  /// record with the returned public URL.
  ///
  /// Returns the uploaded photo's public URL on success.
  /// Throws [AuthFailure] or [NetworkFailure] on error.
  Future<String> uploadProfilePhoto(File imageFile) async {
    final token = state.token;
    if (token == null) {
      throw const InvalidCredentialsFailure();
    }

    final url = await _api.uploadProfilePhoto(
      token: token,
      imageFile: imageFile,
    );

    // Update in-memory state and local persistence.
    final updatedUser = state.user?.copyWith(avatarUrl: url);
    if (updatedUser != null) {
      await _storage.saveUser(updatedUser);
      state = state.copyWith(user: updatedUser);
      AppLogger.info('Profile photo URL updated in state', tag: 'AuthController');
    }

    return url;
  }
}
