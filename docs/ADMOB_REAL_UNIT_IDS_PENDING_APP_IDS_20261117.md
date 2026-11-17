# 켜봄 실제 AdMob 광고 단위 연결 현황 — 2026-11-17

## 브랜치

- 작업: `feature/admob-real-ids-20261117`
- 기준: `feature/ad-revenue-full-optimization-20261115`
- 기존 P2P 영상/오디오/Firestore 운영비 최적화 변경 없음
- Android 5개, iOS 5개: 사용자 제공 스크린샷을 기준으로 실제 광고 단위 ID 입력
- 소유자 ID/비밀번호/결제·은행 계정 정보는 저장하거나 요청하지 않음

## 1. 실제 광고 단위 ID (코드 연결 완료)

광고 단위 ID는 `/`가 들어간 공개용 AdMob 식별자다.
`lib/kyeobom_ad_policy.dart`의 `String.fromEnvironment` 기본값으로 연결했으며,
필요할 때 `--dart-define`으로 다른 광고 ID를 덮어쓸 수 있다.

| 형식 | Android 광고 단위 | iOS 광고 단위 |
|---|---|---|
| 배너 | ca-app-pub-5893975529562336/6414884933 | ca-app-pub-5893975529562336/6152316006 |
| 네이티브 | ca-app-pub-5893975529562336/2426317273 | ca-app-pub-5893975529562336/4638768834 |
| 전면 | ca-app-pub-5893975529562336/2290585905 | ca-app-pub-5893975529562336/5599275527 |
| 앱 오프닝 | ca-app-pub-5893975529562336/2085078484 | ca-app-pub-5893975529562336/4647662645 |
| 보상형 | ca-app-pub-5893975529562336/6343887693 | ca-app-pub-5893975529562336/5529499473 |

## 2. 아직 미완료: AdMob 앱 ID 2개 (물결표 ~)

광고 단위 ID와 별개로 **AdMob 앱 ID**는 두 플랫폼마다 한 개씩 필요하다.

| 플랫폼 | 필요한 앱 ID | 현재 상태 |
|---|---|---|
| Android | ca-app-pub-5893975529562336~XXXXXXXXXX | 미제공 |
| iOS | ca-app-pub-5893975529562336~YYYYYYYYYY | 미제공 |

`XXXXXXXXXX`, `YYYYYYYYYY`는 형식 설명용 임시 글자이며 실제 값이 아니다.
실제 앱 ID를 추측해 생성하지 않는다.
AdMob 콘솔의 **앱 → 켜봄(Android/iOS) → 앱 설정 → 앱 ID**에서 복사한다.

Android 플랫폼 파일: `android/app/src/main/AndroidManifest.xml`
  - `com.google.android.gms.ads.APPLICATION_ID`
iOS 플랫폼 파일: `ios/Runner/Info.plist`
  - `GADApplicationIdentifier`

현재는 위 두 플랫폼 파일에 Google 공식 샘플 앱 ID가 남아 있다.
**실제 AdMob 앱 ID를 받기 전에는 샘플 값을 교체하지 않는다.**
현재 `KYEOBOM_ENABLE_LIVE_ADS`의 기본값은 `false`, 앱 ID 설정은 공백이며,
따라서 릴리스에서 실제 광고 요청은 차단된다.

## 3. 앱 ID를 받으면 기존 제공 스크립트로 적용

```bash
cd ~/Flutter/flutter_home_camera

git fetch origin
git switch --track origin/feature/admob-real-ids-20261117

# 반드시 AdMob 콘솔에서 확인한 진짜 앱 ID 사용:
bash tools/configure_kyeobom_admob_app_ids.sh \
  "진짜_Android_앱ID_물결표포함" \
  "진짜_iOS_앱ID_물결표포함"
```

두 앱 ID를 받은 뒤 추가할 릴리스 설정 예시:

```bash
flutter build appbundle --release \
  --dart-define=KYEOBOM_ENABLE_LIVE_ADS=true \
  --dart-define=KYEOBOM_ANDROID_ADMOB_APP_ID=실제Android앱ID

flutter build ipa --release \
  --dart-define=KYEOBOM_ENABLE_LIVE_ADS=true \
  --dart-define=KYEOBOM_IOS_ADMOB_APP_ID=실제iOS앱ID
```

각 광고 단위 ID는 이번 브랜치에서 이미 연결했으므로 위 빌드에서 별도로 10개
광고 단위 정의를 모두 전달할 필요 없다. 다른 `--dart-define`을 넘기면 기본값
대신 그 값으로 대체된다.

**전면·앱 오프닝·보상형 광고는 각각 `KYEOBOM_ENABLE_INTERSTITIAL_ADS`,
`KYEOBOM_ENABLE_APP_OPEN_ADS`, `KYEOBOM_ENABLE_REWARDED_ADS`
를 별도로 `true`로 설정했을 때에만 활성화된다.** 설정 없이 카메라
앞에서 갑자기 전체화면 광고가 나오지 않게 만든 안전장치다.

## 4. 앱 ID 전에도 가능한 QA

```bash
flutter pub get
flutter analyze
flutter test test/kyeobom_admob_owner_units_test.dart
flutter test
```

개발용 `flutter run`은 Google 공식 **데모 광고 단위**를 사용하도록 유지했다.
따라서 실제 광고 단위를 클릭하거나 반복 요청해서 테스트하지 않는다.

실제 광고 ID로 QA 할 때는 AdMob 설정에서 해당 기기를 테스트 기기로 등록해
실수로 무효 트래픽이 발생하지 않게 해야 한다.

## 5. 출시 이전 별도 확인

- Android applicationId (현재 코드의 예제 `com.example.flutter_home_camera`) 최종 확정
- iOS Bundle ID 및 Firebase 앱 등록정보 일치
- AdMob UMP 개인정보 동의 메시지 및 Apple/Google 개인정보 공시
- `app-ads.txt`, 스토어 등록, AdMob 앱 준비 상태 검토
- Android·iOS 실기기 테스트 완료 및 실제 광고 정책 확인
- Google Mobile Ads Mediation에서 파트너/어댑터 설정(원할 때 별도 작업)
- `main` / `dev`에 병합하지 않았음
