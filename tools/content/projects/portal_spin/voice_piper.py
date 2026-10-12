r"""Placeholder voice when edge-tts is refused (403, 2026-10-12): piper speaks, faster-whisper times the words.

    python voice_piper.py speak <project> <brief.md> <voice.onnx>   # Mac: voice\<line>.wav, 48 kHz stereo, trimmed
    python voice_piper.py align <project> <brief.md>                # PC: voice\words.json in voice.py's format
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "pc"))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
import brief as brief_mod  # noqa: E402

TRIM = ("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,"
        "areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,areverse")


def rows(brief):
    return [(r["line"], r["text"]) for r in brief_mod.voice_rows(brief_mod.parse(brief)["script"])]


def dur(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return float(out)


def speak(project, brief, model):
    vdir = os.path.join(project, "voice")
    os.makedirs(vdir, exist_ok=True)
    for key, text in rows(brief):
        raw = os.path.join(vdir, key + "_raw.wav")
        subprocess.run(["piper", "-m", model, "-f", raw, "--length-scale", "0.92"], input=text.encode(), check=True,
                       capture_output=True)
        wav = os.path.join(vdir, key + ".wav")
        subprocess.run(["ffmpeg", "-nostdin", "-y", "-loglevel", "error", "-i", raw, "-af", TRIM, "-ar", "48000",
                        "-ac", "2", wav], check=True)
        os.remove(raw)
        print("%-4s %5.2fs  %s" % (key, dur(wav), text[:60]))


def align(project, brief):
    from faster_whisper import WhisperModel
    model = WhisperModel("small.en", device="cpu", compute_type="int8", cpu_threads=4)
    out = {}
    for key, text in rows(brief):
        wav = os.path.join(project, "voice", key + ".wav")
        segs, _ = model.transcribe(wav, word_timestamps=True, initial_prompt=text, language="en")
        heard = [w for s in segs for w in s.words]
        said = text.split()
        length = dur(wav)
        words = []
        if len(heard) == len(said):
            for w, h in zip(said, heard):
                words.append({"word": w, "t": round(h.start, 3), "dur": round(h.end - h.start, 3)})
        else:  # counts differ: spread the script's words over the speech by letters
            span = (heard[0].start, heard[-1].end) if heard else (0.0, length)
            letters = [len(re.sub(r"\W", "", w)) + 1 for w in said]
            t = span[0]
            for w, n in zip(said, letters):
                d = (span[1] - span[0]) * n / sum(letters)
                words.append({"word": w, "t": round(t, 3), "dur": round(d, 3)})
                t += d
        out[key] = {"file": wav, "dur": length, "lead_trimmed": 0.0, "voice": "piper en_US-ryan-high",
                    "rate": "0.92", "words": words}
        print("%-4s %5.2fs  heard %d said %d" % (key, length, len(heard), len(said)))
    with open(os.path.join(project, "voice", "words.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)


if __name__ == "__main__":
    if sys.argv[1] == "speak":
        speak(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        align(sys.argv[2], sys.argv[3])
