"""
PANOPTICON -- beach: Map 5 in the hub's order, the beach yacht map. A bay held between two curved
jetties of sand that run out from a beach; the island rises behind a low rock wall; teal shallows,
then dark deep water (the pit); a yacht anchored at the bay's centre is the tower. ONE sculpt
(shared vertices where parts meet), exported per chunk:

    beach_ground.glb   seabed edge, shallows, sand, the rock wall, the jetty heads     BeachGround
    beach_island.glb   the island behind the wall: grass, headlands, hills, far coast  BeachIsland
    beach_rocks.glb    boulders sunk into the sand, shallows, wall foot and heads      BeachRocks
    beach_palms.glb    palms planted in the sand and on the island                     BeachPalms
    beach_water.glb    the sea, flat and static, to the horizon (no collider)          BeachWater

World coordinates, instanced at identity (Blender +Z -> Godot +Y, +Y -> Godot -Z; bearings as the
scene's markers, pol()). The mouth faces bearing 0; the lap runs 38 -> 322 deg at r 58.

    tools/modelling/model build beach [--chunk island]
    python3 tools/modelling/maps/beach/beach_build.py --check
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
import beach_lib as il  # noqa: E402
from beach_lib import (Mesh, Rng, UP, DOWN, pol, bearing_of, rad_of, lerp, lerp3, clamp, smooth, ramp,  # noqa: E402
                     angdiff, h2, vnoise, fbm, ring_noise, add, sub, scale, dot, cross, unit)
if bpy is not None:
    import mdl  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "beach"
SEED = 52817
FACING_YAW = 0.0
NC = 360                    # columns round the bay near the lane: 1 deg, 1.0 m at the lane
DECK_Z = 23.0               # the sand the lane runs on (every map's deck)
WATER_Z = 22.6              # the sea's surface
LANE_R = 58.0               # the lap: 38 -> 322 deg, 287 m
ENTRY_B, EXIT_B = 38.0, 322.0

# -- the bay shore: waterline, a narrow wadeable shelf, then the drop to deep water (the pit)
WL_R = 53.0                 # waterline radius ...
WL_WANDER = 0.7             # ... and how far it wanders
SHELF = 3.0                 # metres of shallows inside the waterline
SHELF_DEPTH = 0.5           # water depth at the shelf's edge
DEEP_Z = 10.0               # the drop-off's foot, under opaque water
SAND_ROWS = 6               # rows between the dry sand's first row and the wall foot
WET = 1.3                   # metres of wet sand above the waterline

# -- the beach rock wall: about 2 m, low enough to see the island over
WALL_R = 63.6               # the wall's foot ...
WALL_WANDER = 0.6
WALL_H = (1.75, 2.3)        # its height wanders between these
WALL_ROWS = ((0.0, 0.0), (0.3, 0.06), (0.62, 0.16), (0.95, 0.3), (1.25, 0.45), (1.55, 0.58), (1.8, 0.78),
             (1.0, 1.15))   # (share of the height, metres back); the last is the lip's top
WALL_JIT = (0.2, 0.08)      # per-vertex wander: metres in/out, share of the height
ISLAND_LIFT = 1.85          # the island's ground behind the lip, over the deck

# -- the island behind the wall
ISLAND_D = [0.6, 1.6, 3.0, 5.0, 7.5, 10.0, 13.0, 16.0, 19.0, 22.0, 25.0, 28.5, 32.0, 36.0, 41.0, 47.0,
            54.0, 63.0, 74.0, 87.0, 102.0, 120.0]        # rows behind the wall's top, metres
FAR_R = [(200.0, 180), (228.0, 180), (262.0, 180), (300.0, 180), (345.0, 120), (395.0, 120),
         (450.0, 120), (515.0, 90), (590.0, 90), (680.0, 72), (790.0, 72), (920.0, 60)]   # (r, columns)
RIDGE = (2.2, 4.5, 4.0)     # the jetty's hummock behind its wall: height, distance behind the wall, half width
ARM_W = (12.0, 6.5)         # the jetty's land behind its wall, at its root and near its head (metres)
MAIN_COAST = (-20.0, 0.0035, 58.0)   # the big island's coast: x at the jetty roots, curvature, |y| it bends from
COAST_SLOPE = 0.42          # the coast's fall into the sea
HILLS = ((180.0, 300.0, 66.0, 105.0), (146.0, 245.0, 44.0, 78.0), (214.0, 360.0, 84.0, 120.0),
         (122.0, 205.0, 26.0, 58.0), (243.0, 238.0, 38.0, 68.0), (168.0, 470.0, 58.0, 150.0),
         (196.0, 160.0, 18.0, 50.0), (262.0, 300.0, 30.0, 90.0), (100.0, 330.0, 34.0, 90.0))  # (bearing, r, h, spread)

# -- the jetty heads: a rock knoll where the sand ends, beyond the start and the portal
HEAD_S = 152.0              # s of the knoll's top
HEAD_W = (5.5, 10.0)        # half extents: degrees along, metres across
HEAD_H = 4.2
HEAD_R = 60.5
END_S = (149.0, 162.0)      # the land drops away into the sea between these s

# -- the sea
WATER_R = [0.0, 8.0, 18.0, 28.0, 36.0, 42.0, 45.5]                     # rings in the bay (absolute)
WATER_IN = [-7.5, -5.5, -4.3, -3.5, -3.0, -2.5, -2.0, -1.5, -1.0, -0.55, -0.2, 0.0, 0.8]   # metres off the waterline
WATER_OUT = [66.0, 69.0, 72.0, 75.0, 78.0, 81.0, 84.0, 87.0, 90.0, 94.0, 99.0]   # absolute rings outside the wall
WATER_FAR = [(105.0, 180), (112.0, 180), (120.0, 180), (130.0, 180), (142.0, 180), (156.0, 180), (172.0, 180),
             (190.0, 180), (215.0, 180), (250.0, 180), (300.0, 120), (380.0, 120), (500.0, 90), (700.0, 72),
             (1000.0, 60), (1500.0, 48), (2200.0, 36), (3000.0, 36)]
SHORE_FOAM = (0.86, 0.97, 0.95)        # sRGB at the waterline
SHALLOW = (0.6, 0.91, 0.84)            # the wadeable band (refs: 150..160, 229..232, 208..216)
TEAL = (0.22, 0.8, 0.8)                # over the drop-off (refs 55, 205, 203)
DEEP = (0.06, 0.38, 0.66)              # the pit: dark water
OPEN = (0.02, 0.55, 0.81)              # open sea, toward the horizon (refs 0..20, 139, 206)
HORIZON = (0.6, 0.77, 0.85)            # the sky's horizon colour: the sea's last ring
SKY_FADE = (500.0, 3000.0)

# -- colours carried by the vertices (x the drawn tile)
WET_SAND = (0.86, 0.85, 0.79)
JUNGLE_NEAR = (0.33, 0.6, 0.27)        # x the pale canopy tile
JUNGLE_HAZE = (0.5, 0.68, 0.7)
HAZE_D = (60.0, 650.0)                 # distance from the bay's centre where the haze starts and is whole
GRASS_EDGE = (28.0, 46.0)              # metres behind the wall where grass gives way to canopy

# -- palms and rocks
PALM_ISLAND = 100
PALM_SAND = 14
PALM_H = (7.0, 11.5)
PALM_SAND_H = (6.5, 9.0)
TRUNK_R = (0.21, 0.15)      # base and top radius
TRUNK_SEG = 0.85            # metres a trunk segment rises
FRONDS = (7, 9)
FROND_L = (3.4, 4.6)
FROND_W = 0.36              # half width at the widest

TWO_PI = 2.0 * math.pi
INFO = {}


# =============================================================================
# FIELDS -- every line of the sculpt is a function of bearing
# =============================================================================

def s_of(b):
    """Degrees off the beach's centre (bearing 180): 0 at the back, 180 in the mouth."""
    return abs(angdiff(b, 180.0))


