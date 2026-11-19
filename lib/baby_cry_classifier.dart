import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';
import 'baby_cry_policy.dart';

/// Optional local QA only. Model is loaded from the app bundle; no HTTP,
/// logging of samples, recording, or cloud calls.
class BabyCryClassifier {
  static const modelAsset = 'assets/baby_cry/yamnet.tflite';
  Interpreter? _interpreter;
  IsolateInterpreter? _worker;

  Future<void> initialize() async {
    if (_worker != null) return;
    final options = InterpreterOptions()..threads = 1;
    Interpreter? interpreter;
    try {
      interpreter = await Interpreter.fromAsset(modelAsset, options: options);
      final inputs = interpreter.getInputTensors();
      final outputs = interpreter.getOutputTensors();
      bool shapeMatches(List<int> shape, int size) =>
          (shape.length == 1 && shape[0] == size) ||
          (shape.length == 2 && shape[0] == 1 && shape[1] == size);
      if (inputs.length != 1 || outputs.length != 1 ||
          inputs.first.type != TensorType.float32 ||
          outputs.first.type != TensorType.float32 ||
          !shapeMatches(inputs.first.shape, BabyCryPolicy.inputSamples) ||
          !shapeMatches(outputs.first.shape, BabyCryPolicy.classCount)) {
        throw StateError('Unexpected YAMNet tensor signature');
      }
      _worker = await IsolateInterpreter.create(address: interpreter.address);
      _interpreter = interpreter;
      // Check actual inference/output transfer with a synthetic silence frame.
      // A valid YAMNet prediction can have tiny cry scores, but not an
      // untouched or entirely zero 521-class vector.
      await classify(Float32List(BabyCryPolicy.inputSamples));
    } catch (_) {
      await _worker?.close();
      _worker = null;
      _interpreter = null;
      interpreter?.close();
      rethrow;
    } finally {
      options.delete();
    }
  }

  Future<BabyCryInference> classify(Float32List frame) async {
    final worker = _worker;
    if (worker == null || frame.length != BabyCryPolicy.inputSamples) {
      throw StateError('Cry model/frame is not ready');
    }
    // Tensor shapes/dtypes were checked at initialization. Use contiguous
    // buffers instead of nested lists: Tensor.copyTo may replace an inner
    // list, leaving a separately retained reference unchanged. ByteBuffer
    // is explicitly copied into caller-owned memory by tflite_flutter 0.12.1.
    final input = Float32List.fromList(frame);
    final output = Float32List(BabyCryPolicy.classCount);
    output.fillRange(0, output.length, double.nan);
    await worker.run(input.buffer, output.buffer);
    return BabyCryInference.fromScores(output);
  }

  Future<void> close() async {
    try {
      await _worker?.close();
    } finally {
      _worker = null;
      _interpreter?.close();
      _interpreter = null;
    }
  }
}
