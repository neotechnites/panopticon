r"""Ryan's voice chain (decision 357): "make it a stable volume, cut the ends for the keyboard
sound, and cut my breaths. That's it."

    python -m cp.vo_clean <in.wav> <out.wav>

1. Ends: the take is cut to its first and last run of speech (>= 0.25 s above -38 dBFS
   RMS in 10 ms frames), with 0.08 s kept either side, so the key press that starts and
   stops a recording is gone. A click is short; speech is not.
2. Breaths: quiet runs between speech (-55 to -30 dBFS, 0.12-0.9 s, louder than the
   room tone) are turned down 18 dB with 15 ms ramps; nothing is cut, so timing holds.
3. Level: gentle compression, then two-pass loudnorm to -16 LUFS / -1.5 dBTP.
Deterministic: the same take always gives the same wav. Output pcm_s24le 48 kHz stereo.
"""
import json
import os
import re
import subprocess
import sys

FF = ["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error"]
SR = 16000
HOP = 160                       # 10 ms
SPEECH_DB = -38.0
SPEECH_MIN_S = 0.25
EDGE_KEEP_S = 0.08
BREATH_DB = (-55.0, -30.0)
BREATH_S = (0.12, 0.9)
BREATH_CUT_DB = 18.0
TARGET_LUFS, TARGET_TP = -16.0, -1.5


def _pcm(path):
    import numpy as np
    raw = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1",
                          "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def _frames_db(x):
    import numpy as np
    n = len(x) // HOP
    fr = x[:n * HOP].reshape(n, HOP)
    rms = np.sqrt((fr * fr).mean(axis=1) + 1e-12)
    return 20 * np.log10(rms)


def _runs(mask):
    runs, start = [], None
    for i, m in enumerate(list(mask) + [False]):
        if m and start is None:
            start = i
        elif not m and start is not None:
            runs.append((start, i))
            start = None
    return runs


def analyse(path):
    """-> (t_in, t_out, breaths[(t0, t1)]) in seconds of the source take."""
    import numpy as np
    db = _frames_db(_pcm(path))
    hop_s = HOP / SR
    speech = [r for r in _runs(db > SPEECH_DB) if (r[1] - r[0]) * hop_s >= SPEECH_MIN_S]
    if not speech:
        raise SystemExit("vo_clean: no speech found in %s" % path)
    t_in = max(0.0, speech[0][0] * hop_s - EDGE_KEEP_S)
    t_out = min(len(db) * hop_s, speech[-1][1] * hop_s + EDGE_KEEP_S)
    floor = float(np.percentile(db, 10))
    breaths = []
    for (a0, a1), (b0, b1) in zip(speech, speech[1:]):
        gap = db[a1:b0]
        mask = (gap > max(BREATH_DB[0], floor + 6)) & (gap < BREATH_DB[1])
        for r0, r1 in _runs(mask):
            d = (r1 - r0) * hop_s
            if BREATH_S[0] <= d <= BREATH_S[1]:
                breaths.append(((a1 + r0) * hop_s, (a1 + r1) * hop_s))
    return t_in, t_out, breaths


def _breath_filter(breaths, t_in):
    if not breaths:
        return "anull"
    g = 10 ** (-BREATH_CUT_DB / 20)
    terms = []
    for b0, b1 in breaths:
        b0, b1 = b0 - t_in, b1 - t_in
        r = 0.015
        # 1 outside, g inside, linear 15 ms ramps at both ends
        terms.append("if(between(t,%.4f,%.4f),%.5f+(1-%.5f)*max(0,max((%.4f-t)/%.3f,(t-%.4f)/%.3f)),1)"
                     % (b0 - r, b1 + r, g, g, b0 + r, 2 * r, b1 - r, 2 * r))
    expr = "*".join("min(1,%s)" % t for t in terms)
    return "volume=volume='%s':eval=frame" % expr


def clean(src, out):
    t_in, t_out, breaths = analyse(src)
    chain = ["atrim=start=%.4f:end=%.4f" % (t_in, t_out), "asetpts=PTS-STARTPTS", _breath_filter(breaths, t_in),
             "acompressor=threshold=-24dB:ratio=3:attack=8:release=120:makeup=2"]
    pre = ",".join(chain)
    meas = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-i", src, "-af",
                           pre + ",loudnorm=I=%s:TP=%s:LRA=7:print_format=json" % (TARGET_LUFS, TARGET_TP),
                           "-f", "null", "-"], capture_output=True, text=True)
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", meas.stderr, re.S)
    if not m:
        raise SystemExit("vo_clean: loudnorm measure failed on %s" % src)
    j = json.loads(m.group(0))
    ln = ("loudnorm=I=%s:TP=%s:LRA=7:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:"
          "offset=%s:linear=true" % (TARGET_LUFS, TARGET_TP, j["input_i"], j["input_tp"], j["input_lra"],
                                     j["input_thresh"], j["target_offset"]))
    subprocess.run(FF + ["-i", src, "-af", pre + "," + ln + ",aresample=48000", "-ac", "2", "-c:a", "pcm_s24le",
                         out], check=True)
    return {"in": round(t_in, 3), "out": round(t_out, 3), "breaths": len(breaths)}


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: python -m cp.vo_clean <in.wav> <out.wav>")
    print(json.dumps(clean(sys.argv[1], sys.argv[2])))
