import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/logger/app_logger.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_token.dart';
import '../domain/login_request.dart';
import '../domain/logout_result.dart';
import '../domain/registered_user.dart';
import '../domain/registration_request.dart';

class AuthApiResponse {
  const AuthApiResponse({required this.token, this.user});
  final AuthToken token;
  final RegisteredUser? user;
}

class FederatedAuthResponse {
  const FederatedAuthResponse({
    required this.token,
    required this.user,
    required this.isNewUser,
  });
  final AuthToken token;
  final RegisteredUser user;

  /// `true` when the backend just provisioned the Firestore profile.
  /// Drives the routing to ``/onboarding/complete-profile`` so DNI +
  /// phone get filled before the user lands on `/home`.
  final bool isNewUser;
}

/// HTTP client for the Auth bounded context.
///
/// Endpoints:
///  - POST `${ApiConfig.baseUrl}/register`
///  - POST `${ApiConfig.baseUrl}/login`
class AuthApi {
  AuthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AuthApiResponse> register(RegistrationRequest request) async {
    AppLogger.info('Attempting registration for: ${request.email}', tag: 'AuthApi');
    final res = await _send('/auth/register', request.toJson());
    AppLogger.info('Registration successful for: ${request.email}', tag: 'AuthApi');
    return _parseSession(res);
  }

  Future<AuthApiResponse> login(LoginRequest request) async {
    AppLogger.info('Attempting login for: ${request.email}', tag: 'AuthApi');
    final res = await _send('/auth/login', request.toJson());
    AppLogger.info('Login successful for: ${request.email}', tag: 'AuthApi');
    return _parseSession(res);
  }

  /// Revokes the Firebase refresh tokens server-side. The backend validates
  /// the bearer (`check_revoked=True`) and on success returns a
  /// [LogoutResult] with the revocation timestamp.
  ///
  /// Local-first contract: the caller (`AuthController.signOut`) always
  /// clears local credentials regardless of the network outcome. So:
  ///  - HTTP 200 → typed result returned.
  ///  - HTTP 401 (token already revoked / expired / invalid) → treated as a
  ///    successful local logout; the device session must still be cleared.
  ///  - Any other failure → returns `LogoutResult.localOnly()`.
  Future<LogoutResult> logout({required AuthToken token}) async {
    AppLogger.info('Attempting logout', tag: 'AuthApi');
    final http.Response res;
    try {
      res = await _client
          .post(
            ApiConfig.uri('/auth/logout'),
            headers: {
              ...ApiConfig.jsonHeaders,
              'Authorization': 'Bearer ${token.value}',
            },
          )
          .timeout(ApiConfig.defaultTimeout);
    } catch (e) {
      AppLogger.warning('Network error during logout, forcing local logout: $e', tag: 'AuthApi');
      return const LogoutResult.localOnly();
    }

    if (res.statusCode == 401) {
      // Token already invalid server-side — local revoke still proceeds.
      AppLogger.info('Logout: Token already invalid server-side (401)', tag: 'AuthApi');
      return const LogoutResult.localOnly();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      AppLogger.warning('Logout: Server returned status ${res.statusCode}', tag: 'AuthApi');
      return const LogoutResult.localOnly();
    }
    try {
      final result = LogoutResult.fromJson(_decodeJson(res));
      AppLogger.info('Logout successful server-side', tag: 'AuthApi');
      return result;
    } catch (e) {
      AppLogger.warning('Failed to parse logout response: $e', tag: 'AuthApi');
      return const LogoutResult.localOnly();
    }
  }

  /// Patches mutable profile fields (`name`, `lastName`, `phone`) for the
  /// authenticated user. Pass only the fields you want to change — the
  /// backend leaves omitted ones untouched.
  ///
  /// Returns the freshly merged [RegisteredUser] from the server.
  Future<RegisteredUser> updateProfile({
    required AuthToken token,
    String? name,
    String? lastName,
    String? phone,
  }) async {
    final body = <String, dynamic>{
      'name': ?name,
      'lastName': ?lastName,
      'phone': ?phone,
    };

    AppLogger.info('PATCH /auth/me (${body.keys.toList()})', tag: 'AuthApi');
    final http.Response res;
    try {
      res = await _client
          .patch(
            ApiConfig.uri('/auth/me'),
            headers: {
              ...ApiConfig.jsonHeaders,
              'Authorization': 'Bearer ${token.value}',
            },
            body: jsonEncode(body),
          )
          .timeout(ApiConfig.defaultTimeout);
    } on TimeoutException {
      throw const NetworkFailure('The request timed out');
    } catch (e, stack) {
      AppLogger.error('Network error during profile update', tag: 'AuthApi', error: e, stackTrace: stack);
      throw const NetworkFailure();
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final json = _decodeJson(res);
      return RegisteredUser.fromJson(json);
    }
    throw _mapError(res, path: '/auth/me');
  }

