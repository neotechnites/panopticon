#!/usr/bin/env bash
# External footage for a project: yt-dlp on the PC, credited in SOURCES.md.
#
#   tools/content/fetch.sh <project> <url> <name> --find WORD          # caption cues with WORD, no download
#   tools/content/fetch.sh <project> <url> <name> --from 7:00 --to 7:12  # that section -> external\<name>.mp4
#   tools/content/fetch.sh <project> <url> <name>                        # the whole video into external\src\
#   tools/content/fetch.sh <project> - - --cc-search "fall guys grab"    # Creative Commons results only, listed
#
# --find greps the English captions for a word and prints each cue's time: how
# to locate "the scream a little after 6:50" before downloading anything. A
# section download is keyframe-cut by yt-dlp (--download-sections) then
# re-encoded to external\<name>.mp4 so the cut concatenates cleanly. Every
# download appends its entry (URL, title, uploader, date, licence, in/out, a
# credit line) to external\SOURCES.md; a licence YouTube leaves blank is written
# as "Standard YouTube licence (NOT Creative Commons)" -- fair-use/commentary.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/fetch.sh <project> <url> <name> [--from T --to T | --find WORD | --cc-search QUERY]}"
URL="${2:?url}"
CLIP="${3:?name}"
shift 3
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
DIR=$(project_dir "${NAME}")
ARGS=""
for a in "$@"; do ARGS="${ARGS} '$(printf '%s' "$a" | sed "s/'/''/g")'"; done
T0=$(now_ms)
pc_layout "${DIR}"
pc <<PS
New-Item -ItemType Directory -Force -Path '${DIR}\\external\\src' | Out-Null
PS
pc_push "${CONTENT_DIR}/pc/fetch.py" "$(ff "${DIR}")/scripts/fetch.py"
pc <<PS
\$ErrorActionPreference = 'Continue'
\$env:PYTHONIOENCODING = 'utf-8'
& '${PC_PYTHON}' '${DIR}\\scripts\\fetch.py' '${DIR}' '${URL}' '${CLIP}' ${ARGS} 2>&1
PS
echo "fetch: $(since "$T0")"