def wl(b):
    return WL_R + WL_WANDER * ring_noise(b, SEED + 1, ((3, 1.0), (7, 0.6), (13, 0.3)))


def wf(b):
    return WALL_R + WALL_WANDER * ring_noise(b, SEED + 2, ((4, 1.0), (9, 0.5), (17, 0.35)))


def wall_h(b):
    t = 0.5 + 0.5 * ring_noise(b, SEED + 3, ((5, 1.0), (11, 0.7), (23, 0.4)))
    return lerp(WALL_H[0], WALL_H[1], t)


def top_r(b):
    return wf(b) + WALL_ROWS[-1][1]


def drop(b):
    """How far the land has sunk at the jetty's end: 0 on the run, the whole height past the head."""
    return 7.0 * smooth((s_of(b) - END_S[0]) / (END_S[1] - END_S[0]))


def bell(x):
    x = abs(x)
    return 0.0 if x >= 1.0 else (1.0 - x * x) ** 2


def head(b, r):
    """The jetty head's rock knoll, metres over the land."""
    s = s_of(b)
    lump = 0.15 * vnoise(b * 0.7, r * 0.5, SEED + 7)
    return HEAD_H * (1.0 + lump) * bell((s - HEAD_S) / HEAD_W[0]) * bell((r - HEAD_R) / HEAD_W[1])


def arm_w(b):
    """How far the jetty's land runs behind its wall before the outer coast: narrowing to the head."""
    s = s_of(b)
    return lerp(ARM_W[0], ARM_W[1], ramp(s, 80.0, 146.0)) + 2.0 * ring_noise(b, SEED + 8, ((9, 1.0), (19, 0.6)))


def main_coast(x, y):
    """Metres inside the big island's coast (negative: out at sea). The coast meets the jetties' roots."""
    ay = abs(y)
    xc = MAIN_COAST[0] - MAIN_COAST[1] * max(ay - MAIN_COAST[2], 0.0) ** 2 + 7.0 * fbm(y / 40.0, 3.0, SEED + 13, 3)
    return xc - x


def hills(x, y):
    h = 0.0
    for b, r, hh, sp in HILLS:
        px, py, _z = pol(b, r, 0.0)
        h += hh * math.exp(-((x - px) ** 2 + (y - py) ** 2) / (2.0 * sp * sp))
    return h + 9.0 * fbm(x / 70.0, y / 70.0, SEED + 9, 3)


def island_z(b, r):
    """The island's ground behind the wall: the jetty's strip, or the big island, and their fall into the sea."""
    d = r - top_r(b)
    x, y, _z = pol(b, r, 0.0)
    s = s_of(b)
    base = DECK_Z + ISLAND_LIFT + 0.35 * fbm(x / 9.0, y / 9.0, SEED + 10)
    # the jetty: a low hummock of grass and rock behind its wall
    hump = RIDGE[0] * (1.0 - ramp(s, 120.0, 148.0)) * bell((d - RIDGE[1]) / RIDGE[2])
    arm = min(base + hump, WATER_Z + COAST_SLOPE * (arm_w(b) - d))
    # the big island behind the beach: rising into hills
    inside = main_coast(x, y)
    land = base + min(d, 30.0) * 0.04 + hills(x, y) * ramp(d, 14.0, 90.0) * ramp(inside, 10.0, 90.0)
    big = min(land, WATER_Z + COAST_SLOPE * inside)
    z = max(arm, big)
    return max(z, WATER_Z - 9.0) - drop(b)


