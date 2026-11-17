# 켜봄 — 320x50 광고, 기존 앱 아이콘 복원, com.mingyu.kyeobom 통일 (2026-11-17)

작업 브랜치: `feature/admob-banner-branding-ids-20261117`
기준: `fix/ios-native-ad-validator-viewer-20261117`

## 소스 코드에 반영 완료

- 뷰어 홈의 배너를 `getLargeAnchoredAdaptiveBannerAdSize()`에서
  **표준 `AdSize.banner` (320x50)** 로 변경. 영상/음성 보기는 광고 대기 없이 그대로.
  기존 사진에서 큰 광고 요청으로 생긴 상하 검은 여백을 줄이려는 수정이며,
  배너 내용을 임의로 확대/잘라내지 않음.
- Android `namespace` + `applicationId` = `com.mingyu.kyeobom`
  (`android/app/build.gradle.kts`).
- Android `MainActivity` Kotlin `package` 및 소스 경로를
  `android/app/src/main/kotlin/com/mingyu/kyeobom/MainActivity.kt`로 이관.
  화면 잠금 방지/가로 회전 채널 코드는 **변경하지 않음**.
- iOS `Runner`의 Debug/Profile/Release
  `PRODUCT_BUNDLE_IDENTIFIER = com.mingyu.kyeobom`으로 변경.
- iOS `RunnerTests` = `com.mingyu.kyeobom.RunnerTests`.
- AdMob 실제 앱 ID, 광고 단위 10개, Firebase 영상 신호, WebRTC,
  DataChannel, 앱 내부 디자인 변경하지 않음.
- iOS Native Validator는 **별도 QA 미완료**: 기본 자동 노출 비활성화 유지.
  validator 자체를 끄지 않음.
- `tools/normalize_kyeobom_local_identifiers.py`: 사용자 Mac에서
  원래 수정한 Gradle/Xcode 설정을 보존하면서 식별자만 재설정하는 도구.
- `tools/restore_kyeobom_app_icons.py`: Mac의 기존 이미지 원본만 사용해
  iOS/Android 아이콘 크기를 복원하는 도구, 기존 아이콘 Desktop 백업 후 덮어씀.
- `tools/check_kyeobom_platform_identity.py`: 설정 일치 여부를 읽기 전용 검사.

## 중요: 앱 아이콘이 사라지는 이유

GitHub에는 기본 `mipmap-*/ic_launcher.png`과 iOS `AppIcon.appiconset`
파일이 저장되어 있지만, 사용자 Mac 로그에 있던
`assets/branding/app_icon_real.png`는 **저장소에 커밋되어 있지 않음**.

사용자 이전 로그에서 실사용 PNG가 `M`(수정) 또는
`??`(추적되지 않은 파일)로 나타났음. Git 브랜치를 변경하거나
`git stash`한 후 복원하지 않으면 기본 앱 아이콘이 표시될 수 있음.
따라서 이전 이미지 파일을 GitHub에서 임의로 추정하거나 새로 만들지 않음.

원본이 이미 존재하면:

```bash
cd ~/Flutter/flutter_home_camera
ls -lh assets/branding/app_icon_real.png
python3 tools/restore_kyeobom_app_icons.py \
  assets/branding/app_icon_real.png
```

파일이 없다면 **Mac stash에서 찾기**:

```bash
git stash list
git stash show --include-untracked --name-only 'stash@{0}' \
  | grep -E 'app_icon_real|ic_launcher|AppIcon'
# 실제 원본이 들어 있는 stash 번호를 골라서:
git show 'stash@{N}^3:assets/branding/app_icon_real.png' \
  > ~/Desktop/kyeobom_icon_from_stash.png
open ~/Desktop/kyeobom_icon_from_stash.png
# 이미지가 정확히 이전에 사용하던 아이콘인지 확인한 후:
python3 tools/restore_kyeobom_app_icons.py \
  ~/Desktop/kyeobom_icon_from_stash.png
```

위 예시의 `N`은 실제 stash 번호로 대체. `^3`은 Git stash가
추적되지 않은(untracked) 파일을 별도로 저장한 부모를 나타냄.
파일이 없으면 다른 번호를 보거나 Mac 기존 백업/사진 폴더 사용.
**이 작업은 stash를 삭제하지 않음.**

아이콘 파일을 직접 복원한 이후에는 실제 PNG 결과를 확인하고,
배포용 별도 커밋으로 반영하는 것이 좋음.
기존 PNG가 없는 상태에서는 원본 디자인의 아이콘 복원 작업을
완료로 표시하면 안 됨.

## Firebase 및 iOS 서명 설정 반드시 필요

