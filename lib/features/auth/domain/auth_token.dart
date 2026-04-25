class AuthToken {
  const AuthToken({required this.value, required this.issuedAt});

  final String value;
  final DateTime issuedAt;

  Map<String, dynamic> toJson() => {
        'value': value,
        'issuedAt': issuedAt.millisecondsSinceEpoch,
      };

  /// Accepts `issuedAt` as either an epoch number (seconds or milliseconds)
  /// or an ISO-8601 string for forward compatibility.
  factory AuthToken.fromJson(Map<String, dynamic> json) {
    final raw = json['issuedAt'];
    final DateTime issued;
    if (raw is num) {
      // Heuristic: values < 1e12 look like epoch seconds; otherwise ms.
      issued = raw < 1e12
          ? DateTime.fromMillisecondsSinceEpoch((raw * 1000).toInt())
          : DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    } else if (raw is String) {
      issued = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      issued = DateTime.now();
    }
    return AuthToken(value: json['value'] as String, issuedAt: issued);
  }
}
