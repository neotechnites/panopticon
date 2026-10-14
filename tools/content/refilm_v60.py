#!/usr/bin/env python3
"""refilm_v60.py: refilm every shot of rough_v59_beats with Movie Maker and rebuild it as v60 on the v59 edit.

  gen      write the v60 brief entries (in/seconds from the spec's handles) into projects/trailer_reveal.md
  smoke    run every v60 entry headless on the Mac and compare its events with the old PC takes' logs
  film     sync the PC and film every entry with shot.sh --movie
  edit     align each new cut to v59, build rough_v60_beats.mp4 on the PC and copy it to the Mac
  all      gen, smoke, film, edit

Spec: projects/trailer_reveal/refilm_v60.json (the v59 segment table). Nothing here judges the picture.
"""
import json
import math
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
BRIEF = os.path.join(HERE, "projects", "trailer_reveal.md")
SPEC = os.path.join(HERE, "projects", "trailer_reveal", "refilm_v60.json")
RENDERS = os.path.expanduser("~/Desktop/panopticon-renders/trailer_reveal")
PC_RENDERS = "C:\\Users\\ddd\\Desktop\\panopticon-renders\\content\\trailer_reveal"
FPS = 60
BEGIN, END = "# v60 refilm begin", "# v60 refilm end"

HELL = "--set=shimmer=0.06"
# New id -> (say, capture, tape). The capture lines are the v59 shots' own (their brief entries), the hell lead-in's v52 stage and the beach shots'.
ENTRIES = {
    "1r": ("v60 refilm of the cold open: the guard's window from the lead-in behind the lip rock through the squeeze (v59 0-164)",
           "--shot=s3_open_lane --stage=trailer_open_pre --pov=guard --hud=crosshair --bots=3 --rifle=projectile --set=fire_at=3.24;shimmer=0.06 --seed=20261001", "open_pre"),
    "2r": ("v60 refilm of 2: the runner behind the victim looks up at the tower (v59 165-330)", None, None),
    "4tr": ("v60 refilm of 4t: the forest runner (v59 662-787)", None, None),
    "5gr": ("v60 refilm of 5g: the forest scope shot (v59 788-912)", None, None),
    "5hr": ("v60 refilm of 5h: the marble scope shot, Movie Maker so the round's flight does not stall (v59 913-995; Ryan note 1)", None, None),
    "20": ("v60 beach scope: the sniper's shot on the sand (v59 996-1063; filmed untaped before, now an entry)",
           "--map=beach --shot=pack_lead --stage=trailer_beach_track --bots=3 --pov=guard --hud=crosshair --rifle=projectile --shimmer=0 --set=fire=2.6 --seed=20261001", None),
    "6r": ("v60 refilm of 6: hell runner behind the rock (v59 1064-1129)", None, None),
    "7r": ("v60 refilm of 7: hell scope (v59 1130-1207)", None, None),
    "8r": ("v60 refilm of 8: hell runner after the miss (v59 1208-1323)", None, None),
    "21": ("v60 beach run: one continuous take, no splice (v59 1324-1448; Ryan note 2)",
           "--map=beach --shot=pack_lead --stage=trailer_beach_run --bots=3 --pov=runner --rifle=projectile --shimmer=0 --seed=20261001", None),
    "9agr": ("v60 refilm of 9ag: the forest shover, one take from its first frame (v59 1449-1592; Ryan note 3)", None, None),
    "9bgr": ("v60 refilm of 9bg: the falling victim (v59 1593-1716)", None, None),
    "10ar": ("v60 refilm of 10a: the marble runner (v59 1717-1851)", None, None),
    "10br": ("v60 refilm of 10b: the scope as the victim is hit (v59 1852-2009)", None, None),
    "22": ("v60 beach portal run: the first half of the portal run on the sand, the marble run's own steps and pace, one run to one portal (v59 2010-2093; Ryan note 4)",
           "--map=beach --shot=portal --stage=trailer_beach_portal --bots=3 --pov=runner --rifle=projectile --shimmer=0 --seed=20261001", None),
    "12sr": ("v60 refilm of 12s: the marble half of the portal run, the first-person shove, the guard thrown with his rifle (v59 2094-2316; Ryan notes 5, 6)", None, None),
}
BASE = {"2r": "2", "4tr": "4t", "5gr": "5g", "5hr": "5h", "6r": "6", "7r": "7", "8r": "8", "9agr": "9ag", "9bgr": "9bg", "10ar": "10a", "10br": "10b", "12sr": "12s"}


