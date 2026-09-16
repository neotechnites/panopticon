"""
marble_wall -- the WALL part of Map 2 (marble): from the spike floor's outer
ring (seam_wall_foot) up to the crown of the dome. A part of marble_build.py,
built into its welded _Mesh against the seam contract there.

    socles       plain ashlar from every tier's base to its sill line
    7 tiers      64 arched cells each (mb.TIER_BASE), Map 1's cell size
                 (4.0 x 5.5 m mouths); EVERY cell an open recess CELL_D deep
                 to a dark back wall
    bars         BAR_N square iron bars over every arch: pyramids standing on
                 the sill BAR_D into the reveal, tips set into the head. Their
                 feet are stitched into the sill's own reveal, so the bars are
                 part of the one stone
    pilasters    on every pier, sill line to cornice, running up INTO the cornice
    cornices     one per tier, band mb.BAND_Z -- except the SLAB_TIER's, band
                 mb.SLAB_BAND_Z (SLAB_Z0 .. DECK_Z), which has NO FRONT FACE:
                 its soffit and top front lines are mb.slab_stations() at those
                 two heights (mb.seam_slab), and the lane part's walkway slab
                 closes onto them
    frieze       the Greek key over the top tier, and the great cornice whose
                 back edge is the dome's spring ring (mb.seam_dome_spring)
    dome         a coffered spherical cap off the 192-station spring ring, 64
                 facets round, thinning to 32 then 16 toward the medallion

Every point on the wall face is _Bay.at(u, z, d), so shared points weld. The
only free edges this part leaves are three loops of 192: the foot ring at
FLOOR_Z and the slab tier's two cornice front lines. No T-junction: the frame
round each arch is zippered straight onto the corners of its bay rectangle,
so the rectangle's edges carry no stray vertices and the pilaster returns,
soffits and cornice faces are plain quads.

    python3 tools/modelling/marble_wall_build.py      # build alone, audit
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

if __name__ == "__main__":                # the lane part is not needed to audit this one
    import types
    sys.modules.setdefault("marble_lane_build", types.ModuleType("marble_lane_build"))

import marble_build as mb  # noqa: E402

# =============================================================================
# TUNABLES (the wall's own; the shared ones are mb.*)
# =============================================================================

PW = mb.PILASTER_W
PP = mb.PILASTER_PROUD
HW = mb.ARCH_W / 2.0
BHW = mb.BAR_HW
BAR_SET = 0.06              # a bar's tip this far past the head's circle: set into the stone
DOME_FIRST_BAND = 1.5       # metres up the sphere the 192 -> 64 zipper band takes
DOME_THIN = (32, 16)        # station counts of the last two rings, toward the pole
SIDE_SPLITS = 1             # the frame's side margins, pilaster fronts and returns in this many stacked quads
SIDE_SWITCH = 0.5           # head angle where the frame's fan moves from the middle side point to the top corner
COFFER_ZONE = "coffer"
UP, DOWN = mb.UP, mb.DOWN
TWO_PI = mb.TWO_PI

_STATS = {}
_Bay = mb._Bay              # mb.slab_stations() and wall_stations() use this very class: the seams weld


# =============================================================================
# HELPERS
# =============================================================================

def _tier_band(tier):
    """(z1, z2) of the tier's cornice over the tier base."""
    return mb.SLAB_BAND_Z if tier == mb.SLAB_TIER else mb.BAND_Z


def _area2(p, q, r):
    ux, uy, uz = q[0] - p[0], q[1] - p[1], q[2] - p[2]
    vx, vy, vz = r[0] - p[0], r[1] - p[1], r[2] - p[2]
    cx, cy, cz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    return math.sqrt(cx * cx + cy * cy + cz * cz)


