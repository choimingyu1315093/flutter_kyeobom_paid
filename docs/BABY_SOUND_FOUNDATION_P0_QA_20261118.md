# 켜봄 유료 · 베이비 모드 P0 소리 변화 감지 기반 (2026-11-18)

## 사전 승인된 QA

사용자가 2026-11-18 보고한 이벤트 녹화 P1 Android/iOS 실기기 10/10 항목 통과를 기준으로 다음 단계 진행.
현재 P1 영상 송출·마이크 ON/OFF·QR·화면 회전·MP4 저장·재생 로직은 변경하지 않았다.

## 구현 범위 — 오디오 크기만 분석하는 첫 단계

- 유료 별도 브랜치: `paid/baby-sound-detection-foundation-20261118`
- 기존 거치폰 홈에 **베이비 모드 · 소리 변화 감지** ON/OFF. 기본 OFF.
- ON을 눌렀을 때만 플랫폼 마이크 권한을 요청; 동의 기록을 로컬 SharedPreferences에 저장.
- 거치폰이 **앱 실행·대기 상태**이고, 라이브 영상이 꺼져 있고, 안전한 배터리·발열 상태일 때 마이크 dBFS 모니터링.
- Android: AudioRecord 16kHz mono에서 RMS 크기만 산출. iOS: AVAudioEngine input tap에서 RMS 크기만 산출.
- 오디오 샘플은 Dart·디스크·Firebase·네트워크로 전송하지 않음. dBFS(소리 크기) 수치만 Dart로 전달.
- 500ms 주기, 첫 8회(약 4초) 주변 소리 기준 수집, 주변보다 12dB 이상 + 최소 -55 dBFS 초과한 샘플이 3회 지속되면 1회 이벤트.
- 동일 소리 이벤트 쿨다운 90초. 소리 변화 건수를 **거치폰 화면**에 표시(앱 재시작 후 건수 초기화).
- 라이브 영상 시작 전 오디오 미터 종료, 라이브 영상 종료 후 사용자가 ON인 경우에만 대기 감지 자동 재개.
- 앱 백그라운드/대기 종료 시 즉시 감지 종료. 충전이 없고 배터리가 낮거나 발열 위험 시 감지 종료.
- 영상 시청 중 새로 ON으로 전환 금지, OFF는 언제든 허용. 작은 폰에서 설정 스크롤 제공.

## 구현하지 않은 것

- **아기 울음 판별** (현재는 모든 지속적인 소리 변화에 반응하는 단순 음량 기반 탐지).
- 부모폰에 FCM 푸시 전송 / 소리 이벤트 Firestore 기록 / 클라우드 저장.
- 수면 중 백그라운드 마이크 무한 청취.
- 소리 녹음/재생 및 공유.
- 이벤트 녹화 중 오디오 추가/영상 원격 재생.
- 머신러닝 모델 기반 울음 분류 및 오탐 평가.

따라서 현재 단계에서는 '울음 감지 알림 완료'라고 사용자에게 설명하거나 상용 출시해서는 안 된다.

## Mac 자동 테스트

```bash
cd ~/Flutter/flutter_kyeobom_paid
git status --short
git fetch origin
git switch --track origin/paid/baby-sound-detection-foundation-20261118
flutter pub get
flutter test test/baby_sound_policy_test.dart
flutter test test/baby_sound_monitor_test.dart
flutter test test/baby_sound_ui_test.dart
flutter test
flutter analyze --no-fatal-infos
flutter build apk --debug
flutter build ios --debug --no-codesign
```

로컬 flutter pubspec.lock, .firebaserc 등 기존 QA 설정 파일을 지우거나 리셋하지 않는다.
기준 브랜치/무료 프로젝트/구독 병렬 브랜치 병합·수정 금지.

## 실기기 검증

1. Android 거치폰, iPhone 뷰어폰. **베이비 모드 기본 OFF**, 마이크 OS 사용 표시 없음.
2. Android 거치폰에서 ON, 마이크 사용 허용. 화면에 '소리 감지 중' 표시 및 OS 마이크 표시.
3. 먼저 4~5초 조용히 두어 기준 소음을 학습. 그다음 3초 이상 말하기/박수 여러 번/아기 울음 테스트 녹음 *재생*을 스피커에서 틀어 감지 건수 증가 확인. (소리 자체를 앱이 저장하지 않음)
4. 짧은 단발성 소리에는 감지하지 않고, 90초 내 반복 소리에는 중복 이벤트가 최소화되는지 확인.
5. ON -> OFF 후 OS 마이크 표시가 꺼지고 더 이상 건수가 늘지 않는지 확인.
6. 다시 ON → iPhone 실시간 보기 시작. 거치폰 소리 감지 자동 일시정지, 정상 영상·원격 마이크 재생 유지.
7. iPhone 실시간 보기 종료 → 거치폰에서 베이비 소리 감지 자동 재개.
8. 앱 홈으로 이동/화면 종료 → 소리 감지 중지; 복귀하면 ON일 경우 재개.
9. 앱 완전 종료 후 재실행 → ON 설정 복구, OFF는 OFF 유지.
10. iPhone 거치폰 / Android 뷰어폰으로 역할을 바꿔 동일 검증.
11. 권한 거부 → 기능 ON 실패를 알려주고 물리 마이크가 지속적으로 동작하지 않아야 함.
12. 기존 P1 이벤트 자동 녹화 20초 MP4·재생/삭제, QR 해제, 배터리·발열 표시의 회귀 확인.

### 오류 발생 시

Android:
```bash
ANDROID_ID=$(flutter devices --machine | python3 -c 'import json,sys; print(next(d["id"] for d in json.load(sys.stdin) if d["targetPlatform"].startswith("android")))')
flutter run -d "$ANDROID_ID" --debug
```

iOS:
```bash
flutter run -d 00008130-001250C81AF3803A --debug
```

현재 Debug/Release는 실제 Firebase를 사용할 수 있다. QA용 Firebase Auth/Firestore 에뮬레이터가 필요하면 별도의 플래그를 명시하고 서버를 시작해야 한다.
기기 양쪽은 동일 bundle ID가 설치돼 무료 앱을 덮어쓸 수 있다.

## 후속 단계

온디바이스 소리 변화 감지의 기기·발열·배터리·오탐·유지 시간 실기기 검증 후:
1. 울음 분류 정확도 검증 및 오탐 축소(단순 크기 감지와 분리)
2. 승인된 뷰어에게만 이벤트를 알려주는 저비용 이벤트 전송 + FCM 서버 기능 (보안 규칙 별도 검증 및 사용자 승인 배포)
3. 사용자에게 부모폰 수신 푸시/알림 UX 테스트
4. 저조도 영상 개선 (제품 로드맵 후속 단계)

운영 Firestore 규칙과 Cloud Functions, 무료 프로젝트 파일, 기존 P1 브랜치에는 이번 변경 사항이 없다.