**Firebase 프로젝트를 새로 만들지 말 것!**
현재 사용 중인 'HomeCamera' Firebase 프로젝트 **안에**
아래 새 앱을 추가 등록해야 함.

1. Firebase Console → 기존 HomeCamera 프로젝트 → 프로젝트 설정 →
   앱 추가 → Android 앱 → `com.mingyu.kyeobom` 등록
2. 새 `google-services.json` 다운로드 →
   Mac의 `android/app/google-services.json`을 백업한 뒤 새 파일로 교체
3. 같은 프로젝트에서 iOS 앱 추가 →
   Bundle ID `com.mingyu.kyeobom` → 새 `GoogleService-Info.plist` 다운로드
   → `ios/Runner/GoogleService-Info.plist`로 교체
4. 필요 시 `flutterfire configure`를 **기존 Firebase 프로젝트**를 선택해 실행.
   `lib/firebase_options.dart`의 신규 플랫폼 Firebase App ID도 맞춰야 함.
5. Firebase Authentication·Firestore는 같은 프로젝트를 사용하므로
   서버 데이터/보안 규칙은 유지할 수 있지만, **기기의 앱 패키지가
   변경되어 새 설치로 취급**된다. 로그인/연결 복구 테스트 필요.
6. App Check, SHA-1/SHA-256 (Android), iOS APNs/푸시, iOS App Check
   등록이 신규 Firebase App ID에 맞는지 확인.
7. Xcode → `ios/Runner.xcworkspace` → Runner → Signing & Capabilities →
   `com.mingyu.kyeobom`의 App ID / 자동 서명 프로비저닝 확인.
8. 프로젝트 자체 Google services Gradle plugin 설정은 사용자 Mac에서
   수정돼 있던 내용을 **지우지 않도록 보호**. 이번 브랜치의 단순
   `android/app/build.gradle.kts` 파일만 덮어쓰면 로컬 Firebase
   플러그인이 빠질 수 있으므로 아래 도구를 사용.

콘솔 등록 전에 Android/iOS 빌드에 바로 들어가면 package/Bundle ID와
Firebase 설정 불일치, 로그인 실패, iOS 서명 실패가 발생할 수 있음.

## Mac 로컬 변경 안전 보존

사용자의 Mac에는 이미 `android/app/build.gradle.kts`,
`ios/Runner.xcodeproj/project.pbxproj`, `lib/remote_control.dart`,
Firebase 설정과 실제 앱 아이콘 등 **중요한 미커밋 변경 사항**이 있음.

기존 브랜치에서 `git reset --hard`, `git clean -fd` 금지.
브랜치 이동 전 `git status -sb`를 확인하고, `git stash push -u`
등으로 모두 안전하게 보관하고 새 브랜치로 이동.

`git stash apply` 중 Gradle/Xcode 파일이 충돌할 수 있음.
**충돌을 억지로 버리지 말고**, Mac에서 사용자가 수정한 Gradle과
Xcode 파일을 백업한 후 `tools/normalize_kyeobom_local_identifiers.py`
를 실행하면 해당 파일의 플러그인·서명 내용은 보존하면서 패키지명만 바뀜.
다른 충돌은 로그를 확인할 때까지 작업 중단.

```bash
python3 tools/normalize_kyeobom_local_identifiers.py
python3 tools/check_kyeobom_platform_identity.py
flutter pub get
flutter test test/kyeobom_platform_identity_test.dart
flutter analyze
flutter test
```

## 실기기 광고/영상 QA

- iOS 홈 제목 + 영상 버튼 + **320x50 크기 표준 배너**
- iOS 광고 내의 비정상적으로 큰 상하 검정 여백이 줄었는지
- Android 홈에서 표준 배너 크기와 영상 버튼 동작
- Android 거치폰/iPhone 뷰어 + iPhone 거치폰/Android 뷰어, 첫 영상/음성
- 종료 후 마이크/카메라 중지, iPhone 가로 회전/복귀
- iOS Native Validator 문제 1건: 상세 `See issues` 화면 확인 후
  실제 원인 수정, 공식 테스트 기기에서 재검증
  (`--dart-define=KYEOBOM_AD_FORMAT=native` +
   `--dart-define=KYEOBOM_ENABLE_IOS_NATIVE_ADS=true`)
- 기본 iOS `auto`에서는 Validator 위험 네이티브 광고 대신 배너 노출

현재 개발 결과: **코드 및 복구 도구 구현**.
Mac 로컬 PNG 바이트를 직접 읽을 수 없으므로 아이콘 결과물의 실제
원본 여부를 확인하지 못했고, Firebase Console의 새 앱 등록도
사용자 계정 작업이어서 완료됐다고 주장할 수 없음.
실기기/Flutter 빌드는 사용자 Mac에서 검증 필요.
