#!/usr/bin/env bash
# Capture and render ONE shot of a project on the PC, from its entry in the brief.
#
#   tools/content/shot.sh <project> <n> [--crosshair] [--movie] [--name NAME]
#
# Rough (the default): ONE take at real speed, the screen recorded (lib.sh pc_rough);
# a portrait take is 810x1440, scaled to 1080x1920 at the cut. A failed gate prints why
# and stops: no retry, no fallback. --movie (final only): Movie Maker, native 1080x1920.
# --name: the cut is cuts\NAME.mp4 (default NN). A cut an earlier tag used is never overwritten.
#
# Entry fields it reads: capture (run_clip args) or still (shot.gd args), tape (a
# recorded take, tools/content/tape.sh: every input played back, the same shot every
# time), flash (take seconds and length of a white frame burned in), seconds,
# in (seconds into the take the cut starts), gap, at (git ref for a before/after
# pair), hold (seconds a still is held), takes, motion and freeze (gate
# overrides: motion is the floor, freeze the stretches allowed, or "waive" for a
# fixed lens Ryan has passed), hud (crosshair | on; --crosshair on the command
# line is the same as hud: crosshair -- a guard POV keeps the crosshair, nothing
# else is drawn on any shot), and file (a name: the same cut is also written on
# its own, in the brief's aspect, to final\<file>.mp4 -- a shot handed over as a
# clip, not a timeline).
#
# A short is filmed PORTRAIT through a temporary override.cfg in C:\dev\verify; the
# lens composes for it (Camera3D fov is vertical). Nothing is filmed landscape and cropped.
# Output on the PC, under content\<project>\ (layout in lib.sh): cuts\NN.mp4, the
# master cut to seconds+gap with game audio muted over the gap, plus final\<file>.mp4
# when the entry has a file: line. Takes are captured to takes\NN_tK.mkv (.avi with --movie) and
# gated; once the shot is cut the chosen take's gate report and log move to
# notes\NN.gate.txt and notes\NN.take.log and every take of the shot is deleted.
# Any scratch worktree left under panopticon-renders is removed at the end.
# Stills and captions are applied at render, not here.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

USAGE="usage: tools/content/shot.sh <project> <n> [--crosshair] [--movie] [--name NAME]"
PROJECT="${1:?${USAGE}}"
N="${2:?${USAGE}}"
CROSSHAIR=0; MODE=rough; OUT=""
set -- "${@:3}"
while [ $# -gt 0 ]; do
  case "$1" in --crosshair) CROSSHAIR=1 ;; --movie) MODE=movie ;; --name) OUT="$2"; shift ;; *) die "unknown flag $1" ;; esac
  shift
done
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
KIND=$(brief_head "${BRIEF}" kind short)
DIR=$(project_dir "${NAME}")
NN=$(pad2 "${N}")
OUT="${OUT:-${NN}}"