def sand_z(b, r):
    """The beach between the waterline and the wall foot."""
    w, f = wl(b), wf(b)
    x, y, _z = pol(b, r, 0.0)
    if r < w:
        t = (w - r) / SHELF
        z = WATER_Z - SHELF_DEPTH * smooth(min(t, 1.0) * 0.5 + 0.5 * min(t, 1.0) ** 1.4) if t <= 1.0 else \
            WATER_Z - SHELF_DEPTH - (WATER_Z - SHELF_DEPTH - DEEP_Z) * smooth(min((t - 1.0) * SHELF / 5.0, 1.0))
    else:
        u = r - w
        z = WATER_Z + (DECK_Z - WATER_Z) * smooth(min(u / 2.6, 1.0)) + 0.16 * ramp(r, w + 2.6, f)
        z += 0.03 * fbm(x / 2.5, y / 2.5, SEED + 12) * ramp(u, 0.5, 2.0)
    return z + head(b, r) - drop(b)


# =============================================================================
# SCULPT
# =============================================================================

def FACE(c):
    """Up, leaning toward the bay: the wall's upright faces look at the bay, every other face up."""
    r = math.hypot(c[0], c[1]) or 1.0
    return (-0.08 * c[0] / r, -0.08 * c[1] / r, 1.0)


def _jb(b, k, amp):
    return amp * (2.0 * h2(int(round(b * 10.0)), k, SEED + 20) - 1.0)


class Sculpt(object):
    """The ground as one Mesh: rows from the drop-off out through sand, wall and island."""

    def __init__(self):
        self.m = Mesh()
        self.rows = []           # each NC long
        self.kind = {}           # vertex id -> row kind
        self.wall_top = None

    def v(self, p, col, kind):
        i = self.m.v(p, col)
        self.kind[i] = kind
        return i

    # -- vertex colours --------------------------------------------------------
    def _sand_col(self, b, r, z):
        w = wl(b)
        wet = 1.0 - ramp(r - w, 0.25, WET)
        c = lerp3((1.0, 1.0, 1.0), WET_SAND, wet)
        foot = 1.0 - 0.08 * ramp(r, wf(b) - 1.2, wf(b))
        n = 0.97 + 0.03 * vnoise(b * 0.9, r * 0.6, SEED + 30)
        return (c[0] * foot * n, c[1] * foot * n, c[2] * foot * n, 1.0)

    def _rock_col(self, p):
        n = 0.88 + 0.16 * h2(int(p[0] * 7.0), int(p[1] * 7.0 + p[2] * 13.0), SEED + 31)
        wet = 1.0 - 0.28 * (1.0 - ramp(p[2], WATER_Z - 0.2, WATER_Z + 0.5))
        return (n * wet, n * wet, n * wet * 1.01, 1.0)

    def _land_col(self, p):
        """Grass and canopy: near green, far toward the sky's haze."""
        dist = math.hypot(p[0], p[1])
        hz = ramp(dist, HAZE_D[0], HAZE_D[1]) ** 0.8
        n = 0.92 + 0.12 * vnoise(p[0] / 13.0, p[1] / 13.0, SEED + 32)
        c = lerp3(JUNGLE_NEAR, JUNGLE_HAZE, hz)
        return (c[0] * n, c[1] * n, c[2] * n, 1.0)

    # -- rows ------------------------------------------------------------------
    def build(self):
        m = self.m
        rows = []
        # the drop, the shelf and the sand: offsets from the waterline, then the dry sand
        shore = [-7.0, -5.0, -SHELF, -2.2, -1.4, -0.7, -0.25, 0.0, 0.45, 1.0, 1.7, 2.6]
        for k, off in enumerate(shore):
            row = []
            for i in range(NC):
                b = float(i)
                r = wl(b) + off + (0.0 if k < 2 else _jb(b, 40 + k, 0.12))
                z = sand_z(b, r) if off != 0.0 else WATER_Z + head(b, r) - drop(b)
                row.append(self.v(pol(b, r, z), self._sand_col(b, r, z), "shore" if off < 0.0 else "sand"))
            rows.append(row)
        for k in range(1, SAND_ROWS + 1):
            row = []
            for i in range(NC):
                b = float(i)
                t = k / float(SAND_ROWS + 1)
                r = lerp(wl(b) + 2.6, wf(b), t) + _jb(b, 60 + k, 0.25)
                bj = b + _jb(b, 80 + k, 0.3)
                z = sand_z(bj, r)
                row.append(self.v(pol(bj, r, z), self._sand_col(bj, r, z), "sand"))
            rows.append(row)
        # the wall: from the foot (on the sand) up its battered, blocky face to the lip
        for k, (hs, back_m) in enumerate(WALL_ROWS):
            row = []
            for i in range(NC):
                b = float(i)
                foot_z = sand_z(b, wf(b))
                h = wall_h(b)
                if k == len(WALL_ROWS) - 1:
                    r = top_r(b)
                    z = island_z(b, r)
                    z = max(z, foot_z + h * 0.93) if drop(b) < 0.5 else z
                    kind = "lip"
                else:
                    blk = vnoise(b * 0.55, hs * 3.0, SEED + 40)        # blocks standing proud or set back
                    r = wf(b) + back_m + (0.0 if k == 0 else WALL_JIT[0] * blk + _jb(b, 100 + k, 0.08))
                    z = foot_z + h * hs + (0.0 if k == 0 else _jb(b, 120 + k, WALL_JIT[1]) * h * 0.4)
                    z += head(b, r) * (0.0 if k == 0 else 1.0) * 0.0
                    kind = "foot" if k == 0 else "wall"
                if k == 0:
                    z = sand_z(b, r)
                p = pol(b, r, z)
                row.append(self.v(p, self._rock_col(p) if k else self._sand_col(b, r, z), kind))
            rows.append(row)
        self.wall_top = rows[-1]
        # the island behind the wall
        for k, d in enumerate(ISLAND_D):
            row = []
            for i in range(NC):
                b = float(i) + (_jb(float(i), 200 + k, 0.3) if k > 1 else 0.0)
                r = top_r(b) + d + _jb(float(i), 220 + k, 0.2 * min(d, 4.0))
                z = island_z(b, r)
                p = pol(b, r, z)
                row.append(self.v(p, self._land_col(p), "island"))
            rows.append(row)
        self.rows = rows
        n_ground = len(shore) + SAND_ROWS + len(WALL_ROWS)
        self._grid(rows[:n_ground], "ground")
        self._grid(rows[n_ground - 1:], "island")
        # far rings: absolute radii, fewer columns, stitched to the last near row
        prev = rows[-1]
        for r, n in FAR_R:
            ring = []
            for j in range(n):
                b = (j + 0.5 * (len(ring) % 2)) * 360.0 / n
                z = island_z(b, r)
                p = pol(b, r, z)
                ring.append(self.v(p, self._land_col(p), "island"))
            self._stitch(prev, ring)
            prev = ring
        return m

    def _hidden(self, ids):
        return all(self.m.verts[v][2] < WATER_Z - 1.2 for v in ids)

    def _grid(self, rows, chunk):
        m = self.m
        for lo, hi in zip(rows, rows[1:]):
            for i in range(NC):
                j = (i + 1) % NC
                q = (lo[i], lo[j], hi[j], hi[i])
                if self._hidden(q):
                    continue
                m.quad(q[0], q[1], q[2], q[3], FACE, self._zone, chunk)

    def _stitch(self, a, b_):
        before = len(self.m.faces)
        self.m.stitch(a, b_, FACE, self._zone, "island")
        keep = [k for k in range(before, len(self.m.faces)) if not self._hidden(self.m.faces[k])]
        drop_ = set(range(before, len(self.m.faces))) - set(keep)
        if drop_:
            self.m.faces = [f for k, f in enumerate(self.m.faces) if k not in drop_]
            self.m.zones = [z for k, z in enumerate(self.m.zones) if k not in drop_]
            self.m.chunks = [c for k, c in enumerate(self.m.chunks) if k not in drop_]

    def _zone(self, n, c, ids):
        kinds = [self.kind.get(v, "island") for v in ids]
        b, r = bearing_of(c), rad_of(c)
        steep = 1.0 - abs(n[2])
        if c[2] < WATER_Z - 0.7:
            return "sand"
        if "wall" in kinds or ("lip" in kinds and "island" not in kinds):
            return "rock"
        if all(k in ("sand", "shore", "foot") for k in kinds):
            return "rock" if head(b, r) > 0.45 or steep > 0.55 else "sand"
        if steep > 0.5 or (head(b, r) > 0.45 and c[2] > WATER_Z + 0.3):
            return "rock"
        if c[2] < WATER_Z + 0.9 and steep < 0.3:
            return "sand"
        d = r - top_r(b)
        edge = lerp(GRASS_EDGE[0], GRASS_EDGE[1], 0.5 + 0.5 * vnoise(c[0] / 17.0, c[1] / 17.0, SEED + 50))
        if main_coast(c[0], c[1]) < 25.0:
            edge = 1e9                                   # the jetties and the coast stay grass
        return "grass" if d < edge else "jungle"


