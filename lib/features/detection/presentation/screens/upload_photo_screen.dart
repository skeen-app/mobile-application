import 'package:flutter/material.dart';

import '../../../../core/widgets/skeen_bottom_nav.dart';
import '../../../../core/widgets/skeen_placeholder_screen.dart';

/// Gallery upload variant of the Detection scan flow (Figma 54:302).
class UploadPhotoScreen extends StatelessWidget {
  const UploadPhotoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeenPlaceholderScreen(
      title: 'Upload a photo',
      subtitle: 'from your gallery',
      body:
          'Pick an existing image from the gallery and run the same on-device '
          'analysis used for live scans.',
      activeTab: SkeenNavTab.home,
      showBack: true,
    );
  }
}
