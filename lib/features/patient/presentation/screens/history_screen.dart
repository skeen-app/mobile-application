import 'package:flutter/material.dart';

import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_placeholder_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeenPlaceholderScreen(
      title: 'History',
      body: 'Chronological log of every scan, grouped by lesion and region.',
      activeTab: SkeenNavTab.history,
    );
  }
}
