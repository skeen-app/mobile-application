import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'camera_intrinsics.dart';

/// 3×3 matrix, row-major. Used for the plane→image homography.
@immutable
class Matrix3 {
  const Matrix3(this.m);

  /// Nine values, row-major.
  final List<double> m;

  static const Matrix3 identity = Matrix3([1, 0, 0, 0, 1, 0, 0, 0, 1]);

  double at(int row, int col) => m[row * 3 + col];

  /// Applies the projective transform to a 2-D point.
  /// Returns null when the point maps to infinity (w ≈ 0).
  Offset? apply(double x, double y) {
    final w = m[6] * x + m[7] * y + m[8];
    if (w.abs() < 1e-12) return null;
    return Offset(
      (m[0] * x + m[1] * y + m[2]) / w,
      (m[3] * x + m[4] * y + m[5]) / w,
    );
  }

  Matrix3 multiply(Matrix3 o) {
    final out = List<double>.filled(9, 0);
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        out[r * 3 + c] = at(r, 0) * o.at(0, c) +
            at(r, 1) * o.at(1, c) +
            at(r, 2) * o.at(2, c);
      }
    }
    return Matrix3(out);
  }

  Matrix3? inverse() {
    final a = m;
    final det = a[0] * (a[4] * a[8] - a[5] * a[7]) -
        a[1] * (a[3] * a[8] - a[5] * a[6]) +
        a[2] * (a[3] * a[7] - a[4] * a[6]);
    if (det.abs() < 1e-12) return null;
    final inv = 1.0 / det;
    return Matrix3([
      (a[4] * a[8] - a[5] * a[7]) * inv,
      (a[2] * a[7] - a[1] * a[8]) * inv,
      (a[1] * a[5] - a[2] * a[4]) * inv,
      (a[5] * a[6] - a[3] * a[8]) * inv,
      (a[0] * a[8] - a[2] * a[6]) * inv,
      (a[2] * a[3] - a[0] * a[5]) * inv,
      (a[3] * a[7] - a[4] * a[6]) * inv,
      (a[1] * a[6] - a[0] * a[7]) * inv,
      (a[0] * a[4] - a[1] * a[3]) * inv,
    ]);
  }

  @override
  String toString() => 'Matrix3(${m.map((v) => v.toStringAsFixed(4)).join(', ')})';
}

/// Which physical reference the pose was resolved from.
enum MarkerType {
  /// The printed 4×4 code card.
  aruco,

  /// A coin of known diameter. **Not implemented**: kept in the vocabulary
  /// so telemetry can name it if it ever is, never reported today.
  coin,
}

extension MarkerTypeX on MarkerType {
  String get slug => this == MarkerType.aruco ? 'aruco' : 'coin';
}

/// How the current pose was obtained.
enum PoseSource {
  /// From a marker detection on this frame.
  detected,

  /// Carried forward from the last detection and rotated by the integrated
  /// gyroscope. Metric quantities (px/mm) are unchanged by a pure rotation
  /// to first order; tilt is updated.
  predicted,
}

/// The camera's pose relative to the skin plane, resolved from the fiducial
/// marker — the only metric reference in the scene.
///
/// Every field here is **measured or resolved from geometry**, never
/// estimated from image statistics. Where a quantity could not be resolved
/// (no marker in view, no camera intrinsics), there is no pose at all rather
/// than a pose with plausible defaults; `null` is the honest value and the
/// gate treats it as closed.
@immutable
class SkinPlanePose {
  const SkinPlanePose({
    required this.pxPerMm,
    required this.tiltDeg,
    required this.planeToImage,
    required this.markerCorners,
    required this.markerCentre,
    required this.planeNormalCamera,
    required this.rotation,
    required this.translation,
    required this.intrinsics,
    required this.detectedAt,
    required this.source,
    required this.detectionMs,
    this.markerType = MarkerType.aruco,
  });

  /// Image pixels per millimetre **on the skin plane at the marker centre**,
  /// in full-frame stream coordinates. Geometric mean of the two principal
  /// scales of the homography's Jacobian, so it is defined even under tilt
  /// (at the gate's ≤12° the anisotropy is under 2%).
  final double pxPerMm;

