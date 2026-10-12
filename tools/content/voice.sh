#!/usr/bin/env bash
# The voice of a project: en-US-AndrewNeural +5% on the pinned edge-tts endpoint (pc/voice.py),
# preflighted first, no other voice; or Ryan's own recording laid into a gap.
#
#   tools/content/voice.sh <project> [--tag T] [--force]   # speak the tag's ## script lines
#   tools/content/voice.sh <project> <wav> [n]             # a recording at shot n's gap
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/voice.sh <project> [--tag T] [--force] | <project> <wav> [n]}"
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
DIR=$(project_dir "${NAME}")

if [ $# -ge 2 ] && [ "${2}" != "--force" ] && [ "${2}" != "--tag" ]; then
  WAV="$2"
  [ -f "${WAV}" ] || die "no recording at ${WAV}"
  N="${3:-}"
  if [ -z "${N}" ]; then
    for n in $(seq 1 "$(brief_count "${BRIEF}")"); do
      if python3 -c "import sys; sys.exit(0 if $(brief_field "${BRIEF}" "${n}" gap 0) > 0 else 1)"; then N=${n}; break; fi
    done
  fi
  [ -n "${N}" ] || die "${NAME} has no shot with a gap: line"
  NN=$(pad2 "${N}")
  pc_push "${WAV}" "$(ff "${DIR}")/voice/voice_${NN}.wav"
  echo "voice_${NN}.wav laid at shot ${NN}'s gap"
  exec "${CONTENT_DIR}/render.sh" "${PROJECT}"
fi

grep -q '^## script' "${BRIEF}" || die "${NAME} has no ## script section to speak"
FORCE=""; TAG=""
shift
while [ $# -gt 0 ]; do
  case "$1" in --force) FORCE="--force" ;; --tag) TAG="$2"; shift ;; *) die "unknown option $1" ;; esac
  shift
done
T0=$(now_ms)
pc_layout "${DIR}"
pc_push "${BRIEF}" "$(ff "${DIR}")/notes/brief.md"
pc_push "${CONTENT_DIR}/pc/brief.py" "$(ff "${DIR}")/scripts/brief.py"
pc_push "${CONTENT_DIR}/pc/voice.py" "$(ff "${DIR}")/scripts/voice.py"
pc <<EOF
\$ErrorActionPreference = 'Continue'
& '${PC_PYTHON}' '${DIR}\\scripts\\voice.py' '${DIR}' '${DIR}\\notes\\brief.md' '${TAG}' ${FORCE} 2>&1
exit \$LASTEXITCODE
EOF
echo "voice: $(since "$T0")"
