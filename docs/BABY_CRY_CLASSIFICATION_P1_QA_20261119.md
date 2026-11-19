# P1 candidate cry classification — local QA, not release

P0 user-reported acceptance: 47/47 Android station and 47/47 iPhone station,
including QR, live AV, event MP4, foreground/background, and 30-minute runs.
P0 automatic UI regression: restore correct standby audio-transmission OFF copy.
P1 remains opt-in using `--dart-define=KYEOBOM_CRY_QA=true` at build time.
The existing general sound detector and 90-second cooldown are independent.

The official Google YAMNet model maps class 20 to Baby cry, infant cry.
One 975ms mono window is resampled to 16kHz and evaluated on a single CPU
thread in an isolate. The direct class-20 score threshold remains 0.45.
When class 19 is top (score >= 0.25), class 20 is ranked 1–3 and its
score is >= 0.18, the prediction corroborates baby cry. The corroborated
score must be >= 0.30 to count as strong evidence; a direct hit is also strong.
Require two distinct hits including one strong among the last seven
valid predictions within eight seconds. Class 19 alone is insufficient.
These are QA parameters, not calibrated probabilities or accuracy claims.
Adult crying can still be a false positive; explicitly test it with speech,
music, TV and other ordinary negative sounds before release.
Capture gaps over three seconds and invalid inputs clear evidence.
Evidence collected during the 90-second cooldown cannot trigger a later event.
QA UI shows recent evidence or cooldown seconds; logs show both.
Separate cry candidate count/score displayed only on station. No pushes yet.

Model binary is not in Git: the development environment could not access
the official storage URL. Prepare from official URL locally; validates
the TFLite header and embedded label index, records SHA256, then interpreter
validates float32 input/output shape. URL "latest" is not a pinned release.
Do not ship until checksum and license/attribution verified for fixed file.

No audio files, server upload, audio logs, or new permission on viewer.
Only transient bounded waveform windows in memory in QA mode; native
capture disabled in ordinary P0 mode, while streaming, backgrounded, OFF,
or leaving station. Model failures must leave normal sound monitoring usable.

## Run
```bash
git fetch origin
git switch --track origin/paid/baby-cry-classification-p1-20261119
bash tools/prepare_baby_cry_model.sh
flutter pub get
flutter test test/kyeobom_ui_test.dart
flutter test test/baby_cry_policy_test.dart
flutter test
flutter build apk --debug --dart-define=KYEOBOM_CRY_QA=true
flutter build ios --debug --no-codesign --dart-define=KYEOBOM_CRY_QA=true
```

## QA
QR pair Android station + iPhone viewer, then swap. Enable baby mode on
station. Confirm separate model score text, no model failure. Quiet,
speech, knock, vacuum, music and externally played baby cries (not actual
distress) at similar volume. Observe cry score and separate count, not
generic sound counter. Wait at least 90s between independent positive
events. Use multiple distinct clips, real ambient noise, distances 1m/3m,
30-minute thermal check, stream/mic transition, recorder compatibility,
OFF/background/return. Report false positives/negatives with scenario and
score; do not tune blindly. TV playback of actual cries can also trigger.
A baby monitor is not a substitute for direct supervision.

After device QA and accuracy measurement, decide threshold and server
push scope, then separately implement approved-viewer-only metadata/FCM
and test security rules before any deployment. Existing Firestore rules,
Cloud Functions, free repo and other paid baseline branches unchanged.

## Intermittent-cry follow-up QA
Android screenshot showed peak 0.8906, five threshold hits across 150 predictions,
and zero events. This confirms high-score output but does not isolate the exact
reason for rejection without per-frame logs. Retest three different cry clips
at 1m with 90-second cooldown expired. Retest ordinary negative sounds after
the policy change. If a clip fails, capture score/time sequence from
KyeobomCryQA logs. Do not interpret 0.8906 as measured accuracy.

## Score fusion follow-up
The supplied Android trace had three direct hits, all with class 19 ranked first.
Preserve direct evidence while recognizing the overlapping classes, require at
least one strong hit, and log elapsed milliseconds and evidence type. The
policy-only replay assumes sampling cadence because older logs lack timestamps;
retest separate, previously unused clips outside cooldown and compare adult
crying and normal speech before release.

## Quiet and distant cry QA (bounded gain fallback)
Android user QA: 8/10. Three ordinary cry clips, adult speech/cry, TV/music,
infant babbling/laughter and cooldown passed; quiet cry and 3m cry missed.
No per-frame traces were supplied for those two misses, hence gain improvement
is a hypothesis, not a verified fix. Raw scoring and temporal policy remain
unchanged. For raw non-strong evidence outside cooldown, eligible input
(-65 to -32 dBFS after DC removal) receives bounded gain toward -28 dBFS,
maximum 16x and peak 0.90. The second prediction can replace raw only if
strong under the existing policy, top category 19 or 20 and cry rank <=3.
Exactly one observation per window; silence/strong raw signals bypass gain.
No new native capture, recording, data transmission or model dependency.
KYEOBOM_CRY_GAIN_QA=false disables gain for controlled A/B comparison.
The fallback can amplify noise too, so quiet/3m and all negative tests must
be repeated at the same volume and distance, plus novel cries and noisy rooms.
Logs report rawCry, gainCry, gain, gainDbFS, gainUsed, gainRuns and gainHits.
The UI gain hits/runs count evidence, not events or model accuracy.
Native overlapping capture and denoising are deferred until gain QA results.
