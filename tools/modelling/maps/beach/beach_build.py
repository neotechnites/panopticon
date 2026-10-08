"""
PANOPTICON -- beach: the beach yacht map. A U-shaped bay held between two curved sand jetties that run
out from a beach; the island rises behind a low wall of stacked beach rock; light turquoise sea, a
wadeable shelf, then deep teal water (the pit); a yacht anchored in the bay is the tower. ONE sculpt
(shared vertices where parts meet), exported per chunk:

    beach_ground.glb   seabed edge, shallows, sand, the wall's core, the jetty heads    BeachGround
    beach_island.glb   the island behind the wall: grass, canopy, hills, far coast      BeachIsland
    beach_rocks.glb    the wall's stacked boulders, and rocks in sand, shallows, heads  BeachRocks
    beach_palms.glb    palms planted in the sand and on the island                      BeachPalms
    beach_water.glb    the sea, flat and static, to the horizon (no collider)           BeachWater

World coordinates, instanced at identity (Blender +Z -> Godot +Y, +Y -> Godot -Z; bearings as the
scene's markers, pol()). The mouth faces bearing 0; the lap runs 60 -> 300 deg at r 68.5.

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
from beach_lib import (Mesh, Rng, UP, pol, bearing_of, rad_of, lerp, lerp3, clamp, smooth, ramp,  # noqa: E402
                       angdiff, h2, vnoise, fbm, ring_noise)
if bpy is not None:
    import mdl  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "beach"
SEED = 52817
FACING_YAW = 0.0
NC = 360                    # columns round the bay: 1 deg, 1.2 m at the lane
DECK_Z = 23.0               # the sand the lane runs on (every map's deck)
WATER_Z = 22.6              # the sea's surface
LANE_R = 68.5               # the lap: 60 -> 300 deg, 287 m; the mouth spans the other 120 deg
ENTRY_B, EXIT_B = 60.0, 300.0
RUN_S = 180.0 - ENTRY_B     # s (degrees off the beach's centre) of the start and the portal

# -- the bay shore: waterline, a narrow wadeable shelf, then the drop to deep water (the pit)
WL_R = 63.5                 # waterline radius ...
WL_WANDER = 0.8             # ... and how far it wanders
SHELF = 3.0                 # metres of shallows inside the waterline
SHELF_DEPTH = 0.5           # water depth at the shelf's edge
DEEP_Z = 10.0               # the drop-off's foot, under opaque water
SAND_ROWS = 7               # rows between the dry sand's first row and the wall foot
WET = 1.3                   # metres of wet sand above the waterline

# -- the beach rock wall: about 2 m of stacked boulders on a rock core, low enough to see the island over
WALL_R = 74.1               # the wall's foot (10.6 m of sand) ...
WALL_WANDER = 0.6
WALL_H = (1.4, 1.7)       # the core's height wanders between these (the cap course stands proud of it)
WALL_ROWS = ((0.0, 0.0), (0.2, 0.75), (0.45, 1.0), (0.7, 1.2), (0.9, 1.35), (1.0, 1.6))   # (share, metres back)
CORE_SHADE = 0.42           # the core shows only in the gaps between boulders
COURSES = (((0.2, 0.5), (0.0, 0.0), (1.2, 2.6), (0.75, 0.95), (0.3, 0.42), 0.0),
           ((0.5, 0.85), (0.75, 1.05), (0.85, 1.6), (0.65, 0.85), (0.15, 0.3), 0.12))
#   (metres back of the foot, base over the sand, size, squash, sink, share left out): foot and cap courses
ISLAND_LIFT = 1.45          # the island's ground behind the lip, over the deck

# -- the island behind the wall
ISLAND_D = [0.6, 1.6, 3.0, 5.0, 7.5, 10.0, 13.0, 16.0, 19.0, 22.0, 25.0, 28.5, 32.0, 36.0, 40.5, 45.5,
            51.0, 57.0, 64.0, 72.0, 81.0, 91.0, 102.0, 114.0, 127.0, 141.0]   # rows behind the wall's top
FAR_R = [(226.0, 360), (238.0, 360), (250.0, 360), (263.0, 360), (276.0, 360), (290.0, 360), (305.0, 360),
         (320.0, 360), (336.0, 360), (353.0, 360), (371.0, 360), (390.0, 360), (412.0, 240), (436.0, 240),
         (462.0, 240), (492.0, 240), (528.0, 180), (570.0, 180), (620.0, 120), (690.0, 120), (780.0, 90),
         (900.0, 72)]                                                     # (r, columns): rows ~12 m apart over the hills
RIDGE = (2.2, 4.5, 4.0)     # the jetty's hummock behind its wall: height, distance behind, half width
ARM_W = (14.0, 7.0)         # the jetty's land behind its wall, at its root and near its head (metres)
COAST_SLOPE = 0.42          # the coast's fall into the sea
MAIN_COAST = (-26.0, 0.003, 71.0)   # the big island's coast: x at the jetty roots, curvature, |y| it bends from
HILLS = ((180.0, 360.0, 78.0, 150.0), (143.0, 300.0, 52.0, 110.0), (216.0, 430.0, 104.0, 170.0),
         (121.0, 255.0, 34.0, 80.0), (246.0, 290.0, 46.0, 95.0), (166.0, 570.0, 72.0, 200.0),
         (198.0, 205.0, 24.0, 70.0), (266.0, 370.0, 40.0, 120.0), (100.0, 400.0, 44.0, 130.0),
         (232.0, 620.0, 90.0, 220.0))   # (bearing, r, height, reach)
RIDGES = (20.0, 95.0)       # ridged noise over the hills: metres, wavelength
CROWN = (7.0, 4.4, 150.0)   # the canopy's crowns: cell metres near the beach, crown height, r where cells double

# -- the jetty heads: a rock knoll where the sand ends, beyond the start and the portal
HEAD_S = RUN_S + 8.5        # s of the knoll's top
HEAD_W = (4.6, 9.5)         # half extents: degrees along, metres across
HEAD_H = 4.4
HEAD_R = 70.5
END_S = (RUN_S + 6.0, RUN_S + 17.0)    # the land drops away into the sea between these s

# -- the sea (sRGB, from the refs)
WATER_R = [0.0, 12.0, 26.0, 38.0, 48.0, 54.0]                           # rings in the bay (absolute)
WATER_IN = [-8.5, -6.5, -5.0, -4.0, -3.4, -3.0, -2.5, -2.0, -1.5, -1.0, -0.55, -0.2, 0.0, 0.8]
WATER_OUT = [77.0, 80.0, 83.0, 86.0, 89.0, 92.0, 96.0, 100.0, 105.0, 111.0]
WATER_FAR = [(118.0, 180), (126.0, 180), (135.0, 180), (146.0, 180), (160.0, 180), (178.0, 180),
             (200.0, 180), (230.0, 180), (270.0, 120), (330.0, 120), (420.0, 120), (550.0, 90),
             (750.0, 72), (1050.0, 60), (1500.0, 48), (2200.0, 36), (3000.0, 36)]
SHORE_FOAM = (0.88, 0.98, 0.96)        # at the waterline
SHALLOW = (0.62, 0.92, 0.86)           # the wadeable shelf (n64 refs 150..160, 229..232, 208..216)
TURQ = (0.12, 0.78, 0.86)              # light turquoise sea (Sunshine 10, 189, 224; img1 30, 212, 197)
PIT = (0.0, 0.47, 0.6)                 # the bay's deep water, the pit: deep teal
PIT_FADE = (8.0, 60.0)                 # x (toward the mouth) where the deep teal starts to thin, and is gone
OPEN_FAR = (0.0, 0.56, 0.8)            # open sea toward the horizon (Sunshine far 0, 139, 206)
HORIZON = (0.64, 0.8, 0.9)             # the sky's horizon colour: the sea's last ring
SKY_FADE = (700.0, 3000.0)

# -- colours carried by the vertices (x the drawn tile; grass and canopy tiles are pale)
WET_SAND = (0.88, 0.86, 0.79)
GRASS_VC = (0.46, 0.74, 0.32)
JUNGLE_VC = ((0.22, 0.48, 0.18), (0.3, 0.63, 0.23), (0.44, 0.73, 0.27))   # dark, mid and light canopy
HAZE_VC = (0.6, 0.76, 0.8)
HAZE_D = (120.0, 800.0)                # distance from the bay's centre where the haze starts and is whole

# -- palms
PALM_CLUSTERS = 40
PALM_SAND = 6               # clusters on the sand, at the wall's foot
PALM_SLOPE = 22             # single palms standing out of the canopy on the lower slopes
PALM_H = (7.0, 12.0)
PALM_SAND_H = (6.5, 9.5)
TRUNK_R = (0.23, 0.16)      # base and top radius
TRUNK_SEG = 0.85            # metres a trunk segment rises
FRONDS = (9, 11)
FROND_L = (3.8, 5.2)
FROND_W = 0.52              # half width at the widest

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
    lump = 0.15 * vnoise(b * 0.7, r * 0.5, SEED + 7)
    return HEAD_H * (1.0 + lump) * bell((s_of(b) - HEAD_S) / HEAD_W[0]) * bell((r - HEAD_R) / HEAD_W[1])


def arm_w(b):
    """How far the jetty's land runs behind its wall before the outer coast: narrowing to the head."""
    return lerp(ARM_W[0], ARM_W[1], ramp(s_of(b), 80.0, RUN_S + 4.0)) + 2.0 * ring_noise(b, SEED + 8, ((9, 1.0), (19, 0.6)))


