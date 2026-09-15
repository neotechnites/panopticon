"""
marble_wall -- the wall of Map 2 (marble), from the trough's outer ring up
to the crown of the dome. A part of marble_build.py, built into its welded
_Mesh against the seam contract there.

    socle        plain ashlar from the wall foot (seam_wall_foot) to the sill line
    3 tiers      64 arched cells each, Map 1's cell size (4.0 x 5.5 m mouths);
                 tier 1 a short reveal to a slotted stone SCREEN (the cell-bars
                 language of Map 1), tiers 2-3 an open recess to a dark back wall
    pilasters    on every pier, sill line to cornice, running up INTO the cornice
    cornices     one per tier; the frieze (Greek key) and the great cornice over
                 the top tier, whose back edge is the dome's spring ring
    dome         a coffered spherical cap off the 192-station spring ring, 64
                 facets round, thinning to 32 then 16 toward the medallion

Every point on the wall face is _Bay.at(u, z, d), so shared points weld; the
only free edges this part leaves are the 192 of the foot ring. No T-junction:
the frame round each arch is zippered straight onto the four corners of its
bay rectangle, so the rectangle's edges carry no stray vertices and the
pilaster returns, soffits and cornice faces are plain quads.

    python3 tools/modelling/marble_wall_build.py      # build alone, audit
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import marble_build as mb  # noqa: E402

# =============================================================================
# TUNABLES (the wall's own; the shared ones are mb.*)
# =============================================================================

PW = mb.PILASTER_W
PP = mb.PILASTER_PROUD
HW = mb.ARCH_W / 2.0
LANE_MERGE = 0.10           # a screen-lane ray this close to a head segment takes its place
SLOT_TOP_UNDER = mb.SLOT_UP + 0.4   # the slots' flat top this far under the crown
DOME_FIRST_BAND = 1.5       # metres up the sphere the 192 -> 64 zipper band takes
DOME_THIN = (32, 16)        # station counts of the last two rings, toward the pole
SIDE_SPLITS = 3             # the frame's side margins, pilaster fronts and returns in this many stacked quads
SIDE_SWITCH = 0.5           # head angle where the frame's fan moves from the middle side point to the top corner
COFFER_ZONE = "coffer"
UP, DOWN = mb.UP, mb.DOWN
TWO_PI = mb.TWO_PI

_STATS = {}


# =============================================================================
# HELPERS
# =============================================================================

class _Bay(mb._Bay):
    """mb._Bay with the normal of the LAST bay fixed: its corner angles are
    6.19 and 0.0, whose plain average points the wrong way. (mb._Bay.at with
    d = 0 is unaffected, so the seam stations still weld.)"""

    def __init__(self, i, rad=mb.WALL_R):
        mb._Bay.__init__(self, i, rad)
        am = mb.ANG[i % mb.NSIDE] + math.pi / mb.NSIDE
        self.n_in = (-math.cos(am), -math.sin(am), 0.0)
        self.n_out = (math.cos(am), math.sin(am), 0.0)


def _corner_pt(i, z, proud):
    """The pilaster/cornice corner: the radial point r WALL_R - proud on bay
    corner i's own bearing, so both bays meeting there use one vertex."""
    a = mb.ANG[i % mb.NSIDE]
    r = mb.WALL_R - proud
    return (r * math.cos(a), r * math.sin(a), z)


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


def _acos(x):
    return math.acos(max(-1.0, min(1.0, x)))


def _merge_angles(base, extra, tol):
    """base angles with extra ones added; an extra within tol of a base angle
    replaces it (so the lane boundary exists exactly, and no sliver is made)."""
    out = list(base)
    for e in extra:
        near = [k for k, b in enumerate(out) if abs(b - e) < tol]
        if near:
            out[near[0]] = e
        else:
            out.append(e)
    out.sort()
    return out


# =============================================================================
# ONE CELL: frame, reveal, and a screen or a back wall
# =============================================================================