def _convex(m, ids, want, zone):
    """A convex polygon (it may carry collinear runs) as the fan whose
    thinnest triangle is fattest: the apex is never inside a collinear run."""
    n = len(ids)
    if n == 3:
        m.tri(ids[0], ids[1], ids[2], want, zone)
        return
    if n == 4:
        m.quad(ids[0], ids[1], ids[2], ids[3], want, zone)
        return
    pts = [m.verts[i] for i in ids]
    best, best_min = 0, -1.0
    for a in range(n):
        lo = 1e9
        for k in range(1, n - 1):
            lo = min(lo, _area2(pts[a], pts[(a + k) % n], pts[(a + k + 1) % n]))
        if lo > best_min:
            best, best_min = a, lo
    if best_min < 1e-7:
        raise RuntimeError("no non-degenerate fan for a %d-gon" % n)
    ring = ids[best:] + ids[:best]
    m.fan(ring, want, zone)


def _zip_open(m, inner, inner_a, outer, outer_a, want, zone):
    """Triangles between two open chains ordered by a shared parameter (an
    angle here): whichever chain's next point comes first advances. The ends
    are joined: inner[0]-outer[0] and inner[-1]-outer[-1] are edges."""
    ni, no = len(inner), len(outer)
    i = o = 0
    while i < ni - 1 or o < no - 1:
        ai = inner_a[i + 1] if i < ni - 1 else 1e9
        ao = outer_a[o + 1] if o < no - 1 else 1e9
        if ai <= ao:
            m.tri(inner[i], inner[i + 1], outer[o], want, zone)
            i += 1
        else:
            m.tri(inner[i], outer[o], outer[o + 1], want, zone)
            o += 1


def _zip_ring(m, outer, outer_a, inner, inner_a, want, zone):
    """mb._zipper with the tie broken the other way: when the two rings have
    a station at the same angle, the INNER advances first, so the outer's
    station pairs with the inner vertex under it and not with the one a
    whole facet back (which made 1 degree triangles on the dome's first
    band, whose outer stations sit 0.5 m apart round each corner)."""
    no, ni = len(outer), len(inner)
    io = ii = 0
    a_o = list(outer_a) + [outer_a[0] + TWO_PI]
    a_i = list(inner_a) + [inner_a[0] + TWO_PI]
    while io < no or ii < ni:
        next_o = a_o[io + 1] if io < no else 1e9
        next_i = a_i[ii + 1] if ii < ni else 1e9
        o0, i0 = outer[io % no], inner[ii % ni]
        if next_o < next_i - 1e-9:
            tri = (o0, outer[(io + 1) % no], i0)
            io += 1
        else:
            tri = (o0, inner[(ii + 1) % ni], i0)
            ii += 1
        w = want(m.verts[tri[0]], m.verts[tri[1]], m.verts[tri[2]]) if callable(want) else want
        m.tri(tri[0], tri[1], tri[2], w, zone)


class _Rec(object):
    """A stand-in for _Mesh: records a zip's triangles as index triples."""

    def __init__(self):
        self.tris = []

    def tri(self, a, b, c, want, zone):
        self.tris.append((a, b, c))


# =============================================================================
# ONE CELL: frame, reveal, the barred sill and a dark back wall
# =============================================================================

