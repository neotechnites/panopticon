"""
PANOPTICON -- forest pit: the foggy drop round Map 3's tree.

Not a model of its own: forest_build.py calls in here with its _Ground (g).

    pit_floor(g)         the dark floor grown inward off the bank's last row
                         (g.pit[-1]), part of the one contiguous ground mesh
    brambles(g)          thorny branches out of the bank's quads, some arching
                         up over the rim; every one socketed (shares vertices)
    fog_mesh(cls, g)     a separate node (FOG_NAME): stacked translucent discs
                         filling the pit, tint and alpha in COLOR_0 (cls is
                         forest_build._RayMesh); the scene shows it unshaded,
                         mixed, vertex colour as albedo -- GL Compatibility has
                         no fog volumes, so the fog is layers

No water: the pit is a dark floor under fog, and thorns come out of the fog.

    python3 tools/modelling/forest_build.py --check     proves the whole ground
"""

import math
import sys

import forest_tree_build as ft
from forest_tree_build import UP, DOWN, pol, add, sub, norm, dot, lerp, bez, zipper

FOG_NAME = "ForestFog"
FOG_TINT = (0.34, 0.37, 0.29)   # gold-grey-green, kept dim: nine layers stack to ~0.94 opacity, and unshaded
                                # fog brighter than the sunlit lane reads as milk, not gloom


# ---- the fog: nine 48-gon discs, each three annuli of vertex alpha ----------------
FOG_Z = (-12.5, -6.0, 1.083)    # bottom, top, pitch: seven layers from under the floor (y -11.05, the old water
                                # height) to 5 m over it: the fog starts where the floor was and thins over it,
                                # the thicket standing out of it
FOG_N = 48
FOG_HOLE = (6.8, 10.0)          # round the trunk: alpha 0 at 6.8 (outside the trunk, r <= 6.4 above the roots,
                                # so no disc cuts it into rings), full at 10.0
FOG_BANK = (-2.5, 0.6)          # full alpha out to bank_r(z) - 2.5, zero at bank_r(z) + 0.6 (inside the bank)
FOG_ALPHA = (0.5, 0.05)         # the bottom layer, easing to the top layer (dense at the floor, a haze over it)
FOG_DEPTH_DIM = 0.70            # the tint at the bottom layer, as a factor; 1.0 at the top: darker at depth

# ---- the thicket: brambles out of the floor, a mass across the pit bottom ---------
PIT_SEED = 4471023              # its own rng: editing the brambles diffs only the brambles
FLOOR_Z = -11.05                # the floor (the bank's last row)
FLOOR_RINGS = [(38.0, 120)] + [(38.0 - 2.25 * k, 120) for k in range(1, 13)] + [(7.0, 60)]   # r 38 in to 11 by 2.25, then 7
                                # (r, vertices) inward from the bank's 240: equal counts loft into quads (the
                                # brambles' sockets), the count halves by a zipper, the centre is a fan under the trunk
BRAMBLES = 50                   # the tall ones ...
SCRUB = 150                     # ... and the low tangle between them: short, thinner, no forks
SCRUB_H = (3.0, 6.5)
SCRUB_R = (0.26, 0.2, 0.12, 0.075)
SCRUB_THORNS = (2, 4)
SCRUB_SPACING = 1.0             # a scrub root keeps this far from every other root (the tall ones keep 1.6)
BRAMBLE_ROWS = (1, 12)          # floor quads between rings j and j+1 (rings 1..13: r 38 in to 11)
BRAMBLE_AVOID = ()              # nothing on the floor to keep clear of
BRAMBLE_PTS = (4, 22)           # points along a path ...
BRAMBLE_SEG = 1.15              # ... one per this much length, within that
BRAMBLE_R = (0.42, 0.36, 0.28, 0.17, 0.085)   # the tip is a point (its ring edge clears the sliver angle on a wandered 1.5 m segment)
BRAMBLE_SIDES = 5
THICKET_H = ((9.0, 15.0, 19.0), (38.0, 4.0, 7.0))   # (r, min height, max height) at the trunk and at the bank: tallest round the trunk
THICKET_LEAN = (0.25, 0.6)      # a bramble's top sits this fraction of its height sideways from its root
THICKET_DRIFT = (10.0, 40.0)    # degrees the lean swings round as it climbs (a twist)
BRAMBLE_WANDER = 0.45           # per-point jitter on the inner points
FORKS = (2, 3)                  # side branches per bramble, out of its own quads
FORK_AT = (0.3, 0.6)            # ... along the bramble
FORK_L = (3.0, 6.0)             # ... this long, climbing and swinging sideways
FORK_R = 0.55                   # ... this fraction of the parent's radius there
THORNS = (6, 10)
THORN_R = (0.2, 0.07)           # base ring (along the bramble) and tip ring
THORN_FLAT = 0.6                # the base ring across the bramble, as a fraction: a blade, and it fits the quad
THORN_MIN_DEG = 4.0             # a thorn whose best bridging makes a smaller angle is not grown
THORN_L = 0.9
THORN_LEAN = 0.45               # toward the bramble's tip, as a fraction of the normal
THORN_MAX_U = 1.0               # thorns sit where the bramble is thick enough for the ring to fit its quad
THORN_ZONE = "cell"             # the darkest sheet: thorns and stems read as black spikes against the fog
STEM_ZONE = "cell"

