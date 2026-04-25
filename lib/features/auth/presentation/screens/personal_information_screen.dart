import 'package:flutter/material.dart';

import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_placeholder_screen.dart';

class PersonalInformationScreen extends StatelessWidget {
  const PersonalInformationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeenPlaceholderScreen(
      title: 'Personal Information',
      subtitle: 'edit your details',
      body:
          'Edit your name, date of birth, contact details, and emergency '
          'contact information.',
      activeTab: SkeenNavTab.profile,
      showBack: true,
    );
  }
}