def ground_z(b, r):
    """The ground's height anywhere (for planting and for the sea's colour)."""
    if r < wf(b):
        return sand_z(b, r)
    if r < top_r(b):
        return sand_z(b, wf(b)) + wall_h(b)
    return island_z(b, r)


# =============================================================================
# THE SEA -- flat, static, coloured by the depth under it
# =============================================================================

def sea_col(b, r):
    depth = WATER_Z - ground_z(b, r)
    c = lerp3(SHORE_FOAM, SHALLOW, ramp(depth, 0.0, 0.16))
    c = lerp3(c, TEAL, ramp(depth, SHELF_DEPTH * 0.9, 2.2))
    c = lerp3(c, DEEP, ramp(depth, 2.2, 7.0))
    open_ = ramp(r, 90.0, 400.0)
    c = lerp3(c, OPEN, open_ * ramp(depth, 2.0, 7.0))
    c = lerp3(c, HORIZON, ramp(r, SKY_FADE[0], SKY_FADE[1]) ** 1.3)
    return (c[0], c[1], c[2], 1.0)


def build_sea():
    m = Mesh()
    rings = []
    centre = m.v((0.0, 0.0, WATER_Z), sea_col(0.0, 0.0))
    for r in WATER_R[1:]:
        rings.append([m.v(pol(i * 360.0 / NC, r, WATER_Z), sea_col(i * 360.0 / NC, r)) for i in range(NC)])
    for off in WATER_IN:
        ring = []
        for i in range(NC):
            b = float(i)
            r = wl(b) + off
            ring.append(m.v(pol(b, r, WATER_Z), sea_col(b, r)))
        rings.append(ring)
    for r in WATER_OUT:
        rings.append([m.v(pol(i * 360.0 / NC, r, WATER_Z), sea_col(i * 360.0 / NC, r)) for i in range(NC)])
    first = rings[0]
    for i in range(NC):
        m.tri(centre, first[i], first[(i + 1) % NC], UP, "water", "water")
    for lo, hi in zip(rings, rings[1:]):
        for i in range(NC):
            j = (i + 1) % NC
            q = (lo[i], lo[j], hi[j], hi[i])
            if all(ground_z(bearing_of(m.verts[v]), rad_of(m.verts[v])) > WATER_Z + 0.4 for v in q):
                continue                              # under the land
            m.quad(q[0], q[1], q[2], q[3], UP, "water", "water")
    prev = rings[-1]
    for r, n in WATER_FAR:
        ring = [m.v(pol(j * 360.0 / n, r, WATER_Z), sea_col(j * 360.0 / n, r)) for j in range(n)]
        m.stitch(prev, ring, UP, "water", "water")
        prev = ring
    keep = [k for k, f in enumerate(m.faces)
            if not all(ground_z(bearing_of(m.verts[v]), rad_of(m.verts[v])) > WATER_Z + 0.4 for v in f)]
    m.faces = [m.faces[k] for k in keep]
    m.zones = [m.zones[k] for k in keep]
    m.chunks = [m.chunks[k] for k in keep]
    return m


