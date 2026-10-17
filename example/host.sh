#!/bin/bash
# Hosts the newest ./output/AP_<seed>.zip from generate.sh on this machine.
# Players connect to <this machine's address>:38281. Stop with /exit or Ctrl+C;
# progress is saved next to the zip and resumes on the next start.
set -euo pipefail
shopt -s nullglob

AP_VERSION="${AP_VERSION:-0.6.8}"
PORT="${PORT:-38281}"
DIR="$(cd "$(dirname "$0")" && pwd)"
AP="$DIR/.archipelago-$AP_VERSION"

if [[ ! -x "$AP/.venv/bin/python" ]]; then
    echo "Run ./generate.sh first." >&2
    exit 1
fi

seeds=("$DIR"/output/AP_*.zip)
if (( ${#seeds[@]} == 0 )); then
    echo "No output/AP_*.zip found. Run ./generate.sh first." >&2
    exit 1
fi
SEED="$(ls -t "${seeds[@]}" | head -n 1)"

# Patch files (for example .apred for Pokemon Red) for the other players.
# Exit code 11 means the seed has none (e.g. Stardew Valley uses a mod instead).
unzip -o -q "$SEED" -x '*.archipelago' '*_Spoiler.txt' -d "$DIR/output" || [[ $? -eq 11 ]]

echo "Hosting $(basename "$SEED") on port $PORT."
echo "Patches: $DIR/output"
cd "$AP"
SKIP_REQUIREMENTS_UPDATE=1 exec "$AP/.venv/bin/python" MultiServer.py "$SEED" \
    --host 0.0.0.0 --port "$PORT"
