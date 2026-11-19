# P1 candidate cry classification — local QA, not release

P0 user-reported acceptance: 47/47 Android station and 47/47 iPhone station,
including QR, live AV, event MP4, foreground/background, and 30-minute runs.
P0 automatic UI regression: restore correct standby audio-transmission OFF copy.
P1 remains opt-in using `--dart-define=KYEOBOM_CRY_QA=true` at build time.
The existing general sound detector and 90-second cooldown are independent.

The official Google YAMNet model maps class 20 to Baby cry, infant cry.
One 975ms mono window is resampled to 16kHz and evaluated on a single CPU
thread in an isolate. A 0.45 starting score threshold and two positive
windows among the last five valid predictions within six seconds
are QA parameters, not calibrated probabilities or accuracy claims.
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