  /// Federated sign-in: hands a Firebase ID token (obtained from any
  /// Firebase-supported provider — Google today) to the backend so it
  /// can verify, upsert the Firestore profile, and return our session.
  Future<FederatedAuthResponse> signInWithFirebaseToken({
    required String idToken,
  }) async {
    AppLogger.info('Attempting federated sign-in', tag: 'AuthApi');
    final res = await _send('/auth/firebase', {'idToken': idToken});
    final json = _decodeJson(res);
    final tokenJson = json['token'];
    final userJson = json['user'];
    if (tokenJson is! Map<String, dynamic> ||
        userJson is! Map<String, dynamic>) {
      throw const ServerFailure('Malformed federated sign-in response');
    }
    return FederatedAuthResponse(
      token: AuthToken.fromJson(tokenJson),
      user: RegisteredUser.fromJson(userJson),
      isNewUser: json['isNewUser'] as bool? ?? false,
    );
  }

  /// Fills DNI + phone for a profile created by federated sign-in.
  /// Idempotency guarded server-side: 409 once DNI is already set.
  Future<RegisteredUser> completeProfile({
    required AuthToken token,
    required String dni,
    required String phone,
    String? name,
    String? lastName,
  }) async {
    AppLogger.info('POST /auth/me/complete-profile', tag: 'AuthApi');
    final body = <String, dynamic>{
      'dni': dni,
      'phone': phone,
      if (name != null && name.isNotEmpty) 'name': name,
      if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
    };
    final http.Response res;
    try {
      res = await _client
          .post(
            ApiConfig.uri('/auth/me/complete-profile'),
            headers: {
              ...ApiConfig.jsonHeaders,
              'Authorization': 'Bearer ${token.value}',
            },
            body: jsonEncode(body),
          )
          .timeout(ApiConfig.defaultTimeout);
    } on TimeoutException {
      throw const NetworkFailure('The request timed out');
    } catch (e, stack) {
      AppLogger.error('Network error during complete-profile',
          tag: 'AuthApi', error: e, stackTrace: stack);
      throw const NetworkFailure();
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return RegisteredUser.fromJson(_decodeJson(res));
    }
    throw _mapError(res, path: '/auth/me/complete-profile');
  }

