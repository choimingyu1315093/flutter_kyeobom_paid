#!/usr/bin/env bash
# Run isolated, empty Auth+Firestore emulators for two physical phones.
# Never touches production data and never deploys security rules.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
QA_DIR="$ROOT/tools/paid_security_rules"
RULES_LOCAL="$QA_DIR/firestore.rules"
if [[ ! -f "$ROOT/firestore.rules" ]]; then
  echo "안전 중단: 기존 루트 firestore.rules가 없습니다." >&2
  exit 2
fi
if [[ -L "$RULES_LOCAL" ]]; then
  echo "안전 중단: QA rules 경로가 심볼릭 링크입니다. 수동 확인이 필요합니다." >&2
  exit 2
fi
if [[ -e "$RULES_LOCAL" ]] && ! cmp -s "$ROOT/firestore.rules" "$RULES_LOCAL"; then
  echo "안전 중단: QA 임시 규칙이 루트 규칙과 다릅니다. 덮어쓰지 않습니다." >&2
  exit 2
fi
if [[ ! -f "$ROOT/firestore.rules" || ! -f "$ROOT/android/app/google-services.json" ]]; then
  echo "firestore.rules 또는 Android Firebase 설정을 찾을 수 없습니다." >&2
  exit 2
fi
PROJECT_ID="$(python3 - "$ROOT/android/app/google-services.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f)['project_info']['project_id'])
PY
)"
if [[ -z "$PROJECT_ID" ]]; then
  echo "Firebase projectId 확인 실패" >&2
  exit 2
fi
if ! command -v firebase >/dev/null 2>&1; then
  echo "firebase CLI를 찾지 못했습니다." >&2
  exit 2
fi

# Crash-safe reuse: a previous terminal closure may have left this exact
# rules copy. Preserve pre-existing files; only clean up our own copy.
created_rules=false
if [[ ! -e "$RULES_LOCAL" ]]; then
  cp -- "$ROOT/firestore.rules" "$RULES_LOCAL"
  created_rules=true
else
  echo "이전 QA 규칙 복사본이 원본과 같아서 안전하게 재사용합니다."
fi
cleanup() {
  if [[ "$created_rules" == true ]]; then
    if cmp -s "$ROOT/firestore.rules" "$RULES_LOCAL"; then
      rm -f -- "$RULES_LOCAL"
    else
      echo "QA 규칙 복사본이 변경되어 자동 제거하지 않습니다." >&2
    fi
  fi
}
trap cleanup EXIT
cd "$QA_DIR"

printf '\n켜봄 실기기 전용 로컬 QA\nFirebase project ID (로컬 에뮬레이터의 ID): %s\n' "$PROJECT_ID"
echo "실제 Firebase 서버에 규칙·데이터를 배포하지 않습니다."
echo "⚠️  Auth/Firestore 에뮬레이터가 Wi-Fi LAN(0.0.0.0)에 열립니다."
echo "집/사무실 신뢰 가능한 Wi-Fi에서만 사용하고, 테스트 종료 후 Ctrl+C."
echo "실기기에서는 반드시 KYEOBOM_USE_FIREBASE_EMULATORS=true로 실행하세요."
echo
firebase emulators:start \
  --config "$QA_DIR/firebase.device_qa.json" \
  --project "$PROJECT_ID" \
  --only auth,firestore