# what the check reports
INFO = {"brambles": 0, "thorns": 0, "forks": 0, "top": (0.0, 0.0), "layers": []}


def pit_floor(g):
    """The floor at FLOOR_Z: rings inward from the bank's last row. Rings of
    equal count are lofted into registered quads (the thicket's sockets); a
    count change is a zipper; the centre is a fan under the trunk. g.floor
    keeps the rings (outermost first)."""
    m = g.m
    outer = g.pit[-1]
    z = m.verts[outer[0]][2]
    g.floor = [outer]
    for (rad, n) in FLOOR_RINGS:
        ring = [m.v(pol(360.0 * s / n, rad, z)) for s in range(n)]
        if len(ring) == len(outer):
            for i in range(n):
                q = (i + 1) % n
                m.quad(outer[i], outer[q], ring[q], ring[i], UP, "cell")
        else:
            zipper(m, outer, ring, UP, "cell", centre=(0.0, 0.0, 0.0))
        g.floor.append(ring)
        outer = ring
    ft._cap(m, outer, (0.0, 0.0, z), UP, "cell")   # a centre vertex: a fan from a ring vertex is all slivers


# =============================================================================
# BRAMBLES
# =============================================================================

def _near(b, target, deg):
    return abs(((b - target) + 180.0) % 360.0 - 180.0) < deg


def _cubic(p0, p1, p2, p3, n):
    out = []
    for k in range(n):
        t = k / float(n - 1)
        a, b, c = lerp(p0, p1, t), lerp(p1, p2, t), lerp(p2, p3, t)
        d, e = lerp(a, b, t), lerp(b, c, t)
        out.append(lerp(d, e, t))
    return out


def _host(g):
    """The module that built g (forest_build, or a renamed copy of it): its
    _ptube and _bank_r are the ground's own."""
    return sys.modules[g.__class__.__module__]


def _quad_normal(m, ids):
    """The emitted face normal of a registered quad (the side it was built to face)."""
    return norm(ft._newell([m.verts[j] for j in m.quad_corners(ids)]))


def _floor_quad(g, j, i):
    a, b = g.floor[j], g.floor[j + 1]
    n = len(a)
    q = (i + 1) % n
    return (a[i], a[q], b[q], b[i])


def _floor_patch(g, j, i):
    """Two neighbouring floor quads (columns i and i+1 between rings j and j+1):
    a bramble's base ring (BRAMBLE_R[0]) needs the width. None when either is
    missing or not a registered quad (a zipper band)."""
    a, b = g.floor[j], g.floor[j + 1]
    if len(a) != len(b):
        return None
    n = len(a)
    patch = [_floor_quad(g, j, i), _floor_quad(g, j, (i + 1) % n)]
    for q in patch:
        if None in q or not g.m.has_quad(q):
            return None
    return patch


def _sockets(g, r, count, rows, taken, roots, spacing=1.6):
    """``count`` floor patches (j, i) in ``rows``, none overlapping, all real
    quads, spread so no root stands within ``spacing`` of another (``roots``
    is the list of root points so far, extended)."""
    out = []
    tries = 0
    while len(out) < count and tries < 6000:
        tries += 1
        j = r.i(rows[0], rows[1])
        n = len(g.floor[j])
        i = r.i(0, n - 1)
        if (j, i) in taken or (j, (i + 1) % n) in taken or (j, (i - 1) % n) in taken:
            continue
        patch = _floor_patch(g, j, i)
        if patch is None:
            continue
        c = g.m.centroid(sorted(set(v for q in patch for v in q)))
        if any(math.hypot(c[0] - p[0], c[1] - p[1]) < spacing for p in roots):
            continue
        taken.add((j, i))
        taken.add((j, (i + 1) % n))
        roots.append(c)
        out.append((j, i))
    return out


