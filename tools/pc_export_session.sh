#!/usr/bin/env bash
# One multi-peer session of an exported Windows build on the PC, driven by tools/export_check.
#
#   tools/pc_export_session.sh <name> <headless|windowed> <timeout s> <host args> [-- <client args>]...
#
# Each group is the driver's own --key=value list (see session_driver.gd); --role, --port and --name
# are filled in. EXE= picks the build, PC_ROOT= the PC folder, PORT= the port. Logs come back to OUT=.
# KEEP=1 keeps the session folder, so each peer starts with the user data (shader cache) of the last run.
set -euo pipefail
[ $# -ge 4 ] || { sed -n 2,8p "$0" >&2; exit 2; }
NAME="$1"; MODE="$2"; TIMEOUT="$3"; shift 3
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PC=${PC_HOST:-panopticon-pc}
PC_ROOT="${PC_ROOT:-C:\\dev\\worktrees\\winbuild}"
EXE="${EXE:?EXE= the exported panopticon.exe on the PC}"
PORT="${PORT:-27990}"
OUT="${OUT:-$HERE/build/sessions/$NAME}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP/config.json" "$EXE" "$PC_ROOT" "$NAME" "$MODE" "$TIMEOUT" "$PORT" "$@" <<'PY'
import json, sys
path, exe, root, name, mode, timeout, port, *rest = sys.argv[1:]
groups, cur = [], []
for a in rest:
    if a == "--":
        groups.append(cur); cur = []
    else:
        cur.append(a)
groups.append(cur)
peers = []
for i, g in enumerate(groups):
    who = "host" if i == 0 else "c%d" % i
    role = "server" if i == 0 else "client"
    named = [] if any(x.startswith("--name=") for x in g) else ["--name=" + ("Host" if i == 0 else "C%d" % i)]
    peers.append({"name": who, "args": ["--role=" + role, "--port=" + port] + named + g})
build = exe.replace("/", "\\").split("\\")[-3]
json.dump({"exe": exe, "harness": root + "\\_harness\\" + build, "driver": root + "\\drv\\session_driver.gd", "out": root + "\\_logs\\" + name,
           "headless": mode == "headless", "timeout": int(timeout), "stagger": 1500, "peers": peers}, open(path, "w"))
PY

SESSION="$PC_ROOT\\_logs\\$NAME"
ssh -o ConnectTimeout=20 "$PC" "New-Item -ItemType Directory -Force -Path '$PC_ROOT\\drv','$SESSION' | Out-Null; if (-not '${KEEP:-}') { Remove-Item -Recurse -Force '$SESSION\\*' -ErrorAction SilentlyContinue }; Remove-Item -Force '$SESSION\\done','$SESSION\\result.txt' -ErrorAction SilentlyContinue; exit 0"
scp -q "$HERE/tools/export_check/session_driver.gd" "$HERE/tools/export_check/run_session.ps1" "$PC:$PC_ROOT\\drv\\"
scp -q "$TMP/config.json" "$PC:$SESSION\\config.json"
RUN="powershell -NoProfile -ExecutionPolicy Bypass -File $PC_ROOT\\drv\\run_session.ps1 -Config $SESSION\\config.json"
if [ "$MODE" = headless ]; then
  ssh "$PC" "$RUN" | tr -d '\r'
else
  # A window needs the logged-on console session; an SSH session has no desktop and no GPU.
  # Registered at priority 4: a default task runs below normal with low I/O priority, which no player's launch does.
  TASK="PanopticonExport_$NAME"
  ssh "$PC" "
    \$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $PC_ROOT\\drv\\run_session.ps1 -Config $SESSION\\config.json'
    \$p = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -LogonType Interactive
    \$s = New-ScheduledTaskSettingsSet -Priority 4 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TASK -Action \$a -Principal \$p -Settings \$s -Force | Out-Null
    Start-ScheduledTask -TaskName $TASK
    \$deadline = (Get-Date).AddSeconds($TIMEOUT + 90)
    while (-not (Test-Path '$SESSION\\done') -and (Get-Date) -lt \$deadline) { Start-Sleep -Seconds 1 }
    Unregister-ScheduledTask -TaskName $TASK -Confirm:\$false
    if (Test-Path '$SESSION\\result.txt') { Get-Content '$SESSION\\result.txt' } else { Write-Output 'NO RESULT' }
  " | tr -d '\r'
fi
mkdir -p "$OUT"
FWD="$(printf '%s' "$SESSION" | tr '\\' '/')"
scp -q "$PC:$FWD/*.log" "$PC:$FWD/*.err" "$PC:$FWD/result.txt" "$OUT/"
