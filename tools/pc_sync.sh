#!/usr/bin/env bash
# Push main to the PC play copy safely: never discards Ryan's uncommitted edits there.
set -e
cd "$(dirname "$0")/.."
git push -q pc main:refs/heads/incoming
ssh panopticon-pc '
  $m = git -C C:/dev/panopticon status --porcelain | Where-Object { $_ -notmatch "^\?\?" }
  if ($m) { Write-Output "REFUSED: PC has uncommitted tracked edits:"; $m; exit 2 }
  Remove-Item C:\dev\panopticon\assets\models\*_albedo.png*, C:\dev\panopticon\assets\models\*_emissive.png* -ErrorAction SilentlyContinue
  git -C C:/dev/panopticon clean -fq -- assets/models
  git -C C:/dev/panopticon merge --ff-only -q incoming
  Get-ChildItem C:\dev\panopticon\assets\models\*.glb.import | ForEach-Object {
    $t = Get-Content $_.FullName -Raw
    if ($t -match "gltf/embedded_image_handling=") { $t = $t -replace "gltf/embedded_image_handling=\d", "gltf/embedded_image_handling=3" }
    else { $t = $t -replace "\[params\]\r?\n", "[params]`r`ngltf/embedded_image_handling=3`r`n" }
    Set-Content -NoNewline $_.FullName $t
  }
  Remove-Item C:\dev\panopticon\assets\models\*_albedo.png*, C:\dev\panopticon\assets\models\*_emissive.png* -ErrorAction SilentlyContinue
  cmd /c "C:\tools\godot\godot.exe --headless --import --path C:\dev\panopticon > C:\dev\import.txt 2>&1"
  $e = (Select-String -Path C:\dev\import.txt -Pattern "ERROR" | Measure-Object -Line).Lines
  Write-Output ("PC at " + (git -C C:/dev/panopticon log --oneline -1) + " | import errors: " + $e)
'