def _height_at(rad):
    """(min, max) bramble height at radius rad: THICKET_H interpolated."""
    (r0, lo0, hi0), (r1, lo1, hi1) = THICKET_H
    u = max(0.0, min(1.0, (rad - r0) / (r1 - r0)))
    return lo0 + (lo1 - lo0) * u, hi0 + (hi1 - hi0) * u


def _bramble_path(g, r, patch, height=None):
    """A path out of the floor patch's centre, climbing to a height set by its
    radius (tallest round the trunk) or given, leaning sideways and twisting
    round as it climbs, jittered on its inner points."""
    m = g.m
    c = m.centroid(sorted(set(v for q in patch for v in q)))
    b0 = -math.degrees(math.atan2(c[1], c[0]))
    r0 = math.hypot(c[0], c[1])
    lo, hi = _height_at(r0) if height is None else height
    h = r.u(lo, hi)
    lean = r.u(*THICKET_LEAN) * h
    a_lean = r.u(0.0, 360.0)                          # which way it leans
    drift = r.u(*THICKET_DRIFT) * r.pick((-1.0, 1.0))
    raw = [c, add(c, UP, 0.6)]
    steps = max(4, int(h / 1.5))
    for k in range(1, steps + 1):
        u = k / float(steps)
        a = math.radians(a_lean + drift * u)
        off = lean * u * u
        p = (c[0] + off * math.cos(a), c[1] + off * math.sin(a), c[2] + h * u)
        rr = math.hypot(p[0], p[1])
        if rr < 8.0:                                  # never into the trunk
            p = (p[0] * 8.0 / rr, p[1] * 8.0 / rr, p[2])
        raw.append(p)
    length = sum(math.sqrt(sum((raw[k][i] - raw[k - 1][i]) ** 2 for i in range(3))) for k in range(1, len(raw)))
    npts = max(BRAMBLE_PTS[0], min(BRAMBLE_PTS[1], int(math.ceil(length / BRAMBLE_SEG)) + 1))
    path = _resample(raw, npts)         # even segments: the tip ring's edge against a long last segment is a sliver
    for k in range(2, npts - 1):
        p = path[k]
        bb = -math.degrees(math.atan2(p[1], p[0]))
        path[k] = add(add(p, ft.tangent(bb), r.u(-1.0, 1.0) * BRAMBLE_WANDER), ft.radial(bb), r.u(-1.0, 1.0) * BRAMBLE_WANDER)
    return path


def _fits(g, quads, path, radius, min_deg=THORN_MIN_DEG):
    """Would a tube of ``radius`` starting down ``path`` socket into the patch
    ``quads`` without a sliver? The same ring _ptube's weld makes, scored the
    way _best_ring scores it."""
    host = _host(g)
    m = g.m
    t, ex, ez = ft.frames(path)[0]
    pn, sx, sy, loop = host._patch_frame(m, quads)
    plane = (m.centroid(loop), pn)
    loop_pts = [m.verts[v] for v in loop]
    best = 0.0
    for k in range(24):
        ph = 2.0 * math.pi * k / 24
        pts = ft.project_ring(host._ring_at(path[0], ex, ez, radius, BRAMBLE_SIDES, 1.0, ph), t, plane)
        best = max(best, host._bridge_quality(loop_pts, pts, pn, sx, sy))
    return best >= math.radians(min_deg)


def _fork(g, r, rings, path, radii):
    """A side branch out of one of the bramble's own quads at FORK_AT along
    it: FORK_L long, climbing and swinging sideways, capped; returns its rings
    and path (for thorns), or None when no quad there is free."""
    m = g.m
    _ptube = _host(g)._ptube
    n = len(rings)
    sides = len(rings[0])
    i = max(1, min(n - 2, int(round(r.u(*FORK_AT) * (n - 1)))))
    for _ in range(6):
        s = r.i(0, sides - 1)
        q = (s + 1) % sides
        q2 = (s + 2) % sides
        patch = [(rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s]),
                 (rings[i][q], rings[i][q2], rings[i + 1][q2], rings[i + 1][q])]   # two sides of five: the ring needs the width
        if not all(m.has_quad(qd) for qd in patch):
            continue
        n_out = norm(add(_quad_normal(m, patch[0]), _quad_normal(m, patch[1])))
        if n_out[2] < -0.3:                       # never out of the underside
            continue
        c = m.centroid(sorted(set(v for qd in patch for v in qd)))
        along = norm(sub(path[i + 1], path[i]))
        L = r.u(*FORK_L)
        d0 = norm(add(n_out, along, 0.4))
        d1 = norm(add(add(along, n_out, 0.5), UP, 0.9))
        raw = [c, add(c, d0, 0.25 * L), add(add(c, d0, 0.5 * L), d1, 0.2 * L), add(add(c, d0, 0.6 * L), d1, 0.5 * L)]
        npts = max(4, int(math.ceil(L / BRAMBLE_SEG)) + 1)
        fpath = _resample(_cubic(raw[0], raw[1], raw[2], raw[3], 24), npts)
        rad = ft._at(radii, i / float(n - 1)) * FORK_R
        if not _fits(g, patch, fpath, rad):
            continue
        frings = _ptube(m, fpath, (rad, rad * 0.75, max(0.075, rad * 0.5)), BRAMBLE_SIDES, STEM_ZONE, start=(patch, STEM_ZONE),
                        caps=(False, True), wob=0.08, rng=r)
        return frings, fpath
    return None