def spec():
    return json.load(open(SPEC))


def brief_entry(entry_id):
    text = open(BRIEF).read()
    for block in re.split(r"\n(?=## )", text):
        if re.match(r"## %s\n" % re.escape(entry_id), block):
            return {k: v for k, v in re.findall(r"^(capture|tape|seconds|in|said):\s*(.*)$", block, re.M)}
    raise SystemExit("no brief entry %s" % entry_id)


def windows(sp):
    """entry id -> (in, seconds): the take's game seconds the edit uses, plus the handles."""
    use = {}
    for seg in sp["segments"]:
        if "shot" not in seg:
            continue
        n = seg["out"][1] - seg["out"][0]
        lo, hi = seg["t_a"], seg["t_a"] + n / FPS
        a, b = use.get(seg["shot"], (lo, hi))
        use[seg["shot"]] = (min(a, lo), max(b, hi))
    out = {}
    for shot, (lo, hi) in use.items():
        # Floored to four decimals so the cut's first frame is the grid frame, never the one after it.
        start = math.floor(max(0.0, math.floor((lo - sp["handle_before"]) * FPS) / FPS) * 1e4) / 1e4
        out[shot] = (start, math.ceil((hi + sp["handle_after"] - start) * 20) / 20)
    return out


def gen():
    sp = spec()
    win = windows(sp)
    expect = json.load(open(os.path.join(HERE, "projects", "trailer_reveal", "refilm_v60_expect.json"))) \
        if os.path.exists(os.path.join(HERE, "projects", "trailer_reveal", "refilm_v60_expect.json")) else {}
    blocks = [BEGIN]
    for entry_id, (said, capture, tape) in ENTRIES.items():
        if capture is None:
            base = brief_entry(BASE[entry_id])
            capture, tape = base["capture"], base.get("tape")
        start, seconds = win[entry_id]
        lines = ["", "## %s" % entry_id, "said: %s" % said, "capture: %s" % capture]
        if tape:
            lines.append("tape: %s" % tape)
        lines += ["seconds: %s" % seconds, "in: %s" % start, "freeze: waive"]
        for clause in expect.get(entry_id, []):
            lines.append("expect: %s" % clause)
        blocks += lines
    blocks += ["", END, ""]
    text = open(BRIEF).read()
    chunk = "\n".join(blocks)
    if BEGIN in text:
        text = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", lambda m: chunk, text, flags=re.S)
    else:
        text = text.replace("\n## reshoot", "\n" + chunk + "\n## reshoot", 1)
    text = re.sub(r"^tag: .*$", "tag: rough_v60_beats", text, count=1, flags=re.M)
    open(BRIEF, "w").write(text)
    for entry_id in ENTRIES:
        print("  %-5s in %-8s seconds %s" % ((entry_id,) + win[entry_id]))


def smoke_args(entry_id, extra=""):
    e = brief_entry(entry_id)
    args = e["capture"]
    if e.get("tape"):
        args += " --tape=res://tools/content/projects/trailer_reveal/tapes/%s.json" % e["tape"]
    if "--seed=" not in args:
        args += " --seed=20261001"
    secs = float(e["in"]) + float(e["seconds"]) + 1.0
    return args, secs


def run_smoke(entry_id, log_path):
    args, secs = smoke_args(entry_id)
    cmd = ["godot", "--headless", "--path", REPO, "--fixed-fps", str(FPS), "--script", "res://tools/capture/run_clip.gd", "--"] + args.split() + ["--seconds=%.2f" % secs]
    # --set values carry ';' and no spaces, so a plain split is safe.
    env = dict(os.environ, STAGE_DEBUG="1")
    with open(log_path, "w") as log:
        subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, env=env, check=False)


EVENT = re.compile(r"^\[(event|stage)\]\s+([0-9.]+)\s+(.*)$")
NOISE = ("footstep", "seat", "at Runner", " at ", "round started")


def events(path):
    out = []
    for line in open(path, errors="replace"):
        m = EVENT.match(line)
        if m and not any(w in m.group(3) for w in ("footstep", "seat ", "round_started")) and not m.group(3).startswith("at "):
            out.append((float(m.group(2)), m.group(1), m.group(3).strip()))
    return out


