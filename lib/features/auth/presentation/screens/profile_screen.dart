import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_star_field.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';
import '../../application/auth_controller.dart';
import '../../application/profile_providers.dart';
import '../../domain/patient_profile_summary.dart';
import '../../domain/registered_user.dart';
import '../widgets/avatar_action_sheet.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_settings_row.dart';
import '../widgets/profile_stat_card.dart';

/// Profile dashboard — Auth bounded context.
///
/// Reads identity from `authControllerProvider` — `avatarUrl`, `lastScanAt`
/// and the rest of the user record are persisted at register/login time, so
/// rendering this screen requires no network call. The registered-moles
/// counter is computed from the local lesion repository.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Bumped after every successful upload to force `Image.network` to drop
  /// any cached bytes. The persisted `avatarUrl` itself is never modified.
  int _avatarRefreshToken = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider.select((s) => s.user));
    final summaryAsync = ref.watch(profileSummaryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.55,
                child: SkeenStarField(seed: 27, density: 16),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                SkeenTopAppBar(
                  title: 'Profile',
                  subtitle: 'your personal info',
                  onBack: () {
                    final router = GoRouter.of(context);
                    if (router.canPop()) {
                      router.pop();
                    } else {
                      router.goNamed('home');
                    }
                  },
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, viewport) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: viewport.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 20, 20, 16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  _ProfileHeader(
                                    user: user,
                                    avatarRefreshToken: _avatarRefreshToken,
                                    onAvatarTap: () =>
                                        _onAvatarTap(context, ref, user),
                                  ),
                                  const SizedBox(height: 18),
                                  _StatsRow(summary: summaryAsync),
                                  const SizedBox(height: 18),
                                  _SettingsSection(),
                                  const SizedBox(height: 24),
                                  _LogoutButton(
                                    onPressed: () =>
                                        _onLogout(context, ref),
                                  ),
                                  const Spacer(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SkeenBottomNav(
                  activeTab: SkeenNavTab.profile,
                  onTabSelected: (tab) => _onTabSelected(context, tab),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onAvatarTap(
    BuildContext context,
    WidgetRef ref,
    RegisteredUser? user,
  ) async {
    final hasPhoto = (user?.avatarUrl ?? '').isNotEmpty;
    final action = await showAvatarActionSheet(
      context,
      hasExistingPhoto: hasPhoto,
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case AvatarAction.takePhoto:
        await _pickAndUpload(context, ref, ImageSource.camera);
      case AvatarAction.uploadPhoto:
        await _pickAndUpload(context, ref, ImageSource.gallery);
      case AvatarAction.deletePhoto:
        // Backend DELETE endpoint not yet available.
        _showSnackBar(context, 'Photo removal coming soon');
    }
  }

  Future<void> _pickAndUpload(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } catch (_) {
      if (!context.mounted) return;
      _showSnackBar(
        context,
        source == ImageSource.camera
            ? 'Could not open the camera'
            : 'Could not open the gallery',
      );
      return;
    }
    if (picked == null || !context.mounted) return;

    // Read bytes — works on every platform (web has no dart:io File).
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;

    final filename = picked.name.isNotEmpty ? picked.name : 'avatar.jpg';
    final mimeType = picked.mimeType ?? _mimeFromName(filename);

    _showSnackBar(context, 'Uploading photo…');

    try {
      final newUrl = await ref
          .read(authControllerProvider.notifier)
          .uploadProfilePhoto(
            bytes: bytes,
            filename: filename,
            mimeType: mimeType,
          );

      // The backend overwrites `profiles/{uid}.{ext}`, so the URL is
      // identical across uploads. Drop the cached bytes for that URL and
      // bump the refresh token so `Image.network` rebuilds with a fresh
      // stream — without ever modifying the persisted URL itself.
      final provider = NetworkImage(newUrl);
      await provider.evict();

      if (!mounted) return;
      setState(() => _avatarRefreshToken++);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showSnackBar(context, 'Profile photo updated ✓');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showSnackBar(context, 'Upload failed — please try again');
    }
  }

  static String _mimeFromName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.indigo,
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: AppColors.violetaClaro,
          ),
        ),
      ),
    );
  }

  Future<void> _onLogout(BuildContext context, WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).signOut();
    if (!context.mounted) return;
    context.goNamed('onboarding');
  }

  void _onTabSelected(BuildContext context, SkeenNavTab tab) {
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
        return;
    }
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.avatarRefreshToken,
    required this.onAvatarTap,
  });

  final RegisteredUser? user;
  final int avatarRefreshToken;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1A44),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A1F66)),
      ),
      child: Column(
        children: [
          ProfileAvatar(
            photoUrl: user?.avatarUrl,
            onTap: onAvatarTap,
            refreshToken: avatarRefreshToken,
          ),
          const SizedBox(height: 12),
          Text(
            user?.fullName ?? 'Welcome',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 22,
              height: 1.3,
              color: AppColors.violetaClaro,
            ),
          ),
          if ((user?.email ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              user!.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF8B76E1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.summary});
  final AsyncValue<PatientProfileSummary> summary;

  @override
  Widget build(BuildContext context) {
    final value = summary.valueOrNull;
    final molesText = summary.isLoading && value == null
        ? '—'
        : (value?.registeredMoles ?? 0).toString();
    final nextCheckupText = _formatNextCheckup(value?.nextCheckupAt);

    return Row(
      children: [
        Expanded(
          child: ProfileStatCard(
            label: 'Registered\nMoles',
            value: molesText,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: ProfileStatCard(
            label: 'Next Checkup',
            value: nextCheckupText,
            valueColor: const Color(0xFFFFB690),
          ),
        ),
      ],
    );
  }

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _formatNextCheckup(DateTime? at) {
    if (at == null) return 'No scans yet';
    return '${_months[at.month - 1]} ${at.year}';
  }
}

class _SettingsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1A44),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A1F66)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          ProfileSettingsRow(
            iconAsset: 'assets/images/profile/personal_info.svg',
            label: 'Personal Information',
            onTap: () => context.pushNamed('personal-info'),
          ),
          const _Divider(),
          ProfileSettingsRow(
            iconAsset: 'assets/images/profile/medical_history.svg',
            label: 'Medical History',
            onTap: () => context.pushNamed('history'),
          ),
          const _Divider(),
          ProfileSettingsRow(
            iconAsset: 'assets/images/profile/privacy_security.svg',
            label: 'Privacy & Security',
            onTap: () => context.pushNamed('privacy-security'),
          ),
          const _Divider(),
          ProfileSettingsRow(
            iconAsset: 'assets/images/profile/notifications.svg',
            label: 'Notifications',
            onTap: () => context.pushNamed('notifications'),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      color: const Color(0xFF2A1F66),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onPressed,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: AppColors.violeta.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/images/profile/logout.svg',
                width: 16,
                height: 16,
                colorFilter: const ColorFilter.mode(
                  AppColors.violeta,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Logout',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  height: 1.5,
                  color: AppColors.violeta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