class _Cell(object):
    """The arch of one bay on one tier, in the bay's (u, z) plane.

    outline: the closed loop, sill left to right, up the right jamb, over the
    head (right to left), down the left jamb -- as (u, z). chain_a: the angle
    of each outline point round the springing centre, monotonic from the
    right sill corner (negative) to the left sill corner (past pi)."""

    def __init__(self, bay, tier):
        self.bay = bay
        B = mb.TIER_BASE[tier]
        band = _tier_band(tier)
        self.B = B
        self.s = B + mb.SILL_UP
        self.sp = self.s + mb.ARCH_JAMB
        self.crown = self.sp + HW
        self.z1, self.z2 = B + band[0], B + band[1]
        self.u0, self.u1 = PW / 2.0, bay.L - PW / 2.0
        self.c = bay.L / 2.0
        c, s, sp = self.c, self.s, self.sp
        head = [math.pi * k / mb.HEAD_SEG for k in range(mb.HEAD_SEG + 1)]
        # the side margins are split in SIDE_SPLITS: the rect's side points,
        # and the jamb points at the same heights (those under the springing)
        self.side_z = [s + (self.z1 - s) * k / SIDE_SPLITS for k in range(SIDE_SPLITS + 1)]
        jamb = [z for z in self.side_z[1:-1] if z < sp - 1e-6]
        # the outline: sill, right jamb up, head right to left, left jamb down
        pts = [(c - HW, s), (c + HW, s)]
        pts += [(c + HW, z) for z in jamb] + [(c + HW, sp)]
        pts += [(c + HW * math.cos(t), sp + HW * math.sin(t)) for t in head[1:-1]]
        pts += [(c - HW, sp)] + [(c - HW, z) for z in reversed(jamb)]
        self.outline = pts
        # THE FRAME, zipped onto the rectangle's side points. The right half
        # is zipped (_zip_open) from the right sill corner up to the crown, by
        # angle about the springing centre; the left half is its MIRROR
        # (index for index), and one bridge triangle crown / top-right /
        # top-left joins them. A single zip round the whole arch is not
        # symmetric: sweeping down the left side it reaches the bottom corner
        # before the jamb's mid point and leaves a sliver there.
        crown_k = 2 + len(jamb) + mb.HEAD_SEG // 2                # outline index of the crown
        self.chain = list(range(1, crown_k + 1))
        self.chain_a = [math.atan2(pts[k][1] - sp, pts[k][0] - c) for k in self.chain]
        right = [(self.u1, z) for z in self.side_z]                  # ascending
        left = [(self.u0, z) for z in reversed(self.side_z)]
        self.rect = right + left
        # the hand-over angles up the right side: a side point under the
        # springing takes over at its own ray (after the jamb point at its
        # height, which is steeper), the ones beside the head at the
        # springing and SIDE_SWITCH. NOT the corners' own rays: a corner's fan
        # over the convex head is only sound up to its tangent point.
        n_side = len(self.side_z)
        ray = [math.atan2(z - sp, self.u1 - c) for z in self.side_z]
        up = [-1e9]
        for k in range(1, n_side):
            if self.side_z[k] < sp:
                up.append(ray[k])
            elif k == n_side - 1:
                up.append(SIDE_SWITCH)
            else:
                up.append(0.0 if not any(a >= 0.0 for a in up) else
                          min(SIDE_SWITCH, SIDE_SWITCH * (k - 1) / max(1, n_side - 2)))
        self.rect_a = up
        n_out = len(pts)
        rec = _Rec()
        _zip_open(rec, self.chain, self.chain_a, [n_out + k for k in range(n_side)], up, UP, "")
        allpts = pts + self.rect
        key = dict(((round(u, 6), round(z, 6)), k) for k, (u, z) in enumerate(allpts))
        mirror = [key[(round(2.0 * c - u, 6), round(z, 6))] for (u, z) in allpts]
        self.frame = list(rec.tris)
        self.frame += [(mirror[a], mirror[b], mirror[c]) for (a, b, c) in rec.tris]
        self.frame.append((crown_k, n_out + n_side - 1, n_out + n_side))
        # the bars: evenly spaced across the mouth, standing BAR_D into the reveal
        self.bar_u = [c - HW + (k + 1) * mb.ARCH_W / (mb.BAR_N + 1) for k in range(mb.BAR_N)]

    def head_z(self, u):
        return self.sp + math.sqrt(max(0.0, HW * HW - (u - self.c) ** 2))

    def foot(self, m, k, front, left):
        """A corner of bar k's square foot on the sill."""
        u = self.bar_u[k] + (-BHW if left else BHW)
        d = mb.BAR_D + (-BHW if front else BHW)
        return m.v(self.bay.at(u, self.s, d))


def _plinth(m, bl, br, top, want, zone):
    """[bl, br] against a top chain of many points: one big triangle to a
    middle top point, then a fan from each bottom corner over its half."""
    j = len(top) // 2
    m.tri(bl, br, top[j], want, zone)
    for k in range(0, j):
        m.tri(bl, top[k], top[k + 1], want, zone)
    for k in range(j, len(top) - 1):
        m.tri(br, top[k], top[k + 1], want, zone)


