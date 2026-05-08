import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/capture_quality.dart';

/// Live readiness checklist overlay positioned below the AR reticle.
/// Shows 4 items (Lighting, Focus, Distance, Stability) with animated
/// check/cross icons and color transitions. Matches the GuidancePill
/// design pattern from Figma (153:465).
class ReadinessChecklistOverlay extends StatelessWidget {
  const ReadinessChecklistOverlay({
    super.key,
    required this.readiness,
  });

  final CaptureReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final items = readiness.checklist;
    final allReady = readiness.isReady;

    return Positioned(
      left: 20,
      right: 20,
      bottom: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.85),
          border: Border.all(
            color: allReady
                ? AppColors.turquesa.withValues(alpha: 0.6)
                : AppColors.violetaOscuro,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: allReady ? AppColors.turquesa : AppColors.naranja,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: allReady
                            ? AppColors.turquesa.withValues(alpha: 0.5)
                            : AppColors.naranja.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  allReady ? 'READY TO CAPTURE' : 'PREPARING CAPTURE',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 9,
                    letterSpacing: 1.2,
                    color: allReady ? AppColors.turquesa : AppColors.naranja,
                  ),
                ),
                const Spacer(),
                Text(
                  '${readiness.passedCount}/4',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: allReady ? AppColors.turquesa : AppColors.hintText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _ChecklistItem(
                    label: item.label,
                    passed: item.passed,
                    hint: item.hint,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.label,
    required this.passed,
    required this.hint,
  });

  final String label;
  final bool passed;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Icon(
            passed ? Icons.check_circle : Icons.radio_button_unchecked,
            key: ValueKey(passed),
            color: passed ? const Color(0xFF22C55E) : AppColors.hintText,
            size: 16,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label — $hint',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              fontSize: 10,
              color: passed
                  ? AppColors.violetaClaro
                  : AppColors.hintText.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
