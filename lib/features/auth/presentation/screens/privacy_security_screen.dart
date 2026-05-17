import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/notifications/notifications_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../application/auth_controller.dart';
import '../../application/privacy_settings.dart';
import '../../domain/auth_failure.dart';

class PrivacySecurityScreen extends ConsumerWidget {
  const PrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(privacySettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            SkeenTopAppBar(
              title: 'Privacy & Security'.tr,
              subtitle: 'manage your data'.tr,
              showBack: true,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _CloudSyncTile(
                    enabled: settings.cloudSyncEnabled,
                    onChanged: (v) => ref
                        .read(privacySettingsProvider.notifier)
                        .setCloudSyncEnabled(v),
                  ),
                  const SizedBox(height: 16),
                  _SectionHeader(label: 'ACCOUNT'.tr),
                  const SizedBox(height: 8),
                  _ChangePasswordRow(
                    onTap: () => _onChangePassword(context, ref),
                  ),
                  const SizedBox(height: 16),
                  _SectionHeader(label: 'YOUR DATA'.tr),
                  const SizedBox(height: 8),
                  _PolicyCard(
                    title: 'How your scans are stored'.tr,
                    body: ('Every photo is encrypted on your device with AES-256 '
                            'before being persisted. Even when cloud sync is on, '
                            'the image is uploaded to a private bucket tied to '
                            'your account — only you can request a download URL.')
                        .tr,
                    icon: Icons.lock_outline,
                  ),
                  const SizedBox(height: 12),
                  _PolicyCard(
                    title: 'What we never store'.tr,
                    body: ('Your name, DNI and contact details are kept on your '
                            'profile only. They are never written into the scan '
                            'documents or filenames — the cloud copy is anonymous.')
                        .tr,
                    icon: Icons.shield_moon_outlined,
                  ),
                ],
              ),
            ),
            SkeenBottomNav(
              activeTab: SkeenNavTab.profile,
              onTabSelected: (tab) {
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
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _onChangePassword(BuildContext context, WidgetRef ref) async {
  final email = ref.read(authControllerProvider).user?.email;
  if (email == null) return;
  final maskedPreview = _maskedPreview(email);

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _ChangePasswordSheet(maskedEmail: maskedPreview),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  final auth = ref.read(authControllerProvider);
  final token = auth.token;
  if (token == null) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final result =
        await ref.read(authApiProvider).requestMyPasswordReset(token: token);
    ref.notifications.recordPasswordChanged();
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.indigo,
        content: Text(
          'Instructions sent to ${result.maskedEmail}',
          style: const TextStyle(color: AppColors.violetaClaro),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  } on AuthFailure catch (failure) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  } catch (_) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Could not send instructions'.tr)),
    );
  }
}

String _maskedPreview(String email) {
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 1.0,
          color: Color(0xFF7B6BB6),
        ),
      ),
    );
  }
}

class _ChangePasswordRow extends StatelessWidget {
  const _ChangePasswordRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1444),
            border: Border.all(color: const Color(0xFF2F1B66)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.violeta.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.lock_reset_outlined,
                  color: AppColors.violeta,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Change password'.tr,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppColors.violetaClaro,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Send reset instructions to your email'.tr,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: Color(0xFFCCC3D8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFF958DA1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends StatelessWidget {
  const _ChangePasswordSheet({required this.maskedEmail});
  final String maskedEmail;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.violetaOscuro),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hintText.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.violeta.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.lock_reset_outlined,
                color: AppColors.violeta,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Reset your password'.tr,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 18,
                letterSpacing: -0.18,
                color: AppColors.violetaClaro,
              ),
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        "We'll email password reset instructions to ".tr,
                  ),
                  TextSpan(
                    text: maskedEmail,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.violetaClaro,
                    ),
                  ),
                  TextSpan(
                    text: ". Tap the link in the email to set a new password.".tr,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w400,
                fontSize: 13,
                height: 1.5,
                color: Color(0xFFCCC3D8),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.violetaClaro,
                      side: const BorderSide(color: Color(0xFF44248D)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('Cancel'.tr),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.violeta,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('Send'.tr),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudSyncTile extends StatelessWidget {
  const _CloudSyncTile({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1444),
        border: Border.all(color: const Color(0xFF2F1B66)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.violeta.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.cloud_sync_outlined,
                  color: AppColors.violeta,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cloud sync of scans'.tr,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.violetaClaro,
                  ),
                ),
              ),
              Switch(
                value: enabled,
                onChanged: onChanged,
                activeThumbColor: AppColors.violeta,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ('When ON, your captured lesion photos are uploaded to a private '
            'bucket so you can access them from any device and your '
            'history is backed up. The image is re-encrypted at rest in '
            'cloud and never tied to your name or DNI. When OFF, scans '
            'stay only on this phone.').tr,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: 12,
              height: 1.5,
              color: Color(0xFFCCC3D8),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A123E),
        border: Border.all(color: const Color(0xFF2A1F5C)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.violetaClaro),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.violetaClaro,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: 11,
                    height: 1.5,
                    color: Color(0xFF9C92C5),
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
