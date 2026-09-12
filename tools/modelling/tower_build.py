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

FLOOR_Z    = 0.17      # his floor disc
CUT_Z      = 5.00      # every face entirely above this is his old cap: deleted
SILL_Z     = 1.40      # collider lip; jump apex is 1.11, so he cannot leave
CEIL_Z     = 5.60      # inner ceiling
R_REF      = 8.00      # radius the arc widths below are quoted at

# Outer rings above his rim, then the dome as (z, radius multiplier).
Z_OUT      = (1.30, 2.20, 3.40, 4.95, 5.60, 6.10)
TAPER      = (1.00, 1.00, 1.00, 1.00, 0.995, 0.96)         # per Z_OUT ring
DOME       = ((6.60, 0.86), (7.00, 0.62), (7.30, 0.32))
APEX_Z     = 7.50
K_LO, K_HI = 1, 4      # ring indices the holes are cut between (1.30 .. 4.95)

Z_IN       = (FLOOR_Z, 1.30, 4.95, CEIL_Z)
KI_LO, KI_HI = 1, 2

RING_STEP  = 0.20      # random walk per ring, m
DRIFT_CAP  = 0.34      # never systematically wider or narrower than his rim
Z_JAG      = 0.09      # height jitter on the new rings, m
SEED       = 20260912

N_HOLES   = 7
SPANS     = (4, 4, 4, 4, 3, 3, 3)      # bearing steps each hole is cut across
GAPS      = (1, 1, 1, 1, 1, 1, 1)      # rock between them
MARGIN    = (0.55, 0.95)    # rock left inside the span, each side, m
MARGIN_FAT = (1.20, 1.60)   # ...except twice, which is where the wall is wide
W_CLAMP   = (3.60, 5.00)    # hole width, m
H_HOLE    = (2.90, 3.30)    # hole height, m
Z_HOLE    = (1.45, 1.62)    # hole bottom, m -- above the sill
Z_HOLE_MAX = 4.70           # ...and its top stays under the 4.95 ring
BLOB_JAG  = 0.14            # per-vertex radial wobble of a hole outline
SPLAY     = 0.78            # inner mouth is this much of the outer: angled reveals

EYE_H = 1.65
BODY_H = 1.80

SNAP_TOL  = 0.065      # reuse one of his vertices within this of a bearing

# Atlas zones as (u0, v0, u1, v1), matching the packed HellRock atlas.
ZONE_ROCK  = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)
ZONE_CARVE = (0.5, 0.0, 1.0, 0.5)
UV_SCALE = 0.13
UV_PAD = 1.5 / 128.0

TAU = 2.0 * math.pi
NSUB = 32              # set from his rim loop at build time
BEAR = []              # his rim's own bearings, ascending


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


def _outline(loop):
    """His loop as plain (x, y) -- it has to outlive the bmesh."""
    return [(v.co.x, v.co.y) for v in _order_ccw(loop)]


def _radius_at(pts, theta):
    """Radius of a closed outline at ``theta`` -- a point ON his own edge."""
    bl = [math.atan2(y, x) % TAU for x, y in pts]
    n = len(pts)
    for i in range(n):
        if (theta - bl[i]) % TAU <= (bl[(i + 1) % n] - bl[i]) % TAU:
            p0, p1 = Vector(pts[i] + (0.0,)), Vector(pts[(i + 1) % n] + (0.0,))
            f = min(1.0, max(0.0, _fac_for_bearing(p0, p1, theta)))
            p = p0 + (p1 - p0) * f
            return math.hypot(p.x, p.y)
    return math.hypot(*pts[0])


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


def _facew(bm, verts, zone):
    """A face whose winding is already right -- do not second-guess it."""
    try:
        f = bm.faces.new(verts)
    except ValueError:
        return None
    f.normal_update()
    NEW.append((f, zone))
    return f


def _rad(a, inward=False):
    return (-math.cos(a), -math.sin(a), 0.0) if inward else (math.cos(a), math.sin(a), 0.0)


# =============================================================================
# THE CONTINUOUS ROCK
# =============================================================================