def _resample(pts, n):
    """``n`` points evenly by arc length along the polyline ``pts``."""
    cum = [0.0]
    for k in range(1, len(pts)):
        cum.append(cum[-1] + math.sqrt(sum((pts[k][i] - pts[k - 1][i]) ** 2 for i in range(3))))
    out = []
    for k in range(n):
        want = cum[-1] * k / float(n - 1)
        j = 1
        while j < len(cum) - 1 and cum[j] < want:
            j += 1
        seg = cum[j] - cum[j - 1]
        t = (want - cum[j - 1]) / seg if seg > 1e-9 else 0.0
        out.append(lerp(pts[j - 1], pts[j], t))
    return out


def _thorn(g, m, quad, along, d, local_r=None):
    """One thorn out of a bramble quad: a three-vertex base ring on the quad
    (THORN_R[0] along the bramble, THORN_FLAT of that across it, so the ring
    fits the narrow quad and its bridging keeps its angles) socketed at the
    best phase, a tiny tip ring THORN_L out along ``d``, three quads and a
    cap. Skipped (False) when no phase bridges without a sliver."""
    host = _host(g)
    c = m.centroid(quad)
    n, ex, ey, loop = host._patch_frame(m, [quad])
    across = norm(ft.cross(n, along))
    along = norm(ft.cross(across, n))
    a = THORN_R[0] if local_r is None else min(THORN_R[0], local_r * 1.2)   # a thin twig takes a smaller thorn
    b = a * THORN_FLAT
    length = THORN_L * math.sqrt(a / THORN_R[0])
    pts_fn = lambda ph: [add(add(c, along, a * math.cos(ph + 2.0 * math.pi * s / 3)), across, b * math.sin(ph + 2.0 * math.pi * s / 3)) for s in range(3)]
    loop_pts = [m.verts[v] for v in loop]
    best = None
    for k in range(24):
        ph = 2.0 * math.pi * k / 24
        pts = pts_fn(ph)
        q = host._bridge_quality(loop_pts, pts, n, ex, ey)
        if best is None or q > best[0]:
            best = (q, ph, pts)
    if best[0] < math.radians(THORN_MIN_DEG):
        return False
    base = [m.v(p) for p in best[2]]
    m.socket([quad], base, THORN_ZONE)
    tip_c = add(c, d, length)
    tr = max(0.045, THORN_R[1] * math.sqrt(a / THORN_R[0]))
    tip = [m.v(add(add(tip_c, along, tr * math.cos(best[1] + 2.0 * math.pi * s / 3)),
                   across, tr * math.sin(best[1] + 2.0 * math.pi * s / 3))) for s in range(3)]
    axis = lerp(c, tip_c, 0.5)
    for s in range(3):
        q = (s + 1) % 3
        idx = (base[s], base[q], tip[q], tip[s])
        m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), axis), THORN_ZONE)
    m.tri(tip[0], tip[1], tip[2], d, THORN_ZONE)
    return True


def _thorns(g, r, rings, path, want_range=None):
    """THORNS thorns grown out of the bramble's own quads (socketed), on its
    thicker half, leaning toward the tip, at most two per segment."""
    m = g.m
    n = len(rings)
    sides = len(rings[0])
    slots = [(i, s) for i in range(n - 1) if i / float(n - 1) <= THORN_MAX_U for s in range(sides)]
    want = r.i(*(want_range or THORNS))
    made = 0
    used_seg = {}
    while made < want and slots:
        i, s = slots.pop(r.i(0, len(slots) - 1))
        if used_seg.get(i, 0) >= 2:
            continue
        q = (s + 1) % sides
        quad = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
        if not m.has_quad(quad):
            continue
        n_out = _quad_normal(m, quad)
        along = norm(sub(path[i + 1], path[i]))
        d = norm(add(add(n_out, along, THORN_LEAN), ft.tangent(r.u(0.0, 360.0)), 0.12))
        if dot(d, n_out) < 0.6:
            d = n_out
        local_r = sum(math.dist(m.verts[v], path[i]) for v in rings[i]) / float(sides)
        if local_r < 0.085:                       # too thin a twig for a thorn ring
            continue
        if _thorn(g, m, quad, along, d, local_r):
            used_seg[i] = used_seg.get(i, 0) + 1
            made += 1
    return made


