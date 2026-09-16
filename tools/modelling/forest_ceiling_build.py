"""
PANOPTICON -- forest ceiling: the leaf roof over Map 3's clearing.

Not a model of its own: forest_build.py calls in here with its _Ground (g) and
this module grows the ceiling into g.m, sharing vertices with the wall's top
row (g.wall[-1]) so the ground stays ONE contiguous mesh. Three calls:

    ceil_rows(g)    the sheet's rings of vertices, g.ceil[0] IS g.wall[-1]; sets g.ceil_pole
    ceil_faces(g)   the sheet's faces with the gaps left open; fills g.rays with
                    (the gap's corner points, its half width at the top) per gap
    dress(g)        everything hung under the sheet: limbs, crossing branches,
                    leaf clumps at different depths, vines -- every one socketed
                    into a sheet quad (or a wall quad) so it shares vertices

The sheet is a dome, y 33 at the wall to 44 over the tree, its underside
lumped +-0.6 m, with GAPS of varied size (1 x 1 quad ~1.5 m to 4 x 2 ~6 x 6 m)
cut through it. Under it, one great limb grows out of the top of every forest
trunk pilaster in the wall (a socket in its bark quads) and curves inward and
up under the sheet to end in a socket in a sheet quad; a crossing branch
leaves each limb at ~40 % of its length, runs diagonally under the sheet past
the next limb's tip and ends in the sheet there; a leaf clump sits at each
limb / branch fork on a short stem; ~24 more clumps hang under the sheet on
stems at varied depths; ~30 vines curl down off sheet sockets. Nothing hangs
below y 30.5, and nothing within r 13 of the centre is below y 39 (the tree's
crown reaches 37.8).

The sun shafts (forest_build._ray_mesh) read g.rays; forest_build.ray_lines
turns each entry into a shaft from RAY_IN up the sun line inside the gap.

    python3 tools/modelling/forest_build.py --check     proves the whole ground
"""

import math

import forest_tree_build as ft
from forest_tree_build import UP, DOWN, pol, add, sub, norm, dot, lerp, bez, zipper

# =============================================================================
# TUNABLES
# =============================================================================

CEIL_Z = 33.0               # the leaf ceiling at the wall ...
CEIL_DOME = 11.0            # ... and this much higher over the centre (y 44)
CEIL_R = [60.0, 57.0, 54.0, 51.0, 48.0, 45.0, 41.5, 37.0, 32.0, 26.5, 20.5, 14.0, 8.0, 3.0]
CEIL_N_INNER = [120, 60, 24]    # vertices on the last three rings: the centre thins out, no sliver fan
CEIL_LUMP = 0.6             # the underside's lumps, +- this
CEIL_POLE_LIFT = 0.3
# (bearing, ring band, columns, bands): a hole through the leaf ceiling, and a sun ray.
# Sizes vary and no two neighbouring bays match: 1 x 1 (~1.5 x 3 m) up to 4 x 2 (~5.5 x 6 m).
GAPS = [(22.0, 2, 2, 1), (52.0, 4, 3, 2), (80.0, 1, 1, 1), (106.0, 2, 4, 2),
        (134.0, 6, 2, 1), (162.0, 3, 1, 1), (190.0, 5, 3, 1), (218.0, 1, 2, 2),
        (245.0, 7, 2, 1), (272.0, 3, 3, 1), (300.0, 4, 1, 2), (330.0, 2, 2, 2)]
GAP_HALF = (0.45, 0.5, 2.2)  # a gap's shaft half width at the top: this x its narrower side, clamped

SEED = 9110271 + 77         # the ceiling's own seed: editing it diffs only the ceiling
FLOOR_Z = 30.5              # nothing hangs below this ...
CORE = (13.0, 39.0)         # ... and nothing within this radius of the centre below this height

LIMB_R = (0.9, 0.45)        # a great limb, root to tip
LIMB_SIDES = 8
LIMB_ROOT_FLAT = (0.3, 0.75)  # the root ring is squashed to fit the wall's 1.2 m top band, round by the 3rd station
LIMB_L = (12.0, 16.0)       # how far it runs inward
LIMB_SWING = (5.0, 10.0)    # degrees of bearing it curves through, alternating sides
LIMB_GAP = 1.3              # daylight between the limb's top and the sheet's lowest lump, once clear of the wall
LIMB_U = (0.1, 0.22, 0.36, 0.5, 0.64, 0.78)    # path stations along the limb before its sweep up

