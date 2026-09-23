#!/usr/bin/env bash
# Render ONE in-game frame of a scene on the PC's GPU and bring the png to the Mac.
#
#   tools/pc_shot.sh <git-ref> <res://scene> <out.png on the Mac> <pos x,y,z> <look x,y,z>
#   tools/pc_shot.sh <git-ref> <res://scene> <out dir on the Mac> --list <file>
#
# --list: one shot per line, "name x,y,z x,y,z" (pos, look), all from ONE Godot
# run into <out dir>/<name>.png (RES= and SETTLE= apply to it too).
#
# Why a separate clone. tools/pc_sync.sh owns C:\dev\panopticon -- that is Ryan's
# play copy, it carries his uncommitted edits, and nothing here may touch it.
# This script keeps its own throwaway clone at C:/Users/ddd/panopticon-ceiling so
# a subagent can look at a branch that has not been merged anywhere.
#
# Why a scheduled task. An OpenSSH session on Windows lands in session 0, which
# has no OpenGL context: godot there fails to make a window and hangs. The shot
# is therefore handed to the logged-on CONSOLE session through a copy of
# tools/modelling/lib/pcrun.ps1, exactly as the modelling pipeline does for
# EEVEE, and the .bat writes shot.log and then shot.done with its exit code --
# a scheduled task returns immediately and its own status tells you nothing.
#
# Godot is y-up: pos/look are Godot world coordinates.
#
# Two optional environment variables:
#   RES=1920x1080   render at that size. Godot's root viewport is project.godot's
#                   and --resolution does not touch it, so the size arrives as a
#                   temporary override.cfg -- written into the THROWAWAY CLONE
#                   only, never C:\dev\panopticon, and removed in a finally
#                   whatever happens, exactly as tools/capture/capture.sh does.
#   SETTLE=4        seconds of real time to run before the shot, for anything
#                   that eases into place (the WatchingEye's pupil). Passed
#                   through to shot.gd as --settle=.
#   FLAT=1          override every drawn surface with one plain grey: the shot
#                   then shows FORM and nothing else, which is the only way to
#                   tell a geometry defect from a texture one without guessing.
#   FOV=45          camera field of view in degrees (shot.gd's default is 100).
# Unset, all of them leave the godot command line and the render exactly as they were.
set -euo pipefail

usage() {
  echo "usage: tools/pc_shot.sh <git-ref> <res://scene> <out.png> <pos x,y,z> <look x,y,z>" >&2
  echo "       tools/pc_shot.sh <git-ref> <res://scene> <out dir> --list <file>" >&2
  exit 2
}
[ $# -eq 5 ] || usage

REF="$1"; SCENE="$2"; OUT="$3"; POS="$4"; LOOK="$5"
LIST=""
if [ "$POS" = "--list" ]; then
  LIST="$LOOK"; [ -f "$LIST" ] || { echo "pc_shot: no such list: $LIST" >&2; exit 2; }
fi

case "$SCENE" in res://*) ;; *) echo "pc_shot: <scene> must be a res:// path" >&2; exit 2 ;; esac
if [ -z "$LIST" ]; then
  case "$POS"  in *,*,*) ;; *) echo "pc_shot: <pos> must be x,y,z" >&2;  exit 2 ;; esac
  case "$LOOK" in *,*,*) ;; *) echo "pc_shot: <look> must be x,y,z" >&2; exit 2 ;; esac
fi

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || { echo "pc_shot: no such ref: $REF" >&2; exit 2; }