# =============================================================================
# ROCKS -- faceted boulders, each sunk into what it stands on
# =============================================================================

def boulder(m, cx, cy, size, seed, sink=0.3, squash=0.7, chunk="rocks"):
    """A faceted boulder of about `size` metres, its base `sink` of its height below the ground."""
    r = Rng(seed)
    gz = ground_z(bearing_of((cx, cy, 0.0)), math.hypot(cx, cy))
    hz = size * 0.5 * squash
    cz = gz + hz * (1.0 - 2.0 * sink)
    yaw = r.u(0.0, TWO_PI)
    sx, sy = size * 0.5 * r.u(0.85, 1.2), size * 0.5 * r.u(0.7, 1.0)
    lats = (-0.95, -0.45, 0.1, 0.6)
    nseg = 7
    rings = []
    for la in lats:
        ring = []
        for k in range(nseg):
            a = (k + 0.5 * (len(rings) % 2)) * TWO_PI / nseg + r.u(-0.18, 0.18)
            j = r.u(0.82, 1.12)
            cl = math.cos(la * math.pi / 2.0)
            lx, ly = math.cos(a) * sx * cl * j, math.sin(a) * sy * cl * j
            px = cx + lx * math.cos(yaw) - ly * math.sin(yaw)
            py = cy + lx * math.sin(yaw) + ly * math.cos(yaw)
            pz = cz + math.sin(la * math.pi / 2.0) * hz * r.u(0.85, 1.1)
            ring.append(m.v((px, py, pz)))
        rings.append(ring)
    top = m.v((cx + r.u(-0.1, 0.1) * size, cy + r.u(-0.1, 0.1) * size, cz + hz * r.u(0.95, 1.12)))
    bot = m.v((cx, cy, cz - hz))
    out = lambda p: (p[0] - cx, p[1] - cy, p[2] - cz)
    m.grid(rings, out, "rock", chunk)
    for k in range(nseg):
        m.tri(rings[-1][k], rings[-1][(k + 1) % nseg], top, out, "rock", chunk)
        m.tri(rings[0][k], rings[0][(k + 1) % nseg], bot, out, "rock", chunk)
    return (cx, cy, size)


def _in_lane(b, r, pad):
    return abs(r - LANE_R) < 3.0 + pad


def build_rocks():
    m = Mesh()
    placed = []
    rr = Rng(SEED + 300)
    # at the wall's foot, on the sand
    for k in range(34):
        b = rr.u(0.0, 360.0)
        if s_of(b) > 146.0:
            continue
        size = rr.u(0.55, 1.5)
        r = wf(b) - size * 0.25 + rr.u(-0.3, 0.2)
        if r - size * 0.6 < LANE_R + 3.2:
            r = LANE_R + 3.2 + size * 0.6
        x, y, _z = pol(b, r, 0.0)
        placed.append(boulder(m, x, y, size, SEED + 1000 + k, sink=0.3))
    # low rocks in the shallows: never taller than 0.6 m over the water
    for k in range(10):
        b = rr.u(0.0, 360.0)
        if s_of(b) > 140.0:
            continue
        r = wl(b) - rr.u(0.6, 2.4)
        size = rr.u(0.45, 0.95)
        x, y, _z = pol(b, r, 0.0)
        placed.append(boulder(m, x, y, size, SEED + 1100 + k, sink=0.15, squash=0.55))
    # the jetty heads: a pile of big rock on each knoll
    for side, hb in ((0, 180.0 - HEAD_S), (1, 180.0 + HEAD_S)):
        for k in range(7):
            b = hb + rr.u(-4.5, 4.5)
            r = HEAD_R + rr.u(-6.5, 6.0)
            size = rr.u(1.6, 3.4)
            x, y, _z = pol(b, r, 0.0)
            placed.append(boulder(m, x, y, size, SEED + 1200 + 10 * side + k, sink=0.35))
    # the island: headland crests and the outer coast
    for k in range(60):
        b = rr.u(0.0, 360.0)
        if s_of(b) > 150.0:
            continue
        x0, y0, _z = pol(b, top_r(b) + 20.0, 0.0)
        d = rr.u(2.0, 40.0 if main_coast(x0, y0) > 0.0 else arm_w(b) + 3.0)
        r = top_r(b) + d
        z = ground_z(b, r)
        if z < WATER_Z - 0.4:
            continue
        size = rr.u(0.8, 2.6)
        x, y, _z = pol(b, r, 0.0)
        placed.append(boulder(m, x, y, size, SEED + 1300 + k, sink=0.35))
    INFO["rocks"] = len(placed)
    return m, placed


# =============================================================================
# PALMS -- segmented trunks, drooping folded fronds
# =============================================================================

