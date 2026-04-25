import 'package:flutter/material.dart';

import 'skeen_constellation.dart';
import 'skeen_wordmark.dart';

class SkeenAuthHeader extends StatelessWidget {
  const SkeenAuthHeader({super.key});

  static const double _constellationWidth = 64;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          SkeenWordmark(fontSize: 26),
          Positioned(
            left: 8,
            top: 14,
            width: _constellationWidth,
            height: _constellationWidth * (65 / 77),
            child: SkeenConstellation(),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            width: _constellationWidth,
            height: _constellationWidth * (65 / 77),
            child: SkeenConstellation(),
          ),
        ],
      ),
    );
  }
}
