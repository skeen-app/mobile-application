import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../detection/application/providers.dart';
import '../../detection/infrastructure/secure_lesion_repository.dart';

/// Per-row mole thumbnail loader for the history list.
///
/// Loads the encrypted scan from local SQLite, decrypts the JPEG, then
/// crops a square around ``inference.lesionCentroid`` (or the image's
/// center when the centroid is missing) and resizes to a 144 px tile.
/// The crop is sized to ~32 % of the shortest side so the lunar reads
/// clearly even in the small list-row miniature.
///
/// `autoDispose.family<id>` keeps the provider scoped: the thumbnail is
/// only computed when its row is on screen and is freed when the user
/// scrolls past.
final scanThumbnailProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, scanId) async {
  final repo = ref.watch(lesionRepositoryProvider);
  if (repo is SecureLesionRepository) {
    await repo.initialize();
  }
  final analysis = await repo.findById(scanId, includeImage: true);
  final bytes = analysis?.imageBytes;
  if (bytes == null || bytes.isEmpty) return null;

  final centroid =
      analysis?.result.lesionCentroid ?? const Offset(0.5, 0.5);
  return compute(
    _cropMoleThumbnail,
    _CropArgs(bytes: bytes, cx: centroid.dx, cy: centroid.dy),
  );
});

/// Top-level isolate-friendly crop. Defined here so `compute` can pass
/// it across the isolate boundary (Dart serialises function references
/// only at top level / static).
Uint8List _cropMoleThumbnail(_CropArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return args.bytes;
  final shortest = math.min(decoded.width, decoded.height);
  final cropSide = math.max(64, (shortest * 0.32).round());

  final centerX = (args.cx * decoded.width).round();
  final centerY = (args.cy * decoded.height).round();
  final left =
      (centerX - cropSide ~/ 2).clamp(0, decoded.width - cropSide);
  final top =
      (centerY - cropSide ~/ 2).clamp(0, decoded.height - cropSide);

  final cropped = img.copyCrop(
    decoded,
    x: left,
    y: top,
    width: cropSide,
    height: cropSide,
  );
  final resized = img.copyResize(cropped, width: 144, height: 144);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 86));
}

class _CropArgs {
  const _CropArgs({required this.bytes, required this.cx, required this.cy});
  final Uint8List bytes;
  final double cx;
  final double cy;
}