def main_coast(x, y):
    """Metres inside the big island's coast (negative: out at sea). The coast meets the jetties' roots."""
    xc = MAIN_COAST[0] - MAIN_COAST[1] * max(abs(y) - MAIN_COAST[2], 0.0) ** 2 + 7.0 * fbm(y / 40.0, 3.0, SEED + 13, 3)
    return xc - x


def hills(x, y):
    """Distinct peaks with ridged flanks."""
    h = 0.0
    for b, r, hh, sp in HILLS:
        px, py, _z = pol(b, r, 0.0)
        d = math.hypot(x - px, y - py) / sp
        h = max(h, hh * bell(d * 0.85) ** 0.8) + 0.25 * hh * bell(d * 0.6)
    ridge = 1.0 - abs(fbm(x / RIDGES[1], y / RIDGES[1], SEED + 9, 3))
    return h + RIDGES[0] * ridge * ridge * ramp(h, 4.0, 30.0)


def canopy(x, y):
    """(height, shade) of the jungle's crowns: domes on a jittered grid, larger with distance."""
    cell = CROWN[0] * (1.0 + math.hypot(x, y) / CROWN[2])
    ci, cj = math.floor(x / cell), math.floor(y / cell)
    best = 0.0
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            i, j = ci + di, cj + dj
            fx = (i + 0.2 + 0.6 * h2(i, j, SEED + 60)) * cell
            fy = (j + 0.2 + 0.6 * h2(i, j, SEED + 61)) * cell
            rad = cell * (0.62 + 0.3 * h2(i, j, SEED + 62))
            best = max(best, 1.0 - (math.hypot(x - fx, y - fy) / rad) ** 2)
    return CROWN[1] * (cell / CROWN[0]) ** 0.5 * max(best, 0.0) ** 0.55, max(best, 0.0)


