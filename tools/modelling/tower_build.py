"""tower -- ONE continuous rock, from Ryan's TowerRock, with holes punched in it.

His body is appended from assets/models/tower.blend. His CAP is deleted. The
rock then keeps rising at the body's own width with the body's own wobble and
closes over in a low dome -- no band, no overhang, no horizontal line. The
windows are irregular rounded blobs cut through that wall, splayed to an inner
skin at r 7.0 which is the collision surface.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# The model hangs 37 m below its origin, so mdl's ground plane lands above the
# camera at low elevations and renders a black frame. World light replaces it.
mdl.DEFAULTS["ground"] = False
mdl.DEFAULTS["world_grey"] = 0.30
mdl.DEFAULTS["world_strength"] = 0.90

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "tower"
OBJECT_NAME = "TowerRock"
COLLIDER_NAME = "TowerCollision-colonly"
BLEND_PATH = r"C:\dev\panopticon\assets\models\tower.blend"

FLOOR_Z    = 0.17      # our floor disc, welded to the inner skin
CUT_Z      = -3.00     # every face of his entirely above this is deleted
SILL_Z     = 1.40      # collider lip; jump apex is 1.11, so he cannot leave
BAND_LO    = 0.95      # ring under the openings
BAND_HI    = 5.45      # ring over them -- the lintel
CEIL_Z     = 5.72      # inner ceiling
TOP_Z      = (5.95, 6.55)   # the shoulder, as (z, z) before the dome
R_IN       = 7.00      # inner skin == collision radius
R_BAND     = 7.90      # mean outer radius the room wants
R_REF      = 8.60      # set at build time to the band's real mean radius

DOME       = ((6.95, 0.84), (7.22, 0.58), (7.42, 0.30))
APEX_Z     = 7.50
TOP_MUL    = (0.99, 0.965)  # per shoulder ring

CREEP      = 0.14      # most a ring's MEAN radius may move, m -- inward only
RING_STEP  = 0.20      # his own per-vertex random walk, m/ring
DRIFT_CAP  = 0.34
Z_JAG      = 0.09      # height jitter on the new rings, m
SEED       = 20260912

# Eight openings. Each owns three bearing columns; the fourth is its pier, so
# the pier is a column in its own right and can be far thinner than a window.
N_HOLES   = 8
PIER_W    = (0.72, 1.18)    # stone left between two openings, m
COL_FR    = (0.22, 0.56, 0.22)   # the opening's three columns, of its own arc
COL_JIT   = 0.05
H_HOLE    = (3.32, 3.50)    # opening height at its middle, m
Z_HOLE    = (1.44, 1.52)    # its sill
Z_HOLE_MAX = 5.02
CHAMF_B   = (0.08, 0.18)    # corner eased off the sill -- eye height is 1.65
CHAMF_T   = (0.32, 0.58)    # ...and off the head, where it can be generous
SPL_B     = (0.05, 0.12)    # inner mouth drops this far (middle, corner)
SPL_T     = (0.10, 0.32)    # ...and rises this far: splayed reveals

EYE_H = 1.65
BODY_H = 1.80

SNAP_TOL  = 0.025      # reuse one of his vertices within this of a bearing

# Atlas zones as (u0, v0, u1, v1), matching the packed HellRock atlas.
ZONE_ROCK  = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)
ZONE_CARVE = (0.5, 0.0, 1.0, 0.5)
UV_SCALE = 0.13
UV_PAD = 1.5 / 128.0

TAU = 2.0 * math.pi
NSUB = 32
BEAR = []              # the 32 bearings, ascending, set at build time
Z_IN = ()              # inner ring heights, set at build time
KI_LO, KI_HI = 1, 2
K_FLOOR = K_LO = K_HI = 0      # outer ring indices, set at build time


# =============================================================================
# HELPERS
# =============================================================================

class _Rng(object):
    """Deterministic LCG so the wall is byte-identical every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def f(self):
        return self.n() / float(0x7FFFFFFF)

    def sf(self):
        return self.f() * 2.0 - 1.0

    def i(self, a, b):
        return a + (self.n() >> 12) % (b - a + 1)

    def rng(self, span):
        return span[0] + (span[1] - span[0]) * self.f()

    def shuffle(self, xs):
        for i in range(len(xs) - 1, 0, -1):
            j = self.i(0, i)
            xs[i], xs[j] = xs[j], xs[i]
        return xs


def _bear(co):
    return math.atan2(co.y, co.x) % TAU


