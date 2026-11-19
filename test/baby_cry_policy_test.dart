import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/baby_cry_policy.dart';

void main() {
  final now = DateTime(2026, 11, 19);
  test('intermittent high scores separated by a quiet breath trigger', () {
    final p = BabyCryPolicy();
    expect(p.observe(.05, now), false);
    expect(p.observe(.89, now.add(const Duration(seconds: 1))), false);
    expect(p.observe(.20, now.add(const Duration(seconds: 2))), false);
    expect(p.observe(.60, now.add(const Duration(seconds: 3))), true);
  });
  test('single spike and isolated hits outside the last five windows do not trigger', () {
    final p = BabyCryPolicy();
    expect(p.observe(.89, now), false);
    for (var second = 1; second <= 5; second++) {
      expect(p.observe(.01, now.add(Duration(seconds: second))), false);
    }
    expect(p.observe(.8, now.add(const Duration(seconds: 6))), false);
    expect(p.recentHits, 1);
  });
  test('evidence older than six seconds is discarded even within five windows', () {
    final p = BabyCryPolicy();
    expect(p.observe(.89, now), false);
    expect(p.observe(.01, now.add(const Duration(seconds: 3))), false);
    expect(p.observe(.01, now.add(const Duration(seconds: 6))), false);
    expect(p.observe(.89, now.add(const Duration(seconds: 7))), false);
    expect(p.recentHits, 1);
  });
  test('invalid score clears evidence and threshold remains 0.45', () {
    final p = BabyCryPolicy();
    expect(p.observe(.44, now), false);
    expect(p.observe(.449, now.add(const Duration(seconds: 1))), false);
    expect(p.recentHits, 0);
    expect(p.observe(.9, now.add(const Duration(seconds: 2))), false);
    expect(p.observe(double.nan, now.add(const Duration(seconds: 3))), false);
    expect(p.observe(.9, now.add(const Duration(seconds: 4))), false);
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
  test('diagnostic reads actual cry index, rank and top class', () {
    final scores = List<double>.filled(521, .01);
    scores[0] = .8;
    scores[20] = .3;
    scores[19] = .5;
    final result = BabyCryInference.fromScores(scores);
    expect(result.cryScore, .3);
    expect(result.cryRank, 3);
    expect(result.topIndex, 0);
    expect(result.topLabel, 'Speech');
    expect(() => BabyCryInference.fromScores([.1]), throwsStateError);
    expect(() => BabyCryInference.fromScores(Float32List(521)), throwsStateError);
    expect(() => BabyCryInference.fromScores(
        Float32List(521)..fillRange(0, 521, double.nan)), throwsStateError);
  });
  test('RMS reports normalized waveform level and silence', () {
    expect(babyCryInputDbfs(Float32List(15600)), -100);
    expect(babyCryInputDbfs(Float32List.fromList(List.filled(15600, .5))),
        closeTo(-6.02, .01));
  });
  test('diagnostic distinguishes recent evidence and cooldown', () {
    final p = BabyCryPolicy();
    expect(p.observe(.5, now), false);
    expect(p.recentHits, 1);
    expect(p.inCooldown(now), false);
    expect(p.observe(.5, now), true);
    expect(p.inCooldown(now), true);
    expect(p.cooldownSecondsRemaining(now), 90);
    expect(p.observe(.99, now.add(const Duration(seconds: 89))), false);
    expect(p.recentHits, 0);
    expect(p.inCooldown(now.add(const Duration(seconds: 90))), false);
    expect(p.observe(.99, now.add(const Duration(seconds: 90))), false);
    expect(p.observe(.99, now.add(const Duration(seconds: 91))), true);
  });
  test('rejects wrong length, rate and non-finite audio', () {
    expect(babyCryResample(Float32List(10), 16000), isNull);
    expect(babyCryResample(Float32List(7800), 8000), isNull);
    final bad = Float32List(15600)..[10] = double.nan;
    expect(babyCryResample(bad, 16000), isNull);
  });
}
