r"""Render a plan: one lossless clip per line, the master, the one lossy delivery mp4, gates G7-G11 + G13.

    python -m cp.render <project dir> [--tag NAME] [--only L3,L4] [--jobs 2] [--content-root DIR]

The project dir holds plan.json and voice/manifest.json (cp.voice), and takes/<line>/take.json
for captured lines. Out: lines/L#.mkv (utvideo 4:2:0 BT.709, exactly the line's frames),
edl.json, final/master/<tag>.mkv (utvideo + pcm), final/<tag>.mp4 (H.264 crf 12 4:2:0 BT.709,
AAC), a .prov.json beside every file, and render_gates.json.

A line's picture is its parts in order at speed 1.0. Footage shorter than the line fails G9
("needs footage +N s"): there is no hold, loop or slow-down anywhere in this file, and the
filtergraph guard refuses one if it ever appears. A beat moves the part's in-point (or the
previous part's length) so the event frame lands on its word (G10).

Plan lines take their picture from `parts` [{path, in, len?, cont?}], else reuse.parts, else
reuse {path, in, len}, else takes/<id>/take.json. Relative paths resolve against the project
dir, then --content-root. A beat may name the event frame directly: {"word", "event",
"src": {"path", "t"}} for footage without a take.json.
"""
import argparse
import concurrent.futures
import contextlib
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "pc"))
from cp import layout, music  # noqa: E402

VERSION = "1"
FPS = 60
GAP_S = 0.25                  # air after a voiced line
LAST_GAP_S = 0.6              # after the last line
THREADS = 4
CARD_Y = 0.2                  # comment card centre, fraction of the height
LOSSLESS_V = ["-c:v", "utvideo", "-pix_fmt", "yuv420p", "-color_primaries", "bt709", "-color_trc", "bt709",
              "-colorspace", "bt709", "-color_range", "tv"]
DELIVERY_V = ["-c:v", "libx264", "-preset", "medium", "-crf", "12", "-pix_fmt", "yuv420p", "-profile:v", "high",
              "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv",
              "-x264-params", "colorprim=bt709:transfer=bt709:colormatrix=bt709"]
DELIVERY_A = ["-c:a", "aac", "-b:a", "320k", "-ar", "48000"]
FREEZE = ("-50", "0.75")      # freezedetect noise dB, seconds (lib.sh)
DUP_MAX = 0.02                # mpdecimate duplicate ratio per line
DEFAULT_ROOTS = [r"C:\Users\ddd\Desktop\panopticon-renders\content",
                 os.path.expanduser("~/Desktop/panopticon-renders/content")]
FORBIDDEN = [(re.compile(r"\btpad\b"), "tpad (frame hold)"), (re.compile(r"\bloop\s*="), "loop filter"),
             (re.compile(r"setpts\s*=\s*(?!PTS-STARTPTS)"), "setpts retime"), (re.compile(r"minterpolate"),
             "minterpolate"), (re.compile(r"\bframerate\s*="), "framerate interpolation"),
             (re.compile(r"atempo|asetrate"), "audio retime")]
_LOG = threading.Lock()


def log(msg):
    with _LOG:
        print(msg, flush=True)


# ---------------------------------------------------------------------------
# shared media helpers
# ---------------------------------------------------------------------------

def _popen_kw():
    if os.name == "nt":
        return {"creationflags": 0x00004000}          # BELOW_NORMAL_PRIORITY_CLASS
    return {"preexec_fn": lambda: os.nice(10)}


def ff(args, what):
    r = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error", "-threads", str(THREADS)]
                       + args, capture_output=True, text=True, **_popen_kw())
    if r.returncode != 0:
        raise RuntimeError("%s: ffmpeg failed\n%s" % (what, r.stderr[-3000:]))
    return r


_probe = {}


def probe(path):
    st = os.stat(path)
    key = (path, st.st_size, st.st_mtime)
    if key not in _probe:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                              "stream=codec_type,codec_name,width,height,r_frame_rate,pix_fmt,nb_frames:format=duration",
                              "-of", "json", path], capture_output=True, text=True, check=True).stdout
        d = json.loads(out)
        v = next((s for s in d.get("streams", []) if s["codec_type"] == "video"), {})
        a = next((s for s in d.get("streams", []) if s["codec_type"] == "audio"), None)
        num, den = (v.get("r_frame_rate") or "0/1").split("/")
        _probe[key] = {"dur": float(d.get("format", {}).get("duration") or 0), "w": v.get("width"),
                       "h": v.get("height"), "fps": float(num) / float(den) if float(den) else 0,
                       "vcodec": v.get("codec_name"), "pix_fmt": v.get("pix_fmt"),
                       "acodec": a.get("codec_name") if a else None,
                       "nb_frames": int(v["nb_frames"]) if v.get("nb_frames", "N/A").isdigit() else None}
    return _probe[key]