OLD_LOG = {"1r": "takes\\v52_B2.log", "2r": "notes\\02.take.log", "4tr": "notes\\04t.take.log", "5gr": "notes\\05g.take.log",
           "5hr": "notes\\05h.take.log", "20": "takes\\beach_k_t2.log", "6r": "notes\\06.take.log", "7r": "notes\\07.take.log",
           "8r": "notes\\08.take.log", "21": "takes\\beach_run_t2.log", "9agr": "notes\\09ag.take.log", "9bgr": "notes\\09bg.take.log",
           "10ar": "notes\\10a.take.log", "10br": "notes\\10b.take.log", "12sr": "notes\\12s.take.log"}
KEEP = re.compile(r"^(hit|out|shove|catch|ghosted|hand|shot)\b|arrived|kill beat|finale shove|round hit|shoves|squeeze")


def key_events(path):
    return [(t, txt) for t, _, txt in events(path) if KEEP.search(txt)]


def pull_old(entry_id, tmp):
    from_pc = OLD_LOG.get(entry_id)
    if not from_pc:
        return None
    dest = os.path.join(tmp, "old_%s.log" % entry_id)
    key = os.path.expanduser("~/.ssh/panopticon_pc_ed25519")
    subprocess.run(["scp", "-q", "-i", key, "ddd@100.114.41.16:" + (PC_RENDERS + "\\" + from_pc).replace("\\", "/"), dest], check=False)
    return dest if os.path.exists(dest) else None


def smoke(only=None):
    tmp = os.environ.get("REFILM_TMP") or os.path.join(os.environ.get("TMPDIR", "/tmp"), "refilm_v60")
    os.makedirs(tmp, exist_ok=True)
    bad = 0
    for entry_id in ENTRIES:
        if only and entry_id not in only:
            continue
        log = os.path.join(tmp, "smoke_%s.log" % entry_id)
        run_smoke(entry_id, log)
        new = key_events(log)
        old_path = pull_old(entry_id, tmp)
        old = key_events(old_path) if old_path else []
        horizon = max([t for t, _ in new] + [0.0])
        missed = []
        for t, txt in old:
            if t > horizon + 0.01:
                continue
            if not any(abs(t - t2) <= 1.5 / FPS and txt.split()[0:2] == txt2.split()[0:2] for t2, txt2 in new):
                missed.append((t, txt))
        clauses = [v for k, v in re.findall(r"^(expect):\s*(.*)$", open(BRIEF).read().split("## %s\n" % entry_id, 1)[1].split("\n## ", 1)[0], re.M)]
        gate = subprocess.run([sys.executable, os.path.join(HERE, "expect.py"), log] + clauses, capture_output=True, text=True)
        misses = [l.strip() for l in gate.stdout.splitlines() if "MISSED" in l]
        same = "same moments as the old take" if not missed else "DIFFERENT from the old take: " + "; ".join("%.2f %s" % m for m in missed[:4])
        verdict = ("expect PASS; " if not misses else "expect MISS %s; " % misses) + same
        print("%-5s %2d events  vs old take %-10s %s" % (entry_id, len(new), "(none)" if not old_path else "%d events" % len(old), verdict))
        for t, txt in new[:8]:
            print("        %6.2f  %s" % (t, txt[:90]))
        bad += bool(misses)
    return bad


def pad2(entry_id):
    m = re.match(r"(\d+)(.*)", entry_id)
    return "%02d%s" % (int(m.group(1)), m.group(2))


KEY = os.path.expanduser("~/.ssh/panopticon_pc_ed25519")
HOST = "ddd@100.114.41.16"


def ssh(command):
    return subprocess.run(["ssh", "-i", KEY, "-o", "ConnectTimeout=20", HOST, command], check=True, capture_output=True, text=True).stdout


def pc_ps(script_text, name="refilm_v60_step.ps1"):
    """Run a PowerShell script on the PC from a file (no quoting games), print its output."""
    local = os.path.join(os.environ.get("TMPDIR", "/tmp"), name)
    open(local, "w").write(script_text)
    subprocess.run(["scp", "-q", "-i", KEY, local, "%s:C:/Users/ddd/%s" % (HOST, name)], check=True)
    out = subprocess.run(["ssh", "-i", KEY, HOST, "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\ddd\\%s" % name],
                         capture_output=True, text=True)
    os.remove(local)
    sys.stdout.write(out.stdout)
    if out.returncode != 0:
        raise SystemExit("PC step failed (%d): %s" % (out.returncode, out.stderr[-3000:]))
    return out.stdout


