#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$ROOT/local.env" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT/local.env"
fi
SESSION_FILES="${SESSION_FILES:?Set SESSION_FILES in $ROOT/local.env to the prepared Archipelago runtime folder}"
PYTHON="$SESSION_FILES/ap311/bin/python"
RUNTIME="$SESSION_FILES/ap-runtime"
CAMPAIGN="${1:-$ROOT/dist/multiworld/AP_69318679617106091104.zip}"

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [absolute-path-to-generated-multiworld.zip]" >&2
    exit 2
fi
if [[ ! -x "$PYTHON" || ! -f "$RUNTIME/WebHost.py" ]]; then
    echo "The prepared Archipelago runtime is missing: $SESSION_FILES" >&2
    exit 1
fi
if [[ "$CAMPAIGN" != /* || ! -f "$CAMPAIGN" ]]; then
    echo "Provide an existing absolute campaign path: $CAMPAIGN" >&2
    exit 1
fi
if lsof -nP -iTCP:38281 -sTCP:LISTEN >/dev/null 2>&1 || lsof -nP -iTCP:38280 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port 38280 or 38281 is busy. Stop start-local-server.command (or an older WebHost) first." >&2
    exit 1
fi

echo "Starting local-only Archipelago WebHost (room, tracker, server log) on 127.0.0.1."
echo "Pathogenic: ws://127.0.0.1:38281, slot Pathogenic1"
echo "Pokemon: 127.0.0.1:38281, slot PkmnPlayer"
echo "Room progress lives in $ROOT/local-webhost. Press Ctrl+C to stop."
export SKIP_REQUIREMENTS_UPDATE=1
exec "$PYTHON" "$ROOT/tools/local_webhost.py" --runtime "$RUNTIME" --data "$ROOT/local-webhost" --campaign "$CAMPAIGN"