CAPTURE=$(brief_field "${BRIEF}" "${N}" capture)
STILL=$(brief_field "${BRIEF}" "${N}" still)
SECONDS_WANTED=$(brief_field "${BRIEF}" "${N}" seconds 6)
GAP=$(brief_field "${BRIEF}" "${N}" gap 0)
IN=$(brief_field "${BRIEF}" "${N}" in 0)      # seconds into the take the cut starts
AT=$(brief_field "${BRIEF}" "${N}" at)
REF=$(brief_field "${BRIEF}" "${N}" ref)   # capture this one shot at a git ref, with that ref's own tools
HOLD=$(brief_field "${BRIEF}" "${N}" hold 3)
TAKES_MAX=$(brief_field "${BRIEF}" "${N}" takes "${TAKES_MAX}")
# A pinned seed plays the same take every time; retrying it buys nothing. Rough is one take.
[[ "${CAPTURE}" == *--seed=* ]] && TAKES_MAX=1
[ "${MODE}" = rough ] && TAKES_MAX=1
MOTION_MIN=$(brief_field "${BRIEF}" "${N}" motion "${MOTION_MIN}")
FREEZE_ALLOWED=$(brief_field "${BRIEF}" "${N}" freeze 0)   # stretches frozen >= 0.75 s allowed; "waive" skips the gate
HUD=$(brief_field "${BRIEF}" "${N}" hud)
TAPE=$(brief_field "${BRIEF}" "${N}" tape)
FLASH=$(brief_field "${BRIEF}" "${N}" flash)
[ "${CROSSHAIR}" = 1 ] && HUD=crosshair
SAID=$(brief_field "${BRIEF}" "${N}" said)
FILE=$(brief_field "${BRIEF}" "${N}" file)      # also deliver this cut as final\<file>.mp4
SIZE=$(brief_head "${BRIEF}" size "${SIZE}")   # a brief may pin its frame (16:9 1920x1080)
ASPECT=$(brief_head "${BRIEF}" aspect "$([ "${KIND}" = devlog ] && echo 16:9 || echo 9:16)")
# 9:16 is filmed 9:16 (Ryan: "the frame should consider the mobile viewing port"). The
# screen is 2560x1440: rough portrait is 810x1440 real time; only --movie is native 1080x1920.
if [ "${ASPECT}" = 9:16 ]; then
  [ "${MODE}" = movie ] && SIZE=1080x1920 || SIZE=810x1440
  MASTER="scale=1080:1920"; GATE_SCALE="scale=90:160"
else
  MASTER="scale=${SIZE%%x*}:${SIZE##*x}"; GATE_SCALE="scale=160:90"
fi
[ "${MODE}" = rough ] && [ "${SIZE##*x}" -gt 1440 ] && die "a ${SIZE} take does not fit the 2560x1440 screen in real time; only a final films --movie"
# Both modes leave a lossless RGB take: rough records it, movie packs Movie Maker's PNG frames.
TAKE_EXT=mkv; IN_SPEC="in_range=pc"
# The cut is lossless RGB (no generation loss): the take is decoded by its own tags.
MASTER="${MASTER}:flags=lanczos,format=rgb24"
VLOSSLESS="-c:v libx264rgb -preset veryfast -qp 0"
TAGS="-color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709"
[ -n "${CAPTURE}${STILL}" ] || die "shot ${N} of ${NAME} has no capture: or still: line"
REFUSED=$(shot_refusal "${BRIEF}" "${N}")
[ -z "${REFUSED}" ] || die "shot.sh refuses shot ${N} of ${NAME}: ${REFUSED}"
if [ -n "${TAPE}" ]; then CAPTURE="${CAPTURE} --tape=$(tape_res "${NAME}" "${TAPE}")"; fi
if [ -n "${FLASH}" ]; then
  read -r FLASH_AT FLASH_LEN <<< "${FLASH}"
  MASTER="${MASTER},drawbox=c=white:t=fill:enable='between(t,$(python3 -c "print(${FLASH_AT} - ${IN})"),$(python3 -c "print(${FLASH_AT} - ${IN} + ${FLASH_LEN:-0.045})"))'"
fi
# No HUD on any shot unless the entry asks: hud: crosshair (a guard POV) or hud: on.
if [ -n "${HUD}" ] && [[ "${CAPTURE}" != *--hud=* ]]; then CAPTURE="${CAPTURE} --hud=${HUD}"; fi
echo "shot ${NN} -> cuts\\${OUT}.mp4 (${MODE} ${SIZE}): ${SAID}"

pc_lock "shot ${NAME} ${NN}"
# The scratch checkout is shared: film only from this branch's own commit.
if [ "$(pc <<< 'git -C C:/dev/verify rev-parse HEAD' | tr -d '\r')" != "$(git -C "${REPO_DIR}" rev-parse HEAD)" ]; then
  "${CONTENT_DIR}/sync.sh"
fi
pc_layout "${DIR}"
USED=$(pc <<EOF
Select-String -Path '${DIR}\\cuts\\*_used.txt' -SimpleMatch -Pattern 'cuts/${OUT}.mp4' -List -EA SilentlyContinue | ForEach-Object { \$_.Filename }
EOF
)
[ -z "${USED}" ] || die "cuts\\${OUT}.mp4 is in an earlier cut (${USED//$'\n'/ }); film it under a new --name"
pc_push "${BRIEF}" "$(ff "${DIR}")/notes/brief.md"

