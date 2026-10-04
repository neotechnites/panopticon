"""
PANOPTICON -- ice: Map 4. A glacier chamber under an ice-cave roof: a shelf of lake ice round a
crevassed pit, a wall of seracs and buttresses, a scalloped see-through roof, and a serac ridge
across the lane at 353 deg. ONE sculpt (one mesh, shared vertices), exported per chunk:

    ice_ground.glb   pit floor, pit wall, the crevassed rim, the lane       IceGround
    ice_wall.glb     the serac wall, lane edge to the roof's spring ring    IceWall
    ice_gate.glb     the ridge across the lane (the lane's own surface)     IceGate
    ice_roof.glb     the scalloped roof and the bright shell seen through   IceRoof, IceRoofOuter

World coordinates, instanced at identity (Blender +Z -> Godot +Y, +Y -> Godot -Z; bearings as
map 1's pol()). Map 1's ring: lane y 23.0, never narrower than r 46.7..57.3; pit floor y -11.05.

    tools/modelling/model build ice [--chunk wall]
    python3 tools/modelling/maps/ice/ice_build.py --check
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
import ice_lib as il  # noqa: E402
from ice_lib import (Mesh, Rng, UP, DOWN, pol, bearing_of, rad_of, lerp, lerp3, clamp, smooth, ramp,  # noqa: E402
                     angdiff, interp, h2, vnoise, fbm, ring_noise, worley)
if bpy is not None:
    import mdl  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "ice"
SEED = 40931
FACING_YAW = 0.0
NC = 360                    # columns round the ring: 1 deg, 0.8 m at the lip, 1.0 m at the wall
DECK_Z = 23.0
INNER_R = 46.7              # map 1's lane: the lip never comes outside this ...
OUTER_R = 57.3              # ... and the wall foot never inside this
FLOOR_Z = -11.05

# -- the rim and the pit wall: straight-fronted slabs set en echelon, a crevasse notch between most
SLAB_W = (4, 16)            # degrees of rim a slab holds (whole degrees: a boundary is a column)
FIRN = (0.4, 7.5)           # metres of pale firn at a slab's head before the blue ice
DEEP_Y = (8.0, 5.0)         # the blue gives way to dark ice at this height, wandering this much by slab
SLAB_PUSH = (0.5, 2.4)      # metres its foremost corner stands out past INNER_R
SLAB_SKEW = 15.0            # degrees its front is turned off the ring's tangent, either way
SLAB_NOTCH = 0.7            # share of boundaries that are a crevasse notch (the rest a crease)
NOTCH_RUN = (9.0, 22.0)     # metres a notch's cleft runs down the pit wall
NOTCH_DEPTH = 2.4           # how far the cleft cuts back into the wall
VEIN_LEN = (2.5, 7.0)       # metres a notch's blue vein runs on into the lane
LANE_R = [47.6, 49.2, 50.8, 52.4, 54.0, 55.6, 57.0]   # lane rows between the lip and the wall foot
LANE_JIT = (0.35, 0.3)      # row wander: metres of radius, degrees of bearing

# -- the pit wall, lip to floor: (y, base radius)
PIT_Y = [22.86, 22.35, 21.3, 19.6, 17.6, 15.2, 12.6, 10.0, 7.4, 4.8, 2.2, -0.4, -3.0, -5.6, -7.6]
PIT_R = [(-11.05, 41.4), (-7.6, 42.3), (2.5, 44.3), (12.6, 45.9), (19.6, 46.85), (21.3, 46.75),
         (22.35, 46.48), (22.86, 46.52), (23.0, 46.7)]
PIT_KEEP = [(-8.0, 0.35), (12.6, 0.5), (19.6, 0.85), (22.35, 1.0), (23.0, 1.0)]   # share of a slab's set kept with depth
PIT_BAND = (6.5, 0.5)       # a slab's fracture tiers: height, offset
FACET = (2.6, 3.4, 0.5)     # fracture facets on every face: width, height, relief
CORNICE = 0.3               # share of slabs that carry a snow cornice on the lip
BENCH_Y = (12.5, 2.0)       # a calved shelf's height and its wander
BENCH_OUT = 1.7             # how far the wall under a shelf stands out
FLOOR_R = [38.8, 35.5, 31.0, 25.5, 19.5, 13.0, 6.5]
FLOOR_NC = 120
FLOOR_APRON = (1.0, 1.6)    # rubble apron at the wall's foot: least, extra
FLOOR_PLATE = 7.0           # pressure plates on the frozen pool

# -- the serac wall: flat-faced blocks en echelon; rows over the lane, the foot cove, the lean
# into the roof's spring ring
WALL_DZ = [0.0, 0.4, 1.1, 2.3, 3.9, 5.8, 8.4, 10.4, 12.0, 13.2, 14.2]
WALL_COVE = [0.0, 0.5, 0.9, 1.1, 1.15, 1.15, 1.15, 1.15, 1.15, 1.15, 1.15]
WALL_DRIFT = [0.0, 0.9, 1.75, 2.05, 1.9, 1.5, 1.2, 1.15, 1.15, 1.15, 1.15]   # the cove under a snow bank
WALL_SPRING = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.3, 0.6, 0.85, 1.0]
WALL_CLEAR_ROWS = 3         # rows a body can touch: these only ever stand back from the foot line
FOOT_MIN = 57.6             # the wall foot where a serac stands furthest forward
PROW_GAP = (28, 48)         # degrees between two prows: the piers the roof's keels spring from
PROW_W = (5, 8)
MASSIF_BACK = (0.3, 2.6)    # how far the wall between two prows stands back
# a massif's style: serac width (deg), skew (deg), cleft share, ledge share, step between neighbours
STYLES = {"towers": ((6, 12), 15.0, 0.85, 0.3, 1.4), "shattered": ((2, 4), 20.0, 0.6, 0.6, 1.1),
          "sheer": ((9, 16), 8.0, 0.3, 0.2, 0.6)}
CLEFT_BACK = (1.3, 2.6)     # how far a cleft column stands behind its seracs
SERAC_LEAN = (-0.05, 0.09)  # radius per metre of height: negative leans out over the lane
LEDGE_ROWS = (4, 5, 6)      # a serac's snow ledge: one of these rows and the next sit on one line
LEDGE_BACK = (0.8, 1.9)
OVERHANG = (0.5, 1.0)       # a serac whose head stands forward of its foot
PROW_LEAN = [0.0, 0.0, 0.0, 0.0, 0.2, 0.5, 0.8, 1.1, 1.2, 0.9, 0.0]
SPRING_R = (55.6, 0.8, 1.2)  # the spring ring: radius, wander, pull-in at a prow
SPRING_Z = (34.6, 5.2)      # its height at a prow, and the rise of the vault between two prows

# -- the ridge across the lane (the gate): the lane's own surface rising between two columns
GATE_B = 353.0
GATE_COLS = (351, 355)
GATE_ROWS = 6               # wall rows 0..6: crest 8.4 m over the lane
GATE_HALF = [2.0, 1.5, 1.2, 1.05, 0.95, 0.8, 0.55]   # half width in degrees per row
GATE_PROW = 0.6             # the pit end leans this far out over the lip
GATE_CREST = (0.8, 1.22)    # the ridge's crest wanders between these shares of its height
GATE_FACET = 0.28           # degrees a face block stands in or out

# -- icicles: spikes grown out of the faces they hang from
ICICLE_WALL = (0.3, 1.0, 3.2)     # share of the wall's overhanging faces that carry one; length least, most
ICICLE_LIP = (0.4, 0.7, 2.6)      # ... of the faces under the pit's cornice
ICICLE_ROOF = (0.22, 1.6, 4.5)    # ... of the roof's faces on a keel
ICICLE_COL = (0.92, 0.98, 1.0, 1.0)

# -- the roof: scallops on the Delaunay dual, keels from the buttresses, an oculus over the tower
APEX_Z = 61.0
ROOF_STEP = 0.068           # scallop pitch as a share of the spring radius (3.8 m)
ROOF_FIRST = 0.955
ROOF_DISH = (1.0, 0.9)    # a dish's rise: least, extra
ROOF_LOBE = 2.2
KEEL_DEPTH = (2.0, 3.8)
KEEL_W = 2.8
KEEL_MIN_GAP = 24.0         # degrees between two keels
OCULUS = (0.28, 2.2)        # share of the radius, lift
ROOF_DEEP = (0.05, 0.16, 0.34, 1.0)    # thick ice: dark, opaque
ROOF_THIN = (0.9, 1.0, 1.0, 0.44)      # thin ice: bright, see-through
RIM_COL = (0.07, 0.2, 0.4, 1.0)        # the spring ring's own colour, on the wall's head and the roof's rim
ROOF_CREST = 0.45           # a scallop's crest carries this share of its dish's light
SHELL_UP = 4.2              # the bright shell stands this far over the roof ...
SHELL_OUT = 13.0            # ... and this far outside its rim, behind the deepest bay
SHELL_NC = 72
SHELL_RINGS = (1.0, 0.93, 0.84, 0.74, 0.63, 0.52, 0.41, 0.3, 0.19, 0.09)
SHELL_DARK = (0.08, 0.22, 0.5, 1.0)    # under a drift of snow
SHELL_LIGHT = (0.82, 0.95, 1.0, 1.0)   # bare ice with the sky behind it
SUN_B = 150.0               # the side the daylight comes from ...
SUN_EL = 62.0               # ... and its height: the scene's Sun, the light pools on the lane
POOL = (0.74, 1.0)          # the lane's light under thick roof and under thin
SUN_AT = 0.5                # where the sun's glare stands on the shell, as a share of the radius
SUN_SPREAD = 13.0           # metres its glare spreads

TWO_PI = 2.0 * math.pi
INFO = {}


# =============================================================================
# FIELDS -- every line of the sculpt is a function of bearing
# =============================================================================

def _chord(seg, b):
    """Radius of a flat face at bearing b: seg["near"] where it stands nearest the pit."""
    bm = clamp(seg["psi"], seg["b0"], seg["b1"])
    return seg["near"] * math.cos(math.radians(bm - seg["psi"])) / math.cos(math.radians(b - seg["psi"]))


def _ring_segments(seed, widths, fixed):
    """Whole-degree segments round the ring, the fixed one (b0, b1) first: [(b0, b1)], b1 may pass 360."""
    r = Rng(seed)
    out = [fixed]
    b = fixed[1]
    end = fixed[0] + 360
    while end - b > widths[1]:
        w = r.i(widths[0], widths[1])
        if end - (b + w) < widths[0]:
            w = end - b - widths[0]
        out.append((b, b + w))
        b += w
    out.append((b, end))
    return out, r


def _slabs():
    """The rim's slabs: each a straight front, pushed and skewed; "notch" opens a crevasse at b0."""
    spans, r = _ring_segments(SEED + 1, SLAB_W, (347, 359))
    out = []
    for k, (b0, b1) in enumerate(spans):
        gate = k == 0
        skew = 0.0 if gate else r.u(-SLAB_SKEW, SLAB_SKEW)
        push = 0.7 if gate else r.u(*SLAB_PUSH)
        seg = {"b0": b0, "b1": b1, "psi": 0.5 * (b0 + b1) + skew, "near": INNER_R - push, "h": r.f(),
               "notch": r.f() < SLAB_NOTCH, "run": r.u(*NOTCH_RUN), "vein": r.u(*VEIN_LEN),
               "firn": r.u(*FIRN), "deep": DEEP_Y[0] + r.u(-DEEP_Y[1], DEEP_Y[1]),
               "cornice": (not gate) and r.f() < CORNICE}
        far = max(_chord(seg, b0 + 0.5), _chord(seg, b1 - 0.5))
        if far > INNER_R - 0.12:                      # its far corner may not stand back past map 1's lip
            seg["near"] -= far - (INNER_R - 0.12)
        out.append(seg)
    return out


