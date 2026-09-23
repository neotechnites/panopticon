"""
PANOPTICON -- forest pit: the foggy drop round Map 3's tree.

Not a model of its own: forest_build.py calls in here with its _Ground (g).

    pit_floor(g)         the dark floor grown inward off the bank's last row
                         (g.pit[-1]), part of the one contiguous ground mesh
    brambles(g)          thorny branches out of the bank's quads, some arching
                         up over the rim; every one socketed (shares vertices)
    fog_mesh(cls, g)     a separate node (FOG_NAME): stacked discs filling the
                         pit, tint and alpha in COLOR_0 (cls is
                         forest_build._RayMesh); the scene shows it unshaded,
                         mixed, vertex colour as albedo -- GL Compatibility has
                         no fog volumes, so the fog is layers
    fog_report()         what those discs do to a ray straight down the pit

No water: the pit is a dark floor under fog, and thorns come out of the fog. The
floor is not meant to be seen at all -- a pit reads as bottomless only while
nothing flat at the end of it reaches the eye -- so the fog is built to a number
rather than to a look: the bottom of the stack is one opaque slab and a vertical
ray leaves under FOG_PROOF of the floor's own colour. It takes two things
together. The slab is here; the other half is `disable_fog = true` on FogMat in
scenes/ring/forest.tscn, without which the Environment's depth fog repaints these
layers AND the floor behind them to one pale colour, and one colour spread over
one flat plane is exactly what reads as a floor.

    python3 tools/modelling/forest_pit_build.py         the fog's own numbers
    python3 tools/modelling/forest_build.py --check     proves the whole ground
"""

import math
import sys

import forest_tree_build as ft
from forest_tree_build import UP, DOWN, pol, add, sub, norm, dot, lerp, bez, zipper

FOG_NAME = "ForestFog"
FOG_TINT = (0.26, 0.28, 0.22)   # gold-grey-green, kept dim: a column stacks fourteen layers, and unshaded
                                # fog brighter than the sunlit lane reads as milk, not gloom. Godot shows
                                # this x FOG_OVERRIDE, and FOG_DEPTH_DIM takes the floor end near black
FOG_OVERRIDE = 0.6              # FogMat's albedo alpha in scenes/ring/forest.tscn. The scene multiplies every
                                # vertex alpha by this, so it is the ceiling on what one layer can hide
                                # (a layer at vertex alpha 1.0 still passes 40 % of what is behind it).
                                # fog_report() models it: leave it out and the transmittance numbers are fiction


# ---- the fog: a stack of translucent discs standing in for a fog volume -----------
# Read as a pit with no bottom, not a lid. A pit has no bottom when nothing flat at the
# end of it ever reaches the eye, so the stack is built as ONE opaque slab low down with
# a rolling, thinning top: solid to FOG_SOLID of the stack, then falling to exactly zero
# at a drift-varied height, feathered into the trunk and buried in the bank. Two things
# beat the floor between them -- the slab (which the vertical transmittance measures) and
# FogMat's disable_fog, without which the Environment's depth fog repaints these layers
# AND the floor behind them to one pale colour, and one colour over one flat plane is
# exactly what reads as a floor. GL Compatibility has no fog volumes, so the fog is layers.
FOG_Z = (-11.6, 4.0, 1.2)       # bottom (just under the floor at -11.05), top, pitch: 14 layers, the top
                                # one at alpha 0 so the fog ends in air, never on a plane
FOG_N = 36                      # segments round: 14 layers x 5 bands x 36 x 2 = 5040 tris, which is
                                # what the forest has left under its 130k budget (the fog is a tenth of it)
FOG_HOLE = (6.8, 13.0)          # round the trunk: alpha 0 at 6.8 (outside the trunk, r <= 6.4 above the
                                # roots) easing to full at 13.0 -- a wide inner feather, no ring edge
FOG_BANK = (2.0, 9.0, 0.6)      # the rim feather, which SHRINKS WITH DEPTH: this wide right through the
                                # slab, this wide at the top layer, and always ending this far INSIDE the bank, so the
                                # fog stops buried in earth and can never show an edge against it. Nine
                                # metres of feather at the floor left the bank's foot and the floor's outer
                                # rim (r 33..42 of a 42 m floor) inside the ramp -- and that rim is the
                                # nearest flat thing to an eye on the lane, half of what read as a floor.
                                # Two metres down there puts 91 % of the floor's area under the solid slab;
                                # up top the feather stays wide, where the fog has to fade into open air