def jungle_mask(x, y, d):
    return ramp(d, 20.0, 34.0) * ramp(main_coast(x, y), 14.0, 34.0)


def island_z(b, r):
    """The island's ground behind the wall: the jetty's strip, or the big island, and their fall into the sea."""
    d = r - top_r(b)
    x, y, _z = pol(b, r, 0.0)
    s = s_of(b)
    base = DECK_Z + ISLAND_LIFT + 0.35 * fbm(x / 9.0, y / 9.0, SEED + 10)
    hump = RIDGE[0] * (1.0 - ramp(s, 100.0, RUN_S + 6.0)) * bell((d - RIDGE[1]) / RIDGE[2])
    arm = min(base + hump, WATER_Z + COAST_SLOPE * (arm_w(b) - d))
    inside = main_coast(x, y)
    land = base + min(d, 30.0) * 0.04 + hills(x, y) * ramp(d, 14.0, 90.0) * ramp(inside, 10.0, 90.0)
    jm = jungle_mask(x, y, d)
    if jm > 0.0:
        land += canopy(x, y)[0] * jm
    big = min(land, WATER_Z + COAST_SLOPE * inside)
    return max(max(arm, big), WATER_Z - 9.0) - drop(b)


def sand_z(b, r):
    """The beach between the shelf's foot and the wall foot: smooth, no grain in the shape."""
    w, f = wl(b), wf(b)
    if r < w:
        t = (w - r) / SHELF
        if t <= 1.0:
            z = WATER_Z - SHELF_DEPTH * (0.5 * t + 0.5 * t ** 1.4)
        else:
            z = WATER_Z - SHELF_DEPTH - (WATER_Z - SHELF_DEPTH - DEEP_Z) * smooth(min((t - 1.0) * SHELF / 5.0, 1.0))
    else:
        u = r - w
        z = WATER_Z + (DECK_Z - WATER_Z) * smooth(min(u / 2.6, 1.0)) + 0.16 * ramp(r, w + 2.6, f)
    return z + head(b, r) - drop(b)


def ground_z(b, r):
    """The ground's height anywhere (for planting and for the sea's colour)."""
    if r < wf(b):
        return sand_z(b, r)
    if r < top_r(b):
        return sand_z(b, wf(b)) + wall_h(b)
    return island_z(b, r)


# =============================================================================
# SCULPT
# =============================================================================

def FACE(c):
    """Up, leaning toward the bay."""
    r = math.hypot(c[0], c[1]) or 1.0
    return (-0.08 * c[0] / r, -0.08 * c[1] / r, 1.0)


def INWARD(c):
    """The wall's face: toward the bay, and up."""
    r = math.hypot(c[0], c[1]) or 1.0
    return (-c[0] / r, -c[1] / r, 0.35)


def _jb(b, k, amp):
    return amp * (2.0 * h2(int(round(b * 10.0)), k, SEED + 20) - 1.0)


def land_col(p):
    """Grass near the wall; canopy beyond in patches of three greens, crowns lit on top and dark between,
    valleys darker and ridges lighter; haze far off."""
    x, y = p[0], p[1]
    b, r = bearing_of(p), math.hypot(x, y)
    d = r - top_r(b)
    jm = jungle_mask(x, y, d)
    t = 0.5 + 0.5 * fbm(x / 70.0, y / 70.0, SEED + 33, 3)
    jungle = lerp3(JUNGLE_VC[0], JUNGLE_VC[1], ramp(t, 0.25, 0.5)) if t < 0.5 else \
        lerp3(JUNGLE_VC[1], JUNGLE_VC[2], ramp(t, 0.55, 0.8))
    c = lerp3(GRASS_VC, jungle, jm)
    if jm > 0.0:
        sh = canopy(x, y)[1]
        h0 = hills(x, y)
        rv = h0 - 0.25 * (hills(x + 18.0, y) + hills(x - 18.0, y) + hills(x, y + 18.0) + hills(x, y - 18.0))
        f = lerp(1.0, lerp(0.6, 1.14, sh) * clamp(1.0 + rv / 8.0, 0.68, 1.28), jm)
        c = (c[0] * f, c[1] * f, c[2] * f)
    n = 0.94 + 0.08 * vnoise(x / 13.0, y / 13.0, SEED + 32)
    c = (c[0] * n, c[1] * n, c[2] * n)
    c = lerp3(c, HAZE_VC, ramp(r, HAZE_D[0], HAZE_D[1]) ** 0.75)
    return (min(c[0], 1.0), min(c[1], 1.0), min(c[2], 1.0), 1.0)