def film(first=None):
    state = os.path.join(RENDERS, "v60_work")
    os.makedirs(state, exist_ok=True)
    done_path = os.path.join(state, "filmed.txt")
    done = set(open(done_path).read().split()) if os.path.exists(done_path) else set()
    if not first and not done:
        subprocess.run([os.path.join(HERE, "sync.sh")], check=True)
    started = first is None
    for entry_id in ENTRIES:
        if entry_id == first:
            started = True
        if not started or entry_id in done:
            continue
        subprocess.run([os.path.join(HERE, "shot.sh"), "trailer_reveal", entry_id, "--movie"], check=True)
        with open(done_path, "a") as f:
            f.write(entry_id + "\n")
    print("film: every entry filmed (state %s; delete it to refilm from scratch)" % done_path)


def gray_frames(path, w=96, h=54):
    import numpy as np
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", "scale=%d:%d:flags=area,format=gray" % (w, h), "-f", "rawvideo", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, h, w).astype("float32")


def ncc(a, b):
    a = a - a.mean()
    b = b - b.mean()
    den = math.sqrt(float((a * a).sum() * (b * b).sum()))
    return float((a * b).sum()) / den if den else 0.0


def align(sp, win, thumbs, base_thumbs):
    """Per segment: (first take frame, offset d, how). Frame idx(f) = nominal(f) + d for out frame f."""
    plan = []
    for seg in sp["segments"]:
        a, b = seg["out"]
        if seg.get("from_base"):
            plan.append({"seg": seg, "kind": "base"})
            continue
        shot = seg["shot"]
        start = win[shot][0]
        first_abs = math.ceil(start * FPS - 1e-6)
        nominal = round(seg["t_a"] * FPS) - first_abs
        d, how, detail = 0, "exact", ""
        if seg.get("align") == "corr":
            frames = thumbs[shot]
            anchor = seg.get("anchor")
            lo, hi = (max(a, anchor - 24), min(b, anchor + 24)) if anchor else (a, b)
            scores = {}
            for dd in range(-24, 25):
                vals = [ncc(base_thumbs[f], frames[nominal + (f - a) + dd]) for f in range(lo, hi)
                        if 0 <= nominal + (f - a) + dd < len(frames)]
                if len(vals) >= (hi - lo) * 0.8:
                    scores[dd] = sum(vals) / len(vals)
            best = max(scores, key=scores.get)
            others = [v for k, v in scores.items() if abs(k - best) > 2]
            margin = scores[best] - (max(others) if others else 0.0)
            if margin >= 0.004 and scores[best] > 0.6:
                d, how = best, "corr"
            else:
                how = "WEAK (kept d=0)"
            detail = "ncc %.3f at d=%+d, d=0 %.3f, margin %.3f" % (scores[best], best, scores.get(0, 0.0), margin)
        idx0 = nominal + d
        n = b - a
        if idx0 < 0 or idx0 + n > len(thumbs[shot]):
            raise SystemExit("segment %s needs take frames %d-%d of %s (has %d): lengthen in/seconds and refilm it" % (seg["name"], idx0, idx0 + n, shot, len(thumbs[shot])))
        plan.append({"seg": seg, "kind": "take", "idx0": idx0, "d": d, "how": how, "detail": detail, "nominal": nominal})
    return plan


def lut_cube(spec_text):
    gain, power = (float(x) for x in spec_text.split()[1:3])
    size = 33
    rows = ["LUT_3D_SIZE %d" % size]
    for bb in range(size):
        for g in range(size):
            for r in range(size):
                rgb = (r / (size - 1), g / (size - 1), bb / (size - 1))
                k = 1.0 + (gain - 1.0) * (1.0 - max(rgb)) ** power
                rows.append("%.6f %.6f %.6f" % tuple(min(c * k, 1.0) for c in rgb))
    return "\n".join(rows) + "\n"