BRANCH_R = (0.45, 0.25)     # a crossing branch out of a limb's side ...
BRANCH_SIDES = 6
BRANCH_ROOT = 0.4           # its socket ring on the limb's side (three of the limb's quads), a touch under BRANCH_R[0]
BRANCH_SEG = 3              # ... leaving from this limb segment (u 0.36..0.5, ~40 %)
BRANCH_SAG = 1.2            # its dip mid-run
BRANCH_SEGS = 12            # segments of its run: ~2 m each, or the thin end's ring chords make slivers
BRANCH_PAST = 3.5           # degrees past the next limb's tip it ends
BRANCH_IN = 2.0             # ... and this much inward of that tip

CLUMPS = 24
CLUMP_R = (1.2, 2.4)
CLUMP_HANG = (0.6, 3.0)     # stem length: the clump's top this far under the sheet
CLUMP_SEGS = (6, 7)         # a clump's segments (its stem's sides): small / big
STEM_R = (0.22, 0.16)
JUNCTION_R = (1.05, 1.35)   # the clump at a limb / branch fork
JUNCTION_SEG = 4            # limb segment its stem leaves from (u 0.5..0.64)
JUNCTION_OUT = 2.6          # how far to the side of the limb the clump hangs

VINES = 30
VINE_R = 0.07
VINE_L = (3.0, 7.0)
VINE_SEGS = 10
VINE_CURL = (0.25, 0.6)     # how far the tip drifts sideways

WELL_R = 0.3                # the least radius of the square well a small sheet socket sits in
HANG_BANDS = 7              # clumps and vines hang from sheet bands 0..6 (r >= 37): the inner bands' quads are too long and thin to socket cleanly
CLEAR = 0.3                 # least gap kept between anything hung and anything else
TWO_PI = 2.0 * math.pi


# =============================================================================
# THE SHEET
# =============================================================================

def _nc(g):
    return len(g.wall[-1])


def _col_of(nc, b):
    return int(round(b / (360.0 / nc))) % nc


def dome_z(rad):
    """The smooth dome's height at radius rad (before the lumps)."""
    return CEIL_Z + CEIL_DOME * (1.0 - (rad / CEIL_R[0]) ** 2)


def sheet_z(g, x, y):
    """The sheet's underside at (x, y), lumps and all."""
    return dome_z(math.hypot(x, y)) + CEIL_LUMP * g.ceil_f(x * 0.5, y * 0.5)


def _gap_cells(nc):
    holes = set()
    for (b, k, cols, bands) in GAPS:
        c0 = _col_of(nc, b)
        for dc in range(cols):
            for dk in range(bands):
                holes.add(((c0 + dc) % nc, k + dk))
    return holes


def ceil_rows(g):
    m = g.m
    nc = _nc(g)
    ceil_n = [nc] * (len(CEIL_R) - len(CEIL_N_INNER)) + CEIL_N_INNER
    g.ceil.append(g.wall[-1])
    for k, rad in enumerate(CEIL_R[1:], start=1):
        row = []
        n = ceil_n[k]
        for i in range(n):
            p = pol(i * 360.0 / n, rad, 0.0)
            row.append(m.v((p[0], p[1], sheet_z(g, p[0], p[1]))))
        g.ceil.append(row)
    g.ceil_pole = m.v((0.0, 0.0, CEIL_Z + CEIL_DOME + CEIL_POLE_LIFT))


def ceil_faces(g):
    m = g.m
    nc = _nc(g)
    holes = _gap_cells(nc)
    g.ceil_holes = holes
    for k in range(len(g.ceil) - 1):
        a, b = g.ceil[k], g.ceil[k + 1]
        if len(a) != len(b):
            zipper(m, a, b, DOWN, "shade", centre=(0.0, 0.0, 0.0))
            continue
        for i in range(nc):
            q = (i + 1) % nc
            if (i, k) in holes:
                continue
            m.quad(a[i], a[q], b[q], b[i], DOWN, "shade")
    last = g.ceil[-1]
    for i in range(len(last)):
        q = (i + 1) % len(last)
        m.tri(g.ceil_pole, last[i], last[q], DOWN, "shade")
    for (b, k, cols, bands) in GAPS:
        c0 = _col_of(nc, b)
        c1 = (c0 + cols) % nc
        ids = (g.ceil[k][c0], g.ceil[k][c1], g.ceil[k + bands][c1], g.ceil[k + bands][c0])
        pts = [m.verts[i] for i in ids]
        w = _dist(pts[0], pts[1])
        h = _dist(pts[1], pts[2])
        half = min(GAP_HALF[2], max(GAP_HALF[1], GAP_HALF[0] * min(w, h)))
        g.rays.append((pts, half))     # the gap's corners: its centre is the shaft's


# =============================================================================
# DRESSING -- limbs, branches, clumps and vines, every one socketed
# =============================================================================

