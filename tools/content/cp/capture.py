"""content capture: a plan.json game row -> takes/<line>/take.avi (utvideo, native size) + take.json, gated G3-G6.

rough: the PC's main screen, real time (portrait tops out at 810x1440 there).
final: the capture-only virtual monitor at the output size (cp/pc/install_virtual_monitor.ps1).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

try:
    from . import pclock
    from .pclock import PcError, pc, pc_pull, pc_push
except ImportError:  # run as a script
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from cp import pclock  # type: ignore
    from cp.pclock import PcError, pc, pc_pull, pc_push  # type: ignore

VERSION = "1"
HERE = Path(__file__).resolve().parent
PC_GODOT = r"C:\tools\godot\godot.exe"
PC_VERIFY = r"C:\dev\verify"
PC_WORKTREES = r"C:\dev\worktrees"
PC_CONTENT = r"C:\Users\ddd\Desktop\panopticon-renders\content"
PC_TOOLS = r"C:\dev\cp"
FPS = 60
SYNC_FRAMES = 90
TAIL_FRAMES = 30
OUTPUT = {"short": (1080, 1920), "devlog": (1920, 1080), "trailer": (1920, 1080)}
SCREEN = (2560, 1440)          # the PC's main screen: what rough mode can hold
POV_ARG = {"prisoner": "runner", "guard": "guard", "ghost": "ghost"}
DEFAULT_SHOT = "s3_open_lane"  # run_clip needs a path even when a body is ridden
SETTLE_S = 1.5                 # a stage places its bodies in the first second; the used window starts after
# Gate numbers (shot.sh's take gate, design section d).
MOTION_MIN = 0.02
BYTES_PER_S_MIN = 1_000_000
MAGENTA_MAX = 0.005
FULL_WHITE_YMIN = 230.0
LUMA_TOLERANCE = 0.15
LENGTH_SLACK_S = 0.5
DROP_MAX = 0.01       # G4b: repeated frames in the used window, and game time lost against wall time, as a share
CLIP_MIN_S = 0.1      # a lens event shorter than this (gaps under it merged) is a graze, not a shot in the rock
EVENT_ALIAS = {"out": "death"}


def take_size(kind: str, mode: str) -> tuple[int, int, str]:
    """The take's frame. Never larger than the screen it is grabbed from; never scaled up later here."""
    w, h = OUTPUT.get(kind, OUTPUT["short"])
    if mode == "final" or (w <= SCREEN[0] and h <= SCREEN[1]):
        return w, h, ""
    s = SCREEN[1] / h
    rw, rh = int(round(w * s / 2) * 2), SCREEN[1]
    return rw, rh, f"rough: {w}x{h} does not fit the {SCREEN[0]}x{SCREEN[1]} screen; filmed {rw}x{rh} (final mode films {w}x{h})"


def window(row: dict) -> tuple[float, float]:
    """The part of the take the cut uses: [in, in + len] in take seconds."""
    g = row.get("game") or {}
    t_in = float(g.get("in", SETTLE_S))
    length = g.get("seconds")
    if length is None:
        ms = row.get("min_seconds")
        length = ms if isinstance(ms, (int, float)) else 6.0
    return t_in, float(length)


def run_clip_args(row: dict) -> list[str]:
    g = row["game"]
    args = [f"--shot={g.get('shot') or DEFAULT_SHOT}"]
    if g.get("map"):
        args.append(f"--map={g['map']}")
    pov = POV_ARG.get(g.get("pov", ""), g.get("pov_arg", ""))
    if pov:
        args.append(f"--pov={pov}")
    if g.get("stage") and g["stage"] not in ("none", "free"):
        args.append(f"--stage={g['stage']}")
    if g.get("set"):
        args.append(f"--set={g['set']}")
    if g.get("bots") is not None:
        args.append(f"--bots={int(g['bots'])}")
    if g.get("seed") is not None:
        args.append(f"--seed={int(g['seed'])}")
    if g.get("hud") and g["hud"] not in ("off", "none"):
        args.append(f"--hud={g['hud']}")
    if g.get("tape"):
        tape = g["tape"]
        args.append(f"--tape={tape if tape.startswith('res://') else 'res://' + tape.lstrip('/')}")
    if any(a.startswith(("--write-movie", "--final")) for a in g.get("args", [])):
        raise SystemExit(f"capture {row['id']}: offline capture (--write-movie/--final) is refused: takes are real time (decision 195)")
    args += [a for a in g.get("args", []) if not a.startswith(("--seconds", "--sync", "--tail-marker", "--deny-look"))]
    if any(a.startswith("--look") for a in args) and not g.get("look_override"):
        raise SystemExit(f"capture {row['id']}: --look in the row without look_override: yes")
    if not g.get("look_override"):
        args.append("--deny-look")
    return args


