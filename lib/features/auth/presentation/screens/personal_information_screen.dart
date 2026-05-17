import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/logger/app_logger.dart';
import '../../../../core/notifications/notifications_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_star_field.dart';
import '../../../../core/widgets/skeen_text_field.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../application/auth_controller.dart';
import '../../domain/auth_failure.dart';
import '../../domain/registered_user.dart';

/// Personal information — Auth/Profile context.
///
/// Lets the user edit their mutable identity fields (`name`, `lastName`,
/// `phone`) against `PATCH /auth/me`, and trigger soft-deletion of the
/// account against `DELETE /auth/me`. DNI and email are shown read-only:
///   - DNI is the government identifier; mutating it would silently break
///     historic medical records.
///   - Email is the Firebase Auth login; changing it requires a separate
///     re-verification flow that is out of scope for this screen.
class PersonalInformationScreen extends ConsumerStatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  ConsumerState<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState
    extends ConsumerState<PersonalInformationScreen> {
  final _nameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    if (user != null) _hydrateFromUser(user);
    _nameCtrl.addListener(_onChanged);
    _lastNameCtrl.addListener(_onChanged);
    _phoneCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromUser(RegisteredUser user) {
    _nameCtrl.text = user.name;
    _lastNameCtrl.text = user.lastName;
    _phoneCtrl.text = user.phone;
  }

  void _onChanged() => setState(() {});

  bool get _isDirty {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return false;
    return _nameCtrl.text.trim() != user.name ||
        _lastNameCtrl.text.trim() != user.lastName ||
        _phoneCtrl.text.trim() != user.phone;
  }

  bool get _isValid {
    return _nameCtrl.text.trim().isNotEmpty &&
        _lastNameCtrl.text.trim().isNotEmpty &&
        _phoneCtrl.text.trim().isNotEmpty;
  }

  Future<void> _save() async {
    final user = ref.read(authControllerProvider).user;
    if (user == null || !_isDirty || !_isValid || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final name = _nameCtrl.text.trim();
      final lastName = _lastNameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();
      final changedFields = <String>[
        if (name != user.name) 'name',
        if (lastName != user.lastName) 'lastName',
        if (phone != user.phone) 'phone',
      ];
      await ref.read(authControllerProvider.notifier).updateProfile(
            name: name != user.name ? name : null,
            lastName: lastName != user.lastName ? lastName : null,
            phone: phone != user.phone ? phone : null,
          );
      if (changedFields.isNotEmpty) {
        ref.notifications.recordProfileEdited(fields: changedFields);
      }
      if (!mounted) return;
      _showSnack('Profile updated', destructive: false);
    } on AuthFailure catch (failure) {
      AppLogger.warning('Profile update failed: $failure',
          tag: 'PersonalInformationScreen');
      if (!mounted) return;
      setState(() => _error = _failureMessage(failure));
    } catch (e, stack) {
      AppLogger.error('Profile update crashed',
          tag: 'PersonalInformationScreen', error: e, stackTrace: stack);
      if (!mounted) return;
      setState(() => _error = 'Could not save changes. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _DeleteConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;
    await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      if (!mounted) return;
      // The router's auth guard already bounces — this is belt-and-
      // suspenders so we don't depend on listener timing.
      context.goNamed('onboarding');
    } on AuthFailure catch (failure) {
      AppLogger.warning('Account deletion failed: $failure',
          tag: 'PersonalInformationScreen');
      if (!mounted) return;
      setState(() => _error = _failureMessage(failure));
    } catch (e, stack) {
      AppLogger.error('Account deletion crashed',
          tag: 'PersonalInformationScreen', error: e, stackTrace: stack);
      if (!mounted) return;
      setState(() => _error = 'Could not delete account. Please try again.');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  static String _failureMessage(AuthFailure failure) {
    if (failure is NetworkFailure) {
      return 'Network error. Check your connection.';
    }
    if (failure is InvalidCredentialsFailure) {
      return 'Your session expired. Please sign in again.';
    }
    if (failure is ServerFailure) return 'Server error. Please try again.';
    if (failure is AuthApiFailure) return failure.message;
    return 'Something went wrong.';
  }

  void _showSnack(String message, {required bool destructive}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: destructive ? AppColors.fucsia : AppColors.indigo,
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: destructive ? Colors.white : AppColors.violetaClaro,
          ),
        ),
      ),
    );
  }

  /// Masks a DNI so only the first 2 and last 1 characters are visible.
  /// Example: '72345678' → '72•••••8'
  static String _maskDni(String dni) {
    if (dni.length <= 3) return dni;
    final visible = dni.substring(0, 2);
    final last = dni.substring(dni.length - 1);
    final masked = '•' * (dni.length - 3);
    return '$visible$masked$last';
  }

  /// Masks an email — first 2 local-part characters + '***@domain'.
  /// Matches the masking used in the password-change popup.
  static String _maskEmail(String email) {
    try {
      final parts = email.split('@');
      if (parts.length != 2) return email;
      final local = parts[0];
      final domain = parts[1];
      if (local.length <= 2) return '$local***@$domain';
      return '${local.substring(0, 2)}***@$domain';
    } catch (_) {
      return email;
    }
  }

  void _onTabSelected(SkeenNavTab tab) {
    switch (tab) {
      case SkeenNavTab.home:
        context.goNamed('home');
      case SkeenNavTab.history:
        context.goNamed('history');
      case SkeenNavTab.scan:
        context.pushNamed('scan-a-mole');
      case SkeenNavTab.experts:
        context.goNamed('experts');
      case SkeenNavTab.profile:
        context.goNamed('profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider.select((s) => s.user));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.55,
                child: SkeenStarField(seed: 33, density: 16),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                SkeenTopAppBar(
                  title: 'Personal Information'.tr,
                  subtitle: 'edit your details'.tr,
                ),
                Expanded(
                  child: user == null
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.violeta,
                            strokeWidth: 2,
                          ),
                        )
                      : SingleChildScrollView(
                          padding:
                              const EdgeInsets.fromLTRB(20, 20, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _SectionHeader(text: 'IDENTITY'),
                              const SizedBox(height: 12),
                              SkeenTextField(
                                label: 'First name',
                                controller: _nameCtrl,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 8),
                              SkeenTextField(
                                label: 'Last name',
                                controller: _lastNameCtrl,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 8),
                              SkeenTextField(
                                label: 'Phone',
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9+\s\-]'),
                                  ),
                                ],
                                textInputAction: TextInputAction.done,
                              ),
                              const SizedBox(height: 18),
                              const _SectionHeader(text: 'LOCKED'),
                              const SizedBox(height: 12),
                              _LockedField(
                                label: 'DNI',
                                value: _maskDni(user.dni),
                                hint:
                                    'Government ID — contact support to change.',
                              ),
                              const SizedBox(height: 12),
                              _LockedField(
                                label: 'Email',
                                value: _maskEmail(user.email),
                                hint:
                                    'Used to sign in — change is not yet supported.',
                              ),
                              const SizedBox(height: 24),
                              if (_error != null)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 13,
                                      color: AppColors.fucsia,
                                    ),
                                  ),
                                ),
                              _SaveButton(
                                enabled: _isDirty && _isValid,
                                loading: _saving,
                                onPressed: _save,
                              ),
                              const SizedBox(height: 32),
                              _DangerZone(
                                onDelete: _deleting ? null : _confirmDelete,
                                deleting: _deleting,
                              ),
                            ],
                          ),
                        ),
                ),
                SkeenBottomNav(
                  activeTab: SkeenNavTab.profile,
                  onTabSelected: _onTabSelected,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w600,
        fontSize: 12,
        letterSpacing: 0.6,
        color: Color(0xFF8B76E1),
      ),
    );
  }
}