class _Cell(object):
    """The arch of one bay on one tier, in the bay's (u, z) plane.

    outline: the closed loop, sill left to right, up the right jamb, over the
    head (right to left), down the left jamb -- as (u, z). chain_a: the angle
    of each outline point round the springing centre, monotonic from the
    right sill corner (negative) to the left sill corner (past pi)."""

    def __init__(self, bay, tier, screen):
        self.bay = bay
        B = mb.TIER_BASE[tier]
        self.B = B
        self.s = B + mb.SILL_UP
        self.sp = self.s + mb.ARCH_JAMB
        self.crown = self.sp + HW
        self.z1 = B + mb.BAND_Z[0]
        self.u0, self.u1 = PW / 2.0, bay.L - PW / 2.0
        self.c = bay.L / 2.0
        self.screen = screen
        c, s, sp = self.c, self.s, self.sp
        head = [math.pi * k / mb.HEAD_SEG for k in range(mb.HEAD_SEG + 1)]
        self.lanes = []                                       # (u_a, u_b, is_slot)
        self.z_bot = self.z_top = None
        sill_in = []
        jamb = []                                             # jamb heights, above the sill
        if screen:
            self.z_bot = s + mb.SLOT_UP
            self.z_top = self.crown - SLOT_TOP_UNDER
            stone = (mb.ARCH_W - mb.SLOT_N * mb.SLOT_W) / (mb.SLOT_N + 1)
            u = c - HW
            bounds = [u]
            for k in range(mb.SLOT_N):
                u += stone
                bounds.append(u)
                u += mb.SLOT_W
                bounds.append(u)
            bounds.append(c + HW)
            for k in range(len(bounds) - 1):
                self.lanes.append((bounds[k], bounds[k + 1], k % 2 == 1))
            sill_in = bounds[1:-1]
            # the lane boundaries take the place of any head segment within
            # LANE_MERGE, and so do the two points where the head crosses the
            # slots' top line (the end lanes are split there)
            self.t_ztop = math.asin((self.z_top - sp) / HW)
            head = _merge_angles(head, [_acos((u - c) / HW) for u in sill_in]
                                 + [self.t_ztop, math.pi - self.t_ztop], LANE_MERGE)
            jamb = [self.z_bot]
        self.head = head
        self.sill_us = sorted(set([c - HW, c + HW] + sill_in))
        # the side margins are split in SIDE_SPLITS: the rect's side points,
        # and the jamb points at the same heights (those under the springing)
        self.side_z = [s + (self.z1 - s) * k / SIDE_SPLITS for k in range(SIDE_SPLITS + 1)]
        jamb = sorted(set(jamb + [z for z in self.side_z[1:-1] if z < sp - 1e-6]))
        # the outline: sill, right jamb up, head right to left, left jamb down
        pts = [(u, s) for u in self.sill_us]
        pts += [(c + HW, z) for z in jamb] + [(c + HW, sp)]
        pts += [(c + HW * math.cos(t), sp + HW * math.sin(t)) for t in head[1:-1]]
        pts += [(c - HW, sp)] + [(c - HW, z) for z in reversed(jamb)]
        self.outline = pts
        # the chain the frame zips onto its rectangle: from the right sill
        # corner round to the left one, by angle about the springing centre
        n_sill = len(self.sill_us)
        self.chain = list(range(n_sill - 1, len(pts))) + [0]
        self.chain_a = []
        for k in self.chain:
            u, z = pts[k]
            a = math.atan2(z - sp, u - c)
            if u < c - 1e-9 and z < sp - 1e-9:
                a += TWO_PI                                   # the left jamb: past pi
            self.chain_a.append(a)
        z1 = self.z1
        # the four corners the chain zips onto, and the chain angle at which
        # the zipper moves on to the next corner. NOT the corners' own ray
        # angles: a corner's fan over the convex head is only sound up to its
        # tangent point (1.9 rad from the upper-right corner, 1.2 from the
        # upper-left), so the hand-over happens at the springing, the crown
        # and the far springing, where both corners see the arc.
        right = [(self.u1, z) for z in self.side_z]                  # ascending
        left = [(self.u0, z) for z in reversed(self.side_z)]
        self.rect = right + left
        # hand-over angles up the right side: the lowest side points take over
        # at their own ray angle (they see the whole jamb), the ones beside the
        # head at the springing, SIDE_SWITCH and the crown; mirrored on the left
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
                          min(SIDE_SWITCH, 0.0 + (SIDE_SWITCH - 0.0) * (k - 1) / max(1, n_side - 2)))
        down = [math.pi / 2.0] + [math.pi - a for a in reversed(up[1:])]
        self.rect_a = up + down

    def head_z(self, u):
        return self.sp + math.sqrt(max(0.0, HW * HW - (u - self.c) ** 2))


