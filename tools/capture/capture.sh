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
# session with the GPU. And Movie Maker records the ROOT VIEWPORT, sized by
# run_clip.gd's own --viewport arg now, not a project.godot override.cfg.
#
# Concurrency: --write-movie renders offline, so two Godot instances on the PC's
# console session are fine. Each run gets its own scheduled-task name, output
# .avi and log, so nothing shared races; MAX_PARALLEL (default 2) is a Mac-side
# mkdir semaphore, so a third run waits its turn rather than piling onto the PC.
#
# Overridable by environment: PC_PROJECT PC_GODOT PC_HOST FPS SIZE SEED BOTS DELAY LOOK STAGE POV AUDIO MAX_PARALLEL.
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
MAX_PARALLEL=${MAX_PARALLEL:-2}

RUNID="$$_${RANDOM}"   # unique per invocation: task name, temp .avi, log never collide
PC_DIR='C:\Users\ddd\Desktop\panopticon-renders\clips'
PC_AVI="${PC_DIR}\\${SHOT}.avi"
PC_AVI_RUN="${PC_DIR}\\.run_${RUNID}_${SHOT}.avi"
PC_LOG="C:\\dev\\panopticon_clip_${RUNID}.log"
TASK="panopticon_clip_${RUNID}"
MAC_DIR=~/Desktop/panopticon-renders/clips

# A MAX_PARALLEL-wide mkdir semaphore; a third concurrent run waits its turn.
LOCK_ROOT=${TMPDIR:-/tmp}/panopticon_capture.locks
mkdir -p "${LOCK_ROOT}"
SLOT=""
acquire_slot() {
  while :; do
    for i in $(seq 1 "${MAX_PARALLEL}"); do
      if mkdir "${LOCK_ROOT}/slot${i}" 2>/dev/null; then SLOT="${LOCK_ROOT}/slot${i}"; return; fi
    done
    sleep 1
  done
}
release_slot() { [ -n "${SLOT}" ] && rmdir "${SLOT}" 2>/dev/null; true; }
trap release_slot EXIT
acquire_slot

CMD="${GODOT} --path ${PROJECT} --script res://tools/capture/run_clip.gd"
CMD="${CMD} --write-movie ${PC_AVI_RUN} --fixed-fps ${FPS} --resolution ${SIZE}"
CMD="${CMD} -- --shot=${SHOT} --seconds=${SECS} --delay=${DELAY} --look=${LOOK} --stage=${STAGE} --pov=${POV} --audio=${AUDIO} --seed=${SEED} --bots=${BOTS} --viewport=${SIZE}"

echo "PC> ${CMD}"
mkdir -p "${MAC_DIR}"

ssh "${HOST}" "\$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path '${PC_DIR}' | Out-Null
Remove-Item '${PC_AVI_RUN}' -ErrorAction SilentlyContinue
\$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c ${CMD} > ${PC_LOG} 2>&1'
\$who = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -LogonType Interactive
Register-ScheduledTask -TaskName '${TASK}' -Action \$action -Principal \$who -Force | Out-Null
Start-ScheduledTask -TaskName '${TASK}'
while ((Get-ScheduledTask -TaskName '${TASK}').State -eq 'Running') { Start-Sleep -Seconds 2 }
\$code = (Get-ScheduledTaskInfo -TaskName '${TASK}').LastTaskResult
Unregister-ScheduledTask -TaskName '${TASK}' -Confirm:\$false
Get-Content '${PC_LOG}' -ErrorAction SilentlyContinue | Select-Object -Last 12
if (\$code -ne 0) { Write-Output \"godot exit \$code\"; Remove-Item '${PC_AVI_RUN}' -ErrorAction SilentlyContinue; exit \$code }
Move-Item -Force '${PC_AVI_RUN}' '${PC_AVI}'"

# Clips stay on the PC (Ryan: nothing lands on the Mac unless it is being posted).
# Pass --pull to copy this one clip to the Mac.
if [ "${PULL:-0}" = "1" ]; then
  scp -q "${HOST}:C:/Users/ddd/Desktop/panopticon-renders/clips/${SHOT}.avi" "${MAC_DIR}/"
  ls -lh "${MAC_DIR}/${SHOT}.avi"
else
  echo "clip on the PC: C:\\Users\\ddd\\Desktop\\panopticon-renders\\clips\\${SHOT}.avi (add --pull to copy it here)"
fi
