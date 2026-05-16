import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Semicircular UV-index dial used inside `TemperatureCard`.
///
/// Layout (top → bottom, all centred):
///   "UV Index"  — label
///   ╭─────────╮ — half-moon arc
///      0.2      — numeric value
///      LOW      — category
class UvIndexDial extends StatelessWidget {
  const UvIndexDial({super.key, required this.uvIndex, this.size = 96});

  final double uvIndex;
  final double size;

  static const double _maxUv = 11.0;

  @override
  Widget build(BuildContext context) {
    final clamped = uvIndex.clamp(0.0, _maxUv);

    // Arc geometry — derived once, shared with painter.
    final strokeWidth = size * 0.12;
    final radius = (size / 2) - strokeWidth / 2 - 2;
    // The box needs exactly: radius (above center) + stroke/2 (cap overshoot)
    final arcBoxHeight = radius + strokeWidth / 2 + 2;

    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "UV Index" label
          Text(
            'UV Index',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: size * 0.10,
              height: 1.2,
              letterSpacing: 0.2,
              color: AppColors.violetaClaro.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 4),
          // Semicircle arc — center pinned to bottom of this box
          SizedBox(
            width: size,
            height: arcBoxHeight,
            child: CustomPaint(
              painter: _UvDialPainter(
                progress: clamped / _maxUv,
                fillColor: _fillColor(clamped),
                strokeWidth: strokeWidth,
                radius: radius,
              ),
            ),
          ),
          // Numeric value
          Text(
            clamped.toStringAsFixed(clamped >= 10 ? 0 : 1),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: size * 0.22,
              height: 1,
              letterSpacing: -0.5,
              color: AppColors.textPrimary,
            ),
          ),
          // Category label
          Text(
            _label(clamped),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: size * 0.075,
              letterSpacing: 0.4,
              color: _labelColor(clamped),
            ),
          ),
        ],
      ),
    );
  }

  static Color _fillColor(double uv) {
    if (uv >= 8) return const Color(0xFFEF4444);
    if (uv >= 6) return const Color(0xFFF97316);
    if (uv >= 3) return const Color(0xFFEAB308);
    return const Color(0xFF22C55E);
  }

  static String _label(double uv) {
    if (uv >= 11) return 'EXTREME';
    if (uv >= 8) return 'VERY HIGH';
    if (uv >= 6) return 'HIGH';
    if (uv >= 3) return 'MODERATE';
    return 'LOW';
  }

  static Color _labelColor(double uv) {
    if (uv >= 8) return AppColors.naranja;
    if (uv >= 6) return AppColors.naranja.withValues(alpha: 0.85);
    if (uv >= 3) return AppColors.violetaLink;
    return AppColors.violetaClaro.withValues(alpha: 0.6);
  }
}

class _UvDialPainter extends CustomPainter {
  _UvDialPainter({
    required this.progress,
    required this.fillColor,
    required this.strokeWidth,
    required this.radius,
  });

  final double progress;
  final Color fillColor;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    // Center at the bottom-center of the box so the semicircle
    // arcs upward and fits exactly within the allocated height.
    final center = Offset(size.width / 2, size.height);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = AppColors.indigoClaro;
    canvas.drawArc(rect, math.pi, math.pi, false, track);

    // Filled progress arc
    if (progress > 0) {
      final fill = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = fillColor;
      canvas.drawArc(rect, math.pi, math.pi * progress, false, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _UvDialPainter old) =>
      old.progress != progress || old.fillColor != fillColor;
}
