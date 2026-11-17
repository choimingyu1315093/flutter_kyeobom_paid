# 켜봄: 거치폰 배터리·발열 푸시 알림 (2026-11-17)

전용 브랜치: `feature/smart-health-push-alerts-20261117`  
기준 브랜치: `feature/smart-device-health-20261117`  
병합/서버 배포: **미수행** (사용자 QA 승인 후)

## 구현 범위
서버가 보내는 푸시 알림은 정확히 다음 세 가지입니다.
1. `battery_low`: 거치폰 배터리 20% 이하, **충전 중이 아닐 때만** 1회. 25% 이상 회복하거나 충전 시작 후 다시 20% 이하로 떨어지면 재알림
2. `thermal_serious`: Android SEVERE 이상(3), iOS SERIOUS 이상(2) 처음 진입 시 1회
3. `thermal_critical`: Android CRITICAL 이상(4), iOS CRITICAL(3) 진입 시 추가 1회. 정상 -> 위험 단계로 바로 뛰면 '심각' 알림은 생략

배터리 5% 단독 알림, 네트워크 상태, 연결 복구, 소리/움직임 알림은 **없습니다**.
위험이 계속 유지되는 동안 반복 알림을 보내지 않습니다. 발열은 SERIOUS 미만으로 내려갈 때까지 재무장하지 않습니다.

## 실시간 보기 중 알림
- 거치폰 대기 / 실시간 송출 중: 앱이 전경에 있는 동안 같은 30초 주기로 배터리·발열을 확인
- 상태 변경 시 `homecamStations/{uid}/telemetry/health` Firestore 기록
- Cloud Functions v2 `notifyOnHealthChange`가 상태 변경과 Firestore 트랜잭션 기반 중복 방지 후 FCM 전송
- **뷰어폰이 실시간 영상 시청 중(가로 전체화면)**이면 FCM `onMessage` 수신 즉시 상단 경고 배너 8초 표시. 영상·마이크 중단 없음
- 뷰어폰 백그라운드 / 잠금 상태: OS 푸시 알림에 제목과 본문 표시. 앱 권한·OS 정책·네트워크에 따라 도착 시간은 달라질 수 있음
- 뷰어폰으로 진입 시에만 FCM 토큰 등록 및 알림 권한 요청; 같은 계정으로 로그인한 거치폰은 role=station/token=null 로 등록하여 자기 자신에게 푸시가 가지 않게 함
- 앱을 정상 로그아웃하면 기기 토큰을 등록 해제하고 Firebase Messaging 토큰도 삭제 시도

## 사전 설정: Firebase와 Apple (필수)
1. Firebase **기존 HomeCamera 프로젝트** 사용. 새 Firebase 프로젝트를 생성하지 말 것.
2. Firebase Console → 프로젝트 설정 → Cloud Messaging → Apple 앱 구성에서 **APNs Auth Key (.p8)**, Key ID, Apple Team ID 등록
3. Apple Developer 콘솔에서 해당 iOS 앱의 App ID에 Push Notifications 활성화, 프로비저닝 갱신
4. Xcode → Runner → Signing & Capabilities의 Push Notifications 기능과 서명 팀 확인. `ios/Runner/Runner.entitlements`는 **개발용 APNs 환경**으로 설정되어 있음. TestFlight/App Store 배포 전에는 프로덕션 APNs 환경에 맞는 배포용 서명/entitlement 확인이 별도로 필요
5. Android 13+ / iPhone 뷰어폰에서 켜봄 알림 권한 허용. Android 알림 채널 이름은 '거치폰 배터리·발열 위험'
6. FCM 등록은 **뷰어폰에서 '홈캠 보기'에 한 번 진입**할 때 수행. 앱 홈의 등록 오류 안내가 보이면 APNs, 권한, Firestore 규칙 확인
7. Cloud Functions v2 배포에는 Firebase 프로젝트의 **Blaze 요금제 및 결제 설정**이 필요할 수 있음. Firebase Functions 실행 및 Firestore 읽기/FCM 전송에 운영 비용 가능. 서버는 아직 배포하지 않음

### Firestore Rules
현재 `firestore.rules`에는 이전 `telemetry/health` 규칙과 함께 아래 규칙이 추가되어 있습니다. Firebase Console 규칙을 **백업 후 기존 규칙과 비교**하여 두 블록을 `homecamStations/{uid}` 안에 게시해야 합니다.

```js
match /devices/{deviceId} {
  allow read, write: if isOwner();
}

match /alertState/{alertId} {
  allow read, write: if false; // only trusted Admin SDK
}
```

부모 문서의 allow가 하위 컬렉션에 자동 적용되지 않습니다. Admin SDK 서버 함수는 client Firestore rules를 우회하며 dedup 상태를 안전하게 기록합니다.

