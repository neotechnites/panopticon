"""
PANOPTICON -- aspens: Map 6, first pass. A big grove of fall aspens on open ground, no roof, and a
tree stump in the middle for the tower. ONE sculpt in one Blender scene, exported per chunk:

    aspens_ground.glb     the ground to the horizon; its inner rim IS the stump's foot ring   AspensGround
    aspens_stump.glb      the stump the guard stands on (instanced under Tower)                 AspensStump
    aspens_near0..7.glb   the grove out to NEAR_R, one chunk per 45 deg of bearing              AspensNear0..7
    aspens_far0..3.glb    the outer grove out to FOREST_R, low detail, one chunk per 90 deg     AspensFar0..3

Trees are six modelled aspens (VARIANTS) and three far ones (FAR_VARIANTS), placed turned and scaled;
leaves and grass tufts are alpha-cut cards (maps/aspens/materials/aspens_card.gdshader).
World coordinates, instanced at identity (Blender +Z -> Godot +Y, +Y -> Godot -Z; bearings as the
scene's markers, pol()). Sizes and colours: docs/maps/aspens.md.

    tools/modelling/model build aspens [--chunk near3] --views none
    python3 tools/modelling/maps/aspens/aspens_build.py --check
"""

import json
import math
import os
import sys

try:
    import bpy
except ImportError:                       # --check on the Mac: geometry only
    bpy = None

_HOME = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HOME)
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break
import texel as tx  # noqa: E402
if bpy is not None:
    import mdl  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "aspens"
SEED = 60125
FACING_YAW = 0.0
DECK_Z = 23.0               # every map's deck: the ground at the starts and at the stump

# -- size (docs/maps/aspens.md has the working)
START_R = 110.0             # the starts: 10.0 s at 11 m/s; a runner is 7.4 x 2.1 px unscoped at 1080p
CLEAR_R = 9.0               # no tree nearer the stump than this
NEAR_R = 138.0              # full-detail trees out to here (28 m past the starts)
FOREST_R = 215.0            # the grove's edge
HORIZON_R = (240.0, 270.0, 320.0, 400.0, 520.0, 700.0, 900.0)
SPOT_CLEAR = 2.5            # no trunk this near a start or finish marker
SPOTS = ((5.0, START_R), (335.0, START_R))

# -- spacing: a sightline's mean free path through the trunks is 1 / (density x trunk width).
TRUNK_W = 0.33              # mean trunk width at chest height (VARIANTS by weight)
FREE_PATH = START_R         # the guard's mean clear run: one start distance
DENSITY = 1.0 / (TRUNK_W * FREE_PATH)       # 0.0275 trees per m2
MIN_GAP = 3.6               # no two trunks nearer than this
FAR_DENSITY = DENSITY * 1.1                 # past the starts nobody aims through it: close the horizon
FAR_GAP = 3.2

# -- ground
SWELL = 0.45                # metres the ground rolls, +-
SWELL_M = 46.0              # over about this far
FLAT = ((0.0, 6.0, 16.0), (98.0, 104.0, 116.0, 122.0))   # flat at the stump, and on the starts' ring
PATCH_M = 30.0              # olive and green grass change over about this far
G_LIT = (0.26, 0.45, 0.51)  # x the olive tile = frame0's green grass (74, 89, 39)
G_DARK = (0.17, 0.3, 0.38)  # x the olive tile = frame0's shaded green (64, 78, 35)

# -- the stump: a giant aspen's, sawn flat
STUMP_H = 2.0               # the guard's floor: his eye 3.65 m over the ground (5.95 on the rings)
STUMP_R = 2.25              # the cut face's radius
STUMP_SEG = 28
STUMP_ROOTS = ((12.0, 1.25, 26.0), (63.0, 0.8, 20.0), (118.0, 1.1, 24.0), (171.0, 0.7, 18.0),
               (214.0, 1.3, 27.0), (268.0, 0.9, 22.0), (321.0, 1.05, 23.0))   # bearing, reach, half width
STUMP_Z = (0.0, 0.28, 0.75, 1.35, STUMP_H)
STUMP_FOOT = 2.65           # radius at the ground between roots
BARK_U = 1.6                # metres of trunk one turn of the bark tile wraps (32 texels)
BARK_V = 12.8

