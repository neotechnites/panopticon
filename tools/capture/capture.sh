#!/usr/bin/env bash
# Record one named b-roll shot on the PC and bring the .avi back to the Mac.
#
#   tools/capture/capture.sh <shot> [seconds]
#
# Ships nothing: the PC plays whatever tools/pc_sync.sh last pushed there.
#
# Two Windows facts this works around. Movie Maker needs a real window, and an
# ssh session lands in session 0 where there is no OpenGL context at all -- godot
# there fails to create a window and hangs -- so the run is handed to a scheduled
# task with an Interactive principal, which puts it in the logged-on console
# session with the GPU. And Movie Maker records the ROOT VIEWPORT, whose size is
# project.godot's and which --resolution does not touch, so SIZE is applied
# through a temporary override.cfg that is removed again whatever happens.
#
# Overridable by environment: PC_PROJECT PC_GODOT PC_HOST FPS SIZE SEED BOTS DELAY LOOK STAGE POV AUDIO.
set -euo pipefail

PULL=0
for a in "$@"; do [ "$a" = "--pull" ] && PULL=1; done
set -- "${@/--pull/}"
SHOT="${1:?usage: tools/capture/capture.sh <shot> [seconds] [--pull]}"
SECS="${2:-0}"   # 0 means the shot's own authored duration

HOST=${PC_HOST:-panopticon-pc}
PROJECT=${PC_PROJECT:-'C:\dev\panopticon'}
GODOT=${PC_GODOT:-'C:\tools\godot\godot.exe'}
FPS=${FPS:-60}
SIZE=${SIZE:-1280x720}
SEED=${SEED:-20260930}
BOTS=${BOTS:-7}
DELAY=${DELAY:-0}   # seconds of match played before the path starts
LOOK=${LOOK:-social}
STAGE=${STAGE:-}
POV=${POV:-}
AUDIO=${AUDIO:-near}

WIDTH=${SIZE%%x*}
HEIGHT=${SIZE##*x}
PC_DIR='C:\Users\ddd\Desktop\panopticon-renders\clips'
PC_AVI="${PC_DIR}\\${SHOT}.avi"
PC_LOG='C:\dev\panopticon_clip.log'
TASK=panopticon_clip
MAC_DIR=~/Desktop/panopticon-renders/clips

CMD="${GODOT} --path ${PROJECT} --script res://tools/capture/run_clip.gd"
CMD="${CMD} --write-movie ${PC_AVI} --fixed-fps ${FPS} --resolution ${SIZE}"
CMD="${CMD} -- --shot=${SHOT} --seconds=${SECS} --delay=${DELAY} --look=${LOOK} --stage=${STAGE} --pov=${POV} --audio=${AUDIO} --seed=${SEED} --bots=${BOTS}"

echo "PC> ${CMD}"
mkdir -p "${MAC_DIR}"

ssh "${HOST}" "\$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path '${PC_DIR}' | Out-Null
Remove-Item '${PC_AVI}' -ErrorAction SilentlyContinue
Set-Content -Path '${PROJECT}\override.cfg' -Value @('[display]','window/size/viewport_width=${WIDTH}','window/size/viewport_height=${HEIGHT}')
try {
  \$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c ${CMD} > ${PC_LOG} 2>&1'
  \$who = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -LogonType Interactive
  Register-ScheduledTask -TaskName '${TASK}' -Action \$action -Principal \$who -Force | Out-Null
  Start-ScheduledTask -TaskName '${TASK}'
  while ((Get-ScheduledTask -TaskName '${TASK}').State -eq 'Running') { Start-Sleep -Seconds 2 }
  \$code = (Get-ScheduledTaskInfo -TaskName '${TASK}').LastTaskResult
  Unregister-ScheduledTask -TaskName '${TASK}' -Confirm:\$false
  Get-Content '${PC_LOG}' -ErrorAction SilentlyContinue | Select-Object -Last 12
  if (\$code -ne 0) { Write-Output \"godot exit \$code\"; exit \$code }
} finally {
  Remove-Item '${PROJECT}\override.cfg' -ErrorAction SilentlyContinue
}"

# Clips stay on the PC (Ryan: nothing lands on the Mac unless it is being posted).
# Pass --pull to copy this one clip to the Mac.
if [ "${PULL:-0}" = "1" ]; then
  scp -q "${HOST}:C:/Users/ddd/Desktop/panopticon-renders/clips/${SHOT}.avi" "${MAC_DIR}/"
  ls -lh "${MAC_DIR}/${SHOT}.avi"
else
  echo "clip on the PC: C:\\Users\\ddd\\Desktop\\panopticon-renders\\clips\\${SHOT}.avi (add --pull to copy it here)"
fi
