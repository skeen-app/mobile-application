import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../../../core/widgets/skeen_star_field.dart';

class ForgotPasswordSuccessScreen extends StatelessWidget {
  const ForgotPasswordSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: 100,
              left: 0,
              right: 0,
              height: 160,
              child: SkeenStarField(seed: 12, density: 24),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  const Icon(
                    Icons.mark_email_read_outlined,
                    color: AppColors.turquesa,
                    size: 80,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Check your email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.24,
                      color: AppColors.violetaClaro,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your request has been received. You will soon receive an email with instructions to follow.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      height: 1.4,
                      letterSpacing: -0.16,
                      color: AppColors.hintText,
                    ),
                  ),
                  const Spacer(),
                  SkeenButton.primary(
                    label: 'Back to login',
                    onPressed: () => context.go('/login'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