def _dist(p, q):
    return math.sqrt(sum((p[k] - q[k]) ** 2 for k in range(3)))


def _seg_dist(p, a, b):
    ab = sub(b, a)
    L = dot(ab, ab)
    t = 0.0 if L < 1e-12 else max(0.0, min(1.0, dot(sub(p, a), ab) / L))
    return _dist(p, add(a, ab, t))


class _State(object):
    """What dress() keeps between parts: the mesh, its own rng, the sheet quads
    already claimed, and the capsules / spheres placed so far (for clearance)."""

    def __init__(self, g, fb):
        self.g, self.m, self.fb = g, g.m, fb
        self.r = ft._Rng(SEED)
        self.nc = _nc(g)
        self.taken = set()          # sheet quads (col, band) claimed or next to something claimed
        for (i, k) in g.ceil_holes:
            self._take(i, k)
        self.caps = []              # (a, b, radius, tag)
        self.sph = []               # (centre, radius, tag)
        self.count = {"limbs": 0, "branches": 0, "clumps": 0, "junction_clumps": 0, "vines": 0}
        self.min_clear = 1e9
        self.worst = math.pi         # the worst bridging angle any socket here settled for

    def _take(self, i, k):
        for di in (-1, 0, 1):
            for dk in (-1, 0, 1):
                self.taken.add(((i + di) % self.nc, k + dk))

    def sheet_quad(self, k, i):
        i %= self.nc
        q = (i + 1) % self.nc
        ids = (self.g.ceil[k][i], self.g.ceil[k][q], self.g.ceil[k + 1][q], self.g.ceil[k + 1][i])
        return ids if self.m.has_quad(ids) else None

    def sheet_patch(self, bearing, rad, cols=1):
        """``cols`` sheet quads side by side centred on (bearing, rad), none of
        them claimed or next to a claim; shifts a little to find room. Returns
        (quads, centroid) or None."""
        step = 360.0 / self.nc
        for dr in (0.0, -1.5, 1.5, -3.0, 3.0):
            rr = rad + dr
            k = None
            for kk in range(len(CEIL_R) - len(CEIL_N_INNER) - 1):
                if CEIL_R[kk] >= rr >= CEIL_R[kk + 1]:
                    k = kk
            if k is None:
                continue
            for db in (0.0, step, -step, 2 * step, -2 * step):
                bb = bearing + db
                i0 = int(math.floor(bb / step)) if cols % 2 else int(round(bb / step)) - cols // 2
                quads = []
                for dc in range(cols):
                    i = (i0 + dc) % self.nc
                    q = self.sheet_quad(k, i)
                    if q is None or (i, k) in self.taken:
                        quads = None
                        break
                    quads.append(q)
                if not quads:
                    continue
                for dc in range(cols):
                    self._take((i0 + dc) % self.nc, k)
                loop = self.fb._patch_frame(self.m, quads)[3]
                return quads, self.m.centroid(loop)
        return None

    def clear(self, p, rad, skip=None):
        """The smallest gap between a sphere at p and everything placed so far."""
        best = 1e9
        for (a, b, rr, tag) in self.caps:
            if tag is not skip:
                best = min(best, _seg_dist(p, a, b) - rr - rad)
        for (c, rr, tag) in self.sph:
            if tag is not skip:
                best = min(best, _dist(p, c) - rr - rad)
        return best

    def add_tube(self, path, radii, tag):
        n = len(path)
        for i in range(n - 1):
            rr = max(ft._at(radii, i / float(n - 1)), ft._at(radii, (i + 1) / float(n - 1)))
            self.caps.append((path[i], path[i + 1], rr, tag))

    def add_sphere(self, c, rad, tag):
        self.sph.append((c, rad, tag))

    def note(self, p, rad, skip=None):
        self.min_clear = min(self.min_clear, self.clear(p, rad, skip))


def _tube(m, path, radii, sides, zone, caps=(True, True), wob=0.0, rng=None, first_ring=None, last_ring=None,
          phase=0.0):
    """ft.tube with the rings turned ``phase`` round their axis (its own ring
    layout otherwise), so a socket ring built with the same phase never twists."""
    n = len(path)
    fr = ft.frames(path)
    rings = []
    for i in range(n):
        if i == 0 and first_ring is not None:
            rings.append(list(first_ring))
            continue
        if i == n - 1 and last_ring is not None:
            rings.append(list(last_ring))
            continue
        t, ex, ez = fr[i]
        rad = ft._at(radii, i / float(max(1, n - 1)))
        rings.append([m.v(q) for q in _ring(path[i], ex, ez, rad, sides, phase, wob, rng)])
    for i in range(n - 1):
        axis = lerp(path[i], path[i + 1], 0.5)
        for s in range(sides):
            q = (s + 1) % sides
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), axis), zone)
    if caps[0] and first_ring is None:
        m.fan(rings[0], (-fr[0][0][0], -fr[0][0][1], -fr[0][0][2]), zone)
    if caps[1] and last_ring is None:
        m.fan(rings[-1], fr[-1][0], zone)
    return rings