def make_graph(plan, cube):
    """The filter graph (input 0 is v59, the cuts follow in the order returned) and the edit table."""
    report = ["| segment | v59 out | shot | take frames | d | how |", "|---|---|---|---|---|---|"]
    graph, inputs, labels, cuts = [], {}, [], []
    for item in plan:
        seg = item["seg"]
        a, b = seg["out"]
        k = len(labels)
        if item["kind"] == "base":
            graph.append("[0:v]trim=start_frame=%d:end_frame=%d,setpts=PTS-STARTPTS,format=gbrp[s%d]" % (a, b, k))
            report.append("| %s | %d-%d | v59 | %d-%d | | copied |" % (seg["name"], a, b - 1, a, b - 1))
        else:
            shot = seg["shot"]
            if shot not in inputs:
                inputs[shot] = len(inputs) + 1
                cuts.append(shot)
            i0 = item["idx0"]
            chain = "[%d:v]trim=start_frame=%d:end_frame=%d,setpts=PTS-STARTPTS,format=gbrp" % (inputs[shot], i0, i0 + b - a)
            if seg.get("grade") == "hell" and cube:
                chain += ",lut3d=file=%s:interp=tetrahedral,format=gbrp" % cube
            graph.append(chain + "[s%d]" % k)
            report.append("| %s | %d-%d | %s | %d-%d | %+d | %s %s |" % (seg["name"], a, b - 1, shot, i0, i0 + b - a - 1, item["d"], item["how"], item["detail"]))
        labels.append("[s%d]" % k)
    graph.append("%sconcat=n=%d:v=1:a=0,fps=%d,scale=out_range=tv:out_color_matrix=bt709,format=yuv420p[v]" % ("".join(labels), len(labels), FPS))
    return ";".join(graph), report, cuts


def selftest():
    """Cut stand-in takes out of v59 itself, mis-state their clocks, and check the align and the graph give v59 back."""
    import numpy as np
    sp = spec()
    win = windows(sp)
    tmp = os.path.join(os.environ.get("TMPDIR", "/tmp"), "refilm_v60_selftest")
    os.makedirs(tmp, exist_ok=True)
    base = os.path.join(RENDERS, sp["base"])
    base_thumbs = gray_frames(base)
    shift = {"corr": 4, "exact": 0}
    fake, thumbs, truth = {}, {}, {}
    for seg in sp["segments"]:
        if "shot" not in seg:
            continue
        shot = seg["shot"]
        a, b = seg["out"]
        if shot in fake:
            continue
        lo = max(0, a - 30)
        hi = b + 30
        for other in sp["segments"]:
            if other.get("shot") == shot:
                lo, hi = min(lo, max(0, other["out"][0] - 30)), max(hi, other["out"][1] + 30)
        path = os.path.join(tmp, "%s.mkv" % shot)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", base, "-vf", "trim=start_frame=%d:end_frame=%d,setpts=PTS-STARTPTS,format=gbrp" % (lo, hi), "-c:v", "utvideo", path], check=True)
        fake[shot] = (path, lo)
        thumbs[shot] = gray_frames(path)
    # Each segment's t_a is moved so its nominal frame is off by the shift; the align must undo it.
    skewed = json.loads(json.dumps(sp))
    for seg in skewed["segments"]:
        if "shot" not in seg:
            continue
        start = win[seg["shot"]][0]
        first_abs = math.ceil(start * FPS - 1e-6)
        true_idx = seg["out"][0] - fake[seg["shot"]][1]
        seg["t_a"] = (first_abs + true_idx + shift[seg.get("align", "exact")]) / FPS
    plan = align(skewed, win, thumbs, base_thumbs)
    bad = [(i["seg"]["name"], i["d"]) for i in plan if i["kind"] == "take" and i["seg"].get("align") == "corr" and i["d"] != -shift["corr"]]
    graph_text, report, cuts = make_graph(plan, None)
    print("\n".join(report))
    open(os.path.join(tmp, "g.txt"), "w").write(graph_text)
    out = os.path.join(tmp, "self.mp4")
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", base] + sum((["-i", fake[c][0]] for c in cuts), []) + ["-filter_complex_script", os.path.join(tmp, "g.txt"), "-map", "[v]", "-c:v", "libx264", "-crf", "14", "-pix_fmt", "yuv420p", out]
    subprocess.run(cmd, check=True)
    got = gray_frames(out)
    diff = float(np.abs(got - base_thumbs[:len(got)]).mean())
    print("selftest: %d frames, mean abs diff to v59 %.3f, align misses %s" % (len(got), diff, bad or "none"))
    return 1 if bad or diff > 2.0 or len(got) != sp["frames"] else 0


