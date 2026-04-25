class PasswordRule {
  const PasswordRule(this.label, this.met);
  final String label;
  final bool met;
}

class Validators {
  const Validators._();

  static final RegExp _emailRegex =
      RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$');
  static final RegExp _dniRegex = RegExp(r'^\d{8}$');
  static final RegExp _phoneRegex = RegExp(r'^\d{9}$');

  static String? required(String value, {String name = 'This field'}) {
    return value.trim().isEmpty ? '$name is required' : null;
  }

  static String? email(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(v)) return 'Invalid email format';
    return null;
  }

  static String? dni(String value) {
    if (value.isEmpty) return 'DNI is required';
    if (!_dniRegex.hasMatch(value)) return 'DNI must be exactly 8 digits';
    return null;
  }

  static String? phone(String value) {
    if (value.isEmpty) return 'Phone is required';
    if (!_phoneRegex.hasMatch(value)) return 'Phone must be 9 digits';
    return null;
  }

  static List<PasswordRule> passwordRules(String value) {
    return [
      PasswordRule('At least 8 characters', value.length >= 8),
      PasswordRule('One uppercase letter', RegExp(r'[A-Z]').hasMatch(value)),
      PasswordRule('One lowercase letter', RegExp(r'[a-z]').hasMatch(value)),
      PasswordRule('One number', RegExp(r'\d').hasMatch(value)),
      PasswordRule(
        'One special character',
        RegExp(r'''[!@#\$%\^&\*\(\)_\+\-=\[\]\{\};:"\\|,.<>/?~`]''').hasMatch(value),
      ),
    ];
  }

  static bool isPasswordStrong(String value) {
    return passwordRules(value).every((rule) => rule.met);
  }

  static String? password(String value) {
    if (value.isEmpty) return 'Password is required';
    if (!isPasswordStrong(value)) return 'Password does not meet all requirements';
    return null;
  }

  static String? confirmPassword(String value, String original) {
    if (value.isEmpty) return 'Please confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }
}
