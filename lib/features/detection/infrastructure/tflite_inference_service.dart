import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/inference_result.dart';
import '../domain/ports.dart';

class PreprocessResult {
  PreprocessResult({required this.tensor, this.centroid});
  final List tensor;
  final Offset? centroid;
}

/// Real implementation of [InferenceServicePort] backed by `tflite_flutter`.
///
/// **Model:** `skeen_model_v2.tflite` — EfficientNet-B1, 5 lesion classes,
/// fully uint8-quantized (input AND output) per the training export
/// (`inference_input_type=tf.uint8`). Verified tensor signature:
///   * input  `[1, 240, 240, 3]` uint8, quant scale 1.0 / zeroPoint 0
///     → feed **raw `[0, 255]` RGB**. EfficientNet's internal normalization
///       layer is baked into the graph; we MUST NOT divide or rescale.
///   * output `[1, 5]` uint8, quant scale `0.00390625` (1/256) / zeroPoint 0
///     → dequantize each score with `real = (raw - zeroPoint) * scale` to
///       recover the softmax probabilities in `[0, 1]`.
///
/// **Why a synchronous [Interpreter] instead of [IsolateInterpreter]?**
/// Same reason as [TfliteSkinGateService]: `tflite_flutter`'s isolate path
/// deadlocks silently on uint8 tensors. Inference is single-shot on capture
/// and the UI is already gated behind the "analyzing" overlay, so blocking
/// the main isolate for the ~10–20 ms quantized run is acceptable. The slow
/// step (JPEG decode + resize, ~200 ms) stays on a worker isolate via
/// [compute].
///
/// See `docs/specs/AI_MODEL_SPECS.md` for the full spec.
class TfliteInferenceService implements InferenceServicePort {
  TfliteInferenceService({
    this.modelAsset = 'assets/models/skeen_model_v2.tflite',
  });

  final String modelAsset;

  Interpreter? _interpreter;

  // Output dequantization parameters, populated by [load]. The model emits
  // uint8 softmax scores mapped back to real probabilities via
  // `(raw - zeroPoint) * scale`. Cached so we don't query the tensor on
  // every inference.
  double _outputScale = 1.0;
  int _outputZeroPoint = 0;

  static const int _numClasses = 5;

  @override
  Future<void> load() async {
    if (_interpreter != null) return;
    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(modelAsset, options: options);

    final outputTensor = _interpreter!.getOutputTensors().first;
    _outputScale = outputTensor.params.scale;
    _outputZeroPoint = outputTensor.params.zeroPoint;

    if (kDebugMode) {
      final inputs = _interpreter!.getInputTensors();
      final outputs = _interpreter!.getOutputTensors();
      debugPrint(
        'TFLite classifier loaded: $modelAsset\n'
        '  input[0]:  shape=${inputs.first.shape}, type=${inputs.first.type}, '
        'scale=${inputs.first.params.scale}, zeroPoint=${inputs.first.params.zeroPoint}\n'
        '  output[0]: shape=${outputs.first.shape}, type=${outputs.first.type}, '
        'scale=$_outputScale, zeroPoint=$_outputZeroPoint',
      );
    }
  }

  @override
  Future<InferenceResult> classify(Uint8List jpegBytes) async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('InferenceService.load() must be called before classify');
    }

    final sw = Stopwatch()..start();

    // Decode + resize + centroid calculation off the main isolate.
    final preprocessResult = await compute(_preprocess, jpegBytes);
    final preprocessMs = sw.elapsedMilliseconds;

    // Output buffer: uint8 of shape [1, 5]. `List.filled(...).reshape<int>`
    // yields the `List<List<int>>` that `Tensor.copyTo` writes uint8 outputs
    // into.
    final output = List.filled(_numClasses, 0).reshape<int>([1, _numClasses]);

    // Synchronous run on the main isolate — fast for this quantized model.
    interpreter.run(preprocessResult.tensor, output);
    final totalMs = sw.elapsedMilliseconds;
    sw.stop();

    // Dequantize uint8 → real softmax probabilities in [0, 1].
    final raw = (output[0] as List).cast<int>();
    final scores = raw
        .map((v) => (v - _outputZeroPoint) * _outputScale)
        .toList(growable: false);

    if (kDebugMode) {
      debugPrint(
        'TFLite inference: preprocess=${preprocessMs}ms, '
        'total=${totalMs}ms (inference=${totalMs - preprocessMs}ms), '
        'raw=$raw, scores=${scores.map((s) => s.toStringAsFixed(3)).toList()}',
      );
    }

    return InferenceResult(
      scores: scores,
      lesionCentroid: preprocessResult.centroid,
    );
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
  }
}

/// Top-level so it can run in a worker isolate via `compute`.
/// Performs 3 tasks:
/// 1. Decodes JPEG.
/// 2. Extracts a 300x300 ROI (Target Ring area), applies inverse thresholding,
///    and calculates the Center of Mass (centroid) for AR anchoring.
/// 3. Resizes to 240x240 and produces the **uint8** `[1, 240, 240, 3]` tensor
///    with raw `[0, 255]` RGB values (no normalization — the model's internal
///    rescaling handles it).
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
  final resized = img.copyResize(
    decoded,
    width: _kInputSize,
    height: _kInputSize,
    interpolation: img.Interpolation.linear,
  );

  // uint8 tensor, raw [0, 255] RGB — NO normalization.
  final input = Uint8List(1 * _kInputSize * _kInputSize * 3);
  var i = 0;
  for (var y = 0; y < _kInputSize; y++) {
    for (var x = 0; x < _kInputSize; x++) {
      final p = resized.getPixel(x, y);
      input[i++] = p.r.toInt();
      input[i++] = p.g.toInt();
      input[i++] = p.b.toInt();
    }
  }

  return PreprocessResult(
    tensor: input.reshape([1, _kInputSize, _kInputSize, 3]),
    centroid: centroid,
  );
}

/// Model input edge length. Mirrors [TfliteInferenceService._inputSize] but
/// lives at top level so the isolate entry point [_preprocess] can read it.
const int _kInputSize = 240;
