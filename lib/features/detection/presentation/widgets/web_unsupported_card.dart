import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/skeen_button.dart';
import '../../../../core/widgets/skeen_top_app_bar.dart';

/// Web build target. The AR-AI bridge depends on ARKit/ARCore, both of
/// which are mobile-only — so on the web we surface a clear "use the
/// mobile app" card instead of pretending the feature works.
class WebUnsupportedCard extends StatelessWidget {
  const WebUnsupportedCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const SkeenTopAppBar(
              title: 'Scan a mole',
              subtitle: 'AI analysis in seconds',
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.indigo,
                  border: Border.all(color: AppColors.violetaOscuro),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.smartphone_rounded,
                      color: AppColors.violetaClaro,
                      size: 56,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'AR scan is mobile-only',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.violetaClaro,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "skeen's AR-guided lesion analysis uses ARKit (iOS) "
                      'and ARCore (Android) for real-time depth and anchor '
                      'tracking. Open the mobile app on your phone to '
                      'continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        height: 1.5,
                        color: AppColors.hintText,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SkeenButton.primary(
                      label: 'Back to home',
                      onPressed: () => context.go('/home'),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