def _sill(m, cell, fl, fr, br, bl):
    """The sill's reveal, [c-HW, c+HW] x [0, CELL_D] in (u, d), with the
    bars' square feet cut out of it: a fan from the front-left corner over
    the back chain (the front-right corner, then every foot's front corners
    right to left), the same from the back-left corner over the feet's back
    corners, one gap quad between consecutive feet and one at each end. The
    feet's four edges are then each on one sill face and one bar face."""
    n = mb.BAR_N
    ff = [(cell.foot(m, k, True, True), cell.foot(m, k, True, False)) for k in range(n)]    # (left, right)
    bf = [(cell.foot(m, k, False, True), cell.foot(m, k, False, False)) for k in range(n)]
    chain = [fr]
    for k in reversed(range(n)):
        chain += [ff[k][1], ff[k][0]]
    m.fan([fl] + chain, UP, "shade")
    chain = [br]
    for k in reversed(range(n)):
        chain += [bf[k][1], bf[k][0]]
    m.fan([bl] + chain, UP, "shade")
    m.quad(fl, ff[0][0], bf[0][0], bl, UP, "shade")
    for k in range(n - 1):
        m.quad(ff[k][1], ff[k + 1][0], bf[k + 1][0], bf[k][1], UP, "shade")
    m.quad(ff[n - 1][1], fr, br, bf[n - 1][1], UP, "shade")


def _bars(m, cell):
    """BAR_N square pyramids: feet on the sill (the sill's own vertices), the
    apex BAR_SET past the head's circle -- in the stone."""
    bay = cell.bay
    for k in range(mb.BAR_N):
        u = cell.bar_u[k]
        apex = m.v(bay.at(u, cell.head_z(u) + BAR_SET, mb.BAR_D))
        fl, fr = cell.foot(m, k, True, True), cell.foot(m, k, True, False)
        bl, br = cell.foot(m, k, False, True), cell.foot(m, k, False, False)
        m.tri(fl, fr, apex, bay.n_in, "iron")
        m.tri(br, bl, apex, bay.n_out, "iron")
        m.tri(bl, fl, apex, bay.dir(-1.0, 0.0), "iron")
        m.tri(fr, br, apex, bay.dir(1.0, 0.0), "iron")
    _STATS["bars"] = _STATS.get("bars", 0) + mb.BAR_N


def _cell(m, i, tier, zone_face):
    """One cell of bay i on tier `tier`."""
    bay = _Bay(i)
    cell = _Cell(bay, tier)
    c, sp = cell.c, cell.sp
    n_in = bay.n_in

    loop0 = [m.v(bay.at(u, z)) for (u, z) in cell.outline]
    rect = [m.v(bay.at(u, z)) for (u, z) in cell.rect]
    # the frame: the outline zipped onto the rectangle's side points
    ids = loop0 + rect
    for (a, b, c3) in cell.frame:
        m.tri(ids[a], ids[b], ids[c3], n_in, zone_face)

    # the plinth under the sill: bottom corners only (the seam / the cornice
    # top has nothing between them), the sill line's points along the top
    bl, br = m.v(bay.at(cell.u0, cell.B)), m.v(bay.at(cell.u1, cell.B))
    _plinth(m, bl, br, [rect[-1], loop0[0], loop0[1], rect[0]], n_in, "plinth")

    # the reveal: every outline segment CELL_D into the wall -- but the sill
    # (segment 0 -> 1), which carries the bars' feet
    loopd = [m.v(bay.at(u, z, mb.CELL_D)) for (u, z) in cell.outline]
    nl = len(cell.outline)
    for k in range(1, nl):
        j = (k + 1) % nl
        mu = 0.5 * (cell.outline[k][0] + cell.outline[j][0])
        mz = 0.5 * (cell.outline[k][1] + cell.outline[j][1])
        w = bay.dir(c - mu, sp - mz)                          # toward the springing centre
        if abs(w[0]) + abs(w[1]) + abs(w[2]) < 1e-9:
            w = UP
        m.quad(loop0[k], loop0[j], loopd[j], loopd[k], w, "shade")
    _sill(m, cell, loop0[0], loop0[1], loopd[1], loopd[0])
    _convex(m, loopd, n_in, "cellin")                        # the dark back wall

    n0 = len(m.faces)
    _bars(m, cell)
    _STATS["tris_bars"] = _STATS.get("tris_bars", 0) + len(m.faces) - n0
    _STATS["cells"] = _STATS.get("cells", 0) + 1


