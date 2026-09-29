"""
forest_tiles -- Map 3's eight texture files and how every forest model wears them.

Seven 64 px tiles of at most eight colours (grass, path, leaf, bark, fern, rock,
dark), tiling at texel.MPT like hell's and marble's sheets, and forest_ornament:
the lamp's glow | the portal's swirl, 64 px each, albedo and glow the same pixels.
A zone wears its tile times a per-corner COLOR_0 tint, so verge, edge, shade,
sun, root, earth and the rock's damp faces keep the mean colour their own file
had (OLD below) without a file of their own.

    dress(ob, zones, "atlas")                          # UVs, COLOR_0, materials, slots
    python3 tools/modelling/maps/forest/forest_tiles.py --write /tmp/tiles   # PNGs, no Blender
"""

import math
import os
import sys

try:
    import bpy
except ImportError:
    bpy = None

import texel as tx  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

LEAF_ZONES = ("leaf", "shade", "sun")  # zones soften() blends: the leaf tile's tints
SOFT_PASSES = 3                 # neighbour-average passes: the sun/shade step spreads over ~3 face rings
TILE = 64                       # texels a side: TILE * tx.MPT = 3.2 m before a tile repeats
SEED = 0x7E11

# Palettes: the bytes the files hold, sampled from the 256 px sheets they replace.
GRASS = ((36, 59, 12), (51, 67, 11), (66, 77, 12), (77, 87, 16), (31, 49, 10))
PATH = ((38, 32, 13), (43, 36, 16), (51, 47, 16), (57, 52, 18), (45, 56, 15))
LEAF = ((20, 29, 11), (24, 33, 11), (44, 66, 19), (58, 78, 22), (78, 98, 31), (60, 80, 24), (144, 155, 44))
BARK = ((28, 20, 12), (31, 23, 13), (35, 26, 16), (17, 13, 8), (44, 34, 20), (8, 6, 4), (23, 35, 12))
FERN = ((15, 27, 8), (17, 31, 9), (20, 37, 11), (38, 63, 17), (51, 78, 22), (9, 17, 6))
ROCK = ((43, 46, 36), (52, 55, 42), (60, 63, 47), (74, 76, 57), (31, 34, 27), (45, 54, 37), (21, 23, 18))
DARK = ((1, 1, 1), (2, 2, 1), (2, 3, 2), (9, 12, 6))
GLOW = ((59, 32, 9), (122, 71, 22), (16, 9, 3))
SWIRL = ((255, 235, 100), (87, 105, 26), (31, 45, 15), (8, 13, 5), (2, 3, 1))

SWIRL_ARMS = 3
SWIRL_TURNS = 2.6               # how many times an arm wraps from the rim to the core
SWIRL_WIDTH = 0.42              # share of an arm's band that is bright
SWIRL_CY = 1.5 / 3.15           # the disc's centre up the opening: portal DISC_CENTRE_Z / APEX_Z

HALF = 0.5 / TILE               # half a texel: a cell's UVs stay off its neighbour
GLOW_RECT = (HALF / 2.0, HALF, 0.5 - HALF / 2.0, 1.0 - HALF)   # the ornament's left half
SWIRL_RECT = (0.5 + HALF / 2.0, HALF, 1.0 - HALF / 2.0, 1.0 - HALF)

# key -> (image stem, glows, wears COLOR_0)
KEYS = {
    "grass": ("forest_grass_albedo", False, True),
    "path": ("forest_path_albedo", False, True),
    "leaf": ("forest_leaf_albedo", False, True),
    "bark": ("forest_bark_albedo", False, True),
    "fern": ("forest_fern_albedo", False, True),
    "rock": ("forest_rock_albedo", False, True),
    "dark": ("forest_dark_albedo", False, True),
    "lamp": ("forest_ornament_albedo", True, True),
    "swirl": ("forest_ornament_albedo", True, False),
}