def _ring(centre, ex, ez, radius, sides, phase=0.0, wob=0.0, rng=None):
    pts = []
    for s in range(sides):
        a = phase + TWO_PI * s / sides
        rr = radius * (1.0 + wob * rng.sf()) if (wob and rng) else radius
        pts.append(add(add(centre, ex, rr * math.cos(a)), ez, rr * math.sin(a)))
    return pts


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


def _well(st, quads, path, rad, sides, zone, at_start=True, phase=0.0):
    """A small tube end socketed into a big sheet patch in two stages, so no
    bridging triangle is a sliver: the patch is claimed by a square well ring,
    and the tube's own ring -- projected onto the patch along the tube, phased
    as the tube phases it -- is zipped to the well. The well's size and phase
    are the ones that bridge best on both sides (fb._bridge_quality). Returns
    the tube's ring ids (first_ring / last_ring for ft.tube / _tube)."""
    m, fb = st.m, st.fb
    n, ex, ey, loop = fb._patch_frame(m, quads)
    loop_pts = [m.verts[v] for v in loop]
    c = m.centroid(loop)
    plane = (c, n)
    fr = ft.frames(path)
    t, tx, tz = fr[0] if at_start else fr[-1]
    p = path[0] if at_start else path[-1]
    inner = ft.project_ring(_ring(p, tx, tz, rad, sides, phase), t, plane)
    reach = max(_dist(q, c) for q in inner)
    base = max(WELL_R, 1.4 * reach + 0.1)
    best = None
    for ra in (base, base + 0.08, base + 0.16, base + 0.25, base + 0.35):
        for k in range(36):
            ph = TWO_PI * k / 36
            sq = [add(add(c, ex, ra * math.cos(ph + TWO_PI * j / 4)), ey, ra * math.sin(ph + TWO_PI * j / 4))
                  for j in range(4)]
            q = min(fb._bridge_quality(loop_pts, sq, n, ex, ey), fb._bridge_quality(sq, inner, n, ex, ey))
            if best is None or q > best[0]:
                best = (q, sq)
    outer = [m.v(q) for q in best[1]]
    m.socket(quads, outer, zone)
    ids = [m.v(q) for q in inner]
    _zip(m, outer, ids, n, ex, ey, zone)
    st.worst = min(st.worst, best[0])
    return ids


def _limb_radius(seg, t, n):
    return ft._at(LIMB_R, (seg + t) / float(n - 1))


# ---- limbs -------------------------------------------------------------------

def _limb(st, b, k):
    """One great limb: out of the wall's top bark band at the pilaster at
    bearing b, curving inward (swinging to one side) and up under the sheet,
    sweeping up into a two-quad sheet socket at its tip."""
    g, m, r, fb = st.g, st.m, st.r, st.fb
    nc = st.nc
    c0 = fb._col_of(b)
    j = len(g.wall) - 2
    patch = []
    for i in (c0 - 1, c0, c0 + 1):
        i %= nc
        q = (g.wall[j][i], g.wall[j][(i + 1) % nc], g.wall[j + 1][(i + 1) % nc], g.wall[j + 1][i])
        if m.has_quad(q):
            patch.append(q)
    loop = fb._patch_frame(m, patch)[3]
    p0 = m.centroid(loop)
    r0 = math.hypot(p0[0], p0[1])
    L = r.u(*LIMB_L)
    swing = r.u(*LIMB_SWING) * (1.0 if k % 2 == 0 else -1.0)
    found = st.sheet_patch(b + swing, r0 - L, cols=2)
    if found is None:
        found = st.sheet_patch(b + swing * 0.5, r0 - L + 2.0, cols=2)
    end_patch, end_c = found
    r_end = math.hypot(end_c[0], end_c[1])
    b_end = -math.degrees(math.atan2(end_c[1], end_c[0]))
    n = len(LIMB_U) + 3
    path = [p0]
    for idx, u in enumerate(LIMB_U, start=1):
        rad = ft._at(LIMB_R, idx / float(n - 1))
        gap = LIMB_GAP * min(1.0, 0.35 + 1.7 * u)       # hugs the sheet's edge, then peels away
        p = pol(b + swing * u ** 1.3, r0 - (r0 - r_end) * u, 0.0)
        z = max(dome_z(math.hypot(p[0], p[1])) - (CEIL_LUMP + rad + gap), FLOOR_Z + rad + 0.3)
        if idx == 1:                                     # leaves the trunk top rising, just under the sheet's edge
            z = min(max(z, p0[2] + 0.4), sheet_z(g, p[0], p[1]) - rad - 0.3)
        path.append((p[0], p[1], z))
    rad = ft._at(LIMB_R, (n - 2) / float(n - 1))
    p = pol(b_end, r_end + 0.9, 0.0)                     # the sweep up into the sheet
    path.append((p[0], p[1], dome_z(r_end + 0.9) - (CEIL_LUMP + rad + 0.45)))
    path.append(end_c)
    flat = list(LIMB_ROOT_FLAT) + [1.0] * (len(path) - len(LIMB_ROOT_FLAT))
    rings = fb._ptube(m, path, LIMB_R, LIMB_SIDES, "bark", start=(patch, "bark"), end=(end_patch, "shade"),
                      flat=flat, wob=0.04, rng=r)
    tag = ("limb", k)
    st.add_tube(path, LIMB_R, tag)
    st.count["limbs"] += 1
    return {"b": b, "swing": swing, "b_end": b_end, "r_end": r_end, "path": path, "rings": rings,
            "tag": tag, "k": k}