def frames_of(path):
    """Exact decoded frame count (mkv carries no nb_frames)."""
    out = subprocess.run(["ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0", "-show_entries",
                          "stream=nb_read_packets", "-of", "csv=p=0", path], capture_output=True, text=True).stdout
    return int(out.strip() or 0)


_sha = {}


def sha1(path):
    st = os.stat(path)
    key = (path, st.st_size, st.st_mtime)
    if key not in _sha:
        h = hashlib.sha1()
        with open(path, "rb") as f:
            for b in iter(lambda: f.read(1 << 22), b""):
                h.update(b)
        _sha[key] = h.hexdigest()
    return _sha[key]


def write_prov(out, inputs, encoder, lossless, extra=None):
    body = {"inputs": [sha1(p) for p in inputs], "input_paths": [os.path.abspath(p) for p in inputs],
            "encoder": encoder, "lossless": bool(lossless), "tool": "cp.render", "version": VERSION,
            "sha1": sha1(out)}
    body.update(extra or {})
    with open(out + ".prov.json", "w", encoding="utf-8") as f:
        json.dump(body, f, indent=1)


def read_prov(path):
    p = path + ".prov.json"
    if not os.path.exists(p):
        return None
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def guard(filtergraph):
    """Refuse any filter that holds, loops or retimes footage (G9 is enforced in code, not prose)."""
    for rx, what in FORBIDDEN:
        if rx.search(filtergraph):
            raise RuntimeError("render refused: %s in the filtergraph" % what)


@contextlib.contextmanager
def heavy_lock(owner):
    """WP2's PC lease for one heavy render batch, when cp.pclock is present."""
    try:
        from cp import pclock
        fn = getattr(pclock, "lock", None) or getattr(pclock, "lease", None)
    except ImportError:
        fn = None
    if fn is None:
        yield
        return
    with fn("heavy", owner=owner):
        yield


# ---------------------------------------------------------------------------
# planning
# ---------------------------------------------------------------------------

def norm(w):
    return re.sub(r"[^a-z0-9']", "", w.lower())


def word_time(words, phrase, end=False):
    """Seconds into the line of a phrase's first occurrence (onset, or end with end=True)."""
    toks = [norm(t) for t in phrase.split() if norm(t)]
    seq = [norm(w["w"]) for w in words]
    for i in range(len(seq) - len(toks) + 1):
        if seq[i:i + len(toks)] == toks:
            return words[i + len(toks) - 1]["t1"] if end else words[i]["t0"]
    return None


def resolve(path, project, roots):
    if os.path.isabs(path) and os.path.exists(path):
        return path
    rel = path.replace("\\", os.sep).replace("/", os.sep)
    for base in [project] + list(roots):
        cand = os.path.join(base, rel)
        if os.path.exists(cand):
            return cand
    raise RuntimeError("source not found: %s (looked in %s)" % (path, ", ".join([project] + list(roots))))


def line_parts(line, project, roots):
    """The line's footage as [{path, in, len|None, cont, max_end, events}]."""
    raw = line.get("parts") or (line.get("reuse") or {}).get("parts")
    if not raw and line.get("reuse"):
        r = line["reuse"]
        raw = [{"path": r["path"], "in": r.get("in", 0.0), "len": r.get("len")}]
    events = []
    if not raw:
        tj = os.path.join(project, "takes", line["id"], "take.json")
        if not os.path.exists(tj):
            return []
        with open(tj, encoding="utf-8") as f:
            take = json.load(f)
        raw = [{"path": take["path"], "in": take.get("t0", 0.0), "max_end": take.get("t1")}]
        events = take.get("events", [])
    out = []
    for p in raw:
        ab = resolve(p["path"], project, roots)
        info = probe(ab)
        end = info["dur"] if p.get("max_end") is None else min(info["dur"], p["max_end"])
        out.append({"path": ab, "key": p["path"], "in": float(p.get("in") or 0.0), "len": p.get("len"),
                    "cont": bool(p.get("cont")), "end": end, "info": info, "events": events,
                    "freeze_ok": p.get("freeze_ok")})
    return out


def span_frames(line, manifest, is_last):
    v = (manifest.get("lines") or {}).get(line["id"])
    if v:
        return int(math.ceil((v["dur"] + (LAST_GAP_S if is_last else GAP_S)) * FPS - 1e-6))
    ms = line.get("min_seconds")
    if isinstance(ms, (int, float)) and ms > 0:
        return int(round(ms * FPS))
    return None                                   # an M line: its parts' lengths decide