class Sculpt(object):
    """The ground as one Mesh: rows from the drop-off out through sand, the wall's core and the island."""

    def __init__(self):
        self.m = Mesh()
        self.kind = {}

    def v(self, p, col, kind):
        i = self.m.v(p, col)
        self.kind[i] = kind
        return i

    def _sand_col(self, b, r):
        wet = 1.0 - ramp(r - wl(b), 0.25, WET)
        c = lerp3((1.0, 1.0, 1.0), WET_SAND, wet)
        foot = 1.0 - 0.1 * ramp(r, wf(b) - 1.4, wf(b))
        return (c[0] * foot, c[1] * foot, c[2] * foot, 1.0)

    def _core_col(self, p, hs):
        """Shadowed in the gaps low down; the core's top, seen between the cap stones, is plain rock."""
        n = lerp(CORE_SHADE, 0.92, ramp(hs, 0.7, 0.95)) * (0.9 + 0.2 * h2(int(p[0] * 5.0), int(p[1] * 5.0 + p[2] * 9.0), SEED + 31))
        return (n, n, n, 1.0)

    def build(self):
        rows = []
        shore = [-7.0, -5.0, -SHELF, -2.2, -1.4, -0.7, -0.25, 0.0, 0.45, 1.0, 1.7, 2.6]
        for k, off in enumerate(shore):
            row = []
            for i in range(NC):
                b = float(i)
                r = wl(b) + off
                z = sand_z(b, r) if off != 0.0 else WATER_Z + head(b, r) - drop(b)
                row.append(self.v(pol(b, r, z), self._sand_col(b, r), "shore" if off < 0.0 else "sand"))
            rows.append(row)
        for k in range(1, SAND_ROWS + 1):
            row = []
            for i in range(NC):
                b = float(i)
                r = lerp(wl(b) + 2.6, wf(b), k / float(SAND_ROWS + 1))
                row.append(self.v(pol(b, r, sand_z(b, r)), self._sand_col(b, r), "sand"))
            rows.append(row)
        for k, (hs, back) in enumerate(WALL_ROWS):
            row = []
            for i in range(NC):
                b = float(i)
                foot_z = sand_z(b, wf(b))
                if k == len(WALL_ROWS) - 1:
                    r = top_r(b)
                    z = island_z(b, r)
                    z = max(z, foot_z + wall_h(b)) if drop(b) < 0.5 else z
                    kind = "lip"
                elif k == 0:
                    r, z, kind = wf(b), foot_z, "foot"
                else:
                    r = wf(b) + back + _jb(b, 100 + k, 0.12)
                    z = foot_z + wall_h(b) * hs + _jb(b, 120 + k, 0.06)
                    kind = "wall"
                p = pol(b, r, z)
                row.append(self.v(p, self._core_col(p, hs) if k else self._sand_col(b, r), kind))
            rows.append(row)
        for k, d in enumerate(ISLAND_D):
            row = []
            for i in range(NC):
                b = float(i) + (_jb(float(i), 200 + k, 0.3) if k > 1 else 0.0)
                r = top_r(b) + d + _jb(float(i), 220 + k, 0.2 * min(d, 4.0))
                p = pol(b, r, island_z(b, r))
                row.append(self.v(p, land_col(p), "island"))
            rows.append(row)
        n_ground = len(shore) + SAND_ROWS + len(WALL_ROWS)
        self._grid(rows[:n_ground], "ground")
        self._grid(rows[n_ground - 1:], "island")
        prev = rows[-1]
        for r, n in FAR_R:
            ring = []
            for j in range(n):
                b = (j + 0.5 * (len(FAR_R) % 2)) * 360.0 / n
                p = pol(b, r, island_z(b, r))
                ring.append(self.v(p, land_col(p), "island"))
            self._stitch(prev, ring)
            prev = ring
        return self.m

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
                wall = any(self.kind.get(v) in ("wall", "lip") for v in q)
                m.quad(q[0], q[1], q[2], q[3], INWARD if wall else FACE, self._zone, chunk)

    def _stitch(self, a, b_):
        m = self.m
        before = len(m.faces)
        m.stitch(a, b_, FACE, self._zone, "island")
        keep = [k for k in range(before, len(m.faces)) if not self._hidden(m.faces[k])]
        m.faces[before:] = [m.faces[k] for k in keep]
        m.zones[before:] = [m.zones[k] for k in keep]
        m.chunks[before:] = [m.chunks[k] for k in keep]

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
        if steep > 0.55 or (head(b, r) > 0.45 and c[2] > WATER_Z + 0.3):
            return "rock"
        if c[2] < WATER_Z + 0.9 and steep < 0.3:
            return "sand"
        return "jungle" if jungle_mask(c[0], c[1], r - top_r(b)) > 0.5 else "grass"


