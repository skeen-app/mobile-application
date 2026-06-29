import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_alert_dialog.dart';
import '../../../../core/widgets/skeen_auth_header.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../../../core/widgets/skeen_text_field.dart';
import '../../application/auth_controller.dart';
import '../../application/validators.dart';
import '../../domain/auth_failure.dart';

/// First-time federated users (Google sign-in) land here. The Firestore
/// profile gets pre-populated with name + email from Google but DNI and
/// phone need explicit user input. ``POST /auth/me/complete-profile``
/// patches both fields, then we route to ``/home``.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState
    extends ConsumerState<CompleteProfileScreen> {
  final _dniCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _submitted = false;
  bool _busy = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _dniCtrl.addListener(_onChanged);
    _phoneCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _dniCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  String? get _dniError => Validators.dni(_dniCtrl.text);
  String? get _phoneError => Validators.phone(_phoneCtrl.text);

  bool get _isValid => _dniError == null && _phoneError == null;

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _serverError = null;
    });
    if (!_isValid || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).completeFederatedProfile(
            dni: _dniCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
          );
      if (!mounted) return;
      // First-time federated users must still accept the Terms &
      // Conditions before landing on /home — the email+password funnel
      // routes through this same screen, so Google sign-up is no longer
      // the odd one out that skips the step.
      context.go('/onboarding/terms');
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _serverError = failure.message);
    } catch (_) {
      if (!mounted) return;
      await SkeenAlertDialog.showError(
        context,
        title: 'We could not finish your profile'.tr,
        message: 'Please check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider.select((s) => s.user));
    final greetingName = (user?.name ?? '').trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AutofillGroup(
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const SkeenAuthHeader(),
                  const SizedBox(height: 28),
                  Text(
                    // Translate the static template, then interpolate the
                    // name so the lookup key stays language-stable.
                    greetingName.isEmpty
                        ? 'Almost there'.tr
                        : '${'Almost there'.tr}, $greetingName',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.22,
                      color: AppColors.violetaClaro,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ('We just need your DNI and phone number to finish '
                    'setting up your medical history. These are required '
                    'to keep your records consistent and won\'t change '
                    'after you save them.').tr,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      height: 1.5,
                      letterSpacing: -0.14,
                      color: AppColors.hintText,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if ((user?.email ?? '').isNotEmpty)
                    _ReadOnlyChip(
                      label: 'Signed in with Google'.tr,
                      value: user!.email,
                    ),
                  if ((user?.email ?? '').isNotEmpty)
                    const SizedBox(height: 18),
                  SkeenTextField(
                    label: 'DNI'.tr,
                    controller: _dniCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    textInputAction: TextInputAction.next,
                    errorText: _submitted ? _dniError : null,
                  ),
                  const SizedBox(height: 16),
                  SkeenTextField(
                    label: 'Phone Number'.tr,
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    errorText: _submitted ? _phoneError ?? _serverError : null,
                  ),
                  const SizedBox(height: 28),
                  SkeenButton.primary(
                    label: 'Save and continue'.tr,
                    isLoading: _busy,
                    onPressed: _busy ? () {} : _submit,
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyChip extends StatelessWidget {
  const _ReadOnlyChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1444),
        border: Border.all(color: const Color(0xFF2F1B66)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_outlined,
            color: AppColors.turquesa,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: AppColors.turquesa,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: AppColors.violetaClaro,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
