import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/class_label.dart';
import '../../domain/inference_result.dart';

/// "Augmented Result" card — the AR-anchored diagnosis popup.
///
/// Per the spec, every lesion classification surfaces with elevated visual
/// weight; the difference between malignant and benign is communicated
/// through accent color, not size. Includes entry animation and tap
/// callback to navigate to the triage result screen.
class FloatingDiagnosisLabel extends StatefulWidget {
  const FloatingDiagnosisLabel({
    super.key,
    required this.result,
    this.onTap,
  });

  final InferenceResult result;
  final VoidCallback? onTap;

  @override
  State<FloatingDiagnosisLabel> createState() => _FloatingDiagnosisLabelState();
}

class _FloatingDiagnosisLabelState extends State<FloatingDiagnosisLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _entry, curve: Curves.easeOutBack),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entry, curve: Curves.easeOut),
    );
    _entry.forward();
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  Color _accent() {
    switch (widget.result.warningLevel) {
      case WarningLevel.alert:
        return AppColors.fucsia;
      case WarningLevel.caution:
        return AppColors.naranja;
      case WarningLevel.reassuring:
        return AppColors.turquesa;
    }
  }

  String _warningCopy() {
    switch (widget.result.warningLevel) {
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
    final pct = (widget.result.confidence * 100).toStringAsFixed(0);
    return AnimatedBuilder(
      animation: _entry,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: child,
        ),
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Material(
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
                  widget.result.topLabel.display,
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
                if (widget.onTap != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Tap to view details →',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 9,
                      color: accent.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
