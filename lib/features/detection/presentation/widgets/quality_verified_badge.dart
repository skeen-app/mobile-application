import 'package:skeen/core/localization/locale_controller.dart';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Turquoise "Quality Verified" glassmorphism badge from the Figma tamizaje
/// screen (153:646). Overlays the captured image card to confirm that the
/// capture passed all readiness checks.
class QualityVerifiedBadge extends StatelessWidget {
  const QualityVerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.turquesa.withValues(alpha: 0.20),
            border: Border.all(
              color: AppColors.turquesa.withValues(alpha: 0.30),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(9999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 15,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_outlined,
                color: AppColors.turquesa,
                size: 16,
              ),
              SizedBox(width: 8),
              Text(
                'Quality Verified'.tr,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.turquesa,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
