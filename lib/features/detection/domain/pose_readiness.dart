import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'capture_roi.dart';
import 'capture_standard.dart';
import 'skin_plane_pose.dart';

/// What the marker pose says the user should do next. Each value has a
/// spatial representation on screen (the disc's colour and size, the nadir
/// cue, the reticle), so only [showMarker] ever needs words.
enum PoseAdvice {
  /// No marker in view, or the pose went stale.
  showMarker,

  /// Measured px/mm is under the target: the disc is smaller than the box.
  moveCloser,

  /// Measured px/mm is over the target: the disc overflows the box.
  moveAway,

  /// Local tilt at the disc exceeds the limit: the nadir cue is open.
  levelPhone,

  /// Pose is fine but no lesion is segmented inside the box yet.
  findLesion,

  /// Lesion segmented but off the disc centre.
  centreLesion,

  ok,
}

/// The physical gate: the three axes only the marker can measure — scale,
/// angle and centring — folded into one verdict.
///
/// **Fail-closed on every axis.** No pose, a stale pose, or a missing lesion
/// centroid all read as "not ready"; nothing here defaults to pass.
///
/// Thresholds live in `capture_standard.dart`, next to their derivations.
@immutable
class PoseReadiness {
  const PoseReadiness({
    required this.hasPose,
    this.scaleRatio,
    this.localTiltDeg,
    this.centreOffset,
  });

  /// No usable pose: absent marker, stale detection, or no intrinsics.
  static const PoseReadiness absent = PoseReadiness(hasPose: false);

  final bool hasPose;

  /// Measured px/mm over the target px/mm for this stream's crop. 1.0 is on
  /// target; null without a pose.
  final double? scaleRatio;

  /// Tilt at the target disc — the angle between the plane normal and the
  /// viewing ray to the disc centre, which is what foreshortens a lesion
  /// sitting there. Null without a pose.
  final double? localTiltDeg;

  /// Distance from the lesion centroid to the disc centre, as a fraction of
  /// the disc radius. Null without a pose **or without a segmented lesion**.
  final double? centreOffset;

  bool get scaleOk =>
      scaleRatio != null && (scaleRatio! - 1).abs() <= kScaleTolerance;

  bool get tiltOk => localTiltDeg != null && localTiltDeg! <= kMaxTiltDeg;

  bool get centredOk => centreOffset != null && centreOffset! <= kCentreTolerance;

  bool get isReady => hasPose && scaleOk && tiltOk && centredOk;

  PoseAdvice get advice {
    if (!hasPose) return PoseAdvice.showMarker;
    if (!scaleOk) {
      return scaleRatio! < 1 ? PoseAdvice.moveCloser : PoseAdvice.moveAway;
    }
    if (!tiltOk) return PoseAdvice.levelPhone;
    if (centreOffset == null) return PoseAdvice.findLesion;
    if (!centredOk) return PoseAdvice.centreLesion;
    return PoseAdvice.ok;
  }

  /// Evaluates the gate for one instant.
  ///
  /// [roi] is the analysed region in **stream pixels** — its side is the
  /// crop side that fixes the target px/mm. [lesionCentroidRoi] is the
  /// segmenter's centroid, ROI-normalized in the stream frame.
  factory PoseReadiness.evaluate({
    required SkinPlanePose? pose,
    required RoiBounds roi,
    required DateTime now,
    Offset? lesionCentroidRoi,
  }) {
    if (pose == null || pose.isStaleAt(now)) return absent;
    if (roi.width <= 0 || roi.height <= 0) return absent;

    final target = targetPxPerMm(roi.width.toDouble());
    if (target <= 0) return absent;

    // Both scale and tilt are evaluated AT THE DISC — where the lesion is —
    // not at the marker centre. Under tilt the marker sits at a different
    // depth than the disc, and it is the disc's px/mm the crop will have.
    final disc = TargetDisc.centreMm();
    final scaleAtDisc = pose.pxPerMmAt(disc.dx, disc.dy);
    if (scaleAtDisc <= 0) return absent;
    final ratio = scaleAtDisc / target;
    final tilt = pose.localTiltDeg(disc.dx, disc.dy);

    double? centre;
    if (lesionCentroidRoi != null) {
      final discPx = pose.project(disc.dx, disc.dy);
      final radiusPx = scaleAtDisc * TargetDisc.diameterMm / 2;
      if (discPx != null && radiusPx > 0) {
        final lesionPx = Offset(
          roi.left + lesionCentroidRoi.dx * roi.width,
          roi.top + lesionCentroidRoi.dy * roi.height,
        );
        centre = (lesionPx - discPx).distance / radiusPx;
      }
    }

    return PoseReadiness(
      hasPose: true,
      scaleRatio: ratio,
      localTiltDeg: tilt,
      centreOffset: centre,
    );
  }

  @override
  String toString() => hasPose
      ? 'PoseReadiness(scale ×${scaleRatio!.toStringAsFixed(2)}, '
          'tilt ${localTiltDeg!.toStringAsFixed(1)}°, '
          'centre ${centreOffset?.toStringAsFixed(2) ?? "—"}, $advice)'
      : 'PoseReadiness(absent)';
}
