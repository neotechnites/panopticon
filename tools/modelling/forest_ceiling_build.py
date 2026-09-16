"""
PANOPTICON -- forest roof: the gallery of leaves over Map 3's lane, and the
grand canopy dome over the ravine (map 1's roof pattern, grown in leaves).

Not a model of its own: forest_build.py calls in here with its _Ground (g) and
this module grows the roof into g.m, sharing vertices with the wall's top row
(g.wall[-1]) so the ground stays ONE contiguous mesh. Four calls:

    gallery_rows(g)  the low leaf roof over the lane: rings r 60 -> 46.7 at
                     y 36, g.gal[0] IS g.wall[-1]; its last ring is the rim the
                     wall above the gallery stands on (forest_build._upper_rows)
    gallery_faces(g) that roof's faces
    dome_rows(g)     the dome's rings, g.dome[0] IS g.upper[-1] (y 50)
    dome_faces(g)    the dome, its organic gaps left open, and g.rays
    dress(g)         leaf clumps round every gap's rim -- the gaps read as
                     daylight between clumps, never as a cut rectangle

Heights (world y, the lane is 23.0):

    gallery roof ...  36.0  over the lane, 13 m up: dense leaf, lumped, nothing
                      hanging under it
    wall above .....  36.0 -> 50.0 at r ~47: three more tiers of barred cells
                      (forest_build), seen from the tower and across the ring
    dome ...........  50.0 at the rim to 63.2 over the tree: 40 m over the lane,
                      three times the gallery, the tree's crown (37.2..39.7)
                      standing up into it

The gaps are organic blobs cut out of the dome's quad grid (a wobbly radius
round a centre, no two alike), all on the sun's side, each with a ring of leaf
clumps hung round its rim; forest_build._ray_mesh turns g.rays into one soft
shaft per gap.

    python3 tools/modelling/forest_build.py --check     proves the whole ground
"""

import math

import forest_tree_build as ft
from forest_tree_build import UP, DOWN, pol, add, sub, norm, dot, lerp, zipper

# =============================================================================
# TUNABLES
# =============================================================================

GALLERY_Z = 36.0            # the leaf gallery roof over the lane: 13 m over the grass
GALLERY_R = [60.0, 55.9, 51.5, 46.7]        # wall top inward to the pit lip
GALLERY_SAG = 0.5           # the roof dips this much mid-span (zero at both edges)
GALLERY_LUMP = 0.55         # ... and its underside is lumped this much: leaf clumps, not a lid
LEAF_T = 0.12               # a gallery quad lit enough to be "leaf" rather than "shade" ...
DOME_LEAF_T = -0.05         # ... and a dome quad, higher and catching more of the gaps' light

# (r, y, vertices): the dome over the ravine, springing off the wall above the gallery.
# 120 columns from ring 1 in: a 2 m chord against a 3 m band is a square-ish quad, which
# is what lets a gap's rim and a clump's socket sit in it without slivers.
DOME = [(47.7, 50.0, 240), (44.0, 53.4, 120), (40.5, 56.0, 120), (37.0, 58.0, 120),
        (33.0, 59.6, 120), (28.0, 61.0, 120), (22.0, 62.0, 60), (14.0, 62.8, 60),
        (7.0, 63.2, 30)]
DOME_TOP = 63.4             # the pole
DOME_LUMP = 2.2             # the dome billows this much: leaf masses, never a smooth dish
DOME_LUMP_SCALE = 0.55      # ... at this much of the field's own wavelength (6..15 m clumps)
GAP_BANDS = (1, 5)          # gaps are cut in dome bands 1..4 (r 28..44): the uniform 120-wide ones

# (bearing, band, radius in metres, wobble seed): a hole through the canopy, and a
# sun shaft. All on the sun's side (SUN bears 120) so the shafts read as one light.
GAPS = [(74.0, 3, 3.2, 11), (103.0, 1, 4.2, 23), (127.0, 4, 2.4, 37),
        (149.0, 2, 3.6, 53), (172.0, 3, 2.8, 71)]
GAP_RAG = (0.55, 0.45)      # every vertex on a gap's edge is pulled this far in y and in plan:
                            # the rim is torn leaf, not a staircase of quads
GAP_LIT = 2                 # cells this far round a gap are the lit "sun" leaf: the light
                            # falls on the leaves it comes past, never on a hard black edge
GAP_WOB = (0.30, 0.22, 0.14)   # the blob's radius wobbles at 2, 3 and 5 per turn
GAP_HALF = (0.42, 0.5, 2.2)    # the shaft's half width at the top: this x the blob's radius, clamped

