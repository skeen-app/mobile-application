import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'class_label.dart';

/// Output of one TFLite inference pass over a captured frame. Pure data;
/// no Flutter or platform deps.
@immutable
class InferenceResult {
  InferenceResult({
    required this.scores,
    this.lesionCentroid,
  })  : assert(scores.length == ClassLabel.values.length,
            'Model must emit one score per ClassLabel'),
        topLabel = ClassLabel.fromIndex(_argmaxIndex(scores)),
        confidence = scores.reduce((a, b) => a > b ? a : b);

  /// Probability per class, indexed to match [ClassLabel.index].
  final List<double> scores;
  final ClassLabel topLabel;
  final double confidence;
  
  /// The center of mass calculated via contrast thresholding (optional).
  final Offset? lesionCentroid;

  /// Risk bucket for the AR label palette / history row. The rule combines
  /// class identity (always wins for malignant) with confidence:
  ///
  ///   * SCC / Melanoma at ≥ 0.40 → alert (per spec recall target)
  ///   * Any malignant or pre-malignant class → caution (minimum)
  ///   * Benign + ≥ 0.65 confidence → reassuring
  ///   * Otherwise → caution (low-confidence benign falls back here)
  WarningLevel get warningLevel {
    if (topLabel.isHighRisk && confidence >= 0.40) return WarningLevel.alert;
    if (!topLabel.isBenign) return WarningLevel.caution;
    if (confidence >= 0.65) return WarningLevel.reassuring;
    return WarningLevel.caution;
  }

  Map<String, dynamic> toJson() => {
        'topLabel': topLabel.slug,
        'confidence': confidence,
        'scores': scores,
      };

  factory InferenceResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['scores'] as List).cast<num>();
    return InferenceResult(scores: raw.map((n) => n.toDouble()).toList());
  }

  static int _argmaxIndex(List<double> scores) {
    var maxIdx = 0;
    var maxVal = scores[0];
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > maxVal) {
        maxVal = scores[i];
        maxIdx = i;
      }
    }
    return maxIdx;
  }
}