# -- trees: (height, trunk width at the foot, crown foot, limbs, weight); every trunk stands plumb
VARIANTS = (
    (21.0, 0.42, 10.5, 8, 3),
    (18.0, 0.30, 9.0, 7, 5),
    (23.5, 0.68, 12.0, 9, 1),
    (16.0, 0.24, 8.0, 6, 4),
    (19.5, 0.34, 10.0, 7, 4),
    (22.0, 0.52, 11.5, 8, 2),
)
FAR_VARIANTS = ((20.0, 0.44, 6.0, 0, 1), (16.5, 0.34, 3.6, 0, 1), (11.0, 0.24, 1.4, 0, 1))   # leaves lower toward the edge: the grove closes in gold, as istock's far trunks do
FAR_STEP = (165.0, 192.0)   # past these radii the lower-leaved far trees take over
SCALE = (0.88, 1.12)
TRUNK_RINGS = ((-0.5, 1.10), (1.3, 0.93), (0.45, 0.74), (0.78, 0.46), (-0.35, 0.12))   # z (m, share of H, m under the tip), share of the foot radius
BRANCH_COL = (0.047, 0.028, 0.017)          # x the bark tile = the photo's black (47, 34, 23)
LIMB = ((2.0, 3.8), (22.0, 50.0))           # a limb's reach (longest low in the crown) and its rise, degrees
CARD = (1.9, 2.8)           # a leaf mass: two crossed cards this wide
CARD_SHADE = ((0.72, 0.85, 1.0), (0.11, 0.48, 0.6), (0.17, 0.26, 0.35))   # (share, from, to) of leaf masses: the photo's bright, mid and dark leaf
LEAF_GLOW = 1.3             # LeafMat's glow, over the shade: the bright masses burn out to the photo's yellow
COLLIDER_TOP = 8.0          # trunks stop shots and bodies to here

# -- tufts: crossed grass cards, in the Minecraft frame's dry yellow and green
TUFT_R = 140.0              # out to here
TUFT_PER_TREE = (1, 3)      # round each near trunk's foot ...
TUFT_FOOT = (0.45, 1.7)     # ... this far out
TUFT_LOOSE = 2200           # and this many in the open
TUFT_SIZE = ((0.7, 1.05), (0.4, 0.72))      # width, height: under a runner's knee to mid thigh
TUFT_GREEN = (0.26, 0.53, 0.49)             # x the dry tile = frame0's lit green (85, 108, 45)

# -- the scene's light, restated by maps/aspens/aspens.tscn (the review renders use these)
SUN_BEARING = 140.0
SUN_EL = 50.0
SUN = 0.22
AMBIENT = 0.44
FOG = (70.0, 380.0, 0.8)                    # begin, end, density
FOG_COL = (244, 179, 75)                    # istock's far background between the trunks (p80)
SKY_TOP = (214, 216, 240)                   # istock's sky between the leaves
SKY_HORIZON = (246, 244, 239)               # istock's blown white
EYE = 1.65

TWO_PI = 2.0 * math.pi
UP = (0.0, 0.0, 1.0)
INFO = {}


# =============================================================================
# HELPERS
# =============================================================================

def pol(bearing_deg, radius, z):
    """Game bearing (as the scene's markers) -> Blender xyz."""
    a = math.radians(-bearing_deg)
    return (radius * math.cos(a), radius * math.sin(a), z)


def bearing_of(p):
    return (-math.degrees(math.atan2(p[1], p[0]))) % 360.0


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def ramp(x, a, b):
    t = clamp((x - a) / (b - a))
    return t * t * (3.0 - 2.0 * t)


def lerp3(p, q, t):
    return tuple(p[k] + (q[k] - p[k]) * t for k in range(3))