# =============================================================================
# PILASTERS AND CORNICES
# =============================================================================

def _pilaster_half(m, i, bay, u_edge, side_z, left):
    """One half of a pilaster, in bay i: the half from the bay corner (u 0 or
    L) to the pilaster edge u_edge, in stacked quads at the frame's side
    heights. left: this is the bay's left corner."""
    corner = i if left else i + 1
    s = side_z[0]
    cs = [m.v(mb.corner_pt(corner, z, PP)) for z in side_z]
    fs = [m.v(bay.at(u_edge, z, -PP)) for z in side_z]
    es = [m.v(bay.at(u_edge, z)) for z in side_z]
    for k in range(len(side_z) - 1):
        m.quad(cs[k], fs[k], fs[k + 1], cs[k + 1], bay.n_in, "column")               # the fluted front
        m.quad(fs[k], es[k], es[k + 1], fs[k + 1], bay.dir(1.0 if left else -1.0, 0.0), "marble")   # the return
    ws = m.v(bay.at(0.0 if left else bay.L, s))
    m.quad(ws, es[0], fs[0], cs[0], DOWN, "shade")                      # the underside


def _cornice(m, i, bay, z1, z2, proud, soffit_full, front=True):
    """A cornice over bay i: soffit at z1 (between the pilasters, or the whole
    bay), a front face in three, a top face in three whose back edge is the
    tier above's bottom line. Its front lines are mb.corner_pt and
    bay.at(u, z, -proud) -- for proud BAND_PROUD, mb.slab_stations(). front
    False leaves the front OPEN between the two lines (the slab tier: the
    lane part's walkway slab closes onto them)."""
    u0, u1 = PW / 2.0, bay.L - PW / 2.0
    cl1, cr1 = m.v(mb.corner_pt(i, z1, proud)), m.v(mb.corner_pt(i + 1, z1, proud))
    cl2, cr2 = m.v(mb.corner_pt(i, z2, proud)), m.v(mb.corner_pt(i + 1, z2, proud))
    fl1, fr1 = m.v(bay.at(u0, z1, -proud)), m.v(bay.at(u1, z1, -proud))
    fl2, fr2 = m.v(bay.at(u0, z2, -proud)), m.v(bay.at(u1, z2, -proud))
    wl1, wr1 = m.v(bay.at(u0, z1)), m.v(bay.at(u1, z1))
    n_in = bay.n_in
    m.quad(wl1, wr1, fr1, fl1, DOWN, "shade")                           # soffit
    if soffit_full:
        m.quad(m.v(bay.at(0.0, z1)), wl1, fl1, cl1, DOWN, "shade")
        m.quad(wr1, m.v(bay.at(bay.L, z1)), cr1, fr1, DOWN, "shade")
    if front:
        m.quad(cl1, fl1, fl2, cl2, n_in, "band")                        # front, in three
        m.quad(fl1, fr1, fr2, fl2, n_in, "band")
        m.quad(fr1, cr1, cr2, fr2, n_in, "band")
    bl, bm0, bm1, br = (m.v(bay.at(0.0, z2)), m.v(bay.at(u0, z2)),
                        m.v(bay.at(u1, z2)), m.v(bay.at(bay.L, z2)))
    m.quad(cl2, fl2, bm0, bl, UP, "shade")                              # top, in three
    m.quad(fl2, fr2, bm1, bm0, UP, "shade")
    m.quad(fr2, cr2, br, bm1, UP, "shade")


# =============================================================================
# THE DOME
# =============================================================================