SEED = 9110271 + 77         # the roof's own seed: editing it diffs only the roof

RIM_CLUMPS = 6              # leaf clumps round each gap's rim ...
CLUMP_R = (0.9, 1.7)        # ... this big, hung this far under the dome
CLUMP_HANG = (0.5, 1.8)
CLUMP_SEGS = 6
STEM_R = (0.2, 0.15)
CLEAR = 0.22                # least gap kept between two clumps
WELL_R = 0.3                # the least radius of the square well a stem's socket sits in
MIN_BRIDGE = 6.0            # degrees: a quad that cannot take a socket this cleanly is skipped
TWO_PI = 2.0 * math.pi


# =============================================================================
# THE GALLERY ROOF -- over the lane only, as map 1's rock ceiling
# =============================================================================

def _nc(g):
    return len(g.wall[-1])


def _col_of(nc, b):
    return int(round(b / (360.0 / nc))) % nc


def gallery_z(g, x, y):
    """The gallery roof's underside at (x, y): a shallow sag across the annulus,
    lumped like leaf clumps."""
    rad = math.hypot(x, y)
    u = (GALLERY_R[0] - rad) / (GALLERY_R[0] - GALLERY_R[-1])
    u = max(0.0, min(1.0, u))
    sag = GALLERY_SAG * math.sin(math.pi * u)
    return GALLERY_Z - sag + GALLERY_LUMP * g.ceil_f(x * 0.9, y * 0.9)


def gallery_rows(g):
    m = g.m
    nc = _nc(g)
    g.gal.append(g.wall[-1])
    for rad in GALLERY_R[1:]:
        row = []
        for i in range(nc):
            p = pol(i * 360.0 / nc, rad, 0.0)
            row.append(m.v((p[0], p[1], gallery_z(g, p[0], p[1]))))
        g.gal.append(row)


def _leafy(g, ids, thr=LEAF_T, k=0.9, off=0.0):
    """Leaf where the underside bulges down into the light, shade in the hollows."""
    c = g.m.centroid(ids)
    return "leaf" if g.ceil_f(c[0] * k + off, c[1] * k) > thr else "shade"


def gallery_faces(g):
    m = g.m
    nc = _nc(g)
    for k in range(len(g.gal) - 1):
        a, b = g.gal[k], g.gal[k + 1]
        for i in range(nc):
            q = (i + 1) % nc
            ids = (a[i], a[q], b[q], b[i])
            m.quad(ids[0], ids[1], ids[2], ids[3], DOWN, _leafy(g, ids))


# =============================================================================
# THE DOME -- grand, far over the ravine, with organic gaps
# =============================================================================

def dome_z(rad):
    """The dome's smooth height at radius rad (before the lumps)."""
    if rad >= DOME[0][0]:
        return DOME[0][1]
    for k in range(len(DOME) - 1):
        (r0, z0, _n0), (r1, z1, _n1) = DOME[k], DOME[k + 1]
        if r1 <= rad <= r0:
            return z0 + (z1 - z0) * (r0 - rad) / (r0 - r1)
    return DOME_TOP


def dome_r(z):
    """The dome's radius at height z: the envelope the sun shafts live inside."""
    if z <= DOME[0][1]:
        return DOME[0][0]
    for k in range(len(DOME) - 1):
        (r0, z0, _n0), (r1, z1, _n1) = DOME[k], DOME[k + 1]
        if z0 <= z <= z1:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    if z <= DOME_TOP:
        return DOME[-1][0] * (DOME_TOP - z) / max(1e-6, DOME_TOP - DOME[-1][1])
    return 0.0


def sheet_z(g, x, y):
    """The dome's underside at (x, y), lumps and all."""
    k = DOME_LUMP_SCALE
    return dome_z(math.hypot(x, y)) + DOME_LUMP * g.ceil_f(x * k + 60.0, y * k)


def dome_rows(g):
    m = g.m
    g.dome.append(g.upper[-1])
    for (rad, _z, n) in DOME[1:]:
        row = []
        for i in range(n):
            p = pol(i * 360.0 / n, rad, 0.0)
            row.append(m.v((p[0], p[1], sheet_z(g, p[0], p[1]))))
        g.dome.append(row)
    g.ceil_pole = m.v((0.0, 0.0, DOME_TOP))


def _blob_r(rng_ph, ang, radius):
    """The gap's wobbly radius at angle ``ang``: never a circle, never a box."""
    f = 1.0
    for (k, amp) in zip((2.0, 3.0, 5.0), GAP_WOB):
        f += amp * math.sin(k * ang + rng_ph[int(k) % 3])
    return radius * max(0.35, f)


