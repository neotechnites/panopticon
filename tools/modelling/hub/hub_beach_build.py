"""
PANOPTICON -- hub_beach: wedge 4 of the hub ring (bearings 108..144), dressed
as the beach (Map 4). Not a model of its own: hub_base_build imports THEME
and builds it into the one hub rock. See _Theme in hub_base_build.py.

    the floor shelves from the sand (r 42.2) down 0.32 m to a shallow bottom
        at r 46.4, and runs flat to the wall: dry sand, damp sand, a band of
        foam at the swash, then the turquoise of the shallows
    the dais on "rock": a flat slab of the shore's stone
    the wedge's slice of the outer wall as a bank of beach boulders, its crest
        wandering 4.2..5.8 m, nine lumps bulging into the lobby
    two palms and a boulder on the sand, two rocks standing in the shallows,
        each in its own hole in the floor grid

Every zone is ("beach", <SHEETS class>): the beach map's own tiles, box
projected at texel.MPT. The foam and the water are the one drawn water tile
(white lace on pale) at the shore's foam colour and at the shallows' turquoise.

    python3 tools/modelling/hub/hub_base_build.py --check
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import hub_base_build as hb  # noqa: E402
import beach_lib as bl  # noqa: E402  the beach's own vector helpers and rng
import texel as tx  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

JITTER = 0.045              # floor vertex height wander: sand, not paving

# ---- the shore: the floor shelves into the shallows ------------------------
SHORE = (42.2, 46.4)        # radii the sand's edge and the shelf's bottom stand at
SHELF_Z = -0.32             # how far the bottom lies under the sand
BANDS = ((42.6, "sand"), (45.0, "wet"), (46.2, "foam"))   # a cell's zone by its mean radius; past them, "water"

# ---- the palms, as beach_build grows them ----------------------------------
PALMS = ((114.0, 40.0, 7.6), (118.0, 29.5, 6.3))    # bearing, radius, height
TRUNK_R = (0.42, 0.26)      # base and top radius (beach_build's own)
TRUNK_FOOT = 1.38           # the base ring's flare, where it meets the sand
TRUNK_SEG = 1.05            # metres a trunk ring spans
TRUNK_SIDES = 8
PALM_LEAN = (4.0, 11.0)     # degrees off vertical
CROWN = (0.17, 0.22, 0.42)  # the crown's inner ring radius, its lift, the apex lift
FRONDS = (7, 8)             # of the eight crown quads, this many grow a frond
FROND_L = (2.4, 3.4)
FROND_W = (0.26, 0.36)
FROND_FLAT = 0.3            # a frond's thickness as a fraction of its half width
FROND_SEG = 3
FROND_UP = (0.30, 0.62)     # rise and droop of the frond's arc, as fractions of its length
FROND_DROOP = (0.85, 1.25)
FROND_SOCKET = 0.26         # a frond's root ring: this far in from its crown quad's corners

# ---- boulders: one on the sand, two standing in the shallows ----------------
ROCKS = ((137.0, 34.0, 0.92, 0.82), (132.0, 46.5, 0.70, 0.62), (118.0, 46.0, 0.58, 0.52))
#          bearing, radius, foot radius, height
ROCK_SIDES = 9
ROCK_RINGS = ((0.88, 0.42), (0.58, 0.78), (0.0, 1.0))            # radius and height, as fractions

# ---- the outer wall: a bank of beach boulders -------------------------------
WALL_TOP = (4.2, 5.8)       # the crest wanders between these
WALL_T = 1.3                # over the stock hb.WALL_T
ROWS = (0.7, 1.6, 2.5, 3.4)
MID_ROW = 2                 # the row the two end fans meet at
JAG_R, JAG_Z = 0.30, 0.22   # a sheet vertex's own wander, in and up
BULGE_MAX = 1.9
# bearing, height, half-span along the wall, half-span up, how far it bulges in
BULGE = ((110.0, 1.6, 3.4, 2.1, 1.45), (114.5, 3.0, 2.6, 1.7, 1.10), (117.5, 1.2, 3.0, 1.9, 1.55),
         (122.0, 2.6, 3.2, 2.0, 1.25), (126.0, 1.0, 2.8, 1.6, 1.50), (129.5, 3.1, 3.0, 2.0, 1.15),
         (133.5, 1.5, 3.4, 2.2, 1.60), (137.5, 2.9, 2.6, 1.8, 1.20), (141.5, 1.3, 3.0, 1.9, 1.40))

SEED = 4260118
TWO_PI = 2.0 * math.pi
UP = (0.0, 0.0, 1.0)
DOWN = (0.0, 0.0, -1.0)

# ---- the tiles: beach_build.SHEETS, for the classes this wedge wears ---------
SHEETS = {
    "sand": tx.Sheet("sand", mode="box", roughness=0.95),
    "wet": tx.Sheet("wet", stem="beach_sand", tint=(0.62, 0.60, 0.55), mode="box", roughness=0.8),
    "foam": tx.Sheet("foam", stem="beach_water", tint=(0.75, 0.95, 0.91), mode="box", roughness=0.6),
    "water": tx.Sheet("water", stem="beach_water", tint=(0.34, 0.83, 0.71), mode="box", roughness=0.3),
    "rock": tx.Sheet("rock", mode="box", roughness=0.9),
    "bark": tx.Sheet("bark", stem="beach_wood", tint=(0.589, 0.373, 0.193), mode="box", roughness=0.95),
    "leaf": tx.Sheet("leaf", stem="beach_foliage", mode="box", roughness=0.9),
}


def Z(name):
    assert name in SHEETS, name
    return ("beach", name)


# =============================================================================
# HELPERS -- hub_base_build's pol() convention: (r cos a, r sin a)
# =============================================================================

def _centroid(m, idx):
    n = float(len(idx))
    return tuple(sum(m.verts[j][k] for j in idx) / n for k in range(3))


def _out(c, g):
    """Away from the crown's axis: every face of the crown band is wound by this,
    so the two fronds either side of a rim edge cannot disagree about it."""
    return (g[0] - c[0], g[1] - c[1], 0.0)


def _frame(along):
    """(along, across, up) for a frond: across horizontal, up square to both."""
    a = bl.unit(along)
    across = bl.unit(bl.cross(UP, a)) if abs(a[2]) < 0.99 else (1.0, 0.0, 0.0)
    return a, across, bl.cross(a, across)


def _bez(p0, p1, p2, n):
    out = []
    for k in range(n + 1):
        t = k / float(n)
        s = 1.0 - t
        out.append(tuple(s * s * p0[c] + 2.0 * s * t * p1[c] + t * t * p2[c] for c in range(3)))
    return out


def _loft(m, rings, path, zone):
    """Quads between successive rings of equal count, normals off the axis."""
    for i in range(len(rings) - 1):
        axis = bl.lerp3(path[i], path[i + 1], 0.5)
        n = len(rings[i])
        for s in range(n):
            q = (s + 1) % n
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], bl.sub(_centroid(m, idx), axis), zone)


# =============================================================================
# A BOULDER -- a squat irregular dome, on the sand or standing in the shallows
# =============================================================================

def _shelf(r):
    """The floor's height at radius ``r``: flat sand, then a smooth shelf down."""
    t = min(1.0, max(0.0, (r - SHORE[0]) / (SHORE[1] - SHORE[0])))
    return SHELF_Z * t * t * (3.0 - 2.0 * t)


