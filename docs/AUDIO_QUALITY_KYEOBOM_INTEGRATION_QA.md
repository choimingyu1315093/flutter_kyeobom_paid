# HomeCamera — Kyeobom UI + natural audio quality integration

QA branch: `feature/audio-quality-kyeobom-integration-20261115`
Functional base: `feature/station-audio-auto-dual-landscape-20261115`
Design source: `feature/kyeobom-ui-20261115` (local worktree may be named
`flutter_home_camera_design`).

## Changes

### Sound quality (audio-only WebRTC connection)

The station-side microphone previously used `getUserMedia(audio:true)`
with Android/iOS default telephony-oriented audio processing. Such processing
can sound compressed/pumping on faint room noises and breath sounds.

- Requests optional disabling of echo cancellation, automatic gain control,
  noise suppression, high-pass and typing-noise detection where supported.
- Opus offer includes `maxaveragebitrate=48000`, `useinbandfec=1`, and
  `usedtx=0`. This allows higher-quality continuous room sound and
  error resilience, but bitrate and FEC effectiveness depend on transport,
  actual codec negotiation and the operating system.
- If device audio capture rejects the optional constraints, fall back to the
  previously working audio capture parameters.
- If modified Opus SDP is rejected, fall back to the original offer.
- NO video-peer SDP/ICE code changes. No paid service, new user-facing
  modes, amplification, recording, or extra microphones.
- Not a guaranteed cure for **physical mic distortion**, speaker damage,
  acoustic interference, network congestion, or low-grade hardware.
- Since suppression is weaker, environmental hiss/fan noise may increase.
  Compare on the same device/volume/network to assess the tradeoff.

### UI

From the Kyeobom design-only branch:
- `lib/kyeobom_design.dart`: theme, palette, vector preview logo, reusable UI.
- `lib/kyeobom_screens.dart`: dark station and live-view presentation.
- `lib/remote_control.dart`: ONLY replaced login UI; Firebase Auth and remote
  signaling methods stay on the functional branch implementation.
- `lib/main.dart`: applied Kyeobom theme and role screen; wired the
  station/viewer presentation widgets while preserving state and camera,
  audio, auto-mic, dual-landscape and pinch gesture behavior.
- The station waiting view retains **실시간 보기 시 거치폰 마이크 자동 켜기**,
  the privacy default (OFF), and station-only manual ON/OFF during viewing.
- The landscape live video still fills behind safe insets; controls remain
  inside the safe area, and both landscape sides can rotate.
- Current logo is the design branch's vector prototype, not a final app icon.

## No changes

- No Firestore security rules changes or extra required Firebase setup.
- No application feature changes to payments/ads/etc.
- No merge to `main` or either source branch.

## Commands

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/feature/audio-quality-kyeobom-integration-20261115
flutter pub get
flutter analyze
flutter test
flutter run -d RFCT3225GCZ
# Detach with 'd' (do not quit station), then run on iPhone:
flutter run -d 00008130-001250C81AF3803A
```

If switching is prevented by local Xcode/FlutterFire changes, preserve those
files. DO NOT hard reset or discard project signing configuration.

## Verification

1. Kyeobom login, role screen, station waiting design, viewer start/stop UI.
2. Station waiting app remains dark; camera/mic OFF and screen stays awake.
3. Verify station auto-mic opt-in persists and is OFF in waiting state.
4. Start viewer: actual live video appears, correct landscape fill, pinch 1–4x,
   physically rotate viewer 180° and verify orientation of every control.
5. In the station room, play a constant low-volume voice/soft baby-like sound
   at fixed distance (NOT near an actual sleeping baby). Compare how it sounds
   at the viewer using the same network and phone volume against the
   previously working `feature/station-audio-auto-dual-landscape-20261115`.
6. Listen for the previous muffled/pumping/crackling and new background hiss,
   and verify no audio dropouts, echoes, feedback or sudden clipping.
7. Station mic off: viewer audio stops but video continues.
8. Viewer stop: station mic/camera OFF; return to portrait.
9. Test Android station→iPhone viewer and iPhone station→Android viewer.
10. Repeat 3 start/stop cycles and test once with mobile data vs Wi-Fi.
    STUN-only means some cross-network links will fail until TURN is added.

## Safety boundaries

- Same-account pairing and stored SDP/ICE are still proof-of-concept.
- Mic is disabled while waiting and capture is not recorded. Never assume
  connection will always stay available; do not rely on this as a guaranteed
  baby-safety monitor.
- Real-device quality is subjective and not verifiable by `flutter test`.