def _dome(m, coll=False):
    R = (mb.WALL_R ** 2 + mb.DOME_RISE ** 2) / (2.0 * mb.DOME_RISE)
    zc = mb.DOME_Z0 + mb.DOME_RISE - R
    phi0 = math.asin(mb.WALL_R / R)
    phi_cap = math.asin(mb.DOME_CAP_R / R)

    def want(a, b, c):
        cx, cy, cz = ((a[0] + b[0] + c[0]) / 3.0, (a[1] + b[1] + c[1]) / 3.0, (a[2] + b[2] + c[2]) / 3.0)
        return (-cx, -cy, zc - cz)

    def ring(phi, n):
        angs = [mb.TWO_PI * k / n for k in range(n)]
        return mb._ring(m, R * math.sin(phi), zc + R * math.cos(phi), n, angs), angs

    if coll:
        rings = [ring(phi0 + (phi_cap - phi0) * k / 4, mb.NSIDE) for k in range(5)]
    else:
        stations, z = mb.seam_dome_spring()
        spring = [m.v(p) for p in mb.station_pts(stations, z)]
        rings = [(spring, mb.station_angles(stations))]
        phi1 = phi0 - DOME_FIRST_BAND / R                    # a short first band: fat zipper triangles
        counts = [mb.NSIDE] * (mb.DOME_RINGS - len(DOME_THIN)) + list(DOME_THIN)
        for k, n in enumerate(counts):
            rings.append(ring(phi1 + (phi_cap - phi1) * k / (len(counts) - 1), n))
    for k in range(len(rings) - 1):
        (lo, la), (hi, ha) = rings[k], rings[k + 1]
        if len(lo) != len(hi):
            _zip_ring(m, lo, la, hi, ha, want, COFFER_ZONE)
            continue
        n = len(lo)
        for i in range(n):
            j = (i + 1) % n
            pa, pb = m.verts[lo[i]], m.verts[hi[j]]
            m.quad(lo[i], lo[j], hi[j], hi[i], want(pa, pb, pb), COFFER_ZONE)
    top_ring = rings[-1][0]
    top = m.v((0.0, 0.0, zc + R * math.cos(phi_cap)))
    n = len(top_ring)
    for i in range(n):
        m.tri(top, top_ring[i], top_ring[(i + 1) % n], DOWN, "band")
    return zc + R


# =============================================================================
# THE WALL
# =============================================================================

def build(m):
    """The wall into m. Returns the numbers."""
    _STATS.clear()
    counts = {}
    mark = [len(m.faces)]

    def take(label):
        counts[label] = counts.get(label, 0) + len(m.faces) - mark[0]
        mark[0] = len(m.faces)

    for t, B in enumerate(mb.TIER_BASE):
        s = B + mb.SILL_UP
        band = _tier_band(t)
        z1, z2 = B + band[0], B + band[1]
        for i in range(mb.NSIDE):
            _cell(m, i, t, "marble" if (i + t) % 2 == 0 else "marble2")
        take("tris_cells")
        for i in range(mb.NSIDE):
            bay = _Bay(i)
            # the plinth strips under the pilasters, down to the bottom line
            for (ua, ub) in ((0.0, PW / 2.0), (bay.L - PW / 2.0, bay.L)):
                m.quad(m.v(bay.at(ua, B)), m.v(bay.at(ub, B)), m.v(bay.at(ub, s)),
                       m.v(bay.at(ua, s)), bay.n_in, "plinth")
            side_z = [s + (z1 - s) * k / SIDE_SPLITS for k in range(SIDE_SPLITS + 1)]
            _pilaster_half(m, i, bay, PW / 2.0, side_z, True)
            _pilaster_half(m, i, bay, bay.L - PW / 2.0, side_z, False)
        take("tris_pilasters")
        for i in range(mb.NSIDE):
            _cornice(m, i, _Bay(i), z1, z2, mb.BAND_PROUD, False, front=(t != mb.SLAB_TIER))
        take("tris_cornices")

    # the frieze and the great cornice over the top tier
    f0, f1 = mb.FRIEZE_Z
    for i in range(mb.NSIDE):
        bay = _Bay(i)
        for (ua, ub, zone) in ((0.0, PW / 2.0, "marble"), (PW / 2.0, bay.L - PW / 2.0, "frieze"),
                               (bay.L - PW / 2.0, bay.L, "marble")):
            m.quad(m.v(bay.at(ua, f0)), m.v(bay.at(ub, f0)), m.v(bay.at(ub, f1)),
                   m.v(bay.at(ua, f1)), bay.n_in, zone)
    take("tris_frieze")
    g0, g1 = mb.CORNICE_Z
    for i in range(mb.NSIDE):
        _cornice(m, i, _Bay(i), g0, g1, mb.CORNICE_PROUD, True)
    take("tris_cornices")
    apex = _dome(m)
    take("tris_dome")

    # the bars were built with their cells: count them apart
    counts["tris_bars"] = _STATS.get("tris_bars", 0)
    counts["tris_cells"] -= counts["tris_bars"]
    info = {"cells": _STATS.get("cells", 0), "bars": _STATS.get("bars", 0),
            "tiers": len(mb.TIER_BASE), "dome_apex": round(apex, 2)}
    info.update(counts)
    return info


