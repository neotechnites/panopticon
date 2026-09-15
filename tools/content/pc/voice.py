r"""Speak every line of a brief's ## script table with a Microsoft neural voice.

Runs ON THE PC (tools/content/voice.sh pushes it):

    python voice.py <project dir> <brief.md> [--force]

For each row with text: voice\<line>.mp3 from edge-tts (the voice and rate from
the script header's `voice:` line, default en-US-AndrewNeural +5%), then
voice\<line>.wav -- 48 kHz stereo with the leading and trailing silence trimmed
so a line's length is its spoken length -- and its word boundaries, converted
to the trimmed wav's timebase, merged into voice\words.json:

    {"l0": {"file": ..., "dur": 2.78, "lead_trimmed": 0.15,
            "words": [{"word": "I", "t": -0.04, "dur": 0.11}, ...]}, ...}

A line is only regenerated when its text, voice or rate changed: the hash of
those is kept in voice\<line>.txt, so a one-word edit to line 7 re-speaks line 7
and nothing else. --force re-speaks everything.
"""
import asyncio
import hashlib
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brief as brief_mod  # noqa: E402

TRIM = ("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,"
        "areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,areverse")
FF = ["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error"]


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


async def speak(text, voice, rate, mp3):
    import edge_tts
    words = []
    com = edge_tts.Communicate(text, voice, rate=rate, boundary="WordBoundary")
    with open(mp3, "wb") as f:
        async for chunk in com.stream():
            if chunk["type"] == "audio":
                f.write(chunk["data"])
            elif chunk["type"] == "WordBoundary":
                words.append({"word": chunk["text"], "t": chunk["offset"] / 1e7, "dur": chunk["duration"] / 1e7})
    return words


async def main():
    project = sys.argv[1]
    brief_path = sys.argv[2]
    force = "--force" in sys.argv[3:]
    parsed = brief_mod.parse(brief_path)
    script = parsed["script"]
    if not script:
        print("voice: the brief has no ## script section")
        return 2
    spec = script["head"].get("voice", "en-US-AndrewNeural +5%").split()
    voice = spec[0]
    rate = spec[1] if len(spec) > 1 else "+0%"
    vdir = os.path.join(project, "voice")
    os.makedirs(vdir, exist_ok=True)
    words_path = os.path.join(vdir, "words.json")
    words_all = {}
    if os.path.exists(words_path):
        with open(words_path, encoding="utf-8") as f:
            words_all = json.load(f)
    spoken = kept = 0
    for row in brief_mod.voice_rows(script):
        key = row["line"]
        text = row["text"]
        stamp = hashlib.sha1(f"{voice}|{rate}|{text}".encode("utf-8")).hexdigest()
        mp3 = os.path.join(vdir, f"{key}.mp3")
        wav = os.path.join(vdir, f"{key}.wav")
        tag = os.path.join(vdir, f"{key}.txt")
        if not force and os.path.exists(wav) and key in words_all and os.path.exists(tag):
            with open(tag, encoding="utf-8") as f:
                if f.read().strip() == stamp:
                    kept += 1
                    continue
        words = await speak(text, voice, rate, mp3)
        lead = lead_silence(mp3)
        subprocess.run(FF + ["-i", mp3, "-af", TRIM, "-ar", "48000", "-ac", "2", wav], check=True)
        length = dur(wav)
        for w in words:
            w["t"] = round(w["t"] - lead, 3)
            w["dur"] = round(w["dur"], 3)
        words_all[key] = {"file": wav, "dur": length, "lead_trimmed": lead, "voice": voice, "rate": rate, "words": words}
        with open(tag, "w", encoding="utf-8") as f:
            f.write(stamp + "\n")
        spoken += 1
        tail = length - (words[-1]["t"] + words[-1]["dur"]) if words else 0.0
        print(f"{key:4s} {len(words):2d} words  {length:5.2f}s  (lead trimmed {lead:.2f}s, tail {tail:+.2f}s)  {text[:52]}")
    with open(words_path, "w", encoding="utf-8") as f:
        json.dump(words_all, f, indent=1)
    print(f"voice: {spoken} spoken, {kept} unchanged; voice={voice} rate={rate}; {words_path}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
