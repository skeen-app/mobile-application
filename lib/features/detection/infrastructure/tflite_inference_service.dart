import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/inference_result.dart';
import '../domain/ports.dart';

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

    // Decode + resize off the main isolate too — `image` is pure Dart and
    // can be heavy on a 12 MP capture.
    final input = await compute(_preprocess, jpegBytes);

    // Allocate the output buffer in the shape the interpreter expects.
    final output = List.filled(_numClasses, 0.0)
        .reshape<double>([1, _numClasses]);

    await isolate.run(input, output);

    final scores = (output[0] as List).cast<double>();
    return InferenceResult(scores: scores);
  }

  @override
  Future<void> dispose() async {
    await _isolate?.close();
    _interpreter?.close();
    _isolate = null;
    _interpreter = null;
  }
}

/// Top-level so it can run in a worker isolate via `compute`. Decodes the
/// JPEG, bilinearly resizes to 224×224, and produces the
/// `[1, 224, 224, 3]` Float32 tensor the model expects (range 0–255).
List _preprocess(Uint8List jpegBytes) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) {
    throw const FormatException('Could not decode capture as image');
  }
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
  return input.reshape([1, 224, 224, 3]);
}
