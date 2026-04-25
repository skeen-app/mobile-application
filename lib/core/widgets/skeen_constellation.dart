import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class SkeenConstellation extends StatefulWidget {
  const SkeenConstellation({super.key});

  @override
  State<SkeenConstellation> createState() => _SkeenConstellationState();
}

class _SkeenConstellationState extends State<SkeenConstellation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _ConstellationPainter(
            time: _controller.value * 2 * math.pi,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({required this.time});

  final double time;

  // Base vertices (polygon order) in the original SVG viewBox coordinates.
  static const Size _viewBox = Size(77, 65);
  static const List<Offset> _basePoints = [
    Offset(7.5, 64.0),
    Offset(12.0, 46.0),
    Offset(1.5, 30.5),
    Offset(33.0, 26.0),
    Offset(49.0, 1.5),
    Offset(73.5, 17.5),
    Offset(76.0, 46.0),
    Offset(56.0, 56.5),
  ];

  // Per-point motion params: [freqX, freqY, phaseX, phaseY, ampX, ampY].
  // Prime-ish frequency ratios prevent the pattern from ever repeating exactly.
  static const List<List<double>> _params = [
    [1.0, 0.9, 0.00, 1.20, 2.8, 2.2],
    [0.8, 1.1, 2.10, 0.40, 2.2, 2.8],
    [1.2, 0.7, 0.80, 2.50, 2.8, 2.2],
    [0.7, 1.3, 3.40, 1.70, 3.0, 2.5],
    [1.1, 0.8, 1.50, 3.00, 2.4, 1.8],
    [0.9, 1.2, 2.70, 0.90, 2.0, 2.5],
    [1.3, 0.8, 0.30, 2.20, 2.5, 2.0],
    [0.8, 1.1, 2.40, 1.40, 2.8, 2.2],
  ];

  static const Color _dotColor = Color(0xFFAAA7CF);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / _viewBox.width;
    final sy = size.height / _viewBox.height;

    // Slow global pulse modulates per-point amplitudes so the whole shape
    // breathes between "closed" (points near their base) and "open" (points
    // spread further). 0.45 keeps a minimum motion so it's never fully static.
    final globalPulse = 0.45 + 0.55 * (math.sin(time * 0.35) + 1) / 2;

    final points = <Offset>[
      for (var i = 0; i < _basePoints.length; i++) _animated(i, sx, sy, globalPulse),
    ];

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.indigoClaro;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();
    canvas.drawPath(path, edgePaint);

    final dotPaint = Paint()..color = _dotColor;
    final dotRadius = 1.5 * math.min(sx, sy);
    for (final p in points) {
      canvas.drawCircle(p, dotRadius, dotPaint);
    }
  }

  Offset _animated(int i, double sx, double sy, double globalPulse) {
    final base = _basePoints[i];
    final p = _params[i];
    final dx = math.sin(time * p[0] + p[2]) * p[4] * globalPulse;
    final dy = math.sin(time * p[1] + p[3]) * p[5] * globalPulse;
    return Offset((base.dx + dx) * sx, (base.dy + dy) * sy);
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter old) => old.time != time;
}
