# 켜봄 AdMob 실제 앱/광고 단위 ID 연결 — 2026-11-17

작업 브랜치: `feature/admob-real-ids-20261117`
기준 브랜치: `feature/ad-revenue-full-optimization-20261115`
`dev`/`main`에 미병합.

## 연결 완료

| 항목 | Android | iOS |
|---|---|---|
| AdMob APP ID (`~`) | `ca-app-pub-5893975529562336~4819053037` | `ca-app-pub-5893975529562336~6718137266` |
| 홈 배너 | `ca-app-pub-5893975529562336/6414884933` | `ca-app-pub-5893975529562336/6152316006` |
| 홈 네이티브 | `ca-app-pub-5893975529562336/2426317273` | `ca-app-pub-5893975529562336/4638768834` |
| 전면 광고 | `ca-app-pub-5893975529562336/2290585905` | `ca-app-pub-5893975529562336/5599275527` |
| 앱 오프닝 | `ca-app-pub-5893975529562336/2085078484` | `ca-app-pub-5893975529562336/4647662645` |
| 보상형 | `ca-app-pub-5893975529562336/6343887693` | `ca-app-pub-5893975529562336/5529499473` |

반영 파일:
- `android/app/src/main/AndroidManifest.xml`: Android 실제 APP ID
- `ios/Runner/Info.plist`: iOS 실제 APP ID
- `lib/kyeobom_ad_policy.dart`: 양쪽 실제 APP ID 2개 및 광고 단위 10개를 기본값으로 적용; 명시적 `--dart-define`은 여전히 덮어쓰기 가능
- `test/kyeobom_admob_owner_units_test.dart`: 12개 ID와 개발/출시 가드 검증

## 중요한 광고 요청 안전 장치

1. **Debug/Profile**: 항상 Google 공식 **테스트 광고 단위 ID**. 실제 앱 ID는 플랫폼 메타데이터이지만 개발 빌드에서 실제 광고 단위는 사용하지 않는다.
2. **Release 기본값**: `KYEOBOM_ENABLE_LIVE_ADS=false`. 계정 ID가 실제여도 수익 광고를 요청하지 않는다.
3. **Release 광고 활성화**: `--dart-define=KYEOBOM_ENABLE_LIVE_ADS=true`를 명시해야 한다. 사용자 개인정보 동의 UMP 처리가 허용한 경우에만 광고 요청한다.
4. **전면/앱오프닝/리워드**: 별도의 `KYEOBOM_ENABLE_INTERSTITIAL_ADS`, `KYEOBOM_ENABLE_APP_OPEN_ADS`, `KYEOBOM_ENABLE_REWARDED_ADS`는 기본 `false`다.
5. 사용자 직접 광고 클릭, 실제 광고 반복 로딩/노출 테스트 금지. 실광고 테스트 시 **AdMob에 QA 단말을 테스트 기기로 등록한 뒤** 진행.
6. 미출시 앱의 실제 광고 게재·수익은 AdMob의 검토 상태 및 스토어 연결, app-ads.txt 요건에 따라 제한될 수 있다.

## Mac QA

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/feature/admob-real-ids-20261117

flutter pub get
flutter analyze
flutter test
```

Android 데모 배너 테스트:
```bash
flutter run -d RFCT3225GCZ --dart-define=KYEOBOM_AD_FORMAT=banner
```

iOS 데모 네이티브 테스트:
```bash
flutter run -d 00008130-001250C81AF3803A \
  --dart-define=KYEOBOM_AD_FORMAT=native
```

Android/iOS에서 모두 거치폰과 뷰어폰 역할을 바꿔 실시간 영상,
첫 오디오, 화면회전, 거치폰 대기, 종료 후 카메라/마이크 해제,
Firestore DataChannel 유지 신호가 정상인지 확인.

추가 광고 형식 QA: `docs/ADMOB_FULL_MONETIZATION_QA_20261115.md`

## AdMob 앱/스토어 출시 준비

- 현재 Android `applicationId`는 `com.example.flutter_home_camera`로 확인됨. 정식 Play 패키지명을 정한 후 Firebase Android 등록 정보와 함께 일치시킬 것.
- iOS Bundle Identifier / Firebase plist 서명 정보 검증
- UMP 개인정보 보호/메시지 설정과 광고 대상 이용자 정책
- Play/App Store 개인정보 공시, 개발자 웹사이트 및 app-ads.txt
- AdMob 앱 준비 상태 확인, 앱 출시 후 광고 수익 모니터링
- AdMob 미디에이션의 제3자 파트너 계정, 네트워크 어댑터, 실제 입찰은 별도 외부 설정이 필요함.

## 출시 빌드 예시 (소유자의 실제 테스트 기기에서 무효 트래픽을 방지할 것)

```bash
# Android 출시용 배너/네이티브 허용 (전면 광고는 기본 비활성)
flutter build appbundle --release \
  --dart-define=KYEOBOM_ENABLE_LIVE_ADS=true

# iOS 출시용 배너/네이티브 허용 (전면 광고는 기본 비활성)
flutter build ipa --release \
  --dart-define=KYEOBOM_ENABLE_LIVE_ADS=true
```

전면 광고가 필요하면 별도 플래그, 사전 QA, 앱 정책 검토 후 켤 것.

본 브랜치 수정은 앱 ID/광고 단위 및 그 검증 테스트로 한정.
**Flutter 빌드 및 Android/iOS 실기기 QA는 아직 수행하지 않음.**
