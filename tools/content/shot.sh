#!/usr/bin/env bash
# Capture and render ONE shot of a project on the PC, from its entry in the brief.
#
#   tools/content/shot.sh <project> <n>
#
# Entry fields it reads: capture (run_clip args) or still (shot.gd args), seconds,
# in (seconds into the take the cut starts), gap, at (git ref for a before/after
# pair), hold (seconds a still is held), takes and motion (gate overrides).
# Output on the PC: content\<kind>\<project>\takes\NN_tK.avi (+ .txt gate report)
# and shots\NN.mp4, a 16:9 master cut to seconds+gap with game audio muted over
# the gap. Stills and captions are applied at render, not here.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/shot.sh <project> <n>}"
N="${2:?usage: tools/content/shot.sh <project> <n>}"
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
KIND=$(brief_head "${BRIEF}" kind short)
[ "${KIND}" = devlog ] && FOLDER=devlogs || FOLDER=shorts
DIR="${PC_CONTENT}\\${FOLDER}\\${NAME}"
NN=$(pad2 "${N}")

CAPTURE=$(brief_field "${BRIEF}" "${N}" capture)
STILL=$(brief_field "${BRIEF}" "${N}" still)
SECONDS_WANTED=$(brief_field "${BRIEF}" "${N}" seconds 6)
GAP=$(brief_field "${BRIEF}" "${N}" gap 0)
IN=$(brief_field "${BRIEF}" "${N}" in 0)      # seconds into the take the cut starts
AT=$(brief_field "${BRIEF}" "${N}" at)
HOLD=$(brief_field "${BRIEF}" "${N}" hold 3)
TAKES_MAX=$(brief_field "${BRIEF}" "${N}" takes "${TAKES_MAX}")
# A pinned seed plays the same take every time; retrying it buys nothing.
[[ "${CAPTURE}" == *--seed=* ]] && TAKES_MAX=1
MOTION_MIN=$(brief_field "${BRIEF}" "${N}" motion "${MOTION_MIN}")
SAID=$(brief_field "${BRIEF}" "${N}" said)
[ -n "${CAPTURE}${STILL}" ] || die "shot ${N} of ${NAME} has no capture: or still: line"
echo "shot ${NN}: ${SAID}"

pc <<EOF
New-Item -ItemType Directory -Force -Path '${DIR}\\takes', '${DIR}\\shots' | Out-Null
EOF
pc_push "${BRIEF}" "$(ff "${DIR}")/brief.md"

# --- One take: godot, then the gate. Prints "motion=<f> freeze=<n>" last. -----
take() {  # take <tag> <seed> <seconds>
  local tag="$1" seed="$2" secs="$3"
  local avi="${DIR}\\takes\\${tag}.avi" log="${DIR}\\takes\\${tag}.log"
  local args="${CAPTURE}"
  [[ "${args}" == *--seed=* ]] || args="${args} --seed=${seed}"
  local t0; t0=$(now_ms)
  pc_godot "--script res://tools/capture/run_clip.gd --write-movie ${avi} --fixed-fps ${FPS} --resolution ${SIZE} -- ${args} --seconds=${secs}" "${log}" | sed 's/^/  | /'
  echo "  take ${tag}: godot $(since "$t0")" >&2
  t0=$(now_ms)
  pc <<EOF
\$m = ffmpeg -hide_banner -nostats -i '${avi}' -an -vf "fps=10,scale=160:90,format=gray,tblend=all_mode=difference,lutyuv=y='if(gt(val,24),255,0)',signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null - 2>\$null | Select-String 'YAVG=' | ForEach-Object { [double](\$_ -replace '.*YAVG=','') }
\$motion = if (\$m) { (\$m | Measure-Object -Average).Average / 255.0 } else { 0 }
\$f = ffmpeg -hide_banner -nostats -i '${avi}' -an -vf "freezedetect=n=${FREEZE_NOISE_DB}dB:d=${FREEZE_MAX_SECONDS}" -f null - 2>&1 | Select-String 'freeze_duration' | Measure-Object
\$line = ('motion={0:N4} freeze={1}' -f \$motion, \$f.Count)
Set-Content -Path '${DIR}\\takes\\${tag}.txt' -Value \$line
Write-Output \$line
EOF
  echo "  take ${tag}: gate $(since "$t0")" >&2
}

# --- A movie take with retries; echoes the chosen take's tag. ------------------
best_take() {  # best_take <prefix> <seconds>
  local prefix="$1" secs="$2" seed="${SEED:-20260930}" chosen="" chosen_motion=0 k
  for k in $(seq 1 "${TAKES_MAX}"); do
    local tag="${prefix}_t${k}" report
    report=$(take "${tag}" "$((seed + k - 1))" "${secs}" | tee /dev/stderr | tail -1)
    local motion freeze
    motion=$(echo "${report}" | sed -n 's/.*motion=\([0-9.]*\).*/\1/p')
    freeze=$(echo "${report}" | sed -n 's/.*freeze=\([0-9]*\).*/\1/p')
    if [ "${freeze:-1}" = 0 ] && python3 -c "import sys; sys.exit(0 if float('${motion:-0}') >= ${MOTION_MIN} else 1)"; then
      echo "${tag}"; return
    fi
    if [ "${freeze:-1}" = 0 ] && python3 -c "import sys; sys.exit(0 if float('${motion:-0}') > ${chosen_motion} else 1)"; then
      chosen="${tag}"; chosen_motion="${motion}"
    fi
    echo "  take ${tag} failed the gate (${report}); retrying with seed $((seed + k))" >&2
  done
  [ -n "${chosen}" ] || chosen="${prefix}_t1"
  echo "  no take passed; keeping ${chosen}" >&2
  echo "${chosen}"
}

