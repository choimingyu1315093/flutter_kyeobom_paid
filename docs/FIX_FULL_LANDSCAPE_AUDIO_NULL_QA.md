# P3.3 QA — true landscape video and audio null-stream fix

Branch: `fix/landscape-fill-audio-null-20261115`
Parent: `feature/landscape-video-station-mic-20261115`

## Root cause of the shown audio exception

The viewer called `RTCVideoRenderer.muted = false` **before** assigning
`srcObject`. The flutter_webrtc native implementation throws the exact
message shown by the user: "Can't be muted: The MediaStream is null". It
also doesn't support setting `muted` on a remote track. The property write
has been removed; playback only attaches the received audio stream and
routes sound to the speaker.

## Landscape video behavior

- When the viewer starts streaming, the **viewer screen** enters landscape.
- The actual remote video pixels are rotated clockwise by 90 degrees in
  landscape, independent of unreliable width/height reports.
- `RTCVideoViewObjectFitCover` fills the rotated view instead of showing
  giant black bars. This **crops** edges when aspect ratios differ.
- Video is **edge-to-edge**, including behind display cutout/safe areas,
  while back/stop/status buttons stay inside safe areas.
- Zoom and pinch controls remain available; no manual rotation button.
- Stopping stream or leaving viewer restores the viewer orientation.

## Build and QA

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/fix/landscape-fill-audio-null-20261115
flutter pub get
flutter analyze
flutter test
flutter run -d RFCT3225GCZ
# press 'd' to detach (not 'q') and then run on iPhone:
flutter run -d 00008130-001250C81AF3803A
```

1. Ensure both devices have this build and log in with the existing
   test account.
2. Android station -> iPhone viewer. Press **실시간 보기 시작**. Verify the
   **actual scene** (floor, box text, ceiling) is upright and fills the
   available horizontal screen. Confirm no large black side bars.
3. Zoom/pinch 1x–4x; pan and reset. Verify no accidental manual rotate UI.
4. Station: **마이크 켜기**, grant permission; viewer should no longer show
   the null-MediaStream exception. Verify real audio is audible, not only
   ICE-connected text.
5. Station: **마이크 끄기**. Verify viewer stops hearing audio while video
   remains live and station mic indicator disappears.
6. Stop video; verify automatic portrait restore and no camera/microphone
   indicators on station.
7. Reverse roles iPhone station -> Android viewer; repeat steps 2–6.

**Important:** if scene is upright but important edges are cropped, this
is the expected trade-off of `Cover`. If scene appears 90° the wrong way
in a given station orientation, record which role/physical orientation;
the current default rotates clockwise to match the screenshots supplied.
Physical scene orientation cannot be inferred reliably from frame pixel
width and height alone.

## Status

Source changes pushed; real-device Flutter analyze/test and audio playback
still need verification. Current pairing, TURN and other P3 limitations remain.
