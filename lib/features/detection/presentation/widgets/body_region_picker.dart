import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Bottom sheet / inline picker for body region selection after capture.
/// Presented before navigating to the triage result screen so the captured
/// lesion can be associated with a body region for the body map / history.
class BodyRegionPicker extends StatelessWidget {
  const BodyRegionPicker({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _regions = <_RegionOption>[
    _RegionOption(label: 'Head', icon: Icons.face_outlined),
    _RegionOption(label: 'Neck', icon: Icons.accessibility_new),
    _RegionOption(label: 'Chest', icon: Icons.airline_seat_flat),
    _RegionOption(label: 'Back', icon: Icons.event_seat),
    _RegionOption(label: 'Left Arm', icon: Icons.back_hand_outlined),
    _RegionOption(label: 'Right Arm', icon: Icons.front_hand_outlined),
    _RegionOption(label: 'Abdomen', icon: Icons.crop_square_outlined),
    _RegionOption(label: 'Left Leg', icon: Icons.directions_walk),
    _RegionOption(label: 'Right Leg', icon: Icons.directions_walk_outlined),
  ];

  /// Show as a modal bottom sheet.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => BodyRegionPicker(
        onSelected: (region) => Navigator.of(ctx).pop(region),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.violetaOscuro),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.hintText.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Where is the mole located?',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 18,
              letterSpacing: -0.18,
              color: AppColors.violetaClaro,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select the body region for tracking',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: AppColors.hintText,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _regions
                .map((r) => _RegionChip(
                      label: r.label,
                      icon: r.icon,
                      onTap: () => onSelected(r.label),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _RegionOption {
  const _RegionOption({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1444),
            border: Border.all(color: const Color(0xFF2F1B66)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.violeta, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
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