def _side_patch(st, limb, seg, d, nq):
    """``nq`` neighbouring quads of the limb's segment ``seg`` facing ``d``:
    (quads, their centroid)."""
    m = st.m
    rings, path = limb["rings"], limb["path"]
    ns = len(rings[seg])
    axis = lerp(path[seg], path[seg + 1], 0.5)

    def quad(s):
        s %= ns
        return (rings[seg][s], rings[seg][(s + 1) % ns], rings[seg + 1][(s + 1) % ns], rings[seg + 1][s])

    def score(s):
        return dot(norm(sub(m.centroid(quad(s)), axis)), d)

    best = max(range(ns), key=score)
    if nq == 3:
        sides = [best - 1, best, best + 1]
    else:
        nb = best + 1 if score(best + 1) >= score(best - 1) else best - 1
        sides = [best, nb]
    quads = [quad(s) for s in sides]
    if not all(m.has_quad(q) for q in quads):
        return None
    n, _ex, _ey, loop = st.fb._patch_frame(m, quads)
    return quads, m.centroid(loop), n


def _side_pts(st, limb, seg, path, rad, sides, phase):
    """A tube's first ring on the limb's own surface: laid in the surface's
    tangent plane at path[0] (a ring tilted to the surface, slid onto the
    cylinder, comes out skewed), its ex the tube frame's ex turned into that
    plane so _tube's next ring pairs with it vertex for vertex."""
    a, b = limb["path"][seg], limb["path"][seg + 1]
    n = len(limb["path"])
    t, ex, ez = ft.frames(path)[0]
    ab = sub(b, a)
    tt = max(0.0, min(1.0, dot(sub(path[0], a), ab) / dot(ab, ab)))
    ns = norm(sub(path[0], add(a, ab, tt)))          # the surface normal at the socket
    ex = norm(sub(ex, (ns[0] * dot(ex, ns), ns[1] * dot(ex, ns), ns[2] * dot(ex, ns))))
    ez = ft.cross(ns, ex)
    pts = []
    for s in range(sides):
        ang = phase + TWO_PI * s / sides
        p = add(add(path[0], ex, rad * math.cos(ang)), ez, rad * math.sin(ang))
        tt = max(0.0, min(1.0, dot(sub(p, a), ab) / dot(ab, ab)))
        ap = add(a, ab, tt)
        pts.append(add(ap, norm(sub(p, ap)), _limb_radius(seg, tt, n)))
    return pts


def _side_ring(st, limb, seg, quads, path, rad, sides, zone):
    """Socket a _side_pts ring into ``quads`` at the phase that bridges best
    (a loop vertex far along the limb seeing a ring edge end-on is a sliver).
    Returns (ids, phase)."""
    m, fb = st.m, st.fb
    n, ex, ey, loop = fb._patch_frame(m, quads)
    loop_pts = [m.verts[v] for v in loop]
    best = None
    for k in range(24):
        ph = TWO_PI * k / 24
        pts = _side_pts(st, limb, seg, path, rad, sides, ph)
        q = fb._bridge_quality(loop_pts, pts, n, ex, ey)
        if best is None or q > best[0]:
            best = (q, ph, pts)
    ids = [m.v(p) for p in best[2]]
    m.socket(quads, ids, zone)
    st.worst = min(st.worst, best[0])
    return ids, best[1]


