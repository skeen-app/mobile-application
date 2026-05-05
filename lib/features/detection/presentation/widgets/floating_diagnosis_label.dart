import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/class_label.dart';
import '../../domain/inference_result.dart';

/// "Augmented Result" card — Task 3 of the AR-AI bridge.
///
/// Per the spec (#9 in the latest brief), every lesion classification
/// surfaces with elevated visual weight; the difference between malignant
/// and benign is communicated through accent color, not size.
class FloatingDiagnosisLabel extends StatelessWidget {
  const FloatingDiagnosisLabel({super.key, required this.result});

  final InferenceResult result;

  Color _accent() {
    switch (result.warningLevel) {
      case WarningLevel.alert:
        return AppColors.fucsia;
      case WarningLevel.caution:
        return AppColors.naranja;
      case WarningLevel.reassuring:
        return AppColors.turquesa;
    }
  }

  String _warningCopy() {
    switch (result.warningLevel) {
      case WarningLevel.alert:
        return 'High-risk lesion · consult a dermatologist';
      case WarningLevel.caution:
        return 'Atypical pattern · clinical review recommended';
      case WarningLevel.reassuring:
        return 'Benign pattern · routine self-monitoring';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    final pct = (result.confidence * 100).toStringAsFixed(0);
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.92),
          border: Border.all(color: accent, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.45),
              blurRadius: 22,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: accent, blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'AR DIAGNOSIS',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 9,
                    letterSpacing: 1.2,
                    color: accent,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$pct%',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result.topLabel.display,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                letterSpacing: -0.16,
                color: AppColors.violetaClaro,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _warningCopy(),
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: 11,
                height: 1.4,
                color: AppColors.hintText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
