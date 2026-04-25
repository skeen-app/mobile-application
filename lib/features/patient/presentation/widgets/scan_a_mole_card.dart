import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_star_field.dart';

/// Primary CTA on the home dashboard — routes the user into the Detection
/// context. Visually mirrors Figma `82:242 / Buttons (95:398)`.
///
/// Decoration: a constellation of twinkling stars (`SkeenStarField`) drifts
/// behind a flat, fully-opaque telescope illustration so the icon stays
/// readable even on small phones.
class ScanAMoleCard extends StatelessWidget {
  const ScanAMoleCard({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.violeta,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onPressed,
        child: Container(
          height: 97,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const SizedBox(
                width: 92,
                height: 85,
                child: _TelescopeStage(),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan a mole',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        height: 1.5,
                        letterSpacing: -0.16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'AI analysis in seconds',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        height: 1.5,
                        letterSpacing: -0.11,
                        color: Color(0xCCEDE9FE),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 47,
                height: 47,
                decoration: BoxDecoration(
                  color: const Color(0xFF9057F0),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.arrow_forward,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated star field as the background, telescope SVG as the foreground.
class _TelescopeStage extends StatelessWidget {
  const _TelescopeStage();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          child: SkeenStarField(seed: 11, density: 12),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: SvgPicture.asset(
              'assets/images/home/scan_telescope.svg',
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(
                AppColors.violetaClaro,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