def pc_project(ref: str) -> str:
    """The PC checkout a take is filmed in: a detached worktree per resolved commit (origin/<ref> first), never a
    checkout another job owns. It gets this checkout's tools/capture, so any ref's takes carry markers, [light], [clip]."""
    ref = ref or "main"
    out = pc(f"""
$ErrorActionPreference = 'Continue'
git -C C:/dev/verify fetch -q origin 2>&1 | Out-Null
$sha = git -C C:/dev/verify rev-parse --verify -q 'origin/{ref}^{{commit}}'
if (-not $sha) {{ $sha = git -C C:/dev/verify rev-parse --verify -q '{ref}^{{commit}}' }}
if (-not $sha) {{ Write-Output 'NOREF'; exit 0 }}
$sha = $sha.Trim()
$p = '{PC_WORKTREES}\\cp_' + $sha.Substring(0, 10)
if (-not (Test-Path "$p\\project.godot")) {{
  git -C C:/dev/verify worktree add --detach $p $sha 2>&1 | Out-Null
  if (Test-Path C:\\dev\\verify\\.godot\\imported) {{ robocopy C:\\dev\\verify\\.godot\\imported "$p\\.godot\\imported" /E /NFL /NDL /NJH /NJS /NP | Out-Null }}
  cmd /c "{PC_GODOT} --headless --import --path $p > $p\\import.txt 2>&1"
  cmd /c "{PC_GODOT} --headless --import --path $p >> $p\\import.txt 2>&1"
}}
Write-Output $p
""", timeout=1800)
    p = out.strip().splitlines()[-1] if out.strip() else "NOREF"
    if p == "NOREF":
        raise SystemExit(f"capture: ref {ref!r} is not on the PC (push it to origin)")
    subprocess.run(["scp", "-rq", str(HERE.parent.parent / "capture"), f"{pclock.PC_HOST}:{(p + '/tools').replace(chr(92), '/')}"],
                   check=True)
    return p


LOG_RE = re.compile(r"^\[(event|light|clip|take)\]\s+(-?[0-9.]+)\s+(.*)$")


def parse_log(text: str) -> dict:
    events, light, clips, end, errors = [], [], [], None, []
    for line in text.splitlines():
        if ("SCRIPT ERROR" in line or line.startswith("--deny-look") or "would not load" in line
                or "Failed loading resource" in line or "Can't load dependency" in line):
            errors.append(line.strip())
        if line.startswith("[clip] probe:"):
            clips.append({"t": -1.0, "what": line[len("[clip] "):].strip()})
            continue
        m = LOG_RE.match(line.strip())
        if not m:
            continue
        tag, t, rest = m.group(1), float(m.group(2)), m.group(3).strip()
        if tag == "event":
            parts = rest.split()
            kind = parts[0] if parts else "?"
            events.append({"t": t, "kind": EVENT_ALIAS.get(kind, kind), "who": parts[1] if len(parts) > 1 else "",
                           "raw": rest})
        elif tag == "light":
            live, _, shipped = rest.partition("  shipped ")
            d = {"t": t}
            for k, v in re.findall(r"(\w+)=(\S+)", live):
                d[k] = v if k == "look" else float(v)
            d["shipped"] = {k: float(v) for k, v in re.findall(r"(\w+)=(\S+)", shipped)}
            light.append(d)
        elif tag == "clip":
            clips.append({"t": t, "what": rest})
        elif tag == "take":
            end = t
    return {"events": events, "light": light, "clip_events": clips, "t_end": end, "errors": errors}


