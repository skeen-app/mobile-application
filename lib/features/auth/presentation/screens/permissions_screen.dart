import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../../../core/widgets/skeen_star_field.dart';
import '../../../../core/widgets/skeen_step_indicator.dart';

/// Step 1 of the post-registration onboarding funnel.
///
/// All switches start OFF. Toggling a switch ON triggers the corresponding
/// OS permission prompt synchronously — that is the whole point of this
/// screen. The visual switch state mirrors the *granted* status reported
/// by the platform: deny the prompt and the switch snaps back off.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _camera = false;
  bool _gallery = false;
  bool _notifications = false;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _hydrateFromOs();
  }

  /// Reflect any permissions the user has already accepted (e.g. the camera
  /// prompt fired during registration's profile-photo flow). Without this
  /// the switches would lie about the actual OS state.
  Future<void> _hydrateFromOs() async {
    final results = await Future.wait([
      Permission.camera.status,
      _galleryPermission().status,
      Permission.notification.status,
    ]);
    if (!mounted) return;
    setState(() {
      _camera = results[0].isGranted;
      _gallery = results[1].isGranted;
      _notifications = results[2].isGranted;
    });
  }

  /// `Permission.photos` covers iOS and Android 13+ (READ_MEDIA_IMAGES).
  /// On older Android the plugin transparently maps to legacy storage.
  Permission _galleryPermission() => Permission.photos;

  Future<void> _toggle({
    required bool currentValue,
    required Permission permission,
    required String permissionLabel,
    required void Function(bool) apply,
  }) async {
    if (_busy) return;

    // Switch OFF: apps can't programmatically revoke permissions, so we
    // bounce the user to system settings instead of silently lying.
    if (currentValue) {
      final goToSettings = await _confirmRevoke(permissionLabel);
      if (goToSettings == true) {
        await openAppSettings();
        await _hydrateFromOs();
      }
      return;
    }

    setState(() => _busy = true);
    final status = await permission.request();
    if (!mounted) return;
    setState(() {
      _busy = false;
      apply(status.isGranted);
    });

    if (status.isPermanentlyDenied) {
      await _showPermanentlyDeniedDialog(permissionLabel);
    }
  }

  Future<bool?> _confirmRevoke(String label) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.indigo,
        title: Text(
          'Revoke $label access?',
          style: const TextStyle(
            color: AppColors.violetaClaro,
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Permissions can only be revoked from system settings. Open them now?',
          style: const TextStyle(
            color: AppColors.hintText,
            fontFamily: 'Poppins',
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermanentlyDeniedDialog(String label) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.indigo,
        title: Text(
          '$label permission blocked',
          style: const TextStyle(
            color: AppColors.violetaClaro,
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: const Text(
          'You previously denied this permission. Enable it from system settings to continue.',
          style: TextStyle(
            color: AppColors.hintText,
            fontFamily: 'Poppins',
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: 100,
              left: 0,
              right: 0,
              height: 160,
              child: SkeenStarField(seed: 21, density: 16),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const SkeenStepIndicator(currentStep: 1, totalSteps: 2),
                  const SizedBox(height: 40),
                  const _AccessHeading(),
                  const SizedBox(height: 24),
                  const Text(
                    'In order to analyze and save your history',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      height: 1.5,
                      letterSpacing: -0.16,
                      color: AppColors.hintText,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _PermissionCard(
                    title: 'Camera',
                    description: 'To scan and analyze lunars',
                    iconPath: 'assets/images/camera_icon.svg',
                    iconBackground: const Color(0xFF381E75),
                    value: _camera,
                    onChanged: (_) => _toggle(
                      currentValue: _camera,
                      permission: Permission.camera,
                      permissionLabel: 'Camera',
                      apply: (granted) => _camera = granted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PermissionCard(
                    title: 'Gallery',
                    description: 'To scan and analyze lunars',
                    iconPath: 'assets/images/gallery_icon.svg',
                    iconBackground: const Color(0xFF172F5A),
                    value: _gallery,
                    onChanged: (_) => _toggle(
                      currentValue: _gallery,
                      permission: _galleryPermission(),
                      permissionLabel: 'Gallery',
                      apply: (granted) => _gallery = granted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PermissionCard(
                    title: 'Notifications',
                    description: 'To scan and analyze lunars',
                    iconPath: 'assets/images/notifications_icon.svg',
                    iconBackground: const Color(0xFF432338),
                    value: _notifications,
                    onChanged: (_) => _toggle(
                      currentValue: _notifications,
                      permission: Permission.notification,
                      permissionLabel: 'Notifications',
                      apply: (granted) => _notifications = granted,
                    ),
                  ),
                  const Spacer(),
                  SkeenButton.primary(
                    label: 'Continue',
                    onPressed: () => context.go('/onboarding/terms'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessHeading extends StatelessWidget {
  const _AccessHeading();

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: const TextSpan(
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 20,
          height: 1.2,
          letterSpacing: -0.2,
        ),
        children: [
          TextSpan(
            text: 's',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.violeta,
            ),
          ),
          TextSpan(
            text: 'keen',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.naranja,
            ),
          ),
          TextSpan(
            text: ' needs\naccess to',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: AppColors.violetaClaro,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.title,
    required this.description,
    required this.iconPath,
    required this.iconBackground,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final String iconPath;
  final Color iconBackground;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 93,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF24154B),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 69,
            height: 71,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: SvgPicture.asset(iconPath, width: 28, height: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    letterSpacing: -0.15,
                    color: AppColors.violetaClaro,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    height: 1.1,
                    letterSpacing: -0.13,
                    color: AppColors.hintText,
                  ),
                ),
              ],
            ),
          ),
          _PillSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _PillSwitch extends StatelessWidget {
  const _PillSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 47,
        height: 23,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? AppColors.violeta : const Color(0xFF331C6B),
          borderRadius: BorderRadius.circular(11.5),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 17,
            height: 17,
            decoration: const BoxDecoration(
              color: AppColors.violetaClaro,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
