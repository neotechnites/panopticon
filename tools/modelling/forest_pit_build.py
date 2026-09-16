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

# ---- the floor -----------------------------------------------------------------
FLOOR_RINGS = [(31.0, 120), (20.0, 60), (9.0, 24)]   # (r, vertices) inward from the bank's 240

# ---- the fog: nine 48-gon discs, each three annuli of vertex alpha ----------------
FOG_Z = (-7.0, 20.0, 3.0)       # bottom, top, pitch: y -7 .. 20, ten layers; the top ones are thin, so the
                                # bank fades into the fog instead of meeting a surface
FOG_N = 48
FOG_HOLE = (6.8, 10.0)          # round the trunk: alpha 0 at 6.8 (outside the trunk, r <= 6.4 above the roots,
                                # so no disc cuts it into rings), full at 10.0
FOG_BANK = (-2.5, 0.6)          # full alpha out to bank_r(z) - 2.5, zero at bank_r(z) + 0.6 (inside the bank)
FOG_ALPHA = (0.36, 0.05)        # the bottom layer, easing to the top layer (a haze, not a lid)
FOG_DEPTH_DIM = 0.70            # the tint at the bottom layer, as a factor; 1.0 at the top: darker at depth

# ---- brambles: thorny branches socketed into the bank -----------------------------
PIT_SEED = 4471023              # its own rng: editing the brambles diffs only the brambles
BRAMBLES = 26
ARCHING = 8                     # ... of which this many arch up over the lip
BRAMBLE_QUAD_ROWS = (3, 6)      # bank quads between pit rows j and j+1, j in this range (rows 3..7, y 21.5..14.3)
ARCH_QUAD_ROWS = (3, 5)         # the arching ones start high on the bank
BRAMBLE_AVOID = ((350.0, 6.0), (5.0, 6.0), (335.0, 6.0))   # (bearing, half width): the fence, the portal, the spawn
BRAMBLE_PTS = (6, 9)            # points along a path ...
BRAMBLE_SEG = 1.15              # ... one per this much length, within that
BRAMBLE_R = (0.26, 0.20, 0.14, 0.08)
BRAMBLE_SIDES = 5
BRAMBLE_OUT = (2.0, 6.0)        # how far a pit bramble twists out over the pit
BRAMBLE_WANDER = 0.22           # per-point sideways / vertical jitter on the inner points
ARCH_END_R = (47.2, 48.0)       # where an arching bramble ends: over the lane's lip band ...
ARCH_END_Z = (23.9, 24.8)       # ... this high, never past r 48.5
ARCH_PEAK_Z = 25.7              # the bezier's pull over the lip (the curve itself stays under 25)
ARCH_SWING = 4.0                # degrees of sideways drift, end to start
THORNS = (4, 7)
THORN_R = (0.08, 0.02)          # base ring (along the bramble) and tip ring
THORN_FLAT = 0.6                # the base ring across the bramble, as a fraction: a blade, and it fits the quad
THORN_MIN_DEG = 3.5             # a thorn whose best bridging makes a smaller angle is not grown
THORN_L = 0.35
THORN_LEAN = 0.45               # toward the bramble's tip, as a fraction of the normal
THORN_MAX_U = 0.5               # thorns sit on the thicker half of a bramble (the ring must fit the quad)

# what the check reports
INFO = {"brambles": 0, "thorns": 0, "top": (0.0, 0.0), "layers": []}


def pit_floor(g):
    """The floor: rings inward from the bank's last row, thinning out to a small fan."""
    m = g.m
    outer = g.pit[-1]
    for (rad, n) in FLOOR_RINGS:
        z = g.m.verts[outer[0]][2]
        ring = [m.v(pol(360.0 * s / n, rad, z)) for s in range(n)]
        zipper(m, outer, ring, UP, "cell", centre=(0.0, 0.0, 0.0))
        outer = ring
    m.fan(outer, UP, "cell")


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


def _bank_quad(g, j, i):
    NC = len(g.pit[0])
    q = (i + 1) % NC
    return (g.pit[j][i], g.pit[j][q], g.pit[j + 1][q], g.pit[j + 1][i])


def _sockets(g, r, count, rows, taken):
    """``count`` bank quads (j, i) in ``rows``, off the fence, the portal and the
    spawn, none twice, all real quads (the cell hollows and the split sill lines
    are not)."""
    NC = len(g.pit[0])
    out = []
    tries = 0
    while len(out) < count and tries < 4000:
        tries += 1
        j = r.i(rows[0], rows[1])
        i = r.i(0, NC - 1)
        if (j, i) in taken:
            continue
        b = i * 360.0 / NC + 180.0 / NC
        if any(_near(b, tb, w) for (tb, w) in BRAMBLE_AVOID):
            continue
        quad = _bank_quad(g, j, i)
        if None in quad or not g.m.has_quad(quad):
            continue
        taken.add((j, i))
        out.append((j, i))
    return out