def _wrap(a):
    """Signed angle difference folded into (-pi, pi]."""
    return (a + math.pi) % TAU - math.pi


def _newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n.x += (a[1] - b[1]) * (a[2] + b[2])
        n.y += (a[2] - b[2]) * (a[0] + b[0])
        n.z += (a[0] - b[0]) * (a[1] + b[1])
    return n


# =============================================================================
# HIS MESH -- boundary loops, resampling
# =============================================================================

def _boundary_loops(bm):
    """Every open edge loop, as an ordered vertex ring."""
    bedges = [e for e in bm.edges if e.is_boundary]
    adj = {}
    for e in bedges:
        for v in e.verts:
            adj.setdefault(v, []).append(e)
    seen, loops = set(), []
    for e0 in bedges:
        if e0 in seen:
            continue
        seen.add(e0)
        v0 = e0.verts[0]
        loop, e, v = [v0], e0, e0.verts[1]
        while v is not v0:
            loop.append(v)
            nxt = [x for x in adj.get(v, []) if x not in seen]
            if not nxt:
                break
            e = nxt[0]
            seen.add(e)
            v = e.other_vert(v)
        loops.append(loop)
    return loops


def _loop_stats(loop):
    zs = [v.co.z for v in loop]
    rs = [math.hypot(v.co.x, v.co.y) for v in loop]
    return {"n": len(loop), "z0": min(zs), "z1": max(zs), "zm": sum(zs) / len(zs),
            "r0": min(rs), "r1": max(rs), "rm": sum(rs) / len(rs)}


def _order_ccw(loop):
    """Rotate/reverse so bearings increase from index 0."""
    area = 0.0
    for i in range(len(loop)):
        a, b = loop[i].co, loop[(i + 1) % len(loop)].co
        area += a.x * b.y - b.x * a.y
    if area < 0.0:
        loop = list(reversed(loop))
    k = min(range(len(loop)), key=lambda i: _bear(loop[i].co))
    return loop[k:] + loop[:k]


def _edge_between(a, b):
    for e in a.link_edges:
        if e.other_vert(a) is b:
            return e
    return None


def _fac_for_bearing(p0, p1, b):
    """Parameter along p0->p1 whose bearing is b. Linear, exact."""
    s, c = math.sin(b), math.cos(b)
    a0 = p0.x * s - p0.y * c
    d = (p1.x - p0.x) * s - (p1.y - p0.y) * c
    if abs(d) < 1e-9:
        return 0.5
    return -a0 / d


def _resample(loop, bearings, tol=SNAP_TOL):
    """His loop, cut so it has exactly one vertex on each bearing."""
    loop = _order_ccw(loop)
    n = len(loop)
    bl = [_bear(v.co) for v in loop]
    out = [None] * len(bearings)
    used, segs = set(), {}
    for ti, b in enumerate(bearings):
        j = min(range(n), key=lambda k: abs(_wrap(bl[k] - b)))
        if abs(_wrap(bl[j] - b)) < tol and j not in used:
            out[ti] = loop[j]
            used.add(j)
            continue
        hits = [i for i in range(n)
                if (b - bl[i]) % TAU <= (bl[(i + 1) % n] - bl[i]) % TAU]
        if not hits:
            raise SystemExit("MDL ERROR: loop is not star-shaped at %.3f rad" % b)
        segs.setdefault(hits[0], []).append((ti, b))
    for k, items in segs.items():
        items.sort(key=lambda it: (it[1] - bl[k]) % TAU)
        cur, end = loop[k], loop[(k + 1) % n]
        for ti, b in items:
            e = _edge_between(cur, end)
            if e is None:
                raise SystemExit("MDL ERROR: resample lost the edge at %.3f rad" % b)
            f = min(0.92, max(0.08, _fac_for_bearing(cur.co, end.co, b)))
            _e, nv = bmesh.utils.edge_split(e, cur, f)
            out[ti] = nv
            cur = nv
    if any(v is None for v in out):
        raise SystemExit("MDL ERROR: resample left a bearing unfilled")
    return out


# =============================================================================
# FACES
# =============================================================================

NEW = []          # [(BMFace, zone)] -- everything this script adds


def _face(bm, verts, want, zone):
    """A face whose normal is flipped to agree with ``want``."""
    try:
        f = bm.faces.new(verts)
    except ValueError:
        return None
    f.normal_update()
    if f.normal.dot(Vector(want)) < 0.0:
        f.normal_flip()
    NEW.append((f, zone))
    return f


def _rad(a, inward=False):
    return (-math.cos(a), -math.sin(a), 0.0) if inward else (math.cos(a), math.sin(a), 0.0)


