r"""Cut a short from its brief: the voice leads, the picture follows.

Runs ON THE PC (tools/content/assemble.sh pushes it):

    python assemble.py <project dir> <brief.md> <tag> [--no-captions]

The brief's ## script table maps every voice line to a clip and says how the
clip fits the line (the v6 retime of the shove short, generalised):

    | line | clip | in | len | fit | speed | text | card |

  clip   one clip, or several comma separated -- `path[@in[:len]]` each -- played
         back to back as one slot, so a line whose voice outlasts the first clip
         continues into the next instead of freezing on a last frame.
  in     source seconds the window starts, or at=T: the window is centred on T
         (a shove at 1.4 s: at=1.4 len=2.1 speed=0.75 -> 2.8 s on screen), or
         `cont`: carry on from where the line before it stopped in the same clip
         cell, so a card can come up over the picture that is already playing
         with no cut.
  len    source seconds in the window; blank is to the end of the clip
  fit    line    the slot is the voice + pad; a longer clip is trimmed, a shorter
                 one holds its last frame
         trim    as line, but a short clip ends the slot early
         slow    as line, but a short clip is slowed to fill it
         nohold  the clip ends the slot; leftover voice carries into the next line
         wait    the slot is the window / speed and the voice starts with it: the
                 next line waits for the picture (held if the voice is longer)
         window onset=S end=S gap=S hold=S
                 an external clip with its own sound: the voice line, `gap`
                 seconds of quiet, then the clip's audio from `onset` to `end`
                 (source seconds) at full level with the music ducked 0.3 s
                 before and back 0.5 s after, then `hold` seconds of picture and
                 music only. The video in-point is onset - (voice + gap).
         beat S  no voice: S seconds of the clip over the music
  speed  playback rate for the window (0.75 slows it); blank is 1. One value
         covers every clip part; a comma list is one per part; `fill` on the
         last part is the rate that makes it span exactly what is left of the
         slot -- slowed when its source is short, trimmed when it is long,
         never frozen and never fast-forwarded.
  card   a still that slides in over the picture with no cut:
         `path w=900 y=0.35 in=0.35 out=0.30` -- the png scaled to w wide
         keeping aspect, its centre at y of the height, in from the right over
         `in` seconds at the line's first word, out to the left over `out`
         seconds at its last word, with the drop shadow baked in by card.py.
         Swapping the png is a one-file replacement.

A fit compares the clip's seconds ON SCREEN (source / speed) with the slot, so
a slowed clip is measured as what it plays, not as what it holds.

Script header: music: <path under the project>  music_db: -18  music_fade: 1 1.5
pad: 0.2  captions: pop|none  captions_font: Impact  captions_size: 64
captions_y: 0.72 (fraction of the height)  game: 0.25 (each take's own sound
under the voice, linear, tempo-matched to a slowed picture; 0 or absent is
silent)  copy_720: yes (also write final\<tag>_720.mp4).

Every rendered segment is cached in cuts\_cache\ by a hash of its source
(path, mtime, size) and every number that shapes it, so a caption, music or
voice change re-encodes no video; the captioned picture is cached by the
picture's hash and the caption file's. The caption burn is its own video-only
ffmpeg pass: burning inside the 15-input audio graph deadlocked ffmpeg. Writes
final\<tag>.mp4, cuts\<tag>_timing.txt (the table below, in the v6 format) and
cuts\<tag>_lines.json (each line's start in the cut).
"""
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brief as brief_mod  # noqa: E402

FPS = 60
W, H = 1080, 1920
FF = ["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error"]
MUSIC_DUCK = 0.3      # music ramp-down before a window's audio
MUSIC_BACK = 0.5      # music ramp-up after it
WINDOW_FADE = 0.3     # the window audio's own fade-out, ending at `end`


