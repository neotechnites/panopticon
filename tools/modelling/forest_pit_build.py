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
FOG_Z = (-7.0, 13.0, 2.5)       # bottom, top, pitch: y -7 .. 13, nine layers; the top is 10 m under the rim
                                # (y 23) and thin, so the bank above it stands clear and fades into the fog
FOG_N = 48
FOG_HOLE = (6.8, 10.0)          # round the trunk: alpha 0 at 6.8 (outside the trunk, r <= 6.4 above the roots,
                                # so no disc cuts it into rings), full at 10.0
FOG_BANK = (-2.5, 0.6)          # full alpha out to bank_r(z) - 2.5, zero at bank_r(z) + 0.6 (inside the bank)
FOG_ALPHA = (0.42, 0.06)        # the bottom layer, easing to the top layer (a haze, not a lid)
FOG_DEPTH_DIM = 0.70            # the tint at the bottom layer, as a factor; 1.0 at the top: darker at depth

# ---- brambles: thorny branches socketed into the bank -----------------------------
PIT_SEED = 4471023              # its own rng: editing the brambles diffs only the brambles
BRAMBLES = 36                   # thorny branches rising out of the fog and climbing the bank
ARCHING = 14                    # ... of which this many reach over the rim onto the lane's edge
BRAMBLE_QUAD_ROWS = (7, 9)      # bank quads between pit rows j and j+1: rows 7..10, y 14.3..8.9, in and just over the fog top (13)
ARCH_QUAD_ROWS = (7, 8)         # the over-rim ones start a little higher (they have the longest climb)
BRAMBLE_AVOID = ((350.0, 7.0), (5.0, 6.0), (335.0, 6.0))   # (bearing, half width): the fence, the portal, the spawn
BRAMBLE_PTS = (8, 22)           # points along a path ...
BRAMBLE_SEG = 1.15              # ... one per this much length, within that
BRAMBLE_R = (0.42, 0.36, 0.28, 0.17, 0.065)   # the tip is a point (its ring edge still clears the sliver angle)
BRAMBLE_SIDES = 5
BRAMBLE_STAND = 0.45            # a climbing bramble runs this far in front of the bank
BRAMBLE_TOP_Z = (18.5, 22.4)    # where a pit bramble's climb ends (under the lip) ...
BRAMBLE_LEAN = (1.0, 2.2)       # ... its last stretch leaning out from the wall this far
BRAMBLE_DRIFT = (8.0, 16.0)     # degrees of sideways drift over the climb (either way)
BRAMBLE_WANDER = 0.3            # per-point sideways / radial jitter on the inner points
ARCH_END_R = (47.4, 48.3)       # where an over-rim bramble ends: on the lane's lip band ...
ARCH_END_Z = (23.5, 24.4)       # ... this high, never past r 48.6 (the path starts at r 50.5)
ARCH_PEAK_Z = 24.9              # the climb's pull over the lip (with the wander the curve stays under 25.3)
FORKS = (1, 2)                  # side branches per bramble, out of its own quads
FORK_AT = (0.3, 0.6)            # ... along the bramble
FORK_L = (3.0, 6.0)             # ... this long, climbing and swinging sideways
FORK_R = 0.55                   # ... this fraction of the parent's radius there
THORNS = (7, 12)
THORN_R = (0.2, 0.07)           # base ring (along the bramble) and tip ring
THORN_FLAT = 0.6                # the base ring across the bramble, as a fraction: a blade, and it fits the quad
THORN_MIN_DEG = 4.0             # a thorn whose best bridging makes a smaller angle is not grown
THORN_L = 0.9
THORN_LEAN = 0.45               # toward the bramble's tip, as a fraction of the normal
THORN_MAX_U = 1.0               # thorns sit where the bramble is thick enough for the ring to fit its quad
THORN_ZONE = "cell"             # the darkest sheet: thorns and stems read as black spikes against the fog and the bank
STEM_ZONE = "cell"

# what the check reports
INFO = {"brambles": 0, "thorns": 0, "forks": 0, "top": (0.0, 0.0), "layers": []}


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


def _bank_patch(g, j, i):
    """Two neighbouring bank quads (columns i and i+1 of row j): a bramble's base
    ring (BRAMBLE_R[0]) needs the width. None when either is missing."""
    NC = len(g.pit[0])
    patch = [_bank_quad(g, j, i), _bank_quad(g, j, (i + 1) % NC)]
    for q in patch:
        if None in q or not g.m.has_quad(q):
            return None
    return patch


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
        if (j, i) in taken or (j, (i + 1) % NC) in taken or (j, (i - 1) % NC) in taken:
            continue
        b = i * 360.0 / NC + 360.0 / NC
        if any(_near(b, tb, w) for (tb, w) in BRAMBLE_AVOID):
            continue
        patch = _bank_patch(g, j, i)
        if patch is None:
            continue
        taken.add((j, i))
        taken.add((j, (i + 1) % NC))
        out.append((j, i))
    return out


