#!/usr/bin/env bash
# Force-reimport hell's map_base chunks in this Mac checkout, as pc_sync.sh does on the PC: the import
# script (hot rock material, lightmap UV2) is code, not an import param, so a pull alone never re-runs it.
#   tools/mac_reimport.sh        -- run after every pull; restart an open editor afterwards
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
rm -f "$HERE"/.godot/imported/map_base_*.glb-*
"$GODOT" --headless --import --path "$HERE" > "$HERE/.godot/mac_import.txt" 2>&1 || true
echo "mac at $(git -C "$HERE" log --oneline -1) | import errors: $(grep -c ERROR "$HERE/.godot/mac_import.txt" || true)"