class Rng(object):
    """Deterministic LCG."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def f(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return (self.s >> 8) / float(0x7FFFFF)

    def u(self, a, b):
        return a + (b - a) * self.f()


def h2(i, j, seed):
    n = (i * 374761393 + j * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFFFF) / float(0x1000000)


def vnoise(x, y, seed):
    i, j = math.floor(x), math.floor(y)
    fx, fy = x - i, y - j
    fx, fy = fx * fx * (3.0 - 2.0 * fx), fy * fy * (3.0 - 2.0 * fy)
    a, b, c, d = h2(i, j, seed), h2(i + 1, j, seed), h2(i, j + 1, seed), h2(i + 1, j + 1, seed)
    return 2.0 * (a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy) - 1.0


def fbm(x, y, seed):
    return (vnoise(x, y, seed) + 0.5 * vnoise(2 * x, 2 * y, seed + 17) + 0.25 * vnoise(4 * x, 4 * y, seed + 34)) / 1.75


class Mesh(object):
    """Triangle accumulator: a face states where its normal points, its material zone and its
    chunk; vertices carry a colour (COLOR_0); uv[face] holds a custom zone's corner UVs."""

    def __init__(self):
        self.verts, self.cols, self.faces, self.zones, self.chunks, self.uv = [], [], [], [], [], {}

    def v(self, p, col=(1.0, 1.0, 1.0)):
        self.verts.append((float(p[0]), float(p[1]), float(p[2])))
        self.cols.append((col[0], col[1], col[2], 1.0))
        return len(self.verts) - 1

    def tri(self, a, b, c, want, zone, chunk, uvs=None):
        pa, pb, pc = self.verts[a], self.verts[b], self.verts[c]
        e1, e2 = [pb[k] - pa[k] for k in range(3)], [pc[k] - pa[k] for k in range(3)]
        n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        if n[0] * n[0] + n[1] * n[1] + n[2] * n[2] < 1e-14:
            return
        cen = tuple((pa[k] + pb[k] + pc[k]) / 3.0 for k in range(3))
        w = want(cen) if callable(want) else want
        if n[0] * w[0] + n[1] * w[1] + n[2] * w[2] < 0.0:
            b, c = c, b
            if uvs is not None:
                uvs = (uvs[0], uvs[2], uvs[1])
        if uvs is not None:
            self.uv[len(self.faces)] = dict(zip((a, b, c), uvs))
        self.faces.append((a, b, c))
        self.zones.append(zone)
        self.chunks.append(chunk)

    def quad(self, a, b, c, d, want, zone, chunk, uvs=None):
        u = uvs or (None, None, None, None)
        self.tri(a, b, c, want, zone, chunk, uvs and (u[0], u[1], u[2]))
        self.tri(a, c, d, want, zone, chunk, uvs and (u[0], u[2], u[3]))

    def stitch(self, ring_a, ring_b, want, zone, chunk):
        """Zipper two closed rings (each in rising bearing order) of different counts."""
        ba = [bearing_of(self.verts[v]) for v in ring_a]
        bb = [bearing_of(self.verts[v]) for v in ring_b]
        i = j = 0
        na, nb = len(ring_a), len(ring_b)
        while i < na or j < nb:
            nxt_a = ba[i + 1] if i + 1 < na else ba[0] + 360.0
            nxt_b = bb[j + 1] if j + 1 < nb else bb[0] + 360.0
            if j >= nb or (i < na and nxt_a <= nxt_b):
                self.tri(ring_a[i % na], ring_a[(i + 1) % na], ring_b[j % nb], want, zone, chunk)
                i += 1
            else:
                self.tri(ring_a[i % na], ring_b[(j + 1) % nb], ring_b[j % nb], want, zone, chunk)
                j += 1

    def part(self, chunk):
        """(verts, cols, faces, zones, uv) of one chunk, unreferenced vertices dropped."""
        remap, verts, cols, faces, zones, uv = {}, [], [], [], [], {}
        for fi, (f, z, c) in enumerate(zip(self.faces, self.zones, self.chunks)):
            if c != chunk:
                continue
            g = []
            for vi in f:
                if vi not in remap:
                    remap[vi] = len(verts)
                    verts.append(self.verts[vi])
                    cols.append(self.cols[vi])
                g.append(remap[vi])
            if fi in self.uv:
                uv[len(faces)] = {remap[vi]: t for vi, t in self.uv[fi].items()}
            faces.append(tuple(g))
            zones.append(z)
        return verts, cols, faces, zones, uv


# =============================================================================
# GROUND
# =============================================================================

def swell_amp(r):
    a = ramp(r, FLAT[0][1], FLAT[0][2])
    lo0, lo1, hi0, hi1 = FLAT[1]
    return a * (1.0 - ramp(r, lo0, lo1) * (1.0 - ramp(r, hi0, hi1)))


def ground_z(x, y):
    return DECK_Z + SWELL * swell_amp(math.hypot(x, y)) * fbm(x / SWELL_M + 3.1, y / SWELL_M - 7.7, SEED)


def ground_col(x, y):
    t = -fbm(x / PATCH_M - 11.3, y / PATCH_M + 5.9, SEED + 5)
    c = lerp3((1.0, 1.0, 1.0), G_LIT, ramp(t, 0.02, 0.26))
    return lerp3(c, G_DARK, ramp(t, 0.36, 0.6))


def stump_r(bearing, z):
    """The stump's outline: roots reach out at the ground and are gone by half height."""
    foot = STUMP_FOOT
    for b, reach, half in STUMP_ROOTS:
        d = abs((bearing - b + 180.0) % 360.0 - 180.0)
        if d < half:
            foot += reach * (0.5 + 0.5 * math.cos(math.pi * d / half)) ** 1.5
    top = STUMP_R * (1.0 + 0.05 * math.sin(math.radians(3 * bearing + 40.0)) + 0.03 * math.sin(math.radians(7 * bearing)))
    t = ramp(z, 0.0, 1.2)
    return foot + (top - foot) * (1.0 - (1.0 - t) ** 2.2)


def ring_count(r):
    return 28 if r < 20.0 else 56 if r < 45.0 else 112 if r < 100.0 else 224 if r < 330.0 else 112 if r < 600.0 else 56


