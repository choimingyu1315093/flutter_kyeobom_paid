#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/assets/baby_cry"
URL="https://storage.googleapis.com/mediapipe-models/audio_classifier/yamnet/float32/latest/yamnet.tflite"
mkdir -p "$DIR"
if [[ -s "$DIR/yamnet.tflite" && -s "$DIR/yamnet.sha256" ]]; then
  (cd "$DIR" && shasum -a 256 -c yamnet.sha256)
  echo "Reusing checked local QA model."
  exit 0
fi
TMP="$(mktemp "$DIR/.yamnet.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
curl --fail --location --proto '=https' --proto-redir '=https' --retry 2 --max-time 120 "$URL" -o "$TMP"
python3 - "$TMP" <<'PY'
import pathlib, sys, zipfile
p = pathlib.Path(sys.argv[1])
with p.open("rb") as f:
    header = f.read(8)
if p.stat().st_size < 100000 or header[4:8] != b"TFL3":
    raise SystemExit("Invalid TFLite model header/size")
# Official classifier embeds its label file as a ZIP associated file.
with zipfile.ZipFile(p) as z:
    matches = []
    for name in z.namelist():
        if not name.lower().endswith((".txt", ".csv")):
            continue
        lines = z.read(name).decode("utf-8-sig").splitlines()
        if len(lines) == 521 and lines[20].strip() == "Baby cry, infant cry":
            matches.append(name)
    if not matches:
        raise SystemExit("Unexpected YAMNet label map; refusing to use model")
print("TFLite header and 521-class label map verified.")
PY
mv "$TMP" "$DIR/yamnet.tflite"
(cd "$DIR" && shasum -a 256 yamnet.tflite > yamnet.sha256 && cat yamnet.sha256)
echo "Model ready for local QA only. Record hash for future release pinning."
