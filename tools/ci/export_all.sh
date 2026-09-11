#!/usr/bin/env bash
# Export Windows (over ssh to panopticon-pc) and macOS (locally) release builds.
# Prints both zip paths and sizes. build/ is gitignored -- nothing here commits.
set -euo pipefail
cd "$(dirname "$0")/../.."

WIN_HOST=panopticon-pc
WIN_WORKTREE='C:\dev\verify'
WIN_OUT='C:\dev\build\panopticon-win'
WIN_GODOT='C:\tools\godot\godot.exe'

echo "== Windows (via $WIN_HOST) =="
ssh "$WIN_HOST" 'git -C C:\dev\verify reset --hard main' >/dev/null
scp -q tools/ci/export_presets.windows.cfg "$WIN_HOST:C:\dev\verify\export_presets.cfg"
ssh "$WIN_HOST" '
New-Item -ItemType Directory -Force -Path C:\dev\build\panopticon-win | Out-Null
cd C:\dev\verify
& C:\tools\godot\godot.exe --headless --path . --import | Out-Null
& C:\tools\godot\godot.exe --headless --path . --export-release "Windows Desktop" C:\dev\build\panopticon-win\panopticon.exe
if (-not (Test-Path C:\dev\build\panopticon-win\panopticon.exe) -or -not (Test-Path C:\dev\build\panopticon-win\panopticon.pck)) {
    Write-Error "Windows export: exe or pck missing"; exit 1
}
Compress-Archive -Path C:\dev\build\panopticon-win -DestinationPath C:\dev\build\panopticon-win.zip -Force
'
WIN_ZIP_SIZE=$(ssh "$WIN_HOST" '(Get-Item C:\dev\build\panopticon-win.zip).Length')

echo "== macOS (local) =="
cp tools/ci/export_presets.macos.cfg export_presets.cfg
godot --headless --path . --import >/dev/null
mkdir -p build/panopticon-mac
godot --headless --path . --export-release "macOS" build/panopticon-mac/Panopticon.app
rm -f export_presets.cfg
test -d build/panopticon-mac/Panopticon.app
rm -f build/panopticon-mac.zip
ditto -c -k --sequesterRsrc --keepParent build/panopticon-mac/Panopticon.app build/panopticon-mac.zip
MAC_ZIP_SIZE=$(stat -f%z build/panopticon-mac.zip)

echo
echo "Windows: $WIN_OUT.zip (${WIN_ZIP_SIZE} bytes) on $WIN_HOST"
echo "macOS:   $(pwd)/build/panopticon-mac.zip (${MAC_ZIP_SIZE} bytes)"
