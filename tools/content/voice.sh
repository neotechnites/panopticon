#!/usr/bin/env bash
# Lay Ryan's voice recording into a project's gap and re-render.
#
#   tools/content/voice.sh <project> <wav> [n]
#
# The wav lands at shot n's gap (default: the first shot that has one) as
# content\<project>\voice\voice_NN.wav on the PC, then render.sh runs again.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/voice.sh <project> <wav> [n]}"
WAV="${2:?usage: tools/content/voice.sh <project> <wav> [n]}"
[ -f "${WAV}" ] || die "no recording at ${WAV}"
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
DIR=$(project_dir "${NAME}")

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
