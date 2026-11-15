# P3 WebRTC live-view QA (2026-11-15)

## Scope

This milestone adds *video-only* WebRTC streaming from a foreground station to a
viewer. No audio and no recording. Firebase is used for owner-authenticated SDP
and ICE signaling; live video is never written to Firestore.

This is an **engineering prototype**, not production-ready pairing.

## Prerequisites

1. Keep the existing HomeCamera Firebase configuration from `flutterfire configure`.
2. Enable Firebase Authentication Email/Password, as already tested in P2.
3. In Firebase Console > Firestore Database > Rules, publish the **updated**
   `firestore.rules`. P2 rules do not allow the new session subcollections.
4. On each device, sign in with the **same test account** as in P2.
5. Station device must be kept unlocked, charged, and app in the foreground.

## Build and test commands

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git pull --ff-only origin feature/p0-core-homecam-20261114
flutter pub get
flutter analyze
flutter test

flutter run -d RFCT3225GCZ
# Switch devices after installation:
flutter run -d 00008130-001250C81AF3803A
```

Since `flutter_webrtc` is a native plugin, perform a full rebuild, not hot reload.

## Two-device verification

1. Android as station: open "거치폰 · 카메라 대기"; approve waiting-mode notice.
   Camera should stay **OFF** while waiting.
2. iPhone as viewer: open "뷰어폰 · 실시간 보기"; tap "실시간 보기 시작".
3. Confirm the Android camera indicator turns on and the live image appears
   on the iPhone. Status messages should progress through offer/answer/ICE.
4. Tap "실시간 보기 종료": image should disappear and Android camera indicator
   should turn off.
5. Repeat with **iPhone as station / Android as viewer**.
6. Repeat start/stop several times without restarting the apps.
7. Background the viewer while streaming. Station should stop streaming; if
   the viewer is forcibly killed, the station heartbeat watchdog attempts to
   stop the stream within ~45–55 seconds in a healthy foreground app.

Try both phones on the same Wi-Fi first. After this passes, test Wi-Fi vs
mobile data. STUN-only connections can fail on carrier-grade NAT: this is a
known limitation, not evidence that Firebase is broken.

## Current limitations

- STUN-only; **TURN credentials and fallback are not yet provided**.
- Both phones share a test account. Replace with QR pairing, scoped permissions,
  revocation, and device-bound authorization before production.
- `onlineHint` is best-effort only; not an authoritative online presence.
- Candidate docs accumulate under `homecamStations/{uid}/sessions/{id}`.
  Add TTL/cleanup and rate limits before public testing.
- The watchdog depends on the foreground station app's lifecycle/timers; it
  does not replace actual long-duration Android/iOS device QA.
- No automatic reconnect/re-offer after a broken ICE connection.
- iOS does not support guaranteed locked/background camera activation.

## Failure triage

- `permission-denied`: ensure latest Firestore rules are published.
- `no camera` / permission error: inspect OS camera permission.
- `ICE failed` with successful answer: retry on same Wi-Fi; TURN is likely
  needed for cross-network reliability.
- iOS Swift Package Manager build failure: copy the exact Xcode error log,
  keep locally generated FlutterFire files; do not hard reset the repo.
