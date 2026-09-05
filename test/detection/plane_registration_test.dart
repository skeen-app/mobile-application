import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:skeen/features/detection/application/pose_estimator.dart';
import 'package:skeen/features/detection/domain/camera_intrinsics.dart';
import 'package:skeen/features/detection/domain/capture_roi.dart';
import 'package:skeen/features/detection/domain/capture_standard.dart';
import 'package:skeen/features/detection/domain/display_mapping.dart';
import 'package:skeen/features/detection/domain/fiducial_marker.dart';
import 'package:skeen/features/detection/domain/skin_plane_pose.dart';

/// WP-2a/2b — the target disc and the nadir cue are pure functions of the
/// pose; these pin the geometry the painter draws.
const _k = CameraIntrinsics(
  focalPx: 800,
  principalX: 320,
  principalY: 180,
  frameWidth: 640,
  frameHeight: 360,
);

/// Marker corners for a plane tilted by [tiltDeg] about the camera X axis at
/// [distanceMm], exactly as the WP-1 renderer projects them.
List<Offset> _corners({
  double tiltDeg = 0,
  double distanceMm = 150,
  double offsetYmm = 0,
}) {
  final th = tiltDeg * math.pi / 180;
  final c = math.cos(th), s = math.sin(th);
  Offset project(double x, double y) {
    final zc = y * s + distanceMm;
    return Offset(
      _k.focalPx * x / zc + _k.principalX,
      _k.focalPx * (y * c + offsetYmm) / zc + _k.principalY,
    );
  }

  const h = 15.0;
  return [project(-h, -h), project(h, -h), project(h, h), project(-h, h)];
}

SkinPlanePose _pose({
  double tiltDeg = 0,
  double distanceMm = 150,
  double offsetYmm = 0,
}) =>
    estimatePose(
      corners: _corners(
        tiltDeg: tiltDeg,
        distanceMm: distanceMm,
        offsetYmm: offsetYmm,
      ),
      intrinsics: _k,
      detectedAt: DateTime(2026, 9, 4),
      detectionMs: 0,
    )!;

