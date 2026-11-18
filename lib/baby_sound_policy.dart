/// On-device sound-change detection only. No audio is retained, uploaded,
/// recorded or classified as a cry. Detection deliberately errs conservative.
class BabySoundDetector {
  BabySoundDetector({
    this.calibrationSamples = 8,
    this.requiredSamples = 3,
    this.minimumDeltaDb = 12,
    this.minimumLoudnessDb = -55,
    this.cooldown = const Duration(seconds: 90),
  });

  final int calibrationSamples;
  final int requiredSamples;
  final double minimumDeltaDb;
  final double minimumLoudnessDb;
  final Duration cooldown;

  double? _baselineDb;
  int _baselineSamples = 0;
  int _consecutive = 0;
  DateTime? _lastAlert;

  double? get baselineDb => _baselineDb;
  bool get calibrated => _baselineSamples >= calibrationSamples;

  /// Accepts negative dBFS from the native mic meter, never PCM samples.
  /// Returns true only for a sustained, significant change in volume.
  bool observe(double db, DateTime now) {
    if (!db.isFinite || db < -100 || db > 0) return false;
    if (!calibrated) {
      final previous = _baselineDb;
      _baselineDb = previous == null
          ? db
          : (previous * _baselineSamples + db) / (_baselineSamples + 1);
      _baselineSamples++;
      return false;
    }

    final baseline = _baselineDb ?? db;
    final elevated = db >= minimumLoudnessDb &&
        db - baseline >= minimumDeltaDb;
    if (!elevated) {
      _consecutive = 0;
      // Slowly follow normal background noise; loud spikes do not adjust
      // baseline so ongoing crying/speech cannot immediately hide itself.
      _baselineDb = baseline * 0.98 + db * 0.02;
      return false;
    }

    _consecutive++;
    if (_consecutive < requiredSamples) return false;
    _consecutive = 0;

    if (_lastAlert != null && now.difference(_lastAlert!) < cooldown) {
      return false;
    }
    _lastAlert = now;
    return true;
  }

  void reset() {
    _baselineDb = null;
    _baselineSamples = 0;
    _consecutive = 0;
    // Preserve cooldown even after a live-viewing interruption.
  }
}
