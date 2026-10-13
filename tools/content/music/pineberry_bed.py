"""Pineberry Rush trailer bed: melody stem alone before the drop, the master from the drop, melody stem alone from the final title card."""
import subprocess, sys, numpy as np
SR = 48000
BAR = 4 * 0.3483
DROP_SONG = 19.311          # bass onset in the master
TITLE_T = 5.703             # trailer time of the title hit
END_TITLE_T = 43.033        # trailer time the final title card appears
def load(f):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', f, '-ac', '2', '-ar', str(SR), '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2)
def main(src_dir, length, out):
    mix = load(f'{src_dir}/01. Pineberry Rush.wav'); mel = load(f'{src_dir}/PineberryRushMelody.wav')
    s = lambda t: int(round(t * SR))
    song = lambda t: DROP_SONG + (t - TITLE_T)          # song time under trailer time t after the drop
    intro_end = DROP_SONG + 26 * BAR + 4 * BAR          # 4 bars of the drop-section melody, ending on a bar line
    intro = mel[s(intro_end - TITLE_T):s(intro_end)].copy()
    fi = s(0.1); intro[:fi] *= np.linspace(0, 1, fi)[:, None]
    body = mix[s(DROP_SONG):s(song(END_TITLE_T))]
    tail = mel[s(song(END_TITLE_T)):s(song(length))]
    xf = s(0.01); buf = intro
    for p in (body, tail):
        r = np.linspace(0, 1, xf)[:, None]
        buf = np.concatenate([buf[:-xf], buf[-xf:] * (1 - r) + p[:xf] * r, p[xf:]])
    buf = buf[:s(length)] * 10 ** (-0.5 / 20)
    fo = s(2.5); buf[-fo:] *= np.linspace(1, 0, fo)[:, None]
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', '-', out], input=buf.astype(np.float32).tobytes(), check=True)
    print(f'intro melody {intro_end - TITLE_T:.3f}-{intro_end:.3f}, drop at {TITLE_T}, melody alone from {END_TITLE_T} (song {song(END_TITLE_T):.3f})')
if __name__ == '__main__':
    main(sys.argv[1], float(sys.argv[2]), sys.argv[3])
