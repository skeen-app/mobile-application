import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Distance reading from the depth sensor (LiDAR / ARCore Depth) or a
/// camera-focus heuristic when no sensor is available. Always in
/// **centimeters** so the domain stays SI-friendly without unit conversions
/// scattered through the UI.
@immutable
class CaptureDistance {
  const CaptureDistance.cm(this.cm) : isEstimated = false;
  const CaptureDistance.estimated(this.cm) : isEstimated = true;
  const CaptureDistance.unknown()
      : cm = double.nan,
        isEstimated = true;

  final double cm;
  final bool isEstimated;
  bool get isKnown => !cm.isNaN;

  /// Optimal range for the EfficientNetB0 fine-tune (see PROJECT spec).
  /// 15 cm centerpoint with ±2 cm tolerance feels stable in user tests; the
  /// outer band 10–20 cm is "acceptable but coach the user".
  static const double sweetSpotCm = 15.0;
  static const double sweetSpotTolerance = 2.0;
  static const double minAcceptableCm = 10.0;
  static const double maxAcceptableCm = 20.0;

  bool get isInSweetSpot =>
      isKnown && (cm - sweetSpotCm).abs() <= sweetSpotTolerance;

  bool get isInAcceptableRange =>
      isKnown && cm >= minAcceptableCm && cm <= maxAcceptableCm;

  /// True when the user is too close (red ring). Distinct from
  /// [tooFar] so coaching copy can be specific.
  bool get tooClose => isKnown && cm < minAcceptableCm;
  bool get tooFar => isKnown && cm > maxAcceptableCm;
}

/// 2D bounding box in **camera-frame pixel space** (origin top-left).
/// Today this is constructed from the on-screen reticle (the lesion is
/// always centered by UX); when a real detector lands the same struct
/// will be filled from the model output instead.
@immutable
class BoundingBox {
  const BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.frameWidth,
    required this.frameHeight,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final double frameWidth;
  final double frameHeight;

  Offset get center => Offset(left + width / 2, top + height / 2);

  /// Center expressed in normalized [0,1] coordinates — what hit-test APIs
  /// (ARKit, ARCore) consume.
  Offset get normalizedCenter => Offset(
        center.dx / frameWidth,
        center.dy / frameHeight,
      );
}

/// 3D pose returned by an AR hit-test against the detected skin plane.
/// Translation is in **meters** (AR convention); rotation is a quaternion.
@immutable
class WorldAnchor {
  const WorldAnchor({
    required this.id,
    required this.translation,
    required this.rotation,
  });

  final String id;
  final Vector3 translation;
  final Quaternion rotation;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tx': translation.x,
        'ty': translation.y,
        'tz': translation.z,
        'qx': rotation.x,
        'qy': rotation.y,
        'qz': rotation.z,
        'qw': rotation.w,
      };

  factory WorldAnchor.fromJson(Map<String, dynamic> json) => WorldAnchor(
        id: json['id'] as String,
        translation: Vector3(
          (json['tx'] as num).toDouble(),
          (json['ty'] as num).toDouble(),
          (json['tz'] as num).toDouble(),
        ),
        rotation: Quaternion(
          (json['qx'] as num).toDouble(),
          (json['qy'] as num).toDouble(),
          (json['qz'] as num).toDouble(),
          (json['qw'] as num).toDouble(),
        ),
      );
}

/// Lightweight value types so the domain doesn't depend on `vector_math`.
/// (Adding it just for two structs would bloat the dependency graph.)
@immutable
class Vector3 {
  const Vector3(this.x, this.y, this.z);
  final double x, y, z;
}

@immutable
class Quaternion {
  const Quaternion(this.x, this.y, this.z, this.w);
  final double x, y, z, w;
  static const Quaternion identity = Quaternion(0, 0, 0, 1);
}