### Cloud Functions 배포 (코드 검증 후)
```bash
cd ~/Flutter/flutter_home_camera
firebase projects:list
cd functions
npm install
npm run check
cd ..
firebase deploy --only functions:notifyOnHealthChange --project YOUR_HOME_CAMERA_PROJECT_ID
```
`YOUR_HOME_CAMERA_PROJECT_ID`를 Firebase Console에서 확인한 프로젝트 ID로 교체하세요.
기존 서버 함수를 삭제하거나 다른 프로젝트에 배포하지 말 것.
`firebase.json`에 Node 22 배포 설정이 포함되어 있습니다.
Cloud Functions 배포는 단순 GitHub push나 Flutter 설치로 자동 진행되지 않습니다.

## 로컬 통합 코드 QA
```bash
cd ~/Flutter/flutter_home_camera
git fetch origin
git switch --detach origin/feature/smart-health-push-alerts-20261117
bash tools/qa_smart_device_health.sh --ios
```
- Flutter 분석, 전체 Widget/Unit 테스트, 3종 경고 정책 Node 테스트, Android Release APK와 iOS Release 빌드
- 신규 Firebase Messaging 플러그인 설치로 Android 빌드 구성이 바뀔 수 있으므로 반드시 Release APK를 직접 실행하여 초기 크래시 회귀 여부 확인
- 이 작업 환경에는 Flutter/Xcode가 없어 빌드/기기 알림 수신은 아직 검증하지 못함
- `Firebase.initializeApp` 설정은 사용자가 앞서 생성한 **기존** `firebase_options.dart`/Firebase 구성 유지. 이 파일을 공개 GitHub에 올리지 않음

## 실제 푸시 QA
1. Android 거치폰 + iPhone 뷰어폰 (같은 Firebase Auth 계정), 두 기기에 신규 빌드 설치
2. 뷰어폰에서 '홈캠 보기' 열고 알림 권한 허용; Firebase Firestore `homecamStations/{uid}/devices/{installationId}`에 `role:viewer`/fcmToken 등록 확인
3. 거치폰 '홈캠으로 사용' 진입, 거치폰 문서는 `role:station`, token null인지 확인
4. 뷰어폰 **실시간 보기 중**, 거치폰의 실제 경고 발생 시 가로 영상 상단 알림 배너 표시 여부 확인 (영상/마이크 영향이 없어야 함)
5. 뷰어폰 백그라운드 및 화면 잠금 시에도 동일 경고를 OS 알림으로 받는지 확인
6. Android↔iOS 역할 교차해서 동일 동작 점검
7. 같은 배터리/발열 단계 유지 시 중복 알림이 발생하지 않는지 확인
8. 거치폰을 **인위적으로 과열하지 말 것.** 저배터리·발열 이벤트 로직은 Node 단위 테스트로 검증하고, 실제 푸시 전달 경로는 안전한 Firebase Console 테스트 메시지로 먼저 확인
9. 권한 거부 및 APNs 미연동 시 뷰어에 설정 안내가 표시되는지 확인
   - **기기를 과열하지 않고 FCM 전달 테스트**: Firebase Console → Messaging에서 Viewer 문서의 `fcmToken`으로 테스트 전송할 때 추가 데이터에 `kind=health_alert`, `type=thermal_serious`, `uid=Firebase Auth UID` 지정. iPhone/Android 뷰어 앱이 전경이면 화면 상단 알림 배너로 확인. 백그라운드면 OS 알림 확인. 계정 UID나 FCM 토큰은 채팅에 공유하지 말 것.
   - 이 테스트는 알림 전송/수신 경로 확인이며, **실제 센서 임계값→Firestore trigger** 검증은 Node 정책 테스트와 서버 Functions 로그로 별도 확인
10. 현 서버 릴리스에서는 **기존 Firebase 서비스와 광고/영상에 영향이 없는지** 회귀 QA 완료 후에만 병합

## 제약
- FCM/APNs는 OS가 최종 배송을 제어하므로 **즉시성 보장 불가**. 거치폰 로컬 감지 최대 약 30초 + 네트워크/함수/푸시 지연
- iOS 실제 푸시 수신은 Apple Push Notifications capability, 배포용 서명, APNs Auth Key가 필요. 로컬 시뮬레이터는 푸시 전체 QA를 대체하지 못함
- 거치폰 앱이 강제 종료되거나 iOS OS가 중지시킨 경우 지속 모니터링은 보장되지 않음
- 서버는 상태 문서가 갱신될 때만 알림을 판단하며, Firestore 데이터 수집이 중단되면 알림도 중단됨
- 계정 구조는 기존 동일 계정 1-거치폰/여러-뷰어 테스트 설계를 유지. 정식 출시 전 디바이스 페어링/소유권 분리 필요