  /// Public password-reset flow — used by the unauthenticated
  /// `forgot-password` screen. The backend always responds 200 (even if
  /// the email isn't registered) to prevent enumeration; the only branch
  /// where this throws is genuine network / 5xx / rate-limit failures.
  Future<void> requestPasswordReset({required String email}) async {
    AppLogger.info('POST /auth/password-reset/request', tag: 'AuthApi');
    final http.Response res;
    try {
      res = await _client
          .post(
            ApiConfig.uri('/auth/password-reset/request'),
            headers: ApiConfig.jsonHeaders,
            body: jsonEncode({'email': email}),
          )
          .timeout(ApiConfig.defaultTimeout);
    } on TimeoutException {
      throw const NetworkFailure('The request timed out');
    } catch (e, stack) {
      AppLogger.error('Network error during password reset request',
          tag: 'AuthApi', error: e, stackTrace: stack);
      throw const NetworkFailure();
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return;
    if (res.statusCode == 429) {
      throw const AuthApiFailure(
          'Too many attempts. Please wait a few minutes and try again.');
    }
    throw _mapError(res, path: '/auth/password-reset/request');
  }

  /// Authenticated password-reset flow — Privacy & Security → Change
  /// password. The backend reads the email from the user's profile and
  /// returns it partially masked so the UI can confirm "We sent
  /// instructions to jo***@example.com" without having to render the
  /// stored email in plaintext.
  Future<({String maskedEmail})> requestMyPasswordReset({
    required AuthToken token,
  }) async {
    AppLogger.info('POST /auth/me/password-reset', tag: 'AuthApi');
    final http.Response res;
    try {
      res = await _client
          .post(
            ApiConfig.uri('/auth/me/password-reset'),
            headers: {
              ...ApiConfig.jsonHeaders,
              'Authorization': 'Bearer ${token.value}',
            },
          )
          .timeout(ApiConfig.defaultTimeout);
    } on TimeoutException {
      throw const NetworkFailure('The request timed out');
    } catch (e, stack) {
      AppLogger.error('Network error during authenticated reset',
          tag: 'AuthApi', error: e, stackTrace: stack);
      throw const NetworkFailure();
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final json = _decodeJson(res);
      return (maskedEmail: json['email'] as String? ?? '');
    }
    if (res.statusCode == 429) {
      throw const AuthApiFailure(
          'Too many attempts. Please wait a few minutes and try again.');
    }
    throw _mapError(res, path: '/auth/me/password-reset');
  }

  /// Soft-deletes the user record (Firestore `isActive=false`) and removes
  /// the Firebase Auth identity. The local session is the caller's
  /// responsibility — see [AuthController.deleteAccount].
  Future<void> deleteAccount({required AuthToken token}) async {
    AppLogger.info('DELETE /auth/me', tag: 'AuthApi');
    final http.Response res;
    try {
      res = await _client
          .delete(
            ApiConfig.uri('/auth/me'),
            headers: {
              ...ApiConfig.jsonHeaders,
              'Authorization': 'Bearer ${token.value}',
            },
          )
          .timeout(ApiConfig.defaultTimeout);
    } on TimeoutException {
      throw const NetworkFailure('The request timed out');
    } catch (e, stack) {
      AppLogger.error('Network error during account deletion', tag: 'AuthApi', error: e, stackTrace: stack);
      throw const NetworkFailure();
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw _mapError(res, path: '/auth/me');
  }

  /// Uploads a profile photo to the backend.
  ///
  /// Sends a `multipart/form-data` POST to `/auth/profile-photo` with the
  /// image bytes. Works on every Flutter target (mobile, desktop, web) by
  /// reading from memory instead of `dart:io`. The backend validates type
  /// (jpeg/png/webp), extension, size ≤ 5 MB, and magic bytes, then persists
  /// the photo to Cloud Storage and updates the user's `avatarUrl` in
  /// Firestore.
  ///
  /// Returns the public URL of the uploaded image.
  Future<String> uploadProfilePhoto({
    required AuthToken token,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    AppLogger.info('Attempting profile photo upload: $filename (${bytes.lengthInBytes} bytes)', tag: 'AuthApi');
    final uri = ApiConfig.uri('/auth/profile-photo');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${token.value}'
      ..headers['Accept'] = 'application/json';

    final parts = mimeType.split('/');
    final mediaType = parts.length == 2
        ? MediaType(parts[0], parts[1])
        : MediaType('application', 'octet-stream');

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: mediaType,
      ),
    );

    final http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(ApiConfig.defaultTimeout);
    } on TimeoutException {
      AppLogger.warning('Profile photo upload timed out', tag: 'AuthApi');
      throw const NetworkFailure('The request timed out');
    } catch (e, stack) {
      AppLogger.error('Network exception during profile photo upload', tag: 'AuthApi', error: e, stackTrace: stack);
      throw const NetworkFailure();
    }

    final res = await http.Response.fromStream(streamed);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final json = _decodeJson(res);
      AppLogger.info('Profile photo uploaded successfully', tag: 'AuthApi');
      return json['url'] as String;
    }
    AppLogger.error('Profile photo upload failed: HTTP ${res.statusCode}', tag: 'AuthApi');
    throw _mapError(res, path: '/auth/profile-photo');
  }

  AuthApiResponse _parseSession(http.Response res) {
    final json = _decodeJson(res);
    final tokenJson = json['token'];
    if (tokenJson is! Map<String, dynamic>) {
      throw const ServerFailure('Malformed response: missing token');
    }
    final token = AuthToken.fromJson(tokenJson);
    final userJson = json['user'];
    final user = userJson is Map<String, dynamic>
        ? RegisteredUser.fromJson(userJson)
        : null;
    return AuthApiResponse(token: token, user: user);
  }

  Future<http.Response> _send(String path, Map<String, dynamic> body) async {
    AppLogger.info('POST $path', tag: 'AuthApi');
    final http.Response res;
    try {
      res = await _client
          .post(
            ApiConfig.uri(path),
            headers: ApiConfig.jsonHeaders,
            body: jsonEncode(body),
          )
          .timeout(ApiConfig.defaultTimeout);
    } on TimeoutException {
      AppLogger.warning('Request to $path timed out', tag: 'AuthApi');
      throw const NetworkFailure('The request timed out');
    } catch (e, stack) {
      AppLogger.error('Network exception during POST $path', tag: 'AuthApi', error: e, stackTrace: stack);
      throw const NetworkFailure();
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res;
    }
    AppLogger.warning('Request to $path failed with status ${res.statusCode}', tag: 'AuthApi');
    throw _mapError(res, path: path);
  }

  AuthFailure _mapError(http.Response res, {required String path}) {
    final body = _tryDecodeJson(res);
    final code = (body is Map ? body['code'] : null)?.toString();
    final message =
        (body is Map ? (body['detail'] ?? body['error']) : null)?.toString() ??
        'Request failed (${res.statusCode})';

    switch (res.statusCode) {
      case 400:
      case 422:
        if (code == 'DNI_TAKEN' || message.toLowerCase().contains('dni')) {
          return const DniAlreadyRegisteredFailure();
        }
        if (code == 'EMAIL_TAKEN' || message.toLowerCase().contains('email')) {
          return const EmailAlreadyRegisteredFailure();
        }
        return AuthApiFailure(message);
      case 401:
      case 403:
        return const InvalidCredentialsFailure();
      case 409:
        return path.contains('register')
            ? const EmailAlreadyRegisteredFailure()
            : AuthApiFailure(message);
      default:
        if (res.statusCode >= 500) return ServerFailure(message);
        return AuthApiFailure(message);
    }
  }

  Map<String, dynamic> _decodeJson(http.Response res) {
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        statusCode: res.statusCode,
        message: 'Invalid JSON response',
        body: res.body,
      );
    }
  }

  dynamic _tryDecodeJson(http.Response res) {
    try {
      return jsonDecode(res.body);
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
