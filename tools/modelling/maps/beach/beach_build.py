"""
PANOPTICON -- beach: the beach yacht map. A U-shaped bay held between two curved sand jetties that run
out from a beach; the island rises behind a low wall of stacked beach rock; light turquoise sea, a
wadeable shelf, then deep teal water (the pit); a yacht anchored in the bay is the tower. ONE sculpt
(shared vertices where parts meet), exported per chunk:

    beach_ground.glb   seabed edge, shallows, sand, the wall's core, the jetty heads    BeachGround
    beach_island.glb   the island behind the wall: grass, canopy, hills, far coast      BeachIsland
    beach_rocks.glb    the wall's stacked boulders, and rocks in sand, shallows, heads  BeachRocks
    beach_palms.glb    palms planted in the sand and on the island                      BeachPalms
    beach_props.glb    beach sets, driftwood, shells, the tiki bar by the portal        BeachProps
    beach_water.glb    the sea to the horizon, moved by its shader (no collider)        BeachWater
    beach_waves.glb    the shore's wave strips, timed by beach_waves.gdshader            BeachWaves

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
SHELF = 11.0                # metres of shallows inside the waterline (8 to 14 along the U)
SHELF_DEPTH = 1.1           # water depth at the shallows' outer edge
DEEP_Z = 10.0               # the drop-off's foot, under opaque water
SAND_ROWS = 7               # rows between the dry sand's first row and the wall foot
WET = 1.3                   # metres of wet sand above the waterline

# -- the beach rock wall: about 2 m of stacked boulders on a rock core, low enough to see the island over
WALL_R = 74.1               # the wall's foot (10.6 m of sand) ...
WALL_WANDER = 0.6
WALL_H = (1.0, 1.25)      # the core's height wanders between these (the cap course stands proud of it)
WALL_ROWS = ((0.0, 0.0), (0.2, 0.75), (0.45, 1.0), (0.7, 1.2), (0.9, 1.35), (1.0, 1.6))   # (share, metres back)
CORE_SHADE = 0.74           # the core shows only in the gaps between boulders
COURSES = (((0.2, 0.5), (0.0, 0.0), (1.2, 2.6), (0.75, 0.95), (0.3, 0.42), 0.0),
           ((0.5, 0.85), (0.95, 1.25), (0.9, 1.7), (0.65, 0.85), (0.15, 0.3), 0.12))
#   (metres back of the foot, base over the sand, size, squash, sink, share left out): foot and cap courses
ISLAND_LIFT = 1.55          # the island's ground behind the lip, over the deck

# -- the island behind the wall
ISLAND_D = [0.6, 1.6, 3.0, 5.0, 7.5, 10.0, 13.0, 16.0, 19.0, 22.0, 25.0, 28.5, 32.0, 36.0, 40.5, 45.5,
            51.0, 57.0, 64.0, 72.0, 81.0, 91.0, 102.0, 114.0, 127.0, 141.0]   # rows behind the wall's top
FAR_R = [(226.0, 360), (238.0, 360), (250.0, 360), (263.0, 360), (276.0, 360), (290.0, 360), (305.0, 360),
         (320.0, 360), (336.0, 360), (353.0, 360), (371.0, 360), (390.0, 360), (412.0, 240), (436.0, 240),
         (462.0, 240), (492.0, 240), (528.0, 180), (570.0, 180), (620.0, 120), (690.0, 120), (780.0, 90),
         (900.0, 72)]                                                     # (r, columns): rows ~12 m apart over the hills
RIDGE = (1.6, 6.0, 4.5)     # the jetty's hummock behind its wall: height, distance behind, half width
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
WATER_R = [0.0, 12.0, 24.0, 34.0, 42.0]                           # rings in the bay (absolute)
WATER_IN = [-17.0, -12.0, -8.5, -6.0, -4.0, -2.8, -1.8, -1.0, -0.4, 0.0, 0.6, 1.2, 1.8, 2.4]
#            metres off the waterline: out past the swash's run-up, so the moving water always meets the sand
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
WET_SAND = (0.95, 0.94, 0.9)        # a damp band at the waterline; the swash's wetting is the sand shader's
REEF_PATCHES = 12                   # modest reef patches on the bay's sand, out past the shallows
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

# -- the water's baked look (GameCube style: per-vertex colour and alpha, linear values; beach_water.gdshader)
SEA_SHALLOW = (0.3, 0.97, 0.9)
SEA_TURQ = (0.02, 0.8, 0.86)
SEA_DEEP = (0.0, 0.34, 0.62)
SEA_OPEN = (0.0, 0.56, 0.8)
SEA_HORIZON = (0.64, 0.8, 0.9)
BED_TINT = (0.26, 0.84, 0.82)       # the bed under water takes the sea's colour ...
ABSORB = (0.3, 0.07, 0.055)         # ... and loses light with depth, red first


def to_lin(c):
    return tuple((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c[:3])


def to_srgb(c):
    return tuple(min(1.0, max(0.0, 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055)) for v in c[:3])


def under_water(c, depth):
    """A bed vertex colour (sRGB) as seen through `depth` metres of water, baked (sRGB back)."""
    if depth <= 0.0:
        return c
    lin = to_lin(c)
    k = smooth(depth / 0.8)
    lin = tuple(lin[i] * lerp(1.0, BED_TINT[i], k) * math.exp(-ABSORB[i] * depth) for i in range(3))
    return to_srgb(lin) + (c[3] if len(c) > 3 else 1.0,)


def caustic_w(depth):
    """How strongly the caustic net lies on the bed at this depth (baked into the bed's UV2.x)."""
    return smooth(depth / 0.15) * (1.0 - smooth((depth - 2.5) / 4.5)) if depth > 0.03 else 0.0


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


def _island_z(b, r):
    """The island's ground behind the wall: the jetty's strip, or the big island, and their fall into the sea."""
    d = r - top_r(b)
    x, y, _z = pol(b, r, 0.0)
    s = s_of(b)
    base = DECK_Z + ISLAND_LIFT + 0.35 * fbm(x / 9.0, y / 9.0, SEED + 10)
    inside = main_coast(x, y)
    hump = RIDGE[0] * (1.0 - ramp(s, 100.0, RUN_S + 6.0)) * bell((d - RIDGE[1]) / RIDGE[2]) * ramp(inside, 10.0, -10.0)
    arm = min(base + hump, WATER_Z + COAST_SLOPE * (arm_w(b) - d))
    land = base + min(d, 30.0) * 0.04 + hills(x, y) * ramp(d, 14.0, 90.0) * ramp(inside, 10.0, 90.0)
    jm = jungle_mask(x, y, d)
    if jm > 0.0:
        land += canopy(x, y)[0] * jm
    big = min(land, WATER_Z + COAST_SLOPE * inside)
    return max(max(arm, big), WATER_Z - 9.0) - drop(b)


def shelf_w(b):
    """The wadeable shallows' width along the U: 8 to 14 m of see-through water before it deepens."""
    return SHELF * (1.0 + 0.27 * ring_noise(b, SEED + 41, ((3, 1.0), (7, 0.7), (16, 0.4))))


def shelf_d(b):
    """The shallows' depth at their outer edge, 0.95 to 1.25 m (wadeable: the pit's roof is 1.6 m down)."""
    return SHELF_DEPTH * (1.0 + 0.14 * ring_noise(b, SEED + 43, ((4, 1.0), (9, 0.6))))


def reef(x, y):
    """Where the bay's few reef patches may grow: 0 = sand, 1 = reef ground."""
    return ramp(vnoise(x / 11.0, y / 11.0, SEED + 61), 0.35, 0.6)


def _kill_profile(b, r):
    """The slope past the shallows exactly as it was when the pit's roof was set (kept so the death line does
    not move until Ryan decides on the wading): from the shallows' edge toward 9 m over 10 to 16 m."""
    sd = shelf_d(b)
    t = wl(b) - r - shelf_w(b)
    x, y, _z = pol(b, r, 0.0)
    run = 13.0 + 3.0 * ring_noise(b, SEED + 45, ((2, 1.0), (5, 0.8), (11, 0.4)))
    floor = 9.0 + 2.0 * vnoise(x / 14.0, y / 14.0, SEED + 47)
    return sd + (floor - sd) * smooth(min(t / run, 1.0))


def anchorage(x, y):
    """Deeper water where the yacht lies: 5.5 m under it, gone by 24 m."""
    return 5.5 * (1.0 - smooth(math.hypot(x, y) / 24.0))


def mouth_floor(x):
    """The bay's floor depth by x alone: 2 m at the back half, deepening from mid-bay to 12 m between the
    jetty tips and 22 out at sea."""
    return 2.0 + 20.0 * smooth((x + 15.0) / 100.0)


def bed_depth(b, r):
    """The bay's sandy bed past the shallows, 2.5 to 4 m deep at the back of the bay and deepening steadily
    out through the mouth (x toward 0 deg); every line toward the mouth only goes deeper."""
    sd = shelf_d(b)
    t = wl(b) - r - shelf_w(b)
    x, y, _z = pol(b, r, 0.0)
    d = max(1.7, 2.5 + 0.7 * vnoise(x / 20.0, y / 20.0, SEED + 47), mouth_floor(x), anchorage(x, y))
    run = lerp(4.0, 34.0, smooth((x + 15.0) / 50.0))            # out toward the mouth the slope is long
    old = _kill_profile(b, r)
    if old < 1.7:
        return old                                             # the death line stays where it was
    new = max(1.7, lerp(sd, d, smooth(min(t / run, 1.0))))
    return lerp(old, new, smooth((old - 1.7) / 2.0))


def _sand_z(b, r):
    """The beach between the bay's floor and the wall foot: smooth, no grain in the shape."""
    w, f = wl(b), wf(b)
    if r < w:
        t = (w - r) / shelf_w(b)
        if t <= 1.0:
            z = WATER_Z - shelf_d(b) * (0.3 * t + 0.7 * t ** 1.6)
        else:
            z = WATER_Z - bed_depth(b, r)
    else:
        u = r - w
        z = WATER_Z + (DECK_Z - WATER_Z) * smooth(min(u / 2.6, 1.0)) + 0.16 * ramp(r, w + 2.6, f)
    return z + head(b, r) - drop(b)


def mouth_cap(b, r, z):
    """Out through the bay's mouth (past the jetty heads) the sea floor deepens steadily with x toward the
    open ocean, whatever the sunk land under it would say; nothing on the run or the heads changes."""
    k = ramp(abs(s_of(b)), HEAD_S + 5.5, HEAD_S + 16.0) * ramp(r, WL_R - 6.0, WL_R + 4.0)   # outside the bay only
    if k <= 0.0:
        return z
    x = pol(b, r, 0.0)[0]
    return min(z, WATER_Z - k * (2.0 + 20.0 * smooth((x + 20.0) / 100.0)))


def sand_z(b, r):
    z = _sand_z(b, r)
    km = ramp(s_of(b), HEAD_S - 1.0, HEAD_S + 7.0) * (1.0 - ramp(r, WL_R - 2.0, WL_R + 6.0))
    if km > 0.0:                       # across the mouth the floor just deepens seaward: no rim, no ridge
        x = pol(b, r, 0.0)[0]
        z = lerp(z, WATER_Z - max(mouth_floor(x), anchorage(x, pol(b, r, 0.0)[1])), km)
    return mouth_cap(b, r, z)


def island_z(b, r):
    return mouth_cap(b, r, _island_z(b, r))


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
        self.m.uv2 = {}
        self.kind = {}

    def v(self, p, col, kind):
        depth = WATER_Z - p[2]
        i = self.m.v(p, under_water(col, depth))
        self.m.uv2[i] = (caustic_w(depth), 0.0)
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
        shore = [-40.0, -37.0, -34.0, -31.0, -28.0, -25.5, -23.0, -21.0, -19.0, -17.0, -15.3, -13.7, -12.2, -10.8,
                 -9.4, -8.0, -6.6, -5.3, -4.1, -3.0, -2.0, -1.2, -0.55, -0.2, 0.0, 0.45, 1.0, 1.7, 2.6]
        for k, off in enumerate(shore):
            row = []
            for i in range(NC):
                b = float(i)
                r = wl(b) + off
                z = sand_z(b, r) if off != 0.0 else mouth_cap(b, r, WATER_Z + head(b, r) - drop(b))
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
        # the bay's floor inside the innermost row, in coarser rings to its middle
        prev = rows[0]
        for rr_, n in ((20.0, 240), (16.0, 200), (12.0, 160), (8.0, 100), (4.0, 50)):
            ring = []
            for j in range(n):
                b = j * 360.0 / n
                ring.append(self.v(pol(b, rr_, sand_z(b, rr_)), self._sand_col(b, rr_), "shore"))
            self.m.stitch(prev, ring, FACE, self._zone, "ground")
            prev = ring
        mid = self.v((0.0, 0.0, sand_z(0.0, 0.0)), self._sand_col(0.0, 0.0), "shore")
        for j in range(len(prev)):
            self.m.tri(prev[j], prev[(j + 1) % len(prev)], mid, FACE, self._zone, "ground")
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
        """Far out at sea (r > 100) the sea is opaque; the bay and its mouth keep their whole bed."""
        return all(self.m.verts[v][2] < WATER_Z - 2.5 and rad_of(self.m.verts[v]) > 100.0 for v in ids)

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

def sea_col(b, r, rocks=()):
    """The water's baked look at (b, r): (linear colour, alpha, foam ring round rocks)."""
    depth = WATER_Z - ground_z(b, r)
    if r > 90.0 and depth > 8.5:       # the open sea reads deep all round, whatever sank where
        depth = 14.0
    d = max(depth, 0.0)
    col = lerp3(SEA_SHALLOW, SEA_TURQ, smooth((d - 0.05) / 1.05))
    col = lerp3(col, SEA_DEEP, smooth((d - 2.2) / 4.0))       # darker blue from mid-bay out
    col = lerp3(col, SEA_OPEN, smooth((r - 110.0) / 590.0))
    far = smooth((r - SKY_FADE[0]) / (SKY_FADE[1] - SKY_FADE[0])) ** 1.4
    col = lerp3(col, SEA_HORIZON, far)
    alpha = 0.14 + 0.5 * (1.0 - math.exp(-d / 6.0))
    alpha = lerp(alpha, 1.0, smooth((d - 6.0) / 8.0))
    alpha = lerp(alpha, 1.0, smooth((r - 84.0) / 14.0))
    px, py, _z = pol(b, r, 0.0)
    ring = 0.0
    for cx, cy, size in rocks:
        dd = math.hypot(px - cx, py - cy) - size * 0.45
        if dd < 2.4:
            ring = max(ring, ramp(dd, 2.3, 0.1))
    return col + (1.0,), (alpha, 1.0 - ring)      # glTF flips v: the shader reads UV2.y as the ring


def build_sea(rocks=()):
    """The sea's surface at still water; the shader moves it. rocks: (x, y, size) the foam rings round."""
    m = Mesh()
    m.uv2 = {}

    def col(b, r):
        c, data = sea_col(b, r, rocks)
        col.last = data
        return c

    _v = m.v

    def vtx(p, c):
        i = _v(p, c)
        m.uv2[i] = col.last
        return i

    m.v = vtx
    centre = m.v((0.0, 0.0, WATER_Z), col(0.0, 0.0))
    inner = []
    for r in WATER_R[1:]:
        inner.append([m.v(pol(i * 3.0, r, WATER_Z), col(i * 3.0, r)) for i in range(120)])   # deep, one colour
    shore = [[m.v(pol(i * 2.0, wl(i * 2.0) + off, WATER_Z), col(i * 2.0, wl(i * 2.0) + off)) for i in range(180)]
             for off in WATER_IN]                                  # 2 deg columns: the era's budget
    for i in range(120):
        m.tri(centre, inner[0][i], inner[0][(i + 1) % 120], UP, "water", "water")
    m.grid(inner, UP, "water", "water")
    m.stitch(inner[-1], shore[0], UP, "water", "water")
    m.grid(shore, UP, "water", "water")
    rings = [shore[-1]]
    for r in WATER_OUT:
        ring = [m.v(pol(i * 1.5, r, WATER_Z), col(i * 1.5, r)) for i in range(240)]
        m.stitch(rings[-1], ring, UP, "water", "water")
        rings.append(ring)
    prev = rings[-1]
    for r, n in WATER_FAR:
        ring = [m.v(pol(j * 360.0 / n, r, WATER_Z), col(j * 360.0 / n, r)) for j in range(n)]
        m.stitch(prev, ring, UP, "water", "water")
        prev = ring
    keep = [k for k, f in enumerate(m.faces)
            if not all(ground_z(bearing_of(m.verts[v]), rad_of(m.verts[v])) > WATER_Z + 0.6 for v in f)]
    m.faces = [m.faces[k] for k in keep]
    m.zones = [m.zones[k] for k in keep]
    m.chunks = [m.chunks[k] for k in keep]
    return m


# =============================================================================
# ROCKS -- faceted boulders, each sunk into what it stands on
# =============================================================================

def boulder(m, cx, cy, size, seed, sink=0.3, squash=0.7, gz=None, nseg=6, lats=(-0.9, -0.3, 0.3, 0.72), zone="rock"):
    """A faceted boulder of about `size` metres, its base `sink` of its height below gz (the ground):
    its own proportions, lean, facet count, roundness, broken faces and tone, darker and warmer at its foot."""
    r = Rng(seed)
    first = len(m.verts)
    if gz is None:
        gz = ground_z(bearing_of((cx, cy, 0.0)), math.hypot(cx, cy))
    nseg = max(5, nseg + r.i(-1, 1))
    angular = r.f() < 0.45                                     # blocky, broken stone; else water-worn
    hz = size * 0.5 * squash * r.u(0.85, 1.15)
    cz = gz + hz * (1.0 - 2.0 * sink)
    yaw = r.u(0.0, TWO_PI)
    tilt, tilt_dir = math.radians(r.u(0.0, 18.0)), r.u(0.0, TWO_PI)
    sx, sy = size * 0.5 * r.u(0.85, 1.3), size * 0.5 * r.u(0.6, 0.95)
    tone = r.u(0.9, 1.04)
    tint = (1.03, 1.0, 0.95) if r.f() < 0.5 else (0.96, 0.98, 1.03)
    col = (tone * tint[0], tone * tint[1], tone * tint[2], 1.0)
    tx_, ty_ = math.cos(tilt_dir), math.sin(tilt_dir)

    def place(lx, ly, lz):
        """Local point -> world: lean about a horizontal axis, then yaw, then to the centre."""
        lean = lx * tx_ + ly * ty_
        lx2, lz2 = lx + tx_ * (lean * (math.cos(tilt) - 1.0) - lz * math.sin(tilt)), lz * math.cos(tilt) + lean * math.sin(tilt)
        ly2 = ly + ty_ * (lean * (math.cos(tilt) - 1.0) - lz * math.sin(tilt))
        return (cx + lx2 * math.cos(yaw) - ly2 * math.sin(yaw), cy + lx2 * math.sin(yaw) + ly2 * math.cos(yaw), cz + lz2)

    jit = (0.62, 1.25) if angular else (0.8, 1.12)
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
    # broken faces: two or three planes shear the stone flat, sideways and across the top
    for k in range(r.i(2, 3)):
        a, up = r.u(0.0, TWO_PI), (r.u(0.5, 0.95) if k == 0 else r.u(-0.1, 0.45))
        dv = il.unit((math.cos(a) * math.sqrt(1.0 - up * up), math.sin(a) * math.sqrt(1.0 - up * up), up))
        reach = max(abs(il.dot(il.sub(m.verts[i], (cx, cy, cz)), dv)) for i in range(first, len(m.verts)))
        cut = reach * r.u(0.62, 0.82)
        for i in range(first, len(m.verts)):
            over = il.dot(il.sub(m.verts[i], (cx, cy, cz)), dv) - cut
            if over > 0.0:
                m.verts[i] = il.sub(m.verts[i], il.scale(dv, over))
    lo_z = min(m.verts[i][2] for i in range(first, len(m.verts)))
    hi_z = max(m.verts[i][2] for i in range(first, len(m.verts)))
    foot = max(lo_z, gz - 0.05)
    for i in range(first, len(m.verts)):
        t = clamp((m.verts[i][2] - foot) / max(hi_z - foot, 0.1)) ** 0.8
        shade = lerp(0.8, 1.0, t)
        warm = lerp3((1.0, 0.93, 0.84), (0.98, 0.99, 1.0), t)
        m.cols[i] = (min(1.0, col[0] * shade * warm[0]), min(1.0, col[1] * shade * warm[1]),
                     min(1.0, col[2] * shade * warm[2]), 1.0)
    for i in range(first, len(m.verts)):                       # baked: wet above still water, the weed band,
        h = m.verts[i][2] - WATER_Z                             # and the water's absorption below
        c = m.cols[i]
        if 0.0 <= h < 0.35:
            w = lerp(0.62, 1.0, smooth(h / 0.35))
            c = (c[0] * w, c[1] * w * 0.98, c[2] * w * 0.95, 1.0)
        elif h < 0.0:
            weed = 1.0 - smooth((-h - 0.05) / 0.4)
            c = (c[0] * lerp(1.0, 0.5, weed), c[1] * lerp(1.0, 0.54, weed), c[2] * lerp(1.0, 0.42, weed), 1.0)
            c = under_water(c, -h)
        m.cols[i] = c
    out = lambda p: (p[0] - cx, p[1] - cy, p[2] - cz)
    m.grid(rings, out, zone, "rocks")
    for k in range(nseg):
        m.tri(rings[-1][k], rings[-1][(k + 1) % nseg], top, out, zone, "rocks")
        m.tri(rings[0][k], rings[0][(k + 1) % nseg], bot, out, zone, "rocks")
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
    # a few modest reef patches on the bay's sand, out past the shallows: low flattened coral heads, crowded
    # in the middle of the patch and scattering out into the sand, all well under the surface
    made, tries = 0, 0
    while made < REEF_PATCHES and tries < 4000:
        tries += 1
        b = rr.u(0.0, 360.0)
        r = rr.u(8.0, wl(b) - shelf_w(b) - 4.0)
        x, y, _z = pol(b, r, 0.0)
        depth = WATER_Z - ground_z(b, r)
        if reef(x, y) < 0.7 or not 2.4 < depth < 9.0:
            continue
        made += 1
        radius = rr.u(2.5, 4.5)
        for k in range(rr.i(9, 16)):
            a, d = rr.u(0.0, TWO_PI), radius * rr.f() ** 0.7
            cx, cy = x + math.cos(a) * d, y + math.sin(a) * d
            gz = ground_z(bearing_of((cx, cy, 0.0)), math.hypot(cx, cy))
            size = min(rr.u(0.6, 1.8) * (1.0 - 0.5 * d / radius), (WATER_Z - 0.9 - gz) / 0.35)
            if size > 0.35:
                boulder(m, cx, cy, size, SEED + 4000 + 20 * made + k, sink=0.45, squash=rr.u(0.4, 0.6), gz=gz,
                        nseg=6, lats=(-0.6, 0.15, 0.65), zone="reef")
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
# PROPS -- beach sets (umbrella, towels, loungers, a cooler), driftwood, shells, the tiki hut by the portal
# =============================================================================

def frame(b, r, yaw=0.0):
    """(origin on the ground, along, out): `along` the way bearings rise, `out` toward the wall, turned by yaw."""
    a = math.radians(-b)
    t, n = (math.sin(a), -math.cos(a), 0.0), (math.cos(a), math.sin(a), 0.0)
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    t, n = (t[0] * cy + n[0] * sy, t[1] * cy + n[1] * sy, 0.0), (n[0] * cy - t[0] * sy, n[1] * cy - t[1] * sy, 0.0)
    x, y, _z = pol(b, r, 0.0)
    return (x, y, ground_z(b, r)), t, n


def at(o, t, n, a, d, h):
    return (o[0] + t[0] * a + n[0] * d, o[1] + t[1] * a + n[1] * d, o[2] + h)


def box(m, c, ax, ay, az, zone, col, bottom=False):
    """An oriented box: centre c, half-extent vectors ax, ay, az; flat faces, its own colour."""
    sgn = ((1, 1), (1, -1), (-1, -1), (-1, 1))
    for e, (p, q) in ((az, (ax, ay)), (ax, (ay, az)), (ay, (az, ax))):
        for s in ((1, -1) if bottom or e is not az else (1,)):
            ctr = tuple(c[k] + s * e[k] for k in range(3))
            vs = [m.v(tuple(ctr[k] + i * p[k] + j * q[k] for k in range(3)), col) for i, j in sgn]
            m.quad(vs[0], vs[1], vs[2], vs[3], tuple(s * e[k] for k in range(3)), zone, "props")


def tube(m, uv, pts, radii, sides, zone, col, caps=(True, True)):
    """A tube along pts (each its radius), its UV unrolled: u round (metres), v along (metres)."""
    rings, along = [], 0.0
    for k, p in enumerate(pts):
        q0, q1 = pts[max(0, k - 1)], pts[min(len(pts) - 1, k + 1)]
        d = il.unit(il.sub(q1, q0))
        side = il.unit(il.cross(d, UP if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)))
        up = il.cross(side, d)
        if k:
            along += math.dist(pts[k - 1], p)
        ring = []
        for j in range(sides + 1):
            a = j * TWO_PI / sides
            ring.append((m.v(tuple(p[i] + radii[k] * (math.cos(a) * side[i] + math.sin(a) * up[i]) for i in range(3)), col),
                         (j * TWO_PI * radii[0] / sides / 12.8, along / 12.8)))
        rings.append(ring)
    f0 = len(m.faces)
    m.grid([[v for v, _uv in ring] for ring in rings],
           lambda c: il.sub(c, pts[min(range(len(pts)), key=lambda i: math.dist(pts[i], c))]), zone, "props", closed=False)
    lookup = {v: w for ring in rings for v, w in ring}
    for fi in range(f0, len(m.faces)):
        for vi in m.faces[fi]:
            uv[(fi, vi)] = lookup[vi]
    for cap, ring, sgn in ((caps[0], rings[0], -1.0), (caps[1], rings[-1], 1.0)):
        if not cap:
            continue
        p = pts[0] if sgn < 0 else pts[-1]
        q = pts[1] if sgn < 0 else pts[-2]
        out = il.unit(il.sub(p, q))
        mid = m.v(p, col)
        for j in range(sides):
            m.tri(ring[j][0], ring[j + 1][0], mid, out, zone, "props")
            for vi in m.faces[-1]:
                pp = m.verts[vi]
                uv[(len(m.faces) - 1, vi)] = (0.5 + (pp[0] - p[0]) / 12.8, 0.5 + (pp[1] - p[1]) / 12.8)


