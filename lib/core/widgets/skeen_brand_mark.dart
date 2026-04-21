import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SkeenBrandMark extends StatefulWidget {
  const SkeenBrandMark({super.key});

  static const String _ellipsesAsset = 'assets/images/brand_ellipses.svg';
  static const String _constellationAsset =
      'assets/images/brand_constellation.svg';

  @override
  State<SkeenBrandMark> createState() => _SkeenBrandMarkState();
}

class _SkeenBrandMarkState extends State<SkeenBrandMark>
    with TickerProviderStateMixin {
  late final AnimationController _ellipses;
  late final AnimationController _stars;

  static const double _baseAngle = -22.31 * math.pi / 180;

  @override
  void initState() {
    super.initState();
    _ellipses = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _stars = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _ellipses.dispose();
    _stars.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final constellationSize = w * 0.22;

        return Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _ellipses,
              builder: (context, child) {
                final t = _ellipses.value * 2 * math.pi;
                final sway = math.sin(t) * 0.035;
                final breath = 1 + math.sin(t * 0.8) * 0.015;
                return Transform.rotate(
                  angle: _baseAngle + sway,
                  child: Transform.scale(scale: breath, child: child),
                );
              },
              child: SizedBox(
                width: w * 0.95,
                height: h * 0.92,
                child: SvgPicture.asset(
                  SkeenBrandMark._ellipsesAsset,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _stars,
              builder: (context, child) {
                final t = _stars.value * 2 * math.pi;
                final dy = math.sin(t) * 3.5;
                final dx = math.cos(t * 0.7) * 2.5;
                return Transform.translate(
                  offset: Offset(dx, dy),
                  child: child,
                );
              },
              child: SizedBox(
                width: constellationSize,
                height: constellationSize * (65 / 77),
                child: SvgPicture.asset(
                  SkeenBrandMark._constellationAsset,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
