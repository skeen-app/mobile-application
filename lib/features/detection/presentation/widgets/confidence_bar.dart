import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';

/// Animated horizontal progress bar matching Figma tamizaje confidence display
/// (153:670). Background track: `#31305a`, fill: `#d2bbff`, 6px height,
/// pill-shaped. Shows "AI Confidence" label + percentage.
class ConfidenceBar extends StatelessWidget {
  const ConfidenceBar({
    super.key,
    required this.confidence,
  });

  /// Value from 0.0 to 1.0.
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).toStringAsFixed(0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'AI Confidence'.tr,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: Color(0xFFD2BBFF),
              ),
            ),
            Text(
              '$pct%',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 24,
                color: Color(0xFFD2BBFF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: const Color(0xFF31305A),
            borderRadius: BorderRadius.circular(9999),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    width: constraints.maxWidth * confidence.clamp(0.0, 1.0),
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD2BBFF),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
