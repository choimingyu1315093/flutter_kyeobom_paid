# 켜봄: 대기 시작 팝업 리디자인 + iPhone 첫 오디오 재생 초기화

브랜치: `fix/station-dialog-ios-first-audio-20261115`

기준 브랜치: `feature/figma-49-2-kyeobom-appicon-20261115`

## 1. 홈캠 시작 팝업

- 기본 Material `AlertDialog` 대신 네이비·블루 디자인 토큰을 사용하는
  `showKyeobomStationStartDialog`를 추가했습니다.
- 안내 카드 두 개(어두운 화면, 충전기·앱 실행 유지), 프라이버시 안내,
  명확한 두 버튼(취소, 대기 시작)을 사용합니다.
- 사용자가 정한 **세 가지 정확한 안내 문구**와 `true/false` 반환값은
  그대로 유지합니다. 기존 카메라·마이크·대기 동작은 변경하지 않았습니다.

## 2. iPhone 첫 뷰어 오디오 재생 문제

재현 보고:
1. 첫 실행: **Android 거치폰 → iPhone 뷰어폰** = 영상 정상/소리 없음.
2. 역할 교차: **iPhone 거치폰 → Android 뷰어폰** = 소리 정상.
3. 다시 교차: **Android 거치폰 → iPhone 뷰어폰** = 소리 정상.

정확한 네이티브 오류 로그가 없으므로 원인 확정은 아니지만,
iPhone이 거치폰으로 동작할 때 최초 마이크 캡처가 Apple 오디오
세션을 활성화하고, 이후 뷰어의 수신 오디오까지 정상화하는
초기화 순서 문제가 유력합니다.

`ViewerAudio.attach`에서 Firebase 오디오 offer를 받기 전에:

- iOS `Helper.setAppleAudioIOMode(AppleAudioIOMode.remoteOnly, preferSpeakerOutput:true)`
- iOS `Helper.ensureAudioSession()`

를 실행합니다. **뷰어폰 마이크 캡처나 권한 요청은 하지 않습니다.**

별도 오디오 트랙 수신 및 ICE 연결 시 오디오 세션 출력을 다시 확인하고,
iOS에서 짧은 단일 출력 복구 재시도를 실행합니다. iOS `remoteOnly`
방식에서는 통화용 speakerphone override를 하지 않습니다.
Android 수신 측은 기존 스피커 경로 동작을 유지합니다.

기존 WebRTC 영상 Peer, Opus 음질 파라미터, 거치폰 마이크, Firestore
규칙, 가로 회전·확대/축소와 Firebase 인증 코드는 변경하지 않았습니다.

## 테스트

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/fix/station-dialog-ios-first-audio-20261115
flutter pub get
flutter analyze
flutter test

# Android에 새 버전 설치/실행
flutter run -d RFCT3225GCZ
# 디버거 분리 시 'd' 사용
# iPhone에 새 버전 설치/실행
flutter run -d 00008130-001250C81AF3803A
```

기존 브랜치에 아직 로컬 아이콘 파일, FlutterFire/Xcode 변경사항이 있다면
`git switch`에서 충돌이 날 수 있습니다. `reset --hard`를 사용하거나
설정 파일을 삭제하지 말고 충돌 내용을 먼저 확인하세요.

### 실기기 재현 테스트 (가장 중요)

1. 정상 로그인 후 거치폰 시작 팝업이 새 디자인이고, 취소/시작이 정상인지
   확인합니다. 대기 상태에서 카메라·마이크는 OFF여야 합니다.
2. **첫 번째 테스트를 반드시 Android 거치폰 / iPhone 뷰어폰 순서로**
   진행합니다. 소리가 안 들리는 문제를 재현하는 조건이기 때문입니다.
3. iPhone을 *거치폰으로 전환하지 않고*, Android 주변에서 소리를 내서
   iPhone에 바로 전달되는지 확인합니다.
4. 실시간 보기 종료 → 다시 시작을 3회 반복합니다. 모든 회차에서
   영상 및 소리의 연결 상태와 해제를 확인합니다.
5. 그다음 iPhone 거치폰 / Android 뷰어폰 반대 역할도 테스트합니다.
6. 자동 마이크 사용 설정이 거치폰에서 켜져 있어야 합니다.
   대기 중 마이크 OFF, 실시간 보기 중 ON, 보기 종료 후 OFF를 확인합니다.
7. 소리가 안 들리면 양쪽 기기의 오디오 상태 문자열과
   `flutter run` 로그를 전달합니다. `onTrack`, `ICE`,
   `오디오 출력 초기화 오류` 여부가 중요합니다.

### 카메라 화질 (이번 수정에서 변경 없음)

현재 `lib/webrtc_session.dart`에는 1280×720, 20fps 이상적 요청이 있습니다.
1080p, 24/30fps, adaptive bitrate, 초점/노출, 디지털 확대 품질은
기술적으로 추가 검토할 수 있으나 이번 브랜치는 오디오/팝업 수정만입니다.

## 검증 한계

GitHub에서 소스 변경은 완료했으나 Mac의 Flutter 분석, 위젯 테스트,
iOS/Android 실기기 첫 세션 오디오 성공은 사용자가 테스트해야 합니다.
