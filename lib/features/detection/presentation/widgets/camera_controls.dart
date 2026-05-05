import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Vertical zoom slider docked along the right edge of the viewfinder.
/// Range mirrors the camera plugin contract: 1× (no zoom) to 5× (max
/// reasonable on phone optics without quality loss).
class CameraZoomSlider extends StatelessWidget {
  const CameraZoomSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1.0,
    this.max = 5.0,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.55),
        border: Border.all(color: AppColors.violetaOscuro),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            '${value.toStringAsFixed(1)}×',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: AppColors.violetaClaro,
            ),
          ),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  activeTrackColor: AppColors.violeta,
                  inactiveTrackColor: AppColors.violetaOscuro,
                  thumbColor: AppColors.violetaClaro,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill-shaped flash toggle. Sits next to the shutter row.
class CameraFlashButton extends StatelessWidget {
  const CameraFlashButton({
    super.key,
    required this.isOn,
    required this.onTap,
  });

  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isOn ? AppColors.naranja : AppColors.violetaClaro;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.65),
          border: Border.all(color: color, width: 1.2),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isOn
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Icon(
          isOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          color: color,
          size: 22,
        ),
      ),
    );
  }
}