def _sideways(b_from, b_to, rad):
    """Unit direction at bearing b_from (radius rad), toward bearing b_to."""
    p, q = pol(b_from, rad, 0.0), pol(b_to, rad, 0.0)
    return norm(sub(q, p))


def _branch(st, A, B):
    """A crossing branch out of limb A's side at ~40 % of its length, running
    diagonally under the sheet past limb B's tip to a sheet socket just beyond it."""
    g, m, r, fb = st.g, st.m, st.r, st.fb
    seg = BRANCH_SEG
    a_mid = lerp(A["path"][seg], A["path"][seg + 1], 0.5)
    r_mid = math.hypot(a_mid[0], a_mid[1])
    b_mid = -math.degrees(math.atan2(a_mid[1], a_mid[0]))
    dh = _sideways(b_mid, B["b"], r_mid)
    sign = 1.0 if ((B["b"] - A["b"]) % 360.0) < 180.0 else -1.0
    d = norm(add(dh, (0.0, 0.0, -0.35)))
    found = _side_patch(st, A, seg, d, 3)
    if found is None:
        return None
    patch, start, n_p = found
    end = st.sheet_patch(B["b_end"] + sign * BRANCH_PAST, B["r_end"] - BRANCH_IN, cols=2)
    if end is None:
        end = st.sheet_patch(B["b_end"] + sign * BRANCH_PAST * 1.6, B["r_end"] - BRANCH_IN - 1.5, cols=2)
    if end is None:
        return None
    end_patch, end_c = end
    p1 = add(start, norm(add(n_p, d, 0.5)), 1.4)
    r_e = math.hypot(end_c[0], end_c[1])
    b_e = -math.degrees(math.atan2(end_c[1], end_c[0]))
    back = _sideways(b_e, b_mid, r_e)
    pre = add(end_c, back, 0.55)
    pre = (pre[0], pre[1], sheet_z(g, pre[0], pre[1]) - 1.3)
    mid = lerp(p1, pre, 0.5)
    inward = norm((-mid[0], -mid[1], 0.0))
    ctrl = add(add(mid, inward, 1.5), (0.0, 0.0, -BRANCH_SAG))
    path = [start, p1] + bez(p1, ctrl, pre, BRANCH_SEGS)[1:] + [end_c]
    n = len(path)
    for i in range(1, n - 1):                    # under the sheet, over the floor, clear of the limbs
        x, y, z = path[i]
        rad = ft._at(BRANCH_R, i / float(n - 1))
        z = min(z, sheet_z(g, x, y) - rad - 0.45)
        z = max(z, FLOOR_Z + rad + 0.25)
        skip = A["tag"] if i <= 2 else None
        for _ in range(8):
            if st.clear((x, y, z), rad, skip) >= CLEAR or z - 0.3 < FLOOR_Z + rad + 0.25:
                break
            z -= 0.3
        path[i] = (x, y, z)
    ring0, ph = _side_ring(st, A, seg, patch, path, BRANCH_ROOT, BRANCH_SIDES, "bark")
    ring1 = _well(st, end_patch, path, BRANCH_R[1], BRANCH_SIDES, "shade", at_start=False, phase=ph)
    _tube(m, path, BRANCH_R, BRANCH_SIDES, "bark", caps=(False, False), wob=0.05, rng=r,
          first_ring=ring0, last_ring=ring1, phase=ph)
    for i in range(2, n - 1):
        st.note(path[i], ft._at(BRANCH_R, i / float(n - 1)))
    tag = ("branch", A["k"])
    st.add_tube(path, BRANCH_R, tag)
    st.count["branches"] += 1
    return {"path": path, "tag": tag, "sign": sign, "dh": dh}


# ---- clumps ---------------------------------------------------------------------

def _clump_hang(m, ring, centre, radius, zone, rng, squash=0.75, wob=0.2):
    """A leaf clump hung off a tube's last ring (its top): rings down round a
    ball, each vertex under its own on the ring above, a bottom tip. ft.clump_end
    turned over -- the stem comes from above here."""
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
    return rings


def _clump_fits(st, centre, radius, skip=None):
    """The clump's sphere clears everything placed, the floor, the wall, the
    core, and the sheet over its top ring."""
    g = st.g
    R = radius * 1.2
    if centre[2] - 0.75 * R < FLOOR_Z + 0.2:
        return False
    rc = math.hypot(centre[0], centre[1])
    if rc + R > CEIL_R[0] - 1.6 or (rc - R < CORE[0] + 1.0 and centre[2] - 0.75 * R < CORE[1]):
        return False
    if st.clear(centre, R, skip) < CLEAR:
        return False
    top = centre[2] + 0.43 * R
    for s in range(8):
        a = TWO_PI * s / 8
        x, y = centre[0] + 0.82 * R * math.cos(a), centre[1] + 0.82 * R * math.sin(a)
        if sheet_z(g, x, y) - top < 0.3:
            return False
    return True


