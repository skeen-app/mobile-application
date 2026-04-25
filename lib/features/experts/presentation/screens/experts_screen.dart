import 'package:flutter/material.dart';

import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_placeholder_screen.dart';

/// Experts directory — connects patients with vetted dermatologists for
/// follow-up consultation when a scan is flagged as high-risk.
class ExpertsScreen extends StatelessWidget {
  const ExpertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeenPlaceholderScreen(
      title: 'Experts',
      body:
          'Browse vetted dermatologists, request a remote second opinion, and '
          'send your scan history securely.',
      activeTab: SkeenNavTab.experts,
    );
  }
}