  /// Angle between the camera's optical axis and the skin-plane normal, in
  /// degrees. 0 = perpendicular.
  final double tiltDeg;

  /// Maps plane coordinates (millimetres, origin at the marker centre, X to
  /// the marker's right, Y down) to full-frame pixel coordinates. This is
  /// what every registered overlay is projected through.
  final Matrix3 planeToImage;

  /// Marker corners in full-frame pixels, ordered from the marker's canonical
  /// top-left, clockwise.
  final List<Offset> markerCorners;

  /// Marker centre in full-frame pixels.
  final Offset markerCentre;

  /// Unit normal of the skin plane in camera coordinates (x right, y down, z
  /// forward). Kept so a predicted pose can rotate it by the gyroscope.
  final List<double> planeNormalCamera;

  /// Rotation plane→camera, row-major 3×3 (columns are the plane's X, Y and
  /// normal axes in camera coordinates).
  final List<double> rotation;

  /// Plane origin (marker centre) in camera coordinates, millimetres.
  final List<double> translation;

  /// Intrinsics the pose was resolved with (at the zoom in force).
  final CameraIntrinsics intrinsics;

  /// Projects a point given in plane coordinates **with height** — `z` is
  /// millimetres along the plane normal, negative toward the camera — to
  /// full-frame pixels. This is what the homography cannot do, and what the
  /// nadir cue needs: a point floating above the skin.
  Offset? project3(double xMm, double yMm, double zMm) {
    final r = rotation;
    final xc = r[0] * xMm + r[1] * yMm + r[2] * zMm + translation[0];
    final yc = r[3] * xMm + r[4] * yMm + r[5] * zMm + translation[1];
    final zc = r[6] * xMm + r[7] * yMm + r[8] * zMm + translation[2];
    if (zc <= 1e-6) return null;
    return Offset(
      intrinsics.focalPx * xc / zc + intrinsics.principalX,
      intrinsics.focalPx * yc / zc + intrinsics.principalY,
    );
  }

  /// Pixels per millimetre **at a given plane point**: √|det J| of the
  /// plane→image map there. [pxPerMm] is this quantity at the marker centre;
  /// the gate uses it at the target disc, where the lesion is. Under tilt
  /// the two differ by the depth difference between marker and disc.
  double pxPerMmAt(double xMm, double yMm) {
    final m = planeToImage.m;
    final w = m[6] * xMm + m[7] * yMm + m[8];
    if (w.abs() < 1e-12) return 0;
    final u = (m[0] * xMm + m[1] * yMm + m[2]) / w;
    final v = (m[3] * xMm + m[4] * yMm + m[5]) / w;
    final dudx = (m[0] - u * m[6]) / w;
    final dudy = (m[1] - u * m[7]) / w;
    final dvdx = (m[3] - v * m[6]) / w;
    final dvdy = (m[4] - v * m[7]) / w;
    final det = (dudx * dvdy - dudy * dvdx).abs();
    return det.isFinite ? math.sqrt(det) : 0;
  }

