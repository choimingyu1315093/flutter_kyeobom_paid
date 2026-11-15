# 켜봄 — 운영비 최적화 1단계 QA

브랜치: `feature/cost-optimization-datachannel-20261115`
안정화 기준: `fix/station-dialog-ios-first-audio-20261115`

## 이번 브랜치에서 실제 구현한 항목

1. **Firestore 연결 유지 쓰기 최적화**
   - 기존: 실시간 보기 중 `viewerHeartbeatAt`을 **매 10초** Firestore에 기록.
   - 새 버전 + 새 버전: 같은 WebRTC 영상 Peer의 `RTCDataChannel`로
     10초마다 하트비트와 ACK를 직접 교환. 정상 연결 후
     **반복 Firestore 쓰기 0회** (세션 시작/종료 SDP/ICE 쓰기는 유지).
   - 구버전 기기나 데이터 채널 장애 시: 최초 연결로부터 20초 뒤
     필요할 때만 **20초 간격 Firestore 임시 하트비트**를 사용.
     ACK를 수신하면 해당 fallback 쓰기를 중지.
   - 기존 앱이 보내는 `viewerHeartbeatAt`은 새 거치폰에서도 받아
     화면이 45초 뒤 임의 종료되지 않도록 호환성 유지.

2. **안전한 연결 종료**
   - 거치폰은 DataChannel 또는 구버전의 정상 Firestore 신호를
     받지 못한 지 **45초 초과** 시 송출 종료 콜백 실행.
   - 마이크와 카메라 종료, 앱 백그라운드 종료 처리, 기존 화면 회전·
     확대·축소, iOS 첫 오디오 재생 수정은 그대로 유지.
   - 사용자가 강제 종료하면 서버 신호를 보내지 못할 수 있으므로
     거치폰이 독립적으로 생존 신호를 감시하는 구조가 중요.

3. **Firestore 저장 용량 관리**
   - 로그인 또는 앱 시작 시 하루 최대 1회, 종료된 지 48시간이 넘은
     세션을 최대 12개 정리.
   - `viewerCandidates` / `stationCandidates` 하위 문서도 삭제.
   - 진행 중인 세션은 얼마나 오래 시청 중이든 건드리지 않음.
   - 서버 함수·유료 Firestore TTL 사용하지 않음.
   - 두 앱이 모두 강제 종료되어 상태가 `ended`로 기록되지 않은
     오래된 고아 세션은 이번 보수적 정리 대상에서 제외됨.

4. **유료 중계 비용 가드**
   - 영상·소리 연결은 모두 **STUN 기반 직접 P2P 연결** 유지.
   - 유료 TURN/SFU를 추가하지 않음. 따라서 TURN 중계 과금은 0원.
   - 직접 P2P가 제한되는 통신사/공유기에서는 영상 연결 실패 가능.
   - 향후 TURN 도입은 사용량 계측, 인증·쿼터 및 하드 예산 제한을
     먼저 개발한 뒤 별도 QA 브랜치에서 검증해야 함.

## Firestore 쓰기 절감 예시 (한 세션, 1대의 뷰어폰)

| 사용 시간 | 기존 10초 쓰기 | 개선 후 정상 P2P 쓰기 | 호환 fallback 20초 쓰기 |
|---|---:|---:|---:|
| 1시간 | 360 | 0 (초기 협상 제외) | 약 180 |
| 8시간 | 2,880 | 0 (초기 협상 제외) | 약 1,440 |
| 24시간 | 8,640 | 0 (초기 협상 제외) | 약 4,320 |

초기 연결 협상이 느리면 ACK 전에 fallback 쓰기가 1~수 회 발생할 수 있음.
위 표의 0은 **DataChannel ACK가 연결된 이후의 주기적 쓰기**만 의미.

## 로컬에서 테스트

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/feature/cost-optimization-datachannel-20261115

flutter pub get
flutter analyze
flutter test

flutter run -d RFCT3225GCZ
# Android 거치폰을 띄운 상태에서 'd'를 눌러 분리 후
flutter run -d 00008130-001250C81AF3803A
```

원래의 iOS 코드 서명, Firebase 설정, 로컬 앱 아이콘 파일을
`git reset --hard`나 `git clean -fd`로 삭제하지 말 것.
`git switch`가 로컬 변경 때문에 막히면 충돌 내용을 먼저 확인.

### 정상 기능 회귀 QA

- [ ] Android 거치폰 → iPhone 뷰어폰 **첫 연결부터 소리 정상**.
- [ ] 반대로 iPhone 거치폰 → Android 뷰어폰에서도 소리 정상.
- [ ] 영상 전체 화면, 줌, 가로 180도 회전, 종료 후 세로 복귀.
- [ ] 거치폰 자동 마이크 옵션 및 수동 마이크 버튼 정상.
- [ ] 새 버전 양쪽에서 2분 이상 연결이 유지되며 45초 자동 종료 없음.
- [ ] 영상 종료 후 거치폰 카메라·마이크가 꺼짐.
- [ ] **뷰어 앱을 강제 종료**해도 거치폰은 일정 시간 안에
      카메라·마이크를 종료(네트워크/스케줄러에 따라 약 45~50초).
- [ ] Wi-Fi와 모바일 데이터를 서로 달리한 상태에서도 P2P가 가능하면
      영상과 소리가 정상(불가능하면 현재 STUN-only 제한에 해당).
- [ ] 1시간 장시간 시청 시 과열/통신 오류/메모리 문제가 없는지 확인.
- [ ] 실기기 8시간·24시간 연속 QA는 별도 충전·발열 안전 조치 후 진행.

### 실제 비용 경로 확인

두 기기 모두 새 브랜치로 실행하면 뷰어폰 디버그 로그에:

```text
[kyeobom/cost] viewer direct ACK (no DB keepalive writes)
```

거치폰에서는:

```text
[kyeobom/cost] station P2P heartbeat received
```

를 최초 1회 확인할 수 있음.

둘 중 하나가 없고 아래 로그가 나오면 P2P 하트비트에 실패해
Firestore fallback이 시작된 것:

```text
[kyeobom/cost] Firestore fallback active (legacy/no ACK)
```

Firebase 콘솔 Firestore의 현재 `homecamStations/{uid}/sessions/{sessionId}`:
정상 DataChannel 연결 후에는 `viewerHeartbeatAt` 값이
**계속 업데이트되지 않아야** 함. 처음 협상 중 fallback이 잠깐
발생했을 수 있으므로 필드 자체의 존재 여부만으로 판단하지 말 것.

**혼합 버전 테스트**: 거치폰은 이전 안정 브랜치, 뷰어폰은 신규
브랜치로 90초 연결; 이어 역할/버전을 바꿔 같은 테스트.
fallback 환경에서는 서버 반복 쓰기가 발생하지만 영상은 유지되는지
확인하고, 최종적으로 두 기기 모두 신규 브랜치로 복귀.

## 주의 사항

- 현 환경에서는 Flutter/Android/iOS 빌드를 실행할 수 없으므로,
  본 문서는 **소스 반영 후 실기기 검증이 필요한 QA 기준**임.
- 본 앱은 베이비 모니터로서 영상/소리가 항상 연결된다고
  보장할 수 없으며 안전 장치의 대체품으로 사용하면 안 됨.
- 광고 SDK, 카메라 해상도/프레임레이트, TURN 서버는 변경하지 않았음.
- 원가 0원은 영상의 P2P 중계비에 관한 이야기이며,
  Firestore의 초기 시그널링/정리 작업, 앱스토어 계정 비용 및
  다른 인프라 비용이 무조건 0원이라는 뜻은 아님.
