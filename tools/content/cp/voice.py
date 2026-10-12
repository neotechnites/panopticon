r"""Voice for a plan: Andrew at +5% through the pinned edge-tts endpoint, or Ryan's own takes.

    python -m cp.voice --check                         # preflight (G0 calls this first)
    python -m cp.voice <plan.json> --out <dir>         # voice\L#.wav, words.json, manifest.json
    python -m cp.voice <plan.json> --out <dir> --ryan <dir of L#.wav>

The voice, rate and endpoint are constants. Nothing in a spec or plan can change
them and no code path names another engine: a failure stops the build with
"VOICE FAILED: <reason>". Word timings come from edge-tts WordBoundary; if the
endpoint sends none, faster-whisper force-aligns the same Andrew wav against the
known text (alignment, not substitution). Times are seconds from the start of
the trimmed wav, so a line's length is its spoken length.
"""
import argparse
import asyncio
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time

VOICE = "en-US-AndrewNeural"
RATE = "+5%"
ENDPOINT = "wss://api.msedgeservices.com/tts/cognitiveservices/websocket/v1"
EDGE_TTS_VERSION = "7.2.8"
TOOL_VERSION = "1"
CHECK_TEXT = "Panopticon voice check."
TRIM = ("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,"
        "areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,areverse")
FF = ["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error"]


class VoiceFailed(SystemExit):
    def __init__(self, why):
        super().__init__("VOICE FAILED: %s" % why)


def _dur(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return float(out) if out else 0.0


def sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def write_prov(out, inputs, encoder, lossless, extra=None):
    """<out>.prov.json: what made this file (see schema/prov.json)."""
    body = {"inputs": [sha1(p) if os.path.exists(p) else p for p in inputs],
            "input_paths": [os.path.abspath(p) if os.path.exists(p) else p for p in inputs],
            "encoder": encoder, "lossless": bool(lossless), "tool": "cp.voice", "version": TOOL_VERSION,
            "sha1": sha1(out)}
    body.update(extra or {})
    with open(out + ".prov.json", "w", encoding="utf-8") as f:
        json.dump(body, f, indent=1)


def pin_endpoint():
    """Import edge-tts and point it at the pinned endpoint; anything else stops the build."""
    try:
        import edge_tts
        import edge_tts.communicate as comm
    except ImportError as e:
        raise VoiceFailed("edge-tts not installed (%s)" % e)
    if getattr(edge_tts, "__version__", "") != EDGE_TTS_VERSION:
        raise VoiceFailed("edge-tts %s, pinned %s" % (getattr(edge_tts, "__version__", "?"), EDGE_TTS_VERSION))
    url = "%s?Ocp-Apim-Subscription-Key=%s" % (ENDPOINT, edge_tts.constants.TRUSTED_CLIENT_TOKEN)
    comm.WSS_URL = url
    edge_tts.constants.WSS_URL = url
    if not comm.WSS_URL.startswith(ENDPOINT):
        raise VoiceFailed("edge-tts endpoint not the pinned one")
    return edge_tts


async def _speak(text, mp3):
    edge_tts = pin_endpoint()
    words, meta = [], {"voice": VOICE}
    com = edge_tts.Communicate(text, VOICE, rate=RATE, boundary="WordBoundary")
    try:
        with open(mp3, "wb") as f:
            async for chunk in com.stream():
                if chunk["type"] == "audio":
                    f.write(chunk["data"])
                elif chunk["type"] == "WordBoundary":
                    t0 = chunk["offset"] / 1e7
                    words.append({"w": chunk["text"], "t0": t0, "t1": t0 + chunk["duration"] / 1e7})
    except Exception as e:  # noqa: BLE001 -- every failure is loud, none is substituted
        status = getattr(e, "status", None) or getattr(e, "code", None) or type(e).__name__
        raise VoiceFailed("%s (%s)" % (status, str(e)[:200]))
    meta["voice_echo"] = com.tts_config.voice
    return words, meta


def speak(text, mp3):
    return asyncio.run(_speak(text, mp3))


def preflight():
    """Synthesise the check line and assert the four things the design names."""
    with tempfile.TemporaryDirectory() as d:
        mp3 = os.path.join(d, "check.mp3")
        words, meta = speak(CHECK_TEXT, mp3)
        size = os.path.getsize(mp3) if os.path.exists(mp3) else 0
        length = _dur(mp3) if size else 0.0
        why = []
        if size == 0:
            why.append("empty mp3")
        if not 0.8 <= length <= 3.0:
            why.append("duration %.2f s outside 0.8-3" % length)
        if len(words) < 2:
            why.append("%d WordBoundary events" % len(words))
        if VOICE.split("-")[-1].replace("Neural", "") not in meta.get("voice_echo", ""):
            why.append("voice not echoed (%s)" % meta.get("voice_echo"))
        if why:
            raise VoiceFailed("; ".join(why))
    return {"ok": True, "voice": VOICE, "rate": RATE, "endpoint": ENDPOINT, "dur": round(length, 3),
            "words": len(words)}


def _lead_silence(path):
    p = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-i", path, "-af", "silencedetect=n=-45dB:d=0.05",
                        "-f", "null", "-"], capture_output=True, text=True)
    m = re.search(r"silence_start: (-?[\d.]+)\s*\n.*?silence_end: ([\d.]+)", p.stderr, re.S)
    return float(m.group(2)) if m and float(m.group(1)) <= 0.01 else 0.0


