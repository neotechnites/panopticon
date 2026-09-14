"""
PANOPTICON -- hub_base: the lobby floor. A flat ring of ten 36-degree wedges
round a plain circular plinth the tower is dropped onto as a scene node.
Wedge 1 (bearings 0..36) is a taste of the hell map: the arena's rock atlas,
a shallow lava pool with sloped banks and a stepping stone, four stalagmites.
Wedges 2..10 are undecided maps: bare grey stone, a low round dais at the
centre for a "?" marker. Wedge seams are 0.3 m inlaid bands, 3 cm recessed.

World coordinates, instance at identity: floor at y 0, plinth top at 0.35,
slab bottom at -2, outer wall 1.2..2.0 over the floor, sky open.
Blender +Z -> Godot +Y, Blender +Y -> Godot -Z.

One manifold rock; collision rides in the .glb as a `-colonly` node: flat
deck cut where the pool is, plinth, wall, dais pucks, pool banks and floor,
stalagmite stacks. Three materials: HellRock (painted atlas, byte-identical
to the arena's), Lava (the arena's river sheet), HubStone (painted grey).

    tools/modelling/model build hub_base
    python3 tools/modelling/hub_base_build.py --check     # geometry only, no Blender
"""

import math
import os
import sys

try:
    import bpy
except ImportError:                       # --check on the Mac: geometry only
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, HERE + os.sep + "lib")
if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["ground"] = False
    mdl.DEFAULTS["world_grey"] = 0.30
    mdl.DEFAULTS["world_strength"] = 0.90

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "hub_base"
OBJECT_NAME = "HubBaseRock"
COLLIDER_NAME = "HubBaseCollision-colonly"
FACING_YAW = 0.0

R_IN = 21.0                 # floor inner edge: the plinth chamfer foot
R_PLINTH = 20.0             # chamfer top; the tower rock (r <= 13.4) leaves a 6.6 m walk round it
PLINTH_Z = 0.35
PLINTH_RINGS = (19.0, 17.6, 16.2, 14.6, 12.5, 9.5, 6.0, 3.0)   # plinth top rings: squarish quads, no radial streaks
R_OUT = 40.0                # floor outer edge: the wall foot
WALL_T = 1.2
WALL_H = (1.2, 2.0)         # the wall top wanders between these
SLAB_Z = -2.0
N_WEDGE = 10
WEDGE = 2.0 * math.pi / N_WEDGE
N_INT = 19                  # interior column intervals per wedge
N_RINGS = 16                # radial intervals R_IN..R_OUT (~1.19 m)
SEAM_W = 0.3                # the inlaid band between wedges
SEAM_LIP = 0.02             # the band's lip: a 2 cm slant down to the recess
SEAM_D = 0.03
JITTER_HELL = 0.06          # floor vertex height wander, hell wedge
JITTER_STONE = 0.03         # ... and the stone wedges: tiles, not dead flat
HELL_WEDGE = 0

DAIS_R, DAIS_BASE_R, DAIS_H, DAIS_SIDES = 1.5, 1.9, 0.2, 24
DAIS_RAD = 0.5 * (R_IN + R_OUT)

POOL_B, POOL_RAD = 16.0, 31.5   # bearing, radius of the lava pool centre
POOL_R = 2.2                    # mean rim radius; the shape stretches it along the ring
POOL_N = 32
POOL_SHAPE = (0.20, 0.05)           # rim: 2nd and 3rd harmonic
FOOT_SHAPE = 0.12                   # foot: 2nd harmonic only, so it stays CONVEX for the lava zipper
BANK_W = 0.8                    # mean rim-to-foot, horizontally; never steeper than ~36 deg
LAVA_Z = -0.3
STONE_OFF = 0.45                # the stepping stone, off centre along the long axis
STONE_R = (0.55, 0.45)          # foot and top radius
STONE_TOP = 0.03
STONE_SIDES = 8

SPIKES = [(6.0, 24.5, "short"), (29.0, 25.0, "tall"),
          (30.0, 36.5, "medium"), (4.0, 36.5, "short")]   # bearing, radius, size

HOLE_PAD = 0.7              # a hole's clearance past its feature: past any cell chord
COLL_INT = 8                # collider deck: columns per wedge ...
COLL_RINGS = 10             # ... and radial intervals
COLL_PAD = 3.2

SEED = 4180221
POOL_SEED = 5140737
WALL_SEED = 7331
EYE_H = 1.65

# ---- HellRock atlas -- identical to map_base_build.py --------------------
USE_TEXTURE_FILES = True
TEX_DIR = "textures"
TEX_SIZE = 128
TEX_ALBEDO = "map_base_rock_albedo"
TEX_EMISSIVE = "map_base_rock_emissive"
TEX_SEED = 6661031
ROCK_ROUGHNESS = 0.95
ROCK_METALLIC = 0.0
UV_SCALE = 0.13
UV_PAD = 1.5 / TEX_SIZE

ZONE_ROCK = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)
ZONE_CARVE = (0.5, 0.0, 1.0, 0.5)
ZONE_EMBER = (0.0, 0.0, 0.5, 0.5)
ZONE_GLOW = (0.5, 0.0, 1.0, 0.25)
ZONE_DECK = ("deck",) + ZONE_ROCK      # the lighter cell: SHADE goes black under neutral light
DECK_UV_SCALE = 0.34

# ---- the lava pool: the arena's river sheet ------------------------------
ZONE_RIVER = ("river",)
RIVER_TEX = 256
RIVER_ALBEDO = "map_base_river_albedo"
RIVER_EMISSIVE = "map_base_river_emissive"
RIVER_SEED = 7720133
FLOW_SPAN = 10.0
CROSS_SPAN = 10.0

# ---- HubStone: the undecided wedges ---------------------------------------
STONE_TEX = 128
STONE_ALBEDO = "hub_stone_albedo"
STONE_EMISSIVE = "hub_stone_emissive"
STONE_SEED = 2718281
ZONE_STONE = ("stone", 0.0, 0.5, 0.5, 1.0)     # the wedge floor
ZONE_SEAM = ("stone", 0.5, 0.5, 1.0, 1.0)      # the inlaid band
ZONE_SIDE = ("stone", 0.5, 0.0, 1.0, 0.5)      # wall, slab
ZONE_DAIS = ("stone", 0.0, 0.0, 0.5, 0.5)      # dais, plinth: dressed

