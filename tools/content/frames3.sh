#!/usr/bin/env bash
# Three frames from one cut clip, side by side, pulled to the Mac.
#
#   tools/content/frames3.sh <project> <clip-basename> <t1> <t2> <t3>
#
# Reads content\<project>\cuts\<clip-basename>.mp4 on the PC, takes one frame at
# each of t1, t2, t3, scales each to 360 wide preserving aspect (source is
# portrait 9:16), hstacks the three into
# content\<project>\frames\<clip-basename>.png, and pulls it to
# MAC_STILLS/<project>_<clip-basename>.png.
#
# Each t is either seconds (1.81667) or an exact frame, written n<FRAME> (n109).
# Seconds are snapped to a frame index with the clip's own rate, read off the
# file: a sheet lands on ONE named frame, never between two. The frames chosen
# are printed, so the number that made the picture is written down.
#
# Why this is frame-exact and not a seek. These sheets are read to see a moment
# that lasts one frame -- the squeeze, the hit, the body going -- and `-ss T`
# answers "the first frame at or after T", which is a different question: a time
# rounded off a log, or a couple of hundredths of drift, hands back a frame or
# three after the one being looked for, and at 60 fps three frames is 50 ms, long
# enough for the recoil to carry the scope off the body and the sheet to show an
# empty lane. So the frame is named by index and cut out with trim=start_frame,
# which cannot land anywhere else. The clip is decoded from the top once and
# split three ways rather than opened three times.
#
# A hit's frame, from a take log: the log stamps the physics tick that resolved
# it, and the frame carrying the result is the next one to be drawn --
#   frame = round(t_hit * fps) - round(in * fps) + 1
# where `in` is the shot's in: (seconds of the take the cut drops). Measured on
# shot 2 of the projectile short: hits logged at 3.30, 5.90 and 8.48 s with
# in: 1.5 are whole on cut frames 108, 264 and 419 and gone on 109, 265 and 420.
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

# The clip's own frame rate, so seconds snap against the picture and not against
# an assumption. n<FRAME> arguments never need it; ask only when one is seconds.
clip_fps() {
  local rate
  rate=$(pc <<EOF | tr -d '\r' | tail -1
\$ErrorActionPreference = 'Stop'
ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 '${SRC}'
EOF
  ) || die "frames3: cannot read ${SRC} on the PC"
  python3 - "${rate}" <<'PY'
import sys
r = sys.argv[1].strip()
try:
    n, d = (r.split("/") + ["1"])[:2]
    fps = float(n) / float(d)
except (ValueError, ZeroDivisionError):
    fps = 0.0
print(f"{fps:.6f}" if fps > 0 else "")
PY
}

FPS_CLIP=""
# frame_of <t> : the frame index this argument names.
frame_of() {
  local t="$1"
  if [[ "${t}" =~ ^n([0-9]+)$ ]]; then echo "${BASH_REMATCH[1]}"; return; fi
  [[ "${t}" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "frames3: '${t}' is neither seconds nor n<FRAME>"
  [ -n "${FPS_CLIP}" ] || FPS_CLIP=$(clip_fps)
  [ -n "${FPS_CLIP}" ] || die "frames3: ${CLIP}.mp4 reports no frame rate; name the frame as n<FRAME>"
  python3 -c "print(int(round(float('${t}') * float('${FPS_CLIP}'))))"
}

F1=$(frame_of "${T1}")
F2=$(frame_of "${T2}")
F3=$(frame_of "${T3}")

# One decode, split three ways; trim=start_frame cuts out exactly the frame named.
# setpts lands each selected frame at 0 so hstack pairs them instead of waiting.
BRANCHES=""
K=0
for F in "${F1}" "${F2}" "${F3}"; do
  BRANCHES="${BRANCHES}[s${K}]trim=start_frame=${F}:end_frame=$((F + 1)),setpts=PTS-STARTPTS,scale=360:-2[f${K}];"
  K=$((K + 1))
done
FILTER="[0:v]split=3[s0][s1][s2];${BRANCHES}[f0][f1][f2]hstack=inputs=3[out]"
CMD="ffmpeg -hide_banner -loglevel error -y -i '${SRC}' -filter_complex '${FILTER}' -map '[out]' -frames:v 1 '${OUT}'"

if [ "${DRYRUN:-0}" = "1" ]; then
  echo "${CMD}"
  exit 0
fi

pc <<EOF || die "missing ${SRC} on PC, or ffmpeg failed"
\$ErrorActionPreference = 'Stop'
if (-not (Test-Path '${SRC}')) { Write-Error 'frames3: missing ${SRC}'; exit 1 }
Invoke-Expression "${CMD}"
if ((Get-Item '${OUT}').Length -lt 1024) { Write-Error 'frames3: ${OUT} is empty; a frame index is past the end of the clip'; exit 1 }
Write-Output ('frames3 ' + (Get-Item '${OUT}').Length)
EOF

mkdir -p "${MAC_STILLS}"
pc_pull "$(ff "${DIR}")/frames/${CLIP}.png" "${MAC_STILLS}/${PROJECT}_${CLIP}.png"
echo "frames3: frames ${F1}, ${F2}, ${F3} -> ${MAC_STILLS}/${PROJECT}_${CLIP}.png"
