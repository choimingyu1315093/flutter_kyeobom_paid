# 켜봄 이벤트 자동 녹화 P1 — 독립 QA (2026-11-18)

## 브랜치 / 범위

- 대상: `flutter_kyeobom_paid`
- 브랜치: `paid/event-motion-recording-p1-20261118`
- 기준: 실기기 29/29 항목을 통과한 `paid/free-secure-health-compat-20261118`
- **무료 저장소 / 유료 기준 브랜치 / Android 결제 병렬 브랜치 수정 없음**
- Firebase 운영 규칙, Cloud Functions, Storage에 **쓰기 또는 배포 없음**

## 구현된 P1 기능

- 거치폰의 `이벤트 자동 녹화` 스위치: 기본 OFF, 로컬 기기에 opt-in 저장
- 오직 뷰어가 실시간 영상을 보는 동안 **이미 열려 있는 거치폰 WebRTC 카메라 트랙**에서 희소 프레임 감지
- 자동 노출 밝기 변화 필터링, 연속 움직임 확인, 60초 중복 녹화 방지
- 움직임이 감지되면 **20초 길이의 무음 MP4 영상**을 거치폰 앱 내부 저장소에 기록
- 녹화 파일은 `MediaRecorder.stop()` 성공 후에만 목록에 노출, 저장 중 충돌 시 오래된 미완성 파일 정리
- 거치폰에서 목록 조회·영상 재생·개별 영구 삭제
- 최대 50개, 최대 256MiB, 보관 30일 이후 정리 (먼저 도달하는 한도 적용)
- 영상 연결 종료/앱 백그라운드 전환/배터리 및 발열 위험 시 우선 녹화 종료, 카메라 및 WebRTC 보호
- 기존 마이크 동작 유지. 이벤트 영상에 오디오를 녹음하지 않음. 업로드/클라우드 비용 없음.

## 구현하지 않은 다음 단계

- 대기 중 카메라나 마이크를 켜서 감지하는 스마트 감시 모드 (현재 대기 모드는 카메라/마이크 OFF 원칙 유지)
- 이벤트 전 5초 프리롤 버퍼
- 울음·소리 감지 (베이비 모드와 통합 예정)
- 뷰어폰에서 녹화 목록 조회·영상 다운로드 및 장치 간 안전한 파일 전송
- 프리미엄 1회 결제 권한 연계 (다른 브랜치에서 개발 중)
- 클라우드 백업/관리/공유

## QA 1 — Mac 자동 검사

```bash
cd ~/Flutter/flutter_kyeobom_paid
git status --short
git fetch origin
git switch --track origin/paid/event-motion-recording-p1-20261118
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
flutter build ios --debug --no-codesign
```

기존 Firebase 로컬 설정 파일은 삭제하지 않는다. `git reset --hard` 금지.

## QA 2 — 로컬 에뮬레이터

터미널 A (연결 종료 전까지 유지):

```bash
cd ~/Flutter/flutter_kyeobom_paid
bash tools/paid_security_rules/run_device_qa_emulators.sh
```

터미널 B (Android, id 자동 지정):

```bash
cd ~/Flutter/flutter_kyeobom_paid
MAC_IP=$(ipconfig getifaddr en0)
ANDROID_ID=$(flutter devices --machine | python3 -c 'import json,sys; print(next(d["id"] for d in json.load(sys.stdin) if d["targetPlatform"].startswith("android")))')
flutter run -d "$ANDROID_ID" --debug \
  --dart-define=KYEOBOM_USE_FIREBASE_EMULATORS=true \
  --dart-define=KYEOBOM_EMULATOR_HOST="$MAC_IP"
```

터미널 C (iPhone, iOS 장치 ID는 실제 연결 장치에 맞춰 사용):

```bash
cd ~/Flutter/flutter_kyeobom_paid
MAC_IP=$(ipconfig getifaddr en0)
flutter run -d 00008130-001250C81AF3803A --debug \
  --dart-define=KYEOBOM_USE_FIREBASE_EMULATORS=true \
  --dart-define=KYEOBOM_EMULATOR_HOST="$MAC_IP"
```

## QA 3 — 실기기 P1 체크

1. Android 거치폰: 앱 대기 중 **이벤트 자동 녹화 기본 OFF** 확인, 카메라·마이크 OFF 확인
2. 거치폰에서 자동 녹화를 ON. 이 순간에는 카메라/마이크가 켜지지 않아야 함
3. iPhone 뷰어: QR 승인 후 실시간 보기. 거치폰 상태가 감지 중으로 변경
4. 카메라 앞에서 손/몸을 움직여 약 6~10초 동안 변화 유도. 거치폰에 녹화 중 표시
5. 20초 후 저장 완료 문구 확인. 실시간 영상/음성이 끊기지 않았는지 확인
6. 뷰어 종료 후 거치폰 `저장된 이벤트 영상 보기`: 20초 내외 MP4가 재생되는지 확인
7. 영상 삭제 후 목록에서 사라지는지 확인
8. 스위치를 OFF하고 다시 시청: 움직임이 있어도 녹화되지 않아야 함
9. 녹화 중 뷰어 연결을 종료: recorder가 정리되고 카메라·마이크 OFF, 짧은 클립 저장 허용
10. 60초 이내 반복 움직임에도 클립이 무제한 생성되지 않는지 확인
11. iPhone 거치폰 / Android 뷰어로 역할을 바꿔 동일 검증
12. 회귀 QA: QR 승인, 영상/음성, 배터리/발열 상태, 재연결, 뷰어 접근 해제, 광고의 이전 동작 확인

실기기에서 `MediaRecorder` 지원/코덱·파일 재생 여부는 아직 확인 전이며, iOS/Android 양쪽의 실제 MP4 저장 QA가 필수다.

## 배포/병합 금지

P1 QA가 끝나기 전에는 `paid/free-secure-health-compat-20261118`, `paid/integrated-20261117`, `flutter_home_camera`에 병합하지 않는다. Firebase 관련 CLI deploy 명령을 실행하지 않는다.