# =============================================================================
# THE SEA -- flat, static, coloured by the depth under it
# =============================================================================

def sea_col(b, r):
    depth = WATER_Z - ground_z(b, r)
    c = lerp3(SHORE_FOAM, SHALLOW, ramp(depth, 0.0, 0.16))
    c = lerp3(c, TURQ, ramp(depth, SHELF_DEPTH * 0.9, 2.0))
    x = r * math.cos(math.radians(b))                     # toward the mouth: the deep teal thins out through it
    bay = ramp(x, PIT_FADE[1], PIT_FADE[0]) * ramp(r, WL_R + 2.0, WL_R - 2.0)
    c = lerp3(c, PIT, bay * ramp(depth, 2.5, 7.5))
    c = lerp3(c, OPEN_FAR, (1.0 - bay) * ramp(r, 110.0, 700.0))
    c = lerp3(c, HORIZON, ramp(r, SKY_FADE[0], SKY_FADE[1]) ** 1.4)
    return (c[0], c[1], c[2], 1.0)


def build_sea():
    m = Mesh()
    centre = m.v((0.0, 0.0, WATER_Z), sea_col(0.0, 0.0))
    inner = []
    for r in WATER_R[1:]:
        inner.append([m.v(pol(i * 3.0, r, WATER_Z), sea_col(i * 3.0, r)) for i in range(120)])   # deep, one colour
    shore = [[m.v(pol(float(i), wl(float(i)) + off, WATER_Z), sea_col(float(i), wl(float(i)) + off)) for i in range(NC)]
             for off in WATER_IN]
    for i in range(120):
        m.tri(centre, inner[0][i], inner[0][(i + 1) % 120], UP, "water", "water")
    m.grid(inner, UP, "water", "water")
    m.stitch(inner[-1], shore[0], UP, "water", "water")
    m.grid(shore, UP, "water", "water")
    rings = [shore[-1]]
    for r in WATER_OUT:
        ring = [m.v(pol(i * 1.5, r, WATER_Z), sea_col(i * 1.5, r)) for i in range(240)]
        m.stitch(rings[-1], ring, UP, "water", "water")
        rings.append(ring)
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

def boulder(m, cx, cy, size, seed, sink=0.3, squash=0.7, gz=None, nseg=6, lats=(-0.9, -0.3, 0.3, 0.72)):
    """A faceted boulder of about `size` metres, its base `sink` of its height below gz (the ground):
    its own proportions, lean, facet count, roundness and tone, so no two read alike."""
    r = Rng(seed)
    if gz is None:
        gz = ground_z(bearing_of((cx, cy, 0.0)), math.hypot(cx, cy))
    nseg = max(5, nseg + r.i(-1, 1))
    angular = r.f() < 0.45                                     # blocky, broken stone; else water-worn
    hz = size * 0.5 * squash * r.u(0.85, 1.15)
    cz = gz + hz * (1.0 - 2.0 * sink)
    yaw = r.u(0.0, TWO_PI)
    tilt, tilt_dir = math.radians(r.u(0.0, 18.0)), r.u(0.0, TWO_PI)
    sx, sy = size * 0.5 * r.u(0.85, 1.3), size * 0.5 * r.u(0.6, 0.95)
    tone = r.u(0.78, 1.06)
    tint = (1.03, 1.0, 0.95) if r.f() < 0.5 else (0.96, 0.98, 1.03)
    col = (tone * tint[0], tone * tint[1], tone * tint[2], 1.0)
    tx_, ty_ = math.cos(tilt_dir), math.sin(tilt_dir)

    def place(lx, ly, lz):
        """Local point -> world: lean about a horizontal axis, then yaw, then to the centre."""
        lean = lx * tx_ + ly * ty_
        lx2, lz2 = lx + tx_ * (lean * (math.cos(tilt) - 1.0) - lz * math.sin(tilt)), lz * math.cos(tilt) + lean * math.sin(tilt)
        ly2 = ly + ty_ * (lean * (math.cos(tilt) - 1.0) - lz * math.sin(tilt))
        return (cx + lx2 * math.cos(yaw) - ly2 * math.sin(yaw), cy + lx2 * math.sin(yaw) + ly2 * math.cos(yaw), cz + lz2)

    jit = (0.7, 1.18) if angular else (0.86, 1.08)
    rings = []
    for la in lats:
        ring = []
        for k in range(nseg):
            a = (k + 0.5 * (len(rings) % 2)) * TWO_PI / nseg + r.u(-0.25, 0.25)
            j = r.u(*jit)
            cl = math.cos(la * math.pi / 2.0)
            ring.append(m.v(place(math.cos(a) * sx * cl * j, math.sin(a) * sy * cl * j,
                                  math.sin(la * math.pi / 2.0) * hz * r.u(0.85, 1.1)), col))
        rings.append(ring)
    top = m.v(place(r.u(-0.12, 0.12) * size, r.u(-0.12, 0.12) * size, hz * (r.u(0.75, 0.9) if angular else r.u(0.95, 1.1))), col)
    bot = m.v(place(0.0, 0.0, -hz), col)
    out = lambda p: (p[0] - cx, p[1] - cy, p[2] - cz)
    m.grid(rings, out, "rock", "rocks")
    for k in range(nseg):
        m.tri(rings[-1][k], rings[-1][(k + 1) % nseg], top, out, "rock", "rocks")
        m.tri(rings[0][k], rings[0][(k + 1) % nseg], bot, out, "rock", "rocks")
    return (cx, cy, size)


