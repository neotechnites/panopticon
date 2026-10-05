#!/usr/bin/env python3
"""Paints the rifle's placeholder side picture (rifle.ase slice rifle_side_albedo) from the public-domain photo
named in tools/modelling/weapons/rifle_n64_trace.py: sheared level, reduced, toned, shaded, palette-limited."""
import argparse, math, os, subprocess, sys, tempfile, urllib.request
import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(ROOT, "tools", "modelling", "weapons"))
import rifle_n64_trace as T  # noqa: E402

PHOTO = os.path.expanduser("~/Desktop/panopticon-renders/textures/photos/rifle/m1903a4_m84.jpg")
SHEET = os.path.join(ROOT, "weapons", "textures", "rifle.ase")
SLICE = "rifle_side_albedo"
ASEPRITE = os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/Aseprite/Aseprite.app/Contents/MacOS/aseprite")

SUPER = 4                   # photo samples per texel side
COLOURS = 32                # the palette
PAD = 2                     # texels each part's edge colour is carried into the background
GROUND = (22, 18, 16)       # the background past the padding
WOOD_RAMP = ((0.0, (30, 14, 8)), (0.35, (84, 42, 20)), (0.6, (128, 72, 34)), (1.0, (184, 122, 66)))
STEEL_RAMP = ((0.0, (8, 9, 12)), (0.3, (34, 37, 46)), (0.6, (78, 84, 98)), (1.0, (156, 162, 176)))
WOOD_SHADE = (1.14, 0.8)   # light on the top row of the wood, on its bottom row
TUBE_SHADE = (0.22, 0.62, 0.27, 0.15)  # a clean tube's floor, its highlight's lift, the highlight's place and width (0 top, 1 bottom)
RIM_LIFT = 0.3              # how much lighter a tube's mouth is painted
GRAIN = (0.07, 0.16, 11)    # wood grain painted in: the soft streaks' depth, the dark streaks' depth, texels a streak runs
BOLT_PATCH = ((202, 217), (55, 77), 17)  # the bolt handle painted out: photo x span, y span, columns right to copy wood from
BUTT_TAIL = ((17.0, 70.0, 130.0), (26.0, 69.5, 134.0), (44.0, 68.0, 131.0))   # the photo's butt behind the saw cut
INSET = 1.5                 # photo pixels shaved off every traced edge: the photo's own soft outline
WOOD, STEEL, TUBE = 1, 2, 3
EDGE_SKIP = {WOOD: (0.2, 0.9), TUBE: (0.14, 0.88)}   # depths a part's edge rows are read from: just inside the photo's outline


def photo():
    if not os.path.exists(PHOTO):
        os.makedirs(os.path.dirname(PHOTO), exist_ok=True)
        req = urllib.request.Request(T.SOURCE_URL, headers={"User-Agent": "panopticon-texture-tool/1.0"})
        with urllib.request.urlopen(req) as r, open(PHOTO, "wb") as f:
            f.write(r.read())
    im = np.asarray(Image.open(PHOTO).convert("RGB"), dtype=np.float64)
    (x0, x1), (y0, y1), dx = BOLT_PATCH
    im[y0:y1, x0:x1] = im[y0:y1, x0 + dx:x1 + dx]
    return im


def part(x, y):
    """(class, depth 0 top .. 1 bottom, keep white, top-to-bottom photo pixels) of photo pixel (x, y); class 0 off the gun."""
    for (xs, ys, _span) in T.MOUNTS:
        if xs[0] <= x <= xs[1] and ys[0] <= y <= ys[1]:
            return STEEL, 0.5, False, 0.0
    (tx0, tx1), (ty0, ty1) = T.TURRET[0], T.TURRET[1]
    if tx0 <= x <= tx1 and ty0 <= y <= ty1:
        return STEEL, 0.4, True, 0.0
    if T.SCOPE[0][0] - 9.0 <= x <= T.SCOPE[-1][0] + 1.0:
        top = T._ramp(x, [(r[0], r[1]) for r in T.SCOPE])
        bot = T._ramp(x, [(r[0], r[2]) for r in T.SCOPE])
        if top + INSET <= y <= bot - INSET:
            return TUBE, (y - top) / (bot - top), True, bot - top
    if T.BARREL[0][0] <= x <= T.MUZZLE_X + 0.5 and T.BARREL_PX[0] + INSET <= y <= T.BARREL_PX[1] - INSET:
        return TUBE, (y - T.BARREL_PX[0]) / (T.BARREL_PX[1] - T.BARREL_PX[0]), True, T.BARREL_PX[1] - T.BARREL_PX[0]
    (nx0, nx1), ntop, nbot = T.NOSE[0], T.NOSE[1], T.NOSE[2]
    if nx0 <= x <= nx1 and ntop + INSET <= y <= nbot - INSET:
        return STEEL, (y - ntop) / (nbot - ntop), False, 0.0
    rows = list(BUTT_TAIL) + [r[:3] for r in T.STOCK]
    if rows[0][0] <= x <= rows[-1][0]:
        top = T._ramp(x, [(r[0], r[1]) for r in rows])
        bot = T._ramp(x, [(r[0], r[2]) for r in rows])
        if T.ACTION[0][0] <= x <= T.ACTION[-1][0] and T._ramp(x, [(r[0], r[1]) for r in T.ACTION]) + INSET <= y < top:
            return STEEL, 0.5, False, 0.0
        if top + INSET <= y <= bot - 1.6 * INSET:
            return WOOD, min(max((y - top) / (bot - top), 0.0), 1.0), False, bot - top
    return 0, 0.0, False, 0.0


