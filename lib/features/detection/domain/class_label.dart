/// The six lesion classes emitted by `skeen_v3.tflite` (EfficientNet-B0).
///
/// Order MUST match the model's output index map EXACTLY:
///   0 ACK  actinic_keratosis (pre-cancerous)
///   1 BCC  basal cell carcinoma      → malignant
///   2 MEL  melanoma                  → malignant
///   3 NEV  nevus                     → benign
///   4 SCC  squamous cell carcinoma   → malignant
///   5 OTHER other benign lesions (e.g. seborrheic keratosis)
///
/// The first five slugs are unchanged from the previous 5-class model and in
/// the same positions, so scans persisted by the old model deserialize into
/// the correct class; only the new index 5 (`other`) is additive.
enum ClassLabel {
  actinicKeratosis(slug: 'actinic_keratosis', display: 'Actinic Keratosis'),
  bcc(slug: 'bcc', display: 'Basal Cell Carcinoma'),
  melanoma(slug: 'melanoma', display: 'Melanoma'),
  nevus(slug: 'nevus', display: 'Benign Nevus'),
  scc(slug: 'scc', display: 'Squamous Cell Carcinoma'),
  other(slug: 'other', display: 'Other lesion');

  const ClassLabel({
    required this.slug,
    required this.display,
  });

  final String slug;
  final String display;

  /// Confirmed-malignant classes that count toward the cascade's
  /// `malignant_sum` and elevate the risk level: {BCC, MEL, SCC}.
  bool get isMalignant =>
      this == ClassLabel.bcc ||
      this == ClassLabel.melanoma ||
      this == ClassLabel.scc;

  /// Pre-cancerous, NOT confirmed malignant. Surfaced with elevated weight
  /// (caution) per clinical policy but excluded from the malignant sum.
  bool get isPrecancerous => this == ClassLabel.actinicKeratosis;

  /// Clinically benign classes: {NEV, OTHER}. Only these can yield a
  /// reassuring verdict.
  bool get isBenign =>
      this == ClassLabel.nevus || this == ClassLabel.other;

  /// The two classes driving the project's recall target (Melanoma + SCC).
  /// Highest-priority alerts in the UI palette.
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
