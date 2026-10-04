"""
PANOPTICON -- ice_tower: Map 4's guard tower, a Lake Michigan pier light encased in ice.
One revolution skin of 72 columns (one per 5 deg mullion): tiered curtains, the lantern and cupola welded on.

    tools/modelling/model build ice_tower
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

if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["ground"] = False

# =============================================================================
# TUNABLES  (local z, origin = the Tower node; the room floor is 1.70)
# =============================================================================

NAME = "ice_tower"
OBJECT_NAME = "IceTower"
COLLIDER_NAME = "IceTowerCollision-colonly"
FACING_YAW = 0.0

WIND_BEARING = 200.0        # windward: the heavy ice faces this bearing
WIND_POWER = 2.6            # how tightly the ice gathers on the windward side
COLS = 72                   # 5 deg columns: a pier (mullion) is one column, an opening eight
PIER_EVERY = 9              # column j is a pier when j % 9 == 0 (bearings 45k..45k+5)

FLOOR_Z, ROOM_R, DRUM_R = 1.70, 6.86, 7.80
SILL_Z, HEAD_Z, CEIL_Z, KERB_Z = 2.35, 7.00, 7.25, 2.95
SIGHT = (7.8, 1.9, 6.5)     # nothing at r > 7.8 between z 1.9 and 6.5

PIT_Z = -36.40              # the pit floor; the mound runs 0.4 below it
MOUND_Z = PIT_Z - 0.40
MOUND_R = (12.6, 4.2)       # skirt radius lee, + windward (+ faceted lobes up to 2.2)
MOUND_H = (1.6, 2.6)        # height over the floor where it meets the shaft, lee, + windward (+ lobes up to 1.0)
SHARDS = (27, 31, 34, 38, 41, 44, 47, 51, 55)   # mound columns that grow a frozen-spray shard, leaning leeward

SHAFT_FOOT = (10.0, PIT_Z)  # the conical riveted shaft, foot ...
CORBEL = [(6.9, -3.5), (7.05, -2.55), (7.45, -1.65), (8.1, -0.95), (8.9, -0.42), (9.6, -0.05)]  # ... and its cove to the deck
DECK_Z, DECK_R = 0.30, 9.6
TOP_LEN = 4.0               # the last metres of steel to the gallery beard's join are sampled densely

# the tiered curtains, bottom up: (lip z, proud, icicle length, extra reach of the rime fingers onto the lee)
TIERS = [(-26.9, 1.5, 3.0, 0.10), (-22.1, 2.0, 4.0, -0.04), (-17.3, 2.4, 4.6, 0.16), (-12.5, 1.8, 3.8, 0.02)]
TIER_C_MIN = 0.5            # in the lee a tier lies flat on the steel, this tall
LEAN = 0.6                  # tan of the icicles' lean off vertical, trailing downwind round the shaft (~31 deg)
BAND_DZ, BAND_H, BAND_PROUD = 2.2, 0.44, 0.12   # the riveted plate bands, over the three lower tiers' lips
PATCHES = ((62.0, 1, 1.1), (328.0, 2, 1.0), (96.0, 3, 0.9))   # (bearing, tier, radius): detached rime on the lee
PORTHOLES = ((2, 0), (5, 1), (3, 2))   # (column, gap above tier): iron-framed portholes in the lee steel
PORTHOLE_R = (0.32, 0.22)
STREAMERS_GALLERY = (28, 30, 32, 48, 50, 52)   # columns: horizontal streamers off the iced rail
STREAMERS_TIER = ((1, 29), (1, 32), (1, 48), (1, 51), (3, 30), (3, 33), (3, 47), (3, 50))   # (tier, column)
STREAMER_LEN = (1.5, 3.0)

CURTAIN_ROOT_Z = -0.10      # the gallery drape hangs from the deck edge
CURTAIN_LEN = (1.5, 7.0)    # lee, + windward (x w^1.3): ~1.5 m lee, ~8.5 windward, toothed
TOOTH = (0.4, 0.2)          # tooth length spread, lee and windward
CURTAIN_T = (0.18, 0.75)    # drape thickness beyond the deck edge, lee, + windward
RAIL_TOP = (1.20, 0.22)     # fringe top lee, + windward (<= 1.45)
FRINGE_IN = (9.25, -0.55)   # fringe inner face radius, lee, + windward
ICE_T = (0.25, 0.85)        # sheathing at the mound's cove: base, + spray swell (x w)

ROOF = [(8.35, 7.85), (7.6, 8.6), (6.2, 9.6), (4.6, 10.45), (3.0, 11.15), (1.9, 11.8), (1.35, 12.35)]                                    # the ogee dome, eave up
ROOF2 = [(0.95, 12.75), (0.6, 13.05)]                     # 24 sides
NECK = [(0.36, 13.2), (0.36, 13.5)]                       # 12 sides
BALL = (14.0, 0.52, (-55.0, -20.0, 18.0, 52.0, 76.0))     # ventilator ball: centre z, radius, latitudes
ROD = [(0.07, 14.58), (0.065, 14.78), (0.025, 16.6)]      # lightning rod, 6 sides
ROD_TIP = 16.85
RIB_COLS = (0, 1)           # a rib over every mullion: columns j % 9 in this set
RIB_H = 0.18
CAP_T = 0.75                # the slumped ice cap over the cupola's windward side ...
CAP_LOBES = (182.5, 227.5)  # ... in two lobes over the windward piers
EAVE_DRIP = 0.75            # eave icicles hang this far below the soffit (stop >= 6.6, in front of the openings)
PIER_ICICLES = {36: 4.6, 45: 4.9}   # pier column: z of a long icicle's tip, in front of the mullion only

SHADE_ICE = (0.82, 0.92, 1.0)
SHADE_DEEP = (0.55, 0.70, 0.92)
SHADE_UNDER = (0.42, 0.55, 0.78)
SHADE_PAINT = (1.0, 0.96, 0.94)
SHADE_ROOM = (0.78, 0.78, 0.8)
SHADE_WINDOW = (0.10, 0.11, 0.13)

ICICLE_U = 5.0              # icicle tile repeats round the drape (~0.05 m a texel at r 9.6)
IRON_TINT = (0.25, 0.27, 0.30)

SHEETS = {
    "paint": tx.Sheet("paint", stem="ice_paint", ref_r=8.0),
    "iron": tx.Sheet("iron", stem="ice_iron", ref_r=8.0, tint=IRON_TINT),
    "plate": tx.Sheet("plate", stem="ice_iron", mode="box", tint=IRON_TINT),   # room floor and ceiling: no swirl at the axis
    "glacier": tx.Sheet("glacier", stem="ice_glacier", ref_r=9.0),
    "blue": tx.Sheet("blue", stem="ice_blue", ref_r=9.0),
    "snow": tx.Sheet("snow", stem="ice_snow", ref_r=9.0),
    "icicle": tx.Sheet("icicle", stem="ice_icicle", mode="custom"),
}

TWO_PI = 2.0 * math.pi
UP, DOWN = (0.0, 0.0, 1.0), (0.0, 0.0, -1.0)


# =============================================================================
# MATH
# =============================================================================

def pol(bearing_deg, r, z):
    a = math.radians(-bearing_deg)
    return (r * math.cos(a), r * math.sin(a), z)


def _lerp(a, b, t):
    return a + (b - a) * t


def _smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def _hash(j, salt):
    x = math.sin(j * 12.9898 + salt * 78.233) * 43758.5453
    return x - math.floor(x)


def _wind(bearing):
    """1 facing the wind, 0 in the lee."""
    phi = math.radians(bearing - WIND_BEARING)
    return ((1.0 + math.cos(phi)) * 0.5) ** WIND_POWER


def _noise(theta, salt):
    return (0.5 * math.cos(3 * theta + 1.3 + salt) + 0.3 * math.cos(7 * theta + 0.4 + 2 * salt)
            + 0.2 * math.cos(11 * theta + 2.1 + 3 * salt))


def _newell(pts):
    nx = ny = nz = 0.0
    for i in range(len(pts)):
        ax, ay, az = pts[i]
        bx, by, bz = pts[(i + 1) % len(pts)]
        nx += (ay - by) * (az + bz)
        ny += (az - bz) * (ax + bx)
        nz += (ax - bx) * (ay + by)
    return (nx, ny, nz)


# =============================================================================
# MESH -- welding face accumulator, normals stated, colours and custom UVs carried
# =============================================================================

class _Mesh(object):
    WELD = 1.0e-4

    def __init__(self):
        self.verts, self.faces, self.zones, self.groups = [], [], [], []
        self.col = {}            # vertex -> rgb
        self.face_col = {}       # triangle -> rgb (overrides)
        self.face_uv = {}        # triangle -> {vertex: uv}
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

    def _emit(self, idx, want, zone, uv=None, col=None):
        n = _newell([self.verts[j] for j in idx])
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        gid = len(self.groups)
        tris = [(idx[0], idx[1], idx[2])] + ([(idx[0], idx[2], idx[3])] if len(idx) == 4 else [])
        for t in tris:
            k = len(self.faces)
            self.faces.append(t)
            self.zones.append(zone)
            self.groups.append(gid)
            if uv is not None:
                self.face_uv[k] = uv
            if col is not None:
                self.face_col[k] = col

    def raw(self, ids, zone, uv=None):
        """A convex polygon fanned in the winding given: a grid's own order, no normal test."""
        gid = len(self.groups)
        for i in range(1, len(ids) - 1):
            t = (ids[0], ids[i], ids[i + 1])
            k = len(self.faces)
            self.faces.append(t)
            self.zones.append(zone)
            self.groups.append(gid)
            if uv:
                self.face_uv[k] = {v: uv[v] for v in t}

    def quad(self, a, b, c, d, want, zone, uv=None, col=None):
        self._emit([a, b, c, d], want, zone, uv, col)

    def tri(self, a, b, c, want, zone, uv=None):
        self._emit([a, b, c], want, zone, uv)

    def centroid(self, ids):
        return tuple(sum(self.verts[i][k] for i in ids) / len(ids) for k in range(3))

    def zipper(self, outer, inner, want_fn, zone):
        """Triangles between two axis-centred rings of any counts, matched by angle."""
        def ang(v):
            p = self.verts[v]
            return math.atan2(p[1], p[0]) % TWO_PI
        O, I = sorted(outer, key=ang), sorted(inner, key=ang)
        aO, aI = [ang(v) for v in O], [ang(v) for v in I]
        i = j = 0
        while i < len(O) or j < len(I):
            no = aO[i + 1] if i + 1 < len(O) else aO[0] + TWO_PI
            ni = aI[j + 1] if j + 1 < len(I) else aI[0] + TWO_PI
            o, n = O[i % len(O)], I[j % len(I)]
            if (i < len(O) and no <= ni) or j >= len(I):
                tri = (o, O[(i + 1) % len(O)], n)
                i += 1
            else:
                tri = (o, I[(j + 1) % len(I)], n)
                j += 1
            self.tri(tri[0], tri[1], tri[2], want_fn(self.centroid(tri)), zone)

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


