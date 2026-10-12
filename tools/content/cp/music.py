r"""The cut's audio: voice at its line starts, an optional music bed under it, one master level.

Bed: -18 dB under the voice (PLAYBOOK: -16 was "maybe 20% quieter"), 1.0 s fade in,
1.5 s fade out, never looped, ducked a further 12 dB over keep-audio beats with
0.3 s ramps. Master: two-pass loudnorm to -14 LUFS, true peak -1.5 dBTP so the AAC
delivery stays under -1. Everything here is pcm_s24le 48 kHz stereo (lossless).
"""
import json
import os
import re
import subprocess

FF = ["ffmpeg", "-nostdin", "-hide_banner", "-y", "-loglevel", "error"]
BED_DB = -18.0
FADE_IN, FADE_OUT = 1.0, 1.5
DUCK_DB, DUCK_RAMP = 12.0, 0.3
TARGET_I, TARGET_TP, TARGET_LRA = -14.0, -1.5, 11.0
PCM = ["-ar", "48000", "-ac", "2", "-c:a", "pcm_s24le"]


def _run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("music: ffmpeg failed\n" + r.stderr[-2000:])
    return r


def voice_track(placements, total_s, out_wav):
    """placements: [(wav, start_s)] -> one wav of total_s with each voice line at its start."""
    if not placements:
        _run(FF + ["-f", "lavfi", "-t", "%.4f" % total_s, "-i", "anullsrc=r=48000:cl=stereo"] + PCM + [out_wav])
        return out_wav
    args, fc = list(FF), []
    for i, (wav, start) in enumerate(placements):
        args += ["-i", wav]
        ms = int(round(start * 1000))
        fc.append("[%d:a]aresample=48000,aformat=channel_layouts=stereo,adelay=%d|%d[v%d]" % (i, ms, ms, i))
    fc.append("".join("[v%d]" % i for i in range(len(placements))) +
              "amix=inputs=%d:normalize=0:duration=longest,apad=whole_dur=%.4f,atrim=duration=%.4f[a]"
              % (len(placements), total_s, total_s))
    _run(args + ["-filter_complex", ";".join(fc), "-map", "[a]"] + PCM + [out_wav])
    return out_wav


def bed(track, start_s, end_s, total_s, out_wav, offset_s=0.0, ducks=()):
    """The music bed from track[offset_s:] placed over [start_s, end_s) of the cut."""
    length = max(0.0, end_s - start_s)
    vol = "%s" % (10 ** (BED_DB / 20))
    expr = [vol]
    for d0, d1 in ducks:
        a, b = d0 - start_s, d1 - start_s
        g = 10 ** (-DUCK_DB / 20)
        expr.append("(1-(1-%.5f)*clip(min((t-%.4f)/%.3f,(%.4f-t)/%.3f),0,1))"
                    % (g, a - DUCK_RAMP, DUCK_RAMP, b + DUCK_RAMP, DUCK_RAMP))
    chain = ("atrim=start=%.4f:duration=%.4f,asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,"
             "volume='%s':eval=frame,afade=t=in:d=%.2f,afade=t=out:st=%.4f:d=%.2f,adelay=%d|%d,"
             "apad=whole_dur=%.4f,atrim=duration=%.4f"
             % (offset_s, length, "*".join(expr), FADE_IN, max(0.0, length - FADE_OUT), FADE_OUT,
                int(start_s * 1000), int(start_s * 1000), total_s, total_s))
    _run(FF + ["-i", track, "-af", chain] + PCM + [out_wav])
    return out_wav


def loudness(path):
    """(integrated LUFS, true peak dBTP) by ebur128."""
    r = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-i", path, "-vn", "-af", "ebur128=peak=true",
                        "-f", "null", "-"], capture_output=True, text=True)
    tail = r.stderr[r.stderr.rfind("Summary:"):]
    i = re.search(r"I:\s+(-?[\d.]+) LUFS", tail)
    tp = re.search(r"Peak:\s+(-?[\d.]+|-inf) dBFS", tail)
    if not i:
        raise SystemExit("music: ebur128 read nothing from %s" % path)
    return float(i.group(1)), (float(tp.group(1)) if tp and tp.group(1) != "-inf" else -99.0)


def master(inputs, out_wav):
    """Mix the stems (voice, bed, game sound) and bring the mix to -14 LUFS / -1.5 dBTP in two passes."""
    args = list(FF)
    for p in inputs:
        args += ["-i", p]
    mix = "".join("[%d:a]" % i for i in range(len(inputs))) + "amix=inputs=%d:normalize=0:duration=longest" % len(inputs)
    probe = ["ffmpeg", "-nostdin", "-hide_banner"] + args[len(FF):]
    meas = subprocess.run(probe + ["-filter_complex", mix + ",loudnorm=I=%s:TP=%s:LRA=%s:print_format=json"
                                       % (TARGET_I, TARGET_TP, TARGET_LRA), "-f", "null", "-"],
                          capture_output=True, text=True)
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", meas.stderr, re.S)
    if not m:
        raise SystemExit("music: loudnorm measure failed\n" + meas.stderr[-1500:])
    j = json.loads(m.group(0))
    ln = ("loudnorm=I=%s:TP=%s:LRA=%s:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:"
          "linear=true" % (TARGET_I, TARGET_TP, TARGET_LRA, j["input_i"], j["input_tp"], j["input_lra"],
                           j["input_thresh"], j["target_offset"]))
    _run(args + ["-filter_complex", mix + "," + ln + ",aresample=48000[a]", "-map", "[a]"] + PCM + [out_wav])
    return out_wav


def gate_g13(final_path, manifest, game_audio=False):
    """G13: Andrew +5% (or Ryan's wavs) per the manifest; -14 LUFS +-1; <= -1 dBTP; game audio off unless kept."""
    from cp.voice import gate_g13_manifest
    ok_v, why_v = gate_g13_manifest(manifest)
    i, tp = loudness(final_path)
    ok_l = abs(i - TARGET_I) <= 1.0 and tp <= -1.0
    return ok_v and ok_l, "%s; %.1f LUFS, %.1f dBTP%s" % (why_v, i, tp, "; game audio kept" if game_audio else "")