def build_rocks():
    m = Mesh()
    placed = []
    rr = Rng(SEED + 300)
    # the wall: a foot course of big stones sunk in the sand, a cap course of smaller ones on the core,
    # every stone its own size, set back and spacing, and now and then a gap where the core shows
    for c, (back, base, size_r, squash, sink, gap) in enumerate(COURSES):
        b = rr.u(0.0, 2.0)
        while b < 360.0:
            if s_of(b) > HEAD_S - 1.0:
                b += 0.5
                continue
            size = lerp(size_r[0], size_r[1], rr.f() ** 1.6)
            r = wf(b) + rr.u(*back)
            if rr.f() >= gap:
                x, y, _z = pol(b, r, 0.0)
                gz = sand_z(b, wf(b)) + rr.u(*base)
                boulder(m, x, y, size, SEED + 2000 + 1000 * c + int(b * 10), sink=rr.u(*sink), squash=rr.u(*squash),
                        gz=gz, nseg=5, lats=(-0.6, 0.15, 0.65))
                if c == 0:
                    placed.append((x, y, size))
            b += size * rr.u(0.85, 1.15) / (math.radians(1.0) * r)
    # low rocks in the shallows: never more than 0.5 m over the water
    for k in range(12):
        b = rr.u(0.0, 360.0)
        if s_of(b) > RUN_S - 6.0:
            continue
        r = wl(b) - rr.u(0.6, 2.4)
        size = rr.u(0.45, 0.9)
        x, y, _z = pol(b, r, 0.0)
        placed.append(boulder(m, x, y, size, SEED + 1100 + k, sink=0.15, squash=0.55))
    # the jetty heads: a pile of big rock on each knoll
    for side, hb in ((0, 180.0 - HEAD_S), (1, 180.0 + HEAD_S)):
        for k in range(8):
            b = hb + rr.u(-3.8, 3.8)
            r = HEAD_R + rr.u(-6.5, 6.0)
            size = rr.u(1.6, 3.6)
            x, y, _z = pol(b, r, 0.0)
            placed.append(boulder(m, x, y, size, SEED + 1200 + 10 * side + k, sink=0.35, nseg=7))
    # the island: outcrops on the jetty strips and along the coast
    for k in range(36):
        b = rr.u(0.0, 360.0)
        if s_of(b) > RUN_S + 2.0:
            continue
        x0, y0, _z = pol(b, top_r(b) + 20.0, 0.0)
        d = rr.u(2.0, 40.0 if main_coast(x0, y0) > 0.0 else arm_w(b) + 3.0)
        r = top_r(b) + d
        if ground_z(b, r) < WATER_Z - 0.4:
            continue
        x, y, _z = pol(b, r, 0.0)
        boulder(m, x, y, rr.u(0.9, 2.6), SEED + 1300 + k, sink=0.35, lats=(-0.6, 0.15, 0.65))
    INFO["rocks"] = len(m.faces)
    return m, placed


# =============================================================================
# PALMS -- segmented trunks, full drooping crowns, planted in clusters
# =============================================================================

