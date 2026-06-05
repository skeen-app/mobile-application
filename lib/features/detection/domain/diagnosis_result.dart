import 'package:flutter/foundation.dart';

import 'class_label.dart';

/// Triage verdict produced by the cascade's conservative three-tier decision
/// logic (see [TriageDecisionPolicy]). This is the *clinical* read on top of
/// the raw [InferenceResult] scores — it is what the result screen and the
/// not-skin dialog surface to the user.
///
/// Pure data; no Flutter/platform deps beyond `@immutable`. The [messageKey]
/// and [titleKey] are English l10n keys resolved at the presentation layer via
/// the app's `.tr` extension, so the domain stays language-agnostic while the
/// user still reads Spanish/English per their locale.
enum TriageCategory {
  /// Stage-1 short-circuit: the frame did not look like skin. The classifier
  /// never ran. Surfaced by the existing not-skin dialog.
  notSkin,

  /// `nevus_p >= TH_BENIGN`. Findings compatible with a benign lesion.
  benign,

  /// `malignant_sum >= TH_MALIGNANT_SUM` AND a single malignant class reached
  /// `TH_SPECIFIC`. Carries a concrete [DiagnosisResult.lesionType].
  malignantSpecific,

  /// `malignant_sum >= TH_MALIGNANT_SUM` but no single class reached
  /// `TH_SPECIFIC`. Risk present, type undetermined.
  malignantUnspecified,

  /// None of the above thresholds met. Inconclusive — recommend specialist.
  inconclusive,
}

@immutable
class DiagnosisResult {
  const DiagnosisResult({
    required this.category,
    required this.confidence,
    required this.titleKey,
    required this.messageKey,
    this.lesionType,
  });

  /// The conservative tier this lesion falls into.
  final TriageCategory category;

  /// Concrete lesion type — only populated for [TriageCategory.malignantSpecific].
  final ClassLabel? lesionType;

  /// Probability of the winning class, in `[0, 1]`. Shown in the UI as a
  /// percentage. For [TriageCategory.notSkin] this carries the skin score.
  final double confidence;

  /// English l10n key for the short headline (e.g. "Benign findings").
  final String titleKey;

  /// English l10n key for the full user-facing message. For
  /// [TriageCategory.malignantSpecific] the key contains a `{type}`
  /// placeholder the presentation layer replaces with the localized lesion
  /// name.
  final String messageKey;

  bool get isMalignant =>
      category == TriageCategory.malignantSpecific ||
      category == TriageCategory.malignantUnspecified;
}