  /// Tilt **as seen at a given plane point**: the angle between the plane
  /// normal and the viewing ray to that point, in degrees.
  ///
  /// [tiltDeg] is the global figure (normal vs. optical axis). For a point
  /// off the optical axis the two differ by the point's parallax — the
  /// target disc sits ~29 mm from the marker, i.e. ~11° off-axis at 15 cm —
  /// and it is the *local* angle that foreshortens the lesion's border. The
  /// nadir cue is drawn from this, so it closes exactly when the disc is
  /// being viewed head-on, which is also when the crop is undistorted.
  double localTiltDeg(double xMm, double yMm) {
    final r = rotation;
    final ray = Vec3.normalize([
      r[0] * xMm + r[1] * yMm + translation[0],
      r[3] * xMm + r[4] * yMm + translation[1],
      r[6] * xMm + r[7] * yMm + translation[2],
    ]);
    final cos = Vec3.dot(ray, planeNormalCamera).abs().clamp(0.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  /// Distance from the camera to the marker centre, millimetres.
  double get distanceMm => math.sqrt(
        translation[0] * translation[0] +
            translation[1] * translation[1] +
            translation[2] * translation[2],
      );

  /// Wall-clock time of the last **real** detection this pose derives from.
  final DateTime detectedAt;

  final PoseSource source;

  /// How long the detector took on the frame that produced this pose, in
  /// milliseconds. Diagnostic; persisted so the Dart-vs-native decision can
  /// be made from field numbers.
  final int detectionMs;

  final MarkerType markerType;

  /// Milliseconds since the last real detection.
  int ageAt(DateTime now) => now.difference(detectedAt).inMilliseconds;

  /// A pose older than this is no longer trusted: fail-closed.
  ///
  /// ~4 detection periods at the 100 ms cadence. Long enough that a single
  /// dropped detection (motion blur, partial occlusion by a finger) does not
  /// flicker the gate; short enough that a marker that has actually left the
  /// frame closes it within half a second.
  static const int staleAfterMs = 400;

  bool isStaleAt(DateTime now) => ageAt(now) > staleAfterMs;

  /// Projects a plane point (mm) to full-frame pixels.
  Offset? project(double xMm, double yMm) => planeToImage.apply(xMm, yMm);

  SkinPlanePose copyWith({
    double? tiltDeg,
    Matrix3? planeToImage,
    List<double>? planeNormalCamera,
    List<double>? rotation,
    List<double>? translation,
    PoseSource? source,
  }) =>
      SkinPlanePose(
        pxPerMm: pxPerMm,
        tiltDeg: tiltDeg ?? this.tiltDeg,
        planeToImage: planeToImage ?? this.planeToImage,
        markerCorners: markerCorners,
        markerCentre: markerCentre,
        planeNormalCamera: planeNormalCamera ?? this.planeNormalCamera,
        rotation: rotation ?? this.rotation,
        translation: translation ?? this.translation,
        intrinsics: intrinsics,
        detectedAt: detectedAt,
        source: source ?? this.source,
        detectionMs: detectionMs,
        markerType: markerType,
      );

  @override
  String toString() => 'SkinPlanePose('
      '${pxPerMm.toStringAsFixed(2)} px/mm, '
      'tilt ${tiltDeg.toStringAsFixed(1)}°, '
      '${source.name})';
}

/// Small vector helpers shared by the estimator and the tracker.
class Vec3 {
  Vec3._();

  static List<double> normalize(List<double> v) {
    final n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (n < 1e-12) return [0, 0, 1];
    return [v[0] / n, v[1] / n, v[2] / n];
  }

  static List<double> cross(List<double> a, List<double> b) => [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
      ];

  static double dot(List<double> a, List<double> b) =>
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

  /// Rotates [v] by the rotation matrix [r] (row-major 3×3).
  static List<double> rotate(List<double> r, List<double> v) => [
        r[0] * v[0] + r[1] * v[1] + r[2] * v[2],
        r[3] * v[0] + r[4] * v[1] + r[5] * v[2],
        r[6] * v[0] + r[7] * v[1] + r[8] * v[2],
      ];

  /// Rodrigues: rotation matrix (row-major) for the rotation vector [w]
  /// (axis × angle, radians).
  static List<double> rodrigues(List<double> w) {
    final theta = math.sqrt(w[0] * w[0] + w[1] * w[1] + w[2] * w[2]);
    if (theta < 1e-9) return [1, 0, 0, 0, 1, 0, 0, 0, 1];
    final kx = w[0] / theta, ky = w[1] / theta, kz = w[2] / theta;
    final c = math.cos(theta), s = math.sin(theta), v = 1 - c;
    return [
      c + kx * kx * v,
      kx * ky * v - kz * s,
      kx * kz * v + ky * s,
      ky * kx * v + kz * s,
      c + ky * ky * v,
      ky * kz * v - kx * s,
      kz * kx * v - ky * s,
      kz * ky * v + kx * s,
      c + kz * kz * v,
    ];
  }

  static List<double> transpose(List<double> r) =>
      [r[0], r[3], r[6], r[1], r[4], r[7], r[2], r[5], r[8]];

  /// Row-major 3×3 product a·b.
  static List<double> matMul(List<double> a, List<double> b) {
    final out = List<double>.filled(9, 0);
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        out[r * 3 + c] = a[r * 3] * b[c] +
            a[r * 3 + 1] * b[3 + c] +
            a[r * 3 + 2] * b[6 + c];
      }
    }
    return out;
  }
}
