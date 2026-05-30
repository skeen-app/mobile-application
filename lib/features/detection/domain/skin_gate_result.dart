import 'package:flutter/foundation.dart';

/// Default cut-off used by the cascade's first stage to decide whether the
/// captured image looks like skin. Tunable from a single place so future
/// telemetry can drive the threshold without touching call sites.
///
/// `skin_detector_v1.tflite` (MobileNetV3Small, fully uint8-quantized)
/// has a severely compressed output distribution post-quantization:
/// empirical raw values cluster in 0–4 out of the 256 possible buckets,
/// with skin ≈ raw 4 (score ≈ 0.016) and non-skin ≈ raw 0 (score
/// ≈ 0.000). The model still discriminates, but with razor-thin margin.
///
/// 0.008 (≈ raw ≥ 3) is the lowest threshold that still rejects
/// confident non-skin while letting genuine skin through. This is a
/// workaround — v2 should be re-trained with one of:
///   • `inference_output_type = tf.float32` (skip output quantization
///     entirely; preserves the full sigmoid resolution)
///   • Post-hoc temperature scaling before export
///   • A representative calibration dataset richer in skin samples so
///     the quantization buckets aren't all clustered near 0
const double kSkinGateThreshold = 0.008;

/// Output of the cascade's stage-1 model (skin / not-skin filter).
///
/// The model emits a single sigmoid score in `[0, 1]` where higher values
/// mean "the image likely shows skin". The actual cancer classifier
/// ([InferenceResult]) only runs when [isSkin] is true.
@immutable
class SkinGateResult {
  const SkinGateResult({
    required this.skinScore,
    this.threshold = kSkinGateThreshold,
  });

  /// Sigmoid score in `[0, 1]`. 1.0 ≈ "definitely skin", 0.0 ≈ "definitely
  /// not skin".
  final double skinScore;

  /// Cut-off applied to [skinScore] when computing [isSkin].
  final double threshold;

  bool get isSkin => skinScore >= threshold;
}