void main() {
  group('capture standard — derived, not chosen', () {
    test('the ROI on the skin follows from lesion size and fill target', () {
      expect(kRoiSideMm, kLesionReferenceMm / kLesionFillTarget);
      expect(kRoiSideMm, 12.0);
      expect(TargetDisc.diameterMm, kRoiSideMm);
    });

    test('target px/mm scales with the crop resolution', () {
      // The same physical standard is a different pixel density per stream.
      expect(targetPxPerMm(360), 30.0);
      expect(targetPxPerMm(540), 45.0);
    });

    test('the disc clears the marker: the crop never contains the card', () {
      // Restriction: the model's crop must exclude the marker. The disc IS
      // the crop on the skin, so a positive clearance to the quiet zone
      // is the invariant — verified here, not by eye.
      expect(TargetDisc.clearanceMm(), closeTo(TargetDisc.gapMm, 1e-9));
      expect(TargetDisc.clearanceMm(), greaterThan(0));

      final c = TargetDisc.centreMm();
      final m = FiducialMarker.study;
      final discBottom = c.dy + TargetDisc.diameterMm / 2;
      final quietTop = -(m.sideMm / 2 + m.cellMm * m.quietZoneCells);
      expect(discBottom, lessThan(quietTop));
    });
  });

  group('pose: rigid frame and 3-D projection', () {
    test('a plane point projects the same through H and through (R, t)', () {
      for (final tilt in [0.0, 12.0, 25.0]) {
        final pose = _pose(tiltDeg: tilt);
        for (final p in [const Offset(0, 0), const Offset(10, -20), const Offset(-7, 4)]) {
          final viaH = pose.project(p.dx, p.dy)!;
          final via3 = pose.project3(p.dx, p.dy, 0)!;
          expect((viaH - via3).distance, lessThan(0.5), reason: 'tilt $tilt, $p');
        }
      }
    });

    test('translation recovers the working distance', () {
      expect(_pose(distanceMm: 150).distanceMm, closeTo(150, 3));
      expect(_pose(distanceMm: 100).distanceMm, closeTo(100, 2));
    });

    test('head-on: the nadir point closes onto the disc centre', () {
      // Camera looking straight down at the DISC (marker centre shifted so
      // the disc, not the marker, is on the optical axis).
      final c = TargetDisc.centreMm();
      final pose = _pose(offsetYmm: -c.dy);
      final centre = pose.project3(c.dx, c.dy, 0)!;
      final top = pose.project3(c.dx, c.dy, -TargetDisc.nadirHeightMm)!;

      expect(pose.localTiltDeg(c.dx, c.dy), lessThan(1.0));
      expect((top - centre).distance, lessThan(4));
    });

    test('level but off-axis: the cue is open by the parallax angle', () {
      // Optical axis perpendicular to the plane, marker on-axis, disc 29 mm
      // above it. The disc is seen ~11° off-axis — that IS local tilt, and
      // it is what foreshortens a lesion sitting there.
      final pose = _pose();
      final c = TargetDisc.centreMm();
      final local = pose.localTiltDeg(c.dx, c.dy);
      final expectedDeg = math.atan(-c.dy / 150) * 180 / math.pi;
      expect(local, closeTo(expectedDeg, 1.0));
      expect(pose.tiltDeg, lessThan(1.0), reason: 'global tilt is still 0');

      final centre = pose.project3(c.dx, c.dy, 0)!;
      final top = pose.project3(c.dx, c.dy, -TargetDisc.nadirHeightMm)!;
      final dDisc = math.sqrt(150 * 150 + c.dy * c.dy);
      final expectedPx = _k.focalPx *
          TargetDisc.nadirHeightMm *
          math.sin(local * math.pi / 180) /
          dDisc;
      expect((top - centre).distance, closeTo(expectedPx, expectedPx * 0.25));
    });

    test('the cue tracks local tilt across known inclinations', () {
      final c = TargetDisc.centreMm();
      for (final tilt in [12.0, 25.0]) {
        final pose = _pose(tiltDeg: tilt, offsetYmm: -c.dy);
        final local = pose.localTiltDeg(c.dx, c.dy);
        expect(local, closeTo(tilt, 3.0), reason: 'tilt $tilt');

        final centre = pose.project3(c.dx, c.dy, 0)!;
        final top = pose.project3(c.dx, c.dy, -TargetDisc.nadirHeightMm)!;
        final expected = _k.focalPx *
            TargetDisc.nadirHeightMm *
            math.sin(local * math.pi / 180) /
            150;
        expect((top - centre).distance, closeTo(expected, expected * 0.25),
            reason: 'tilt $tilt');
        expect((top - centre).distance, greaterThan(10),
            reason: 'visible at $tilt°');
      }
    });

    test('the nadir point floats toward the camera, not into the skin', () {
      // At tilt the point above the plane must project on the side the
      // camera leans toward; a sign error would put it below.
      final pose = _pose(tiltDeg: 20);
      final c = TargetDisc.centreMm();
      final centre = pose.project3(c.dx, c.dy, 0)!;
      final top = pose.project3(c.dx, c.dy, -TargetDisc.nadirHeightMm)!;
      final below = pose.project3(c.dx, c.dy, TargetDisc.nadirHeightMm)!;

      expect((top - centre).dy.sign, isNot((below - centre).dy.sign));
      expect(pose.distanceMm, greaterThan(0));
    });
  });

  group('target disc geometry', () {
    test('at target scale the disc is the guide box', () {
      // A crop of 360 px covering 12 mm ⇒ 30 px/mm. At that scale the
      // disc's projection is 360 px wide: exactly the box.
      final distance = _k.focalPx / targetPxPerMm(360);
      final pose = _pose(distanceMm: distance);
      final c = TargetDisc.centreMm();
      const r = TargetDisc.diameterMm / 2;
      final left = pose.project(c.dx - r, c.dy)!;
      final right = pose.project(c.dx + r, c.dy)!;

      expect((right - left).distance, closeTo(360, 360 * 0.03));
      expect(pose.pxPerMm / targetPxPerMm(360), closeTo(1.0, 0.03));
    });

    test('the disc shrinks with distance and flattens with tilt', () {
      final near = _pose(distanceMm: 100);
      final far = _pose(distanceMm: 200);
      final c = TargetDisc.centreMm();
      const r = TargetDisc.diameterMm / 2;
      double width(SkinPlanePose p) =>
          (p.project(c.dx + r, c.dy)! - p.project(c.dx - r, c.dy)!).distance;
      double height(SkinPlanePose p) =>
          (p.project(c.dx, c.dy + r)! - p.project(c.dx, c.dy - r)!).distance;

      expect(width(near) / width(far), closeTo(2.0, 0.1));

      final c2 = TargetDisc.centreMm();
      final tilted = _pose(tiltDeg: 30, offsetYmm: -c2.dy);
      expect(height(tilted) / width(tilted), lessThan(0.92),
          reason: 'foreshortened into an ellipse (cos 30° ≈ 0.87)');
      final headOn = _pose(offsetYmm: -c2.dy);
      expect(height(headOn) / width(headOn), closeTo(1.0, 0.03));
    });
  });

  group('stream → widget mapping', () {
    test('90° mounting: the landscape frame stands upright', () {
      const stream = Size(640, 360);
      expect(displayFrameSizeFor(stream, 90), const Size(360, 640));
      // Stream top-left → display top-right; stream +x → display down.
      expect(streamToDisplayPx(const Offset(0, 0), stream, 90),
          const Offset(360, 0));
      expect(streamToDisplayPx(const Offset(640, 0), stream, 90),
          const Offset(360, 640));
      expect(streamToDisplayPx(const Offset(320, 180), stream, 90),
          const Offset(180, 320));
    });

    test('cover fit centres the frame in the widget', () {
      // 360×640 display frame in a 350×500 widget: width-driven cover.
      const frame = Size(360, 640);
      const widget = Size(350, 500);
      final s = 350 / 360;
      final centre = displayFrameToWidget(const Offset(180, 320), frame, widget);
      expect(centre.dx, closeTo(175, 1e-9));
      expect(centre.dy, closeTo(250, 1e-9));
      final corner = displayFrameToWidget(Offset.zero, frame, widget);
      expect(corner.dy, closeTo((500 - 640 * s) / 2, 1e-9));
    });

    test('the composite agrees with the ROI mapping used by the reticle', () {
      // A point at the ROI's normalized (0.25, 0.25) must land on the same
      // widget pixel whether it goes through the ROI path (reticle, glare)
      // or the full-frame path (disc, nadir). One geometry, two routes.
      const stream = Size(640, 360);
      const widget = Size(350, 500);
      final display = displayFrameSizeFor(stream, 90);
      final boxSide = resolveGuideBoxSide(widget.shortestSide);
      final roiSpec = CaptureRoi.fromPreviewGeometry(
        widgetSize: widget,
        frameSize: display,
        guideBoxSide: boxSide,
      );
      final roi = roiSpec.boundsIn(640, 360);

      // Full-frame route.
      final streamPx = Offset(
        roi.left + 0.25 * roi.width,
        roi.top + 0.25 * roi.height,
      );
      final viaFrame = streamToWidget(streamPx, stream, 90, widget);

      // ROI route, as the reticle painter does it: normalized → display →
      // inside the centred guide box.
      final d = roiToDisplay(const Offset(0.25, 0.25), 90);
      final viaRoi = Offset(
        (widget.width - boxSide) / 2 + d.dx * boxSide,
        (widget.height - boxSide) / 2 + d.dy * boxSide,
      );

      expect((viaFrame - viaRoi).distance, lessThan(1.0),
          reason: 'box, measured ROI and crop are one square');
    });
  });
}
