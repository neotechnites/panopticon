"""
PANOPTICON -- ice: Map 4. An ice cavern: what map 1 does in rock, in ice. A shelf of lake ice round
a crevassed pit, a wall of flat-faced blue ice with tiers of barred cells cut into it, a scalloped
see-through roof, and a slotted ice screen across the lane at 353 deg. ONE sculpt (one mesh, shared
vertices), exported per chunk:

    ice_ground.glb   pit floor, pit wall and its cells, the crevassed rim, the lane   IceGround
    ice_wall.glb     the ice wall and its cells, lane edge to the roof's spring ring  IceWall
    ice_gate.glb     the slotted screen across the lane (the lane's own surface)      IceGate
    ice_roof.glb     the scalloped roof and the bright shell seen through             IceRoof, IceRoofOuter

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
                     angdiff, interp, h2, vnoise, fbm, ring_noise, worley, add, sub, scale, dot, cross, unit)
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

# -- the ice wall: flat faces en echelon between the roof's piers, leaning in to its spring ring
PIERS = [(348, 358), (380, 385), (413, 421), (460, 468), (494, 502), (523, 530), (553, 558), (596, 602),
         (642, 647), (675, 681)]                     # the piers the roof's keels spring from (fixed: the roof stays)
VAULTS = [(358, 380, 0.9731223312762178), (385, 413, 0.8154195803904033), (421, 460, 0.8662097354185265),
          (468, 494, 0.9177147528785172), (502, 523, 0.6621493413626363), (530, 553, 0.8298627412155559),
          (558, 596, 0.5964138622777299), (602, 642, 0.8676478824195721), (647, 675, 0.6873061582215021),
          (681, 708, 0.5949651473719058)]            # the roof's rise between two piers (fixed with them)
WALL_DZ = [0.0, 0.45, 1.1, 3.4, 4.9, 6.1, 8.1, 9.4, 10.3, 10.8, 11.2, 11.6]     # rows over the lane at a pier
WALL_RISE = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.5, 0.8, 1.0]      # share of the vault's rise a row takes
WALL_COVE = [0.0, 0.55, 0.95, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1]     # the face stands back off its foot
WALL_DRIFT = [0.0, 0.9, 1.45, 1.3, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1]     # the cove under a snow bank
WALL_CLEAR_ROWS = 3         # rows a body can touch: these only ever stand back from the foot line
LEAN_FROM = 4.0             # metres over the lane where the wall starts in toward the spring ring ...
LEAN_POW = 1.7              # ... and how late it gets there
FOOT_MIN = 57.6             # the wall foot where a face stands furthest forward
FACE_W = (6, 11)            # degrees of wall a face holds
FACE_SKEW = 8.0             # degrees a face is turned off the ring's tangent, either way
BAY_BACK = (0.4, 2.2)       # how far the wall between two piers stands back
FACE_STEP = 0.9             # ... and how far its faces step past one another
SPRING_R = (55.6, 0.8, 1.2)  # the spring ring: radius, wander, pull-in at a pier
SPRING_Z = (34.6, 5.2)      # its height at a pier, and the rise of the vault between two piers

# -- cells: an arched mouth cut through the ice, a reveal back to a screen of ice bars, cold light behind
TIERS = ((2, 3, 4), (5, 6, 7), (8, 9, 10))           # wall rows: sill, springing, head
TIER_SHARE = (0.9, 0.8, 1.0)                         # share of a tier's places that hold a cell
TIER_RISE = 3.0             # the top tier only where the vault has risen this far
CELL_W = (2, 4)             # columns a wall cell is wide
PIT_TIERS = ((5, 4, 3), (8, 7, 6), (11, 10, 9))      # PIT_Y rows: sill, springing, head
PIT_SHARE = (0.9, 0.8, 0.6)
PIT_CELL_W = (3, 5)
CELL_DZ = (0.25, 0.3)       # a cell's sill and head wander this far off their rows
CELL_BACK = (0.45, 0.8)     # the screen stands this far behind the mouth's deepest point
CELL_SPLAY = 0.93           # ... and is this share of the mouth: the reveals splay
ARCH_H = (0.78, 0.95)       # the arch's crown, as a share of the way to the head row
ARCH_P = (1.7, 2.6)         # its superellipse power: 2 is round, less is pointed
BAR_W = (0.2, 0.3)          # an ice bar's width ...
BAR_GAP = (0.3, 0.42)       # ... and the light between two
BAR_PROUD = (0.08, 0.15, 0.24)      # how far its ridge stands off the screen: foot, middle, head
GLOW_COL = ((0.72, 0.8, 0.9, 1.0), (1.0, 1.0, 1.0, 1.0))      # the light at a cell's sill and head
BAR_COL = (0.5, 0.64, 0.84, 1.0)

# -- the screen across the lane (the gate): the lane's own surface rising into a wall of fused ice
# columns with slots cut clean through it; no slot wider than GATE_SLOT[1]
GATE_B = 353.0
GATE_COLS = (351, 355)
GATE_ROWS = 7               # wall rows 0..7: crest 9.4 m over the lane
GATE_HALF = [2.0, 0.95, 0.6, 0.48, 0.46, 0.5, 0.62, 0.42]      # half thickness in degrees per row
GATE_RIDGE = 0.22           # degrees a column's ridge stands proud of its edges
GATE_SLOT = (0.34, 0.44)    # metres of light between two columns
GATE_COLUMN = (0.5, 0.95)   # a column's width
GATE_END = 1.0              # the column at the lip
GATE_FLARE = 2.0            # metres of solid ice where the screen grows out of the wall
GATE_SLOT_ROWS = ((2, 5), (2, 6), (2, 5), (3, 6), (2, 4))      # rows a slot runs between
GATE_CREST = 0.7            # the crest's wander, metres

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


def _faces():
    """The wall in plan: the piers, and between each pair a bay of flat faces set back, skewed
    and stepped past one another."""
    r = Rng(SEED + 3)
    out = []
    n = len(PIERS)
    for k, (p0, p1) in enumerate(PIERS):
        out.append({"b0": p0, "b1": p1, "psi": 0.5 * (p0 + p1) + (0.0 if k == 0 else r.u(-5.0, 5.0)),
                    "near": FOOT_MIN + r.u(0.0, 0.35), "kind": "pier", "h": r.f(), "drift": 0.0})
        nxt = PIERS[(k + 1) % n][0] + (360 if k + 1 == n else 0)
        back = r.u(*BAY_BACK)
        b = p1
        while b < nxt:
            w = min(r.i(*FACE_W), nxt - b)
            if nxt - (b + w) < FACE_W[0]:
                w = nxt - b
            out.append({"b0": b, "b1": b + w, "psi": b + 0.5 * w + r.u(-FACE_SKEW, FACE_SKEW),
                        "near": FOOT_MIN + back + r.u(0.0, FACE_STEP), "kind": "face", "h": r.f(),
                        "drift": 1.0 if back > 1.3 and r.f() < 0.6 else 0.0})
            b += w
    return out


SLABS = _slabs()
FACES = _faces()
PROWS = [(0.5 * (p0 + p1) % 360.0, 0.5 * (p1 - p0)) for p0, p1 in PIERS]


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


def face_r(i, b):
    """(radius, face) of the wall's plan line at column i (bearing b): its face's chord, the mean of two at a crease."""
    seg, edge, prev, ii = _seg_of(FACES, i)
    if edge:
        return 0.5 * (_chord(seg, ii) + _chord(prev, prev["b1"])), seg
    return _chord(seg, _seg_b(seg, b)), seg


def foot(i):
    """The wall's foot line at column i: the lane's outer edge."""
    return face_r(i, float(i))[0]


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


def bench(b):
    """(0..1 share, height) of a calved shelf on the pit wall at bearing b."""
    m_ = ramp(ring_noise(b, SEED + 31, ((3, 1.0), (8, 0.7))), 0.12, 0.42)
    return m_, BENCH_Y[0] + BENCH_Y[1] * ring_noise(b, SEED + 32, ((2, 1.0), (5, 0.6)))


def _cell(r, i0, w, rows):
    return {"i0": i0, "w": w, "rows": rows, "seed": r.i(1, 1 << 20),
            "dz": (r.u(-CELL_DZ[0], CELL_DZ[0]), r.u(-CELL_DZ[1], CELL_DZ[1]))}


def _wall_cells():
    """Cells packed along each face of the wall, a column of ice between two; the top tier only
    under a risen vault."""
    out = []
    for seg in FACES:
        if seg["kind"] != "face":
            continue
        for t, share in enumerate(TIER_SHARE):
            r = Rng(SEED + 400 + 131 * t + seg["b0"])
            cur = seg["b0"] + 1 + r.i(0, 1)
            while True:
                w = r.i(*CELL_W) if t < 2 else CELL_W[0]
                if cur + w > seg["b1"] - 1:
                    break
                rise = min(SPRING_Z[1] * vault(float(i)) for i in range(cur, cur + w + 1))
                if r.f() < share and (t < 2 or rise >= TIER_RISE):
                    out.append(_cell(r, cur, w, TIERS[t]))
                cur += w + r.i(1, 2)
    return out


def _pit_cells():
    """Cells in the pit wall's slabs, clear of the crevasse notches and the calved shelves."""
    out = []
    for k, seg in enumerate(SLABS):
        if k == 0:
            continue
        nxt = SLABS[(k + 1) % len(SLABS)]
        lo = seg["b0"] + (3 if seg["notch"] else 1)
        hi = seg["b1"] - (3 if nxt["notch"] else 1)
        for t, share in enumerate(PIT_SHARE):
            r = Rng(SEED + 500 + 131 * t + seg["b0"])
            cur = lo + r.i(0, 1)
            while True:
                w = r.i(*PIT_CELL_W)
                if cur + w > hi:
                    break
                if r.f() < share and all(bench(float(i))[0] <= 0.0 for i in range(cur - 1, cur + w + 2)):
                    out.append(_cell(r, cur, w, PIT_TIERS[t]))
                cur += w + r.i(1, 2)
    return out