def build_ground(m):
    """Rings from the stump's own foot ring out to the horizon. Returns that foot ring."""
    foot = [m.v(pol(360.0 * k / STUMP_SEG, stump_r(360.0 * k / STUMP_SEG, 0.0), DECK_Z), (0.72, 0.72, 0.66))
            for k in range(STUMP_SEG)]
    radii = [4.6, 6.2, 8.5, 11.5, 15.0, 19.0, 24.0, 30.0]
    while radii[-1] < 222.0:
        radii.append(radii[-1] + 6.0)
    radii += list(HORIZON_R)
    rng = Rng(SEED + 1)
    prev = foot
    for ri, r in enumerate(radii):
        n = ring_count(r)
        ring = []
        for k in range(n):
            jit = 0.0 if r > 230.0 or abs(r - START_R) < 9.0 else 1.0
            b = 360.0 * (k + 0.5 * (ri % 2) + jit * rng.u(-0.22, 0.22)) / n
            rr = r + jit * rng.u(-0.9, 0.9) * min(1.0, r / 20.0)
            x, y, _z = pol(b, rr, 0.0)
            ring.append(m.v((x, y, ground_z(x, y)), ground_col(x, y)))
        ring.sort(key=lambda v: bearing_of(m.verts[v]))
        m.stitch(prev, ring, UP, "grass", "ground")
        prev = ring
    return foot


def build_stump(m, foot_ring):
    """Bark from the ground's own rim up to the cut, then the cut face. Shares foot_ring's positions."""
    reps = round(TWO_PI * STUMP_FOOT / BARK_U)
    out = lambda c: (c[0], c[1], 0.0)
    rows = []
    for zi, z in enumerate(STUMP_Z):
        row = []
        for k in range(STUMP_SEG):
            b = 360.0 * k / STUMP_SEG
            shade = 0.74 + 0.26 * ramp(z, 0.0, 0.9)
            p = m.verts[foot_ring[k]] if zi == 0 else pol(b, stump_r(b, z), DECK_Z + z)
            row.append(m.v(p, (shade, shade, shade * 0.97)))
        rows.append(row)
    for zi in range(len(rows) - 1):
        for k in range(STUMP_SEG):
            j = (k + 1) % STUMP_SEG
            u0, u1 = reps * k / float(STUMP_SEG), reps * (k + 1) / float(STUMP_SEG)
            v0, v1 = STUMP_Z[zi] / BARK_V, STUMP_Z[zi + 1] / BARK_V
            m.quad(rows[zi][k], rows[zi][j], rows[zi + 1][j], rows[zi + 1][k], out, "bark", "stump",
                   ((u0, v0), (u1, v0), (u1, v1), (u0, v1)))
    wood_uv = lambda p: (0.5 + p[0] / 6.4, 0.5 + p[1] / 6.4)
    rim = [m.v(m.verts[v]) for v in rows[-1]]
    mid = [m.v(pol(360.0 * (k + 0.5) / 14, 1.1, DECK_Z + STUMP_H)) for k in range(14)]
    c = m.v((0.0, 0.0, DECK_Z + STUMP_H))
    f0 = len(m.faces)
    m.stitch(mid, rim, UP, "wood", "stump")
    for k in range(14):
        m.tri(mid[k], mid[(k + 1) % 14], c, UP, "wood", "stump")
    for fi in range(f0, len(m.faces)):
        m.uv[fi] = {vi: wood_uv(m.verts[vi]) for vi in m.faces[fi]}


# =============================================================================
# TREES -- modelled once per variant in its own frame (foot at the origin), then placed
# =============================================================================

def _shade(rng):
    pick = rng.f()
    for share, lo, hi in CARD_SHADE:
        pick -= share
        if pick <= 0.0:
            return rng.u(lo, hi)
    return 1.0