def run(args, **kw):
    r = subprocess.run(args, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise SystemExit("ffmpeg failed: %s\n%s" % (" ".join(str(a) for a in args[:12]), r.stderr[-2000:]))
    return r


def dur(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return float(out) if out else 0.0


def png_size(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip().split(",")
    return int(out[0]), int(out[1])


def is_landscape(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip().split(",")
    return int(out[0]) > int(out[1])


def has_audio(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries", "stream=codec_type",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip()
    return bool(out)


def fit_filter(path):
    """Portrait: a straight scale. Landscape: a blurred fill behind a width-fit picture."""
    if is_landscape(path):
        return (f"split[a][b];[a]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},boxblur=24:4[bg];"
                f"[b]scale={W}:-2[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2")
    return f"scale={W}:{H}"


def snap(seconds):
    return round(seconds * FPS) / FPS


def sha(*parts):
    return hashlib.sha1("|".join(str(p) for p in parts).encode("utf-8")).hexdigest()[:20]


def stat_key(path):
    st = os.stat(path)
    return f"{os.path.abspath(path)}|{int(st.st_mtime)}|{st.st_size}"


def parse_fit(fit):
    words = fit.split()
    mode = words[0] if words else "line"
    opts = {}
    for w in words[1:]:
        if "=" in w:
            k, v = w.split("=", 1)
            opts[k] = float(v)
        else:
            opts["value"] = float(w)
    return mode, opts


def parse_parts(cell):
    r"""A clip cell is one or more parts, comma separated, each `path[@in[:len]]`
    in source seconds: the picture of one slot, played back to back. So
    `cuts/01a_pack.mp4,cuts/01a_hook.mp4` is the pack take and then the hook
    take -- a line whose voice outlasts the first clip continues into the next
    one instead of freezing on its last frame."""
    parts = []
    for raw in cell.split(","):
        spec = raw.strip()
        if not spec:
            continue
        path, at, length = spec, None, None
        if "@" in path:
            path, _, win = path.partition("@")
            if ":" in win:
                win, _, ln = win.partition(":")
                length = float(ln)
            at = float(win)
        parts.append({"path": path.strip(), "in": at, "len": length})
    if not parts:
        raise SystemExit("assemble: a clip cell with no clip in it")
    return parts


def parse_speeds(cell, n):
    r"""The speed column: blank is 1x for every part, one number is that speed
    for all of them, a comma list is one per part. `fill` is the speed that
    makes a part span exactly what is left of the slot -- slowed when its source
    is short, trimmed when its source is long, never frozen and never
    fast-forwarded. Only the last part may be `fill`."""
    cell = (cell or "").strip()
    if not cell:
        return [1.0] * n
    vals = [v.strip().lower() for v in cell.split(",")]
    if len(vals) == 1:
        vals = vals * n
    if len(vals) != n:
        raise SystemExit("assemble: %d speeds for %d clip parts" % (len(vals), n))
    speeds = ["fill" if v == "fill" else float(v) for v in vals]
    if "fill" in speeds[:-1]:
        raise SystemExit("assemble: only the last clip part may have speed fill")
    return speeds


def parse_card(cell):
    r"""The card column: a still that slides over the picture that is already
    playing, no cut. `path w=900 y=0.35 in=0.35 out=0.30` -- the png scaled to
    `w` wide keeping its aspect, its centre at `y` of the height, sliding in
    from the right over `in` seconds at the line's first word and out to the
    left over `out` seconds at its last word. Swapping the png for another at
    the same size rule is a one-file replacement."""
    cell = (cell or "").strip()
    if not cell:
        return None
    bits = cell.split()
    card = {"path": bits[0], "w": 900, "y": 0.35, "in": 0.35, "out": 0.30,
            "alpha": 0.6, "blur": 24, "dx": 0, "dy": 12}
    for b in bits[1:]:
        k, _, v = b.partition("=")
        if k not in card or k == "path":
            raise SystemExit("assemble: card: unknown option %s" % b)
        card[k] = float(v)
    card["w"] = int(card["w"])
    return card


def atempo_chain(speed):
    """atempo only takes 0.5-2.0 a stage, so a bigger stretch is staged."""
    if abs(speed - 1.0) < 1e-6:
        return ""
    n = 1
    while not (0.5 <= speed ** (1.0 / n) <= 2.0):
        n += 1
    step = speed ** (1.0 / n)
    return ",".join("atempo=%.6f" % step for _ in range(n))


def main():
    project, brief_path, tag = sys.argv[1], sys.argv[2], sys.argv[3]
    captions_wanted = "--no-captions" not in sys.argv[4:]
    parsed = brief_mod.parse(brief_path)
    script = parsed["script"]
    if not script:
        raise SystemExit("assemble: the brief has no ## script section")
    head = script["head"]
    pad = float(head.get("pad", 0.2))
    cache = os.path.join(project, "cuts", "_cache")
    work = os.path.join(project, "cuts", "_work", tag)
    os.makedirs(cache, exist_ok=True)
    os.makedirs(work, exist_ok=True)
    os.makedirs(os.path.join(project, "final"), exist_ok=True)

    # --- the voice ---------------------------------------------------------
    vdir = os.path.join(project, "voice")
    words_all = {}
    for name in ("words.json", "words_all.json"):
        p = os.path.join(vdir, name)
        if os.path.exists(p):
            with open(p, encoding="utf-8") as f:
                words_all = json.load(f)
            break
    voice = {}
    missing = []
    for row in brief_mod.voice_rows(script):
        wav = os.path.join(vdir, f"{row['line']}.wav")
        if not os.path.exists(wav):
            missing.append(row["line"])
            continue
        voice[row["line"]] = {"file": wav, "dur": dur(wav)}
    if missing:
        raise SystemExit("assemble: no voice for line(s) %s -- run tools/content/voice.sh first" % ", ".join(missing))

    # --- the slots ---------------------------------------------------------
    t0 = time.time()
    table = ["{0:<4} {1:>7} {2:>7} {3:<52} {4}".format("line", "start", "len", "clip", "fit")]
    segments = []
    starts = {}
    windows = []          # (audio start, audio end, source, onset, length)
    cursor = 0.0
    carry = 0.0
    prev_clip = None
    prev_rest = None      # what is left of the previous line's chain, for in: cont
    games = []            # (absolute start, src, source in, source seconds, speed, on screen)
    game_vol = float(head.get("game", 0) or 0)
    for row in script["rows"]:
        key = row["line"]
        mode, opts = parse_fit(row.get("fit", "line") or "line")
        raw_in = (row.get("in", "") or "0").strip()
        card = parse_card(row.get("card", ""))
        line_len = (voice[key]["dur"] + pad) if key in voice else 0.0

        # --- the chain: one source window per clip part, in order -----------
        if raw_in == "cont":
            if prev_clip != row["clip"] or not prev_rest:
                raise SystemExit(f"assemble: {key}: in: cont wants the line before it on the same clip with picture left")
            wins = [dict(w) for w in prev_rest]
        else:
            wins = []
            for i, part in enumerate(parse_parts(row["clip"])):
                src = os.path.join(project, part["path"].replace("/", os.sep))
                if not os.path.exists(src):
                    raise SystemExit(f"assemble: {key}: no clip at {src}")
                length = part["len"]
                if part["in"] is not None:
                    s_in = part["in"]
                elif i > 0:
                    s_in = 0.0
                elif raw_in.startswith("at="):
                    if not row.get("len"):
                        raise SystemExit(f"assemble: {key}: at= needs a len")
                    length = float(row["len"])
                    s_in = max(0.0, float(raw_in[3:]) - length / 2.0)
                else:
                    s_in = float(raw_in or 0)
                    if length is None and row.get("len"):
                        length = float(row["len"])
                avail_i = length if length is not None else max(dur(src) - s_in, 0.01)
                wins.append({"path": part["path"], "src": src, "in": s_in, "avail": avail_i})
        speeds = parse_speeds(row.get("speed", ""), len(wins))
        if mode == "window" and len(wins) != 1:
            raise SystemExit(f"assemble: {key}: a window wants one clip part, not {len(wins)}")
        orig = [w["avail"] for w in wins]
        avail = sum(orig)
        has_fill = speeds[-1] == "fill"
        out_fixed = sum(w["avail"] / s for w, s in zip(wins, speeds) if s != "fill")
        out_total = None if has_fill else out_fixed     # None: a fill part stretches to anything

        # --- how long the slot is ------------------------------------------
        starts[key] = cursor + carry
        carry_out = 0.0
        window_audio = None
        want = snap(line_len + carry)
        if mode == "window":
            onset, end = opts["onset"], opts["end"]
            gap = opts.get("gap", 0.15)
            after = opts.get("hold", 1.0)
            audio_in = voice[key]["dur"] + gap          # slot offset where the clip's sound starts
            audio_len = end - onset
            seg_len = snap(audio_in + audio_len + after)
            wins[0]["in"] = onset - audio_in
            if wins[0]["in"] < 0:
                raise SystemExit(f"assemble: {key}: the window's onset ({onset}s) is closer to the clip's start than the line is long")
            wins[0]["avail"] = seg_len
            speeds = [1.0 if has_fill else speeds[0]]
            window_audio = (cursor + carry + audio_in, wins[0]["src"], onset, audio_len)
            fit = ("window: src {:.2f}-{:.2f}s; line ends +{:.2f}s, sound on +{:.2f}s, off +{:.2f}s, then {:.1f}s music only"
                   .format(wins[0]["in"], wins[0]["in"] + seg_len, voice[key]["dur"], audio_in, audio_in + audio_len, after))
        elif mode == "beat":
            seg_len = snap(opts.get("value", 1.0))
            fit = "beat {:.2f}s (clip {:.2f}s on screen)".format(seg_len, out_fixed)
        elif mode == "nohold":
            seg_len = want if out_total is None or want <= out_total else snap(out_total)
            carry_out = max((line_len + carry) - seg_len, 0.0)
            fit = ("no hold: clip {:.2f}s ends, {:.2f}s of line carried to next".format(out_fixed, carry_out)
                   if carry_out > 0.005 else "trimmed -{:.2f}s (clip {:.2f}s)".format(out_fixed - seg_len, out_fixed))
        elif mode == "wait":
            seg_len = snap(out_fixed) if out_total is not None else want
            fit = "the picture leads: {:.2f}s on screen (line {:.2f}s)".format(seg_len, line_len)
            if want > seg_len + 0.005:
                seg_len = want
                fit += ", the line holds it +{:.2f}s".format(want - snap(out_fixed))
        elif mode == "trim":
            seg_len = want if out_total is None or want <= out_total else snap(out_total)
            fit = ("cut short with clip ({:.2f}s)".format(out_fixed) if seg_len < want - 0.005
                   else "trimmed -{:.2f}s (clip {:.2f}s)".format(out_fixed - seg_len, out_fixed))
        elif mode == "slow":
            seg_len = want
            if out_total is not None and out_total < seg_len - 0.005:
                scale = out_total / seg_len
                speeds = [s * scale for s in speeds]
                out_fixed = sum(w["avail"] / s for w, s in zip(wins, speeds))
                fit = "slowed to fill (clip {:.2f}s of source)".format(avail)
            else:
                fit = "trimmed -{:.2f}s (clip {:.2f}s)".format(out_fixed - seg_len, out_fixed)
        else:
            seg_len = want
            fit = ("trimmed -{:.2f}s (clip {:.2f}s)".format(out_fixed - seg_len, out_fixed)
                   if out_total is not None and out_total - seg_len > 0.005 else "exact")
        if carry > 0.005 and mode not in ("window", "beat"):
            fit += " [+{:.2f}s carried from prev line]".format(carry)

        # --- the slot's seconds, spread over the parts in order -------------
        rem = seg_len
        for i, w in enumerate(wins):
            s = speeds[i]
            if s == "fill":
                share = max(rem, 1.0 / FPS)
                if w["avail"] >= share:
                    w["speed"], w["avail"] = 1.0, share     # trimmed; never fast-forwarded
                else:
                    w["speed"] = w["avail"] / share
                w["out"] = share
            else:
                w["speed"] = s
                out_i = w["avail"] / s
                if out_i > rem + 1e-9:
                    w["out"] = max(rem, 0.0)
                    w["avail"] = w["out"] * s
                else:
                    w["out"] = out_i
            w["hold"] = 0.0
            rem = max(rem - w["out"], 0.0)
        live = [i for i, w in enumerate(wins) if w["out"] > 1e-6]
        used = sum(w["out"] for w in wins)
        if seg_len - used > 0.005:
            wins[live[-1] if live else 0]["hold"] = seg_len - used
            fit += "; held +{:.2f}s on the last frame".format(seg_len - used)
        rest = []
        for i, w in enumerate(wins):
            left = orig[i] - w["avail"]
            if left > 1.0 / FPS:
                rest.append({"path": w["path"], "src": w["src"], "in": w["in"] + w["avail"], "avail": left})
        prev_clip, prev_rest = row["clip"], rest

        # --- the card, if this line carries one -----------------------------
        card_png = ""
        card_t = None
        if card:
            import card as card_mod                       # only a line with a card needs it
            src_png = os.path.join(project, card["path"].replace("/", os.sep))
            if not os.path.exists(src_png):
                raise SystemExit(f"assemble: {key}: no card at {src_png}")
            card_png = os.path.join(cache, sha(stat_key(src_png), card["w"], card["alpha"], card["blur"],
                                               card["dx"], card["dy"]) + "_card.png")
            if not os.path.exists(card_png):
                card_mod.shadowed(src_png, card_png, width=card["w"], alpha=card["alpha"],
                                  blur=int(card["blur"]), dx=int(card["dx"]), dy=int(card["dy"]))
            cw, ch = png_size(card_png)
            ws = words_all.get(key, {}).get("words", [])
            t_in = max(0.0, ws[0]["t"]) if ws else 0.0
            t_out = max(t_in + card["in"], ws[-1]["t"]) if ws else max(seg_len - card["out"], t_in + card["in"])
            card_t = (cw, ch, t_in, t_out)
            fit += "; card {}x{} slides in at {:.2f}s over {:.2f}s, out at {:.2f}s over {:.2f}s".format(
                cw, ch, t_in, card["in"], t_out, card["out"])

        # --- render every part ----------------------------------------------
        if window_audio:
            windows.append(window_audio)
        part_start = starts[key]
        for i, w in enumerate(wins):
            if w["out"] <= 1e-6:
                continue
            vf = ""
            if abs(w["speed"] - 1.0) > 1e-9:
                vf += "setpts={:.6f}*PTS,".format(1.0 / w["speed"])
            vf += fit_filter(w["src"]) + f",fps={FPS},format=yuv420p"
            if w["hold"] > 0.005:
                vf += ",tpad=stop_mode=clone:stop_duration={:.4f}".format(w["hold"])
            out_len = w["out"] + w["hold"]
            card_over = ""
            if card_t:
                off = part_start - starts[key]           # where this part starts on screen
                cw, ch, t_in, t_out = card_t
                if t_out + card["out"] > off and t_in < off + out_len:
                    card_over = card_mod.overlay_args(cw, ch, card["y"], t_in - off, card["in"],
                                                      t_out - off, card["out"], W, H)
            seg_key = sha(stat_key(w["src"]), "%.4f" % w["in"], "%.4f" % w["avail"], "%.6f" % w["speed"],
                          "%.4f" % out_len, vf, FPS, card_over,
                          stat_key(card_png) if (card_png and card_over) else "")
            seg = os.path.join(cache, seg_key + ".mp4")
            if not os.path.exists(seg):
                args = FF + ["-ss", "%.4f" % w["in"], "-t", "%.4f" % w["avail"], "-i", w["src"]]
                if card_over:
                    # the pixel format is set after the overlay, so the card's alpha
                    # is still there to blend with
                    pic = vf[:-len(",format=yuv420p")] if vf.endswith(",format=yuv420p") else vf
                    args += ["-loop", "1", "-i", card_png, "-filter_complex",
                             "[0:v]" + pic + "[pic];[1:v]format=rgba[card];[pic][card]overlay="
                             + card_over + ",format=yuv420p[v]", "-map", "[v]"]
                else:
                    args += ["-vf", vf]
                args += ["-t", "%.4f" % out_len, "-an", "-c:v", "libx264", "-preset", "fast", "-crf", "18", seg]
                run(args)
                fit += "  [rendered]" if i == 0 else ""
            segments.append(seg)
            if game_vol > 0 and mode != "window" and has_audio(w["src"]):
                games.append((part_start, w["src"], w["in"], w["avail"], w["speed"], w["out"]))
            part_start += out_len

        clip_name = " , ".join("{}[{:.2f}-{:.2f}]".format(w["path"].replace("/", "\\"), w["in"], w["in"] + w["avail"])
                               for i, w in enumerate(wins) if i in live)
        fit += " @ " + ", ".join("%.3fx" % wins[i]["speed"] for i in live)
        table.append("{0:<4} {1:>6.2f}s {2:>6.2f}s {3:<52} {4}".format(key, cursor, seg_len, clip_name, fit))
        cursor += seg_len
        carry = carry_out
    t_segments = time.time() - t0

    # --- the picture -------------------------------------------------------
    t0 = time.time()
    list_path = os.path.join(work, "list.txt")
    with open(list_path, "w", encoding="utf-8") as f:
        for seg in segments:
            f.write("file '%s'\n" % seg.replace("\\", "/"))
    pic_key = sha(*[os.path.basename(s) for s in segments])
    picture = os.path.join(cache, pic_key + "_pic.mp4")
    if not os.path.exists(picture):
        run(FF + ["-f", "concat", "-safe", "0", "-i", list_path, "-c", "copy", picture])
    total = dur(picture)
    t_picture = time.time() - t0

    # --- captions: absolute line starts -> ASS, burned in a pass of its own ---
    t0 = time.time()
    cap_info = ""
    video_in = picture
    style = head.get("captions", "pop")
    if captions_wanted and style != "none":
        if not words_all:
            raise SystemExit("assemble: captions want voice\\words.json (run voice.sh) or captions: none")
        ass_text, cap_info = build_ass(starts, words_all, head)
        ass_path = os.path.join(work, "captions.ass")
        with open(ass_path, "w", encoding="utf-8") as f:
            f.write(ass_text)
        cap_key = sha(pic_key, hashlib.sha1(ass_text.encode("utf-8")).hexdigest())
        captioned = os.path.join(cache, cap_key + "_cap.mp4")
        if not os.path.exists(captioned):
            # libass reads the path itself: relative, forward slashes, from the project dir.
            rel = os.path.relpath(ass_path, project).replace("\\", "/")
            run(FF + ["-i", picture, "-vf", f"subtitles={rel}", "-an", "-c:v", "libx264", "-preset", "medium",
                      "-crf", "18", "-pix_fmt", "yuv420p", captioned], cwd=project)
            cap_info += "  [burned]"
        video_in = captioned
    t_captions = time.time() - t0

    # --- audio: voice + music + the windows, muxed over the picture -----------
    t0 = time.time()
    inputs = ["-i", video_in]
    filters = []
    mix = ""
    idx = 1
    for key, v in voice.items():
        inputs += ["-i", v["file"]]
        ms = int(round(starts[key] * 1000))
        filters.append(f"[{idx}:a]adelay={ms}|{ms}[a{idx}]")
        mix += f"[a{idx}]"
        idx += 1
    summary = []
    music = head.get("music", "")
    if music:
        mpath = os.path.join(project, music.replace("/", os.sep))
        if not os.path.exists(mpath):
            raise SystemExit(f"assemble: no music at {mpath}")
        db = float(head.get("music_db", -16))
        fades = (head.get("music_fade", "1.0 1.5") + " 1.5").split()
        fade_in, fade_out = float(fades[0]), float(fades[1])
        gate = "1"
        for a_start, _src, _onset, a_len in windows:
            on, off = a_start, a_start + a_len
            g = ("if(lt(t\\,{0:.3f})\\,1\\,if(lt(t\\,{1:.3f})\\,1-(t-{0:.3f})/{2}\\,if(lt(t\\,{3:.3f})\\,0\\,"
                 "if(lt(t\\,{4:.3f})\\,(t-{3:.3f})/{5}\\,1))))").format(on - MUSIC_DUCK, on, MUSIC_DUCK, off, off + MUSIC_BACK, MUSIC_BACK)
            gate = g if gate == "1" else f"({gate})*({g})"
            summary.append("window: sound {:.2f}-{:.2f}s (src {:.2f}-{:.2f}s); music off {:.2f}-{:.2f}s, back by {:.2f}s".format(
                on, off, _onset, _onset + a_len, on - MUSIC_DUCK, off, off + MUSIC_BACK))
        inputs += ["-stream_loop", "-1", "-i", mpath]
        filters.append("[{0}:a]atrim=0:{1:.3f},volume={2}dB,afade=t=in:st=0:d={3},volume='{4}':eval=frame,"
                       "afade=t=out:st={5:.3f}:d={6}[am]".format(idx, total, db, fade_in, gate, total - fade_out, fade_out))
        mix += "[am]"
        idx += 1
        summary.append("audio: voice + music {} dB (fade in {}s, fade out {}s)".format(db, fade_in, fade_out))
    else:
        summary.append("audio: voice only, no music" + ("" if games else "; no game audio"))
    for a_start, src, onset, a_len in windows:
        if not has_audio(src):
            raise SystemExit(f"assemble: window clip {src} has no audio")
        inputs += ["-ss", f"{onset:.4f}", "-t", f"{a_len:.4f}", "-i", src]
        ms = int(round(a_start * 1000))
        filters.append("[{0}:a]afade=t=in:st=0:d=0.03,afade=t=out:st={1:.3f}:d={2},adelay={3}|{3}[w{0}]".format(
            idx, max(a_len - WINDOW_FADE, 0.0), WINDOW_FADE, ms))
        mix += f"[w{idx}]"
        idx += 1
    for g_start, g_src, g_in, g_avail, g_speed, g_out in games:
        inputs += ["-ss", "%.4f" % g_in, "-t", "%.4f" % g_avail, "-i", g_src]
        tempo = atempo_chain(g_speed)
        ms = int(round(g_start * 1000))
        filters.append("[{0}:a]{1}atrim=0:{2:.3f},volume={3:.4f},afade=t=in:st=0:d=0.03,"
                       "afade=t=out:st={4:.3f}:d=0.05,adelay={5}|{5}[g{0}]".format(
                           idx, tempo + "," if tempo else "", g_out, game_vol, max(g_out - 0.05, 0.0), ms))
        mix += "[g{}]".format(idx)
        idx += 1
    if games:
        summary.append("game audio: the take's own sound under the voice at {:.0f}% ({:+.1f} dB), {} parts, "
                       "tempo-matched to the picture".format(game_vol * 100, 20 * math.log10(game_vol), len(games)))
    n_in = idx - 1
    if n_in == 0:
        raise SystemExit("assemble: nothing to mix (no voice, no music)")
    graph = ";".join(filters) + ";" + mix + "amix=inputs={}:normalize=0:duration=longest,atrim=0:{:.3f}[out]".format(n_in, total)
    out = os.path.join(project, "final", f"{tag}.mp4")
    run(FF + inputs + ["-filter_complex", graph, "-map", "0:v", "-map", "[out]", "-c:v", "copy", "-c:a", "aac",
                       "-b:a", "192k", "-movflags", "+faststart", out])
    small = ""
    if str(head.get("copy_720", "no")).strip().lower() in ("yes", "true", "1"):
        small = os.path.join(project, "final", f"{tag}_720.mp4")
        run(FF + ["-i", out, "-vf", "scale=720:-2", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                  "-pix_fmt", "yuv420p", "-c:a", "copy", "-movflags", "+faststart", small])
        summary.append("720p copy: %s" % small)
    t_audio = time.time() - t0

    # --- the record --------------------------------------------------------
    table.append("")
    table += summary
    if cap_info:
        table.append(cap_info)
    table.append("total: {:.2f}s".format(dur(out)))
    table.append("phases: segments {:.0f}s, picture {:.0f}s, captions {:.0f}s, audio+mux {:.0f}s".format(
        t_segments, t_picture, t_captions, t_audio))
    with open(os.path.join(project, "cuts", f"{tag}_timing.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(table) + "\n")
    with open(os.path.join(project, "cuts", f"{tag}_lines.json"), "w", encoding="utf-8") as f:
        json.dump({k: round(v, 4) for k, v in starts.items()}, f, indent=1)
    print("\n".join(table))
    print(f"final: {out}")
    return 0


def build_ass(starts, words_all, head):
    """Pop-in word captions: 2-3 word chunks, uppercase, the current word yellow with a scale pop."""
    font = head.get("captions_font", "Impact")
    size = int(head.get("captions_size", 64))
    y = int(H * float(head.get("captions_y", 0.72)))
    yellow, white = "&H4DE1FF&", "&HFFFFFF&"
    tail = 0.08

    def chunks(n):
        out = []
        while n > 0:
            if n == 4:
                out += [2, 2]
                n = 0
            elif n <= 3:
                out.append(n)
                n = 0
            else:
                out.append(3)
                n -= 3
        return out

    def ts(t):
        t = max(0.0, t)
        return "%d:%02d:%05.2f" % (int(t // 3600), int(t % 3600 // 60), t % 60)

    header = (
        "[Script Info]\nScriptType: v4.00+\nPlayResX: %d\nPlayResY: %d\nWrapStyle: 2\nScaledBorderAndShadow: yes\n\n"
        "[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, "
        "Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, "
        "MarginR, MarginV, Encoding\n"
        "Style: Pop,%s,%d,%s,%s,&H000000&,&H80000000&,0,0,0,0,100,100,1,0,1,4,3,5,40,40,0,1\n\n"
        "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
    ) % (W, H, font, size, white, white)
    events = []
    n_chunks = 0
    gaps = []
    for key, t0 in starts.items():
        if key not in words_all:
            continue
        ws = words_all[key]["words"]
        abs_words = [{"w": w["word"].upper(), "s": t0 + max(0.0, w["t"]), "e": t0 + max(0.0, w["t"]) + w["dur"]} for w in ws]
        groups = []
        i = 0
        for n in chunks(len(abs_words)):
            groups.append(abs_words[i:i + n])
            i += n
        for c, grp in enumerate(groups):
            n_chunks += 1
            # The chunk hangs on for `tail` after its last word, but never past
            # the next chunk's first word: two chunks drawn at once read as one
            # garbled line (measured on l6 of the projectile cut, where
            # "that" starts 68 ms before "implemented" had finished hanging).
            end_chunk = grp[-1]["e"] + tail
            if c + 1 < len(groups):
                end_chunk = min(end_chunk, groups[c + 1][0]["s"])
            if end_chunk <= grp[-1]["s"]:
                end_chunk = grp[-1]["s"] + 0.05
            for j, w in enumerate(grp):
                s = w["s"]
                e = grp[j + 1]["s"] if j + 1 < len(grp) else end_chunk
                if e <= s:
                    e = s + 0.05
                parts = []
                for k, x in enumerate(grp):
                    if k == j:
                        parts.append("{\\c" + yellow + "\\fscx80\\fscy80\\t(0,60,\\fscx110\\fscy110)\\t(60,120,\\fscx100\\fscy100)}" + x["w"] + "{\\r}")
                    else:
                        parts.append("{\\c" + white + "}" + x["w"] + "{\\r}")
                text = "{\\an5\\pos(%d,%d)\\blur0.6}" % (W // 2, y) + " ".join(parts)
                events.append("Dialogue: 0,%s,%s,Pop,,0,0,0,,%s" % (ts(s), ts(e), text))
        for a, b in zip(abs_words, abs_words[1:]):
            g = b["s"] - a["e"]
            if g > 0.4:
                gaps.append((key, a["w"], round(g, 2)))
    info = "captions: %d chunks, %d word events, font %s %dpx, y=%d" % (n_chunks, len(events), font, size, y)
    if gaps:
        info += "; word gaps > 0.4s: %s" % gaps
    return header + "\n".join(events) + "\n", info


if __name__ == "__main__":
    sys.exit(main())
