import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/domain/class_label.dart';
import 'package:skeen/features/detection/domain/diagnosis_result.dart';
import 'package:skeen/features/detection/domain/inference_result.dart';
import 'package:skeen/features/detection/domain/triage_decision_policy.dart';

/// Builds a score vector in the model's alphabetical class order:
/// [actinic_keratosis, bcc, melanoma, nevus, scc].
InferenceResult _scores({
  double ak = 0,
  double bcc = 0,
  double melanoma = 0,
  double nevus = 0,
  double scc = 0,
}) {
  return InferenceResult(scores: [ak, bcc, melanoma, nevus, scc]);
}

void main() {
  const policy = TriageDecisionPolicy();

  test('Rule 1: nevus_p >= 0.70 → benign', () {
    final d = policy.evaluate(_scores(nevus: 0.72, melanoma: 0.10, scc: 0.18));
    expect(d.category, TriageCategory.benign);
    expect(d.lesionType, isNull);
    expect(d.confidence, closeTo(0.72, 1e-9));
  });

  test('Rule 1 takes precedence even if malignant_sum is high', () {
    // nevus 0.70 wins before the malignant_sum branch is considered.
    final d = policy.evaluate(_scores(nevus: 0.70, scc: 0.30));
    expect(d.category, TriageCategory.benign);
  });

  test('Rule 2: malignant_sum >= 0.55 AND a class >= 0.55 → specific', () {
    final d = policy.evaluate(_scores(melanoma: 0.60, nevus: 0.20, scc: 0.10));
    expect(d.category, TriageCategory.malignantSpecific);
    expect(d.lesionType, ClassLabel.melanoma);
    expect(d.confidence, closeTo(0.60, 1e-9));
  });

  test('Rule 3: malignant_sum >= 0.55 but no class >= 0.55 → unspecified', () {
    // ak+bcc+melanoma+scc = 0.20+0.20+0.20+0.05 = 0.65, top = 0.20 < 0.55.
    final d = policy.evaluate(
      _scores(ak: 0.20, bcc: 0.20, melanoma: 0.20, nevus: 0.35, scc: 0.05),
    );
    expect(d.category, TriageCategory.malignantUnspecified);
    expect(d.lesionType, isNull);
    expect(d.confidence, closeTo(0.65, 1e-9));
  });

  test('Rule 4: nothing reaches threshold → inconclusive', () {
    // nevus 0.50 (<0.70), malignant_sum 0.50 (<0.55).
    final d = policy.evaluate(
      _scores(ak: 0.20, melanoma: 0.30, nevus: 0.50),
    );
    expect(d.category, TriageCategory.inconclusive);
    expect(d.lesionType, isNull);
  });

  test('Boundary: nevus exactly 0.70 is benign (>=)', () {
    expect(
      policy.evaluate(_scores(nevus: 0.70, melanoma: 0.30)).category,
      TriageCategory.benign,
    );
  });

  test('Boundary: malignant_sum exactly 0.55 with top exactly 0.55', () {
    final d = policy.evaluate(_scores(melanoma: 0.55, nevus: 0.45));
    expect(d.category, TriageCategory.malignantSpecific);
    expect(d.lesionType, ClassLabel.melanoma);
  });

  test('top_mal picks the strongest malignant class', () {
    final d = policy.evaluate(
      _scores(ak: 0.05, bcc: 0.58, melanoma: 0.05, nevus: 0.22, scc: 0.10),
    );
    expect(d.category, TriageCategory.malignantSpecific);
    expect(d.lesionType, ClassLabel.bcc);
  });
}
