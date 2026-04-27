import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import 'skeen_bottom_nav.dart';
import 'skeen_star_field.dart';
import 'skeen_top_app_bar.dart';

/// Reusable scaffolding for screens that are wired into navigation but whose
/// real implementation lands in a later iteration. Keeps the bottom nav,
/// background, top app bar, and overall composition consistent across stub
/// destinations.
class SkeenPlaceholderScreen extends StatelessWidget {
  const SkeenPlaceholderScreen({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    required this.activeTab,
    this.showBack = false,
  });

  final String title;
  final String? subtitle;
  final String body;
  final SkeenNavTab activeTab;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.45,
                child: SkeenStarField(seed: 23, density: 14),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                if (showBack)
                  SkeenTopAppBar(
                    title: title,
                    subtitle: subtitle,
                    showBack: true,
                  ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!showBack)
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: 22,
                                letterSpacing: -0.22,
                                color: AppColors.violetaClaro,
                              ),
                            ),
                          if (!showBack) const SizedBox(height: 14),
                          Text(
                            body,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w400,
                              fontSize: 14,
                              height: 1.5,
                              color: AppColors.hintText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SkeenBottomNav(
                  activeTab: activeTab,
                  onTabSelected: (tab) => _onTabSelected(context, tab),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onTabSelected(BuildContext context, SkeenNavTab tab) {
    switch (tab) {
      case SkeenNavTab.home:
        context.goNamed('home');
      case SkeenNavTab.history:
        context.goNamed('history');
      case SkeenNavTab.scan:
        context.pushNamed('scan-a-mole');
      case SkeenNavTab.experts:
        context.goNamed('experts');
      case SkeenNavTab.profile:
        context.goNamed('profile');
    }
  }
}
