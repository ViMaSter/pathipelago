#!/bin/bash
# Generates an Archipelago multiworld from every *.yaml and *.apworld next to this script.
# Output: ./output/AP_<seed>.zip; host it with ./host.sh.
set -euo pipefail
shopt -s nullglob

AP_VERSION="${AP_VERSION:-0.6.8}"
DIR="$(cd "$(dirname "$0")" && pwd)"
AP="$DIR/.archipelago-$AP_VERSION"

PYTHON=""
for candidate in python3.13 python3.12 python3.11; do
    if command -v "$candidate" >/dev/null; then PYTHON="$candidate"; break; fi
done
if [[ -z "$PYTHON" ]]; then
    echo "Archipelago $AP_VERSION needs Python 3.11, 3.12 or 3.13." >&2
    exit 1
fi

yamls=("$DIR"/*.yaml)
if (( ${#yamls[@]} == 0 )); then
    echo "Put the player .yaml files next to $0." >&2
    exit 1
fi

if [[ ! -x "$AP/.venv/bin/python" ]]; then
    echo "Downloading Archipelago $AP_VERSION..."
    rm -rf "$AP"
    mkdir -p "$AP"
    curl -fsSL "https://github.com/ArchipelagoMW/Archipelago/archive/refs/tags/$AP_VERSION.tar.gz" \
        | tar xz -C "$AP" --strip-components 1
    "$PYTHON" -m venv "$AP/.venv"
fi

mkdir -p "$AP/custom_worlds"
rm -f "$AP/custom_worlds/"*.apworld
for world in "$DIR"/*.apworld; do
    cp "$world" "$AP/custom_worlds/"
done

# Generate.py reads every file in the players folder, so give it only the YAMLs.
rm -rf "$AP/players"
mkdir -p "$AP/players"
cp "${yamls[@]}" "$AP/players/"

cd "$AP"
"$AP/.venv/bin/python" ModuleUpdate.py --yes
SKIP_REQUIREMENTS_UPDATE=1 "$AP/.venv/bin/python" Generate.py \
    --player_files_path "$AP/players" --outputpath "$DIR/output" </dev/null
echo "Done. Host it with ./host.sh"
