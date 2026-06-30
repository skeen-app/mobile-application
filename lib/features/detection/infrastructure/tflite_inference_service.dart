import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../core/logger/app_logger.dart';
import '../domain/class_label.dart';
import '../domain/inference_result.dart';
import '../domain/ports.dart';

class PreprocessResult {
  PreprocessResult({
    required this.tensor,
    required this.inputMin,
    required this.inputMax,
    this.centroid,
  });
  final List tensor;
  final Offset? centroid;

  /// Min / max pixel value actually written into the input tensor. Logged on
  /// every inference so we can confirm on-device that the model receives RAW
  /// `[0, 255]` pixels (NOT `[0, 1]`) — i.e. there is no accidental double
  /// normalization (the bug that made the old model predict "always melanoma").
  final double inputMin;
  final double inputMax;
}

/// Real implementation of [InferenceServicePort] backed by `tflite_flutter`.
///
/// **Model:** `skeen_v3.tflite` — EfficientNet-B0, 6 lesion classes
/// (ACK, BCC, MEL, NEV, SCC, OTHER — see [ClassLabel]).
///
/// **Input** `[1, 224, 224, 3]` **float32**, RGB, RAW pixel range `[0, 255]`.
///   EfficientNet's `preprocess_input` normalization is BAKED INTO the graph,
///   so we MUST feed un-normalized pixels: no `/255`, no mean/std, no rescale.
///   Doing any manual normalization here causes a DOUBLE normalization and
///   collapses accuracy.
///
/// **Output** `[1, 6]` **float32** — softmax probabilities that already sum to
///   1.0. The argmax is the predicted class; the max value is the confidence.
///   No dequantization (the model is NOT uint8-quantized).
///
/// **Why a synchronous [Interpreter]?** Inference is single-shot on capture and
/// the UI is gated behind the "analyzing" overlay, so blocking the main isolate
/// for the short float32 run is acceptable. The slow step (JPEG decode + resize)
/// stays on a worker isolate via [compute].
class TfliteInferenceService implements InferenceServicePort {
  TfliteInferenceService({
    this.modelAsset = 'assets/models/skeen_v3.tflite',
  });

  final String modelAsset;

  Interpreter? _interpreter;

  static const int _numClasses = 6;

  @override
  Future<void> load() async {
    if (_interpreter != null) return;
    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(modelAsset, options: options);

    final inputs = _interpreter!.getInputTensors();
    final outputs = _interpreter!.getOutputTensors();

    // TEMP (verification) — logged via AppLogger so it shows on the device in
    // any build mode, not just debug. Confirms the model signature is the
    // float32 224×224 / [1,6] we expect. Remove once integration is verified.
    AppLogger.info(
      'classifier loaded: $modelAsset\n'
      '  input[0]:  shape=${inputs.first.shape}, type=${inputs.first.type}\n'
      '  output[0]: shape=${outputs.first.shape}, type=${outputs.first.type}',
      tag: 'ModelDebugV3',
    );
  }

  @override
  Future<InferenceResult> classify(Uint8List jpegBytes) async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('InferenceService.load() must be called before classify');
    }

    final sw = Stopwatch()..start();

    // Decode + crop-to-square-resize + centroid calculation off the main isolate.
    final pre = await compute(_preprocess, jpegBytes);
    final preprocessMs = sw.elapsedMilliseconds;

    // Output buffer: float32 of shape [1, 6]. `List.filled(..., 0.0)
    // .reshape<double>(...)` yields the `List<List<double>>` that
    // `Tensor.copyTo` writes float32 outputs into.
    final output = List.filled(_numClasses, 0.0).reshape<double>([1, _numClasses]);

    interpreter.run(pre.tensor, output);
    final totalMs = sw.elapsedMilliseconds;
    sw.stop();

    // Output is already softmax in [0, 1] — no dequantization.
    final scores = (output[0] as List).cast<double>().toList(growable: false);

    final result = InferenceResult(
      scores: scores,
      lesionCentroid: pre.centroid,
    );

    // TEMP (verification) — predicted class, all 6 probabilities, and the
    // input pixel range. The range MUST be ~[0, 255] (max well above 1.0); a
    // max ≤ 1.0 would mean an accidental normalization. Remove after verifying.
    final probs = <String>[
      for (var i = 0; i < scores.length; i++)
        '${ClassLabel.values[i].slug}=${scores[i].toStringAsFixed(3)}',
    ].join(', ');
    AppLogger.info(
      'inference: pred=${result.topLabel.slug} '
      'conf=${(result.confidence * 100).toStringAsFixed(1)}% | '
      'probs=[$probs] | '
      'inputRange=[${pre.inputMin.toStringAsFixed(1)}..${pre.inputMax.toStringAsFixed(1)}] '
      '(raw0..255=${pre.inputMax > 1.5}) | '
      'preprocess=${preprocessMs}ms total=${totalMs}ms',
      tag: 'ModelDebugV3',
    );

    return result;
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
  }
}

