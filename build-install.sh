#!/bin/bash
# Developer loop: test, build, and install the mod ZIP into the full game's local mods folder.
# Players should subscribe on the Steam Workshop instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
GAME="$HOME/Library/Application Support/Steam/steamapps/common/Pathogenic/Pathogenic.app"
GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
PYTHON="${PYTHON:-python3}"
BUILD_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --game) GAME="${2:?--game needs an absolute .app path}"; shift 2 ;;
        --godot) GODOT="${2:?--godot needs an executable path}"; shift 2 ;;
        --build-only) BUILD_ONLY=1; shift ;;
        --help)
            echo "Usage: ./build-install.sh [--build-only] [--game /path/Pathogenic.app] [--godot /path/Godot]"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

command -v "$PYTHON" >/dev/null
[[ -x "$GODOT" ]] || { echo "Godot is required for validation; set GODOT or use --godot." >&2; exit 1; }
"$PYTHON" "$ROOT/tools/test.py" --godot "$GODOT"
"$PYTHON" "$ROOT/tools/build.py"
if [[ "$BUILD_ONLY" == 1 ]]; then
    echo "Build and isolated tests passed. No game files changed."
    exit 0
fi
if pgrep -x Pathogenic >/dev/null; then
    echo "Quit Pathogenic before installing." >&2
    exit 1
fi
"$PYTHON" "$ROOT/tools/install.py" --game "$GAME"
echo "Start Pathogenic from Steam and open Settings > MultiworldGG."