def clip_intervals(clips: list[dict], t_end: float) -> list[dict]:
    out, open_at, what = [], None, ""
    for c in clips:
        if c["what"] != "clear" and open_at is None:
            open_at, what = c["t"], c["what"]
        elif c["what"] == "clear" and open_at is not None:
            out.append({"from": open_at, "to": c["t"], "what": what})
            open_at = None
        elif c["what"] != "clear":
            what = c["what"]
    if open_at is not None:
        out.append({"from": open_at, "to": t_end, "what": what})
    merged: list[dict] = []
    for i in out:
        if merged and i["from"] - merged[-1]["to"] < CLIP_MIN_S:
            merged[-1]["to"] = i["to"]
        else:
            merged.append(dict(i))
    return [i for i in merged if i["to"] - i["from"] >= CLIP_MIN_S]


# --- Gates G3-G6: each returns {"pass", "reason"} -------------------------------------------

def gate(ok: bool, reason: str) -> dict:
    return {"pass": bool(ok), "reason": reason}


def g3_desktop(res: dict, want: tuple[int, int], log: dict) -> dict:
    if not res.get("ok"):
        return gate(False, f"no take: {res.get('error', '?')}")
    if (res["w"], res["h"]) != want:
        return gate(False, f"frame {res['w']}x{res['h']}, asked {want[0]}x{want[1]}")
    for k in ("head_full_white", "tail_full_white"):
        if res.get(k, -1) < FULL_WHITE_YMIN:
            return gate(False, f"{k.split('_')[0]} marker not white edge to edge (Ymin {res.get(k)}): the window does not fill the frame")
    if res.get("magenta_max", 0) >= MAGENTA_MAX:
        return gate(False, f"wallpaper magenta in {res['magenta_max'] * 100:.2f}% of a frame")
    if log["t_end"] is not None and abs(res["duration"] - log["t_end"]) > LENGTH_SLACK_S:
        return gate(False, f"take {res['duration']:.2f} s between markers, game ran {log['t_end']:.2f} s")
    return gate(True, f"{res['w']}x{res['h']} between markers ({res['t0']:.2f}-{res['t1']:.2f} s of the recording), no desktop")


def g4_alive(res: dict, row: dict) -> dict:
    if not res.get("ok"):
        return gate(False, "no take")
    g = row.get("game") or {}
    rate = res["bytes"] / max(res["duration"], 0.01)
    motion_min = float(g.get("motion", MOTION_MIN))
    if rate < BYTES_PER_S_MIN:
        return gate(False, f"{rate / 1e6:.2f} MB/s: empty take")
    if res["black"]:
        return gate(False, f"{res['black']} black stretch(es) >= 0.5 s")
    if res["freeze"] and g.get("freeze") != "waive":
        return gate(False, f"{res['freeze']} frozen stretch(es) >= 0.75 s")
    if res["motion"] < motion_min:
        return gate(False, f"motion {res['motion']:.4f} < {motion_min}")
    return gate(True, f"{rate / 1e6:.1f} MB/s, motion {res['motion']:.4f}, no black, no freeze")


def g4b_frames(res: dict, log: dict) -> dict:
    """No dropped frames: the game kept 60 fps for the whole take (a repeat in the grab is a frame it missed)."""
    if not res.get("ok"):
        return gate(False, "no take")
    n, dup = res.get("win_frames") or 0, res.get("dup_frames")
    if not n or dup is None:
        return gate(False, "dropped frames unmeasured (capture.ps1 too old)")
    share = dup / n
    pace = 1.0 - log["t_end"] / res["duration"] if log.get("t_end") and res.get("duration") else 0.0
    if share > DROP_MAX or pace > DROP_MAX:
        return gate(False, f"dropped frames: {dup}/{n} repeated ({share * 100:.1f}%), game time {pace * 100:+.1f}% behind wall time")
    return gate(True, f"{dup}/{n} repeated frames ({share * 100:.1f}%), game time {pace * 100:+.1f}% behind")