# ---- stalagmites -- the arena's S1 shapes ---------------------------------
S1_SKIRT = (0.5, 1.0, 0.3)
S1_SKIRT_P = 2.5
S1_RIM_JITTER = 0.3
S1_FLARE = 2.6
S1_RIDGE_Z = 0.8
S1_SIZES = {"short": (1.2, 2.4, 0.16, 0.28), "medium": (2.4, 3.8, 0.26, 0.38),
            "tall": (3.8, 6.0, 0.32, 0.42)}

# Render-only company: the arches tower and the eye, read from Ryan's play copy
# on the PC exactly as tower_build.py reads its .blend. Never exported.
TOWER_GLB = r"C:\dev\panopticon\assets\models\tower_arches.glb"
EYE_GLB = r"C:\dev\panopticon\assets\models\eye.glb"
TOWER_FOOT = 36.4               # model-local depth of the rock's foot under its origin
EYE_H_OVER_TOWER = 7.2          # WatchingEyeProfile.height_metres
EYE_RADIUS = 2.5                # ... radius_metres

REVIEW_SUN = 3.0
REVIEW_WORLD = 1.0
REVIEW_EXPOSURE = 0.6

TWO_PI = 2.0 * math.pi
UP = (0.0, 0.0, 1.0)
DOWN = (0.0, 0.0, -1.0)
EPS = 1e-9


# =============================================================================
# TEXTURE -- copied from map_base_build.py so the atlas is the same rock
# =============================================================================

class _Rng(object):
    """Deterministic LCG; the model is byte-identical every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def bits(self):
        return self.n() >> 12

    def f(self):
        return self.n() / float(0x7FFFFFFF)

    def sf(self):
        return self.f() * 2.0 - 1.0

    def i(self, a, b):
        return a + self.bits() % (b - a + 1)

    def pick(self, seq):
        return seq[self.bits() % len(seq)]


def _s2l(rgb):
    out = []
    for c in rgb:
        c /= 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return out


class _Canvas(object):
    def __init__(self, size):
        self.w = self.h = size
        n = size * size * 4
        self.alb = [0.0] * n
        self.emi = [0.0] * n
        for i in range(size * size):
            self.alb[i * 4 + 3] = 1.0
            self.emi[i * 4 + 3] = 1.0

    def put(self, x, y, rgb, glow=None):
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        o = (y * self.w + x) * 4
        r, g, b = _s2l(rgb)
        self.alb[o], self.alb[o + 1], self.alb[o + 2] = r, g, b
        if glow is not None:
            r, g, b = _s2l(glow)
            self.emi[o], self.emi[o + 1], self.emi[o + 2] = r, g, b

    def wrap(self, x, y, rgb, glow=None):
        self.put(x % self.w, y % self.h, rgb, glow)

    def rect(self, x0, y0, x1, y1, rgb, glow=None):
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.put(x, y, rgb, glow)


def _rect_of(zone, size):
    u0, v0, u1, v1 = zone
    return (int(u0 * size), int(v0 * size), int(u1 * size), int(v1 * size))


def _fill(c, r, box, shades):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            c.put(x, y, r.pick(shades))


def _shatter(c, r, box, shades, count, minsz, maxsz):
    """Squarish blotches with no preferred direction."""
    x0, y0, x1, y1 = box
    for _ in range(count):
        w = r.i(minsz, maxsz)
        h = max(minsz, min(maxsz, w + r.i(-1, 1)))
        x, y = r.i(x0, x1 - w - 1), r.i(y0, y1 - h - 1)
        c.rect(x, y, x + w, y + h, r.pick(shades))


def _paint_rock(c, r, box):
    _fill(c, r, box, [(74, 27, 25), (58, 20, 19), (90, 35, 30), (46, 16, 16)])
    _shatter(c, r, box, [(96, 40, 33), (48, 16, 16), (110, 48, 38)], 20, 6, 15)
    _shatter(c, r, box, [(32, 11, 12), (118, 56, 43)], 12, 4, 9)
    x0, y0, x1, y1 = box
    for _ in range(6):
        x, y = r.i(x0 + 2, x1 - 4), r.i(y0 + 2, y1 - 4)
        c.rect(x, y, x + 2, y + 2, (172, 44, 12), (114, 22, 3))


def _paint_shade(c, r, box):
    _fill(c, r, box, [(34, 12, 12), (24, 8, 9), (44, 17, 15), (17, 6, 7)])
    _shatter(c, r, box, [(42, 16, 15), (10, 3, 4)], 20, 4, 11)
    x0, y0, x1, y1 = box
    for _ in range(4):
        x, y = r.i(x0 + 2, x1 - 4), r.i(y0 + 2, y1 - 4)
        c.rect(x, y, x + 2, y + 2, (140, 34, 9), (92, 16, 2))


def _paint_carve(c, r, box):
    _fill(c, r, box, [(84, 58, 53), (72, 48, 44), (96, 69, 63), (64, 42, 39)])
    _shatter(c, r, box, [(66, 43, 40), (102, 74, 68), (56, 35, 33)], 14, 5, 14)
    _shatter(c, r, box, [(74, 38, 27), (46, 27, 25)], 10, 4, 10)
    x0, y0, x1, y1 = box
    for _ in range(10):
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        c.rect(x, y, x + 2, y + 2, (52, 32, 30))
    for _ in range(3):
        x, y = r.i(x0 + 2, x1 - 4), r.i(y0 + 2, y1 - 4)
        c.rect(x, y, x + 2, y + 2, (152, 48, 14), (88, 18, 2))


def _paint_ember(c, r, box):
    x0, y0, x1, y1 = box
    _fill(c, r, box, [(11, 4, 5), (16, 6, 6), (7, 2, 3), (20, 8, 7)])
    for _ in range(15):
        x, y = r.i(x0, x1 - 1), r.i(y0, y1 - 1)
        for _step in range(60):
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if x0 <= x + dx < x1 and y0 <= y + dy < y1:
                        c.put(x + dx, y + dy, (58, 15, 4), (74, 15, 1))
            hot = r.pick([(255, 150, 30), (255, 212, 88), (248, 100, 14)])
            c.put(x, y, hot, hot)
            x += r.i(-1, 1)
            y += r.i(-1, 1)
            if not (x0 <= x < x1 and y0 <= y < y1):
                break
    for _ in range(30):
        c.put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), (7, 3, 4))
    for _ in range(10):
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        c.rect(x, y, x + 2, y + 2, (236, 92, 18), (194, 54, 5))


def _paint_glow(c, r, box):
    x0, y0, x1, y1 = box
    shades = [(214, 44, 8), (196, 34, 6), (232, 60, 14), (178, 28, 6)]
    for y in range(y0, y1):
        for x in range(x0, x1):
            s = r.pick(shades)
            c.put(x, y, s, s)
    for _ in range(14):
        x, w = r.i(x0, x1 - 3), r.i(1, 2)
        yy, h = r.i(y0, y1 - 6), r.i(4, 10)
        c.rect(x, yy, x + w, min(y1, yy + h), (128, 18, 4), (104, 12, 2))
    for _ in range(12):
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        c.rect(x, y, x + 2, y + 2, (255, 128, 34), (255, 128, 34))


def _images(c, size, names):
    out = []
    for name, buf in ((names[0], c.alb), (names[1], c.emi)):
        img = bpy.data.images.new(name, size, size, alpha=False)
        img.colorspace_settings.name = "sRGB"
        img.pixels.foreach_set(buf)
        img.update()
        out.append(img)
    return out[0], out[1]


def build_texture():
    """Paint the hell-rock atlas; byte-identical to the arena's."""
    c = _Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    _paint_rock(c, r, _rect_of(ZONE_ROCK, TEX_SIZE))
    _paint_shade(c, r, _rect_of(ZONE_SHADE, TEX_SIZE))
    _paint_carve(c, r, _rect_of(ZONE_CARVE, TEX_SIZE))
    _paint_ember(c, r, _rect_of(ZONE_EMBER, TEX_SIZE))
    _paint_glow(c, r, _rect_of(ZONE_GLOW, TEX_SIZE))
    return _images(c, TEX_SIZE, (TEX_ALBEDO, TEX_EMISSIVE))


