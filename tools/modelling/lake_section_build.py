"""
PANOPTICON -- lake_section: the lava river, sunk into the ring deck.

The deck between bearings 292.3 and 338.3 is cut away and replaced by a river
of lava brimming 0.7 m under it, at y 22.3, with rock shores at both ends. It
issues from a low slot at the foot of the shaft wall (r 57.3, 300.3..306.3 deg,
head at y 22.75 so the wall and the deck over it are never cut) and leaves over
the inner lip (r 46.7) as ONE sheet down the section's whole inner edge.
Seven rock pillars stand 1.2 m out of it on a 7.0 m zigzag; the three inner
ones carry a rock fin on the tower side, tall enough to hide a runner on them.

Authored in WORLD coordinates, like map_base_build.py, so the scene instances
it at identity. Blender +Z -> Godot +Y, Blender +Y -> Godot -Z, and a game
bearing of b degrees is Blender angle -b.

Two surfaces: HellRock (the tower's atlas, same painter and seed) and LavaRiver
(its own tiling sheet, streaked along the flow). Collision rides in the .glb as
a `-colonly` node and covers ONLY what a runner may stand on -- rock above
y 22.5, pillar tops and sides, fins. Nothing below that, and nothing on the
lava or the fall: the scene's TrapVolume owns the kill.

    tools/modelling/model build lake_section --cpu --samples 24 --cam 300,25 --cam 320,8
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# The model hangs 8 m below its own deck; mdl's ground plane would sit under
# the waterfall and light it from below.
mdl.DEFAULTS["ground"] = False
mdl.DEFAULTS["world_grey"] = 0.24
mdl.DEFAULTS["world_strength"] = 0.80

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "lake_section"
OBJECT_NAME = "LakeSection"
COLLIDER_NAME = "LakeCollision-colonly"
MARKER_NAME = "LavaSurface"

A0, A1 = 292.3, 338.3           # section extent, game bearings; 1 deg columns
NCOL = int(round(A1 - A0))
RAMP_IN = (292.3, 294.3)        # entry bank: deck level -> the river
RAMP_OUT = (336.3, 338.3)       # exit bank

INNER_R = 46.7                  # the lip of the void
OUTER_R = 57.3                  # foot of the shaft wall
DECK_Z = 23.0
LAVA_Z = 22.30                  # the river surface -- the TrapVolume's height
LAVA_SWELL = 0.04

# Trench cross-section: (radius, rock height). The river brims 0.7 m under the
# deck and the rock never rises to meet it on the tower side, so it leaves over
# the lip along the WHOLE inner edge. Outboard it crosses 22.3 at r 56.77.
CP_BASE = [(46.70, 21.95), (47.60, 21.60), (48.60, 21.40),
           (55.40, 21.40), (56.50, 21.95), (57.30, 23.00)]
CP_SHOULDER = [(55.40, 21.40), (56.50, 21.80), (57.30, 22.35)]  # slot jamb
CP_FLOOR = [(55.40, 21.40), (56.50, 21.45), (57.30, 21.55)]     # slot sill

RST = [46.70, 47.60, 48.60, 50.00, 51.40, 52.80, 54.20, 55.40,
       56.00, 56.50, 56.90, 57.30]

BED_JAG = 0.14                  # rock jitter in the trench

# ---- the river mouth: a low slot at the foot of the wall. Its head is under
# the deck plane, so the wall and the deck over it are never cut.
MOUTH_FLOOR = [301.3, 302.3, 303.3, 304.3, 305.3]   # the open channel
MOUTH_LEDGE = [300.3, 306.3]                        # jambs, slot narrowing
MOUTH_BACK = 60.0
MOUTH_CEIL = 22.75              # slot head: 0.45 m over the river, 0.25 under
                                # the deck, so rock carries on above it

# ---- the fall: ONE sheet off the whole lip --------------------------------
FALL_DROP = (6.0, 8.0)          # metres below the lip
FALL_GAP = 0.55                 # ... except where the curtain tears
FALL_ROWS = 5
FALL_SUB = 2                    # sheet columns per degree of lip
FALL_OUT = 2.00                 # how far the sheet leans in off the lip; it has
                                # to clear map_base's jittered pit wall

# ---- the run: 7 pillars, 7.00 m centre to centre, alternating r ------------
PIL_OUT_R = 54.8
PIL_IN_R = 50.2
PIL_STEP = 5.7676               # degrees: chord(54.8, 50.2, step) = 7.000 m
PIL_B0 = 298.0
PIL_TOP_Z = 23.5
PIL_HALF = (1.40, 1.30)         # (outer, inner) circumradius at the top
PIL_SIDES = 7

FIN_R = 48.50                   # tower side of each inner pillar
FIN_TOP_Z = 27.30               # 3.8 m over the pillar top
FIN_HALF_T = 1.70               # tangential
FIN_HALF_R = 0.42               # radial

SEED = 5140737
EYE_H = 1.65

# ---- rock atlas: byte-identical to tower_build.py / map_base_build.py ------
TEX_SIZE = 128
TEX_ALBEDO = "lake_rock_albedo"
TEX_EMISSIVE = "lake_rock_emissive"
TEX_SEED = 6661031
ROCK_ROUGHNESS = 0.95
ROCK_METALLIC = 0.0
UV_SCALE = 0.13
UV_PAD = 1.5 / TEX_SIZE

ZONE_ROCK = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)
ZONE_CARVE = (0.5, 0.0, 1.0, 0.5)
ZONE_EMBER = (0.0, 0.0, 0.5, 0.5)
ZONE_DECK = ("deck",) + ZONE_SHADE
DECK_UV_SCALE = 0.34

# ---- the river sheet: its own tiling texture, streaked along the flow ------
ZONE_LAVA = ("lava",)           # flow runs radially, wall -> lip
ZONE_FALL = ("fall",)           # flow runs down
RIVER_TEX = 256
RIVER_ALBEDO = "lake_river_albedo"
RIVER_EMISSIVE = "lake_river_emissive"
RIVER_SEED = 7720133
FLOW_SPAN = 10.0                # metres per texture repeat along the flow
CROSS_SPAN = 10.0               # ... and across it
CROSS_R = 52.0                  # nominal radius the tangential UV is measured at

FACING_YAW = 0.0

TWO_PI = 2.0 * math.pi
UP = (0.0, 0.0, 1.0)
DOWN = (0.0, 0.0, -1.0)
EPS = 1e-9


# =============================================================================
# TEXTURE
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


def build_texture():
    c = _Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    _paint_rock(c, r, _rect_of(ZONE_ROCK, TEX_SIZE))
    _paint_shade(c, r, _rect_of(ZONE_SHADE, TEX_SIZE))
    _paint_carve(c, r, _rect_of(ZONE_CARVE, TEX_SIZE))
    _paint_ember(c, r, _rect_of(ZONE_EMBER, TEX_SIZE))
    return _images(c, TEX_SIZE, TEX_ALBEDO, TEX_EMISSIVE)


def _images(c, size, albedo_name, emissive_name):
    out = []
    for name, buf in ((albedo_name, c.alb), (emissive_name, c.emi)):
        img = bpy.data.images.new(name, size, size, alpha=False)
        img.colorspace_settings.name = "sRGB"
        img.pixels.foreach_set(buf)
        img.update()
        out.append(img)
    return out[0], out[1]


def _river_texture():
    """The river: molten, with everything STREAKED along +U, which every lava
    face maps to its own flow direction. Wraps on both axes so it tiles."""
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

    for _ in range(90):                       # crust rafts, drawn out by the flow
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        w, h = r.i(18, 70), r.i(2, 7)
        sh = r.pick(crust)
        for dy in range(h):
            for dx in range(w):
                c.wrap(x + dx, y + dy + (dx // 26), sh, (0, 0, 0))

    for _ in range(150):                      # dark filaments: the shear lines
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        sh = r.pick(crust)
        for dx in range(r.i(30, 110)):
            c.wrap(x + dx, y, sh, (6, 2, 2))
            if r.i(0, 6) == 0:
                y += r.i(-1, 1)

    for _ in range(200):                      # warm streaks either side of them
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        sh = r.pick(warm)
        for dx in range(r.i(20, 90)):
            c.wrap(x + dx, y, sh, sh)
            if r.i(0, 8) == 0:
                y += r.i(-1, 1)

    for _ in range(120):                      # white-hot cores, long and thin
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        core = r.pick([(255, 216, 104), (255, 184, 64), (255, 232, 150)])
        for dx in range(r.i(8, 46)):
            c.wrap(x + dx, y, core, core)
            if r.i(0, 10) == 0:
                y += r.i(-1, 1)
    return _images(c, RIVER_TEX, RIVER_ALBEDO, RIVER_EMISSIVE)


def tex_material(name, albedo, emissive, double_sided=False):
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
    mat.use_backface_culling = not double_sided
    mat.diffuse_color = (0.13, 0.04, 0.04, 1.0)
    return mat


# =============================================================================
# GEOMETRY -- winding is checked against a wanted normal, never assumed
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
        for i in range(1, len(ring) - 1):
            self.tri(ring[0], ring[i], ring[i + 1], want, zone)

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


def pol(bearing_deg, radius, z):
    """A game bearing in Blender world coordinates (Godot +Z is Blender -Y)."""
    a = math.radians(-bearing_deg)
    return (radius * math.cos(a), radius * math.sin(a), z)


def _radial(bearing_deg):
    a = math.radians(-bearing_deg)
    return (math.cos(a), math.sin(a), 0.0)


def _tangent(bearing_deg):
    a = math.radians(-bearing_deg)
    return (-math.sin(a), math.cos(a), 0.0)


def _lerp(a, b, t):
    return a + (b - a) * t


def _smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


def _interp(cps, x):
    if x <= cps[0][0]:
        return cps[0][1]
    for (x0, y0), (x1, y1) in zip(cps, cps[1:]):
        if x <= x1:
            return _lerp(y0, y1, (x - x0) / max(x1 - x0, EPS))
    return cps[-1][1]


# =============================================================================
# THE TRENCH
# =============================================================================

def _mouth_c(b):
    if any(abs(b - x) < 0.01 for x in MOUTH_FLOOR):
        return 1.0
    if any(abs(b - x) < 0.01 for x in MOUTH_LEDGE):
        return 0.5
    return 0.0


def _shore(b):
    if b <= RAMP_IN[1]:
        return 1.0 - _smooth((b - RAMP_IN[0]) / (RAMP_IN[1] - RAMP_IN[0]))
    if b >= RAMP_OUT[0]:
        return _smooth((b - RAMP_OUT[0]) / (RAMP_OUT[1] - RAMP_OUT[0]))
    return 0.0


def bed(b, r):
    """Rock height of the trench floor/banks at (bearing, radius)."""
    z = _interp(CP_BASE, r)
    mc = _mouth_c(b)
    if mc > 0.0 and r >= 55.40:
        z = _interp(CP_SHOULDER if mc == 0.5 else CP_FLOOR, r)
    return _lerp(z, DECK_Z, _shore(b))


def _rock_zone(pts):
    """Atlas zone from what the facet is: deck, living rock, shadow, cleft."""
    zs = [p[2] for p in pts]
    zc = sum(zs) / len(zs)
    dz = max(zs) - min(zs)
    span = max(max(p[0] for p in pts) - min(p[0] for p in pts),
               max(p[1] for p in pts) - min(p[1] for p in pts), EPS)
    steep = dz / span > 1.1
    if zc > 22.85 and not steep:
        return ZONE_DECK
    if zc < 22.10:
        return ZONE_EMBER
    if zc < 22.60 or steep:
        return ZONE_SHADE
    return ZONE_ROCK


def _trench(m, r):
    """The rock grid, then the lava laid over everything it covers."""
    cols = [A0 + i for i in range(NCOL + 1)]
    nr = len(RST)
    jit = [[0.0] * nr for _ in range(NCOL + 1)]
    for i, b in enumerate(cols):
        amp = BED_JAG * (1.0 - _shore(b))
        for j in range(1, nr - 1):
            jit[i][j] = amp * r.sf()
    grid = [[m.v(pol(b, RST[j], bed(b, RST[j]) + jit[i][j])) for j in range(nr)]
            for i, b in enumerate(cols)]
    zof = [[m.verts[grid[i][j]][2] for j in range(nr)] for i in range(NCOL + 1)]

    for i in range(NCOL):
        for j in range(nr - 1):
            pts = [m.verts[grid[i][j]], m.verts[grid[i + 1][j]],
                   m.verts[grid[i + 1][j + 1]], m.verts[grid[i][j + 1]]]
            m.quad(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1],
                   UP, _rock_zone(pts))

    lava = 0
    for i in range(NCOL):
        for j in range(nr - 1):
            corners = (zof[i][j], zof[i + 1][j], zof[i + 1][j + 1], zof[i][j + 1])
            if min(corners) >= LAVA_Z - 0.02:
                continue
            ring = []
            for (ci, cj) in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)):
                ring.append(m.v(pol(cols[ci], RST[cj],
                                    LAVA_Z + LAVA_SWELL * math.sin(1.7 * ci + 2.3 * cj))))
            m.quad(ring[0], ring[1], ring[2], ring[3], UP, ZONE_LAVA)
            lava += 1
    return lava


# =============================================================================
# THE MOUTH -- a tunnel under the wall; its lintel is the deck plane
# =============================================================================

def _mouth(m):
    b0, b1 = MOUTH_LEDGE[0], MOUTH_LEDGE[1]
    cols = [b0 + k for k in range(int(round(b1 - b0)) + 1)]
    rs = [OUTER_R, OUTER_R + 0.9, OUTER_R + 1.8, MOUTH_BACK]

    def floor_z(b, rr):
        return bed(b, OUTER_R)

    grid = [[m.v(pol(b, rr, floor_z(b, rr))) for rr in rs] for b in cols]
    for i in range(len(cols) - 1):
        for j in range(len(rs) - 1):
            zc = 0.25 * sum(m.verts[grid[a][bb]][2]
                            for (a, bb) in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)))
            zone = ZONE_SHADE if zc > LAVA_Z else ZONE_EMBER
            m.quad(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1], UP, zone)

    # side walls facing into the tunnel, then the ceiling and the back
    for k, b in ((0, cols[0]), (len(cols) - 1, cols[-1])):
        into = -1.0 if k == 0 else 1.0
        for j in range(len(rs) - 1):
            t0 = m.v(pol(b, rs[j], MOUTH_CEIL))
            t1 = m.v(pol(b, rs[j + 1], MOUTH_CEIL))
            m.quad(grid[k][j], grid[k][j + 1], t1, t0,
                   _mul(_tangent(b), into), ZONE_SHADE)

    ceil = [[m.v(pol(b, rr, MOUTH_CEIL)) for rr in rs] for b in cols]
    for i in range(len(cols) - 1):
        for j in range(len(rs) - 1):
            m.quad(ceil[i][j], ceil[i + 1][j], ceil[i + 1][j + 1], ceil[i][j + 1],
                   DOWN, ZONE_SHADE)
    for i in range(len(cols) - 1):
        m.quad(grid[i][-1], grid[i + 1][-1], ceil[i + 1][-1], ceil[i][-1],
               _mul(_radial(cols[i]), -1.0), ZONE_SHADE)

    # The lintel: the slot's head is under the deck, so rock carries on above
    # it and neither the deck nor the wall is ever cut.
    for i in range(len(cols) - 1):
        a0 = ceil[i][0]
        a1 = ceil[i + 1][0]
        t0 = m.v(pol(cols[i], OUTER_R, DECK_Z))
        t1 = m.v(pol(cols[i + 1], OUTER_R, DECK_Z))
        m.quad(a0, a1, t1, t0, _mul(_radial(cols[i]), -1.0), ZONE_SHADE)

    # the river carrying on into the slot, to stop in the dark
    for i in range(len(cols) - 1):
        if _mouth_c(cols[i]) != 1.0 or _mouth_c(cols[i + 1]) != 1.0:
            continue
        for j in range(len(rs) - 1):
            ring = [m.v(pol(cols[i], rs[j], LAVA_Z)),
                    m.v(pol(cols[i + 1], rs[j], LAVA_Z)),
                    m.v(pol(cols[i + 1], rs[j + 1], LAVA_Z)),
                    m.v(pol(cols[i], rs[j + 1], LAVA_Z))]
            m.quad(ring[0], ring[1], ring[2], ring[3], UP, ZONE_LAVA)
    return cols, rs


def _mul(v, s):
    return (v[0] * s, v[1] * s, v[2] * s)


# =============================================================================
# THE FALL -- ONE sheet, the whole inner edge of the section
# =============================================================================

def _fall(m, r):
    """The river leaves along its entire lip. Weight of flow walks along the
    length, so the sheet is thick and long in places, torn open in others --
    not a flat curtain."""
    b0, b1 = RAMP_IN[1] - 0.5, RAMP_OUT[0] + 0.5
    n = int(round((b1 - b0) * FALL_SUB))
    bs = [b0 + (b1 - b0) * k / float(n) for k in range(n + 1)]

    flow = []
    cur = 0.7
    for _ in bs:
        cur = min(1.0, max(0.35, cur + 0.20 * r.sf()))
        flow.append(cur)
    for _ in range(6):                          # tears in the curtain
        k = r.i(4, n - 4)
        for d in range(-1, 2):
            flow[k + d] = 0.0
    for k in range(n + 1):                      # ... and it dies into the shores
        flow[k] *= min(1.0, min(k, n - k) / 5.0)

    rows = FALL_ROWS
    ids = []
    for k, b in enumerate(bs):
        f = flow[k]
        drop = FALL_GAP + (FALL_DROP[0] + (FALL_DROP[1] - FALL_DROP[0]) * f
                           - FALL_GAP) * (f ** 0.4)
        lean = FALL_OUT * (0.45 + 0.75 * f)
        skin = 0.30 * r.f()                     # the sheet's own thickness
        col = []
        for iv in range(rows + 1):
            t = iv / float(rows)
            rr = INNER_R - 0.08 - skin - lean * (t ** 1.6) - 0.10 * r.f()
            col.append(m.v(pol(b, rr, LAVA_Z - drop * t)))
        ids.append(col)
    for k in range(n):
        for iv in range(rows):
            m.quad(ids[k][iv], ids[k + 1][iv], ids[k + 1][iv + 1], ids[k][iv + 1],
                   _mul(_radial(bs[k]), -1.0), ZONE_FALL)
    return n * rows


# =============================================================================
# PILLARS AND FINS
# =============================================================================

def _pillars():
    out = []
    for k in range(7):
        b = PIL_B0 + PIL_STEP * k
        out.append((b, PIL_OUT_R if k % 2 == 0 else PIL_IN_R, k % 2 == 1))
    return out


def _column(m, bearing, radius, sect, rings, r, top_zone, ragged=0.0):
    """An irregular faceted column. ``sect`` is [(d_radial, d_tangential), ...];
    ``rings`` is [(z, scale), ...] bottom to top."""
    er, et = _radial(bearing), _tangent(bearing)
    base = pol(bearing, radius, 0.0)
    lvl = []
    for (z, sc) in rings:
        ring = []
        for (dr, dt) in sect:
            p = (base[0] + er[0] * dr * sc + et[0] * dt * sc,
                 base[1] + er[1] * dr * sc + et[1] * dt * sc,
                 z + (ragged * r.sf() if ragged else 0.0))
            ring.append(m.v(p))
        lvl.append(ring)
    ns = len(sect)
    for a in range(len(lvl) - 1):
        for i in range(ns):
            j = (i + 1) % ns
            mid = (0.5 * (sect[i][0] + sect[j][0]), 0.5 * (sect[i][1] + sect[j][1]))
            want = (er[0] * mid[0] + et[0] * mid[1], er[1] * mid[0] + et[1] * mid[1], 0.0)
            zc = 0.5 * (rings[a][0] + rings[a + 1][0])
            m.quad(lvl[a][i], lvl[a][j], lvl[a + 1][j], lvl[a + 1][i], want,
                   ZONE_EMBER if zc < 20.9 else ZONE_SHADE)
    m.fan(lvl[-1], UP, top_zone)
    return lvl


def _pillar_sect(half, sides, r):
    sect = []
    for i in range(sides):
        a = TWO_PI * (i + 0.32 * r.sf()) / sides
        k = half * (0.80 + 0.20 * r.f())
        sect.append((k * math.cos(a), k * math.sin(a)))
    return sect


def _fin_sect(r):
    pts = []
    for i in range(6):
        a = TWO_PI * (i + 0.22 * r.sf()) / 6
        pts.append((FIN_HALF_R * math.cos(a) * (0.8 + 0.2 * r.f()),
                    FIN_HALF_T * math.sin(a) * (0.85 + 0.15 * r.f())))
    return pts


SECTS = {}      # pillar index -> (pillar section, fin section or None).
                # The collider re-uses these; a second draw from the rng would
                # give it a different polygon from the one you can see.


def _build_pillars(m, r):
    for k, (b, rad, inner) in enumerate(_pillars()):
        half = PIL_HALF[1] if inner else PIL_HALF[0]
        sect = _pillar_sect(half, PIL_SIDES, r)
        fs = _fin_sect(r) if inner else None
        SECTS[k] = (sect, fs)
        _column(m, b, rad, sect,
                [(20.90, 1.22), (21.80, 1.14), (22.70, 1.06), (PIL_TOP_Z, 1.0)],
                r, ZONE_ROCK)
        if inner:
            _column(m, b, FIN_R, fs,
                    [(20.80, 1.30), (22.40, 1.12), (23.90, 1.0),
                     (25.60, 0.88), (FIN_TOP_Z, 0.70)],
                    r, ZONE_SHADE, ragged=0.22)


# =============================================================================
# COLLISION -- only what a runner may stand on
# =============================================================================

COLL_MIN_Z = 22.50
COLL_RST = [46.70, 47.60, 48.60, 55.40, 56.50, 56.90, 57.30]


def _collider(r):
    c = _Mesh()
    cols = [A0 + 2.0 * k for k in range(int(round((A1 - A0) / 2.0)) + 1)]
    nr = len(COLL_RST)
    grid = [[c.v(pol(b, COLL_RST[j], bed(b, COLL_RST[j]))) for j in range(nr)]
            for b in cols]
    for i in range(len(cols) - 1):
        for j in range(nr - 1):
            zs = [c.verts[grid[a][bb]][2]
                  for (a, bb) in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
            if min(zs) < COLL_MIN_Z:
                continue
            c.quad(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1],
                   UP, ZONE_ROCK)

    for k, (b, rad, inner) in enumerate(_pillars()):
        sect, fs = SECTS[k]
        _column(c, b, rad, sect, [(22.00, 1.10), (PIL_TOP_Z, 1.0)], r, ZONE_ROCK)
        if inner:
            _column(c, b, FIN_R, fs, [(22.00, 1.14), (FIN_TOP_Z, 0.70)], r, ZONE_ROCK)

    # the floor of the river mouth: rock ledges either side of the channel,
    # the channel itself at lava height so standing in it is standing in lava.
    mcols = [MOUTH_LEDGE[0] + k
             for k in range(int(round(MOUTH_LEDGE[1] - MOUTH_LEDGE[0])) + 1)]
    for i in range(len(mcols) - 1):
        a0 = c.v(pol(mcols[i], OUTER_R, bed(mcols[i], OUTER_R)))
        a1 = c.v(pol(mcols[i + 1], OUTER_R, bed(mcols[i + 1], OUTER_R)))
        a2 = c.v(pol(mcols[i + 1], MOUTH_BACK, bed(mcols[i + 1], OUTER_R)))
        a3 = c.v(pol(mcols[i], MOUTH_BACK, bed(mcols[i], OUTER_R)))
        c.quad(a0, a1, a2, a3, UP, ZONE_ROCK)
    return c


# =============================================================================
# UV
# =============================================================================

def _flow_uv(me, uvl, poly, vertical):
    """The river's own sheet. U runs along the flow -- radially inward across
    the trench, straight down on a fall -- so the streaks always follow it."""
    for li in poly.loop_indices:
        co = me.vertices[me.loops[li].vertex_index].co
        rad = math.hypot(co[0], co[1])
        ang = math.atan2(co[1], co[0])
        u = ((LAVA_Z - co[2]) + (OUTER_R - INNER_R)) if vertical else (OUTER_R - rad)
        uvl.data[li].uv = (u / FLOW_SPAN, (-ang * CROSS_R) / CROSS_SPAN)


def _deck_uv(me, uvl, poly, zone, r):
    """Deck facets project in (radius, arc), as map_base's deck does, so the
    apron carries the same grain as the ring it plugs into."""
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


def unwrap(ob, zones, seed=0):
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + seed * 7919 + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        zone = zones[pi]
        if zone[0] == "lava":
            _flow_uv(me, uvl, poly, False)
            continue
        if zone[0] == "fall":
            _flow_uv(me, uvl, poly, True)
            continue
        if zone[0] == "deck":
            _deck_uv(me, uvl, poly, zone[1:], r)
            continue
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


# =============================================================================
# EXTRA RENDERS -- hand-placed, because mdl's rig only orbits the whole section
# =============================================================================

def _shots(spec, objects):
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

    world = bpy.data.worlds.new("Hell")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.26, 0.05, 0.04, 1.0)
    bg.inputs[1].default_value = 0.60
    ld = bpy.data.lights.new("KeyRed", type="SUN")
    ld.energy = 5.5
    ld.color = (1.0, 0.38, 0.30)
    key = mdl._link(bpy.data.objects.new("KeyRed", ld))
    key.rotation_euler = (math.radians(22.0), math.radians(14.0), math.radians(-40.0))

    target = mdl._link(bpy.data.objects.new("ShotTarget", None))
    cam = mdl._link(bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
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

    shot("run", pol(290.0, 52.5, DECK_Z + EYE_H), pol(312.0, 52.0, 22.7),
         26.0, (1400, 800))
    shot("top", pol(315.0, 10.0, 58.0), pol(315.3, 52.0, 22.4), 32.0, (1200, 1000))
    shot("fall", pol(316.0, 16.0, 20.5), pol(311.0, 46.6, 19.5), 22.0, (1400, 800))
    shot("mouth", pol(308.2, 51.0, 23.6), pol(303.3, 58.4, 22.4), 34.0, (1200, 800))
    shot("pillars", pol(300.5, 44.0, 28.0), pol(320.0, 52.0, 23.0), 34.0, (1300, 800))

    for ob in (cam, target, key):
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    r = _Rng(SEED)
    m = _Mesh()
    lava_cells = _trench(m, r)
    _mouth(m)
    fall_tris = 2 * _fall(m, r)
    _build_pillars(m, r)

    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    river_a, river_e = _river_texture()
    mdl.save_texture(river_a)
    mdl.save_texture(river_e)

    ob = m.object(OBJECT_NAME)
    unwrap(ob, m.zones)
    mdl.finish(ob, tex_material("HellRock", albedo, emissive), strip_uvs=False)
    ob.data.materials.append(tex_material("LavaRiver", river_a, river_e,
                                          double_sided=True))
    lava_tris = 0
    for pi, poly in enumerate(ob.data.polygons):
        if m.zones[pi][0] in ("lava", "fall"):
            poly.material_index = 1
            lava_tris += 1

    coll = _collider(_Rng(SEED))
    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True

    marker = mdl._link(bpy.data.objects.new(MARKER_NAME, None))
    marker.location = pol(0.5 * (A0 + A1), 52.0, LAVA_Z)
    marker.empty_display_size = 1.5

    tot = len(ob.data.polygons)
    print("MDL STATS visual_tris=%d rock_tris=%d lava_tris=%d collision_tris=%d"
          % (tot, tot - lava_tris, lava_tris, len(coll_ob.data.polygons)))
    print("MDL STATS lava_y=%.2f lava_cells=%d fall_tris=%d mouth=%.1f..%.1f deg head=%.2f"
          % (LAVA_Z, lava_cells, fall_tris, MOUTH_LEDGE[0], MOUTH_LEDGE[1], MOUTH_CEIL))
    print("MDL STATS section=%.1f..%.1f deg r=%.1f..%.1f deck_y=%.2f pillar_top=%.2f"
          % (A0, A1, INNER_R, OUTER_R, DECK_Z, PIL_TOP_Z))
    for k, (b, rad, inner) in enumerate(_pillars()):
        print("MDL STATS pillar%d bearing=%.3f r=%.1f %s"
              % (k + 1, b, rad, "inner+fin" if inner else "outer"))
    return [ob, coll_ob, marker]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_shots)