def _bramble_path(g, r, quad, arch):
    """A path out of the bank patch's centre (two quads) that climbs the bank: it runs
    BRAMBLE_STAND in front of the wall (bank_r(z) - STAND), drifting sideways
    BRAMBLE_DRIFT degrees over the climb, jittered on its inner points. Over-rim
    ones climb to the lip, curl over the round-over and end on the lane's lip
    band; the rest stop under the lip (BRAMBLE_TOP_Z) leaning out from the wall."""
    m = g.m
    bank_r = _host(g)._bank_r
    c = m.centroid(sorted(set(v for q in quad for v in q)))
    n_in = norm(add(_quad_normal(m, quad[0]), _quad_normal(m, quad[1])))   # the bank faces the axis
    if dot(n_in, (-c[0], -c[1], 0.0)) < 0.0:
        n_in = (-n_in[0], -n_in[1], -n_in[2])
    b0 = -math.degrees(math.atan2(c[1], c[0]))        # bearing of the socket
    z0 = c[2]
    drift = r.u(*BRAMBLE_DRIFT) * r.pick((-1.0, 1.0))
    raw = [c, add(c, n_in, 0.6)]                      # leave the wall square to it
    if arch:
        z_top = 23.0
    else:
        z_top = r.u(*BRAMBLE_TOP_Z)
    steps = max(4, int((z_top - z0) / 1.5))
    for k in range(1, steps + 1):
        u = k / float(steps)
        z = z0 + (z_top - z0) * u
        raw.append(pol(b0 + drift * u, bank_r(z) - BRAMBLE_STAND, z))
    if arch:
        re, ze = r.u(*ARCH_END_R), r.u(*ARCH_END_Z)
        b1 = b0 + drift
        raw.append(pol(b1, 46.5, ARCH_PEAK_Z - 0.6))
        raw.append(pol(b1 + drift * 0.08, 47.0, ARCH_PEAK_Z))
        raw.append(pol(b1 + drift * 0.15, re, ze))
    else:
        lean = r.u(*BRAMBLE_LEAN)
        b1 = b0 + drift
        raw.append(pol(b1 + drift * 0.06, bank_r(z_top) - BRAMBLE_STAND - lean * 0.6, z_top + 0.8))
        raw.append(pol(b1 + drift * 0.12, bank_r(z_top) - BRAMBLE_STAND - lean, z_top + 1.2))
    length = sum(math.sqrt(sum((raw[k][i] - raw[k - 1][i]) ** 2 for i in range(3))) for k in range(1, len(raw)))
    npts = max(BRAMBLE_PTS[0], min(BRAMBLE_PTS[1], int(math.ceil(length / BRAMBLE_SEG)) + 1))
    path = _resample(raw, npts)         # even segments: the tip ring's edge against a long last segment is a sliver
    # the wander: sideways and radial jitter on the inner points; the first
    # segment keeps its direction (it sets the socket ring's projection)
    for k in range(2, npts - 1):
        p = path[k]
        bb = -math.degrees(math.atan2(p[1], p[0]))
        path[k] = add(add(p, ft.tangent(bb), r.u(-1.0, 1.0) * BRAMBLE_WANDER), ft.radial(bb), r.u(-1.0, 0.3) * BRAMBLE_WANDER)
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
        local_r = sum(math.dist(m.verts[v], path[i]) for v in rings[i]) / float(sides)
        if local_r < 0.085:                       # too thin a twig for a thorn ring
            continue
        if _thorn(g, m, quad, along, d, local_r):
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
    count = thorns = forks = 0
    for (spots, arch) in ((arch_spots, True), (pit_spots, False)):
        for (j, i) in spots:
            patch = _bank_patch(g, j, i)
            if patch is None:
                continue
            path = _bramble_path(g, r, patch, arch)
            if not _fits(g, patch, path, BRAMBLE_R[0]):
                continue
            rings = _ptube(m, path, BRAMBLE_R, BRAMBLE_SIDES, STEM_ZONE, start=(patch, "earth"),
                           caps=(False, True), wob=0.08, rng=r)
            for _ in range(r.i(*FORKS)):
                fork = _fork(g, r, rings, path, BRAMBLE_R)
                if fork is not None:
                    thorns += _thorns(g, r, fork[0], fork[1])
                    forks += 1
            thorns += _thorns(g, r, rings, path)
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
