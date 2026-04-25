import 'package:flutter/material.dart';

import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_placeholder_screen.dart';

class ReminderScreen extends StatelessWidget {
  const ReminderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeenPlaceholderScreen(
      title: 'Reminders',
      body:
          'Schedule periodic check-ins for at-risk lesions and recurring '
          'self-exam routines.',
      activeTab: SkeenNavTab.home,
      showBack: true,
    );
  }
}
