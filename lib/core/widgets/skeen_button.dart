import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum _SkeenButtonVariant { primary, secondary }

class SkeenButton extends StatelessWidget {
  const SkeenButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
  })  : _variant = _SkeenButtonVariant.primary;

  const SkeenButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
  })  : _variant = _SkeenButtonVariant.secondary;

  final String label;
  final VoidCallback onPressed;
  final _SkeenButtonVariant _variant;

  static const double _height = 52;
  static const double _radius = 11;
  static const BoxShadow _shadow = BoxShadow(
    color: Color(0x40000000),
    offset: Offset(0, 4),
    blurRadius: 4,
  );

  @override
  Widget build(BuildContext context) {
    final isPrimary = _variant == _SkeenButtonVariant.primary;
    final shadowOffset = isPrimary ? 5.93 : 4.93;

    final fill = isPrimary ? AppColors.violeta : AppColors.background;
    final shadowColor =
        isPrimary ? AppColors.violetaOscuro : AppColors.indigoClaro;
    final labelColor =
        isPrimary ? AppColors.textPrimary : AppColors.violetaLink;
    final border =
        isPrimary ? null : Border.all(color: AppColors.indigoClaro);

    return SizedBox(
      height: _height + shadowOffset,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: shadowOffset,
            child: Container(
              height: _height,
              decoration: BoxDecoration(
                color: shadowColor,
                borderRadius: BorderRadius.circular(_radius),
                boxShadow: const [_shadow],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _height,
            child: Material(
              color: fill,
              borderRadius: BorderRadius.circular(_radius),
              child: InkWell(
                borderRadius: BorderRadius.circular(_radius),
                onTap: onPressed,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_radius),
                    border: border,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      letterSpacing: -0.16,
                      color: labelColor,
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