def _bramble_path(g, r, quad, arch):
    """A wandering path out of the bank quad's centre: a cubic bezier in the
    radial plane with sideways drift, jittered on its inner points. Arching
    ones climb over the lip and end above the lane's lip band; the rest twist
    out over the pit."""
    m = g.m
    c = m.centroid(quad)
    n_in = _quad_normal(m, quad)                      # the bank faces the axis
    if dot(n_in, (-c[0], -c[1], 0.0)) < 0.0:
        n_in = (-n_in[0], -n_in[1], -n_in[2])
    b = -math.degrees(math.atan2(c[1], c[0]))         # bearing of the socket
    r0, z0 = math.hypot(c[0], c[1]), c[2]
    tn = ft.tangent(b)
    if arch:
        swing = r.u(-ARCH_SWING, ARCH_SWING)
        re, ze = r.u(*ARCH_END_R), r.u(*ARCH_END_Z)
        p1 = add(add(c, n_in, 1.6), UP, 0.5)
        p2 = pol(b + swing * 0.5, r0 - 0.8, ARCH_PEAK_Z)
        p3 = pol(b + swing, re, ze)
        raw = _cubic(c, p1, p2, p3, 48)
    else:
        L = r.u(*BRAMBLE_OUT)
        side = r.u(-1.0, 1.0)
        lift = r.u(-0.5, 0.35)
        p1 = add(add(c, n_in, 0.35 * L), UP, 0.25)
        p2 = add(add(add(c, n_in, 0.7 * L), tn, side * 0.3 * L), UP, lift * 0.5 * L)
        p3 = add(add(add(c, n_in, L), tn, side * 0.5 * L), UP, lift * L)
        raw = _cubic(c, p1, p2, p3, 48)
    length = sum(math.sqrt(sum((raw[k][i] - raw[k - 1][i]) ** 2 for i in range(3))) for k in range(1, len(raw)))
    npts = max(BRAMBLE_PTS[0], min(BRAMBLE_PTS[1], int(math.ceil(length / BRAMBLE_SEG)) + 1))
    path = _resample(raw, npts)         # even segments: the tip ring's edge against a long last segment is a sliver
    # the wander: sideways and vertical jitter on the inner points; the first
    # segment keeps its direction (it sets the socket ring's projection)
    for k in range(2, npts - 1):
        path[k] = add(add(path[k], tn, r.u(-1.0, 1.0) * BRAMBLE_WANDER), UP, r.u(-1.0, 1.0) * BRAMBLE_WANDER)
    return path


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


def _thorn(g, m, quad, along, d):
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
    a, b = THORN_R[0], THORN_R[0] * THORN_FLAT
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
    m.socket([quad], base, "root")
    tip_c = add(c, d, THORN_L)
    tip = [m.v(add(add(tip_c, along, THORN_R[1] * math.cos(best[1] + 2.0 * math.pi * s / 3)),
                   across, THORN_R[1] * math.sin(best[1] + 2.0 * math.pi * s / 3))) for s in range(3)]
    axis = lerp(c, tip_c, 0.5)
    for s in range(3):
        q = (s + 1) % 3
        idx = (base[s], base[q], tip[q], tip[s])
        m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), axis), "root")
    m.tri(tip[0], tip[1], tip[2], d, "root")
    return True


def _thorns(g, r, rings, path):
    """THORNS thorns grown out of the bramble's own quads (socketed), on its
    thicker half, leaning toward the tip, at most two per segment."""
    m = g.m
    n = len(rings)
    sides = len(rings[0])
    slots = [(i, s) for i in range(n - 1) if i / float(n - 1) <= THORN_MAX_U for s in range(sides)]
    want = r.i(*THORNS)
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
        if _thorn(g, m, quad, along, d):
            used_seg[i] = used_seg.get(i, 0) + 1
            made += 1
    return made


def brambles(g):
    """BRAMBLES thorny branches out of the bank: five-sided tapered tubes
    (BRAMBLE_R) socketed into bank quads on rows BRAMBLE_QUAD_ROWS, ARCHING of
    them climbing over the lip to end above the lane's lip band, the rest
    twisting out over the pit; THORNS three-sided thorns each, socketed into
    the bramble's own quads. Zone "root". Fills INFO for the check."""
    m = g.m
    _ptube = _host(g)._ptube
    r = ft._Rng(PIT_SEED)
    taken = set()
    arch_spots = _sockets(g, r, ARCHING, ARCH_QUAD_ROWS, taken)
    pit_spots = _sockets(g, r, BRAMBLES - len(arch_spots), BRAMBLE_QUAD_ROWS, taken)
    v0 = len(m.verts)
    count = thorns = 0
    for (spots, arch) in ((arch_spots, True), (pit_spots, False)):
        for (j, i) in spots:
            quad = _bank_quad(g, j, i)
            path = _bramble_path(g, r, quad, arch)
            rings = _ptube(m, path, BRAMBLE_R, BRAMBLE_SIDES, "root", start=([quad], "earth"),
                           caps=(False, True), wob=0.08, rng=r)
            thorns += _thorns(g, r, rings, path)
            count += 1
    top = (0.0, -1e9)
    for p in m.verts[v0:]:
        if p[2] > top[1]:
            top = (math.hypot(p[0], p[1]), p[2])
    INFO["brambles"], INFO["thorns"], INFO["top"] = count, thorns, top
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
