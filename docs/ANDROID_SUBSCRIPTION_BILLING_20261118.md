# 켜봄 Android 구독 화면·Play Billing 및 프리미엄 게이트 (1차)

브랜치 paid/android-subscriptions-account-20261118
원본 paid/integrated-20261117 미변경
무료 저장소 feature/free-hd-secure-pairing-recovery-20261117 미변경

## 구현

lib/kyeobom_subscription_screen.dart:
- 월간·연간 상품은 Google Play 가격을 조회하여 표시
- 실제 Android Play 결제 화면 연결
- 구독 내역 복원, Google Play 구독 관리·해지 링크
- iPhone 결제는 아직 제공하지 않음 (준비 중 안내)
- 가격, 자동 갱신, 계정 삭제 시 별도 해지 필요 안내
- 미완성 유료 자동화 기능을 완성된 혜택인 것처럼 표기하지 않음
- 내부 QA용 Android 실제 결제 활성화:
  --dart-define=KYEOBOM_ENABLE_ANDROID_IAP_QA=true
  기본값 false: 구매 버튼 비활성화

lib/kyeobom_billing_controller.dart:
- in_app_purchase purchaseStream을 먼저 등록
- Play 월간·연간 상품 정보 조회
- GooglePlayPurchaseParam applicationUserName = SHA256(Firebase UID)
- 서버 Callable verifyKyeobomGooglePlaySubscription에 Play 구매 토큰 전달
- 서버에서 구독·사용자·만료 확인 이후에만 구매 완료(acknowledgement)
- pending, canceled, error, server not found, invalid purchase 모두 프리미엄 잠금
- restorePurchases 수신 시에도 서버에 재검증
- refreshKyeobomSubscription에서 서버 측 최신 구독 상태 재확인

lib/kyeobom_premium_gate.dart:
- 서버에서 기록한 homecamEntitlements/{uid} 실시간 읽기.
- owner 일치/활성/유효기간 모두 충족해야 paid 위젯을 노출.
- Firestore 오류·오프라인·만료 시 fail-closed.
- 무료 QR, 실시간 영상 및 과열 보호는 잠그지 않음.
- **반드시 실제 유료 기능 백엔드도 서버 측 권한 체크 필요.**
- 기존 paid 저장소는 단일 계정 페어링 로직이므로 지금 상태에서
  바로 서비스 배포/무료 QR 브랜치 병합하면 안 됨.

## Play Console 외부 설정이 필요한 이유

위 함수는 Google Play Developer API에서 직접 확인하므로,
Play Console 구독상품/Google Cloud 서비스 계정 연결이 없으면
실제로 결제가 성공해도 서버 인증은 실패하도록 되어 있음.
현재 상품 ID:
- kyeobom_premium_monthly
- kyeobom_premium_yearly

구독 가격은 사전에 고정하지 않고 Play Store 실가격을 사용.
인앱 결제는 Google Play를 통해 설치된 내부 테스트 빌드에서 검증.
Firebase Cloud Functions는 운영 프로젝트에 아직 배포하지 않음.

## 기존 paid 프로젝트에 적용

~~~bash
cd ~/Flutter/flutter_kyeobom_paid
git fetch origin
git show origin/paid/android-subscriptions-account-20261118:tools/apply_android_subscription_qa_locally.py > tools/apply_android_subscription_qa_locally.py
python3 -m py_compile tools/apply_android_subscription_qa_locally.py
python3 tools/apply_android_subscription_qa_locally.py
flutter pub get
flutter test test/kyeobom_premium_entitlement_test.dart
flutter analyze --no-fatal-infos
git diff --check
~~~

개발용으로 화면만 확인 시 구매 버튼 비활성화:
~~~bash
flutter run --debug -d RFCT3225GCZ
~~~

실제 Play 결제 QA는 서명된 Play 내부 테스트 설치, 서버 함수
배포, 상품 등록 후에만:
~~~bash
flutter run --debug -d RFCT3225GCZ \
  --dart-define=KYEOBOM_ENABLE_ANDROID_IAP_QA=true
~~~

참고: Google Play 결제는 Play를 통해 설치한 빌드·테스터 조건에
영향을 받으므로 Flutter CLI로 설치한 빌드에서 실제 결제 성공을
보장할 수 없음. 결제 QA는 Play 내부 테스터 버전을 우선 사용.

## 아직 남은 것

- 실제 Play Console 상품·가격/기본 플랜 및 개발자 API 권한 연결
- 메인 무료 QR 인증 방식과 유료 저장소의 기능 충돌 없이 통합
- 유료 기능 각각의 서버 접근/데이터 보호 경로에서 entitlement 검사
- 구매 복원·갱신·해지·환불·홀드·계정 변경·재설치 테스트
- iOS 인앱결제 추후 별도 개발
- 개인정보 처리방침·약관 및 외부 계정 삭제 URL과 Play 출시 설문
- 프로덕션 Firebase Functions/Rules는 자동 배포하지 않음