def _out(c, up=0.0):
    r = math.hypot(c[0], c[1]) or 1.0
    return (c[0] / r, c[1] / r, up)


# =============================================================================
# THE SKIN -- per column one profile, mound to sill; every column the same rows
# =============================================================================

def _shaft_line():
    """The base curve (r, z): shaft foot, the cone, the corbel's cove to the deck edge."""
    return [SHAFT_FOOT] + CORBEL


def _curve_at(s, line):
    """(r, z, nr, nz) at arc length s along a polyline, the outward normal of its segment."""
    for k in range(len(line) - 1):
        (r0, z0), (r1, z1) = line[k], line[k + 1]
        L = math.hypot(r1 - r0, z1 - z0)
        if s <= L or k == len(line) - 2:
            t = min(1.0, max(0.0, s / L))
            return (_lerp(r0, r1, t), _lerp(z0, z1, t), (z1 - z0) / L, -(r1 - r0) / L)
        s -= L
    raise ValueError


def _s_of_z(z, line):
    s = 0.0
    for k in range(len(line) - 1):
        (r0, z0), (r1, z1) = line[k], line[k + 1]
        L = math.hypot(r1 - r0, z1 - z0)
        if z <= z1 or k == len(line) - 2:
            return s + L * min(1.0, max(0.0, (z - z0) / (z1 - z0)))
        s += L
    return s


def _lobe(theta, z, w, salt=0.0):
    """Fluted, wind-sheared lobes: 0..1, troughs low."""
    side = math.sin(math.radians(-math.degrees(theta) - WIND_BEARING))   # which flank: the flutes slant downwind
    th = theta + 0.035 * (0.0 - z) * (1.0 if side >= 0.0 else -1.0) * (0.3 + w)
    v = 0.5 + 0.3 * math.cos(9 * th + 0.7 + salt) + 0.2 * math.cos(17 * th - 0.11 * z + 1.9 + salt)
    return min(1.0, max(0.0, v))


def _cover(bearing):
    """The tiers' coverage: positive on the windward half, zero about 73 deg off the wind."""
    phi = math.radians(bearing - WIND_BEARING)
    return ((1.0 + math.cos(phi)) * 0.5) ** 2 - 0.3


