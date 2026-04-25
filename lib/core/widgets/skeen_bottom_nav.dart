import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';

/// Identifies which tab is currently active so the nav bar paints the
/// matching icon/label in the active tone. Screens declare their own tab
/// when wiring `SkeenBottomNav`.
enum SkeenNavTab {
  home,
  history,
  scan,
  experts,
  profile,
}

/// Reusable bottom navigation bar shared across all post-auth screens.
///
/// Mirrors the Figma `Navigation Shell` (152:418): a frosted-glass strip with
/// four flanking icon tabs and a central elevated FAB. The active tab paints
/// in `--violetaClaro`, inactive tabs in `--stroke`-tinted gray. The center
/// FAB is the primary scan entry point regardless of context.
class SkeenBottomNav extends StatelessWidget {
  const SkeenBottomNav({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
  });

  final SkeenNavTab activeTab;
  final ValueChanged<SkeenNavTab> onTabSelected;

  static const double height = 80;
  static const double _fabSize = 52;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height + 12, // FAB protrudes above the bar
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.indigo.withValues(alpha: 0.53),
                    border: Border(
                      top: BorderSide(color: AppColors.violetaOscuro),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _NavItem(
                          asset: 'assets/images/nav/home_icon.svg',
                          label: 'Home',
                          active: activeTab == SkeenNavTab.home,
                          onTap: () => onTabSelected(SkeenNavTab.home),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          asset: 'assets/images/nav/history_icon.svg',
                          label: 'History',
                          active: activeTab == SkeenNavTab.history,
                          onTap: () => onTabSelected(SkeenNavTab.history),
                        ),
                      ),
                      const SizedBox(width: _fabSize + 12),
                      Expanded(
                        child: _NavItem(
                          asset: 'assets/images/nav/experts_icon.svg',
                          label: 'Experts',
                          active: activeTab == SkeenNavTab.experts,
                          onTap: () => onTabSelected(SkeenNavTab.experts),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          asset: 'assets/images/nav/profile_icon.svg',
                          label: 'Profile',
                          active: activeTab == SkeenNavTab.profile,
                          onTap: () => onTabSelected(SkeenNavTab.profile),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: _CenterFab(
                onTap: () => onTabSelected(SkeenNavTab.scan),
                isActive: activeTab == SkeenNavTab.scan,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.asset,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String asset;
  final String label;
  final bool active;
  final VoidCallback onTap;

  static const Color _activeColor = AppColors.violetaLink;
  static const Color _inactiveColor = Color(0xFF3B3261);

  @override
  Widget build(BuildContext context) {
    final color = active ? _activeColor : _inactiveColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                asset,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.08,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterFab extends StatelessWidget {
  const _CenterFab({required this.onTap, required this.isActive});

  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final fill = isActive ? AppColors.violetaOscuro : AppColors.violeta;
    return SizedBox(
      width: SkeenBottomNav._fabSize + 6,
      height: SkeenBottomNav._fabSize + 12,
      child: Stack(
        children: [
          Positioned(
            left: 3,
            top: 6,
            child: Container(
              width: SkeenBottomNav._fabSize,
              height: SkeenBottomNav._fabSize,
              decoration: BoxDecoration(
                color: AppColors.violetaOscuro,
                borderRadius: BorderRadius.circular(13),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 4,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 3,
            top: 0,
            child: Material(
              color: fill,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: onTap,
                child: SizedBox(
                  width: SkeenBottomNav._fabSize,
                  height: SkeenBottomNav._fabSize,
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/images/nav/plus_icon.svg',
                      width: 28,
                      height: 28,
                      colorFilter: const ColorFilter.mode(
                        AppColors.violetaClaro,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
