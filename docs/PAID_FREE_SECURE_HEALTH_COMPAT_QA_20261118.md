# Paid / Free secure pairing + device health compatibility QA

2026-11-18 · Branch: `paid/free-secure-health-compat-20261118`

## Scope
Source: free secure pairing/recovery branch (2026-11-17) plus the 2026-11-18 account branch's iOS Auth-realm guard and read-only entitlement rules.

- Free repo `flutter_home_camera`: untouched
- Paid integrated baseline, parallel subscription branch: untouched
- Production Firestore rules and Functions: **NOT deployed**
- Paid app: anonymous station identity; separate approved email viewer; QR pairing/recovery; HD fallback/reconnect plus paid health controls and FCM
- Health telemetry: station writes, approved viewer reads
- FCM devices: viewer's Auth UID-scoped token, server compares station.viewerUid before sending. Stale viewers excluded.
- Android Firebase native options generated via Google Services plugin and local `google-services.json`; iOS uses local `GoogleService-Info.plist`. Both are gitignored.

## Mac QA commands

```bash
cd ~/Flutter/flutter_kyeobom_paid
git status --short
git fetch origin
# Back up/stash tracked local changes BEFORE switching; NEVER hard reset
git switch --track origin/paid/free-secure-health-compat-20261118
flutter pub get
flutter analyze --no-fatal-infos
flutter test

cd functions
npm install
npm run check
cd ..

cd tools/paid_security_rules
npm install
cd ../..
bash tools/paid_security_rules/run_emulator_tests.sh
```

The security suite uses a dedicated demo Firebase project and port 8281; it does not publish rules.

For Android/iPhone pairing QA WITHOUT production writes:

```bash
# terminal 1: trusted private Wi-Fi ONLY
bash tools/paid_security_rules/run_device_qa_emulators.sh

# separate terminals, one per connected device:
flutter run -d <DEVICE_ID> --debug \
  --dart-define=KYEOBOM_USE_FIREBASE_EMULATORS=true \
  --dart-define=KYEOBOM_EMULATOR_HOST=<MAC_LAN_IP>
```

Test: anonymous station creation -> QR claim/approval -> real-time video/audio -> health telemetry and viewer card -> devices/authUid token registration -> revocation -> previously approved viewer denied -> role swap Android/iPhone. Production FCM push delivery is NOT emulated.

## Production gate and rollback
Do not deploy this branch's `firestore.rules` or `functions/index.js` yet. Compare the live published rules and confirm account entitlement/QR permissions remain intact. The paid Functions source contains only `notifyOnHealthChange`, not the free account/subscription Functions. **Never run a blanket Functions deployment from the paid directory**: it may offer to delete other deployed functions. A later approved health-only deploy must target `functions:notifyOnHealthChange` and be checked with a rollback plan.

Unverified: Mac Flutter tests/build, emulator rules QA, actual deployed rules, two-device pairing + health push. Event recording starts only after these gates pass.
