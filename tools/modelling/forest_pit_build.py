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
FOG_TINT = (0.26, 0.28, 0.22)   # gold-grey-green, kept dim: a column stacks fourteen layers, and unshaded
                                # fog brighter than the sunlit lane reads as milk, not gloom. Godot shows
                                # this x 0.6 (the override's albedo), so the floor end lands near 0.08


# ---- the fog: a stack of translucent discs standing in for a fog volume -----------
# Read as a pit, not a lid: the alpha falls to zero at the top layer (no top plane to
# see), feathers a long way into the bank, wobbles low-frequency round and up so no
# disc reads as a sheet, and darkens with depth. GL Compatibility has no fog volumes.
FOG_Z = (-11.6, 4.0, 1.2)       # bottom (just under the floor at -11.05), top, pitch: 14 layers, the top
                                # one at alpha 0 so the fog ends in air, never on a plane
FOG_N = 36                      # segments round: 14 layers x 5 bands x 36 x 2 = 5040 tris, which is
                                # what the forest has left under its 130k budget (the fog is a tenth of it)
FOG_HOLE = (6.8, 13.0)          # round the trunk: alpha 0 at 6.8 (outside the trunk, r <= 6.4 above the
                                # roots) easing to full at 13.0 -- a wide inner feather, no ring edge
FOG_BANK = (-9.0, 0.6)          # the rim feather: full alpha out to bank_r(z) - 9.0, zero 0.6 m INSIDE
                                # the bank, so the fog thins for nine metres before it ever meets earth
FOG_MID = 0.5                   # a ring this far across the full-alpha span: the wobble varies radially
FOG_FEATHER = 0.42              # alpha at the middle of the rim feather (eased, not a straight ramp)
FOG_ALPHA = 0.45                # the bottom layer ... (0.18 was invisible in Godot: the pit floor is sunlit, and a
                                # column has to stack to ~0.85 opacity to put that floor into gloom; the scene's
                                # FogMat alpha can only scale this DOWN)
FOG_CURVE = 1.6                 # ... falling as (1 - u/reach)^FOG_CURVE to exactly 0 where the column ends
FOG_DEPTH_DIM = 0.50            # the tint at the bottom layer, as a factor; 1.0 at the top: gloom below
FOG_REACH = 0.65                # how high a column of fog climbs, as a fraction of the stack: FOG_REACH in
                                # the thin places, 1.0 in the thick ones, set by the drift field -- the top
                                # of the fog ROLLS instead of lying flat, and never reaches past the top
                                # layer, which is therefore alpha 0 all the way round: no plane to see
FOG_DENSE = 0.30                # ... and the same field thickens and thins the column, +/- this much
FOG_DRIFT = ((3, 0.05, 0.0, 0.45),     # (lobes round, radians per metre up, phase, weight): low frequency and
             (5, -0.03, 1.90, 0.35),   # ALMOST vertical -- a bank thick here and thin there leans slowly as
             (8, 0.02, 4.10, 0.20))    # it climbs, where a fast z term would average out over the stack
FOG_RADIAL = (0.16, 2.3, 0.35)         # one more drift term across the radius (radians per metre, phase,
                                       # weight): a 40 m period, two samples a ring apart -- patches, not stripes
FOG_GAIN = 1.7                         # the sines rarely line up, so the field is scaled to its range and
                                       # clipped: banks with thick middles, not a gentle swell

# ---- the thicket: brambles out of the floor, a mass across the pit bottom ---------
PIT_SEED = 4471023              # its own rng: editing the brambles diffs only the brambles
FLOOR_Z = -11.05                # the floor (the bank's last row)
FLOOR_RINGS = [(38.0, 120)] + [(38.0 - 1.5 * k, 120) for k in range(1, 19)] + [(7.0, 60)]   # r 38 in to 11 by 1.5, then 7
                                # (r, vertices) inward from the bank's 240: equal counts loft into quads (the
                                # brambles' sockets), the count halves by a zipper, the centre is a fan under the trunk
