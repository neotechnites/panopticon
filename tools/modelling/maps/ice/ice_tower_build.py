"""
PANOPTICON -- ice_tower: Map 4's guard tower, map 1's tower in ice: a fused, faceted ice column from the pit floor,
its head carved into the guard chamber with eight round-headed arches, a low ice dome with a snow cap.

    tools/modelling/model build ice_tower --views none
    python3 tools/modelling/maps/ice/ice_tower_build.py --check
"""

import math
import os
import sys

try:
    import bpy
except ImportError:
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import texel as tx  # noqa: E402
import ice_lib as il  # noqa: E402

if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["ground"] = False

# =============================================================================
# TUNABLES  (Blender local, z up; origin = the Tower node datum, world y 25.35)
# =============================================================================

NAME = "ice_tower"
OBJECT_NAME = "IceTower"
COLLIDER_NAME = "IceTowerCollision-colonly"
FACING_YAW = 0.0
SEED = 4417

# the guard datum: TowerVariant's plugs are sized to these
FLOOR_Z, ROOM_R, SILL_Z, HEAD_Z, CEIL_Z = 1.70, 6.86, 2.35, 7.00, 7.25
PHASE, SPAN, BAYS = 25.0, 40.0, 8          # opening k centred on 25 + 45k, 40 deg wide
ARCH_SEG = 8                               # segments in each semicircular head
ARCH_R = math.radians(SPAN * 0.5) * ROOM_R  # the head's radius, measured round the room wall
SPRING_Z = HEAD_Z - ARCH_R
SIGHT = (7.95, 2.45, 6.80)                 # nothing at r > 7.95 between z 2.45 and 6.8 outside the piers

DRUM_R, DRUM_JIT = 7.78, 0.08              # the drum's outer face, not a circle: jittered per vertex
RIB = (0.40, 0.30)                         # the pier's ice rib, proud of the drum / down the shaft

# the column: (z, mean radius), off tower_arches.glb: foot ~10.5, narrows to ~7.7 at -15, swells at -10, ~7.7 under the drum
PIT_Z = -36.40
FOOT_Z = PIT_Z - 0.40
SHAFT = [(-36.8, 9.4), (-34.0, 9.2), (-30.0, 9.0), (-25.0, 9.4), (-20.0, 8.6), (-15.0, 7.55), (-10.0, 8.45),
         (-6.0, 8.05), (-2.5, 7.55), (1.6, 7.55)]
ROWS = [-36.8, -36.15, -35.1, -33.4, -31.3, -28.9, -26.3, -23.6, -20.8, -18.0, -15.2, -12.4, -9.7, -7.1,
        -4.7, -2.5, -0.6, 0.9]
ROW_JIT = 0.70                             # shaft rows wander this far in z: no horizontal rings
# the fracture planes: corner bearings and radius factors of the plan polygon, per tier (z); edges wander between
PLAN_Z = [-36.8, -30.5, -23.0, -16.5, -9.5, -3.5, 1.6]
PLAN_B = [0.0, 38.0, 101.0, 146.0, 197.0, 233.0, 296.0]
PLAN_F = [1.06, 0.92, 1.10, 0.95, 1.12, 0.90, 1.02]
PLAN_WANDER = (11.0, 0.08)                 # per tier: corner bearing (deg) and radius (fraction) wander
PLAN_TOP = 0.35                            # under the ledge the plan softens to this fraction of its wander
# fused stalagmites: (bearing, half-width deg, extra radius at the foot, z where it has merged)
LOBES = [(10.0, 40.0, 2.6, -14.0), (150.0, 28.0, 1.4, -22.0), (262.0, 30.0, 1.8, -18.0)]
# buttress blocks round the foot: sectors of unequal width, each its own height over the pit and its own reach
BLOCK_W = (22.0, 52.0)
BLOCK_H = (1.4, 6.0)
BLOCK_E = (0.9, 2.6)
SHARDS = [(3, 2, 2.6, 2.4), (17, 1, 2.2, 3.1), (34, 2, 1.8, 2.0), (52, 1, 2.8, 3.4), (66, 2, 2.0, 2.2)]  # (line, row, out, up)
# refrozen bulges: (bearing, z, amp, half-width deg, half-height)
BULGES = [(62.0, -27.0, 1.2, 24.0, 3.0), (215.0, -11.0, 0.9, 20.0, 2.4)]
# the heavy flutes, fused organ-pipe icicles on one side: (bearing, proud, z top)
FLUTES = [(318.0, 1.45, -1.5), (352.0, 0.95, -4.0), (27.0, 1.25, -2.5), (61.0, 0.65, -7.0), (196.0, 0.8, -9.0)]
FLUTE_HALF = 11.0                          # a flute's half-width in plan, degrees
NOISE = (0.02, 0.10)                       # lumps, top / foot: small, the planes stay flat
FACET = (0.02, 0.08)                       # per-vertex jitter, top / foot
TWIST = 0.0
TANG_JIT = 0.6                             # degrees of per-vertex wander round the shaft
LEAN = [(-36.8, 0.85, -0.45), (-24.0, 0.30, 0.55), (-12.0, -0.35, 0.20), (-3.0, 0.0, 0.0)]  # axis drift (x, y)

