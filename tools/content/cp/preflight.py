"""G0 preflight: the Andrew voice works, the PC answers, ffmpeg can capture, locks are writable, review tools exist.
Capture-only checks (virtual monitor, ddagrab, utvideo) run only when the plan films something."""
import argparse
import base64
import os
import shutil
import subprocess
import sys

PC = os.environ.get("CONTENT_PC", "panopticon-pc")
LOCKS = r"C:\dev\locks"
VOICE = "en-US-AndrewNeural"
RATE = "+5%"
# Same synth as cp/voice.py --check, run on the PC's patched edge-tts when cp.voice is not importable.
_VOICE_PY = r'''
import asyncio, edge_tts, io, sys
async def go():
    c = edge_tts.Communicate("Panopticon voice check.", "%s", rate="%s", boundary="WordBoundary")
    audio, words = b"", 0
    async for ch in c.stream():
        if ch["type"] == "audio": audio += ch["data"]
        elif ch["type"] == "WordBoundary": words += 1
    print(len(audio), words)
try:
    asyncio.run(go())
except Exception as e:
    print("ERR", getattr(e, "status", ""), str(e)[:160]); sys.exit(1)
''' % (VOICE, RATE)


def ssh(cmd, timeout=40):
    """PowerShell on the PC; returns (rc, stdout+stderr)."""
    try:
        p = subprocess.run(["ssh", "-o", "ConnectTimeout=8", "-o", "BatchMode=yes", PC,
                            "powershell -NoProfile -ExecutionPolicy Bypass -Command -"],
                           input=cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, f"ssh {PC} timed out after {timeout}s"


def check_pc():
    rc, out = ssh("hostname")
    return rc == 0 and bool(out), f"PC {PC} answers ({out})" if rc == 0 else f"PC {PC} unreachable: {out[:120]}"


def check_voice():
    try:
        from . import voice  # WP3: pinned Andrew + endpoint check, raises/returns False on failure
        fn = getattr(voice, "check", None) or getattr(voice, "preflight", None)
        if fn is not None:
            r = fn()
            ok = r if isinstance(r, bool) else bool(r and r[0])
            return ok, f"voice: cp.voice check {'ok' if ok else 'FAILED'}" + ("" if isinstance(r, bool) else f" ({r[1]})")
    except ImportError:
        pass
    b64 = base64.b64encode(_VOICE_PY.encode()).decode()
    rc, out = ssh(f'$p = Join-Path $env:TEMP "cp_voicecheck.py"; '
                  f'[IO.File]::WriteAllBytes($p, [Convert]::FromBase64String("{b64}")); python $p')
    parts = out.split()
    if rc != 0 or len(parts) < 2 or parts[0] == "ERR" or not parts[0].isdigit():
        return False, f"VOICE FAILED: {out[-160:]}"
    size, words = int(parts[0]), int(parts[1])
    secs = size * 8 / 48000  # edge-tts default: 24 kHz 48 kbit/s mp3
    ok = 0.8 <= secs <= 3.0 and words >= 2
    return ok, f"voice {VOICE} {RATE}: {secs:.2f}s, {words} word boundaries" + ("" if ok else " (VOICE FAILED)")


def check_locks():
    rc, out = ssh(f'New-Item -ItemType Directory -Force {LOCKS} | Out-Null; '
                  f'Set-Content {LOCKS}\\.probe x; Remove-Item {LOCKS}\\.probe; "ok"')
    return rc == 0 and out.endswith("ok"), f"lock dir {LOCKS} writable" if rc == 0 else f"lock dir: {out[:120]}"


def check_ffmpeg_capture():
    rc, out = ssh('$f = ffmpeg -hide_banner -filters 2>&1 | Select-String ddagrab; '
                  '$e = ffmpeg -hide_banner -encoders 2>&1 | Select-String utvideo; "$([bool]$f) $([bool]$e)"')
    ok = out.strip().endswith("True True")
    return ok, "PC ffmpeg has ddagrab and utvideo" if ok else f"PC ffmpeg lacks ddagrab/utvideo ({out[-60:]})"


def check_monitor():
    rc, out = ssh("Get-PnpDevice -Class Display,Monitor -Status OK | ForEach-Object FriendlyName")
    names = [n for n in out.splitlines() if n.strip()]
    virt = [n for n in names if any(k in n.lower() for k in ("virtual", "idd", "parsec", "usbmmidd", "mtt"))]
    return bool(virt), f"virtual monitor: {virt[0]}" if virt else f"no virtual capture monitor (devices: {', '.join(names)[:120]})"


def check_review_tools():
    miss = []
    try:
        import google.genai  # noqa: F401
    except ImportError:
        miss.append("google-genai")
    if not os.environ.get("GEMINI_API_KEY"):
        miss.append("GEMINI_API_KEY")
    for b in ("ffmpeg", "ffprobe", "tesseract"):
        if not shutil.which(b):
            miss.append(b)
    return not miss, "Mac review tools present" if not miss else f"Mac missing: {', '.join(miss)}"


BASE = [("pc", check_pc), ("voice", check_voice), ("locks", check_locks), ("review", check_review_tools)]
CAPTURE = [("ffmpeg", check_ffmpeg_capture), ("monitor", check_monitor)]


def run(capture=False, voice=True, log=print):
    """Returns (pass, reason, {check: [pass, reason]})."""
    checks = [c for c in BASE if voice or c[0] != "voice"] + (CAPTURE if capture else [])
    res = {}
    for name, fn in checks:
        try:
            res[name] = list(fn())
        except Exception as e:
            res[name] = [False, f"{name}: {e}"]
        log(("ok   " if res[name][0] else "FAIL ") + res[name][1])
    bad = [r[1] for r in res.values() if not r[0]]
    return not bad, ("; ".join(bad) if bad else f"{len(res)} checks ok"), res


def main(argv=None):
    ap = argparse.ArgumentParser(prog="content preflight")
    ap.add_argument("--capture", action="store_true", help="also check the capture backend")
    a = ap.parse_args(argv)
    ok, why, _ = run(capture=a.capture)
    print(("G0 PASS: " if ok else "G0 FAIL: ") + why)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
