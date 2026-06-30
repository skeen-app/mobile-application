import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/domain/class_label.dart';
import 'package:skeen/features/detection/domain/diagnosis_result.dart';
import 'package:skeen/features/detection/domain/inference_result.dart';
import 'package:skeen/features/detection/domain/triage_decision_policy.dart';

/// Builds a score vector in the model's index order (skeen_v3, 6 classes):
/// [ACK, BCC, MEL, NEV, SCC, OTHER].
InferenceResult _scores({
  double ak = 0,
  double bcc = 0,
  double melanoma = 0,
  double nevus = 0,
  double scc = 0,
  double other = 0,
}) {
  return InferenceResult(scores: [ak, bcc, melanoma, nevus, scc, other]);
}

void main() {
  const policy = TriageDecisionPolicy();

  test('malignant_sum only counts BCC + MEL + SCC (not ACK)', () {
    // Old model summed ACK into malignant_sum; the new policy must NOT.
    // ACK 0.50 + BCC 0.10 + MEL 0.10 + SCC 0.10 → malignant_sum = 0.30 < 0.55.
    final d = policy.evaluate(
      _scores(ak: 0.50, bcc: 0.10, melanoma: 0.10, scc: 0.10, nevus: 0.20),
    );
    expect(d.category, isNot(TriageCategory.malignantSpecific));
    expect(d.category, isNot(TriageCategory.malignantUnspecified));
  });

  test('Rule 1: malignant_sum >= 0.55 AND a class >= 0.55 → specific', () {
    final d = policy.evaluate(_scores(melanoma: 0.60, nevus: 0.20, scc: 0.10));
    expect(d.category, TriageCategory.malignantSpecific);
    expect(d.lesionType, ClassLabel.melanoma);
    expect(d.confidence, closeTo(0.60, 1e-9));
  });

  test('Rule 2: malignant_sum >= 0.55 but no class >= 0.55 → unspecified', () {
    // bcc+mel+scc = 0.20+0.20+0.20 = 0.60, top = 0.20 < 0.55.
    final d = policy.evaluate(
      _scores(bcc: 0.20, melanoma: 0.20, scc: 0.20, nevus: 0.40),
    );
    expect(d.category, TriageCategory.malignantUnspecified);
    expect(d.lesionType, isNull);
    expect(d.confidence, closeTo(0.60, 1e-9));
  });

  test('Rule 3: ack_p >= 0.55 → precancerous', () {
    final d = policy.evaluate(_scores(ak: 0.60, nevus: 0.40));
    expect(d.category, TriageCategory.precancerous);
    expect(d.lesionType, ClassLabel.actinicKeratosis);
    expect(d.confidence, closeTo(0.60, 1e-9));
  });

  test('Malignant takes precedence over precancerous', () {
    // ACK 0.30 but BCC 0.60 → malignant_sum 0.60, top BCC 0.60 → specific.
    final d = policy.evaluate(_scores(ak: 0.30, bcc: 0.60, nevus: 0.10));
    expect(d.category, TriageCategory.malignantSpecific);
    expect(d.lesionType, ClassLabel.bcc);
  });

  test('Rule 4: benign_sum (nevus + other) >= 0.70 → benign', () {
    final d = policy.evaluate(_scores(nevus: 0.72, melanoma: 0.10, scc: 0.18));
    expect(d.category, TriageCategory.benign);
    expect(d.lesionType, isNull);
    expect(d.confidence, closeTo(0.72, 1e-9));
  });

  test('Benign verdict aggregates NEV + OTHER', () {
    // Neither benign class alone reaches 0.70, but together 0.45+0.40=0.85.
    final d = policy.evaluate(_scores(nevus: 0.45, other: 0.40, melanoma: 0.15));
    expect(d.category, TriageCategory.benign);
    expect(d.confidence, closeTo(0.85, 1e-9));
  });

  test('Rule 5: nothing reaches threshold → inconclusive (not forced)', () {
    // malignant_sum 0.30, ack 0.20, benign_sum 0.50 — all below cut-offs.
    final d = policy.evaluate(
      _scores(ak: 0.20, melanoma: 0.30, nevus: 0.50),
    );
    expect(d.category, TriageCategory.inconclusive);
    expect(d.lesionType, isNull);
  });

  test('Boundary: benign_sum exactly 0.70 is benign (>=)', () {
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