def _kill_cap(bm):
    """Everything of his above CUT_Z: the hat, its underside and his ceiling."""
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


def _outer_rings(bm, rim_v, r):
    """His rim, continued upward at his own width, then closed as a low dome."""
    r_rim = [math.hypot(v.co.x, v.co.y) for v in rim_v]
    drift = [0.0] * NSUB
    rings = [list(rim_v)]
    rad = [list(r_rim)]
    zed = [[v.co.z for v in rim_v]]
    for z0 in Z_OUT:
        row, rr, zz = [], [], []
        for i in range(NSUB):
            d = drift[i] + RING_STEP * r.sf()
            drift[i] = max(-DRIFT_CAP, min(DRIFT_CAP, d))
            rr.append((r_rim[i] + drift[i]) * TAPER[len(rings) - 1])
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


def _inner_rings(bm, flr_v, rfun, r):
    """A true prism at r 7.0 -- the collision surface -- on his floor's edge."""
    rings = [list(flr_v)]
    for z0 in Z_IN[1:]:
        row = []
        for i in range(NSUB):
            rr = rfun(BEAR[i])
            z = z0 + (0.10 * r.sf() if z0 == CEIL_Z else 0.0)
            row.append(bm.verts.new((rr * math.cos(BEAR[i]),
                                     rr * math.sin(BEAR[i]), z)))
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
    nk = len(Z_OUT) + 1
    rs = [rad[k][i] * (1.0 - f) + rad[k][j] * f for k in range(nk)]
    zs = [zed[k][i] * (1.0 - f) + zed[k][j] * f for k in range(nk)]
    for k in range(nk - 1):
        if zs[k] <= zeta <= zs[k + 1]:
            t = (zeta - zs[k]) / max(1e-6, zs[k + 1] - zs[k])
            return rs[k] * (1.0 - t) + rs[k + 1] * t
    return rs[-1] if zeta > zs[-1] else rs[0]


def _layout(r):
    """Eight holes round the tower: irregular widths, irregular spacing."""
    spans = r.shuffle(list(SPANS))
    gaps = r.shuffle(list(GAPS))
    fat = set()
    while len(fat) < 2:
        fat.add(r.i(0, N_HOLES - 1))
    holes, at = [], r.i(0, NSUB - 1)
    for h in range(N_HOLES):
        holes.append({"a": at % NSUB, "span": spans[h], "fat": h in fat})
        at += spans[h] + gaps[h]
    return holes


def _blob(rad, zed, hole, r):
    """One rounded, irregular opening as (bearing, height) around its centre."""
    a, span = hole["a"], hole["span"]
    b = (a + span) % NSUB
    ba, bb = BEAR[a], BEAR[a] + ((BEAR[b] - BEAR[a]) % TAU)
    uc = 0.5 * (ba + bb)
    marg = r.rng(MARGIN_FAT if hole["fat"] else MARGIN)
    w = max(W_CLAMP[0], min(W_CLAMP[1], (bb - ba) * R_REF - 2.0 * marg))
    z0 = r.rng(Z_HOLE)
    hgt = min(r.rng(H_HOLE), Z_HOLE_MAX - z0)
    zc = z0 + 0.5 * hgt
    n = 7 + r.i(0, 1)
    ph0 = TAU * r.f()
    out = []
    for k in range(n):
        phi = ph0 + TAU * k / n + (TAU / n) * 0.26 * r.sf()
        s = 1.0 + BLOB_JAG * r.sf()
        du = 0.5 * w * s * math.cos(phi)
        dz = 0.5 * hgt * s * math.sin(phi)
        out.append((uc + du / R_REF, zc + dz))
    hole.update({"b": b, "w": w, "h": hgt, "z0": zc - 0.5 * hgt, "uc": uc,
                 "ring": out, "n": n})
    return hole