# the frozen ledge under the sill, then eave and dome: (r, z), all jittered
LEDGE = [(None, 1.52), (8.40, 1.88), (8.38, 2.27)]   # root (on the shaft), underside lip, top lip
LEDGE_ROOT = (7.35, 8.05)
LEDGE_RAG = 0.38                           # the ledge's lip wanders this far in and out
PIER_OUT = [0.95, 0.45, 1.25, 0.6, 1.05, 0.4, 0.8, 0.7]   # each pier's buttress, proud of the drum
EAVE = [(DRUM_R, 7.38), (8.45, 7.62), (8.60, 7.92)]
EAVE_RAG = (0.32, 0.22)                    # the eave's lip wanders this far out and up, per line and per bay
DOME = [7.35, 6.0, 4.2, 2.2]               # the dome's rings (radius); heights from the planes below
DOME_PLANES = [(20.0, 0.27), (75.0, 0.36), (128.0, 0.30), (181.0, 0.24), (236.0, 0.33), (290.0, 0.29), (338.0, 0.38)]
DOME_TOP = 10.30
APEX = (0.45, -0.30)
SNOW_LEAN = (300.0, 0.55)                  # the snow cap slumps toward this bearing, its line this much lower there
VAULT = [(5.0, 7.62), (2.6, 7.92)]
VAULT_TOP = 8.02
FLOOR_RINGS = (4.4, 2.0)
SNOW_Z = 8.95                              # the dome's snow line (waves +-0.35)

# icicles: (min, max) length
DRIP_OPEN = (0.30, 0.52)                   # under the eave over an opening: tips stay above 6.85
DRIP_PIER = (1.9, 3.0)                     # under the eave in front of a pier
DRIP_LEDGE = (0.9, 4.2)                    # under the ledge, all round
DRIP_BULGE = (0.6, 1.5)                    # under the shaft's overhangs
BULGE_DRIPS = 34

ICE = (0.80, 0.90, 1.0)
RIDGE = (0.93, 1.0, 1.0)
RECESS = (0.48, 0.62, 0.92)
TROUGH = (0.30, 0.44, 0.80)
LIT = (0.88, 0.97, 1.0)
CORE = (0.70, 0.80, 0.98)
TIP = (0.95, 1.0, 1.0)
WHITE = (1.0, 1.0, 1.0)

SHEETS = {
    "blue": tx.Sheet("blue", stem="ice_blue", ref_r=9.0),
    "floor": tx.Sheet("floor", stem="ice_blue", mode="box"),
    "deep": tx.Sheet("deep", stem="ice_deep", mode="box"),
    "snow": tx.Sheet("snow", stem="ice_snow", mode="box"),
    "icicle": tx.Sheet("icicle", stem="ice_icicle", mode="fit_v", rect=(0.0, 0.5, 1.0, 1.0)),
}

TWO_PI = 2.0 * math.pi
UP, DOWN = (0.0, 0.0, 1.0), (0.0, 0.0, -1.0)


# =============================================================================
# MATH
# =============================================================================

pol = il.pol
_lerp = il.lerp


def _h(i, salt):
    return il.h2(i, salt, SEED)


def _s(i, salt):
    return 2.0 * _h(i, salt) - 1.0


def _mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))


def _scale(c, k):
    return tuple(min(1.0, x * k) for x in c)


def _newell(pts):
    return tuple(il.newell(pts))


def _unit(v):
    return il.unit(v)


# =============================================================================
# MESH -- welding face accumulator, normals stated, colours carried
# =============================================================================

