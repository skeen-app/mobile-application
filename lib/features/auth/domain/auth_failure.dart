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
