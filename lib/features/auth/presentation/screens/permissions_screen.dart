import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../../../core/widgets/skeen_star_field.dart';
import '../../../../core/widgets/skeen_step_indicator.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _camera = true;
  bool _gallery = false;
  bool _notifications = true;

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
                  const SkeenStepIndicator(currentStep: 1, totalSteps: 3),
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
                    onChanged: (v) => setState(() => _camera = v),
                  ),
                  const SizedBox(height: 16),
                  _PermissionCard(
                    title: 'Gallery',
                    description: 'To scan and analyze lunars',
                    iconPath: 'assets/images/gallery_icon.svg',
                    iconBackground: const Color(0xFF172F5A),
                    value: _gallery,
                    onChanged: (v) => setState(() => _gallery = v),
                  ),
                  const SizedBox(height: 16),
                  _PermissionCard(
                    title: 'Notifications',
                    description: 'To scan and analyze lunars',
                    iconPath: 'assets/images/notifications_icon.svg',
                    iconBackground: const Color(0xFF432338),
                    value: _notifications,
                    onChanged: (v) => setState(() => _notifications = v),
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