def place(line, parts, span_f, words, cont_pos):
    """Fix every part's in-point and frame count; returns (segments, span_f, shortfall_s, beats, notes)."""
    notes = []
    for p in parts:
        if p["cont"]:
            if p["key"] in cont_pos:
                p["in"] = cont_pos[p["key"]]
            else:
                notes.append("cont: no earlier use of %s, from %.2f s" % (p["key"], p["in"]))
    fixed = {}
    beats = []
    for b in line.get("beats") or []:
        tw = word_time(words, b["word"])
        if tw is None:
            raise RuntimeError("%s: beat word %r not in the voice" % (line["id"], b["word"]))
        k, te = None, None
        src = b.get("src")
        for i, p in enumerate(parts):
            if src and (os.path.basename(src["path"]) == os.path.basename(p["key"])):
                k, te = i, float(src["t"])
                break
            evs = [e for e in p["events"] if e.get("kind") == b.get("event")]
            if not src and evs:
                k, te = i, float(evs[0]["t"])
                break
        if k is None:
            raise RuntimeError("%s: no event for beat %r" % (line["id"], b["word"]))
        if k == 0:
            parts[0]["in"] = te - tw
            if parts[0]["in"] < 0:
                raise RuntimeError("%s: G10 the %s at %.2f s comes before %r at %.2f s" % (
                    line["id"], b.get("event"), te, b["word"], tw))
            fixed[0] = 0
        else:
            fixed[k] = int(round((tw - (te - parts[k]["in"])) * FPS))
        beats.append({"word": b["word"], "k": k, "te": te, "tw": tw, "tol": float(b.get("tolerance_s") or 2.0 / FPS)})
    segs, t = [], 0
    for i, p in enumerate(parts):
        avail = int(math.floor((p["end"] - p["in"]) * FPS + 1e-6))
        if avail <= 0:
            raise RuntimeError("%s: %s has nothing left after %.2f s" % (line["id"], p["key"], p["in"]))
        if i in fixed and i > 0:
            if not segs:
                raise RuntimeError("%s: beat part has no part before it" % line["id"])
            prev = segs[-1]
            prev["len_f"] = fixed[i] - prev["start_f"]
            if prev["len_f"] <= 0:
                raise RuntimeError("%s: G10 beat needs part %d to start at %.2f s, before the previous part" % (
                    line["id"], i, fixed[i] / FPS))
            t = fixed[i]
        if p["len"] is not None:
            want = int(round(float(p["len"]) * FPS))
        elif i + 1 < len(parts):
            want = avail if (i + 1) not in fixed else None
        else:
            want = (span_f - t) if span_f is not None else avail
        segs.append({"path": p["path"], "key": p["key"], "in": p["in"], "start_f": t, "len_f": want, "avail": avail,
                     "freeze_ok": p.get("freeze_ok"),
                     "info": p["info"]})
        if want is not None:
            t += want
    if segs and segs[-1]["len_f"] is None:
        segs[-1]["len_f"] = (span_f or 0) - segs[-1]["start_f"]
    if span_f is None:
        span_f = sum(s["len_f"] for s in segs)
    # cut at the span; anything past it is dropped
    kept, short = [], 0
    for s in segs:
        if s["start_f"] >= span_f:
            continue
        s["len_f"] = min(s["len_f"], span_f - s["start_f"])
        kept.append(s)
    for s in kept:
        if s["len_f"] > s["avail"]:
            short += s["len_f"] - s["avail"]
    covered = sum(s["len_f"] for s in kept)
    short += max(0, span_f - covered)
    for s in kept:
        cont_pos[s["key"]] = s["in"] + s["len_f"] / FPS
    return kept, span_f, short / FPS, beats, notes


def overlay_time(ref, words, span_s):
    if ref in (None, "", "line_start"):
        return 0.0
    if ref == "line_end":
        return span_s
    kind, _, arg = ref.partition(":")
    off = 0.0
    m = re.match(r"^(.*?)([+-]\d+(?:\.\d+)?)$", arg)
    if m and kind != "t":
        arg, off = m.group(1), float(m.group(2))
    if kind == "t":
        return float(arg)
    t = word_time(words, arg, end=(kind == "word_end"))
    if t is None:
        raise RuntimeError("overlay cue %r not in the voice" % ref)
    return min(span_s, max(0.0, t + off))


# ---------------------------------------------------------------------------
# rendering
# ---------------------------------------------------------------------------

