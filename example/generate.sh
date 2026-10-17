#!/bin/bash
# Generate locally, then upload the resulting ZIP at https://multiworld.gg/uploads.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

for candidate in "${PYTHON:-python3.13}" python3.12 python3; do
    if command -v "$candidate" >/dev/null && "$candidate" -c \
        'import sys; v = sys.version_info; sys.exit(not ((3, 13, 5) <= v < (3, 14) or (3, 12, 7) <= v < (3, 13)))'; then
        exec "$candidate" "$DIR/generate.py" "$DIR"
    fi
done
echo "MultiworldGG generation needs Python 3.13.5+ (below 3.14), or 3.12.7+. Set PYTHON to its executable." >&2
exit 1
