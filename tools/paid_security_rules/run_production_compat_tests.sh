#!/usr/bin/env bash
# Run the exact published-free security rules plus paid health subrules.
# Local emulator only. Never deploy and never modify firestore.rules.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
export KYEOBOM_TEST_RULES_PATH="$ROOT/tools/paid_security_rules/production_free_additive.rules"
if [[ ! -f "$KYEOBOM_TEST_RULES_PATH" ]]; then
  echo "검증용 운영 규칙 파일이 없습니다." >&2
  exit 2
fi
echo "실제 운영 규칙 그대로 + 상태/FCM 하위 규칙 3개만 검증합니다."
echo "실제 Firebase 배포 없음 · 운영 Firestore 접근 없음"
bash "$ROOT/tools/paid_security_rules/run_emulator_tests.sh"
