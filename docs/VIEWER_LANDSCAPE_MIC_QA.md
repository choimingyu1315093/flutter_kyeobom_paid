# P3.1 landscape viewer + optional one-way audio

Branch: `feature/viewer-landscape-microphone-20261115`, based on validated P3.

## Changes
- **Removed:** manual 90-degree *image* rotation (no pixel rotations).
- **Added:** viewer `가로 보기` forces device landscape; `자동 회전` restores system behavior.
- Auto-rotate by physically rotating the device works when the OS permits it.
- In landscape, the live video occupies the screen and controls overlay the picture.
- Preserved pinch-to-zoom, pan, + / − and reset (1x–4x).
- **Added (prototype):** viewer `소리 듣기` remotely enables the **station microphone** to monitor ambient sound. No talk-back / viewer microphone transmission.
- Default mic is OFF; no mic capture happens during station idle or video-only sessions.
- Station has an explicit optional `마이크 권한 미리 허용` action. Permission is requested, then capture is **immediately stopped**.
- Audio m-line is negotiated in advance, then station uses sender `replaceTrack` to attach/detach capture without SDP renegotiation.
- When leaving live view, backgrounding, or ending WebRTC, all microphone tracks are stopped and disposed.

## Test sequence

1. In station phone (e.g. Android), update to this branch and build afresh.
2. From station waiting screen, tap **마이크 권한 미리 허용 (선택)** and grant OS permission.
   The screen must say `마이크 권한 준비 완료 · 현재 마이크 OFF` afterward.
3. On viewer phone (e.g. iPhone), run same branch, same test Firebase account.
4. Start live viewing. Confirm video **still works and microphone is OFF**.
5. Physically rotate viewer sideways with OS auto-rotate enabled. Verify wider live video. If phone auto-rotate is locked, tap `가로 보기` and verify landscape. Tap `자동 회전` to restore.
6. Confirm there is **no video 90° rotation button**, and pinch-to-zoom (1–4x), pan, +, −, and reset still work.
7. Tap `소리 듣기`. Verify `거치폰 마이크 ON` on station and `거치폰 소리 수신 중` on viewer. Verify sound is audible on viewer speaker.
8. Tap `마이크 끄기`. Confirm station displays OFF and microphone permission indicator disappears. Verify audio stops, but video continues.
9. End session. Confirm camera and mic indicators disappear; no audio remains captured.
10. Swap station/viewer roles (iPhone station / Android viewer) and repeat.
11. Repeat ON/OFF 10 times, including orientation changes while streaming.

## Commands

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/feature/viewer-landscape-microphone-20261115
flutter pub get
flutter analyze
flutter test
flutter run -d RFCT3225GCZ
# After detaching the Android debugger with 'd', launch on iPhone:
flutter run -d 00008130-001250C81AF3803A
```

Important: if `git switch` refuses due to local FlutterFire project changes,
do NOT use `git reset --hard` or overwrite local `firebase_options.dart`
or signing settings. Back up your changes and report the conflict.

## Important limits

- Both phones still share a test email account. No proper QR pairing/revocation yet.
- Microphone permission dialogs require *station-side* human confirmation at first use; an unattended station cannot automatically approve an OS permission prompt.
- Some iOS/Android devices may route remote audio differently. Test speaker playback, `replaceTrack` behavior, and the remote mic indicator explicitly.
- STUN-only: cross-carrier connectivity is not guaranteed; TURN and reconnect remain pending.
- Rotation and zoom only change display; station camera physical rotation or optical zoom are not modified.
- No audio recordings, persistence, or two-way talk are implemented.
