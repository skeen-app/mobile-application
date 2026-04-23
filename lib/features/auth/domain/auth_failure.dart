sealed class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

class NetworkFailure extends AuthFailure {
  const NetworkFailure([super.message = 'No connection to the server']);
}

class DniAlreadyRegisteredFailure extends AuthFailure {
  const DniAlreadyRegisteredFailure()
      : super('This DNI is already registered');
}

class EmailAlreadyRegisteredFailure extends AuthFailure {
  const EmailAlreadyRegisteredFailure()
      : super('This email is already registered');
}

class InvalidCredentialsFailure extends AuthFailure {
  const InvalidCredentialsFailure()
      : super('Invalid email or password');
}

class ServerFailure extends AuthFailure {
  const ServerFailure([super.message = 'The server is having trouble']);
}

/// Generic API failure used when the backend returns a 4xx without a
/// specific known code.
class AuthApiFailure extends AuthFailure {
  const AuthApiFailure(super.message);
}
