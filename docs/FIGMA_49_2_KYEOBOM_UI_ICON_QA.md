# 켜봄 — Figma 49:2 디자인 및 앱 아이콘 QA

Branch: `feature/figma-49-2-kyeobom-appicon-20261115`
Functional base: `feature/audio-quality-kyeobom-integration-20261115`

## Design source

Provided by user: Figma overview screenshot, with frames:
1. 시작 및 로그인
1-1. 계정 만들기
1-2. 비밀번호 찾기
2. 기기 역할 선택
3. 홈캠 대기 화면
4. 홈캠 보기 홈
5. 실시간 보기 (가로 모드)

**Important:** The Figma connector returned a tool-call quota error. We used
the user's actual overview screenshot, but individual frames are only about
100px wide in that overview; tiny typography/icons cannot be read exactly.
The implementation follows its visible structure, dark navy/blue accents,
light cards, near-black waiting state, and landscape video UI without
claiming pixel-perfect reproduction of inaccessible vector assets.

## Preserved functional behavior

- Firebase account sign-in remains `RemoteControl.instance.signIn`.
- Added separate **email sign-up** and **password reset** UI; the latter calls
  `FirebaseAuth.instance.sendPasswordResetEmail`.
- Existing same-account prototype pairing, camera streaming, audio quality,
  station auto-mic consent/storage, audio ON/OFF, zoom, orientation and
  screen wakelock are unchanged.
- Verified video peer code `lib/webrtc_session.dart` unchanged; audio peer
  `lib/audio_session.dart` unchanged; Firestore rules unchanged.
- UI screens reflect live transport state; portrait viewer remains a
  dashboard, landscape remains full-bleed live video.

## Device app name

- Android: `android/app/src/main/AndroidManifest.xml` label **켜봄**.
- iOS: `ios/Runner/Info.plist` CFBundleDisplayName/CFBundleName **켜봄**.
- Flutter MaterialApp title also **켜봄**.
- Package IDs and Firebase configuration unchanged.

## Apply the user's original icon (local Mac step)

Screenshots of Finder do **not** contain the raw image bytes. To use the
actual `app_icon_real.png` from Mac Downloads, run:

```bash
cd ~/Flutter/flutter_home_camera
bash tools/apply_kyeobom_icons.sh
```

The script first tries `~/Downloads/app_icon_real.png`, then scans
`~/Downloads` up to four folder levels (including an `AppIcons` folder).
If the file has another location, pass its real PNG path:

```bash
bash tools/apply_kyeobom_icons.sh "$HOME/Downloads/AppIcons (6)/app_icon_real.png"
```

Only use that second command if the example path exists.
The script copies the actual PNG into Flutter's asset directory, generates
Android launcher bitmap density variants and a flattened, opaque iOS
AppIcon.appiconset (18 images).

The generated binary images are on the user's Mac. They cannot be committed
by the GitHub connector until uploaded or pushed from that computer.

## Pull and smoke test

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/feature/figma-49-2-kyeobom-appicon-20261115

bash tools/apply_kyeobom_icons.sh

flutter pub get
flutter analyze
flutter test
flutter run -d RFCT3225GCZ

# use 'd' to detach without terminating station;
# then run the same branch on iPhone:
flutter run -d 00008130-001250C81AF3803A
```

If `git switch` fails due to locally edited FlutterFire settings, do not
run `git reset --hard`. Back up local files and reconcile the conflict.

## QA checklist

- Login layout: real logo/wordmark, email/password, login, signup/reset links.
- Sign-up and reset screens visible; do not test with a disposable
  email that you do not own.
- Device selection offers station vs viewer; the start-waiting dialog
  continues to show the three required Korean sentences.
- Black station standby: camera/mic OFF, screen remains awake, auto-mic
  preference still works and persists on station phone.
- Viewer dashboard styled in Figma light/navy system, starts real live view.
- Landscape live screen fills, audio from station only, zoom/pinch/pan/stop,
  180-degree device flip all work.
- Exit returns to portrait and station closes camera/microphone.
- Compare actual launcher icon on Android/iPhone home screen to original
  `app_icon_real.png`; if icon does not refresh, uninstall/reinstall
  only after preserving local app data as needed.
- Test Android station -> iOS viewer and reverse; compare natural sound
  against previous passing build.

**Status:** Source committed; Flutter analyzer, widget tests, real icons,
device screenshot comparison, and final QA must be run on the user's Mac.