def _band(r):
    """The zone a floor cell of mean radius ``r`` wears."""
    for (edge, name) in BANDS:
        if r < edge:
            return Z(name)
    return Z("water")


def _rock(m, k, coll=False):
    b, rad, foot_r, h = ROCKS[k]
    rng = bl.Rng(SEED + 311 * (k + 1))
    cx, cy, _ = hb.pol(b, rad)
    z0 = _shelf(rad)
    ph = rng.u(0.0, TWO_PI)
    prev, base = [], None
    for (fr, fz) in ((1.0, 0.0),) + ROCK_RINGS[:-1]:
        ring = [m.v((cx + foot_r * fr * (1.0 + 0.17 * rng.u(-1.0, 1.0)) * math.cos(ph + TWO_PI * s / ROCK_SIDES),
                     cy + foot_r * fr * (1.0 + 0.17 * rng.u(-1.0, 1.0)) * math.sin(ph + TWO_PI * s / ROCK_SIDES),
                     z0 + h * fz)) for s in range(ROCK_SIDES)]
        if base is None:
            base = ring
        else:
            hb._stack(m, prev, ring, cx, cy, Z("rock"))
        prev = ring
    cap = m.v((cx + 0.1 * foot_r * rng.u(-1.0, 1.0), cy + 0.1 * foot_r * rng.u(-1.0, 1.0), z0 + h))
    for s in range(ROCK_SIDES):
        m.tri(prev[s], prev[(s + 1) % ROCK_SIDES], cap, UP, Z("rock"))
    if coll:
        m.fan(base, DOWN, Z("rock"))
    far = max(math.hypot(m.verts[v][0] - cx, m.verts[v][1] - cy) for v in base)
    return (cx, cy, far + hb.HOLE_PAD, base, _band(rad))


