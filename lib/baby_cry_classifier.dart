import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';
import 'baby_cry_policy.dart';

/// Optional local QA only. Model is loaded from the app bundle; no HTTP,
/// logging of samples, recording, or cloud calls.
class BabyCryClassifier {
  static const modelAsset = 'assets/baby_cry/yamnet.tflite';
  Interpreter? _interpreter;
  IsolateInterpreter? _worker;
  bool _inputBatched = false;
  bool _outputBatched = false;

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
      _inputBatched = inputs.first.shape.length == 2;
      _outputBatched = outputs.first.shape.length == 2;
      _worker = await IsolateInterpreter.create(address: interpreter.address);
      _interpreter = interpreter;
    } catch (_) {
      interpreter?.close();
      rethrow;
    } finally {
      options.delete();
    }
  }

  Future<double> score(Float32List frame) async {
    final worker = _worker;
    if (worker == null || frame.length != BabyCryPolicy.inputSamples) {
      throw StateError('Cry model/frame is not ready');
    }
    // Explicit nested lists preserve the verified input/output tensor rank.
    final values = frame.toList(growable: false);
    final result = List<double>.filled(BabyCryPolicy.classCount, 0);
    await worker.run(
      _inputBatched ? [values] : values,
      _outputBatched ? [result] : result,
    );
    final score = result[BabyCryPolicy.cryClassIndex];
    if (!score.isFinite || score < 0 || score > 1) {
      throw StateError('Invalid model score');
    }
    return score;
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
