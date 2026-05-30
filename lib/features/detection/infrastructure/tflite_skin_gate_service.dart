import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/ports.dart';
import '../domain/skin_gate_result.dart';

/// Real implementation of [SkinGateServicePort] backed by `tflite_flutter`.
///
/// **Why a synchronous [Interpreter] instead of [IsolateInterpreter]?**
/// The cancer classifier uses [IsolateInterpreter] because its tensors
/// are `Float32List` — a type that `tflite_flutter` serializes cleanly
/// across the isolate port. This model is **fully uint8-quantized**
/// (input AND output) per the training export
/// (`inference_input_type=tf.uint8`). The package's isolate path
/// deadlocks silently on uint8 tensors; synchronous inference sidesteps
/// the bug entirely.
///
/// Blocking the main isolate is acceptable here because the model is
/// tiny + quantized (~1.3 MB, ~5–15 ms inference) and the UI is already
/// gated behind the "analyzing" overlay at this point. Preprocessing —
/// the slow step (JPEG decode + resize, ~200 ms) — stays on a worker
/// isolate via [compute].
///
/// **Input:** `Uint8List` shape `[1, 224, 224, 3]` with raw `[0, 255]`
/// RGB pixel values. MobileNetV3Small's built-in Rescaling layer handles
/// normalization inside the graph.
///
/// **Output:** `Uint8List` shape `[1, 1]`. The single sigmoid value is
/// quantized to uint8 and must be **dequantized** with the model's
/// output `scale` and `zeroPoint`:
///   `real_score = (raw_uint8 - zeroPoint) * scale`
/// These are read from the output tensor's [QuantizationParams] at load
/// time and cached.
///
/// See `docs/specs/AI_MODEL_SPECS.md` for the full spec.
class TfliteSkinGateService implements SkinGateServicePort {
  TfliteSkinGateService({
    this.modelAsset = 'assets/models/skin_detector_v1.tflite',
  });

  final String modelAsset;

  Interpreter? _interpreter;

  // Output dequantization parameters, populated by [load]. The model
  // emits uint8 scores that map back to the real sigmoid range via
  // `(raw - zeroPoint) * scale`. Caching avoids querying the tensor on
  // every inference.
  double _outputScale = 1.0;
  int _outputZeroPoint = 0;

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
        'Skin-gate model loaded: $modelAsset\n'
        '  input[0]:  shape=${inputs.first.shape}, type=${inputs.first.type}, '
        'scale=${inputs.first.params.scale}, zeroPoint=${inputs.first.params.zeroPoint}\n'
        '  output[0]: shape=${outputs.first.shape}, type=${outputs.first.type}, '
        'scale=$_outputScale, zeroPoint=$_outputZeroPoint',
      );
    }
  }

  @override
  Future<SkinGateResult> evaluate(Uint8List jpegBytes) async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('SkinGateService.load() must be called before evaluate');
    }

    final sw = Stopwatch()..start();

    // Heavy preprocessing (decode + resize) on a worker isolate.
    final tensor = await compute(_preprocessSkinGate, jpegBytes);
    final preprocessMs = sw.elapsedMilliseconds;

    // Output buffer: uint8 of shape [1, 1]. Using `List.filled(1, 0)
    // .reshape<int>(...)` produces a `List<List<int>>` which is what
    // `Tensor.copyTo` writes into for uint8 outputs.
    final output = List.filled(1, 0).reshape<int>([1, 1]);

    // Synchronous run on the main isolate — fast (~5–15 ms) for this
    // quantized MobileNetV3Small.
    interpreter.run(tensor, output);
    final totalMs = sw.elapsedMilliseconds;
    sw.stop();

    final raw = (output[0] as List).cast<int>().first;
    final score = (raw - _outputZeroPoint) * _outputScale;
    final result = SkinGateResult(skinScore: score);

    if (kDebugMode) {
      debugPrint(
        'Skin-gate inference: preprocess=${preprocessMs}ms, '
        'total=${totalMs}ms (inference=${totalMs - preprocessMs}ms), '
        'raw=$raw, score=${score.toStringAsFixed(3)}, isSkin=${result.isSkin}',
      );
    }

    return result;
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
  }
}

/// Top-level so it can run in a worker isolate via `compute`. Decodes the
/// JPEG, bilinear-resizes to 224×224, and emits the `[1, 224, 224, 3]`
/// **uint8** tensor with raw RGB pixel values in `[0, 255]`.
List _preprocessSkinGate(Uint8List jpegBytes) {
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

  final input = Uint8List(1 * 224 * 224 * 3);
  var i = 0;
  for (var y = 0; y < 224; y++) {
    for (var x = 0; x < 224; x++) {
      final p = resized.getPixel(x, y);
      input[i++] = p.r.toInt();
      input[i++] = p.g.toInt();
      input[i++] = p.b.toInt();
    }
  }

  return input.reshape([1, 224, 224, 3]);
}