def edit():
    sp = spec()
    win = windows(sp)
    work = os.path.join(RENDERS, "v60_work")
    os.makedirs(work, exist_ok=True)
    base_path = os.path.join(RENDERS, sp["base"])
    print("edit: v59's frames")
    base_thumbs = gray_frames(base_path)
    shots = sorted({s["shot"] for s in sp["segments"] if "shot" in s})
    ps = ["$ErrorActionPreference='Stop'", "New-Item -ItemType Directory -Force C:\\Users\\ddd\\r60thumbs | Out-Null"]
    for shot in shots:
        ps.append("ffmpeg -hide_banner -loglevel error -y -i '%s\\cuts\\%s.mp4' -vf scale=96:54:flags=area,format=gray -f rawvideo C:\\Users\\ddd\\r60thumbs\\%s.gray" % (PC_RENDERS, pad2(shot), shot))
    pc_ps("\n".join(ps) + "\n", "refilm_v60_thumbs.ps1")
    import numpy as np
    thumbs = {}
    for shot in shots:
        dest = os.path.join(work, "%s.gray" % shot)
        subprocess.run(["scp", "-q", "-i", KEY, "%s:C:/Users/ddd/r60thumbs/%s.gray" % (HOST, shot), dest], check=True)
        thumbs[shot] = np.fromfile(dest, np.uint8).reshape(-1, 54, 96).astype("float32")
    plan = align(sp, win, thumbs, base_thumbs)
    graph_text, report, cuts = make_graph(plan, "grade_hell.cube")
    open(os.path.join(work, "%s.graph.txt" % sp["tag"]), "w").write(graph_text)
    open(os.path.join(work, "grade_hell.cube"), "w").write(lut_cube(sp["grade_hell"]))
    open(os.path.join(work, "%s_edit.md" % sp["tag"]), "w").write("\n".join(report) + "\n")
    print("\n".join(report))
    for local in ("grade_hell.cube", "%s.graph.txt" % sp["tag"]):
        subprocess.run(["scp", "-q", "-i", KEY, os.path.join(work, local), "%s:C:/Users/ddd/r60build_%s" % (HOST, local)], check=True)
    subprocess.run(["scp", "-q", "-i", KEY, base_path, "%s:C:/Users/ddd/r60build_base.mp4" % HOST], check=True)
    inp = " ".join("-i '%s\\cuts\\%s.mp4'" % (PC_RENDERS, pad2(s)) for s in cuts)
    out_name = "%s.mp4" % sp["tag"]
    build = [
        "$ErrorActionPreference='Stop'", "Set-Location C:\\Users\\ddd",
        "Copy-Item r60build_grade_hell.cube grade_hell.cube -Force",
        "ffmpeg -hide_banner -loglevel error -y -i r60build_base.mp4 %s -/filter_complex r60build_%s.graph.txt -map '[v]' -map 0:a -c:v libx264 -preset medium -crf 14 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc iec61966-2-1 -color_range tv -c:a copy -movflags +faststart '%s\\final\\%s'" % (inp, sp["tag"], PC_RENDERS, out_name),
        "Copy-Item r60build_%s.graph.txt '%s\\final\\master\\%s.graph.txt' -Force" % (sp["tag"], PC_RENDERS, sp["tag"]),
        "Remove-Item r60build_* , grade_hell.cube -Force",
        "Remove-Item C:\\Users\\ddd\\r60thumbs, C:\\Users\\ddd\\r60f -Recurse -Force -ErrorAction SilentlyContinue",
        "(Get-Item '%s\\final\\%s').Length" % (PC_RENDERS, out_name),
    ]
    print("edit: building %s on the PC" % out_name)
    pc_ps("\n".join(build) + "\n", "refilm_v60_build.ps1")
    subprocess.run(["scp", "-q", "-i", KEY, "%s:%s/final/%s" % (HOST, PC_RENDERS.replace("\\", "/"), out_name), os.path.join(RENDERS, out_name)], check=True)
    pc_ps("Remove-Item C:\\Users\\ddd\\refilm_v60_*.ps1 -Force -ErrorAction SilentlyContinue\n", "refilm_v60_clean.ps1")
    print("edit: %s" % os.path.join(RENDERS, out_name))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "gen":
        gen()
    elif cmd == "film":
        film(sys.argv[2] if len(sys.argv) > 2 else None)
    elif cmd == "selftest":
        sys.exit(selftest())
    elif cmd == "edit":
        edit()
    elif cmd == "all":
        gen()
        if smoke():
            raise SystemExit("smoke missed; nothing was filmed")
        film()
        edit()
    elif cmd == "smoke":
        sys.exit(1 if smoke(sys.argv[2:] or None) else 0)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
