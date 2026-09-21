#!/usr/bin/env bash
# Three frames from one cut clip, side by side, pulled to the Mac.
#
#   tools/content/frames3.sh <project> <clip-basename> <t1> <t2> <t3>
#
# Reads content\<project>\cuts\<clip-basename>.mp4 on the PC, takes one frame
# at each of t1, t2, t3 seconds, scales each to 360 wide preserving aspect
# (source is portrait 9:16), hstacks the three into
# content\<project>\frames\<clip-basename>.png, and pulls it to
# MAC_STILLS/<project>_<clip-basename>.png.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[ "$#" -ge 5 ] || die "usage: tools/content/frames3.sh <project> <clip-basename> <t1> <t2> <t3>"
PROJECT="$1"
CLIP="$2"
T1="$3"
T2="$4"
T3="$5"

DIR=$(project_dir "${PROJECT}")
SRC="${DIR}\\cuts\\${CLIP}.mp4"
OUT="${DIR}\\frames\\${CLIP}.png"

INPUTS="-ss ${T1} -i '${SRC}' -ss ${T2} -i '${SRC}' -ss ${T3} -i '${SRC}'"
FILTER="[0:v]scale=360:-2[f0];[1:v]scale=360:-2[f1];[2:v]scale=360:-2[f2];[f0][f1][f2]hstack=inputs=3[out]"
CMD="ffmpeg -hide_banner -loglevel error -y ${INPUTS} -filter_complex '${FILTER}' -map '[out]' -frames:v 1 '${OUT}'"

if [ "${DRYRUN:-0}" = "1" ]; then
  echo "${CMD}"
  exit 0
fi

pc <<EOF || die "missing ${SRC} on PC, or ffmpeg failed"
\$ErrorActionPreference = 'Stop'
if (-not (Test-Path '${SRC}')) { Write-Error 'frames3: missing ${SRC}'; exit 1 }
Invoke-Expression "${CMD}"
Write-Output ('frames3 ' + (Get-Item '${OUT}').Length)
EOF

mkdir -p "${MAC_STILLS}"
pc_pull "$(ff "${DIR}")/frames/${CLIP}.png" "${MAC_STILLS}/${PROJECT}_${CLIP}.png"
echo "frames3: ${MAC_STILLS}/${PROJECT}_${CLIP}.png"