def _patch(bearing, z):
    """Detached rime patches on the lee."""
    f = 0.0
    for (pb, tier, rad) in PATCHES:
        d = ((bearing - pb + 180.0) % 360.0 - 180.0) * math.pi / 180.0 * 8.0
        dz = z - (TIERS[tier][0] - 0.3)
        f += 0.65 * math.exp(-(d * d + dz * dz) / (rad * rad))
    return f


def _steel(line, z, t):
    """(r, z) on the steel at height z, t proud along its normal."""
    r, zz, nr, nz = _curve_at(_s_of_z(z, line), line)
    return r + t * nr, zz + t * nz


def column(j):
    """One column's profile, mound to sill: dicts {p, cls, neg, f, col, v, name}.
    cls/neg: the class of the segment up from the point where the rime field f is >= 0 / < 0."""
    b = 5.0 * j
    a = math.radians(-b)
    er, et = (math.cos(a), math.sin(a)), (-math.sin(a), math.cos(a))
    w = _wind(b)
    dwind = (math.cos(math.radians(-(WIND_BEARING + 180.0))), math.sin(math.radians(-(WIND_BEARING + 180.0))))
    dt = dwind[0] * et[0] + dwind[1] * et[1]                   # downwind, along the tangent
    lean = LEAN * max(-1.0, min(1.0, 2.0 * dt))
    side = 1.0 if dt >= 0.0 else -1.0
    n1 = _noise(a, 0.0)
    line = _shaft_line()
    cov = _cover(b)
    sign = 1.0 if j % 2 == 0 else -1.0
    pts = []

    def P(r, z, cls, col, v=None, tang=0.0, neg=None, f=None, name=None):
        xyz = (r * er[0] + tang * et[0], r * er[1] + tang * et[1], z)
        if f is not None and f < 0.0:
            col = SHADE_PAINT
        pts.append({"p": xyz, "cls": cls, "neg": neg or cls, "f": 1.0 if f is None else f, "col": col, "v": v,
                    "name": name})

    def ice_col(t, lob):
        k = min(1.0, t / 1.2)
        base = tuple(_lerp(SHADE_ICE[c], SHADE_DEEP[c], k * 0.6) for c in range(3))
        f = 0.72 + 0.33 * lob
        return tuple(min(1.0, base[c] * f) for c in range(3))

    dark = tuple(c * 0.48 for c in SHADE_UNDER)

    # ---- the frozen-spray mound: big faceted lobes
    facet = abs(((b / 360.0 * 7.0 + 0.3 * n1) % 1.0) - 0.5) * 2.0          # a triangle wave: flat facets, sharp ridges
    lobeM = 0.6 * facet + 0.4 * (0.5 + 0.5 * _noise(a, 1.7))
    H = MOUND_H[0] + MOUND_H[1] * w + 1.0 * lobeM
    R0 = MOUND_R[0] + MOUND_R[1] * w + 2.2 * lobeM
    z_mt = PIT_Z + H
    lob0 = _lobe(a, z_mt, w)
    t_mt = w ** 1.15 * (ICE_T[0] + ICE_T[1]) * (0.45 + 0.75 * lob0)
    r_mt, _z = _steel(line, z_mt, t_mt)
    P(R0, MOUND_Z, "glacier", SHADE_ICE)
    P(R0 - 0.55, PIT_Z + 0.22, "glacier", (0.9, 0.95, 1.0), name="mound1")
    P(_lerp(r_mt, R0, 0.5 + 0.12 * facet), PIT_Z + H * 0.55, "glacier", (0.78, 0.88, 1.0))
    P(_lerp(r_mt, R0, 0.2), PIT_Z + H * 0.88, "glacier", SHADE_DEEP)

    # ---- the shaft: the mound's cove, then four tiered curtains, three plate bands between them
    fs = cov + 0.04 * n1
    P(r_mt, z_mt, "glacier", ice_col(t_mt, lob0), neg="paint", f=fs + 0.25 * w)
    tiers = []
    for k, (zL, Tm, Cm, reach) in enumerate(TIERS):
        ft = cov + 0.06 * _noise(a, k + 3.0)
        s = _smooth(0.0, 0.35, ft)
        T, C = Tm * s, TIER_C_MIN + (Cm - TIER_C_MIN) * s
        C_t = C * (1.0 + 0.25 * sign * (0.5 + 0.5 * _hash(j, 10 + k)))
        d_o = -0.3 + (0.3 + 0.75 * C) * _smooth(0.6, 1.5, T)
        tiers.append((zL, T, C, C_t, d_o, ft, max(0.0, reach + 0.1 + 0.08 * math.sin(3.1 * k + (1.0 if side > 0 else 2.5)))))
    zA0 = tiers[0][0] - tiers[0][3] + tiers[0][4]
    lowmid = 0.5 * (z_mt + zA0)
    r, z = _steel(line, lowmid, 0.0)
    fl = fs + _patch(b, lowmid)
    t = 0.1 * _smooth(0.0, 0.3, fl) + w ** 1.15 * 0.6 * _smooth(0.0, 0.3, fs)
    r, z = _steel(line, lowmid, t)
    P(r, z, "glacier", ice_col(t, 0.5), neg="paint", f=fl)
    for k, (zL, T, C, C_t, d_o, ft, reach) in enumerate(tiers):
        lob = _lobe(a, zL, 1.0, k)

        def fc(rw, z):
            return ft + reach * rw + _patch(b, z)

        def rime(f):
            return 0.07 * _smooth(0.0, 0.3, f)

        zT = zL - C_t
        zA = zT + d_o
        zU = 0.5 * (zA + zT) - 0.1 * T * _smooth(0.6, 1.5, T)
        zC = zL - 0.45 * C_t
        zS = zL + 0.3 * T + 0.05
        zB = zL + 0.65 * T + 0.1
        rows = ((zA, 0.0, 0.3, "blue", dark, None, 0.0, "A%d" % k),
                (zU, 0.5 * T, 0.5, "blue", SHADE_UNDER, None, 0.5, "U%d" % k),
                (zT, 0.8 * T, 0.6, "icicle", SHADE_DEEP, 0.5, 1.0, "T%d" % k),
                (zC, T * (1.0 + 0.3 * (lob - 0.5)), 0.85, "icicle", ice_col(0.5, lob), 0.775, 0.45, "C%d" % k),
                (zL, T, 1.0, "glacier", SHADE_ICE, 1.0, 0.0, "lip%d" % k),
                (zS, 0.45 * T, 0.8, "snow" if (_noise(a, 5.0 + k) > 0.45 and T > 1.0) else "glacier",
                 (0.95, 0.97, 1.0), None, 0.0, "S%d" % k),
                (zB, 0.0, 0.4, "blue", dark, None, 0.0, "B%d" % k))
        for (zz, off, rw, cls, col, v, frac, name) in rows:
            f = fc(rw, zz)
            r, z = _steel(line, zz, off + rime(f))
            P(r, z, cls, col, v=v, tang=lean * max(0.0, zL - zz) * (frac > 0.0), neg="paint", f=f, name=name)
        if k < len(tiers) - 1:                              # a riveted plate band in the gap above
            zb = zL + BAND_DZ
            for (zz, off, name) in ((zb - 0.5 * BAND_H, 0.0, "s%d" % k), (zb, BAND_PROUD, "p%d" % k),
                                    (zb + 0.5 * BAND_H, 0.0, "e%d" % k)):
                f = cov + 0.04 * n1 + _patch(b, zz)
                r, z = _steel(line, zz, off + 0.1 * _smooth(0.0, 0.3, f))
                P(r, z, "blue", dark, neg="iron" if name[0] in "sp" else "paint", f=f, name=name)

    # ---- the steel above the top tier, up to the gallery beard's join
    L_s = CURTAIN_LEN[0] + CURTAIN_LEN[1] * w ** 1.3
    L = L_s * (1.0 + _lerp(TOOTH[0], TOOTH[1], w) * sign * (0.55 + 0.45 * _hash(j, 1)))
    z_tip = CURTAIN_ROOT_Z - L
    z_join = CURTAIN_ROOT_Z - L_s * (0.45 + 0.5 * w)
    zB3 = tiers[-1][0] + 0.65 * tiers[-1][1] + 0.1
    s_B, s_j = _s_of_z(zB3, line), _s_of_z(z_join, line)
    s_split = max(s_B + 0.5 * (s_j - s_B), s_j - TOP_LEN)
    ss = [s_split] + [_lerp(s_split, s_j, (i + 1) / 3.0) for i in range(3)]
    for k, s in enumerate(ss):
        r, z, nr, nz = _curve_at(s, line)
        lob = _lobe(a, z, w)
        f = cov + 0.04 * n1 + 0.15 * _smooth(z_join - 3.0, z_join, z) + 0.14 * math.sin(1.3 * z + (0.5 if side > 0 else 2.1))
        t = _smooth(0.0, 0.3, f) * w ** 1.15 * (0.2 + 0.9 * _smooth(zB3, z_join, z)) * (0.6 + 0.6 * lob)
        t += 0.08 * _smooth(0.0, 0.3, f)
        cls = "glacier"
        if k == len(ss) - 1:
            P(r + t * nr, z + t * nz, "blue", dark)
        else:
            P(r + t * nr, z + t * nz, cls, ice_col(t, lob), neg="paint", f=f)
    rJ, zJ = math.hypot(pts[-1]["p"][0], pts[-1]["p"][1]), pts[-1]["p"][2]

    # ---- the gallery drape: underside, toothed tips leaning downwind, the curtain up to the iced rail
    t_c = CURTAIN_T[0] + CURTAIN_T[1] * w

    def r_curt(fr):
        z = CURTAIN_ROOT_Z - L * fr
        return DECK_R + t_c * (1.0 - 0.35 * fr) + 0.12 * _noise(a, 4.0 + fr) + 0.5 * w * (_lobe(a, z, w, 2.0) - 0.5)

    rT = r_curt(1.0) - 0.15
    rU = 0.5 * (rJ + rT)
    zU = 0.5 * (zJ + z_tip) - 0.12 * abs(rT - rJ)
    P(rU, zU, "blue", dark, tang=lean * max(0.0, CURTAIN_ROOT_Z - zU))
    drape = [(rT, z_tip, 1.0)] + [(r_curt(f), CURTAIN_ROOT_Z - L * f, f) for f in (0.7, 0.38)]
    drape.append((r_curt(0.0), CURTAIN_ROOT_Z, 0.0))
    z_rt = min(1.45, RAIL_TOP[0] + RAIL_TOP[1] * w + 0.03 * n1)
    r_ro = DECK_R + 0.12 + 0.55 * w
    drape += [(r_curt(0.0) + 0.04, 0.65, 0.0), (r_ro, z_rt, 0.0)]
    total = sum(math.hypot(drape[k + 1][0] - drape[k][0], drape[k + 1][1] - drape[k][1])
                for k in range(len(drape) - 1))
    run = 0.0
    for k, (r, z, frac) in enumerate(drape):
        if k:
            run += math.hypot(r - drape[k - 1][0], z - drape[k - 1][1])
        v = 0.5 + 0.5 * run / total
        col = tuple(_lerp(SHADE_DEEP[c], SHADE_ICE[c] * 1.08, v * 2.0 - 1.0) for c in range(3))
        P(r, z, "icicle", tuple(min(1.0, x) for x in col), v=v, tang=lean * max(0.0, CURTAIN_ROOT_Z - z),
          name="fmid" if k == len(drape) - 2 else None)
    pts[-1]["cls"] = pts[-1]["neg"] = "iron" if w < 0.35 else "snow"        # the rail top, iced or not

    # ---- the gallery: the fringe's inner face, the deck, a cove up the murette
    r_fi = FRINGE_IN[0] + FRINGE_IN[1] * w
    deck_snow = 0.25 * w
    P(r_fi + 0.08, z_rt - 0.06, "glacier" if w > 0.35 else "iron", SHADE_ICE)
    P(r_fi, DECK_Z + 0.08 + deck_snow, "iron" if w < 0.4 else "snow", (0.85, 0.88, 0.92))
    P(DRUM_R + 0.28 + 0.4 * w, DECK_Z + 0.07 + deck_snow * 1.2, "glacier", SHADE_ICE)
    P(DRUM_R + 0.07 + 0.08 * w, DECK_Z + 0.3 + 0.75 * w, "glacier" if w > 0.6 else "paint", SHADE_PAINT)
    P(DRUM_R, DECK_Z + 0.5 + 0.85 * w, "paint", SHADE_PAINT)
    P(DRUM_R, SILL_Z, "paint", SHADE_PAINT)
    return pts


