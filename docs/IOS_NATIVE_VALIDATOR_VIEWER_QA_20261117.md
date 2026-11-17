# 켜봄 iOS Native Ad Validator / 실시간 보기 회귀 QA (2026-11-17)

## 증상과 확인된 사실

- iPhone 뷰어에서 Google 공식 네이티브 테스트 광고 위에
  `AdMob native ad validator: 1 implementation issue found` 팝업 발생.
- 화면을 가리는 Native Validator는 Google Mobile Ads SDK의 테스트 진단 UI다.
  **실제 위반 원인은 "See issues" 화면 없이 특정할 수 없다.**
- 원본 Mac 로그: `flutter analyze` 결과 info 12건(컴파일 에러 아님),
  `flutter test`: 41개 테스트 모두 통과.
- `git switch --track origin/feature/admob-real-ids-20261117`는
  "branch ... already exists"로 **실패**함. 이후 로컬에서 실행한 코드가
  GitHub 최신 커밋과 동일한지는 `git branch --show-current`,
  `git log -1 --oneline` 및 `git status -sb` 확인 전에는 단정할 수 없다.
- 사용자의 Mac에는 Firebase json/plist, iOS 서명, 앱 아이콘 등
  커밋하지 않은 중요한 로컬 파일이 존재한다. **초기화 금지**.

## 이번 수정 (GitHub 전용 수정 브랜치)

브랜치: `fix/ios-native-ad-validator-viewer-20261117`
기준: `feature/admob-real-ids-20261117`

1. 기본 A/B 실험에서 iOS NativeAd만 **임시 격리**.
   - iOS에서는 적응형 배너 테스트 광고로 자동 전환.
   - Android 네이티브 광고/배너 A-B 기능은 유지.
   - iOS 네이티브 구현 문제 수정 전 실제 광고 사용자에게 자동 노출되지 않음.
   - iOS 네이티브 검증 재진입은 `--dart-define=KYEOBOM_ENABLE_IOS_NATIVE_ADS=true`
     및 `--dart-define=KYEOBOM_AD_FORMAT=native` 동시 설정.
2. iOS 네이티브 AdWidget에 확정 너비, 132dp 높이 사용.
   작은 화면에서는 네이티브 대신 배너 사용.
3. 영상 화면 진입 시 `AdWidget`이 위젯 트리에서 내려간 **다음 프레임에**
   iOS/Android 광고 리소스를 dispose하도록 변경.
4. 카메라 기능만 검증하고 싶다면
   `--dart-define=KYEOBOM_QA_DISABLE_ADS=true`로 **디버그에서만**
   모든 광고 요청을 비활성화할 수 있음. 릴리스 광고 보호 설정은 불변.
5. Native Validator 자체는 **비활성화하지 않음**.
   검사 문제를 감추지 않고 원인 화면을 볼 수 있게 둠.
6. WebRTC, 오디오, Firebase, UI 디자인, 앱 아이콘, 스토어 ID 변경 없음.

## 즉시 점검 (새 브랜치 적용 전에도 가능)

기존 실행 창을 종료하고, 네이티브 광고 대신 배너를 선택:

```bash
cd ~/Flutter/flutter_home_camera
git branch --show-current
git status -sb

flutter run -d 00008130-001250C81AF3803A \
  --dart-define=KYEOBOM_AD_FORMAT=banner
```

이 상태에서 뷰어폰 실시간 보기, 가로 회전, iPhone 첫 오디오,
연결 종료와 거치폰 카메라/마이크 중단을 확인.
위 명령에서 광고 경고가 재현되지 않으면 네이티브 테스트 광고에
한정된 이슈로 좁힐 수 있음. 배너에서도 같은 빈 화면이면
앱 화면 전환/실행 브랜치·플랫폼 뷰 로그를 추가 분석해야 함.

## 로컬 파일을 보존한 채 수정 브랜치 테스트

**현재 변경파일이 많으므로**, 자동으로 지우는 `reset --hard`나
`clean -fd`를 사용하지 않는다.

```bash
cd ~/Flutter/flutter_home_camera

# 현재 브랜치·로컬 변경 확인
git branch --show-current
git status -sb

# Firebase 설정, 앱 아이콘, 코드 수정 등을 임시 보관. -u는 untracked 포함.
git stash push -u -m "kyeobom-local-config-before-ad-validator-20261117"

git fetch origin
git switch -c fix/ios-native-ad-validator-viewer-20261117 \
  --track origin/fix/ios-native-ad-validator-viewer-20261117

# stash는 삭제하지 않는 'apply'로 보관된 작업 복원
git stash apply stash@{0}
git status -sb

flutter pub get
flutter analyze
flutter test

# iPhone: 네이티브 광고 자동 격리(배너) + 핵심 기능 확인
flutter run -d 00008130-001250C81AF3803A \
  --dart-define=KYEOBOM_AD_FORMAT=auto

# 광고 요청을 완전히 끈 상태로 영상·오디오만 추가 확인
flutter run -d 00008130-001250C81AF3803A \
  --dart-define=KYEOBOM_QA_DISABLE_ADS=true
```

**주의:** `git stash apply`에서 conflict가 발생하면 Flutter 빌드로
진행하지 말고 **그 충돌 로그를 전달**. 사용자 설정 파일은 백업 stash에
남아 있으므로 위험한 강제 재설정 금지. 추후 `git stash drop`도
보존 파일/설정을 확인한 이후에만 수행.

## Native Validator의 정확한 문제 진단

Google 공식 문서:
- <https://developers.google.com/admob/ios/native/validator>
- <https://support.google.com/admob/answer/9923650>
- <https://developers.google.com/admob/flutter/native/templates>

개발 중 **고의로 iOS 네이티브 재검사**를 할 때만:

```bash
flutter run -d 00008130-001250C81AF3803A \
  --dart-define=KYEOBOM_AD_FORMAT=native \
  --dart-define=KYEOBOM_ENABLE_IOS_NATIVE_ADS=true
```

Validator 알림이 뜨면 `See issues`를 눌러 **실제 위반 설명을 캡처**.
상세 위반이 확인되기 전에는 특정 네이티브 정책 오류가 해결됐다고
주장하면 안 됨. Validator의 `GADNativeAdValidatorEnabled=false` 설정은
사용하지 않는다.

## 합격 기준

- [ ] iOS 뷰어 홈에서 배너 테스트 광고가 화면을 가리지 않고 표시
- [ ] iOS 뷰어 실시간 보기 클릭 → 가로 영상이 정상 보임
- [ ] Android 거치폰 → iOS 뷰어폰 오디오 정상
- [ ] 앱 종료/홈 전환/연결 종료 후 카메라·마이크 자동 해제
- [ ] Android 뷰어에서도 배너/네이티브 광고 정상
- [ ] 웹RTC DataChannel/Firestore 쓰기 절감 동작 유지
- [ ] 별도 네이티브 실험에서 Validator 문제 원인 파악 후 해소
- [ ] 실광고 자동 노출 전 iOS 네이티브 Validator 재통과