/// Top-level so it can run in a worker isolate via `compute`.
/// Performs 3 tasks:
/// 1. Decodes the (already guide-cropped, square) JPEG.
/// 2. Extracts a centered ROI, applies inverse luminance thresholding, and
///    computes the centroid (center of mass) for AR anchoring.
/// 3. Resizes to 224×224 (bilinear) and produces the **float32**
///    `[1, 224, 224, 3]` tensor with RAW `[0, 255]` RGB values — NO
///    normalization (EfficientNet's rescaling lives inside the graph).
PreprocessResult _preprocess(Uint8List jpegBytes) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) {
    throw const FormatException('Could not decode capture as image');
  }

  // ── 1. Fast Centroid Calculation (Contrast-based) ─────────────
  Offset? centroid;
  final w = decoded.width;
  final h = decoded.height;

  // We want a 300x300 crop from the center
  final cropW = min(300, w);
  final cropH = min(300, h);
  final cropStartX = (w - cropW) ~/ 2;
  final cropStartY = (h - cropH) ~/ 2;

  final gray = img.grayscale(decoded);

  // Pass 1: find mean and min luminance in the crop region
  double sumLum = 0;
  int countLum = 0;
  int minLum = 255;
  const step = 2; // sample every 2nd pixel for speed

  for (var y = cropStartY; y < cropStartY + cropH; y += step) {
    for (var x = cropStartX; x < cropStartX + cropW; x += step) {
      final lum = gray.getPixel(x, y).luminance.round();
      sumLum += lum;
      countLum++;
      if (lum < minLum) minLum = lum;
    }
  }

  if (countLum > 0) {
    final meanLum = sumLum / countLum;
    // Threshold: pixels darker than (mean + darkest) / 2 are "lesion"
    final threshold = ((meanLum + minLum) / 2).round();

    // Pass 2: compute weighted centroid of dark pixels
    double cx = 0, cy = 0;
    int darkCount = 0;

    for (var y = cropStartY; y < cropStartY + cropH; y += step) {
      for (var x = cropStartX; x < cropStartX + cropW; x += step) {
        final lum = gray.getPixel(x, y).luminance.round();
        if (lum <= threshold) {
          // Inverse threshold weight: darker = more weight
          final weight = max(1, threshold - lum);
          cx += x * weight;
          cy += y * weight;
          darkCount += weight;
        }
      }
    }

    if (darkCount >= 10) {
      final absoluteCx = cx / darkCount;
      final absoluteCy = cy / darkCount;
      // Normalize relative to full original image (0.0 to 1.0)
      final normX = absoluteCx / w;
      final normY = absoluteCy / h;

      // Only accept if it's within the ROI boundaries (sanity check)
      if (normX >= 0.1 && normX <= 0.9 && normY >= 0.1 && normY <= 0.9) {
        centroid = Offset(normX, normY);
      }
    }
  }

  // ── 2. Resize and Tensor Prep ─────────────────────────────────
  // The incoming JPEG is already the square guide-box crop, so resizing to a
  // square 224 introduces no aspect distortion.
  final resized = img.copyResize(
    decoded,
    width: _kInputSize,
    height: _kInputSize,
    interpolation: img.Interpolation.linear,
  );

  // float32 tensor, RAW [0, 255] RGB — NO normalization (baked into graph).
  final input = Float32List(1 * _kInputSize * _kInputSize * 3);
  var i = 0;
  var inputMin = 255.0;
  var inputMax = 0.0;
  for (var y = 0; y < _kInputSize; y++) {
    for (var x = 0; x < _kInputSize; x++) {
      final p = resized.getPixel(x, y);
      final r = p.r.toDouble();
      final g = p.g.toDouble();
      final b = p.b.toDouble();
      input[i++] = r;
      input[i++] = g;
      input[i++] = b;
      final lo = min(r, min(g, b));
      final hi = max(r, max(g, b));
      if (lo < inputMin) inputMin = lo;
      if (hi > inputMax) inputMax = hi;
    }
  }

  return PreprocessResult(
    tensor: input.reshape([1, _kInputSize, _kInputSize, 3]),
    inputMin: inputMin,
    inputMax: inputMax,
    centroid: centroid,
  );
}

/// Model input edge length (EfficientNet-B0). Lives at top level so the
/// isolate entry point [_preprocess] can read it.
const int _kInputSize = 224;
