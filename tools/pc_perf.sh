#!/usr/bin/env bash
# Frame-time of ONE map from ONE camera pose on the PC's GPU (tools/perf/profile_match.gd
# --static=1), the CSV brought back to the Mac. Same throwaway clone and console-session
# hand-off as tools/pc_shot.sh; never C:\dev\panopticon.
#
#   tools/pc_perf.sh <git-ref> <map id> <out.csv> <at x,y,z> <look x,y,z> [seconds]
set -euo pipefail
[ $# -ge 5 ] || { echo "usage: tools/pc_perf.sh <git-ref> <map> <out.csv> <at x,y,z> <look x,y,z> [seconds]" >&2; exit 2; }
REF="$1"; MAP="$2"; OUT="$3"; AT="$4"; LOOK="$5"; SECS="${6:-20}"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || { echo "pc_perf: no such ref: $REF" >&2; exit 2; }

PC=${PC_HOST:-panopticon-pc}
GODOT=${PC_GODOT:-'C:\tools\godot\godot.exe'}
CLONE='C:/Users/ddd/panopticon-ceiling'
CLONE_W='C:\Users\ddd\panopticon-ceiling'
WORK='C:/Users/ddd/panopticon-perf-work'
WORK_W='C:\Users\ddd\panopticon-perf-work'
PC_CSV="$WORK/perf.csv"
TASK=PanopticonPerf
TIMEOUT=${PC_PERF_TIMEOUT:-600}
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

say "clone $CLONE at $REF"
ssh -o ConnectTimeout=20 "$PC" "
  \$ErrorActionPreference = 'Stop'
  if (-not (Test-Path '$CLONE_W\\.git')) { git clone --quiet C:/dev/panopticon '$CLONE' }
  New-Item -ItemType Directory -Force -Path '$WORK_W' | Out-Null
"
git push "$PC:$CLONE" "$REF:refs/heads/incoming" -f 2>&1 | tail -1
ssh -o ConnectTimeout=20 "$PC" "
  \$ErrorActionPreference = 'Stop'
  git -C '$CLONE' checkout -q -f -B shot incoming
  git -C '$CLONE' reset -q --hard incoming
  git -C '$CLONE' clean -fdq -- ':(glob)**/models/**'
  Get-ChildItem $CLONE_W -Recurse -Include *_albedo.png*, *_emissive.png* | Where-Object { \$_.Directory.Name -eq 'models' } | Remove-Item -ErrorAction SilentlyContinue
  \$hook = 'res://tools/import/mipmap_textures.gd'
  Get-ChildItem $CLONE_W -Recurse -Filter *.glb.import | ForEach-Object {
    \$t = Get-Content \$_.FullName -Raw
    if (\$t -match 'gltf/embedded_image_handling=') { \$t = \$t -replace 'gltf/embedded_image_handling=\\d', 'gltf/embedded_image_handling=3' }
    else { \$t = \$t -replace '\\[params\\]\\r?\\n', \"[params]\`r\`ngltf/embedded_image_handling=3\`r\`n\" }
    if (\$t -match 'import_script/path=(.*)') {
      \$cur = \$Matches[1].Trim().Trim([char]34)
      if (\$cur -eq '' -or \$cur -eq \$hook) { \$t = \$t -replace 'import_script/path=[^\\r\\n]*', ('import_script/path=' + [char]34 + \$hook + [char]34) }
      else { Write-Output ('WARNING: ' + \$_.Name + ' keeps its own import_script ' + \$cur) }
    }
    else { \$t = \$t -replace '\\[params\\]\\r?\\n', (\"[params]\`r\`nimport_script/path=\" + [char]34 + \$hook + [char]34 + \"\`r\`n\") }
    [IO.File]::WriteAllText(\$_.FullName, \$t)
  }
  cmd /c \"$GODOT --headless --import --path $CLONE_W > $WORK_W\\import.txt 2>&1\"
  Write-Output ('perf at ' + (git -C '$CLONE' log --oneline -1))
"

scp -q "$HERE/tools/modelling/lib/pcrun.ps1" "$PC:$WORK/pcrun.ps1"
cat > "$TMP/perf.bat" <<EOB
@echo off
set W=$WORK_W
del /q "%W%\\perf.done" 2>nul
del /q "%W%\\perf.csv" 2>nul
cd /d "%W%"
"$GODOT" --path $CLONE_W --script res://tools/perf/profile_match.gd -- --static=1 --map=$MAP --at=$AT --look=$LOOK --seconds=$SECS --warmup=3 --width=1920 --height=1080 --label=$MAP --out=$PC_CSV > "%W%\\perf.log" 2>&1
set RC=%ERRORLEVEL%
findstr /c:"SUMMARY " "%W%\\perf.log" >nul || set RC=1
echo %RC% > "%W%\\perf.done"
EOB
scp -q "$TMP/perf.bat" "$PC:$WORK/perf.bat"

say "perf $MAP at=$AT look=$LOOK ${SECS}s"
ssh -o ConnectTimeout=20 "$PC" \
  "powershell -NoProfile -ExecutionPolicy Bypass -File '$WORK_W\\pcrun.ps1' -Bat '$WORK_W\\perf.bat' -TaskName '$TASK' -TimeoutSec $TIMEOUT"
mkdir -p "$(dirname "$OUT")"
scp -q "$PC:$PC_CSV" "$OUT"
grep SUMMARY "$OUT"
