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

  /// Risk bucket for the AR label palette / history row. Driven by class
  /// identity first (malignancy/pre-cancer always wins), confidence second.
  /// Class indices are read via [ClassLabel] getters — no hardcoded order:
  ///
  ///   * SCC / Melanoma at ≥ 0.40 → alert (per spec recall target)
  ///   * Any confirmed-malignant class (BCC/MEL/SCC) → caution (minimum)
  ///   * Pre-cancerous (ACK) → caution
  ///   * Benign (NEV/OTHER) + ≥ 0.65 confidence → reassuring
  ///   * Otherwise → caution (low-confidence benign falls back here)
  WarningLevel get warningLevel {
    if (topLabel.isHighRisk && confidence >= 0.40) return WarningLevel.alert;
    if (topLabel.isMalignant) return WarningLevel.caution;
    if (topLabel.isPrecancerous) return WarningLevel.caution;
    if (topLabel.isBenign && confidence >= 0.65) return WarningLevel.reassuring;
    return WarningLevel.caution;
  }

  Map<String, dynamic> toJson() => {
        'topLabel': topLabel.slug,
        'confidence': confidence,
        'scores': scores,
        if (lesionCentroid != null)
          'centroid': {'x': lesionCentroid!.dx, 'y': lesionCentroid!.dy},
      };

  factory InferenceResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['scores'] as List).cast<num>();
    final centroid = json['centroid'] as Map?;
    return InferenceResult(
      // Scans persisted by the previous 5-class model carry 5 scores; the
      // current model emits 6. Fit the stored vector to the current class
      // count (pad missing trailing classes with 0.0 / truncate extras) so
      // legacy rows still load instead of tripping the length assert. The
      // first five class indices are unchanged, so the argmax is preserved.
      scores: _fitToClassCount(raw.map((n) => n.toDouble()).toList()),
      lesionCentroid: centroid == null
          ? null
          : Offset(
              (centroid['x'] as num).toDouble(),
              (centroid['y'] as num).toDouble(),
            ),
    );
  }

  /// Normalizes a (possibly legacy) score vector to exactly
  /// [ClassLabel.values] entries — pads trailing classes with 0.0 and
  /// truncates any extras. Keeps deserialization of old persisted scans safe
  /// across the 5→6 class migration.
  static List<double> _fitToClassCount(List<double> scores) {
    final n = ClassLabel.values.length;
    if (scores.length == n) return scores;
    final fitted = List<double>.filled(n, 0.0);
    for (var i = 0; i < n && i < scores.length; i++) {
      fitted[i] = scores[i];
    }
    return fitted;
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