def umbrella(m, o, t, n, cols, lean, seed):
    """A beach umbrella: a pole sunk in the sand, an eight-gore canopy (gores alternate cols), leaning `lean`."""
    r = Rng(seed)
    tilt = math.radians(lean)
    axis = tuple(n[k] * -math.sin(tilt) + UP[k] * math.cos(tilt) for k in range(3))   # leaning toward the bay
    pole = lambda h: tuple(o[k] + axis[k] * h for k in range(3))
    side = il.unit(il.cross(axis, n))
    fwd = il.cross(side, axis)
    box(m, pole(1.0), tuple(side[k] * 0.03 for k in range(3)), tuple(fwd[k] * 0.03 for k in range(3)),
        tuple(axis[k] * 1.35 for k in range(3)), "plastic", (0.94, 0.93, 0.9))
    top = 2.42
    apex = pole(top)
    spin = r.u(0.0, TWO_PI)
    ribs = []
    for g in range(9):
        a = spin + g * TWO_PI / 8.0
        dirv = tuple(math.cos(a) * side[k] + math.sin(a) * fwd[k] for k in range(3))
        ribs.append([tuple(apex[k] + dirv[k] * rad + axis[k] * -drop for k in range(3))
                     for rad, drop in ((0.62, 0.16), (1.18, 0.42))])
    for g in range(8):
        col = cols[g % 2]
        a0, a1 = ribs[g], ribs[g + 1]
        mid = tuple((a0[1][k] + a1[1][k]) * 0.5 + axis[k] * 0.07 for k in range(3))
        ap, m0, m1, r0, r1, sc = (m.v(p, col) for p in (apex, a0[0], a1[0], a0[1], a1[1], mid))
        for tri in ((ap, m0, m1), (m0, r0, sc), (m0, sc, m1), (m1, sc, r1)):
            m.tri(tri[0], tri[1], tri[2], axis, "canvas", "props")
    box(m, pole(top + 0.05), tuple(side[k] * 0.045 for k in range(3)), tuple(fwd[k] * 0.045 for k in range(3)),
        tuple(axis[k] * 0.06 for k in range(3)), "plastic", (0.94, 0.93, 0.9))
    return (o[0], o[1], 0.06)


