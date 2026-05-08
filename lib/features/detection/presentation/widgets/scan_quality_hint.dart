import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/capture_quality.dart';

/// Floating glass card that surfaces the live capture-quality assessment
/// to non-expert users. Displayed above the shutter so it stays readable
/// against the camera preview.
class ScanQualityHint extends StatelessWidget {
  const ScanQualityHint({super.key, required this.quality});

  final CaptureQuality quality;

  Color _accent() {
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

  IconData _icon() {
    switch (quality.level) {
      case CaptureQualityLevel.poor:
        return Icons.lightbulb_outline;
      case CaptureQualityLevel.acceptable:
        return Icons.wb_sunny_outlined;
      case CaptureQualityLevel.good:
        return Icons.center_focus_strong_outlined;
      case CaptureQualityLevel.excellent:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.indigo.withValues(alpha: 0.78),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon(), color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  quality.label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: -0.13,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  quality.hint,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    height: 1.35,
                    color: AppColors.textPrimary,
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