def collider(c):
    """What a body can touch: the wall face under the walkway (r WALL_R), the
    pilaster line over it (r WALL_R - BAND_PROUD: the cornice fronts and the
    pilasters), the annulus between the two at DECK_Z (the stone is above it:
    it faces down), the like annulus at the dome's spring (stone below), and
    the dome."""
    lo = mb._ring(c, mb.WALL_R, mb.FLOOR_Z)
    deck_out = mb._ring(c, mb.WALL_R, mb.DECK_Z)
    mb._band(c, lo, deck_out, True, "marble")
    deck_in = mb._ring(c, mb.WALL_R - mb.BAND_PROUD, mb.DECK_Z)
    hi_in = mb._ring(c, mb.WALL_R - mb.BAND_PROUD, mb.DOME_Z0)
    mb._band(c, deck_in, hi_in, True, "marble")
    hi_out = mb._ring(c, mb.WALL_R, mb.DOME_Z0)
    n = mb.NSIDE
    for i in range(n):
        j = (i + 1) % n
        c.quad(deck_in[i], deck_in[j], deck_out[j], deck_out[i], DOWN, "marble")
        c.quad(hi_in[i], hi_in[j], hi_out[j], hi_out[i], UP, "marble")
    _dome(c, coll=True)


# =============================================================================
# AUDIT -- the part alone
# =============================================================================

def _min_angle(m, f):
    P = [m.verts[i] for i in f]
    out = 180.0
    for k in range(3):
        a, b, c = P[k], P[(k + 1) % 3], P[(k + 2) % 3]
        u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        lu, lv = math.sqrt(sum(x * x for x in u)), math.sqrt(sum(x * x for x in v))
        if lu < 1e-12 or lv < 1e-12:
            return 0.0
        out = min(out, math.degrees(math.acos(max(-1.0, min(1.0, sum(u[i] * v[i] for i in range(3)) / (lu * lv))))))
    return out


def _signed_area(P):
    return 0.5 * sum(P[k][0] * P[(k + 1) % len(P)][1] - P[(k + 1) % len(P)][0] * P[k][1]
                     for k in range(len(P)))


def _overlap2(A, B, tol=1e-7):
    """Do two 2-D triangles' interiors intersect? Separating-axis test."""
    for T in (A, B):
        for k in range(3):
            p, q = T[k], T[(k + 1) % 3]
            ax, ay = q[1] - p[1], p[0] - q[0]
            pa = [x * ax + y * ay for (x, y) in A]
            pb = [x * ax + y * ay for (x, y) in B]
            if max(pa) <= min(pb) + tol or max(pb) <= min(pa) + tol:
                return False
    return True


