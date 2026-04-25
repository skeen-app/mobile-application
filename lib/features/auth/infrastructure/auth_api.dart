import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_config.dart';
import '../../../core/network/api_exception.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_token.dart';
import '../domain/login_request.dart';
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

  /// Best-effort sign-out. The endpoint is not yet implemented on the
  /// backend; the client therefore swallows network/server errors so the
  /// caller can always proceed to clear local state. The token is sent in
  /// the `Authorization` header so the backend can revoke it once supported.
  Future<void> logout({required AuthToken token}) async {
    try {
      await _client
          .post(
            ApiConfig.uri('/auth/logout'),
            headers: {
              ...ApiConfig.jsonHeaders,
              'Authorization': 'Bearer ${token.value}',
            },
          )
          .timeout(ApiConfig.defaultTimeout);
    } catch (_) {
      // Logout is local-first: a failed remote revoke must not block the
      // user from leaving the session on this device.
    }
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
