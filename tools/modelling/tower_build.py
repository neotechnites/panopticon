"""tower -- the watch chamber, SCULPTED OUT OF Ryan's hand-modelled TowerRock.

The body is not generated here. It is appended from assets/models/tower.blend
with its HellRock material and packed atlas. The room wall is then built as a
CONTINUATION of that rock: his open rim loop (top of the column body) and his
open cap loop (underside of the cap) are resampled onto one shared set of
bearings and bridged, so every ring of the wall is his own silhouette
interpolated -- no new cylinder, no ring stuck on. Slots are cut out of that
bridge; the wall's thickness is closed by an inner skin welded to his floor.
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
SILL_TOP   = 1.30      # jump apex is 1.11, so the guard cannot leave
FIL_LO     = 1.65      # fillet ring, 0.35 above the sill
FIL_HI     = 4.60      # fillet ring, 0.35 below the lintel
SLOT_TOP   = 4.95
CEIL_Z     = 5.56      # his cap underside
R_IN       = 7.00      # fallback inner radius if his floor is already welded
R_REF      = 8.00      # radius the arc widths below are quoted at

# The bridge's sub-columns are HIS faceting: the bearing set is his rim loop's
# vertices merged with his cap loop's, so every ring lands on his own corners
# and neither loop is left with a T-junction. Clamped into this range.
SUB_MIN    = 48        # his corners, halved where they are far apart
SUB_MAX    = 80        # high: dropping one of his corners cracks his loop
MERGE_TOL  = 0.065     # two bearings closer than this are one sub-column, rad
SNAP_TOL   = 0.065     # reuse one of his vertices within this of a bearing
R_JAG      = 0.15      # radial jitter on the new rings, m
Z_JAG      = 0.10      # height jitter on the new rings, m
CHAMFER    = 0.35      # corner flare into sill and lintel, m of arc
SPLAY      = 0.30      # reveal splay: the outer mouth is this much wider, m
SEED       = 20260911

N_BAYS    = 9          # nine slots; seven thin columns and two fat ones
COL_W     = (1.25, 1.80)    # column width at R_REF, metres...
COL_FAT   = (2.30, 2.80)    # ...except two of them
SLOT_W    = (0.88, 1.12)    # slot width as a weight; the ring closes on it
COL_MIN   = 1.05            # no column may snap thinner than this
SLOT_MIN  = 2.60            # ...and no slot narrower than this to pay for it

EYE_H = 1.65
BODY_H = 1.80

# Atlas zones as (u0, v0, u1, v1), matching the packed HellRock atlas.
ZONE_ROCK  = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)
ZONE_CARVE = (0.5, 0.0, 1.0, 0.5)
UV_SCALE = 0.13
UV_PAD = 1.5 / 128.0

TAU = 2.0 * math.pi
NSUB = 32              # set from his loops at build time


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
# HIS MESH -- boundary loops, the missing face, resampling
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
    """His loop, cut so it has exactly one vertex on each bearing.

    Existing vertices within ``tol`` are reused; otherwise his own boundary
    edge is split, so the new vertex lies ON his silhouette and the mesh stays
    welded. Returns [BMVert] parallel to ``bearings``.
    """
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
# THE WALL
# =============================================================================

NEW = []          # [(BMFace, zone)] -- everything this script adds


def _face(bm, verts, want, zone):
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


def _tan(a, sign):
    return (-math.sin(a) * sign, math.cos(a) * sign, 0.0)


def _merge_bearings(*loops):
    """His corners, both loops at once: the sub-column boundaries.

    Bearings closer together than MERGE_TOL are one boundary. The count is then
    nudged into [SUB_MIN, SUB_MAX] by halving the widest gaps.
    """
    out = []
    for lp in loops:
        for v in lp:
            b = _bear(v.co)
            if all(abs(_wrap(b - o)) > MERGE_TOL for o in out):
                out.append(b)
    out.sort()
    while len(out) < SUB_MIN:
        gaps = [((out[(i + 1) % len(out)] - out[i]) % TAU, i) for i in range(len(out))]
        g, i = max(gaps)
        out.insert(i + 1, (out[i] + g * 0.5) % TAU)
        out.sort()
    while len(out) > SUB_MAX:
        gaps = [((out[(i + 1) % len(out)] - out[i]) % TAU, i) for i in range(len(out))]
        _g, i = min(gaps)
        out.pop((i + 1) % len(out))
    return out


def _layout(bear, r):
    """Nine bays, cut on whichever of his corners land nearest the target arc.

    Widths are chosen in metres first -- seven thin columns, two fat, slots
    sharing what is left unequally -- then snapped to his sub-columns, so the
    spacing round the tower is irregular without any run collapsing.
    """
    n = len(bear)
    if n < 2 * N_BAYS:
        raise SystemExit("MDL ERROR: only %d sub-columns for %d bays" % (n, N_BAYS))
    arc = [(bear[(i + 1) % n] - bear[i]) % TAU * R_REF for i in range(n)]
    pos = [0.0]
    for a in arc:
        pos.append(pos[-1] + a)
    circ = pos[-1]

    cols = [COL_W[0] + (COL_W[1] - COL_W[0]) * r.f() for _ in range(N_BAYS)]
    fat = set()
    while len(fat) < 2:
        fat.add(r.i(0, N_BAYS - 1))
    for i in fat:
        cols[i] = COL_FAT[0] + (COL_FAT[1] - COL_FAT[0]) * r.f()
    w = [SLOT_W[0] + (SLOT_W[1] - SLOT_W[0]) * r.f() for _ in range(N_BAYS)]
    share = (circ - sum(cols)) / sum(w)
    slots = [x * share for x in w]

    tgt = []
    for k in range(N_BAYS):
        tgt += [cols[k], slots[k]]
    floors = [COL_MIN if k % 2 == 0 else SLOT_MIN for k in range(len(tgt))]

    # Snap each run onto one of his corners. The remaining targets are rescaled
    # to the arc still unspent, so a run that had to overshoot does not starve
    # the rest; and no candidate may leave the runs after it below minimum.
    cuts, prev, runs = [], 0, len(tgt) - 1
    for k in range(runs):
        left = circ - pos[prev]
        c = pos[prev] + tgt[k] * left / sum(tgt[k:])
        need = sum(floors[k + 1:]) * 1.25    # margin: his facets are quantised
        lo = max(prev + 1, k + 1)
        hi = max(lo, min(n - (runs - k), n - 1))
        cand = list(range(lo, hi + 1))
        keep = [i for i in cand
                if pos[i] - pos[prev] >= floors[k] and circ - pos[i] >= need]
        best = min(keep or cand, key=lambda i: abs(pos[i] - c))
        cuts.append(best)
        prev = best
    edges = [0] + cuts
    bays = []
    for k in range(N_BAYS):
        a, b = edges[2 * k], edges[2 * k + 1]
        c = edges[2 * k + 2] if 2 * k + 2 < len(edges) else n
        bays.append({"col": (a, b), "slot": (b, c)})
    push = [0] * n
    for bay in bays:
        a, b = bay["slot"]
        push[a % n] = 1             # left jamb flares into the slot
        push[b % n] = -1
    return bays, push


def _smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def _build_wall(bm, rim_v, cap_v, flr_v, ceil_v, rfun, bear, push, bays, r):
    """Bridge his rim to his cap, cut the slots, close the thickness."""
    r_rim = [math.hypot(v.co.x, v.co.y) for v in rim_v]
    r_cap = [math.hypot(v.co.x, v.co.y) for v in cap_v]
    z_rim = sum(v.co.z for v in rim_v) / NSUB
    z_cap = sum(v.co.z for v in cap_v) / NSUB

    zs = [None, SILL_TOP, FIL_LO, FIL_HI, SLOT_TOP, None]
    # OUTER rings. 0 and 5 are his own vertices; 1..4 interpolate his two
    # silhouettes at that bearing and wobble, so no ring is level or round.
    outer = [list(rim_v)] + [None] * 4 + [list(cap_v)]
    ob_ang = [list(bear)] + [None] * 4 + [list(bear)]
    for k in (1, 2, 3, 4):
        s = _smooth((zs[k] - z_rim) / (z_cap - z_rim))
        row, angs = [], []
        for i in range(NSUB):
            a = bear[i] + (push[i] * CHAMFER / R_REF if k in (1, 4) else 0.0)
            rad = r_rim[i] * (1.0 - s) + r_cap[i] * s + R_JAG * r.sf()
            z = zs[k] + Z_JAG * r.sf()
            row.append(bm.verts.new((rad * math.cos(a), rad * math.sin(a), z)))
            angs.append(a)
        outer[k] = row
        ob_ang[k] = angs

    # INNER skin: his floor polygon extruded up to his ceiling's edge. Welded
    # to both -- his floor ring at the bottom, his ceiling ring at the top --
    # and a true prism in between, because that is the collision surface. Its
    # jambs are splayed in, so every reveal is angled, never square to the wall.
    zin = [FLOOR_Z, SILL_TOP, FIL_LO, FIL_HI, SLOT_TOP, CEIL_Z]
    inner = [flr_v] + [None] * 4 + [ceil_v]
    for k in (1, 2, 3, 4):
        extra = CHAMFER if k in (1, 4) else 0.0
        row = []
        for i in range(NSUB):
            a = bear[i] + push[i] * (SPLAY + extra) / R_REF
            rr = rfun(a)
            row.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), zin[k])))
        inner[k] = row

    open_gap = (1, 2, 3)          # the gaps the slots are cut out of
    slot_of = {}
    for bay in bays:
        a, b = bay["slot"]
        for k in range(a, b):
            slot_of[k % NSUB] = bay

    # ---- skins --------------------------------------------------------------
    for k in range(5):
        for i in range(NSUB):
            j = (i + 1) % NSUB
            cut = k in open_gap and i in slot_of
            mid = ob_ang[k][i] + 0.5 * ((ob_ang[k][j] - ob_ang[k][i]) % TAU)
            if not cut:
                _face(bm, [outer[k][i], outer[k][j], outer[k + 1][j], outer[k + 1][i]],
                      _rad(mid), ZONE_ROCK)
            if not cut:
                _face(bm, [inner[k][i], inner[k][j], inner[k + 1][j], inner[k + 1][i]],
                      _rad(mid, inward=True), ZONE_SHADE)

    # ---- sill top, lintel soffit, reveals -----------------------------------
    for bay in bays:
        a, b = bay["slot"]
        for k in range(a, b):
            i, j = k % NSUB, (k + 1) % NSUB
            _face(bm, [outer[1][i], outer[1][j], inner[1][j], inner[1][i]],
                  (0.0, 0.0, 1.0), ZONE_CARVE)
            _face(bm, [outer[4][i], outer[4][j], inner[4][j], inner[4][i]],
                  (0.0, 0.0, -1.0), ZONE_CARVE)
        for idx, sign in ((a % NSUB, 1), (b % NSUB, -1)):
            for k in open_gap:
                _face(bm, [outer[k][idx], outer[k + 1][idx],
                           inner[k + 1][idx], inner[k][idx]],
                      _tan(bear[idx], sign), ZONE_CARVE)

    # ---- footing: close the annulus between his floor edge and his rim -------
    for i in range(NSUB):
        j = (i + 1) % NSUB
        _face(bm, [inner[0][i], inner[0][j], outer[0][j], outer[0][i]],
              (0.0, 0.0, -1.0), ZONE_SHADE)

    return inner, outer


def _ceiling(bm, inner, r):
    """Only when his cap has no floor over the room. Faces DOWN."""
    hub = bm.verts.new((0.0, 0.0, CEIL_Z + 0.09))
    top = inner[5]
    for i in range(NSUB):
        _face(bm, [hub, top[i], top[(i + 1) % NSUB]], (0.0, 0.0, -1.0), ZONE_SHADE)


# =============================================================================
# COLLIDER -- flat, quiet, and never over a slot
# =============================================================================

def _collider(bays, bear, rfun):
    verts, faces = [], []

    def v(p):
        verts.append(tuple(p))
        return len(verts) - 1

    def pt(i, z):
        rr = rfun(bear[i])
        return (rr * math.cos(bear[i]), rr * math.sin(bear[i]), z)

    def emit(idx, want):
        pts = [verts[k] for k in idx]
        if _newell(pts).dot(Vector(want)) < 0.0:
            idx = list(reversed(idx))
        if len(idx) == 4:
            faces.append((idx[0], idx[1], idx[2]))
            faces.append((idx[0], idx[2], idx[3]))
        else:
            faces.append(tuple(idx))

    floor = [v(pt(i, FLOOR_Z)) for i in range(NSUB)]
    for i in range(1, NSUB - 1):
        emit([floor[0], floor[i], floor[i + 1]], (0.0, 0.0, 1.0))
    sill = [v(pt(i, SILL_TOP)) for i in range(NSUB)]
    for i in range(NSUB):
        j = (i + 1) % NSUB
        mid = bear[i] + 0.5 * ((bear[j] - bear[i]) % TAU)
        emit([floor[i], floor[j], sill[j], sill[i]], _rad(mid, inward=True))
    for bay in bays:
        a, b = bay["col"]
        i, j = a % NSUB, b % NSUB
        lo = [v(pt(i, SILL_TOP)), v(pt(j, SILL_TOP))]
        hi = [v(pt(i, CEIL_Z)), v(pt(j, CEIL_Z))]
        emit([lo[0], lo[1], hi[1], hi[0]], _rad(bear[i], inward=True))
    for bay in bays:
        a, b = bay["slot"]
        i, j = a % NSUB, b % NSUB
        n = [v(pt(i, SLOT_TOP)), v(pt(j, SLOT_TOP))]
        o = [v((1.18 * rfun(bear[i]) * math.cos(bear[i]),
                1.18 * rfun(bear[i]) * math.sin(bear[i]), SLOT_TOP)),
             v((1.18 * rfun(bear[j]) * math.cos(bear[j]),
                1.18 * rfun(bear[j]) * math.sin(bear[j]), SLOT_TOP))]
        emit([n[0], n[1], o[1], o[0]], (0.0, 0.0, -1.0))
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
    # Is there already a surface over the room? Only a face sitting low over
    # the floor's middle counts; the cap's own outer skin does not.
    roof = sum(1 for p in ob.data.polygons
               if math.hypot(p.center.x, p.center.y) < 4.0 and 4.9 < p.center.z < 6.6)
    print("MDL STATS body verts=%d tris=%d z=%.2f..%.2f roof_faces=%d mat=%s uv=%s tex=[%s]"
          % (len(ob.data.vertices), len(ob.data.loop_triangles),
             min(zs), max(zs), roof, mat.name, uvname, ", ".join(imgs)))
    return ob, mat, uvname, roof > 0


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

    shot("facade", (ux * 25.0, uy * 25.0, 3.4), (0.0, 0.0, 2.9), 42.0, (1300, 950))

    fl = bpy.data.lights.new("RoomFill", type="POINT")
    fl.energy = 900.0
    fl.color = (1.0, 0.55, 0.40)
    lamp = mdl._link(bpy.data.objects.new("RoomFill", fl))
    lamp.location = (-ux * 1.8, -uy * 1.8, 2.6)
    shot("room", (-ux * 4.6, -uy * 4.6, EYE_H + 0.3), (ux * 24.0, uy * 24.0, 1.4),
         18.0, (1100, 820))
    bpy.data.objects.remove(lamp, do_unlink=True)

    for ob in (cam, target, key):
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    global OPEN_BEARING, NEW, NSUB
    NEW = []
    rock, mat, uvname, has_ceiling = _append_rock()
    r = _Rng(SEED)

    bm = bmesh.new()
    bm.from_mesh(rock.data)

    # ---- his open loops: classify, fill the stray one -----------------------
    loops = _boundary_loops(bm)
    low, high, strays = [], [], []
    for lp in loops:
        st = _loop_stats(lp)
        print("MDL STATS loop n=%d z=%.2f..%.2f (mean %.2f) r=%.2f..%.2f (mean %.2f)"
              % (st["n"], st["z0"], st["z1"], st["zm"], st["r0"], st["r1"], st["rm"]))
        (low if st["zm"] < 2.0 else high if 4.4 < st["zm"] < 6.4 else strays).append(lp)
    # Down here his rim is the wider of the two; up there his cap underside is
    # the biggest ring and his ceiling's edge the next. Anything else is a hole.
    low.sort(key=lambda lp: _loop_stats(lp)["rm"])
    high.sort(key=len)
    rim = low[-1] if low else None
    floor = low[-2] if len(low) > 1 else None
    cap = high[-1] if high else None
    ceil = high[-2] if len(high) > 1 else None
    strays += high[:-2]
    if rim is None or cap is None or floor is None or ceil is None:
        raise SystemExit("MDL ERROR: expected rim, floor, cap and ceiling loops")

    for lp in strays:
        st = _loop_stats(lp)
        vs = set(lp)
        edges = [e for e in bm.edges if e.is_boundary and e.verts[0] in vs and e.verts[1] in vs]
        res = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        made = res.get("faces", [])
        if not made and 3 <= len(lp) <= 8:
            try:
                made = [bm.faces.new(_order_ccw(lp))]
            except ValueError:
                made = []
        want = Vector((0.0, 0.0, 1.0 if st["zm"] > 3.0 else -1.0))
        for f in made:
            f.normal_update()
            if f.normal.dot(want) < 0.0:
                f.normal_flip()
            NEW.append((f, ZONE_ROCK))
        print("MDL STATS hole_filled n=%d faces=%d at z=%.2f..%.2f r=%.2f..%.2f"
              % (st["n"], len(made), st["z0"], st["z1"], st["r0"], st["r1"]))
    if not strays:
        print("MDL STATS hole_filled none (no stray boundary loop)")

    # ---- resample his two silhouettes onto one shared bearing set -----------
    n_rim, n_cap = len(rim), len(cap)
    bear = _merge_bearings(rim, cap)
    NSUB = len(bear)
    bays, push = _layout(bear, r)
    ib = [bear[i] + push[i] * SPLAY / R_REF for i in range(NSUB)]
    rim_v = _resample(rim, bear)
    cap_v = _resample(cap, bear)
    flr_v = _resample(floor, ib)
    ceil_v = _resample(ceil, ib)
    outline = _outline(floor)
    rfun = lambda a: _radius_at(outline, a % TAU)     # noqa: E731

    inner, outer = _build_wall(bm, rim_v, cap_v, flr_v, ceil_v, rfun,
                               bear, push, bays, r)
    if not has_ceiling:
        _ceiling(bm, inner, r)
    print("MDL STATS ceiling=%s" % ("his cap" if has_ceiling else "added disc"))

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

    coll_ob = _collider(bays, bear, rfun)
    coll_ob.hide_render = True

    a, b = bays[0]["slot"]
    OPEN_BEARING = bear[a % NSUB] + 0.5 * ((bear[b % NSUB] - bear[a % NSUB]) % TAU)

    rock.data.calc_loop_triangles()
    coll_ob.data.calc_loop_triangles()
    arc = [(bear[(i + 1) % NSUB] - bear[i]) % TAU for i in range(NSUB)]
    col_w = [sum(arc[k % NSUB] for k in range(*bay["col"])) * R_REF for bay in bays]
    slot_w = [sum(arc[k % NSUB] for k in range(*bay["slot"])) * R_REF for bay in bays]
    print("MDL STATS visual_tris=%d collision_tris=%d new_faces=%d"
          % (len(rock.data.loop_triangles), len(coll_ob.data.loop_triangles), n_new))
    print("MDL STATS loops rim=%d cap=%d floor=%d ceiling=%d sub_columns=%d"
          % (n_rim, n_cap, len(floor), len(ceil), NSUB))
    print("MDL STATS rings z=rim,%.2f,%.2f,%.2f,%.2f,cap  jitter r=%.2f z=%.2f"
          % (SILL_TOP, FIL_LO, FIL_HI, SLOT_TOP, R_JAG, Z_JAG))
    print("MDL STATS slots=%d slot_w=%.2f..%.2f column_w=%.2f..%.2f ratio=1:%.1f..1:%.1f"
          % (len(bays), min(slot_w), max(slot_w), min(col_w), max(col_w),
             min(s / c for s, c in zip(slot_w, col_w)),
             max(s / c for s, c in zip(slot_w, col_w))))
    print("MDL STATS sill=%.2f headroom=%.2f chamfer=%.2f splay=%.2f uv_layers=%d"
          % (SILL_TOP - FLOOR_Z, CEIL_Z - BODY_H, CHAMFER, SPLAY,
             len(rock.data.uv_layers)))
    return [rock, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=0.0, post=_extra_renders)