def dome_quad_ids(g, k, i):
    n = len(g.dome[k])
    q = (i + 1) % n
    return (g.dome[k][i], g.dome[k][q], g.dome[k + 1][q], g.dome[k + 1][i])


def _gap_cells(g):
    """Per gap: its dome quads (an organic blob, no two alike) and their centres."""
    out = []
    lo, hi = GAP_BANDS
    nc = len(g.dome[lo])
    for (b, band, radius, seed) in GAPS:
        r = ft._Rng(SEED + seed)
        ph = (r.f() * TWO_PI, r.f() * TWO_PI, r.f() * TWO_PI)
        c = pol(b, 0.5 * (DOME[band][0] + DOME[band + 1][0]), 0.0)
        cells, pts = [], []
        for k in range(lo, hi):
            for i in range(nc):
                p = g.m.centroid(dome_quad_ids(g, k, i))
                d = (p[0] - c[0], p[1] - c[1])
                dist = math.hypot(d[0], d[1])
                if dist > radius * 1.7:
                    continue
                if dist <= _blob_r(ph, math.atan2(d[1], d[0]), radius):
                    cells.append((i, k))
                    pts.append(p)
        if not pts:                                   # a blob too small for one quad
            k, i = band, _col_of(nc, b)
            cells = [(i, k)]
            pts = [g.m.centroid(dome_quad_ids(g, k, i))]
        cells, pts = _one_blob(cells, pts, nc)        # no stray speck off to the side
        out.append({"b": b, "radius": radius, "cells": cells, "pts": pts,
                    "centre": tuple(sum(p[j] for p in pts) / float(len(pts)) for j in range(3))})
    return out


def _one_blob(cells, pts, nc):
    """The blob's biggest 4-connected island: a lone cell off the edge reads as a
    hole punched in the leaves, not as daylight through them."""
    want = set(cells)
    seen = set()
    best = None
    for start in cells:
        if start in seen:
            continue
        stack, island = [start], []
        seen.add(start)
        while stack:
            (i, k) = stack.pop()
            island.append((i, k))
            for (di, dk) in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                n = ((i + di) % nc, k + dk)
                if n in want and n not in seen:
                    seen.add(n)
                    stack.append(n)
        if best is None or len(island) > len(best):
            best = island
    keep = set(best)
    out = [(c, p) for (c, p) in zip(cells, pts) if c in keep]
    return [c for (c, _p) in out], [p for (_c, p) in out]


def _rag_rims(g, holes):
    """Pull every vertex on a gap's edge about: the rim is torn leaf, not a
    staircase of quads. The vertices are shared, so the leaves round it move too."""
    r = ft._Rng(SEED + 911)
    ids = set()
    for (i, k) in holes:
        ids.update(dome_quad_ids(g, k, i))
    for vid in sorted(ids):
        (x, y, z) = g.m.verts[vid]
        rad = math.hypot(x, y)
        t = (-y / rad, x / rad, 0.0) if rad > 1e-6 else (1.0, 0.0, 0.0)
        p = add((x, y, z), t, GAP_RAG[1] * r.sf())
        rr = 1.0 + GAP_RAG[1] * r.sf() / max(1.0, rad)
        g.m.verts[vid] = (p[0] * rr, p[1] * rr, z + GAP_RAG[0] * r.sf())


def dome_faces(g):
    m = g.m
    g.gaps = _gap_cells(g)
    holes = set()
    for gap in g.gaps:
        holes.update(gap["cells"])
    g.ceil_holes = holes
    lit = set()
    nc = len(g.dome[GAP_BANDS[0]])
    for (i, k) in holes:
        for di in range(-GAP_LIT, GAP_LIT + 1):
            for dk in range(-GAP_LIT, GAP_LIT + 1):
                lit.add(((i + di) % nc, k + dk))
    _rag_rims(g, holes)
    for k in range(len(g.dome) - 1):
        a, b = g.dome[k], g.dome[k + 1]
        if len(a) != len(b):
            zipper(m, a, b, DOWN, "shade", centre=(0.0, 0.0, 0.0))
            continue
        for i in range(len(a)):
            if (i, k) in holes:
                continue
            q = (i + 1) % len(a)
            ids = (a[i], a[q], b[q], b[i])
            zone = "sun" if (i, k) in lit else _leafy(g, ids, DOME_LEAF_T, DOME_LUMP_SCALE, 60.0)
            m.quad(ids[0], ids[1], ids[2], ids[3], DOWN, zone)
    last = g.dome[-1]
    for i in range(len(last)):
        q = (i + 1) % len(last)
        m.tri(g.ceil_pole, last[i], last[q], DOWN, "shade")
    for gap in g.gaps:
        half = min(GAP_HALF[2], max(GAP_HALF[1], GAP_HALF[0] * gap["radius"]))
        g.rays.append((gap["pts"], half))


