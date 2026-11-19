import 'dart:math' as math;
import 'dart:typed_data';

import 'baby_cry_policy.dart';

/// P1 QA only: bounded, per-window gain for quiet microphone inputs.
/// This is not denoising; gain raises background noise as well as the cry.
class BabyCryGainFrame {
  const BabyCryGainFrame({
    required this.samples,
    required this.gain,
    required this.inputDbfs,
    required this.outputDbfs,
  });
  final Float32List samples;
  final double gain;
  final double inputDbfs;
  final double outputDbfs;
}

BabyCryGainFrame? prepareBabyCryGain(Float32List raw) {
  if (raw.length != BabyCryPolicy.inputSamples) return null;
  var mean = 0.0;
  for (final v in raw) {
    if (!v.isFinite || v < -1 || v > 1) return null;
    mean += v;
  }
  mean /= raw.length;
  // Remove DC offset only on the fallback path. Keep the original unmodified.
  var power = 0.0;
  var peak = 0.0;
  for (final v in raw) {
    final centered = v - mean;
    power += centered * centered;
    peak = math.max(peak, centered.abs());
  }
  final rms = math.sqrt(power / raw.length);
  if (rms <= 0 || peak <= 0) return null;
  final dbfs = 20 * math.log(rms) / math.ln10;
  // Avoid near-silence and already adequate signals. These are initial
  // QA bounds, NOT calibrated noise-floor or microphone-distance limits.
  if (dbfs < -65 || dbfs > -32) return null;
  const targetRms = 0.039810717055349734; // -28 dBFS
  final gain = math.min(16.0, math.min(targetRms / rms, 0.90 / peak));
  if (gain < 1.5) return null;
  final output = Float32List(raw.length);
  for (var i = 0; i < raw.length; i++) {
    output[i] = ((raw[i] - mean) * gain).clamp(-0.90, 0.90).toDouble();
  }
  return BabyCryGainFrame(samples: output, gain: gain,
      inputDbfs: dbfs, outputDbfs: babyCryInputDbfs(output));
}

/// Preserve existing raw evidence. The boosted path can promote evidence
/// only if it independently satisfies the existing strong policy and the
/// highest-scored category is infant cry or sobbing, with infant cry in
/// the top three. A weak boosted prediction never adds a vote.
/// Both predictions refer to ONE audio window; caller must vote once.
BabyCryInference selectBabyCryInference({
  required BabyCryPolicy policy,
  required BabyCryInference raw,
  BabyCryInference? boosted,
}) {
  if (boosted == null ||
      policy.evidenceFor(raw) == BabyCryEvidence.strong) return raw;
  final cryTop = boosted.topIndex == BabyCryPolicy.cryClassIndex ||
      boosted.topIndex == BabyCryPolicy.sobbingClassIndex;
  if (cryTop && boosted.cryRank >= 1 && boosted.cryRank <= 3 &&
      policy.evidenceFor(boosted) == BabyCryEvidence.strong) {
    return boosted;
  }
  return raw;
}
