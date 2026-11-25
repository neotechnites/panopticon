"""Draws the aspens map's placeholder tiles into maps/aspens/textures/raw/, then the live PNGs beside it:
raw -> 1 px wrapped gaussian -> a 16-colour median cut per tile, its darkest entry the tile's own darkest (n64_chain's steps 4-5; values are not stretched, the colours are measured)."""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import n64_chain  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "maps", "aspens", "textures")
STEMS = ("aspens_grass_albedo", "aspens_bark_albedo", "aspens_leaf_albedo", "aspens_tuft_albedo", "aspens_wood_albedo")

# Measured from refs/Map 6 (docs/maps/aspens.md has the table). Bark and leaf are the photo's lit
# colours divided by the scene's lit factor, so the lit faces land on the photo on screen.
# Grass and leaf are mostly seen in the canopy's shade (x 0.88 linear): the measured colours x 1.06 undo it.
GRASS_OLIVE = ((135, 127, 49), (122, 116, 39), (143, 136, 58))      # frame0 grass top: median, p15, p85
GRASS_GREEN = ((90, 114, 48), (71, 89, 36))                         # frame0 green grass: lit, shaded
GRASS_TUFT = ((159, 152, 79), (179, 164, 73), (137, 128, 59))       # frame0 dry tufts
BARK = ((205, 198, 190), (190, 180, 169), (220, 214, 207))          # istock trunk: lit, shade, p80
BARK_MARK = ((47, 34, 23), (63, 50, 45), (120, 108, 97))            # istock knots: median, the big trunk's, a scar's edge
LEAF = ((240, 173, 7), (247, 212, 28), (199, 144, 23), (153, 109, 23), (89, 64, 18))   # istock canopy's five clusters ...
LEAF_SHARE = (0.34, 0.21, 0.24, 0.16, 0.05)                                           # ... and their shares
GRASS_TUFT_CARD = ((160, 145, 65), (144, 137, 71), (124, 116, 53))  # frame0 dry tufts, as seen (the cards are unshaded)
WOOD = ((200, 190, 175), (178, 165, 149), (63, 50, 45))             # the trunk's greys: face, growth ring, check


