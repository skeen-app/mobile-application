import 'dart:math' as math;

import '../domain/color_calibration.dart';
import '../domain/fiducial_marker.dart';
import '../domain/luma_frame.dart';
import '../domain/skin_plane_pose.dart';

/// Reads the marker's grey and white patches off the frame that produced
/// the pose.
///
/// Each patch is sampled on a 5×5 grid over its inner 60%, projected through
/// the pose so the samples land on the printed patch however the card is
/// turned or tilted. Validity is checked, not assumed: a patch under a
/// finger, across a shadow edge, or blown out by a highlight is reported
/// invalid with the reason, and no calibration is produced from it.
PatchReading samplePatches({
  required LumaFrame frame,
  required SkinPlanePose pose,
  FiducialMarker marker = FiducialMarker.study,
}) {
  final rgb = frame.rgb;
  if (rgb == null) return const PatchReading.invalid('no colour plane');

  final grey = _samplePatch(frame, rgb, pose, marker.greyPatch);
  if (grey == null) return const PatchReading.invalid('grey patch off-frame');
  final white = _samplePatch(frame, rgb, pose, marker.whitePatch);
  if (white == null) return const PatchReading.invalid('white patch off-frame');

  if (grey.lumaStdDev > PatchReading.maxPatchStdDev) {
    return const PatchReading.invalid('grey patch not uniform');
  }
  if (white.lumaStdDev > PatchReading.maxPatchStdDev) {
    return const PatchReading.invalid('white patch not uniform');
  }
  if (white.lumaMean > PatchReading.maxWhiteLuma) {
    return const PatchReading.invalid('white patch clipped');
  }
  if (grey.lumaMean < PatchReading.minGreyLuma) {
    return const PatchReading.invalid('grey patch too dark');
  }
  if (grey.lumaMean >= white.lumaMean) {
    return const PatchReading.invalid('grey not darker than white');
  }

  return PatchReading(
    greyLinear: grey.linearMean,
    whiteLinear: white.linearMean,
    greyLuma: grey.lumaMean,
    whiteLuma: white.lumaMean,
  );
}

class _PatchStats {
  const _PatchStats({
    required this.linearMean,
    required this.lumaMean,
    required this.lumaStdDev,
  });

  final List<double> linearMean;
  final double lumaMean;
  final double lumaStdDev;
}

_PatchStats? _samplePatch(
  LumaFrame frame,
  List<int> rgb,
  SkinPlanePose pose,
  ColorPatch patch,
) {
  const grid = 5;
  const inner = 0.6;
  final half = patch.sideMm / 2 * inner;

  var sumLuma = 0.0, sumLumaSq = 0.0;
  final sumLin = [0.0, 0.0, 0.0];
  var n = 0;

  for (var gy = 0; gy < grid; gy++) {
    for (var gx = 0; gx < grid; gx++) {
      final xMm = patch.centreMm.dx + (gx / (grid - 1) - 0.5) * 2 * half;
      final yMm = patch.centreMm.dy + (gy / (grid - 1) - 0.5) * 2 * half;
      final full = pose.project(xMm, yMm);
      if (full == null) return null;
      final x = (full.dx / frame.scaleToFull).round();
      final y = (full.dy / frame.scaleToFull).round();
      if (x < 0 || y < 0 || x >= frame.width || y >= frame.height) return null;

      final i = y * frame.width + x;
      final luma = frame.luma[i].toDouble();
      sumLuma += luma;
      sumLumaSq += luma * luma;
      sumLin[0] += srgbToLinear(rgb[i * 3].toDouble());
      sumLin[1] += srgbToLinear(rgb[i * 3 + 1].toDouble());
      sumLin[2] += srgbToLinear(rgb[i * 3 + 2].toDouble());
      n++;
    }
  }
  if (n == 0) return null;

  final mean = sumLuma / n;
  final variance = math.max(0.0, sumLumaSq / n - mean * mean);
  return _PatchStats(
    linearMean: [sumLin[0] / n, sumLin[1] / n, sumLin[2] / n],
    lumaMean: mean,
    lumaStdDev: math.sqrt(variance),
  );
}