def palm(m, base, height, lean_b, lean, seed, uv):
    """One palm: base (x, y, z) on the ground; lean_b the bearing it leans toward, lean in degrees."""
    r = Rng(seed)
    la = math.radians(-lean_b)
    dirx, diry = math.cos(la), math.sin(la)
    tl = math.radians(lean)
    nseg = max(6, int(height / TRUNK_SEG))
    sides = 6
    rings = []

    def axis(t):
        bend = math.sin(tl) * height * (0.45 * t + 0.55 * t * t)     # curving more toward the top
        return (base[0] + dirx * bend, base[1] + diry * bend, base[2] - 0.35 + (height + 0.35) * t * math.cos(tl * 0.6))

    for k in range(nseg + 1):
        t = k / float(nseg)
        c = axis(t)
        rad = lerp(TRUNK_R[0], TRUNK_R[1], t) * (1.35 if k == 0 else 1.0)
        for lip in ((0.0, 1.0), (0.12, 1.16)) if 0 < k < nseg and k % 2 == 0 else ((0.0, 1.0),):
            ring = []
            cz = c[2] - lip[0] * TRUNK_SEG
            for j in range(sides):
                a = j * TWO_PI / sides + k * 0.35
                ring.append(m.v((c[0] + math.cos(a) * rad * lip[1], c[1] + math.sin(a) * rad * lip[1], cz)))
            rings.append((ring, cz))
    rings.sort(key=lambda e: e[1])
    ring_ids = [e[0] for e in rings]
    out = lambda p: (p[0] - axis(clamp((p[2] - base[2]) / height))[0], p[1] - axis(clamp((p[2] - base[2]) / height))[1], 0.0)
    f0 = len(m.faces)
    m.grid(ring_ids, out, "bark", "palms")
    for fi in range(f0, len(m.faces)):
        for vi in m.faces[fi]:
            p = m.verts[vi]
            c = axis(clamp((p[2] - base[2]) / height))
            a = math.atan2(p[1] - c[1], p[0] - c[0])
            uv[(fi, vi)] = (0.5 + a / TWO_PI * 0.07, (p[2] - base[2]) / 12.8)
    top = axis(1.0)
    cap = m.v((top[0], top[1], top[2] + 0.25))
    for j in range(sides):
        m.tri(ring_ids[-1][j], ring_ids[-1][(j + 1) % sides], cap, UP, "bark", "palms")
        for vi in (ring_ids[-1][j], ring_ids[-1][(j + 1) % sides], cap):
            uv[(len(m.faces) - 1, vi)] = (0.5, 0.0)
    # fronds
    nf = r.i(*FRONDS)
    for f in range(nf):
        az = f * TWO_PI / nf + r.u(-0.25, 0.25)
        length = r.u(*FROND_L)
        up = r.u(0.25, 0.75)                 # the frond's rise before it droops
        ax, ay = math.cos(az), math.sin(az)
        px, py = -ay, ax
        steps = 4
        spine, left, right, ts = [], [], [], []
        for k in range(steps + 1):
            t = k / float(steps)
            dist = length * t
            z = top[2] + 0.1 + length * (up * t - (up + 0.55) * t * t)
            w = max(0.06, FROND_W * math.sin(math.pi * min(0.97, t * 1.15)) ** 0.7)
            w *= 1.0 if k % 2 == 0 else 0.82                                 # leaflets ragged along the edge
            c = (top[0] + ax * dist, top[1] + ay * dist, z)
            fold = 0.45 * w
            spine.append(m.v(c))
            left.append(m.v((c[0] + px * w, c[1] + py * w, c[2] - fold)))
            right.append(m.v((c[0] - px * w, c[1] - py * w, c[2] - fold)))
            ts.append((dist, w))
        for side, sign in ((left, 1.0), (right, -1.0)):
            for k in range(steps):
                q = (spine[k], spine[k + 1], side[k + 1], side[k])
                m.tri_as(q[0], q[1], q[2], "leaf", "palms")
                fi = len(m.faces) - 1
                m.tri_as(q[0], q[2], q[3], "leaf", "palms")
                for fj, tri in ((fi, (q[0], q[1], q[2])), (fi + 1, (q[0], q[2], q[3]))):
                    for vi in tri:
                        kk = spine.index(vi) if vi in spine else side.index(vi)
                        d_, w_ = ts[kk]
                        across = 0.0 if vi in spine else sign * w_
                        uv[(fj, vi)] = (0.5 + across / 12.8, d_ / 12.8)
    return top


def build_palms():
    m = Mesh()
    uv = {}
    rr = Rng(SEED + 500)
    spots = []
    # on the sand, at the wall's foot, leaning out over the beach
    tries = 0
    while len(spots) < PALM_SAND and tries < 400:
        tries += 1
        b = rr.u(0.0, 360.0)
        if s_of(b) > 128.0 or any(abs(angdiff(b, sb)) < 9.0 for sb, _r, _k in spots if _k == "sand"):
            continue
        r = wf(b) - rr.u(0.9, 1.4)
        spots.append((b, r, "sand"))
    # the island: thick along the wall, thinning back; none in the sea or on a cliff
    tries = 0
    while len([s for s in spots if s[2] == "island"]) < PALM_ISLAND and tries < 6000:
        tries += 1
        b = rr.u(0.0, 360.0)
        if s_of(b) > 147.0:
            continue
        d = 1.5 + 45.0 * rr.f() ** 1.7
        r = top_r(b) + d
        z = ground_z(b, r)
        if z < WATER_Z + 0.8:
            continue
        x, y, _z = pol(b, r, 0.0)
        if any(math.hypot(x - pol(sb, sr, 0.0)[0], y - pol(sb, sr, 0.0)[1]) < 4.2 for sb, sr, _k in spots):
            continue
        z2 = ground_z(b + 0.6, r + 0.6)
        if abs(z2 - z) > 0.9:
            continue
        spots.append((b, r, "island"))
    trunks = []
    for k, (b, r, kind) in enumerate(spots):
        x, y, _z = pol(b, r, 0.0)
        z = ground_z(b, r)
        if kind == "sand":
            h = rr.u(*PALM_SAND_H)
            lean_b = b + 180.0 + rr.u(-25.0, 25.0)     # toward the bay
            lean = rr.u(12.0, 24.0)
        else:
            h = rr.u(*PALM_H)
            lean_b = rr.u(0.0, 360.0)
            lean = rr.u(3.0, 16.0)
        palm(m, (x, y, z), h, lean_b, lean, SEED + 600 + k, uv)
        if kind == "sand":
            trunks.append((x, y, z))
    INFO["palms"] = len(spots)
    return m, uv, trunks


