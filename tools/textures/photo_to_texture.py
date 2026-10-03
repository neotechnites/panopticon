#!/usr/bin/env python3
"""Turns Ryan's photos into low-res textures; batch mode fills a home's alternate <home>_photo.ase sheet.
Never invents pixels: only crops, scales, tones and quantises the photo it is given. See docs/TEXTURES.md."""
import argparse, os, shutil, subprocess, sys, tempfile
from PIL import Image, ImageEnhance, ImageOps

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
PHOTOS = os.path.expanduser("~/Desktop/panopticon-renders/textures/photos")
ASEPRITE = os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/Aseprite/Aseprite.app/Contents/MacOS/aseprite")
PHOTO_EXT = (".jpg", ".jpeg", ".png", ".heic", ".heif", ".tif", ".tiff", ".webp")
HOMES = {   # live sheet (repo-relative), per-home defaults
    "forest": {"sheet": "maps/forest/textures/forest.ase", "size": 128, "tile": "blend",
               "alias": {"leaf": "forest_sun_albedo", "leaves": "forest_sun_albedo", "dirt": "forest_path_albedo"}},
    "prisoner": {"sheet": "characters/textures/prisoner.ase", "size": 64, "tile": None,
                 "alias": {"body": "prisoner2_albedo", "prisoner": "prisoner2_albedo"}},
}
BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def load_photo(path):
    if path.lower().endswith((".heic", ".heif")):
        tmp = os.path.join(tempfile.mkdtemp(), "photo.png")
        subprocess.run(["sips", "-s", "format", "png", path, "--out", tmp], check=True, capture_output=True)
        path = tmp
    return ImageOps.exif_transpose(Image.open(path)).convert("RGB")


def crop_square(im, crop):
    if crop:
        x, y, w, h = crop
        return im.crop((x, y, x + w, y + h))
    side = min(im.size)
    x, y = (im.width - side) // 2, (im.height - side) // 2
    return im.crop((x, y, x + side, y + side))


