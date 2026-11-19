import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/baby_cry_policy.dart';

void main() {
  final now = DateTime(2026, 11, 19);
  test('low score and one isolated high score are ignored', () {
    final p = BabyCryPolicy();
    expect(p.observe(.05, now), false);
    expect(p.observe(.95, now), false);
    expect(p.observe(.20, now), false);
    expect(p.observe(.95, now), false);
    expect(p.observe(.95, now), true);
  });
  test('cooldown and pause reset consecutive window evidence', () {
    final p = BabyCryPolicy();
    p.observe(.9, now);
    p.resetWindow();
    expect(p.observe(.9, now), false);
    expect(p.observe(.9, now), true);
    expect(p.observe(.9, now.add(const Duration(seconds: 30))), false);
    expect(p.observe(.9, now.add(const Duration(seconds: 31))), false);
    expect(p.observe(.9, now.add(const Duration(seconds: 91))), false);
    expect(p.observe(.9, now.add(const Duration(seconds: 92))), true);
  });
  test('two scores separated by a long capture gap cannot trigger', () {
    final p = BabyCryPolicy();
    expect(p.observe(.9, now), false);
    expect(p.observe(.9, now.add(const Duration(seconds: 10))), false);
    expect(p.observe(.9, now.add(const Duration(seconds: 11))), true);
  });
  test('converts 16k and 48k mono device input to fixed float waveform', () {
    final mono = Float32List.fromList(List.filled(15600, .25));
    expect(babyCryResample(mono, 16000), orderedEquals(mono));
    final highRate = Float32List.fromList(List.filled(46800, .5));
    final output = babyCryResample(highRate, 48000)!;
    expect(output.length, 15600);
    expect(output.every((v) => v == .5), true);
  });
  test('rejects wrong length, rate and non-finite audio', () {
    expect(babyCryResample(Float32List(10), 16000), isNull);
    expect(babyCryResample(Float32List(7800), 8000), isNull);
    final bad = Float32List(15600)..[10] = double.nan;
    expect(babyCryResample(bad, 16000), isNull);
  });
}
