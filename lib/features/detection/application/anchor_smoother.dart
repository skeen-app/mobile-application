import 'dart:ui';

import '../domain/camera_intrinsics.dart';
import '../domain/capture_roi.dart';
import '../domain/lesion_anchor.dart';
import '../domain/skin_plane_pose.dart';

/// Turns the segmenter's ~3 Hz lesion centroid into a reticle position that
/// moves with the phone.
///
/// Two inputs, two roles:
///  • **Measurements** (from the ROI metrics) are the truth. They are blended
///    with an exponential moving average so a single noisy frame does not
///    yank the ring, and they reset the prediction.
///  • **Gyroscope steps** carry the position forward between measurements.
///    A camera rotation moves every image point by the conjugate homography
///    `K Rᵀ K⁻¹` — the same relation the pose tracker uses — so the ring
///    stays on the lesion while the phone moves, instead of lagging behind
///    and then jumping at the next measurement.
///
/// Everything is ROI-normalized in the stream frame; the overlay maps it to
/// the screen. No measurement for [LesionAnchor.staleAfterMs] ⇒ no anchor:
/// the ring disappears rather than sitting on skin the lesion has left.
class AnchorSmoother {
  AnchorSmoother({this.alpha = 0.5, DateTime Function()? clock})
      : assert(alpha > 0 && alpha <= 1),
        _now = clock ?? DateTime.now;

  /// EMA weight on a new measurement. 0.5 halves a jump each frame: a
  /// segmenter that jitters by a few percent of the box settles in two
  /// frames, and a real move of the lesion is followed within ~3.
  final double alpha;

  final DateTime Function() _now;
  LesionAnchor? _anchor;

  LesionAnchor? get current {
    final a = _anchor;
    if (a == null) return null;
    return a.isStaleAt(_now()) ? null : a;
  }

  void measure({
    required Offset centre,
    required double diameterFraction,
    required DateTime at,
  }) {
    final previous = current;
    if (previous == null) {
      _anchor = LesionAnchor(
        centre: centre,
        diameterFraction: diameterFraction,
        measuredAt: at,
        predicted: false,
      );
      return;
    }
    _anchor = LesionAnchor(
      centre: Offset(
        previous.centre.dx + alpha * (centre.dx - previous.centre.dx),
        previous.centre.dy + alpha * (centre.dy - previous.centre.dy),
      ),
      diameterFraction: previous.diameterFraction +
          alpha * (diameterFraction - previous.diameterFraction),
      measuredAt: at,
      predicted: false,
    );
  }

  /// Applies a small camera rotation. [rotationTransposed] is `Rᵀ` for the
  /// rotation the camera underwent (row-major 3×3), [intrinsics] describe
  /// the stream at its current zoom, and [roi] is the ROI in stream pixels.
  void predict({
    required List<double> rotationTransposed,
    required CameraIntrinsics intrinsics,
    required RoiBounds roi,
  }) {
    final a = current;
    if (a == null || roi.width <= 0 || roi.height <= 0) return;

    final k = Matrix3([
      intrinsics.focalPx, 0, intrinsics.principalX,
      0, intrinsics.focalPx, intrinsics.principalY,
      0, 0, 1,
    ]);
    final kInv = k.inverse();
    if (kInv == null) return;
    final conj = k.multiply(Matrix3(rotationTransposed)).multiply(kInv);

    final px = roi.left + a.centre.dx * roi.width;
    final py = roi.top + a.centre.dy * roi.height;
    final moved = conj.apply(px, py);
    if (moved == null) return;

    _anchor = a.copyWith(
      centre: Offset(
        ((moved.dx - roi.left) / roi.width).clamp(0.0, 1.0),
        ((moved.dy - roi.top) / roi.height).clamp(0.0, 1.0),
      ),
      predicted: true,
    );
  }

  void reset() => _anchor = null;
}
