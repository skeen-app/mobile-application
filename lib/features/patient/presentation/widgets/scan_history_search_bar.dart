import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Pill-shaped search input + filter button row used at the top of the
/// history screen. Stateless — owners pass a [TextEditingController] and
/// react to [onChanged] / [onFilterPressed].
class ScanHistorySearchBar extends StatelessWidget {
  const ScanHistorySearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onFilterPressed,
    this.activeFilterCount = 0,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterPressed;
  final int activeFilterCount;

  static const Color _surface = Color(0xFF0A0732);
  static const Color _stroke = Color(0x264A4455); // rgba(74,68,85,0.15)

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _stroke),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.search,
                  size: 20,
                  color: Color(0xFF958DA1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    cursorColor: AppColors.violetaClaro,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      color: AppColors.violetaClaro,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Search history...'.tr,
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        color: Color(0xFF958DA1),
                      ),
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    },
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xFF958DA1),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: _stroke),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onFilterPressed,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.tune,
                    size: 20,
                    color: AppColors.violetaClaro,
                  ),
                  if (activeFilterCount > 0)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.violeta,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
