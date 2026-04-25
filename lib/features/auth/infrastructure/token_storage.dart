import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/auth_token.dart';
import '../domain/registered_user.dart';

class TokenStorage {
  TokenStorage(this._prefs);

  final SharedPreferences _prefs;

  static const String _tokenKey = 'auth.token';
  static const String _userKey = 'auth.user';

  Future<void> saveToken(AuthToken token) async {
    await _prefs.setString(_tokenKey, jsonEncode(token.toJson()));
  }

  AuthToken? readToken() {
    final raw = _prefs.getString(_tokenKey);
    if (raw == null) return null;
    return AuthToken.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveUser(RegisteredUser user) async {
    await _prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  RegisteredUser? readUser() {
    final raw = _prefs.getString(_userKey);
    if (raw == null) return null;
    return RegisteredUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clear() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_userKey);
  }
}
