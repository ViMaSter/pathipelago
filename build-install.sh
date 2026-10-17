#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
GAME="$HOME/Library/Application Support/Steam/steamapps/common/Pathogenic Demo/Pathogenic.app"
GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
PYTHON="${PYTHON:-python3}"
GDRE="${GDRE:-/Applications/Godot RE Tools.app/Contents/MacOS/Godot RE Tools}"
VERIFY=0
BUILD_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --game) GAME="${2:?--game needs an absolute .app path}"; shift 2 ;;
        --godot) GODOT="${2:?--godot needs an executable path}"; shift 2 ;;
        --gdre) GDRE="${2:?--gdre needs the GDRE Tools executable path}"; shift 2 ;;
        --verify) VERIFY=1; shift ;;
        --build-only) BUILD_ONLY=1; shift ;;
        --help)
            echo "Usage: ./build-install.sh [--verify] [--build-only] [--game /path/Pathogenic.app] [--godot /path/Godot] [--gdre /path/GDRE]"
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
[[ "$(uname -s)" == Darwin ]] || { echo "The installer currently supports the verified macOS demo only." >&2; exit 1; }
[[ "$GAME" == /* && -f "$GAME/Contents/Resources/Pathogenic.pck" ]] || {
    echo "Game app not found: $GAME" >&2; exit 1;
}
[[ -x "$GDRE" ]] || {
    echo "GDRE Tools 2.7.4 is required to build a private modded app. Set GDRE or use --gdre." >&2
    exit 1
}
if pgrep -x Pathogenic >/dev/null; then
    echo "Quit Pathogenic before installing." >&2
    exit 1
fi
if [[ "$VERIFY" == 1 ]]; then
    [[ -t 0 ]] || { echo "--verify requires a terminal to confirm Steam has finished." >&2; exit 1; }
    open "steam://validate/4029380"
    echo "Steam verification requested; this does NOT mean verification has completed."
    echo "Wait for Steam to finish verifying Pathogenic Demo. Type VERIFIED to continue:"
    read -r answer
    [[ "$answer" == VERIFIED ]] || { echo "Installation cancelled." >&2; exit 1; }
else
    echo "Steam verification skipped (use --verify to request it)."
fi
if pgrep -x Pathogenic >/dev/null; then
    echo "Quit Pathogenic before installing." >&2
    exit 1
fi
"$PYTHON" "$ROOT/tools/build_demo.py" "$GAME" --gdre "$GDRE"
echo
echo "Private modded app built; native bootstrap and packed shop hook verified."
echo "You can start the modded game using: $ROOT/launch-modded.command"
echo "Keep Steam running. Starting the normal Steam shortcut starts the UNMODDED game."
echo "The official game, other mods and original saves were not cleared or changed."
echo "Open Settings > Archipelago in the game to connect to a generated Pathogenic Demo slot."
echo "Bootstrap tests do not prove visual gameplay compatibility; see README.md for validation limits."