def align(wav, text):
    """faster-whisper word timings for a wav whose text is known (Andrew fallback, Ryan's takes)."""
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        raise VoiceFailed("no WordBoundary events and faster-whisper is not installed to align %s" % wav)
    model = WhisperModel("small.en", device="cpu", compute_type="int8")
    import numpy as np
    raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", wav, "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
                         capture_output=True, check=True).stdout          # ffmpeg decodes: no PyAV version coupling
    segs, _ = model.transcribe(np.frombuffer(raw, np.float32), word_timestamps=True, initial_prompt=text,
                               language="en", beam_size=5)
    heard = [{"w": w.word.strip(), "t0": float(w.start), "t1": float(w.end)} for s in segs for w in s.words]
    known = text.split()
    if not heard:
        raise VoiceFailed("alignment found no words in %s" % wav)
    if len(heard) == len(known):
        for h, k in zip(heard, known):
            h["w"] = k
    return heard


def _norm(w):
    return re.sub(r"[^a-z0-9']", "", w.lower())


def lines_of(plan):
    out = []
    for ln in plan["lines"]:
        text = (ln.get("text") or "").strip()
        if text and text != "...":
            out.append((ln["id"], text))
    return out


def run(plan_path, out_dir, ryan=None, force=False):
    with open(plan_path, encoding="utf-8") as f:
        plan = json.load(f)
    vdir = os.path.join(out_dir, "voice")
    os.makedirs(vdir, exist_ok=True)
    man_path = os.path.join(vdir, "manifest.json")
    old = {}
    if os.path.exists(man_path):
        with open(man_path, encoding="utf-8") as f:
            old = json.load(f)
    engine = "ryan" if ryan else "edge-tts"
    manifest = {"engine": engine, "voice": "ryan" if ryan else VOICE, "rate": "1.0" if ryan else RATE,
                "endpoint": "" if ryan else ENDPOINT, "lines": {}}
    if not ryan:
        preflight()
    for lid, text in lines_of(plan):
        wav = os.path.join(vdir, lid + ".wav")
        stamp = hashlib.sha1(("%s|%s|%s|%s" % (engine, manifest["voice"], manifest["rate"], text)).encode()).hexdigest()
        prev = (old.get("lines") or {}).get(lid)
        if not force and prev and prev.get("stamp") == stamp and os.path.exists(wav) and old.get("engine") == engine:
            manifest["lines"][lid] = prev
            continue
        t = time.time()
        if ryan:
            from cp import vo_clean
            src = os.path.join(ryan, lid + ".wav")
            if not os.path.exists(src):
                raise SystemExit("voice: Ryan's take %s is missing" % src)
            vo_clean.clean(src, wav)
            words = align(wav, text)
            inputs, enc = [src], "vo_clean pcm_s24le"
        else:
            mp3 = os.path.join(vdir, lid + ".mp3")
            words, _ = speak(text, mp3)
            lead = _lead_silence(mp3)
            subprocess.run(FF + ["-i", mp3, "-af", TRIM, "-ar", "48000", "-ac", "2", "-c:a", "pcm_s24le", wav],
                           check=True)
            if words:
                words = [{"w": w["w"], "t0": round(max(0.0, w["t0"] - lead), 3), "t1": round(max(0.0, w["t1"] - lead), 3)}
                         for w in words]
            else:
                words = align(wav, text)
            inputs, enc = [mp3], "edge-tts mp3 -> pcm_s24le"
        length = _dur(wav)
        manifest["lines"][lid] = {"wav": os.path.relpath(wav, out_dir).replace("\\", "/"), "dur": round(length, 4),
                                  "words": words, "text": text, "stamp": stamp}
        write_prov(wav, inputs, enc, True, {"voice": manifest["voice"], "rate": manifest["rate"]})
        print("%-4s %2d words %5.2fs (%.1fs)  %s" % (lid, len(words), length, time.time() - t, text[:60]))
    with open(man_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    with open(os.path.join(vdir, "words.json"), "w", encoding="utf-8") as f:
        json.dump({k: v["words"] for k, v in manifest["lines"].items()}, f, indent=1)
    print("voice: %d lines, %s %s; %s" % (len(manifest["lines"]), manifest["voice"], manifest["rate"], man_path))
    return manifest


def gate_g13_manifest(manifest):
    """The voice half of G13: the manifest names Andrew +5% on the pinned endpoint, or Ryan's takes."""
    if manifest.get("engine") == "ryan":
        return True, "voice: Ryan's takes"
    ok = (manifest.get("engine") == "edge-tts" and manifest.get("voice") == VOICE and manifest.get("rate") == RATE
          and manifest.get("endpoint") == ENDPOINT)
    return ok, "voice %s %s %s" % (manifest.get("voice"), manifest.get("rate"),
                                   "pinned endpoint" if manifest.get("endpoint") == ENDPOINT else "WRONG endpoint")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("plan", nargs="?")
    ap.add_argument("--out")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--ryan")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args(argv)
    if a.check:
        print(json.dumps(preflight()))
        return 0
    if not a.plan or not a.out:
        ap.error("plan and --out are required")
    run(a.plan, a.out, a.ryan, a.force)
    return 0


if __name__ == "__main__":
    sys.exit(main())