def _plinth(m, bl, br, top, want, zone):
    """[bl, br] against a top chain of many points: one big triangle to a
    middle top point, then a fan from each bottom corner over its half."""
    j = len(top) // 2
    m.tri(bl, br, top[j], want, zone)
    for k in range(0, j):
        m.tri(bl, top[k], top[k + 1], want, zone)
    for k in range(j, len(top) - 1):
        m.tri(br, top[k], top[k + 1], want, zone)


def _cell(m, i, tier, zone_face):
    """One cell of bay i on tier `tier`."""
    bay = _Bay(i)
    cell = _Cell(bay, tier, screen=(tier == 0))
    c, s, sp = cell.c, cell.s, cell.sp
    depth = mb.SCREEN_D if cell.screen else mb.CELL_D
    n_in = bay.n_in

    loop0 = [m.v(bay.at(u, z)) for (u, z) in cell.outline]
    rect = [m.v(bay.at(u, z)) for (u, z) in cell.rect]
    # the frame: the outline zipped onto the rectangle's four corners
    _zip_open(m, [loop0[k] for k in cell.chain], cell.chain_a, rect, cell.rect_a, n_in, zone_face)

    # the plinth under the sill: bottom corners only (the seam / the cornice
    # top has nothing between them), the sill line's points along the top
    bl, br = m.v(bay.at(cell.u0, cell.B)), m.v(bay.at(cell.u1, cell.B))
    ns = len(cell.sill_us)
    _plinth(m, bl, br, [rect[-1]] + loop0[:ns] + [rect[0]], n_in, "plinth")

    # the reveal: every outline segment, `depth` into the wall
    loopd = [m.v(bay.at(u, z, depth)) for (u, z) in cell.outline]
    nl = len(cell.outline)
    for k in range(nl):
        j = (k + 1) % nl
        mu = 0.5 * (cell.outline[k][0] + cell.outline[j][0])
        mz = 0.5 * (cell.outline[k][1] + cell.outline[j][1])
        w = bay.dir(c - mu, sp - mz)
        if abs(w[0]) + abs(w[1]) + abs(w[2]) < 1e-9:
            w = UP
        m.quad(loop0[k], loop0[j], loopd[j], loopd[k], w, "shade")

    if not cell.screen:
        _convex(m, loopd, n_in, "cellin")
    else:
        _screen(m, cell, loopd, depth)
        _STATS["screens"] = _STATS.get("screens", 0) + 1
    _STATS["cells"] = _STATS.get("cells", 0) + 1


