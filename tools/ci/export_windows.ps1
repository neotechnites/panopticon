# Windows export, run on the PC by tools/build.sh inside C:\dev\verify.
# Prints WIN_ZIP=, WIN_ZIP_BYTES=, WIN_EXE_BYTES=, WIN_PCK_BYTES=, WIN_SMOKE= lines for the Mac side to parse.
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$Godot = 'C:\tools\godot\godot.exe',
    [string]$Worktree = 'C:\dev\verify',
    [string]$OutRoot = "$env:USERPROFILE\Desktop\panopticon-builds"
)
$ErrorActionPreference = 'Stop'
$out = Join-Path (Join-Path $OutRoot $Version) 'panopticon-win'
$zip = Join-Path (Join-Path $OutRoot $Version) 'panopticon-win.zip'
$exe = Join-Path $out 'panopticon.exe'
$pck = Join-Path $out 'panopticon.pck'
$log = Join-Path (Join-Path $OutRoot $Version) 'win-export.log'

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force -Path $out | Out-Null
Remove-Item -Force $zip -ErrorAction SilentlyContinue

Set-Location $Worktree
cmd /c "`"$Godot`" --headless --path . --import > `"$log`" 2>&1"
cmd /c "`"$Godot`" --headless --path . --export-release `"Windows Desktop`" `"$exe`" >> `"$log`" 2>&1"
if (-not ((Test-Path $exe) -and (Test-Path $pck) -and (Get-Item $exe).Length -gt 0 -and (Get-Item $pck).Length -gt 0)) {
    Get-Content $log | Select-Object -Last 30
    Write-Error "Windows export: exe or pck missing/empty in $out"
    exit 1
}

# Smoke: the exported exe boots headless and loads the main scene.
$smoke = Join-Path (Join-Path $OutRoot $Version) 'win-smoke.log'
cmd /c "`"$exe`" --headless --verbose --quit-after 60 > `"$smoke`" 2>&1"
$code = $LASTEXITCODE
$loaded = Select-String -Path $smoke -Pattern "Completed load for: 'res://scenes/ui/main_menu.tscn'" -Quiet
$ok = ($code -eq 0) -and $loaded

Compress-Archive -Path $out -DestinationPath $zip -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$entries = [IO.Compression.ZipFile]::OpenRead($zip).Entries | Select-Object -ExpandProperty FullName
if (-not ($entries -contains 'panopticon-win\panopticon.exe') -or -not ($entries -contains 'panopticon-win\panopticon.pck')) {
    Write-Error "Windows zip is missing the exe or pck: $($entries -join ', ')"
    exit 1
}

Write-Output "WIN_ZIP=$zip"
Write-Output "WIN_ZIP_BYTES=$((Get-Item $zip).Length)"
Write-Output "WIN_EXE_BYTES=$((Get-Item $exe).Length)"
Write-Output "WIN_PCK_BYTES=$((Get-Item $pck).Length)"
Write-Output ("WIN_SMOKE=" + $(if ($ok) { 'ok' } else { "FAIL(exit=$code loaded=$loaded)" }))
if (-not $ok) { exit 1 }
