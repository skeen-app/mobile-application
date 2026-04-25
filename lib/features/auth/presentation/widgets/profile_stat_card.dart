import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Single tile in the "Health Stats Row" — gradient indigo card with a
/// 2-line uppercase label and a large value text. The decorative icon in
/// the bottom-right corner is supplied by the caller (or omitted).
class ProfileStatCard extends StatelessWidget {
  const ProfileStatCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor = AppColors.violetaClaro,
    this.decoration,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Widget? decoration;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xCC1C1A44),
            Color(0xE6181640),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A1F66)),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.6,
                  height: 1.4,
                  color: Color(0xFF8B76E1),
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  height: 1.2,
                  color: valueColor,
                ),
              ),
            ],
          ),
          if (decoration != null)
            Positioned(
              right: -16,
              bottom: -16,
              width: 50,
              height: 50,
              child: Opacity(opacity: 0.55, child: decoration!),
            ),
        ],
      ),
    );
  }
}
