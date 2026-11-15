# 켜봄 광고 수익 최적화 — 전체 개발 QA 및 출시 가이드

날짜: 2026-11-15
기준: `feature/ad-revenue-optimization-20261115`
개발: `feature/ad-revenue-full-optimization-20261115`

## 완료된 코드

| 기능 | 실제 동작 | 상태 |
|---|---|---|
| 뷰어홈 배너/네이티브 | 홈 하단에 고정, 실시간 보기 버튼 가리지 않음 | 구현 |
| 형식 A/B | 설치 단위 50/50, 자동 또는 형식 강제, 로컬 저장 | 구현 |
| 실패 대체 | 네이티브 실패 시 적응형 배너 1회 대체 | 구현 |
| 앱 오프닝 | 뷰어홈에 머문 경험 있는 사용자, 앱 재진입 시에만 | 조건부 구현 |
| 전면 광고 | **사용자가 내부 '연결 종료'를 직접 누른 뒤** 홈 전환 시에만 | 조건부 구현 |
| 선택형 리워드 | 자발적인 광고 시청 후 **홈 광고 12시간 숨김** | 선택형 구현 |
| 실시간 영상 진입 | 광고 0회. 어떤 광고도 시작을 기다리게 하지 않음 | 보호 |
| 거치폰·로그인·회원가입 | 광고 SDK 화면 없음 | 보호 |
| 노출 제한 | 전체 자동 전체화면 광고 합산 **하루 최대 1회** | 구현 |
| 라이브 광고 차단 | 실제 ID·옵트인 없으면 릴리스 광고 요청 안 함 | 구현 |
| 개인정보 | UMP 동의 후 요청·동의 취소 시 캐시 폐기 | 구현 |
| 콘텐츠 등급 | AdMob RequestConfiguration에서 G (가족 전체) | 구현 |
| 광고 실패 | 무응답/No-fill 시 카메라·영상 기능에 영향 없음 | 구현 |
| 광고 측정 | 광고 요청/로드/노출/클릭/유료 추정/보상 로컬 통계 | 구현 |
| 미디에이션 준비 | 어댑터 초기화·응답 네트워크 로그·Ad Inspector | 기반 구현 |

### 수익과 UX를 동시에 관리하는 보수적 조건

**조건부 전면 광고**
- 영상 확인을 직접 종료하고 뷰어 홈으로 돌아가는 경우만 후보
- 최소 3회의 완료된 시청 기록, 해당 시청 15초 이상
- 로드된 광고가 없으면 광고 없이 홈으로 복귀, 나중에 갑자기 보이지 않음
- 합산 자동 전체화면 광고 **하루 최대 1회**
- 자동 전체화면 광고 간 최소 6시간
- 앱 종료/앱 백그라운드/뒤로가기/카메라 연결 오류 시에는 표시하지 않음
- 캐시된 전면 광고가 1시간 이상 지나면 폐기

**앱 오프닝 광고**
- 첫 실행에 표시하지 않음. 해당 사용자의 시청 완료 기록 최소 5회
- 뷰어 홈에서 앱을 10분 이상 백그라운드에 두었다가 다시 열었을 때만 후보
- 거치폰, 실시간 영상, 긴급 연결 진입, 신규 설치에서는 제외
- 준비된 광고가 이미 있어야 함; 광고 로딩을 기다리지 않음
- 마지막 전체화면 광고 후 24시간 이상, 합산 하루 최대 1회
- 앱 오프닝 캐시 4시간 지나면 폐기

**리워드**
- 뷰어 홈에서 사용자가 선택 버튼을 눌러야 함
- 12시간 동안 홈의 배너/네이티브 광고를 숨기는 보상
- 보상을 안 받아도 **모든 카메라·음성 기능이 무료**
- 리워드는 자동 광고 수익을 잠식할 수 있어 기본 비활성