def towel(m, b, r, length, width, yaw, stripes):
    """A towel laid on the sand, following it, a thin hem down into it; striped across its length."""
    o, t, n = frame(b, r, yaw)
    bands = len(stripes)
    pts = lambda a, d: (lambda q: (q[0], q[1], ground_z(bearing_of(q), math.hypot(q[0], q[1])) + 0.035))(at(o, t, n, a, d, 0.0))
    for k in range(bands):
        a0, a1 = -length / 2 + length * k / bands, -length / 2 + length * (k + 1) / bands
        col = stripes[k]
        q = [m.v(pts(a, d), col) for a, d in ((a0, -width / 2), (a1, -width / 2), (a1, width / 2), (a0, width / 2))]
        m.quad(q[0], q[1], q[2], q[3], UP, "canvas", "props")
        for (aa, dd), (ab, db) in ((((a0, -width / 2)), (a1, -width / 2)), ((a1, width / 2), (a0, width / 2))):
            p0, p1 = pts(aa, dd), pts(ab, db)
            h = [m.v(p0, col), m.v(p1, col), m.v((p1[0], p1[1], p1[2] - 0.08), col), m.v((p0[0], p0[1], p0[2] - 0.08), col)]
            m.quad(h[0], h[1], h[2], h[3], tuple(n[i] * (1 if dd > 0 else -1) for i in range(3)), "canvas", "props")
        if k in (0, bands - 1):
            a = a0 if k == 0 else a1
            p0, p1 = pts(a, -width / 2), pts(a, width / 2)
            h = [m.v(p0, col), m.v(p1, col), m.v((p1[0], p1[1], p1[2] - 0.08), col), m.v((p0[0], p0[1], p0[2] - 0.08), col)]
            m.quad(h[0], h[1], h[2], h[3], tuple(t[i] * (1 if k else -1) for i in range(3)), "canvas", "props")