# =============================================================================
# COLLIDERS -- purpose-built
# =============================================================================

def build_ground_collider():
    """Shelf, shallows and sand at the sculpt's own heights (coarser), the wall as a sheer face 3.2 m
    tall on its foot line, and the jetty heads' knolls."""
    g = Mesh()
    offs = [-SHELF - 0.6, -SHELF, -1.5, 0.0, 1.3, 2.6]
    step = 2
    rows = []
    for off in offs:
        rows.append([g.v(pol(float(i), wl(float(i)) + off, sand_z(float(i), wl(float(i)) + off) - 0.02))
                     for i in range(0, NC, step)])
    for t in (0.35, 0.7, 1.0):
        rows.append([g.v(pol(float(i), lerp(wl(float(i)) + 2.6, wf(float(i)) + 0.15, t),
                             sand_z(float(i), lerp(wl(float(i)) + 2.6, wf(float(i)) + 0.15, t)) - 0.02))
                     for i in range(0, NC, step)])
    n = len(rows[0])
    for lo, hi in zip(rows, rows[1:]):
        for i in range(n):
            j = (i + 1) % n
            q = (lo[i], lo[j], hi[j], hi[i])
            if all(g.verts[v][2] < WATER_Z - 3.0 for v in q):
                continue
            g.quad(q[0], q[1], q[2], q[3], UP, "c", "ground")
    lo = rows[-1]
    hi = [g.v((g.verts[v][0], g.verts[v][1], g.verts[v][2] + 3.4)) for v in lo]
    inward = lambda c: (-c[0], -c[1], 0.0)
    for i in range(n):
        j = (i + 1) % n
        if s_of(i * step) > 160.0:
            continue
        g.quad(lo[i], lo[j], hi[j], hi[i], inward, "c", "ground")
    # the knolls: a coarse grid over each head
    for hb in (180.0 - HEAD_S, 180.0 + HEAD_S):
        grid = []
        for bi in range(9):
            b = hb - HEAD_W[0] * 1.1 + bi * HEAD_W[0] * 2.2 / 8.0
            grid.append([g.v(pol(b, HEAD_R + (ri - 4) * HEAD_W[1] * 1.1 / 4.0,
                                 ground_z(b, HEAD_R + (ri - 4) * HEAD_W[1] * 1.1 / 4.0) + 0.05)) for ri in range(9)])
        g.grid(grid, UP, "c", "ground", closed=False)
    return g


def build_rock_collider(placed):
    """Every boulder a runner can reach (sand, shallows, heads) as a squat octagonal prism."""
    c = Mesh()
    for cx, cy, size in placed:
        b, r = bearing_of((cx, cy, 0.0)), math.hypot(cx, cy)
        if r > wf(b) + 1.0 and abs(angdiff(abs(angdiff(b, 180.0)), HEAD_S)) > 9.0:
            continue
        gz = ground_z(b, r)
        lo, hi = [], []
        rad = size * 0.45
        for k in range(8):
            a = k * TWO_PI / 8.0
            lo.append(c.v((cx + math.cos(a) * rad, cy + math.sin(a) * rad, gz - 0.3)))
            hi.append(c.v((cx + math.cos(a) * rad * 0.7, cy + math.sin(a) * rad * 0.7, gz + size * 0.32)))
        out = lambda p, cx=cx, cy=cy: (p[0] - cx, p[1] - cy, 0.0)
        c.grid([lo, hi], out, "c", "rocks")
        t = c.v((cx, cy, gz + size * 0.38))
        for k in range(8):
            c.tri(hi[k], hi[(k + 1) % 8], t, UP, "c", "rocks")
    return c


def build_trunk_collider(trunks):
    c = Mesh()
    for x, y, z in trunks:
        lo = [c.v((x + math.cos(k * TWO_PI / 6) * 0.3, y + math.sin(k * TWO_PI / 6) * 0.3, z - 0.3)) for k in range(6)]
        hi = [c.v((x + math.cos(k * TWO_PI / 6) * 0.3, y + math.sin(k * TWO_PI / 6) * 0.3, z + 3.0)) for k in range(6)]
        c.grid([lo, hi], lambda p, x=x, y=y: (p[0] - x, p[1] - y, 0.0), "c", "palms")
    return c


def build_geometry():
    s = Sculpt()
    m = s.build()
    rocks, placed = build_rocks()
    palms, uv, trunks = build_palms()
    sea = build_sea()
    cols = {"ground": build_ground_collider(), "rocks": build_rock_collider(placed),
            "palms": build_trunk_collider(trunks)}
    return s, m, rocks, palms, uv, sea, cols


# =============================================================================
# SHEETS -- one tiling tile per class (lib/texel.py), world-projected
# =============================================================================

def _ref(centre):
    return max(30.0, math.hypot(centre[0], centre[1]))


