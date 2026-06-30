import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../domain/capture_crop_config.dart';
import '../domain/ports.dart';

/// Real [CaptureCropperPort] backed by the `image` package. Decoding +
/// cropping + re-encoding runs on a worker isolate via [compute] so the
/// capture flow never blocks the main isolate (mirrors the rest of the
/// pipeline's preprocessing).
///
/// **This is the ONLY place the crop math lives.** Both cascade models
/// receive the same cropped buffer afterwards; each still does its own
/// `copyResize` to 224 downstream.
class ImageCaptureCropper implements CaptureCropperPort {
  const ImageCaptureCropper();

  @override
  Future<CropOutcome> crop(
    Uint8List jpegBytes, {
    required Size previewSize,
  }) async {
    // Flag off → identical-to-legacy behavior: hand the bytes straight back.
    if (!kGuideCropEnabled) {
      return CropOutcome(
        bytes: jpegBytes,
        fracX: 1.0,
        fracY: 1.0,
        applied: false,
      );
    }

    final args = _CropArgs(
      bytes: jpegBytes,
      strategy: kGuideCropStrategy,
      ratio: kGuideCropRatio,
      boxLogicalPx: kGuideBoxLogicalPx,
      previewShortestSide: previewSize.shortestSide,
    );
    return compute(_cropCenteredSquare, args);
  }
}

/// Isolate payload — plain fields so it serializes across the [compute] port.
class _CropArgs {
  const _CropArgs({
    required this.bytes,
    required this.strategy,
    required this.ratio,
    required this.boxLogicalPx,
    required this.previewShortestSide,
  });

  final Uint8List bytes;
  final CropStrategy strategy;
  final double ratio;
  final double boxLogicalPx;
  final double previewShortestSide;
}

/// Top-level entry point for [compute]. Crops a **centered square** out of
/// the incoming capture. The square is always centered, so a lesion the user
/// framed in the (centered) guide box is preserved regardless of strategy;
/// the strategies only differ in how the square's SIDE is chosen.
CropOutcome _cropCenteredSquare(_CropArgs a) {
  final decoded = img.decodeImage(a.bytes);
  if (decoded == null) {
    // Decode failure — fail open, return the original untouched.
    return CropOutcome(bytes: a.bytes, fracX: 1.0, fracY: 1.0, applied: false);
  }

  final w = decoded.width;
  final h = decoded.height;
  final shortSide = min(w, h);

  // ── Resolve the crop ratio per strategy ──────────────────────────────
  double ratio;
  switch (a.strategy) {
    case CropStrategy.centeredFraction:
      // Surface-agnostic: a blind fraction of the shorter side.
      ratio = a.ratio;
      break;
    case CropStrategy.coverGeometry:
      // Higher-fidelity (plain-camera BoxFit.cover): the captured square
      // fills the preview's shorter side, so the visible guide box occupies
      // (boxLogicalPx / previewShortestSide) of it. Deriving the ratio from
      // the REAL on-screen proportion keeps the crop locked to the box even
      // across different preview sizes.
      //
      // TODO(detection): validate on-device against the native AR render.
      // The AR path's captureFrame() resolution/crop is opaque from Dart, so
      // for that surface this degrades to a centered square of the same
      // proportion — acceptable, but not pixel-exact. The plain-camera path
      // is the faithful one.
      ratio = a.previewShortestSide > 0
          ? a.boxLogicalPx / a.previewShortestSide
          : a.ratio;
      break;
  }
  ratio = ratio.clamp(0.2, 1.0);

  final side = (shortSide * ratio).round().clamp(1, shortSide);
  final left = (w - side) ~/ 2;
  final top = (h - side) ~/ 2;

  final cropped = img.copyCrop(decoded, x: left, y: top, width: side, height: side);
  final bytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 92));

  return CropOutcome(
    bytes: bytes,
    fracX: side / w,
    fracY: side / h,
    applied: true,
  );
}
