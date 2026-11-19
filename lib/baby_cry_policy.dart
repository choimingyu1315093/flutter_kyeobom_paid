import 'dart:typed_data';

/// QA starting threshold, NOT a validated probability of crying.
class BabyCryPolicy {
  static const inputSamples = 15600;
  static const sampleRate = 16000;
  static const cryClassIndex = 20;
  static const classCount = 521;

  BabyCryPolicy({
    this.threshold = 0.45,
    this.requiredWindows = 2,
    this.cooldown = const Duration(seconds: 90),
  });
  final double threshold;
  final int requiredWindows;
  final Duration cooldown;
  int _streak = 0;
  DateTime? _lastEvent;

  bool observe(double score, DateTime now) {
    if (!score.isFinite || score < threshold || score > 1) {
      _streak = 0;
      return false;
    }
    if (++_streak < requiredWindows) return false;
    _streak = 0;
    final last = _lastEvent;
    if (last != null && now.difference(last) < cooldown) return false;
    _lastEvent = now;
    return true;
  }

  /// Pause/restore discards the previous consecutive-window evidence.
  void resetWindow() => _streak = 0;
}

/// Native inputs are mono, sampled at the actual device rate. Convert one
/// 975-ms window to 16kHz. Average each source interval when downsampling
/// rather than dropping all intermediate samples. No file or network IO.
Float32List? babyCryResample(Float32List input, int sourceRate) {
  if (sourceRate < 16000 || sourceRate > 192000) return null;
  final expected = (sourceRate * 0.975).round();
  if (input.length != expected) return null;
  final output = Float32List(BabyCryPolicy.inputSamples);
  for (var i = 0; i < output.length; i++) {
    final a = i * input.length ~/ output.length;
    final b = (i + 1) * input.length ~/ output.length;
    var sum = 0.0;
    for (var j = a; j < b; j++) {
      if (!input[j].isFinite) return null;
      sum += input[j];
    }
    output[i] = (sum / (b - a)).clamp(-1.0, 1.0).toDouble();
  }
  return output;
}