# A bramble is a three-sided tube whose rings are barbed: one vertex of every
# ring is pushed out SPIKE, the side rotating ring to ring, so the stem itself
# is a zigzag of thorns and costs nothing beyond its six triangles a segment.
# No separate thorn geometry: at PLANTS plants that is what keeps the thicket
# inside the contract.
PLANTS = 1150                   # tall ones (a fifth) and scrub, spread over the floor
TALL_SHARE = 0.22
PLANT_ROWS = (1, 18)            # floor quads between rings j and j+1 (rings 1..19: r 38 in to 11)
PLANT_SPACING = 1.0             # a root keeps this far from every other root
TALL_H = ((9.0, 6.5, 8.5), (38.0, 4.0, 6.0))   # (r, min height, max height) at the trunk and at the bank: tallest round the trunk
SCRUB_H = ((9.0, 4.0, 6.5), (38.0, 2.5, 4.5))
TALL_R = (0.3, 0.24, 0.16, 0.08)
SCRUB_R = (0.2, 0.15, 0.08)
RING_STEP = 1.1                 # metres between barbed rings along a plant
SPIKE = (0.35, 0.65)            # how far the barb vertex stands out of the stem
PLANT_LEAN = (0.3, 0.7)         # a plant's top sits this fraction of its height sideways from its root
PLANT_DRIFT = (20.0, 90.0)      # degrees the lean swings round as it climbs (a twist)
PLANT_WANDER = 0.35             # per-point jitter on the inner points
FORK_SHARE = 0.6                # of the tall ones, this share gets a side branch out of one quad of the stem
FORK_AT = (0.3, 0.6)            # ... along the stem
FORK_L = (2.0, 4.0)             # ... this long, climbing and swinging sideways
FORK_R = 0.6                    # ... this fraction of the parent's radius there
SOCKET_MIN_DEG = 4.0            # a socket whose best bridging makes a smaller angle is not grown
STEM_ZONE = "cell"              # the darkest sheet: the thicket reads as black spikes against the fog

# what the check reports
INFO = {"brambles": 0, "tall": 0, "forks": 0, "top": (0.0, 0.0), "layers": []}


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


def _floor_patch(g, j, i, width=1):
    """``width`` neighbouring floor quads (columns i.. between rings j and j+1);
    None when any is missing or not a registered quad (a zipper band)."""
    a, b = g.floor[j], g.floor[j + 1]
    if len(a) != len(b):
        return None
    n = len(a)
    patch = [_floor_quad(g, j, (i + k) % n) for k in range(width)]
    for q in patch:
        if None in q or not g.m.has_quad(q):
            return None
    return patch


def _sockets(g, r, count, rows, spacing):
    """``count`` floor quads (j, i) in ``rows``, all real quads, none twice,
    spread so no root stands within ``spacing`` of another. A cell grid keeps
    the spacing test cheap at this many plants."""
    out = []
    cells = {}
    taken = set()
    tries = 0
    while len(out) < count and tries < 40000:
        tries += 1
        j = r.i(rows[0], rows[1])
        n = len(g.floor[j])
        i = r.i(0, n - 1)
        if (j, i) in taken:
            continue
        patch = _floor_patch(g, j, i)
        if patch is None:
            continue
        c = g.m.centroid(patch[0])
        key = (int(math.floor(c[0] / spacing)), int(math.floor(c[1] / spacing)))
        near = False
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for p in cells.get((key[0] + dx, key[1] + dy), ()):
                    if math.hypot(c[0] - p[0], c[1] - p[1]) < spacing:
                        near = True
        if near:
            continue
        taken.add((j, i))
        cells.setdefault(key, []).append(c)
        out.append((j, i))
    return out


def _height_at(table, rad):
    """(min, max) plant height at radius rad: the table interpolated."""
    (r0, lo0, hi0), (r1, lo1, hi1) = table
    u = max(0.0, min(1.0, (rad - r0) / (r1 - r0)))
    return lo0 + (lo1 - lo0) * u, hi0 + (hi1 - hi0) * u


def _plant_path(g, r, c, table):
    """A path out of ``c`` climbing to a height set by its radius (tallest
    round the trunk), leaning sideways and twisting round as it climbs,
    jittered on its inner points, never inside r 8 (the trunk)."""
    r0 = math.hypot(c[0], c[1])
    lo, hi = _height_at(table, r0)
    h = r.u(lo, hi)
    lean = r.u(*PLANT_LEAN) * h
    a_lean = r.u(0.0, 360.0)
    drift = r.u(*PLANT_DRIFT) * r.pick((-1.0, 1.0))
    raw = [c, add(c, UP, 0.45)]
    steps = max(3, int(h / 1.2))
    for k in range(1, steps + 1):
        u = k / float(steps)
        a = math.radians(a_lean + drift * u)
        off = lean * u * u
        p = (c[0] + off * math.cos(a), c[1] + off * math.sin(a), c[2] + h * u)
        rr = math.hypot(p[0], p[1])
        if rr < 8.0:
            p = (p[0] * 8.0 / rr, p[1] * 8.0 / rr, p[2])
        raw.append(p)
    length = sum(math.sqrt(sum((raw[k][i] - raw[k - 1][i]) ** 2 for i in range(3))) for k in range(1, len(raw)))
    npts = max(3, int(round(length / RING_STEP)) + 1)
    path = _resample(raw, npts)
    for k in range(2, npts - 1):
        p = path[k]
        bb = -math.degrees(math.atan2(p[1], p[0]))
        path[k] = add(add(p, ft.tangent(bb), r.u(-1.0, 1.0) * PLANT_WANDER), ft.radial(bb), r.u(-1.0, 1.0) * PLANT_WANDER)
    return path


