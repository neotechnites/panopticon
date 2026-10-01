r"""Two-pass loudnorm of a cut's audio, picture copied.

Runs ON THE PC:  python loudnorm.py <in.mp4> <out.mp4> [I=-14] [TP=-1]
"""
import json
import re
import subprocess
import sys

src, out = sys.argv[1], sys.argv[2]
I = sys.argv[3] if len(sys.argv) > 3 else "-14"
TP = sys.argv[4] if len(sys.argv) > 4 else "-1"
base = "loudnorm=I=%s:TP=%s:LRA=11" % (I, TP)
p = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", src, "-af", base + ":print_format=json", "-f", "null", "-"],
                   capture_output=True, text=True)
m = json.loads(re.search(r"\{[^{}]*\}", p.stderr[p.stderr.rindex("Parsed_loudnorm"):], re.S).group(0))
af = base + ":measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true" % (
    m["input_i"], m["input_tp"], m["input_lra"], m["input_thresh"], m["target_offset"])
subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-map", "0:v", "-map", "0:a", "-af", af,
                "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", out], check=True)
print("in I=%s TP=%s -> %s" % (m["input_i"], m["input_tp"], out))
