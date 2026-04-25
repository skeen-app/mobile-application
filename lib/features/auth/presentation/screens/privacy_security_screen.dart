import 'package:flutter/material.dart';

import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_placeholder_screen.dart';

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeenPlaceholderScreen(
      title: 'Privacy & Security',
      body:
          'Biometric login, change password, manage data sharing with '
          'consulting dermatologists, and export or delete your account.',
      activeTab: SkeenNavTab.profile,
      showBack: true,
    );
  }
}
