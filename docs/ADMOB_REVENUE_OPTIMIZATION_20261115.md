# 켜봄 — 광고 수익 최적화 개발 / AdMob 2026-11-15

기준: `feature/cost-optimization-datachannel-20261115`
작업 브랜치: `feature/ad-revenue-optimization-20261115`
광고 SDK: `google_mobile_ads ^9.2.0` (Flutter >=3.38.1, Dart >=3.10)

## 구현 상태

- [x] Android 및 iOS Google 공식 **샘플 AdMob 앱 ID** 플랫폼 설정
- [x] 샘플 배너/네이티브 광고 단위 ID 연동
- [x] 뷰어폰 홈 **하단 1개 광고**만 표시
- [x] 네이티브 소형 템플릿 vs 대형 적응형 배너 **설치 단위 50:50 A/B**
- [x] 네이티브 광고 로딩 실패 시 배너로 **1회 대체**
- [x] 앱 설치 단위 A/B 배정만 local SharedPreferences 저장 (Firebase 없음)
- [x] SDK의 UMP 동의 가능 여부 확인; 승인되지 않았으면 요청 금지
- [x] 동의가 필요한 경우 영상 확인을 가로막지 않는 **선택 버튼**
- [x] UMP 개인정보 설정 재열기 버튼(필요한 경우)
- [x] 로컬 이벤트: 로드/노출/클릭/추정 유료 이벤트 집계 (Firebase 없음)
- [x] 릴리스에서 명시적 라이브 광고 허용 및 실제 ID 검증 전까지 광고 요청 차단
- [x] 거치폰·실시간 영상·로그인·회원가입·기기 역할 선택에는 광고 없음
- [x] 기존 WebRTC 영상·음질·오디오·화면 회전·DataChannel·Firestore 비용 절감 유지
- [ ] 실제 AdMob 앱 등록 및 **고유 앱/광고 단위 ID** 연결(소유자가 해야 함)
- [ ] AdMob 개인정보 보호/메시지 설정 및 스토어 개인정보 항목 등록
- [ ] Android/iPhone 실기기 테스트 광고 QA
- [ ] 출시 후 A/B eCPM·실제 노출률 비교 및 최적 배치 결정
- [ ] 필요성이 입증되면 앱 오프닝 광고 실험(현재 미구현)

## 왜 종료 시 전면 광고를 넣지 않았나

실시간 영상 중 또는 연결 직전 강제 광고는 사용 목적을 방해함.
사용자가 앱을 홈으로 보내거나 종료하면 광고 자체가 노출되지 않을 수 있음.
종료 순간의 전면 광고는 AdMob 구현 가이드상 허용되지 않음.
앱 오프닝 광고도 현재는 비활성: 빠른 홈캠 확인이 먼저.

## 광고가 실제로 표시되는 곳

뷰어폰의 세로 홈 대시보드, 모든 연결 버튼과 개인정보 안내 뒤에 광고
레이블을 붙여 보여 줌. `실시간 보기`를 누르면 즉시 광고 위젯이 제거돼
플랫폼 뷰 리소스가 dispose됨. 화면 전체가 가로로 바뀌면 광고 없음.
거치폰 대기 및 카메라 송출 화면에서는 광고 SDK 초기화도 요청하지 않음.

## 테스트 실행

```bash
cd ~/Flutter/flutter_home_camera
git status --short
git fetch origin
git switch --track origin/feature/ad-revenue-optimization-20261115

flutter pub get
flutter analyze
flutter test

# Android 기본 A/B 테스트(실제 영상 동작 유지)
flutter run -d RFCT3225GCZ --dart-define=KYEOBOM_AD_FORMAT=native

# iPhone 다른 기기에 배너 테스트
flutter run -d 00008130-001250C81AF3803A \
  --dart-define=KYEOBOM_AD_FORMAT=banner
```

이전 브랜치에서 local `android/app/build.gradle.kts`,
`ios/Runner.xcodeproj/project.pbxproj`, `pubspec.lock` 등
개인 설정이 수정돼 있을 수 있음. `git reset --hard`,
`git clean -fd`로 지우지 말고 상태 확인 후 전환할 것.

### 광고 QA 포인트

1. 뷰어폰 홈에 광고 레이블 및 실제 **Test Ad**가 표시되는지 확인.
   UMP가 사용자 동의를 요구하면 '광고 및 개인정보 선택'을 통해 처리.
   동의하지 않아도 실시간 영상은 여전히 무료로 열려야 함.
2. `KYEOBOM_AD_FORMAT=native` → 소형 네이티브 광고.
3. `KYEOBOM_AD_FORMAT=banner` → 적응형 배너 광고.
4. 광고 로딩 실패 시 화면은 깨지지 않고 실시간 보기 버튼을 즉시 누를 수 있음.
5. 실시간 보기 도중 **광고 없음**, 음질 정상, 180도 회전·줌 정상.
6. 거치폰의 어두운 대기 화면에 광고 없음, 마이크·발열 증가 없어야 함.
7. 뷰어폰 내부 '광고 QA · native/banner' 버튼을 눌러 로컬 로드/노출/클릭
   집계를 확인. 테스트 광고를 억지로 반복 클릭하면 안 됨.