def _barbed_tube(g, r, path, radii, patch, zone):
    """A three-sided tube along ``path`` grown out of ``patch`` (its first ring
    socketed at the best phase, refused when no phase bridges without a
    sliver), every later ring barbed: vertex (i mod 3) pushed out SPIKE. Tip
    capped. Returns the rings, or None."""
    host = _host(g)
    m = g.m
    fr = ft.frames(path)
    n = len(path)
    t, ex, ez = fr[0]
    pn, sx, sy, loop = host._patch_frame(m, patch)
    plane = (m.centroid(loop), pn)
    r0 = ft._at(radii, 0.0)
    pts_fn = lambda ph: ft.project_ring(host._ring_at(path[0], ex, ez, r0, 3, 1.0, ph), t, plane)
    loop_pts = [m.verts[v] for v in loop]
    best = None
    for k in range(24):
        ph = 2.0 * math.pi * k / 24
        pts = pts_fn(ph)
        q = host._bridge_quality(loop_pts, pts, pn, sx, sy)
        if best is None or q > best[0]:
            best = (q, ph, pts)
    if best[0] < math.radians(SOCKET_MIN_DEG):
        return None
    ids = [m.v(p) for p in best[2]]
    m.socket(patch, ids, zone)
    rings = [ids]
    ph = best[1]
    for i in range(1, n):
        t, ex, ez = fr[i]
        rad = ft._at(radii, i / float(n - 1))
        spike = (i % 3, r.u(*SPIKE))
        ring = []
        for s in range(3):
            a = ph + 2.0 * math.pi * s / 3
            rr = rad + (spike[1] if s == spike[0] and i < n - 1 else 0.0)
            ring.append(m.v(add(add(path[i], ex, rr * math.cos(a)), ez, rr * math.sin(a))))
        rings.append(ring)
    for i in range(n - 1):
        axis = lerp(path[i], path[i + 1], 0.5)
        for s in range(3):
            q = (s + 1) % 3
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), axis), zone)
    m.tri(rings[-1][0], rings[-1][1], rings[-1][2], fr[-1][0], zone)
    return rings


def _fork(g, r, rings, path, radii):
    """A side branch out of one quad of the stem at FORK_AT along it:
    FORK_L long, climbing and swinging sideways, barbed like the stem."""
    m = g.m
    n = len(rings)
    i = max(1, min(n - 2, int(round(r.u(*FORK_AT) * (n - 1)))))
    s = r.i(0, 2)
    q = (s + 1) % 3
    patch = [(rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])]   # one side of three: two would fold in the plane
    if not m.has_quad(patch[0]):
        return None
    n_out = _quad_normal(m, patch[0])
    if n_out[2] < -0.3:
        return None
    c = m.centroid(sorted(set(v for qd in patch for v in qd)))
    along = norm(sub(path[i + 1], path[i]))
    L = r.u(*FORK_L)
    d0 = norm(add(n_out, along, 0.4))
    d1 = norm(add(add(along, n_out, 0.5), UP, 0.9))
    raw = [c, add(c, d0, 0.25 * L), add(add(c, d0, 0.5 * L), d1, 0.2 * L), add(add(c, d0, 0.6 * L), d1, 0.5 * L)]
    npts = max(3, int(round(L / RING_STEP)) + 1)
    fpath = _resample(_cubic(raw[0], raw[1], raw[2], raw[3], 24), npts)
    rad = ft._at(radii, i / float(n - 1)) * FORK_R
    return _barbed_tube(g, r, fpath, (rad, rad * 0.7, max(0.07, rad * 0.4)), patch, STEM_ZONE)


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