FOG_MID = 0.5                   # a ring this far across the full-alpha span: the wobble varies radially
FOG_FEATHER = 0.55              # alpha at the middle of the rim feather. Raised from 0.42 with the shrink:
                                # 0.42 shaped a nine-metre ramp nobody reads end to end, but the floor's
                                # two-metre one is seen whole, and a ramp that is already half gone at its
                                # midpoint lets the rim through
FOG_ALPHA = 1.0                 # the floor layer's alpha: opaque, the most a vertex colour can ask for.
                                # Anything less cannot win -- FOG_OVERRIDE caps one layer at 0.6, so putting
                                # a vertical ray under 0.5 % transmittance needs six layers at the ceiling
FOG_SOLID = 0.45                # ... and the bottom this fraction of the stack holds it: six layers of solid
                                # dark (y -11.6 to -4.6) that the drift never thins. Below the roll the fog
                                # is not a gradient, it is the dark. This is the number the transmittance
                                # proof moves; the layers above it are the look
FOG_CURVE = 1.6                 # above the slab the column falls as ((reach - u)/(reach - FOG_SOLID))^this
                                # to exactly 0 where the column ends
FOG_DEPTH_DIM = 0.15            # the tint at the floor, as a factor; 1.0 at the top. Deepened from 0.50 now
                                # that the floor layer is opaque: what an opaque layer shows IS its tint, and
                                # the bottom of a bottomless pit has to converge on black, not on a colour
                                # (0.26 x 0.15 x FOG_OVERRIDE = 0.023 linear, against 0.156 up in the haze)
FOG_REACH = 0.65                # how high a column of fog climbs, as a fraction of the stack: FOG_REACH in
                                # the thin places, 1.0 in the thick ones, set by the drift field -- the top
                                # of the fog ROLLS instead of lying flat, and never reaches past the top
                                # layer, which is therefore alpha 0 all the way round: no plane to see.
                                # 0.65 is 3 m clear of FOG_SOLID, so the slab's own top is always buried
                                # under graded fog and is never a surface either
FOG_DENSE = 0.30                # ... and the same field thickens and thins the column, +/- this much --
                                # weighted to the roll and zero in the slab, because a thin spot low down
                                # is a window onto the floor
FOG_DRIFT = ((3, 0.05, 0.0, 0.45),     # (lobes round, radians per metre up, phase, weight): low frequency and
             (5, -0.03, 1.90, 0.35),   # ALMOST vertical -- a bank thick here and thin there leans slowly as
             (8, 0.02, 4.10, 0.20))    # it climbs, where a fast z term would average out over the stack
FOG_RADIAL = (0.16, 2.3, 0.35)         # one more drift term across the radius (radians per metre, phase,
                                       # weight): a 40 m period, two samples a ring apart -- patches, not stripes
FOG_GAIN = 1.7                         # the sines rarely line up, so the field is scaled to its range and
                                       # clipped: banks with thick middles, not a gentle swell
FOG_PROOF = 0.005                      # what fog_report() has to beat: the share of the floor that may still
                                       # reach an eye looking straight down the pit, through the whole stack
FOG_MONO = 0.005                       # how much a layer may be brighter than the one under it before the
                                       # stack counts as having a lid in it. Not zero: two neighbouring rings
                                       # end at slightly different heights, so where a column runs out the
                                       # interpolated alpha can tick up by a ten-thousandth. Anything the eye
                                       # could see is orders above this

# ---- the thicket: brambles out of the floor, a mass across the pit bottom ---------
PIT_SEED = 4471023              # its own rng: editing the brambles diffs only the brambles
FLOOR_Z = -11.05                # the floor (the bank's last row)
FLOOR_RIM = 42.0                # ... and how far out it goes: the bank's radius there. The last 2 m of it
                                # is under the fog's rim feather, not the slab, so fog_report reads it apart
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


def _fog_layers():
    """The stack's heights, floor first: FOG_Z read out as a list so the mesh and
    the report walk exactly the same layers."""
    z0, z1, pitch = FOG_Z
    out = []
    z = z0
    while z <= z1 + 1e-6:
        out.append(z)
        z += pitch
    return out


def fog_feather(u):
    """How wide the rim feather is at height fraction u: FOG_BANK[0] through the
    whole slab, then easing out to FOG_BANK[1] at the top layer. It widens with
    the roll and not before, because the slab has to reach the earth -- the floor
    runs out to r 42 and a feather that had already opened to four metres by the
    middle of the slab left its outer band, the band nearest the eye, in the ramp."""
    roll = max(0.0, min(1.0, (u - FOG_SOLID) / max(1e-6, 1.0 - FOG_SOLID)))
    return FOG_BANK[0] + (FOG_BANK[1] - FOG_BANK[0]) * _ease(roll)


