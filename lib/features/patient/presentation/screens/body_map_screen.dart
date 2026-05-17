import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_placeholder_screen.dart';

/// Full-screen body map (Figma 149:125 derivative) where the patient can pan,
/// zoom, and tap individual mole markers to drill into per-lesion history.
class BodyMapScreen extends StatelessWidget {
  const BodyMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeenPlaceholderScreen(
      title: 'Complete body map'.tr,
      subtitle: 'track your moles'.tr,
      body:
          'Full-figure view with pannable mole markers and per-lesion history '
          'will live here.',
      activeTab: SkeenNavTab.home,
      showBack: true,
    );
  }
}
