/// The physical capture standard: what a "standardised" frame means in
/// millimetres and degrees, in one place, each value derived and justified.
///
/// These are the quantities the marker makes measurable. Anything here is a
/// **gate threshold or a registered-overlay dimension**, so a change is a
/// change to the study's independent variable — recalibrate from the pilot,
/// but never quietly.
library;

import 'dart:ui';

import 'fiducial_marker.dart';

/// Reference lesion diameter. The ABCD rule's D criterion turns at 6 mm; a
/// lesion of that size is the case the standard has to render well, and
/// smaller ones only get more margin.
const double kLesionReferenceMm = 6.0;

/// Where in the accepted fill band ([CaptureScale] 0.25–0.80) the reference
/// lesion should land: the centre of it, so scale tolerance is symmetric.
const double kLesionFillTarget = 0.5;

/// Side of the analysed region on the skin, in mm. **Derived**, not chosen:
/// the reference lesion at the target fill fraction sets it —
/// 6 mm / 0.5 = 12 mm. This is the diameter of the target disc drawn on the
/// skin plane, and with the crop's pixel side it fixes the target px/mm.
const double kRoiSideMm = kLesionReferenceMm / kLesionFillTarget;

/// Target scale for a crop whose side is [roiSidePx] pixels: the pixels
/// that will cover [kRoiSideMm] of skin. Depends on the device's stream
/// resolution, which is why it is a function and not a constant — the same
/// physical standard on a 720p stream and a 1080p stream is a different
/// number of pixels per millimetre.
double targetPxPerMm(double roiSidePx) => roiSidePx / kRoiSideMm;

/// Accepted deviation of measured px/mm from [targetPxPerMm]. ±15% tolerates
/// hand tremor along the optical axis (a few mm at 15 cm) without letting
/// lesion size drift between captures by more than the D criterion can bear.
const double kScaleTolerance = 0.15;

/// Maximum tilt of the optical axis from the skin normal. Above 12° the
/// foreshortening (1 − cos θ ≈ 2.2%) plus the perspective gradient across a
/// 5–6 mm lesion visibly deforms its border, which is where asymmetry and
/// irregularity are judged.
const double kMaxTiltDeg = 12.0;

/// How far the lesion centroid may sit from the target disc centre, as a
/// fraction of the disc radius. 0.2 leaves at least 40% of the radius of
/// perilesional skin on the near side — the border is never at the crop
/// edge.
const double kCentreTolerance = 0.2;

/// The target disc in the skin plane's coordinate frame (mm, origin at the
/// marker centre, X to the marker's right, Y down).
///
/// The disc is anchored **to the marker**, not to the screen: it is a fixed
/// spot on the skin the user aims at. The protocol places the card directly
/// below the lesion with its top edge toward it, so the disc sits above the
/// marker's top edge with a small gap. Everything drawn inside it is
/// therefore registered to the same physical plane as the marker.
class TargetDisc {
  const TargetDisc._();

  /// Diameter on the skin: the analysed region itself.
  static const double diameterMm = kRoiSideMm;

  /// Clearance between the marker's quiet zone and the disc edge, so the
  /// crop never contains the card. Verified by test, not by eye.
  static const double gapMm = 3.0;

  /// Disc centre, plane frame.
  static Offset centreMm({FiducialMarker marker = FiducialMarker.study}) {
    final quiet = marker.cellMm * marker.quietZoneCells;
    final y = -(marker.sideMm / 2 + quiet + gapMm + diameterMm / 2);
    return Offset(0, y);
  }

  /// Nearest distance from the disc edge to the marker's quiet-zone edge.
  static double clearanceMm({FiducialMarker marker = FiducialMarker.study}) {
    final quiet = marker.cellMm * marker.quietZoneCells;
    final discBottom = centreMm(marker: marker).dy + diameterMm / 2;
    final quietTop = -(marker.sideMm / 2 + quiet);
    return quietTop - discBottom;
  }

  /// Height of the nadir cue above the plane. Tall enough that a 12° tilt
  /// at 15 cm displaces its projection by ~16 px on a 720p stream — clearly
  /// off-centre — and it collapses onto the disc centre when level.
  static const double nadirHeightMm = 15.0;
}
