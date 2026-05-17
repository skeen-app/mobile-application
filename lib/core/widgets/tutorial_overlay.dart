
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'tutorial_storage.dart';

/// Three-step animated tutorial overlay shown to newly registered users.
///
/// Steps:
///   1. Where to scan — spotlight on the bottom-nav Scan button
///   2. How to scan  — full-card with camera icon explanation
///   3. Download PDF — full-card with PDF icon explanation
///
/// The overlay is a transparent route pushed on top of the home screen so
/// it can paint a scrim + coach-mark cards while the real UI is visible
/// underneath. Completing or skipping persists the flag via [TutorialStorage].
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.scanButtonCenter,
    required this.scanButtonRadius,
  });

  /// Center of the "Scan" button in global coordinates, used by step 1
  /// to punch the spotlight hole.
  final Offset scanButtonCenter;

  /// Radius of the spotlight circle around the Scan button.
  final double scanButtonRadius;

  /// Push the tutorial on top of the current route.
  static Future<void> show(
    BuildContext context, {
    required Offset scanButtonCenter,
    required double scanButtonRadius,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) => TutorialOverlay(
          scanButtonCenter: scanButtonCenter,
          scanButtonRadius: scanButtonRadius,
        ),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0; // 0, 1, 2
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  static const _steps = [
    _TutorialStep(
      title: 'Start a Scan',
      description:
          'Tap the Scan button at the center of the navigation bar to '
          'begin analyzing a mole on your skin.',
      icon: Icons.center_focus_strong_rounded,
      hasSpotlight: true,
    ),
    _TutorialStep(
      title: 'Capture your Mole',
      description:
          'Use the AR camera to scan in real-time, or upload a photo '
          'from your gallery. Our AI will analyze the lesion instantly.',
      icon: Icons.camera_alt_rounded,
      hasSpotlight: false,
    ),
    _TutorialStep(
      title: 'Download your Report',
      description:
          'After the analysis, download a detailed PDF report to share '
          'with your dermatologist for professional follow-up.',
      icon: Icons.picture_as_pdf_rounded,
      hasSpotlight: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  void _finish() {
    TutorialStorage.markCompleted();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // ── Scrim + spotlight ──────────────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ScrimPainter(
                    spotlightCenter:
                        step.hasSpotlight ? widget.scanButtonCenter : null,
                    spotlightRadius: widget.scanButtonRadius,
                    pulseValue: _pulseAnimation.value,
                  ),
                );
              },
            ),
          ),

          // ── Pulsing ring around the scan button (step 1 only) ──
          if (step.hasSpotlight)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, _) {
                final extra = 8.0 + 6.0 * _pulseAnimation.value;
                final opacity = 0.7 - 0.3 * _pulseAnimation.value;
                return Positioned(
                  left: widget.scanButtonCenter.dx -
                      widget.scanButtonRadius -
                      extra,
                  top: widget.scanButtonCenter.dy -
                      widget.scanButtonRadius -
                      extra,
                  child: IgnorePointer(
                    child: Container(
                      width: (widget.scanButtonRadius + extra) * 2,
                      height: (widget.scanButtonRadius + extra) * 2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.violeta.withValues(alpha: opacity),
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

          // ── Instruction card ──────────────────────────────────────
          if (step.hasSpotlight)
            Positioned(
              left: 24,
              right: 24,
              bottom: skeenBottomNavHeight + bottomPadding + 28,
              child: _buildCard(step),
            )
          else
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(child: _buildCard(step)),
              ),
            ),

          // ── Skip button ───────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: TextButton(
              onPressed: _skip,
              child: const Text(
                'Skip',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.violetaClaro,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(_TutorialStep step) {
    final isLast = _step == _steps.length - 1;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey(_step),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1A44),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.violeta.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.violeta.withValues(alpha: 0.15),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Step icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.violeta.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                step.icon,
                size: 30,
                color: AppColors.violeta,
              ),
            ),
            const SizedBox(height: 18),
            // Title
            Text(
              step.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 20,
                height: 1.2,
                color: AppColors.violetaClaro,
              ),
            ),
            const SizedBox(height: 10),
            // Description
            Text(
              step.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w400,
                fontSize: 14,
                height: 1.55,
                color: AppColors.hintText,
              ),
            ),
            const SizedBox(height: 22),
            // Step dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _steps.length,
                (i) => Container(
                  width: i == _step ? 22 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _step
                        ? AppColors.violeta
                        : AppColors.violeta.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Next / Get started button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.violeta,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                child: Text(isLast ? 'Get started!' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Height constant matching `SkeenBottomNav.height` so the spotlight
/// card positions above the nav bar.
const double skeenBottomNavHeight = 78;

class _TutorialStep {
  const _TutorialStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.hasSpotlight,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool hasSpotlight;
}

/// Paints the semi-transparent scrim with an optional circular cutout
/// (spotlight) around the Scan button for step 1.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter({
    this.spotlightCenter,
    required this.spotlightRadius,
    required this.pulseValue,
  });

  final Offset? spotlightCenter;
  final double spotlightRadius;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.82);

    if (spotlightCenter != null) {
      // Punch a circular hole for the spotlight
      final r = spotlightRadius + 4.0 * pulseValue;
      final outer = Path()..addRect(Offset.zero & size);
      final hole = Path()
        ..addOval(Rect.fromCircle(center: spotlightCenter!, radius: r));
      final combined = Path.combine(PathOperation.difference, outer, hole);
      canvas.drawPath(combined, scrim);

      // Soft glow ring around the spotlight
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = AppColors.violeta.withValues(alpha: 0.25 + 0.15 * pulseValue)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(spotlightCenter!, r + 4, glow);
    } else {
      canvas.drawRect(Offset.zero & size, scrim);
    }
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) =>
      old.spotlightCenter != spotlightCenter ||
      old.pulseValue != pulseValue;
}
