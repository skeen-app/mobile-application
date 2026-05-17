import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/notifications/notifications_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_auth_header.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../../../core/widgets/skeen_text_field.dart';
import '../../../../core/widgets/skeen_star_field.dart';
import '../../application/auth_controller.dart';
import '../../application/validators.dart';
import '../../domain/auth_failure.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _submitted = false;
  bool _busy = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  String? get _emailError => Validators.email(_emailCtrl.text);
  bool get _isValid => _emailError == null;

  Future<void> _onSubmit() async {
    setState(() {
      _submitted = true;
      _serverError = null;
    });
    if (!_isValid || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authApiProvider).requestPasswordReset(
            email: _emailCtrl.text.trim(),
          );
      ref.notifications.recordPasswordChanged();
      if (!mounted) return;
      context.go('/forgot-password/success');
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _serverError = failure.message);
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _serverError = 'Could not send instructions. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: 100,
              left: 0,
              right: 0,
              height: 160,
              child: SkeenStarField(seed: 42, density: 16),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AutofillGroup(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      const SkeenAuthHeader(),
                      const SizedBox(height: 32),
                      Text(
                        'Forgot password?'.tr,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.22,
                          color: AppColors.violetaClaro,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your email address and we will send you instructions to reset your password.'.tr,
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
                        label: 'Email'.tr,
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.email],
                        errorText:
                            _submitted ? _emailError ?? _serverError : null,
                      ),
                      const SizedBox(height: 32),
                      SkeenButton.primary(
                        label: 'Send instructions'.tr,
                        isLoading: _busy,
                        onPressed: _busy ? () {} : _onSubmit,
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: GestureDetector(
                          onTap: () => context.go('/login'),
                          child: Text(
                            'Back to login'.tr,
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
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
