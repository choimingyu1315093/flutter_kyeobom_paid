import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/baby_sound_policy.dart';

void main() {
  final base = DateTime(2026, 11, 18, 18, 0);
  BabySoundDetector ready({Duration cooldown = const Duration(seconds: 90)}) {
    final detector = BabySoundDetector(cooldown: cooldown);
    for (var i = 0; i < 8; i++) {
      expect(detector.observe(-67, base.add(Duration(seconds: i))), false);
    }
    return detector;
  }

  test('requires calibration; quiet ambience never triggers', () {
    final detector = ready();
    expect(detector.calibrated, true);
    expect(detector.observe(-67, base.add(const Duration(seconds: 9))), false);
    expect(detector.baselineDb, closeTo(-67, 0.1));
  });

  test('one sudden knock is not mistaken for sustained sound', () {
    final detector = ready();
    expect(detector.observe(-25, base.add(const Duration(seconds: 9))), false);
    expect(detector.observe(-67, base.add(const Duration(seconds: 10))), false);
    expect(detector.observe(-25, base.add(const Duration(seconds: 11))), false);
  });

  test('three consecutive loud samples create one sound event', () {
    final detector = ready();
    expect(detector.observe(-35, base.add(const Duration(seconds: 9))), false);
    expect(detector.observe(-34, base.add(const Duration(seconds: 10))), false);
    expect(detector.observe(-34, base.add(const Duration(seconds: 11))), true);
  });

  test('90-second cooldown avoids repeated alerts', () {
    final detector = ready();
    for (var i = 0; i < 3; i++) {
      final isAlert = detector.observe(-35, base.add(Duration(seconds: 10 + i)));
      expect(isAlert, i == 2);
    }
    for (var i = 0; i < 6; i++) {
      expect(detector.observe(-30, base.add(Duration(seconds: 20 + i))), false);
    }
    expect(detector.observe(-35, base.add(const Duration(seconds: 110))), false);
    expect(detector.observe(-35, base.add(const Duration(seconds: 111))), false);
    expect(detector.observe(-35, base.add(const Duration(seconds: 112))), true);
  });

  test('uniformly loud background does not trigger without change', () {
    final detector = BabySoundDetector();
    for (var i = 0; i < 8; i++) {
      expect(detector.observe(-29, base.add(Duration(seconds: i))), false);
    }
    for (var i = 9; i < 20; i++) {
      expect(detector.observe(-29, base.add(Duration(seconds: i))), false);
    }
  });

  test('invalid audio levels ignored and calibration restarts after reset', () {
    final detector = ready();
    expect(detector.observe(double.nan, base), false);
    expect(detector.observe(3, base), false);
    detector.reset();
    expect(detector.calibrated, false);
    expect(detector.observe(-22, base), false);
  });
}