def render_base(lp, out, W, H):
    """Parts + overlays -> lossless clip of exactly lp['span_f'] frames."""
    args, fc, labels = [], [], []
    for i, s in enumerate(lp["segs"]):
        info = s["info"]
        if (info["h"] or 0) < H or (info["w"] or 0) < W:
            raise RuntimeError("%s: G7 %s is %sx%s, below %dx%d (no upscaling)" % (
                lp["id"], s["key"], info["w"], info["h"], W, H))
        len_s = s["len_f"] / FPS
        args += ["-ss", "%.4f" % s["in"], "-t", "%.4f" % (len_s + 0.5), "-i", s["path"]]
        chain = ["fps=%d" % FPS]
        if (info["w"], info["h"]) != (W, H):
            chain.append("scale=%d:%d:flags=lanczos" % (W, H))
        chain += ["setsar=1", "format=yuv420p", "trim=end_frame=%d" % s["len_f"], "setpts=PTS-STARTPTS"]
        fc.append("[%d:v]%s[p%d]" % (i, ",".join(chain), i))
        labels.append("[p%d]" % i)
    n = len(labels)
    fc.append("".join(labels) + "concat=n=%d:v=1:a=0[base]" % n)
    cur = "[base]"
    for j, ov in enumerate(lp["overlays"]):
        still = ["-ignore_loop", "0"] if ov["png"].lower().endswith(".gif") else ["-loop", "1", "-framerate", str(FPS)]
        args += still + ["-t", "%.4f" % (lp["span_f"] / FPS + 0.5), "-i", ov["png"]]
        fc.append("[%d:v]%s[o%d]" % (n + j, ov.get("chain", "format=rgba"), j))
        fc.append("%s[o%d]overlay=%s:format=auto[ov%d]" % (cur, j, ov["args"], j))
        cur = "[ov%d]" % j
    fc.append("%sformat=yuv420p[vout]" % cur)
    graph = ";".join(fc)
    guard(graph)
    ff(args + ["-filter_complex", graph, "-map", "[vout]", "-frames:v", str(lp["span_f"]), "-an"] + LOSSLESS_V
       + [out], lp["id"] + " base")
    write_prov(out, [s["path"] for s in lp["segs"]] + [o["png"] for o in lp["overlays"]], "utvideo yuv420p", True,
               {"line": lp["id"], "frames": lp["span_f"]})


def burn(lp, base, ass, out):
    cwd = os.path.dirname(ass)
    r = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error", "-threads", str(THREADS),
                        "-i", base, "-vf", "ass=%s" % os.path.basename(ass), "-frames:v", str(lp["span_f"]), "-an"]
                       + LOSSLESS_V + [out], capture_output=True, text=True, cwd=cwd, **_popen_kw())
    if r.returncode != 0:
        raise RuntimeError("%s burn: ffmpeg failed\n%s" % (lp["id"], r.stderr[-3000:]))
    write_prov(out, [base, ass], "utvideo yuv420p + ass", True, {"line": lp["id"], "frames": lp["span_f"]})


def motion_check(path, span_f):
    """G9 post-check on a rendered line: frozen stretches and duplicate-frame ratio."""
    r = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-i", path, "-vf",
                        "freezedetect=n=%sdB:d=%s,mpdecimate" % FREEZE, "-f", "null", "-"],
                       capture_output=True, text=True, **_popen_kw())
    freezes = len(re.findall(r"freeze_start", r.stderr))
    m = re.findall(r"frame=\s*(\d+)", r.stderr)
    kept = int(m[-1]) if m else span_f
    dup = max(0.0, 1.0 - kept / float(span_f)) if span_f else 0.0
    return freezes, dup


# ---------------------------------------------------------------------------
# the run
# ---------------------------------------------------------------------------

