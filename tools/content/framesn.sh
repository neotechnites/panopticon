#!/usr/bin/env bash
# N frames from one cut clip in rows, pulled to the Mac.
#
#   tools/content/framesn.sh <project> <clip-basename> <per-row> <t1> <t2> ...
#
# frames3.sh's contract, for a sheet that has to FOLLOW something across a
# flight rather than show three separate moments: reads
# content\<project>\cuts\<clip>.mp4 on the PC, writes
# content\<project>\frames\<clip>.png, pulls it to
# MAC_STILLS/<project>_<clip>.png. Each t is seconds or an exact frame written
# n<FRAME>; seconds snap to a frame index off the clip's own rate, and the
# indices used are printed, so the numbers that made the picture are written
# down.
#
# Frame-exact for frames3.sh's reason: `-ss T` answers "the first frame at or
# after T", and a hundredth of drift at 60 fps hands back a frame or three
# later -- with a bullet in flight that is a different part of the flight. One
# decode, split N ways, each branch cut out with trim=start_frame.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[ "$#" -ge 4 ] || die "usage: tools/content/framesn.sh <project> <clip-basename> <per-row> <t1> <t2> ..."
PROJECT="$1"; CLIP="$2"; PER_ROW="$3"; shift 3
[ "${PER_ROW}" -ge 1 ] || die "framesn: per-row must be 1 or more"

DIR=$(project_dir "${PROJECT}")
SRC="${DIR}\\cuts\\${CLIP}.mp4"
OUT="${DIR}\\frames\\${CLIP}.png"
COUNT="$#"
[ $((COUNT % PER_ROW)) -eq 0 ] || die "framesn: ${COUNT} frames do not fill rows of ${PER_ROW}"

RATE=$(pc <<EOF | tr -d '\r' | tail -1
\$ErrorActionPreference = 'Stop'
ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 '${SRC}'
EOF
) || die "framesn: cannot read ${SRC} on the PC"
FPS=$(python3 -c "
n, d = (('${RATE}'.strip() + '/1').split('/') + ['1'])[:2]
print(float(n) / float(d))")

FRAMES=()
for T in "$@"; do
  case "${T}" in
    n*) FRAMES+=("${T#n}") ;;
    *)  FRAMES+=("$(python3 -c "print(int(round(${T} * ${FPS})))")") ;;
  esac
done

SPLIT="[0:v]split=${COUNT}"
BRANCHES=""
K=0
for F in "${FRAMES[@]}"; do
  SPLIT="${SPLIT}[s${K}]"
  BRANCHES="${BRANCHES}[s${K}]trim=start_frame=${F}:end_frame=$((F + 1)),setpts=PTS-STARTPTS,scale=360:-2[f${K}];"
  K=$((K + 1))
done
ROWS=$((COUNT / PER_ROW))
STACK=""
ROW_LABELS=""
for ((R = 0; R < ROWS; R++)); do
  for ((C = 0; C < PER_ROW; C++)); do
    STACK="${STACK}[f$((R * PER_ROW + C))]"
  done
  STACK="${STACK}hstack=inputs=${PER_ROW}[r${R}];"
  ROW_LABELS="${ROW_LABELS}[r${R}]"
done
if [ "${ROWS}" -eq 1 ]; then
  FILTER="${SPLIT};${BRANCHES}${STACK%;}"
  FILTER="${FILTER/\[r0\]/[out]}"
else
  FILTER="${SPLIT};${BRANCHES}${STACK}${ROW_LABELS}vstack=inputs=${ROWS}[out]"
fi
CMD="ffmpeg -hide_banner -loglevel error -y -i '${SRC}' -filter_complex '${FILTER}' -map '[out]' -frames:v 1 '${OUT}'"

pc <<EOF || die "missing ${SRC} on PC, or ffmpeg failed"
\$ErrorActionPreference = 'Stop'
if (-not (Test-Path '${SRC}')) { Write-Error 'framesn: missing ${SRC}'; exit 1 }
Invoke-Expression "${CMD}"
if ((Get-Item '${OUT}').Length -lt 1024) { Write-Error 'framesn: ${OUT} is empty; a frame index is past the end of the clip'; exit 1 }
Write-Output ('framesn ' + (Get-Item '${OUT}').Length)
EOF

mkdir -p "${MAC_STILLS}"
pc_pull "$(ff "${DIR}")/frames/${CLIP}.png" "${MAC_STILLS}/${PROJECT}_${CLIP}.png"
echo "framesn: frames ${FRAMES[*]} -> ${MAC_STILLS}/${PROJECT}_${CLIP}.png"
