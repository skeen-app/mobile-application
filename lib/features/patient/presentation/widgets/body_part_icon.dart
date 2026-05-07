import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../domain/body_region.dart';

/// Inline anatomical SVG icons used in the history list and the
/// body-region picker. Inlined as strings so the change ships without
/// touching the asset bundle.
///
/// Style: single-stroke line drawing, 24x24 viewBox, currentColor — so
/// the surrounding tint controls the rendered colour.
class BodyPartIcon extends StatelessWidget {
  const BodyPartIcon({
    super.key,
    required this.region,
    required this.color,
    this.size = 24,
  });

  factory BodyPartIcon.fromLabel({
    Key? key,
    required String label,
    required Color color,
    double size = 24,
  }) {
    return BodyPartIcon(
      key: key,
      region: _labelToRegion(label),
      color: color,
      size: size,
    );
  }

  final BodyRegion region;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svgFor(region),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  static BodyRegion _labelToRegion(String label) {
    final l = label.toLowerCase();
    if (l.contains('head') || l.contains('scalp') ||
        l.contains('cheek') || l.contains('face') || l.contains('neck')) {
      return BodyRegion.head;
    }
    if (l.contains('chest') || l.contains('abdomen') ||
        l.contains('belly') || l.contains('thorax')) {
      return BodyRegion.chest;
    }
    if (l.contains('back')) return BodyRegion.back;
    if (l.contains('left arm') || l.contains('left forearm') ||
        l.contains('left shoulder')) {
      return BodyRegion.leftArm;
    }
    if (l.contains('right arm') || l.contains('right forearm') ||
        l.contains('right shoulder')) {
      return BodyRegion.rightArm;
    }
    if (l.contains('left leg') || l.contains('left thigh') ||
        l.contains('left calf')) {
      return BodyRegion.leftLeg;
    }
    if (l.contains('right leg') || l.contains('right thigh') ||
        l.contains('right calf')) {
      return BodyRegion.rightLeg;
    }
    return BodyRegion.chest;
  }

  static String _svgFor(BodyRegion region) {
    switch (region) {
      case BodyRegion.head:
        return _head;
      case BodyRegion.chest:
        return _chest;
      case BodyRegion.back:
        return _back;
      case BodyRegion.leftArm:
        return _leftArm;
      case BodyRegion.rightArm:
        return _rightArm;
      case BodyRegion.leftLeg:
        return _leftLeg;
      case BodyRegion.rightLeg:
        return _rightLeg;
    }
  }

  // ── SVG strings (24x24, stroke-linecap=round) ────────────────────────
  // Each shape is a simplified anatomical line drawing — head silhouette
  // with neck, ribcage outline for chest/back, arm + shoulder for arms,
  // thigh + calf for legs. Designed to read well at 18-24px.

  static const String _head = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
  stroke="currentColor" stroke-width="1.6" stroke-linecap="round"
  stroke-linejoin="round">
  <path d="M8 11c0-3 1.8-5.2 4-5.2S16 8 16 11c0 1.6-.4 2.8-1.1 3.7"/>
  <path d="M9 14c.6.4 1 1.1 1 2v.5"/>
  <path d="M10 17.2v1.6c0 .6.4 1 1 1h2c.6 0 1-.4 1-1v-1.6"/>
  <path d="M14 14c-.6.4-1 1.1-1 2v.5"/>
  <circle cx="10" cy="10.8" r=".5" fill="currentColor"/>
  <circle cx="14" cy="10.8" r=".5" fill="currentColor"/>
  <path d="M10.8 12.6c.4.3 1 .3 1.4 0"/>
</svg>''';

  static const String _chest = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
  stroke="currentColor" stroke-width="1.6" stroke-linecap="round"
  stroke-linejoin="round">
  <path d="M5 7c2-1.2 4.5-1.8 7-1.8S17 5.8 19 7"/>
  <path d="M6 8c1 4 1 8-1 11"/>
  <path d="M18 8c-1 4-1 8 1 11"/>
  <path d="M9 9.5c1.4 1.6 4.6 1.6 6 0"/>
  <path d="M9.4 13c.6 1.2 4.6 1.2 5.2 0"/>
  <path d="M9.7 16.2c.5 1 4.1 1 4.6 0"/>
</svg>''';

  static const String _back = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
  stroke="currentColor" stroke-width="1.6" stroke-linecap="round"
  stroke-linejoin="round">
  <path d="M5 7c2-1.2 4.5-1.8 7-1.8S17 5.8 19 7"/>
  <path d="M6 8c1 4 1 8-1 11"/>
  <path d="M18 8c-1 4-1 8 1 11"/>
  <path d="M12 6.5v12"/>
  <path d="M9 9.5h6"/>
  <path d="M9 13h6"/>
  <path d="M9 16.5h6"/>
</svg>''';

  static const String _leftArm = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
  stroke="currentColor" stroke-width="1.6" stroke-linecap="round"
  stroke-linejoin="round">
  <circle cx="16.5" cy="6.5" r="2.2"/>
  <path d="M14.6 8.2c-1.6 1.6-3 4-4 6.5"/>
  <path d="M10.6 14.7c-.6 1.4-1.2 3-1.4 4.5"/>
  <path d="M9.5 19c-.5.6-1.4 1-2.2 1"/>
  <path d="M14.4 7.3l-3 1.7"/>
</svg>''';

  static const String _rightArm = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
  stroke="currentColor" stroke-width="1.6" stroke-linecap="round"
  stroke-linejoin="round">
  <circle cx="7.5" cy="6.5" r="2.2"/>
  <path d="M9.4 8.2c1.6 1.6 3 4 4 6.5"/>
  <path d="M13.4 14.7c.6 1.4 1.2 3 1.4 4.5"/>
  <path d="M14.5 19c.5.6 1.4 1 2.2 1"/>
  <path d="M9.6 7.3l3 1.7"/>
</svg>''';

  static const String _leftLeg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
  stroke="currentColor" stroke-width="1.6" stroke-linecap="round"
  stroke-linejoin="round">
  <path d="M14 4c.5 2 .8 4 .5 6"/>
  <path d="M14.4 10c-.4 2.6-1.4 5.4-2.6 8"/>
  <path d="M11.6 18c-.6 1.4-1.4 2.6-2.4 3.6"/>
  <path d="M9 21.4c-.7.3-1.6.5-2.4.5"/>
  <path d="M12.4 4l3.6.6"/>
</svg>''';

  static const String _rightLeg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
  stroke="currentColor" stroke-width="1.6" stroke-linecap="round"
  stroke-linejoin="round">
  <path d="M10 4c-.5 2-.8 4-.5 6"/>
  <path d="M9.6 10c.4 2.6 1.4 5.4 2.6 8"/>
  <path d="M12.4 18c.6 1.4 1.4 2.6 2.4 3.6"/>
  <path d="M15 21.4c.7.3 1.6.5 2.4.5"/>
  <path d="M11.6 4l-3.6.6"/>
</svg>''';
}