def palm(m, base, height, lean_b, lean, seed, uv, far=False):
    """One palm: base (x, y, z) on the ground; lean_b the bearing it leans toward, lean in degrees.
    far: a palm on the hills, seen from 60 m and more: fewer segments and fronds."""
    r = Rng(seed)
    la = math.radians(-lean_b)
    dirx, diry = math.cos(la), math.sin(la)
    tl = math.radians(lean)
    nseg = max(4, int(height / (TRUNK_SEG * (2.0 if far else 1.0))))
    sides = 5

    def axis(t):
        bend = math.sin(tl) * height * (0.45 * t + 0.55 * t * t)
        return (base[0] + dirx * bend, base[1] + diry * bend,
                base[2] - 0.35 + (height + 0.35) * t * math.cos(tl * 0.6))

    rings = []
    for k in range(nseg + 1):
        t = k / float(nseg)
        c = axis(t)
        rad = lerp(TRUNK_R[0], TRUNK_R[1], t) * (1.4 if k == 0 else 1.0)
        for lip in (((0.0, 1.0), (0.12, 1.16)) if 0 < k < nseg and k % 3 == 0 and not far else ((0.0, 1.0),)):
            cz = c[2] - lip[0] * TRUNK_SEG
            rings.append(([m.v((c[0] + math.cos(j * TWO_PI / sides + k * 0.35) * rad * lip[1],
                                c[1] + math.sin(j * TWO_PI / sides + k * 0.35) * rad * lip[1], cz))
                           for j in range(sides)], cz))
    rings.sort(key=lambda e: e[1])
    ring_ids = [e[0] for e in rings]

    def outward(p):
        c = axis(clamp((p[2] - base[2]) / height))
        return (p[0] - c[0], p[1] - c[1], 0.0)

    f0 = len(m.faces)
    m.grid(ring_ids, outward, "bark", "palms")
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
        for vi in m.faces[-1]:
            uv[(len(m.faces) - 1, vi)] = (0.5, 0.0)
    nf = r.i(*FRONDS) - (3 if far else 0)
    for f in range(nf + (0 if far else 3)):
        young = f >= nf                                     # three short fronds standing up in the middle
        az = (f * TWO_PI / nf + r.u(-0.2, 0.2)) if not young else r.u(0.0, TWO_PI)
        length = r.u(*FROND_L) * (0.45 if young else 1.0)
        up = r.u(0.9, 1.3) if young else r.u(0.2, 0.7)
        droop = 0.25 if young else r.u(0.75, 1.1)
        ax, ay = math.cos(az), math.sin(az)
        px, py = -ay, ax
        steps = 3 if young else 4
        spine, left, right, ts = [], [], [], []
        for k in range(steps + 1):
            t = k / float(steps)
            dist = length * t
            z = top[2] + 0.1 + length * (up * t - (up + droop) * t * t)
            w = max(0.07, FROND_W * (0.6 if young else 1.0) * math.sin(math.pi * min(0.97, 0.12 + t)) ** 0.6)
            c = (top[0] + ax * dist, top[1] + ay * dist, z)
            fold = 0.4 * w
            spine.append(m.v(c))
            left.append(m.v((c[0] + px * w, c[1] + py * w, c[2] - fold)))
            right.append(m.v((c[0] - px * w, c[1] - py * w, c[2] - fold)))
            ts.append((dist, w))
        for side, sign in ((left, 1.0), (right, -1.0)):
            for k in range(steps):
                q = (spine[k], spine[k + 1], side[k + 1], side[k])
                for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                    m.tri_as(tri[0], tri[1], tri[2], "leaf", "palms")
                    fi = len(m.faces) - 1
                    for vi in tri:
                        kk = spine.index(vi) if vi in spine else side.index(vi)
                        d_, w_ = ts[kk]
                        uv[(fi, vi)] = (0.5 + (0.0 if vi in spine else sign * w_) / 12.8, d_ / 12.8)


def build_palms():
    m = Mesh()
    uv = {}
    rr = Rng(SEED + 500)
    spots = []
    # on the sand at the wall's foot, in twos and threes, leaning out over the beach
    centres = []
    tries = 0
    while len(centres) < PALM_SAND and tries < 500:
        tries += 1
        b = rr.u(0.0, 360.0)
        if s_of(b) > RUN_S - 12.0 or any(abs(angdiff(b, c)) < 22.0 for c in centres):
            continue
        centres.append(b)
        for k in range(rr.i(2, 3)):
            bb = b + rr.u(-2.2, 2.2)
            spots.append((bb, wf(bb) - rr.u(1.0, 1.6), "sand", b))
    # the island: clusters thick along the wall, thinning back; none in the sea or on a cliff
    made, tries = 0, 0
    while made < PALM_CLUSTERS and tries < 4000:
        tries += 1
        b = rr.u(0.0, 360.0)
        if s_of(b) > RUN_S + 3.0:
            continue
        d = 1.5 + 34.0 * rr.f() ** 1.6
        r = top_r(b) + d
        if ground_z(b, r) < WATER_Z + 0.8:
            continue
        cx, cy, _z = pol(b, r, 0.0)
        if any(math.hypot(cx - pol(sb, sr, 0.0)[0], cy - pol(sb, sr, 0.0)[1]) < 6.0 for sb, sr, _k, _c in spots):
            continue
        made += 1
        for k in range(rr.i(1, 4)):
            a, rad = rr.u(0.0, TWO_PI), rr.u(0.0, 2.6)
            x, y = cx + math.cos(a) * rad, cy + math.sin(a) * rad
            pb, pr = bearing_of((x, y, 0.0)), math.hypot(x, y)
            if pr < top_r(pb) + 1.0 or ground_z(pb, pr) < WATER_Z + 0.8:
                continue
            if abs(ground_z(pb + 0.6, pr + 0.6) - ground_z(pb, pr)) > 0.9:
                continue
            spots.append((pb, pr, "island", bearing_of((cx, cy, 0.0)) if rad < 0.3 else None))
    made, tries = 0, 0
    while made < PALM_SLOPE and tries < 3000:
        tries += 1
        b = rr.u(0.0, 360.0)
        r = top_r(b) + rr.u(40.0, 140.0)
        x, y, _z = pol(b, r, 0.0)
        if main_coast(x, y) < 30.0 or abs(ground_z(b + 0.4, r + 1.0) - ground_z(b, r)) > 1.2:
            continue
        made += 1
        spots.append((b, r, "slope", None))
    trunks = []
    for k, (b, r, kind, centre) in enumerate(spots):
        x, y, _z = pol(b, r, 0.0)
        z = ground_z(b, r)
        if kind == "sand":
            h = rr.u(*PALM_SAND_H)
            lean_b = b + 180.0 + rr.u(-30.0, 30.0)                 # toward the bay
            lean = rr.u(14.0, 28.0)
            trunks.append((x, y, z))
        else:
            h = rr.u(*PALM_H)
            lean_b = rr.u(0.0, 360.0)
            lean = rr.u(4.0, 20.0)
        palm(m, (x, y, z), h, lean_b, lean, SEED + 600 + k, uv, far=kind == "slope")
    INFO["palms"] = len(spots)
    return m, uv, trunks