# =============================================================================
# THE CONTINUOUS ROCK
# =============================================================================

def _kill_cap(bm):
    """Everything of his above CUT_Z -- deep enough to be off the rim bulge."""
    doomed = [f for f in bm.faces if all(v.co.z > CUT_Z for v in f.verts)]
    n = len(doomed)
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    return n, len(loose)


def _ring_dz(loop):
    """His own ring spacing: loop vertices against their neighbours below."""
    on = set(loop)
    ds = [v.co.z - e.other_vert(v).co.z
          for v in loop for e in v.link_edges if e.other_vert(v) not in on]
    ds = [d for d in ds if 0.10 < d < 6.0]
    return sum(ds) / len(ds) if ds else 1.50


def _ring_zs(z_loop, dz):
    """Ring heights from his cut loop to the dome, at his own spacing."""
    zs = []
    n = max(1, int(round((FLOOR_Z - z_loop) / dz)))
    for k in range(1, n + 1):
        zs.append(z_loop + (FLOOR_Z - z_loop) * k / float(n))
    k_floor = len(zs)
    zs.append(BAND_LO)
    k_lo = len(zs)
    zs.append(BAND_HI)          # no ring inside the band: _band owns that strip
    k_hi = len(zs)
    zs += list(TOP_Z)
    return zs, k_floor, k_lo, k_hi      # indices already allow for rings[0]


def _outer_rings(bm, rim_v, zs, r):
    """His cut loop, continued upward at his own width, closed as a low dome."""
    r_rim = [math.hypot(v.co.x, v.co.y) for v in rim_v]
    tgt = sum(r_rim) / float(NSUB)
    drift = [0.0] * NSUB
    rings = [list(rim_v)]
    rad = [list(r_rim)]
    zed = [[v.co.z for v in rim_v]]
    for k, z0 in enumerate(zs):
        if tgt > R_BAND:                       # inward only -- never widens
            tgt = max(R_BAND, tgt - CREEP)
        want = tgt
        if k >= len(zs) - len(TOP_MUL):
            want = tgt * TOP_MUL[k - (len(zs) - len(TOP_MUL))]
        rr, zz, row = [], [], []
        for i in range(NSUB):
            d = drift[i] + RING_STEP * r.sf()
            drift[i] = max(-DRIFT_CAP, min(DRIFT_CAP, d))
            rr.append(r_rim[i] + drift[i])
        s = want / (sum(rr) / float(NSUB))
        rr = [x * s for x in rr]
        for i in range(NSUB):
            zz.append(z0 + Z_JAG * r.sf())
            row.append(bm.verts.new((rr[i] * math.cos(BEAR[i]),
                                     rr[i] * math.sin(BEAR[i]), zz[i])))
        rings.append(row)
        rad.append(rr)
        zed.append(zz)
    top = rad[-1]
    for z0, mul in DOME:
        row, rr, zz = [], [], []
        for i in range(NSUB):
            rr.append(top[i] * (mul + 0.02 * r.sf()))
            zz.append(z0 + 0.5 * Z_JAG * r.sf())
            row.append(bm.verts.new((rr[i] * math.cos(BEAR[i]),
                                     rr[i] * math.sin(BEAR[i]), zz[i])))
        rings.append(row)
        rad.append(rr)
        zed.append(zz)
    apex = bm.verts.new((0.10 * r.sf(), 0.10 * r.sf(), APEX_Z + 0.06 * r.sf()))
    return rings, rad, zed, apex


def _inner_rings(bm, r):
    """A true prism at R_IN -- the collision surface -- standing on our floor."""
    rings = []
    for z0 in Z_IN:
        row = []
        for i in range(NSUB):
            z = z0 + (0.08 * r.sf() if z0 == CEIL_Z else 0.0)
            row.append(bm.verts.new((R_IN * math.cos(BEAR[i]),
                                     R_IN * math.sin(BEAR[i]), z)))
        rings.append(row)
    return rings


def _seg(beta):
    """Index of the bearing segment ``beta`` falls in, and the fraction along."""
    for i in range(NSUB):
        j = (i + 1) % NSUB
        span = (BEAR[j] - BEAR[i]) % TAU
        d = (beta - BEAR[i]) % TAU
        if d <= span:
            return i, (d / span if span > 1e-9 else 0.0)
    return 0, 0.0