def run(project, tag=None, only=None, jobs=2, roots=None):
    t_start = time.time()
    project = os.path.abspath(project)
    roots = roots or DEFAULT_ROOTS
    with open(os.path.join(project, "plan.json"), encoding="utf-8") as f:
        plan = json.load(f)
    man_path = os.path.join(project, "voice", "manifest.json")
    manifest = {"lines": {}}
    if os.path.exists(man_path):
        with open(man_path, encoding="utf-8") as f:
            manifest = json.load(f)
    W, H = plan.get("aspect") or ([1080, 1920] if plan.get("kind") == "short" else [1920, 1080])
    tag = tag or plan["name"]
    lines_dir = os.path.join(project, "lines")
    base_dir = os.path.join(lines_dir, ".base")
    card_dir = os.path.join(project, "cards")
    for d in (lines_dir, base_dir, card_dir):
        os.makedirs(d, exist_ok=True)

    # 1. plan every line (cont positions run in order)
    import card as card_mod
    cont_pos, lps, pos = {}, [], 0
    for i, line in enumerate(plan["lines"]):
        words = ((manifest.get("lines") or {}).get(line["id"]) or {}).get("words") or []
        parts = line_parts(line, project, roots)
        span_f = span_frames(line, manifest, i == len(plan["lines"]) - 1)
        if not parts:
            raise RuntimeError("%s: no footage (plan has no parts, reuse or take)" % line["id"])
        segs, span_f, short_s, beats, notes = place(line, parts, span_f, words, cont_pos)
        lp = {"id": line["id"], "text": line.get("text", ""), "start_f": pos, "span_f": span_f, "segs": segs,
              "short_s": short_s, "beats": beats, "notes": notes, "words": words, "overlays": []}
        span_s = span_f / FPS
        for k, ov in enumerate(line.get("overlays") or []):
            if ov["kind"] not in ("comment_card", "image"):
                raise RuntimeError("%s: overlay kind %s is not built yet" % (line["id"], ov["kind"]))
            t_in = overlay_time(ov.get("in"), words, span_s)
            t_out = overlay_time(ov.get("out", "line_end"), words, span_s)
            if ov["kind"] == "image":
                lp["overlays"].append(_image_overlay(ov, resolve(ov["path"], project, roots), t_in, t_out, W, H))
                continue
            png = os.path.join(card_dir, "%s_card%d.png" % (line["id"], k))
            c = card_mod.comment_card(png, ov.get("handle", "@commenter"), ov.get("text", ""),
                                      mark_placeholder=bool(ov.get("placeholder")), workdir=card_dir)
            d_in, d_out = 0.35, 0.3
            t_out_start = max(t_in + d_in, t_out - d_out)
            args = card_mod.overlay_args(c["w"], c["h"], CARD_Y, t_in, d_in, t_out_start, d_out, W, H)
            bx, by, bw, bh = c["body"]
            top = int(round(CARD_Y * H - c["h"] / 2.0)) + by
            lp["overlays"].append({"kind": "comment_card", "png": png, "args": args, "t0": t_in,
                                   "t1": t_out_start + d_out, "box": (int((W - bw) / 2), top, bw, bh),
                                   "band": (0, top, W, bh), "text": ov.get("text", "")})
        lps.append(lp)
        pos += span_f
    total_f = pos

    print("plan: %d lines, %.2f s (%d frames @ %d), %dx%d" % (len(lps), total_f / FPS, total_f, FPS, W, H))
    for lp in lps:
        print("  %-4s @%6.2f %5.2fs  %s%s" % (lp["id"], lp["start_f"] / FPS, lp["span_f"] / FPS, " + ".join(
            "%s@%.2f %.2fs" % (os.path.basename(s["key"]), s["in"], s["len_f"] / FPS) for s in lp["segs"]),
            "  | card %.2f-%.2f" % (lp["overlays"][0]["t0"], lp["overlays"][0]["t1"]) if lp["overlays"] else ""))
        for n in lp["notes"]:
            print("      ! " + n)
    g9_plan = [lp for lp in lps if lp["short_s"] > 1e-6]
    if g9_plan:
        for lp in g9_plan:
            print("G9 FAIL %s needs footage +%.2f s (capture: seconds += %.1f)" % (lp["id"], lp["short_s"],
                                                                                   lp["short_s"] + 1))
        raise SystemExit("render: %d line(s) need footage; nothing rendered" % len(g9_plan))

    todo = [lp for lp in lps if not only or lp["id"] in only]
    cache_path = os.path.join(lines_dir, ".cache.json")
    cache = {}
    if os.path.exists(cache_path):
        with open(cache_path, encoding="utf-8") as f:
            cache = json.load(f)

    def base_key(lp):
        body = {"v": VERSION, "W": W, "H": H, "span": lp["span_f"],
                "segs": [[sha1(s["path"]), round(s["in"], 4), s["len_f"]] for s in lp["segs"]],
                "ov": [[sha1(o["png"]), o["args"], o.get("chain", "")] for o in lp["overlays"]]}
        return hashlib.sha1(json.dumps(body, sort_keys=True).encode()).hexdigest()

    # 2. base clips + OCR
    with heavy_lock("cp.render %s" % plan["name"]):
        def do_base(lp):
            out = os.path.join(base_dir, lp["id"] + ".mkv")
            key = base_key(lp)
            lp["base"], lp["base_key"] = out, key
            ent = cache.get(lp["id"], {})
            if ent.get("base") == key and os.path.exists(out) and "ocr" in ent:
                lp["ocr"] = ent["ocr"]
                lp["g9post"] = ent["g9post"]
                return "cached"
            t = time.time()
            render_base(lp, out, W, H)
            got = frames_of(out)
            if got != lp["span_f"]:
                raise RuntimeError("%s: base has %d frames, wanted %d" % (lp["id"], got, lp["span_f"]))
            ocr = layout.ocr_boxes(out, offset=lp["start_f"] / FPS, workdir=base_dir)
            lp["ocr"] = layout.drop_owned(ocr, [dict(o, box=o["band"]) for o in _global_overlays(lp)])
            lp["g9post"] = motion_check(out, lp["span_f"])
            cache[lp["id"]] = {"base": key, "ocr": lp["ocr"], "g9post": lp["g9post"]}
            return "%.0fs" % (time.time() - t)

        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
            for lp, res in zip(todo, ex.map(do_base, todo)):
                log("  base %-4s %s  ocr %d box(es)  freeze %d dup %.1f%%" % (
                    lp["id"], res, len(lp["ocr"]), lp["g9post"][0], 100 * lp["g9post"][1]))
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump(cache, f, indent=1)

        # 3. captions, solved over the whole cut
        cap_lines = [{"id": lp["id"], "start": lp["start_f"] / FPS, "dur": lp["span_f"] / FPS} for lp in lps]
        words = {lp["id"]: lp["words"] for lp in lps}
        caps = layout.captions_for(cap_lines, words, plan.get("captions", "pop"), W)
        obstacles = []
        for lp in lps:
            for o in _global_overlays(lp):
                obstacles.append({"kind": "card" if o["kind"] == "comment_card" else o["kind"], "text": o["text"],
                                  "box": o["band"], "t0": o["t0"], "t1": o["t1"]})
            obstacles.extend(lp.get("ocr") or cache.get(lp["id"], {}).get("ocr") or [])
        caps, unplaced = layout.solve(caps, obstacles, W, H)
        g11 = layout.gate_g11(caps, obstacles)
        if unplaced:
            g11 = (False, "no free slot for %d caption(s), first '%s' at %.2f s; " % (
                len(unplaced), unplaced[0]["text"], unplaced[0]["t0"]) + g11[1])
        moved = [c for c in caps if abs(c["box"][1] + c["box"][3] / 2 - layout.CAPTION_Y * H) > 1]
        log("captions: %d, %d moved off 0.72 by other text; G11 %s: %s" % (
            len(caps), len(moved), "pass" if g11[0] else "FAIL", g11[1]))

        # 4. burn captions into each line
        def do_burn(lp):
            t0, t1 = lp["start_f"] / FPS, (lp["start_f"] + lp["span_f"]) / FPS
            mine = [c for c in caps if layout.overlaps_t(c["t0"], c["t1"], t0, t1)]
            ass = os.path.join(lines_dir, lp["id"] + ".ass")
            layout.write_ass(ass, mine, W, H, offset=t0, window=(t0, t1))
            out = os.path.join(lines_dir, lp["id"] + ".mkv")
            key = hashlib.sha1((lp["base_key"] + open(ass, encoding="utf-8").read()).encode()).hexdigest()
            ent = cache.get(lp["id"], {})
            lp["out"], lp["captions"] = out, mine
            if ent.get("line") == key and os.path.exists(out):
                return "cached"
            t = time.time()
            burn(lp, lp["base"], ass, out)
            ent["line"] = key
            return "%.0fs" % (time.time() - t)

        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
            for lp, res in zip(todo, ex.map(do_burn, todo)):
                log("  line %-4s %s" % (lp["id"], res))
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump(cache, f, indent=1)
        if only:
            print("render: --only %s done (no master)" % ",".join(sorted(only)))
            return None

        # 5. audio, master, delivery
        final_dir = os.path.join(project, "final")
        master_dir = os.path.join(final_dir, "master")
        os.makedirs(master_dir, exist_ok=True)
        total_s = total_f / FPS
        placements = [(os.path.join(project, (manifest["lines"][lp["id"]]["wav"])), lp["start_f"] / FPS)
                      for lp in lps if lp["id"] in (manifest.get("lines") or {})]
        voice_wav = music.voice_track(placements, total_s, os.path.join(master_dir, tag + "_voice.wav"))
        write_prov(voice_wav, [p for p, _ in placements], "pcm_s24le", True)
        stems = [voice_wav]
        if plan.get("music"):
            track = resolve(plan["music"], project, roots)
            bed = music.bed(track, 0.0, total_s, total_s, os.path.join(master_dir, tag + "_bed.wav"),
                            float(plan.get("music_offset", 0.0)))
            write_prov(bed, [track], "pcm_s24le", True)
            stems.append(bed)
        audio = music.master(stems, os.path.join(master_dir, tag + "_mix.wav"))
        write_prov(audio, stems, "pcm_s24le loudnorm", True)
        lst = os.path.join(master_dir, tag + "_concat.txt")
        with open(lst, "w", encoding="utf-8") as f:
            for lp in lps:
                f.write("file '%s'\n" % lp["out"].replace("\\", "/").replace("'", "'\\''"))
        master = os.path.join(master_dir, tag + ".mkv")
        ff(["-f", "concat", "-safe", "0", "-i", lst, "-i", audio, "-map", "0:v", "-map", "1:a", "-c:v", "copy",
            "-c:a", "pcm_s24le", "-t", "%.4f" % total_s, master], "master")
        write_prov(master, [lp["out"] for lp in lps] + [audio], "utvideo copy + pcm_s24le", True)
        final = os.path.join(final_dir, tag + ".mp4")
        ff(["-i", master] + DELIVERY_V + DELIVERY_A + ["-movflags", "+faststart", final], "delivery")
        write_prov(final, [master], "libx264 crf 12 yuv420p bt709 + aac 320k", False)

    # 6. edl + gates
    edl = {"name": plan["name"], "fps": FPS, "w": W, "h": H, "total": round(total_s, 4),
           "master": os.path.relpath(master, project), "final": os.path.relpath(final, project), "lines": []}
    for lp in lps:
        st = lp["start_f"] / FPS
        edl["lines"].append({
            "id": lp["id"], "start": round(st, 4), "dur": round(lp["span_f"] / FPS, 4),
            "clip": os.path.relpath(lp["out"], project),
            "wav": (manifest["lines"][lp["id"]]["wav"] if lp["id"] in manifest.get("lines", {}) else None),
            "parts": [{"path": s["path"], "sha1": sha1(s["path"]), "in": round(s["in"], 4),
                       "len": round(s["len_f"] / FPS, 4), "speed": 1.0} for s in lp["segs"]],
            "overlays": [{"kind": o["kind"], "box": _box(o["box"]), "t0": round(o["t0"], 4), "t1": round(o["t1"], 4)}
                         for o in _global_overlays(lp)],
            "captions": [{"text": c["text"], "box": _box(c["box"]), "t0": c["t0"], "t1": c["t1"]}
                         for c in lp["captions"]],
            "beats": [_beat_global(lp, b) for b in lp["beats"]]})
    with open(os.path.join(project, "edl.json"), "w", encoding="utf-8") as f:
        json.dump(edl, f, indent=1)
    gates = run_gates(project, edl=edl, lps=lps, g11=g11, manifest=manifest, plan=plan)
    print("render: %s  %.2f s  in %.0f s wall" % (final, total_s, time.time() - t_start))
    return gates


