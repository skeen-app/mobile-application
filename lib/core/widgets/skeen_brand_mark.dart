import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'skeen_constellation.dart';

class SkeenBrandMark extends StatefulWidget {
  const SkeenBrandMark({super.key});

  static const String _ellipsesAsset = 'assets/images/brand_ellipses.svg';

  @override
  State<SkeenBrandMark> createState() => _SkeenBrandMarkState();
}

class _SkeenBrandMarkState extends State<SkeenBrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ellipses;

  static const double _baseAngle = -22.31 * math.pi / 180;

  // Ellipse pulse: scale ±2.5%, opacity fades between these bounds
  // (brightest → soft) in sync with the expansion.
  static const double _ellipseScaleAmp = 0.025;
  static const double _ellipseOpacityMin = 0.55;
  static const double _ellipseOpacityMax = 1.0;

  @override
  void initState() {
    super.initState();
    _ellipses = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ellipses.dispose();
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
                final pulse = (math.sin(t) + 1) / 2;
                final scale = 1 + _ellipseScaleAmp * pulse;
                final opacity = _ellipseOpacityMax -
                    (_ellipseOpacityMax - _ellipseOpacityMin) * pulse;
                final sway = math.sin(t * 0.5) * 0.025;

                return Transform.rotate(
                  angle: _baseAngle + sway,
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(opacity: opacity, child: child),
                  ),
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
            SizedBox(
              width: constellationSize,
              height: constellationSize * (65 / 77),
              child: const SkeenConstellation(),
            ),
          ],
        );
      },
    );
  }
}