def _wall_r(rad, zed, beta, zeta):
    """Radius of the outer wall at an arbitrary bearing and height."""
    i, f = _seg(beta)
    j = (i + 1) % NSUB
    nk = len(rad)
    rs = [rad[k][i] * (1.0 - f) + rad[k][j] * f for k in range(nk)]
    zs = [zed[k][i] * (1.0 - f) + zed[k][j] * f for k in range(nk)]
    for k in range(nk - 1):
        if zs[k] <= zeta <= zs[k + 1]:
            t = (zeta - zs[k]) / max(1e-6, zs[k + 1] - zs[k])
            return rs[k] * (1.0 - t) + rs[k + 1] * t
    return rs[-1] if zeta > zs[-1] else rs[0]


def _pol(rr, b, z):
    return (rr * math.cos(b), rr * math.sin(b), z)


def _openings(r):
    """Eight openings on the column grid, as outline heights on four bearings.

    ``zb``/``zt`` are the outer mouth, ``zbi``/``zti`` the wider inner one.
    """
    outs = []
    for g in range(N_HOLES):
        c = [(4 * g + k) % NSUB for k in range(4)]
        zb1, zb2 = r.rng(Z_HOLE), r.rng(Z_HOLE)
        zt1 = min(Z_HOLE_MAX, zb1 + r.rng(H_HOLE))
        zt2 = min(Z_HOLE_MAX, zb2 + r.rng(H_HOLE))
        zb = [zb1 + r.rng(CHAMF_B), zb1, zb2, zb2 + r.rng(CHAMF_B)]
        zt = [zt1 - r.rng(CHAMF_T), zt1, zt2, zt2 - r.rng(CHAMF_T)]
        db = [SPL_B[1], SPL_B[0], SPL_B[0], SPL_B[1]]
        dt = [SPL_T[1], SPL_T[0], SPL_T[0], SPL_T[1]]
        outs.append({"g": g, "c": c,
                     "zb": zb, "zt": zt,
                     "zbi": [zb[k] - db[k] for k in range(4)],
                     "zti": [zt[k] + dt[k] for k in range(4)]})
    return outs


def _eye_width(o):
    """Arc the outer mouth spans at eye height, m."""
    def cross(k0, k1):
        z0, z1 = o["zb"][k0], o["zb"][k1]
        b0 = BEAR[o["c"][k0]]
        b1 = b0 + ((BEAR[o["c"][k1]] - b0) % TAU)
        if z0 <= EYE_H:
            return b0
        return b0 + (b1 - b0) * min(1.0, (z0 - EYE_H) / max(1e-6, z0 - z1))
    return ((cross(3, 2) - cross(0, 1)) % TAU) * R_REF


def _band(bm, rings, rad, zed, inner, outs):
    """The opening band: mouth outlines, the stone around them, the reveals."""
    lo, hi = rings[K_LO], rings[K_HI]
    ilo, ihi = inner[KI_LO], inner[KI_HI]
    for o in outs:
        c = o["c"]
        o["vb"] = [bm.verts.new(_pol(_wall_r(rad, zed, BEAR[c[k]], o["zb"][k]),
                                     BEAR[c[k]], o["zb"][k])) for k in range(4)]
        o["vt"] = [bm.verts.new(_pol(_wall_r(rad, zed, BEAR[c[k]], o["zt"][k]),
                                     BEAR[c[k]], o["zt"][k])) for k in range(4)]
        o["ib"] = [bm.verts.new(_pol(R_IN, BEAR[c[k]], o["zbi"][k]))
                   for k in range(4)]
        o["it"] = [bm.verts.new(_pol(R_IN, BEAR[c[k]], o["zti"][k]))
                   for k in range(4)]

    for gi, o in enumerate(outs):
        nx = outs[(gi + 1) % N_HOLES]
        c = o["c"]
        for k in range(3):
            i, j = c[k], c[k + 1]
            mid = BEAR[i] + 0.5 * ((BEAR[j] - BEAR[i]) % TAU)
            _face(bm, [lo[i], lo[j], o["vb"][k + 1], o["vb"][k]],
                  _rad(mid), ZONE_ROCK)
            _face(bm, [o["vt"][k], o["vt"][k + 1], hi[j], hi[i]],
                  _rad(mid), ZONE_ROCK)
            _face(bm, [ilo[i], ilo[j], o["ib"][k + 1], o["ib"][k]],
                  _rad(mid, True), ZONE_SHADE)
            _face(bm, [o["it"][k], o["it"][k + 1], ihi[j], ihi[i]],
                  _rad(mid, True), ZONE_SHADE)

        i, j = c[3], nx["c"][0]                      # the pier, one column wide
        mid = BEAR[i] + 0.5 * ((BEAR[j] - BEAR[i]) % TAU)
        for A, B, C, D, zone, want in (
                (lo[i], lo[j], nx["vb"][0], o["vb"][3], ZONE_ROCK, _rad(mid)),
                (o["vb"][3], nx["vb"][0], nx["vt"][0], o["vt"][3], ZONE_ROCK,
                 _rad(mid)),
                (o["vt"][3], nx["vt"][0], hi[j], hi[i], ZONE_ROCK, _rad(mid)),
                (ilo[i], ilo[j], nx["ib"][0], o["ib"][3], ZONE_SHADE,
                 _rad(mid, True)),
                (o["ib"][3], nx["ib"][0], nx["it"][0], o["it"][3], ZONE_SHADE,
                 _rad(mid, True)),
                (o["it"][3], nx["it"][0], ihi[j], ihi[i], ZONE_SHADE,
                 _rad(mid, True))):
            _face(bm, [A, B, C, D], want, zone)

        O = o["vb"] + [o["vt"][3], o["vt"][2], o["vt"][1], o["vt"][0]]
        I = o["ib"] + [o["it"][3], o["it"][2], o["it"][1], o["it"][0]]
        _reveal(bm, O, I)


