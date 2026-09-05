import 'package:flutter/foundation.dart';

/// Pinhole intrinsics of the camera stream the marker is detected in.
///
/// Tilt cannot be resolved from a homography without the focal length — the
/// same trapezoid can be a strongly tilted wide lens or a gently tilted long
/// one. Scale (px/mm) does not need it, but the perpendicularity axis does,
/// so a device that cannot report its focal length cannot measure tilt and
/// is excluded from the study on that named ground rather than handed an
/// assumed value.
///
/// Sourced from platform metadata: on Android from
/// `LENS_INFO_AVAILABLE_FOCAL_LENGTHS` and `SENSOR_INFO_PHYSICAL_SIZE`
/// (both required of every Camera2 device), on iOS from the capture device's
/// field of view. Never estimated from the image.
@immutable
class CameraIntrinsics {
  const CameraIntrinsics({
    required this.focalPx,
    required this.principalX,
    required this.principalY,
    required this.frameWidth,
    required this.frameHeight,
  });

  /// Focal length in pixels of the stream this describes, at zoom 1.0.
  final double focalPx;

  /// Principal point. Platforms rarely report it; the frame centre is the
  /// documented assumption and is accurate to a few pixels on phone modules.
  final double principalX;
  final double principalY;

  final int frameWidth;
  final int frameHeight;

  /// Intrinsics for the same stream under a digital zoom factor: the crop
  /// magnifies the image about the centre, so the focal length scales with
  /// it while the principal point stays put.
  CameraIntrinsics zoomed(double zoom) => CameraIntrinsics(
        focalPx: focalPx * zoom,
        principalX: principalX,
        principalY: principalY,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
      );

  /// Intrinsics rescaled to a stream of a different resolution but the same
  /// field of view (e.g. the detector's downsampled luma plane).
  CameraIntrinsics scaledTo(int width, int height) {
    final sx = width / frameWidth;
    final sy = height / frameHeight;
    return CameraIntrinsics(
      focalPx: focalPx * sx,
      principalX: principalX * sx,
      principalY: principalY * sy,
      frameWidth: width,
      frameHeight: height,
    );
  }

  @override
  String toString() =>
      'CameraIntrinsics(f=${focalPx.toStringAsFixed(1)}px, '
      'c=(${principalX.toStringAsFixed(1)}, ${principalY.toStringAsFixed(1)}), '
      '$frameWidth×$frameHeight)';
}
