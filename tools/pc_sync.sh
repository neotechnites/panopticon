#!/usr/bin/env bash
# Push main to the PC play copy safely: never discards Ryan's uncommitted edits there.
set -e
cd "$(dirname "$0")/.."
git push -q pc main:refs/heads/incoming
ssh panopticon-pc '
  $m = git -C C:/dev/panopticon status --porcelain | Where-Object { $_ -notmatch "^\?\?" }
  if ($m) { Write-Output "REFUSED: PC has uncommitted tracked edits:"; $m; exit 2 }
  Get-ChildItem C:\dev\panopticon -Recurse -Include *_albedo.png*, *_emissive.png* | Where-Object { $_.Directory.Name -eq "models" } | Remove-Item -ErrorAction SilentlyContinue
  git -C C:/dev/panopticon clean -fq -- ':(glob)**/models/**'
  $incomingFiles = git -C C:/dev/panopticon ls-tree -r --name-only incoming
  $untrackedFiles = git -C C:/dev/panopticon ls-files --others --exclude-standard
  foreach ($f in $untrackedFiles) {
    if ($incomingFiles -contains $f) {
      Remove-Item (Join-Path C:\dev\panopticon $f) -Force -ErrorAction SilentlyContinue
    }
  }
  git -C C:/dev/panopticon merge --ff-only -q incoming
  if ($LASTEXITCODE -ne 0) { Write-Output "SYNC FAILED"; exit 3 }
  $hook = "res://tools/import/mipmap_textures.gd"
  Get-ChildItem C:\dev\panopticon -Recurse -Filter *.glb.import | ForEach-Object {
    $t = Get-Content $_.FullName -Raw
    if ($t -match "gltf/embedded_image_handling=") { $t = $t -replace "gltf/embedded_image_handling=\d", "gltf/embedded_image_handling=3" }
    else { $t = $t -replace "\[params\]\r?\n", "[params]`r`ngltf/embedded_image_handling=3`r`n" }
    if ($t -match "import_script/path=(.*)") {
      $cur = $Matches[1].Trim().Trim([char]34)
      if ($cur -eq "" -or $cur -eq $hook) { $t = $t -replace "import_script/path=[^\r\n]*", ("import_script/path=" + [char]34 + $hook + [char]34) }
      else { Write-Output ("WARNING: " + $_.Name + " keeps its own import_script " + $cur) }
    }
    else { $t = $t -replace "\[params\]\r?\n", ("[params]`r`nimport_script/path=" + [char]34 + $hook + [char]34 + "`r`n") }
    [IO.File]::WriteAllText($_.FullName, $t)
  }
  Get-ChildItem C:\dev\panopticon -Recurse -Include *_albedo.png*, *_emissive.png* | Where-Object { $_.Directory.Name -eq "models" } | Remove-Item -ErrorAction SilentlyContinue
  Remove-Item C:\dev\panopticon\.godot\uid_cache.bin -ErrorAction SilentlyContinue
  cmd /c "C:\tools\godot\godot.exe --headless --import --path C:\dev\panopticon > C:\dev\import.txt 2>&1"
  $e = (Select-String -Path C:\dev\import.txt -Pattern "ERROR" | Measure-Object -Line).Lines
  Write-Output ("PC at " + (git -C C:/dev/panopticon log --oneline -1) + " | import errors: " + $e)
'

git push -q origin main 2>&1 | tail -1
