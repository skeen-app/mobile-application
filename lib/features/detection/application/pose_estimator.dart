import 'dart:math' as math;
import 'dart:ui';

import '../domain/camera_intrinsics.dart';
import '../domain/fiducial_marker.dart';
import '../domain/homography.dart';
import '../domain/skin_plane_pose.dart';

/// Resolves the camera's pose relative to the skin plane from the marker's
/// four corners and the camera intrinsics — a planar PnP.
///
/// Two outputs, two different requirements:
///
///  • **px/mm** needs only the homography. It is the local scale of the
///    plane→image map at the marker centre, and the marker's physical side
///    is known. No intrinsics involved.
///  • **tilt** needs the focal length. The homography is `K [r1 r2 t]` up to
///    scale; stripping `K` recovers the plane's orientation, and without `K`
///    the same image quad is consistent with many tilts. That is why a
///    device that cannot report its focal length cannot measure this axis
///    and is excluded on that ground — never handed an assumed value.
///
/// Corners are in full-frame stream pixels and the intrinsics must describe
/// the same frame (and the same zoom).
SkinPlanePose? estimatePose({
  required List<Offset> corners,
  required CameraIntrinsics intrinsics,
  required DateTime detectedAt,
  required int detectionMs,
  FiducialMarker marker = FiducialMarker.study,
}) {
  if (corners.length != 4) return null;

  // Plane frame: millimetres, origin at the marker centre, X to the marker's
  // right, Y down — matching the canonical clockwise corner order the
  // detector produces (TL, TR, BR, BL).
  final half = marker.sideMm / 2;
  final plane = [
    Offset(-half, -half),
    Offset(half, -half),
    Offset(half, half),
    Offset(-half, half),
  ];

  final hom = homographyFromPoints(plane, corners);
  if (hom == null) return null;

  final pxPerMm = _scaleAtOrigin(hom);
  if (pxPerMm == null || !pxPerMm.isFinite || pxPerMm <= 0) return null;

  final frame = _decompose(hom, intrinsics);
  if (frame == null) return null;
  final normal = frame.r3;

  // Tilt = angle between the optical axis (0,0,1) and the plane normal.
  final cosTilt = normal[2].abs().clamp(0.0, 1.0);
  final tiltDeg = math.acos(cosTilt) * 180 / math.pi;

  final centre = hom.apply(0, 0);
  if (centre == null) return null;

  return SkinPlanePose(
    pxPerMm: pxPerMm,
    tiltDeg: tiltDeg,
    planeToImage: hom,
    markerCorners: List<Offset>.unmodifiable(corners),
    markerCentre: centre,
    planeNormalCamera: normal,
    rotation: [
      frame.r1[0], frame.r2[0], frame.r3[0],
      frame.r1[1], frame.r2[1], frame.r3[1],
      frame.r1[2], frame.r2[2], frame.r3[2],
    ],
    translation: frame.t,
    intrinsics: intrinsics,
    detectedAt: detectedAt,
    source: PoseSource.detected,
    detectionMs: detectionMs,
  );
}

/// Geometric mean of the homography's principal scales at the plane origin:
/// `sqrt(|det J|)` where J is the 2×2 Jacobian of the projective map. For a
/// fronto-parallel plane this is exactly the marker's pixel side over its
/// millimetre side; under tilt it is the mean of the foreshortened and
/// unforeshortened scales.
double? _scaleAtOrigin(Matrix3 hom) {
  final m = hom.m;
  final w = m[8];
  if (w.abs() < 1e-12) return null;
  final u = m[2] / w;
  final v = m[5] / w;
  // d/dX and d/dY of (num/den) at the origin, den = w.
  final dudx = (m[0] - u * m[6]) / w;
  final dudy = (m[1] - u * m[7]) / w;
  final dvdx = (m[3] - v * m[6]) / w;
  final dvdy = (m[4] - v * m[7]) / w;
  final det = (dudx * dvdy - dudy * dvdx).abs();
  return math.sqrt(det);
}

class _PlaneFrame {
  const _PlaneFrame(this.r1, this.r2, this.r3, this.t);
  final List<double> r1;
  final List<double> r2;
  final List<double> r3;
  final List<double> t;
}

/// Strips the intrinsics from the homography and recovers the plane's frame
/// in camera coordinates: `K⁻¹ H = λ [r1 r2 t]`, `r3 = r1 × r2`.
///
/// r1 and r2 are re-orthogonalised before the cross product; with noisy
/// corners they are never exactly perpendicular and the normal would
/// otherwise inherit the skew. `t` comes out in millimetres because the
/// plane points were given in millimetres.
_PlaneFrame? _decompose(Matrix3 hom, CameraIntrinsics k) {
  final f = k.focalPx;
  if (!(f > 0) || !f.isFinite) return null;
  final cx = k.principalX, cy = k.principalY;
  final m = hom.m;

  // K⁻¹ = [[1/f, 0, -cx/f], [0, 1/f, -cy/f], [0, 0, 1]]
  List<double> col(int c) => [
        (m[0 + c] - cx * m[6 + c]) / f,
        (m[3 + c] - cy * m[6 + c]) / f,
        m[6 + c],
      ];
  var r1 = col(0);
  var r2 = col(1);
  final t = col(2);

  final n1 = math.sqrt(Vec3.dot(r1, r1));
  final n2 = math.sqrt(Vec3.dot(r2, r2));
  if (n1 < 1e-12 || n2 < 1e-12) return null;

  // The marker must be in front of the camera: fix the overall sign so
  // t_z > 0 (r3 is unaffected either way, but the convention keeps the
  // plane frame consistent for the overlays).
  final lambda = 2.0 / (n1 + n2);
  final sign = (t[2] * lambda) >= 0 ? 1.0 : -1.0;
  r1 = [for (final v in r1) v * lambda * sign];
  r2 = [for (final v in r2) v * lambda * sign];
  final tScaled = [for (final v in t) v * lambda * sign];

  // Gram–Schmidt.
  r1 = Vec3.normalize(r1);
  final proj = Vec3.dot(r2, r1);
  r2 = Vec3.normalize([
    r2[0] - proj * r1[0],
    r2[1] - proj * r1[1],
    r2[2] - proj * r1[2],
  ]);
  final r3 = Vec3.cross(r1, r2);
  if (!r3.every((v) => v.isFinite)) return null;
  if (!tScaled.every((v) => v.isFinite)) return null;
  return _PlaneFrame(r1, r2, r3, tScaled);
}
