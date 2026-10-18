"""Ryan's recorded voice (an Audacity 4 .aup4) -> voice/<line>.wav + voice/words.json, his words as transcribed.

    tools/content/.venv/bin/python tools/content/vo.py <short.aup4> --brief <brief.md> --tag vN --out <voice dir>
"""
import argparse
import difflib
import json
import os
import re
import shutil
import sqlite3
import struct
import subprocess
import sys
import tempfile

import numpy as np
import soundfile as sf

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "pc"))
import brief as brief_mod  # noqa: E402

KEY = 0.15          # decision 357 (1): the fixed window cut off both ends of every recorded clip (the key press)
ROOM_DB = -45.0     # at or below this a 10 ms frame is room tone
LEVEL = "acompressor=threshold=-20dB:ratio=3:attack=5:release=80:makeup=2"
LOUD = "loudnorm=I=-16:TP=-1.5:LRA=7"
BREATH = 0.15       # decision 357 (3): an inter-word gap is ducked to this gain
SPLIT = 0.3         # a take splits at the deepest dip within this many seconds of the words' gap
MODEL = "small.en"
OUT_RATE = 48000
FF = ["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error"]


def read_doc(db):
    """The project's binary XML (Audacity ProjectSerializer) as a flat list of (start|end|attr, name[, value])."""
    d, doc = db.execute("select dict, doc from project").fetchone()
    buf, names, cs, i, out = bytes(d) + bytes(doc), {}, 1, 0, []

    def s(b):
        return b.decode({1: "utf-8", 2: "utf-16-le", 4: "utf-32-le"}[cs])
    while i < len(buf):
        t = buf[i]
        i += 1
        if t == 0:
            cs = buf[i]
            i += 1
        elif t == 15:
            k, n = struct.unpack_from("<HH", buf, i)
            names[k] = s(buf[i + 4:i + 4 + n])
            i += 4 + n
        elif t in (1, 2):
            k, = struct.unpack_from("<H", buf, i)
            out.append(("start" if t == 1 else "end", names[k]))
            i += 2
        elif t == 3:
            k, n = struct.unpack_from("<Hi", buf, i)
            out.append(("attr", names[k], s(buf[i + 6:i + 6 + n])))
            i += 6 + n
        elif t in (4, 6, 8):
            k, v = struct.unpack_from("<Hi" if t != 8 else "<HI", buf, i)
            out.append(("attr", names[k], v))
            i += 6
        elif t == 5:
            k, v = struct.unpack_from("<HB", buf, i)
            out.append(("attr", names[k], bool(v)))
            i += 3
        elif t == 7:
            k, v = struct.unpack_from("<Hq", buf, i)
            out.append(("attr", names[k], v))
            i += 10
        elif t == 9:
            k, v, _ = struct.unpack_from("<Hfi", buf, i)
            out.append(("attr", names[k], v))
            i += 10
        elif t == 10:
            k, v, _ = struct.unpack_from("<Hdi", buf, i)
            out.append(("attr", names[k], v))
            i += 14
        elif t in (11, 12):
            n, = struct.unpack_from("<i", buf, i)
            i += 4 + n
        elif t in (13, 14):
            pass
        elif t == 16:   # named binary (the thumbnail)
            k, n = struct.unpack_from("<Hi", buf, i)
            i += 6 + n
        else:
            raise SystemExit("vo: unknown aup4 field type %d at byte %d" % (t, i))
    return out


def clips(aup4):
    """Every clip of every unmuted track, in time order: (name, mono float32 samples with Audacity's trims applied, rate)."""
    with tempfile.TemporaryDirectory() as tmp:
        copy = os.path.join(tmp, "copy.aup4")
        shutil.copy2(aup4, copy)                  # the recording itself is never opened for writing
        db = sqlite3.connect(copy)
        stack, track, clip, found = [], None, None, []
        for o in read_doc(db):
            if o[0] == "start":
                stack.append(o[1])
                if o[1] == "wavetrack":
                    track = {"rate": 44100.0, "mute": False, "channel": 0}
                elif o[1] == "waveclip":
                    clip = {"blocks": [], "trimLeft": 0.0, "trimRight": 0.0, "offset": 0.0, "name": ""}
                continue
            if o[0] == "end":
                tag = stack.pop()
                if tag == "waveclip" and clip is not None:
                    if not track["mute"] and clip["blocks"]:
                        x = np.concatenate([np.frombuffer(db.execute("select samples from sampleblocks where blockid=?",
                                                                     (b,)).fetchone()[0], dtype="<f4") for b in clip["blocks"]])
                        r = track["rate"]
                        x = x[int(round(clip["trimLeft"] * r)):len(x) - int(round(clip["trimRight"] * r))]
                        found.append((clip["offset"], clip["name"], x.astype(np.float32), int(r)))
                    clip = None
                continue
            _, k, v = o
            where = stack[-1] if stack else ""
            if where == "wavetrack" and k in ("rate", "mute"):
                track[k] = v
            elif where == "waveclip" and k in clip:
                clip[k] = v
            elif where == "waveblock" and k == "blockid" and clip is not None:
                clip["blocks"].append(int(v))
        db.close()
    return [(n, x, r) for _, n, x, r in sorted(found, key=lambda c: c[0])]