PC=${PC_HOST:-panopticon-pc}
GODOT=${PC_GODOT:-'C:\tools\godot\godot.exe'}
CLONE='C:/Users/ddd/panopticon-ceiling'          # forward slashes: git, scp, --path
CLONE_W='C:\Users\ddd\panopticon-ceiling'        # backslashes: cmd
WORK='C:/Users/ddd/panopticon-shot-work'
WORK_W='C:\Users\ddd\panopticon-shot-work'
PC_PNG='C:/Users/ddd/panopticon-ceiling-shot.png'
PC_SHOTS='C:/Users/ddd/panopticon-shot-work/shots'
PC_SHOTS_W='C:\Users\ddd\panopticon-shot-work\shots'
TASK=PanopticonShot
TIMEOUT=${PC_SHOT_TIMEOUT:-600}
RES=${RES:-}
SETTLE=${SETTLE:-}
FLAT=${FLAT:-}
FOV=${FOV:-}
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# override.cfg is this script's alone: write it only when RES asks, but always
# clear it afterwards, so an aborted run cannot silently resize the next one.
OVERRIDE_SET=""
OVERRIDE_DEL="Remove-Item '$CLONE_W\\override.cfg' -ErrorAction SilentlyContinue"
if [ -n "$RES" ]; then
  case "$RES" in *[0-9]x[0-9]*) ;; *) echo "pc_shot: RES must be WIDTHxHEIGHT" >&2; exit 2 ;; esac
  RES_W=${RES%%x*}; RES_H=${RES##*x}
  OVERRIDE_SET="\$ErrorActionPreference = 'Stop'; Set-Content -Path '$CLONE_W\\override.cfg' -Value @('[display]','window/size/viewport_width=$RES_W','window/size/viewport_height=$RES_H')"
fi

# Empty when SETTLE is unset, which leaves the command line below byte-for-byte
# what it has always been.
SETTLE_ARG=""
[ -n "$SETTLE" ] && SETTLE_ARG=" --settle=$SETTLE"
[ -n "$FLAT" ]   && SETTLE_ARG="$SETTLE_ARG --flat=$FLAT"
[ -n "$FOV" ]    && SETTLE_ARG="$SETTLE_ARG --fov=$FOV"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

# -- 1. the clone exists, and it is NOT C:\dev\panopticon -----------------------
say "clone $CLONE"
ssh -o ConnectTimeout=20 "$PC" "
  \$ErrorActionPreference = 'Stop'
  if (-not (Test-Path '$CLONE_W\\.git')) {
    git clone --quiet C:/dev/panopticon '$CLONE'
    Write-Output 'cloned'
  } else { Write-Output 'present' }
  New-Item -ItemType Directory -Force -Path '$WORK_W' | Out-Null
"

# -- 2. the ref lands there as 'incoming', checked out as 'shot' ---------------
say "push $REF -> incoming"
git push "$PC:$CLONE" "$REF:refs/heads/incoming" -f 2>&1 | tail -2
ssh -o ConnectTimeout=20 "$PC" "
  \$ErrorActionPreference = 'Stop'
  git -C '$CLONE' checkout -q -f -B shot incoming
  git -C '$CLONE' reset -q --hard incoming
  git -C '$CLONE' clean -fdq -- assets/models
  Write-Output ('shot at ' + (git -C '$CLONE' log --oneline -1))
"

# -- 3. the .glb.import rewrite pc_sync.sh applies, then a headless import ------
# Godot's default extracts every embedded texture as a sibling png and rewrites
# the .import to point at it; =3 keeps the images inside the .glb, so the tree
# stays clean and the materials survive a clean checkout.
say "import"
ssh -o ConnectTimeout=20 "$PC" "
  Remove-Item $CLONE_W\\assets\\models\\*_albedo.png*, $CLONE_W\\assets\\models\\*_emissive.png* -ErrorAction SilentlyContinue
  Get-ChildItem $CLONE_W\\assets\\models\\*.glb.import | ForEach-Object {
    \$t = Get-Content \$_.FullName -Raw
    if (\$t -match 'gltf/embedded_image_handling=') { \$t = \$t -replace 'gltf/embedded_image_handling=\\d', 'gltf/embedded_image_handling=3' }
    else { \$t = \$t -replace '\\[params\\]\\r?\\n', \"[params]\`r\`ngltf/embedded_image_handling=3\`r\`n\" }
    [IO.File]::WriteAllText(\$_.FullName, \$t)
  }
  Remove-Item $CLONE_W\\assets\\models\\*_albedo.png*, $CLONE_W\\assets\\models\\*_emissive.png* -ErrorAction SilentlyContinue
  cmd /c \"$GODOT --headless --import --path $CLONE_W > $WORK_W\\import.txt 2>&1\"
  \$e = (Select-String -Path $WORK_W\\import.txt -Pattern 'ERROR' | Measure-Object -Line).Lines
  Write-Output ('import errors: ' + \$e)
"

# -- 4. the shot, in the console session ---------------------------------------
scp -q "$HERE/tools/modelling/lib/pcrun.ps1" "$PC:$WORK/pcrun.ps1"

if [ -n "$LIST" ]; then
  ssh -o ConnectTimeout=20 "$PC" "Remove-Item -Recurse -Force '$PC_SHOTS_W' -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force -Path '$PC_SHOTS_W' | Out-Null"
  scp -q "$LIST" "$PC:$WORK/shots.txt"
  SHOT_ARGS="--scene=$SCENE --list=$WORK/shots.txt --out=$PC_SHOTS"
else
  SHOT_ARGS="--scene=$SCENE --pos=$POS --look=$LOOK --out=$PC_PNG"
fi

cat > "$TMP/shot.bat" <<EOF
@echo off
set W=$WORK_W
del /q "%W%\\shot.done" 2>nul
del /q "$PC_PNG" 2>nul
cd /d "%W%"
"$GODOT" --path $CLONE_W --script res://tools/shot.gd -- $SHOT_ARGS$SETTLE_ARG > "%W%\\shot.log" 2>&1
set RC=%ERRORLEVEL%
findstr /c:"SHOT " "%W%\\shot.log" >nul || set RC=1
echo %RC% > "%W%\\shot.done"
EOF
scp -q "$TMP/shot.bat" "$PC:$WORK/shot.bat"

say "shot $SCENE ${LIST:+list=$LIST}${LIST:-pos=$POS look=$LOOK}${RES:+ res=$RES}${SETTLE:+ settle=${SETTLE}s}${FLAT:+ flat}${FOV:+ fov=$FOV}"
ssh -o ConnectTimeout=20 "$PC" "
  $OVERRIDE_SET
  try {
    powershell -NoProfile -ExecutionPolicy Bypass -File '$WORK_W\\pcrun.ps1' -Bat '$WORK_W\\shot.bat' -TaskName '$TASK' -TimeoutSec $TIMEOUT
    if (\$LASTEXITCODE -ne 0) { exit \$LASTEXITCODE }
  } finally {
    $OVERRIDE_DEL
  }
"

# -- 5. home ------------------------------------------------------------------
if [ -n "$LIST" ]; then
  mkdir -p "$OUT"
  scp -q "$PC:$PC_SHOTS/*.png" "$OUT/"
  say "$(ls "$OUT"/*.png | wc -l | tr -d ' ') shots -> $OUT"
else
  mkdir -p "$(dirname "$OUT")"
  scp -q "$PC:$PC_PNG" "$OUT"
  say "$(ls -l "$OUT" | awk '{print $5, $NF}')"
fi
