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
PC_PYTHON=${PC_PYTHON:-'C:\Users\ddd\tools\python\python.exe'}   # edge-tts and yt-dlp live here
PC_SERVE_PORT=${PC_SERVE_PORT:-8765}
PC_RENDERS='C:\Users\ddd\Desktop\panopticon-renders'
PC_CONTENT="${PC_RENDERS}\content"
PC_BRANCH=${PC_BRANCH:-work-content}
FPS=${FPS:-60}
SIZE=${SIZE:-1280x720}
MJPEG_QUALITY=${MJPEG_QUALITY:-0.95}
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
    /^## / { inside = ($2 == n); next }
    inside && $0 ~ "^"key":" { sub("^"key":[ \t]*", ""); print; exit }' "$1")
  echo "${value:-${4:-}}"
}

# A shot id is a number with an optional letter (5b): 05b.
pad2() { local n="${1%%[!0-9]*}"; printf '%02d%s' "$((10#${n}))" "${1#"${n}"}"; }

# The tape a brief entry plays (tools/capture/clip_tape.gd), in the repo next to the brief.
tape_res() { echo "res://tools/content/projects/$1/tapes/$2.json"; }

# --- The project folder on the PC ----------------------------------------------
# Every project is one folder, content\<project>\, split by what a file is:
#   final\    delivered clips: <file>.mp4 from a shot's file: line, final*.mp4
#   cuts\     the edit: NN.mp4 shot masters, timeline.mp4, beats.txt, list.txt, slates\
#   voice\    voice_NN.wav recordings and voice_gap.txt
#   notes\    brief.md, caption_NN.txt, NN.gate.txt and NN.take.log per shot
#   stages\   stage .gd scripts written for the shots
#   frames\   pulled frames: sheet.png, final_still.png, NN.png stills
#   scripts\  resolve_project.lua and any one-off .ps1
#   takes\    raw takes while a shot is being captured; gone once it is cut
PROJECT_FOLDERS='final cuts voice notes stages frames scripts'

project_dir() { echo "${PC_CONTENT}\\$1"; }

# pc_layout <dir> : make the project folder and its subfolders.
pc_layout() {
  local dir="$1" list
  list=$(for f in ${PROJECT_FOLDERS}; do printf "'%s\\\\%s', " "${dir}" "${f}"; done)
  pc <<EOF
New-Item -ItemType Directory -Force -Path ${list}'${dir}\\takes' | Out-Null
EOF
}

# pc_promote <dir> <NN> <tag> : shot NN is cut; keep the chosen take's gate report
# and Godot log as notes\NN.gate.txt and notes\NN.take.log, delete every take of
# the shot (the passing one has been rendered, the failing ones are not kept), and
# drop takes\ when it is empty.
pc_promote() {
  local dir="$1" nn="$2" tag="$3"
  pc <<EOF
\$t = '${dir}\\takes'
if (Test-Path "\$t\\${tag}.txt") { Move-Item -Force "\$t\\${tag}.txt" '${dir}\\notes\\${nn}.gate.txt' }
if (Test-Path "\$t\\${tag}.log") { Move-Item -Force "\$t\\${tag}.log" '${dir}\\notes\\${nn}.take.log' }
\$gone = Get-ChildItem \$t -File -Filter '${nn}_*' -ErrorAction SilentlyContinue
\$bytes = (\$gone | Measure-Object Length -Sum).Sum
\$gone | Remove-Item -Force
if ((Test-Path \$t) -and -not (Get-ChildItem \$t -Force)) { Remove-Item \$t -Force }
Write-Output ('takes of ${nn} deleted: ' + \$gone.Count + ' files, ' + [math]::Round(\$bytes / 1MB, 1) + ' MB')
EOF
}

# pc_worktrees_clean : unregister and delete any git worktree of the real repo or
# the scratch checkout that was left under panopticon-renders (a work_<shot>
# copy of the repo is scratch: it goes when the shot is done).
pc_worktrees_clean() {
  pc <<EOF
foreach (\$repo in 'C:/dev/panopticon', 'C:/dev/verify') {
  \$paths = git -C \$repo worktree list --porcelain 2>\$null | Where-Object { \$_ -like 'worktree *' } | ForEach-Object { \$_.Substring(9) }
  foreach (\$p in \$paths) {
    if (\$p -like '*/panopticon-renders/*') {
      git -C \$repo worktree remove --force \$p 2>&1 | Out-Null
      if (Test-Path \$p) { Remove-Item -LiteralPath \$p -Recurse -Force }
      Write-Output ('scratch worktree removed: ' + \$p)
    }
  }
  git -C \$repo worktree prune 2>\$null
}
EOF
}