def brambles(g):
    """The thicket: BRAMBLES thorny branches out of the pit floor, five-sided
    tapered tubes (BRAMBLE_R) socketed into two-quad floor patches, climbing
    THICKET_H (tallest round the trunk) and leaning, with FORKS side branches
    and THORNS thorns each, socketed into the bramble's own quads. Fills INFO
    for the check."""
    m = g.m
    _ptube = _host(g)._ptube
    r = ft._Rng(PIT_SEED)
    taken = set()
    roots = []
    spots = _sockets(g, r, BRAMBLES, BRAMBLE_ROWS, taken, roots)
    scrub = _sockets(g, r, SCRUB, BRAMBLE_ROWS, taken, roots, SCRUB_SPACING)
    v0 = len(m.verts)
    count = thorns = forks = 0
    for (spot_list, tall) in ((spots, True), (scrub, False)):
        for (j, i) in spot_list:
            patch = _floor_patch(g, j, i)
            if patch is None:
                continue
            radii = BRAMBLE_R if tall else SCRUB_R
            path = _bramble_path(g, r, patch, None if tall else SCRUB_H)
            if not _fits(g, patch, path, radii[0]):
                continue
            rings = _ptube(m, path, radii, BRAMBLE_SIDES, STEM_ZONE, start=(patch, "cell"),
                           caps=(False, True), wob=0.08, rng=r)
            if tall:
                for _ in range(r.i(*FORKS)):
                    fork = _fork(g, r, rings, path, radii)
                    if fork is not None:
                        thorns += _thorns(g, r, fork[0], fork[1])
                        forks += 1
            thorns += _thorns(g, r, rings, path, THORNS if tall else SCRUB_THORNS)
            count += 1
    top = (0.0, -1e9)
    for p in m.verts[v0:]:
        if p[2] > top[1]:
            top = (math.hypot(p[0], p[1]), p[2])
    INFO["brambles"], INFO["thorns"], INFO["forks"], INFO["top"] = count, thorns, forks, top
    INFO["max_r"] = max(math.hypot(p[0], p[1]) for p in m.verts[v0:]) if count else 0.0


# =============================================================================
# FOG
# =============================================================================

def _ease(u):
    return 0.5 - 0.5 * math.cos(math.pi * u)


def fog_mesh(cls, g):
    """Nine stacked discs (FOG_Z), each a FOG_N-gon of three annuli: a hole
    ring round the trunk (alpha 0 at FOG_HOLE[0], full at FOG_HOLE[1]), full
    alpha out to bank_r(z) + FOG_BANK[0], zero at bank_r(z) + FOG_BANK[1]
    inside the bank, so no edge ever shows. Alpha FOG_ALPHA[0] at the bottom
    layer easing to FOG_ALPHA[1] at the top; the tint FOG_TINT, dimmed
    FOG_DEPTH_DIM at the bottom. The bottom layer's vertices come first: the
    triangle order is the blend order, seen from above."""
    _bank_r = _host(g)._bank_r
    m = cls()
    z0, z1, pitch = FOG_Z
    layers = []
    z = z0
    while z <= z1 + 1e-6:
        layers.append(z)
        z += pitch
    INFO["layers"] = []
    for k, z in enumerate(layers):
        u = k / float(len(layers) - 1)
        alpha = FOG_ALPHA[0] + (FOG_ALPHA[1] - FOG_ALPHA[0]) * _ease(u)
        dim = FOG_DEPTH_DIM + (1.0 - FOG_DEPTH_DIM) * u
        tint = (FOG_TINT[0] * dim, FOG_TINT[1] * dim, FOG_TINT[2] * dim)
        br = _bank_r(z)
        radii = [(FOG_HOLE[0], 0.0), (FOG_HOLE[1], alpha), (br + FOG_BANK[0], alpha), (br + FOG_BANK[1], 0.0)]
        rings = []
        for (rad, a) in radii:
            rings.append([m.cv(pol(360.0 * s / FOG_N, rad, z), tint + (a,)) for s in range(FOG_N)])
        for i in range(len(rings) - 1):
            for s in range(FOG_N):
                q = (s + 1) % FOG_N
                m.quad(rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s], UP, "fog")
        INFO["layers"].append((z, round(alpha, 3), round(br + FOG_BANK[1], 2)))
    return m