# =============================================================================
# A PALM -- a leaning segmented trunk, a crown of drooping fronds
# =============================================================================

class _Palm(object):
    """One palm's axis, so the crown's world centre is known to the UVs."""

    def __init__(self, k):
        b, rad, h = PALMS[k]
        self.rng = bl.Rng(SEED + 733 * (k + 1))
        self.h = h
        self.base = hb.pol(b, rad, _shelf(rad))
        lean = math.radians(self.rng.u(*PALM_LEAN))
        az = self.rng.u(0.0, TWO_PI)
        self.dir = (math.cos(az), math.sin(az))
        self.tilt = lean
        self.crown = self.axis(1.0)

    def axis(self, t):
        bend = math.sin(self.tilt) * self.h * (0.45 * t + 0.55 * t * t)
        return (self.base[0] + self.dir[0] * bend, self.base[1] + self.dir[1] * bend,
                self.base[2] + self.h * t * math.cos(self.tilt * 0.6))


def _palm(m, k, coll=False):
    """Returns the base ring (z 0) the floor hole is zippered to."""
    p = _Palm(k)
    r = p.rng
    n = max(4, int(round(p.h / TRUNK_SEG)))
    rings, centres = [], []
    for s in range(n + 1):
        t = s / float(n)
        c = p.axis(t)
        rad = bl.lerp(TRUNK_R[0], TRUNK_R[1], t) * (TRUNK_FOOT if s == 0 else 1.0)
        rings.append([m.v((c[0] + rad * (1.0 + 0.09 * r.u(-1.0, 1.0)) * math.cos(TWO_PI * j / TRUNK_SIDES + 0.3 * s),
                           c[1] + rad * (1.0 + 0.09 * r.u(-1.0, 1.0)) * math.sin(TWO_PI * j / TRUNK_SIDES + 0.3 * s),
                           c[2])) for j in range(TRUNK_SIDES)])
        centres.append(c)
    for s in range(n):
        hb._stack(m, rings[s], rings[s + 1], 0.5 * (centres[s][0] + centres[s + 1][0]),
                  0.5 * (centres[s][1] + centres[s + 1][1]), Z("bark"))
    if coll:
        m.fan(rings[0], DOWN, Z("bark"))
        m.fan(rings[-1], UP, Z("bark"))
        return rings[0], p
    _crown(m, r, p, rings[-1])
    return rings[0], p


def _crown(m, r, p, ring):
    """The crown over the trunk's top ring: an inner ring lifted inside it, an
    apex, and a frond out of all but one of the ring's quads."""
    c = p.crown
    inner = [m.v((c[0] + CROWN[0] * math.cos(TWO_PI * (s + 0.5) / TRUNK_SIDES),
                  c[1] + CROWN[0] * math.sin(TWO_PI * (s + 0.5) / TRUNK_SIDES), c[2] + CROWN[1]))
             for s in range(TRUNK_SIDES)]
    apex = m.v((c[0], c[1], c[2] + CROWN[2]))
    slots = list(range(TRUNK_SIDES))
    while len(slots) > r.i(*FRONDS):
        slots.pop(r.i(0, len(slots) - 1))
    for s in range(TRUNK_SIDES):
        q = (s + 1) % TRUNK_SIDES
        quad = (ring[s], ring[q], inner[q], inner[s])
        m.tri(apex, inner[s], inner[q], UP, Z("bark"))
        g = _centroid(m, quad)
        if s not in slots:
            m.quad(quad[0], quad[1], quad[2], quad[3], _out(c, g), Z("bark"))
            continue
        _frond(m, r, quad, math.atan2(g[1] - c[1], g[0] - c[0]), c)


