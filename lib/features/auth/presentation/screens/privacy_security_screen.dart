import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../application/privacy_settings.dart';

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
            const SkeenTopAppBar(
              title: 'Privacy & Security',
              subtitle: 'manage your data',
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
                  _PolicyCard(
                    title: 'How your scans are stored',
                    body:
                        'Every photo is encrypted on your device with AES-256 '
                        'before being persisted. Even when cloud sync is on, '
                        'the image is uploaded to a private bucket tied to '
                        'your account — only you can request a download URL.',
                    icon: Icons.lock_outline,
                  ),
                  const SizedBox(height: 12),
                  _PolicyCard(
                    title: 'What we never store',
                    body:
                        'Your name, DNI and contact details are kept on your '
                        'profile only. They are never written into the scan '
                        'documents or filenames — the cloud copy is anonymous.',
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
              const Expanded(
                child: Text(
                  'Cloud sync of scans',
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
          const Text(
            'When ON, your captured lesion photos are uploaded to a private '
            'bucket so you can access them from any device and your '
            'history is backed up. The image is re-encrypted at rest in '
            'cloud and never tied to your name or DNI. When OFF, scans '
            'stay only on this phone.',
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