def _noise(rng, h, w, cell):
    """Wrapped value noise 0..1: a coarse random grid, bilinear up."""
    gh, gw = max(1, h // cell), max(1, w // cell)
    g = rng.rand(gh, gw)
    ys, xs = np.arange(h) * gh / h, np.arange(w) * gw / w
    y0, x0 = ys.astype(int), xs.astype(int)
    fy, fx = (ys - y0)[:, None], (xs - x0)[None, :]
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a, b = g[y0 % gh][:, x0 % gw], g[y0 % gh][:, (x0 + 1) % gw]
    c, d = g[(y0 + 1) % gh][:, x0 % gw], g[(y0 + 1) % gh][:, (x0 + 1) % gw]
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy


def _put(img, y, x, col):
    img[y % img.shape[0], x % img.shape[1]] = col


def grass(rng):
    n = 256
    img = np.zeros((n, n, 3), np.uint8)
    field = _noise(rng, n, n, 16) * 0.6 + _noise(rng, n, n, 5) * 0.4
    img[:] = GRASS_OLIVE[0]
    img[field < 0.42] = GRASS_OLIVE[1]
    img[field > 0.6] = GRASS_OLIVE[2]
    for _ in range(2600):                               # blades: short upright strokes
        y, x, ln = rng.randint(n), rng.randint(n), rng.randint(2, 5)
        col = (GRASS_OLIVE[1], GRASS_OLIVE[2], GRASS_GREEN[0], GRASS_GREEN[1])[rng.choice(4, p=(0.35, 0.3, 0.25, 0.1))]
        for k in range(ln):
            _put(img, y - k, x, col)
            _put(img, y - k, x + 1, col)
    for _ in range(60):                                 # dry tufts: a fan of pale strokes
        cy, cx = rng.randint(n), rng.randint(n)
        for _b in range(rng.randint(5, 10)):
            x, lean, ln = cx + rng.randint(-5, 6), rng.choice((-1, 0, 0, 1)), rng.randint(6, 13)
            col = GRASS_TUFT[rng.choice(3, p=(0.5, 0.3, 0.2))]
            for k in range(ln):
                _put(img, cy - k, x + (lean * k) // 3, col)
                _put(img, cy - k, x + 1 + (lean * k) // 3, col)
    return img


def bark(rng):
    h, w = 256, 32
    img = np.zeros((h, w, 3), np.uint8)
    band = (_noise(rng, h, 1, 3) * 0.65 + _noise(rng, h, 1, 11) * 0.35)[:, :1].repeat(w, 1)   # fine horizontal banding
    field = band * 0.75 + _noise(rng, h, w, 8) * 0.25
    img[:] = BARK[0]
    img[field < 0.4] = BARK[1]
    img[field > 0.64] = BARK[2]
    for _ in range(96):                                 # scars: thin dark lines across the trunk, drooping at the ends
        y, x, ln = rng.randint(h), rng.randint(w), rng.randint(4, 15)
        col = BARK_MARK[1] if rng.rand() < 0.55 else BARK_MARK[2]
        for k in range(ln):
            t = abs(k - ln / 2.0) / (ln / 2.0)
            _put(img, y + int(round(1.2 * t * t)), x + k, col)
    ys = np.linspace(10, h - 10, 8) + rng.randint(-10, 11, 8)
    for y in ys.astype(int):                            # eyes: a flat black lens, a brow over it, whiskers out both sides
        x, half = rng.randint(w), rng.randint(4, 8)
        for dx in range(-half, half + 1):
            t = abs(dx) / float(half)
            for dy in range(-int(round(1.0 * (1 - t * t))), int(round(1.2 * (1 - t))) + 1):
                _put(img, y + dy, x + dx, BARK_MARK[0])
        for dx in range(-half - 2, half + 3):           # the brow: an arch a little wider than the eye
            t = abs(dx) / float(half + 2)
            _put(img, y - 3 + int(round(3.0 * t * t)), x + dx, BARK_MARK[0] if t < 0.7 else BARK_MARK[1])
        for arm in (-1, 1):
            for k in range(1, rng.randint(3, 8)):
                _put(img, y + 1 + k // 3, x + arm * (half + 1 + k), BARK_MARK[1])
    return img


def _fill(img, alpha, col):
    """Colour under the cut-away texels, so the soft pass has no dark fringe."""
    img[alpha == 0] = col
    return np.dstack([img, alpha])


def leaf(rng):
    """Four leaf clusters, one per quarter: small round leaves thick in the middle, sky between them at the rim."""
    n, q = 128, 64
    img = np.zeros((n, n, 3), np.uint8)
    alpha = np.zeros((n, n), np.uint8)
    for cell in range(4):
        oy, ox = q * (cell // 2), q * (cell % 2)
        sy, sx = rng.uniform(15, 19), rng.uniform(17, 21)
        for _ in range(250):
            y, x = rng.normal(31.5, sy), rng.normal(31.5, sx)
            r = rng.choice((1, 2, 2))
            if not (r + 2 <= y < q - r - 2 and r + 2 <= x < q - r - 2):
                continue
            col = LEAF[rng.choice(5, p=LEAF_SHARE)]
            for dy in range(-r, r + 1):
                span = int(round((r * r - dy * dy) ** 0.5))
                for dx in range(-span, span + 1):
                    img[oy + int(y) + dy, ox + int(x) + dx] = col
                    alpha[oy + int(y) + dy, ox + int(x) + dx] = 255
    return _fill(img, alpha, LEAF[0])


def tuft(rng):
    """Four dry grass tufts, one per quarter: blades fanning up from the foot (v = 0 is the ground)."""
    n, q = 128, 64
    img = np.zeros((n, n, 3), np.uint8)
    alpha = np.zeros((n, n), np.uint8)
    for cell in range(4):
        oy, ox = q * (cell // 2), q * (cell % 2)
        for _ in range(rng.randint(15, 22)):
            x0 = 31.5 + rng.normal(0, 9)
            lean, ln = rng.normal(0, 0.32), rng.randint(22, 58)
            col = GRASS_TUFT_CARD[rng.choice(3, p=(0.45, 0.35, 0.2))]
            for k in range(ln):
                x = int(round(x0 + lean * k + 0.004 * lean * k * k))
                wide = 2 if k < ln * 0.6 else 1
                for dx in range(wide):
                    if 2 <= x + dx < q - 2 and k < q - 2:
                        img[oy + q - 1 - k, ox + x + dx] = col      # image row 63 of the quarter is the foot
                        alpha[oy + q - 1 - k, ox + x + dx] = 255
    return _fill(img, alpha, GRASS_TUFT_CARD[0])


def wood(rng):
    n = 128
    yy, xx = np.mgrid[0:n, 0:n]
    wob = _noise(rng, n, n, 16) * 5.0
    rad = np.hypot(yy - 63.5 + wob * 0.5, xx - 63.5 - wob * 0.5) + wob
    img = np.zeros((n, n, 3), np.uint8)
    img[:] = WOOD[0]
    img[(rad % 5.0) < 1.3] = WOOD[1]                    # growth rings, 0.25 m apart
    for a in rng.rand(7) * 2 * np.pi:                   # checks: radial cracks from near the pith
        r0, r1 = rng.randint(4, 14), rng.randint(26, 60)
        for r in range(r0, r1):
            _put(img, int(round(63.5 + r * np.sin(a))), int(round(63.5 + r * np.cos(a))), WOOD[2])
    return img


def main():
    raw = os.path.join(ROOT, "raw")
    os.makedirs(raw, exist_ok=True)
    tiles = {}
    for seed, (stem, draw) in enumerate(zip(STEMS, (grass, bark, leaf, tuft, wood))):
        tiles[stem] = draw(np.random.RandomState(8800 + seed))
        Image.fromarray(tiles[stem]).save(os.path.join(raw, stem + ".png"))
    open(os.path.join(raw, ".gdignore"), "w").close()
    soft = {s: np.clip(n64_chain.blur_wrap(t[..., :3].astype(np.float64) / 255.0, n64_chain.SIGMA), 0.0, 1.0) for s, t in tiles.items()}
    for stem in STEMS:
        im = Image.fromarray((soft[stem] * 255 + 0.5).astype(np.uint8), "RGB")
        pal = im.quantize(16, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        cols = np.array(pal.getpalette()[:48], np.uint8).reshape(16, 3)
        px = np.asarray(im).reshape(-1, 3)
        cols[cols.sum(1).argmin()] = px[px.sum(1).argmin()]      # median cut greys the darkest marks: keep the tile's own darkest
        pal.putpalette(cols.reshape(-1).tolist())
        q = im.quantize(palette=pal, dither=Image.Dither.NONE).convert("RGB")
        if tiles[stem].shape[2] == 4:                   # the cut is kept as drawn
            q = Image.fromarray(np.dstack([np.asarray(q), tiles[stem][..., 3]]), "RGBA")
        q.save(os.path.join(ROOT, stem + ".png"))
        print("%-22s %dx%d  mean rgb %s" % (stem, q.width, q.height, np.asarray(q.convert("RGB")).reshape(-1, 3).mean(0).round(1)))


if __name__ == "__main__":
    main()