**기본 설정**
- 홈 광고: 개발 빌드에서는 Google 테스트 광고 활성, 릴리스는 실제 AdMob ID까지 준비해야 활성
- 조건부 전면/앱 오프닝/선택형 리워드: **모두 기본 비활성** (`--dart-define`으로 각각 실험 활성화)
- 이는 기능이 미구현이어서가 아니라 사용자를 방해하지 않고 광고 이탈률을 비교하기 위한 출시 가드

## 실제 기기 테스트

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/feature/ad-revenue-full-optimization-20261115
flutter pub get
flutter analyze
flutter test
```

### 홈 하단 광고 + 전면 광고 빠른 QA

```bash
flutter run -d RFCT3225GCZ \
  --dart-define=KYEOBOM_AD_FORMAT=native \
  --dart-define=KYEOBOM_ENABLE_INTERSTITIAL_ADS=true \
  --dart-define=KYEOBOM_AD_QA_FAST=true
```

- 거치폰 하나, Android 뷰어폰 하나 준비
- 뷰어홈에서 테스트 광고가 **하단 고정**되고 영상 버튼을 가리지 않는지
- 실시간 보기 15초 이상 → 앱 내 연결 종료 → **미리 로드돼 있던 경우에만** 샘플 전면 광고 1회
- 다음 시청 종료에는 전체화면 광고가 중복 노출되지 않는지
- iPhone에서도 역방향으로 광고와 영상·오디오 정상인지 확인

### 앱 오프닝 전용 QA

```bash
flutter run -d 00008130-001250C81AF3803A \
  --dart-define=KYEOBOM_ENABLE_APP_OPEN_ADS=true \
  --dart-define=KYEOBOM_AD_QA_FAST=true
```

- 현재 뷰어폰에서 적어도 한 번 영상 확인 후 홈 복귀
- 뷰어 홈을 15초 이상 백그라운드로 보낸 뒤 앱 재진입
- 준비된 테스트 광고가 있으면 1회만 표시
- 실시간 영상 시청 중 앱 전환 후 재진입에는 앱 오프닝 광고가 뜨면 **실패**
- 첫 설치·로그인 직후 바로 앱 오프닝이 뜨면 **실패**

`KYEOBOM_AD_QA_FAST=true`는 **디버그 빌드에서만** 시청 완료 문턱을 1회,
앱 오프닝 백그라운드 대기 조건을 15초로 완화함.
릴리스 빌드에서는 위 원래 제한이 자동 적용됨.
두 형식은 하루 1회 노출 제한을 공유하므로 시험할 때 **각각 별도 세션/기기** 권장.

### 선택형 리워드 QA

```bash
flutter run -d RFCT3225GCZ \
  --dart-define=KYEOBOM_ENABLE_REWARDED_ADS=true
