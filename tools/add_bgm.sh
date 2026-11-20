#!/bin/bash
# Add a background-music track: re-encode to 44.1 kHz stereo AAC (the format the player runs at)
# and drop it into Resources/Audio. The app picks up every audio file in that folder automatically.
# Usage: tools/add_bgm.sh input.mp3 [output-name]   (then add its licence row to docs/licenses.md)
set -euo pipefail
in="$1"; name="${2:-$(basename "${in%.*}")}"
out="$(cd "$(dirname "$0")/.." && pwd)/Resources/Audio/${name}.m4a"
ffmpeg -y -loglevel error -i "$in" -vn -c:a aac -b:a 144k -ac 2 -ar 44100 "$out"
echo "added $out"
