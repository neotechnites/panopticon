"""Rebuild prisoner2's head and neck as one ring-lofted shell with a sculpted face; close the crotch; re-bake AO; re-export.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_face2.py -- [--out <blend>]
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "modelling", "lib"))
sys.path.insert(0, HERE)
import glb_textures  # noqa: E402
from prisoner2_face import bake_ao  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"

# The head's frame: U leans forward with the wedge so its crown and underside sit level, F faces forward.
U = Vector((0, -0.30, 1.0)).normalized()
F = Vector((0, -1.0, -0.30)).normalized()
X = Vector((1, 0, 0))
O = Vector((0, -0.075, 1.60))
# The skull as it shipped: face rim, mid section, back section (x >= 0; mirrored). Hulled, then rounded.
SKULL = [(0.0, -0.259, 1.648), (0.098, -0.259, 1.648), (0.115, -0.239, 1.598), (0.118, -0.235, 1.552),
         (0.07, -0.225, 1.508), (0.03, -0.231, 1.466), (0.0, -0.231, 1.466),
         (0.0, -0.12, 1.702), (0.086, -0.12, 1.702), (0.14, -0.12, 1.634), (0.15, -0.12, 1.566),
         (0.072, -0.12, 1.512), (0.056, -0.12, 1.478), (0.0, -0.12, 1.478),
         (0.0, 0.105, 1.79), (0.048, 0.105, 1.79), (0.07, 0.105, 1.716), (0.078, 0.105, 1.626),
         (0.056, 0.105, 1.57), (0.042, 0.105, 1.548), (0.0, 0.105, 1.548)]
ROUND = 90.0                   # plane blend sharpness (1/m): higher = harder skull edges
WALL = 0.6                     # |normal . U| under this is wall, over it is crown or underside
FACE_X = [i * 0.016 for i in range(-6, 7)]   # face columns, shot straight back along -F
SIDE = [(0.135, -0.18), (0.15, -0.12), (0.126, -0.045), (0.102, 0.03), (0.078, 0.105)]  # side columns aimed at (x, y): on the skull's edges and between them
ROWS = [i / 11 for i in range(12)]  # wall rows down from the brow edge, as a share of the face's height
SPLIT = 0.5                    # rows above this hold their height across the face; below, they stretch to each column's jaw
NECK_IN = Vector((0, -0.145, 1.40))     # straight below where the neck enters the skull
NECK_R = (0.050, 0.044)        # neck radius at the skull (x, depth)
NECK_RINGS = (0.25, 0.5, 0.75)
EYE = (3, 3, 0.022, 0.034, 0.17)        # column, row, depth (m), radius x (m), radius y (share of face)
MOUTH = 8                      # the mouth's row
BACK_ROWS = (0, 2, 4, 6, 8, 10, 11)  # the wall rows kept round the sides and back (0 = brow edge)
EASE = 0.35                    # share of each face vertex's relief blended toward its neighbours'
CROTCH_UV = (0.25, 0.80)       # a plain trouser texel for the crotch gusset
SKIN = (183, 239, 63, 63)      # the largest square of plain skin in the albedo (px x, y, w, h): no painted marks


def skull_planes():
    bm = bmesh.new()
    for x, y, z in SKULL:
        bm.verts.new((x, y, z))
        if x:
            bm.verts.new((-x, y, z))
    bmesh.ops.convex_hull(bm, input=bm.verts)
    planes = []
    for f in bm.faces:
        n = f.normal.copy()
        hit = next((p for p in planes if p[0].dot(n) > 0.998), None)
        if hit:
            hit[0] = (hit[0] * hit[2] + n).normalized()
            hit[2] += 1
            hit[3].extend(v.co.copy() for v in f.verts)
        else:
            planes.append([n, 0.0, 1, [v.co.copy() for v in f.verts]])
    bm.free()
    return [(n, max(n.dot(p) for p in pts)) for n, _d, _c, pts in planes]


PLANES = skull_planes()


def field(p):
    a = [n.dot(p) - d for n, d in PLANES]
    m = max(a)
    return m + math.log(sum(math.exp(ROUND * (x - m)) for x in a)) / ROUND


def normal(p):
    a = [n.dot(p) - d for n, d in PLANES]
    m = max(a)
    w = [math.exp(ROUND * (x - m)) for x in a]
    g = sum((n * wi for (n, _d), wi in zip(PLANES, w)), Vector())
    return g.normalized()


def out_of(o, d, far=0.6):
    """From o inside the skull, the surface point along d."""
    lo, hi = 0.0, far
    for _ in range(40):
        mid = (lo + hi) / 2
        if field(o + d * mid) < 0:
            lo = mid
        else:
            hi = mid
    return o + d * lo


def into(o, d, far=0.8):
    """From o outside, the first surface point along d, or None."""
    a, b = 0.0, far
    for _ in range(50):
        m1, m2 = a + (b - a) / 3, b - (b - a) / 3
        if field(o + d * m1) < field(o + d * m2):
            b = m2
        else:
            a = m1
    tm = (a + b) / 2
    if field(o + d * tm) >= 0:
        return None
    lo, hi = 0.0, tm
    for _ in range(40):
        mid = (lo + hi) / 2
        if field(o + d * mid) > 0:
            lo = mid
        else:
            hi = mid
    return o + d * hi


def h_of(p):
    return (p - O).dot(U)


class Column:
    """One meridian of the head: a face column (x) or a side column (angle about U)."""

    def __init__(self, x=None, theta=None):
        self.x, self.theta = x, theta

    def at(self, h):
        if self.x is not None:
            return into(O + X * self.x + U * h + F * 0.5, -F)
        d = F * math.cos(self.theta) + X * math.sin(self.theta)
        return out_of(O + U * h, d)

    def wall(self, h):
        if self.x is None and field(O + U * h) >= 0:
            return False
        p = self.at(h)
        return p is not None and abs(normal(p).dot(U)) < WALL

    def span(self):
        """Lowest and highest h where this column is still wall."""
        hs = [-0.30 + 0.004 * i for i in range(150)]
        ok = [h for h in hs if self.wall(h)]

        def edge(good, bad):
            for _ in range(20):
                m = (good + bad) / 2
                if self.wall(m):
                    good = m
                else:
                    bad = m
            return good
        self.lo = edge(ok[0], ok[0] - 0.004)
        self.hi = edge(ok[-1], ok[-1] + 0.004)


def columns():
    face = [Column(x=x) for x in FACE_X]
    for c in face:
        c.span()
    side = []
    for x, y in SIDE:
        e = Vector((x, y, O.z)) - O
        side.append(Column(theta=math.atan2(e.dot(X), e.dot(F))))
    back = [Column(theta=math.pi)]
    other = [Column(theta=-c.theta) for c in reversed(side)]
    for c in side + back + other:
        c.span()
    return face + side + back + other


def row_heights(col, depth0):
    """Wall rows for one column, bottom to top."""
    depth = col.hi - col.lo
    hs = []
    for fr in ROWS:
        if col.x is not None:
            yd = fr * depth0 if fr <= SPLIT else SPLIT * depth0 + (fr - SPLIT) / (1 - SPLIT) * (depth - SPLIT * depth0)
        else:
            yd = fr * depth
        hs.append(col.hi - yd)
    return list(reversed(hs))


def remap(ci, ri, x, y, centre, cell, scale, full, part):
    """Square rings of grid cells around a feature become ellipses: real edge loops."""
    ec, er, ex, ey = centre
    r = max(abs(ci - ec), abs(ri - er))
    if r == 0 or r > full + (1 if part else 0):
        return x, y
    qx, qy = (x - ex) / (r * cell[0]), (y - ey) / (r * cell[1])
    n = math.hypot(qx, qy)
    nx, ny = ex + qx / n * r * cell[0] * scale[0], ey + qy / n * r * cell[1] * scale[1]
    b = 1.0 if r <= full else part
    return x + (nx - x) * b, y + (ny - y) * b


def bump(dx, dy, rx, ry):
    q = (dx / rx) ** 2 + (dy / ry) ** 2
    return (1 - q) ** 2 if q < 1 else 0.0


def smooth(a, b, t):
    t = min(max((t - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def relief(x, y):
    """Face displacement (m, outward) at x across and y down from the brow edge (share of the face's height)."""
    ax = abs(x)
    d = 0.0
    # brow shelf: a ledge over both eyes, dropping hard into the sockets
    d += 0.011 * (0.4 + 0.6 * smooth(0.0, 0.08, y)) * (1 - smooth(0.13, 0.21, y)) * (1 - smooth(0.085, 0.115, ax))
    # eye sockets
    d -= EYE[2] * bump(ax - 0.048, y - ROWS[EYE[1]], EYE[3], EYE[4])
    # nose: bridge from between the brows to the tip, undercut to the base
    ridge = max(0.0, 1 - ax / 0.026)
    prof = 0.0
    if 0.17 < y <= 0.455:
        prof = 0.004 + 0.036 * ((y - 0.17) / 0.285) ** 1.3
    elif 0.455 < y < 0.56:
        prof = 0.040 * (1 - (y - 0.455) / 0.105) ** 1.5
    d += prof * ridge
    d += 0.007 * bump(ax - 0.020, y - 0.50, 0.014, 0.07)            # nostril wings
    # cheekbones and the hollow under them
    d += 0.011 * bump(ax - 0.082, y - 0.40, 0.032, 0.14)
    d -= 0.007 * bump(ax - 0.072, y - 0.66, 0.026, 0.15)
    # mouth: a soft muzzle with a shallow line across it
    d += 0.008 * bump(ax, y - 0.72, 0.052, 0.20)
    d -= 0.005 * bump(ax, y - ROWS[MOUTH], 0.026, 0.06)
    # chin
    d += 0.012 * bump(ax, y - 0.93, 0.032, 0.11)
    return d


def build_head(bm, collar):
    """Neck rings up from the collar, the skull's underside, wall, crown; returns the new faces."""
    dfl = bm.verts.layers.deform.active
    ob = bpy.data.objects["Runner"]
    gi = {n: ob.vertex_groups[n].index for n in ("Spine", "Neck", "Head")}
    cols = columns()
    nc = len(cols)
    centre = cols[len(FACE_X) // 2]
    top0, depth0 = centre.hi, centre.hi - centre.lo
    walls = []
    cell = (0.016, depth0 / (len(ROWS) - 1))
    for ci, col in enumerate(cols):
        hs = row_heights(col, depth0)
        ring = []
        for k, h in enumerate(hs):
            ri = len(hs) - 1 - k                     # 0 = brow edge
            if col.x is not None:
                fx = ci - len(FACE_X) // 2
                x, y = col.x, top0 - h
                for c in (-EYE[0], EYE[0]):
                    ctr = (c, EYE[1], c * 0.016, ROWS[EYE[1]] * depth0)
                    x, y = remap(fx, ri, x, y, ctr, cell, (0.95, 0.85), 2, 0.0)
                x, y = remap(fx, ri, x, y, (0, MOUTH, 0.0, ROWS[MOUTH] * depth0), cell, (1.35, 0.6), 1, 0.4)
                p = Column(x=x).at(top0 - y)
            else:
                p = col.at(h)
            assert p is not None, (ci, ri)
            ring.append(p)
        walls.append(ring)
    # relief, along the skull normal, eased once over the grid so no single vertex spikes
    def disp(p):
        n = normal(p)
        return n, relief(p.x, (top0 - h_of(p)) / depth0) * smooth(0.35, 0.75, n.dot(F))
    dd = [[disp(p)[1] for p in ring] for ring in walls]
    nc_, nr_ = len(walls), len(walls[0])
    eased = [[0.0] * nr_ for _ in range(nc_)]
    for c in range(nc_):
        for r in range(nr_):
            nb = [dd[(c - 1) % nc_][r], dd[(c + 1) % nc_][r]] + [dd[c][q] for q in (r - 1, r + 1) if 0 <= q < nr_]
            eased[c][r] = dd[c][r] * (1 - EASE) + sum(nb) / len(nb) * EASE
    for c, ring in enumerate(walls):
        for k, p in enumerate(ring):
            ring[k] = p + normal(p) * eased[c][k]

    def off(m):
        """How far m sits from the sculpted surface: picks each quad's diagonal so creases are not sawn."""
        n = normal(m)
        base = m - n * field(m)
        return (m - (base + n * disp(base)[1])).length
    nr = len(walls[0])
    # crown
    crest = out_of(O, U)
    cap = []
    for col in walls:
        q = col[-1].lerp(crest, 0.5)
        cap.append(into(q + U * 0.3, -U))
    # underside: neck hole, then halfway out to the wall's foot
    entry = into(NECK_IN, U)
    hole, mid = [], []
    for col in walls:
        foot = col[0]
        d = foot - entry
        d -= U * d.dot(U)
        d.normalize()
        q = entry + X * (d.dot(X) * NECK_R[0]) + F * (d.dot(F) * NECK_R[1])
        hole.append(into(q - U * 0.2, U))
        mid.append(into(foot.lerp(hole[-1], 0.5) - U * 0.2, U))
    # neck: Hermite from the collar to the hole, leaving the collar along the neck and arriving flared
    cc = sum((v.co for v in collar), Vector()) / len(collar)
    axis = (entry - cc).normalized()
    ang = [angle_about(v.co, cc, axis) for v in collar]
    if (ang[1] - ang[0]) % (2 * math.pi) > math.pi:
        collar = list(reversed(collar))
    length = (entry - cc).length
    cpts = []
    for k in range(nc):
        d = hole[k] - entry
        d -= axis * d.dot(axis)
        cpts.append(on_ring(collar, cc, axis, d.normalized()))
    neck = [[] for _ in NECK_RINGS]
    for k in range(nc):
        c0, c1 = cpts[k][0], hole[k]
        radial = (c1 - entry)
        radial -= axis * radial.dot(axis)
        t0 = axis * length
        t1 = (axis + radial.normalized() * 0.5).normalized() * length * 0.7
        for i, u in enumerate(NECK_RINGS):
            h00, h10, h01, h11 = 2 * u**3 - 3 * u**2 + 1, u**3 - 2 * u**2 + u, -2 * u**3 + 3 * u**2, u**3 - u**2
            neck[i].append(c0 * h00 + t0 * h10 + c1 * h01 + t1 * h11)
    # split the collar where the columns leave it
    for k in range(nc):
        split_collar(bm, cpts[k])
    loop = boundary_loop(bm)
    # vertices
    def vring(pts, w):
        out = []
        for p in pts:
            v = bm.verts.new(p)
            for g, x in w.items():
                if x > 0:
                    v[dfl][gi[g]] = x
            out.append(v)
        return out
    # which box plane each column's skin is mapped from: 0 front/back, 1 sides, 2 crown/underside
    tag = {}

    def side_on(d):
        return 1 if abs(d.dot(X)) > abs(d.dot(F)) else 0
    rings = []
    for i, u in enumerate(NECK_RINGS):
        head = smooth(0.15, 1.0, u)
        spine = max(0.0, 0.5 * (1 - u / 0.5))
        rings.append(vring(neck[i], {"Spine": spine, "Head": head, "Neck": 1 - head - spine}))
        for k, v in enumerate(rings[-1]):
            tag[v] = (k, side_on(hole[k] - entry))
    rings.append(vring(hole, {"Head": 1.0}))
    rings.append(vring(mid, {"Head": 1.0}))
    # wall: every row across the face, every other row round the sides and back
    wall = []
    for c in range(nc):
        keep = range(nr) if cols[c].x is not None else [k for k in range(nr) if (nr - 1 - k) in BACK_ROWS]
        wall.append([(k, v) for k, v in zip(keep, vring([walls[c][k] for k in keep], {"Head": 1.0}))])
        th = cols[c].theta
        for _k, v in wall[-1]:
            tag[v] = (c, 0 if th is None else side_on(F * math.cos(th) + X * math.sin(th)))
    cap_ring = vring(cap, {"Head": 1.0})
    pole = vring([crest], {"Head": 1.0})[0]
    for v in rings[-2] + rings[-1] + cap_ring + [pole]:
        tag[v] = (None, 2)
    faces = []

    def quad(q):
        if off((q[0].co + q[2].co) / 2) <= off((q[1].co + q[3].co) / 2):
            return [bm.faces.new((q[0], q[1], q[2])), bm.faces.new((q[0], q[2], q[3]))]
        return [bm.faces.new((q[0], q[1], q[3])), bm.faces.new((q[1], q[2], q[3]))]

    def band(a, b, split):
        for k in range(nc):
            k2 = (k + 1) % nc
            q = (a[k], a[k2], b[k2], b[k])
            faces.extend(quad(q) if split else [bm.faces.new(q)])
    faces += zipper(bm, loop, rings[0], cc, axis)
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        band(a, b, i >= len(NECK_RINGS))
    band(rings[-1], [w[0][1] for w in wall], True)
    for c in range(nc):
        A, B = wall[c], wall[(c + 1) % nc]
        i = j = 0
        while i < len(A) - 1 or j < len(B) - 1:
            na = A[i + 1][0] if i < len(A) - 1 else nr
            nb = B[j + 1][0] if j < len(B) - 1 else nr
            if na == nb:
                faces.extend(quad((A[i][1], B[j][1], B[j + 1][1], A[i + 1][1])))
                i, j = i + 1, j + 1
            elif na < nb:
                faces.append(bm.faces.new((A[i][1], B[j][1], A[i + 1][1])))
                i += 1
            else:
                faces.append(bm.faces.new((A[i][1], B[j][1], B[j + 1][1])))
                j += 1
    band([w[-1][1] for w in wall], cap_ring, True)
    rings.append(cap_ring)
    last = rings[-1]
    for k in range(nc):
        faces.append(bm.faces.new((last[k], last[(k + 1) % nc], pole)))
    plane = {}
    for fc in faces:
        ts = [tag[v] for v in fc.verts if v in tag]
        if any(t[1] == 2 for t in ts):
            plane[fc] = 2
            continue
        ks = {t[0] for t in ts}
        first = next((k for k in ks if (k + 1) % nc in ks), next(iter(ks)))
        plane[fc] = next(t[1] for t in ts if t[0] == first)
    return faces, plane


def angle_about(p, c, axis):
    d = p - c
    d -= axis * d.dot(axis)
    fx = (F - axis * F.dot(axis)).normalized()
    xx = axis.cross(fx)
    a = math.atan2(d.dot(xx), d.dot(fx))
    return a


def on_ring(collar, cc, axis, d):
    """Where the ray from the collar centre along d crosses the collar polygon: (point, edge verts, fac)."""
    n = len(collar)
    want = angle_about(cc + d, cc, axis)
    for i in range(n):
        a, b = collar[i], collar[(i + 1) % n]
        aa, ab = angle_about(a.co, cc, axis), angle_about(b.co, cc, axis)
        span = (ab - aa) % (2 * math.pi)
        off = (want - aa) % (2 * math.pi)
        if off <= span + 1e-9:
            # intersect ray with segment in the collar plane
            pa, pb = a.co - cc, b.co - cc
            pa -= axis * pa.dot(axis)
            pb -= axis * pb.dot(axis)
            dd = d - axis * d.dot(axis)
            e = pb - pa
            den = dd.cross(e).dot(axis)
            t = dd.cross(pa).dot(axis) / den if abs(den) > 1e-12 else 0.0
            t = -t
            t = min(max(t, 0.0), 1.0)
            return (a.co.lerp(b.co, t), a, b, t)
    raise AssertionError("collar")


def split_collar(bm, cp):
    p, a, b, t = cp
    if t < 0.08 or t > 0.92:
        return
    loop = boundary_loop(bm)
    for i, v in enumerate(loop):
        w = loop[(i + 1) % len(loop)]
        seg = w.co - v.co
        s = (p - v.co).dot(seg) / seg.length_squared
        if 0.02 < s < 0.98 and ((v.co + seg * s) - p).length < 1e-6:
            e = bm.edges.get((v, w))
            ne, nv = bmesh.utils.edge_split(e, v, s)
            nv.co = p
            return
    raise AssertionError("split")


def boundary_loop(bm):
    edges = [e for e in bm.edges if e.is_boundary]
    nxt = {}
    for e in edges:
        a, b = e.verts
        lp = e.link_loops[0]
        if lp.vert is a:
            nxt[b] = a
        else:
            nxt[a] = b
    start = edges[0].verts[0]
    loop, v = [start], nxt[start]
    while v is not start:
        loop.append(v)
        v = nxt[v]
    assert len(loop) == len(edges), (len(loop), len(edges))
    return loop


def zipper(bm, lower, upper, cc, axis):
    """Stitch two closed rings of different counts by angle."""
    la = [angle_about(v.co, cc, axis) for v in lower]
    if (la[1] - la[0]) % (2 * math.pi) > math.pi:
        lower = list(reversed(lower))
        la = list(reversed(la))
    ua = [angle_about(v.co, cc, axis) for v in upper]
    i0 = min(range(len(lower)), key=lambda i: abs((la[i] - ua[0] + math.pi) % (2 * math.pi) - math.pi))
    lower = lower[i0:] + lower[:i0]
    la = la[i0:] + la[:i0]
    base = ua[0]
    unwrap = lambda a: (a - base + 0.5) % (2 * math.pi) - 0.5  # noqa: E731
    lA = [unwrap(a) for a in la] + [unwrap(la[0]) + 2 * math.pi]
    uA = [unwrap(a) for a in ua] + [unwrap(ua[0]) + 2 * math.pi]
    i = j = 0
    n, m = len(lower), len(upper)
    out = []
    while i < n or j < m:
        if j >= m or (i < n and lA[i + 1] <= uA[j + 1]):
            out.append(bm.faces.new((lower[i % n], lower[(i + 1) % n], upper[j % m])))
            i += 1
        else:
            out.append(bm.faces.new((lower[i % n], upper[(j + 1) % m], upper[j % m])))
            j += 1
    return out


def assign_uvs(bm, faces, plane):
    """Box-map each new face onto one patch of plain skin, the whole head fitting it once: no seams but the box's."""
    uvl = bm.loops.layers.uv.active
    axes = (X, U, F)
    planes = [(0, 1), (2, 1), (0, 2)]
    verts = {v for fc in faces for v in fc.verts}
    lo = [min(v.co.dot(ax) for v in verts) for ax in axes]
    hi = [max(v.co.dot(ax) for v in verts) for ax in axes]
    x0, y0, w, h = SKIN
    texel = min(w, h) / max(b - a for a, b in zip(lo, hi))
    for fc in faces:
        i, j = planes[plane[fc]]
        for l in fc.loops:
            px = x0 + (l.vert.co.dot(axes[i]) - lo[i]) * texel
            py = y0 + (hi[j] - l.vert.co.dot(axes[j])) * texel
            l[uvl].uv = (px / 512, 1 - py / 512)


def close_crotch(bm):
    """The gusset under the fly sampled bare skin: give it trouser cloth."""
    uvl = bm.loops.layers.uv.active
    dfl = bm.verts.layers.deform.active
    ob = bpy.data.objects["Runner"]
    hips = ob.vertex_groups["Hips"].index
    bm.verts.ensure_lookup_table()
    gusset = [f for f in bm.faces if f.material_index == 0 and f.calc_center_median().z < 0.81
              and abs(f.calc_center_median().x) < 0.08 and any(v[dfl].get(hips, 0) > 0.99 for v in f.verts)]
    assert len(gusset) == 6, len(gusset)
    s = 0.004
    for f in gusset:
        for k, l in enumerate(f.loops):
            a = 2 * math.pi * k / 3
            l[uvl].uv = (CROTCH_UV[0] + s * math.cos(a), CROTCH_UV[1] + s * math.sin(a))
    return gusset


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[argv.index("--out") + 1] if "--out" in argv else None
    ob = bpy.data.objects["Runner"]
    arm = bpy.data.objects["Armature"]
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    dfl = bm.verts.layers.deform.active
    head, neck = ob.vertex_groups["Head"].index, ob.vertex_groups["Neck"].index
    # the ears: loose shells, gone
    seen, comps = set(), []
    for v in bm.verts:
        if v in seen:
            continue
        comp, stack = [], [v]
        seen.add(v)
        while stack:
            a = stack.pop()
            comp.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b not in seen:
                    seen.add(b)
                    stack.append(b)
        comps.append(comp)
    comps.sort(key=len)
    bmesh.ops.delete(bm, geom=[v for c in comps[:-1] for v in c], context="VERTS")
    bm.verts.index_update()
    gone = [v for v in bm.verts if v[dfl].get(head, 0) > 0 or v[dfl].get(neck, 0) > 0.69]
    bmesh.ops.delete(bm, geom=gone, context="VERTS")
    collar = boundary_loop(bm)
    assert len(collar) == 6, len(collar)
    faces, plane = build_head(bm, collar)
    smooth_flag = next(f.smooth for f in bm.faces if f not in faces)
    for fc in faces:
        fc.material_index = 0
        fc.smooth = smooth_flag
    bm.normal_update()
    assign_uvs(bm, faces, plane)
    close_crotch(bm)
    bmesh.ops.triangulate(bm, faces=[fc for fc in bm.faces if len(fc.verts) > 3], quad_method="BEAUTY")
    bad = [e for e in bm.edges if not e.is_manifold]
    assert not bad, len(bad)
    bm.to_mesh(me)
    bm.free()
    me.update()
    bake_ao(me)
    if out:
        bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
        print("FACE2 wrote", out, "tris", len(me.polygons))
        return
    bpy.ops.wm.save_mainfile()
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=GLB, export_format="GLB", use_selection=True,
                              export_apply=False, export_yup=True, export_normals=True,
                              export_texcoords=True, export_vertex_color="ACTIVE")
    glb_textures.externalize(GLB, lambda n, data: TEX_URI)
    print("FACE2 wrote", GLB, "tris", len(me.polygons))


if __name__ == "__main__":
    main()
