"""PC leases, one per capture: C:\\dev\\locks\\<slot>\\owner.json {owner, pid, host, token, expires}.

`screen` covers one real-time take, `heavy` one render batch. A lease past its expiry is broken by
the next taker, so a dead agent cannot wedge the PC. Also the ssh helper the PC tools share.
"""
from __future__ import annotations

import base64
import contextlib
import json
import os
import socket
import subprocess
import time
import uuid

PC_HOST = os.environ.get("CP_PC_HOST", "panopticon-pc")
LOCK_ROOT = r"C:\dev\locks"
LEGACY_LOCK = r"C:\dev\content.lock"   # the old whole-short lock; honoured while it exists
SLOTS = ("screen", "heavy")


class PcError(RuntimeError):
    pass


def pc(script: str, timeout: float = 900, check: bool = True) -> str:
    """Run a PowerShell script on the PC over ssh and return its stdout."""
    encoded = base64.b64encode(script.encode("utf-16-le")).decode()
    proc = subprocess.run(
        ["ssh", "-o", "ConnectTimeout=20", PC_HOST,
         f"powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand {encoded}"],
        capture_output=True, text=True, timeout=timeout)
    err = "\n".join(l for l in proc.stderr.splitlines() if not l.startswith(("#< CLIXML", "<Objs")))
    if check and proc.returncode != 0:
        raise PcError(f"pc: exit {proc.returncode}: {err.strip()[-800:]}")
    return proc.stdout


def pc_push(local: str, remote: str) -> None:
    subprocess.run(["scp", "-q", local, f"{PC_HOST}:{remote.replace(chr(92), '/')}"], check=True)


def pc_pull(remote: str, local: str) -> None:
    subprocess.run(["scp", "-q", f"{PC_HOST}:{remote.replace(chr(92), '/')}", local], check=True)


def _ps_str(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def try_acquire(slot: str, owner: str, seconds: float) -> str | None:
    """One attempt. Returns the lease token, or None while someone else holds it."""
    if slot not in SLOTS:
        raise ValueError(f"pclock: unknown slot {slot}")
    token = uuid.uuid4().hex
    lease = {"owner": owner, "pid": os.getpid(), "host": socket.gethostname(), "token": token,
             "expires": time.time() + 3 * seconds}
    d = f"{LOCK_ROOT}\\{slot}"
    out = pc(f"""
$ErrorActionPreference = 'Stop'
$d = {_ps_str(d)}
New-Item -ItemType Directory -Force -Path {_ps_str(LOCK_ROOT)} | Out-Null
if ((Test-Path {_ps_str(LEGACY_LOCK)}) -and ({_ps_str(slot)} -eq 'screen')) {{
  Write-Output ('HELD legacy content.lock: ' + (Get-Content {_ps_str(LEGACY_LOCK + chr(92) + 'owner.txt')} -EA SilentlyContinue)); exit 0 }}
if (Test-Path $d) {{
  $o = Get-Content "$d\\owner.json" -Raw -EA SilentlyContinue | ConvertFrom-Json -EA SilentlyContinue
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  if ($o -and $o.expires -gt $now) {{ Write-Output ('HELD ' + $o.owner); exit 0 }}
  if (-not $o -and ((Get-Item $d).LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddMinutes(-2))) {{ Write-Output 'HELD (being written)'; exit 0 }}
  Remove-Item -Recurse -Force $d
  Write-Output ('BROKE expired lease of ' + $(if ($o) {{ $o.owner }} else {{ '?' }}))
}}
try {{ New-Item -ItemType Directory -Path $d | Out-Null }} catch {{ Write-Output 'HELD (race)'; exit 0 }}
Set-Content -Path "$d\\owner.json" -Value {_ps_str(json.dumps(lease))}
Write-Output 'GOT'
""", timeout=60)
    if "GOT" in out.split():
        return token
    return None


def acquire(slot: str, owner: str, seconds: float, wait: float = 3600, poll: float = 15) -> str:
    """Block until the lease is ours (poll every `poll` s), up to `wait` s."""
    deadline = time.time() + wait
    while True:
        token = try_acquire(slot, owner, seconds)
        if token:
            return token
        if time.time() > deadline:
            raise PcError(f"pclock: {slot} still held after {wait:.0f} s")
        time.sleep(poll)


def release(slot: str, token: str) -> None:
    d = f"{LOCK_ROOT}\\{slot}"
    pc(f"""
$d = {_ps_str(d)}
$o = Get-Content "$d\\owner.json" -Raw -EA SilentlyContinue | ConvertFrom-Json -EA SilentlyContinue
if ($o -and $o.token -eq {_ps_str(token)}) {{ Remove-Item -Recurse -Force $d }}
""", timeout=60, check=False)


@contextlib.contextmanager
def lease(slot: str, owner: str, seconds: float, wait: float = 3600):
    token = acquire(slot, owner, seconds, wait)
    try:
        yield token
    finally:
        release(slot, token)


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="PC lease: content lock screen|heavy")
    ap.add_argument("slot", choices=SLOTS)
    ap.add_argument("action", choices=["take", "free", "show"])
    ap.add_argument("--owner", default="manual")
    ap.add_argument("--seconds", type=float, default=120)
    ap.add_argument("--token", default="")
    a = ap.parse_args()
    if a.action == "take":
        print(acquire(a.slot, a.owner, a.seconds))
    elif a.action == "free":
        release(a.slot, a.token)
    else:
        print(pc(f"Get-Content '{LOCK_ROOT}\\{a.slot}\\owner.json' -EA SilentlyContinue"))