def _prof_want(m, lo, hi):
    """Outward for a profile walked up the outside, solid on the left: (dz, -dr) in the column's plane."""
    p0, p1 = m.centroid(lo), m.centroid(hi)
    dr = math.hypot(p1[0], p1[1]) - math.hypot(p0[0], p0[1])
    dz = p1[2] - p0[2]
    o = _out(m.centroid(lo + hi))
    return (o[0] * dz, o[1] * dz, -dr)


CROSS_COL = (0.9, 0.92, 0.95)


def _poly(m, ids, want, cls, uvs):
    """A sub-polygon of a grid quad, wound outward (the grid order reversed); uvs when the class states its own."""
    m.raw(list(reversed(ids)), cls, uvs)


def _cut_quad(m, corners, want, pos, neg):
    """A quad cut on the rime field's zero line (marching squares): the boundary is its own
    polyline, never the grid. corners: [(id, f, uv)]; a crossing is computed in canonical order."""
    pos_l, neg_l, uv = [], [], {}
    for (i, f, u) in corners:
        if u is not None:
            uv[i] = u
    signs = [f >= 0.0 for (_i, f, _u) in corners]
    for e in range(4):
        (ia, fa, ua), (ib, fb, ub) = corners[e], corners[(e + 1) % 4]
        (pos_l if fa >= 0.0 else neg_l).append(ia)
        if (fa >= 0.0) != (fb >= 0.0):
            (i0, f0, u0), (i1, f1, u1) = sorted(((ia, fa, ua), (ib, fb, ub)), key=lambda c: c[0])
            t = min(0.92, max(0.08, f0 / (f0 - f1)))
            p = tuple(_lerp(m.verts[i0][c], m.verts[i1][c], t) for c in range(3))
            x = m.v(p, CROSS_COL)
            if u0 is not None and u1 is not None:
                uv[x] = (_lerp(u0[0], u1[0], t), _lerp(u0[1], u1[1], t))
            pos_l.append(x)
            neg_l.append(x)
    saddle = signs[0] == signs[2] and signs[1] == signs[3] and signs[0] != signs[1]
    if saddle:                                   # the centre's side is a hexagon, the other two corner triangles
        cp = sum(f for (_i, f, _u) in corners) >= 0.0
        hexa, hcls = (pos_l, pos) if cp else (neg_l, neg)
        tl, tcls = (neg_l, neg) if cp else (pos_l, pos)
        _poly(m, hexa, want, hcls, uv if hcls == "icicle" else None)
        for (i, f, _u) in corners:
            if (f >= 0.0) == cp:
                continue
            x = tl.index(i)
            _poly(m, [tl[x - 1], i, tl[(x + 1) % len(tl)]], want, tcls, uv if tcls == "icicle" else None)
        return
    if len(pos_l) >= 3:
        _poly(m, pos_l, want, pos, uv if pos == "icicle" else None)
    if len(neg_l) >= 3:
        _poly(m, neg_l, want, neg, uv if neg == "icicle" else None)