def _frame_audit(tier):
    """The frame of a cell on this tier, in the bay's (u, z) plane: no two
    triangles overlap, none is degenerate, and together they are exactly the
    rectangle less the arch (_Mesh._emit turns each the right way, so areas
    are unsigned here). Returns (ok, min angle, n)."""
    cell = _Cell(_Bay(0), tier)
    pts2 = cell.outline + cell.rect
    tris = [[pts2[i] for i in t] for t in cell.frame]
    areas = [abs(_signed_area(T)) for T in tris]
    ok = all(a > 1e-9 for a in areas)
    for a in range(len(tris)):
        for b in range(a + 1, len(tris)):
            if _overlap2(tris[a], tris[b]):
                ok = False
    want = (cell.u1 - cell.u0) * (cell.z1 - cell.s) - abs(_signed_area(cell.outline))
    ok = ok and abs(sum(areas) - want) < 1e-6
    lo = 180.0
    for T in tris:
        m3 = [(p[0], p[1], 0.0) for p in T]
        lo = min(lo, _min_angle(type("M", (), {"verts": m3})(), (0, 1, 2)))
    return ok, lo, len(tris)


def _seam_audit(m):
    """The part's free edges are exactly the three seam rings."""
    directed = {}
    for f in m.faces:
        for k in range(3):
            directed[(f[k], f[(k + 1) % 3])] = 1
    free = set()
    for (a, b) in directed:
        if (b, a) not in directed:
            free.add(a)
            free.add(b)
    have = set((round(m.verts[i][0], 4), round(m.verts[i][1], 4), round(m.verts[i][2], 4)) for i in free)
    st, zf = mb.seam_wall_foot()
    ss, z_soffit, z_top = mb.seam_slab()
    want = set()
    for (x, y, z) in mb.station_pts(st, zf) + mb.station_pts(ss, z_soffit) + mb.station_pts(ss, z_top):
        want.add((round(x, 4), round(y, 4), round(z, 4)))
    return have == want, len(have), len(want)


if __name__ == "__main__":
    m = mb._Mesh()
    info = build(m)
    a = mb.audit(m, "wall")
    loops = mb.boundary_loops(m)
    print("boundary loops: %d  %s" % (len(loops), loops[:4]))
    print("info:", " ".join("%s=%s" % kv for kv in sorted(info.items())))
    angs = sorted(_min_angle(m, f) for f in m.faces)
    print("min triangle angle %.2f deg; under 1 deg: %d, under 3 deg: %d, under 5 deg: %d of %d"
          % (angs[0], sum(1 for x in angs if x < 1.0), sum(1 for x in angs if x < 3.0),
             sum(1 for x in angs if x < 5.0), len(angs)))
    frames_ok = True
    for t in sorted(set([0, mb.SLAB_TIER])):
        fok, flo, fn = _frame_audit(t)
        frames_ok = frames_ok and fok
        print("frame zip tier %d (band %s): %d triangles, %s, min angle %.2f deg"
              % (t, _tier_band(t), fn, "no overlaps, tiles the frame" if fok else "OVERLAP/GAP", flo))
    seams_ok, n_have, n_want = _seam_audit(m)
    print("seams: free vertices %d, seam-ring points %d, %s" % (n_have, n_want, "MATCH" if seams_ok else "MISMATCH"))
    c = mb._Mesh()
    collider(c)
    mb.audit(c, "wall-collider")
    # Alone, the part is TWO pieces: the wall under the slab tier's open
    # cornice front and the wall over it. The lane part's walkway slab, closing
    # onto the soffit and top lines, joins them (marble_build --check: 1).
    ok = (a["components"] == 2 and a["boundary_edges"] == 3 * 192 and a["doubled_edges"] == 0
          and a["over_edges"] == 0 and a["degenerate"] == 0 and a["duplicate_positions"] == 0
          and len(loops) == 3 and all(n == 192 for (n, _r, _z) in loops) and frames_ok and seams_ok)
    print("WALL PART %s (two pieces alone: the slab tier's cornice front is the lane part's slab)"
          % ("OK" if ok else "NOT OK"))
    sys.exit(0 if ok else 1)