def _frond(m, r, quad, az, c):
    """A frond out of a crown quad: a 4-ring inset in the quad (the quad's rim
    bridges to it), a thin flat tube arching up and drooping over, capped."""
    cs = [m.verts[i] for i in quad]
    f = FROND_SOCKET
    root_pts = []
    for (u, v) in ((f, f), (1.0 - f, f), (1.0 - f, 1.0 - f), (f, 1.0 - f)):
        root_pts.append(tuple(((1 - u) * (1 - v)) * cs[0][k] + (u * (1 - v)) * cs[1][k]
                              + (u * v) * cs[2][k] + ((1 - u) * v) * cs[3][k] for k in range(3)))
    root = [m.v(q) for q in root_pts]
    for s in range(4):
        q = (s + 1) % 4
        idx = (quad[s], quad[q], root[q], root[s])
        m.quad(idx[0], idx[1], idx[2], idx[3], _out(c, _centroid(m, idx)), Z("bark"))
    bp = _centroid(m, root)
    az += r.u(-0.18, 0.18)
    L, W = r.u(*FROND_L), r.u(*FROND_W)
    up, droop = r.u(*FROND_UP), r.u(*FROND_DROOP)
    ax, ay = math.cos(az), math.sin(az)
    mid = (bp[0] + ax * L * 0.5, bp[1] + ay * L * 0.5, bp[2] + up * L)
    tip = (bp[0] + ax * L, bp[1] + ay * L, bp[2] + (2.0 * up - droop) * L * 0.5)
    path = _bez(bp, mid, tip, FROND_SEG)
    along, across, high = _frame(bl.sub(path[1], path[0]))
    angs = [math.atan2(bl.dot(bl.sub(q, bp), high), bl.dot(bl.sub(q, bp), across)) for q in root_pts]
    rings = [root]
    for i in range(1, FROND_SEG + 1):
        rad = W * 0.5 * (1.0 - 0.75 * (i - 1) / float(max(1, FROND_SEG - 1)))
        rings.append([m.v((path[i][0] + across[0] * rad * math.cos(t) + high[0] * rad * math.sin(t) * FROND_FLAT,
                           path[i][1] + across[1] * rad * math.cos(t) + high[1] * rad * math.sin(t) * FROND_FLAT,
                           path[i][2] + across[2] * rad * math.cos(t) + high[2] * rad * math.sin(t) * FROND_FLAT))
                      for t in angs])
    _loft(m, rings, path, Z("leaf"))
    m.fan(rings[-1], bl.sub(path[-1], path[-2]), Z("leaf"))


# =============================================================================
# THE THEME
# =============================================================================

