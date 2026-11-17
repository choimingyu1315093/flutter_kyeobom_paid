# 켜봄 — 교차 실기기 QA 완료 후 광고 마무리 (2026-11-17)

브랜치: `fix/admob-native-validator-qa-20261117`
기준: `feature/admob-banner-branding-ids-20261117`

## 확인된 사용자 QA

사용자는 Android 거치폰 ↔ iOS 뷰어폰, 반대 방향 거치/뷰어,
실시간 영상·음성, 연결 해제, 화면 전환, 로그인, 앱 아이콘과
기본 배너의 교차 실기기 테스트가 모두 정상이라고 보고했다.

## 이번 코드 변경

1. 기본 홈: **320×50 표준 배너 그대로 유지**, iOS 네이티브 자동 송출 **금지**.
2. 네이티브 광고는 오직 `kDebugMode` + 명시적
   `KYEOBOM_ENABLE_IOS_NATIVE_ADS=true`에서만 iOS 사용 가능.
   릴리스에 `KYEOBOM_ENABLE_IOS_NATIVE_ADS=true`를 전달해도
   검증되지 않은 iOS 네이티브가 활성화되지 않음.
3. 명시적 디버그 네이티브 검사 모드
   (`KYEOBOM_ENABLE_IOS_NATIVE_ADS=true`,
   `KYEOBOM_AD_FORMAT=native`)에서는 광고를
   고정 하단이 아닌 **스크롤 홈 본문**에 배치.
   Google Native Validator의 `See issues`가 화면 아래로
   잘리는 현상을 피하고 사용자 기본 영상 버튼을 가리지 않도록 함.
4. 작은 네이티브 템플릿의 광고 슬롯을 **160dp**로 설정
   (Google 권장 높이 90~200dp), 실제 표시 폭을
   320dp 이상 확보할 수 있는 기기에서만 요청.
5. 기본 배너 320dp 폭에 홈 양쪽 20dp 여백, 카드 테두리 1dp를
   포함해 필요한 화면 폭 **362dp 이상**인 경우에만 요청.
   320~360dp 기기에서는 광고를 생략해 화면 버튼이 깨지지 않게 함.
6. 위 정책의 단위 테스트 추가.
7. 기존 원격 제어, Firebase, WebRTC, DataChannel, 마이크/카메라,
   앱 아이콘, 안드로이드 패키지명, iOS Bundle ID,
   실제 AdMob 앱·광고 단위 ID 변경 없음.

## iPhone 네이티브 광고 진단 명령

평소 안정성 검증 시:

```bash
flutter run -d 00008130-001250C81AF3803A \
  --dart-define=KYEOBOM_AD_FORMAT=auto
```

**한 번만 별도 QA를 할 때**:

```bash
flutter run -d 00008130-001250C81AF3803A \
  --dart-define=KYEOBOM_AD_FORMAT=native \
  --dart-define=KYEOBOM_ENABLE_IOS_NATIVE_ADS=true
```

뷰어 모드를 연 후 홈 페이지 아래로 스크롤 → 테스트 네이티브
광고 / Native Ad Validator 진단을 확인.
`1 implementation issue found`가 계속 나오면
**`See issues` 상세 페이지를 캡처해 실제 지적 사항을 확인**한다.
팝업이 잘려 보이면 홈 스크롤을 위/아래로 움직여 광고를
화면 중간으로 옮긴 뒤 재확인.
Native Validator를 비활성화하는 Info.plist 설정은 추가하지 않음.

Google 공식 안내:
- <https://developers.google.com/admob/ios/native/validator>
- <https://developers.google.com/admob/flutter/native/templates>
- <https://developers.google.com/admob/flutter/banner/fixed-size>

**정확한 Validator 지적 내용이 없는 현시점에는
네이티브 광고 오류 해결 완료라고 주장할 수 없음.**

## 2026-11-17 추가: 로컬 viewer_ads.dart 충돌 해결

이전 버전 적용 도구는 `git apply --check`에서
`lib/kyeobom_viewer_ads.dart:380 patch does not apply`를 보고하고
**어떤 파일도 수정하지 않고 종료**했다.

