#!/usr/bin/env bash
# Record the tape a shot plays: the staged take run once, headless, on the PC, and every
# body's input, every outside write and every trigger pull written down per physics tick.
#
#   tools/content/tape.sh <project> <n> [--no-sync]
#
# The entry's capture: line is the take; its tape: line names the file, and every entry
# naming the same tape is the same event down other eyes. The tape lands in
# tools/content/projects/<project>/tapes/<tape>.json; commit it and shot.sh plays it.
# Authoring only: a reshoot never records, it plays (reshoot_all.sh).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/tape.sh <project> <n> [--no-sync]}"
N="${2:?usage: tools/content/tape.sh <project> <n> [--no-sync]}"
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
DIR=$(project_dir "${NAME}")
CAPTURE=$(brief_field "${BRIEF}" "${N}" capture)
TAPE=$(brief_field "${BRIEF}" "${N}" tape)
[ -n "${CAPTURE}" ] && [ -n "${TAPE}" ] || die "shot ${N} of ${NAME} needs capture: and tape: lines"
[ "${3:-}" = "--no-sync" ] || "$(dirname "$0")/sync.sh"

# Long enough for every entry that plays this tape: in + seconds + gap + 1 s, as shot.sh films.
SECS=0
for id in $(grep '^## [0-9]' "${BRIEF}" | awk '{print $2}'); do
  [ "$(brief_field "${BRIEF}" "${id}" tape)" = "${TAPE}" ] || continue
  SECS=$(python3 -c "print(max(${SECS}, $(brief_field "${BRIEF}" "${id}" in 0) + $(brief_field "${BRIEF}" "${id}" seconds 6) + $(brief_field "${BRIEF}" "${id}" gap 0) + 1.0))")
done
OUT_DIR="${CONTENT_DIR}/projects/${NAME}/tapes"
mkdir -p "${OUT_DIR}"
PC_TAPE="${DIR}\\stages\\tape_${TAPE}.json"
PC_LOG="${DIR}\\notes\\tape_${TAPE}.log"
T0=$(now_ms)
pc_layout "${DIR}"
pc <<EOF
cmd /c "${PC_GODOT} --headless --path ${PC_PROJECT} --fixed-fps ${FPS} --script res://tools/capture/run_clip.gd -- ${CAPTURE} --seconds=${SECS} --record=${PC_TAPE} > ${PC_LOG} 2>&1"
Get-Content '${PC_LOG}' | Where-Object { \$_ -match '^(\\[event\\]|\\[tape\\]|\\[stage\\]|SCRIPT ERROR)' }
EOF
pc_pull "$(ff "${PC_TAPE}")" "${OUT_DIR}/${TAPE}.json"
echo "tape ${TAPE}: ${SECS} s recorded in $(since "$T0") -> ${OUT_DIR}/${TAPE}.json"