def _fog_rings(br, u):
    """The six (radius, weight) rings of one layer, inner to outer, for a bank
    radius br at height fraction u: the hole round the trunk, the body at full
    weight, and the rim feather of fog_feather(u), always ending FOG_BANK[2]
    inside the earth."""
    r_in, r_out = FOG_HOLE[1], br - fog_feather(u)
    r_end = br + FOG_BANK[2]
    return [(FOG_HOLE[0], 0.0),
            (r_in, 1.0),
            (r_in + (r_out - r_in) * FOG_MID, 1.0),
            (r_out, 1.0),
            (r_out + (r_end - r_out) * 0.5, FOG_FEATHER),
            (r_end, 0.0)]


def _fog_column(u, reach, d):
    """One column of fog at height fraction u, as a share of FOG_ALPHA.

    Solid 1.0 to FOG_SOLID -- the slab, which the drift is not allowed to thin,
    because a thin spot low down is a window onto the floor -- then falling as
    ((reach - u) / (reach - FOG_SOLID)) ** FOG_CURVE to exactly 0 at reach, with
    the drift thickening and thinning that falling part by FOG_DENSE. So the
    number goes DOWN with height at every step (fog_report proves it), the fog's
    top rolls between reach = FOG_REACH and the top layer, and the top layer,
    where u is 1.0 and reach never is more, is 0 all the way round."""
    if u <= FOG_SOLID:
        return 1.0
    if u >= reach:
        return 0.0
    base = ((reach - u) / max(1e-6, reach - FOG_SOLID)) ** FOG_CURVE
    roll = _ease((u - FOG_SOLID) / max(1e-6, 1.0 - FOG_SOLID))
    return max(0.0, min(1.0, base * (1.0 + FOG_DENSE * d * roll)))


def fog_mesh(cls, g):
    """The pit's fog: _fog_layers() discs of FOG_N-gons, each five annuli wide --
    a hole round the trunk (alpha 0 at FOG_HOLE[0], full at FOG_HOLE[1]), the body,
    and the rim feather out to zero FOG_BANK[2] inside the bank, so the fog never
    shows an edge against earth and the feather narrows as it goes down, until at
    the floor the body covers all but the last two metres of it.

    Every vertex is a column of the drift field (_fog_column): solid to FOG_SOLID
    of the stack, then falling to zero at a height the field rolls between
    FOG_REACH and the top. So the bottom is not a gradient, it is the dark -- a
    ray straight down the pit comes out under FOG_PROOF -- while the top rolls
    between the bramble tops and the stack's ceiling and is zero at the top layer
    everywhere: no plane anywhere, and the tall brambles come through the thin
    places. The tint darkens to FOG_DEPTH_DIM at depth, so the dark the slab shows
    is very nearly black. The bottom layer's vertices come first: the triangle
    order is the blend order, seen from above."""
    _bank_r = _host(g)._bank_r
    m = cls()
    layers = _fog_layers()
    INFO["layers"] = []
    for k, z in enumerate(layers):
        u = k / float(len(layers) - 1)
        dim = FOG_DEPTH_DIM + (1.0 - FOG_DEPTH_DIM) * _ease(u)
        tint = (FOG_TINT[0] * dim, FOG_TINT[1] * dim, FOG_TINT[2] * dim)
        radii = _fog_rings(_bank_r(z), u)
        rings = []
        peak = 0.0
        for (rad, w) in radii:
            ring = []
            for s in range(FOG_N):
                deg = 360.0 * s / FOG_N
                d = _drift(deg, rad, z)
                reach = FOG_REACH + (1.0 - FOG_REACH) * (0.5 + 0.5 * d)
                a = w * FOG_ALPHA * _fog_column(u, reach, d)
                peak = max(peak, a)
                ring.append(m.cv(pol(deg, rad, z), tint + (a,)))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for s in range(FOG_N):
                q = (s + 1) % FOG_N
                m.quad(rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s], UP, "fog")
        INFO["layers"].append((round(z, 2), round(peak, 3), round(radii[-1][0], 2)))
    return m


# ---- the proof: what a ray straight down the pit actually gets through ------------

def _fog_alpha_at(bank_r, deg, rad, z, u):
    """The alpha the shader interpolates at (deg, rad) on the layer at z: the two
    bracketing ring vertices of _fog_rings, blended across the band the way the
    quad blends them. 0 outside the outermost ring."""
    radii = _fog_rings(bank_r, u)
    vals = []
    for (rr, w) in radii:
        d = _drift(deg, rr, z)
        reach = FOG_REACH + (1.0 - FOG_REACH) * (0.5 + 0.5 * d)
        vals.append((rr, w * FOG_ALPHA * _fog_column(u, reach, d)))
    if rad <= vals[0][0] or rad >= vals[-1][0]:
        return 0.0
    for i in range(len(vals) - 1):
        (r0, a0), (r1, a1) = vals[i], vals[i + 1]
        if r0 <= rad <= r1:
            t = (rad - r0) / max(1e-9, r1 - r0)
            return a0 + (a1 - a0) * t
    return 0.0


