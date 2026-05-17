import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_brand_mark.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../../../core/widgets/skeen_wordmark.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned(
                  top: constraints.maxHeight * 0.06,
                  left: 10,
                  right: 10,
                  height: constraints.maxHeight * 0.40,
                  child: const SkeenBrandMark(),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 32,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SkeenWordmark(),
                      const SizedBox(height: 50),
                      Text(
                        'Your personal shield against skin cancer'.tr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          height: 1.5,
                          letterSpacing: -0.18,
                          color: AppColors.hintText,
                        ),
                      ),
                      const SizedBox(height: 50),
                      SkeenButton.primary(
                        label: 'Create an account',
                        onPressed: () => context.go('/register'),
                      ),
                      const SizedBox(height: 20),
                      SkeenButton.secondary(
                        label: 'I already have an account',
                        onPressed: () => context.go('/login'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
