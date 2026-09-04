import 'package:flutter/foundation.dart';

/// How still the phone is, measured with the gyroscope.
///
/// Motion was previously inferred from the Laplacian score, which conflates
/// three different things — defocus, subject texture and camera shake — and
/// therefore could not distinguish "blurred because it is moving" from
/// "blurred because it is out of focus". The gyroscope measures rotation
/// directly, so the two signals become independent and the coaching can name
/// the actual problem.
@immutable
class CaptureStability {
  const CaptureStability({required this.angularSpeed});

  /// Smoothed magnitude of the gyroscope vector, in rad/s.
  final double angularSpeed;

  /// Reported before the first sensor sample arrives. Not steady: the gate
  /// stays shut until the sensor has actually said something.
  static const CaptureStability unknown =
      CaptureStability(angularSpeed: double.nan);

  bool get isKnown => !angularSpeed.isNaN;

  /// 0.15 rad/s ≈ 8.6 °/s. At a typical macro working distance with an
  /// exposure around 1/60 s that is roughly a pixel of smear on a 1080-wide
  /// frame — the point where motion starts eating the fine border detail the
  /// classifier reads. Hand tremor at rest sits near 0.02–0.05 rad/s, so a
  /// steady hand clears this comfortably.
  static const double steadyThreshold = 0.15;

  bool get isSteady => isKnown && angularSpeed <= steadyThreshold;

  @override
  String toString() => isKnown
      ? 'CaptureStability(${angularSpeed.toStringAsFixed(3)} rad/s)'
      : 'CaptureStability(unknown)';
}