def seamless_blend(im):
    """Half-offset blend, one axis at a time: edges come from the photo's middle, so it wraps."""
    w, h = im.size
    for axis in (0, 1):
        n = w if axis == 0 else h
        ramp = Image.new("L", (n, 1))
        ramp.putdata([int(255 * (1 - abs(2 * (i + 0.5) / n - 1))) for i in range(n)])
        mask = ramp.resize((w, h)) if axis == 0 else ramp.transpose(Image.Transpose.ROTATE_90).resize((w, h))
        dx, dy = (w // 2, 0) if axis == 0 else (0, h // 2)
        shifted = Image.new("RGB", (w, h))
        shifted.paste(im, (dx - w if dx else 0, dy - h if dy else 0))
        shifted.paste(im, (dx, dy))
        im = Image.composite(im, shifted, mask)
    return im


def levels(im, cutoff):
    """Stretches luminance to full range (cutoff % clipped each end); keeps each pixel's colour offset."""
    lum = im.convert("L")
    lo, hi = _clip_points(lum, cutoff)
    k = 255.0 / max(1, hi - lo)
    px, lp = im.load(), lum.load()
    for y in range(im.height):
        for x in range(im.width):
            L = lp[x, y]
            d = (L - lo) * k - L
            px[x, y] = tuple(max(0, min(255, int(c + d + 0.5))) for c in px[x, y])
    return im


def _clip_points(lum, cutoff):
    hist, n = lum.histogram(), lum.width * lum.height * cutoff / 100.0
    lo = hi = acc = 0
    for i, c in enumerate(hist):
        acc += c
        if acc > n:
            lo = i
            break
    acc = 0
    for i in range(255, -1, -1):
        acc += hist[i]
        if acc > n:
            hi = i
            break
    return lo, hi


def read_palette(path):
    """Colours from a JASC/GIMP .pal/.gpl, a .png, or an .ase (via Aseprite)."""
    if path.lower().endswith((".pal", ".gpl")):
        cols = []
        for line in open(path):
            parts = line.split()
            if len(parts) >= 3 and all(p.isdigit() for p in parts[:3]):
                cols.append(tuple(int(p) for p in parts[:3]))
        return cols
    if path.lower().endswith(".ase"):
        tmp = os.path.join(tempfile.mkdtemp(), "sheet.png")
        subprocess.run([ASEPRITE, "-b", path, "--save-as", tmp], check=True, capture_output=True)
        path = tmp
    im = Image.open(path).convert("RGBA")
    return sorted({c[:3] for _n, c in im.getcolors(1 << 24) if c[3] > 0})


def quantise(im, palette, dither):
    px, out = im.load(), Image.new("RGB", im.size)
    opx, cache = out.load(), {}
    for y in range(im.height):
        for x in range(im.width):
            r, g, b = px[x, y]
            if dither:
                d = (BAYER4[y % 4][x % 4] / 16.0 - 0.5) * 32
                r, g, b = (max(0, min(255, int(v + d))) for v in (r, g, b))
            key = (r, g, b)
            if key not in cache:
                cache[key] = min(palette, key=lambda c: (c[0] - r) ** 2 * 3 + (c[1] - g) ** 2 * 4 + (c[2] - b) ** 2 * 2)
            opx[x, y] = cache[key]
    return out


def convert(photo, a):
    im = load_photo(photo)
    if a.rotate:
        im = im.rotate(-a.rotate, expand=True)
    im = crop_square(im, a.crop)
    work = a.size * 8
    if a.tile == "mirror":
        half = im.resize((work // 2, work // 2), Image.LANCZOS)
        im = Image.new("RGB", (work, work))
        im.paste(half, (0, 0)); im.paste(ImageOps.mirror(half), (work // 2, 0))
        im.paste(ImageOps.flip(half), (0, work // 2)); im.paste(ImageOps.flip(ImageOps.mirror(half)), (work // 2, work // 2))
    else:
        im = im.resize((work, work), Image.LANCZOS)
        if a.tile == "blend":
            im = seamless_blend(im)
    im = im.reduce(8)   # box average over whole 8x8 cells: wraps exactly, no edge bleed
    if a.levels:   # stretch the photo's own darkest..brightest to full range (scaled photos go flat)
        im = levels(im, a.levels)
    if a.contrast != 1.0:
        im = ImageEnhance.Contrast(im).enhance(a.contrast)
    if a.gamma != 1.0:
        im = im.point([int(255 * (i / 255) ** (1 / a.gamma) + 0.5) for i in range(256)] * 3)
    if a.palette:
        im = quantise(im, read_palette(a.palette), a.dither)
    elif a.colors:
        im = im.quantize(a.colors, method=Image.Quantize.MEDIANCUT,
                         dither=Image.Dither.ORDERED if a.dither else Image.Dither.NONE).convert("RGB")
    return im


def write(im, out, preview_dir):
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    im.save(out)
    os.makedirs(preview_dir, exist_ok=True)
    prev = os.path.join(preview_dir, os.path.splitext(os.path.basename(out))[0] + "_8x.png")
    im.resize((im.width * 8, im.height * 8), Image.NEAREST).save(prev)
    print("%s -> %s (preview %s)" % (os.path.basename(out), out, prev))


def slice_bounds(sheet):
    out = subprocess.run([ASEPRITE, "-b", sheet, "--script", os.path.join(HERE, "slice_bounds.lua")],
                         check=True, capture_output=True, text=True).stdout
    return {p[0]: tuple(int(v) for v in p[1:5]) for p in (l.split() for l in out.splitlines()) if len(p) == 5}


def short_name(home, sl):
    """forest_grass_albedo -> grass: the photo stem Ryan uses."""
    n = sl[len(home) + 1:] if sl.startswith(home + "_") else sl
    return n[:-len("_albedo")] if n.endswith("_albedo") else n


def batch(a):
    cfg, home = HOMES[a.home], a.home
    live = os.path.join(ROOT, cfg["sheet"])
    stem = live[:-4]
    hand, alt = stem + "_hand.ase", stem + "_photo.ase"
    base = hand if os.path.exists(hand) else live   # photo variant live -> hand-drawn is in _hand.ase
    folder = os.path.join(PHOTOS, home)
    bounds = slice_bounds(base)
    by_stem = {}
    for sl in bounds:
        by_stem[sl], by_stem[short_name(home, sl)] = sl, sl
    for stem_, sl in cfg["alias"].items():
        if sl in bounds:
            by_stem.setdefault(stem_, sl)
    pairs, unmatched, tmp = [], [], tempfile.mkdtemp()
    for f in sorted(os.listdir(folder)):
        if not f.lower().endswith(PHOTO_EXT):
            continue
        key = os.path.splitext(f)[0].lower()
        hits = [s for s in bounds if key in s]
        sl = by_stem.get(key) or (hits[0] if len(hits) == 1 else None)   # else unique slice containing it
        if not sl:
            unmatched.append(f)
            continue
        w, h = bounds[sl][2:]
        im = convert(os.path.join(folder, f), argparse.Namespace(**dict(vars(a), size=min(a.size, w, h))))
        write(im, os.path.join(folder, "out", sl + ".png"), os.path.join(folder, "preview"))
        if w % im.width or h % im.height:
            print("note: %s is %dx%d, not a multiple of %d; scaled nearest anyway" % (sl, w, h, im.width))
        big = im.resize((w, h), Image.NEAREST)   # smaller than the slice: chunkier pixels, same UVs and density
        path = os.path.join(tmp, sl + ".png")
        big.save(path)
        pairs.append("%s=%s" % (sl, path))
    shutil.copyfile(base, alt)
    if pairs:
        subprocess.run([ASEPRITE, "-b", "--script-param", "sheet=" + alt, "--script-param", "pairs=" + ";".join(pairs),
                        "--script", os.path.join(HERE, "place_slices.lua")], check=True, capture_output=True)
    if os.path.exists(hand):   # photo variant is the live one: keep it current
        shutil.copyfile(alt, live)
        print("photo sheet is live: copied into %s; run tools/textures/export_sheets.sh" % cfg["sheet"])
    print("%d photo(s) placed into %s" % (len(pairs), os.path.relpath(alt, ROOT)))
    if unmatched:
        print("UNMATCHED (rename to a slice name): " + ", ".join(unmatched))
        print("slice names: " + ", ".join(short_name(home, s) for s in bounds) +
              " (also: " + ", ".join(sorted(cfg["alias"])) + ")")


def write_palette(home):
    """tools/textures/palettes/<home>.pal (JASC, Aseprite-readable) from the live sheet's colours."""
    cols = read_palette(os.path.join(ROOT, HOMES[home]["sheet"]))
    out = os.path.join(HERE, "palettes", home + ".pal")
    with open(out, "w", newline="\n") as fh:
        fh.write("JASC-PAL\n0100\n%d\n" % len(cols) + "".join("%d %d %d\n" % c for c in cols))
    print("%d colours -> %s" % (len(cols), os.path.relpath(out, ROOT)))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    one = sub.add_parser("one", help="convert one photo")
    one.add_argument("photo")
    one.add_argument("-o", "--out", help="output PNG (default: photos/<home>/out/<stem>.png)")
    pal = sub.add_parser("palette", help="rewrite palettes/<home>.pal from the live sheet")
    pal.add_argument("home", choices=sorted(HOMES))
    bat = sub.add_parser("batch", help="every photo in photos/<home>/ into <home>_photo.ase")
    for p in (one, bat):
        if p is bat:
            p.add_argument("home", choices=sorted(HOMES))
        else:
            p.add_argument("--home", choices=sorted(HOMES), help="use this home's defaults and palette")
        p.add_argument("--size", type=int, choices=(32, 64, 128, 256))
        p.add_argument("--crop", type=int, nargs=4, metavar=("X", "Y", "W", "H"))
        p.add_argument("--tile", choices=("blend", "mirror", "off"), help="seamless: half-offset blend or mirror")
        p.add_argument("--palette", help=".pal/.gpl/.png/.ase to lock colours to (default: the home's)")
        p.add_argument("--colors", type=int, help="auto palette of N colours (median cut) instead")
        p.add_argument("--dither", action="store_true", help="ordered (Bayer) dither when quantising")
        p.add_argument("--levels", type=float, default=1.0, help="auto-levels clip %% each end, 0 = off (default 1)")
        p.add_argument("--contrast", type=float, default=0.7, help="<1 pulls toward mid-tones (default 0.7)")
        p.add_argument("--gamma", type=float, default=1.0)
        p.add_argument("--rotate", type=float, default=0.0, help="degrees clockwise")
    a = ap.parse_args()
    if a.cmd == "palette":
        return write_palette(a.home)
    cfg = HOMES.get(a.home or "", {"size": 64, "tile": None})
    a.size = a.size or cfg["size"]
    a.tile = None if a.tile == "off" else (a.tile or cfg["tile"])
    if a.home and not a.palette and not a.colors:
        a.palette = os.path.join(HERE, "palettes", a.home + ".pal")
    if a.cmd == "batch":
        batch(a)
    else:
        folder = os.path.join(PHOTOS, a.home or "misc")
        stem = os.path.splitext(os.path.basename(a.photo))[0]
        write(convert(a.photo, a), a.out or os.path.join(folder, "out", stem + ".png"), os.path.join(folder, "preview"))


if __name__ == "__main__":
    sys.exit(main())