8. 양쪽 모두 Android/iOS를 바꿔 영상·오디오 1차 연결 시험.
9. Firebase Firestore 주기적 쓰기 여전히 DataChannel 방식인지 확인.
10. 실시간 시청을 길게 해도 광고 SDK가 별도로 요청하지 않는지 확인.

**주의:** 로컬에서 개발자가 직접 실제 광고를 반복 클릭하면
invalid traffic 정책 위반 위험이 있음. 반드시 테스트용 광고를 사용.

## 라이브 광고 출시 이전 — 반드시 할 일

1. <https://admob.google.com> 에서 Android와 iOS 각각 **켜봄 앱** 등록.
2. 각 앱의 **앱 ID** (`~` 포함) 2개와 네이티브 및 배너의
   **광고 단위 ID** (`/` 포함) 4개 생성.
3. 테스트 앱 ID를 실제 ID로 교체:
   ```bash
   bash tools/configure_kyeobom_admob_app_ids.sh \
     "ca-app-pub-1234567890123456~1234567890" \
     "ca-app-pub-0987654321098765~0987654321"
   ```
   위 숫자는 **형식 예시**이므로 실제 AdMob의 두 앱 ID로 바꿔야 함.
4. Google AdMob의 Privacy & messaging에서 필요한 UMP 개인정보
   메시지를 만들고, GDPR/EEA/미국 주별 요구사항을 검토.
5. Apple App Privacy/ATT 정책, Google Play Data safety, 개인정보처리방침,
   아동 대상 여부, 광고 노출 정책 등을 실제 데이터 처리 기준으로 검토.
6. 실제 광고 단위 ID로 릴리스 빌드. Dart define 예:
   ```bash
   flutter build appbundle --release \
     --dart-define=KYEOBOM_ENABLE_LIVE_ADS=true \
     --dart-define=KYEOBOM_ANDROID_ADMOB_APP_ID=ACTUAL_ANDROID_APP_ID \
     --dart-define=KYEOBOM_ANDROID_ADMOB_NATIVE_ID=ACTUAL_ANDROID_NATIVE_ID \
     --dart-define=KYEOBOM_ANDROID_ADMOB_BANNER_ID=ACTUAL_ANDROID_BANNER_ID

   flutter build ipa --release \
     --dart-define=KYEOBOM_ENABLE_LIVE_ADS=true \
     --dart-define=KYEOBOM_IOS_ADMOB_APP_ID=ACTUAL_IOS_APP_ID \
     --dart-define=KYEOBOM_IOS_ADMOB_NATIVE_ID=ACTUAL_IOS_NATIVE_ID \
     --dart-define=KYEOBOM_IOS_ADMOB_BANNER_ID=ACTUAL_IOS_BANNER_ID
   ```
7. 빌드 전 네이티브 AndroidManifest/Info.plist의 앱 ID와 Dart define 앱 ID가
   일치하는지 재확인. 서로 다르면 광고 수익이 발생하지 않을 수 있음.

릴리스 가드: 위 단계를 완료하지 않거나
`KYEOBOM_ENABLE_LIVE_ADS=true`가 없으면 **라이브 광고 요청 0회**.
Debug/Profile는 구글 공식 Demo 앱/단위 ID만 요청.

## 운영비 / 수익 분석

- 로컬 A/B 배정과 QA 이벤트는 SharedPreferences에만 기록.
  광고 앱 이벤트·영상·음성·로그인/계정 정보를 Firebase로 광고 수집하지 않음.
- AdMob의 실제 보고서에서 **형식별 실노출/수익/eCPM**을 비교할 것.
- `onPaidEvent`는 계정 지원/허용 여부에 따라 값이 없을 수 있음.
  로컬 `paid` 집계는 확정 수익이 아니며 AdMob 정산이 기준.
- 서버 운영비는 기존 P2P 우선/Firestore 하트비트 최적화 유지.
- 매월 **광고 수익 - Firestore/TURN 등 실제 운영비**를 검증한 후 A/B 결과를 적용.
- 배너/네이티브 둘 다 무조건 더 많은 광고를 보여 주는 전략이 아니라
  **광고 1개 자리**에서 단가와 노출 성공률이 좋은 형식을 선택하는 실험.
- 앱 오프닝/리워드/전면 광고는 실험 데이터 없는 상태에서는 추가하지 않음.

## 공식 문서

- <https://developers.google.com/admob/flutter/quick-start>
- <https://developers.google.com/admob/flutter/native/templates>
- <https://developers.google.com/admob/flutter/privacy>
- <https://support.google.com/admob/answer/6201362>

현재 결과: **코드 구현 및 정적 검토**. Flutter/Android/iPhone 빌드와
AdMob 계정/기기 실기기 실험은 사용자의 Mac에서 최종 확인 필요.
