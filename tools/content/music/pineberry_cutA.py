"""Trailer cut A bed: 16 beats of drums intro, the full mix from bar 14 (the drop) for 96 beats, the melody stem from bar 38 fading to silence."""
import subprocess, sys, numpy as np
SR = 48000
BEAT = 60 / 174; BAR = 4 * BEAT        # bar lines at n * BAR from the file start; the drop is bar 14
GAIN_DB = -0.5                          # v42's level against the master file
def load(f):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', f, '-ac', '2', '-ar', str(SR), '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2)
def main(src_dir, intro_wav, length, out):
    s = lambda t: int(round(t * SR))
    mix = load(f'{src_dir}/01. Pineberry Rush.wav'); mel = load(f'{src_dir}/PineberryRushMelody.wav'); intro = load(intro_wav)
    xf = s(0.01); n = s(length)
    # (source, source start, trailer start, trailer end); each part runs xf past its end into the next one's crossfade
    parts = [(intro, 0.0, 0.0, 16 * BEAT), (mix, 14 * BAR, 16 * BEAT, 112 * BEAT), (mel, 38 * BAR, 112 * BEAT, length)]
    buf = np.zeros((n + xf, 2), np.float32)
    for i, (src, a, t0, t1) in enumerate(parts):
        seg = src[s(a):s(a) + s(t1) - s(t0) + xf].copy()
        if i > 0: seg[:xf] *= np.linspace(0, 1, xf)[:, None]
        if i < len(parts) - 1: seg[-xf:] *= np.linspace(1, 0, xf)[:, None]
        buf[s(t0):s(t0) + len(seg)] += seg
    buf = buf[:n] * 10 ** (GAIN_DB / 20)
    fo = n - s(112 * BEAT); buf[-fo:] *= np.linspace(1, 0, fo)[:, None]   # melody fades over the end card to silence
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', '-', out], input=buf.tobytes(), check=True)
    print(f'drop at {16 * BEAT:.4f} s, melody from {112 * BEAT:.4f} s, {length:.4f} s')
if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4])
