/// Server-confirmed result of a sign-out call.
///
/// Mirrors the backend `LogoutResponse` schema. The `loggedOutAt` timestamp
/// is what the backend records as the moment the refresh tokens were
/// revoked; the client uses it for analytics / debug surfaces only.
class LogoutResult {
  const LogoutResult({
    required this.loggedOut,
    this.userId,
    this.loggedOutAt,
    this.message,
  });

  final bool loggedOut;
  final String? userId;
  final DateTime? loggedOutAt;
  final String? message;

  /// Synthetic result used when the network call fails or the token had
  /// already been revoked. The local clean-up still proceeds in those cases.
  const LogoutResult.localOnly()
      : loggedOut = false,
        userId = null,
        loggedOutAt = null,
        message = null;

  factory LogoutResult.fromJson(Map<String, dynamic> json) => LogoutResult(
        loggedOut: json['loggedOut'] as bool? ?? false,
        userId: json['userId'] as String?,
        loggedOutAt: (json['loggedOutAt'] as String?) != null
            ? DateTime.tryParse(json['loggedOutAt'] as String)
            : null,
        message: json['message'] as String?,
      );
}
