import 'dart:math' as math;
import 'dart:typed_data';

enum BabyCryEvidence { none, supporting, strong }

/// QA starting thresholds, NOT validated probabilities of crying.
class BabyCryPolicy {
  static const inputSamples = 15600;
  static const sampleRate = 16000;
  static const cryClassIndex = 20;
  static const sobbingClassIndex = 19;
  static const classCount = 521;

  BabyCryPolicy({
    this.threshold = 0.45,
    this.requiredWindows = 2,
    this.cooldown = const Duration(seconds: 90),
    this.evidenceWindow = const Duration(seconds: 8),
    this.maxRecentWindows = 7,
  }) : assert(requiredWindows > 0 && requiredWindows <= maxRecentWindows);
  final double threshold;
  final int requiredWindows;
  final Duration cooldown;
  final Duration evidenceWindow;
  final int maxRecentWindows;
  final List<({DateTime at, BabyCryEvidence evidence})> _recent = [];
  DateTime? _lastEvent;
  DateTime? _lastWindow;

  int get recentHits => _recent
      .where((entry) => entry.evidence != BabyCryEvidence.none).length;
  int get recentStrongHits => _recent
      .where((entry) => entry.evidence == BabyCryEvidence.strong).length;

  int cooldownSecondsRemaining(DateTime now) {
    final last = _lastEvent;
    if (last == null) return 0;
    final remaining = cooldown - now.difference(last);
    return remaining.isNegative
        ? 0
        : (remaining.inMilliseconds / 1000).ceil();
  }

  bool inCooldown(DateTime now) => cooldownSecondsRemaining(now) > 0;

  /// Keep the direct baby-class threshold. Class 19 alone must never
  /// trigger an event: require class 20 to be among the top three, plus
  /// substantial class-19 and class-20 scores in the SAME prediction.
  /// A weaker pair can corroborate, but at least one strong hit is required.
  BabyCryEvidence evidenceFor(BabyCryInference inference) {
    final score = inference.cryScore;
    if (!score.isFinite || score < 0 || score > 1) {
      return BabyCryEvidence.none;
    }
    if (score >= threshold) return BabyCryEvidence.strong;
    if (inference.topIndex != sobbingClassIndex ||
        inference.cryRank < 1 || inference.cryRank > 3 ||
        !inference.topScore.isFinite || inference.topScore > 1 ||
        inference.topScore < 0.25 || score < 0.18) {
      return BabyCryEvidence.none;
    }
    return score >= 0.30
        ? BabyCryEvidence.strong
        : BabyCryEvidence.supporting;
  }

  bool observeInference(BabyCryInference inference, DateTime now) =>
      _observe(inference.cryScore, evidenceFor(inference), now);

  /// Direct-score-only callers keep the same single-window threshold.
  bool observe(double score, DateTime now) => _observe(
      score,
      score.isFinite && score >= threshold && score <= 1
          ? BabyCryEvidence.strong
          : BabyCryEvidence.none,
      now);

  /// Two distinct positive windows (at least one strong) within the
  /// most recent seven predictions and eight seconds.
  /// Invalid input, a capture gap or pause must not bridge evidence.
  bool _observe(double score, BabyCryEvidence evidence, DateTime now) {
    final previousWindow = _lastWindow;
    if (previousWindow != null &&
        (now.isBefore(previousWindow) ||
         now.difference(previousWindow) > const Duration(seconds: 3))) {
      resetWindow();
    }
    _lastWindow = now;
    if (!score.isFinite || score < 0 || score > 1) {
      resetWindow();
      return false;
    }
    if (inCooldown(now)) {
      // Do not carry evidence collected during cooldown into a new event.
      _recent.clear();
      return false;
    }

    _recent.removeWhere((entry) => now.difference(entry.at) > evidenceWindow);
    _recent.add((at: now, evidence: evidence));
    while (_recent.length > maxRecentWindows) {
      _recent.removeAt(0);
    }
    if (evidence == BabyCryEvidence.none ||
        recentHits < requiredWindows || recentStrongHits == 0) return false;

    _recent.clear();
    _lastEvent = now;
    return true;
  }

  /// Pause/restore discards recent-window evidence but preserves cooldown.
  void resetWindow() {
    _recent.clear();
    _lastWindow = null;
  }
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

/// Diagnostic summary of the score vector only. No audio is retained.
class BabyCryInference {
  const BabyCryInference({required this.cryScore, required this.topIndex,
    required this.topScore, required this.cryRank});

  final double cryScore;
  final int topIndex;
  final double topScore;
  final int cryRank;

  factory BabyCryInference.fromScores(List<double> scores) {
    if (scores.length != BabyCryPolicy.classCount ||
        scores.any((s) => !s.isFinite || s < 0 || s > 1)) {
      throw StateError('Invalid YAMNet output scores');
    }
    if (scores.every((s) => s == 0)) {
      throw StateError('All YAMNet scores are zero; output invalid');
    }
    final cry = scores[BabyCryPolicy.cryClassIndex];
    var top = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[top]) top = i;
    }
    return BabyCryInference(cryScore: cry, topIndex: top,
      topScore: scores[top],
      cryRank: 1 + scores.where((s) => s > cry).length);
  }

  String get topLabel => switch (topIndex) {
    0 => 'Speech',
    1 => 'Child speech',
    4 => 'Babbling',
    11 => 'Screaming',
    12 => 'Whispering',
    13 => 'Laughter',
    14 => 'Baby laughter',
    19 => 'Crying, sobbing',
    20 => 'Baby cry, infant cry',
    21 => 'Whimper',
    _ => 'Class #$topIndex',
  };
}

double babyCryInputDbfs(Float32List frame) {
  if (frame.isEmpty) return -100;
  var power = 0.0;
  for (final v in frame) {
    if (!v.isFinite) return -100;
    power += v * v;
  }
  final rms = math.sqrt(power / frame.length);
  return (20 * math.log(math.max(rms, 0.00001)) / math.ln10)
      .clamp(-100.0, 0.0).toDouble();
}
