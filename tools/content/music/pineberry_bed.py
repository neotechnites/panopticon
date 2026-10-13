"""Pineberry Rush trailer bed from Mejer's master + melody stem: hook (3 bars) -> the loud drum bar -> drop on the title -> melody tail under the end card."""
import subprocess, sys, numpy as np
SR = 48000
BEAT = 0.3483; BAR = 4 * BEAT
DROP_SONG = 19.311          # bass onset in the master
TITLE_T = 5.703             # trailer time of the title hit
END_CARD_T = 39.133         # trailer time of the end card downbeat
def load(f):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', f, '-ac', '2', '-ar', str(SR), '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2)
def main(src_dir, length, out):
    mix = load(f'{src_dir}/01. Pineberry Rush.wav'); mel = load(f'{src_dir}/PineberryRushMelody.wav')
    drums_in = DROP_SONG - BAR                           # the one loud drum bar
    hook_end = DROP_SONG - 10 * BAR                      # a bar line inside the melody build
    hook_start = hook_end - (TITLE_T - BAR)          # fills the time before the drum bars
    s = lambda t: int(round(t * SR))
    parts = [mix[s(hook_start):s(hook_end)]]
    body_len = END_CARD_T - (TITLE_T - BAR)
    parts.append(mix[s(drums_in):s(drums_in) + s(body_len)])
    tail_from = drums_in + body_len
    parts.append(mel[s(tail_from):s(tail_from) + s(length - END_CARD_T)])
    xf = s(0.01); out_buf = parts[0]
    for p in parts[1:]:
        ramp = np.linspace(0, 1, xf)[:, None]
        out_buf = np.concatenate([out_buf[:-xf], out_buf[-xf:] * (1 - ramp) + p[:xf] * ramp, p[xf:]])
    out_buf = out_buf[:s(length)] * 10 ** (-0.5 / 20)
    fo = s(2.5); out_buf[-fo:] *= np.linspace(1, 0, fo)[:, None]
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', '-', out], input=out_buf.astype(np.float32).tobytes(), check=True)
    print(f'hook {hook_start:.3f}-{hook_end:.3f}, drums from {drums_in:.3f}, drop at trailer {TITLE_T}, melody tail from song {tail_from:.3f}')
if __name__ == '__main__':
    main(sys.argv[1], float(sys.argv[2]), sys.argv[3])