def _screen(m, cell, loopd, depth):
    """The slotted stone screen at the reveal's end, lane by lane: a quad up
    to the slots' foot, a quad up to their top, a polygon up to the arc; the
    slot lanes leave the middle open into a tunnel to a dark plate."""
    bay, c, s, sp = cell.bay, cell.c, cell.s, cell.sp
    n_in = bay.n_in
    out = cell.outline
    at = dict((tuple(round(x, 6) for x in p), loopd[k]) for k, p in enumerate(out))
    z_bot, z_top = cell.z_bot, cell.z_top
    lanes = cell.lanes
    made = {}

    def sv(u, z):
        key = (round(u, 6), round(z, 6))
        if key in at:
            return at[key]
        if key not in made:
            made[key] = m.v(bay.at(u, z, depth))
        return made[key]

    def arc_between(ua, ub):
        """Outline points from ub's side round to ua's, ascending angle: the
        lane's own boundary points on the head inclusive; at a jamb, every
        point above the slots' foot (the foot point itself is the ring's start)."""
        if abs(ub - (c + HW)) < 1e-9:
            ta = math.atan2(z_bot - sp, HW) + 1e-9            # just past (c + HW, z_bot)
        else:
            ta = _acos((ub - c) / HW) - 1e-9
        if abs(ua - (c - HW)) < 1e-9:
            tb = math.atan2(z_bot - sp, -HW) + TWO_PI - 1e-9   # just short of (c - HW, z_bot)
        else:
            tb = _acos((ua - c) / HW) + 1e-9
        return [loopd[k] for k, a in zip(cell.chain, cell.chain_a) if ta <= a <= tb]

    for k, (ua, ub, slot) in enumerate(lanes):
        edge_l = abs(ua - (c - HW)) < 1e-9
        edge_r = abs(ub - (c + HW)) < 1e-9
        # the foot: sill to the slots' foot, a quad
        m.quad(sv(ua, s), sv(ub, s), sv(ub, z_bot), sv(ua, z_bot), n_in, "marble2")
        if slot:
            tl, tr = sv(ua, z_top), sv(ub, z_top)
            _convex(m, [tl, tr] + arc_between(ua, ub), n_in, "marble2")
            bl, br = sv(ua, z_bot), sv(ub, z_bot)
            d2 = depth + mb.SLOT_D
            bl2, br2 = m.v(bay.at(ua, z_bot, d2)), m.v(bay.at(ub, z_bot, d2))
            tr2, tl2 = m.v(bay.at(ub, z_top, d2)), m.v(bay.at(ua, z_top, d2))
            m.quad(bl, br, br2, bl2, UP, "shade")
            m.quad(tl, tr, tr2, tl2, DOWN, "shade")
            m.quad(bl, tl, tl2, bl2, bay.dir(1.0, 0.0), "shade")
            m.quad(br, tr, tr2, br2, bay.dir(-1.0, 0.0), "shade")
            m.quad(bl2, br2, tr2, tl2, n_in, "cellin")
            _STATS["slots"] = _STATS.get("slots", 0) + 1
            continue
        if edge_l or edge_r:
            # an end lane: from the slots' foot up, bounded by the jamb and
            # the arc on its outer side, by the neighbouring slot's side
            # inboard; split at the slots' top line, where the head has a
            # point (t_ztop), so no triangle spans the whole height
            pts = arc_between(ua, ub)
            t_split = cell.t_ztop if edge_r else math.pi - cell.t_ztop
            angs = [a for a in cell.chain_a]
            ids_a = dict(zip([loopd[k] for k in cell.chain], angs))
            low = [v for v in pts if ids_a[v] <= t_split + 1e-9] if edge_r else \
                  [v for v in pts if ids_a[v] >= t_split - 1e-9]
            high = [v for v in pts if ids_a[v] >= t_split - 1e-9] if edge_r else \
                   [v for v in pts if ids_a[v] <= t_split + 1e-9]
            if edge_r:
                _convex(m, [sv(ua, z_bot), sv(ub, z_bot)] + low + [sv(ua, z_top)], n_in, "marble2")
                _convex(m, [sv(ua, z_top)] + high, n_in, "marble2")
            else:
                _convex(m, [sv(ua, z_bot), sv(ub, z_bot), sv(ub, z_top)] + low, n_in, "marble2")
                _convex(m, [sv(ub, z_top)] + high, n_in, "marble2")
            continue
        m.quad(sv(ua, z_bot), sv(ub, z_bot), sv(ub, z_top), sv(ua, z_top), n_in, "marble2")
        _convex(m, [sv(ua, z_top), sv(ub, z_top)] + arc_between(ua, ub), n_in, "marble2")


# =============================================================================
# PILASTERS AND CORNICES
# =============================================================================

