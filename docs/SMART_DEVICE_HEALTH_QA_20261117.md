# 켜봄 스마트 상태 관리 — 통합 QA (2026-11-17)

개발 전용 브랜치: `feature/smart-device-health-20261117`
기준 브랜치: `feature/ad-revenue-full-optimization-20261115`
미병합: main/기존 진행 중인 브랜치

## 1. 이번 단계 코드 구현
- Android/iOS OS 배터리 잔량 및 충전 상태, OS 발열 **위험 단계**, 인터넷 연결 유형 수집
- 거치폰 앱의 전경 대기 상태에서 카메라/마이크를 켜지 않고 30초 간격 로컬 상태 점검
- 값 변경 시 즉시 Firebase 업데이트, 평소에는 2분 heartbeat (Firestore 비용 관리)
- Firestore 경로: `homecamStations/{auth.uid}/telemetry/health`
- 수집 시각 `collectedAt`, 서버 수신 시각 `lastSeen`, active, battery, charging, thermal, network, platform, risk 저장
- 거치폰이 앱 배경으로 가거나 대기 모드를 종료하면 전송 중지 및 active=false 전송 시도
- 뷰어 홈에서 압축된 '거치폰 상태' 카드 표시. 탭하면 상세 배터리, 발열, 네트워크, 마지막 통신, 경고를 확인
- 마지막 서버 통신과 **실제 수집 시각** 모두 점검하여 약 5분 이상 무응답 시 '연결 확인 필요'
- 복귀 시 SDK 네트워크 재연결 및 앱 전경 복귀에서 즉시 상태 재전송
- Android PowerManager THERMAL_STATUS / iOS ProcessInfo.thermalState 기반 위험도 결정. **온도(℃) 표시는 지원하지 않음**
- 위험 경고: Android MODERATE 이상 / iOS FAIR 이상, 배터리 20% 이하(충전 중 제외)
- 자동 영상 화질 보호: Android SEVERE 이상 / iOS SERIOUS 이상 또는 배터리 20% 이하(충전 중 제외) => 신규 세션 640x360/12fps 요청, 기존 송출 `applyConstraints` 및 `adaptRes` 순으로 재설정 시도 (기기별 API 지원은 실기기 QA 필요)
- 위험 임계: Android CRITICAL 이상 / iOS CRITICAL 또는 충전하지 않는 배터리 <=5% => 기존 송출/마이크 종료, 새 영상 연결 요청 거부
- 위험 해제 후 기존 세션 영상 화질 복구 시도. 새 세션은 정상 프로필로 시작
- 기존 WebRTC 전송, 마이크 동작, 역할 선택, 광고 배치, 백그라운드 송출 중단 정책 유지
- 보안 규칙: `firestore.rules` 내 `match /telemetry/health { allow read, write: if isOwner(); }` 추가
- 상태 수집 실패는 영상/마이크를 종료하지 않음. 앱 내 `permission-denied` / 네트워크 오류 진단 표시

## 2. Firebase 설정 — 반드시 먼저 적용
사용자가 제공한 Firestore 규칙 원문에 아래 블록만 `match /homecamStations/{uid}` 안에 추가하여 Firebase Console의 Firestore Rules에 **게시**.

```js
match /telemetry/health {
  allow read, write: if isOwner();
}
```

GitHub 코드 변경은 실제 Firebase 보안 규칙 게시가 아님. 현재 저장소에는 `firebase.json`/`.firebaserc`가 없어 자동 배포되지 않음.

## 3. 코드 QA — 한 번에
```bash
cd ~/Flutter/flutter_home_camera
git pull --ff-only origin feature/smart-device-health-20261117
bash tools/qa_smart_device_health.sh --ios
```
- `--ios`는 macOS에서 서명 없이 iOS Release 컴파일도 확인. 생략하면 Android만 빌드
- Flutter analyze는 **기존 광고 스타일 info**를 non-fatal 처리, errors 및 warnings는 실패로 처리
- Flutter test는 기기 상태 정책, Firebase 없는 테스트 UI 및 기존 회귀 테스트 검증
- 스크립트 성공 여부와 실기기 Release 동작 여부는 다름. 이 환경에서는 Flutter/Xcode 실행 불가

## 4. 실기기 QA — 서로 다른 네트워크에서 검증
1. Android를 거치폰(홈캠으로 사용), iPhone을 뷰어폰(홈캠 보기)으로 로그인. 두 기기 같은 Firebase 계정 사용
2. 거치폰 대기 진입 후 iPhone 홈의 작은 '거치폰 상태' 카드에 정상 작동/배터리 표시 확인. 카드를 열어 상세 확인
3. 충전기 연결/분리, Wi-Fi/LTE 전환 후 약 30초~2분 내 표시 갱신 확인
4. 거치폰을 백그라운드로 이동하면 연결 상태가 내려가고, 다시 전경 복귀하면 복구되는지 확인
5. 거치폰 인터넷 완전 차단 시 최대 약 5분 내 '연결 확인 필요' (실제로는 5분+위젯 폴링 오차 가능), 재연결 시 자동 복구
6. '실시간 보기' 영상 및 마이크 켜기/끄기, 종료 이후 거치폰이 다시 대기하는지 회귀 QA
7. iPhone을 거치폰, Android를 뷰어폰으로 역할 교환하여 2~6 반복
8. 2시간 대기 시 발열/배터리/영상/앱 강제 종료 유무 확인. 휴대폰을 인위적으로 과열시키지 말 것
9. Firestore 콘솔 `homecamStations/{uid}/telemetry/health`의 `lastSeen`이 갱신되는지 확인
10. Android Studio Debug 성공뿐 아니라 설치된 Release APK 실행 확인. `flutter run --release` 강제종료가 재현되면 Crash Log 첨부

## 5. 테스트 자동화와 플랫폼 한계
- Android/iOS 배포용 앱 서명과 실기기 런타임 테스트는 사용자 Mac/폰에서 수행해야 함. 이 GitHub 작업 환경에서는 실행·검증 불가
- 일반 앱은 사용자가 강제종료했거나 OS가 일시정지한 뒤 자동으로 카메라를 켜거나 iOS 대기 모드를 무기한 재시작할 수 없음
- 뷰어폰 백그라운드 **푸시 알림**은 Firebase Messaging/Functions 또는 서버 인프라가 필요하므로 이번 코드에는 없음. 대신 앱 내 상태 및 경고 표시 구현. 비용/푸시 토큰 설계를 별도 승인 없이 추가하지 않음
- 실시간 화질 전환은 카메라 드라이버별 지원 차이 있음. 미지원 시 화면에 표시하고 영상 연결은 유지; 다음 연결에서 저화질 프로필 적용
- 프로토타입은 같은 계정의 단일 거치폰을 사용한다는 기존 설계를 유지함
