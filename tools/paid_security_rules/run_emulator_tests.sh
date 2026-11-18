#!/usr/bin/env bash
# Run the real repository Firestore rules against the local Firebase emulator.
# Never deploy rules or touch the user's Firebase production project.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
RULES_SOURCE="$REPO_ROOT/firestore.rules"
RULES_LOCAL="$SCRIPT_DIR/firestore.rules"

if [[ ! -f "$RULES_SOURCE" ]]; then
  echo "오류: 기존 firestore.rules 파일을 찾지 못했습니다." >&2
  exit 2
fi
if [[ -L "$RULES_LOCAL" ]]; then
  echo "안전 중단: 기존 QA 규칙이 심볼릭 링크입니다." >&2
  exit 2
fi
if [[ -e "$RULES_LOCAL" ]] && ! cmp -s "$RULES_SOURCE" "$RULES_LOCAL"; then
  echo "안전 중단: 기존 QA 규칙이 원본과 다릅니다. 덮어쓰지 않습니다." >&2
  exit 2
fi

created_rules=false
if [[ ! -e "$RULES_LOCAL" ]]; then
  cp -- "$RULES_SOURCE" "$RULES_LOCAL"
  created_rules=true
else
  echo "기존 QA 규칙이 원본과 일치하므로 재사용합니다."
fi
cleanup() {
  if [[ "$created_rules" == true ]]; then
    if cmp -s "$RULES_SOURCE" "$RULES_LOCAL"; then
      rm -f -- "$RULES_LOCAL"
    else
      echo "QA 규칙이 변경되어 자동 삭제하지 않습니다." >&2
    fi
  fi
}
trap cleanup EXIT

cd "$SCRIPT_DIR"
if ! cmp -s "$RULES_SOURCE" "$RULES_LOCAL"; then
  echo "오류: 테스트 규칙 복사본이 원본과 다릅니다." >&2
  exit 2
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "오류: Firebase CLI(firebase)를 찾지 못했습니다." >&2
  exit 2
fi

echo "테스트 대상: $RULES_SOURCE (복사본은 종료 시 자동 제거)"
echo "Firebase 데모 프로젝트에서만 Firestore 에뮬레이터를 실행합니다."
firebase emulators:exec \
  --project demo-kyeobom-paid-security \
  --only firestore \
  'npm test'