def g5_clipping(log: dict, win: tuple[float, float]) -> dict:
    t_end = log["t_end"] if log["t_end"] is not None else win[0] + win[1]
    if not any(c["what"].startswith("probe:") for c in log["clip_events"]):
        return gate(False, "no [clip] probe in the log: run_clip too old to check the lens")
    lo, hi = win[0], win[0] + win[1]
    hits = [i for i in clip_intervals([c for c in log["clip_events"] if not c["what"].startswith("probe:")], t_end)
            if i["from"] < hi and i["to"] > lo]
    if hits:
        return gate(False, "camera in geometry: " + "; ".join(f"{h['what']} {h['from']:.2f}-{h['to']:.2f} s" for h in hits))
    return gate(True, f"lens clear {lo:.2f}-{hi:.2f} s")


def _ffmpeg_luma(path: str) -> float | None:
    out = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-vf",
                          "scale=270:-2,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-",
                          "-frames:v", "1", "-f", "null", "-"], capture_output=True, text=True)
    m = re.search(r"YAVG=([0-9.]+)", out.stdout + out.stderr)
    return float(m.group(1)) if m else None


def g6_light(res: dict, log: dict, row: dict) -> dict:
    g = row.get("game") or {}
    denied = [e for e in log["errors"] if "deny-look" in e]
    if denied:
        return gate(False, denied[0])
    if not log["light"]:
        return gate(False, "no [light] in the log")
    if not g.get("look_override"):
        for l in log["light"]:
            sh = l.get("shipped", {})
            bad = [k for k in ("exposure", "ambient", "sky") if abs(l.get(k, -1) - sh.get(k, -2)) > 1e-3]
            if bad or l.get("look") != "shipped" or l.get("fill", 0) > 0:
                return gate(False, f"light at {l['t']:.2f} s is not the game's: " +
                            ", ".join(f"{k} {l.get(k)} vs {sh.get(k)}" for k in bad) + f" look={l.get('look')} fill={l.get('fill')}")
    ref = HERE / "ref" / f"{g.get('map', '')}.png"
    if not ref.exists():
        return gate(True, f"[light] = shipped; no reference still cp/ref/{g.get('map')}.png, luma not compared")
    ref_luma = _ffmpeg_luma(str(ref))
    if not ref_luma or res.get("luma_median", -1) < 0:
        return gate(False, "luma unmeasured")
    d = res["luma_median"] / ref_luma - 1.0
    if abs(d) > LUMA_TOLERANCE:
        return gate(False, f"median luma {res['luma_median']:.1f} vs reference {ref_luma:.1f} ({d * 100:+.0f}%)")
    return gate(True, f"[light] = shipped, luma {d * 100:+.0f}% of the reference")


def g3b_realtime(take: dict) -> dict:
    """No offline frames in a rough take: real time ddagrab only, never Movie Maker (decision 195)."""
    offline = take.get("capture") != "realtime-ddagrab" or any(
        a.startswith(("--write-movie", "--final")) for a in take.get("args", []))
    if offline and take.get("mode") != "final":
        return gate(False, f"offline capture in a rough take ({take.get('capture')}): refused")
    return gate(True, f"{take.get('capture')}, {take.get('mode')}")


def _arg(args: list[str], key: str) -> str:
    for a in args:
        if a.startswith(f"--{key}="):
            return a.split("=", 1)[1]
    return ""


def g6b_matches_plan(take: dict, row: dict, expected_commit: str, log: dict | None = None) -> dict:
    """The take is the row: map, POV, stage and commit in take.json equal the plan's, and the world loaded."""
    g = row.get("game") or {}
    broken = [e for e in (log or {}).get("errors", []) if "loading resource" in e or "load dependency" in e]
    if broken:
        return gate(False, f"the world did not load ({len(broken)} resource errors): {broken[0]}")
    args = take.get("args", [])
    want = {"map": g.get("map", ""), "pov": POV_ARG.get(g.get("pov", ""), g.get("pov_arg", "")),
            "stage": g.get("stage", "") if g.get("stage") not in ("none", "free") else ""}
    bad = [f"{k} {_arg(args, k)!r} != plan {v!r}" for k, v in want.items() if _arg(args, k) != v]
    bad += [f"{k} {take.get(k)!r} != plan {g.get(k)!r}" for k in ("map", "stage") if take.get(k) != g.get(k, "")]
    if take.get("commit") != expected_commit:
        bad.append(f"commit {take.get('commit', '')[:10]} != plan ref {g.get('ref', 'main')} {expected_commit[:10]}")
    return gate(not bad, "; ".join(bad) if bad else f"map/pov/stage/commit = plan ({expected_commit[:10]})")