def _bridge(bm, O, PO, I, PI, zone, flip):
    """Fill the annulus between boundary O and hole outline I with triangles.

    Both loops are given in the wall's own (arc, height) chart, where a CCW
    winding is an outward normal; ``flip`` turns that round for the inner skin.
    """
    def ccw(L, P):
        a = sum(P[k][0] * P[(k + 1) % len(P)][1] - P[(k + 1) % len(P)][0] * P[k][1]
                for k in range(len(P)))
        return (L, P) if a >= 0.0 else (L[::-1], P[::-1])

    O, PO = ccw(O, PO)
    I, PI = ccw(I, PI)
    cx = sum(p[0] for p in PI) / len(PI)
    cy = sum(p[1] for p in PI) / len(PI)
    ang = lambda p: math.atan2(p[1] - cy, p[0] - cx)      # noqa: E731
    aO, aI = [ang(p) for p in PO], [ang(p) for p in PI]
    m, n = len(O), len(I)
    j0 = min(range(n), key=lambda k: abs(_wrap(aI[k] - aO[0])))
    I, aI = I[j0:] + I[:j0], aI[j0:] + aI[:j0]

    def cum(a):
        t = [0.0]
        for k in range(len(a)):
            t.append(t[-1] + (a[(k + 1) % len(a)] - a[k]) % TAU)
        return t

    tO, tI = cum(aO), cum(aI)
    ci = cj = 0
    while ci < m or cj < n:
        to = tO[ci + 1] if ci < m else 1e9
        ti = tI[cj + 1] if cj < n else 1e9
        if to <= ti:
            tri = [O[ci], O[(ci + 1) % m], I[cj % n]]
            ci += 1
        else:
            tri = [O[ci % m], I[(cj + 1) % n], I[cj % n]]
            cj += 1
        _facew(bm, tri[::-1] if flip else tri, zone)


def _patch(bm, rings, rad, zed, hole, r):
    """Cut one hole out of the outer wall and return its outline verts."""
    a, span = hole["a"], hole["span"]
    idx = [(a + k) % NSUB for k in range(span + 1)]
    ub = [BEAR[a] + ((BEAR[i] - BEAR[a]) % TAU) for i in idx]
    ub[0] = BEAR[a]

    O, PO = [], []

    def add(k, t):
        O.append(rings[k][idx[t]])
        PO.append((ub[t] * R_REF, zed[k][idx[t]]))

    for t in range(span + 1):
        add(K_LO, t)
    for k in range(K_LO + 1, K_HI + 1):
        add(k, span)
    for t in range(span - 1, -1, -1):
        add(K_HI, t)
    for k in range(K_HI - 1, K_LO, -1):
        add(k, 0)

    I, PI = [], []
    for beta, zeta in hole["ring"]:
        rr = _wall_r(rad, zed, beta % TAU, zeta)
        I.append(bm.verts.new((rr * math.cos(beta), rr * math.sin(beta), zeta)))
        PI.append((beta * R_REF, zeta))
    _bridge(bm, O, PO, I, PI, ZONE_ROCK, False)
    return I


def _patch_in(bm, rings, hole, rfun):
    """The same hole in the inner skin, smaller, so every reveal is splayed."""
    a, span = hole["a"], hole["span"]
    idx = [(a + k) % NSUB for k in range(span + 1)]
    ub = [BEAR[a] + ((BEAR[i] - BEAR[a]) % TAU) for i in idx]
    O, PO = [], []

    def add(k, t):
        O.append(rings[k][idx[t]])
        PO.append((ub[t] * R_REF, Z_IN[k]))

    for t in range(span + 1):
        add(KI_LO, t)
    for t in range(span, -1, -1):
        add(KI_HI, t)
    uc, zc = hole["uc"], hole["z0"] + 0.5 * hole["h"]
    I, PI = [], []
    for beta, zeta in hole["ring"]:
        bi = uc + (beta - uc) * SPLAY
        zi = zc + (zeta - zc) * SPLAY
        rr = rfun(bi % TAU)
        I.append(bm.verts.new((rr * math.cos(bi), rr * math.sin(bi), zi)))
        PI.append((bi * R_REF, zi))
    _bridge(bm, O, PO, I, PI, ZONE_SHADE, True)
    return I


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


