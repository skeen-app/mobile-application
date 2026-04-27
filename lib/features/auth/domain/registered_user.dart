/// Locally-persisted user identity. Hydrated from the auth API on
/// register/login and re-read on cold start, so views like the profile
/// dashboard can render without an extra network round-trip.
///
/// `avatarUrl` and `lastScanAt` are nullable: the backend will populate them
/// once the corresponding endpoints exist; the UI degrades gracefully when
/// either is missing (default avatar, "—" for next checkup).
class RegisteredUser {
  const RegisteredUser({
    required this.id,
    required this.name,
    required this.lastName,
    required this.dni,
    required this.email,
    required this.phone,
    this.avatarUrl,
    this.lastScanAt,
  });

  final String id;
  final String name;
  final String lastName;
  final String dni;
  final String email;
  final String phone;

  /// Remote URL of the user's profile picture, or `null` when unset.
  final String? avatarUrl;

  /// Timestamp of the most recent scan saved against this user. Drives the
  /// "Next checkup" badge on the profile screen (last scan + 1 month).
  final DateTime? lastScanAt;

  String get fullName => '$name $lastName';

  RegisteredUser copyWith({
    String? id,
    String? name,
    String? lastName,
    String? dni,
    String? email,
    String? phone,
    String? avatarUrl,
    DateTime? lastScanAt,
    bool clearAvatar = false,
    bool clearLastScan = false,
  }) {
    return RegisteredUser(
      id: id ?? this.id,
      name: name ?? this.name,
      lastName: lastName ?? this.lastName,
      dni: dni ?? this.dni,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
      lastScanAt: clearLastScan ? null : (lastScanAt ?? this.lastScanAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lastName': lastName,
        'dni': dni,
        'email': email,
        'phone': phone,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (lastScanAt != null) 'lastScanAt': lastScanAt!.toIso8601String(),
      };

  factory RegisteredUser.fromJson(Map<String, dynamic> json) => RegisteredUser(
        id: json['id'] as String,
        name: json['name'] as String,
        lastName: json['lastName'] as String,
        dni: json['dni'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        lastScanAt: (json['lastScanAt'] as String?) != null
            ? DateTime.tryParse(json['lastScanAt'] as String)
            : null,
      );
}