# =============================================================================
# DRESSING -- leaf clumps round each gap's rim, socketed into the dome
# =============================================================================

def _dist(p, q):
    return math.sqrt(sum((p[k] - q[k]) ** 2 for k in range(3)))


class _State(object):
    """What dress() keeps between clumps: the mesh, its own rng, the dome quads
    already claimed, and the spheres placed so far (for clearance)."""

    def __init__(self, g, fb):
        self.g, self.m, self.fb = g, g.m, fb
        self.r = ft._Rng(SEED + 5)
        self.nc = len(g.dome[GAP_BANDS[0]])
        self.taken = set()
        for (i, k) in g.ceil_holes:
            self.taken.add((i, k))
        self.sph = []
        self.worst = math.pi
        self.count = 0

    def dome_quad(self, k, i):
        i %= self.nc
        q = (i + 1) % self.nc
        ids = (self.g.dome[k][i], self.g.dome[k][q], self.g.dome[k + 1][q], self.g.dome[k + 1][i])
        return ids if self.m.has_quad(ids) else None

    def clear(self, p, rad):
        best = 1e9
        for (c, rr) in self.sph:
            best = min(best, _dist(p, c) - rr - rad)
        return best


def _zip(m, outer, inner, n, ex, ey, zone):
    """Triangles between two rings of any two counts on one plane, matched by
    angle round the inner ring's centroid in the (ex, ey) frame (m.socket's zip)."""
    c = m.centroid(inner)

    def ang(vid):
        d = sub(m.verts[vid], c)
        return math.atan2(dot(d, ey), dot(d, ex))

    O = sorted(outer, key=ang)
    I = sorted(inner, key=ang)
    aO, aI = [ang(v) for v in O], [ang(v) for v in I]
    i = j = 0
    no, ni = len(O), len(I)
    while i < no or j < ni:
        next_o = aO[i + 1] if i + 1 < no else aO[0] + TWO_PI
        next_i = aI[j + 1] if j + 1 < ni else aI[0] + TWO_PI
        oi, ii = O[i % no], I[j % ni]
        if (i < no and next_o <= next_i) or j >= ni:
            m.tri(oi, O[(i + 1) % no], ii, n, zone)
            i += 1
        else:
            m.tri(oi, I[(j + 1) % ni], ii, n, zone)
            j += 1


def _ring(centre, ex, ez, radius, sides, phase=0.0):
    return [add(add(centre, ex, radius * math.cos(phase + TWO_PI * s / sides)),
                ez, radius * math.sin(phase + TWO_PI * s / sides)) for s in range(sides)]


def _well(st, quads, path, rad, sides, zone):
    """A stem's end socketed into a dome patch in two stages, so no bridging
    triangle is a sliver: the patch is claimed by a square well ring, and the
    stem's own ring -- projected onto the patch along the stem -- is zipped to
    it, at the size and phase that bridge best. Returns the stem's ring ids."""
    m, fb = st.m, st.fb
    n, ex, ey, loop = fb._patch_frame(m, quads)
    loop_pts = [m.verts[v] for v in loop]
    c = m.centroid(loop)
    t, tx, tz = ft.frames(path)[0]
    inner = ft.project_ring(_ring(path[0], tx, tz, rad, sides), t, (c, n))
    reach = max(_dist(q, c) for q in inner)
    base = max(WELL_R, 1.4 * reach + 0.1)
    best = None
    for ra in (base, base + 0.08, base + 0.16, base + 0.25):
        for k in range(24):
            ph = TWO_PI * k / 24
            sq = [add(add(c, ex, ra * math.cos(ph + TWO_PI * j / 4)), ey, ra * math.sin(ph + TWO_PI * j / 4))
                  for j in range(4)]
            q = min(fb._bridge_quality(loop_pts, sq, n, ex, ey), fb._bridge_quality(sq, inner, n, ex, ey))
            if best is None or q > best[0]:
                best = (q, sq)
    if best[0] < math.radians(MIN_BRIDGE):      # a ragged rim quad can be too warped to socket
        return None
    outer = [m.v(q) for q in best[1]]
    m.socket(quads, outer, zone)
    ids = [m.v(q) for q in inner]
    _zip(m, outer, ids, n, ex, ey, zone)
    st.worst = min(st.worst, best[0])
    return ids


