import 'dart:math' as math;

import 'package:flutter/material.dart';

class SkeenStarField extends StatefulWidget {
  const SkeenStarField({
    super.key,
    this.seed = 7,
    this.density = 14,
  });

  final int seed;
  final int density;

  @override
  State<SkeenStarField> createState() => _SkeenStarFieldState();
}

class _SkeenStarFieldState extends State<SkeenStarField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Sparkle> _sparkles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);

    final rng = math.Random(widget.seed);
    _sparkles = List.generate(widget.density, (i) {
      final shape = _SparkleShape.values[rng.nextInt(_SparkleShape.values.length)];
      return _Sparkle(
        relX: rng.nextDouble(),
        relY: rng.nextDouble(),
        size: 6.0 + rng.nextDouble() * 10.0,
        baseOpacity: 0.22 + rng.nextDouble() * 0.48,
        driftFreqX: 0.4 + rng.nextDouble() * 0.7,
        driftFreqY: 0.4 + rng.nextDouble() * 0.7,
        driftPhaseX: rng.nextDouble() * math.pi * 2,
        driftPhaseY: rng.nextDouble() * math.pi * 2,
        driftAmpX: 2.0 + rng.nextDouble() * 3.0,
        driftAmpY: 2.0 + rng.nextDouble() * 3.0,
        twinkleFreq: 0.5 + rng.nextDouble() * 1.2,
        twinklePhase: rng.nextDouble() * math.pi * 2,
        rotation: rng.nextDouble() * math.pi,
        shape: shape,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _StarFieldPainter(
              time: _controller.value * 2 * math.pi,
              sparkles: _sparkles,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

enum _SparkleShape { fourPoint, cross, dot, diamond }

class _Sparkle {
  const _Sparkle({
    required this.relX,
    required this.relY,
    required this.size,
    required this.baseOpacity,
    required this.driftFreqX,
    required this.driftFreqY,
    required this.driftPhaseX,
    required this.driftPhaseY,
    required this.driftAmpX,
    required this.driftAmpY,
    required this.twinkleFreq,
    required this.twinklePhase,
    required this.rotation,
    required this.shape,
  });

  final double relX;
  final double relY;
  final double size;
  final double baseOpacity;
  final double driftFreqX;
  final double driftFreqY;
  final double driftPhaseX;
  final double driftPhaseY;
  final double driftAmpX;
  final double driftAmpY;
  final double twinkleFreq;
  final double twinklePhase;
  final double rotation;
  final _SparkleShape shape;
}

class _StarFieldPainter extends CustomPainter {
  _StarFieldPainter({required this.time, required this.sparkles});

  final double time;
  final List<_Sparkle> sparkles;

  static const Color _color = Color(0xFFEDE9FE);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sparkles) {
      final dx = math.sin(time * s.driftFreqX + s.driftPhaseX) * s.driftAmpX;
      final dy = math.cos(time * s.driftFreqY + s.driftPhaseY) * s.driftAmpY;
      final cx = s.relX * size.width + dx;
      final cy = s.relY * size.height + dy;

      final twinkle = 0.5 + 0.5 * math.sin(time * s.twinkleFreq + s.twinklePhase);
      final opacity = (s.baseOpacity * (0.55 + 0.45 * twinkle)).clamp(0.0, 1.0);

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(s.rotation);
      _drawShape(canvas, s.shape, s.size, opacity);
      canvas.restore();
    }
  }

  void _drawShape(Canvas canvas, _SparkleShape shape, double size, double opacity) {
    final paint = Paint()
      ..color = _color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.1;

    switch (shape) {
      case _SparkleShape.fourPoint:
        final half = size / 2;
        canvas.drawLine(Offset(-half, 0), Offset(half, 0), paint);
        canvas.drawLine(Offset(0, -half), Offset(0, half), paint);
        final dotPaint = Paint()..color = _color.withValues(alpha: opacity * 0.9);
        canvas.drawCircle(Offset.zero, 0.9, dotPaint);
      case _SparkleShape.cross:
        final half = size / 2;
        canvas.drawLine(Offset(-half, -half), Offset(half, half), paint);
        canvas.drawLine(Offset(-half, half), Offset(half, -half), paint);
      case _SparkleShape.dot:
        final dotPaint = Paint()..color = _color.withValues(alpha: opacity);
        canvas.drawCircle(Offset.zero, size * 0.12, dotPaint);
      case _SparkleShape.diamond:
        final half = size / 2;
        final path = Path()
          ..moveTo(0, -half)
          ..lineTo(half * 0.5, 0)
          ..lineTo(0, half)
          ..lineTo(-half * 0.5, 0)
          ..close();
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter old) => old.time != time;
}