def _pilaster_half(m, i, bay, u_edge, side_z, left):
    """One half of a pilaster, in bay i: the half from the bay corner (u 0 or
    L) to the pilaster edge u_edge, in stacked quads at the frame's side
    heights. left: this is the bay's left corner."""
    corner = i if left else i + 1
    s = side_z[0]
    cs = [m.v(_corner_pt(corner, z, PP)) for z in side_z]
    fs = [m.v(bay.at(u_edge, z, -PP)) for z in side_z]
    es = [m.v(bay.at(u_edge, z)) for z in side_z]
    for k in range(len(side_z) - 1):
        m.quad(cs[k], fs[k], fs[k + 1], cs[k + 1], bay.n_in, "column")               # the fluted front
        m.quad(fs[k], es[k], es[k + 1], fs[k + 1], bay.dir(1.0 if left else -1.0, 0.0), "marble")   # the return
    ws = m.v(bay.at(0.0 if left else bay.L, s))
    m.quad(ws, es[0], fs[0], cs[0], DOWN, "shade")                      # the underside


def _cornice(m, i, bay, z1, z2, proud, soffit_full):
    """A cornice over bay i: soffit at z1 (between the pilasters, or the whole
    bay), a front face in three, a top face in three whose back edge is the
    tier above's bottom line."""
    u0, u1 = PW / 2.0, bay.L - PW / 2.0
    cl1, cr1 = m.v(_corner_pt(i, z1, proud)), m.v(_corner_pt(i + 1, z1, proud))
    cl2, cr2 = m.v(_corner_pt(i, z2, proud)), m.v(_corner_pt(i + 1, z2, proud))
    fl1, fr1 = m.v(bay.at(u0, z1, -proud)), m.v(bay.at(u1, z1, -proud))
    fl2, fr2 = m.v(bay.at(u0, z2, -proud)), m.v(bay.at(u1, z2, -proud))
    wl1, wr1 = m.v(bay.at(u0, z1)), m.v(bay.at(u1, z1))
    n_in = bay.n_in
    m.quad(wl1, wr1, fr1, fl1, DOWN, "shade")                           # soffit
    if soffit_full:
        m.quad(m.v(bay.at(0.0, z1)), wl1, fl1, cl1, DOWN, "shade")
        m.quad(wr1, m.v(bay.at(bay.L, z1)), cr1, fr1, DOWN, "shade")
    m.quad(cl1, fl1, fl2, cl2, n_in, "band")                            # front, in three
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
        z1, z2 = B + mb.BAND_Z[0], B + mb.BAND_Z[1]
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
            _cornice(m, i, _Bay(i), z1, z2, mb.BAND_PROUD, False)
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

    info = {"cells": _STATS.get("cells", 0), "screens": _STATS.get("screens", 0),
            "slots": _STATS.get("slots", 0), "tiers": len(mb.TIER_BASE),
            "bar_boundary_edges": 0, "dome_apex": round(apex, 2)}
    info.update(counts)
    return info


def collider(c):
    """The plain wall face and the dome: what a body can touch."""
    lo = mb._ring(c, mb.WALL_R, mb.FIELD_Z)
    hi = mb._ring(c, mb.WALL_R, mb.DOME_Z0)
    mb._band(c, lo, hi, True, "marble")
    _dome(c, coll=True)


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


if __name__ == "__main__":
    m = mb._Mesh()
    info = build(m)
    a = mb.audit(m, "wall")
    print("boundary loops:", mb.boundary_loops(m)[:3])
    print("info:", info)
    angs = sorted(_min_angle(m, f) for f in m.faces)
    print("min triangle angle %.2f deg; under 3 deg: %d, under 5 deg: %d of %d"
          % (angs[0], sum(1 for x in angs if x < 3.0), sum(1 for x in angs if x < 5.0), len(angs)))
    c = mb._Mesh()
    collider(c)
    mb.audit(c, "wall-collider")
    ok = (a["components"] == 1 and a["boundary_edges"] == 192 and a["doubled_edges"] == 0
          and a["over_edges"] == 0 and a["degenerate"] == 0 and a["duplicate_positions"] == 0)
    print("WALL PART %s" % ("OK" if ok else "NOT OK"))
    sys.exit(0 if ok else 1)
