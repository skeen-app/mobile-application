import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/auth_failure.dart';
import '../domain/login_request.dart';
import '../domain/registered_user.dart';
import '../domain/registration_request.dart';
import '../infrastructure/auth_api.dart';
import '../infrastructure/token_storage.dart';
import '../../../core/logger/app_logger.dart';
import 'auth_state.dart';

/// Outcome of a federated sign-in (Google today). Drives the routing
/// decision after Google sign-in: complete-profile vs home.
class FederatedSignInOutcome {
  const FederatedSignInOutcome({
    required this.success,
    required this.isNewUser,
    required this.needsProfileCompletion,
  });
  final bool success;
  final bool isNewUser;
  final bool needsProfileCompletion;

  static const FederatedSignInOutcome cancelled = FederatedSignInOutcome(
    success: false,
    isNewUser: false,
    needsProfileCompletion: false,
  );
}

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

  /// Federated sign-in via Google. The flow:
  ///   1. Google Sign-In SDK pops the account picker and yields the
  ///      Google ID + access tokens.
  ///   2. Those exchange for a Firebase credential — which Firebase
  ///      Auth turns into our app-level Firebase user (auto-linking
  ///      with any existing email/password identity sharing the same
  ///      address per the Firebase project settings).
  ///   3. We forward the resulting Firebase ID token to our backend
  ///      ``POST /auth/firebase`` which upserts the Firestore profile
  ///      and returns our session.
  /// OAuth Web client ID for the skeen Firebase project. Optional but
  /// recommended: passing it as ``serverClientId`` forces Google to mint
  /// an ID token whose audience matches Firebase's expectation, which
  /// avoids subtle "DEVELOPER_ERROR" failures on release builds.
  ///
  /// Provide via build flag to override:
  ///   --dart-define=SKEEN_GOOGLE_WEB_CLIENT_ID=<id>.apps.googleusercontent.com
  ///
  /// When empty (default) the package falls back to whatever the
  /// `google-services.json` registers — which works fine in debug as
  /// long as the SHA-1 of the keystore is registered in Firebase Console.
  static const String _googleWebClientId = String.fromEnvironment(
    'SKEEN_GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  Future<FederatedSignInOutcome> signInWithGoogle() async {
    state = state.copyWith(status: AuthStatus.submitting);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId:
            _googleWebClientId.isEmpty ? null : _googleWebClientId,
        scopes: const ['email', 'profile'],
      );
      final account = await googleSignIn.signIn();
      if (account == null) {
        // User dismissed the picker.
        state = state.copyWith(status: AuthStatus.idle);
        return FederatedSignInOutcome.cancelled;
      }
      final googleAuth = await account.authentication;
      final credential = fb_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred =
          await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
      final firebaseIdToken = await userCred.user?.getIdToken();
      if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
        throw const ServerFailure('Could not obtain Firebase token');
      }

      final response = await _api.signInWithFirebaseToken(
        idToken: firebaseIdToken,
      );

      await _storage.saveToken(response.token);
      await _storage.saveUser(response.user);
      state = AuthState(
        status: AuthStatus.authenticated,
        token: response.token,
        user: response.user,
      );

      final needsCompletion =
          response.isNewUser || response.user.dni.trim().isEmpty;
      AppLogger.info(
        'Google sign-in OK — isNewUser=${response.isNewUser} '
        'needsCompletion=$needsCompletion',
        tag: 'AuthController',
      );
      return FederatedSignInOutcome(
        success: true,
        isNewUser: response.isNewUser,
        needsProfileCompletion: needsCompletion,
      );
    } on AuthFailure catch (failure) {
      AppLogger.warning('Google sign-in failed: $failure',
          tag: 'AuthController');
      state = state.copyWith(status: AuthStatus.failure, failure: failure);
      return FederatedSignInOutcome.cancelled;
    } catch (e, stack) {
      AppLogger.error('Google sign-in crashed',
          tag: 'AuthController', error: e, stackTrace: stack);
      state = state.copyWith(
        status: AuthStatus.failure,
        failure: const NetworkFailure(),
      );
      return FederatedSignInOutcome.cancelled;
    }
  }

  /// Fills DNI + phone for a profile created by federated sign-in. After
  /// this call the profile is "complete" and the regular update flow
  /// can be used.
  Future<RegisteredUser> completeFederatedProfile({
    required String dni,
    required String phone,
    String? name,
    String? lastName,
  }) async {
    final token = state.token;
    if (token == null) throw const InvalidCredentialsFailure();
    final updated = await _api.completeProfile(
      token: token,
      dni: dni,
      phone: phone,
      name: name,
      lastName: lastName,
    );
    final merged = (state.user ?? updated).copyWith(
      name: updated.name,
      lastName: updated.lastName,
      dni: updated.dni,
      phone: updated.phone,
      avatarUrl: updated.avatarUrl,
      isActive: updated.isActive,
    );
    await _storage.saveUser(merged);
    state = state.copyWith(user: merged);
    AppLogger.info('Federated profile completed', tag: 'AuthController');
    return merged;
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
    // Best-effort sign out from the federated providers so the next
    // login pops the picker again. Both calls are no-ops when the user
    // never signed in via Google.
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    try {
      await fb_auth.FirebaseAuth.instance.signOut();
    } catch (_) {}
    await _storage.clear();
    state = const AuthState.idle();
    AppLogger.info('Sign out complete', tag: 'AuthController');
  }

  /// Patches mutable profile fields on the backend and mirrors the result
  /// into in-memory state + persistent storage. Pass only the fields you
  /// want to change.
  ///
  /// Throws [AuthFailure] on validation/server error.
  Future<RegisteredUser> updateProfile({
    String? name,
    String? lastName,
    String? phone,
  }) async {
    final token = state.token;
    if (token == null) throw const InvalidCredentialsFailure();

    final updated = await _api.updateProfile(
      token: token,
      name: name,
      lastName: lastName,
      phone: phone,
    );

    // Backend is the source of truth — but it doesn't echo client-only
    // fields (e.g. lastScanAt), so merge instead of replacing wholesale.
    final merged = (state.user ?? updated).copyWith(
      name: updated.name,
      lastName: updated.lastName,
      phone: updated.phone,
      avatarUrl: updated.avatarUrl,
      isActive: updated.isActive,
    );

    await _storage.saveUser(merged);
    state = state.copyWith(user: merged);
    AppLogger.info('Profile fields updated and persisted', tag: 'AuthController');
    return merged;
  }

  /// Initiates account deletion: backend soft-deletes the Firestore record
  /// and hard-deletes the Firebase Auth identity. Locally we always wipe
  /// the session so the router immediately bounces back to onboarding —
  /// even when the network call fails, the device session must end (the
  /// backend has already accepted the intent in the worst case).
  Future<void> deleteAccount() async {
    final token = state.token;
    if (token == null) throw const InvalidCredentialsFailure();
    AppLogger.info('Deleting account', tag: 'AuthController');
    try {
      await _api.deleteAccount(token: token);
    } finally {
      await _storage.clear();
      state = const AuthState.idle();
      AppLogger.info('Local session cleared after deletion', tag: 'AuthController');
    }
  }

  /// Uploads a profile photo via the backend and updates the local user
  /// record with the returned public URL.
  ///
  /// Accepts raw bytes so the same code path works on mobile (where the
  /// picker hands us a file path) and on web (where there is no `dart:io`
  /// File — only an in-memory blob).
  ///
  /// Returns the uploaded photo's public URL on success.
  /// Throws [AuthFailure] or [NetworkFailure] on error.
  Future<String> uploadProfilePhoto({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final token = state.token;
    if (token == null) {
      throw const InvalidCredentialsFailure();
    }

    final url = await _api.uploadProfilePhoto(
      token: token,
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );

    // Persist the URL exactly as the backend returns it — same as what is
    // stored at register/login time, so a cold start with a hydrated user
    // can render the avatar without any extra network call.
    final updatedUser = state.user?.copyWith(avatarUrl: url);
    if (updatedUser != null) {
      await _storage.saveUser(updatedUser);
      state = state.copyWith(user: updatedUser);
      AppLogger.info('Profile photo URL updated in state', tag: 'AuthController');
    }

    return url;
  }
}