def _pyramid(m, base, apex, cls, col=None, mid=None):
    """A spike grown out of a quad of the surface: the quad's edges carry it, nothing overlaps."""
    a = m.v(apex, col)
    inner = tuple(_lerp(m.centroid(base)[c], apex[c], 0.3) for c in range(3))
    rings = [list(base)]
    if mid is not None:
        rings.append([m.v(p, col) for p in mid])
    for r0, r1 in zip(rings, rings[1:]):
        for e in range(4):
            q = (e + 1) % 4
            c = m.centroid((r0[e], r0[q], r1[q], r1[e]))
            m.quad(r0[e], r0[q], r1[q], r1[e], tuple(c[d] - inner[d] for d in range(3)), cls)
    last = rings[-1]
    for e in range(4):
        q = (e + 1) % 4
        c = m.centroid((last[e], last[q], a))
        m.tri(last[e], last[q], a, tuple(c[d] - inner[d] for d in range(3)), cls)


def _porthole(m, quad, want):
    """An iron-framed porthole socketed into a steel quad: the quad's corners zip to the frame ring."""
    c = m.centroid(quad)
    n = _out(c)
    t = (-n[1], n[0], 0.0)
    up = (0.0, 0.0, 1.0)

    def ring(rad, d, col):
        return [m.v(tuple(c[x] + rad * (math.cos(TWO_PI * i / 8) * t[x] + math.sin(TWO_PI * i / 8) * up[x])
                          + d * n[x] for x in range(3)), col) for i in range(8)]

    def ang(v):
        p = m.verts[v]
        d = [p[x] - c[x] for x in range(3)]
        return math.atan2(sum(d[x] * up[x] for x in range(3)), sum(d[x] * t[x] for x in range(3)))

    r0 = ring(PORTHOLE_R[0], 0.0, SHADE_PAINT)
    C = sorted(quad, key=ang)                    # corners counter-clockwise; each edge takes the ring vertex
    ks = []                                      # facing its middle, each corner the ring between two edges
    for e in range(4):
        mid = [0.5 * (m.verts[C[e]][x] + m.verts[C[(e + 1) % 4]][x]) for x in range(3)]
        d = [mid[x] - c[x] for x in range(3)]
        am = math.atan2(sum(d[x] * up[x] for x in range(3)), sum(d[x] * t[x] for x in range(3)))
        ks.append(int(round(am / (TWO_PI / 8))) % 8)
    for e in range(4):
        m.tri(C[e], C[(e + 1) % 4], r0[ks[e]], n, "paint")
        i = ks[e]
        while i != ks[(e + 1) % 4]:
            m.tri(C[(e + 1) % 4], r0[(i + 1) % 8], r0[i], n, "paint")
            i = (i + 1) % 8
    r1 = ring(PORTHOLE_R[0], 0.08, (0.9, 0.9, 0.9))
    r2 = ring(PORTHOLE_R[1], 0.08, (0.9, 0.9, 0.9))
    r3 = ring(PORTHOLE_R[1], -0.04, SHADE_WINDOW)
    for (lo, hi, ctr) in ((r0, r1, None), (r1, r2, 1), (r2, r3, None)):
        for e in range(8):
            q = (e + 1) % 8
            cc = m.centroid((lo[e], lo[q], hi[q], hi[e]))
            if ctr:
                w = n
            else:
                d = [cc[x] - c[x] for x in range(3)]
                dd = sum(d[x] * n[x] for x in range(3))
                w = tuple(d[x] - dd * n[x] for x in range(3))
                if lo is r2:
                    w = tuple(-x for x in w)
            m.quad(lo[e], lo[q], hi[q], hi[e], w, "iron")
    g = m.v(tuple(c[x] - 0.04 * n[x] for x in range(3)), SHADE_WINDOW)
    for e in range(8):
        m.tri(r3[e], r3[(e + 1) % 8], g, n, "iron")
        m.face_col[len(m.faces) - 1] = SHADE_WINDOW


