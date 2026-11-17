#!/bin/bash
# Renders the speech benchmark corpus (HushTests/Fixtures/Speech/filler-clips.json)
# as 16 kHz mono clips with the macOS voices, one <id>.wav per clip.
#
#   scripts/speech-benchmark-clips.sh <output-folder>
#
# Synthetic voices prove the pipeline and compare engines on equal input; they do
# not replace real recordings. Keep real recordings outside Git, named <id>.wav.
set -euo pipefail

out="${1:?usage: $0 <output-folder>}"
corpus="$(cd "$(dirname "$0")/.." && pwd)/Hush/HushTests/Fixtures/Speech/filler-clips.json"
mkdir -p "$out"

/usr/bin/python3 -I - "$corpus" "$out" <<'PY'
import json, subprocess, sys
corpus, out = sys.argv[1], sys.argv[2]
for clip in json.load(open(corpus, encoding="utf-8"))["clips"]:
    path = f"{out}/{clip['id']}.wav"
    subprocess.run(["say", "-v", clip["voice"], "-o", path, "--data-format=LEF32@16000", clip["spoken"]], check=True)
    print(path)
PY
