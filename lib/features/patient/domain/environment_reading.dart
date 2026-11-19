import 'package:skeen/core/localization/locale_controller.dart';
/// Environmental context for the home dashboard temperature card.
///
/// Combines reverse-geocoded location with current temperature and UV index,
/// then derives an SPF recommendation. The reading is a value object — it is
/// recomputed each time `environmentProvider` refreshes.
class EnvironmentReading {
  const EnvironmentReading({
    required this.locationLabel,
    required this.temperatureCelsius,
    required this.uvIndex,
  });

  final String locationLabel;
  final double temperatureCelsius;
  final double uvIndex;

  /// SPF recommendation derived from UV index, with temperature as a
  /// secondary signal for warm climates where UV often co-occurs with heat.
  ///
  /// Thresholds aligned with WHO guidance:
  ///   UV  0–2  → no protection required (SPF 15 if user opts in)
  ///   UV  3–5  → SPF 30
  ///   UV  6–7  → SPF 30 with reapplication
  ///   UV  8–10 → SPF 50+
  ///   UV  11+  → SPF 50+, avoid midday sun
  SpfRecommendation get spfRecommendation {
    if (uvIndex >= 8 || temperatureCelsius >= 28) {
      return SpfRecommendation(label: 'USE SPF 50+'.tr, minimumSpf: 50);
    }
    if (uvIndex >= 6) {
      return SpfRecommendation(label: 'USE SPF 30+'.tr, minimumSpf: 30);
    }
    if (uvIndex >= 3) {
      return SpfRecommendation(label: 'USE SPF 30'.tr, minimumSpf: 30);
    }
    return SpfRecommendation(label: 'SPF 15 OPTIONAL'.tr, minimumSpf: 15);
  }
}

class SpfRecommendation {
  const SpfRecommendation({required this.label, required this.minimumSpf});

  final String label;
  final int minimumSpf;
}