def _paint_stone(c, r, box):
    _fill(c, r, box, [(112, 110, 105), (106, 104, 99), (118, 116, 111), (100, 98, 94)])
    _shatter(c, r, box, [(122, 120, 114), (96, 94, 90), (110, 108, 103)], 20, 6, 15)
    _shatter(c, r, box, [(92, 90, 87), (126, 124, 118)], 12, 4, 9)


def _paint_seam(c, r, box):
    _fill(c, r, box, [(48, 46, 44), (42, 40, 39), (54, 52, 50), (38, 36, 35)])
    _shatter(c, r, box, [(58, 56, 53), (34, 32, 31)], 14, 3, 8)


def _paint_side(c, r, box):
    _fill(c, r, box, [(86, 84, 80), (80, 78, 75), (92, 90, 86), (74, 72, 69)])
    _shatter(c, r, box, [(98, 96, 91), (66, 64, 62)], 20, 5, 14)


def _paint_dais(c, r, box):
    _fill(c, r, box, [(142, 140, 134), (136, 134, 128), (148, 146, 140), (130, 128, 122)])
    _shatter(c, r, box, [(154, 152, 145), (124, 122, 116)], 16, 4, 10)


def build_stone_texture():
    """Neutral grey stone, no emission: floor, seam band, sides, dais."""
    c = _Canvas(STONE_TEX)
    r = _Rng(STONE_SEED)
    _paint_stone(c, r, _rect_of(ZONE_STONE[1:], STONE_TEX))
    _paint_seam(c, r, _rect_of(ZONE_SEAM[1:], STONE_TEX))
    _paint_side(c, r, _rect_of(ZONE_SIDE[1:], STONE_TEX))
    _paint_dais(c, r, _rect_of(ZONE_DAIS[1:], STONE_TEX))
    return _images(c, STONE_TEX, (STONE_ALBEDO, STONE_EMISSIVE))


def rock_material(name, albedo, emissive):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    for img, socket, y in ((albedo, "Base Color", 260), (emissive, "Emission Color", -220)):
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.interpolation = "Closest"
        node.location = (-460, y)
        nt.links.new(node.outputs["Color"], bsdf.inputs[socket])
    bsdf.inputs["Roughness"].default_value = ROCK_ROUGHNESS
    bsdf.inputs["Metallic"].default_value = ROCK_METALLIC
    bsdf.inputs["Emission Strength"].default_value = 1.0   # exactly 1.0: no KHR warning
    mat.diffuse_color = (0.13, 0.04, 0.04, 1.0)
    return mat