def _box(b):
    return {"x": b[0], "y": b[1], "w": b[2], "h": b[3]}


def _global_overlays(lp):
    st = lp["start_f"] / FPS
    return [dict(o, t0=st + o["t0"], t1=st + o["t1"]) for o in lp["overlays"]]


def _beat_global(lp, b):
    st = lp["start_f"] / FPS
    s = lp["segs"][b["k"]]
    return {"word": b["word"], "t_word": round(st + b["tw"], 4),
            "t_event": round(st + s["start_f"] / FPS + (b["te"] - s["in"]), 4), "tolerance_s": b["tol"]}


# ---------------------------------------------------------------------------
# gates G7-G11, G13
# ---------------------------------------------------------------------------

def gate_g7(edl, project, W, H):
    bad = []
    for ln in edl["lines"]:
        i = probe(os.path.join(project, ln["clip"]))
        if (i["w"], i["h"]) != (W, H) or abs(i["fps"] - FPS) > 0.01:
            bad.append("%s %sx%s@%.2f" % (ln["id"], i["w"], i["h"], i["fps"]))
        for p in ln["parts"]:
            s = probe(p["path"])
            if (s["h"] or 0) < H or (s["w"] or 0) < W:
                bad.append("%s source %s %sx%s upscaled" % (ln["id"], os.path.basename(p["path"]), s["w"], s["h"]))
    f = probe(os.path.join(project, edl["final"]))
    if (f["w"], f["h"]) != (W, H) or abs(f["fps"] - FPS) > 0.01:
        bad.append("final %sx%s@%.2f" % (f["w"], f["h"], f["fps"]))
    return (not bad), ("; ".join(bad[:4]) if bad else "lines and final %dx%d@%d, no source below output" % (W, H, FPS))


