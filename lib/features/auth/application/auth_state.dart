import '../domain/auth_failure.dart';
import '../domain/auth_token.dart';
import '../domain/registered_user.dart';

enum AuthStatus { idle, submitting, authenticated, failure }

class AuthState {
  const AuthState({
    required this.status,
    this.token,
    this.user,
    this.failure,
  });

  const AuthState.idle() : this(status: AuthStatus.idle);

  final AuthStatus status;
  final AuthToken? token;
  final RegisteredUser? user;
  final AuthFailure? failure;

  bool get isSubmitting => status == AuthStatus.submitting;
  bool get isAuthenticated => status == AuthStatus.authenticated && token != null;

  AuthState copyWith({
    AuthStatus? status,
    AuthToken? token,
    RegisteredUser? user,
    AuthFailure? failure,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
      user: user ?? this.user,
      failure: failure,
    );
  }
}
