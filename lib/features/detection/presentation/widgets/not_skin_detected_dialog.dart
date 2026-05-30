import 'package:flutter/material.dart';
import 'package:skeen/core/localization/locale_controller.dart';

import '../../../../core/theme/app_colors.dart';

/// Educational modal shown when the cascade's stage-1 model rejects the
/// captured frame as "not skin". Shared by the AR capture screen and the
/// gallery upload screen so the user sees the same guidance regardless of
/// the entry point.
///
/// Returns `true` when the user taps the "Try again" CTA, `false` (or
/// `null`) when the dialog is dismissed by the system back gesture.
class NotSkinDetectedDialog extends StatelessWidget {
  const NotSkinDetectedDialog({super.key});

  /// Convenience launcher. The dialog is non-dismissible by tapping outside
  /// so the user has to acknowledge the rejection explicitly.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NotSkinDetectedDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.violetaOscuro),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.naranja.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.visibility_off_outlined,
                size: 30,
                color: AppColors.naranja,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No skin detected'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 18,
                letterSpacing: -0.18,
                color: AppColors.violetaClaro,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ('Make sure the photo is focused on a skin area with a visible '
                      'lesion. Avoid clothing, backgrounds, or blurry frames.')
                  .tr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                height: 1.5,
                color: AppColors.hintText,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.violeta,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                child: Text('Try again'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
