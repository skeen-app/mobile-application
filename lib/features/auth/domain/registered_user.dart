class RegisteredUser {
  const RegisteredUser({
    required this.id,
    required this.name,
    required this.lastName,
    required this.dni,
    required this.email,
    required this.phone,
  });

  final String id;
  final String name;
  final String lastName;
  final String dni;
  final String email;
  final String phone;

  String get fullName => '$name $lastName';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lastName': lastName,
        'dni': dni,
        'email': email,
        'phone': phone,
      };

  factory RegisteredUser.fromJson(Map<String, dynamic> json) => RegisteredUser(
        id: json['id'] as String,
        name: json['name'] as String,
        lastName: json['lastName'] as String,
        dni: json['dni'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String,
      );
}
