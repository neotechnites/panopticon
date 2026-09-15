#!/usr/bin/env bash
# The voice of a project: spoken by a neural voice from the brief, or Ryan's own
# recording laid into a gap.
#
#   tools/content/voice.sh <project> [--force]      # TTS every ## script line
#   tools/content/voice.sh <project> <wav> [n]      # a recording at shot n's gap
#
# The first form speaks each row of the brief's `## script` table with edge-tts
# on the PC (tools/content/pc/voice.py): voice\<line>.wav per line, silence
# trimmed so a line is as long as it is spoken, and voice\words.json with every
# word's start and length in the wav's own timebase -- what assemble.sh times
# the picture and the captions off. A line whose text has not changed is not
# spoken again; --force speaks them all. Ryan's own recording replaces a line by
# dropping it in as voice\<line>.wav (48 kHz stereo) and re-running assemble.sh.
#
# The second form is the gap-based path: the wav lands at shot n's gap (default:
# the first shot that has one) as voice\voice_NN.wav, then render.sh runs again.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/voice.sh <project> [--force] | <project> <wav> [n]}"
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
DIR=$(project_dir "${NAME}")

if [ $# -ge 2 ] && [ "${2}" != "--force" ]; then
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
FORCE=""; [ "${2:-}" = "--force" ] && FORCE="--force"
T0=$(now_ms)
pc_layout "${DIR}"
pc_push "${BRIEF}" "$(ff "${DIR}")/notes/brief.md"
pc_push "${CONTENT_DIR}/pc/brief.py" "$(ff "${DIR}")/scripts/brief.py"
pc_push "${CONTENT_DIR}/pc/voice.py" "$(ff "${DIR}")/scripts/voice.py"
pc <<EOF
\$ErrorActionPreference = 'Continue'
& '${PC_PYTHON}' '${DIR}\\scripts\\voice.py' '${DIR}' '${DIR}\\notes\\brief.md' ${FORCE} 2>&1
EOF
echo "voice: $(since "$T0")"
