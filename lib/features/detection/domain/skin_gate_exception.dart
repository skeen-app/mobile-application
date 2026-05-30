import 'skin_gate_result.dart';

/// Thrown by the capture pipeline when the cascade's stage-1 model decides
/// the input image is not skin. The capture flow catches this to short-
/// circuit the cancer classifier, skip persistence, and surface the
/// "focus on a skin lesion" dialog to the user.
class NotSkinDetectedException implements Exception {
  const NotSkinDetectedException(this.result);

  final SkinGateResult result;

  @override
  String toString() =>
      'NotSkinDetectedException(score=${result.skinScore.toStringAsFixed(3)}, '
      'threshold=${result.threshold.toStringAsFixed(2)})';
}