class _Mesh(object):
    WELD = 1.0e-4

    def __init__(self):
        self.verts, self.faces, self.zones, self.groups = [], [], [], []
        self.col = {}
        self.face_col = {}
        self.face_uv = {}
        self._index = {}

    def v(self, p, col=None):
        key = (round(p[0] / self.WELD), round(p[1] / self.WELD), round(p[2] / self.WELD))
        i = self._index.get(key)
        if i is None:
            i = len(self.verts)
            self.verts.append((float(p[0]), float(p[1]), float(p[2])))
            self._index[key] = i
        if col is not None and i not in self.col:
            self.col[i] = col
        return i

    def poly(self, idx, want, zone, col=None):
        """want=None: wound exactly as given."""
        n = _newell([self.verts[j] for j in idx])
        if want is not None and n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        gid = len(self.groups)
        if len(idx) == 4:
            a, b, c, d = (self.verts[j] for j in idx)
            if math.dist(a, c) <= math.dist(b, d):
                tris = [(idx[0], idx[1], idx[2]), (idx[0], idx[2], idx[3])]
            else:
                tris = [(idx[0], idx[1], idx[3]), (idx[1], idx[2], idx[3])]
        else:
            tris = [tuple(idx)]
        for t in tris:
            k = len(self.faces)
            self.faces.append(t)
            self.zones.append(zone)
            self.groups.append(gid)
            if col is not None:
                self.face_col[k] = col

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


def _out(c, up=0.0):
    r = math.hypot(c[0], c[1]) or 1.0
    return (c[0] / r, c[1] / r, up)


def _cen(pts):
    return tuple(sum(p[k] for p in pts) / len(pts) for k in range(3))


# =============================================================================
# THE LINES -- 80 meridians: per bay a jamb, the pier's mid rib, a jamb, seven arch lines
# =============================================================================

def lines():
    """[(bearing, kind, head z)]: kind 'jamb' | 'pier' | 'arch'."""
    out = []
    for k in range(BAYS):
        c = PHASE + 45.0 * k
        out.append((c - 25.0, "jamb", SPRING_Z))
        out.append((c - 22.5, "pier", SPRING_Z))
        out.append((c - 20.0, "jamb", SPRING_Z))
        for s in range(1, ARCH_SEG):
            phi = math.pi * s / ARCH_SEG
            out.append((c - SPAN * 0.5 * math.cos(phi), "arch", SPRING_Z + ARCH_R * math.sin(phi)))
    return out


LINES = lines()
N = len(LINES)
GAP = [min((LINES[i][0] - LINES[i - 1][0]) % 360.0, (LINES[(i + 1) % N][0] - LINES[i][0]) % 360.0) for i in range(N)]


def strip_kind(i):
    """'pier' between a jamb and the pier's rib, else 'open'."""
    return "pier" if "pier" in (LINES[i][1], LINES[(i + 1) % N][1]) else "open"


# =============================================================================
# THE COLUMN -- radius as a field of bearing and height
# =============================================================================

def _taper(z, top, foot):
    return _lerp(foot, top, il.smooth((z - FOOT_Z) / (0.0 - FOOT_Z)))


def _tier(z):
    k = max(0, min(len(PLAN_Z) - 2, sum(1 for t in PLAN_Z[1:-1] if z >= t)))
    return k, max(0.0, min(1.0, (z - PLAN_Z[k]) / (PLAN_Z[k + 1] - PLAN_Z[k])))


def _corners(z):
    """The plan polygon at z: [(bearing, radius factor)], corners wandering tier to tier."""
    k, t = _tier(z)
    out = []
    for c, (b0, f0) in enumerate(zip(PLAN_B, PLAN_F)):
        vals = []
        for tk in (k, k + 1):
            soft = PLAN_TOP if tk == len(PLAN_Z) - 1 else 1.0
            vals.append((b0 + soft * PLAN_WANDER[0] * _s(tk * 17 + c, 50),
                         1.0 + soft * ((f0 - 1.0) + PLAN_WANDER[1] * _s(tk * 17 + c, 51))))
        out.append((_lerp(vals[0][0], vals[1][0], t), _lerp(vals[0][1], vals[1][1], t)))
    return out


def _poly_r(b, corners):
    """Distance from the axis to the polygon's edge along bearing b."""
    n = len(corners)
    for c in range(n):
        b0, f0 = corners[c]
        b1, f1 = corners[(c + 1) % n]
        span = (b1 - b0) % 360.0
        d = (b - b0) % 360.0
        if d <= span:
            a0, a1, ab = math.radians(b0), math.radians(b0 + span), math.radians(b0 + d)
            x0, y0, x1, y1 = f0 * math.cos(a0), f0 * math.sin(a0), f1 * math.cos(a1), f1 * math.sin(a1)
            ex, ey = x1 - x0, y1 - y0
            ux, uy = math.cos(ab), math.sin(ab)
            return (x0 * ey - y0 * ex) / (ux * ey - uy * ex)
    return 1.0


_MEAN = {}


def plan_r(b, z):
    cs = _corners(z)
    key = round(z, 4)
    if key not in _MEAN:
        _MEAN[key] = sum(_poly_r(a * 10.0, cs) for a in range(36)) / 36.0
    return il.interp(SHAFT, z) * _poly_r(b, cs) / _MEAN[key]


