class AuthToken {
  const AuthToken({required this.value, required this.issuedAt});

  final String value;
  final DateTime issuedAt;

  Map<String, dynamic> toJson() => {
        'value': value,
        'issuedAt': issuedAt.toIso8601String(),
      };

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
        value: json['value'] as String,
        issuedAt: DateTime.parse(json['issuedAt'] as String),
      );
}