def lounger(m, b, r, yaw, cushion):
    """A slatted teak sun lounger, its back raised, a cushion in the set's colour; 1.95 x 0.64 m."""
    o, t, n = frame(b, r, yaw)
    w = 0.32
    T = lambda s: tuple(t[k] * s for k in range(3))
    N = lambda s: tuple(n[k] * s for k in range(3))
    Z = lambda s: (0.0, 0.0, s)
    wood = (0.96, 0.9, 0.84)
    for side in (-1, 1):
        box(m, at(o, t, n, 0.0, side * (w - 0.03), 0.31), T(0.98), N(0.03), Z(0.05), "teak", wood, bottom=True)
        for a in (-0.88, 0.62):
            box(m, at(o, t, n, a, side * (w - 0.04), 0.14), T(0.035), N(0.035), Z(0.18), "teak", wood)
    box(m, at(o, t, n, 0.25, 0.0, 0.37), T(0.72), N(w), Z(0.02), "teak", wood, bottom=True)
    box(m, at(o, t, n, 0.25, 0.0, 0.43), T(0.69), N(w - 0.03), Z(0.04), "canvas", cushion)
    ang = math.radians(38.0)
    dirv = tuple(-t[k] * math.cos(ang) + UP[k] * math.sin(ang) for k in range(3))
    hinge = at(o, t, n, -0.47, 0.0, 0.37)
    nrm = tuple(t[k] * math.sin(ang) + UP[k] * math.cos(ang) for k in range(3))
    c = tuple(hinge[k] + dirv[k] * 0.38 for k in range(3))
    box(m, c, tuple(dirv[k] * 0.38 for k in range(3)), N(w), tuple(nrm[k] * 0.02 for k in range(3)), "teak", wood, bottom=True)
    c = tuple(hinge[k] + dirv[k] * 0.37 + nrm[k] * 0.06 for k in range(3))
    box(m, c, tuple(dirv[k] * 0.35 for k in range(3)), N(w - 0.03), tuple(nrm[k] * 0.04 for k in range(3)), "canvas", cushion)
    strut = tuple(hinge[k] + dirv[k] * 0.5 + (-UP[k]) * 0.16 for k in range(3))
    box(m, strut, T(0.03), N(w - 0.06), Z(0.15), "teak", wood)
    return (o, t, n, (0.98, w + 0.02, 0.55))