# ss_ps <take-path> : PowerShell setting $ss, the cut's in-point in that take file
# (IN, plus a rough take's sync offset).
ss_ps() {
  echo "\$off = if (Test-Path '$1.sync') { [double]::Parse((Get-Content '$1.sync' -Raw).Trim(), [Globalization.CultureInfo]::InvariantCulture) } else { 0.0 }"
  echo "\$ss = ([double]${IN} + \$off).ToString([Globalization.CultureInfo]::InvariantCulture)"
}

# --- One take: godot, then the gate. Prints "motion=<f> freeze=<n>" last. -----
take() {  # take <tag> <seed> <seconds>
  local tag="$1" seed="$2" secs="$3"
  local avi="${DIR}\\takes\\${tag}.${TAKE_EXT}" log="${DIR}\\takes\\${tag}.log"
  local args="${CAPTURE}"
  [[ "${args}" == *--seed=* ]] || args="${args} --seed=${seed}"
  local t0; t0=$(now_ms)
  if [ "${MODE}" = rough ]; then
    if ! pc_rough "--script res://tools/capture/run_clip.gd -- ${args} --seconds=${secs} --sync=90" "${log}" "${avi}" | sed 's/^/  | /' >&2; then
      echo "FAILED: the recording has no sync frames (Godot log ${log})"; return
    fi
  else
    local frames="${DIR}\\takes\\${tag}_f"
    pc_godot "--script res://tools/capture/run_clip.gd --write-movie ${frames}.png --fixed-fps ${FPS} --resolution ${SIZE} -- ${args} --seconds=${secs}" "${log}" | sed 's/^/  | /'
    pc <<EOF
ffmpeg -hide_banner -loglevel error -y -framerate ${FPS} -i '${frames}%08d.png' -i '${frames}.wav' -vf format=gbrp -c:v utvideo -c:a pcm_s16le '${avi}'
Remove-Item '${frames}*.png', '${frames}.wav' -ErrorAction SilentlyContinue
EOF
  fi
  echo "  take ${tag}: godot $(since "$t0")" >&2
  t0=$(now_ms)
  # The gate reads the cut, not the take: the second held before a stage places
  # its bodies and the tail past the beat are never in the shot.
  pc <<EOF
$(ss_ps "${avi}")
\$m = ffmpeg -hide_banner -nostats -ss \$ss -t ${TOTAL} -i '${avi}' -an -vf "fps=10,${GATE_SCALE},format=gray,tblend=all_mode=difference,lutyuv=y='if(gt(val,24),255,0)',signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null - 2>\$null | Select-String 'YAVG=' | ForEach-Object { [double](\$_ -replace '.*YAVG=','') }
\$motion = if (\$m) { (\$m | Measure-Object -Average).Average / 255.0 } else { 0 }
\$f = ffmpeg -hide_banner -nostats -ss \$ss -t ${TOTAL} -i '${avi}' -an -vf "freezedetect=n=${FREEZE_NOISE_DB}dB:d=${FREEZE_MAX_SECONDS}" -f null - 2>&1 | Select-String 'freeze_duration' | Measure-Object
\$line = ('motion={0:N4} freeze={1}' -f \$motion, \$f.Count)
Set-Content -Path '${DIR}\\takes\\${tag}.txt' -Value \$line
Write-Output \$line
EOF
  echo "  take ${tag}: gate $(since "$t0")" >&2
}

