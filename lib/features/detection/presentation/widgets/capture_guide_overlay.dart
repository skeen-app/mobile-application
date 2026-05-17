import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../../core/theme/app_colors.dart';
import '../../domain/ar_geometry.dart';
import '../../domain/capture_quality.dart';

/// Minimal capture-time overlay that replaces the old red distance ring +
/// AR reticle + four-item checklist. The redesign keeps three signals
/// on screen at all times — lighting, focus, distance — and lets the
/// rest of the camera frame breathe.
///
/// Layout:
///   • Center frame: a 220×220 rounded square outlined with four corner
///     brackets. Subtle (semi-transparent white) by default, switches to
///     a glowing brand-violet when [CaptureReadiness.isReady] flips
///     true. That single colour change is the user's "you're good to
///     shoot" signal — replaces the four-checkmark grid the old UI used.
///   • Bottom bar: three pill chips sitting above the shutter, each
///     carrying an icon + short label + state colour. The distance chip
///     swaps to a directional arrow (↓ move away / ↑ move closer) when
///     the user is outside the 10–20 cm sweet spot.
///   • Haptic: a single light tap fires the moment readiness transitions
///     `false → true` so the user feels the green light without having
///     to glance away from the lesion.
class CaptureGuideOverlay extends StatefulWidget {
  const CaptureGuideOverlay({
    super.key,
    required this.readiness,
    required this.distance,
  });

  final CaptureReadiness readiness;

  /// Raw distance reading so the distance chip can derive direction
  /// (too-close vs too-far). The [CaptureReadiness.distance] bool flag
  /// only tells us "in range / not in range" — not actionable.
  final CaptureDistance distance;

  @override
  State<CaptureGuideOverlay> createState() => _CaptureGuideOverlayState();
}

class _CaptureGuideOverlayState extends State<CaptureGuideOverlay> {
  bool? _previousReady;

  @override
  void didUpdateWidget(covariant CaptureGuideOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasReady = _previousReady;
    final isReady = widget.readiness.isReady;
    if (wasReady == false && isReady) {
      // false → true transition. Soft haptic so the user feels the
      // "ready to shoot" moment without looking at the chips.
      HapticFeedback.lightImpact();
    }
    _previousReady = isReady;
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.readiness.isReady;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Center frame ─────────────────────────────────────────────
        IgnorePointer(
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: ready
                    ? [
                        BoxShadow(
                          color: AppColors.violeta.withValues(alpha: 0.35),
                          blurRadius: 24,
                          spreadRadius: -2,
                        ),
                      ]
                    : const [],
              ),
              child: CustomPaint(
                painter: _CornerBracketsPainter(
                  color: ready
                      ? AppColors.violeta
                      : Colors.white.withValues(alpha: 0.55),
                  stroke: ready ? 3.0 : 2.0,
                  bracketLength: 28,
                  radius: 28,
                ),
              ),
            ),
          ),
        ),

        // ── Bottom chip bar ──────────────────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Chip(
                      icon: Icons.wb_sunny_outlined,
                      label: 'Light'.tr,
                      ok: widget.readiness.lighting.canCapture,
                    ),
                    const SizedBox(width: 6),
                    _Chip(
                      icon: Icons.center_focus_strong_outlined,
                      label: 'Focus'.tr,
                      ok: widget.readiness.focus,
                    ),
                    const SizedBox(width: 6),
                    _DistanceChip(distance: widget.distance),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Chip primitives
// ──────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.ok,
  });

  final IconData icon;
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final accent = ok ? AppColors.violeta : AppColors.naranja;
    final fg = ok ? Colors.white : AppColors.naranja;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: ok ? 0.22 : 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: ok ? 0.55 : 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: -0.1,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Variant of [_Chip] that swaps the trailing icon to a directional
/// arrow when the user is outside the 10–20 cm sweet spot. Reads the
/// [CaptureDistance.tooClose] / [tooFar] booleans so the domain owns
/// the threshold logic and the chip stays a dumb renderer.
class _DistanceChip extends StatelessWidget {
  const _DistanceChip({required this.distance});
  final CaptureDistance distance;

  @override
  Widget build(BuildContext context) {
    final ok = distance.isInAcceptableRange;
    final accent = ok ? AppColors.violeta : AppColors.naranja;
    final fg = ok ? Colors.white : AppColors.naranja;

    IconData arrow;
    String label;
    if (distance.tooClose) {
      // User is < 10 cm — needs to pull away.
      arrow = Icons.arrow_downward_rounded;
      label = 'Move away'.tr;
    } else if (distance.tooFar) {
      // User is > 20 cm — needs to come closer.
      arrow = Icons.arrow_upward_rounded;
      label = 'Move closer'.tr;
    } else {
      arrow = Icons.straighten_rounded;
      label = 'Distance'.tr;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: ok ? 0.22 : 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: ok ? 0.55 : 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(arrow, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: -0.1,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Corner brackets painter
// ──────────────────────────────────────────────────────────────────────

/// Draws four L-shaped brackets in the corners of the available box,
/// rounded inward at [radius]. Used as the "AR-target" frame the user
/// aims at — explicitly NOT a full rectangle so the lesion stays
/// visible without a heavy outline obscuring it.
class _CornerBracketsPainter extends CustomPainter {
  _CornerBracketsPainter({
    required this.color,
    required this.stroke,
    required this.bracketLength,
    required this.radius,
  });

  final Color color;
  final double stroke;
  final double bracketLength;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final r = radius;
    final b = bracketLength;

    // Top-left
    _drawCorner(canvas, paint, Offset(0, 0), Offset(0, h),
        Offset(0, r), Offset(r, 0), b, true, true);
    // Top-right
    _drawCorner(canvas, paint, Offset(w, 0), Offset(w, h),
        Offset(w, r), Offset(w - r, 0), b, false, true);
    // Bottom-left
    _drawCorner(canvas, paint, Offset(0, h), Offset(0, 0),
        Offset(0, h - r), Offset(r, h), b, true, false);
    // Bottom-right
    _drawCorner(canvas, paint, Offset(w, h), Offset(w, 0),
        Offset(w, h - r), Offset(w - r, h), b, false, false);
  }

  void _drawCorner(
    Canvas canvas,
    Paint paint,
    Offset corner,
    Offset _,
    Offset arcStart,
    Offset arcEnd,
    double bracketLen,
    bool isLeft,
    bool isTop,
  ) {
    // Vertical line from corner down/up
    final vEnd = Offset(
      arcStart.dx,
      arcStart.dy + (isTop ? bracketLen : -bracketLen),
    );
    // Horizontal line from corner left/right
    final hEnd = Offset(
      arcEnd.dx + (isLeft ? bracketLen : -bracketLen),
      arcEnd.dy,
    );

    // Rounded arc between arcStart and arcEnd via the corner.
    final rect = Rect.fromCircle(
      center: Offset(
        isLeft ? radius : (corner.dx - radius),
        isTop ? radius : (corner.dy - radius),
      ),
      radius: radius,
    );
    double startAngle;
    if (isLeft && isTop) {
      startAngle = 3.1416; // π
    } else if (!isLeft && isTop) {
      startAngle = -1.5708; // -π/2
    } else if (isLeft && !isTop) {
      startAngle = 1.5708; // π/2
    } else {
      startAngle = 0;
    }

    canvas.drawArc(rect, startAngle, 1.5708, false, paint);
    canvas.drawLine(arcStart, vEnd, paint);
    canvas.drawLine(arcEnd, hEnd, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketsPainter old) =>
      old.color != color ||
      old.stroke != stroke ||
      old.bracketLength != bracketLength ||
      old.radius != radius;
}