TAKE_GATES = {"G3": g3_desktop, "G3b": g3b_realtime, "G4": g4_alive, "G4b": g4b_frames, "G5": g5_clipping, "G6": g6_light,
         "G6b": g6b_matches_plan}


# --- One take on the PC ----------------------------------------------------------------------

def _run_task(job_pc: str, seconds: float, owner: str) -> str:
    task = f"cp_capture_{os.getpid()}_{int(time.time())}"
    return pc(f"""
$ErrorActionPreference = 'Stop'
$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File {PC_TOOLS}\\capture.ps1 -Job "{job_pc}"'
$p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
Register-ScheduledTask -TaskName '{task}' -Action $a -Principal $p -Force | Out-Null
try {{
  Start-ScheduledTask -TaskName '{task}'
  Start-Sleep -Seconds 2
  $deadline = (Get-Date).AddSeconds({int(seconds + 600)})
  while ((Get-ScheduledTask -TaskName '{task}').State -eq 'Running' -and (Get-Date) -lt $deadline) {{ Start-Sleep -Seconds 1 }}
  Write-Output ('task result ' + (Get-ScheduledTaskInfo -TaskName '{task}').LastTaskResult)
}} finally {{ Unregister-ScheduledTask -TaskName '{task}' -Confirm:$false -EA SilentlyContinue }}
""", timeout=seconds + 900)