def cooler(m, b, r, yaw, body):
    """A picnic cooler: a coloured tub, a white lid, a carry handle."""
    o, t, n = frame(b, r, yaw)
    T = lambda s: tuple(t[k] * s for k in range(3))
    N = lambda s: tuple(n[k] * s for k in range(3))
    Z = lambda s: (0.0, 0.0, s)
    white = (0.95, 0.95, 0.93)
    box(m, at(o, t, n, 0.0, 0.0, 0.16), T(0.28), N(0.19), Z(0.19), "plastic", body)
    box(m, at(o, t, n, 0.0, 0.0, 0.385), T(0.3), N(0.21), Z(0.035), "plastic", white)
    for a in (-0.17, 0.17):
        box(m, at(o, t, n, a, 0.0, 0.45), T(0.02), N(0.03), Z(0.035), "plastic", white)
    box(m, at(o, t, n, 0.0, 0.0, 0.49), T(0.19), N(0.03), Z(0.015), "plastic", white)
    return (o, t, n, (0.3, 0.21, 0.42))


def driftwood(m, uv, b, r, length, rad, yaw, seed):
    """A bleached log a third sunk in the sand, bent, tapering, a broken branch stub."""
    rr = Rng(seed)
    o, t, n = frame(b, r, yaw)
    pts, radii = [], []
    bend = rr.u(-0.25, 0.25)
    for k in range(5):
        s = k / 4.0
        a = -length / 2 + length * s
        p = at(o, t, n, a, bend * math.sin(math.pi * s) * length * 0.3, 0.0)
        g = ground_z(bearing_of(p), math.hypot(p[0], p[1]))
        rk = rad * lerp(1.0, 0.62, s) * rr.u(0.92, 1.08)
        pts.append((p[0], p[1], g + rk * 0.15))
        radii.append(rk)
    tone = rr.u(0.9, 1.04)
    col = (tone, tone * 0.98, tone * 0.95)
    tube(m, uv, pts, radii, 6, "drift", col)
    root = pts[1]
    sd = rr.u(0.4, 0.8) * (1 if rr.f() < 0.5 else -1)
    tip = at(root, t, n, 0.35, sd, rad * 1.6)
    tube(m, uv, [root, tip], [radii[1] * 0.45, radii[1] * 0.3], 5, "drift", col, caps=(False, True))
    return (pts[0], pts[-1], max(radii))