class Tree(object):
    """One modelled aspen: plumb trunk rings, thin limbs, leaf masses; in its own frame."""

    def __init__(self, spec, seed, far=False):
        self.h, self.w, crown, limbs, self.weight = spec
        self.far = far
        rng = Rng(seed)
        r0 = self.w * 0.5
        self.sides = 3 if far else (6 if self.w > 0.45 else 5)
        table = (TRUNK_RINGS[0], TRUNK_RINGS[4]) if far else TRUNK_RINGS
        self.rings = []                    # (z, radius)
        for i, (zz, share) in enumerate(table):
            z = self.h + zz if i == len(table) - 1 else zz if i < 2 else zz * self.h
            self.rings.append((z, r0 * share))
        self.limbs = []                    # (from, to)
        self.masses = []                   # (centre, width, shade)
        span = self.h - crown
        if far:
            for k in range(5):
                t = (k + 0.5) / 5.0
                a = math.radians(rng.u(0.0, 360.0))
                reach = (1.0 - 0.6 * t) * rng.u(0.6, 1.6)
                self.masses.append(((reach * math.cos(a), reach * math.sin(a), crown + t * span), rng.u(3.6, 4.6) * (1.0 - 0.3 * t),
                                    _shade(rng)))
            return
        a = rng.u(0.0, 360.0)
        for k in range(limbs):
            t = (k + 0.5) / limbs
            z = crown + t * (span - 1.6) + rng.u(-0.4, 0.4)
            a += 137.5 + rng.u(-22.0, 22.0)
            reach = (LIMB[0][1] - (LIMB[0][1] - LIMB[0][0]) * t) * rng.u(0.8, 1.15)
            rise = math.radians(rng.u(*LIMB[1]))
            d = (math.cos(math.radians(a)) * math.cos(rise), math.sin(math.radians(a)) * math.cos(rise), math.sin(rise))
            tip = (d[0] * reach, d[1] * reach, z + d[2] * reach)
            self.limbs.append(((0.0, 0.0, z), tip))
            for along, grow in ((0.55, 0.92), (1.0, 1.0)):
                c = tuple((0.0, 0.0, z)[q] + (tip[q] - (0.0, 0.0, z)[q]) * along + rng.u(-0.35, 0.35) for q in range(3))
                self.masses.append((c, rng.u(*CARD) * grow * (1.0 - 0.2 * t), _shade(rng)))
        for dz in (-1.5, -0.3):
            self.masses.append(((rng.u(-0.3, 0.3), rng.u(-0.3, 0.3), self.h + dz), rng.u(1.8, 2.3), _shade(rng)))

    def radius_at(self, z):
        for (z0, r0), (z1, r1) in zip(self.rings, self.rings[1:]):
            if z <= z1:
                return r0 + (r1 - r0) * clamp((z - z0) / (z1 - z0))
        return self.rings[-1][1]

    def place(self, m, base, yaw, scale, chunk, rng):
        """Add this tree to the sculpt: turned, scaled, its foot sunk into the ground at base."""
        ca, sa = math.cos(yaw), math.sin(yaw)
        at = lambda p: (base[0] + scale * (p[0] * ca - p[1] * sa), base[1] + scale * (p[0] * sa + p[1] * ca),
                        base[2] + scale * p[2])
        u_off, v_off = rng.f(), rng.f()
        n = self.sides
        rows = [[m.v(at((r * math.cos(TWO_PI * k / n), r * math.sin(TWO_PI * k / n), z))) for k in range(n)]
                for (z, r) in self.rings]
        out = lambda cen: (cen[0] - base[0], cen[1] - base[1], 0.0)
        turns = max(1, int(round(math.pi * self.w * scale / BARK_U)))     # whole turns of the tile round the trunk
        for i in range(len(rows) - 1):
            v0, v1 = v_off + self.rings[i][0] * scale / BARK_V, v_off + self.rings[i + 1][0] * scale / BARK_V
            for k in range(n):
                j = (k + 1) % n
                u0, u1 = u_off + turns * k / float(n), u_off + turns * (k + 1) / float(n)
                m.quad(rows[i][k], rows[i][j], rows[i + 1][j], rows[i + 1][k], out, "bark", chunk,
                       ((u0, v0), (u1, v0), (u1, v1), (u0, v1)))
        tip = m.v(at((0.0, 0.0, self.h)))
        for k in range(n):
            m.tri(rows[-1][k], rows[-1][(k + 1) % n], tip, UP, "bark", chunk,
                  ((u_off + k / float(n), v1), (u_off + (k + 1) / float(n), v1), (u_off + (k + 0.5) / n, v1 + 0.03)))
        for (a, b) in self.limbs:                       # a thin dark limb, three sides
            pa, pb = at(a), at(b)
            d = [pb[k] - pa[k] for k in range(3)]
            ln = math.sqrt(d[0] * d[0] + d[1] * d[1]) or 1.0
            sx, sy = -d[1] / ln, d[0] / ln
            ring_a, ring_b = [], []
            for k in range(3):
                ang = TWO_PI * k / 3
                o = (sx * math.cos(ang), sy * math.cos(ang), math.sin(ang))
                ring_a.append(m.v(tuple(pa[q] + 0.1 * scale * o[q] for q in range(3)), BRANCH_COL))
                ring_b.append(m.v(tuple(pb[q] + 0.035 * scale * o[q] for q in range(3)), BRANCH_COL))
            mid = tuple((pa[q] + pb[q]) * 0.5 for q in range(3))
            away = lambda cen, mid=mid: tuple(cen[q] - mid[q] for q in range(3))
            for k in range(3):
                j = (k + 1) % 3
                m.quad(ring_a[k], ring_a[j], ring_b[j], ring_b[k], away, "bark", chunk,
                       ((0.0, 0.0), (0.1, 0.0), (0.1, 0.2), (0.0, 0.2)))
        for (c, width, shade) in self.masses:
            card_pair(m, at(c), width * scale, width * scale, rng, "leaf", chunk, (shade, shade, shade), tilt=0.9)


