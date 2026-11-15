#!/usr/bin/env bash
# Apply real AdMob App IDs to native manifests after approval in AdMob.
# These identifiers are NOT ad-unit IDs. The Dart production opt-in is separate.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -ne 2 ]]; then
  echo "Usage: bash tools/configure_kyeobom_admob_app_ids.sh <android_app_id> <ios_app_id>" >&2
  echo "Example App ID format: ca-app-pub-1234567890123456~1234567890" >&2
  exit 2
fi
python3 - "$ROOT" "$1" "$2" <<'PY'
import pathlib
import re
import sys

root, android_id, ios_id = sys.argv[1:]
pattern = re.compile(r"^ca-app-pub-[0-9]{16}~[0-9]{10}$")
google_test = "ca-app-pub-3940256099942544"
for key, value in (("Android", android_id), ("iOS", ios_id)):
    if not pattern.fullmatch(value) or value.startswith(google_test):
        raise SystemExit(f"{key} 앱 ID가 올바르지 않습니다. AdMob '앱 ID'를 사용하세요.")

android = pathlib.Path(root) / "android/app/src/main/AndroidManifest.xml"
ios = pathlib.Path(root) / "ios/Runner/Info.plist"
android_text = android.read_text(encoding="utf-8")
ios_text = ios.read_text(encoding="utf-8")

android_pattern = re.compile(
    r'(<meta-data\s+android:name="com.google.android.gms.ads.APPLICATION_ID"\s+android:value=")[^"]+("/>)'
)
ios_pattern = re.compile(
    r'(<key>GADApplicationIdentifier</key>\s*<string>)[^<]+(</string>)'
)

android_result, android_hits = android_pattern.subn(
    lambda match: match.group(1) + android_id + match.group(2),
    android_text, count=1,
)
ios_result, ios_hits = ios_pattern.subn(
    lambda match: match.group(1) + ios_id + match.group(2),
    ios_text, count=1,
)
if android_hits != 1 or ios_hits != 1:
    raise SystemExit("AdMob 설정 위치를 찾지 못했습니다. 원본 파일을 보존했습니다.")

android.write_text(android_result, encoding="utf-8")
ios.write_text(ios_result, encoding="utf-8")
print("AdMob 네이티브 앱 ID 설정 완료. Android/iOS 실제 ID로 변경됐습니다.")
print("주의: 런처 앱 이름, Firebase, 영상 연결 코드는 변경하지 않았습니다.")
print("이제 별도 광고 단위 ID와 --dart-define=KYEOBOM_ENABLE_LIVE_ADS=true도 필요합니다.")
PY