def brambles(g):
    """The thicket: PLANTS barbed three-sided brambles out of the pit floor,
    each socketed into a floor quad, TALL_SHARE of them tall (TALL_H, a side
    branch on FORK_SHARE of those), the rest scrub (SCRUB_H), heights tallest
    round the trunk, leaning and twisting so the crowns tangle. Fills INFO."""
    m = g.m
    r = ft._Rng(PIT_SEED)
    spots = _sockets(g, r, PLANTS, PLANT_ROWS, PLANT_SPACING)
    v0 = len(m.verts)
    count = tall = forks = 0
    for k, (j, i) in enumerate(spots):
        patch = _floor_patch(g, j, i)
        if patch is None:
            continue
        is_tall = r.f() < TALL_SHARE
        c = m.centroid(patch[0])
        path = _plant_path(g, r, c, TALL_H if is_tall else SCRUB_H)
        rings = _barbed_tube(g, r, path, TALL_R if is_tall else SCRUB_R, patch, STEM_ZONE)
        if rings is None:
            continue
        count += 1
        if is_tall:
            tall += 1
            if r.f() < FORK_SHARE and _fork(g, r, rings, path, TALL_R) is not None:
                forks += 1
    top = (0.0, -1e9)
    for p in m.verts[v0:]:
        if p[2] > top[1]:
            top = (math.hypot(p[0], p[1]), p[2])
    INFO["brambles"], INFO["tall"], INFO["forks"], INFO["top"] = count, tall, forks, top
    INFO["max_r"] = max(math.hypot(p[0], p[1]) for p in m.verts[v0:]) if count else 0.0


# =============================================================================
# FOG
# =============================================================================

def _ease(u):
    return 0.5 - 0.5 * math.cos(math.pi * u)


def _drift(deg, rad, z):
    """A low-frequency field in (angle, radius, height), -1..1: the sum of a few
    sines whose weights add to 1. Deterministic -- the fog is the same every build --
    low frequency round (2, 3 and 5 lobes) and ALMOST vertical, so a thick bank of
    fog leans slowly as it climbs instead of averaging out through the stack."""
    a = math.radians(deg)
    w = 0.0
    for (lobes, kz, phase, weight) in FOG_DRIFT:
        w += weight * math.sin(lobes * a + kz * z + phase)
    kr, phase, weight = FOG_RADIAL
    w = (1.0 - weight) * w + weight * math.sin(kr * rad + phase + 0.04 * z)
    return max(-1.0, min(1.0, FOG_GAIN * w))


def fog_mesh(cls, g):
    """The pit's fog: FOG_Z layers of FOG_N-gon discs, each five annuli wide --
    a hole round the trunk (alpha 0 at FOG_HOLE[0], full at FOG_HOLE[1]), the body,
    and a nine-metre feather out to zero 0.6 m inside the bank (FOG_BANK), so the
    fog never shows an edge against earth.

    Every vertex is a column of the drift field: the column climbs FOG_REACH..1.0 of
    the stack and its alpha falls as (1 - u/reach)^FOG_CURVE from FOG_ALPHA at the
    floor to zero where it ends, thickened or thinned FOG_DENSE by the same field.
    So the fog's top ROLLS between the bramble tops and the stack's ceiling and is
    zero at the top layer everywhere -- a gradient thinning toward the rim, no plane
    anywhere, and the tall brambles come through the thin places. The tint darkens to
    FOG_DEPTH_DIM at depth. The bottom layer's vertices come first: the triangle
    order is the blend order, seen from above."""
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
        dim = FOG_DEPTH_DIM + (1.0 - FOG_DEPTH_DIM) * _ease(u)
        tint = (FOG_TINT[0] * dim, FOG_TINT[1] * dim, FOG_TINT[2] * dim)
        br = _bank_r(z)
        r_in, r_out = FOG_HOLE[1], br + FOG_BANK[0]
        r_end = br + FOG_BANK[1]
        radii = [(FOG_HOLE[0], 0.0),
                 (r_in, 1.0),
                 (r_in + (r_out - r_in) * FOG_MID, 1.0),
                 (r_out, 1.0),
                 (r_out + (r_end - r_out) * 0.5, FOG_FEATHER),
                 (r_end, 0.0)]
        rings = []
        peak = 0.0
        for (rad, w) in radii:
            ring = []
            for s in range(FOG_N):
                deg = 360.0 * s / FOG_N
                d = _drift(deg, rad, z)
                reach = FOG_REACH + (1.0 - FOG_REACH) * (0.5 + 0.5 * d)
                a = w * FOG_ALPHA * max(0.0, 1.0 - u / reach) ** FOG_CURVE * (1.0 + FOG_DENSE * d)
                peak = max(peak, a)
                ring.append(m.cv(pol(deg, rad, z), tint + (a,)))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for s in range(FOG_N):
                q = (s + 1) % FOG_N
                m.quad(rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s], UP, "fog")
        INFO["layers"].append((round(z, 2), round(peak, 3), round(r_end, 2)))
    return m