def _skin(m):
    cols = [column(j) for j in range(COLS)]
    rows = len(cols[0])
    assert all(len(c) == rows for c in cols)
    names = {p["name"]: k for k, p in enumerate(cols[0]) if p["name"]}
    ids = [[m.v(c[k]["p"], c[k]["col"]) for k in range(rows)] for c in cols]
    special = {}
    for (j, g) in PORTHOLES:
        special[(j, names["B%d" % g])] = ("porthole",)
    for j in STREAMERS_GALLERY:
        special[(j, names["fmid"])] = ("streamer", 0.45, 1.40)
    for (k, j) in STREAMERS_TIER:
        special[(j, names["lip%d" % k])] = ("streamer", 0.5, None)
    for j in SHARDS:
        special[(j, names["mound1"])] = ("shard",)
    dwind = (math.cos(math.radians(-(WIND_BEARING + 180.0))), math.sin(math.radians(-(WIND_BEARING + 180.0))))
    for j in range(COLS):
        q = (j + 1) % COLS
        for k in range(rows - 1):
            a, b, c, d = ids[j][k], ids[q][k], ids[q][k + 1], ids[j][k + 1]
            pa, pb, pc, pd = cols[j][k], cols[q][k], cols[q][k + 1], cols[j][k + 1]
            want = _prof_want(m, (a, b), (d, c))
            sp = special.get((j, k))
            if sp:
                cen = m.centroid((a, b, c, d))
                o = _out(cen)
                et = (-o[1], o[0], 0.0)
                lee = 1.0 if (dwind[0] * et[0] + dwind[1] * et[1]) >= 0.0 else -1.0
                h = _hash(j, 20 + k)
                if sp[0] == "porthole":
                    _porthole(m, (a, b, c, d), want)
                elif sp[0] == "streamer":
                    ln = _lerp(STREAMER_LEN[0], STREAMER_LEN[1], h)
                    ap = [cen[x] + et[x] * lee * ln + o[x] * sp[1] for x in range(3)]
                    ap[2] = cen[2] - 0.1 if sp[2] is None else min(sp[2], cen[2])
                    _pyramid(m, (a, b, c, d), tuple(ap), "glacier", SHADE_ICE)
                else:
                    ap = (cen[0] + dwind[0] * 1.1 + o[0] * 0.4, cen[1] + dwind[1] * 1.1 + o[1] * 0.4,
                          cen[2] + 2.0 + 1.6 * h)
                    _pyramid(m, (a, b, c, d), ap, "glacier", (0.85, 0.93, 1.0))
                continue
            pos, neg = pa["cls"], pa["neg"]
            fs = (pa["f"], pb["f"], pc["f"], pd["f"])
            uvs = None
            if "icicle" in (pos, neg):
                u0, u1 = ICICLE_U * j / COLS, ICICLE_U * (j + 1) / COLS
                if None not in (pa["v"], pb["v"], pc["v"], pd["v"]):
                    uvs = {a: (u0, pa["v"]), b: (u1, pb["v"]), c: (u1, pc["v"]), d: (u0, pd["v"])}
            if None in fs or all(f >= 0.0 for f in fs) or all(f < 0.0 for f in fs):
                cls = pos if (pa["f"] is None or pa["f"] >= 0.0) else neg
                if None not in fs and all(f < 0.0 for f in fs):
                    cls = neg
                if None not in fs and all(f >= 0.0 for f in fs):
                    cls = pos
                if cls == "icicle" and uvs is None:
                    cls = "glacier"
                m.raw([d, c, b, a], cls, uvs if cls == "icicle" else None)
                continue
            if "icicle" in (pos, neg) and uvs is None:
                pos = "glacier" if pos == "icicle" else pos
            _cut_quad(m, [(a, fs[0], uvs and uvs[a]), (b, fs[1], uvs and uvs[b]),
                          (c, fs[2], uvs and uvs[c]), (d, fs[3], uvs and uvs[d])], want, pos, neg)
    return [ids[j][-1] for j in range(COLS)]


def _ring(m, r, z, n=COLS, col=None):
    return [m.v(pol(360.0 * j / n, r, z), col) for j in range(n)]


def _lantern(m):
    O_s = _ring(m, DRUM_R, SILL_Z)
    I_s = _ring(m, ROOM_R, SILL_Z, col=SHADE_ROOM)
    I_f = _ring(m, ROOM_R, FLOOR_Z, col=SHADE_ROOM)
    O_h = _ring(m, DRUM_R, HEAD_Z, col=(0.9, 0.9, 0.92))
    I_h = _ring(m, ROOM_R, HEAD_Z, col=SHADE_ROOM)
    I_c = _ring(m, ROOM_R, CEIL_Z, col=SHADE_ROOM)
    for j in range(COLS):
        q = (j + 1) % COLS
        mid = m.centroid((O_s[j], O_s[q]))
        out, inn = _out(mid), _out(mid)
        inn = (-inn[0], -inn[1], 0.0)
        m.quad(I_f[j], I_f[q], I_s[q], I_s[j], inn, "paint")
        m.quad(I_h[j], I_h[q], I_c[q], I_c[j], inn, "iron")
        if j % PIER_EVERY == 0:
            m.quad(O_s[j], O_s[q], O_h[q], O_h[j], out, "iron")
            m.quad(I_s[j], I_s[q], I_h[q], I_h[j], inn, "iron")
            a0, a1 = math.radians(-5.0 * j), math.radians(-5.0 * (j + 1))
            m.quad(O_s[j], I_s[j], I_h[j], O_h[j], (-math.sin(a0), math.cos(a0), 0.0), "iron")
            m.quad(O_s[q], I_s[q], I_h[q], O_h[q], (math.sin(a1), -math.cos(a1), 0.0), "iron")
        else:
            m.quad(O_s[j], O_s[q], I_s[q], I_s[j], UP, "paint")
            m.quad(O_h[j], O_h[q], I_h[q], I_h[j], DOWN, "iron")
    fc = m.v((0.0, 0.0, FLOOR_Z), SHADE_ROOM)
    cc = m.v((0.0, 0.0, CEIL_Z), SHADE_ROOM)
    for j in range(COLS):
        q = (j + 1) % COLS
        m.tri(fc, I_f[j], I_f[q], UP, "plate")
        m.tri(cc, I_c[j], I_c[q], DOWN, "plate")
    return O_s, O_h


# =============================================================================
# THE CUPOLA -- cornice, windward eave drips, ribbed dome under a slumped cap,
# ventilator ball, lightning rod
# =============================================================================

def _cap_w(bearing):
    """The cupola's ice cap: windward, gathered in two lobes over the windward piers."""
    lobe = max(math.exp(-(((bearing - c + 180.0) % 360.0 - 180.0) / 22.0) ** 2) for c in CAP_LOBES)
    return _wind(bearing) ** 0.6 * (0.3 + 0.7 * lobe)