# =============================================================================
# COLLIDERS -- purpose-built
# =============================================================================

def build_ground_collider():
    """Shelf, shallows and sand at the sculpt's own heights (coarser), the wall as a sheer face 3.4 m
    tall in front of its boulders, and the jetty heads' knolls."""
    g = Mesh()
    step = 2
    offs = [-SHELF - 0.6, -SHELF, -1.5, 0.0, 1.3, 2.6]
    rows = []
    for off in offs:
        rows.append([g.v(pol(float(i), wl(float(i)) + off, sand_z(float(i), wl(float(i)) + off) - 0.02))
                     for i in range(0, NC, step)])
    for t in (0.35, 0.7, 1.0):
        rows.append([g.v(pol(float(i), lerp(wl(float(i)) + 2.6, wf(float(i)) - 0.5, t),
                             sand_z(float(i), lerp(wl(float(i)) + 2.6, wf(float(i)) - 0.5, t)) - 0.02))
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
        if s_of(i * step) > HEAD_S:
            continue
        j = (i + 1) % n
        g.quad(lo[i], lo[j], hi[j], hi[i], inward, "c", "ground")
    for hb in (180.0 - HEAD_S, 180.0 + HEAD_S):
        grid = []
        for bi in range(9):
            b = hb - HEAD_W[0] * 1.1 + bi * HEAD_W[0] * 2.2 / 8.0
            grid.append([g.v(pol(b, HEAD_R + (ri - 4) * HEAD_W[1] * 1.1 / 4.0,
                                 ground_z(b, HEAD_R + (ri - 4) * HEAD_W[1] * 1.1 / 4.0) + 0.05)) for ri in range(9)])
        g.grid(grid, UP, "c", "ground", closed=False)
    return g


def build_rock_collider(placed):
    """Every boulder a runner can reach (shallows, the wall's foot course, the heads) as a squat prism."""
    c = Mesh()
    for cx, cy, size in placed:
        b, r = bearing_of((cx, cy, 0.0)), math.hypot(cx, cy)
        gz = ground_z(b, min(r, wf(b) - 0.01))
        lo, hi = [], []
        rad = size * 0.45
        for k in range(8):
            a = k * TWO_PI / 8.0
            lo.append(c.v((cx + math.cos(a) * rad, cy + math.sin(a) * rad, gz - 0.3)))
            hi.append(c.v((cx + math.cos(a) * rad * 0.7, cy + math.sin(a) * rad * 0.7, gz + size * 0.32)))
        c.grid([lo, hi], lambda p, cx=cx, cy=cy: (p[0] - cx, p[1] - cy, 0.0), "c", "rocks")
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
SMOOTH = ("sand", "grass", "jungle", "water")     # Gouraud like the refs' ground; rock and palms stay faceted
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


def _shade(ob, zones):
    """Smooth faces in SMOOTH classes; every edge between two classes sharp, so a smooth face never
    bends toward a rock face beside it."""
    me = ob.data
    me.polygons.foreach_set("use_smooth", [z in SMOOTH for z in zones])
    owner = {}
    for pi, poly in enumerate(me.polygons):
        for ek in poly.edge_keys:
            owner.setdefault(ek, set()).add(zones[pi])
    for e in me.edges:
        if len(owner.get(e.key, ())) > 1:
            e.use_edge_sharp = True
    me.update()


def _object(name, verts, cols, faces, zones, mats, face_uv=None):
    ob = mdl.mesh(name, verts, faces)
    tx.unwrap(ob, zones, SHEETS, seed=1, face_uv=face_uv)
    tx.finish(ob, zones, mats)
    _shade(ob, zones)
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
    for mat in mats.values():
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
    print("MDL STATS palms=%d" % INFO.get("palms", 0))
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
    print("palms=%d lane r=%.1f lap=%.0f m" % (INFO["palms"], LANE_R, math.radians(EXIT_B - ENTRY_B) * LANE_R))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, export=_export_chunks)