def gate_g8(final):
    """Walk prov from the final back to the sources: one lossy encode, the delivery itself."""
    lossy, nodes, bad = [], 0, []
    seen, stack = set(), [final]
    while stack:
        p = stack.pop()
        if p in seen:
            continue
        seen.add(p)
        pv = read_prov(p)
        if pv is None:
            continue                                  # a source (take, reused clip, card png, ass)
        nodes += 1
        if not pv.get("lossless"):
            lossy.append(p)
        elif p.lower().endswith((".mkv", ".avi", ".mov")):
            c = probe(p)["vcodec"]
            if c not in ("utvideo", "ffv1") and "qp 0" not in pv.get("encoder", ""):
                bad.append("%s is %s" % (os.path.basename(p), c))
        if pv.get("sha1") and os.path.exists(p) and sha1(p) != pv["sha1"]:
            bad.append("%s changed since its prov" % os.path.basename(p))
        stack.extend(pv.get("input_paths") or [])
    ok = lossy == [final] and not bad
    return ok, "%d derived files walked; lossy: %s%s" % (
        nodes, ", ".join(os.path.basename(x) for x in lossy) or "none", ("; " + "; ".join(bad)) if bad else "")


def _image_overlay(ov, path, t_in, t_out, W, H):
    """A picture (gif or png) centred at y_frac, width_frac of the frame, alpha fading in over fade_s."""
    info = probe(path)
    w = int(round(W * float(ov.get("width_frac", 0.7)) / 2) * 2)
    h = int(round(info["h"] * w / float(info["w"]) / 2) * 2)
    y = int(round(H * float(ov.get("y_frac", 0.3))))
    fade = float(ov.get("fade_s", 0.9 * (t_out - t_in)))
    chain = "fps=%d,scale=%d:%d,format=rgba,fade=t=in:st=%.4f:d=%.4f:alpha=1" % (FPS, w, h, t_in, max(0.04, fade))
    args = "x=%d:y=%d:enable='between(t,%.4f,%.4f)'" % ((W - w) // 2, y, t_in, t_out)
    return {"kind": "image", "png": path, "chain": chain, "args": args, "t0": t_in, "t1": t_out,
            "box": ((W - w) // 2, y, w, h), "band": ((W - w) // 2, y, w, h), "text": os.path.basename(path)}


def gate_g9(lps):
    """Footage covers every line at 1.0x; no freeze or duplicates unless every part of the line carries a
    plan waiver (freeze_ok: <why>, e.g. an old animation's own low frame rate). A waiver never covers a shortfall."""
    bad, waived = [], []
    for lp in lps:
        fr, dup = lp.get("g9post", (0, 0.0))
        if lp["short_s"] > 1e-6:
            bad.append("%s needs footage +%.2f s" % (lp["id"], lp["short_s"]))
        why = [s.get("freeze_ok") for s in lp["segs"]]
        if all(why) and (fr or dup >= DUP_MAX):
            waived.append("%s waived (%s): %d freeze, %.1f%% dup" % (lp["id"], why[0], fr, 100 * dup))
            continue
        if fr:
            bad.append("%s %d frozen stretch(es)" % (lp["id"], fr))
        if dup >= DUP_MAX:
            bad.append("%s %.1f%% duplicate frames" % (lp["id"], 100 * dup))
    worst = max((lp.get("g9post", (0, 0))[1] for lp in lps if not all(s.get("freeze_ok") for s in lp["segs"])),
                default=0)
    msg = "; ".join(bad) if bad else "every line covered at 1.0x; no freeze; max dup %.1f%%" % (100 * worst)
    return (not bad), msg + ("; " + "; ".join(waived) if waived else "")


def gate_g10(edl):
    bad, n = [], 0
    for ln in edl["lines"]:
        for b in ln.get("beats") or []:
            n += 1
            d = abs(b["t_word"] - b["t_event"])
            if d > b.get("tolerance_s", 2.0 / FPS) + 1e-6:
                bad.append("%s '%s' off by %.3f s" % (ln["id"], b["word"], d))
    return (not bad), ("; ".join(bad) if bad else "%d beat(s) on their words" % n)


def run_gates(project, edl=None, lps=None, g11=None, manifest=None, plan=None):
    """G7-G11 and G13 for a rendered project; written to render_gates.json (the WP4 runner reads it)."""
    W, H = edl["w"], edl["h"]
    final = os.path.join(project, edl["final"])
    res = {}
    for name, fn in [("G7", lambda: gate_g7(edl, project, W, H)), ("G8", lambda: gate_g8(final)),
                     ("G9", lambda: gate_g9(lps)), ("G10", lambda: gate_g10(edl)), ("G11", lambda: g11),
                     ("G13", lambda: music.gate_g13(final, manifest, any("keep-audio" in (ln.get("flags") or [])
                                                                       for ln in plan["lines"])))]:
        try:
            ok, why = fn()
        except Exception as e:  # noqa: BLE001 -- a gate that cannot run fails
            ok, why = False, "gate error: %s" % e
        res[name] = {"pass": bool(ok), "reason": why}
        print("%-4s %s  %s" % (name, "pass" if ok else "FAIL", why))
    out = {"gates": res, "pass": all(v["pass"] for v in res.values())}
    with open(os.path.join(project, "render_gates.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("--tag")
    ap.add_argument("--only")
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--content-root", action="append")
    a = ap.parse_args()
    only = set(x.strip() for x in a.only.split(",")) if a.only else None
    g = run(a.project, a.tag, only, a.jobs, a.content_root)
    return 0 if (g is None or g["pass"]) else 1


if __name__ == "__main__":
    sys.exit(main())