def _blocks():
    out, b, k = [], 0.0, 0
    while b < 360.0 - 1e-6:
        w = min(_lerp(BLOCK_W[0], BLOCK_W[1], _h(k, 60)), 360.0 - b)
        out.append((b, b + w, _lerp(BLOCK_H[0], BLOCK_H[1], _h(k, 61)), _lerp(BLOCK_E[0], BLOCK_E[1], _h(k, 62))))
        b += w
        k += 1
    return out


BLOCKS = _blocks()


def block_r(b, z):
    b = b % 360.0
    for (b0, b1, h, e) in BLOCKS:
        if b0 <= b < b1:
            top = PIT_Z + h
            return e * (1.0 - il.ramp(z, top - 0.6, top + 0.5)) * (1.0 - 0.25 * il.ramp(z, PIT_Z, top))
    return 0.0


def shaft_r(b, z):
    """The column's radius at bearing b, height z: the faceted plan, lobes, blocks, bulges."""
    r = plan_r(b, z)
    for (lb, w, amp, zm) in LOBES:
        d = il.angdiff(b, lb) / w
        r += amp * math.exp(-d * d) * (1.0 - il.ramp(z, FOOT_Z, zm))
    for (bb, bz, amp, wb, wz) in BULGES:
        d, e = il.angdiff(b, bb) / wb, (z - bz) / wz
        r += amp * math.exp(-d * d - e * e)
    r += _taper(z, NOISE[0], NOISE[1]) * il.fbm(b / 360.0 * 12.0, z / 3.5, SEED, octaves=3, px=12)
    r += block_r(b, z)
    return r


def axis(z):
    t = [(zz, x) for (zz, x, _y) in LEAN]
    u = [(zz, y) for (zz, _x, y) in LEAN]
    return il.interp(t, z), il.interp(u, z)


def twist(z):
    return TWIST * (1.0 - il.ramp(z, FOOT_Z, -3.0))


def shaft_point(b, r, z, tj=0.0):
    ox, oy = axis(z)
    p = pol(b + twist(z) + tj, r, z)
    return (p[0] + ox, p[1] + oy, z)


def flute(i, z):
    """How proud line i stands on a flute at z: a sharp rib in plan, full to near its top, then it runs out."""
    b = LINES[i][0]
    out = 0.0
    for fb, amp, top in FLUTES:
        d = abs(il.angdiff(b, fb)) / FLUTE_HALF
        if d < 1.0:
            out = max(out, amp * (1.0 - d) ** 1.5 * (1.0 - il.ramp(z, top - 2.5, top + 1.2))
                      * (0.75 + 0.25 * il.ramp(z, PIT_Z, PIT_Z + 6.0)))
    return out


def pier_out(i):
    b, kind, _h0 = LINES[i]
    if kind != "pier":
        return 0.0
    return PIER_OUT[int(round((b - 2.5) / 45.0)) % BAYS]


def dome_z(x, y):
    z = DOME_TOP
    for (pb, slope) in DOME_PLANES:
        d = pol(pb, 1.0, 0.0)
        z = min(z, DOME_TOP - slope * ((x - APEX[0]) * d[0] + (y - APEX[1]) * d[1]))
    return z


# =============================================================================
# PROFILES -- every line the same named rows
# =============================================================================

OUTER = ["s%d" % k for k in range(len(ROWS))] + ["lr", "lu", "lt", "a2", "b", "e0", "e1", "e2"] + \
        ["d%d" % k for k in range(len(DOME))]


