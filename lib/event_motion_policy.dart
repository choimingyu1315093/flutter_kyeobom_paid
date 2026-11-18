/// Motion-only event recording for an explicitly opted-in station.
/// No camera/microphone access is performed by this policy.
abstract final class EventRecordingPolicy {
  static const sampleEvery = Duration(seconds: 2);
  static const clipDuration = Duration(seconds: 20);
  static const cooldown = Duration(seconds: 60);
  static const maxClipAge = Duration(days: 30);
  static const maxClips = 50;
  static const maxStoredBytes = 256 * 1024 * 1024;
}

/// Compares spatial luma samples, excluding a uniform exposure shift.
/// Two consecutive changed frames are required; this reduces false events
/// from camera auto-exposure and random compression noise.
class MotionEventDetector {
  MotionEventDetector({
    this.minimumCellChange = 18,
    this.changedFraction = 0.10,
    this.requiredConsecutive = 2,
    this.cooldown = EventRecordingPolicy.cooldown,
  });

  final int minimumCellChange;
  final double changedFraction;
  final int requiredConsecutive;
  final Duration cooldown;
  List<int>? _previous;
  DateTime? _lastTrigger;
  int _streak = 0;

  bool observe(List<int> luma, DateTime now) {
    if (luma.isEmpty) return false;
    final previous = _previous;
    _previous = List<int>.of(luma);
    if (previous == null || previous.length != luma.length) {
      _streak = 0;
      return false;
    }

    // Treat a global scene brightness change as exposure, not motion.
    var shift = 0.0;
    for (var i = 0; i < luma.length; i++) {
      shift += luma[i] - previous[i];
    }
    shift /= luma.length;
    var changed = 0;
    for (var i = 0; i < luma.length; i++) {
      if ((luma[i] - previous[i] - shift).abs() >= minimumCellChange) {
        changed++;
      }
    }
    if (changed / luma.length >= changedFraction) {
      _streak++;
    } else {
      _streak = 0;
    }
    if (_streak < requiredConsecutive) return false;
    if (_lastTrigger != null &&
        now.difference(_lastTrigger!) < cooldown) return false;
    _lastTrigger = now;
    _streak = 0;
    return true;
  }

  void reset() {
    _previous = null;
    _streak = 0;
    // Preserve cooldown across stopping/restarting an individual stream.
  }
}
