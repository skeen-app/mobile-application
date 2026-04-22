import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/auth_failure.dart';
import '../domain/registration_request.dart';
import '../infrastructure/mock_auth_api.dart';
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

final mockAuthApiProvider = Provider<MockAuthApi>((ref) => MockAuthApi());

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    api: ref.watch(mockAuthApiProvider),
    storage: ref.watch(tokenStorageProvider),
  )..hydrate();
});

class AuthController extends StateNotifier<AuthState> {
  AuthController({required MockAuthApi api, required TokenStorage storage})
      : _api = api,
        _storage = storage,
        super(const AuthState.idle());

  final MockAuthApi _api;
  final TokenStorage _storage;

  void hydrate() {
    final token = _storage.readToken();
    final user = _storage.readUser();
    if (token != null && user != null) {
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
      await _storage.saveToken(response.token);
      await _storage.saveUser(response.user);
      state = AuthState(
        status: AuthStatus.authenticated,
        token: response.token,
        user: response.user,
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

  Future<void> signOut() async {
    await _storage.clear();
    state = const AuthState.idle();
  }
}
