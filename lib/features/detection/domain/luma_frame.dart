import 'package:flutter/foundation.dart';

/// A luma-only frame handed to the marker detector: packed rows, no stride.
///
/// Produced by the camera service from the **same** image stream that feeds
/// the readiness metrics — a second stream would double the camera's work and
/// the two would drift out of sync. Downsampled for the detector's benefit;
/// [scaleToFull] carries the factor so every pose is expressed in full-frame
/// coordinates.
@immutable
class LumaFrame {
  const LumaFrame({
    required this.luma,
    required this.width,
    required this.height,
    required this.capturedAt,
    required this.scaleToFull,
    required this.zoom,
    this.rgb,
  });

  final Uint8List luma;
  final int width;
  final int height;
  final DateTime capturedAt;

  /// Multiply detection-frame pixel coordinates by this to get full-frame
  /// stream coordinates.
  final double scaleToFull;

  /// Digital zoom in force when the frame was captured. Scales the focal
  /// length used by the pose estimator.
  final double zoom;

  /// Interleaved RGB (3 bytes per pixel) at the same downsampled resolution
  /// as [luma], for the colour-patch calibration. Null when the source
  /// buffer had no chroma.
  final Uint8List? rgb;

  int get fullWidth => (width * scaleToFull).round();
  int get fullHeight => (height * scaleToFull).round();
}
