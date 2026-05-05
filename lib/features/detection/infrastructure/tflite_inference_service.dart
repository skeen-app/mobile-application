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

/// Real implementation of [InferenceServicePort] backed by `tflite_flutter`
/// running on an [IsolateInterpreter]. Inference is offloaded to a worker
/// isolate so the AR view can keep rendering at 60 fps while the model
/// classifies (single-shot, on capture).
///
/// Pre-processing matches AI_MODEL_SPECS.md: bilinear 224×224, RGB,
/// `Float32List` shape `[1, 224, 224, 3]` with **values in [0, 255]**
/// (the model has an internal `Rescaling` layer — we MUST NOT divide).
class TfliteInferenceService implements InferenceServicePort {
  TfliteInferenceService({
    this.modelAsset = 'assets/models/skeen_v2_quantized.tflite',
  });

  final String modelAsset;

  IsolateInterpreter? _isolate;
  Interpreter? _interpreter;

  static const int _numClasses = 5;

  @override
  Future<void> load() async {
    if (_isolate != null) return;
    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(modelAsset, options: options);
    _isolate = await IsolateInterpreter.create(address: _interpreter!.address);
    if (kDebugMode) debugPrint('TFLite model loaded: $modelAsset');
  }

  @override
  Future<InferenceResult> classify(Uint8List jpegBytes) async {
    final isolate = _isolate;
    if (isolate == null) {
      throw StateError('InferenceService.load() must be called before classify');
    }

    final sw = Stopwatch()..start();

    // Decode + resize + centroid calculation off the main isolate
    final preprocessResult = await compute(_preprocess, jpegBytes);
    final preprocessMs = sw.elapsedMilliseconds;

    // Allocate the output buffer in the shape the interpreter expects.
    final output = List.filled(_numClasses, 0.0)
        .reshape<double>([1, _numClasses]);

    await isolate.run(preprocessResult.tensor, output);
    final totalMs = sw.elapsedMilliseconds;
    sw.stop();

    if (kDebugMode) {
      debugPrint(
        'TFLite inference: preprocess=${preprocessMs}ms, '
        'total=${totalMs}ms (inference=${totalMs - preprocessMs}ms)',
      );
    }

    final scores = (output[0] as List).cast<double>();
    return InferenceResult(
      scores: scores,
      lesionCentroid: preprocessResult.centroid,
    );
  }

  @override
  Future<void> dispose() async {
    await _isolate?.close();
    _interpreter?.close();
    _isolate = null;
    _interpreter = null;
  }
}

/// Top-level so it can run in a worker isolate via `compute`.
/// Performs 3 tasks:
/// 1. Decodes JPEG.
/// 2. Extracts a 300x300 ROI (Target Ring area), applies inverse thresholding, 
///    and calculates the Center of Mass (centroid) for AR anchoring.
/// 3. Resizes to 224x224 and produces the Float32List tensor for TFLite.
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
    width: 224,
    height: 224,
    interpolation: img.Interpolation.linear,
  );

  final input = Float32List(1 * 224 * 224 * 3);
  var i = 0;
  for (var y = 0; y < 224; y++) {
    for (var x = 0; x < 224; x++) {
      final p = resized.getPixel(x, y);
      input[i++] = p.r.toDouble();
      input[i++] = p.g.toDouble();
      input[i++] = p.b.toDouble();
    }
  }
  
  return PreprocessResult(
    tensor: input.reshape([1, 224, 224, 3]),
    centroid: centroid,
  );
}
