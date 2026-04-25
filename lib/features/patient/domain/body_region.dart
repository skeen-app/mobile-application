import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// High-level body regions used for grouping lesion scans on the home body map.
///
/// The home screen aggregates per-region counts (Head / Chest / Legs); finer
/// regions (Arms, Back, etc.) collapse into the closest aggregate when shown
/// on the dashboard but remain distinct in the underlying `LesionSummary`.
enum BodyRegion {
  head,
  chest,
  leftArm,
  rightArm,
  back,
  leftLeg,
  rightLeg;

  BodyRegionGroup get group {
    switch (this) {
      case BodyRegion.head:
        return BodyRegionGroup.head;
      case BodyRegion.chest:
      case BodyRegion.back:
      case BodyRegion.leftArm:
      case BodyRegion.rightArm:
        return BodyRegionGroup.chest;
      case BodyRegion.leftLeg:
      case BodyRegion.rightLeg:
        return BodyRegionGroup.legs;
    }
  }
}

/// Aggregate buckets surfaced on the home dashboard body map bars.
enum BodyRegionGroup {
  head,
  chest,
  legs;

  String get label {
    switch (this) {
      case BodyRegionGroup.head:
        return 'Head';
      case BodyRegionGroup.chest:
        return 'Chest';
      case BodyRegionGroup.legs:
        return 'Legs';
    }
  }

  Color get accent {
    switch (this) {
      case BodyRegionGroup.head:
        return AppColors.violeta;
      case BodyRegionGroup.chest:
        return AppColors.turquesa;
      case BodyRegionGroup.legs:
        return AppColors.naranja;
    }
  }
}
