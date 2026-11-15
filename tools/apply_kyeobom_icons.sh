#!/usr/bin/env bash
# Apply the *user-provided* icon from ~/Downloads to this existing Flutter app.
# Requires macOS built-in sips and Python 3. Does not alter signing/Firebase.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-$HOME/Downloads/app_icon_real.png}"

if [[ ! -f "$SOURCE" ]]; then
  SOURCE="$(find "$HOME/Downloads" -maxdepth 4 -type f -iname 'app_icon_real.png' -print -quit 2>/dev/null || true)"
fi
if [[ -z "$SOURCE" || ! -f "$SOURCE" ]]; then
  echo "앱 아이콘 PNG를 찾지 못했습니다." >&2
  echo "실행 예: bash tools/apply_kyeobom_icons.sh \"$HOME/Downloads/app_icon_real.png\"" >&2
  echo "AppIcons 폴더에 PNG가 있다면 그 PNG의 전체 경로를 인자로 전달하세요." >&2
  exit 1
fi

command -v sips >/dev/null || { echo "macOS sips가 필요합니다." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3가 필요합니다." >&2; exit 1; }

# Check exact file type and avoid silently stretching a non-square asset.
python3 - "$SOURCE" <<'PY'
import struct
import sys
from pathlib import Path

p = Path(sys.argv[1])
header = p.open("rb").read(24)
if header[:8] != b"\\x89PNG\\r\\n\\x1a\\n":
    sys.exit("원본은 PNG 형식이어야 합니다: " + str(p))
width, height = struct.unpack(">II", header[16:24])
if width != height:
    sys.exit(f"아이콘은 정사각형이어야 합니다: {width}x{height}")
if width < 512:
    print(f"경고: {width}x{height} 원본은 iOS 1024px 아이콘에서 흐릴 수 있습니다.")
print(f"사용자 앱 아이콘 확인: {width}x{height}")
PY

mkdir -p "$ROOT/assets/branding"
cp "$SOURCE" "$ROOT/assets/branding/app_icon_real.png"

# Android launcher icons: overwrite only default project icon files.
for entry in "mdpi:48" "hdpi:72" "xhdpi:96" "xxhdpi:144" "xxxhdpi:192"; do
  density="${entry%%:*}"
  pixels="${entry##*:}"
  outdir="$ROOT/android/app/src/main/res/mipmap-$density"
  mkdir -p "$outdir"
  sips -s format png -z "$pixels" "$pixels" "$SOURCE" \
    --out "$outdir/ic_launcher.png" >/dev/null
done

# iOS home-screen icons must be opaque, so flatten optional alpha with a
# high-quality JPEG intermediate, then export PNG at each required size.
tempdir="$(mktemp -d)"
trap 'rm -rf "$tempdir"' EXIT
sips -s format jpeg -s formatOptions best "$SOURCE" \
  --out "$tempdir/opaque.jpg" >/dev/null
sips -s format png "$tempdir/opaque.jpg" \
  --out "$tempdir/opaque.png" >/dev/null

APPICON="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$APPICON"

python3 - "$tempdir/opaque.png" "$APPICON" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

source = Path(sys.argv[1])
destination = Path(sys.argv[2])

# idiom, base point size, scale
specs = [
    ("iphone", "20", 2), ("iphone", "20", 3),
    ("iphone", "29", 2), ("iphone", "29", 3),
    ("iphone", "40", 2), ("iphone", "40", 3),
    ("iphone", "60", 2), ("iphone", "60", 3),
    ("ipad", "20", 1), ("ipad", "20", 2),
    ("ipad", "29", 1), ("ipad", "29", 2),
    ("ipad", "40", 1), ("ipad", "40", 2),
    ("ipad", "76", 1), ("ipad", "76", 2),
    ("ipad", "83.5", 2),
    ("ios-marketing", "1024", 1),
]
images = []
for idiom, size, scale in specs:
    side = int(float(size) * scale)
    filename = f"Icon-App-{idiom}-{size}@{scale}x.png"
    out = destination / filename
    subprocess.run(
        ["sips", "-s", "format", "png", "-z", str(side), str(side),
         str(source), "--out", str(out)],
        check=True, stdout=subprocess.DEVNULL,
    )
    images.append({
        "idiom": idiom,
        "size": f"{size}x{size}",
        "scale": f"{scale}x",
        "filename": filename,
    })
(destination / "Contents.json").write_text(
    json.dumps({"images": images, "info": {"author": "xcode", "version": 1}},
               ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
print("iOS AppIcon:", len(images), "images")
PY

echo ""
echo "완료: 실제 PNG를 기반으로 켜봄 앱 아이콘을 생성했습니다."
echo "원본: $SOURCE"
echo "Android: android/app/src/main/res/mipmap-*/ic_launcher.png"
echo "iOS: ios/Runner/Assets.xcassets/AppIcon.appiconset"
echo "Flutter 로고: assets/branding/app_icon_real.png"
echo "다음: flutter pub get && flutter run -d <기기ID>"
