import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/tutorial_coach_mark.dart';
import '../../../../core/widgets/tutorial_controller.dart';
import '../../application/providers.dart';
import '../widgets/web_unsupported_card.dart';
import 'ar_scan_screen.dart';
import 'scan_a_mole_screen.dart';

/// Single entry point hit by `pushNamed('scan-a-mole')`. Probes the device
/// for AR + depth support and dispatches to:
///
///   • [WebUnsupportedCard]  → Web build (no ARKit/ARCore)
///   • [ArScanScreen]        → Mobile w/ AR + depth (LiDAR or ARCore Depth)
///   • [ScanAMoleScreen]     → Mobile fallback (no depth sensor)
///
/// Same routing surface as before so the home CTA and bottom-nav FAB
/// don't need to know which scan flow they are about to render.
class ScanRouterScreen extends ConsumerWidget {
  const ScanRouterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const WebUnsupportedCard();

    final tutorialStep = ref.watch(tutorialControllerProvider);

    final caps = ref.watch(arCapabilitiesProvider);

    final child = caps.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.violetaClaro),
          ),
        ),
      ),
      error: (_, _) => const ScanAMoleScreen(),
      data: (c) => c.canRunArBridge
          ? const ArScanScreen()
          : const ScanAMoleScreen(),
    );

    if (tutorialStep != TutorialStep.cameraCapture) {
      return child;
    }

    return Scaffold(
      body: Stack(
        children: [
          child,
          TutorialCoachMark(
            isFloatingTooltip: true,
            title: 'Capture your Mole',
            description:
                'Center the mole on your screen and use the AR camera to scan it '
                'in real-time, or tap the gallery icon to upload a photo.',
            onSkip: () => ref.read(tutorialControllerProvider.notifier).skip(),
          ),
        ],
      ),
    );
  }
}
