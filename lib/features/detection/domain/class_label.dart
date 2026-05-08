/// The five lesion classes emitted by `skeen_v2_quantized.tflite`.
///
/// Order MUST match the model's output index map (see AI_MODEL_SPECS.md):
///   0 actinic_keratosis · 1 bcc · 2 melanoma · 3 nevus · 4 scc
enum ClassLabel {
  actinicKeratosis(slug: 'actinic_keratosis', display: 'Actinic Keratosis'),
  bcc(slug: 'bcc', display: 'Basal Cell Carcinoma'),
  melanoma(slug: 'melanoma', display: 'Melanoma'),
  nevus(slug: 'nevus', display: 'Benign Nevus'),
  scc(slug: 'scc', display: 'Squamous Cell Carcinoma');

  const ClassLabel({
    required this.slug,
    required this.display,
  });

  final String slug;
  final String display;

  /// Nevus is the only class clinically considered benign. Every other class
  /// is malignant or pre-malignant and must be surfaced with elevated visual
  /// weight regardless of confidence (see AI_MODEL_SPECS.md priority rule).
  bool get isBenign => this == ClassLabel.nevus;

  /// Two of the five classes drive the project's recall target (SCC 0.77 +
  /// Melanoma). They are the highest-priority alerts in the UI palette.
  bool get isHighRisk => this == ClassLabel.scc || this == ClassLabel.melanoma;

  static ClassLabel fromIndex(int i) => ClassLabel.values[i];

  static ClassLabel fromSlug(String s) =>
      ClassLabel.values.firstWhere((c) => c.slug == s);
}

/// Coarse risk bucket used by the AR floating label and history rows. Driven
/// by the class first, confidence second — per the priority rule in the spec.
enum WarningLevel {
  /// Benign + high confidence. Turquoise tint.
  reassuring,
  /// Anything classified as malignant/pre-malignant, or any low-confidence
  /// result. Orange tint, prominent label.
  caution,
  /// Highest-risk classes (SCC, Melanoma) with non-trivial confidence.
  /// Fucsia tint, strongest visual treatment.
  alert,
}