class _LockedField extends StatelessWidget {
  const _LockedField({
    required this.label,
    required this.value,
    required this.hint,
  });

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.stroke.withValues(alpha: 0.5)),
        color: AppColors.indigo.withValues(alpha: 0.35),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    letterSpacing: -0.12,
                    color: Color(0xFF817691),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    letterSpacing: -0.16,
                    color: AppColors.hintText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Color(0xFF6B6098),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.lock_outline, size: 16, color: Color(0xFF6B6098)),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: enabled
              ? AppColors.violeta
              : AppColors.violeta.withValues(alpha: 0.35),
          disabledBackgroundColor:
              AppColors.violeta.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        onPressed: enabled && !loading ? onPressed : null,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                'Save changes'.tr,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  letterSpacing: -0.16,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.onDelete, required this.deleting});
  final VoidCallback? onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(text: 'DANGER ZONE'),
        const SizedBox(height: 8),
        Text(
          ('Deleting your account removes your sign-in credentials immediately. '
          'Your medical history is retained for traceability and is no longer '
          'accessible from this app.').tr,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            height: 1.5,
            color: AppColors.hintText,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: AppColors.fucsia.withValues(alpha: 0.55),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            onPressed: onDelete,
            child: deleting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.fucsia),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline,
                          size: 18, color: AppColors.fucsia),
                      SizedBox(width: 8),
                      Text(
                        'Delete account'.tr,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                          color: AppColors.fucsia,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1A44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2F1B66)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      title: Text(
        'Delete account?'.tr,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 18,
          color: AppColors.violetaClaro,
        ),
      ),
      content: Text(
        ('This signs you out and removes your sign-in credentials. The action '
        'cannot be undone from the app.').tr,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          height: 1.5,
          color: AppColors.hintText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel'.tr,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              color: AppColors.violetaLink,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'Delete'.tr,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              color: AppColors.fucsia,
            ),
          ),
        ),
      ],
    );
  }
}