# --- Takes (rough: one, a failed gate stops; movie: retries); echoes the tag. ---
best_take() {  # best_take <prefix> <seconds>
  local prefix="$1" secs="$2" seed="${SEED:-20260930}" chosen="" chosen_motion=0 k
  for k in $(seq 1 "${TAKES_MAX}"); do
    local tag="${prefix}_t${k}" report
    report=$(take "${tag}" "$((seed + k - 1))" "${secs}" | tee /dev/stderr | tail -1)
    [[ "${report}" == FAILED* ]] && die "shot ${NN}: ${report}"
    local motion freeze
    motion=$(echo "${report}" | sed -n 's/.*motion=\([0-9.]*\).*/\1/p')
    freeze=$(echo "${report}" | sed -n 's/.*freeze=\([0-9]*\).*/\1/p')
    if [ "${FREEZE_ALLOWED}" = waive ]; then
      # A fixed lens on a still body fails by construction; Ryan passed the shot.
      pc <<EOF
Add-Content -Path '${DIR}\\takes\\${tag}.txt' -Value 'OVERRIDE: gate waived by the brief (freeze: waive) for this fixed-camera shot'
EOF
      echo "  take ${tag}: gate waived by the brief" >&2
      echo "${tag}"; return
    fi
    if [ "${freeze:-1}" -le "${FREEZE_ALLOWED}" ] && python3 -c "import sys; sys.exit(0 if float('${motion:-0}') >= ${MOTION_MIN} else 1)"; then
      echo "${tag}"; return
    fi
    [ "${MODE}" = rough ] && die "shot ${NN} failed the gate: ${report} (needs motion >= ${MOTION_MIN}, freezes <= ${FREEZE_ALLOWED}); take kept at ${DIR}\\takes\\${tag}.${TAKE_EXT}"
    if [ "${freeze:-1}" -le "${FREEZE_ALLOWED}" ] && python3 -c "import sys; sys.exit(0 if float('${motion:-0}') > ${chosen_motion} else 1)"; then
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
\$src = '${DIR}\\takes\\${tag}.${TAKE_EXT}'
$(ss_ps "${DIR}\\takes\\${tag}.${TAKE_EXT}")
\$audio = ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 \$src
\$af = if (\$audio) { @('-af', "volume=enable='gte(t,${mute})':volume=0", '-c:a', 'aac', '-ar', '48000', '-b:a', '160k') } else { @('-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-shortest', '-c:a', 'aac') }
ffmpeg -hide_banner -loglevel error -y -ss \$ss -i \$src @(\$af) -t ${cut} ${VLOSSLESS} -r ${FPS} -vf "${MASTER}" '${out}'
Write-Output ('rendered ' + (Get-Item '${out}').Length)
EOF
}

# --- The same cut as a clip of its own, in the delivery aspect. -----------------
deliver_take() {  # deliver_take <tag> <cut-seconds>
  [ -n "${FILE}" ] || return 0
  local tag="$1" cut="$2" out="${DIR}\\final\\${FILE}.mp4" geometry
  [ "${ASPECT}" = 9:16 ] && geometry="scale=1080:1920" || geometry="scale=1920:1080"
  geometry="${geometry}:${IN_SPEC}:out_range=tv:out_color_matrix=bt709:flags=lanczos"
  pc <<EOF
\$src = '${DIR}\\takes\\${tag}.${TAKE_EXT}'
$(ss_ps "${DIR}\\takes\\${tag}.${TAKE_EXT}")
\$audio = ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 \$src
\$af = if (\$audio) { @('-c:a', 'aac', '-ar', '48000', '-b:a', '160k') } else { @('-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-shortest', '-c:a', 'aac') }
ffmpeg -hide_banner -loglevel error -y -ss \$ss -i \$src @(\$af) -t ${cut} -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p ${TAGS} -r ${FPS} -vf "${geometry}" -movflags +faststart '${out}'
\$len = ffprobe -v error -show_entries format=duration -of csv=p=0 '${out}'
Write-Output ('clip ' + '${out}' + ' ' + [math]::Round([double]\$len, 2) + ' s ' + (Get-Item '${out}').Length)
EOF
}