# --- Render the shot master from a take. ----------------------------------------
render_take() {  # render_take <tag> <out-mp4> <cut-seconds> <mute-from-seconds>  (from IN seconds in)
  local tag="$1" out="$2" cut="$3" mute="$4"
  pc <<EOF
\$src = '${DIR}\\takes\\${tag}.avi'
\$audio = ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 \$src
\$af = if (\$audio) { @('-af', "volume=enable='gte(t,${mute})':volume=0", '-c:a', 'aac', '-ar', '48000', '-b:a', '160k') } else { @('-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-shortest', '-c:a', 'aac') }
ffmpeg -hide_banner -loglevel error -y -ss ${IN} -i \$src @(\$af) -t ${cut} -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -r ${FPS} -vf "scale=1280:720" '${out}'
Write-Output ('rendered ' + (Get-Item '${out}').Length)
EOF
}

T_ALL=$(now_ms)
TOTAL=$(python3 -c "print(${SECONDS_WANTED} + ${GAP})")
if [ -n "${STILL}" ]; then
  # A still, held: shot.gd renders one PNG, ffmpeg holds it.
  T0=$(now_ms)
  pc_godot "--resolution ${SIZE} --script res://tools/shot.gd -- ${STILL} --out=$(ff "${DIR}")/shots/${NN}.png" "${DIR}\\takes\\${NN}.log" | sed 's/^/  | /'
  echo "  still: godot $(since "$T0")"
  T0=$(now_ms)
  pc <<EOF
ffmpeg -hide_banner -loglevel error -y -loop 1 -i '${DIR}\\shots\\${NN}.png' -f lavfi -i anullsrc=r=48000:cl=stereo -t ${HOLD} -r ${FPS} -vf "scale=1280:720" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -c:a aac -shortest '${DIR}\\shots\\${NN}.mp4'
Write-Output ('rendered ' + (Get-Item '${DIR}\\shots\\${NN}.mp4').Length)
EOF
  echo "  still: render $(since "$T0")"
elif [ -n "${AT}" ]; then
  # Before/after: the same capture at <at> and at the branch head, back to back.
  T0=$(now_ms)
  pc <<EOF
git -C C:/dev/verify checkout -q ${AT}
cmd /c "${PC_GODOT} --headless --import --path ${PC_PROJECT} > C:\\dev\\content_import.txt 2>&1"
Write-Output ('verify at ' + (git -C C:/dev/verify log --oneline -1))
EOF
  echo "  before: checkout+import $(since "$T0")"
  BEFORE=$(best_take "${NN}_before" "$(python3 -c "print(${IN} + ${SECONDS_WANTED})")")
  T0=$(now_ms)
  pc <<EOF
git -C C:/dev/verify checkout -q ${PC_BRANCH}
cmd /c "${PC_GODOT} --headless --import --path ${PC_PROJECT} > C:\\dev\\content_import.txt 2>&1"
Write-Output ('verify at ' + (git -C C:/dev/verify log --oneline -1))
EOF
  echo "  after: checkout+import $(since "$T0")"
  AFTER=$(best_take "${NN}_after" "$(python3 -c "print(${IN} + ${TOTAL})")")
  T0=$(now_ms)
  render_take "${BEFORE}" "${DIR}\\shots\\${NN}_before.mp4" "${SECONDS_WANTED}" "${SECONDS_WANTED}" | sed 's/^/  | /'
  render_take "${AFTER}" "${DIR}\\shots\\${NN}_after.mp4" "${TOTAL}" "${SECONDS_WANTED}" | sed 's/^/  | /'
  pc <<EOF
Set-Content -Path '${DIR}\\shots\\${NN}_pair.txt' -Value @("file '${NN}_before.mp4'", "file '${NN}_after.mp4'")
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i '${DIR}\\shots\\${NN}_pair.txt' -c copy '${DIR}\\shots\\${NN}.mp4'
Write-Output ('rendered ' + (Get-Item '${DIR}\\shots\\${NN}.mp4').Length)
EOF
  echo "  pair: render $(since "$T0")"
else
  TAG=$(best_take "${NN}" "$(python3 -c "print(${IN} + ${TOTAL} + 1.0)")")
  T0=$(now_ms)
  render_take "${TAG}" "${DIR}\\shots\\${NN}.mp4" "${TOTAL}" "${SECONDS_WANTED}" | sed 's/^/  | /'
  echo "  render: $(since "$T0")"
fi
echo "shot ${NN} done in $(since "$T_ALL"): ${DIR}\\shots\\${NN}.mp4"