def _reveal(bm, outer_ring, inner_ring):
    """Angled rock between the outer mouth and the inner mouth of one hole."""
    n = len(outer_ring)
    cen = Vector((0.0, 0.0, 0.0))
    for v in outer_ring + inner_ring:
        cen += v.co
    cen /= float(2 * n)
    for k in range(n):
        j = (k + 1) % n
        quad = [outer_ring[k], outer_ring[j], inner_ring[j], inner_ring[k]]
        mid = sum((v.co for v in quad), Vector()) / 4.0
        _face(bm, quad, (cen - mid), ZONE_CARVE)


def _skins(bm, rings, rad, zed, apex, inner):
    """Every quad of the wall that a hole does not eat, plus floor and ceiling."""
    for k in range(len(rings) - 1):
        if k == K_LO:
            continue                       # the opening band -- see _band
        for i in range(NSUB):
            j = (i + 1) % NSUB
            mid = BEAR[i] + 0.5 * ((BEAR[j] - BEAR[i]) % TAU)
            _face(bm, [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]],
                  _rad(mid), ZONE_ROCK)
    top = rings[-1]
    for i in range(NSUB):
        j = (i + 1) % NSUB
        _face(bm, [top[i], top[j], apex], (0.0, 0.0, 1.0), ZONE_ROCK)

    for k in range(len(inner) - 1):
        if k == KI_LO:
            continue
        for i in range(NSUB):
            j = (i + 1) % NSUB
            mid = BEAR[i] + 0.5 * ((BEAR[j] - BEAR[i]) % TAU)
            _face(bm, [inner[k][i], inner[k][j], inner[k + 1][j], inner[k + 1][i]],
                  _rad(mid, inward=True), ZONE_SHADE)

    # floor: our own disc at FLOOR_Z, welded to the bottom of the inner skin
    fhub = bm.verts.new((0.0, 0.0, FLOOR_Z))
    flr = inner[0]
    for i in range(NSUB):
        _face(bm, [fhub, flr[i], flr[(i + 1) % NSUB]], (0.0, 0.0, 1.0), ZONE_ROCK)

    # footing: close the gap between that disc's edge and the outer wall
    for i in range(NSUB):
        j = (i + 1) % NSUB
        _face(bm, [flr[i], flr[j], rings[K_FLOOR][j], rings[K_FLOOR][i]],
              (0.0, 0.0, -1.0), ZONE_SHADE)

    # ceiling: a shallow disc over the room, facing down
    hub = bm.verts.new((0.0, 0.0, CEIL_Z + 0.14))
    ceil = inner[-1]
    for i in range(NSUB):
        _face(bm, [hub, ceil[i], ceil[(i + 1) % NSUB]], (0.0, 0.0, -1.0), ZONE_SHADE)


# =============================================================================
# COLLIDER -- floor, a sill all round, rock between the holes, a ceiling
# =============================================================================

