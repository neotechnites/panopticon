"""Gate runner -> verify.json, plus G0, G12, G14, G15, G16 (playback rate) and G17 (portrait sources).
Gate contract: fn(ctx) -> (pass, reason) or (pass, reason, {line: reason}); other WPs export `GATES = {"G7": fn}`."""
import base64
import concurrent.futures as cf
import importlib
import json
import os
import re
import subprocess
import tempfile

from . import preflight

PEER_MODULES = ("spec", "plan", "match", "inventory", "capture", "editor", "voice", "render", "layout", "music",
                "timeline")
RATE_TOL = 0.02          # rendered vs real duration of a part, as a fraction
OCR_FPS = 2
OCR_MIN_CONF = 70
PC_NAME = "DESKTOP-B2HNSVH"
# (pattern, flags): whole words unless the token is a path-ish fragment
BANNED = [(r"\bCLAUDE\b", re.I), (r"\.md\b", re.I), (r"\bagents?\b", re.I), (r"\bAI\b", 0), (r"tools/", re.I),
          (r"addons/", re.I), (r"\.claude", re.I), (r"\bddd\b", re.I), (re.escape(PC_NAME), re.I),
          (r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b", 0), (r"\bryan\b", re.I)] + \
    [(re.escape(t), re.I) for t in base64.b64decode("d2hpdGVoZWFkCnN0YWNraW50ZWdyYXRlZA==").decode().split()]  # personal names, kept out of grep
SCRUB = re.compile(r"(^|/)(CLAUDE\.md|AGENTS\.md|\.claude|\.codex|docs|tools)(/|$)|\.md$", re.I)


# ---------- context ----------

class Ctx:
    """Paths of one build. `dir` holds the JSON (plan, edl, voice manifest, verify, review, deliver)."""

    def __init__(self, dir, name=None, kind=None, final=None, spec=None):
        self.dir = dir
        self.spec = spec
        self.final = final  # local mp4 the review and OCR read
        p = self.load("plan.json") or {}
        self.name = name or p.get("name") or os.path.basename(dir.rstrip("/"))
        self.kind = kind or p.get("kind", "short")

    def path(self, f):
        return os.path.join(self.dir, f)

    def load(self, f):
        try:
            with open(self.path(f)) as fh:
                return json.load(fh)
        except (OSError, ValueError):
            return None

    @property
    def aspect(self):
        return tuple((self.load("plan.json") or {}).get("aspect") or ((1080, 1920) if self.kind == "short" else (1920, 1080)))


# ---------- probing (local or PC path) ----------

def is_pc(path):
    return bool(re.match(r"^[A-Za-z]:\\", path or ""))


_probe_cache = {}


def probe(path):
    """{w, h, fps, dur, frames} via ffprobe, on the PC for a Windows path."""
    if path in _probe_cache:
        return _probe_cache[path]
    args = ["-v", "error", "-select_streams", "v:0", "-show_entries",
            "stream=width,height,r_frame_rate,nb_frames:format=duration", "-of", "json"]
    if is_pc(path):
        rc, out = preflight.ssh("ffprobe " + " ".join(args) + f' "{path}"')
    else:
        p = subprocess.run(["ffprobe", *args, path], capture_output=True, text=True)
        rc, out = p.returncode, p.stdout
    if rc != 0:
        raise RuntimeError(f"ffprobe failed on {path}: {out[-120:]}")
    d = json.loads(out[out.index("{"):])
    s = d["streams"][0]
    n, dn = (s.get("r_frame_rate") or "0/1").split("/")
    r = {"w": int(s["width"]), "h": int(s["height"]), "fps": float(n) / float(dn or 1),
         "dur": float(d.get("format", {}).get("duration") or 0), "frames": int(s.get("nb_frames") or 0)}
    _probe_cache[path] = r
    return r


def _take_json(part_path):
    """take.json beside a take (WP2 layout: takes/L03/take.avi + take.json), local or on the PC."""
    d = os.path.dirname(part_path.replace("\\", "/"))
    if is_pc(part_path):
        rc, out = preflight.ssh(f'Get-Content -Raw "{os.path.dirname(part_path)}\\take.json" -ErrorAction SilentlyContinue')
        try:
            return json.loads(out) if rc == 0 and out.strip().startswith("{") else None
        except ValueError:
            return None
    try:
        with open(os.path.join(d, "take.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


# ---------- gates owned here ----------

def g0(ctx):
    plan = ctx.load("plan.json") or {}
    capture = any(l.get("action") in ("capture", "editor") for l in plan.get("lines", []))
    ok, why, _ = preflight.run(capture=capture, log=lambda *_: None)
    return ok, why


def ocr_tokens(video, fps=OCR_FPS, start=None, dur=None):
    """[(t, token, word)] banned tokens found by tesseract in frames of `video`."""
    hits = []
    with tempfile.TemporaryDirectory(prefix="cp_ocr_") as td:
        cmd = ["ffmpeg", "-v", "error"]
        if start is not None:
            cmd += ["-ss", str(start)]
        cmd += ["-i", video]
        if dur is not None:
            cmd += ["-t", str(dur)]
        subprocess.run(cmd + ["-vf", f"fps={fps}", os.path.join(td, "f%05d.png")], check=True)
        frames = sorted(f for f in os.listdir(td) if f.endswith(".png"))

        def one(f):
            p = subprocess.run(["tesseract", os.path.join(td, f), "-", "--psm", "11", "tsv"],
                               capture_output=True, text=True)
            words = []
            for row in p.stdout.splitlines()[1:]:
                c = row.split("\t")
                if len(c) == 12 and c[11].strip() and float(c[10]) >= OCR_MIN_CONF:
                    words.append(c[11].strip())
            text = " ".join(words)
            t = (int(f[1:6]) - 1) / fps + (start or 0)
            return [(t, pat, m.group(0)) for pat, fl in BANNED for m in [re.search(pat, text, fl)] if m]

        with cf.ThreadPoolExecutor(os.cpu_count() or 4) as ex:
            for r in ex.map(one, frames):
                hits += r
    return hits


def scrub_check(listing):
    """Files in an editor worktree listing that must not exist before the editor launches (decision 362)."""
    return [p for p in listing if SCRUB.search(p.replace("\\", "/"))]


def g12(ctx):
    bad = {}
    plan = ctx.load("plan.json") or {}
    for l in plan.get("lines", []):
        if l.get("action") != "editor":
            continue
        tj = ctx.load(f"takes/{l['id']}/take.json") or {}
        left = scrub_check(tj.get("scrub_listing") or [])
        if "scrub_listing" not in tj:
            bad[l["id"]] = "editor take has no scrub listing in take.json"
        elif left:
            bad[l["id"]] = f"editor worktree not scrubbed: {', '.join(left[:4])}"
    if not ctx.final or not os.path.isfile(ctx.final):
        return False, f"no local final to OCR ({ctx.final})", bad
    hits = ocr_tokens(ctx.final)
    edl = ctx.load("edl.json") or {}
    for t, pat, word in hits:
        lid = next((l["id"] for l in edl.get("lines", []) if l["start"] <= t < l["start"] + l["dur"]), "final")
        bad.setdefault(lid, f"banned text '{word}' at {t:.1f}s")
    if bad:
        return False, "; ".join(f"{k}: {v}" for k, v in bad.items()), bad
    return True, f"OCR at {OCR_FPS} fps: no banned tokens"


def g14(ctx):
    from . import review
    r = ctx.load("review.json")
    if not r:
        return False, "no review.json"
    ok, why = review.gate(r)
    return ok, why, {l["id"]: l["reason"] for l in r["lines"] if not l["pass"]}


def g15(ctx):
    d = ctx.load("deliver.json")
    if not d:
        return False, "not delivered (no deliver.json)"
    bad = []
    for k in ("mac", "pc"):
        p = d.get(k)
        if not p:
            bad.append(f"no {k} copy")
            continue
        if not re.search(r"_v\d+\.(mp4|fcpxml)$", p):
            bad.append(f"{k} name not versioned: {p}")
    if d.get("overwrote"):
        bad.append(f"overwrote {d['overwrote']}")
    if d.get("mac") and not os.path.isfile(d["mac"]):
        bad.append("Mac copy missing")
    if d.get("mac") and d.get("size") and os.path.isfile(d["mac"]) and os.path.getsize(d["mac"]) != d["size"]:
        bad.append("Mac copy size differs from the PC copy")
    if ctx.kind == "devlog":
        if not d.get("fcpxml"):
            bad.append("devlog has no fcpxml timeline (358)")
        if d.get("mp4") and not d.get("concat_asked"):
            bad.append("devlog shipped a concat mp4 nobody asked for (358)")
    return (not bad), ("; ".join(bad) if bad else f"delivered {os.path.basename(d.get('mac', ''))} to Mac and PC")


def g16(ctx):
    """Every part plays at 1.0x of real time: speed 1.0, file fps = take fps, file duration = real take time."""
    edl = ctx.load("edl.json")
    if not edl:
        return False, "no edl.json"
    bad = {}
    for l in edl.get("lines", []):
        for p in l.get("parts", []):
            if abs(float(p.get("speed", 1.0)) - 1.0) > 1e-6:
                bad[l["id"]] = f"part {os.path.basename(p['path'])} at speed {p['speed']}"
                break
            try:
                info = probe(p["path"])
            except Exception as e:
                bad[l["id"]] = str(e)
                break
            if p["in"] + p["len"] > info["dur"] + 1 / max(info["fps"], 1):
                bad[l["id"]] = (f"part {os.path.basename(p['path'])} needs {p['in'] + p['len']:.2f}s, "
                                f"source has {info['dur']:.2f}s (held or looped)")
                break
            tj = _take_json(p["path"])
            if tj:
                real = float(tj["t1"]) - float(tj["t0"])
                if tj.get("fps") and abs(info["fps"] - float(tj["fps"])) > 0.01:
                    bad[l["id"]] = (f"{os.path.basename(p['path'])} plays at {info['fps']:g} fps but was captured "
                                    f"at {tj['fps']:g} fps ({info['fps'] / float(tj['fps']):.2f}x)")
                    break
                if real > 0 and abs(info["dur"] - real) / real > RATE_TOL:
                    bad[l["id"]] = (f"{os.path.basename(p['path'])} lasts {info['dur']:.2f}s for {real:.2f}s of real "
                                    f"game time ({real / info['dur']:.2f}x speed)")
                    break
    if bad:
        return False, "; ".join(f"{k}: {v}" for k, v in bad.items()), bad
    return True, "every part at 1.0x real time"


def g17(ctx):
    """A short takes only native portrait sources at least the output size: no letterbox on blur, no upscale."""
    if ctx.kind != "short":
        return True, "not a short"
    edl = ctx.load("edl.json")
    if not edl:
        return False, "no edl.json"
    W, H = ctx.aspect
    bad = {}
    for l in edl.get("lines", []):
        for p in l.get("parts", []):
            try:
                i = probe(p["path"])
            except Exception as e:
                bad[l["id"]] = str(e)
                break
            if i["w"] >= i["h"]:
                bad[l["id"]] = f"{os.path.basename(p['path'])} is landscape {i['w']}x{i['h']} in a portrait short"
                break
            if i["w"] < W or i["h"] < H:
                bad[l["id"]] = f"{os.path.basename(p['path'])} is {i['w']}x{i['h']}, under {W}x{H} (would upscale)"
                break
    if bad:
        return False, "; ".join(f"{k}: {v}" for k, v in bad.items()), bad
    return True, f"every source native portrait >= {W}x{H}"


OWN = {"G0": g0, "G12": g12, "G14": g14, "G15": g15, "G16": g16, "G17": g17}


def registry():
    """All gates: these plus every peer module's GATES dict (a peer may not redefine one owned here)."""
    gates = {}
    for m in PEER_MODULES:
        try:
            mod = importlib.import_module(f"{__package__}.{m}")
        except ImportError:
            continue
        gates.update({k: v for k, v in getattr(mod, "GATES", {}).items() if k not in OWN})
    gates.update(OWN)
    return gates


def run(ctx, ids, log=print):
    """Run gates `ids`, merge into verify.json, return (all pass, {id: result})."""
    reg = registry()
    v = ctx.load("verify.json") or {"gates": {}}
    out = {}
    for gid in ids:
        fn = reg.get(gid)
        if fn is None:
            r = {"pass": False, "reason": f"{gid} not implemented (its module has not landed)"}
        else:
            try:
                res = fn(ctx)
                r = {"pass": bool(res[0]), "reason": res[1]}
                if len(res) > 2 and res[2]:
                    r["lines"] = res[2]
            except Exception as e:
                r = {"pass": False, "reason": f"{gid} crashed: {type(e).__name__}: {e}"}
        v["gates"][gid] = out[gid] = r
        log(f"{gid} {'PASS' if r['pass'] else 'FAIL'}: {r['reason']}")
    v["pass"] = all(g["pass"] for g in v["gates"].values())
    os.makedirs(ctx.dir, exist_ok=True)
    with open(ctx.path("verify.json"), "w") as f:
        json.dump(v, f, indent=1)
    return all(r["pass"] for r in out.values()), out


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(prog="content verify")
    ap.add_argument("dir", help="build dir with plan.json / edl.json")
    ap.add_argument("--final", help="local final mp4")
    ap.add_argument("--gates", default="G12,G16,G17", help="comma list")
    a = ap.parse_args(argv)
    ok, _ = run(Ctx(a.dir, final=a.final), a.gates.split(","))
    return 0 if ok else 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