def profile(i):
    """{row: (xyz, colour)} for line i."""
    b, kind, head = LINES[i]
    P = {}
    for k, z0 in enumerate(ROWS):
        z = z0
        if 0 < k < len(ROWS) - 1:
            z += ROW_JIT * _s(i * 31 + k, 5) * (0.5 if k < 3 else 1.0)
        r = shaft_r(b, z) + flute(i, z) + _taper(z, *FACET) * _s(i * 31 + k, 8)
        tj = min(TANG_JIT, 0.3 * GAP[i]) * _s(i * 31 + k, 7) * (1.0 - il.ramp(z, -4.0, 0.0))
        p = shaft_point(b, r, z, tj)
        for (li, row, out, up) in SHARDS:
            if li == i and row == k:
                o = _out(p)
                p = (p[0] + out * o[0], p[1] + out * o[1], p[2] + up)
        P["s%d" % k] = (p, LIT)
    # the frozen ledge: rooted in the shaft, a lip, a near-flat top running in to the sill
    zr = LEDGE[0][1] + 0.08 * _s(i, 11)
    rr = min(LEDGE_ROOT[1], max(LEDGE_ROOT[0], shaft_r(b, zr)))
    bo = pier_out(i)
    P["lr"] = (pol(b, rr, zr), TROUGH)
    lbay = int(((b + 17.0) % 360.0) // 30.0)
    rag = LEDGE_RAG * (0.55 * _s(i, 12) + 0.45 * _s(lbay, 65))
    P["lu"] = (pol(b, LEDGE[1][0] + rag + 0.5 * bo, LEDGE[1][1] - 0.5 * abs(rag) + 0.08 * _s(i, 13)), RIDGE)
    P["lt"] = (pol(b, LEDGE[2][0] + rag + 0.08 * _s(i, 14) + 0.5 * bo, LEDGE[2][1] + 0.04 * _s(i, 15)), RIDGE)
    drum = DRUM_R + (0.0 if kind == "jamb" else DRUM_JIT * _s(i, 16))
    P["a2"] = (pol(b, drum + 0.7 * bo, SILL_Z), LIT)
    P["b"] = (pol(b, drum + bo, head), RIDGE)
    bay = int(((b - 5.0) % 360.0) // 45.0)
    rag_r = EAVE_RAG[0] * (0.6 * _s(i, 19) + 0.4 * _s(bay, 63))
    rag_z = EAVE_RAG[1] * (0.6 * _s(i, 20) + 0.4 * _s(bay, 64))
    P["e0"] = (pol(b, EAVE[0][0] + DRUM_JIT * _s(i, 17) + 1.05 * bo, EAVE[0][1] + 0.12 * _s(i, 18)), TROUGH)
    P["e1"] = (pol(b, EAVE[1][0] + rag_r + 0.9 * bo, EAVE[1][1] + rag_z), RIDGE)
    e2 = (pol(b, EAVE[2][0] + rag_r + 0.10 * _s(i, 21) + 0.8 * bo, EAVE[2][1] + rag_z + 0.12 * _s(i, 22)), RIDGE)
    P["e2"] = e2
    zlo = e2[0][2] + 0.18
    for k, r in enumerate(DOME):
        x, y, _z = pol(b, r * (1.0 + 0.03 * _s(i * 7 + k, 23)), 0.0)
        z = max(dome_z(x, y), zlo)
        zlo = z + 0.12
        P["d%d" % k] = ((x, y, z), LIT)
    # the chamber
    P["ai"] = (pol(b, ROOM_R, SILL_Z), CORE)
    P["bi"] = (pol(b, ROOM_R, head), CORE)
    P["ci"] = (pol(b, ROOM_R, CEIL_Z), CORE)
    P["k"] = (pol(b, ROOM_R, FLOOR_Z), CORE)
    for k, (r, z) in enumerate(VAULT):
        P["v%d" % k] = (pol(b, r + 0.15 * _s(i, 26 + k), z + 0.06 * _s(i, 28 + k)), CORE)
    for k, r in enumerate(FLOOR_RINGS):
        P["f%d" % k] = (pol(b + 0.3 * GAP[i] * _s(i, 30 + k), r, FLOOR_Z), ICE)
    return P


def _arrises(prof):
    """Pale cyan on the shaft's convex arrises and rib crests, deep in its troughs: {(line, row): convexity}."""
    cv = {}
    rows = ["s%d" % k for k in range(len(ROWS))] + ["d%d" % k for k in range(len(DOME))]
    for row in rows:
        for i in range(N):
            p = prof[i][row][0]
            a, c = prof[(i - 1) % N][row][0], prof[(i + 1) % N][row][0]
            mid = ((a[0] + c[0]) * 0.5, (a[1] + c[1]) * 0.5)
            o = _out(p)
            v = (p[0] - mid[0]) * o[0] + (p[1] - mid[1]) * o[1]
            if row.startswith("d"):
                v = p[2] - 0.5 * (a[2] + c[2])
            cv[(i, row)] = v
            if v > 0.05:
                tone = _mix(LIT, RIDGE, v / 0.25)
            elif v < -0.05:
                tone = _mix(LIT, TROUGH, -v / 0.35)
            else:
                tone = LIT
            if row.startswith("s"):
                tone = _scale(tone, _lerp(0.82, 1.0, il.ramp(p[2], FOOT_Z, -8.0)))
            prof[i][row] = (p, tone)
    return cv


# =============================================================================
# ICICLES -- grown out of a host quad: a rim in the host's class, a 4-sided cone
# =============================================================================

def _spike(m, corners, tip, host_cls, inset=0.45):
    """corners wound outward; the rim and the cone keep that winding."""
    c = _cen([p for p, _c in corners])
    outer = [m.v(p, col) for p, col in corners]
    inner = [m.v(_mix(p, c, inset), _mix(col, RIDGE, 0.5)) for p, col in corners]
    t = m.v(tip, TIP)
    for k in range(4):
        q = (k + 1) % 4
        m.poly([outer[k], outer[q], inner[q], inner[k]], None, host_cls)
    for k in range(4):
        m.poly([inner[k], inner[(k + 1) % 4], t], None, "icicle")


def _tip_clear(tip, b):
    """Push a tip out of the column if it would stand inside it."""
    r = math.hypot(tip[0], tip[1])
    near = [flute(i, tip[2]) for i in range(N) if abs(il.angdiff(LINES[i][0], b)) < 9.0]
    need = shaft_r(b, tip[2]) + max(near + [0.0]) + 0.25
    if tip[2] > 1.0 or r >= need:
        return tip
    k = need / max(r, 1e-6)
    return (tip[0] * k, tip[1] * k, tip[2])


# =============================================================================
# THE ART MESH
# =============================================================================

def _seg_want(p0, p1, cen):
    """Outward for an outer-skin segment walked up and round: (dz, -dr) in the meridian plane."""
    dr = math.hypot(p1[0], p1[1]) - math.hypot(p0[0], p0[1])
    dz = p1[2] - p0[2]
    o = _out(cen)
    return (o[0] * dz, o[1] * dz, -dr)


def build_art():
    m = _Mesh()
    prof = [profile(i) for i in range(N)]
    cv = _arrises(prof)

    def corners(i, ra, rb):
        """Wound outward for a skin walked up and round (ra below rb)."""
        j = (i + 1) % N
        return [prof[i][rb], prof[j][rb], prof[j][ra], prof[i][ra]]

    def quad(i, ra, rb, want, cls, col=None):
        cs = corners(i, ra, rb)
        m.poly([m.v(p, c) for p, c in cs], want, cls, col)

    def fan(i, row, centre, want, cls, col=None):
        j = (i + 1) % N
        m.poly([m.v(*prof[i][row]), m.v(*prof[j][row]), m.v(*centre)], want, cls, col)

    drips = 0
    for i in range(N):
        kind = strip_kind(i)
        j = (i + 1) % N
        mid_b = 0.5 * (LINES[i][0] + LINES[j][0] + (360.0 if j == 0 else 0.0))
        chain = OUTER
        # the outer skin, foot to the dome's last ring
        for ra, rb in zip(chain, chain[1:]):
            if kind == "open" and (ra, rb) == ("a2", "b"):
                continue
            cs = corners(i, ra, rb)
            pts = [p for p, _c in cs]
            cen = _cen(pts)
            want = _seg_want(_cen([pts[2], pts[3]]), _cen([pts[0], pts[1]]), cen)
            n = _unit(_newell(pts))
            if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
                n = (-n[0], -n[1], -n[2])
            cls, col = "blue", None
            if ra == "lt":
                cls, col = "snow", WHITE
            elif ra.startswith("d") or ra == "e2":
                lean = SNOW_LEAN[1] * math.cos(math.radians(il.angdiff(mid_b, SNOW_LEAN[0])))
                wave = SNOW_Z - lean + 0.25 * math.sin(math.radians(3.0 * mid_b) + 0.7) + 0.15 * _s(i, 40)
                if cen[2] > wave and n[2] > 0.35:
                    cls, col = "snow", WHITE
            elif ra == "e0":
                cls = "deep"
            elif ra in ("lr", "lu"):
                cls = "deep"
            elif ra.startswith("s") and n[2] < -0.35:
                cls = "deep"
            elif ra.startswith("s") and rb.startswith("s") and \
                    cv[(i, ra)] + cv[(j, ra)] + cv[(i, rb)] + cv[(j, rb)] < -0.45:
                cls = "deep"
            elif ra.startswith("s") and cen[2] < PIT_Z + 1.5 and n[2] > 0.72:
                cls, col = "snow", WHITE
            # icicles
            if ra == "e0":
                lo, hi = DRIP_PIER if kind == "pier" else DRIP_OPEN
                L = _lerp(lo, hi, _h(i, 41))
                tip = (cen[0], cen[1], cen[2] - L)
                if kind == "open":
                    tip = (cen[0], cen[1], max(tip[2], SIGHT[2] + 0.05))
                _spike(m, cs, tip, cls, 0.42 if kind == "pier" else 0.35)
                continue
            if ra == "lr" and _h(i, 42) > 0.18:
                L = _lerp(DRIP_LEDGE[0], DRIP_LEDGE[1], _h(i, 43) ** 1.5)
                o = _out(cen)
                tip = _tip_clear((cen[0] + 0.12 * o[0], cen[1] + 0.12 * o[1], cen[2] - L), mid_b)
                _spike(m, cs, tip, "deep", 0.4)
                continue
            if (ra.startswith("s") and ra != "s0" and n[2] < -0.28 and drips < BULGE_DRIPS
                    and _h(i * 37 + chain.index(ra), 44) > 0.35):
                L = _lerp(DRIP_BULGE[0], DRIP_BULGE[1], _h(i * 37 + chain.index(ra), 45))
                o = _out(cen)
                tip = _tip_clear((cen[0] + 0.2 * o[0], cen[1] + 0.2 * o[1], cen[2] - L), mid_b)
                _spike(m, cs, tip, "blue", 0.45)
                drips += 1
                continue
            m.poly([m.v(p, c) for p, c in cs], None, cls, col)
        fan(i, "s0", (axis(FOOT_Z) + (FOOT_Z,), RECESS), DOWN, "deep")
        fan(i, "d%d" % (len(DOME) - 1), ((APEX[0], APEX[1], DOME_TOP), WHITE), UP, "snow", WHITE)
        # the opening: sill, soffit; or the pier's inner face
        inward = _out(pol(mid_b, 1.0, 0.0))
        inward = (-inward[0], -inward[1], 0.0)
        if kind == "open":
            quad(i, "a2", "ai", UP, "blue")
            quad(i, "b", "bi", DOWN, "deep")
            quad(i, "bi", "ci", inward, "deep")
        else:
            quad(i, "ai", "bi", inward, "deep")
            quad(i, "bi", "ci", inward, "deep")
        # the chamber: kerb, floor, vault
        quad(i, "k", "ai", inward, "deep")
        quad(i, "k", "f0", UP, "floor")
        quad(i, "f0", "f1", UP, "floor")
        fan(i, "f1", ((0.0, 0.0, FLOOR_Z), ICE), UP, "floor")
        quad(i, "ci", "v0", DOWN, "deep")
        quad(i, "v0", "v1", DOWN, "deep")
        fan(i, "v1", ((0.0, 0.0, VAULT_TOP), CORE), DOWN, "deep")
    # the jambs: one radial reveal each, facing into its opening
    for i in range(N):
        if LINES[i][1] != "jamb":
            continue
        into = LINES[(i + 1) % N][1] == "arch"
        b = LINES[i][0]
        t = pol(b + (90.0 if into else -90.0), 1.0, 0.0)
        ids = [m.v(*prof[i][r]) for r in ("a2", "b", "bi", "ai")]
        m.poly(ids, (t[0], t[1], 0.0), "deep")
    return m


# =============================================================================
# COLLIDER -- hell's idiom: floor fan, kerb to the sill, a quad per pier, the ceiling;
# nothing over the arches; plus the sill ring and the column
# =============================================================================

def build_collider():
    c = _Mesh()
    n = 24
    zs = [FOOT_Z, -35.0, -32.0, -28.0, -24.0, -20.0, -16.0, -12.0, -8.0, -4.0, 0.0, 1.6]
    rings = []
    for z in zs:
        ring = []
        for k in range(n):
            b = 360.0 * k / n
            ring.append(c.v(shaft_point(b, shaft_r(b, z) - 0.12, z)))
        rings.append(ring)
    lip = [c.v(pol(360.0 * k / n, 8.25, SILL_Z)) for k in range(n)]
    rings.append(lip)
    for a, b_ in zip(rings, rings[1:]):
        for k in range(n):
            q = (k + 1) % n
            ids = [a[k], a[q], b_[q], b_[k]]
            cen = c.centroid(ids)
            p0, p1 = c.verts[a[k]], c.verts[b_[k]]
            c.poly(ids, _seg_want(p0, p1, cen), "c")
    kerb_top = [c.v(pol(360.0 * k / n, ROOM_R, SILL_Z)) for k in range(n)]
    kerb_foot = [c.v(pol(360.0 * k / n, ROOM_R, FLOOR_Z)) for k in range(n)]
    ceil = [c.v(pol(360.0 * k / n, ROOM_R, CEIL_Z)) for k in range(n)]
    fc, cc = c.v((0.0, 0.0, FLOOR_Z)), c.v((0.0, 0.0, CEIL_Z))
    for k in range(n):
        q = (k + 1) % n
        inward = _out(c.centroid([kerb_top[k], kerb_top[q]]))
        inward = (-inward[0], -inward[1], 0.0)
        c.poly([lip[k], lip[q], kerb_top[q], kerb_top[k]], UP, "c")
        c.poly([kerb_top[k], kerb_top[q], kerb_foot[q], kerb_foot[k]], inward, "c")
        c.poly([fc, kerb_foot[k], kerb_foot[q]], UP, "c")
        c.poly([cc, ceil[k], ceil[q]], DOWN, "c")
    for k in range(BAYS):                           # one quad per pier, facing the room
        b0, b1 = 45.0 * k, 45.0 * k + 5.0
        ids = [c.v(pol(b0, ROOM_R, SILL_Z)), c.v(pol(b1, ROOM_R, SILL_Z)),
               c.v(pol(b1, ROOM_R, CEIL_Z)), c.v(pol(b0, ROOM_R, CEIL_Z))]
        o = _out(pol(b0 + 2.5, 1.0, 0.0))
        c.poly(ids, (-o[0], -o[1], 0.0), "c")
    return c


def _centroid(self, ids):
    return _cen([self.verts[i] for i in ids])


_Mesh.centroid = _centroid


# =============================================================================
# AUDIT (pure python) -- components, degenerate, open and doubled edges, the sight rule
# =============================================================================

def audit(m):
    parent = list(range(len(m.verts)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    directed, degen = {}, 0
    for f in m.faces:
        for k in range(3):
            e = (f[k], f[(k + 1) % 3])
            directed[e] = directed.get(e, 0) + 1
            ra, rb = find(e[0]), find(e[1])
            if ra != rb:
                parent[ra] = rb
        n = _newell([m.verts[i] for i in f])
        if math.sqrt(sum(x * x for x in n)) < 1e-7:
            degen += 1
    used = set(i for f in m.faces for i in f)
    comps = len(set(find(i) for i in used))
    boundary = sum(1 for (a, b) in directed if (b, a) not in directed)
    doubled = sum(1 for e, n in directed.items() if n > 1)

    def pier(p):
        b = il.bearing_of(p) % 45.0
        return b <= 5.0 + 1e-6 or b >= 45.0 - 1e-6
    sight = sum(1 for p in m.verts if math.hypot(p[0], p[1]) > SIGHT[0] and SIGHT[1] < p[2] < SIGHT[2]
                and not pier(p))
    return {"components": comps, "degenerate": degen, "boundary": boundary, "doubled": doubled,
            "sight_violations": sight, "tris": len(m.faces), "verts": len(m.verts)}


# =============================================================================
# BLENDER: UVs, vertex colour, materials
# =============================================================================

def _tint_material(mat):
    """Base Color = tile x COLOR_0."""
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
    a_in = [i for i in mix.inputs if i.identifier == "A_Color"][0]
    b_in = [i for i in mix.inputs if i.identifier == "B_Color"][0]
    res = [o for o in mix.outputs if o.identifier == "Result_Color"][0]
    nt.links.new(img.outputs["Color"], a_in)
    nt.links.new(col.outputs["Color"], b_in)
    for sock in dest:
        nt.links.new(res, sock)
    return mat


def _colours(ob, m):
    me = ob.data
    attr = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
    flat = [1.0] * (len(me.loops) * 4)
    for pi, poly in enumerate(me.polygons):
        over = m.face_col.get(pi)
        for li in poly.loop_indices:
            c = over or m.col.get(me.loops[li].vertex_index, (1.0, 1.0, 1.0))
            flat[li * 4:li * 4 + 3] = [c[0], c[1], c[2]]
    attr.data.foreach_set("color", flat)
    me.color_attributes.active_color_index = 0
    me.color_attributes.render_color_index = 0


def build():
    m = build_art()
    c = build_collider()
    ob = m.object(OBJECT_NAME)
    classes = list(m.zones)
    tx.unwrap(ob, classes, SHEETS, seed=4, face_uv=m.face_uv, groups=m.groups)
    _colours(ob, m)
    mats = tx.materials("IceTower", {k: SHEETS[k] for k in set(classes)})
    for mat in mats.values():
        _tint_material(mat)
    order = tx.finish(ob, classes, mats)
    tx.report(SHEETS)
    coll = c.object(COLLIDER_NAME)
    coll.hide_render = True
    a = audit(m)
    print("MDL STATS surfaces=%d order=%s" % (len(order), ",".join(order)))
    print("MDL STATS visual_tris=%d collision_tris=%d components=%d degenerate=%d boundary=%d doubled=%d sight=%d"
          % (a["tris"], len(c.faces), a["components"], a["degenerate"], a["boundary"], a["doubled"],
             a["sight_violations"]))
    return [ob, coll]


def _check():
    m = build_art()
    c = build_collider()
    a = audit(m)
    ca = audit(c)
    zs = [p[2] for p in m.verts]
    rs = [math.hypot(p[0], p[1]) for p in m.verts]
    counts = {}
    for z in m.zones:
        counts[z] = counts.get(z, 0) + 1
    print("art %s z=%.2f..%.2f rmax=%.2f classes=%s" % (a, min(zs), max(zs), max(rs), counts))
    print("coll %s" % ca)
    return (a["components"] == 1 and a["degenerate"] == 0 and a["sight_violations"] == 0
            and a["boundary"] == 0 and a["doubled"] == 0)


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW)
