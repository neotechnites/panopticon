#!/usr/bin/env bash
# Poster frames and the dailies page for a project, on the PC.
#
#   tools/content/dailies.sh <project> [--out NAME.html]
#
# Thumbs first (final\thumbs\<clip>.jpg, 360 wide, only when missing or stale),
# then final\index.html (or final\NAME.html): the latest cut with its timing
# table and script lines, the external footage with its credit lines from
# external\SOURCES.md, every shot in the brief with a file: line in order (id,
# Ryan's words, seconds), and any other take in final\. Every video is
# preload="none" with a poster and a cache-busting ?v= on its src. View it
# through tools/content/serve.sh: http://127.0.0.1:8765/final/index.html
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/dailies.sh <project> [--out NAME.html]}"
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
DIR=$(project_dir "${NAME}")
OUT="index.html"
[ "${2:-}" = "--out" ] && OUT="${3:?--out needs a name}"
T0=$(now_ms)
pc_layout "${DIR}"
pc_push "${BRIEF}" "$(ff "${DIR}")/notes/brief.md"
pc_push "${CONTENT_DIR}/pc/brief.py" "$(ff "${DIR}")/scripts/brief.py"
pc_push "${CONTENT_DIR}/pc/dailies.py" "$(ff "${DIR}")/scripts/dailies.py"
pc <<PS
\$ErrorActionPreference = 'Continue'
& '${PC_PYTHON}' '${DIR}\\scripts\\dailies.py' '${DIR}' '${DIR}\\notes\\brief.md' '${DIR}\\final\\${OUT}' 2>&1
PS
echo "dailies: $(since "$T0")  http://127.0.0.1:${PC_SERVE_PORT}/final/${OUT}  (tools/content/serve.sh ${NAME})"
