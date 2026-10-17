#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SESSION_FILES="$SESSION_FILES"
PYTHON="$SESSION_FILES/ap311/bin/python"
RUNTIME="$SESSION_FILES/ap-runtime"
CAMPAIGN="${1:-$ROOT/dist/multiworld/AP_72893771011827805672.zip}"

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [absolute-path-to-generated-multiworld.zip]" >&2
    exit 2
fi
if [[ ! -x "$PYTHON" || ! -f "$RUNTIME/MultiServer.py" ]]; then
    echo "The prepared Archipelago runtime is missing: $SESSION_FILES" >&2
    exit 1
fi
if [[ "$CAMPAIGN" != /* || ! -f "$CAMPAIGN" ]]; then
    echo "Provide an existing absolute campaign path: $CAMPAIGN" >&2
    exit 1
fi

echo "Starting local-only Archipelago on 127.0.0.1:38281."
echo "Pathogenic: ws://127.0.0.1:38281, slot Pathogenic1"
echo "Pokemon: 127.0.0.1:38281, slot PkmnPlayer"
echo "Progress saves beside the campaign archive. Use /exit or Ctrl+C to stop."
cd "$RUNTIME"
export SKIP_REQUIREMENTS_UPDATE=1
exec "$PYTHON" MultiServer.py "$CAMPAIGN" --host 127.0.0.1 --port 38281