```

- 뷰어 홈에 '선택 광고 시청 후 홈 광고 12시간 숨기기' 버튼 표시
- 완료 리워드 콜백 전에는 광고가 숨겨지지 않아야 함
- 보상을 받으면 홈 광고가 사라지고 안내가 나타남
- 다음 앱 실행에서도 12시간 동안 동일한 보상 적용
- 시청하지 않아도 실시간 영상·마이크 기능은 모두 사용 가능

## 로컬 광고 QA 통계

뷰어 홈에서 `광고 QA` 버튼으로 확인:
- requested / loaded / impression / clicked / paid / failed / earned
- USD/KRW 광고 유료 이벤트의 소수 단위 값(`micro`)
- `광고 인스펙터`: AdMob 실제 매칭 및 미디에이션 어댑터 분석
- 실제 지급액은 AdMob 계정의 수익 보고서가 최종 기준
- 이 정보는 **SharedPreferences에만** 저장되므로 Firebase 비용 증가 없음

AdMob Analytics 보고서에서 반드시 확인:
- 앱별 DAU/MAU, 세션 수 및 평균 영상 확인 시간
- 광고 형식별 요청 수, 매칭률, 노출률, eCPM, ARPDAU
- 전면/앱 오프닝 노출 후 다음날 재방문율 및 영상 연결 실패율
- 실제 월별 Firebase/TURN 비용 대비 광고 정산액

## 실제 수익을 발생시키는 마지막 연결 작업 (AdMob 계정 필요)

1. <https://admob.google.com> 에서 Android·iOS 각각 **켜봄** 앱 등록.
2. 앱 ID 각각 1개씩 (숫자 중간 `~`) 및 홈 배너/네이티브,
   전면/앱 오프닝/선택형 리워드의 광고 단위 ID (숫자 중간 `/`) 발급.
3. `bash tools/configure_kyeobom_admob_app_ids.sh "실제Android앱ID" "실제iOS앱ID"` 실행.
4. 릴리스 빌드에 `KYEOBOM_ENABLE_LIVE_ADS=true`,
   `KYEOBOM_{ANDROID,IOS}_ADMOB_{BANNER,NATIVE,APP_OPEN,INTERSTITIAL,REWARDED}_ID`
   각 값을 사용 목적에 맞게 전달.
5. 전면·앱 오프닝·리워드는 계정 ID만으로 자동 활성화되지 않음.
   시험 결과를 보고 각 `KYEOBOM_ENABLE_INTERSTITIAL_ADS`,
   `KYEOBOM_ENABLE_APP_OPEN_ADS`,
   `KYEOBOM_ENABLE_REWARDED_ADS` 플래그를 하나씩 켠다.
6. AdMob 'Privacy & messaging'에서 필요한 UMP 메시지 작성·테스트,
   Apple/Google 개인정보 표시 및 개인정보처리방침 점검.
7. 실제 연결·영상 품질·Audio/DataChannel/거치폰 대기 종료 QA 통과 후에만
   스토어 릴리스. 카메라·오디오 설정은 이 브랜치에서 변경하지 않음.

### AdMob 미디에이션

앱 측의 **배너/네이티브/전면/앱 오프닝/리워드 진입점, SDK 초기화,
어댑터 상태/응답 진단**은 완성돼 있어. 따라서 기존 AdMob 광고 단위를
미디에이션 그룹에 연결하는 기반은 준비된 상태.

하지만 **제3자 광고 네트워크의 실제 미디에이션을 '구성 완료'라고 할 수는 없음**:
- AdMob 계정에서 파트너 광고 네트워크 선정·계약, 앱/광고 단위 매핑, 입찰/수동 eCPM 설정 필요
- 각 파트너의 Android Gradle/iOS CocoaPods 어댑터 설치 필요
- UMP의 광고 파트너 목록 및 개인정보 고지 필요
- 앱별 광고 네트워크 자격 증명/승인이 필요하며, 이 정보 없이 미리
  임의 어댑터를 넣으면 빌드 크기·심사·안정성 비용만 늘 수 있음

**미디에이션은 AdMob 및 파트너 계정 정보를 확보한 후 추가 통합 테스트해야 함.**

관련 공식 가이드:
<https://developers.google.com/admob/flutter/mediation>
<https://developers.google.com/admob/flutter/privacy>
<https://developers.google.com/admob/flutter/app-open>
<https://developers.google.com/admob/flutter/interstitial>
<https://developers.google.com/admob/flutter/rewarded>

## 완료 기준/주의 사항

- 코드 구현과 기본 소스 구조/변경 범위 검토 완료.
- 이 환경에는 Dart·Flutter SDK, Android/iOS 실기기 빌드가 없으므로
  `flutter analyze`, `flutter test`, Android/iPhone 연결 QA는
  사용자의 Mac에서 실행해야 함.
- 실제 광고의 노출률/수익, 이탈률, 광고 네트워크별 최적화 결과는
  실제 AdMob 계정과 일정 기간의 사용자 데이터가 있어야 결정 가능.
- 유료 TURN 서버는 추가하지 않았으며, Firebase 반복 쓰기 최적화 유지.
- 기존 정상 브랜치나 `main`/`dev`에 병합하지 않음.