class BeachTheme(hb._Theme):
    key = "beach"
    jitter = JITTER
    dais_zone = ("beach", "rock")

    def __init__(self):
        self.palms = []

    # -- the floor -----------------------------------------------------------
    def floor_zone(self, r, a):
        return _band(r)

    def floor_z(self, r, a):
        return _shelf(r)

    def features(self, m, w, coll=False):
        holes = []
        self.palms = []
        for k in range(len(PALMS)):
            base, p = _palm(m, k, coll=coll)
            self.palms.append(p)
            holes.append((p.base[0], p.base[1], TRUNK_R[0] * TRUNK_FOOT + hb.HOLE_PAD, base,
                          _band(PALMS[k][1])))
        for k in range(len(ROCKS)):
            holes.append(_rock(m, k, coll=coll))
        return [] if coll else holes      # the collider: each piece stands closed on its deck

    # -- the wall: a bank of beach boulders ----------------------------------
    def wall_top(self, a):
        f = 0.5 + 0.28 * math.sin(5.0 * a + 0.4) + 0.22 * math.sin(11.0 * a + 2.3)
        return WALL_TOP[0] + (WALL_TOP[1] - WALL_TOP[0]) * min(1.0, max(0.0, f))

    def wall_out(self, a):
        return hb.R_OUT + hb.WALL_T + WALL_T

    def wall_zone(self, am):
        return Z("rock")

    def claims_wall(self):
        return True

    def _bulge(self, a, z):
        """How far the boulder bank stands proud of the wall line at (a, z)."""
        out = 0.0
        for (b, bz, ru, rz, d) in BULGE:
            du = (a - math.radians(b)) * hb.R_OUT
            q = (du / ru) ** 2 + ((z - bz) / rz) ** 2
            if q < 1.0:
                out += d * (1.0 - q) ** 1.5
        return min(BULGE_MAX, out)

    def wall(self, m, J, foot, top_in, top_out, bot_out, cols):
        r = bl.Rng(SEED)
        C = list(J) + [J[-1] + 1]
        V = {}
        for c in C[1:-1]:
            a = cols[c][0]
            col = [foot[c]]
            for z in ROWS:
                rad = hb.R_OUT - self._bulge(a, z) + r.u(-JAG_R, JAG_R)
                col.append(m.v((rad * math.cos(a), rad * math.sin(a), z + r.u(-JAG_Z, JAG_Z))))
            col.append(top_in[c])
            V[c] = col
        rock = Z("rock")
        for j in J:
            jn = j + 1
            am = 0.5 * (cols[j][0] + cols[jn][0])
            want = (-math.cos(am), -math.sin(am), 0.0)
            if j == C[0]:
                _end(m, foot[j], top_in[j], V[jn], want, rock)
            elif jn == C[-1]:
                _end(m, foot[jn], top_in[jn], V[j], want, rock)
            else:
                A, B = V[j], V[jn]
                for k in range(len(A) - 1):
                    m.quad(A[k], B[k], B[k + 1], A[k + 1], want, rock)
            m.quad(top_in[j], top_in[jn], top_out[jn], top_out[j], UP, rock)
            m.quad(top_out[j], top_out[jn], bot_out[jn], bot_out[j], (math.cos(am), math.sin(am), 0.0), rock)

    # -- material: one per beach tile this wedge wears ------------------------
    def images(self):
        return ()               # not None: hub_base_build routes this key's faces to unwrap()

    def materials(self):
        """[(class, material)]: the beach tiles, at the beach's own roughness."""
        out = []
        for cls in sorted(SHEETS):
            sh = SHEETS[cls]
            alb, emi = tx.images("beach", sh)
            out.append((cls, tx.material("Beach_" + cls, alb, emi, sh.roughness, sh.metallic, sh.cull, sh.tint)))
        return out

    def slot_key(self, zone):
        return zone[1]

    def unwrap(self, me, uvl, polys, zone, r):
        """World box projection at texel.MPT; a frond runs its leaf tile's
        midrib down its own length, out of the crown it grew from."""
        sheet = SHEETS[zone[1]]
        for pi in polys:
            poly = me.polygons[pi]
            cos = [tuple(me.vertices[me.loops[li].vertex_index].co) for li in poly.loop_indices]
            uvs = self._frond_uv(cos, sheet) if zone[1] == "leaf" else tx.box_uv(cos, tuple(poly.normal), sheet)
            for li, uv in zip(poly.loop_indices, uvs):
                uvl.data[li].uv = uv

    def _frond_uv(self, cos, sheet):
        """Across and along the frond, out of the crown it grew from: the leaf
        tile's own midrib then runs down its spine."""
        mid = tuple(sum(c[k] for c in cos) / len(cos) for k in range(3))
        c = min((p.crown for p in self.palms), key=lambda q: (q[0] - mid[0]) ** 2 + (q[1] - mid[1]) ** 2)
        d = math.hypot(mid[0] - c[0], mid[1] - c[1]) or 1.0
        ax, ay = (mid[0] - c[0]) / d, (mid[1] - c[1]) / d
        return [(0.5 + (-(co[0] - c[0]) * ay + (co[1] - c[1]) * ax) / sheet.metres_u,
                 ((co[0] - c[0]) * ax + (co[1] - c[1]) * ay) / sheet.metres) for co in cos]


def _end(m, f, t, col, want, zone):
    """The interval against a seam column: that column has only its stock foot
    and top, so the sheet's rows fan to them."""
    for i in range(MID_ROW):
        m.tri(f, col[i], col[i + 1], want, zone)
    m.tri(f, col[MID_ROW], t, want, zone)
    for i in range(MID_ROW, len(col) - 1):
        m.tri(t, col[i], col[i + 1], want, zone)


ZONES = tuple(sorted(SHEETS))
THEME = BeachTheme()
