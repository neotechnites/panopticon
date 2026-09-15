#!/usr/bin/env bash
# Serve a project's folder from the PC to this Mac's browser, over the tunnel.
#
#   tools/content/serve.sh <project>          # then open the URL it prints
#   tools/content/serve.sh <project> --stop   # stop the server and the tunnel
#
# On the PC, Python's http.server on 127.0.0.1:8765 serving content\<project>\,
# started through WMI (Win32_Process.Create) so it outlives the ssh session --
# Start-Process from an ssh session dies with it -- with stdout and stderr
# redirected to notes\serve.log, because a console-less python that writes a
# request line to a closed stdout crashes on the first click. If a server for
# another project holds the port, it is stopped first. On the Mac, a
# background ssh tunnel 8765 -> the PC's loopback (reused if one is up), then
# a curl check. Loopback only on both ends: nothing is exposed past Tailscale.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/serve.sh <project> [--stop]}"
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
DIR=$(project_dir "${NAME}")
PORT="${PC_SERVE_PORT}"

tunnel_pids() { pgrep -f "ssh.*-L ${PORT}:127.0.0.1:${PORT}" || true; }

if [ "${2:-}" = "--stop" ]; then
  pc <<PS
\$srv = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" | Where-Object { \$_.CommandLine -match 'http\\.server ${PORT}' }
foreach (\$p in \$srv) {
  Stop-Process -Id \$p.ProcessId -Force -ErrorAction SilentlyContinue
  Stop-Process -Id \$p.ParentProcessId -Force -ErrorAction SilentlyContinue
  Write-Output ('stopped server ' + \$p.ProcessId)
}
if (-not \$srv) { Write-Output 'no server on ${PORT}' }
PS
  for pid in $(tunnel_pids); do kill "${pid}" && echo "tunnel ${pid} closed"; done
  exit 0
fi

pc <<PS
\$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path '${DIR}\\notes' | Out-Null
\$srv = Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" | Where-Object { \$_.CommandLine -match 'http\\.server ${PORT}' }
\$keep = \$false
foreach (\$p in \$srv) {
  if (\$p.CommandLine -match [regex]::Escape('${DIR}')) { \$keep = \$true; Write-Output ('server already up for ${NAME}: pid ' + \$p.ProcessId) }
  else {
    Stop-Process -Id \$p.ProcessId -Force -ErrorAction SilentlyContinue
    Stop-Process -Id \$p.ParentProcessId -Force -ErrorAction SilentlyContinue
    Write-Output ('stopped the server for another project: pid ' + \$p.ProcessId)
    Start-Sleep -Milliseconds 500
  }
}
if (-not \$keep) {
  \$cmd = 'cmd.exe /c "${PC_PYTHON} -u -m http.server ${PORT} --bind 127.0.0.1 --directory ${DIR} > ${DIR}\\notes\\serve.log 2>&1"'
  \$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = \$cmd }
  Write-Output ('server started for ${NAME}: return ' + \$r.ReturnValue + ', pid ' + \$r.ProcessId)
  Start-Sleep -Seconds 2
}
\$code = cmd /c "curl.exe -s -m 5 -o NUL -w %{http_code} http://127.0.0.1:${PORT}/"
Write-Output ('PC loopback check: HTTP ' + \$code)
PS

if [ -z "$(tunnel_pids)" ]; then
  ssh -i "${PC_KEY}" -o ConnectTimeout=20 -o ExitOnForwardFailure=yes -f -N -L "${PORT}:127.0.0.1:${PORT}" "${PC_HOST}"
  echo "tunnel opened: 127.0.0.1:${PORT} -> PC"
else
  echo "tunnel already up (pid $(tunnel_pids | head -1))"
fi
sleep 1
CODE=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/final/index.html" || true)
echo "http://127.0.0.1:${PORT}/final/index.html  (HTTP ${CODE}; 404 means no dailies page yet: tools/content/dailies.sh ${NAME})"
