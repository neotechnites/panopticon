"""The N64 soft chain forest and hell got (texture_log 18-24, 100-102), run once from <dir>/raw/ (the recolour) to the live PNGs:
usage n64_chain.py [--value-mul M] [--sat PULL,MUL] <textures dir> <stem>... ; per tile HSV value min..max -> 0.38..1.0, contrast -30% about 0.5, hue kept, 1 px gaussian wrapped, one 32-colour median cut shared across the set, no dither, RGBA kept."""
import os
import sys

import numpy as np
from PIL import Image

LO, HI = 0.38, 1.0      # the value stretch's black and white points
CONTRAST = 0.7          # -30% about 0.5
SIGMA = 1.0             # px, wrapped
NCOL = 32
SAMPLE = 16384          # pixels each tile weighs in the shared palette


def rgb_to_hsv(a):
    mx = a.max(-1)
    mn = a.min(-1)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-9), 0.0)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    dd = np.maximum(d, 1e-9)
    h = np.where(mx == r, ((g - b) / dd) % 6.0, np.where(mx == g, (b - r) / dd + 2.0, (r - g) / dd + 4.0))
    h = np.where(d > 0, h / 6.0, 0.0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6.0)
    f = h * 6.0 - i
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    i = i.astype(int) % 6
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], -1)


def blur_wrap(a, sigma):
    """Separable gaussian, wrapped on both axes (the tiles repeat)."""
    r = int(np.ceil(3 * sigma))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    out = a.copy()
    for axis in (0, 1):
        acc = np.zeros_like(out)
        for o, w in zip(range(-r, r + 1), k):
            acc += w * np.roll(out, o, axis=axis)
        out = acc
    return out


def chain(rgb, value_mul=1.0, sat=None):
    """rgb float 0..1 -> float 0..1 before the palette."""
    h, s, v = rgb_to_hsv(rgb)
    vmin, vmax = v.min(), v.max()
    v = LO + (v - vmin) / max(vmax - vmin, 1e-9) * (HI - LO)
    v = 0.5 + (v - 0.5) * CONTRAST
    v = np.clip(v * value_mul, 0.0, 1.0)
    if sat is not None:
        pull, mul = sat
        med = np.median(s)
        s = np.clip((med + (s - med) * (1.0 - pull)) * mul, 0.0, 1.0)
    return blur_wrap(hsv_to_rgb(h, s, v), SIGMA)


def main(argv):
    value_mul, sat = 1.0, None
    args = list(argv)
    while args and args[0].startswith("--"):
        flag = args.pop(0)
        if flag == "--value-mul":
            value_mul = float(args.pop(0))
        elif flag == "--sat":
            pull, mul = args.pop(0).split(",")
            sat = (float(pull), float(mul))
        else:
            sys.exit("unknown flag " + flag)
    if len(args) < 2:
        sys.exit(__doc__)
    root, stems = args[0], args[1:]
    raw = os.path.join(root, "raw")
    if not os.path.isdir(raw):
        sys.exit("%s is missing: the chain runs from the raw recolour, never from its own output" % raw)
    pre, alpha = {}, {}
    for stem in stems:
        im = Image.open(os.path.join(raw, stem + ".png")).convert("RGBA")
        a = np.asarray(im).astype(np.float64) / 255.0
        alpha[stem] = np.asarray(im)[..., 3]
        pre[stem] = np.clip(chain(a[..., :3], value_mul, sat), 0.0, 1.0)
    rng = np.random.RandomState(1)
    samples = []
    for stem in stems:
        px = (pre[stem] * 255 + 0.5).astype(np.uint8).reshape(-1, 3)
        samples.append(px[rng.randint(0, len(px), SAMPLE)])
    sheet = Image.fromarray(np.concatenate(samples)[:, None, :], "RGB")
    pal = sheet.quantize(NCOL, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    for stem in stems:
        im = Image.fromarray((pre[stem] * 255 + 0.5).astype(np.uint8), "RGB")
        q = im.quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")
        out = np.dstack([np.asarray(q), alpha[stem]])
        Image.fromarray(out, "RGBA").save(os.path.join(root, stem + ".png"))
        v = np.asarray(q).astype(float)
        l = 0.2126 * v[..., 0] + 0.7152 * v[..., 1] + 0.0722 * v[..., 2]
        print("%-32s %dx%d  luma mean %.1f std %.1f  p5/p95 %.0f/%.0f  colours %d" % (
            stem, q.width, q.height, l.mean(), l.std(), np.percentile(l, 5), np.percentile(l, 95),
            len(np.unique(np.asarray(q).reshape(-1, 3), axis=0))))
    print("palette: %d colours shared across %d tiles; value-mul %.2f; sat %s" % (NCOL, len(stems), value_mul, sat))


if __name__ == "__main__":
    main(sys.argv[1:])
