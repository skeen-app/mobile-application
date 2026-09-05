import 'dart:math' as math;
import 'dart:ui';

import 'capture_stability.dart';

/// Maps a point expressed in **ROI-normalized stream coordinates** (0–1 in
/// the sensor's landscape frame, x along sensor rows) into ROI-normalized
/// **display coordinates** (0–1 in the portrait guide box as the user sees
/// it).
///
/// Every spatial overlay — the lesion reticle, the glare shading, the glare
/// arrow — goes through this one function, so the sensor-to-screen rotation
/// is decided exactly once. The camera plugin rotates the preview by the
/// sensor's mounting orientation to show it upright; the ROI is a centred
/// square, so that rotation is a permutation of the normalized axes.
///
/// For the common 90° mounting the landscape frame is turned clockwise to
/// stand upright: stream +x becomes screen-down, stream +y becomes
/// screen-left.
Offset roiToDisplay(Offset n, int sensorOrientationDegrees) {
  switch (sensorOrientationDegrees % 360) {
    case 90:
      return Offset(1 - n.dy, n.dx);
    case 270:
      return Offset(n.dy, 1 - n.dx);
    case 180:
      return Offset(1 - n.dx, 1 - n.dy);
    default:
      return n;
  }
}

/// Maps a device-frame angular velocity into the camera stream's pixel
/// frame (x right, y down, z into the scene) for the given sensor mounting.
///
/// Device frame: x right, y up the phone, z out of the screen. The back
/// camera looks along −z. For the common 90° mounting the sensor's rows run
/// along the phone's long axis, so stream +x is device −y and stream +y is
/// device −x.
///
/// A wrong sign here shows up as prediction drifting the wrong way for at
/// most one measurement period before a real one corrects it — it is on the
/// device checklist, but it cannot corrupt a measured value.
List<double> gyroToStreamFrame(AngularVelocity g, int sensorOrientation) {
  switch (sensorOrientation % 360) {
    case 90:
      return [-g.y, -g.x, -g.z];
    case 270:
      return [g.y, g.x, -g.z];
    case 180:
      return [-g.x, g.y, -g.z];
    default:
      return [g.x, -g.y, -g.z];
  }
}

/// Size of the frame as displayed (portrait for a 90°/270° mounting).
Size displayFrameSizeFor(Size streamSize, int sensorOrientationDegrees) {
  final o = sensorOrientationDegrees % 360;
  return (o == 90 || o == 270)
      ? Size(streamSize.height, streamSize.width)
      : streamSize;
}

/// Full-frame stream pixel → display-frame pixel (the frame as the preview
/// shows it, before `BoxFit.cover`).
Offset streamToDisplayPx(Offset p, Size streamSize, int sensorOrientation) {
  final w = streamSize.width, h = streamSize.height;
  switch (sensorOrientation % 360) {
    case 90:
      return Offset(h - p.dy, p.dx);
    case 270:
      return Offset(p.dy, w - p.dx);
    case 180:
      return Offset(w - p.dx, h - p.dy);
    default:
      return p;
  }
}

/// Display-frame pixel → preview-widget pixel under `BoxFit.cover`, centred
/// — the exact mapping `_FittedPreview` renders with, so registered overlays
/// land on the pixels they describe.
Offset displayFrameToWidget(Offset p, Size displayFrame, Size widget) {
  if (displayFrame.width <= 0 || displayFrame.height <= 0) return p;
  final s = math.max(
    widget.width / displayFrame.width,
    widget.height / displayFrame.height,
  );
  final ox = (widget.width - displayFrame.width * s) / 2;
  final oy = (widget.height - displayFrame.height * s) / 2;
  return Offset(p.dx * s + ox, p.dy * s + oy);
}

/// Stream pixel → widget pixel in one call.
Offset streamToWidget(
  Offset p,
  Size streamSize,
  int sensorOrientation,
  Size widget,
) =>
    displayFrameToWidget(
      streamToDisplayPx(p, streamSize, sensorOrientation),
      displayFrameSizeFor(streamSize, sensorOrientation),
      widget,
    );

/// Inverse of [roiToDisplay].
Offset displayToRoi(Offset d, int sensorOrientationDegrees) {
  switch (sensorOrientationDegrees % 360) {
    case 90:
      return Offset(d.dy, 1 - d.dx);
    case 270:
      return Offset(1 - d.dy, d.dx);
    case 180:
      return Offset(1 - d.dx, 1 - d.dy);
    default:
      return d;
  }
}
