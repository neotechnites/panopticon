r"""Speak a brief's script lines as en-US-AndrewNeural +5% through the pinned edge-tts endpoint.

Runs ON THE PC (tools/content/voice.sh pushes it):

    python voice.py --check                                  # preflight only
    python voice.py <project dir> <brief.md> [tag] [--force]

The voice, rate and endpoint are constants: no brief, header or flag changes them and
no other engine exists. A preflight synth runs first; any failure stops with
"VOICE FAILED: <why>". Per row with text (not a beat): voice\<line>.wav, 48 kHz
stereo, silence trimmed, and its word timings (wav timebase) in voice\words.json.
A line is re-spoken only when its text changed (hash in voice\<line>.txt).
"""
import asyncio
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brief as brief_mod  # noqa: E402

VOICE = "en-US-AndrewNeural"
RATE = "+5%"
ENDPOINT = "wss://api.msedgeservices.com/tts/cognitiveservices/websocket/v1"
EDGE_TTS_VERSION = "7.2.8"
CHECK_TEXT = "Panopticon voice check."
TRIM = ("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,"
        "areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,areverse")
FF = ["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error"]


class VoiceFailed(SystemExit):
    def __init__(self, why):
        super().__init__("VOICE FAILED: %s" % why)


def dur(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return float(out) if out else 0.0


def lead_silence(mp3):
    """Seconds the trim removes from the front, so word offsets can follow."""
    p = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-i", mp3, "-af", "silencedetect=n=-45dB:d=0.05",
                        "-f", "null", "-"], capture_output=True, text=True)
    m = re.search(r"silence_start: (-?[\d.]+)\s*\n.*?silence_end: ([\d.]+)", p.stderr, re.S)
    return float(m.group(2)) if m and float(m.group(1)) <= 0.01 else 0.0


def pin_endpoint():
    """edge-tts at the pinned version, pointed at the pinned endpoint; anything else stops."""
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
    return edge_tts


async def speak(text, mp3):
    edge_tts = pin_endpoint()
    words = []
    com = edge_tts.Communicate(text, VOICE, rate=RATE, boundary="WordBoundary")
    try:
        with open(mp3, "wb") as f:
            async for chunk in com.stream():
                if chunk["type"] == "audio":
                    f.write(chunk["data"])
                elif chunk["type"] == "WordBoundary":
                    words.append({"word": chunk["text"], "t": chunk["offset"] / 1e7, "dur": chunk["duration"] / 1e7})
    except Exception as e:  # noqa: BLE001 -- every failure is loud, none is substituted
        raise VoiceFailed("%s (%s)" % (type(e).__name__, str(e)[:200]))
    if not os.path.exists(mp3) or os.path.getsize(mp3) == 0:
        raise VoiceFailed("no audio for: %s" % text[:60])
    if not words:
        raise VoiceFailed("no word timings for: %s" % text[:60])
    if "Andrew" not in com.tts_config.voice:
        raise VoiceFailed("voice not Andrew (%s)" % com.tts_config.voice)
    return words


def preflight():
    with tempfile.TemporaryDirectory() as d:
        mp3 = os.path.join(d, "check.mp3")
        words = asyncio.run(speak(CHECK_TEXT, mp3))
        length = dur(mp3)
        if not 0.8 <= length <= 3.0 or len(words) < 2:
            raise VoiceFailed("preflight: %.2f s, %d words" % (length, len(words)))
    print("voice preflight: %s %s, %.2f s, %d words" % (VOICE, RATE, length, len(words)))


def main():
    if sys.argv[1:] == ["--check"]:
        preflight()
        return 0
    args = [a for a in sys.argv[1:] if a != "--force"]
    force = "--force" in sys.argv[1:]
    project, brief_path = args[0], args[1]
    tag = args[2] if len(args) > 2 else ""
    parsed = brief_mod.parse(brief_path)
    script = parsed["scripts"].get(tag) or parsed["script"]
    if not script:
        raise SystemExit("voice: the brief has no ## script section")
    named = script["head"].get("voice", "").split()
    if named and named[:2] != [VOICE, RATE][:len(named)]:
        raise VoiceFailed("the script names voice %s; the only voice is %s %s" % (" ".join(named), VOICE, RATE))
    rows = brief_mod.voice_rows(script)
    if not rows:
        print("voice: no voice lines")
        return 0
    preflight()
    vdir = os.path.join(project, "voice")
    os.makedirs(vdir, exist_ok=True)
    words_path = os.path.join(vdir, "words.json")
    words_all = {}
    if os.path.exists(words_path):
        with open(words_path, encoding="utf-8") as f:
            words_all = json.load(f)
    spoken = kept = 0
    for row in rows:
        key, text = row["line"], row["text"]
        stamp = hashlib.sha1(f"{VOICE}|{RATE}|{text}".encode("utf-8")).hexdigest()
        mp3, wav, tag_path = (os.path.join(vdir, key + ext) for ext in (".mp3", ".wav", ".txt"))
        if not force and os.path.exists(wav) and key in words_all and os.path.exists(tag_path):
            with open(tag_path, encoding="utf-8") as f:
                if f.read().strip() == stamp:
                    kept += 1
                    continue
        words = asyncio.run(speak(text, mp3))
        lead = lead_silence(mp3)
        subprocess.run(FF + ["-i", mp3, "-af", TRIM, "-ar", "48000", "-ac", "2", wav], check=True)
        length = dur(wav)
        for w in words:
            w["t"] = round(w["t"] - lead, 3)
            w["dur"] = round(w["dur"], 3)
        words_all[key] = {"file": wav, "dur": length, "lead_trimmed": lead, "voice": VOICE, "rate": RATE, "words": words}
        with open(tag_path, "w", encoding="utf-8") as f:
            f.write(stamp + "\n")
        spoken += 1
        print(f"{key:4s} {len(words):2d} words  {length:5.2f}s  {text[:60]}")
    with open(words_path, "w", encoding="utf-8") as f:
        json.dump(words_all, f, indent=1)
    print(f"voice: {spoken} spoken, {kept} unchanged; {VOICE} {RATE}; {words_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
