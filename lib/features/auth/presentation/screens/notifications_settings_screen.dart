import 'package:flutter/material.dart';

import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_placeholder_screen.dart';

class NotificationsSettingsScreen extends StatelessWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeenPlaceholderScreen(
      title: 'Notifications',
      body:
          'Toggle scan reminders, OTA model-update alerts, and check-in '
          'notifications. Choose between push, email, or both.',
      activeTab: SkeenNavTab.profile,
      showBack: true,
    );
  }
}
