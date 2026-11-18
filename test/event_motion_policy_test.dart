import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/event_motion_policy.dart';

void main() {
  final epoch = DateTime(2026, 11, 18, 14);

  test('does not mistake first frame or uniform exposure change for motion', () {
    final detector = MotionEventDetector();
    final blank = List<int>.filled(40, 40);
    expect(detector.observe(blank, epoch), isFalse);
    expect(detector.observe(List<int>.filled(40, 140),
        epoch.add(const Duration(seconds: 2))), isFalse);
    expect(detector.observe(List<int>.filled(40, 180),
        epoch.add(const Duration(seconds: 4))), isFalse);
  });

  test('motion must persist across two sampled transitions', () {
    final detector = MotionEventDetector();
    final base = List<int>.filled(40, 50);
    final first = List<int>.of(base)..setRange(0, 8, List.filled(8, 200));
    final second = List<int>.of(base)..setRange(10, 18, List.filled(8, 200));
    expect(detector.observe(base, epoch), isFalse);
    expect(detector.observe(first,
        epoch.add(const Duration(seconds: 2))), isFalse);
    expect(detector.observe(second,
        epoch.add(const Duration(seconds: 4))), isTrue);
  });

  test('after trigger, cooldown blocks adjacent duplicate clips', () {
    final detector = MotionEventDetector();
    final base = List<int>.filled(40, 50);
    List<int> moved(int offset) => List<int>.of(base)
      ..setRange(offset, offset + 8, List.filled(8, 200));
    expect(detector.observe(base, epoch), isFalse);
    expect(detector.observe(moved(0),
        epoch.add(const Duration(seconds: 2))), isFalse);
    expect(detector.observe(moved(10),
        epoch.add(const Duration(seconds: 4))), isTrue);
    expect(detector.observe(moved(20),
        epoch.add(const Duration(seconds: 6))), isFalse);
    expect(detector.observe(moved(0),
        epoch.add(const Duration(seconds: 8))), isFalse);
    expect(detector.observe(moved(10),
        epoch.add(const Duration(seconds: 66))), isTrue);
  });

  test('a reset discards frame baseline but preserves cooldown', () {
    final detector = MotionEventDetector();
    final base = List<int>.filled(40, 50);
    final a = List<int>.of(base)..setRange(0, 8, List.filled(8, 200));
    final b = List<int>.of(base)..setRange(10, 18, List.filled(8, 200));
    detector.observe(base, epoch);
    detector.observe(a, epoch.add(const Duration(seconds: 2)));
    expect(detector.observe(b,
        epoch.add(const Duration(seconds: 4))), isTrue);
    detector.reset();
    expect(detector.observe(base,
        epoch.add(const Duration(seconds: 6))), isFalse);
    expect(detector.observe(a,
        epoch.add(const Duration(seconds: 8))), isFalse);
    expect(detector.observe(b,
        epoch.add(const Duration(seconds: 10))), isFalse);
  });

  test('bounded duration, storage, and retention defaults', () {
    expect(EventRecordingPolicy.clipDuration, const Duration(seconds: 20));
    expect(EventRecordingPolicy.maxClipAge, const Duration(days: 30));
    expect(EventRecordingPolicy.maxClips, 50);
    expect(EventRecordingPolicy.maxStoredBytes, 256 * 1024 * 1024);
  });
}
