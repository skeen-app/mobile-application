import 'class_label.dart';
import 'diagnosis_result.dart';
import 'inference_result.dart';

/// Pure domain service implementing the cascade's **conservative three-tier
/// decision logic** over the classifier's softmax scores.
///
/// This deliberately does NOT touch persistence, [InferenceResult], or the
/// [WarningLevel] palette — those keep driving the AR label, history rows,
/// PDF and notifications. [DiagnosisResult] is a derived clinical read shown
/// on the triage result screen.
///
/// Thresholds (see AI_MODEL_SPECS.md). Tunable from this single place.
class TriageDecisionPolicy {
  const TriageDecisionPolicy();

  /// `nevus_p` cut-off for a benign verdict.
  static const double thBenign = 0.70;

  /// Minimum summed probability over the four malignant classes for any
  /// malignant verdict.
  static const double thMalignantSum = 0.55;

  /// Minimum probability a single malignant class must reach to be named.
  static const double thSpecific = 0.55;

  /// Maps raw classifier scores to a [DiagnosisResult]. Order of the rules
  /// matters and follows the spec exactly:
  ///   1. benign            → nevus_p >= 0.70
  ///   2. malignant_specific→ malignant_sum >= 0.55 AND top_mal_p >= 0.55
  ///   3. malignant_unspec. → malignant_sum >= 0.55 (no class reached 0.55)
  ///   4. inconclusive      → otherwise
  DiagnosisResult evaluate(InferenceResult result) {
    final scores = result.scores;

    final nevusP = scores[ClassLabel.nevus.index];

    // Sum the four malignant classes and find the strongest one.
    var malignantSum = 0.0;
    ClassLabel topMal = ClassLabel.melanoma;
    var topMalP = -1.0;
    for (final label in ClassLabel.values) {
      if (!label.isMalignant) continue;
      final p = scores[label.index];
      malignantSum += p;
      if (p > topMalP) {
        topMalP = p;
        topMal = label;
      }
    }

    // Rule 1 — benign.
    if (nevusP >= thBenign) {
      return DiagnosisResult(
        category: TriageCategory.benign,
        confidence: nevusP,
        titleKey: 'triage.benign.title',
        messageKey: 'triage.benign.message',
      );
    }

    // Rule 2 — malignant, specific type.
    if (malignantSum >= thMalignantSum && topMalP >= thSpecific) {
      return DiagnosisResult(
        category: TriageCategory.malignantSpecific,
        lesionType: topMal,
        confidence: topMalP,
        titleKey: 'triage.malignantSpecific.title',
        messageKey: 'triage.malignantSpecific.message',
      );
    }

    // Rule 3 — malignant, type undetermined.
    if (malignantSum >= thMalignantSum) {
      return DiagnosisResult(
        category: TriageCategory.malignantUnspecified,
        confidence: malignantSum,
        titleKey: 'triage.malignantUnspecified.title',
        messageKey: 'triage.malignantUnspecified.message',
      );
    }

    // Rule 4 — inconclusive.
    return DiagnosisResult(
      category: TriageCategory.inconclusive,
      confidence: result.confidence,
      titleKey: 'triage.inconclusive.title',
      messageKey: 'triage.inconclusive.message',
    );
  }
}
