import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class SkeenStepIndicator extends StatelessWidget {
  const SkeenStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  })  : assert(totalSteps > 0),
        assert(currentStep >= 1 && currentStep <= totalSteps);

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: List.generate(totalSteps, (index) {
            final filled = index < currentStep;
            return Expanded(
              child: Container(
                height: 10,
                margin: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : 6),
                decoration: BoxDecoration(
                  color: filled ? AppColors.violeta : AppColors.violetaOscuro,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        Text(
          '$currentStep of $totalSteps steps',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            letterSpacing: -0.16,
            color: Color(0xFF8B76E1),
          ),
        ),
      ],
    );
  }
}