# zone -> key, per family of models
_COMMON = {"grass": "grass", "verge": "grass", "edge": "grass", "path": "path", "earth": "path",
           "leaf": "leaf", "shade": "leaf", "sun": "leaf", "bark": "bark", "root": "bark",
           "fern": "fern", "cell": "dark", "lamp": "lamp", "swirl": "swirl"}
MAP = {"ground": _COMMON, "atlas": _COMMON,
       "rock": {"granite": "rock", "shade": "rock", "lichen": "rock", "moss": "rock"}}

# Linear mean albedo each zone had in its old file: forest_<zone>_albedo.png (ground),
# forest_atlas_albedo.png's zone cells (atlas), forest_rock_albedo.png's quadrants (rock).
OLD = {
    "ground": {"grass": (0.03539, 0.05588, 0.00368), "verge": (0.03599, 0.04725, 0.00379),
               "edge": (0.01244, 0.02245, 0.00309), "path": (0.02541, 0.02095, 0.00489),
               "earth": (0.00665, 0.00442, 0.00232), "leaf": (0.00731, 0.01338, 0.00289),
               "shade": (0.00443, 0.00929, 0.00277), "sun": (0.02938, 0.04793, 0.00522),
               "fern": (0.00645, 0.01596, 0.00296), "bark": (0.01191, 0.0084, 0.00421),
               "root": (0.01389, 0.00746, 0.00338), "cell": (0.00046, 0.00047, 0.00032),
               "lamp": (0.00046, 0.00047, 0.00032)},
    "atlas": {"grass": (0.03364, 0.05436, 0.00364), "verge": (0.03547, 0.04662, 0.00377),
              "edge": (0.01359, 0.02429, 0.00316), "path": (0.0262, 0.02095, 0.00493),
              "earth": (0.00648, 0.00436, 0.00231), "leaf": (0.00803, 0.01451, 0.003),
              "shade": (0.00198, 0.00335, 0.0013), "sun": (0.0304, 0.04904, 0.00532),
              "fern": (0.00669, 0.01651, 0.00301), "bark": (0.0116, 0.00821, 0.00412),
              "root": (0.01393, 0.00756, 0.00341), "cell": (0.00046, 0.00048, 0.00032)},
    "rock": {"granite": (0.03174, 0.03463, 0.02118), "shade": (0.01319, 0.01523, 0.01062),
             "moss": (0.00607, 0.01242, 0.00285), "lichen": (0.02972, 0.03328, 0.01902)},
}


# =============================================================================
# PAINT -- byte-exact canvases (the files hold these colours, not their linear)
# =============================================================================

class _Raw(tx.Canvas):
    """A tx.Canvas that keeps the bytes it is given."""

    def put(self, x, y, rgb, glow=None):
        o = ((y % self.h) * self.w + (x % self.w)) * 4
        self.alb[o], self.alb[o + 1], self.alb[o + 2] = rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0


def _grass(c, r):
    tx.noise_fill(c, r, c.box, GRASS[:3], cuts=(0.38, 0.66), dither=0, cells=(16, 6))
    tx.blades(c, r, c.box, 110, GRASS[3:])


def _path(c, r):
    tx.noise_fill(c, r, c.box, PATH[:3], cuts=(0.40, 0.72), dither=0, cells=(16, 6))
    tx.blades(c, r, c.box, 70, PATH[3:])