def _seracs():
    """The wall: prows (the piers) with a massif of seracs between each pair. Each serac is a flat
    face set back, skewed and leaned; "cleft" opens one at b0. Returns (seracs, prows, vaults)."""
    r = Rng(SEED + 3)
    centres = [353]
    while 353 + 360 - centres[-1] > PROW_GAP[1] + PROW_GAP[0]:
        centres.append(centres[-1] + r.i(*PROW_GAP))
    if 353 + 360 - centres[-1] > PROW_GAP[1]:
        centres.append((centres[-1] + 353 + 360) // 2)
    spans = [(348, 358)] + [(c - w // 2, c - w // 2 + w) for c in centres[1:] for w in (r.i(*PROW_W),)]
    out, vaults = [], []

    def serac(b0, b1, kind, near, skew, cleft, ledge, drift_):
        seg = {"b0": b0, "b1": b1, "psi": 0.5 * (b0 + b1) + skew, "near": near, "kind": kind, "h": r.f(),
               "cleft": r.f() < cleft, "back": r.u(*CLEFT_BACK), "lean": r.u(*SERAC_LEAN),
               "cz": ((-9.0, 99.0), (-9.0, r.u(5.0, 10.0)), (r.u(3.0, 7.0), 99.0))[r.i(0, 2)],
               "ledge": None, "over": 0.0, "drift": drift_}
        roll = r.f()
        if roll < ledge and b1 - b0 >= 3:
            seg["ledge"] = (LEDGE_ROWS[r.i(0, 2)], r.u(*LEDGE_BACK))
        elif roll > 0.72:
            seg["over"] = r.u(*OVERHANG)
        return seg

    names = sorted(STYLES)
    for k, (p0, p1) in enumerate(spans):
        prow = serac(p0, p1, "prow", FOOT_MIN + r.u(0.0, 0.4), 0.0 if k == 0 else r.u(-6.0, 6.0), 1.0, 0.0, 0.0)
        prow["lean"], prow["over"] = 0.0, 0.0
        out.append(prow)
        nxt = spans[(k + 1) % len(spans)][0] + (360 if k + 1 == len(spans) else 0)
        style = names[r.i(0, 2)]
        (w0, w1), skew, cleft, ledge, step = STYLES[style]
        back = r.u(*MASSIF_BACK)
        vaults.append((p1, nxt, r.u(0.55, 1.0)))
        b = p1
        while b < nxt:
            w = min(r.i(w0, w1), nxt - b)
            if nxt - (b + w) < w0:
                w = nxt - b
            out.append(serac(b, b + w, style, FOOT_MIN + back + r.u(0.0, step), r.u(-skew, skew), cleft, ledge,
                             1.0 if back > 1.3 and r.f() < 0.75 else 0.0))
            b += w
    prows = [(0.5 * (p0 + p1) % 360.0, 0.5 * (p1 - p0)) for p0, p1 in spans]
    return out, prows, vaults


SLABS = _slabs()
SERACS, PROWS, VAULTS = _seracs()


def _seg_of(segs, i):
    """(segment, at_boundary, previous segment) for column i."""
    i = i % NC
    for k, seg in enumerate(segs):
        for ii in (i, i + NC):
            if seg["b0"] <= ii < seg["b1"]:
                return seg, ii == seg["b0"], segs[k - 1], ii
    raise ValueError(i)


def _seg_b(seg, b):
    """b unwrapped into the segment's own span."""
    return b + NC if b < seg["b0"] - 1.0 else b


def lip_r(i, b):
    """The lip's radius at column i (bearing b): its slab's chord, INNER_R in a notch."""
    seg, edge, prev, ii = _seg_of(SLABS, i)
    if edge:
        if seg["notch"]:
            return INNER_R, 1.0
        return 0.5 * (_chord(seg, ii) + _chord(prev, prev["b1"])), 0.0
    return min(_chord(seg, _seg_b(seg, b)), INNER_R - 0.1), 0.0


NOTCHES = [(float(s_["b0"] % NC), s_["run"], s_["vein"]) for s_ in SLABS if s_["notch"]]


def notch_at(b):
    """(across 0..1, run, vein, bearing) of the nearest crevasse notch."""
    best = (0.0, 0.0, 0.0, 0.0)
    for cb, run, vein in NOTCHES:
        a = 1.0 - abs(angdiff(b, cb)) / 1.4
        if a > best[0]:
            best = (a, run, vein, cb)
    return best


def buttress(b):
    """0..1: 1 on a keeled prow's centre line, 0 two degrees past its edge."""
    best = 0.0
    for cb, hw in PROWS:
        best = max(best, 1.0 - smooth((abs(angdiff(b, cb)) - 0.4 * hw) / (0.6 * hw + 2.0)))
    return best


def wall_r(i, b, z, k):
    """(radius, crack 0..1, serac) of the wall's face at column i, height z, row k, before the cove."""
    seg, edge, prev, ii = _seg_of(SERACS, i)

    def face(sg, bb):
        dz = z - DECK_Z
        r = _chord(sg, bb) + sg["lean"] * dz
        if k <= WALL_CLEAR_ROWS:
            r = max(r, _chord(sg, bb))
        if sg["ledge"] and k > sg["ledge"][0]:
            r += sg["ledge"][1]
        if sg["over"] and k >= 5:
            r -= sg["over"] * ramp(k, 4, 7)
        return r

    if edge:
        a, c = face(seg, ii), face(prev, prev["b1"])
        if seg["cleft"]:
            dz = z - DECK_Z
            open_ = ramp(dz, seg["cz"][0] - 1.5, seg["cz"][0]) * (1.0 - ramp(dz, seg["cz"][1], seg["cz"][1] + 1.5))
            deep = max(a, c) + seg["back"] * (0.55 if k == 0 else 1.0)
            return lerp(0.5 * (a + c), deep, open_), open_, seg
        return 0.5 * (a + c), 0.0, seg
    return face(seg, _seg_b(seg, b)), 0.0, seg


def foot(i):
    """The wall's foot line at column i: the lane's outer edge."""
    return wall_r(i, float(i), DECK_Z, 0)[0]


def vault(b):
    """0..1: the rise of the roof's spring line between two prows."""
    for b0, b1, amp in VAULTS:
        for bb in (b, b + 360.0):
            if b0 <= bb <= b1:
                return amp * max(0.0, math.sin(math.pi * (bb - b0) / (b1 - b0))) ** 0.7
    return 0.0


def spring(b):
    """(r, z) of the roof's spring ring: the seam the wall and the roof share."""
    r = SPRING_R[0] + SPRING_R[1] * ring_noise(b, SEED + 7) - SPRING_R[2] * buttress(b)
    return r, SPRING_Z[0] + SPRING_Z[1] * vault(b)


def _keels():
    r = Rng(SEED + 9)
    return [(cb, r.u(*KEEL_DEPTH)) for cb, _hw in PROWS]


KEELS = _keels()


def keel(x, y):
    """0..1 share of the deepest keel under (x, y), before depth."""
    rad = math.hypot(x, y)
    b = bearing_of((x, y))
    best, depth = 0.0, 0.0
    for cb, d in KEELS:
        arc = math.radians(abs(angdiff(b, cb))) * rad
        k = math.exp(-(arc / KEEL_W) ** 2)
        if k > best:
            best, depth = k, d
    rho = rad / spring(b)[0]
    prof = ramp(rho, 0.28, 0.62) * (1.0 - clamp(rho) ** 10)
    return best * prof, depth


def roof_base(x, y):
    """The roof's underside before its scallops: dome, lobes, keels, the oculus."""
    rad = math.hypot(x, y)
    b = bearing_of((x, y)) if rad > 1e-6 else 0.0
    rs, zs = spring(b)
    rho = clamp(rad / rs)
    z = zs + (APEX_Z - zs) * (1.0 - rho ** 2.4) ** 0.62
    z += ROOF_LOBE * fbm(x / 26.0 + 7.3, y / 26.0 + 3.1, SEED + 10) * (1.0 - rho ** 4)
    k, depth = keel(x, y)
    z -= k * depth
    z += OCULUS[1] * (1.0 - ramp(rho, 0.0, OCULUS[0]))
    return z


def sun_pool(x, y, z):
    """0..1: how thin the roof is where the sun's ray to (x, y, z) comes through it."""
    sx, sy, _z = pol(SUN_B, 1.0, 0.0)
    reach = (roof_base(x, y) - z) / math.tan(math.radians(SUN_EL))
    px, py = x + sx * reach, y + sy * reach
    rad = math.hypot(px, py)
    lim = 0.97 * spring(bearing_of((px, py)))[0]
    if rad > lim:
        px, py = px * lim / rad, py * lim / rad
    return roof_thin(px, py)


def roof_normal(x, y):
    """The base surface's normal at (x, y), pointing out of the chamber."""
    e = 0.4
    gx = (roof_base(x + e, y) - roof_base(x - e, y)) / (2.0 * e)
    gy = (roof_base(x, y + e) - roof_base(x, y - e)) / (2.0 * e)
    return il.unit((-gx, -gy, 1.0))


def roof_thin(x, y):
    """0..1: how thin the ice is over (x, y): the light and the see-through both ride on it."""
    rad = math.hypot(x, y)
    b = bearing_of((x, y)) if rad > 1e-6 else 0.0
    rho = clamp(rad / spring(b)[0])
    lobe = fbm(x / 19.0 - 2.0, y / 19.0 + 5.0, SEED + 11)
    sun = 0.5 + 0.5 * math.cos(math.radians(angdiff(b, SUN_B)))
    t = 0.55 + 0.65 * lobe + 0.22 * sun * rho
    t += 0.9 * (1.0 - ramp(rho, 0.0, OCULUS[0] + 0.12))
    t -= 1.1 * keel(x, y)[0]
    t *= 1.0 - 0.85 * ramp(rho, 0.84, 1.0)            # thick and dark where it meets the wall
    return clamp(t)


def _jb(i, key, amp=0.3):
    return (h2(i, key, SEED + 20) - 0.5) * 2.0 * amp


def facet(b, z, ref_r, seed):
    """-1..1: which way the fracture facet at (b, z) is tipped; one value across a facet."""
    px = int(round(TWO_PI * ref_r / FACET[0]))
    _d1, _d2, _cell, hh = worley(b / 360.0 * px, z / FACET[1], seed, px)
    return 2.0 * hh - 1.0


def _gate_col(i):
    return GATE_COLS[0] <= i % NC <= GATE_COLS[1]


# =============================================================================
# THE SCULPT
# =============================================================================

def _shade(col, f):
    return (col[0] * f, col[1] * f, col[2] * f, 1.0)


def _strata(z, b):
    """Summer and winter layers: a faint horizontal banding in the ice."""
    return 0.9 + 0.1 * math.sin(z * 1.9 + 2.5 * vnoise(b * 0.08, z * 0.15, SEED + 30, 0))


class Sculpt(object):
    """The whole map as one Mesh; every part shares its seam vertices with its neighbour."""

    def __init__(self):
        self.m = Mesh()
        self.cleft = {}          # vertex id -> 0..1 depth into a crack
        self._blue = {}          # vertex id -> its slab's or serac's hash
        self.lane = []           # rows lip .. wall foot, NC vertices each
        self.wall = []           # rows foot .. spring
        self.pit = []            # rows lip .. floor join

    # -- lane ---------------------------------------------------------------
    def build_lane(self):
        m = self.m
        lip = []
        for i in range(NC):
            r, notch = lip_r(i, float(i))
            col = self._lane_col(float(i), r)
            lip.append(m.v(pol(float(i), r, DECK_Z), lerp3(col, (0.5, 0.68, 0.88, 1.0), 0.6 * notch)))
        rows = [lip]
        for s, rad in enumerate(LANE_R):
            row = []
            for i in range(NC):
                gate = _gate_col(i)
                b = i + (0.0 if gate else _jb(i, s, LANE_JIT[1]))
                r = rad + (0.0 if gate else _jb(i, 40 + s, LANE_JIT[0]))
                z = DECK_Z + 0.035 * vnoise(b * 0.35, rad * 0.3, SEED + 21, 126)
                row.append(m.v(pol(b, r, z), self._lane_col(b, r)))
            rows.append(row)
        ft = []
        for i in range(NC):
            ft.append(m.v(pol(float(i), foot(i), DECK_Z), self._lane_col(float(i), foot(i))))
        rows.append(ft)
        self.lane = rows
        g0, g1 = GATE_COLS
        m.grid(rows, UP, self._lane_zone, "ground", skip=lambda r, i: g0 <= i < g1)

    def _vein(self, b, r):
        """0..1: on a blue vein running into the lane from a crevasse notch."""
        a, _run, vein, cb = notch_at(b)
        if a <= 0.0:
            return 0.0
        along = (r - INNER_R) / vein
        if along > 1.0:
            return 0.0
        mid = cb + 1.6 * math.sin(max(along, 0.0) * 2.2 + cb)
        d = abs(angdiff(b, mid)) * math.radians(1.0) * r
        return clamp(1.0 - d / 0.9) * (1.0 - smooth(along))

    def _lane_col(self, b, r):
        x, y, _z = pol(b, r, 0.0)
        mott = (0.86 + 0.14 * fbm(x / 6.0, y / 6.0, SEED + 22)) * lerp(POOL[0], POOL[1], sun_pool(x, y, DECK_Z))
        clear = ramp(fbm(x / 11.0, y / 11.0, SEED + 24), 0.1, 0.5)     # windows of clear dark ice
        v = max(self._vein(b, r), 0.8 * clear)
        return lerp3((mott, mott, mott, 1.0), (0.38, 0.6, 0.86, 1.0), v)

    def _lane_zone(self, n, c, ids):
        b, r = bearing_of(c), rad_of(c)
        seg = _seg_of(SERACS, int(round(b)))[0]
        if seg["drift"] and r > foot(int(round(b))) - 1.2 - 1.0 * fbm(c[0] / 3.0, c[1] / 3.0, SEED + 23):
            return "snow"
        return "lane"

    # -- pit wall and floor ---------------------------------------------------
    def _bench(self, b):
        m_ = ramp(ring_noise(b, SEED + 31, ((3, 1.0), (8, 0.7))), 0.12, 0.42)
        return m_, BENCH_Y[0] + BENCH_Y[1] * ring_noise(b, SEED + 32, ((2, 1.0), (5, 0.6)))

    def _pit_point(self, i, k):
        y0 = PIT_Y[k]
        soft = ramp(y0, 22.3, 19.0)                      # the cornice rows keep their line
        seg, edge, prev, ii = _seg_of(SLABS, i)
        b = i + (0.0 if edge else _jb(i, 60 + k, 0.28) * soft)
        y = y0 + _jb(i, 80 + k, 0.45) * soft
        bm, by = self._bench(b)
        kb = next((q for q, yy in enumerate(PIT_Y) if yy <= by + 1.3), len(PIT_Y))
        out = 0.0
        if bm > 0.0:
            if k == kb:
                y = lerp(y, by + 0.12, bm)
            elif k == kb + 1:
                y = lerp(y, by - 0.25, bm)
            if k > kb:
                out = BENCH_OUT * bm * (1.0 - 0.75 * ramp(y0, by - 3.0, by - 16.0))
        keep = interp(PIT_KEEP, y0)

        def face(sg, bb):
            band = int(math.floor((y + 40.0 + 3.0 * sg["h"]) / PIT_BAND[0]))
            off = PIT_BAND[1] * 2.0 * (h2(band, int(sg["b0"]), SEED + 33) - 0.5) * soft
            return (_chord(sg, bb) - INNER_R) * keep - off

        cre = 0.0
        if edge:
            a, c = face(seg, ii), face(prev, prev["b1"])
            if seg["notch"]:
                cre = ramp(y, DECK_Z - seg["run"], 20.5)
                set_ = max(a, c) * (1.0 - cre) + (NOTCH_DEPTH * (0.3 + 0.7 * soft)) * cre
            else:
                set_ = 0.5 * (a + c)
        else:
            set_ = face(seg, _seg_b(seg, b))
        r = interp(PIT_R, y0) + set_ - out + FACET[2] * facet(b, y, 45.0, SEED + 38) * soft * (0.0 if edge else 1.0)
        depth = ramp(y, 21.0, -9.0)
        tone = 0.9 + 0.2 * (seg["h"] - 0.5)
        f = 0.8 * _strata(y, b) * tone * lerp(1.0, 0.45, depth) * lerp(1.0, 0.55, cre)
        vid = self.m.v(pol(b, r, y), (f * 0.92, f * 0.97, f, 1.0))
        self.cleft[vid] = cre
        self._blue[vid] = (DECK_Z - seg["firn"], seg["deep"], seg["cornice"] and not edge)
        return vid

    def build_pit(self):
        m = self.m
        rows = [self.lane[0]]
        for k in range(len(PIT_Y)):
            rows.append([self._pit_point(i, k) for i in range(NC)])
        join = []
        for i in range(NC):
            b = i + _jb(i, 99, 0.25)
            a = FLOOR_APRON[0] + FLOOR_APRON[1] * (0.5 + 0.5 * fbm(b * 0.12, 0.5, SEED + 35, 43))
            r = PIT_R[0][1] + 0.5 * vnoise(b * 0.3, 4.0, SEED + 36, 108)
            join.append(m.v(pol(b, r, FLOOR_Z + a), (0.42, 0.46, 0.5, 1.0)))
        rows.append(join)
        self.pit = rows
        inward = lambda c: (-c[0], -c[1], 0.0)
        m.grid(rows, inward, self._pit_zone, "ground")
        rings = []
        for rad in FLOOR_R:
            ring = []
            for j in range(FLOOR_NC):
                b = (j + 0.5 * (len(rings) % 2)) * 360.0 / FLOOR_NC + _jb(j, 120 + len(rings), 0.8)
                r = rad + _jb(j, 140 + len(rings), 0.9)
                ring.append(m.v(self._floor_point(b, r), (0.4, 0.44, 0.5, 1.0)))
            rings.append(ring)
        m.stitch(join, rings[0], UP, self._floor_zone, "ground")
        for a, b_ in zip(rings, rings[1:]):
            m.stitch(a, b_, UP, self._floor_zone, "ground")
        c = m.v((0.0, 0.0, FLOOR_Z), (0.4, 0.44, 0.5, 1.0))
        last = rings[-1]
        for j in range(FLOOR_NC):
            m.tri(last[j], last[(j + 1) % FLOOR_NC], c, UP, "floor", "ground")

    def _floor_point(self, b, r):
        x, y, _z = pol(b, r, 0.0)
        w = ramp(r, 10.0, 22.0)
        d1, d2, _cell, hh = worley(x / FLOOR_PLATE, y / FLOOR_PLATE, SEED + 37)
        z = FLOOR_Z + w * (0.5 * (hh - 0.5) + 0.45 * (1.0 - smooth((d2 - d1) / 0.18)))
        a = FLOOR_APRON[0] + FLOOR_APRON[1] * (0.5 + 0.5 * fbm(b * 0.12, 0.5, SEED + 35, 43))
        return (x, y, z + a * ramp(r, 30.0, 41.4) ** 2)

    def _pit_zone(self, n, c, ids):
        if n[2] > 0.55:
            return "snow"
        firn, deep, corn = max((self._blue[v] for v in ids if v in self._blue), default=(21.0, 1.0, False))
        if corn and c[2] > 22.2:
            return "snow"
        if min(self.cleft.get(v, 0.0) for v in ids) > 0.3 or c[2] < deep:
            return "deep"
        return "glacier" if c[2] > firn else "blue"

    def _floor_zone(self, n, c, ids):
        return "floor" if n[2] > 0.8 else "deep"

    # -- wall ---------------------------------------------------------------
    def _wall_point(self, i, k):
        if k == 0:
            return self.lane[-1][i]
        seg, edge, _prev, _ii = _seg_of(SERACS, i)
        top = k >= len(WALL_DZ) - 1
        soft = 0.0 if (top or edge or (_gate_col(i) and k <= GATE_ROWS)) else 1.0
        b = i + _jb(i, 200 + k, 0.3) * soft
        rs, zs = spring(b)
        w = WALL_SPRING[k]
        z = DECK_Z + WALL_DZ[k]
        if k >= 2:
            z += _jb(i, 220 + k, 0.24) * (WALL_DZ[k] - WALL_DZ[k - 1]) * soft
        if seg["ledge"] and not edge:
            lr = seg["ledge"][0]
            if k == lr:
                z = DECK_Z + WALL_DZ[lr] + 0.55
            elif k == lr + 1:
                z = DECK_Z + WALL_DZ[lr] + 0.85
        z = lerp(z, zs - (WALL_DZ[-1] - WALL_DZ[k]), w)
        r, crack, _seg = wall_r(i, b, z, k)
        r += lerp(WALL_COVE[k], WALL_DRIFT[k], seg["drift"] * (0.0 if edge else 1.0))
        r -= buttress(b) * PROW_LEAN[k]
        fc = FACET[2] * facet(b, z, 58.0, SEED + 43) * soft * (1.0 - w)
        r += max(fc, 0.0) if k <= WALL_CLEAR_ROWS else fc
        if not seg["drift"] and k in (1, 2):                      # ice rubble along the foot
            r += 0.35 * h2(i, 300 + k, SEED + 44) * soft
            z += 0.3 * (h2(i, 310 + k, SEED + 44) - 0.5) * soft
        r = lerp(r, rs, w)
        tone = 0.88 + 0.24 * (seg["h"] - 0.5)
        f = _strata(z, b) * tone * lerp(1.0, 0.6, crack)
        f *= lerp(1.0, 0.55, ramp(z, zs - 4.5, zs))               # darker into the roof's thick rim
        tint = lerp3((0.86, 0.94, 1.0), (0.55, 0.78, 1.0), ramp(z, zs - 5.5, zs))
        col = lerp3((f * tint[0], f * tint[1], f * tint[2], 1.0), RIM_COL, w ** 2)   # the seam wears the roof's rim
        vid = self.m.v(pol(b, r, z), col)
        self.cleft[vid] = crack
        self._blue[vid] = seg["h"]
        return vid

    def build_wall(self):
        rows = [[self._wall_point(i, k) for i in range(NC)] for k in range(len(WALL_DZ))]
        self.wall = rows
        inward = lambda c: (-c[0], -c[1], 0.0)
        g0, g1 = GATE_COLS
        self.m.grid(rows, inward, self._wall_zone, "wall",
                    skip=lambda r, i: g0 <= i < g1 and r < GATE_ROWS)

    def _wall_zone(self, n, c, ids):
        if n[2] > 0.5 and c[2] < 33.5:
            return "snow"
        if max(self.cleft.get(v, 0.0) for v in ids) > 0.5:
            return "deep"
        if c[2] > spring(bearing_of(c))[1] - 2.4:
            return "deep"
        return "blue" if _seg_of(SERACS, int(math.floor(bearing_of(c))))[0]["h"] > 0.5 else "glacier"

    # -- gate ---------------------------------------------------------------
    def build_gate(self):
        """The ridge across the lane: the lane's own surface rising between two columns into a
        ragged serac fin, its sides the wall's own columns where it meets the wall."""
        m = self.m
        g0 = GATE_COLS[0]
        S, K = len(self.lane) - 1, GATE_ROWS
        cache = {}
        crest = [lerp(GATE_CREST[0], GATE_CREST[1], h2(s, 5, SEED + 50)) for s in range(S)] + [1.0]
        crest[0] = 0.86

        def block(s, c, h):
            """One value across a 2 x 2 patch of a face: the patch stands in or out as one facet."""
            return h2(s // 2 * 31 + (0 if c < 2 else 1), (h + s % 2) // 2, SEED + 51)

        def gv(s, c, h):
            if h == 0:
                return self.lane[s][g0 + c]
            if s == S:
                return self.wall[h][g0 + c]
            if (s, c, h) not in cache:
                base = m.verts[self.lane[s][g0 + c]]
                rad = rad_of(base)
                t = h / float(K)
                side = (c - 2) * 0.5
                half = GATE_HALF[h] * (0.85 + 0.3 * h2(s, 9, SEED + 57))
                b = GATE_B + side * half
                if c in (0, 4) and h < K:
                    b -= side * 2.0 * GATE_FACET * (block(s, c, h) - 0.5) * 2.0 * min(1.0, h / 2.0)
                if s == 0:
                    rad -= GATE_PROW * t ** 0.7 + 0.25 * (h2(c, h, SEED + 52) - 0.5)
                else:
                    rad += 0.35 * (h2(s * 5 + c, h, SEED + 53) - 0.5)
                z = DECK_Z + WALL_DZ[h] * (crest[s] if h > 2 else 1.0)
                z += 0.3 * (h2(s, h * 5 + c, SEED + 54) - 0.5) * t
                if h == K:
                    z += 0.5 * (1.0 - abs(side)) + 0.5 * (h2(s, c, SEED + 58) - 0.5)
                f = _strata(z, b) * (0.86 + 0.2 * block(s, c, h))
                cache[(s, c, h)] = m.v(pol(b, rad, z), (f * 0.9, f * 0.96, f, 1.0))
                self._blue[cache[(s, c, h)]] = block(s, c, h)
            return cache[(s, c, h)]

        t0, t1 = pol(GATE_B - 1.0, 1.0, 0.0), pol(GATE_B + 1.0, 1.0, 0.0)
        along = il.unit((t1[0] - t0[0], t1[1] - t0[1], 0.0))
        back = (-along[0], -along[1], 0.0)

        def zone(n, c, ids):
            if n[2] > 0.55:
                return "snow"
            return "blue" if min(self._blue.get(v, 0.5) for v in ids) > 0.6 else "glacier"

        for s in range(S):
            for h in range(K):
                m.quad(gv(s, 0, h), gv(s + 1, 0, h), gv(s + 1, 0, h + 1), gv(s, 0, h + 1), back, zone, "gate")
                m.quad(gv(s, 4, h), gv(s + 1, 4, h), gv(s + 1, 4, h + 1), gv(s, 4, h + 1), along, zone, "gate")
            for c in range(4):
                m.quad(gv(s, c, K), gv(s, c + 1, K), gv(s + 1, c + 1, K), gv(s + 1, c, K), UP, zone, "gate")
        inward = lambda c: (-c[0], -c[1], 0.0)
        for c in range(4):
            for h in range(K):
                m.quad(gv(0, c, h), gv(0, c + 1, h), gv(0, c + 1, h + 1), gv(0, c, h + 1), inward, zone, "gate")

    # -- roof ---------------------------------------------------------------
    def _roof_col(self, x, y, crest):
        t = roof_thin(x, y)
        if crest:
            t *= ROOF_CREST
        return lerp3(ROOF_DEEP, ROOF_THIN, t)

    def build_roof(self):
        m = self.m
        rim = list(self.wall[-1])
        rimset = set(rim)
        sites = list(rim)
        plan = [(m.verts[v][0], m.verts[v][1]) for v in rim]
        rho = ROOF_FIRST
        ring = 0
        while rho > 0.05:
            n = max(5, int(round(TWO_PI * rho / ROOF_STEP * 0.92)))
            for j in range(n):
                b = (j + 0.5 * (ring % 2) + 0.55 * (h2(j, ring, SEED + 60) - 0.5)) * 360.0 / n
                rr = (rho + (0.25 if ring else 0.1) * ROOF_STEP * 2.0 * (h2(j, ring, SEED + 61) - 0.5)) * spring(b)[0]
                x, y, _z = pol(b, rr, 0.0)
                d = ROOF_DISH[0] + ROOF_DISH[1] * h2(j, ring, SEED + 62)
                nrm = roof_normal(x, y)
                sites.append(m.v((x + nrm[0] * d, y + nrm[1] * d, roof_base(x, y) + nrm[2] * d),
                                 self._roof_col(x, y, False)))
                plan.append((x, y))
            rho -= ROOF_STEP
            ring += 1
        sites.append(m.v((0.0, 0.0, roof_base(0.0, 0.0) + ROOF_DISH[0]), self._roof_col(0.0, 0.0, False)))
        plan.append((0.0, 0.0))

        def crest(cxy, ids):
            x, y = cxy
            return m.v((x, y, roof_base(x, y)), self._roof_col(x, y, True))

        inside = lambda c: math.hypot(c[0], c[1]) < spring(bearing_of(c))[0]
        il.scallops(m, sites, plan, lambda v: v in rimset, inside, crest, "roof", "roof")
        INFO["roof_sites"] = len(sites) - len(rim)

    def build_icicles(self):
        """Icicles hang straight down from the wall's overhangs, the pit's cornice and the roof's keels."""
        m = self.m
        made = 0
        for fi in range(len(m.faces)):
            zone, chunk = m.zones[fi], m.chunks[fi]
            pts = [m.verts[v] for v in m.faces[fi]]
            n = il.unit(il.newell(pts))
            c = tuple(sum(p[k] for p in pts) / 3.0 for k in range(3))
            roll = h2(int(c[0] * 7.0) + 4096, int(c[1] * 7.0) + int(c[2] * 3.0) + 4096, SEED + 80)
            size = h2(int(c[0] * 5.0) + 4096, int(c[1] * 5.0) + 4096, SEED + 81)
            if (chunk == "wall" and zone != "snow" and n[2] < -0.22 and c[2] > DECK_Z + 4.0
                    and c[2] < spring(bearing_of(c))[1] - 2.6):
                share, lo, hi = ICICLE_WALL
            elif chunk == "ground" and n[2] < -0.12 and 20.5 < c[2] < 22.6:
                share, lo, hi = ICICLE_LIP
            elif chunk == "roof" and keel(c[0], c[1])[0] > 0.45:
                share, lo, hi = ICICLE_ROOF
            else:
                continue
            if roll > share:
                continue
            m.spike(fi, (c[0], c[1], c[2] - lerp(lo, hi, size)), "icicle", inset=0.68, col=ICICLE_COL)
            made += 1
        INFO["icicles"] = made

    def build(self):
        self.build_lane()
        self.build_pit()
        self.build_wall()
        self.build_gate()
        self.build_roof()
        self.build_icicles()
        return self.m


def build_shell():
    """The bright shell over the roof: daylight on the far side of the ice, seen through it --
    a low sun's glare on the SUN_B side, snow lying in dark drifts."""
    m = Mesh()
    rings = []
    sx, sy, _sz = pol(SUN_B, SUN_AT * SPRING_R[0], 0.0)
    for rho in SHELL_RINGS:
        ring = []
        for j in range(SHELL_NC):
            b = (j + 0.5 * (len(rings) % 2)) * 360.0 / SHELL_NC
            rs, zs = spring(b)
            bx, by, _z = pol(b, rho * rs, 0.0)
            x, y, _z = pol(b, rho * rs + SHELL_OUT * ramp(rho, 0.6, 1.0), 0.0)
            z = (SPRING_Z[0] - 6.0) if rho == 1.0 else roof_base(bx, by) + SHELL_UP
            glare = math.exp(-((bx - sx) ** 2 + (by - sy) ** 2) / (2.0 * SUN_SPREAD ** 2))
            drift_ = fbm(bx / 13.0 + 1.0, by / 13.0 - 4.0, SEED + 70)
            lum = clamp(0.34 + 0.28 * (1.0 - rho) + 0.3 * drift_ + 0.9 * glare)
            ring.append(m.v((x, y, z), lerp3(SHELL_DARK, SHELL_LIGHT, lum)))
        rings.append(ring)
    down = lambda c: (-c[0], -c[1], 20.0 - c[2])
    m.grid(rings, down, "sky", "roof")
    c = m.v((0.0, 0.0, roof_base(0.0, 0.0) + SHELL_UP), lerp3(SHELL_DARK, SHELL_LIGHT, 0.75))
    for j in range(SHELL_NC):
        m.tri(rings[-1][j], rings[-1][(j + 1) % SHELL_NC], c, down, "sky", "roof")
    return m


# =============================================================================
# COLLIDERS -- purpose-built, one per chunk
# =============================================================================

def build_colliders(s):
    """{chunk: Mesh}: flat lane to the sculpt's own lip and foot lines, pit cone and floor,
    the wall straight up off the foot line, the ridge as a prism, the roof as a coarse dome."""
    out = {}
    g = Mesh()
    lip = [g.v(s.m.verts[v]) for v in s.lane[0]]
    ft = [g.v((lambda p: pol(bearing_of(p), rad_of(p) + 0.6, DECK_Z))(s.m.verts[v])) for v in s.lane[-1]]
    g.grid([lip, ft], UP, "c", "ground")
    mid = [g.v(pol(float(i), 44.6, 6.0)) for i in range(0, NC, 6)]
    low = [g.v(pol(float(i), 41.4, FLOOR_Z)) for i in range(0, NC, 6)]
    inward = lambda c: (-c[0], -c[1], 0.0)
    g.stitch(lip, mid, inward, "c", "ground")
    g.grid([mid, low], inward, "c", "ground")
    c0 = g.v((0.0, 0.0, FLOOR_Z))
    for j in range(len(low)):
        g.tri(low[j], low[(j + 1) % len(low)], c0, UP, "c", "ground")
    out["ground"] = g

    w = Mesh()
    lo, hi = [], []
    feet = [rad_of(s.m.verts[v]) for v in s.lane[-1]]
    for i in range(NC):
        r = min(feet[(i + d) % NC] for d in (-2, -1, 0, 1, 2)) + 0.45      # no slot a body could snag in
        lo.append(w.v(pol(float(i), r, DECK_Z - 0.3)))
        hi.append(w.v(pol(float(i), r, SPRING_Z[0] + 1.5)))
    w.grid([lo, hi], inward, "c", "wall")
    out["wall"] = w

    gt = Mesh()
    ring_lo, ring_hi = [], []
    top = DECK_Z + WALL_DZ[GATE_ROWS]
    for b, r in ((GATE_B - 1.0, 43.6), (GATE_B + 1.0, 43.6), (GATE_B + 0.8, 58.8), (GATE_B - 0.8, 58.8)):
        ring_lo.append(gt.v(pol(b, r, DECK_Z - 0.5)))
        ring_hi.append(gt.v(pol(b, r, top)))
    cen = pol(GATE_B, 51.0, DECK_Z + 4.0)
    away = lambda c: (c[0] - cen[0], c[1] - cen[1], c[2] - cen[2])
    gt.grid([ring_lo, ring_hi], away, "c", "gate")
    gt.quad(ring_hi[0], ring_hi[1], ring_hi[2], ring_hi[3], UP, "c", "gate")
    gt.quad(ring_lo[0], ring_lo[1], ring_lo[2], ring_lo[3], DOWN, "c", "gate")
    out["gate"] = gt

    r_ = Mesh()
    rings = []
    for rho in (1.0, 0.8, 0.6, 0.4, 0.2):
        ring = []
        for j in range(24):
            b = j * 15.0
            x, y, _z = pol(b, rho * spring(b)[0], 0.0)
            ring.append(r_.v((x, y, roof_base(x, y) + (0.0 if rho == 1.0 else 0.4))))
        rings.append(ring)
    down = lambda c: (-c[0], -c[1], 20.0 - c[2])
    r_.grid(rings, down, "c", "roof")
    cc = r_.v((0.0, 0.0, roof_base(0.0, 0.0)))
    for j in range(24):
        r_.tri(rings[-1][j], rings[-1][(j + 1) % 24], cc, down, "c", "roof")
    out["roof"] = r_
    return out


def build_geometry():
    s = Sculpt()
    m = s.build()
    return s, m, build_shell(), build_colliders(s)


# =============================================================================
# SHEETS -- one tiling tile per class (lib/texel.py), world-projected
# =============================================================================

def _ref(centre):
    rad = math.hypot(centre[0], centre[1])
    if centre[2] > DECK_Z + 0.25 and rad > 56.8:
        return 58.5
    return 52.0 if centre[2] > DECK_Z - 0.6 else 45.0


SHEETS = {
    "lane": tx.Sheet("lane", stem="ice_lake", ref_r=_ref, tint=(0.34, 0.58, 0.9), roughness=0.5),
    "snow": tx.Sheet("snow", stem="ice_snow", ref_r=_ref, tint=(0.8, 0.88, 0.97), roughness=0.95),
    "glacier": tx.Sheet("glacier", stem="ice_glacier", ref_r=_ref, tint=(0.72, 0.88, 1.0), roughness=0.6),
    "blue": tx.Sheet("blue", stem="ice_blue", ref_r=_ref, tint=(0.7, 0.82, 1.0), roughness=0.45),
    "deep": tx.Sheet("deep", stem="ice_deep", ref_r=_ref, roughness=0.5),
    "icicle": tx.Sheet("icicle", stem="ice_icicle", mode="fit_v", rect=(0.0, 0.5, 1.0, 1.0), roughness=0.4),
    "floor": tx.Sheet("floor", stem="ice_deep", mode="box", tint=(0.42, 0.48, 0.62), roughness=0.35),
    "roof": tx.Sheet("roof", stem="ice_roof", mode="box", roughness=0.4),
    "sky": tx.Sheet("sky", stem="ice_snow", mode="box", roughness=1.0),
}
CHUNKS = ["ground", "wall", "gate", "roof"]
VIS = {"ground": "IceGround", "wall": "IceWall", "gate": "IceGate", "roof": "IceRoof"}
SHELL_NAME = "IceRoofOuter"
ROOF_ICICLES = "IceRoofIcicles"


# =============================================================================
# BLENDER SIDE
# =============================================================================

def _tint(mat, alpha=False):
    """Base Color = tile x COLOR_0 (x factor): the exporter writes a vertex-coloured texture;
    alpha also sends COLOR_0's alpha to the surface, so it is exported with the colour."""
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
    if alpha:
        nt.links.new(col.outputs["Alpha"], bsdf.inputs["Alpha"])
        mdl._try(mat, "surface_render_method", "BLENDED")
        mdl._try(mat, "blend_method", "BLEND")


def _object(name, verts, cols, faces, zones, mats):
    """A textured, vertex-coloured, flat-shaded object."""
    ob = mdl.mesh(name, verts, faces)
    tx.unwrap(ob, zones, SHEETS, seed=1)
    tx.finish(ob, zones, mats)
    attr = ob.data.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    attr.data.foreach_set("color", [c for rgba in cols for c in rgba])
    ob.data.color_attributes.active_color_index = 0
    ob.data.color_attributes.render_color_index = 0
    return ob


def _part(m, chunk, name, mats, keep=None):
    """One chunk of a Mesh (or only its keep(zone) faces) as its own object: the same vertex
    positions, so seams are exact."""
    remap, verts, cols, faces, zones = {}, [], [], [], []
    for f, z, c in zip(m.faces, m.zones, m.chunks):
        if c != chunk or (keep is not None and not keep(z)):
            continue
        g = []
        for vi in f:
            if vi not in remap:
                remap[vi] = len(verts)
                verts.append(m.verts[vi])
                cols.append(m.cols[vi])
            g.append(remap[vi])
        faces.append(tuple(g))
        zones.append(z)
    return _object(name, verts, cols, faces, zones, mats)


def build():
    s, m, shell, colliders = build_geometry()
    mats = tx.materials(NAME, SHEETS)
    for cls, mat in mats.items():
        _tint(mat, alpha=cls == "roof")
    out = []
    for chunk in CHUNKS:
        # the roof is see-through and its icicles are not: COLOR_0 keeps its alpha only on a
        # mesh whose every material reads it, so the icicles ride as their own object
        vis = _part(m, chunk, VIS[chunk], mats, (lambda z: z != "icicle") if chunk == "roof" else None)
        if chunk == "roof":
            out.append(_part(m, chunk, ROOF_ICICLES, mats, lambda z: z == "icicle"))
        col = colliders[chunk]
        cv, _cc, cf = col.used()
        cob = mdl.mesh(VIS[chunk] + "Collision-colonly", cv, cf)
        cob.hide_render = True
        out += [vis, cob]
        print("MDL STATS %s visual_tris=%d collision_tris=%d" % (chunk, len(vis.data.polygons), len(cf)))
    sv, sc, sf = shell.used()
    out.append(_object(SHELL_NAME, sv, sc, sf, list(shell.zones), mats))
    tx.report(SHEETS)
    print("MDL STATS roof_sites=%d slabs=%d notches=%d seracs=%d icicles=%d"
          % (INFO.get("roof_sites", 0), len(SLABS), len(NOTCHES), len(SERACS), INFO.get("icicles", 0)))
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
        obs = [by_name[label], by_name[label + "Collision-colonly"]]
        nodes = [label, label + "Collision", label + "Collision/CollisionShape3D"]
        if chunk == "roof":
            obs += [by_name[SHELL_NAME], by_name[ROOF_ICICLES]]
            nodes += [SHELL_NAME, ROOF_ICICLES]
        path = os.path.join(out_dir, "%s_%s.glb" % (NAME, chunk))
        mdl.export_glb(path, obs)
        print("MDL EXPORT %s (%d bytes)" % (path, os.path.getsize(path)))
        made.append({"chunk": chunk, "glb": os.path.basename(path),
                     "contract": {"node_paths": nodes, "max_tris": 40000}})
    with open(os.path.join(out_dir, NAME + ".chunks.json"), "w") as fh:
        json.dump({"chunks": made}, fh, indent=1)
    return [os.path.join(out_dir, c["glb"]) for c in made]


def _check():
    s, m, shell, colliders = build_geometry()
    il.report(m, "sculpt")
    for chunk in CHUNKS:
        sub = Mesh()
        sub.verts, sub.cols = m.verts, m.cols
        for f, z, c in zip(m.faces, m.zones, m.chunks):
            if c == chunk:
                sub.faces.append(f)
                sub.zones.append(z)
                sub.chunks.append(c)
        il.report(sub, chunk)
        il.report(colliders[chunk], chunk + "_collider")
    il.report(shell, "shell")
    lip = [rad_of(m.verts[v]) for v in s.lane[0]]
    ft = [rad_of(m.verts[v]) for v in s.lane[-1]]
    print("lip r=%.2f..%.2f (<= %.1f)  foot r=%.2f..%.2f (>= %.1f)  roof_sites=%d"
          % (min(lip), max(lip), INNER_R, min(ft), max(ft), OUTER_R, INFO.get("roof_sites", 0)))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, export=_export_chunks)
