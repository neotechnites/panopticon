#!/usr/bin/env bash
# Bake a scene's LightmapGI on the PC's GPU and bring the bake data to this checkout.
#
#   tools/pc_bake_lightmap.sh <git-ref> <res://scene.tscn>
#
# Godot bakes lightmaps only in the editor, on a RenderingDevice, so this opens the
# editor (Forward+) in the PC's console session in its own throwaway clone, with
# addons/lightmap_bake enabled there to press the button, and res://.lightmap_bake
# present so tools/import/lightmap_split.gd gives the lava a lit emissive stand-in.
# The scene is never saved: only <scene>.lmbake, its .exr and .exr.import come home.
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: tools/pc_bake_lightmap.sh <git-ref> <res://scene.tscn>" >&2; exit 2; }
REF="$1"; SCENE="$2"
case "$SCENE" in res://*.tscn) ;; *) echo "pc_bake_lightmap: <scene> must be a res://...tscn" >&2; exit 2 ;; esac

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
git rev-parse --verify --quiet "$REF^{commit}" >/dev/null || { echo "pc_bake_lightmap: no such ref: $REF" >&2; exit 2; }

PC=${PC_HOST:-panopticon-pc}
GODOT=${PC_GODOT:-'C:\tools\godot\godot.exe'}
CLONE='C:/Users/ddd/panopticon-lmbake'
CLONE_W='C:\Users\ddd\panopticon-lmbake'
WORK='C:/Users/ddd/panopticon-lmbake-work'
WORK_W='C:\Users\ddd\panopticon-lmbake-work'
TIMEOUT=${PC_BAKE_TIMEOUT:-3600}
REL="${SCENE#res://}"; BASE="${REL%.tscn}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
say() { printf '\033[1m==> %s\033[0m\n' "$*"; }

say "clone $CLONE"
ssh -o ConnectTimeout=20 "$PC" "
  \$ErrorActionPreference = 'Stop'
  if (-not (Test-Path '$CLONE_W\\.git')) { git clone --quiet C:/dev/panopticon '$CLONE'; Write-Output 'cloned' } else { Write-Output 'present' }
  New-Item -ItemType Directory -Force -Path '$WORK_W' | Out-Null
"

say "push $REF -> incoming"
git push "$PC:$CLONE" "$REF:refs/heads/incoming" -f 2>&1 | tail -2
ssh -o ConnectTimeout=20 "$PC" "
  \$ErrorActionPreference = 'Stop'
  git -C '$CLONE' checkout -q -f -B bake incoming
  git -C '$CLONE' reset -q --hard incoming
  Remove-Item '$CLONE_W\\lmbake.result' -ErrorAction SilentlyContinue
  Set-Content -Path '$CLONE_W\\.lightmap_bake' -Value 'bake'
  \$p = '$CLONE_W\\project.godot'
  \$t = Get-Content \$p -Raw
  \$t = \$t -replace 'enabled=PackedStringArray\\(', 'enabled=PackedStringArray(\"res://addons/lightmap_bake/plugin.cfg\", '
  [IO.File]::WriteAllText(\$p, \$t)
  Write-Output ('bake at ' + (git -C '$CLONE' log --oneline -1))
  cmd /c \"$GODOT --headless --import --path $CLONE_W > $WORK_W\\import.txt 2>&1\"
  Write-Output ('import errors: ' + (Select-String -Path $WORK_W\\import.txt -Pattern 'ERROR' | Measure-Object -Line).Lines)
"

cat > "$TMP/bake.bat" <<EOF
@echo off
set W=$WORK_W
del /q "%W%\\bake.done" 2>nul
cd /d "%W%"
"$GODOT" --editor --rendering-method forward_plus --path $CLONE_W -- --lmbake=$SCENE > "%W%\\bake.log" 2>&1
findstr /c:"LMBAKE ok" "%W%\\bake.log" >nul
echo %ERRORLEVEL% > "%W%\\bake.done"
EOF
scp -q "$TMP/bake.bat" "$PC:$WORK/bake.bat"
scp -q "$HERE/tools/modelling/lib/pcrun.ps1" "$PC:$WORK/pcrun.ps1"

say "bake $SCENE"
ssh -o ConnectTimeout=20 "$PC" "powershell -NoProfile -ExecutionPolicy Bypass -File '$WORK_W\\pcrun.ps1' -Bat '$WORK_W\\bake.bat' -TaskName PanopticonLmBake -TimeoutSec $TIMEOUT" || true
scp -q "$PC:$WORK/bake.log" "$TMP/bake.log" || true
grep -E "LMBAKE|Done baking|ERROR" "$TMP/bake.log" | head -20 || true
grep -q "LMBAKE ok" "$TMP/bake.log" || { echo "pc_bake_lightmap: bake failed" >&2; exit 1; }

say "home"
for f in $(ssh "$PC" "Get-ChildItem '$CLONE_W\\$(dirname "$REL" | tr / '\\')' -Name | Where-Object { \$_ -like '$(basename "$BASE")*.lmbake' -or \$_ -like '$(basename "$BASE")*.exr' -or \$_ -like '$(basename "$BASE")*.exr.import' }" | tr -d '\r'); do
  scp -q "$PC:$CLONE/$(dirname "$REL")/$f" "$HERE/$(dirname "$REL")/$f"
  ls -l "$HERE/$(dirname "$REL")/$f" | awk '{print $5, $NF}'
done