def _collider(outs):
    """Piers, a sill all round, the floor and the ceiling. Nothing else."""
    verts, faces = [], []

    def v(p):
        verts.append(tuple(p))
        return len(verts) - 1

    def pt(b, z):
        return (R_IN * math.cos(b), R_IN * math.sin(b), z)

    def emit(idx, want):
        pts = [verts[k] for k in idx]
        if _newell(pts).dot(Vector(want)) < 0.0:
            idx = list(reversed(idx))
        if len(idx) == 4:
            faces.append((idx[0], idx[1], idx[2]))
            faces.append((idx[0], idx[2], idx[3]))
        else:
            faces.append(tuple(idx))

    floor = [v(pt(BEAR[i], FLOOR_Z)) for i in range(NSUB)]
    for i in range(1, NSUB - 1):
        emit([floor[0], floor[i], floor[i + 1]], (0.0, 0.0, 1.0))
    sill = [v(pt(BEAR[i], SILL_Z)) for i in range(NSUB)]
    for i in range(NSUB):
        j = (i + 1) % NSUB
        mid = BEAR[i] + 0.5 * ((BEAR[j] - BEAR[i]) % TAU)
        emit([floor[i], floor[j], sill[j], sill[i]], _rad(mid, inward=True))

    # a pier is the stone from one opening's inner mouth to the next one's
    piers = []
    for h in range(N_HOLES):
        b0 = BEAR[outs[h]["c"][3]]
        b1 = BEAR[outs[(h + 1) % N_HOLES]["c"][0]]
        span = (b1 - b0) % TAU
        piers.append(span * R_REF)
        for k in range(2):
            ba = b0 + span * k / 2.0
            bb = b0 + span * (k + 1) / 2.0
            mid = 0.5 * (ba + bb)
            q = [v(pt(ba, SILL_Z)), v(pt(bb, SILL_Z)),
                 v(pt(bb, CEIL_Z)), v(pt(ba, CEIL_Z))]
            emit(q, _rad(mid, inward=True))

    ceil = [v(pt(BEAR[i], CEIL_Z)) for i in range(NSUB)]
    for i in range(1, NSUB - 1):
        emit([ceil[0], ceil[i], ceil[i + 1]], (0.0, 0.0, -1.0))
    return mdl.mesh(COLLIDER_NAME, verts, faces), piers


# =============================================================================
# UV -- per-face planar projection into that face's zone of the packed atlas
# =============================================================================