T_ALL=$(now_ms)
TOTAL=$(python3 -c "print(${SECONDS_WANTED} + ${GAP})")
if [ -n "${STILL}" ]; then
  # A still, held: shot.gd renders one PNG, ffmpeg holds it.
  T0=$(now_ms)
  pc_godot "--resolution ${SIZE} --script res://tools/shot.gd -- ${STILL} --out=$(ff "${DIR}")/frames/${NN}.png" "${DIR}\\takes\\${NN}.log" | sed 's/^/  | /'
  echo "  still: godot $(since "$T0")"
  T0=$(now_ms)
  pc <<EOF
ffmpeg -hide_banner -loglevel error -y -loop 1 -i '${DIR}\\frames\\${NN}.png' -f lavfi -i anullsrc=r=48000:cl=stereo -t ${HOLD} -r ${FPS} -vf "${MASTER}" -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p ${TAGS} -c:a aac -shortest '${DIR}\\cuts\\${OUT}.mp4'
Write-Output ('rendered ' + (Get-Item '${DIR}\\cuts\\${OUT}.mp4').Length)
EOF
  echo "  still: render $(since "$T0")"
  pc_promote "${DIR}" "${NN}" "${NN}" | sed 's/^/  | /'
elif [ -n "${AT}" ]; then
  # Before/after: the same capture at <at> and at the branch head, back to back.
  T0=$(now_ms)
  pc_checkout "${AT}"
  echo "  before: checkout+import $(since "$T0")"
  BEFORE=$(best_take "${NN}_before" "$(python3 -c "print(${IN} + ${SECONDS_WANTED})")")
  T0=$(now_ms)
  pc_checkout "${PC_BRANCH}"
  echo "  after: checkout+import $(since "$T0")"
  AFTER=$(best_take "${NN}_after" "$(python3 -c "print(${IN} + ${TOTAL})")")
  T0=$(now_ms)
  render_take "${BEFORE}" "${DIR}\\cuts\\${OUT}_before.mp4" "${SECONDS_WANTED}" "${SECONDS_WANTED}" | sed 's/^/  | /'
  render_take "${AFTER}" "${DIR}\\cuts\\${OUT}_after.mp4" "${TOTAL}" "${SECONDS_WANTED}" | sed 's/^/  | /'
  pc <<EOF
Set-Content -Path '${DIR}\\cuts\\${OUT}_pair.txt' -Value @("file '${OUT}_before.mp4'", "file '${OUT}_after.mp4'")
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i '${DIR}\\cuts\\${OUT}_pair.txt' -c copy '${DIR}\\cuts\\${OUT}.mp4'
Write-Output ('rendered ' + (Get-Item '${DIR}\\cuts\\${OUT}.mp4').Length)
EOF
  echo "  pair: render $(since "$T0")"
  pc_promote "${DIR}" "${NN}_before" "${BEFORE}" | sed 's/^/  | /'
  pc_promote "${DIR}" "${NN}_after" "${AFTER}" | sed 's/^/  | /'
else
  # A shot at another ref (ref:) is filmed with the capture tools that ref has,
  # then the worktree comes back to the branch.
  if [ -n "${REF}" ]; then
    T0=$(now_ms)
    pc_checkout "${REF}"
    echo "  ref ${REF}: checkout+import $(since "$T0")"
  fi
  TAG=$(best_take "${NN}" "$(python3 -c "print(${IN} + ${TOTAL} + 1.0)")")
  if [ -n "${REF}" ]; then
    T0=$(now_ms)
    pc_checkout "${PC_BRANCH}"
    echo "  back to ${PC_BRANCH}: checkout+import $(since "$T0")"
  fi
  T0=$(now_ms)
  render_take "${TAG}" "${DIR}\\cuts\\${OUT}.mp4" "${TOTAL}" "${SECONDS_WANTED}" | sed 's/^/  | /'
  deliver_take "${TAG}" "${SECONDS_WANTED}" | sed 's/^/  | /'
  echo "  render: $(since "$T0")"
  pc_promote "${DIR}" "${NN}" "${TAG}" | sed 's/^/  | /'
fi
pc_worktrees_clean | sed 's/^/  | /'
echo "shot ${NN} done in $(since "$T_ALL"): ${DIR}\\cuts\\${OUT}.mp4"
