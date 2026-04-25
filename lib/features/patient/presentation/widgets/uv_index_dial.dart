import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Semicircular UV-index dial used inside `TemperatureCard`.
///
/// The arc fills from violet (low) → orange (high) proportionally to the UV
/// reading, capped at the WHO `extreme` threshold (11+). The numeric value
/// sits in the lower half of the dial in a prominent weight so the metric
/// reads at a glance.
class UvIndexDial extends StatelessWidget {
  const UvIndexDial({
    super.key,
    required this.uvIndex,
    this.size = 96,
  });

  final double uvIndex;
  final double size;

  static const double _maxUv = 11.0;

  @override
  Widget build(BuildContext context) {
    final clamped = uvIndex.clamp(0.0, _maxUv);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _UvDialPainter(progress: clamped / _maxUv),
            ),
          ),
          Positioned(
            top: 6,
            child: Text(
              'UV Index',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                height: 1.2,
                color: AppColors.violetaClaro.withValues(alpha: 0.78),
              ),
            ),
          ),
          Positioned(
            top: 30,
            child: Text(
              clamped.toStringAsFixed(clamped >= 10 ? 0 : 1),
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 26,
                height: 1.05,
                letterSpacing: -0.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            child: Text(
              _label(clamped),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 8,
                letterSpacing: 0.4,
                color: _labelColor(clamped),
              ),
            ),
          ),
        ],
      ),
    );
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
  _UvDialPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // The arc occupies a fuller portion of the canvas now: thicker stroke,
    // larger radius, and a steeper sweep so the curve reads as a pronounced
    // half-moon rather than a thin slice.
    final stroke = size.width * 0.13;
    final radius = (size.width / 2) - stroke / 2 - 2;
    final center = Offset(size.width / 2, size.height * 0.62);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.indigoClaro;
    canvas.drawArc(rect, math.pi, math.pi, false, track);

    if (progress > 0) {
      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: math.pi,
          endAngle: 2 * math.pi,
          colors: const [
            AppColors.violeta,
            AppColors.fucsia,
            AppColors.naranja,
          ],
          stops: const [0.0, 0.55, 1.0],
          transform: GradientRotation(math.pi),
        ).createShader(rect);
      canvas.drawArc(rect, math.pi, math.pi * progress, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _UvDialPainter old) => old.progress != progress;
}
