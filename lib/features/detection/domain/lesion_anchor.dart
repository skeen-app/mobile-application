import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Where the lesion is, right now, for the reticle to sit on.
///
/// Position and size come from the tone-invariant segmenter (the same one
/// that gates capture and anchors the result popup); between its ~3 Hz
/// measurements the position is carried forward by the gyroscope so the
/// ring tracks the lesion as the phone moves instead of stepping.
///
/// Coordinates are ROI-normalized in the **stream** frame; the overlay maps
/// them to the screen through `roiToDisplay`.
@immutable
class LesionAnchor {
  const LesionAnchor({
    required this.centre,
    required this.diameterFraction,
    required this.measuredAt,
    required this.predicted,
  });

  /// Lesion centroid, 0–1 within the ROI.
  final Offset centre;

  /// Lesion diameter as a fraction of the ROI side.
  final double diameterFraction;

  /// Time of the last real measurement this anchor derives from.
  final DateTime measuredAt;

  /// True when the position has been carried forward by the gyroscope since
  /// the last measurement.
  final bool predicted;

  /// A measurement older than this is dropped: the reticle disappears rather
  /// than sitting on a lesion that may have left the frame. Three metric
  /// periods at ~3 Hz.
  static const int staleAfterMs = 1000;

  bool isStaleAt(DateTime now) =>
      now.difference(measuredAt).inMilliseconds > staleAfterMs;

  LesionAnchor copyWith({Offset? centre, bool? predicted}) => LesionAnchor(
        centre: centre ?? this.centre,
        diameterFraction: diameterFraction,
        measuredAt: measuredAt,
        predicted: predicted ?? this.predicted,
      );
}
