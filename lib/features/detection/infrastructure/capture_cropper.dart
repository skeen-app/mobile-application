import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../domain/capture_crop_config.dart';
import '../domain/capture_roi.dart';
import '../domain/ports.dart';

/// Real [CaptureCropperPort] backed by the `image` package. Decoding +
/// cropping + re-encoding runs on a worker isolate via [compute] so the
/// capture flow never blocks the main isolate (mirrors the rest of the
/// pipeline's preprocessing).
///
/// **This is the ONLY place the crop is performed, and it no longer decides
/// WHERE to crop.** The region comes in as a [CaptureRoi] — the same value
/// that sized the on-screen guide box and bounded the readiness metrics — and
/// is applied with the same [CaptureRoi.boundsIn] those use. One derivation,
/// three consumers.
///
/// Previously this cut a blind `kGuideCropRatio` of the captured image's
/// shorter side. That constant matched the on-screen box only at the aspect
/// ratio it happened to be tuned for; at any other one the models saw a
/// different region than the user framed and than the gate measured.
class ImageCaptureCropper implements CaptureCropperPort {
  const ImageCaptureCropper();

  @override
  Future<CropOutcome> crop(
    Uint8List jpegBytes, {
    required CaptureRoi roi,
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

    return compute(
      _cropToRoi,
      _CropArgs(bytes: jpegBytes, sideFraction: roi.sideFraction),
    );
  }
}

/// Isolate payload — plain fields so it serializes across the [compute] port.
class _CropArgs {
  const _CropArgs({required this.bytes, required this.sideFraction});

  final Uint8List bytes;
  final double sideFraction;
}

/// Top-level entry point for [compute]. Applies the ROI to the decoded
/// capture using exactly the geometry the metrics pipeline used.
CropOutcome _cropToRoi(_CropArgs a) {
  final decoded = img.decodeImage(a.bytes);
  if (decoded == null) {
    // Decode failure — fail open, return the original untouched.
    return CropOutcome(bytes: a.bytes, fracX: 1.0, fracY: 1.0, applied: false);
  }

  final bounds = CaptureRoi(sideFraction: a.sideFraction)
      .boundsIn(decoded.width, decoded.height);

  final cropped = img.copyCrop(
    decoded,
    x: bounds.left,
    y: bounds.top,
    width: bounds.width,
    height: bounds.height,
  );
  final bytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 92));

  return CropOutcome(
    bytes: bytes,
    fracX: bounds.width / decoded.width,
    fracY: bounds.height / decoded.height,
    applied: true,
  );
}