def sample(im, x, y):
    h, w, _ = im.shape
    x, y = min(max(x, 0.0), w - 1.001), min(max(y, 0.0), h - 1.001)
    i, j = int(x), int(y)
    fx, fy = x - i, y - j
    return (im[j, i] * (1 - fx) + im[j, i + 1] * fx) * (1 - fy) + (im[j + 1, i] * (1 - fx) + im[j + 1, i + 1] * fx) * fy


def reduce(im):
    """The picture at its own size: mean colour, class and depth of each texel's samples that lie on the gun."""
    w, h = T.PICTURE
    rgb, cls, depth = np.zeros((h, w, 3)), np.zeros((h, w), dtype=int), np.zeros((h, w))
    for r in range(h):
        for c in range(w):
            acc, votes, ds = [], {}, []
            for sy in range(SUPER):
                for sx in range(SUPER):
                    x = (c - 1.0 + (sx + 0.5) / SUPER) / T.REDUCE + T.PHOTO_ORIGIN[0]
                    y = (r + (sy + 0.5) / SUPER) / T.REDUCE + T.PHOTO_ORIGIN[1] + T.BORE[2] * (x - T.BORE[0])
                    k, d, keep_white, span = part(x, y)
                    if not k:
                        continue
                    lo, hi = EDGE_SKIP.get(k, (0.0, 1.0))
                    px = sample(im, x, y + (min(max(d, lo), hi) - d) * span)
                    if not keep_white and px.min() > 205.0:
                        continue
                    acc.append(px)
                    ds.append(d)
                    votes[k] = votes.get(k, 0) + 1
            if len(acc) * 2 >= SUPER * SUPER:
                rgb[r, c], depth[r, c] = np.mean(acc, axis=0), float(np.mean(ds))
                cls[r, c] = max(votes, key=votes.get)
    return rgb, cls, depth


def _hash(a, b):
    return ((a * 73856093) ^ (b * 19349663)) % 1009 / 1009.0


def grain(c, r):
    """Lengthwise streaks: each row drifts light and dark along the gun, and now and then runs a dark line."""
    soft, dark, run = GRAIN
    k, f = divmod(c + 3 * r, run)
    f = f / run
    drift = (_hash(k, r) * (1.0 - f) + _hash(k + 1, r) * f - 0.5) * 2.0 * soft
    return drift - (dark if _hash(k * 7 + 1, r * 3) > 0.86 and 0.1 < f < 0.9 else 0.0)


def rims():
    """1 on the picture columns of the scope's two mouths and the muzzle, where a lit rim is painted."""
    out = np.zeros((T.PICTURE[1], T.PICTURE[0]))
    for x in (T.SCOPE[0][0], T.SCOPE[-1][0], T.MUZZLE_X - 1.0):
        out[:, int(T.picture_px(x, 0.0)[0])] = 1.0
    return out


def ramp(v, stops):
    return np.array([T._ramp(v, [(s, col[k]) for s, col in stops]) for k in range(3)])


def tone(rgb, cls, depth, rim):
    """Each texel's photo luminance through its material's ramp, times the shading baked in for its depth."""
    out = np.zeros_like(rgb)
    lum = (rgb * (0.299, 0.587, 0.114)).sum(axis=2) / 255.0
    for r, c in zip(*np.nonzero(cls)):
        v, d = lum[r, c], depth[r, c]
        if cls[r, c] == WOOD:
            v = min(max((v - 0.2) * 1.9, 0.0), 1.0) ** 0.85 + grain(c, r)
            out[r, c] = ramp(min(max(v, 0.0), 1.0), WOOD_RAMP) * (WOOD_SHADE[0] + (WOOD_SHADE[1] - WOOD_SHADE[0]) * d ** 1.5)
        else:
            v = min(max((v - 0.10) * 1.05, 0.0), 1.0)
            if cls[r, c] == TUBE:
                floor, liftv, at, wide = TUBE_SHADE
                v = 0.5 * v + 0.5 * (floor + liftv * math.exp(-((d - at) / wide) ** 2) + 0.1 * math.exp(-((d - 0.84) / 0.08) ** 2))
                v += RIM_LIFT * rim[r, c]
            out[r, c] = ramp(v, STEEL_RAMP)
    return np.clip(out, 0, 255)


