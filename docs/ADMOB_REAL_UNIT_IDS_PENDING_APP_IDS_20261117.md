# 안내: AdMob 앱 ID도 연결 완료됨

이 문서는 광고 앱 ID를 받기 전의 상태를 기록한 이전 안내서야.

2026-11-17에 사용자가 Android 및 iOS AdMob **앱 ID 2개를 모두 제공**했고,
광고 단위 10개와 함께 플랫폼 및 Flutter 코드에 실제 ID를 반영했어.

현재 최종 상태 및 Mac QA 명령어는
[ADMOB_REAL_IDS_CONNECTED_20261117.md](ADMOB_REAL_IDS_CONNECTED_20261117.md)를 확인해.

작업 브랜치: `feature/admob-real-ids-20261117`
실제 광고 송출은 `KYEOBOM_ENABLE_LIVE_ADS=true`가 설정된 릴리스에서만 요청돼.
기본 릴리스는 광고를 요청하지 않고 개발 빌드는 공식 테스트 광고 단위만 사용해.