def _leaf(c, r):
    tx.fill(c, r, c.box, LEAF[:2])
    for _ in range(40):                          # leaves: a blob and its lit top edge
        w = r.i(6, 9)
        h = max(3, w - r.i(0, 2))
        x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
        c.rect(x, y, x + w, y + h, r.pick(LEAF[2:6]))
        c.rect(x, y + h - 1, x + max(2, w // 2), y + h, LEAF[6])


def _bark(c, r):
    tx.fill(c, r, c.box, BARK[:3])
    tx.streaks(c, r, c.box, 12, BARK[3:5], (10, 28), (1, 2))
    tx.streaks(c, r, c.box, 5, [BARK[5]], (5, 12), (1, 1), wander=1)
    for _ in range(3):
        x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
        c.rect(x, y, x + 3, y + 3, BARK[6])


def _fern(c, r):
    tx.fill(c, r, c.box, FERN[:3])
    for _ in range(5):                           # fronds: a stem with side ticks
        x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
        dx = r.pick([-1, 1])
        for k in range(r.i(14, 24)):
            xx, yy = x + (k * dx) // 2, y + k
            c.put(xx, yy, FERN[3])
            if k % 2 == 0:
                c.put(xx - 1, yy, FERN[4])
                c.put(xx + 1, yy, FERN[4])
    tx.blades(c, r, c.box, 14, [FERN[5]])


def _rock(c, r):
    tx.noise_fill(c, r, c.box, ROCK[:3], cuts=(0.34, 0.66), dither=0, cells=(16, 5))
    tx.blades(c, r, c.box, 70, [ROCK[3]])       # feldspar
    tx.blades(c, r, c.box, 90, [ROCK[4]])       # biotite
    tx.blades(c, r, c.box, 60, [ROCK[5]])       # the forest's green cast
    tx.veins(c, r, c.box, [ROCK[6]], 3, 16)      # hairline cleavage


def _dark(c, r):
    tx.fill(c, r, c.box, DARK[:2])
    tx.shatter(c, r, c.box, [DARK[2], DARK[0]], 10, 4, 10)
    for _ in range(2):                           # something pale, far back
        x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
        c.rect(x, y, x + 3, y + 1, DARK[3])


def _ornament(c, r):
    """Left: the cells' dim lamp glow, warmer patches and soot. Right: the portal's
    swirl, sunlit arms on deep leaf shadow, a gold core, a dark rim."""
    tx.fill(c, r, (0, 0, TILE, TILE), [GLOW[0]])
    for _ in range(6):
        x, y = r.i(0, TILE - 4), r.i(0, TILE - 3)
        c.rect(x, y, x + 3, y + 2, GLOW[1])
    for _ in range(14):
        x, y = r.i(0, TILE - 3), r.i(0, TILE - 1)
        c.rect(x, y, x + r.pick([1, 1, 3]), y + 1, GLOW[2])
    cx, cy = TILE / 2.0, TILE * SWIRL_CY
    for y in range(TILE):
        for x in range(TILE):
            dx, dy = (x + 0.5 - cx) / (TILE / 2.0), (y + 0.5 - cy) / (TILE / 2.0)
            rad = math.hypot(dx, dy)
            band = (math.atan2(dy, dx) * SWIRL_ARMS / (2.0 * math.pi) + rad * SWIRL_TURNS) % 1.0
            band = min(band, 1.0 - band) * 2.0     # 0 on the arm, 1 between
            arm = SWIRL_WIDTH * (1.0 - 0.5 * rad)
            if rad > 0.9:
                col = SWIRL[4]
            elif rad < 0.14:
                col = SWIRL[0]
            elif band < arm:
                col = SWIRL[1]
            elif band < arm + 0.22:
                col = SWIRL[2]
            else:
                col = SWIRL[3]
            c.put(TILE + x, y, col)


PAINTERS = {"forest_grass_albedo": (_grass, 1), "forest_path_albedo": (_path, 2),
            "forest_leaf_albedo": (_leaf, 3), "forest_bark_albedo": (_bark, 4),
            "forest_fern_albedo": (_fern, 5), "forest_rock_albedo": (_rock, 6),
            "forest_dark_albedo": (_dark, 7), "forest_ornament_albedo": (_ornament, 8)}


def paint(stem):
    fn, seed = PAINTERS[stem]
    c = _Raw(2 * TILE if stem == "forest_ornament_albedo" else TILE, TILE)
    fn(c, tx.Rng(SEED + seed))
    return c


# =============================================================================
# TINTS -- a zone's old mean over its tile's
# =============================================================================

def _s2l(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def mean(buf, w, h, rect=(0.0, 0.0, 1.0, 1.0)):
    """Linear mean of a bytes-over-255 RGBA buffer inside rect (fractions of w, h)."""
    x0, x1 = int(round(rect[0] * w)), int(round(rect[2] * w))
    y0, y1 = int(round(rect[1] * h)), int(round(rect[3] * h))
    s, n = [0.0, 0.0, 0.0], 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            o = (y * w + x) * 4
            for k in range(3):
                s[k] += _s2l(buf[o + k])
            n += 1
    return [v / n for v in s]


def tint(old, tile_mean):
    """old / tile per channel, capped at 1 (COLOR_0 cannot brighten)."""
    return tuple(min(1.0, old[k] / max(tile_mean[k], 1e-6)) for k in range(3))


# =============================================================================
# BLENDER -- images, materials, dress
# =============================================================================

_IMAGES = {}
_MEANS = {}
_MATS = {}

BOX = {k: tx.Sheet(k, None, size=TILE, mode="box") for k in ("grass", "path", "leaf", "bark", "fern", "rock", "dark")}
BOX["lamp"] = tx.Sheet("lamp", None, mode="fit", width=2 * TILE, size=TILE, rect=GLOW_RECT)


def image(stem):
    """The file when present (mdl finds it anywhere in the repo), else painted."""
    if stem not in _IMAGES:
        import forest_tree_build as ft
        img = ft.image_file(stem + ".png") if ft.USE_TEXTURE_FILES else None
        if img is None:
            c = paint(stem)
            img = bpy.data.images.new(stem, c.w, c.h, alpha=False)
            img.colorspace_settings.name = "sRGB"
            img.pixels.foreach_set(c.alb)
            img.update()
            img.pack()
            print("MDL TEXTURE %s painted (%dx%d)" % (stem, c.w, c.h))
        _IMAGES[stem] = img
    return _IMAGES[stem]


def key_mean(key):
    if key not in _MEANS:
        img = image(KEYS[key][0])
        buf = [0.0] * len(img.pixels)
        img.pixels.foreach_get(buf)
        _MEANS[key] = mean(buf, img.size[0], img.size[1], GLOW_RECT if key == "lamp" else (0.0, 0.0, 1.0, 1.0))
    return _MEANS[key]


def zone_tint(family, zone):
    key = MAP[family][zone]
    if not KEYS[key][2] or zone not in OLD[family]:
        return (1.0, 1.0, 1.0)
    return tint(OLD[family][zone], key_mean(key))


def material(key, prefix="Forest", cull=True):
    tag = (key, prefix, cull)
    if tag not in _MATS:
        import forest_tree_build as ft
        stem, glows, vcol = KEYS[key]
        img = image(stem)
        mat = tx.material("%s%s" % (prefix, key.capitalize()), img, img if glows else None, cull=cull)
        _MATS[tag] = ft.tint_material(mat) if vcol else mat
    return _MATS[tag]


def colours(ob):
    """The mesh's COLOR_0 ("Col", per corner), made white if it is not there yet."""
    me = ob.data
    col = me.color_attributes.get("Col")
    if col is None:
        col = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
        col.data.foreach_set("color", [1.0] * (len(me.loops) * 4))
    me.color_attributes.active_color_index = 0
    me.color_attributes.render_color_index = 0
    return col


def dress(ob, zones, family, sheets=None, flat=True, cull=True, custom=None, prefix="Forest"):
    """UVs (world-locked at tx.MPT), each zone's tint into COLOR_0, one material per
    key, slots assigned. Returns the slot order."""
    keys = [MAP[family][z] for z in zones]
    tx.unwrap(ob, keys, sheets or BOX, seed=1, custom=custom)
    me = ob.data
    col = colours(ob)
    flat_c = [0.0] * (len(me.loops) * 4)
    col.data.foreach_get("color", flat_c)
    tints = {}
    for pi, poly in enumerate(me.polygons):
        z = zones[pi]
        if z not in tints:
            tints[z] = zone_tint(family, z)
        t = tints[z]
        for li in poly.loop_indices:
            for k in range(3):
                flat_c[li * 4 + k] *= t[k]
    col.data.foreach_set("color", flat_c)
    mats = {k: material(k, prefix, cull) for k in set(keys)}
    order = tx.finish(ob, keys, mats, flat=flat)
    print("MDL STATS tiles %s: %s" % (ob.name, " ".join(
        "%s=%s" % (z, ",".join("%.3f" % v for v in tints[z])) for z in sorted(tints))))
    return order


def soften(ob, zones, passes=SOFT_PASSES):
    """Ryan: "the tree leaf thing". The per-face sun/leaf/shade step in COLOR_0 was the hard line on
    the leaves; blend it per welded vertex over the leaf faces, the open boundary (a seam ring) pinned."""
    me = ob.data
    col = colours(ob)
    flat = [0.0] * (len(me.loops) * 4)
    col.data.foreach_get("color", flat)
    key = lambda vi: tuple(round(c, 4) for c in me.vertices[vi].co)
    loops, nbr, edge_n = {}, {}, {}
    for pi, poly in enumerate(me.polygons):
        if zones[pi] not in LEAF_ZONES:
            continue
        ks = [key(me.loops[li].vertex_index) for li in poly.loop_indices]
        for li, k in zip(poly.loop_indices, ks):
            loops.setdefault(k, []).append(li)
        for a, b in zip(ks, ks[1:] + ks[:1]):
            nbr.setdefault(a, set()).add(b)
            nbr.setdefault(b, set()).add(a)
            e = (a, b) if a < b else (b, a)
            edge_n[e] = edge_n.get(e, 0) + 1
    pinned = {k for e, n in edge_n.items() if n == 1 for k in e}
    val = {k: [sum(flat[li * 4 + c] for li in ls) / len(ls) for c in range(3)] for k, ls in loops.items()}
    for _ in range(passes):
        val = {k: v if k in pinned else [(v[c] + sum(val[o][c] for o in nbr[k])) / (1 + len(nbr[k]))
                                         for c in range(3)] for k, v in val.items()}
    for k, ls in loops.items():
        if k in pinned:
            continue
        for li in ls:
            flat[li * 4:li * 4 + 3] = val[k]
    col.data.foreach_set("color", flat)
    print("MDL STATS soften %s: verts=%d pinned=%d passes=%d" % (ob.name, len(loops), len(pinned), passes))


# =============================================================================
# MAC -- write the eight PNGs with no Blender
# =============================================================================

def _write(out_dir):
    import struct
    import zlib
    os.makedirs(out_dir, exist_ok=True)
    for stem in sorted(PAINTERS):
        c = paint(stem)
        rows = []
        for y in range(c.h - 1, -1, -1):
            row = bytearray([0])
            for x in range(c.w):
                o = (y * c.w + x) * 4
                row += bytes(int(round(c.alb[o + k] * 255.0)) for k in range(3))
            rows.append(bytes(row))

        def chunk(tag, data):
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", c.w, c.h, 8, 2, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b"")
        with open(os.path.join(out_dir, stem + ".png"), "wb") as f:
            f.write(png)
        means = mean([v for v in c.alb], c.w, c.h, GLOW_RECT if "ornament" in stem else (0.0, 0.0, 1.0, 1.0))
        keys = [k for k, v in KEYS.items() if v[0] == stem and k != "swirl"]
        for fam in ("ground", "atlas", "rock"):
            for z, k in sorted(MAP[fam].items()):
                if k in keys and z in OLD[fam]:
                    raw = [OLD[fam][z][i] / means[i] for i in range(3)]
                    print("TINT %-22s %-6s %-7s %s" % (stem, fam, z, " ".join("%.3f" % v for v in raw)))


if __name__ == "__main__":
    if "--write" in sys.argv:
        _write(sys.argv[sys.argv.index("--write") + 1])
