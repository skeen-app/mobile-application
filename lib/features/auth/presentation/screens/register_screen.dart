import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_auth_header.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../../../core/widgets/skeen_password_field.dart';
import '../../../../core/widgets/skeen_text_field.dart';
import '../../application/validators.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _dniCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    for (final c in _controllers) {
      c.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<TextEditingController> get _controllers => [
        _nameCtrl,
        _lastNameCtrl,
        _dniCtrl,
        _emailCtrl,
        _phoneCtrl,
        _passwordCtrl,
        _confirmCtrl,
      ];

  void _onChanged() => setState(() {});

  String? get _nameError =>
      Validators.required(_nameCtrl.text, name: 'Name');
  String? get _lastNameError =>
      Validators.required(_lastNameCtrl.text, name: 'Last name');
  String? get _dniError => Validators.dni(_dniCtrl.text);
  String? get _emailError => Validators.email(_emailCtrl.text);
  String? get _phoneError => Validators.phone(_phoneCtrl.text);
  String? get _passwordError => Validators.password(_passwordCtrl.text);
  String? get _confirmError =>
      Validators.confirmPassword(_confirmCtrl.text, _passwordCtrl.text);

  bool get _isValid =>
      _nameError == null &&
      _lastNameError == null &&
      _dniError == null &&
      _emailError == null &&
      _phoneError == null &&
      _passwordError == null &&
      _confirmError == null;

  void _onSubmit() {
    setState(() => _submitted = true);
    if (!_isValid) return;
    // Frontend-only: no backend wiring yet.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AutofillGroup(
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const SkeenAuthHeader(),
                  const SizedBox(height: 24),
                  const Text(
                    'Enter your information',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.22,
                      color: AppColors.violetaClaro,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Fill in the fields below',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      height: 1.4,
                      letterSpacing: -0.16,
                      color: AppColors.hintText,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SkeenTextField(
                    label: 'Name',
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.givenName],
                    errorText: _submitted ? _nameError : null,
                  ),
                  const SizedBox(height: 20),
                  SkeenTextField(
                    label: 'Last Name',
                    controller: _lastNameCtrl,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.familyName],
                    errorText: _submitted ? _lastNameError : null,
                  ),
                  const SizedBox(height: 20),
                  SkeenTextField(
                    label: 'DNI',
                    controller: _dniCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    textInputAction: TextInputAction.next,
                    errorText: _submitted ? _dniError : null,
                    helperBuilder: (_) => _HintPanel(
                      icon: Icons.info_outline,
                      message:
                          'Your DNI must be exactly 8 digits (${_dniCtrl.text.length}/8).',
                      ok: Validators.dni(_dniCtrl.text) == null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SkeenTextField(
                    label: 'Email',
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    errorText: _submitted ? _emailError : null,
                    helperBuilder: (_) => _HintPanel(
                      icon: Icons.alternate_email,
                      message: 'Use a valid format, e.g. name@example.com.',
                      ok: _emailCtrl.text.isEmpty
                          ? null
                          : Validators.email(_emailCtrl.text) == null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SkeenTextField(
                    label: 'Phone Number',
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    errorText: _submitted ? _phoneError : null,
                    helperBuilder: (_) => _HintPanel(
                      icon: Icons.phone_outlined,
                      message:
                          'Peruvian mobile numbers have 9 digits (${_phoneCtrl.text.length}/9).',
                      ok: Validators.phone(_phoneCtrl.text) == null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SkeenPasswordField(
                    label: 'Password',
                    controller: _passwordCtrl,
                    textInputAction: TextInputAction.next,
                    errorText: _submitted ? _passwordError : null,
                  ),
                  const SizedBox(height: 20),
                  SkeenPasswordField(
                    label: 'Confirm your password',
                    controller: _confirmCtrl,
                    textInputAction: TextInputAction.done,
                    showRulesHelper: false,
                    errorText: _submitted ? _confirmError : null,
                  ),
                  const SizedBox(height: 32),
                  SkeenButton.primary(
                    label: 'Continue',
                    onPressed: _onSubmit,
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          letterSpacing: -0.14,
                          color: AppColors.hintText,
                        ),
                        children: [
                          const TextSpan(text: 'Already have an account? '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: GestureDetector(
                              onTap: () => context.go('/login'),
                              child: const Text(
                                'Log in',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  letterSpacing: -0.14,
                                  color: AppColors.violetaLink,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.violetaLink,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HintPanel extends StatelessWidget {
  const _HintPanel({
    required this.icon,
    required this.message,
    this.ok,
  });

  final IconData icon;
  final String message;
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    Color accent;
    if (ok == true) {
      accent = AppColors.turquesa;
    } else if (ok == false) {
      accent = AppColors.fucsia;
    } else {
      accent = AppColors.hintText;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.indigo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                letterSpacing: -0.12,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
