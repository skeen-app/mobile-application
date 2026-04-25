class RegistrationRequest {
  const RegistrationRequest({
    required this.name,
    required this.lastName,
    required this.dni,
    required this.email,
    required this.phone,
    required this.password,
  });

  final String name;
  final String lastName;
  final String dni;
  final String email;
  final String phone;
  final String password;

  Map<String, dynamic> toJson() => {
        'name': name,
        'lastName': lastName,
        'dni': dni,
        'email': email,
        'phone': phone,
        'password': password,
      };
}