def shell(m, b, r, seed):
    """A scallop shell lying on the sand: a ribbed fan, a few centimetres."""
    rr = Rng(seed)
    o, t, n = frame(b, r, rr.u(0.0, 360.0))
    size = rr.u(0.07, 0.12)
    col = [(0.98, 0.9, 0.84), (0.98, 0.78, 0.74), (0.96, 0.84, 0.66), (0.95, 0.93, 0.9)][rr.i(0, 3)]
    hinge = m.v(at(o, t, n, -size * 0.45, 0.0, -0.01), col)
    rim = []
    for k in range(7):
        a = math.radians(-70.0 + 140.0 * k / 6.0)
        rim.append(m.v(at(o, t, n, -size * 0.45 + math.cos(a) * size, math.sin(a) * size, -0.01 + (0.008 if k % 2 else 0.0)), col))
    crown = m.v(at(o, t, n, size * 0.05, 0.0, size * 0.32), col)
    for k in range(6):
        m.tri(rim[k], rim[k + 1], crown, UP, "shell", "props")
    m.tri(hinge, rim[0], crown, UP, "shell", "props")
    m.tri(rim[-1], hinge, crown, UP, "shell", "props")


def tiki_hut(m, uv, b, r):
    """The tiki bar by the portal: four log posts, a thatched hip roof with a ragged fringe, a plank counter
    facing the bay. Footprint 2.8 x 2.2 m against the wall; roof from 2.35 m to 4.3 m."""
    o, t, n = frame(b, r)
    half_a, half_d = 1.4, 1.1
    post_col = (0.86, 0.66, 0.46)
    posts = []
    for a in (-half_a, half_a):
        for d in (-half_d, half_d):
            base = at(o, t, n, a, d, 0.0)
            g = ground_z(bearing_of(base), math.hypot(base[0], base[1]))
            tube(m, uv, [(base[0], base[1], g - 0.3), (base[0], base[1], o[2] + 2.5)], [0.11, 0.1], 6, "drift", post_col)
            posts.append((base[0], base[1], 0.14))
    eave, apex_h, over = 2.36, 4.3, 0.55
    ea, ed = half_a + over, half_d + over
    corners = [at(o, t, n, -ea, -ed, eave), at(o, t, n, ea, -ed, eave), at(o, t, n, ea, ed, eave), at(o, t, n, -ea, ed, eave)]
    ridge = [at(o, t, n, -(ea - ed) - 0.05, 0.0, apex_h), at(o, t, n, (ea - ed) + 0.05, 0.0, apex_h)]
    thatch = (1.0, 0.97, 0.9)

    def face(e0, e1, r0, r1):
        """One roof plane from its eave (e0, e1) to its ridge (r0, r1; one point on a hip) in three
        overlapping courses of thatch, each course's foot standing proud of the one below."""
        ed_ = il.unit(il.sub(e1, e0))
        mid = lerp3(lerp3(e0, e1, 0.5), lerp3(r0, r1, 0.5), 0.5)
        nrm = il.unit(il.cross(il.sub(e1, e0), il.sub(lerp3(r0, r1, 0.5), lerp3(e0, e1, 0.5))))
        if il.dot(nrm, il.sub(mid, (o[0], o[1], o[2] + eave - 1.0))) < 0.0:
            nrm = il.scale(nrm, -1.0)
        ts = (0.0, 0.36, 0.68, 1.0)
        for i in range(3):
            lift = 0.0 if i == 0 else 0.08
            lo = [il.add(lerp3(e, rr_, ts[i]), il.scale(nrm, lift)) for e, rr_ in ((e0, r0), (e1, r1))]
            hi = [lerp3(e, rr_, ts[i + 1] + (0.04 if i < 2 else 0.0)) for e, rr_ in ((e0, r0), (e1, r1))]
            vs = [m.v(p, thatch) for p in (lo[0], lo[1], hi[1], hi[0])]
            f0 = len(m.faces)
            if math.dist(hi[0], hi[1]) < 1e-6:
                m.tri(vs[0], vs[1], vs[2], nrm, "thatch", "props")
            else:
                m.quad(vs[0], vs[1], vs[2], vs[3], nrm, "thatch", "props")
            for fi in range(f0, len(m.faces)):
                for vi in m.faces[fi]:
                    q = m.verts[vi]
                    u = il.dot(il.sub(q, e0), ed_)
                    foot = tuple(e0[k] + ed_[k] * u for k in range(3))
                    uv[(fi, vi)] = (u / 12.8, math.dist(q, foot) / 12.8)

    face(corners[0], corners[1], ridge[0], ridge[1])
    face(corners[2], corners[3], ridge[1], ridge[0])
    face(corners[1], corners[2], ridge[1], ridge[1])
    face(corners[3], corners[0], ridge[0], ridge[0])
    # the ragged fringe hanging from the eave: a strip of straw tongues
    rr = Rng(SEED + 990)
    for k in range(4):
        e0, e1 = corners[k], corners[(k + 1) % 4]
        el = math.dist(e0, e1)
        steps = int(el / 0.32)
        for j in range(steps):
            p0 = lerp3(e0, e1, j / float(steps))
            p1 = lerp3(e0, e1, (j + 1) / float(steps))
            tipp = lerp3(p0, p1, 0.5)
            drop_ = rr.u(0.22, 0.36)
            out = il.unit(il.sub((tipp[0], tipp[1], 0.0), (o[0], o[1], 0.0)))
            tipp = (tipp[0] + out[0] * 0.04, tipp[1] + out[1] * 0.04, tipp[2] - drop_)
            vs = [m.v(p0, thatch), m.v(p1, thatch), m.v(tipp, thatch)]
            m.tri(vs[0], vs[1], vs[2], out, "thatch", "props")
            fi = len(m.faces) - 1
            for vi in m.faces[fi]:
                p = m.verts[vi]
                uv[(fi, vi)] = (math.dist(p, e0) / 12.8, (eave - (p[2] - o[2])) / 12.8 + 0.3)
    # the counter along the bay side, between the front posts
    T = lambda s: tuple(t[k] * s for k in range(3))
    N = lambda s: tuple(n[k] * s for k in range(3))
    Z = lambda s: (0.0, 0.0, s)
    wood = (0.94, 0.86, 0.76)
    box(m, at(o, t, n, 0.0, -half_d + 0.12, 0.5), T(half_a - 0.12), N(0.1), Z(0.56), "teak", wood)
    box(m, at(o, t, n, 0.0, -half_d + 0.06, 1.1), T(half_a + 0.02), N(0.24), Z(0.04), "teak", (1.0, 0.92, 0.82), bottom=True)
    return o, t, n, posts, (half_a, half_d)