def capture_line(plan: dict, row: dict, mode: str, local_dir: Path, retakes: int = 1) -> dict:
    name, line = plan["name"], row["id"]
    g = row.get("game") or {}
    w, h, size_note = take_size(plan.get("kind", "short"), mode)
    win = window(row)
    seconds = round(win[0] + win[1] + 1.0, 2)
    args = run_clip_args(row) + [f"--seconds={seconds}"]
    project = pc_project(g.get("ref", "main"))
    commit = pc(f"git -C '{project}' rev-parse HEAD").strip()
    ref = g.get("ref", "main")
    expected = commit   # pc_project resolved the ref to exactly this commit
    pc_dir = f"{PC_CONTENT}\\{name}\\takes\\{line}"
    local_dir.mkdir(parents=True, exist_ok=True)
    pc(f"New-Item -ItemType Directory -Force -Path '{pc_dir}', '{PC_TOOLS}' | Out-Null")
    pc_push(str(HERE / "pc" / "capture.ps1"), f"{PC_TOOLS}\\capture.ps1")
    take: dict = {}
    for attempt in range(1 + retakes):
        job = {"mode": mode, "w": w, "h": h, "fps": FPS, "godot": PC_GODOT, "project": project,
               "args": " ".join(args), "seconds": seconds, "sync_frames": SYNC_FRAMES, "tail_frames": TAIL_FRAMES,
               "keep_audio": bool(g.get("keep_audio")), "keep_raw": False,
               "win_in": win[0], "win_len": win[1],
               "raw": f"{pc_dir}\\take_raw.avi", "take": f"{pc_dir}\\take.avi",
               "log": f"{pc_dir}\\take.log", "result": f"{pc_dir}\\result.json"}
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(job, f)
        pc_push(f.name, f"{pc_dir}\\job.json")
        os.unlink(f.name)
        pc(f"Remove-Item '{pc_dir}\\result.json', '{pc_dir}\\take.log' -EA SilentlyContinue", check=False)
        t_start = time.time()
        with pclock.lease("screen", f"{name}/{line}", seconds + 60):
            task_out = _run_task(f"{pc_dir}\\job.json", seconds, f"{name}/{line}").strip()
        res = json.loads(pc(f"Get-Content '{pc_dir}\\result.json' -Raw -EA SilentlyContinue", check=False).strip().lstrip("\ufeff")
                         or json.dumps({"ok": False, "error": f"no result.json ({task_out})"}))
        try:
            pc_pull(f"{pc_dir}\\take.log", str(local_dir / "take.log"))
            log_text = (local_dir / "take.log").read_text(errors="replace")
        except subprocess.CalledProcessError:
            log_text = ""
        log = parse_log(log_text)
        gates = {"G3": g3_desktop(res, (w, h), log), "G4": g4_alive(res, row), "G4b": g4b_frames(res, log),
                 "G5": g5_clipping(log, win), "G6": g6_light(res, log, row)}
        take = {
            "line": line, "path": f"{pc_dir}\\take.avi", "w": res.get("w", w), "h": res.get("h", h), "fps": FPS,
            "commit": commit, "args": args, "seed": g.get("seed"), "t0": res.get("t0", 0.0), "t1": res.get("t1", 0.0),
            "map": g.get("map", ""), "pov": g.get("pov", ""), "stage": g.get("stage", ""), "set": g.get("set", ""),
            "bots": int(g.get("bots", 0) or 0), "look": "override" if g.get("look_override") else "shipped",
            "events": log["events"], "light": (log["light"][0] if log["light"] else {}), "light_log": log["light"],
            "clip_events": log["clip_events"],
            "clip_intervals": clip_intervals([c for c in log["clip_events"] if not c["what"].startswith("probe:")],
                                             log["t_end"] or seconds),
            "window": {"in": win[0], "len": win[1]}, "game_end": log["t_end"], "mode": mode, "size_note": size_note,
            "project": project, "attempt": attempt + 1, "wall_seconds": round(time.time() - t_start, 1),
            "measure": {k: res.get(k) for k in ("duration", "bytes", "frames", "black", "freeze", "motion",
                                                 "magenta_max", "luma_median", "win_frames", "dup_frames", "head_full_white", "tail_full_white",
                                                 "white_runs", "screen", "output_idx", "error", "godot_exit")},
            "capture": "realtime-ddagrab", "gates": gates,
        }
        gates["G3b"] = g3b_realtime(take)
        gates["G6b"] = g6b_matches_plan(take, row, expected, log)
        retry = not (gates["G3"]["pass"] and gates["G4"]["pass"] and gates["G4b"]["pass"])
        if not retry or not all(gates[k]["pass"] for k in ("G3b", "G5", "G6", "G6b")):
            break   # G5/G6 are restaged, never retaken blindly
    (local_dir / "take.json").write_text(json.dumps(take, indent=1))
    prov = {"inputs": [], "encoder": "utvideo", "lossless": True, "tool": "cp.capture", "version": VERSION,
            "commit": commit, "input_paths": []}
    (local_dir / "take.avi.prov.json").write_text(json.dumps(prov, indent=1))
    pc_push(str(local_dir / "take.json"), f"{pc_dir}\\take.json")
    pc_push(str(local_dir / "take.avi.prov.json"), f"{pc_dir}\\take.avi.prov.json")
    return take


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("plan", help="plan.json")
    ap.add_argument("lines", nargs="*", help="line ids (L3 ...)")
    ap.add_argument("--all-new", action="store_true", help="every line whose action is capture")
    ap.add_argument("--mode", choices=["rough", "final"], default="rough")
    ap.add_argument("--out", help="local folder for takes/<line>/ (default: next to plan.json)")
    a = ap.parse_args(argv)
    plan_path = Path(a.plan)
    plan = json.loads(plan_path.read_text())
    rows = {r["id"]: r for r in plan["lines"]}
    ids = a.lines or [r["id"] for r in plan["lines"] if r.get("action") == "capture" and a.all_new]
    failed = 0
    for line in ids:
        row = rows[line]
        out = Path(a.out or plan_path.parent) / "takes" / line
        if row.get("source") == "editor":
            try:
                from . import editor
            except ImportError:
                from cp import editor  # type: ignore
            take = editor.capture_editor(plan, row, a.mode, out)
        elif row.get("source") == "game":
            take = capture_line(plan, row, a.mode, out)
        else:
            print(f"{line}: source {row.get('source')} is not captured")
            continue
        bad = [f"{k} {v['reason']}" for k, v in take["gates"].items() if not v["pass"]]
        print(f"{line}: {'PASS' if not bad else 'FAIL'}  {take['w']}x{take['h']}  -> {out / 'take.json'}")
        for k, v in take["gates"].items():
            print(f"  {k} {'pass' if v['pass'] else 'FAIL'}: {v['reason']}")
        if take.get("size_note"):
            print(f"  note: {take['size_note']}")
        failed += bool(bad)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