def _skins(bm, rings, rad, zed, apex, inner, holes, rfun):
    """Every quad of the wall that a hole does not eat, plus floor and ceiling."""
    cut = {}
    for h in holes:
        for k in range(h["span"]):
            cut[(h["a"] + k) % NSUB] = h
    nk = len(Z_OUT) + 1
    for k in range(len(rings) - 1):
        for i in range(NSUB):
            j = (i + 1) % NSUB
            if K_LO <= k < K_HI and i in cut:
                continue
            mid = BEAR[i] + 0.5 * ((BEAR[j] - BEAR[i]) % TAU)
            _face(bm, [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]],
                  _rad(mid), ZONE_ROCK)
    top = rings[-1]
    for i in range(NSUB):
        j = (i + 1) % NSUB
        _face(bm, [top[i], top[j], apex], (0.0, 0.0, 1.0), ZONE_ROCK)

    for k in range(len(inner) - 1):
        for i in range(NSUB):
            j = (i + 1) % NSUB
            if KI_LO <= k < KI_HI and i in cut:
                continue
            mid = BEAR[i] + 0.5 * ((BEAR[j] - BEAR[i]) % TAU)
            _face(bm, [inner[k][i], inner[k][j], inner[k + 1][j], inner[k + 1][i]],
                  _rad(mid, inward=True), ZONE_SHADE)

    # footing: close the gap between his floor's edge and his rim
    for i in range(NSUB):
        j = (i + 1) % NSUB
        _face(bm, [inner[0][i], inner[0][j], rings[0][j], rings[0][i]],
              (0.0, 0.0, -1.0), ZONE_SHADE)

    # ceiling: a shallow disc over the room, facing down
    hub = bm.verts.new((0.0, 0.0, CEIL_Z + 0.14))
    ceil = inner[-1]
    for i in range(NSUB):
        _face(bm, [hub, ceil[i], ceil[(i + 1) % NSUB]], (0.0, 0.0, -1.0), ZONE_SHADE)
    return nk


# =============================================================================
# COLLIDER -- floor, a sill all round, rock between the holes, a ceiling
# =============================================================================