SETS = (     # (bearing, kind, canopy colour, towel/lounger offset, cooler)
    (76.0, "loungers", (0.86, 0.2, 0.18), True),
    (104.0, "towels", (0.18, 0.42, 0.8), False),
    (138.0, "mixed", (0.98, 0.8, 0.22), True),
    (178.0, "loungers", (0.24, 0.66, 0.38), False),
    (214.0, "towels", (0.95, 0.45, 0.6), True),
    (234.0, "mixed", (0.98, 0.55, 0.16), False),
    (285.0, "towels", (0.86, 0.2, 0.18), False),
)
CANVAS_WHITE = (0.96, 0.95, 0.92)
TOWELS = (((0.95, 0.45, 0.6), (0.96, 0.95, 0.92)), ((0.18, 0.62, 0.78), (0.98, 0.84, 0.3)),
          ((0.96, 0.95, 0.92), (0.86, 0.2, 0.18)), ((0.98, 0.55, 0.16), (0.98, 0.84, 0.3)))
HUT_B = 294.5               # the tiki bar, 7 m short of the portal on the wall side
DRIFT = ((66.0, 1.4, 3.2), (99.0, 1.5, 2.4), (126.0, 1.3, 3.6), (150.0, 1.5, 2.2), (190.0, 1.4, 3.0),
         (222.0, 1.5, 2.6), (247.0, 1.3, 3.4), (267.0, 1.5, 2.0))     # (bearing, metres in from the wall foot, length)
DRIFT_SHORE = ((57.0, 2.0, 2.6), (303.5, 2.1, 2.2))                    # (bearing, metres above the waterline, length)
SHELLS = 70


def build_props():
    """Every prop; returns (mesh, uv, solids) where solids are (centre, along, out, half extents) boxes."""
    m = Mesh()
    uv = {}
    rr = Rng(SEED + 800)
    solids, poles = [], []
    edge = lambda b: wf(b) - 1.75          # the props' outer edge: clear of the wall's foot stones
    for k, (b, kind, canopy, has_cooler) in enumerate(SETS):
        rad = math.radians(1.0) * 72.0
        stripes = [canopy if j % 2 == 0 else CANVAS_WHITE for j in range(2)]
        uo, ut, un = frame(b, edge(b) - 1.1)
        poles.append(umbrella(m, uo, ut, un, stripes, rr.u(4.0, 9.0), SEED + 810 + k))
        lie = lambda: -90.0 + rr.u(-8.0, 8.0)          # radial, the head end toward the wall
        if kind == "loungers":
            for side in (-1.0, 1.0):
                solids.append(lounger(m, b + side * 0.9 / rad, edge(b) - 1.0, lie(), canopy))
        elif kind == "towels":
            for j, side in enumerate((-1.0, 1.0)):
                tw = TOWELS[(k + j) % len(TOWELS)]
                towel(m, b + side * 0.78 / rad, edge(b) - 0.9, 1.75, 0.85, lie(), [tw[s % 2] for s in range(5)])
        else:
            solids.append(lounger(m, b - 0.95 / rad, edge(b) - 1.0, lie(), canopy))
            tw = TOWELS[k % len(TOWELS)]
            towel(m, b + 0.82 / rad, edge(b) - 0.9, 1.75, 0.85, lie(), [tw[s % 2] for s in range(5)])
        if has_cooler:
            cb = b + (2.25 if k % 2 else -2.25) / rad
            solids.append(cooler(m, cb, edge(cb) - 0.25, rr.u(-25.0, 25.0), (0.2, 0.48, 0.82) if k % 3 else (0.86, 0.22, 0.2)))
    logs = []
    for k, (b, inset, length) in enumerate(DRIFT):
        logs.append(driftwood(m, uv, b, wf(b) - inset, length, rr.u(0.18, 0.25), rr.u(-12.0, 12.0), SEED + 830 + k))
    for k, (b, up, length) in enumerate(DRIFT_SHORE):
        logs.append(driftwood(m, uv, b, wl(b) + up, length, rr.u(0.14, 0.19), rr.u(-20.0, 20.0), SEED + 850 + k))
    for k in range(SHELLS):
        b = rr.u(ENTRY_B - 4.0, EXIT_B + 4.0)
        shell(m, b, lerp(wl(b) + 0.4, edge(b), rr.f()), SEED + 900 + k)
    hut = tiki_hut(m, uv, HUT_B, edge(HUT_B) - 1.1)
    INFO["props"] = len(m.faces)
    return m, uv, solids, poles, logs, hut