def _clump_hang(m, ring, centre, radius, zone, rng, squash=0.75, wob=0.2):
    """A leaf clump hung off a stem's last ring: rings down round a ball, each
    vertex under its own on the ring above, a bottom tip."""
    segs = len(ring)
    az = [math.atan2(m.verts[v][1] - centre[1], m.verts[v][0] - centre[0]) for v in ring]
    rings = [list(ring)]
    for lat in (62.0, 35.0, -5.0, -40.0, -68.0):
        cl, sl = math.cos(math.radians(lat)), math.sin(math.radians(lat))
        row = []
        for s in range(segs):
            a = az[s] + rng.sf() * (0.04 if lat > 60.0 else 0.12)
            rr = radius * (1.0 + wob * rng.sf())
            row.append(m.v((centre[0] + rr * cl * math.cos(a), centre[1] + rr * cl * math.sin(a),
                            centre[2] + rr * sl * squash)))
        rings.append(row)
    for i in range(len(rings) - 1):
        for s in range(segs):
            q = (s + 1) % segs
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), centre), zone)
    bot = m.v((centre[0], centre[1], centre[2] - radius * squash * (1.0 + wob * rng.sf())))
    for s in range(segs):
        q = (s + 1) % segs
        m.tri(bot, rings[-1][s], rings[-1][q], sub(m.centroid((bot, rings[-1][s], rings[-1][q])), centre), zone)


def _rim_clump(st, k, i, over=None):
    """One leaf clump on a short stem out of dome quad (i, k); ``over`` leans it
    toward the gap's centre so it hangs across the daylight."""
    m, r = st.m, st.r
    quads = [st.dome_quad(k, i)]
    if quads[0] is None:
        return False
    c = m.centroid(st.fb._patch_frame(m, quads)[3])
    hang = r.u(*CLUMP_HANG)
    radius = r.u(*CLUMP_R)
    d = norm((over[0] - c[0], over[1] - c[1], 0.0)) if over is not None else (0.0, 0.0, 0.0)
    lean = r.u(0.8, 1.6) if over is not None else 0.0
    for shrink in (1.0, 0.72, 0.55):                # a crowded rim takes a smaller clump
        radius *= shrink
        centre = (c[0] + d[0] * lean, c[1] + d[1] * lean, c[2] - hang - 0.64 * radius)
        if st.clear(centre, radius * 1.25) >= CLEAR:
            break
    else:
        return False
    end = (centre[0], centre[1], centre[2] + 0.64 * radius)
    path = [c, lerp(c, end, 0.5), end]
    ring0 = _well(st, quads, path, STEM_R[0], CLUMP_SEGS, "shade")
    if ring0 is None:
        return False
    st.taken.add((i, k))
    rings = ft.tube(m, path, STEM_R, CLUMP_SEGS, "bark", caps=(False, False), first_ring=ring0)
    _clump_hang(m, rings[-1], centre, radius, "sun", r)   # lit: they hang in the gap's own light
    st.sph.append((centre, radius * 1.25))
    st.count += 1
    return True


def dress(g):
    """Leaf clumps round every gap's rim: the daylight comes between clumps."""
    import sys
    fb = sys.modules[g.__class__.__module__]   # the driver (forest_build, or a render copy of it)
    st = _State(g, fb)
    before = sum(1 for f in g.m.faces if f is not None)
    lo, hi = GAP_BANDS
    for gap in g.gaps:
        cells = set(gap["cells"])
        c = gap["centre"]
        rim = []
        for (i, k) in sorted(cells):
            for (di, dk) in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                j, kk = (i + di) % st.nc, k + dk
                if lo <= kk < hi and (j, kk) not in cells and (j, kk) not in rim:
                    rim.append((j, kk))
        if not rim:
            continue

        def ang(cell):
            p = g.m.centroid(dome_quad_ids(g, cell[1], cell[0]))
            return math.atan2(p[1] - c[1], p[0] - c[0])

        rim.sort(key=ang)
        made = 0
        for n in range(len(rim)):                       # round the rim, skipping what will not take a socket
            if made >= RIM_CLUMPS:
                break
            i, k = rim[int(n * len(rim) / float(RIM_CLUMPS)) % len(rim)] if n < RIM_CLUMPS else rim[n]
            if _rim_clump(st, k, i, over=c if made % 3 == 0 else None):
                made += 1
    after = sum(1 for f in g.m.faces if f is not None)
    print("MDL STATS roof gallery_y=%.1f dome_y=%.1f..%.1f gaps=%d rim_clumps=%d tris_added=%d worst_bridge_deg=%.1f"
          % (GALLERY_Z, DOME[0][1], DOME_TOP, len(GAPS), st.count, after - before, math.degrees(st.worst)))
    g.ceil_stats = {"rim_clumps": st.count, "tris_added": after - before}
