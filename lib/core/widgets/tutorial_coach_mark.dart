import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A reusable coach mark that draws a dark scrim with a cutout hole (spotlight).
/// It blocks touches everywhere except the spotlight, so the user must
/// physically tap the highlighted UI element.
class TutorialCoachMark extends StatefulWidget {
  const TutorialCoachMark({
    super.key,
    this.spotlightCenter,
    this.spotlightRadius,
    required this.title,
    required this.description,
    required this.onSkip,
    this.isFloatingTooltip = false,
    this.floatingAlignment = Alignment.topCenter,
  });

  final Offset? spotlightCenter;
  final double? spotlightRadius;
  final String title;
  final String description;
  final VoidCallback onSkip;

  /// If true, draws a subtle floating tooltip without blocking the screen
  /// (used for the Camera step).
  final bool isFloatingTooltip;

  /// Determines where the floating tooltip sits when [isFloatingTooltip] is true.
  final Alignment floatingAlignment;

  @override
  State<TutorialCoachMark> createState() => _TutorialCoachMarkState();
}

class _TutorialCoachMarkState extends State<TutorialCoachMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

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

  @override
  Widget build(BuildContext context) {
    if (widget.isFloatingTooltip) {
      return SafeArea(
        child: Align(
          alignment: widget.floatingAlignment,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: _buildCard(),
          ),
        ),
      );
    }

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const double skeenBottomNavHeight = 78;

    return Stack(
      children: [
        // ── Scrim that blocks touches (except the hole) ────────────
        ClipPath(
          clipper: widget.spotlightCenter != null
              ? _HoleClipper(
                  widget.spotlightCenter!,
                  widget.spotlightRadius ?? 0,
                )
              : null,
          child: GestureDetector(
            onTap: () {}, // Consume touches outside the hole
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ScrimPainter(
                    spotlightCenter: widget.spotlightCenter,
                    spotlightRadius: widget.spotlightRadius ?? 0,
                    pulseValue: _pulseAnimation.value,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
        ),

        // ── Pulsing ring around the spotlight ─────────────────────
        if (widget.spotlightCenter != null && widget.spotlightRadius != null)
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, _) {
              final extra = 8.0 + 6.0 * _pulseAnimation.value;
              final opacity = 0.7 - 0.3 * _pulseAnimation.value;
              return Positioned(
                left: widget.spotlightCenter!.dx -
                    widget.spotlightRadius! -
                    extra,
                top: widget.spotlightCenter!.dy -
                    widget.spotlightRadius! -
                    extra,
                child: IgnorePointer(
                  child: Container(
                    width: (widget.spotlightRadius! + extra) * 2,
                    height: (widget.spotlightRadius! + extra) * 2,
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
        Positioned(
          left: 24,
          right: 24,
          bottom: widget.spotlightCenter != null
              ? skeenBottomNavHeight + bottomPadding + 28
              : null,
          child: widget.spotlightCenter != null
              ? _buildCard()
              : Center(child: _buildCard()),
        ),

        // If no spotlight, center the card
        if (widget.spotlightCenter == null)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Center(child: _buildCard()),
            ),
          ),

        // ── Skip button ───────────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: TextButton(
            onPressed: widget.onSkip,
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
    );
  }

  Widget _buildCard() {
    return Container(
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
          // Title
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.2,
              color: AppColors.violetaClaro,
            ),
          ),
          const SizedBox(height: 8),
          // Description
          Text(
            widget.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: 14,
              height: 1.55,
              color: AppColors.hintText,
            ),
          ),
          if (widget.isFloatingTooltip) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: widget.onSkip,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.violeta,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Got it'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HoleClipper extends CustomClipper<Path> {
  _HoleClipper(this.center, this.radius);

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final hole = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    return Path.combine(PathOperation.difference, outer, hole);
  }

  @override
  bool shouldReclip(covariant _HoleClipper old) =>
      old.center != center || old.radius != radius;
}

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
      canvas.drawRect(Offset.zero & size, scrim);

      // Soft glow ring around the spotlight
      final r = spotlightRadius + 4.0 * pulseValue;
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
      old.spotlightCenter != spotlightCenter || old.pulseValue != pulseValue;
}