def unwrap(ob, zone_by_index, name):
    me = ob.data
    uvl = me.uv_layers.get(name)
    if uvl is None:
        print("MDL note: UV layer %r did not survive bmesh; his atlas is lost" % name)
        uvl = me.uv_layers.new(name=name)
    r = _Rng(SEED + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        zone = zone_by_index.get(pi)
        if zone is None:
            continue
        u0, v0, u1, v1 = zone
        span_u, span_v = (u1 - u0) - 2.0 * UV_PAD, (v1 - v0) - 2.0 * UV_PAD
        nrm = poly.normal
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
        fu = -1.0 if r.i(0, 1) else 1.0
        fv = -1.0 if r.i(0, 1) else 1.0
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        mi, mj = min(c[ii] for c in cos), min(c[jj] for c in cos)
        w = min((max(c[ii] for c in cos) - mi) * UV_SCALE, 1.0)
        h = min((max(c[jj] for c in cos) - mj) * UV_SCALE, 1.0)
        ou, ov = r.f() * (1.0 - w), r.f() * (1.0 - h)
        for li, co in zip(poly.loop_indices, cos):
            s = min(ou + (co[ii] - mi) * UV_SCALE, 1.0)
            t = min(ov + (co[jj] - mj) * UV_SCALE, 1.0)
            if fu < 0.0:
                s = 1.0 - s
            if fv < 0.0:
                t = 1.0 - t
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


# =============================================================================
# HIS BODY
# =============================================================================

def _append_rock():
    with bpy.data.libraries.load(BLEND_PATH, link=False) as (src, dst):
        names = [n for n in src.objects if n == OBJECT_NAME]
        if not names:
            raise SystemExit("MDL ERROR: %s has no object %r (has %s)"
                             % (BLEND_PATH, OBJECT_NAME, list(src.objects)))
        dst.objects = names
    ob = dst.objects[0]
    bpy.context.collection.objects.link(ob)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mat = ob.data.materials[0] if ob.data.materials else None
    if mat is None:
        raise SystemExit("MDL ERROR: %s carries no material" % OBJECT_NAME)
    imgs = []
    if mat.use_nodes:
        for nd in mat.node_tree.nodes:
            if nd.type == "TEX_IMAGE" and nd.image:
                if not nd.image.packed_file:
                    nd.image.pack()
                imgs.append("%s %dx%d" % (nd.image.name, nd.image.size[0],
                                          nd.image.size[1]))
    uvname = ob.data.uv_layers[0].name if ob.data.uv_layers else "UVMap"
    ob.data.calc_loop_triangles()
    zs = [v.co.z for v in ob.data.vertices]
    print("MDL STATS body verts=%d tris=%d z=%.2f..%.2f mat=%s uv=%s tex=[%s]"
          % (len(ob.data.vertices), len(ob.data.loop_triangles),
             min(zs), max(zs), mat.name, uvname, ", ".join(imgs)))
    return ob, mat, uvname


# =============================================================================
# EXTRA RENDERS -- the facade at deck height, and the room from inside
# =============================================================================

OPEN_BEARING = 0.0


def _extra_renders(spec, objects):
    scene = bpy.context.scene
    if spec.get("engine", "eevee").lower() == "cycles":
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = int(spec.get("samples", 24))
        scene.cycles.use_denoising = True
    else:
        scene.render.engine = "BLENDER_EEVEE"
        mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 64)))
        mdl._try(scene.eevee, "use_shadows", True)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")

    world = bpy.data.worlds.new("Hell")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.32, 0.09, 0.07, 1.0)
    bg.inputs[1].default_value = 0.55
    ld = bpy.data.lights.new("KeyRed", type="SUN")
    ld.energy = 3.6
    ld.color = (1.0, 0.36, 0.28)
    key = mdl._link(bpy.data.objects.new("KeyRed", ld))
    key.rotation_euler = (math.radians(-62.0), 0.0, math.radians(35.0))

    target = mdl._link(bpy.data.objects.new("InTarget", None))
    cam = mdl._link(bpy.data.objects.new("InCam", bpy.data.cameras.new("InCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"

    ux, uy = math.cos(OPEN_BEARING), math.sin(OPEN_BEARING)
    out_dir = spec.get("out_dir", ".")

    def shot(nm, loc, tgt, lens, res):
        cam.data.lens = lens
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, nm))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    shot("facade", (ux * 26.0, uy * 26.0, 4.2), (0.0, 0.0, 4.0), 42.0, (1300, 950))

    fl = bpy.data.lights.new("RoomFill", type="POINT")
    fl.energy = 900.0
    fl.color = (1.0, 0.55, 0.40)
    lamp = mdl._link(bpy.data.objects.new("RoomFill", fl))
    lamp.location = (-ux * 1.8, -uy * 1.8, 2.6)
    shot("room", (-ux * 4.6, -uy * 4.6, EYE_H + 0.3), (ux * 24.0, uy * 24.0, 2.4),
         18.0, (1100, 820))
    bpy.data.objects.remove(lamp, do_unlink=True)

    for ob in (cam, target, key):
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    global OPEN_BEARING, NEW, BEAR, Z_IN, R_REF, K_FLOOR, K_LO, K_HI
    NEW = []
    rock, mat, uvname = _append_rock()
    r = _Rng(SEED)

    bm = bmesh.new()
    bm.from_mesh(rock.data)

    n_cap, n_loose = _kill_cap(bm)
    print("MDL STATS cap_faces_removed=%d loose_verts_removed=%d" % (n_cap, n_loose))

    # ---- his open loops: the cut edge, plus any hole he left behind ----------
    loops = _boundary_loops(bm)
    cands = []
    for lp in loops:
        st = _loop_stats(lp)
        print("MDL STATS loop n=%d z=%.2f..%.2f (mean %.2f) r=%.2f..%.2f (mean %.2f)"
              % (st["n"], st["z0"], st["z1"], st["zm"], st["r0"], st["r1"], st["rm"]))
        if st["zm"] > CUT_Z - 5.0 and st["n"] >= 8:
            cands.append(lp)
    if not cands:
        raise SystemExit("MDL ERROR: the cut left no loop to continue from")
    rim = max(cands, key=lambda lp: _loop_stats(lp)["n"])
    strays = [lp for lp in loops if lp is not rim]

    for lp in strays:
        st = _loop_stats(lp)
        vs = set(lp)
        edges = [e for e in bm.edges if e.is_boundary and e.verts[0] in vs
                 and e.verts[1] in vs]
        res = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        made = res.get("faces", [])
        want = Vector((0.0, 0.0, 1.0 if st["zm"] > CUT_Z else -1.0))
        for f in made:
            f.normal_update()
            if f.normal.dot(want) < 0.0:
                f.normal_flip()
            NEW.append((f, ZONE_ROCK))
        print("MDL STATS hole_filled n=%d faces=%d z=%.2f..%.2f"
              % (st["n"], len(made), st["z0"], st["z1"]))

    # ---- 32 bearings: 8 groups of 3 window columns and one pier -------------
    rim = _order_ccw(rim)
    dz = _ring_dz(rim)
    st = _loop_stats(rim)
    zs, K_FLOOR, K_LO, K_HI = _ring_zs(st["zm"], dz)
    Z_IN = (FLOOR_Z, BAND_LO, BAND_HI, CEIL_Z)
    R_REF = max(R_BAND, st["rm"] - CREEP * K_LO) if st["rm"] > R_BAND else st["rm"]

    grp = TAU / N_HOLES
    pw = [r.rng(PIER_W) for _ in range(N_HOLES)]
    BEAR = []
    for g in range(N_HOLES):
        span = grp - pw[g] / R_REF
        fr = [f + COL_JIT * r.sf() for f in COL_FR]
        tot = sum(fr)
        BEAR += [g * grp, g * grp + span * fr[0] / tot,
                 g * grp + span * (fr[0] + fr[1]) / tot, g * grp + span]
    rim_v = _resample(rim, BEAR)
    z_loop = sum(v.co.z for v in rim_v) / float(NSUB)
    print("MDL STATS join z=%.2f his_ring_dz=%.2f r_est=%.2f rings_z=%s"
          % (z_loop, dz, R_REF, ",".join("%.2f" % z for z in zs)))

    rings, rad, zed, apex = _outer_rings(bm, rim_v, zs, r)
    means = [sum(row) / float(NSUB) for row in rad]
    R_REF = sum(means[K_LO:K_HI + 1]) / float(K_HI + 1 - K_LO)
    print("MDL STATS ring_means=%s max_step=%.3f"
          % (",".join("%.2f" % m for m in means[:K_HI + 2]),
             max(abs(means[k + 1] - means[k]) for k in range(K_HI))))

    inner = _inner_rings(bm, r)
    outs = _openings(r)
    _band(bm, rings, rad, zed, inner, outs)
    _skins(bm, rings, rad, zed, apex, inner)

    bm.normal_update()
    bm.faces.index_update()
    zone_by_index = {f.index: z for f, z in NEW}
    n_new = len(NEW)
    bm.to_mesh(rock.data)
    bm.free()

    rock.data.update()
    unwrap(rock, zone_by_index, uvname)
    mdl.finish(rock, mat, flat=True, strip_uvs=False)
    rock.name = OBJECT_NAME
    rock.data.name = OBJECT_NAME

    coll_ob, piers = _collider(outs)
    coll_ob.hide_render = True
    OPEN_BEARING = BEAR[outs[0]["c"][0]] + 0.5 * ((BEAR[outs[0]["c"][3]]
                                                   - BEAR[outs[0]["c"][0]]) % TAU)

    rock.data.calc_loop_triangles()
    coll_ob.data.calc_loop_triangles()
    rr = [x for row in rad for x in row]
    eye = [_eye_width(o) for o in outs]
    wd = [((BEAR[o["c"][3]] - BEAR[o["c"][0]]) % TAU) * R_REF for o in outs]
    ht = [max(o["zt"]) - min(o["zb"]) for o in outs]
    circ = TAU * R_REF
    print("MDL STATS visual_tris=%d collision_tris=%d new_faces=%d sub=%d"
          % (len(rock.data.loop_triangles), len(coll_ob.data.loop_triangles),
             n_new, NSUB))
    print("MDL STATS rings=%d z=%.2f..%.2f..dome..%.2f radius=%.2f..%.2f band_r=%.2f"
          % (len(rings), z_loop, TOP_Z[-1], APEX_Z, min(rr), max(rr), R_REF))
    print("MDL STATS holes=%d w=%.2f..%.2f h=%.2f..%.2f z=%.2f..%.2f"
          % (len(outs), min(wd), max(wd), min(ht), max(ht),
             min(min(o["zb"]) for o in outs), max(max(o["zt"]) for o in outs)))
    print("MDL STATS circ=%.1f open_at_eye=%.1f%% eye_w=%.2f..%.2f "
          "pier=%.2f..%.2f"
          % (circ, 100.0 * sum(eye) / circ, min(eye), max(eye),
             min(piers), max(piers)))
    print("MDL STATS sill=%.2f headroom=%.2f splay=%.2f uv_layers=%d"
          % (SILL_Z - FLOOR_Z, CEIL_Z - BODY_H, SPL_T[0],
             len(rock.data.uv_layers)))
    return [rock, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=0.0, post=_extra_renders)
