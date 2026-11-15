# Fix: automatic landscape on live view and WebRTC video recovery

Branch: `fix/auto-landscape-video-recovery-20261115`

## Why this separate branch?

The user already confirmed both iPhone/Android streaming directions worked on
`feature/p0-core-homecam-20261114`. The next branch added an untested audio
transceiver and altered the proven SDP offer/answer, after which live view stopped
working. Without device logs we cannot prove which audio operation caused the
failure.

This fix restores the **exact proven P3 WebRTC signaling code** for video while
retaining the viewer's pinch zoom/pan controls and replacing manual landscape
controls with **automatic landscape on Start**.

**Important:** the microphone controls and capture are temporarily disabled in
this recovery branch. The prior work is preserved in
`feature/viewer-landscape-microphone-20261115`; the microphone must be
reintroduced in a follow-on isolated audio session or another regression-tested
design, without impacting the working video SDP.

## Behavior

- On the viewer page, tap **실시간 보기 시작**.
- After submitting the live request, the viewer forces landscape orientation
  (`landscapeLeft`) and uses the landscape full-screen layout.
- Ending the stream restores portrait first and then returns orientation
  preference control to the OS.
- Leaving the viewer page also releases any forced orientation.
- No **가로 보기**, **자동 회전**, or **영상 90도 회전** button.
- The zoom/pinch/pan gestures (1x–4x), plus/minus, reset are retained.
- Firebase sign-in, Firestore rules, room signaling, video camera control,
  and station waiting mode are not changed.

## Commands

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/fix/auto-landscape-video-recovery-20261115
flutter pub get
flutter analyze
flutter test
flutter run -d RFCT3225GCZ
# On iPhone, after installing both phones with this build:
flutter run -d 00008130-001250C81AF3803A
```

If `git switch` fails due to local FlutterFire or iOS signing changes:
stop and back up local modifications before reconciling; do not use
`git reset --hard`.

## Acceptance

1. Install this same branch build on both phones. Confirm the station is
   foreground in waiting mode, with the camera OFF.
2. Android station -> iPhone viewer: press **실시간 보기 시작**, verify viewer
   turns sideways automatically (do not use an orientation button), then
   live video appears.
3. Pinch-to-zoom, pan, plus/minus, reset all still work at 1x–4x.
4. Press **실시간 보기 종료**: viewer returns to portrait and station camera OFF.
5. Swap roles: iPhone station -> Android viewer, repeat.
6. Repeat connection and end 5 times, including leaving the viewer screen.
7. Confirm mic is not accessed during station idle or streaming.

## Failure triage

- If the station camera stays OFF: note both devices' on-screen status strings
  and collect Flutter logs. Check latest request in Firestore.
- If station camera ON but viewer video blank: report viewer's last status
  (ICE state/onTrack) and platform details; first retry on same Wi-Fi.
- If the viewer screen refuses to rotate on iPhone: report model/OS and whether
  portrait orientation is locked by the system; iOS platform restrictions can
  affect forced orientation.
- No TURN server is configured: some cross-network connections will fail.

## Scope

This branch fixes the **video regression path** by rollback; runtime proof
still requires real-device QA. It does not claim that the precise cause of
the regression has been established without logs.
