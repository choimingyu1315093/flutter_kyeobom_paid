# HomeCamera — Station-origin baby audio and dual-landscape viewer QA

Development branch: `feature/station-audio-auto-dual-landscape-20261115`
Parent: `fix/landscape-fill-audio-null-20261115` (user-reported working AOS/iOS)

## What is the microphone source?

- **Station:** `StationMicrophone.enable()` is the ONLY code that calls
  `getUserMedia({'audio': true, 'video': false})` to capture microphone input.
  It uses the station phone's built-in microphone.
- **Viewer:** `ViewerAudio` listens on an independent WebRTC peer; it never
  calls `getUserMedia`. Received audio plays through its speaker/headphones.
- No viewer microphone capture, talk-back, or recordings.
- No physical mic stays active while waiting in dark mode.

## Unattended baby monitoring

1. With the **station phone physically available**, open station role.
2. In the waiting screen, turn ON
   **실시간 보기 시 거치폰 마이크 자동 켜기**.
3. Grant the **station's** system microphone permission on the first switch.
   Capture is immediately released after this permission step.
4. Leave the station in its foreground dark waiting mode, connected to power.
5. From the **viewer phone**, start live view remotely. Only now the station
   opens its microphone and starts the separate audio-only peer.
6. Hear room/baby audio from the viewer speaker; the viewer microphone
   is never accessed.
7. Stop live view. Station camera and microphone must turn OFF.
8. The preference is stored **locally on that station device** and defaults
   to OFF on a new installation. Toggling it OFF while waiting disables
   future automatic capture.

The existing **거치폰 마이크 켜기 / 끄기** button remains available on the
station during an active video session for manual control.

## Dual landscape orientation

Before: viewer locked to `landscapeLeft`, so physically turning 180° left
controls upside down. Now: both `landscapeLeft` and `landscapeRight` are
accepted during live viewing, which lets Android/iOS rotate the whole viewer
UI. Native platform channel `getViewerLandscapeSide` reports the actual
display/UI orientation; viewer switches video correction from quarter-turn
1 to quarter-turn 3. Pinch zoom, pan, 1–4x buttons remain unchanged.

The physical OS rotation-lock control may prevent automatic switching
between two landscape sides. Enable the device's auto-rotate if this occurs.

## Commands

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/feature/station-audio-auto-dual-landscape-20261115
flutter pub get
flutter analyze
flutter test

# Install/run on Android
flutter run -d RFCT3225GCZ
# Hit 'd' (detach) to keep the station app alive, not 'q'.
# Install/run on iPhone
flutter run -d 00008130-001250C81AF3803A
```

Full native rebuild on both devices: `shared_preferences` added, and
native Android/iOS method channels updated.

If git refuses to switch due to local FlutterFire/signing modifications,
DO NOT reset hard or discard these settings; back up and reconcile safely.

## Manual acceptance checklist

1. Android as station, iPhone as viewer. Station dark waiting screen:
   verify **camera OFF / mic OFF** even after enabling the auto-mic setting.
2. Viewer starts live video. Confirm the station microphone indicator switches
   ON and the viewer hears actual station room sounds. Clap/talk **near
   the station** while the viewer is in a quiet different room to prove
   correct audio source. The viewer OS microphone permission indicator must
   NOT appear.
3. Start/stop live view twice; camera/microphone must turn off after stop and
   reactivate only during viewing.
4. Physically rotate the viewer phone **180° from one landscape orientation
   to the opposite**. Buttons, status label, pinch controls and video must
   remain upright and in their correct relative positions.
5. Test +/- zoom, pinch, pan and reset in both landscape positions.
6. Station during viewing: press **거치폰 마이크 끄기**; viewer audio stops
   but the video remains active. Press **거치폰 마이크 켜기** to resume.
7. Reverse roles (iPhone as station, Android as viewer) and repeat.
8. Remove app from foreground on station; verify capture stops.
9. Turn auto-mic preference OFF and repeat live view: **video works, mic OFF**
   until manually enabled on station.

## Limitations

- Test-only same-email Firebase authentication; production device pairing
  and access revocation are not implemented.
- STUN-only peers: audio and video may connect differently on restrictive
  mobile networks without TURN.
- Android 16 tablets/large displays can limit forced orientation; rotation
  lock on iOS/Android may prevent physical auto-rotation.
- Real-device Android/iOS audio source, speaker playback, and orientation
  response need to be verified; code inspection and unit tests are not
  real-device proof.