def cells(out, cls):
    """The small drawings for faces the side picture cannot reach."""
    def box(name):
        x, y, w, h = T.CELLS[name]
        cls[y:y + h, x:x + w] = WOOD if name == "wood" else STEEL
        return x, y, w, h
    x, y, w, h = box("butt")        # the butt plate: dark steel, chequered, a lit rim, two screws
    for j in range(h):
        for i in range(w):
            rim = i in (0, w - 1) or j in (0, h - 1)
            out[y + j, x + i] = (96, 100, 110) if rim else ((38, 40, 48) if (i + j) % 2 else (56, 59, 68))
    for j in (4, h - 5):
        out[y + j, x + w // 2 - 1:x + w // 2 + 1] = (132, 138, 150)
    x, y, w, h = box("steel")       # a steel bar: dark edges, one highlight line
    for j in range(h):
        v = (0.16, 0.34, 0.86, 0.52, 0.36, 0.26, 0.18, 0.1)[j * 8 // h]
        for i in range(w):
            out[y + j, x + i] = ramp(v * (0.92 if (i * 7 + j * 3) % 5 == 0 else 1.0), STEEL_RAMP)
    x, y, w, h = box("bore")        # the muzzle: a steel ring round a black bore
    for j in range(h):
        for i in range(w):
            rr = math.hypot(i - (w - 1) / 2.0, j - (h - 1) / 2.0) / (w / 2.0)
            out[y + j, x + i] = (4, 4, 5) if rr < 0.5 else ramp(0.62 - 0.3 * j / h, STEEL_RAMP)
    x, y, w, h = box("wood")        # end grain
    for j in range(h):
        for i in range(w):
            out[y + j, x + i] = ramp(0.3 + 0.12 * ((i * 5 + j * 3) % 4) / 3.0, WOOD_RAMP)
    x, y, w, h = box("knob")        # a turret cap: knurled rim, a slot across
    for j in range(h):
        for i in range(w):
            rr = math.hypot(i - (w - 1) / 2.0, j - (h - 1) / 2.0) / (w / 2.0)
            v = 0.5 if rr < 0.6 else (0.3 if (i + j) % 2 else 0.6)
            out[y + j, x + i] = ramp(0.12 if j in (h // 2 - 1, h // 2) and rr < 0.6 else v, STEEL_RAMP)


def pad(out, cls):
    """Carries each edge colour, and its class, PAD texels into the background, so no filter or mip pulls the ground in."""
    for _ in range(PAD):
        new, grown = out.copy(), cls.copy()
        for r, c in zip(*np.nonzero(cls == 0)):
            near = [(r + dr, c + dc) for dr in (-1, 0, 1) for dc in (-1, 0, 1)
                    if 0 <= r + dr < out.shape[0] and 0 <= c + dc < out.shape[1] and cls[r + dr, c + dc]]
            if near:
                new[r, c] = np.mean([out[p] for p in near], axis=0)
                grown[r, c] = cls[near[0]]
        out[:], cls[:] = new, grown
    out[cls == 0] = GROUND


def limit(out, cls):
    """Wood and steel each snapped to their own share of the palette, so neither tints the other."""
    for wood, n in ((True, COLOURS * 9 // 16), (False, COLOURS * 7 // 16 - 1)):
        at = np.nonzero((cls == WOOD) if wood else ((cls != WOOD) & (cls != 0)))
        strip = Image.fromarray(out[at].astype(np.uint8).reshape(1, -1, 3), "RGB")
        out[at] = np.asarray(strip.quantize(n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB"))[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", help="write the PNG here instead of placing it in rifle.ase")
    a = ap.parse_args()
    rgb, cls, depth = reduce(photo())
    out = tone(rgb, cls, depth, rims())
    cells(out, cls)
    pad(out, cls)
    limit(out, cls)
    im = Image.fromarray(out.astype(np.uint8), "RGB")
    png = a.out or os.path.join(tempfile.mkdtemp(), SLICE + ".png")
    im.save(png)
    prev = os.path.join(os.path.dirname(PHOTO), "preview", SLICE + "_8x.png")
    os.makedirs(os.path.dirname(prev), exist_ok=True)
    im.resize((im.width * 8, im.height * 8), Image.NEAREST).save(prev)
    print("%s (preview %s)" % (png, prev))
    if a.out:
        return
    names = subprocess.run([ASEPRITE, "-b", SHEET, "--script", os.path.join(HERE, "slice_bounds.lua")],
                           check=True, capture_output=True, text=True).stdout
    script = "place_slices.lua" if SLICE in names.split() else "add_slice.lua"
    subprocess.run([ASEPRITE, "-b", "--script-param", "sheet=" + SHEET, "--script-param", "pairs=%s=%s" % (SLICE, png),
                    "--script", os.path.join(HERE, script)], check=True, capture_output=True)
    print("%s placed in %s; run tools/textures/export_sheets.sh" % (SLICE, os.path.relpath(SHEET, ROOT)))


if __name__ == "__main__":
    main()
