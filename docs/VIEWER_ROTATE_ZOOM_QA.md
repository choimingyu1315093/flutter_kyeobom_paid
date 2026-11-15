# Viewer rotation and digital zoom QA

Only the viewer's presentation layer changes. No Firebase rules, pairing,
WebRTC signaling, station camera settings, or native permissions are changed.

## Controls

- **영상 90도 회전:** rotates incoming video clockwise (0° → 90° → 180° → 270° → 0°).
  Rotation resets pan/zoom to 1.0x to avoid cropping old focus regions.
- **확대 / 축소:** 1.5x steps, bounded to 1.0–4.0x.
- **Pinch:** two-finger pinch to zoom (up to 4x).
- **Pan:** move the zoomed image with one finger.
- **회전 및 확대 초기화:** restore 0° rotation, 1.0x zoom and center.
- Actual source-camera optical zoom and physical pan/tilt are **not** changed.
- Device autorotation is controlled by iOS/Android orientation settings.
  The 90° control rotates the received video even while the phone stays still.

## Commands

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git switch feature/p0-core-homecam-20261114
git pull --ff-only origin feature/p0-core-homecam-20261114
flutter pub get
flutter analyze
flutter test
flutter run -d RFCT3225GCZ
# On the other connected device:
flutter run -d 00008130-001250C81AF3803A
```

## Manual acceptance

1. Establish video using iPhone as viewer and Android as station.
2. Ensure 0° / 1.0x initially; view video without cropping or stretching.
3. Tap rotate repeatedly; image rotates 90°, 180°, 270°, then 0°.
4. Tap zoom in/out and pinch (1.0–4.0x); pan the enlarged video.
5. Tap reset; confirm 0° and 1.0x with video centered.
6. End/restart live session; confirm incoming video renders and station
   camera still shuts off after closing.
7. Reverse roles (Android viewer, iPhone station) and repeat.
8. Check portrait/landscape viewer rotation with OS auto-rotate on/off.

## Notes

Digital zoom may pixelate: the sender currently transmits roughly 720p.
UI controls appear only while viewer WebRTC session is active.
The existing STUN-only connectivity limitations still apply.
