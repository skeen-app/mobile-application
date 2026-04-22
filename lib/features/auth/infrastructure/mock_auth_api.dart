import 'dart:math';

import '../domain/auth_failure.dart';
import '../domain/auth_token.dart';
import '../domain/registered_user.dart';
import '../domain/registration_request.dart';

class AuthApiResponse {
  const AuthApiResponse({required this.token, required this.user});
  final AuthToken token;
  final RegisteredUser user;
}

class MockAuthApi {
  MockAuthApi({
    Duration latency = const Duration(milliseconds: 900),
    Set<String> reservedDnis = const {'12345678'},
    Set<String> reservedEmails = const {'taken@skeen.pe'},
  })  : _latency = latency,
        _reservedDnis = reservedDnis,
        _reservedEmails = reservedEmails;

  final Duration _latency;
  final Set<String> _reservedDnis;
  final Set<String> _reservedEmails;
  final Random _rng = Random();

  Future<AuthApiResponse> register(RegistrationRequest req) async {
    await Future<void>.delayed(_latency);

    if (_reservedDnis.contains(req.dni)) {
      throw const DniAlreadyRegisteredFailure();
    }
    if (_reservedEmails.contains(req.email.toLowerCase())) {
      throw const EmailAlreadyRegisteredFailure();
    }

    final user = RegisteredUser(
      id: 'usr_${_randomId()}',
      name: req.name.trim(),
      lastName: req.lastName.trim(),
      dni: req.dni,
      email: req.email.trim(),
      phone: req.phone,
    );

    final token = AuthToken(
      value: 'mock.${_randomId()}.${_randomId()}',
      issuedAt: DateTime.now(),
    );

    return AuthApiResponse(token: token, user: user);
  }

  String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(16, (_) => chars[_rng.nextInt(chars.length)]).join();
  }
}
