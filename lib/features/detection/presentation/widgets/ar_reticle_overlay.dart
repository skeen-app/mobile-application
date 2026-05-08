import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/capture_quality.dart';

/// AR-style overlay drawn on top of the live camera preview. Composes the
/// four corner brackets (Figma `Scanner` group 149:180) with a dotted inner
/// circle and an outer ring that softly pulses to suggest "alignment in
/// progress" — the hand-positioning metaphor from the design.
///
/// Reticle color tracks the current [quality] so the user gets immediate
/// feedback on whether their lighting / framing is clinical-grade.
class ArReticleOverlay extends StatefulWidget {
  const ArReticleOverlay({super.key, required this.quality});

  final CaptureQuality quality;

  @override
  State<ArReticleOverlay> createState() => _ArReticleOverlayState();
}

class _ArReticleOverlayState extends State<ArReticleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color _reticleColor() {
    switch (widget.quality.level) {
      case CaptureQualityLevel.poor:
        return AppColors.fucsia;
      case CaptureQualityLevel.acceptable:
        return AppColors.naranja;
      case CaptureQualityLevel.good:
        return AppColors.turquesa;
      case CaptureQualityLevel.excellent:
        return AppColors.violetaClaro;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _reticleColor();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          return CustomPaint(
            painter: _ReticlePainter(
              color: color,
              pulse: _pulse.value,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.color, required this.pulse});

  final Color color;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = size.shortestSide;

    // ── Corner brackets ─────────────────────────────────────────────
    final bracketStroke = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final bracketLen = shortest * 0.12;
    final inset = shortest * 0.08;
    final rect = Rect.fromCenter(
      center: center,
      width: size.width - inset * 2,
      height: size.height * 0.7,
    );

    void corner(Offset a, Offset b, Offset c) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy);
      canvas.drawPath(path, bracketStroke);
    }

    // top-left
    corner(
      rect.topLeft + Offset(0, bracketLen),
      rect.topLeft,
      rect.topLeft + Offset(bracketLen, 0),
    );
    // top-right
    corner(
      rect.topRight + Offset(-bracketLen, 0),
      rect.topRight,
      rect.topRight + Offset(0, bracketLen),
    );
    // bottom-left
    corner(
      rect.bottomLeft + Offset(0, -bracketLen),
      rect.bottomLeft,
      rect.bottomLeft + Offset(bracketLen, 0),
    );
    // bottom-right
    corner(
      rect.bottomRight + Offset(-bracketLen, 0),
      rect.bottomRight,
      rect.bottomRight + Offset(0, -bracketLen),
    );

    // ── Outer pulsing ring ──────────────────────────────────────────
    final outerRadius = shortest * 0.22 + pulse * 6;
    final outerPaint = Paint()
      ..color = color.withValues(alpha: 0.55 + pulse * 0.25)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, outerRadius, outerPaint);

    // ── Dotted inner ring (the lesion target) ───────────────────────
    final innerRadius = shortest * 0.16;
    final dotPaint = Paint()..color = color;
    const dotCount = 36;
    final rotation = pulse * math.pi * 0.25; // gentle rotation
    for (var i = 0; i < dotCount; i++) {
      final angle = rotation + (i * 2 * math.pi / dotCount);
      final dx = center.dx + math.cos(angle) * innerRadius;
      final dy = center.dy + math.sin(angle) * innerRadius;
      canvas.drawCircle(Offset(dx, dy), 1.4, dotPaint);
    }

    // ── Crosshair ticks at the center ───────────────────────────────
    final tick = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      center.translate(-6, 0),
      center.translate(6, 0),
      tick,
    );
    canvas.drawLine(
      center.translate(0, -6),
      center.translate(0, 6),
      tick,
    );
  }

  @override
  bool shouldRepaint(covariant _ReticlePainter old) =>
      old.pulse != pulse || old.color != color;
}
