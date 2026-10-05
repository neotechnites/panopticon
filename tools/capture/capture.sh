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
# session with the GPU. And Movie Maker records the ROOT VIEWPORT at whatever
# size project.godot's own override.cfg says (--resolution and a runtime resize
# both leave the recorded frame at the project's authored size, tested).
#
# Concurrency: --write-movie renders offline, so two Godot instances on the PC's
# console session are fine, but override.cfg is one file per project directory.
# Each run gets a throwaway project directory instead: every entry of the real
# project junction/hardlinked in (no copy, no reimport) except a fresh
# override.cfg, so two runs never see the same file. Each run also gets its own
# scheduled-task name, output .avi and log. MAX_PARALLEL (default 2) is a
# Mac-side mkdir semaphore; a third run waits its turn.
#
# Overridable by environment: PC_PROJECT PC_GODOT PC_HOST FPS SIZE SEED BOTS DELAY LOOK STAGE POV HUD MAP AUDIO MAX_PARALLEL.
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
HUD=${HUD:-}
MAP=${MAP:-}   # a MapCatalog id; empty films the map the saved rules name
AUDIO=${AUDIO:-near}
MAX_PARALLEL=${MAX_PARALLEL:-2}

WIDTH=${SIZE%%x*}
HEIGHT=${SIZE##*x}
RUNID="$$_${RANDOM}"   # unique per invocation: project dir, task name, .avi, log never collide
RUN_PROJECT="C:\\dev\\.capture_runs\\${RUNID}"
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

CMD="${GODOT} --path ${RUN_PROJECT} --script res://tools/capture/run_clip.gd"
CMD="${CMD} --write-movie ${PC_AVI_RUN} --fixed-fps ${FPS} --resolution ${SIZE}"
CMD="${CMD} -- --shot=${SHOT} --seconds=${SECS} --delay=${DELAY} --look=${LOOK} --stage=${STAGE} --pov=${POV} --hud=${HUD} --map=${MAP} --audio=${AUDIO} --seed=${SEED} --bots=${BOTS}"

echo "PC> ${CMD}"
mkdir -p "${MAC_DIR}"

ssh "${HOST}" "\$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path '${PC_DIR}' | Out-Null
Remove-Item '${PC_AVI_RUN}' -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path '${RUN_PROJECT}' | Out-Null
Get-ChildItem -Force -LiteralPath '${PROJECT}' | Where-Object { \$_.Name -ne 'override.cfg' } | ForEach-Object {
  \$t = Join-Path '${RUN_PROJECT}' \$_.Name
  if (\$_.PSIsContainer) { cmd /c mklink /J \"\$t\" \"\$(\$_.FullName)\" | Out-Null } else { cmd /c mklink /H \"\$t\" \"\$(\$_.FullName)\" | Out-Null }
}
Set-Content -Path '${RUN_PROJECT}\override.cfg' -Value @('[display]','window/size/viewport_width=${WIDTH}','window/size/viewport_height=${HEIGHT}')
try {
  \$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c ${CMD} > ${PC_LOG} 2>&1'
  \$who = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -LogonType Interactive
  Register-ScheduledTask -TaskName '${TASK}' -Action \$action -Principal \$who -Force | Out-Null
  Start-ScheduledTask -TaskName '${TASK}'
  while ((Get-ScheduledTask -TaskName '${TASK}').State -eq 'Running') { Start-Sleep -Seconds 2 }
  \$code = (Get-ScheduledTaskInfo -TaskName '${TASK}').LastTaskResult
  Unregister-ScheduledTask -TaskName '${TASK}' -Confirm:\$false
  Get-Content '${PC_LOG}' -ErrorAction SilentlyContinue | Select-Object -Last 12
  if (\$code -ne 0) { Write-Output \"godot exit \$code\"; Remove-Item '${PC_AVI_RUN}' -ErrorAction SilentlyContinue; exit \$code }
  Move-Item -Force '${PC_AVI_RUN}' '${PC_AVI}'
} finally {
  # rmdir on a junction removes only the link; Remove-Item -Recurse must never
  # touch this tree, or it can delete the real project's files through it.
  Get-ChildItem -Force -LiteralPath '${RUN_PROJECT}' -ErrorAction SilentlyContinue | ForEach-Object {
    if (\$_.PSIsContainer) { cmd /c rmdir \"\$(\$_.FullName)\" | Out-Null } else { Remove-Item -Force -LiteralPath \$_.FullName -ErrorAction SilentlyContinue }
  }
  Remove-Item -Force -LiteralPath '${RUN_PROJECT}' -ErrorAction SilentlyContinue
}"

# Clips stay on the PC (Ryan: nothing lands on the Mac unless it is being posted).
# Pass --pull to copy this one clip to the Mac.
if [ "${PULL:-0}" = "1" ]; then
  scp -q "${HOST}:C:/Users/ddd/Desktop/panopticon-renders/clips/${SHOT}.avi" "${MAC_DIR}/"
  ls -lh "${MAC_DIR}/${SHOT}.avi"
else
  echo "clip on the PC: C:\\Users\\ddd\\Desktop\\panopticon-renders\\clips\\${SHOT}.avi (add --pull to copy it here)"
fi