def _stem_clump(st, quads, path, radius, zone, segs, tag):
    """A stem out of ``quads`` along ``path`` (its last segment vertical) with a
    clump hung off its end; the clump's top ring sits just under the stem's end."""
    m, r = st.m, st.r
    ring0 = _well(st, quads, path, STEM_R[0], segs, "shade")
    rings = ft.tube(m, path, STEM_R, segs, "bark", caps=(False, False), first_ring=ring0)
    end = path[-1]
    centre = (end[0], end[1], end[2] - 0.64 * radius)
    _clump_hang(m, rings[-1], centre, radius, zone, r)
    st.add_tube(path, STEM_R, tag)
    st.add_sphere(centre, radius * 1.2, tag)


def _junction_clump(st, limb, branch):
    """The tuft at a limb / branch fork: a stem out of the limb's side opposite
    the branch, a little further along, rising over the limb's shoulder and
    dropping into a clump beside it."""
    g, m, r = st.g, st.m, st.r
    d_away = norm(add((-branch["dh"][0], -branch["dh"][1], 0.0), (0.0, 0.0, 0.5)))
    for seg in (JUNCTION_SEG, JUNCTION_SEG + 1, JUNCTION_SEG - 1):
        found = _side_patch(st, limb, seg, d_away, 3)
        if found is None:
            continue
        quads, p0, n_p = found
        radius = r.u(*JUNCTION_R)
        side = norm((d_away[0], d_away[1], 0.0))
        path = [p0, add(p0, norm(add(n_p, side, 0.5)), 1.0), add(add(p0, side, 2.0), UP, 0.55),
                add(add(p0, side, JUNCTION_OUT), UP, 0.2), add(add(p0, side, JUNCTION_OUT), UP, -0.25)]
        centre = (path[-1][0], path[-1][1], path[-1][2] - 0.64 * radius)
        ok = _clump_fits(st, centre, radius, limb["tag"])
        # the clump must also clear its own limb: only the stem may touch it
        if ok and _seg_dist(centre, limb["path"][seg], limb["path"][seg + 1]) < radius * 1.2 + LIMB_R[0] * 0.75 + 0.2:
            ok = False
        if not ok:
            radius = JUNCTION_R[0]
            centre = (path[-1][0], path[-1][1], path[-1][2] - 0.64 * radius)
            ok = _clump_fits(st, centre, radius, limb["tag"])
        if not ok:
            continue
        stem_path = path
        ring0, ph = _side_ring(st, limb, seg, quads, stem_path, STEM_R[0], CLUMP_SEGS[0], "bark")
        rings = _tube(m, stem_path, STEM_R, CLUMP_SEGS[0], "bark", caps=(False, False), first_ring=ring0, phase=ph)
        _clump_hang(m, rings[-1], centre, radius, "leaf", r)
        tag = ("junction", limb["k"])
        st.add_tube(stem_path, STEM_R, tag)
        st.add_sphere(centre, radius * 1.2, tag)
        st.count["junction_clumps"] += 1
        return True
    return False


def _hanging_clumps(st):
    """~CLUMPS leaf clumps on stems out of sheet quads, at varied depths and
    sizes: the deep big ones where the dome is high, shallow small ones near the
    wall; 'leaf' where they hang low into the light, 'shade' close under the sheet."""
    g, m, r = st.g, st.m, st.r
    nb = HANG_BANDS
    made = 0
    for n in range(CLUMPS):
        hang = CLUMP_HANG[0] + (CLUMP_HANG[1] - CLUMP_HANG[0]) * ((n * 7) % CLUMPS) / float(CLUMPS - 1)
        radius = CLUMP_R[0] + (CLUMP_R[1] - CLUMP_R[0]) * ((n * 5 + 2) % CLUMPS) / float(CLUMPS - 1)
        for _ in range(120):
            k = r.i(0, nb - 1)
            i = r.i(0, st.nc - 1)
            if (i, k) in st.taken or (i + 1, k) in st.taken:
                continue
            qs = [st.sheet_quad(k, i), st.sheet_quad(k, i + 1)]
            if None in qs:
                continue
            c = m.centroid(st.fb._patch_frame(m, qs)[3])
            depth = c[2] - FLOOR_Z - 0.3                        # room under this spot
            h, rad = hang, radius
            if h + 1.55 * rad > depth:                          # too low here: shorten, then shrink
                h = max(CLUMP_HANG[0], depth - 1.55 * rad)
            if h + 1.55 * rad > depth:
                rad = max(CLUMP_R[0], (depth - h) / 1.55)
            if h + 1.55 * rad > depth:
                continue
            lat = r.u(0.15, 0.45) * h
            ang = r.f() * TWO_PI
            side = (math.cos(ang), math.sin(ang), 0.0)
            p1 = add(add(c, side, lat), DOWN, h * 0.5)
            p2 = add(p1, DOWN, h * 0.5)
            centre = (p2[0], p2[1], p2[2] - 0.64 * rad)
            if not _clump_fits(st, centre, rad):
                continue
            if st.clear(p1, STEM_R[0]) < CLEAR:
                continue
            st._take(i, k)
            st._take(i + 1, k)
            segs = CLUMP_SEGS[1] if rad > 1.8 else CLUMP_SEGS[0]
            zone = "leaf" if h + 0.5 * rad >= 2.0 else "shade"
            _stem_clump(st, qs, [c, p1, p2], rad, zone, segs, ("clump", n))
            made += 1
            break
    st.count["clumps"] = made


