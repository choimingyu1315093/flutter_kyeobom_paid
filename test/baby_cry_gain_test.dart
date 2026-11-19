import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_home_camera/baby_cry_gain.dart';
import 'package:flutter_home_camera/baby_cry_policy.dart';

Float32List wave(double amplitude, {double dc = 0}) =>
    Float32List.fromList(List.generate(BabyCryPolicy.inputSamples,
      (i) => dc + amplitude * math.sin(2 * math.pi * i / 40)));

BabyCryInference pred(double cry, {int top = 20, int rank = 1,
    double topScore = .7}) => BabyCryInference(
      cryScore: cry, topIndex: top, cryRank: rank, topScore: topScore);

void main() {
  test('bounded gain strengthens a quiet waveform without mutating raw input', () {
    final raw = wave(.006);
    final original = Float32List.fromList(raw);
    final g = prepareBabyCryGain(raw)!;
    expect(g.gain, greaterThan(1.5));
    expect(g.gain, lessThanOrEqualTo(16));
    expect(g.outputDbfs, closeTo(-28, .1));
    expect(raw, orderedEquals(original));
    expect(g.samples.every((s) => s.abs() <= .900001), true);
  });
  test('very weak but usable waveform has capped gain', () {
    final g = prepareBabyCryGain(wave(.001))!;
    expect(g.gain, 16);
    expect(g.outputDbfs, lessThan(-28));
  });
  test('silence, DC, near-silence and adequately loud input bypass gain', () {
    expect(prepareBabyCryGain(Float32List(15600)), isNull);
    expect(prepareBabyCryGain(wave(0, dc: .02)), isNull);
    expect(prepareBabyCryGain(wave(.00001)), isNull);
    expect(prepareBabyCryGain(wave(.2)), isNull);
    expect(prepareBabyCryGain(Float32List(7)), isNull);
    expect(prepareBabyCryGain(wave(.006)..[2] = double.nan), isNull);
  });
  test('peak cap prevents clipping even for sparse impulse input', () {
    final raw = wave(.006)..[500] = .5;
    final g = prepareBabyCryGain(raw)!;
    expect(g.gain, lessThanOrEqualTo(1.81));
    expect(g.samples.every((s) => s.abs() <= .900001), true);
  });
  test('gain path removes DC offset', () {
    final g = prepareBabyCryGain(wave(.006, dc: .03))!;
    final mean = g.samples.reduce((a,b) => a+b) / g.samples.length;
    expect(mean, closeTo(0, .0002));
  });
  test('strong original evidence is never replaced', () {
    final p = BabyCryPolicy();
    final raw = pred(.6);
    expect(selectBabyCryInference(policy:p, raw:raw, boosted:pred(.9)), same(raw));
  });
  test('strong boosted cry is accepted but weak or unrelated output is not', () {
    final p = BabyCryPolicy();
    final raw = pred(.01, top:494, rank:50);
    final good = pred(.6);
    expect(selectBabyCryInference(policy:p, raw:raw, boosted:good), same(good));
    for (final invalid in [pred(.20, top:19, rank:2),
      pred(.6, top:0, rank:2), pred(.35, top:19, rank:4)]) {
      expect(selectBabyCryInference(policy:p, raw:raw, boosted:invalid), same(raw));
    }
    expect(selectBabyCryInference(policy:p, raw:raw), same(raw));
  });
  test('raw and amplified versions count only as one vote per window', () {
    final p = BabyCryPolicy();
    final raw = pred(.01, top:494, rank:50);
    final chosen = selectBabyCryInference(policy:p, raw:raw, boosted:pred(.6));
    final t = DateTime(2026,11,19);
    expect(p.observeInference(chosen,t), false);
    expect(p.recentHits,1);
    expect(p.observeInference(chosen,t.add(const Duration(seconds:1))), true);
    expect(p.observeInference(chosen,t.add(const Duration(seconds:2))), false);
  });
}