# --- Running Godot on the PC ---------------------------------------------------

# pc_godot <args-after-godot> <log-path> : run Godot in the logged-on console
# session (Movie Maker needs a window and a GPU) via a scheduled task, wait, and
# print the log tail. A temporary override.cfg pins the recorded viewport size and
# the take's JPEG quality (Godot's 0.75 smears the rock the game shows clean).
pc_godot() {
  local args="$1" log="$2" task="panopticon_content_$$"
  local width="${SIZE%%x*}" height="${SIZE##*x}"
  pc <<EOF
\$ErrorActionPreference = 'Stop'
Set-Content -Path '${PC_PROJECT}\\override.cfg' -Value @('[display]','window/size/viewport_width=${width}','window/size/viewport_height=${height}','[editor]','movie_writer/mjpeg_quality=${MJPEG_QUALITY}')
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

# pc_rough <run_clip-args> <log-path> <raw-path> : the same take at real speed. Godot
# plays borderless at 0,0 (--fixed-fps and --max-fps 60) and ffmpeg records that
# 1920x1080 of the screen (ddagrab, no cursor, h264_amf) to <raw-path>. The take's
# white sync frames (run_clip --sync) put its t=0 in <raw-path>.sync, in seconds.
pc_rough() {
  local args="$1" log="$2" raw="$3" task="panopticon_content_$$"
  local width="${SIZE%%x*}" height="${SIZE##*x}" runner="${3%.*}.ps1"
  pc <<EOF
\$ErrorActionPreference = 'Stop'
Set-Content -Path '${PC_PROJECT}\\override.cfg' -Value @('[display]','window/size/viewport_width=${width}','window/size/viewport_height=${height}','window/size/borderless=true','window/size/always_on_top=true')
Set-Content -Path '${runner}' -Value @'
\$g = New-Object System.Diagnostics.ProcessStartInfo 'cmd.exe', '/c ${PC_GODOT} --path ${PC_PROJECT} --fixed-fps ${FPS} --max-fps ${FPS} --resolution ${SIZE} --position 0,0 ${args} > ${log} 2>&1'
\$g.UseShellExecute = \$false; \$g.CreateNoWindow = \$true
\$gp = [System.Diagnostics.Process]::Start(\$g)
\$deadline = (Get-Date).AddSeconds(90)
do {
  Start-Sleep -Milliseconds 50
  \$kid = Get-CimInstance Win32_Process -Filter "ParentProcessId=\$(\$gp.Id)" | Where-Object Name -like 'godot*' | Select-Object -First 1
  \$win = if (\$kid) { (Get-Process -Id \$kid.ProcessId -ErrorAction SilentlyContinue).MainWindowHandle } else { 0 }
} until ((\$win -ne 0) -or \$gp.HasExited -or ((Get-Date) -gt \$deadline))
\$f = New-Object System.Diagnostics.ProcessStartInfo 'cmd.exe', '/c ffmpeg -hide_banner -loglevel error -y -f lavfi -i ddagrab=output_idx=0:framerate=${FPS}:video_size=${SIZE}:offset_x=0:offset_y=0:draw_mouse=0 -vf hwdownload,format=bgra,scale=out_range=tv:out_color_matrix=bt709,format=yuv420p -c:v h264_amf -quality quality -rc cqp -qp_i 14 -qp_p 14 -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 ${raw} 2> ${raw}.err'
\$f.UseShellExecute = \$false; \$f.CreateNoWindow = \$true; \$f.RedirectStandardInput = \$true
\$fp = [System.Diagnostics.Process]::Start(\$f)
if (-not \$gp.WaitForExit(600000) -and \$kid) { Stop-Process -Id \$kid.ProcessId -Force }
\$fp.StandardInput.Write('q'); \$fp.StandardInput.Close()
if (-not \$fp.WaitForExit(30000)) { Stop-Process -Id \$fp.Id -Force }
'@
try {
  \$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ${runner}'
  \$who = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -LogonType Interactive
  Register-ScheduledTask -TaskName '${task}' -Action \$action -Principal \$who -Force | Out-Null
  Start-ScheduledTask -TaskName '${task}'
  Start-Sleep -Seconds 2
  while ((Get-ScheduledTask -TaskName '${task}').State -eq 'Running') { Start-Sleep -Seconds 1 }
} finally {
  Unregister-ScheduledTask -TaskName '${task}' -Confirm:\$false -ErrorAction SilentlyContinue
  Remove-Item '${PC_PROJECT}\\override.cfg' -ErrorAction SilentlyContinue
}
\$ErrorActionPreference = 'Continue'
Get-Content '${raw}.err' -ErrorAction SilentlyContinue | Select-Object -Last 4
Get-Content '${log}' -ErrorAction SilentlyContinue | Where-Object { \$_ -match '^(shot |look |\\[stage\\]|\\[event\\]|\\[pov\\]|SCRIPT ERROR|SHOT )' } | Select-Object -Last 14
\$d = ffmpeg -hide_banner -nostats -i '${raw}' -an -vf 'negate,blackdetect=d=0.25:pix_th=0.05:pic_th=0.98' -f null - 2>&1 | Select-String 'black_end:([0-9.]+)' | Select-Object -Last 1
if (-not \$d) { Write-Output 'rough: no sync frames in the recording'; exit 3 }
\$t0 = [double]::Parse(\$d.Matches[0].Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) - 1.0 / ${FPS}
Set-Content -Path '${raw}.sync' -Value \$t0.ToString([Globalization.CultureInfo]::InvariantCulture)
Write-Output ('rough: take t=0 at ' + \$t0.ToString('0.000') + ' s of the recording')
EOF
}

# PowerShell that imports C:\dev\verify. Godot never re-imports a .glb when only
# the import hook changed, so a changed tools\import\ drops every .glb's md5 and the
# filesystem cache (which otherwise skips the test) and imports twice (stale UIDs).
PC_IMPORT=$(cat <<'PS'
$hook = (Get-ChildItem C:\dev\verify\tools\import -Filter '*.gd' | Sort-Object Name | Get-FileHash | ForEach-Object Hash) -join ''
$stamp = 'C:\dev\verify\.godot\import_hook.stamp'
$passes = 1
if (-not (Test-Path $stamp) -or (Get-Content $stamp -Raw).Trim() -ne $hook) {
  Get-ChildItem C:\dev\verify\.godot\imported -Filter '*.glb-*.md5' -ErrorAction SilentlyContinue | Remove-Item -Force
  Get-ChildItem C:\dev\verify\.godot\editor -Filter 'filesystem_cache*' -ErrorAction SilentlyContinue | Remove-Item -Force
  $passes = 2
  Write-Output 'import hook changed: every .glb re-imported'
}
for ($i = 0; $i -lt $passes; $i++) { cmd /c "C:\tools\godot\godot.exe --headless --import --path C:\dev\verify > C:\dev\content_import.txt 2>&1" }
Set-Content -Path $stamp -Value $hook
# A .glb re-import rewrites its extracted textures' .import with defaults (no mips, new
# uid); the committed ones are what the game runs, so they go back and import again.
$bent = @(git -C C:/dev/verify diff --name-only -- '*.import')
if ($bent) {
  git -C C:/dev/verify checkout -- $bent
  foreach ($b in $bent) { Get-ChildItem C:\dev\verify\.godot\imported -Filter ((Split-Path $b -Leaf) -replace '\.import$', '-*.md5') -ErrorAction SilentlyContinue | Remove-Item -Force }
  Get-ChildItem C:\dev\verify\.godot\editor -Filter 'filesystem_cache*' -ErrorAction SilentlyContinue | Remove-Item -Force
  cmd /c "C:\tools\godot\godot.exe --headless --import --path C:\dev\verify > C:\dev\content_import.txt 2>&1"
  Write-Output ('committed .import restored: ' + $bent.Count)
}
PS
)

# pc_checkout <ref> : put the scratch worktree at <ref> and import it. Only ever
# C:\dev\verify; the real checkout is never touched.
pc_checkout() {
  pc <<EOF
git -C C:/dev/verify checkout -q $1
${PC_IMPORT}
Write-Output ('verify at ' + (git -C C:/dev/verify log --oneline -1))
EOF
}

# Windows path helpers.
win() { echo "$1" | sed 's#/#\\#g'; }
ff() { echo "$1" | sed 's#\\#/#g'; }
