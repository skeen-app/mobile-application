import 'package:skeen/core/localization/locale_controller.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Risk classification reported by the on-device TFLite triage model.
///
/// The colors and labels here are the source of truth for the history pill
/// and any other UI surface that needs to render a risk badge.
enum RiskLevel {
  low,
  medium,
  high;

  String get label {
    switch (this) {
      case RiskLevel.low:
        return 'Low Risk'.tr;
      case RiskLevel.medium:
        return 'Medium Risk'.tr;
      case RiskLevel.high:
        return 'High Risk'.tr;
    }
  }

  /// Solid accent color used for the pill text and border at full opacity.
  Color get accent {
    switch (this) {
      case RiskLevel.low:
        return AppColors.turquesa;
      case RiskLevel.medium:
        return const Color(0xFFFFB690);
      case RiskLevel.high:
        return AppColors.fucsia;
    }
  }
}
