#!/usr/bin/env bash
# One frame from each delivered clip of a project, side by side, pulled to the Mac.
#
#   tools/content/sheet.sh <project>
#
# Reads the shots that carry a file: line; each contributes one frame, taken
# frame: seconds into its clip (default: 45% of the way through), scaled to
# 720 wide. Written to clips\<project>\sheet.png on the PC and pulled to
# MAC_STILLS/<project>_sheet.png.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/sheet.sh <project>}"
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
DIR="${PC_CLIPS}\\${NAME}"
COUNT=$(brief_count "${BRIEF}")
INPUTS=""; FILTER=""; K=0
for n in $(seq 1 "${COUNT}"); do
  FILE=$(brief_field "${BRIEF}" "${n}" file)
  [ -n "${FILE}" ] || continue
  FRAME=$(brief_field "${BRIEF}" "${n}" frame)
  if [ -z "${FRAME}" ]; then
    SECS=$(brief_field "${BRIEF}" "${n}" seconds 6)
    FRAME=$(python3 -c "print(round(${SECS} * 0.45, 2))")
  fi
  INPUTS="${INPUTS} -ss ${FRAME} -i '${DIR}\\${FILE}.mp4'"
  FILTER="${FILTER}[${K}:v]scale=720:-2[f${K}];"
  K=$((K + 1))
done
[ "${K}" -gt 0 ] || die "${NAME} has no shot with a file: line"
STACK=""; for i in $(seq 0 $((K - 1))); do STACK="${STACK}[f${i}]"; done
if [ "${K}" -gt 1 ]; then FILTER="${FILTER}${STACK}hstack=inputs=${K}[out]"; else FILTER="${FILTER}[f0]copy[out]"; fi
pc <<EOF
\$ErrorActionPreference = 'Stop'
Invoke-Expression "ffmpeg -hide_banner -loglevel error -y ${INPUTS} -filter_complex '${FILTER}' -map '[out]' -frames:v 1 '${DIR}\\sheet.png'"
Write-Output ('sheet ' + (Get-Item '${DIR}\\sheet.png').Length)
EOF
mkdir -p "${MAC_STILLS}"
pc_pull "$(ff "${DIR}")/sheet.png" "${MAC_STILLS}/${NAME}_sheet.png"
echo "sheet: ${MAC_STILLS}/${NAME}_sheet.png"