def _mask(cells, quad_rows):
    """({(column, row): the row's lift there}, {(grid row, column)} of the quads a cell replaces)."""
    verts, holes = {}, set()
    for c in cells:
        ks, km, kh = c["rows"]
        for j in range(c["w"] + 1):
            i = (c["i0"] + j) % NC
            verts[(i, ks)], verts[(i, km)], verts[(i, kh)] = c["dz"][0], 0.5 * c["dz"][1], c["dz"][1]
        for j in range(c["w"]):
            for q in quad_rows(c["rows"]):
                holes.add((q, (c["i0"] + j) % NC))
    return verts, holes


WALL_CELLS = _wall_cells()
PIT_CELLS = _pit_cells()


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
        self._blue = {}          # vertex id -> its slab's firn line, deep line and cornice
        self.lane = []           # rows lip .. wall foot, NC vertices each
        self.wall = []           # rows foot .. spring
        self.pit = []            # rows lip .. floor join
        self.wall_mask, self.wall_holes = _mask(WALL_CELLS, lambda rows: (rows[0], rows[1]))
        self.pit_mask, self.pit_holes = _mask(PIT_CELLS, lambda rows: (rows[2] + 1, rows[1] + 1))

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
        seg = _seg_of(FACES, int(round(b)))[0]
        if seg["drift"] and r > foot(int(round(b))) - 1.2 - 1.0 * fbm(c[0] / 3.0, c[1] / 3.0, SEED + 23):
            return "snow"
        return "lane"

    # -- pit wall and floor ---------------------------------------------------
    def _pit_point(self, i, k):
        y0 = PIT_Y[k]
        soft = ramp(y0, 22.3, 19.0)                      # the cornice rows keep their line
        seg, edge, prev, ii = _seg_of(SLABS, i)
        cell = self.pit_mask.get((i, k))
        if cell is not None:                             # this vertex frames a cell: it keeps its slab's plane
            soft, y0 = 0.0, y0 + cell
        b = i + (0.0 if edge else _jb(i, 60 + k, 0.28) * soft)
        y = y0 + _jb(i, 80 + k, 0.45) * soft
        bm, by = bench(b)
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
        m.grid(rows, inward, self._pit_zone, "ground", skip=lambda r, i: (r, i) in self.pit_holes)
        for c in PIT_CELLS:
            ks, km, kh = (q + 1 for q in c["rows"])
            cols = [(c["i0"] + j) % NC for j in range(c["w"] + 1)]
            self.carve([rows[ks][i] for i in cols], [rows[kh][i] for i in cols], rows[km][cols[0]],
                       rows[km][cols[-1]], "ground", c["seed"], self._pit_zone)
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
        _firn, deep, corn = max((self._blue[v] for v in ids if v in self._blue), default=(21.0, 1.0, False))
        if corn and c[2] > 22.2:
            return "snow"
        if min(self.cleft.get(v, 0.0) for v in ids) > 0.3 or c[2] < deep:
            return "deep"
        return "blue"

    def _floor_zone(self, n, c, ids):
        return "floor" if n[2] > 0.8 else "deep"

    # -- wall ---------------------------------------------------------------
    def _wall_point(self, i, k):
        if k == 0:
            return self.lane[-1][i]
        last = len(WALL_DZ) - 1
        seg, edge, _prev, _ii = _seg_of(FACES, i)
        cell = self.wall_mask.get((i, k))
        soft = 0.0 if (k == last or edge or cell is not None or (_gate_col(i) and k <= GATE_ROWS)) else 1.0
        b = i + _jb(i, 200 + k, 0.3) * soft
        rs, zs = spring(b)
        if k == last:
            return self.m.v(pol(b, rs, zs), RIM_COL)     # the seam: the roof's rim, in its colour
        z = DECK_Z + WALL_DZ[k] + WALL_RISE[k] * (zs - SPRING_Z[0])
        if cell is not None:                             # this vertex frames a cell: it keeps its face's plane
            z += cell
        elif k >= 2:
            z += _jb(i, 220 + k, 0.2) * min(WALL_DZ[k] - WALL_DZ[k - 1], 1.2) * soft
        r = face_r(i, b)[0] + lerp(WALL_COVE[k], WALL_DRIFT[k], seg["drift"] * (0.0 if edge else 1.0))
        t = clamp((z - DECK_Z - LEAN_FROM) / (zs - DECK_Z - LEAN_FROM)) ** LEAN_POW
        fc = FACET[2] * facet(b, z, 58.0, SEED + 43) * soft * (1.0 - t)
        r += max(fc, 0.0) if k <= WALL_CLEAR_ROWS else fc
        r = lerp(r, rs, t)
        tone = 0.9 + 0.2 * (seg["h"] - 0.5)
        f = _strata(z, b) * tone * (1.14 if edge else 1.0)            # an arris is thin ice: it carries more light
        f *= lerp(1.0, 0.6, ramp(z, zs - 4.5, zs))                    # darker into the roof's thick rim
        tint = lerp3((0.9, 0.97, 1.0), (0.6, 0.8, 1.0), ramp(z, zs - 5.5, zs))
        return self.m.v(pol(b, r, z), lerp3((f * tint[0], f * tint[1], f * tint[2], 1.0), RIM_COL, t * t))

    def build_wall(self):
        rows = [[self._wall_point(i, k) for i in range(NC)] for k in range(len(WALL_DZ))]
        self.wall = rows
        inward = lambda c: (-c[0], -c[1], 0.0)
        g0, g1 = GATE_COLS
        self.m.grid(rows, inward, self._wall_zone, "wall",
                    skip=lambda r, i: (g0 <= i < g1 and r < GATE_ROWS) or (r, i) in self.wall_holes)
        for c in WALL_CELLS:
            ks, km, kh = c["rows"]
            cols = [(c["i0"] + j) % NC for j in range(c["w"] + 1)]
            self.carve([rows[ks][i] for i in cols], [rows[kh][i] for i in cols], rows[km][cols[0]],
                       rows[km][cols[-1]], "wall", c["seed"], self._wall_zone)

    def _wall_zone(self, n, c, ids):
        if n[2] > 0.5 and c[2] < 33.5:
            return "snow"
        return "deep" if c[2] > spring(bearing_of(c))[1] - 2.2 else "blue"

    # -- cells ----------------------------------------------------------------
    def carve(self, bot, top, spl, spr, chunk, seed, host):
        """A cell in the hole framed by bot (sill), top (head) and the springing vertices spl, spr:
        spandrels to an arched mouth, splayed reveals back to a screen, ice bars standing off it and
        cold light between them. Every seam shares its vertices."""
        m = self.m
        V = m.verts
        r = Rng(seed)
        BL, BR, TL, TR, SL, SR = V[bot[0]], V[bot[-1]], V[top[0]], V[top[-1]], V[spl], V[spr]
        X = unit(sub(BR, BL))
        Y = unit(add(sub(TL, BL), sub(TR, BR)))
        into = unit(cross(X, Y))
        cen = tuple(sum(p[k] for p in (BL, BR, TL, TR, SL, SR)) / 6.0 for k in range(3))
        if into[0] * cen[0] + into[1] * cen[1] < 0.0:
            into = scale(into, -1.0)
        front = scale(into, -1.0)
        # the lines up the screen: a jamb, then each bar's edge, ridge, edge, then the far jamb
        width = math.dist(BL, BR) * CELL_SPLAY
        nb = max(2, int((width - BAR_GAP[0]) / (0.5 * (BAR_W[0] + BAR_W[1] + BAR_GAP[0] + BAR_GAP[1]))))
        spans = [r.u(*BAR_GAP)]
        for _ in range(nb):
            w_ = r.u(*BAR_W)
            spans += [0.5 * w_, 0.5 * w_, r.u(*BAR_GAP)]
        us, acc = [0.0], 0.0
        for sp in spans:
            acc += sp
            us.append(acc / sum(spans))
        us[-1] = 1.0
        n = len(us) - 1
        hh, pw, skew = r.u(*ARCH_H), r.u(*ARCH_P), r.u(0.88, 1.14)

        def arch(u):
            return hh * max(0.0, 1.0 - abs(2.0 * u ** skew - 1.0) ** pw) ** (1.0 / pw)

        def at(u, v):
            return lerp3(lerp3(SL, SR, u), lerp3(TL, TR, u), v)

        A = [spl] + [m.v(at(u, arch(u)), _shade(lerp3(m.cols[spl], m.cols[spr], u), 0.92)) for u in us[1:-1]] + [spr]
        nt = len(top) - 1.0
        m.zipper([spl] + list(top) + [spr], [0.0] + [j / nt for j in range(len(top))] + [1.0], A, us, front, host, chunk)
        mouth = [V[v] for v in bot] + [V[v] for v in A]
        depth = max(dot(sub(p, cen), into) for p in mouth) + r.u(*CELL_BACK)
        mc = lerp3(lerp3(BL, BR, 0.5), at(0.5, arch(0.5)), 0.5)

        def proj(p):
            q = add(p, scale(into, depth - dot(sub(p, cen), into)))
            return lerp3(add(mc, scale(into, depth - dot(sub(mc, cen), into))), q, CELL_SPLAY)

        Bp = [m.v(proj(lerp3(BL, BR, u)), GLOW_COL[0]) for u in us]
        Tp = [m.v(proj(V[a]), lerp3(GLOW_COL[0], GLOW_COL[1], 0.4 + 0.6 * arch(u) / hh)) for a, u in zip(A, us)]
        sill = lambda nrm, c, ids: "snow" if nrm[2] > 0.5 else "reveal"
        m.zipper(bot, [j / (len(bot) - 1.0) for j in range(len(bot))], Bp, us, Y, sill, chunk)
        m.quad(bot[0], spl, Tp[0], Bp[0], X, "reveal", chunk)
        m.quad(bot[-1], spr, Tp[-1], Bp[-1], scale(X, -1.0), "reveal", chunk)
        for j in range(n):
            m.quad(A[j], A[j + 1], Tp[j + 1], Tp[j], sub(mc, lerp3(V[A[j]], V[A[j + 1]], 0.5)), "reveal", chunk)
        j = 0
        while j < n:
            if j % 3 == 0:                               # the light between two bars
                m.quad(Bp[j], Bp[j + 1], Tp[j + 1], Tp[j], front, "glow", chunk)
                j += 1
                continue
            lo, hi = V[Bp[j + 1]], V[Tp[j + 1]]          # a bar: two faces meeting on a ridge that stands off the screen
            wob = r.u(-0.06, 0.06)
            ridge = [Bp[j + 1]]
            for f, proud in zip((0.14, 0.5, 0.86), BAR_PROUD):
                p_ = add(lerp3(lo, hi, f), add(scale(front, proud * r.u(0.8, 1.3)), scale(X, wob * math.sin(3.1 * f))))
                ridge.append(m.v(p_, BAR_COL))
            ridge.append(Tp[j + 1])
            tr = [0.0, 0.14, 0.5, 0.86, 1.0]
            m.zipper([Bp[j], Tp[j]], [0.0, 1.0], ridge, tr, add(front, scale(X, -0.7)), "bar", chunk)
            m.zipper(ridge, tr, [Bp[j + 2], Tp[j + 2]], [0.0, 1.0], add(front, scale(X, 0.7)), "bar", chunk)
            j += 2
        INFO["cells"] = INFO.get("cells", 0) + 1

    # -- gate ---------------------------------------------------------------
    def build_gate(self):
        """The screen across the lane: the lane's own surface rising between two columns into a wall
        of fused ice columns with slots cut clean through it; its wall end is the wall's own columns."""
        m = self.m
        g0 = GATE_COLS[0]
        S, K = len(self.lane) - 1, GATE_ROWS
        r = Rng(SEED + 50)
        lip_r_ = [rad_of(m.verts[self.lane[0][g0 + c]]) for c in range(5)]
        foot_r = [rad_of(m.verts[self.lane[S][g0 + c]]) for c in range(5)]
        span = foot_r[2] - lip_r_[2]
        # the lines along the screen: (metres from the lip, kind); a slot lies between an "R" and the next "L"
        lines = [(0.0, "E"), (0.5 * GATE_END, "M"), (GATE_END, "R")]
        slots = {}
        pos = GATE_END
        while True:
            sw, cw = r.u(*GATE_SLOT), r.u(*GATE_COLUMN)
            if pos + sw + cw > span - GATE_FLARE:
                break
            slots[len(lines) - 1] = GATE_SLOT_ROWS[r.i(0, len(GATE_SLOT_ROWS) - 1)]
            lines += [(pos + sw, "L"), (pos + sw + 0.5 * cw, "M"), (pos + sw + cw, "R")]
            pos += sw + cw
        nf = max(2, int(round((span - pos) / 1.1)))
        lines += [(pos + (span - pos) * (q + 1.0) / nf, "F") for q in range(nf)]
        J = len(lines) - 1
        cache = {}

        def gv(j, c, h):
            if j == J:
                return self.wall[h][g0 + c]
            if h == 0:
                return self.lane[0][g0 + c]              # only the lip end reaches the lane along a line
            if (j, c, h) not in cache:
                d, kind = lines[j]
                flare = smooth((d - (span - GATE_FLARE)) / GATE_FLARE)
                side = (c - 2) * 0.5
                half = GATE_HALF[h] * (0.9 + 0.2 * h2(j, h, SEED + 51))
                if kind == "M" and h < K:
                    half += GATE_RIDGE * (0.6 + 0.8 * h2(j, h, SEED + 52))
                rad = lerp(lip_r_[c], foot_r[c], d / span)
                z = DECK_Z + WALL_DZ[h]
                if h >= 2:
                    rad += 0.06 * (h2(j, h, SEED + 53) - 0.5) * (1.0 - flare)
                    z += 0.5 * (h2(j, h, SEED + 54) - 0.5) * (1.0 - flare)
                if j == 0:
                    rad += 0.3 * h / float(K)             # the lip end stands back off the drop as it rises
                if h == K:
                    z += (GATE_CREST * (h2(j, 7, SEED + 58) - 0.5) + 0.35 * (1.0 - abs(side))) * (1.0 - flare)
                b = GATE_B + side * lerp(half, 2.0, flare)
                f = _strata(z, b) * (0.86 + 0.2 * h2(j // 3, 3, SEED + 55)) * (1.12 if kind == "M" else 1.0)
                cache[(j, c, h)] = m.v(pol(b, rad, z), (f * 0.9, f * 0.97, f, 1.0))
            return cache[(j, c, h)]

        t0, t1 = pol(GATE_B - 1.0, 1.0, 0.0), pol(GATE_B + 1.0, 1.0, 0.0)
        along = unit((t1[0] - t0[0], t1[1] - t0[1], 0.0))
        back = scale(along, -1.0)
        out = unit(pol(GATE_B, 1.0, 0.0))
        zone = lambda n, c, ids: "snow" if n[2] > 0.6 else "blue"
        for j in range(J):
            sl = slots.get(j)
            for h in range(1, K):
                if sl and sl[0] <= h < sl[1]:
                    continue
                m.quad(gv(j, 0, h), gv(j + 1, 0, h), gv(j + 1, 0, h + 1), gv(j, 0, h + 1), back, zone, "gate")
                m.quad(gv(j, 4, h), gv(j + 1, 4, h), gv(j + 1, 4, h + 1), gv(j, 4, h + 1), along, zone, "gate")
            if sl:                                           # the slot's own walls, sill and head, through the ice
                for h in range(sl[0], sl[1]):
                    m.quad(gv(j, 0, h), gv(j, 4, h), gv(j, 4, h + 1), gv(j, 0, h + 1), out, "reveal", "gate")
                    m.quad(gv(j + 1, 0, h), gv(j + 1, 4, h), gv(j + 1, 4, h + 1), gv(j + 1, 0, h + 1),
                           scale(out, -1.0), "reveal", "gate")
                m.quad(gv(j, 0, sl[0]), gv(j + 1, 0, sl[0]), gv(j + 1, 4, sl[0]), gv(j, 4, sl[0]), UP, "reveal", "gate")
                m.quad(gv(j, 0, sl[1]), gv(j + 1, 0, sl[1]), gv(j + 1, 4, sl[1]), gv(j, 4, sl[1]), DOWN, "reveal", "gate")
            for c in range(4):
                m.quad(gv(j, c, K), gv(j, c + 1, K), gv(j + 1, c + 1, K), gv(j + 1, c, K), UP, zone, "gate")
        for c, want in ((0, back), (4, along)):              # the cove: the lane's own edge up to the screen's foot
            lane_ids = [self.lane[s][g0 + c] for s in range(S + 1)]
            fine = [gv(j, c, 1) for j in range(J + 1)]
            m.zipper(lane_ids, [rad_of(m.verts[v]) for v in lane_ids], fine, [rad_of(m.verts[v]) for v in fine],
                     add(want, (0.0, 0.0, 0.6)), zone, "gate")
        inward = lambda c: (-c[0], -c[1], 0.0)
        for c in range(4):
            for h in range(K):
                m.quad(gv(0, c, h), gv(0, c + 1, h), gv(0, c + 1, h + 1), gv(0, c, h + 1), inward, zone, "gate")
        INFO["slots"] = len(slots)

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
            if (chunk == "wall" and zone in ("blue", "deep") and n[2] < -0.3 and c[2] > DECK_Z + 4.0
                    and c[2] < spring(bearing_of(c))[1] - 2.6):
                share, lo, hi = ICICLE_WALL
            elif chunk == "ground" and zone != "glow" and n[2] < -0.12 and 20.5 < c[2] < 22.6:
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
    for b, r in ((GATE_B - 0.9, 45.2), (GATE_B + 0.9, 45.2), (GATE_B + 0.8, 58.8), (GATE_B - 0.8, 58.8)):
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
    "lane": tx.Sheet("lane", stem="ice_lake", ref_r=_ref, tint=(0.55, 0.72, 0.92), roughness=0.4),
    "snow": tx.Sheet("snow", stem="ice_snow", ref_r=_ref, tint=(0.8, 0.88, 0.97), roughness=0.95),
    "blue": tx.Sheet("blue", stem="ice_blue", ref_r=_ref, tint=(0.58, 0.74, 0.96), roughness=0.35),
    "deep": tx.Sheet("deep", stem="ice_deep", ref_r=_ref, roughness=0.4),
    "icicle": tx.Sheet("icicle", stem="ice_icicle", mode="fit_v", rect=(0.0, 0.5, 1.0, 1.0), roughness=0.35),
    "floor": tx.Sheet("floor", stem="ice_deep", mode="box", tint=(0.6, 0.7, 0.86), roughness=0.3),
    "glow": tx.Sheet("glow", stem="ice_glow", size=32, mode="box", roughness=1.0),
    "roof": tx.Sheet("roof", stem="ice_roof", mode="box", roughness=0.4),
    "sky": tx.Sheet("sky", stem="ice_snow", mode="box", roughness=1.0),
}
ZONE_CLASS = {"reveal": "deep", "bar": "deep"}        # a cell's reveals and bars wear the dark ice
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


def _emit(mat):
    """The cells' light: the tile is its own emission, as map 1's cell glow is."""
    nt = mat.node_tree
    img = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
    nt.links.new(img.outputs["Color"], nt.nodes.get("Principled BSDF").inputs["Emission Color"])


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
        zones.append(ZONE_CLASS.get(z, z))
    return _object(name, verts, cols, faces, zones, mats)


def build():
    s, m, shell, colliders = build_geometry()
    mats = tx.materials(NAME, SHEETS)
    for cls, mat in mats.items():
        _tint(mat, alpha=cls == "roof")
    _emit(mats["glow"])
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
    print("MDL STATS roof_sites=%d slabs=%d notches=%d faces=%d cells=%d+%d slots=%d icicles=%d"
          % (INFO.get("roof_sites", 0), len(SLABS), len(NOTCHES), len(FACES), len(WALL_CELLS), len(PIT_CELLS),
             INFO.get("slots", 0), INFO.get("icicles", 0)))
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
    print("lip r=%.2f..%.2f (<= %.1f)  foot r=%.2f..%.2f (>= %.1f)  roof_sites=%d  cells wall=%d pit=%d  slots=%d"
          % (min(lip), max(lip), INNER_R, min(ft), max(ft), OUTER_R, INFO.get("roof_sites", 0), len(WALL_CELLS),
             len(PIT_CELLS), INFO.get("slots", 0)))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, export=_export_chunks)