def card_pair(m, c, w, h, rng, zone, chunk, col, tilt, foot=False):
    """Two crossed alpha-cut cards on one quarter of the zone's sheet; foot: c is the bottom middle."""
    cell = int(rng.f() * 4.0) % 4
    u0, v0 = 0.5 * (cell % 2), 0.5 * (cell // 2)
    a = rng.u(0.0, math.pi)
    for k in range(2):
        ang = a + k * math.pi / 2.0 + rng.u(-0.3, 0.3)
        lean = rng.u(-tilt, tilt)
        ax = (math.cos(ang), math.sin(ang), 0.0)
        up = (-math.sin(ang) * math.sin(lean), math.cos(ang) * math.sin(lean), math.cos(lean))
        lo, hi = (0.0, h) if foot else (-0.5 * h, 0.5 * h)
        q = [m.v(tuple(c[i] + ax[i] * sx * 0.5 * w + up[i] * sz for i in range(3)), col)
             for sx, sz in ((-1, lo), (1, lo), (1, hi), (-1, hi))]
        nrm = (ax[1] * up[2] - ax[2] * up[1], ax[2] * up[0] - ax[0] * up[2], ax[0] * up[1] - ax[1] * up[0])
        m.quad(q[0], q[1], q[2], q[3], nrm, zone, chunk,
               ((u0, v0), (u0 + 0.5, v0), (u0 + 0.5, v0 + 0.5), (u0, v0 + 0.5)))


def scatter():
    """[(x, y, far)]: dart throwing to an exact density, no two trunks nearer than the gap."""
    rng = Rng(SEED + 2)
    spots = [pol(b, r, 0.0) for b, r in SPOTS]
    placed, grid = [], {}
    cell = FAR_GAP

    def fits(x, y, gap):
        ci, cj = int(math.floor(x / cell)), int(math.floor(y / cell))
        for i in range(ci - 2, ci + 3):
            for j in range(cj - 2, cj + 3):
                for (px, py) in grid.get((i, j), ()):
                    if (px - x) ** 2 + (py - y) ** 2 < gap * gap:
                        return False
        return True

    for (r0, r1, dens, gap, far) in ((CLEAR_R, NEAR_R, DENSITY, MIN_GAP, False), (NEAR_R, FOREST_R, FAR_DENSITY, FAR_GAP, True)):
        want = int(round(dens * math.pi * (r1 * r1 - r0 * r0)))
        got = tries = 0
        while got < want and tries < want * 400:
            tries += 1
            r, a = math.sqrt(rng.u(r0 * r0, r1 * r1)), rng.u(0.0, TWO_PI)
            x, y = r * math.cos(a), r * math.sin(a)
            if any((x - s[0]) ** 2 + (y - s[1]) ** 2 < SPOT_CLEAR ** 2 for s in spots) or not fits(x, y, gap):
                continue
            grid.setdefault((int(math.floor(x / cell)), int(math.floor(y / cell))), []).append((x, y))
            placed.append((x, y, far))
            got += 1
    return placed


def build_trees(m):
    """Every tree, and the grass tufts, into the sculpt. Returns [(x, y, z, radius at chest, Tree, scale, chunk)]."""
    near = [Tree(s, SEED + 100 + i) for i, s in enumerate(VARIANTS)]
    far = [Tree(s, SEED + 200 + i, far=True) for i, s in enumerate(FAR_VARIANTS)]
    rng = Rng(SEED + 3)
    out = []
    for (x, y, is_far) in scatter():
        kinds = near
        if is_far:
            rr = math.hypot(x, y) + rng.u(-12.0, 12.0)
            kinds = far[:2] if rr < FAR_STEP[0] else far[1:] if rr < FAR_STEP[1] else far[2:]
        pick = rng.f() * sum(t.weight for t in kinds)
        tree = kinds[-1]
        for t in kinds:
            pick -= t.weight
            if pick <= 0.0:
                tree = t
                break
        b = bearing_of((x, y))
        chunk = ("far%d" % int(b // 90.0)) if is_far else ("near%d" % int(b // 45.0))
        scale = rng.u(*SCALE)
        z = ground_z(x, y)
        tree.place(m, (x, y, z), rng.u(0.0, TWO_PI), scale, chunk, rng)
        out.append((x, y, z, tree.radius_at(1.0) * scale, tree, scale, chunk))
    spots = [(x, y) for (x, y, _z, _r, t, _s, _c) in out if not t.far for _k in range(int(rng.u(TUFT_PER_TREE[0], TUFT_PER_TREE[1] + 0.999)))]
    tufts = []
    for (x, y) in spots:
        a, d = rng.u(0.0, TWO_PI), rng.u(*TUFT_FOOT)
        tufts.append((x + d * math.cos(a), y + d * math.sin(a)))
    for _k in range(TUFT_LOOSE):
        r, a = math.sqrt(rng.u(5.0 ** 2, TUFT_R ** 2)), rng.u(0.0, TWO_PI)
        tufts.append((r * math.cos(a), r * math.sin(a)))
    for (x, y) in tufts:
        if math.hypot(x, y) < 4.6:
            continue
        dry = rng.f() < 0.62
        shade = rng.u(0.85, 1.0)
        chunk = "near%d" % int(bearing_of((x, y)) // 45.0)
        card_pair(m, (x, y, ground_z(x, y) - 0.04), rng.u(*TUFT_SIZE[0]), rng.u(*TUFT_SIZE[1]), rng,
                  "tuft", chunk, tuple(shade * c for c in ((1.0, 1.0, 1.0) if dry else TUFT_GREEN)), tilt=0.18, foot=True)
    INFO["tufts"] = len(tufts)
    return out


# =============================================================================
# COLLIDERS -- purpose-built, one per chunk
# =============================================================================

def build_colliders(m, trees):
    """{chunk: Mesh}: the ground's own surface, the stump as a prism, each trunk as a prism."""
    out = {c: Mesh() for c in CHUNKS}
    g = out["ground"]
    remap = {}
    for f, c in zip(m.faces, m.chunks):
        if c == "ground":
            g.faces.append(tuple(remap.setdefault(vi, g.v(m.verts[vi])) for vi in f))
            g.zones.append("c")
            g.chunks.append("ground")
    s = out["stump"]
    rows = [[s.v(pol(360.0 * k / 14, stump_r(360.0 * k / 14, z) , DECK_Z + z - (0.4 if z == 0.0 else 0.0))) for k in range(14)]
            for z in (0.0, 0.75, STUMP_H)]
    outw = lambda c: (c[0], c[1], 0.0)
    for lo, hi in zip(rows, rows[1:]):
        for k in range(14):
            s.quad(lo[k], lo[(k + 1) % 14], hi[(k + 1) % 14], hi[k], outw, "c", "stump")
    top = s.v((0.0, 0.0, DECK_Z + STUMP_H))
    for k in range(14):
        s.tri(rows[-1][k], rows[-1][(k + 1) % 14], top, UP, "c", "stump")
    for (x, y, z, rad, tree, scale, chunk) in trees:
        cm = out[chunk]
        n = 4 if tree.far else 6
        lo = [cm.v((x + rad * 1.1 * math.cos(TWO_PI * k / n), y + rad * 1.1 * math.sin(TWO_PI * k / n), z - 0.4)) for k in range(n)]
        rt = tree.radius_at(COLLIDER_TOP / scale) * scale
        hi = [cm.v((x + rt * math.cos(TWO_PI * k / n), y + rt * math.sin(TWO_PI * k / n), z + COLLIDER_TOP))
              for k in range(n)]
        outw = lambda c, x=x, y=y: (c[0] - x, c[1] - y, 0.0)
        for k in range(n):
            cm.quad(lo[k], lo[(k + 1) % n], hi[(k + 1) % n], hi[k], outw, "c", chunk)
    return out


CHUNKS = ["ground", "stump"] + ["near%d" % i for i in range(8)] + ["far%d" % i for i in range(4)]
VIS = {c: "Aspens" + c[0].upper() + c[1:] for c in CHUNKS}


def build_geometry():
    m = Mesh()
    foot = build_ground(m)
    build_stump(m, foot)
    trees = build_trees(m)
    return m, trees, build_colliders(m, trees)


def sightlines(trees, dist, n=1440):
    """Share of bearings on which the line from the stump's middle to dist clears every trunk."""
    clear = 0
    for k in range(n):
        a = TWO_PI * k / n
        dx, dy = math.cos(a), math.sin(a)
        ok = True
        for (x, y, _z, rad, _t, _s, _c) in trees:
            along = x * dx + y * dy
            if 0.0 < along < dist and abs(x * dy - y * dx) < rad:
                ok = False
                break
        clear += ok
    return clear / float(n)


# =============================================================================
# SHEETS -- one tile per class at 0.05 m per texel
# =============================================================================

SHEETS = {
    "grass": tx.Sheet("grass", mode="box", roughness=1.0),
    "bark": tx.Sheet("bark", mode="custom", width=32, roughness=1.0),
    "leaf": tx.Sheet("leaf", mode="custom", size=128, roughness=1.0, cull=False),         # four leaf clusters, alpha-cut
    "tuft": tx.Sheet("tuft", mode="custom", size=128, roughness=1.0, cull=False),         # four dry tufts, alpha-cut
    "wood": tx.Sheet("wood", mode="custom", size=128, roughness=1.0),
}


# =============================================================================
# BLENDER SIDE
# =============================================================================

def _tint(mat):
    """Base Color = tile x COLOR_0, so the exporter writes a vertex-coloured texture."""
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    img = bsdf.inputs["Base Color"].links[0].from_node
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(img.outputs["Color"], [i for i in mix.inputs if i.identifier == "A_Color"][0])
    nt.links.new(col.outputs["Color"], [i for i in mix.inputs if i.identifier == "B_Color"][0])
    nt.links.new([o for o in mix.outputs if o.identifier == "Result_Color"][0], bsdf.inputs["Base Color"])


def _object(name, part, mats):
    verts, cols, faces, zones, uv = part
    ob = mdl.mesh(name, verts, faces)
    tx.unwrap(ob, zones, SHEETS, seed=1, face_uv=uv)
    tx.finish(ob, zones, mats)
    attr = ob.data.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    attr.data.foreach_set("color", [c for rgba in cols for c in rgba])
    ob.data.color_attributes.active_color_index = 0
    ob.data.color_attributes.render_color_index = 0
    return ob


def build():
    m, trees, colliders = build_geometry()
    mats = tx.materials(NAME, SHEETS)
    for cls, mat in mats.items():
        _tint(mat)
        if cls in ("leaf", "tuft"):            # the tile's alpha cuts the card
            nt = mat.node_tree
            img = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
            nt.links.new(img.outputs["Alpha"], nt.nodes.get("Principled BSDF").inputs["Alpha"])
            mdl._try(mat, "surface_render_method", "DITHERED")
    out = []
    for chunk in CHUNKS:
        vis = _object(VIS[chunk], m.part(chunk), mats)
        cv, _cc, cf, _cz, _cu = colliders[chunk].part(chunk)
        cob = mdl.mesh(VIS[chunk] + "Collision-colonly", cv, cf)
        cob.hide_render = True
        out += [vis, cob]
        print("MDL STATS %s visual_tris=%d collision_tris=%d" % (chunk, len(vis.data.polygons), len(cf)))
    print("MDL STATS trees near=%d far=%d tufts=%d" % (sum(1 for t in trees if not t[4].far), sum(1 for t in trees if t[4].far), INFO.get("tufts", 0)))
    return out


def _export_chunks(out_dir, objects, spec):
    """One .glb per chunk (only spec["chunk"] when it names one) and the manifest the model tool reads."""
    want = spec.get("chunk") or ""
    if want and want not in CHUNKS:
        raise SystemExit("MDL ERROR no chunk %r; chunks are %s" % (want, ", ".join(CHUNKS)))
    by_name = {o.name: o for o in objects}
    made = []
    for chunk in ([want] if want else CHUNKS):
        label = VIS[chunk]
        path = os.path.join(out_dir, "%s_%s.glb" % (NAME, chunk))
        mdl.export_glb(path, [by_name[label], by_name[label + "Collision-colonly"]])
        print("MDL EXPORT %s (%d bytes)" % (path, os.path.getsize(path)))
        made.append({"chunk": chunk, "glb": os.path.basename(path),
                     "contract": {"node_paths": [label, label + "Collision", label + "Collision/CollisionShape3D"],
                                  "max_tris": 60000}})
    with open(os.path.join(out_dir, NAME + ".chunks.json"), "w") as fh:
        json.dump({"chunks": made}, fh, indent=1)
    return [os.path.join(out_dir, c["glb"]) for c in made]


def _check():
    m, trees, colliders = build_geometry()
    total = 0
    for chunk in CHUNKS:
        n = sum(1 for c in m.chunks if c == chunk)
        total += n
        print("%-7s tris=%d collider_tris=%d" % (chunk, n, len(colliders[chunk].faces)))
    near = [t for t in trees if not t[4].far]
    print("total tris=%d  trees near=%d far=%d  tufts=%d  density=%.4f/m2  chest width mean %.3f m, %.2f..%.2f"
          % (total, len(near), len(trees) - len(near), INFO.get("tufts", 0), DENSITY, 2.0 * sum(t[3] for t in near) / len(near),
             2.0 * min(t[3] for t in near), 2.0 * max(t[3] for t in near)))
    gaps = []
    for i, a in enumerate(near[:400]):
        gaps.append(min(math.hypot(a[0] - b[0], a[1] - b[1]) for j, b in enumerate(near) if j != i))
    print("nearest neighbour: mean %.2f m, least %.2f m" % (sum(gaps) / len(gaps), min(gaps)))
    for d in (30.0, 55.0, START_R):
        print("clear sightlines stump -> %.0f m: %.0f%% of bearings" % (d, 100.0 * sightlines(trees, d)))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        import aspens_views  # noqa: E402
        mdl.main(NAME, build, facing_yaw=FACING_YAW, export=_export_chunks, post=aspens_views.post)
