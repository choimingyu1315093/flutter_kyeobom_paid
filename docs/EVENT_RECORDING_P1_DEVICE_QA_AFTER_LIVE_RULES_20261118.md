# 켜봄 유료 P1 실기기 QA — 운영 Firestore 호환성 검증 후

## 검증 완료 (2026-11-18 사용자 실기기 결과)

운영 Firestore 규칙에 최소 권한 추가 후 사용자가 6/6 통과 보고:
- Android 거치폰 상태 전송 정상
- iPhone 뷰어 배터리/발열/네트워크 표시 정상
- iPhone 위험 알림 토큰 등록 정상
- QR 승인/연결 정상
- 실시간 영상/음성 정상
- 연결 해제 후 뷰어 접근 차단 정상

이는 Cloud Functions 실제 발송이나 녹화 MP4의 정상 작성을 증명하지는 않는다.

## 작업 격리

- QA 전용 브랜치: `paid/event-recording-p1-device-qa-hardening-20261118`
- 브랜치 기준: `paid/live-firestore-health-fcm-compat-20261118`
- 무료 프로젝트/기준 브랜치/구독 브랜치 수정 없음, Firebase 규칙 및 Functions 배포 없음
- 녹화 파일 보관 한도 정리 중 파일이 이미 삭제된 경우 예외 대신 null을 반환
- 앱 전용 pending 디렉터리의 녹화 파일만 publish
- 로컬 파일 시스템 기반의 보관/삭제 테스트 추가

## Mac 검증 및 설치

```bash
cd ~/Flutter/flutter_kyeobom_paid
git status --short
git fetch origin
git switch --track origin/paid/event-recording-p1-device-qa-hardening-20261118
flutter pub get
flutter test test/event_clip_store_test.dart
flutter test
flutter analyze --no-fatal-infos
```

Android Release:
```bash
ANDROID_ID=$(flutter devices --machine | python3 -c 'import json,sys; print(next(d["id"] for d in json.load(sys.stdin) if d["targetPlatform"].startswith("android")))')
flutter run --release -d "$ANDROID_ID"
```

iPhone Release:
```bash
flutter run --release -d 00008130-001250C81AF3803A
```

서로 다른 터미널에서 각각 실행한다. 동일 bundle ID인 무료 앱은 설치 시 교체될 수 있다.
Release는 실제 Firebase 프로젝트를 사용하며 Debug 전용 Auth/Firestore 에뮬레이터 라우팅은 동작하지 않는다.

## 움직임 자동 녹화 P1

1. **거치폰 Android**: 대기 화면에서 '이벤트 자동 녹화' 기본 OFF. 카메라·마이크 OFF 상태 확인
2. 스위치 ON. 계속 대기 중일 때 카메라가 열리면 실패
3. **iPhone 뷰어**에서 실시간 보기. 기존 영상·마이크 동작 유지
4. Android 후면 카메라 앞에서 6~10초 움직임 유도 (손보다 몸 전체 움직임이 감지에 쉬움). '녹화 ON' 또는 20초 녹화 상태 확인
5. 녹화 시작 후 20초 경과. 저장 완료 표시 확인; 시청 중 끊김 없었는지 확인
6. iPhone 실시간 보기 종료. Android 대기 화면에서 '저장된 이벤트 영상 보기' → 생성된 MP4 1개 확인, 재생 확인
7. 영상 삭제 → 목록에서 제거, 다른 파일은 보존
8. 스위치 OFF 후 실시간 시청하며 움직여도 새 영상이 생성되지 않아야 함
9. 스위치 다시 ON, 녹화 중 iPhone 영상 종료 → 카메라/마이크 즉시 종료, 기록 손상/앱 종료 없음
10. iPhone을 거치폰, Android를 뷰어로 교차 확인 (iOS MediaRecorder/코덱 실제 지원 필수)
11. 앱 완전히 종료하고 재실행 → 자동 녹화 설정과 저장한 MP4 파일 유지
12. 재연결 및 연결 해제 → 이전 뷰어 접근 차단, 새 뷰어에게만 영상 전송

현재 P1의 감지는 **실시간 시청 중에만** 진행한다. 대기 중 24시간 감지, 울음소리 감지, 뷰어폰 원격 영상 재생은 아직 미구현. 저장 영상은 거치폰 앱 내부에만 존재한다. 오디오는 녹화하지 않는다.

### 문제가 발생한 경우

- 먼저 거치폰 화면에 뜬 녹화 상태 메시지를 원문 그대로 기록한다.
- Release에서는 자세한 Dart 로그가 제한되므로 동일 조건을 `flutter run --debug`로 재현하되 `KYEOBOM_USE_FIREBASE_EMULATORS` 지정 여부를 확인한다.
- 거치폰/뷰어 연결 문제와 녹화 오류를 분리한다. 녹화 실패 시 WebRTC 실시간 영상이 유지되어야 한다.
- 파일 저장, 재생, 종료, 카메라 부하가 특정 OS에만 발생하는지 비교한다.

## 실 푸시 발송 확인 (읽기 전용)

현재 QA의 '위험 알림 등록 정상'은 기기 토큰의 Firestore 기록이 성공했다는 뜻이며,
실제 FCM 전달 성공을 증명하지 않는다.

```bash
firebase functions:list --project homecamera-13091
firebase functions:log --only notifyOnHealthChange --lines 40 --project homecamera-13091
```

해당 함수의 배포 여부 및 최근 실행 기록을 먼저 확인한다. 함수가 없다면 자동 발송은 동작하지 않는다. **`firebase deploy`는 실행하지 않는다**.
실제 기기를 고의로 과열시키거나 배터리를 5% 이하로 떨어뜨려 테스트하지 않는다. 발송은 향후 안전한 에뮬레이터/스테이징 조건 또는 인증된 테스트 기기에서 검증한다.

## 완료 조건

- 새 로컬 녹화 테스트 포함 Flutter 전체 테스트/Android·iOS Release 빌드 성공
- Android 및 iOS 양쪽의 실제 MP4 저장/재생/삭제 실기기 성공
- 배터리/발열 보호·실시간 영상·연결 권한 회귀 이상 없음
- 현재 운영 규칙 변경·Cloud Functions 배포 없음
- 다른 브랜치와의 병합은 사용자 QA 승인 후 결정
