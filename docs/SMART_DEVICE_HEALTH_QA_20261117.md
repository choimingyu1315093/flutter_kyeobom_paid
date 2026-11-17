# Smart Device Health — QA handoff (2026-11-17)

Branch: `feature/smart-device-health-20261117`
Base: `feature/ad-revenue-full-optimization-20261115`

## Implemented
- Native Android: battery percent, charging, OS thermal severity, Wi-Fi/cellular/offline.
- Native iOS: battery percent, charging, ProcessInfo thermal severity, NWPathMonitor network status.
- Station publishes telemetry every 45 seconds to `homecamStations/{uid}/telemetry/health`.
- Viewer home displays station battery, charging, thermal, network, last-seen and stale/offline status.
- Thermal warning on station (not yet automatic throttling). No camera/microphone capture in health collection.
- Telemetry failures are isolated from existing WebRTC session.

## Important limitations
- No background push notification for disconnected station; viewer dashboard only.
- No automatic camera quality throttling or thermal shutdown yet.
- Firestore station document uses same-account pairing; multiple stations per account are not isolated.
- Telemetry is written while station screen is active; iOS background execution is not guaranteed.
- User-reported iPhone release build succeeded. User's Android log confirms release APK built and installed successfully (2026-11-17); runtime behavior is not yet verified. Network disconnect recovery and extended thermal soak test NOT run in this environment.
- Do not merge before those issues are addressed and QA is approved.

## Local QA
```bash
cd ~/Flutter/flutter_home_camera
git fetch origin
git switch feature/smart-device-health-20261117
git pull --ff-only origin feature/smart-device-health-20261117
flutter pub get
flutter analyze
flutter test
flutter run
```
Check both iOS and Android as station/viewer, charging unplug/plug, Wi-Fi/cellular/offline, station exit, foreground/background, 2h heat, live video and audio regression.

## 2026-11-17 widget-test regression fix
- Submitted log: `flutter test` +35/-5; all five failures were Firebase `[core/no-app]` at `DeviceHealthCard` during isolated layout tests.
- `DeviceHealthCard` now avoids Firestore when Firebase/auth is unavailable; added a no-Firebase regression widget test.
- Cached telemetry stream and added 15-second local stale-heartbeat recheck so the viewer eventually shows a disconnected station without needing a new Firestore event.
- Please rerun `flutter analyze`, `flutter test`, Android and iOS functional QA. CI/device results after this patch are not yet available.

## 2026-11-17 telemetry permission root cause and deployment gate
- Verified code writes `homecamStations/{uid}/telemetry/health`.
- Repository `firestore.rules` previously had explicit rules for `sessions` but **no `telemetry` subcollection match**.
- Firestore security rules for parent documents do not inherit to subcollections. With those rules deployed, the status write/read is denied.
- Fixed on this branch by adding an explicit owner-only `match /telemetry/health { allow read, write: if isOwner(); }` nested under `match /homecamStations/{uid}`.
- Station health sync now surfaces `permission-denied` separately rather than silently ignoring all Firebase errors; viewer shows an access-error notice.
- **Deployment not done by GitHub commit.** This repository has no `firebase.json` or `.firebaserc`. The project's live Firestore rules were not inspected/deployed from this environment.
- Before QA, Firebase console -> project HomeCamera -> Firestore Database -> Rules: review the current rules. Merge just the new telemetry block under `homecamStations/{uid}`; preserve any other live rules, then Publish. Do NOT replace current production rules wholesale from this repository if they have diverged.
- Re-run `flutter test` and Android/iOS QA, and verify `homecamStations/{uid}/telemetry/health` exists and its `lastSeen` changes every ~45s.
- Even after status transmission is fixed, automatic thermal throttling and background disconnect push alerts remain unimplemented, so Smart Management is NOT feature-complete.