def fog_ray(bank_at, deg, rad):
    """A ray straight down the pit at (deg, rad), floor to sky. Returns
    (transmittance, [effective alpha per layer, floor first]) where the effective
    alpha is what Godot draws -- the vertex alpha times FOG_OVERRIDE -- and the
    transmittance is the product of (1 - that) over every layer: the share of the
    floor's own colour that still reaches the eye."""
    layers = _fog_layers()
    eff = []
    through = 1.0
    for k, z in enumerate(layers):
        u = k / float(len(layers) - 1)
        a = FOG_OVERRIDE * _fog_alpha_at(bank_at(z), deg, rad, z, u)
        eff.append(a)
        through *= (1.0 - a)
    return through, eff


def fog_report():
    """Prints the numbers the fog is built to hit, for every bearing and every
    radius of floor the fog is meant to cover: the worst vertical transmittance
    (must beat FOG_PROOF), whether alpha rises with depth everywhere (it must, or
    the stack has a lid in it somewhere), and the effective alpha and feather
    width at three depths. No Blender and no Godot: this is arithmetic on the same
    functions the mesh is built from."""
    import forest_build as fb
    layers = _fog_layers()
    body = [FOG_HOLE[1] + 0.5 * j for j in range(0, 55)]          # r 13.0 .. 40.0, the floor under the slab
    worst = (0.0, 0.0, 0.0)
    rise = (0.0, 0.0)
    rim = (0.0, 0.0, 0.0)
    for s in range(FOG_N):
        deg = 360.0 * s / FOG_N
        for rad in body:
            through, eff = fog_ray(fb._bank_r, deg, rad)
            if through > worst[0]:
                worst = (through, deg, rad)
            for k in range(len(eff) - 1):
                if eff[k + 1] - eff[k] > rise[0]:
                    rise = (eff[k + 1] - eff[k], eff[k + 1])
        through, _eff = fog_ray(fb._bank_r, deg, FLOOR_RIM)
        if through > rim[0]:
            rim = (through, deg, FLOOR_RIM)
    print("fog layers=%d tris=%d override=%.2f" % (len(layers), len(layers) * 5 * FOG_N * 2, FOG_OVERRIDE))
    _t, eff = fog_ray(fb._bank_r, worst[1], worst[2])
    print("fog worst_ray deg=%.0f r=%.1f transmittance=%.5f%% limit=%.3f%% %s"
          % (worst[1], worst[2], 100.0 * worst[0], 100.0 * FOG_PROOF,
             "PASS" if worst[0] <= FOG_PROOF else "FAIL"))
    print("fog worst_ray effective_alpha=%s" % ["%.3f" % a for a in eff])
    print("fog rim_ray r=%.1f transmittance=%.3f%% (the feather: it grades into earth by design)"
          % (rim[2], 100.0 * rim[0]))
    top = 0.0                                                     # the lid check, read off the top layer itself
    for (rad, w) in _fog_rings(fb._bank_r(layers[-1]), 1.0):
        for s in range(FOG_N):
            d = _drift(360.0 * s / FOG_N, rad, layers[-1])
            reach = FOG_REACH + (1.0 - FOG_REACH) * (0.5 + 0.5 * d)
            top = max(top, w * FOG_ALPHA * _fog_column(1.0, reach, d))
    print("fog max_rise_with_height=%.5f at_alpha=%.5f limit=%.3f %s   top_layer_alpha=%.6f"
          % (rise[0], rise[1], FOG_MONO, "PASS" if rise[0] <= FOG_MONO else "FAIL", top))
    for k, z in enumerate(layers):
        u = k / float(len(layers) - 1)
        rings = _fog_rings(fb._bank_r(z), u)
        d = _drift(0.0, rings[2][0], z)
        reach = FOG_REACH + (1.0 - FOG_REACH) * (0.5 + 0.5 * d)
        print("fog layer k=%2d y=%6.2f u=%.3f eff_alpha=%.3f feather=%.2fm body_to_r=%.2f end_r=%.2f dim=%.3f"
              % (k, z, u, FOG_OVERRIDE * FOG_ALPHA * _fog_column(u, reach, d), fog_feather(u),
                 rings[3][0], rings[5][0],
                 FOG_DEPTH_DIM + (1.0 - FOG_DEPTH_DIM) * _ease(u)))


if __name__ == "__main__":
    fog_report()
