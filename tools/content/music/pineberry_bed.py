"""Pineberry Rush trailer bed: drop-section melody stem, the master's drum bar, the drop on the title, melody stem alone from the beat at the final title card."""
import subprocess, sys, numpy as np
SR = 48000
BAR = 4 * 0.3483
DROP_SONG = 19.2866         # song time under the title hit in v27-v42 (bass onset)
TITLE_T = 5.703             # trailer time of the title hit
END_TITLE_T = 43.033        # trailer time the final title card appears
BEAT = 0.3483
TAIL_NOTE_SONG = 56.290     # melody note onset nearest the final title card (0.33 s before it)
def load(f):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', f, '-ac', '2', '-ar', str(SR), '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2)
def main(src_dir, length, out, intro='melody'):
    mix = load(f'{src_dir}/01. Pineberry Rush.wav'); mel = load(f'{src_dir}/PineberryRushMelody.wav')
    s = lambda t: int(round(t * SR))
    song = lambda t: DROP_SONG + (t - TITLE_T)          # song time under trailer time t after the drop
    mel_len = TITLE_T - BAR                             # melody until the drum bar
    intro_end = DROP_SONG + 30 * BAR                    # drop-section melody ending on a bar line
    if intro == 'melody':                               # drop-section melody stem before the drum bar
        intro = mel[s(intro_end - mel_len):s(intro_end)].copy()
        fi = s(0.1); intro[:fi] *= np.linspace(0, 1, fi)[:, None]
    else:                                               # the song itself from song time `intro`, starting before the picture
        intro = mix[s(float(intro)):s(DROP_SONG - BAR)]
    tail_t = TITLE_T + (TAIL_NOTE_SONG - DROP_SONG)     # the melody's note at the final title card
    body = mix[s(DROP_SONG - BAR):s(song(tail_t))]      # the drum bar, the drop, on to that beat
    tail = mel[s(song(tail_t)):s(song(length))]
    xf = s(0.01); buf = intro
    for p in (body, tail):
        r = np.linspace(0, 1, xf)[:, None]
        buf = np.concatenate([buf[:-xf], buf[-xf:] * (1 - r) + p[:xf] * r, p[xf:]])
    lead = len(intro) / SR - (TITLE_T - BAR)            # audio before the picture starts (0 for the melody intro)
    buf = buf[:s(length + lead)] * 10 ** (-0.5 / 20)
    fo = s(2.5); buf[-fo:] *= np.linspace(1, 0, fo)[:, None]
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', '-', out], input=buf.astype(np.float32).tobytes(), check=True)
    print(f'lead {lead:.3f} s; melody {intro_end - mel_len:.3f}-{intro_end:.3f}, drum bar {DROP_SONG - BAR:.3f}, drop at {TITLE_T}, melody alone from beat {tail_t:.3f} (song {song(tail_t):.3f})')
if __name__ == '__main__':
    main(sys.argv[1], float(sys.argv[2]), sys.argv[3], *sys.argv[4:5])