def _roof(m, O_h):
    rows = []
    for j in range(COLS):
        b = 5.0 * j
        a = math.radians(-b)
        er = (math.cos(a), math.sin(a))
        wc = _cap_w(b)
        iced = wc >= 0.3
        rib = RIB_H if j % PIER_EVERY in RIB_COLS else 0.0
        sign = 1.0 if j % 2 == 0 else -1.0
        z_drip = max(6.6, 7.33 - EAVE_DRIP * wc * (1.0 + 0.25 * sign * (0.5 + 0.5 * _hash(j, 9))))
        prof = [((DRUM_R, 7.25), "blue" if iced else "iron", (0.8, 0.8, 0.85), None),                 # the soffit
                ((8.25 + 0.15 * wc, z_drip), "icicle" if iced else "iron", SHADE_UNDER, 0.5),       # the drip / fascia
                ((8.6 + 0.35 * wc + rib * 0.6, 7.62 + 0.12 * wc), "glacier" if iced else "iron", SHADE_ICE, 1.0)]
        n = len(ROOF)
        for k, (r, z) in enumerate(ROOF):
            r0, z0 = ROOF[max(0, k - 1)]
            r1, z1 = ROOF[min(n - 1, k + 1)]
            tl = math.hypot(r1 - r0, z1 - z0)
            nr, nz = (z1 - z0) / tl, -(r1 - r0) / tl
            if nz < 0:
                nr, nz = -nr, -nz
            f = k / float(n - 1)
            t = CAP_T * wc * math.sin(math.pi * min(1.0, f * 1.2 + 0.15)) * (0.75 + 0.5 * _lobe(a, z, wc, 1.0))
            cls = "iron"
            if iced and t > 0.12:
                cls = "snow" if (k >= 4 and wc > 0.75) else "glacier"
            col = SHADE_ICE if cls != "iron" else (0.9, 0.9, 0.95)
            t += rib * (1.0 - 0.6 * f)
            prof.append(((r + t * nr, z + t * nz - 0.15 * t * wc), cls, col, None))
        rows.append([(m.v((r * er[0], r * er[1], z), col), cls, v) for ((r, z), cls, col, v) in prof])
    nrow = len(rows[0])
    for j in range(COLS):
        q = (j + 1) % COLS
        for k in range(-1, nrow - 1):
            lo_j = O_h[j] if k < 0 else rows[j][k][0]
            lo_q = O_h[q] if k < 0 else rows[q][k][0]
            hi_j, hi_q = rows[j][k + 1][0], rows[q][k + 1][0]
            cls = "iron" if k < 0 else rows[j][k][1]
            want = _prof_want(m, (lo_j, lo_q), (hi_j, hi_q))
            if k == 1 and j in PIER_ICICLES:          # a long icicle off the cap, over a pier only
                z_end = PIER_ICICLES[j]
                bc = 5.0 * j + 2.5
                apex = pol(bc, 8.3, z_end)
                base = (lo_j, lo_q, hi_q, hi_j)
                zm = 0.5 * (min(m.verts[x][2] for x in base) + z_end) + 0.4
                mid = [tuple(_lerp(m.verts[x][c], pol(bc, 8.35, zm)[c], 0.55) for c in range(3)) for x in base]
                mid = [(p[0], p[1], min(p[2], zm + 0.25)) for p in mid]
                _pyramid(m, base, apex, "glacier", SHADE_DEEP, mid=mid)
                continue
            uv = None
            if cls == "icicle":
                u0, u1 = ICICLE_U * j / COLS, ICICLE_U * (j + 1) / COLS
                uv = {lo_j: (u0, rows[j][k][2]), lo_q: (u1, rows[q][k][2]),
                      hi_q: (u1, rows[q][k + 1][2]), hi_j: (u0, rows[j][k + 1][2])}
            m.quad(lo_j, lo_q, hi_q, hi_j, want, cls, uv)
    last = [rows[j][-1][0] for j in range(COLS)]

    def roofwant(c):
        return _out(c, 1.2)

    prev = last
    for (r, z), n in [(ROOF2[0], 24), (ROOF2[1], 24)]:
        ring = []
        for i in range(n):
            b = 360.0 * i / n
            t = 0.25 * _cap_w(b) * (1.0 if r > 0.8 else 0.5)
            ring.append(m.v(pol(b, r + 0.3 * t, z + t), (0.9, 0.9, 0.95)))
        if len(prev) != n:
            m.zipper(prev, ring, roofwant, "iron")
        else:
            _band(m, prev, ring, "iron", 1.0)
        prev = ring
    neck0 = _ring(m, NECK[0][0], NECK[0][1], 12, (0.8, 0.8, 0.85))
    m.zipper(prev, neck0, roofwant, "iron")
    neck1 = _ring(m, NECK[1][0], NECK[1][1], 12, (0.8, 0.8, 0.85))
    _band(m, neck0, neck1, "iron", 0.0)
    prev = neck1
    cz, R, lats = BALL
    for lat in lats:
        ring = _ring(m, R * math.cos(math.radians(lat)), cz + R * math.sin(math.radians(lat)), 12, (0.9, 0.9, 0.95))
        _band(m, prev, ring, "iron", 0.0, centre=(0.0, 0.0, cz))
        prev = ring
    rod = _ring(m, ROD[0][0], ROD[0][1], 6, (0.8, 0.8, 0.85))
    m.zipper(prev, rod, roofwant, "iron")
    prev = rod
    for (r, z) in ROD[1:]:
        ring = _ring(m, r, z, 6, (0.8, 0.8, 0.85))
        _band(m, prev, ring, "iron", 0.0)
        prev = ring
    tip = m.v((0.0, 0.0, ROD_TIP), (0.8, 0.8, 0.85))
    for i in range(6):
        m.tri(prev[i], prev[(i + 1) % 6], tip, _out(m.centroid((prev[i], prev[(i + 1) % 6], tip)), 0.3), "iron")


def _band(m, lo, hi, cls, up=0.0, centre=None):
    """Quads between two rings of one count, oriented by the profile rule."""
    n = len(lo)
    for i in range(n):
        q = (i + 1) % n
        m.quad(lo[i], lo[q], hi[q], hi[i], _prof_want(m, (lo[i], lo[q]), (hi[i], hi[q])), cls)


def build_art():
    m = _Mesh()
    top = _skin(m)
    O_s, O_h = _lantern(m)
    assert set(top) == set(O_s), "the murette's top is the lantern's sill ring"
    _roof(m, O_h)
    return m


# =============================================================================
# COLLIDER -- purpose-built, coarse: mound, shaft, drape, gallery, kerb, floor,
# a quad per pier, the ceiling; nothing over the openings
# =============================================================================

