import 'package:flutter/material.dart';

import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_placeholder_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeenPlaceholderScreen(
      title: 'Profile',
      body:
          'Account preferences, identity, biometric login, and clinical '
          'history sharing settings.',
      activeTab: SkeenNavTab.profile,
    );
  }
}
