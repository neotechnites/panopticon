#!/usr/bin/env bash
# Shared by tools/content/*.sh: brief parsing, PC paths, and the Godot runner.
# Everything renders on the PC; the Mac only reads the brief and drives ssh.

CONTENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${CONTENT_DIR}/../.." && pwd)"

PC_HOST=${PC_HOST:-ddd@100.114.41.16}
PC_KEY=${PC_KEY:-~/.ssh/panopticon_pc_ed25519}
PC_PROJECT=${PC_PROJECT:-'C:\dev\verify'}
PC_GODOT=${PC_GODOT:-'C:\tools\godot\godot.exe'}
PC_RESOLVE=${PC_RESOLVE:-'C:\Program Files\Blackmagic Design\DaVinci Resolve\Resolve.exe'}
PC_FUSCRIPT=${PC_FUSCRIPT:-'C:\Program Files\Blackmagic Design\DaVinci Resolve\fuscript.exe'}
PC_CONTENT='C:\Users\ddd\Desktop\panopticon-renders\content'
PC_BRANCH=${PC_BRANCH:-work-content}
FPS=${FPS:-60}
SIZE=${SIZE:-1280x720}
MAC_STILLS=${MAC_STILLS:-$HOME/.claude/jobs/070eaa3c/tmp/content}

# Take gate: a take is kept when at least MOTION_MIN of its pixels change between
# samples 0.1 s apart (averaged over the take) and no stretch of it is frozen for
# FREEZE_MAX_SECONDS. A staged shot is deterministic, so the retries are few.
MOTION_MIN=${MOTION_MIN:-0.02}
FREEZE_MAX_SECONDS=${FREEZE_MAX_SECONDS:-0.75}
FREEZE_NOISE_DB=${FREEZE_NOISE_DB:--50}
TAKES_MAX=${TAKES_MAX:-2}

die() { echo "content: $*" >&2; exit 2; }

# ssh into the PC and run a PowerShell script read from stdin. Encoded, because
# `-Command -` parses stdin line by line and drops a block with no blank line after it.
pc() {
  local encoded
  encoded=$(python3 -c 'import sys,base64; print(base64.b64encode(sys.stdin.read().encode("utf-16-le")).decode())')
  ssh -i "${PC_KEY}" -o ConnectTimeout=20 "${PC_HOST}" "powershell -NoProfile -EncodedCommand ${encoded}" \
    2> >(grep -v '^#< CLIXML\|^<Objs' >&2)
}

pc_pull() { scp -q -i "${PC_KEY}" "${PC_HOST}:$1" "$2"; }
pc_push() { scp -q -i "${PC_KEY}" "$1" "${PC_HOST}:$2"; }

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
since() { echo "$(( ($(now_ms) - $1) / 1000 ))s"; }

# --- The brief -----------------------------------------------------------------

brief_path() {
  local project="$1"
  if [ -f "${project}" ]; then echo "${project}"; return; fi
  local path="${CONTENT_DIR}/projects/${project}.md"
  [ -f "${path}" ] || die "no brief at ${path}"
  echo "${path}"
}

# Header field: brief_head <brief> <key> [default]
brief_head() {
  local value
  value=$(awk -v key="$2" '/^## /{exit} $0 ~ "^"key":"{sub("^"key":[ \t]*",""); print; exit}' "$1")
  echo "${value:-${3:-}}"
}

brief_title() { awk '/^# /{sub("^# ",""); print; exit}' "$1"; }

# Shot count: the number of "## <n>" headings.
brief_count() { grep -c '^## [0-9]' "$1"; }

# Entry field: brief_field <brief> <n> <key> [default]
brief_field() {
  local value
  value=$(awk -v n="$2" -v key="$3" '
    /^## [0-9]+/ { inside = ($2 == n); next }
    inside && $0 ~ "^"key":" { sub("^"key":[ \t]*", ""); print; exit }' "$1")
  echo "${value:-${4:-}}"
}

pad2() { printf '%02d' "$1"; }

# --- Running Godot on the PC ---------------------------------------------------

# pc_godot <args-after-godot> <log-path> : run Godot in the logged-on console
# session (Movie Maker needs a window and a GPU) via a scheduled task, wait, and
# print the log tail. A temporary override.cfg pins the recorded viewport size.
pc_godot() {
  local args="$1" log="$2" task="panopticon_content_$$"
  local width="${SIZE%%x*}" height="${SIZE##*x}"
  pc <<EOF
\$ErrorActionPreference = 'Stop'
Set-Content -Path '${PC_PROJECT}\\override.cfg' -Value @('[display]','window/size/viewport_width=${width}','window/size/viewport_height=${height}')
try {
  \$action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c ${PC_GODOT} --path ${PC_PROJECT} ${args} > ${log} 2>&1'
  \$who = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -LogonType Interactive
  Register-ScheduledTask -TaskName '${task}' -Action \$action -Principal \$who -Force | Out-Null
  Start-ScheduledTask -TaskName '${task}'
  Start-Sleep -Seconds 2
  while ((Get-ScheduledTask -TaskName '${task}').State -eq 'Running') { Start-Sleep -Seconds 2 }
  \$code = (Get-ScheduledTaskInfo -TaskName '${task}').LastTaskResult
  Unregister-ScheduledTask -TaskName '${task}' -Confirm:\$false
  Get-Content '${log}' -ErrorAction SilentlyContinue | Where-Object { \$_ -match '^(shot |look |\\[stage\\]|\\[event\\]|\\[pov\\]|SCRIPT ERROR|SHOT )' } | Select-Object -Last 14
  if (\$code -ne 0) { Write-Output "godot exit \$code" }
} finally {
  Remove-Item '${PC_PROJECT}\\override.cfg' -ErrorAction SilentlyContinue
}
EOF
}

# Windows path helpers.
win() { echo "$1" | sed 's#/#\\#g'; }
ff() { echo "$1" | sed 's#\\#/#g'; }