# ---- vines ----------------------------------------------------------------------

def _vines(st):
    g, m, r = st.g, st.m, st.r
    nb = HANG_BANDS
    made = 0
    for n in range(VINES):
        for _ in range(120):
            k = r.i(0, nb - 1)
            i = r.i(0, st.nc - 1)
            if (i, k) in st.taken or (i + 1, k) in st.taken:
                continue
            qs = [st.sheet_quad(k, i), st.sheet_quad(k, i + 1)]
            if None in qs:
                continue
            c = m.centroid(st.fb._patch_frame(m, qs)[3])
            L = min(r.u(*VINE_L), c[2] - FLOOR_Z - 0.3)
            if L < VINE_L[0] - 0.5:
                continue
            if math.hypot(c[0], c[1]) < CORE[0] + 2.0 and c[2] - L < CORE[1]:
                continue
            phi = r.f() * TWO_PI
            turn = r.u(1.2, 2.4)
            amp = r.u(*VINE_CURL)
            path = []
            for j in range(VINE_SEGS + 1):
                u = j / float(VINE_SEGS)
                a = phi + turn * u
                rr = amp * u ** 0.7 + 0.12 * math.sin(math.pi * u) * u
                path.append((c[0] + rr * math.cos(a), c[1] + rr * math.sin(a), c[2] - L * u))
            if any(st.clear(p, VINE_R) < CLEAR * 0.7 for p in path[1:]):
                continue
            st._take(i, k)
            st._take(i + 1, k)
            ring0 = _well(st, qs, path, VINE_R, 4, "shade")
            ft.tube(m, path, (VINE_R, VINE_R * 0.85, VINE_R * 0.7), 4, "bark", caps=(False, True),
                    first_ring=ring0)
            st.add_tube(path, (VINE_R, VINE_R), ("vine", n))
            made += 1
            break
    st.count["vines"] = made


# ---- dress ------------------------------------------------------------------------

def dress(g):
    """Limbs, crossing branches, fork tufts, hanging clumps and vines under the sheet."""
    import sys
    fb = sys.modules[g.__class__.__module__]   # the driver (forest_build, or a render copy of it): its _ptube, TRUNKS, ...
    st = _State(g, fb)
    before = sum(1 for f in g.m.faces if f is not None)
    limbs = [_limb(st, b, k) for k, b in enumerate(fb.TRUNKS)]
    branches = [_branch(st, limbs[k], limbs[(k + 1) % len(limbs)]) for k in range(len(limbs))]
    for limb, br in zip(limbs, branches):
        if br is not None:
            _junction_clump(st, limb, br)
    _hanging_clumps(st)
    _vines(st)
    after = sum(1 for f in g.m.faces if f is not None)
    lowest = min(v[2] for (a, b, rr, tag) in st.caps for v in (a, b)) - LIMB_R[0]
    print("MDL STATS ceiling dome_y=%.1f..%.1f gaps=%d limbs=%d branches=%d junction_clumps=%d clumps=%d vines=%d "
          "tris_added=%d min_clear=%.2f lowest_axis=%.1f worst_bridge_deg=%.1f"
          % (CEIL_Z, CEIL_Z + CEIL_DOME, len(GAPS), st.count["limbs"], st.count["branches"],
             st.count["junction_clumps"], st.count["clumps"], st.count["vines"], after - before,
             st.min_clear, lowest + LIMB_R[0], math.degrees(st.worst)))
    g.ceil_stats = dict(st.count, tris_added=after - before)