def build_collider():
    c = _Mesh()
    n = 24
    profs = []
    for i in range(n):
        b = 360.0 * i / n
        a = math.radians(-b)
        w = _wind(b)
        line = _shaft_line()
        H = MOUND_H[0] + MOUND_H[1] * w + 0.5 * _noise(a, 0.0)
        R0 = MOUND_R[0] + MOUND_R[1] * w + 0.9 * _noise(a, 1.7)
        L_s = CURTAIN_LEN[0] + CURTAIN_LEN[1] * w ** 1.3
        z_join = CURTAIN_ROOT_Z - L_s * (0.45 + 0.5 * w)
        z_mt = PIT_Z + H
        rb, zb, _a, _b = _curve_at(_s_of_z(z_mt, line), line)
        rj, zj, nr, nz = _curve_at(_s_of_z(z_join, line), line)
        tj = w ** 1.15 * (ICE_T[0] + ICE_T[1] * 0.9)
        t_c = CURTAIN_T[0] + CURTAIN_T[1] * w
        z_rt = min(1.45, RAIL_TOP[0] + RAIL_TOP[1] * w)
        r_fi = FRINGE_IN[0] + FRINGE_IN[1] * w
        rt, zt, _c, _d = _curve_at(_s_of_z(-19.0, line), line)
        prof = [(R0, MOUND_Z), (_lerp(rb, R0, 0.4), PIT_Z + H * 0.6), (rb + w * 0.6, zb), (rt + 2.0 * w, zt),
                (rj + tj * nr, zj + tj * nz), (DECK_R + t_c * 0.65, CURTAIN_ROOT_Z - L_s),
                (DECK_R + t_c, CURTAIN_ROOT_Z), (DECK_R + 0.12 + 0.55 * w, z_rt), (r_fi, z_rt),
                (r_fi, DECK_Z), (DRUM_R, DECK_Z), (DRUM_R, KERB_Z), (ROOM_R, KERB_Z), (ROOM_R, FLOOR_Z)]
        profs.append([c.v(pol(b, r, z)) for (r, z) in prof])
    rows = len(profs[0])
    for i in range(n):
        q = (i + 1) % n
        for k in range(rows - 1):
            ids = (profs[i][k], profs[q][k], profs[i][k + 1], profs[q][k + 1])
            cen = c.centroid(ids)
            p0, p1 = c.verts[profs[i][k]], c.verts[profs[i][k + 1]]
            dr = math.hypot(p1[0], p1[1]) - math.hypot(p0[0], p0[1])
            dz = p1[2] - p0[2]
            nr, nz = dz, -dr                      # profile walks up and round: outward is (dz, -dr)
            o = _out(cen)
            want = (o[0] * nr, o[1] * nr, nz)
            c.quad(profs[i][k], profs[q][k], profs[q][k + 1], profs[i][k + 1], want, "c")
    fc = c.v((0.0, 0.0, FLOOR_Z))
    cc = c.v((0.0, 0.0, CEIL_Z))
    ceil = [c.v(pol(360.0 * i / n, ROOM_R, CEIL_Z)) for i in range(n)]
    for i in range(n):
        q = (i + 1) % n
        c.tri(fc, profs[i][-1], profs[q][-1], UP, "c")
        c.tri(cc, ceil[i], ceil[q], DOWN, "c")
    for k in range(8):                              # one quad per pier, facing the room
        b0, b1 = 45.0 * k, 45.0 * k + 5.0
        ids = [c.v(pol(b0, ROOM_R, KERB_Z)), c.v(pol(b1, ROOM_R, KERB_Z)),
               c.v(pol(b1, ROOM_R, CEIL_Z)), c.v(pol(b0, ROOM_R, CEIL_Z))]
        o = _out(pol(b0 + 2.5, 1.0, 0.0))
        c.quad(ids[0], ids[1], ids[2], ids[3], (-o[0], -o[1], 0.0), "c")
    return c


# =============================================================================
# AUDIT (pure python) -- components, degenerate, duplicate positions, sight rule
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
        b = math.degrees(-math.atan2(p[1], p[0])) % 45.0
        return b <= 5.0 + 1e-6 or b >= 45.0 - 1e-6
    sight = sum(1 for p in m.verts if math.hypot(p[0], p[1]) > SIGHT[0] + 1e-3 and SIGHT[1] < p[2] < SIGHT[2]
                and not pier(p))
    return {"components": comps, "degenerate": degen, "boundary": boundary, "doubled": doubled,
            "sight_violations": sight, "tris": len(m.faces), "verts": len(m.verts)}


# =============================================================================
# BLENDER: UVs, vertex colour, materials, renders
# =============================================================================

def _tint_material(mat):
    """Base Color = tile (x factor) x COLOR_0."""
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


def _render(spec, objects):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    mdl._try(scene.eevee, "taa_render_samples", 16)
    mdl._try(scene.view_settings, "view_transform", "Standard")
    world = bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.42, 0.47, 0.55, 1.0)
    bg.inputs[1].default_value = 0.8
    sd = bpy.data.lights.new("Sun", type="SUN")
    sd.energy = 2.6
    sun = mdl._link(bpy.data.objects.new("Sun", sd))
    sun.rotation_euler = (math.radians(55.0), 0.0, math.radians(-120.0))
    bpy.ops.mesh.primitive_plane_add(size=160.0, location=(0.0, 0.0, PIT_Z))
    floor = bpy.context.active_object
    floor.data.materials.append(mdl.flat_material("PitFloor", (0.30, 0.34, 0.40, 1.0)))
    target = mdl._link(bpy.data.objects.new("ShotTarget", None))
    cam = mdl._link(bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam")))
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    scene.camera = cam
    out_dir = spec.get("out_dir", ".")
    small = bool(spec.get("preview"))

    def shot(name, loc, tgt, lens, res):
        cam.data.lens = lens
        cam.location = loc
        target.location = tgt
        k = 0.6 if small else 1.0
        scene.render.resolution_x, scene.render.resolution_y = int(res[0] * k), int(res[1] * k)
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s_%s.png" % (NAME, name))

    for nm, b in (("lane_windward", WIND_BEARING), ("lane_lee", WIND_BEARING + 180.0),
                  ("lane_flank_e", WIND_BEARING - 90.0), ("lane_flank_w", WIND_BEARING + 90.0)):
        shot(nm, pol(b, 50.0, -0.7), (0.0, 0.0, -12.0), 24.0, (1000, 1300))
    shot("gallery_windward", pol(WIND_BEARING + 25.0, 24.0, 4.0), (0.0, 0.0, 2.0), 30.0, (1300, 1000))
    shot("gallery_lee", pol(WIND_BEARING + 205.0, 24.0, 4.0), (0.0, 0.0, 2.0), 30.0, (1300, 1000))
    shot("lane_lantern", pol(WIND_BEARING + 30.0, 50.0, -0.7), (0.0, 0.0, 4.0), 50.0, (1000, 1000))
    shot("far", pol(WIND_BEARING + 50.0, 95.0, 8.0), (0.0, 0.0, -11.0), 35.0, (1000, 1300))
    shot("room", pol(WIND_BEARING, 3.0, FLOOR_Z + 1.65), pol(WIND_BEARING + 180.0, 6.0, FLOOR_Z + 1.2), 16.0, (1300, 900))
    for ob in (target, cam, sun, floor):
        bpy.data.objects.remove(ob, do_unlink=True)


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
    return a["components"] == 1 and a["degenerate"] == 0 and a["sight_violations"] == 0


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_render)
