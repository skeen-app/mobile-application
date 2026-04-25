import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_exception.dart';
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

/// HTTP client for the Auth bounded context.
///
/// Endpoints:
///  - POST `${ApiConfig.baseUrl}/register`
///  - POST `${ApiConfig.baseUrl}/login`
class AuthApi {
  AuthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AuthApiResponse> register(RegistrationRequest request) async {
    final res = await _send('/auth/register', request.toJson());
    return _parseSession(res);
  }

  Future<AuthApiResponse> login(LoginRequest request) async {
    final res = await _send('/auth/login', request.toJson());
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
    } catch (_) {
      return const LogoutResult.localOnly();
    }

    if (res.statusCode == 401) {
      // Token already invalid server-side — local revoke still proceeds.
      return const LogoutResult.localOnly();
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return const LogoutResult.localOnly();
    }
    try {
      return LogoutResult.fromJson(_decodeJson(res));
    } catch (_) {
      return const LogoutResult.localOnly();
    }
  }

  /// Uploads a profile photo to the backend.
  ///
  /// Sends a `multipart/form-data` POST to `/auth/profile-photo` with the
  /// image file. The backend validates type (jpeg/png/webp), extension,
  /// size ≤ 5 MB, and magic bytes, then persists the photo to Cloud Storage
  /// and updates the user's `avatarUrl` in Firestore.
  ///
  /// Returns the public URL of the uploaded image.
  Future<String> uploadProfilePhoto({
    required AuthToken token,
    required File imageFile,
  }) async {
    final uri = ApiConfig.uri('/auth/profile-photo');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${token.value}'
      ..headers['Accept'] = 'application/json';

    final ext = imageFile.path.split('.').last.toLowerCase();
    final mimeType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
    final parts = mimeType.split('/');

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        imageFile.path,
        contentType: MediaType(parts[0], parts[1]),
      ),
    );

    final http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(ApiConfig.defaultTimeout);
    } on TimeoutException {
      throw const NetworkFailure('The request timed out');
    } catch (_) {
      throw const NetworkFailure();
    }

    final res = await http.Response.fromStream(streamed);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final json = _decodeJson(res);
      return json['url'] as String;
    }
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
      throw const NetworkFailure('The request timed out');
    } catch (_) {
      throw const NetworkFailure();
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res;
    }
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
