# P3.2: horizontal video framing and station microphone

Branch: `feature/landscape-video-station-mic-20261115`  
Base: `fix/auto-landscape-video-recovery-20261115` (the user's verified video-only session).

## What changed

1. After the viewer presses `실시간 보기 시작`, the viewer page still enters landscape automatically.
2. If incoming WebRTC frame dimensions indicate a portrait frame
   (`videoHeight > videoWidth`) in the viewer's landscape layout, its pixels
   are automatically rotated clockwise by 90° using Flutter `RotatedBox`.
   Already-landscape or unknown frames are not rotated. No manual rotate button.
3. Original 1x–4x pinch/zoom/pan/reset controls remain.
4. On the **station**, while a live video session is active, `마이크 켜기`
   and `마이크 끄기` become available.
5. The microphone is OFF while idle. When the user at the station taps ON,
   microphone permission is requested and an **independent, audio-only WebRTC
   connection** is started for the same session.
6. The viewer automatically receives audio from this independent connection.
   The viewer microphone is not used. No recording is performed.
7. OFF, stream stop, app background, or station leaving attempts to stop
   the audio tracks, release audio resources and update Firestore.

**Important:** This is an initial implementation. Real-device audio playback
and orientation direction still require QA. This implementation keeps
`lib/webrtc_session.dart` identical to the validated video-only version.

## Firebase

No Firestore security rule changes. Separate audio offers/answers and ICE
candidate arrays are fields in the existing owner-protected
`homecamStations/{uid}/sessions/{id}` document.

## First build

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/feature/landscape-video-station-mic-20261115
flutter pub get
flutter analyze
flutter test
```

If Git refuses to switch due to local FlutterFire or iOS signing changes:
do not use `git reset --hard`; preserve local changes first.

Full rebuild required on **both devices**, because Android RECORD_AUDIO and
iOS NSMicrophoneUsageDescription were updated.

```bash
flutter run -d RFCT3225GCZ
# detach via 'd', keep app foreground on the Android station
flutter run -d 00008130-001250C81AF3803A
```

## Manual QA

1. Android station, iPhone viewer. Start video as previously validated.
2. Confirm the viewer page and image both show a horizontal picture, not
   a narrow sideways portrait strip. Tap zoom and pinch from 1x to 4x.
3. Confirm the station microphone is OFF by default and Android shows no
   microphone-in-use indicator when video alone is active.
4. While streaming, tap `마이크 켜기` **on the station**; grant OS permission.
   Confirm the microphone indicator appears and viewer plays sound from
   the station. If no audio is heard, record station and viewer status texts.
5. Tap `마이크 끄기` on the station; confirm indicator disappears, audio
   stops, and **video stays connected**.
6. Repeat audio ON/OFF three times, end live video and confirm no camera or
   microphone capture remains.
7. Reverse roles (iPhone station, Android viewer) and repeat.
8. Background or leave station while mic is on; verify both camera/mic stop.

## Known limitations

- A portrait camera that is *intentionally held upright* may also be rotated
  when the viewer is landscape: dimensions alone cannot infer scene content.
  If this proves common, we need explicit station video orientation metadata.
- Clockwise 90° is the initial correction for the reported screenshot. Confirm
  which direction makes floor/walls upright on both phones.
- Audio uses a second WebRTC peer and STUN-only networking; independent
  audio ICE may fail on some NATs even while video works. TURN remains planned.
- Station mic permission requires a person on the station device to approve.
- Same-account auth is still the test-only pairing model; proper device-bound
  pairing and rules are a separate release requirement.
- No media persistence or recording.

## Error logging

If audio or orientation fails, share `flutter analyze`, `flutter test`,
station's mic status and viewer's top overlay status. For deeper capture:

```bash
flutter run -d RFCT3225GCZ 2>&1 | tee ~/Desktop/homecamera_android_audio.log
flutter run -d 00008130-001250C81AF3803A 2>&1 | tee ~/Desktop/homecamera_ios_audio.log
```