SHEETS = {
    "sand": tx.Sheet("sand", ref_r=_ref, roughness=0.95),
    "rock": tx.Sheet("rock", mode="box", roughness=0.9),
    "grass": tx.Sheet("grass", mode="box", roughness=0.95),
    "jungle": tx.Sheet("jungle", mode="box", roughness=0.95),
    "bark": tx.Sheet("bark", mode="custom", roughness=0.95),
    "leaf": tx.Sheet("leaf", mode="custom", roughness=0.9, cull=False),
    "water": tx.Sheet("water", mode="box", roughness=0.3, cull=False),
}
CHUNKS = ["ground", "island", "rocks", "palms", "water"]
VIS = {"ground": "BeachGround", "island": "BeachIsland", "rocks": "BeachRocks", "palms": "BeachPalms",
       "water": "BeachWater"}
COLLIDED = ("ground", "rocks", "palms")


# =============================================================================
# BLENDER SIDE
# =============================================================================

def _tint(mat):
    """Base Color = tile x COLOR_0: the exporter writes a vertex-coloured texture."""
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    img = bsdf.inputs["Base Color"].links[0].from_node
    while img.type != "TEX_IMAGE":
        img = img.inputs[6].links[0].from_node
    dest = [l.to_socket for l in img.outputs["Color"].links]
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(img.outputs["Color"], [i for i in mix.inputs if i.identifier == "A_Color"][0])
    nt.links.new(col.outputs["Color"], [i for i in mix.inputs if i.identifier == "B_Color"][0])
    res = [o for o in mix.outputs if o.identifier == "Result_Color"][0]
    for sock in dest:
        nt.links.new(res, sock)


def _object(name, verts, cols, faces, zones, mats, face_uv=None):
    ob = mdl.mesh(name, verts, faces)
    tx.unwrap(ob, zones, SHEETS, seed=1, face_uv=face_uv)
    tx.finish(ob, zones, mats)
    attr = ob.data.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    attr.data.foreach_set("color", [c for rgba in cols for c in rgba])     # sRGB: Godot reads COLOR_0 so
    ob.data.color_attributes.active_color_index = 0
    ob.data.color_attributes.render_color_index = 0
    return ob


def _part(m, chunk, name, mats, uv=None):
    remap, verts, cols, faces, zones, fuv = {}, [], [], [], [], []
    for fi, (f, z, c) in enumerate(zip(m.faces, m.zones, m.chunks)):
        if c != chunk:
            continue
        g = []
        for vi in f:
            if vi not in remap:
                remap[vi] = len(verts)
                verts.append(m.verts[vi])
                cols.append(m.cols[vi])
            g.append(remap[vi])
        if uv is not None:
            fuv.append({remap[vi]: uv.get((fi, vi), (0.0, 0.0)) for vi in f})
        faces.append(tuple(g))
        zones.append(z)
    face_uv = {k: d for k, d in enumerate(fuv)} if uv is not None else None
    return _object(name, verts, cols, faces, zones, mats, face_uv)


def build():
    s, m, rocks, palms, uv, sea, cols = build_geometry()
    mats = tx.materials(NAME, SHEETS)
    for cls, mat in mats.items():
        _tint(mat)
    out = []
    parts = {"ground": _part(m, "ground", VIS["ground"], mats), "island": _part(m, "island", VIS["island"], mats),
             "rocks": _part(rocks, "rocks", VIS["rocks"], mats), "palms": _part(palms, "palms", VIS["palms"], mats, uv),
             "water": _part(sea, "water", VIS["water"], mats)}
    for chunk in CHUNKS:
        vis = parts[chunk]
        out.append(vis)
        line = "MDL STATS %s visual_tris=%d" % (chunk, len(vis.data.polygons))
        if chunk in COLLIDED:
            cv, _cc, cf = cols[chunk].used()
            cob = mdl.mesh(VIS[chunk] + "Collision-colonly", cv, cf)
            cob.hide_render = True
            out.append(cob)
            line += " collision_tris=%d" % len(cf)
        print(line)
    tx.report(SHEETS)
    print("MDL STATS rocks=%d palms=%d" % (INFO.get("rocks", 0), INFO.get("palms", 0)))
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
        obs = [by_name[label]]
        nodes = [label]
        if chunk in COLLIDED:
            obs.append(by_name[label + "Collision-colonly"])
            nodes += [label + "Collision", label + "Collision/CollisionShape3D"]
        path = os.path.join(out_dir, "%s_%s.glb" % (NAME, chunk))
        mdl.export_glb(path, obs)
        print("MDL EXPORT %s (%d bytes)" % (path, os.path.getsize(path)))
        made.append({"chunk": chunk, "glb": os.path.basename(path),
                     "contract": {"node_paths": nodes, "max_tris": 60000}})
    with open(os.path.join(out_dir, NAME + ".chunks.json"), "w") as fh:
        json.dump({"chunks": made}, fh, indent=1)
    return [os.path.join(out_dir, c["glb"]) for c in made]


def _check():
    s, m, rocks, palms, uv, sea, cols = build_geometry()
    il.report(m, "sculpt")
    for chunk in ("ground", "island"):
        sub = Mesh()
        sub.verts, sub.cols = m.verts, m.cols
        for f, z, c in zip(m.faces, m.zones, m.chunks):
            if c == chunk:
                sub.faces.append(f)
                sub.zones.append(z)
                sub.chunks.append(c)
        il.report(sub, chunk)
    il.report(rocks, "rocks")
    il.report(palms, "palms")
    il.report(sea, "water")
    for k, c in cols.items():
        il.report(c, k + "_collider")
    print("rocks=%d palms=%d lane r=%.1f lap=%.0f m" % (INFO["rocks"], INFO["palms"], LANE_R,
                                                         math.radians(EXIT_B - ENTRY_B) * LANE_R))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, export=_export_chunks)
