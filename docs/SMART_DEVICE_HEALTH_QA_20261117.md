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
- Android/iOS real-device builds, network disconnect recovery and extended thermal soak test NOT run in this environment.
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