새 버전 도구 `tools/apply_admob_native_qa_locally.py`는 다음과 같다.
- GitHub 기준 브랜치, QA 브랜치, Mac의 현 파일을 **3방향 병합**
- 3방향 병합 결과가 정상일 때만 적용
- `viewer_ads.dart`만 충돌하면 기존 코드를 통째로 대체하지 않고,
  광고 크기 보호 로직과 네이티브 영역 높이만 **선택적으로 삽입**
- 그 외 충돌이 있으면 변경하지 않고 종료
- 적용 성공 전 기존 파일 전체 Desktop 백업
- 앱 아이콘, Firebase 파일, Xcode/Gradle 설정, 원격제어 등 미변경

예전 스크립트를 다시 실행하면 같은 오류가 나므로
`git fetch origin` 후 **새 스크립트 파일만 재다운로드**하고
다시 테스트한다. 최신 실행 명령은 아래 절 참조.

---

## Mac 로컬 파일 보호 + 테스트

Mac에는 사용자가 직접 넣은 Android/iOS 아이콘, 새 Firebase 설정,
Xcode 서명, `lib/firebase_options.dart` 등이 Git 미추적 상태로 존재.
**브랜치 switch/reset/clean 없이 기존 디렉터리에서 선택적 패치**.

새 안전 적용 도구는 Git 3방향 병합으로 로컬 코드와 충돌 여부를
**먼저 검사**한다. `viewer_ads.dart`만 충돌할 경우 광고 영역의
제한 로직을 안전하게 선택 적용한다. 다른 충돌은 수정 없이 종료한다.
성공 시 기존 4개 광고 관련 파일을 Desktop에 백업한다.
아이콘/Firebase/서명 파일은 제외.

```bash
cd ~/Flutter/flutter_home_camera
git fetch origin
mkdir -p tools
git show origin/fix/admob-native-validator-qa-20261117:tools/apply_admob_native_qa_locally.py \
  > tools/apply_admob_native_qa_locally.py
python3 tools/apply_admob_native_qa_locally.py

flutter test test/kyeobom_ad_policy_test.dart
flutter test test/kyeobom_ad_placement_test.dart
flutter test
```

이 도구는 현재 브랜치의 다른 작업과 변경 부위가 겹치면 적용을
**거절**한다. 이 경우 코드 원격 HEAD나 기존 브랜치를 강제로
초기화하지 말고 출력된 충돌을 확인해 선택적으로 병합해야 함.
코드만 적용하므로 전체 신규 브랜치의 다른 수정이
Mac에 반영됐다고 가정하면 안 됨.

## 실광고 활성화 전 필수 외부 단계

AdMob의 테스트 광고 표시가 성공했다고 곧 수익 발생하는 것은 아님.

- Google Play/App Store에 실제 앱을 공개 등록하고
  Android `com.mingyu.kyeobom` / iOS `com.mingyu.kyeobom`
  실제 앱을 AdMob에 연결해 앱 준비 상태가 **Ready**인지 확인
- Google의 `app-ads.txt` 검증: App Store/Play Store에 연결된
  개발자 웹 도메인의 `/app-ads.txt`에 AdMob 콘솔이 제공한
  본인 판매자 스니펫을 호스팅하고 상태 확인
- AdMob Privacy & messaging에서 필요한 UMP 사용자 메시지 작성·공개,
  지역별 동의 및 개인 정보 재선택 경로 테스트
- 앱 개인정보처리방침/스토어 개인정보 신고와 실제 광고 수집 데이터 검토
- AdMob 계정 지급 정보, 앱 준비 및 정책 상태, 라이브 광고 승인 확인
- iOS Native 광고는 위 Validator 상세 오류 해소 전까지
  배너만 사용
- 실광고는 릴리스 준비 이후 명시적으로
  `--dart-define=KYEOBOM_ENABLE_LIVE_ADS=true`로 활성화할 수 있으나,
  사전 검증 없이 그 설정으로 실기기 QA하거나 자신의 광고를
  눌러서는 안 됨.

공식 기준:
- <https://support.google.com/admob/answer/10564477>
- <https://support.google.com/admob/answer/14538460>
- <https://developers.google.com/admob/flutter/privacy>

**유지 정책:** 거치폰 대기/실시간 영상 중 광고 미표시.
카메라·마이크 연결을 광고 시청 조건으로 만들지 않음.
