import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_alert_dialog.dart';
import '../../../../core/widgets/skeen_auth_header.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../../../core/widgets/skeen_password_field.dart';
import '../../../../core/widgets/skeen_text_field.dart';
import '../../application/auth_controller.dart';
import '../../application/validators.dart';
import '../../domain/login_request.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_onChanged);
    _passwordCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  String? get _emailError => Validators.email(_emailCtrl.text);
  String? get _passwordError =>
      _passwordCtrl.text.isEmpty ? 'Password is required' : null;

  bool get _isValid => _emailError == null && _passwordError == null;

  Future<void> _onSubmit() async {
    setState(() => _submitted = true);
    if (!_isValid) return;

    final controller = ref.read(authControllerProvider.notifier);
    final ok = await controller.login(
      LoginRequest(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      ),
    );

    if (!mounted) return;
    if (ok) {
      // Returning users skip onboarding (permissions/calibration/terms) —
      // those steps belong only to the post-registration funnel.
      context.go('/home');
    } else {
      final failure = ref.read(authControllerProvider).failure;
      await SkeenAlertDialog.showError(
        context,
        title: "We couldn't log you in",
        message: failure?.message ?? 'Please check your credentials and try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitting = ref.watch(
      authControllerProvider.select((s) => s.isSubmitting),
    );
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
                  const SizedBox(height: 32),
                  const Text(
                    'Log in',
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
                    'Enter your credentials in order to log into your account',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      height: 1.4,
                      letterSpacing: -0.16,
                      color: AppColors.hintText,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SkeenTextField(
                    label: 'Email',
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    errorText: _submitted ? _emailError : null,
                  ),
                  const SizedBox(height: 20),
                  SkeenPasswordField(
                    label: 'Password',
                    controller: _passwordCtrl,
                    textInputAction: TextInputAction.done,
                    showRulesHelper: false,
                    errorText: _submitted ? _passwordError : null,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => context.go('/forgot-password'),
                      child: const Text(
                        'Forgot your password?',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          letterSpacing: -0.14,
                          color: Color(0xFF94489E),
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFF94489E),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SkeenButton.primary(
                    label: "Let's get started!",
                    onPressed: _onSubmit,
                    isLoading: isSubmitting,
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
                          const TextSpan(text: "Don't have an account yet? "),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: GestureDetector(
                              onTap: () => context.go('/register'),
                              child: const Text(
                                'Sign up',
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
