import 'package:flutter/material.dart';

import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_placeholder_screen.dart';

class MedicalHistoryScreen extends StatelessWidget {
  const MedicalHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeenPlaceholderScreen(
      title: 'Medical History',
      subtitle: 'your health records',
      body:
          'Allergies, prior dermatological conditions, family history of skin '
          'cancer, and current medications.',
      activeTab: SkeenNavTab.profile,
      showBack: true,
    );
  }
}
