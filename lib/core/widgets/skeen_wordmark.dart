import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class SkeenWordmark extends StatelessWidget {
  const SkeenWordmark({super.key, this.fontSize = 36});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      const TextSpan(
        children: [
          TextSpan(text: 's', style: TextStyle(color: AppColors.violeta)),
          TextSpan(text: 'keen', style: TextStyle(color: AppColors.naranja)),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: 1.5,
        letterSpacing: -0.01 * fontSize,
      ),
    );
  }
}
