import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/ar_geometry.dart';

/// 3D-looking "Target Ring" that lives in the center of the AR viewfinder
/// and changes color based on the live LiDAR/Depth distance reading:
///
///   • RED      — < 10 cm or > 20 cm (out of range)
///   • ORANGE   — 10–13 cm or 17–20 cm (acceptable, coach toward sweet spot)
///   • GREEN    — 13–17 cm sweet spot (15 cm ± 2 cm)
///
/// The ring softly rotates and pulses so the user gets a sense of "the
/// camera is actively measuring" even when the distance hasn't changed.
class ArDistanceRing extends StatefulWidget {
  const ArDistanceRing({super.key, required this.distance});

  final CaptureDistance distance;

  @override
  State<ArDistanceRing> createState() => _ArDistanceRingState();
}

class _ArDistanceRingState extends State<ArDistanceRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Color _color() {
    final d = widget.distance;
    if (!d.isKnown) return AppColors.violetaClaro;
    if (d.isInSweetSpot) return const Color(0xFF22C55E); // green
    if (d.isInAcceptableRange) return AppColors.naranja;
    return AppColors.fucsia;
  }

  String _label() {
    final d = widget.distance;
    if (!d.isKnown) return 'measuring…';
    if (d.tooClose) return 'too close — pull back';
    if (d.tooFar) return 'too far — move closer';
    if (d.isInSweetSpot) return 'perfect distance';
    return 'almost there';
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    final d = widget.distance;
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _spin,
              builder: (context, _) {
                return CustomPaint(
                  size: const Size(160, 160),
                  painter: _RingPainter(
                    color: color,
                    rotation: _spin.value * 2 * math.pi,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.7),
                border: Border.all(color: color, width: 1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                d.isKnown
                    ? '${d.cm.toStringAsFixed(1)} cm · ${_label()}'
                    : _label(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: -0.11,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.rotation});

  final Color color;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 6;

    // Outer halo for the 3D depth illusion
    final glow = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius + 6, glow);

    // Main ring
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, ring);

    // Rotating ticks — give the user a "it's actively tracking" cue
    final tick = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = rotation + (i * math.pi / 6);
      final inner = Offset(
        center.dx + math.cos(a) * (radius - 8),
        center.dy + math.sin(a) * (radius - 8),
      );
      final outer = Offset(
        center.dx + math.cos(a) * (radius - 2),
        center.dy + math.sin(a) * (radius - 2),
      );
      canvas.drawLine(inner, outer, tick);
    }

    // Crosshair
    final cross = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    canvas.drawLine(
      center.translate(-8, 0),
      center.translate(8, 0),
      cross,
    );
    canvas.drawLine(
      center.translate(0, -8),
      center.translate(0, 8),
      cross,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.rotation != rotation || old.color != color;
}
