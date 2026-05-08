import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/capture_quality.dart';

/// Camera-style shutter for the AR scan screen. Tinted by the live
/// [CaptureQuality]: violet for excellent, turquoise for good, orange when
/// the user should adjust framing or lighting before capturing.
class ScanCaptureButton extends StatelessWidget {
  const ScanCaptureButton({
    super.key,
    required this.quality,
    required this.onPressed,
    required this.isCapturing,
  });

  final CaptureQuality quality;
  final VoidCallback onPressed;
  final bool isCapturing;

  Color _ringColor() {
    switch (quality.level) {
      case CaptureQualityLevel.poor:
        return AppColors.fucsia;
      case CaptureQualityLevel.acceptable:
        return AppColors.naranja;
      case CaptureQualityLevel.good:
        return AppColors.turquesa;
      case CaptureQualityLevel.excellent:
        return AppColors.violetaClaro;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ring = _ringColor();
    return GestureDetector(
      onTap: isCapturing ? null : onPressed,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 4),
          boxShadow: [
            BoxShadow(
              color: ring.withValues(alpha: 0.35),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCapturing
                  ? AppColors.violetaOscuro
                  : AppColors.violeta,
            ),
            child: isCapturing
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.violetaClaro,
                        ),
                      ),
                    ),
                  )
                : const Icon(
                    Icons.camera_alt_rounded,
                    color: AppColors.violetaClaro,
                    size: 28,
                  ),
          ),
        ),
      ),
    );
  }
}
