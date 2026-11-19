import 'package:skeen/core/localization/locale_controller.dart';
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
/// Five inline tabs (no protruding FAB): Home · History · Scan · Insights
/// · Profile. The center "Scan" tab is rendered with a violet-filled
/// rounded square + plus icon so it still reads as the primary action,
/// but it stays inside the bar's silhouette — no overlap with the
/// content above and a stable tap area.
class SkeenBottomNav extends StatelessWidget {
  const SkeenBottomNav({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
  });

  final SkeenNavTab activeTab;
  final ValueChanged<SkeenNavTab> onTabSelected;

  static const double height = 78;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
                    label: 'Home'.tr,
                    active: activeTab == SkeenNavTab.home,
                    onTap: () => onTabSelected(SkeenNavTab.home),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    asset: 'assets/images/nav/history_icon.svg',
                    label: 'History'.tr,
                    active: activeTab == SkeenNavTab.history,
                    onTap: () => onTabSelected(SkeenNavTab.history),
                  ),
                ),
                Expanded(
                  child: _ScanNavItem(
                    active: activeTab == SkeenNavTab.scan,
                    onTap: () => onTabSelected(SkeenNavTab.scan),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    asset: 'assets/images/nav/experts_icon.svg',
                    label: 'Insights'.tr,
                    active: activeTab == SkeenNavTab.experts,
                    onTap: () => onTabSelected(SkeenNavTab.experts),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    asset: 'assets/images/nav/profile_icon.svg',
                    label: 'Profile'.tr,
                    active: activeTab == SkeenNavTab.profile,
                    onTap: () => onTabSelected(SkeenNavTab.profile),
                  ),
                ),
              ],
            ),
          ),
        ),
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

/// Center "Scan" tab — same vertical layout as the other items, but the
/// icon sits inside a violet rounded square so it reads as the primary
/// action without protruding above the bar.
class _ScanNavItem extends StatelessWidget {
  const _ScanNavItem({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = active ? AppColors.violetaOscuro : AppColors.violeta;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/images/nav/plus_icon.svg',
                    width: 22,
                    height: 22,
                    colorFilter: const ColorFilter.mode(
                      AppColors.violetaClaro,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Scan'.tr,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.08,
                  color: AppColors.violetaClaro,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