def build_prop_collider(solids, poles, logs, hut):
    """Loungers, coolers and the counter as boxes, umbrella poles, hut posts and logs as prisms."""
    c = Mesh()
    for o, t, n, (ha, hd, h) in solids:
        box(c, (o[0], o[1], o[2] + h / 2 - 0.05), tuple(t[k] * ha for k in range(3)), tuple(n[k] * hd for k in range(3)),
            (0.0, 0.0, h / 2 + 0.05), "c", (1.0, 1.0, 1.0), bottom=True)
    o, t, n, posts, (ha, hd) = hut
    for x, y, rad in poles + posts:
        g = ground_z(bearing_of((x, y, 0.0)), math.hypot(x, y))
        box(c, (x, y, g + 1.1), (rad, 0.0, 0.0), (0.0, rad, 0.0), (0.0, 0.0, 1.4), "c", (1.0, 1.0, 1.0), bottom=True)
    box(c, (lambda p: (p[0], p[1], p[2]))(at(o, t, n, 0.0, -hd + 0.06, 0.55)), tuple(t[k] * ha for k in range(3)),
        tuple(n[k] * 0.24 for k in range(3)), (0.0, 0.0, 0.62), "c", (1.0, 1.0, 1.0), bottom=True)
    for p0, p1, rad in logs:
        mid = lerp3(p0, p1, 0.5)
        along = il.scale(il.sub(p1, p0), 0.5)
        side = il.scale(il.unit(il.cross(along, UP)), rad)
        box(c, (mid[0], mid[1], mid[2]), along, side, (0.0, 0.0, rad), "c", (1.0, 1.0, 1.0), bottom=True)
    return c


# =============================================================================
# WAVES -- the GameCube way: short foam strips laid on the shore, each its own wave (beach_waves.gdshader)
# =============================================================================

WAVE_OFFS = (-3.0, -2.0, -1.2, -0.55, -0.2, 0.0, 0.45, 1.0, 1.7, 2.6, 3.6)   # metres up the sand from the waterline


def build_waves():
    """One continuous strip along the whole waterline, from 3 m out in the water to 3.6 m up the sand, 4 cm
    over whatever is under it; beach_waves.gdshader runs the waves along it. COLOR is data: g = (metres up
    the sand + 3) / 6.6, b = 0..1 along the strip; UV.x is metres along the shore / 12.8."""
    m = Mesh()
    uv = {}
    lo, hi = ENTRY_B - 2.0, EXIT_B + 2.0
    n = int(hi - lo) * 2
    rows = []
    for off in WAVE_OFFS:
        row = []
        for i in range(n + 1):
            b = lo + (hi - lo) * i / n
            r = wl(b) + off
            z = max(sand_z(b, r) if off != 0.0 else WATER_Z, WATER_Z) + 0.04
            knoll = 1.0 - ramp(head(b, r), 0.05, 0.3)            # r: 0 where the head's rock rises
            row.append(m.v(pol(b, r, z), (knoll, (off + 3.0) / 6.6, i / float(n), 1.0)))
        rows.append(row)
    m.grid(rows, UP, "wave", "waves", closed=False)
    for fi in range(len(m.faces)):
        for vi in m.faces[fi]:
            along = ((bearing_of(m.verts[vi]) - lo) % 360.0) * math.radians(1.0) * WL_R
            uv[(fi, vi)] = (along / 12.8, m.cols[vi][1])
    INFO["waves"] = len(m.faces)
    return m, uv


# =============================================================================
# COLLIDERS -- purpose-built
# =============================================================================

def build_ground_collider():
    """Shelf, shallows and sand at the sculpt's own heights (coarser), the wall as a sheer face 3.4 m
    tall in front of its boulders, and the jetty heads' knolls."""
    g = Mesh()
    step = 2
    offs = [-20.0, -17.0, -14.5, -12.0, -9.5, -7.0, -4.5, -2.0, 0.0, 1.3, 2.6]
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
    props, puv, solids, poles, logs, hut = build_props()
    waves, wuv = build_waves()
    sea = build_sea([p for p in placed if ground_z(bearing_of((p[0], p[1], 0.0)), math.hypot(p[0], p[1])) < WATER_Z + 0.3])
    cols = {"ground": build_ground_collider(), "rocks": build_rock_collider(placed),
            "palms": build_trunk_collider(trunks), "props": build_prop_collider(solids, poles, logs, hut)}
    return s, m, rocks, palms, uv, sea, cols, props, puv, waves, wuv


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
    "canvas": tx.Sheet("canvas", mode="box", roughness=0.9, cull=False),
    "plastic": tx.Sheet("plastic", mode="box", roughness=0.5),
    "teak": tx.Sheet("teak", mode="box", roughness=0.8),
    "drift": tx.Sheet("drift", mode="custom", roughness=0.95),
    "thatch": tx.Sheet("thatch", mode="custom", roughness=0.95, cull=False),
    "shell": tx.Sheet("shell", mode="box", roughness=0.6),
    "reef": tx.Sheet("reef", mode="box", roughness=0.9),
    "wave": tx.Sheet("wave", mode="custom", roughness=0.4, cull=False),
}
SMOOTH = ("sand", "grass", "jungle", "water")     # Gouraud like the refs' ground; rock and palms stay faceted
CHUNKS = ["ground", "island", "rocks", "palms", "props", "water", "waves"]
VIS = {"ground": "BeachGround", "island": "BeachIsland", "rocks": "BeachRocks", "palms": "BeachPalms",
       "props": "BeachProps", "water": "BeachWater",
       "waves": "BeachWaves"}
COLLIDED = ("ground", "rocks", "palms", "props")


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


def _object(name, verts, cols, faces, zones, mats, face_uv=None, uv2=None):
    ob = mdl.mesh(name, verts, faces)
    tx.unwrap(ob, zones, SHEETS, seed=1, face_uv=face_uv)
    if uv2 is not None:                  # UV2 carries baked data (water alpha and foam, the bed's caustic weight)
        me = ob.data
        layer = me.uv_layers.new(name="UV2")
        for li, loop in enumerate(me.loops):
            layer.data[li].uv = uv2[loop.vertex_index]
        me.uv_layers.active_index = 0
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
    uv2 = None
    if getattr(m, "uv2", None):
        inv = {j: i for i, j in remap.items()}
        uv2 = [m.uv2.get(inv[k], (0.0, 0.0)) for k in range(len(verts))]
    return _object(name, verts, cols, faces, zones, mats, face_uv, uv2)


def build():
    s, m, rocks, palms, uv, sea, cols, props, puv, waves, wuv = build_geometry()
    mats = tx.materials(NAME, SHEETS)
    for mat in mats.values():
        _tint(mat)
    out = []
    parts = {"ground": _part(m, "ground", VIS["ground"], mats), "island": _part(m, "island", VIS["island"], mats),
             "rocks": _part(rocks, "rocks", VIS["rocks"], mats), "palms": _part(palms, "palms", VIS["palms"], mats, uv),
             "props": _part(props, "props", VIS["props"], mats, puv), "waves": _part(waves, "waves", VIS["waves"], mats, wuv), "water": _part(sea, "water", VIS["water"], mats)}
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
    s, m, rocks, palms, uv, sea, cols, props, puv, waves, wuv = build_geometry()
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
    il.report(props, "props")
    il.report(waves, "waves")
    il.report(sea, "water")
    for k, c in cols.items():
        il.report(c, k + "_collider")
    print("palms=%d lane r=%.1f lap=%.0f m" % (INFO["palms"], LANE_R, math.radians(EXIT_B - ENTRY_B) * LANE_R))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, export=_export_chunks)