def _river_texture():
    """The river sheet: molten, streaked along +U, tiling both ways."""
    c = _Canvas(RIVER_TEX)
    r = _Rng(RIVER_SEED)
    n = RIVER_TEX
    hot = [(232, 74, 10), (255, 110, 22), (212, 56, 6), (255, 140, 34)]
    warm = [(178, 46, 6), (150, 34, 4), (200, 58, 10)]
    crust = [(34, 12, 10), (24, 8, 8), (46, 18, 14)]
    for y in range(n):
        for x in range(n):
            s = r.pick(hot)
            c.put(x, y, s, s)
    for _ in range(90):
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        w, h = r.i(18, 70), r.i(2, 7)
        sh = r.pick(crust)
        for dy in range(h):
            for dx in range(w):
                c.wrap(x + dx, y + dy + (dx // 26), sh, (0, 0, 0))
    for _ in range(150):
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        sh = r.pick(crust)
        for dx in range(r.i(30, 110)):
            c.wrap(x + dx, y, sh, (6, 2, 2))
            if r.i(0, 6) == 0:
                y += r.i(-1, 1)
    for _ in range(200):
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        sh = r.pick(warm)
        for dx in range(r.i(20, 90)):
            c.wrap(x + dx, y, sh, sh)
            if r.i(0, 8) == 0:
                y += r.i(-1, 1)
    for _ in range(120):
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        core = r.pick([(255, 216, 104), (255, 184, 64), (255, 232, 150)])
        for dx in range(r.i(8, 46)):
            c.wrap(x + dx, y, core, core)
            if r.i(0, 10) == 0:
                y += r.i(-1, 1)
    return _images(c, RIVER_TEX, (RIVER_ALBEDO, RIVER_EMISSIVE))


def _image_file(name):
    """A texture file beside the script, packed into the .glb; None if absent."""
    path = os.path.join(HERE, TEX_DIR, name)
    if not os.path.isfile(path):
        return None
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "sRGB"
    img.pack()
    print("MDL TEXTURE %s from %s" % (img.name, path))
    return img


def _sheet(stem, painted):
    """(albedo, emissive): the files when opted in and present, else painted."""
    alb = _image_file(stem + "_albedo.png") if USE_TEXTURE_FILES else None
    if alb is None:
        return painted()
    return alb, (_image_file(stem + "_emissive.png") or alb)


# =============================================================================
# GEOMETRY HELPERS -- winding is checked, never assumed
# =============================================================================

def _newell(pts):
    nx = ny = nz = 0.0
    n = len(pts)
    for i in range(n):
        ax, ay, az = pts[i]
        bx, by, bz = pts[(i + 1) % n]
        nx += (ay - by) * (az + bz)
        ny += (az - bz) * (ax + bx)
        nz += (ax - bx) * (ay + by)
    return (nx, ny, nz)


class _Mesh(object):
    """Face accumulator: every face states the direction its normal must point."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.zones = []

    def v(self, p):
        self.verts.append(tuple(p))
        return len(self.verts) - 1

    def _emit(self, idx, want, zone):
        pts = [self.verts[j] for j in idx]
        n = _newell(pts)
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        if len(idx) == 4:
            self.faces.append((idx[0], idx[1], idx[2]))
            self.faces.append((idx[0], idx[2], idx[3]))
            self.zones.append(zone)
            self.zones.append(zone)
        else:
            self.faces.append(tuple(idx))
            self.zones.append(zone)

    def quad(self, a, b, c, d, want, zone):
        self._emit([a, b, c, d], want, zone)

    def tri(self, a, b, c, want, zone):
        self._emit([a, b, c], want, zone)

    def fan(self, ring, want, zone):
        """Oriented by the whole ring: a slightly non-convex cap stays one-sided."""
        n = _newell([self.verts[j] for j in ring])
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            ring = list(reversed(ring))
        for i in range(1, len(ring) - 1):
            self.faces.append((ring[0], ring[i], ring[i + 1]))
            self.zones.append(zone)

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


def pol(bearing_deg, rad, z=0.0):
    a = math.radians(bearing_deg)
    return (rad * math.cos(a), rad * math.sin(a), z)


def _wedge_of(a):
    return int((a % TWO_PI) // WEDGE) % N_WEDGE


def _zipper(m, outer, inner, cx, cy, want, zone):
    """Triangles between two loops, both CCW and star-shaped about (cx, cy),
    the inner strictly inside the outer: walked by angle, no crossings."""
    def ang(idx):
        x, y, _ = m.verts[idx]
        return math.atan2(y - cy, x - cx)

    a0 = ang(outer[0])

    def unwrap(a):
        return a0 + (a - a0) % TWO_PI

    ao = [unwrap(ang(v)) for v in outer]
    ai = [unwrap(ang(v)) for v in inner]
    k0 = min(range(len(inner)), key=lambda k: ai[k])
    inner = inner[k0:] + inner[:k0]
    ai = ai[k0:] + ai[:k0]
    for arr in (ao, ai):
        assert all(arr[k] <= arr[k + 1] + 1e-9 for k in range(len(arr) - 1)), \
            "zipper: loop is not star-shaped about its centre"
    nO, nI = len(outer), len(inner)
    ao.append(a0 + TWO_PI)
    ai.append(ai[0] + TWO_PI)
    i = k = 0
    while i < nO or k < nI:
        if i < nO and (k >= nI or ao[i + 1] <= ai[k + 1]):
            m.tri(outer[i], outer[(i + 1) % nO], inner[k % nI], want, zone)
            i += 1
        else:
            m.tri(outer[i % nO], inner[(k + 1) % nI], inner[k % nI], want, zone)
            k += 1


def _columns(r, seams, n_int):
    """Column angles round a ring at radius r: [(angle, kind, wedge)].
    kind: 'edge' (a band's outer edge, z 0), 'in' (inside the band, recessed),
    'int' (wedge floor). Without seams: one 'edge' per wedge boundary."""
    cols = []
    for w in range(N_WEDGE):
        B = w * WEDGE
        if seams:
            h = 0.5 * SEAM_W / r
            e = SEAM_LIP / r
            cols += [(B - h, "edge", w), (B - h + e, "in", w), (B + h - e, "in", w), (B + h, "edge", w)]
            a0, a1 = B + h, B + WEDGE - h
        else:
            cols.append((B, "edge", w))
            a0, a1 = B, B + WEDGE
        for k in range(1, n_int):
            cols.append((a0 + (a1 - a0) * k / n_int, "int", w))
    return cols


class _Grid(object):
    """The floor: a polar grid of quads between R_IN and R_OUT. Features cut
    a hole (every cell with a vertex within D of the centre) and the hole is
    zippered to the feature's own base ring, so the sheet stays one manifold."""

    def __init__(self, m, rings, seams, n_int, jitter, rng):
        self.m = m
        self.rings = rings
        self.nr = len(rings) - 1
        self.cols = [_columns(r, seams, n_int) for r in rings]
        self.nc = len(self.cols[0])
        self.V = []
        for i, r in enumerate(rings):
            row = []
            for (a, kind, w) in self.cols[i]:
                z = 0.0
                if jitter and 0 < i < self.nr:
                    if kind == "in":
                        z = -SEAM_D
                    elif kind == "int":
                        z = (JITTER_HELL if w == HELL_WEDGE else JITTER_STONE) * rng.sf()
                row.append(m.v((r * math.cos(a), r * math.sin(a), z)))
            self.V.append(row)
        self.removed = set()
        self.hole_verts = set()
        self.holes = []

    def _cell(self, i, j):
        jn = (j + 1) % self.nc
        return (self.V[i][j], self.V[i][jn], self.V[i + 1][jn], self.V[i + 1][j])

    def cell_zone(self, i, j):
        c0, c1 = self.cols[i][j], self.cols[i][(j + 1) % self.nc]
        if c0[1] == "in" or c1[1] == "in":
            return ZONE_SEAM
        a1 = c1[0] if j + 1 < self.nc else c1[0] + TWO_PI
        return ZONE_DECK if _wedge_of(0.5 * (c0[0] + a1)) == HELL_WEDGE else ZONE_STONE

    def cut(self, cx, cy, D, loop, zone):
        cells = set()
        for i in range(self.nr):
            for j in range(self.nc):
                for vi in self._cell(i, j):
                    x, y, _ = self.m.verts[vi]
                    if math.hypot(x - cx, y - cy) < D:
                        cells.add((i, j))
                        break
        assert cells, "hole cuts nothing"
        assert not any(i == 0 or i == self.nr - 1 for (i, _) in cells), "hole touches the grid edge"
        verts = set()
        for c in cells:
            verts.update(self._cell(*c))
        assert not (verts & self.hole_verts), "holes touch at (%.1f, %.1f) D=%.2f bearing=%.1f r=%.1f" % (cx, cy, D, math.degrees(math.atan2(cy, cx)), math.hypot(cx, cy))
        self.removed |= cells
        self.hole_verts |= verts
        self.holes.append((cx, cy, cells, loop, zone))

    def _boundary(self, cells, cx, cy):
        edges = []
        for (i, j) in cells:
            a, b, c, d = self._cell(i, j)
            jn = (j + 1) % self.nc
            if (i - 1, j) not in cells:
                edges.append((a, b))
            if (i + 1, j) not in cells:
                edges.append((d, c))
            if (i, (j - 1) % self.nc) not in cells:
                edges.append((a, d))
            if (i, jn) not in cells:
                edges.append((b, c))
        adj = {}
        for (p, q) in edges:
            adj.setdefault(p, []).append(q)
            adj.setdefault(q, []).append(p)
        assert all(len(v) == 2 for v in adj.values()), "hole boundary is not a simple loop"
        start = edges[0][0]
        loop, prev, cur = [start], None, start
        while True:
            nxt = adj[cur][0] if prev is None else [q for q in adj[cur] if q != prev][0]
            if nxt == start:
                break
            loop.append(nxt)
            prev, cur = cur, nxt
        assert len(loop) == len(adj), "hole boundary is more than one loop"
        area = 0.0
        for k in range(len(loop)):
            x0, y0, _ = self.m.verts[loop[k]]
            x1, y1, _ = self.m.verts[loop[(k + 1) % len(loop)]]
            area += (x0 - cx) * (y1 - cy) - (x1 - cx) * (y0 - cy)
        return loop if area > 0.0 else list(reversed(loop))

    def emit(self):
        for i in range(self.nr):
            for j in range(self.nc):
                if (i, j) in self.removed:
                    continue
                a, b, c, d = self._cell(i, j)
                self.m.quad(a, b, c, d, UP, self.cell_zone(i, j))
        for (cx, cy, cells, loop, zone) in self.holes:
            _zipper(self.m, self._boundary(cells, cx, cy), loop, cx, cy, UP, zone)


# =============================================================================
# FEATURES
# =============================================================================

def _ring(m, cx, cy, rad, z, n, rng=None, jit=0.0):
    out = []
    for i in range(n):
        t = TWO_PI * i / n
        rr = rad * (1.0 + jit * rng.sf()) if rng else rad
        out.append(m.v((cx + rr * math.cos(t), cy + rr * math.sin(t), z)))
    return out


def _stack(m, lo, hi, cx, cy, zone):
    """Quads between two rings round (cx, cy), normals outward."""
    n = len(lo)
    for i in range(n):
        j = (i + 1) % n
        x = sum(m.verts[v][0] for v in (lo[i], lo[j], hi[j], hi[i])) / 4.0 - cx
        y = sum(m.verts[v][1] for v in (lo[i], lo[j], hi[j], hi[i])) / 4.0 - cy
        m.quad(lo[i], lo[j], hi[j], hi[i], (x, y, 0.0), zone)


def _dais(m, w, coll=False):
    """A low round dais at the wedge centre: 3 m top, 0.2 m up, chamfered."""
    cx, cy, _ = pol((w + 0.5) * math.degrees(WEDGE), DAIS_RAD)
    base = _ring(m, cx, cy, DAIS_BASE_R, 0.0, DAIS_SIDES)
    top = _ring(m, cx, cy, DAIS_R, DAIS_H, DAIS_SIDES)
    _stack(m, base, top, cx, cy, ZONE_DAIS)
    m.fan(top, UP, ZONE_DAIS)
    if coll:
        m.fan(base, DOWN, ZONE_DAIS)
    return (cx, cy, DAIS_BASE_R + HOLE_PAD, base, ZONE_STONE)


def _pool(m, coll=False):
    """The lava pool: an irregular rim at the floor, a 23 deg bank down to the
    lava 0.3 m under it, one stepping stone standing up out of the lava."""
    rng = _Rng(POOL_SEED)
    cx, cy, _ = pol(POOL_B, POOL_RAD)
    phi = math.radians(POOL_B) + 0.5 * math.pi        # long axis along the ring
    rim, foot, rho_max = [], [], 0.0
    for i in range(POOL_N):
        t = TWO_PI * i / POOL_N + 0.25 * (TWO_PI / POOL_N) * rng.sf()
        rho = POOL_R * (1.0 + POOL_SHAPE[0] * math.cos(2.0 * (t - phi)) + POOL_SHAPE[1] * math.sin(3.0 * t + 1.0))
        rho_max = max(rho_max, rho)
        rim.append(m.v((cx + rho * math.cos(t), cy + rho * math.sin(t), 0.0)))
        rf = (POOL_R - BANK_W) * (1.0 + FOOT_SHAPE * math.cos(2.0 * (t - phi)))
        foot.append(m.v((cx + rf * math.cos(t), cy + rf * math.sin(t), LAVA_Z)))
    for i in range(POOL_N):
        j = (i + 1) % POOL_N
        tm = TWO_PI * (i + 0.5) / POOL_N
        m.quad(rim[i], rim[j], foot[j], foot[i], (-math.cos(tm), -math.sin(tm), 1.0), ZONE_DECK)
    sx, sy = cx + STONE_OFF * math.cos(phi), cy + STONE_OFF * math.sin(phi)
    sbase, stop = [], []
    for i in range(STONE_SIDES):
        t = TWO_PI * i / STONE_SIDES + 0.2 * (TWO_PI / STONE_SIDES) * rng.sf()
        r0 = STONE_R[0] * (1.0 + 0.12 * rng.sf())
        r1 = STONE_R[1] * (1.0 + 0.10 * rng.sf())
        sbase.append(m.v((sx + r0 * math.cos(t), sy + r0 * math.sin(t), LAVA_Z)))
        stop.append(m.v((sx + r1 * math.cos(t), sy + r1 * math.sin(t), STONE_TOP)))
    _stack(m, sbase, stop, sx, sy, ZONE_ROCK)
    m.fan(stop, UP, ZONE_ROCK)
    if coll:
        m.fan(sbase, DOWN, ZONE_ROCK)
        centre = m.v((cx, cy, LAVA_Z))
        for i in range(POOL_N):
            m.tri(foot[i], foot[(i + 1) % POOL_N], centre, UP, ZONE_RIVER)
    else:
        near = min(math.hypot(m.verts[v][0] - sx, m.verts[v][1] - sy) for v in foot)
        far = max(math.hypot(m.verts[v][0] - sx, m.verts[v][1] - sy) for v in sbase)
        assert near > far + 0.2, "stepping stone touches the bank (%.2f vs %.2f)" % (near, far)
        _zipper(m, foot, sbase, sx, sy, UP, ZONE_RIVER)
    return (cx, cy, rho_max + (COLL_PAD if coll else HOLE_PAD), rim, ZONE_DECK)


class _Spike(object):
    """A stalagmite as the arena's S1 makes them: an n-sided tube of rings up
    a bent axis, organic radius per vertex, a flowstone apron into the floor,
    drip ridges. Offsets are (radial, tangential)."""

    SKIRT_W = (1.0, 0.86, 0.72, 0.58, 0.44, 0.31, 0.19, 0.09)
    BODY = (0.34, 0.44, 0.54, 0.64, 0.74, 0.84, 0.92, 0.97, 1.0)

    def __init__(self, H, R, sides, r, bend=0.05, nridge=4, ridge_amp=(0.09, 0.22)):
        self.H, self.R, self.sides = H, R, sides
        self.skirt = min(S1_SKIRT[1], max(S1_SKIRT[0], S1_SKIRT[2] * H))
        sk = [self.skirt * (1.0 - w) ** S1_SKIRT_P / H for w in self.SKIRT_W]
        self.us = tuple(sk + [u for u in self.BODY if u > sk[-1] + 0.06])
        self.angs = [TWO_PI * (i + 0.28 * r.sf()) / sides for i in range(sides)]
        self.fac = [1.0 + 0.13 * r.sf() for _ in range(sides)]
        self.rim = [1.0 + S1_RIM_JITTER * r.sf() for _ in range(sides)]
        self.bend = (r.f() * TWO_PI, bend * (0.6 + 0.4 * r.f()), r.f() * TWO_PI)
        body = [u for u in self.us if max(0.2, S1_RIDGE_Z / H) < u < 0.9]
        self.ridges = []
        for _ in range(nridge):
            if body:
                u = r.pick(body)
                body = [v for v in body if abs(v - u) > 0.05]
                self.ridges.append((u, ridge_amp[0] + (ridge_amp[1] - ridge_amp[0]) * r.f(), 0.11))

    def body(self, u):
        base = 1.0 - 0.72 * u ** 1.4 - 0.12 * max(0.0, (u - 0.92) / 0.08)   # a rounded crown
        ridge = 1.0
        for (uk, ak, wk) in self.ridges:
            ridge += ak * max(0.0, 1.0 - ((u - uk) / wk) ** 2)
        return self.R * base * ridge

    def flare_f(self, u):
        h = u * self.H
        return 1.0 + (S1_FLARE - 1.0) * (1.0 - min(1.0, h / self.skirt) ** (1.0 / S1_SKIRT_P))

    def radius(self, i, u):
        return self.body(u) * self.fac[i] * (1.0 + (self.flare_f(u) - 1.0) * self.rim[i])

    def axis(self, u):
        ph, amp, ph2 = self.bend
        a = amp * self.H * u ** 1.6
        s = 0.05 * self.H * math.sin(TWO_PI * u + ph2) * u * (1.0 - u)
        return (a * math.cos(ph) + s * math.cos(ph2), a * math.sin(ph) + s * math.sin(ph2))

    def section(self, u, frame):
        """World-xy offsets of the cross-section at u round the bent axis."""
        er, et = frame
        ax, ay = self.axis(u)
        out = []
        for i in range(self.sides):
            p, q = ax + self.radius(i, u) * math.cos(self.angs[i]), ay + self.radius(i, u) * math.sin(self.angs[i])
            out.append((er[0] * p + et[0] * q, er[1] * p + et[1] * q))
        return out


def _spike(m, k, coll=False):
    b, rad, size = SPIKES[k]
    rng = _Rng(SEED + 101 * k)
    lo_h, hi_h, lo_r, hi_r = S1_SIZES[size]
    sp = _Spike(lo_h + (hi_h - lo_h) * rng.f(), lo_r + (hi_r - lo_r) * rng.f(), rng.pick((10, 11, 12)), rng)
    cx, cy, _ = pol(b, rad)
    frame = ((cx / rad, cy / rad), (-cy / rad, cx / rad))
    rings, centres = [], []
    for u in sp.us:
        offs = sp.section(u, frame)
        rings.append([m.v((cx + dx, cy + dy, u * sp.H)) for (dx, dy) in offs])
        ax, ay = sp.axis(u)
        centres.append((cx + frame[0][0] * ax + frame[1][0] * ay, cy + frame[0][1] * ax + frame[1][1] * ay))
    for q in range(len(rings) - 1):
        c = (0.5 * (centres[q][0] + centres[q + 1][0]), 0.5 * (centres[q][1] + centres[q + 1][1]))
        _stack(m, rings[q], rings[q + 1], c[0], c[1], ZONE_ROCK)
    m.fan(rings[-1], UP, ZONE_ROCK)
    if coll:
        m.fan(rings[0], DOWN, ZONE_ROCK)
    base_r = max(math.hypot(m.verts[v][0] - cx, m.verts[v][1] - cy) for v in rings[0])
    return (cx, cy, base_r + HOLE_PAD, rings[0], ZONE_DECK), sp


def _wall_tops(cols):
    """The wall's top height per column: low waves plus a per-column jog."""
    rng = _Rng(WALL_SEED)
    out = []
    for (a, _kind, _w) in cols:
        f = 0.45 + 0.28 * math.sin(3.0 * a + 0.7) + 0.17 * math.sin(8.0 * a + 2.1) + 0.12 * rng.sf()
        out.append((WALL_H[0] + (WALL_H[1] - WALL_H[0]) * min(1.0, max(0.0, f)), rng.f()))
    return out


def _wall(m, foot, cols, zone_of):
    """Inner face up from the floor's outer ring, a top, the outer face down
    to the slab bottom. Returns the outer bottom ring."""
    tops = _wall_tops(cols)
    ro = R_OUT + WALL_T
    top_in, top_out, bot_out = [], [], []
    for (a, _k, _w), (t, jog) in zip(cols, tops):
        top_in.append(m.v((R_OUT * math.cos(a), R_OUT * math.sin(a), t)))
        top_out.append(m.v((ro * math.cos(a), ro * math.sin(a), t - 0.1 * jog)))
        bot_out.append(m.v((ro * math.cos(a), ro * math.sin(a), SLAB_Z)))
    n = len(cols)
    for j in range(n):
        jn = (j + 1) % n
        a1 = cols[jn][0] if jn else cols[0][0] + TWO_PI
        am = 0.5 * (cols[j][0] + a1)
        zone = zone_of(am)
        m.quad(foot[j], foot[jn], top_in[jn], top_in[j], (-math.cos(am), -math.sin(am), 0.0), zone)
        m.quad(top_in[j], top_in[jn], top_out[jn], top_out[j], UP, zone)
        m.quad(top_out[j], top_out[jn], bot_out[jn], bot_out[j], (math.cos(am), math.sin(am), 0.0), zone)
    return bot_out


def _plinth(m, lip, cols):
    """Chamfer up from the floor's inner ring to the plinth top, then in."""
    n = len(cols)
    ch = [m.v((R_PLINTH * math.cos(a), R_PLINTH * math.sin(a), PLINTH_Z)) for (a, _k, _w) in cols]
    for j in range(n):
        jn = (j + 1) % n
        a1 = cols[jn][0] if jn else cols[0][0] + TWO_PI
        am = 0.5 * (cols[j][0] + a1)
        m.quad(lip[j], lip[jn], ch[jn], ch[j], (math.cos(am), math.sin(am), 1.0), ZONE_DAIS)
    prev = ch
    for rr in PLINTH_RINGS:
        ring = [m.v((rr * math.cos(a), rr * math.sin(a), PLINTH_Z)) for (a, _k, _w) in cols]
        for j in range(n):
            jn = (j + 1) % n
            m.quad(prev[j], prev[jn], ring[jn], ring[j], UP, ZONE_DAIS)
        prev = ring
    ct = m.v((0.0, 0.0, PLINTH_Z))
    for j in range(n):
        m.tri(prev[j], prev[(j + 1) % n], ct, UP, ZONE_DAIS)


def _wall_zone(am):
    return ZONE_ROCK if _wedge_of(am) == HELL_WEDGE else ZONE_SIDE


def _rock():
    m = _Mesh()
    rings = [R_IN + (R_OUT - R_IN) * i / N_RINGS for i in range(N_RINGS + 1)]
    g = _Grid(m, rings, True, N_INT, True, _Rng(SEED))
    for w in range(N_WEDGE):
        if w != HELL_WEDGE:
            g.cut(*_dais(m, w))
    g.cut(*_pool(m))
    spikes = []
    for k in range(len(SPIKES)):
        hole, sp = _spike(m, k)
        g.cut(*hole)
        spikes.append(sp)
    g.emit()
    bot = _wall(m, g.V[-1], g.cols[-1], _wall_zone)
    cb = m.v((0.0, 0.0, SLAB_Z))
    for j in range(g.nc):
        m.tri(bot[j], bot[(j + 1) % g.nc], cb, DOWN, ZONE_SIDE)
    _plinth(m, g.V[0], g.cols[0])
    return m, spikes


def _collider():
    c = _Mesh()
    rings = [R_IN + (R_OUT - R_IN) * i / COLL_RINGS for i in range(COLL_RINGS + 1)]
    g = _Grid(c, rings, False, COLL_INT, False, None)
    g.cut(*_pool(c, coll=True))
    g.emit()
    for w in range(N_WEDGE):
        if w != HELL_WEDGE:
            _dais(c, w, coll=True)
    for k in range(len(SPIKES)):
        _spike(c, k, coll=True)
    cols = _columns(R_OUT, True, N_INT)                  # the wall top, column for column
    foot = [c.v((R_OUT * math.cos(a), R_OUT * math.sin(a), 0.0)) for (a, _k, _w) in cols]
    bot = _wall(c, foot, cols, lambda am: ZONE_SIDE)
    cb = c.v((0.0, 0.0, SLAB_Z))
    for j in range(len(cols)):
        c.tri(bot[j], bot[(j + 1) % len(cols)], cb, DOWN, ZONE_SIDE)
    _plinth(c, g.V[0], g.cols[0])
    return c


# =============================================================================
# UV
# =============================================================================

def _lava_uv(me, uvl, poly):
    """The river sheet over the pool, streaked along the pool's long axis."""
    cx, cy, _ = pol(POOL_B, POOL_RAD)
    phi = math.radians(POOL_B) + 0.5 * math.pi
    for li in poly.loop_indices:
        co = me.vertices[me.loops[li].vertex_index].co
        dx, dy = co[0] - cx, co[1] - cy
        u = dx * math.cos(phi) + dy * math.sin(phi)
        v = -dx * math.sin(phi) + dy * math.cos(phi)
        uvl.data[li].uv = (0.5 + u / FLOW_SPAN, 0.5 + v / CROSS_SPAN)


def _deck_uv(me, uvl, poly, zone, r):
    """Deck facets project in (radius, arc): even grain all the way round."""
    u0, v0, u1, v1 = zone
    span_u = (u1 - u0) - 2.0 * UV_PAD
    span_v = (v1 - v0) - 2.0 * UV_PAD
    cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
    ac = math.atan2(sum(c[1] for c in cos), sum(c[0] for c in cos))
    rc = sum(math.hypot(c[0], c[1]) for c in cos) / len(cos)
    pts = []
    for co in cos:
        rad = math.hypot(co[0], co[1])
        th = math.atan2(co[1], co[0])
        th = ac + (th - ac + math.pi) % TWO_PI - math.pi
        pts.append((rad * DECK_UV_SCALE, (th - ac) * rc * DECK_UV_SCALE))
    mi = min(p[0] for p in pts)
    mj = min(p[1] for p in pts)
    w = max(p[0] for p in pts) - mi
    h = max(p[1] for p in pts) - mj
    k = min(1.0, 1.0 / max(w, h, EPS))
    pts = [(k * (p[0] - mi), k * (p[1] - mj)) for p in pts]
    w, h = k * w, k * h
    ou, ov = r.f() * (1.0 - w), r.f() * (1.0 - h)
    fu = -1.0 if r.i(0, 1) else 1.0
    fv = -1.0 if r.i(0, 1) else 1.0
    for li, p in zip(poly.loop_indices, pts):
        s = min(ou + p[0], 1.0)
        t = min(ov + p[1], 1.0)
        if fu < 0.0:
            s = 1.0 - s
        if fv < 0.0:
            t = 1.0 - t
        uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


def _box_uv(me, uvl, poly, zone, r):
    """Major-axis projection into an atlas cell at UV_SCALE texel density."""
    u0, v0, u1, v1 = zone
    span_u = (u1 - u0) - 2.0 * UV_PAD
    span_v = (v1 - v0) - 2.0 * UV_PAD
    nrm = poly.normal
    ax = max(range(3), key=lambda i: abs(nrm[i]))
    ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
    fu = -1.0 if r.i(0, 1) else 1.0
    fv = -1.0 if r.i(0, 1) else 1.0
    cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
    mi = min(co[ii] for co in cos)
    mj = min(co[jj] for co in cos)
    w = min((max(co[ii] for co in cos) - mi) * UV_SCALE, 1.0)
    h = min((max(co[jj] for co in cos) - mj) * UV_SCALE, 1.0)
    ou = r.f() * (1.0 - w)
    ov = r.f() * (1.0 - h)
    for li, co in zip(poly.loop_indices, cos):
        s = min(ou + (co[ii] - mi) * UV_SCALE, 1.0)
        t = min(ov + (co[jj] - mj) * UV_SCALE, 1.0)
        if fu < 0.0:
            s = 1.0 - s
        if fv < 0.0:
            t = 1.0 - t
        uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


def unwrap(ob, zones):
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        zone = zones[pi]
        if zone[0] == "river":
            _lava_uv(me, uvl, poly)
        elif zone[0] == "deck":
            _deck_uv(me, uvl, poly, zone[1:], r)
        elif zone[0] == "stone":
            _box_uv(me, uvl, poly, zone[1:], r)
        else:
            _box_uv(me, uvl, poly, zone, r)


# =============================================================================
# RENDERS -- review-lit, hand-placed cameras via TRACK_TO
# =============================================================================

def _hub_render(spec, objects):
    scene = bpy.context.scene
    if spec.get("engine", "eevee").lower() == "cycles":
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = int(spec.get("samples", 64))
        scene.cycles.use_denoising = True
    else:
        scene.render.engine = "BLENDER_EEVEE"
        mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 64)))
        mdl._try(scene.eevee, "use_shadows", True)
        mdl._try(scene.eevee, "use_raytracing", True)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")
    mdl._try(scene.view_settings, "exposure", REVIEW_EXPOSURE)

    world = bpy.data.worlds.new("Review")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.50, 0.48, 0.47, 1.0)
    bg.inputs[1].default_value = REVIEW_WORLD
    sd = bpy.data.lights.new("ReviewSun", type="SUN")
    sd.energy, sd.color = REVIEW_SUN, (1.0, 0.96, 0.92)
    sun = mdl._link(bpy.data.objects.new("ReviewSun", sd))
    aim = mdl._link(bpy.data.objects.new("ReviewAim", None))
    sun.location = pol(250.0, 60.0, 70.0)
    con = sun.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"

    target = mdl._link(bpy.data.objects.new("HubTarget", None))
    cam = mdl._link(bpy.data.objects.new("HubCam", bpy.data.cameras.new("HubCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    out_dir = spec.get("out_dir", ".")

    def shot(name, loc, tgt, lens, res):
        cam.data.lens = lens
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    company = _company()
    shot("eye", pol(18.0, 37.0, EYE_H), (0.0, 0.0, 16.0), 17.0, (1200, 1000))
    shot("walk", pol(95.0, 31.0, EYE_H), pol(175.0, 15.0, 8.0), 18.0, (1400, 800))
    shot("high", pol(215.0, 95.0, 55.0), (0.0, 0.0, 12.0), 28.0, (1500, 1000))
    shot("top", (0.0, -0.5, 130.0), (0.0, 0.0, 0.0), 32.0, (1200, 1200))
    shot("hell", pol(26.0, 38.5, 3.5), (26.1, 10.4, -0.2), 22.0, (1400, 900))

    for ob in (cam, target, sun, aim) + tuple(company):
        bpy.data.objects.remove(ob, do_unlink=True)
    if not spec.get("cams"):
        spec["views"] = []          # the named views frame 82 m of floor as a rifle; skip them


def _company():
    """The tower on the plinth and the eye over it, for the renders only."""
    made = []
    for path, z, scale in ((TOWER_GLB, PLINTH_Z + TOWER_FOOT, 1.0),
                           (EYE_GLB, PLINTH_Z + TOWER_FOOT + EYE_H_OVER_TOWER, EYE_RADIUS)):
        if not os.path.isfile(path):
            print("MDL note: no %s; rendering without it" % path)
            continue
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        for ob in set(bpy.data.objects) - before:
            if ob.parent is None:
                ob.location = (0.0, 0.0, z)
                ob.scale = (scale, scale, scale)
            if "colonly" in ob.name:
                ob.hide_render = True
            made.append(ob)
        print("MDL note: %s placed at z=%.2f for the renders" % (os.path.basename(path), z))
    bpy.context.view_layer.update()
    return made


# =============================================================================
# BUILD
# =============================================================================

def build():
    rock, spikes = _rock()
    coll = _collider()

    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    river_albedo, river_emissive = _sheet("river", _river_texture)
    mdl.save_texture(river_albedo)
    mdl.save_texture(river_emissive)
    stone_albedo, stone_emissive = build_stone_texture()
    mdl.save_texture(stone_albedo)
    mdl.save_texture(stone_emissive)

    ob = rock.object(OBJECT_NAME)
    unwrap(ob, rock.zones)
    mdl.finish(ob, rock_material("HellRock", albedo, emissive), strip_uvs=False)
    ob.data.materials.append(rock_material("Lava", river_albedo, river_emissive))
    ob.data.materials.append(rock_material("HubStone", stone_albedo, stone_emissive))
    counts = [0, 0, 0]
    for pi, poly in enumerate(ob.data.polygons):
        z = rock.zones[pi][0]
        idx = 1 if z == "river" else (2 if z == "stone" else 0)
        poly.material_index = idx
        counts[idx] += 1

    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d hellrock=%d lava=%d stone=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), counts[0], counts[1], counts[2]))
    print("MDL STATS ring r=%.1f..%.1f plinth r=%.1f y=%.2f wall_top=%.1f..%.1f slab_y=%.1f lava_y=%.2f"
          % (R_IN, R_OUT, R_PLINTH, PLINTH_Z, WALL_H[0], WALL_H[1], SLAB_Z, LAVA_Z))
    print("MDL STATS spikes H=%s R=%s" % (" ".join("%.1f" % s.H for s in spikes),
                                          " ".join("%.2f" % s.R for s in spikes)))
    return [ob, coll_ob]


def _check():
    """--check: build the geometry without Blender and prove the rock is one
    closed manifold (every edge in exactly two faces, opposite directions)."""
    rock, spikes = _rock()
    coll = _collider()
    for name, m in (("rock", rock), ("coll", coll)):
        edges = {}
        for f in m.faces:
            for k in range(3):
                e = (f[k], f[(k + 1) % 3])
                edges[e] = edges.get(e, 0) + 1
        bad = sum(1 for (a, b), n in edges.items() if n != 1 or edges.get((b, a), 0) != 1)
        degen = 0
        for f in m.faces:
            n = _newell([m.verts[i] for i in f])
            if math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) < 1e-7:
                degen += 1
        zones = {}
        for z in m.zones:
            key = z[0] if isinstance(z[0], str) else "rock"
            zones[key] = zones.get(key, 0) + 1
        print("%s tris=%d verts=%d nonmanifold_edges=%d degenerate=%d zones=%s"
              % (name, len(m.faces), len(m.verts), bad, degen, zones))
    print("spikes " + " ".join("H=%.1f R=%.2f" % (s.H, s.R) for s in spikes))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_hub_render)
