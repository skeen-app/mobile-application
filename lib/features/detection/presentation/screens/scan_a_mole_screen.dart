import 'package:flutter/material.dart';

import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_placeholder_screen.dart';

/// Entry point for the Detection context's camera-based mole scan.
///
/// Placeholder while the AR viewfinder + capture pipeline lands. Hooks into
/// the home dashboard's "Scan a mole" CTA and the bottom-nav center FAB.
class ScanAMoleScreen extends StatelessWidget {
  const ScanAMoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeenPlaceholderScreen(
      title: 'Scan a mole',
      body:
          'The AR-guided camera scan flow lives here. Calibration, capture, '
          'and on-device inference will be wired in next.',
      activeTab: SkeenNavTab.scan,
      showBack: true,
    );
  }
}