def _collider(holes, rfun):
    verts, faces = [], []

    def v(p):
        verts.append(tuple(p))
        return len(verts) - 1

    def pt(i, z):
        rr = rfun(BEAR[i])
        return (rr * math.cos(BEAR[i]), rr * math.sin(BEAR[i]), z)

    def emit(idx, want):
        pts = [verts[k] for k in idx]
        if _newell(pts).dot(Vector(want)) < 0.0:
            idx = list(reversed(idx))
        if len(idx) == 4:
            faces.append((idx[0], idx[1], idx[2]))
            faces.append((idx[0], idx[2], idx[3]))
        else:
            faces.append(tuple(idx))

    cut = set()
    for h in holes:
        for k in range(h["span"]):
            cut.add((h["a"] + k) % NSUB)

    floor = [v(pt(i, FLOOR_Z)) for i in range(NSUB)]
    for i in range(1, NSUB - 1):
        emit([floor[0], floor[i], floor[i + 1]], (0.0, 0.0, 1.0))
    sill = [v(pt(i, SILL_Z)) for i in range(NSUB)]
    for i in range(NSUB):
        j = (i + 1) % NSUB
        mid = BEAR[i] + 0.5 * ((BEAR[j] - BEAR[i]) % TAU)
        emit([floor[i], floor[j], sill[j], sill[i]], _rad(mid, inward=True))
    for i in range(NSUB):
        if i in cut:
            continue
        j = (i + 1) % NSUB
        mid = BEAR[i] + 0.5 * ((BEAR[j] - BEAR[i]) % TAU)
        q = [v(pt(i, SILL_Z)), v(pt(j, SILL_Z)), v(pt(j, CEIL_Z)), v(pt(i, CEIL_Z))]
        emit(q, _rad(mid, inward=True))
    ceil = [v(pt(i, CEIL_Z)) for i in range(NSUB)]
    for i in range(1, NSUB - 1):
        emit([ceil[0], ceil[i], ceil[i + 1]], (0.0, 0.0, -1.0))
    return mdl.mesh(COLLIDER_NAME, verts, faces)


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
    global OPEN_BEARING, NEW, NSUB, BEAR
    NEW = []
    rock, mat, uvname = _append_rock()
    r = _Rng(SEED)

    bm = bmesh.new()
    bm.from_mesh(rock.data)

    n_cap, n_loose = _kill_cap(bm)
    print("MDL STATS cap_faces_removed=%d loose_verts_removed=%d" % (n_cap, n_loose))

    # ---- his open loops: rim, floor, and any hole he left behind -------------
    loops = _boundary_loops(bm)
    low, strays = [], []
    for lp in loops:
        st = _loop_stats(lp)
        print("MDL STATS loop n=%d z=%.2f..%.2f (mean %.2f) r=%.2f..%.2f (mean %.2f)"
              % (st["n"], st["z0"], st["z1"], st["zm"], st["r0"], st["r1"], st["rm"]))
        (low if st["zm"] < 2.0 else strays).append(lp)
    low.sort(key=lambda lp: _loop_stats(lp)["rm"])
    if len(low) < 2:
        raise SystemExit("MDL ERROR: expected his rim and his floor loop")
    rim, floor = low[-1], low[-2]
    strays += low[:-2]

    for lp in strays:
        st = _loop_stats(lp)
        vs = set(lp)
        edges = [e for e in bm.edges if e.is_boundary and e.verts[0] in vs
                 and e.verts[1] in vs]
        res = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        made = res.get("faces", [])
        want = Vector((0.0, 0.0, 1.0 if st["zm"] > 3.0 else -1.0))
        for f in made:
            f.normal_update()
            if f.normal.dot(want) < 0.0:
                f.normal_flip()
            NEW.append((f, ZONE_ROCK))
        print("MDL STATS hole_filled n=%d faces=%d z=%.2f..%.2f"
              % (st["n"], len(made), st["z0"], st["z1"]))

    # ---- one bearing set: his rim's own corners -----------------------------
    rim = _order_ccw(rim)
    NSUB = len(rim)
    BEAR = [_bear(v.co) for v in rim]
    rim_v = list(rim)
    flr_v = _resample(floor, BEAR)
    outline = _outline(floor)
    rfun = lambda a: _radius_at(outline, a % TAU)     # noqa: E731

    rings, rad, zed, apex = _outer_rings(bm, rim_v, r)
    inner = _inner_rings(bm, flr_v, rfun, r)

    holes = [_blob(rad, zed, h, r) for h in _layout(r)]
    for h in holes:
        ho = _patch(bm, rings, rad, zed, h, r)
        hi = _patch_in(bm, inner, h, rfun)
        _reveal(bm, ho, hi)
    _skins(bm, rings, rad, zed, apex, inner, holes, rfun)

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

    coll_ob = _collider(holes, rfun)
    coll_ob.hide_render = True
    OPEN_BEARING = holes[0]["uc"]

    rock.data.calc_loop_triangles()
    coll_ob.data.calc_loop_triangles()
    rr = [x for row in rad for x in row]
    print("MDL STATS visual_tris=%d collision_tris=%d new_faces=%d sub=%d"
          % (len(rock.data.loop_triangles), len(coll_ob.data.loop_triangles),
             n_new, NSUB))
    print("MDL STATS rings=%d z=rim..%.2f..dome..%.2f radius=%.2f..%.2f"
          % (len(rings), Z_OUT[-1], APEX_Z, min(rr), max(rr)))
    print("MDL STATS holes=%d w=%.2f..%.2f h=%.2f..%.2f z=%.2f..%.2f sides=%s"
          % (len(holes), min(h["w"] for h in holes), max(h["w"] for h in holes),
             min(h["h"] for h in holes), max(h["h"] for h in holes),
             min(h["z0"] for h in holes),
             max(h["z0"] + h["h"] for h in holes),
             ",".join(str(h["n"]) for h in holes)))
    print("MDL STATS sill=%.2f headroom=%.2f splay=%.2f uv_layers=%d"
          % (SILL_Z - FLOOR_Z, CEIL_Z - BODY_H, SPLAY, len(rock.data.uv_layers)))
    return [rock, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=0.0, post=_extra_renders)