def frames_db(x, r):
    w = max(1, r // 100)
    n = len(x) // w
    if n == 0:
        return np.array([-120.0]), w
    rms = np.sqrt(np.mean(x[:n * w].reshape(n, w) ** 2, axis=1))
    return 20 * np.log10(rms + 1e-9), w


def cut_ends(x, r):
    """357 (1): the fixed key-press window off both ends, then back to room tone on each side."""
    k = int(KEY * r)
    return to_room(x[k:len(x) - k] if len(x) > 2 * k else x, r)[0]


def to_room(x, r):
    """Both ends back to the last room-tone frame before / after speech: (samples, samples cut from the front)."""
    db, w = frames_db(x, r)
    loud = np.nonzero(db > ROOM_DB)[0]
    if not len(loud):
        return x, 0
    a, b = max(0, (loud[0] - 3) * w), min(len(x), (loud[-1] + 6) * w)
    return x[a:b], a


def transcribe(model, path):
    pcm = subprocess.run(FF + ["-i", path, "-ac", "1", "-ar", "16000", "-f", "f32le", "-"], capture_output=True, check=True).stdout
    segs, _ = model.transcribe(np.frombuffer(pcm, dtype="<f4"), language="en", word_timestamps=True, beam_size=5, vad_filter=False)
    words, text = [], []
    for s in segs:
        text.append(s.text)
        for w in s.words or []:
            words.append({"word": w.word.strip(), "t": round(float(w.start), 3), "dur": round(float(w.end - w.start), 3)})
    return " ".join(t.strip() for t in text).strip(), words


def norm(w):
    return re.sub(r"[^\w']", "", w).lower()


def assign(script_lines, heard):
    """Each heard word -> its script line index (difflib alignment; unmatched words follow their neighbour)."""
    sw = [(i, norm(w)) for i, (_, t) in enumerate(script_lines) for w in t.split() if norm(w)]
    hw = [norm(w["word"]) for w in heard]
    sm = difflib.SequenceMatcher(None, [w for _, w in sw], hw, autojunk=False)
    line = [None] * len(hw)
    for a, b, n in sm.get_matching_blocks():
        for j in range(n):
            line[b + j] = sw[a + j][0]
    last = next((v for v in line if v is not None), 0)
    for j, v in enumerate(line):
        line[j] = last = v if v is not None else last
    for j in range(1, len(line)):           # monotonic: a line never comes back
        line[j] = max(line[j], line[j - 1])
    return line


def quietest(x, r, a, b):
    """Sample index of the quietest 10 ms frame within SPLIT s of the gap a..b (the silence a take is split at)."""
    a, b = max(0.0, a - SPLIT), min(len(x) / r, b + SPLIT)
    db, w = frames_db(x, r)
    fa, fb = int(a * r) // w, max(int(a * r) // w + 1, int(b * r) // w)
    return (fa + int(np.argmin(db[fa:fb]))) * w + w // 2


def duck_breaths(x, r, words):
    """357 (3): the gaps between words (breaths) down to BREATH gain, 20 ms ramps, never into a word."""
    n = x.shape[-1]
    g = np.ones(n, dtype=np.float32)
    edge, ramp = 0.04, int(0.02 * r)
    spans = [(0.0, words[0]["t"])] if words else []
    spans += [(p["t"] + p["dur"], q["t"]) for p, q in zip(words, words[1:])]
    if words:
        spans.append((words[-1]["t"] + words[-1]["dur"], n / r))
    for a, b in spans:
        i, j = int((a + edge) * r), int((b - edge) * r)
        if j - i < 2 * ramp + int(0.06 * r):
            continue
        g[i:j] = BREATH
        g[i:i + ramp] = np.linspace(1, BREATH, ramp)
        g[j - ramp:j] = np.linspace(BREATH, 1, ramp)
    return x * g


def level(src, dst):
    """357 (2): compress, then two-pass loudnorm to one target, 48 kHz stereo."""
    p = subprocess.run(FF[:-2] + ["-loglevel", "info", "-i", src, "-af", "%s,%s:print_format=json" % (LEVEL, LOUD), "-f", "null", "-"],
                       capture_output=True, text=True)
    m = json.loads(re.search(r"\{[^{}]*\}", p.stderr[p.stderr.rindex("Parsed_loudnorm"):], re.S).group(0))
    af = "%s,%s:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true" % (
        LEVEL, LOUD, m["input_i"], m["input_tp"], m["input_lra"], m["input_thresh"], m["target_offset"])
    subprocess.run(FF + ["-i", src, "-af", af, "-ar", str(OUT_RATE), "-ac", "2", "-c:a", "pcm_s16le", dst], check=True)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("aup4")
    ap.add_argument("--brief", required=True)
    ap.add_argument("--tag", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", default=MODEL)
    a = ap.parse_args(argv)
    parsed = brief_mod.parse(a.brief)
    script = parsed["scripts"].get(a.tag) or parsed["script"]
    if not script:
        raise SystemExit("vo: %s has no ## script %s" % (a.brief, a.tag))
    lines = [(r["line"], r["text"]) for r in brief_mod.voice_rows(script)]
    takes = [(n, cut_ends(x, r), r) for n, x, r in clips(a.aup4)]
    if not takes or not lines:
        raise SystemExit("vo: %d clips, %d voice lines" % (len(takes), len(lines)))
    from faster_whisper import WhisperModel
    model = WhisperModel(a.model, device="cpu", compute_type="int8")
    os.makedirs(a.out, exist_ok=True)
    tmp = tempfile.mkdtemp()
    heard = []                                # every word of every take, timed on its take (whisper sees the whole take)
    for i, (n, x, r) in enumerate(takes):
        p = os.path.join(tmp, "take%d.wav" % i)
        sf.write(p, x, r)
        heard += [dict(w, take=i) for w in transcribe(model, p)[1]]
    if not heard:
        raise SystemExit("vo: nothing heard in %s" % a.aup4)
    pieces = {k: [] for k, _ in lines}        # line id -> [(take index, start sample, end sample)]
    if len(takes) == len(lines):              # one clip per line: the split is the clip boundary
        for i, (k, _) in enumerate(lines):
            pieces[k].append((i, 0, len(takes[i][1])))
    else:                                     # otherwise: split the takes at the silence between lines
        owner = assign(lines, heard)
        for li, (k, _) in enumerate(lines):
            idx = [j for j, o in enumerate(owner) if o == li]
            if not idx:
                raise SystemExit("vo: line %s was not heard in the recording" % k)
            for t in sorted({heard[j]["take"] for j in idx}):
                x, r = takes[t][1], takes[t][2]
                mine = [j for j in idx if heard[j]["take"] == t]
                prev = mine[0] - 1 if mine[0] > 0 and heard[mine[0] - 1]["take"] == t else None
                nxt = mine[-1] + 1 if mine[-1] + 1 < len(heard) and heard[mine[-1] + 1]["take"] == t else None
                s0 = 0 if prev is None else quietest(x, r, heard[prev]["t"] + heard[prev]["dur"], heard[mine[0]]["t"])
                s1 = len(x) if nxt is None else quietest(x, r, heard[mine[-1]]["t"] + heard[mine[-1]]["dur"], heard[nxt]["t"])
                pieces[k].append((t, s0, s1))
    words_all = {}
    for k, _ in lines:
        parts, ws, at, lead = [], [], 0, None
        r = takes[pieces[k][0][0]][2]
        for t, s0, s1 in pieces[k]:
            y, cut = to_room(takes[t][1][s0:s1], r)
            first = (s0 + cut) / r                # take seconds where this piece of the line's wav starts
            lead = first if lead is None else lead
            for w in heard:                       # a word belongs to the piece its middle falls in
                mid = w["t"] + w["dur"] / 2
                if w["take"] == t and s0 / r <= mid < s1 / r:
                    ws.append({"word": w["word"], "t": round(max(0.0, w["t"] - first + at / r), 3), "dur": w["dur"]})
            parts += [y, np.zeros(int(0.15 * r), dtype=np.float32)]
            at += len(y) + int(0.15 * r)
        x = np.concatenate(parts[:-1])
        raw = os.path.join(tmp, "%s_raw.wav" % k)
        sf.write(raw, x, r)
        lvl = os.path.join(tmp, "%s_lvl.wav" % k)
        level(raw, lvl)
        y, yr = sf.read(lvl, dtype="float32", always_2d=True)
        y = duck_breaths(y.T, yr, ws).T
        wav = os.path.join(a.out, "%s.wav" % k)
        sf.write(wav, y, yr, subtype="PCM_16")
        text = " ".join(w["word"] for w in ws)
        words_all[k] = {"file": wav, "dur": round(len(y) / yr, 3), "lead_trimmed": round(lead, 3),
                        "voice": "ryan", "rate": "", "text": text, "words": ws}
        print("%-4s %2d words  %5.2fs  %s" % (k, len(ws), len(y) / yr, text))
    shutil.rmtree(tmp, ignore_errors=True)
    with open(os.path.join(a.out, "words.json"), "w", encoding="utf-8") as f:
        json.dump(words_all, f, indent=1)
    with open(os.path.join(a.out, "source.txt"), "w", encoding="utf-8") as f:
        f.write(os.path.abspath(a.aup4) + "\n")
    print("vo: %d lines from %d clips of %s -> %s" % (len(lines), len(takes), os.path.basename(a.aup4), a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
