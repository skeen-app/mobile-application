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

  /// Benign-probability cut-off for a benign verdict. Summed over the
  /// clinically-benign classes {nevus, other}.
  static const double thBenign = 0.70;

  /// Minimum summed probability over the malignant classes {BCC, MEL, SCC}
  /// for any malignant verdict.
  static const double thMalignantSum = 0.55;

  /// Minimum probability a single malignant class must reach to be named.
  static const double thSpecific = 0.55;

  /// Minimum `ack_p` for a pre-cancerous (actinic keratosis) verdict.
  static const double thPrecancerous = 0.55;

  /// Maps raw classifier scores to a [DiagnosisResult]. Rule order is
  /// safety-first (flag risk before reassuring), and reads class positions
  /// via [ClassLabel] getters so it never assumes a fixed index layout:
  ///   1. malignant_specific → malignant_sum >= 0.55 AND top_mal_p >= 0.55
  ///   2. malignant_unspec.  → malignant_sum >= 0.55 (no class reached 0.55)
  ///   3. precancerous       → ack_p >= 0.55
  ///   4. benign             → benign_sum (nevus+other) >= 0.70
  ///   5. inconclusive       → otherwise (low confidence — NOT forced)
  DiagnosisResult evaluate(InferenceResult result) {
    final scores = result.scores;

    // Sum the malignant classes {BCC, MEL, SCC} and find the strongest one.
    var malignantSum = 0.0;
    ClassLabel topMal = ClassLabel.melanoma;
    var topMalP = -1.0;
    var benignSum = 0.0;
    for (final label in ClassLabel.values) {
      final p = scores[label.index];
      if (label.isMalignant) {
        malignantSum += p;
        if (p > topMalP) {
          topMalP = p;
          topMal = label;
        }
      } else if (label.isBenign) {
        benignSum += p;
      }
    }
    final ackP = scores[ClassLabel.actinicKeratosis.index];

    // Rule 1 — malignant, specific type.
    if (malignantSum >= thMalignantSum && topMalP >= thSpecific) {
      return DiagnosisResult(
        category: TriageCategory.malignantSpecific,
        lesionType: topMal,
        confidence: topMalP,
        titleKey: 'triage.malignantSpecific.title',
        messageKey: 'triage.malignantSpecific.message',
      );
    }

    // Rule 2 — malignant, type undetermined.
    if (malignantSum >= thMalignantSum) {
      return DiagnosisResult(
        category: TriageCategory.malignantUnspecified,
        confidence: malignantSum,
        titleKey: 'triage.malignantUnspecified.title',
        messageKey: 'triage.malignantUnspecified.message',
      );
    }

    // Rule 3 — pre-cancerous (actinic keratosis).
    if (ackP >= thPrecancerous) {
      return DiagnosisResult(
        category: TriageCategory.precancerous,
        lesionType: ClassLabel.actinicKeratosis,
        confidence: ackP,
        titleKey: 'triage.precancerous.title',
        messageKey: 'triage.precancerous.message',
      );
    }

    // Rule 4 — benign.
    if (benignSum >= thBenign) {
      return DiagnosisResult(
        category: TriageCategory.benign,
        confidence: benignSum,
        titleKey: 'triage.benign.title',
        messageKey: 'triage.benign.message',
      );
    }

    // Rule 5 — inconclusive (low confidence; we do NOT force a class).
    return DiagnosisResult(
      category: TriageCategory.inconclusive,
      confidence: result.confidence,
      titleKey: 'triage.inconclusive.title',
      messageKey: 'triage.inconclusive.message',
    );
  }
}
