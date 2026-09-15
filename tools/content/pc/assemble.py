r"""Cut a short from its brief: the voice leads, the picture follows.

Runs ON THE PC (tools/content/assemble.sh pushes it):

    python assemble.py <project dir> <brief.md> <tag> [--no-captions]

The brief's ## script table maps every voice line to a clip and says how the
clip fits the line (the v6 retime of the shove short, generalised):

    | line | clip | in | len | fit | speed | text |

  in     source seconds the window starts, or at=T: the window is centred on T
         (a shove at 1.4 s: at=1.4 len=2.1 speed=0.75 -> 2.8 s on screen)
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
  speed  playback rate for the window (0.75 slows it); blank is 1

Script header: music: <path under the project>  music_db: -18  music_fade: 1 1.5
pad: 0.2  captions: pop|none  captions_font: Impact  captions_size: 64
captions_y: 0.72 (fraction of the height).

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
    table = ["{0:<4} {1:>7} {2:>7} {3:<40} {4}".format("line", "start", "len", "clip", "fit")]
    segments = []
    starts = {}
    windows = []          # (audio start, audio end, source, onset, length)
    cursor = 0.0
    carry = 0.0
    for row in script["rows"]:
        key = row["line"]
        src = os.path.join(project, row["clip"].replace("/", os.sep))
        if not os.path.exists(src):
            raise SystemExit(f"assemble: {key}: no clip at {src}")
        mode, opts = parse_fit(row.get("fit", "line") or "line")
        speed = float(row.get("speed") or 1.0)
        src_dur = dur(src)
        length = float(row["len"]) if row.get("len") else None
        raw_in = row.get("in", "") or "0"
        if raw_in.startswith("at="):
            centre = float(raw_in[3:])
            if length is None:
                raise SystemExit(f"assemble: {key}: at= needs a len")
            start_in = max(0.0, centre - length / 2.0)
        else:
            start_in = float(raw_in)
        avail = length if length is not None else max(src_dur - start_in, 0.01)
        line_len = (voice[key]["dur"] + pad) if key in voice else 0.0
        starts[key] = cursor + carry
        carry_out = 0.0
        hold = 0.0
        window_audio = None
        if mode == "nohold":
            if line_len + carry > avail:
                seg_len = snap(avail)
                carry_out = (line_len + carry) - seg_len
                fit = "no hold: clip {:.2f}s ends, {:.2f}s of line carried to next".format(avail, carry_out)
            else:
                seg_len = snap(line_len + carry)
                fit = "trimmed -{:.2f}s (clip {:.2f}s)".format(avail - seg_len, avail)
        elif mode == "wait":
            seg_len = snap(avail / speed)
            fit = "slowed {}x, src {:.2f}-{:.2f}s -> {:.2f}s (line {:.2f}s waits)".format(
                speed, start_in, start_in + avail, seg_len, line_len)
            if line_len + carry > seg_len:
                hold = line_len + carry - seg_len
                seg_len = snap(line_len + carry)
                fit += ", held +{:.2f}s".format(hold)
        elif mode == "window":
            onset, end = opts["onset"], opts["end"]
            gap = opts.get("gap", 0.15)
            after = opts.get("hold", 1.0)
            audio_in = voice[key]["dur"] + gap          # slot offset where the clip's sound starts
            audio_len = end - onset
            seg_len = snap(audio_in + audio_len + after)
            start_in = onset - audio_in
            if start_in < 0:
                raise SystemExit(f"assemble: {key}: the window's onset ({onset}s) is closer to the clip's start than the line is long")
            avail = seg_len
            window_audio = (cursor + carry + audio_in, src, onset, audio_len)
            fit = ("window: src {:.2f}-{:.2f}s; line ends +{:.2f}s, sound on +{:.2f}s, off +{:.2f}s, then {:.1f}s music only"
                   .format(start_in, start_in + seg_len, voice[key]["dur"], audio_in, audio_in + audio_len, after))
        elif mode == "beat":
            seg_len = snap(opts.get("value", 1.0))
            if seg_len > avail + 0.005:
                hold = seg_len - avail
                fit = "beat {:.2f}s, held +{:.2f}s (clip {:.2f}s)".format(seg_len, hold, avail)
            else:
                fit = "beat {:.2f}s (clip {:.2f}s)".format(seg_len, avail)
        else:
            seg_len = snap(line_len + carry)
            if seg_len > avail + 0.005:
                if mode == "slow":
                    speed = avail / seg_len
                    fit = "slowed to {:.2f}x to fill (clip {:.2f}s)".format(speed, avail)
                elif mode == "trim":
                    seg_len = snap(avail)
                    fit = "cut short with clip ({:.2f}s)".format(avail)
                else:
                    hold = seg_len - avail
                    fit = "held +{:.2f}s (clip {:.2f}s)".format(hold, avail)
            elif avail - seg_len > 0.005:
                fit = "trimmed -{:.2f}s (clip {:.2f}s)".format(avail - seg_len, avail)
            else:
                fit = "exact"
            if carry > 0:
                fit += " [+{:.2f}s carried from prev line]".format(carry)
        if window_audio:
            windows.append(window_audio)
        vf = ""
        if abs(speed - 1.0) > 1e-9:
            vf += "setpts={:.6f}*PTS,".format(1.0 / speed)
        vf += fit_filter(src) + f",fps={FPS},format=yuv420p"
        if hold > 0.005:
            vf += f",tpad=stop_mode=clone:stop_duration={hold:.4f}"
        seg_key = sha(stat_key(src), f"{start_in:.4f}", f"{avail:.4f}", f"{speed:.6f}", f"{seg_len:.4f}", f"{hold:.4f}", vf, FPS)
        seg = os.path.join(cache, seg_key + ".mp4")
        if not os.path.exists(seg):
            run(FF + ["-ss", f"{start_in:.4f}", "-t", f"{avail:.4f}", "-i", src, "-t", f"{seg_len:.4f}", "-vf", vf,
                      "-an", "-c:v", "libx264", "-preset", "fast", "-crf", "18", seg])
            fit += "  [rendered]"
        shown = seg_len if mode == "window" else avail
        clip_name = row["clip"].replace("/", "\\")
        if start_in > 0 or length is not None or mode == "window":
            clip_name += " [{:.2f}-{:.2f}]".format(start_in, start_in + shown)
        table.append("{0:<4} {1:>6.2f}s {2:>6.2f}s {3:<40} {4}".format(key, cursor, seg_len, clip_name, fit))
        segments.append(seg)
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
        summary.append("audio: voice + music {} dB (fade in {}s, fade out {}s); no game audio".format(db, fade_in, fade_out))
    else:
        summary.append("audio: voice only, no music")
    for a_start, src, onset, a_len in windows:
        if not has_audio(src):
            raise SystemExit(f"assemble: window clip {src} has no audio")
        inputs += ["-ss", f"{onset:.4f}", "-t", f"{a_len:.4f}", "-i", src]
        ms = int(round(a_start * 1000))
        filters.append("[{0}:a]afade=t=in:st=0:d=0.03,afade=t=out:st={1:.3f}:d={2},adelay={3}|{3}[w{0}]".format(
            idx, max(a_len - WINDOW_FADE, 0.0), WINDOW_FADE, ms))
        mix += f"[w{idx}]"
        idx += 1
    n_in = idx - 1
    if n_in == 0:
        raise SystemExit("assemble: nothing to mix (no voice, no music)")
    graph = ";".join(filters) + ";" + mix + "amix=inputs={}:normalize=0:duration=longest,atrim=0:{:.3f}[out]".format(n_in, total)
    out = os.path.join(project, "final", f"{tag}.mp4")
    run(FF + inputs + ["-filter_complex", graph, "-map", "0:v", "-map", "[out]", "-c:v", "copy", "-c:a", "aac",
                       "-b:a", "192k", "-movflags", "+faststart", out])
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
        i = 0
        for n in chunks(len(abs_words)):
            grp = abs_words[i:i + n]
            i += n
            n_chunks += 1
            end_chunk = grp[-1]["e"] + tail
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
