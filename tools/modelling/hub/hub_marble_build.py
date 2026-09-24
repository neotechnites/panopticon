"""
PANOPTICON -- hub_marble: wedge 2 of the hub ring (bearings 36..72), dressed
as the marble rotunda (Map 2). Not a model of its own: hub_base_build imports
THEME and builds it into the one hub rock. See _Theme in hub_base_build.py.

The wedge: pale paving (mb "floor", a 3x3 slab cell per quad), the dais in
"plinth", and its slice of the outer wall raised to 8 m and thickened 2.5 m.
The wall, floor to top:

    end piers    the wedge's first and last column intervals: flat, full
                 height, at r 50, "column" -- so the seam edges stay single
    socle        r 50, z 0..0.55, "plinth"; a ledge back to the wall line
    wall line    set back 0.4 m (r 50.4): piers on the stock column polygon,
                 two BAYS as flat chords over five intervals each, jambs on
                 the columns one in from the bay ends (three intervals apart)
    cells        sill 1.0 m over a plinth band, jamb 2.8, semicircular head
                 of HEAD_SEG segments, recess 2.5 m to a dark "cellin" back,
                 "shade" reveals; the frame is rays from the springing centre
                 to the bay box, as mb._arch_frame. Five square "iron" bars
                 0.13 m WELDED into the sill: the sill is split into a
                 rectangle per bar, each zippered to its bar's foot
    frieze       6.5..7.15 on the wall line, one Greek-key quad per interval
    cornice      proud again at r 50: "shade" soffit, "band" front to 8 m
    top, outer   the stock quads (top_in / top_out / bot_out): closed

    python3 tools/modelling/hub/hub_base_build.py --check
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import hub_base_build as hb  # noqa: E402
import marble_build as mb  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

WALL_TOP = 8.0
WALL_THICK = 2.5            # over the stock WALL_T
SETBACK = 0.4               # the wall line behind the socle and the cornice
SOCLE_Z = 0.55
SILL = 1.0                  # over the floor; the plinth band runs SOCLE_Z..SILL
JAMB = 2.8                  # sill to springing
HEAD_SEG = mb.HEAD_SEG
DEPTH = 2.5                 # the recess
BAR_N = mb.BAR_N
BHW = mb.BAR_HW
BAR_D = mb.BAR_D            # bars stand this far into the reveal
BAR_TIP = 0.1               # ... tips this far into the head
FRIEZE_Z = (6.5, 7.15)
CORNICE_Z0 = FRIEZE_Z[1]
BAYS = ((3, 8), (11, 16))   # bay end columns, offsets from the wedge's first claimed column

UP, DOWN, TWO_PI = hb.UP, hb.DOWN, hb.TWO_PI
EPS = 1e-9


def Z(name):
    assert name in mb.ZONES, name
    return ("marble", name)


# =============================================================================
# ONE BAY: a flat chord panel with an arched, barred cell
# =============================================================================

class _Bay(object):
    """The flat panel between two wall-line points. Local (u, z, d): u along
    the chord, z up, d into the wall."""

    def __init__(self, m, v0, v1, am):
        x0, y0, _ = m.verts[v0]
        x1, y1, _ = m.verts[v1]
        self.p0 = (x0, y0)
        dx, dy = x1 - x0, y1 - y0
        self.L = math.hypot(dx, dy)
        self.u = (dx / self.L, dy / self.L)
        self.n_out = (math.cos(am), math.sin(am), 0.0)
        self.n_in = (-math.cos(am), -math.sin(am), 0.0)

    def at(self, u, z, d=0.0):
        return (self.p0[0] + self.u[0] * u + self.n_out[0] * d,
                self.p0[1] + self.u[1] * u + self.n_out[1] * d, z)

    def dir(self, du, dz):
        return (self.u[0] * du, self.u[1] * du, dz)

    def u_of(self, m, v):
        x, y, _ = m.verts[v]
        return (x - self.p0[0]) * self.u[0] + (y - self.p0[1]) * self.u[1]


def _ccw(m, loop):
    """The loop in world-xy counter-clockwise order (what hb._zipper walks)."""
    area = 0.0
    for k in range(len(loop)):
        x0, y0, _ = m.verts[loop[k]]
        x1, y1, _ = m.verts[loop[(k + 1) % len(loop)]]
        area += x0 * y1 - x1 * y0
    return loop if area > 0.0 else list(reversed(loop))


def _poly(m, ring, want, zone):
    """A planar polygon as a fan from ring[0] (which must be off every
    collinear run), one UV group, every triangle's winding checked."""
    g0 = len(m.faces)
    for i in range(1, len(ring) - 1):
        m.tri(ring[0], ring[i], ring[i + 1], want, zone)
    for i in range(g0, len(m.faces)):
        m.groups[i] = g0


class _Cell(object):
    """The arch in the bay's (u, z) plane: springing centre (c, sp), half
    width hw, a HEAD_SEG polygon head, jambs down to the sill at s."""

    def __init__(self, c, hw, s):
        self.c, self.hw, self.s, self.sp = c, hw, s, s + JAMB
        self.head = [(c + hw * math.cos(math.pi * i / HEAD_SEG), self.sp + hw * math.sin(math.pi * i / HEAD_SEG))
                     for i in range(HEAD_SEG + 1)]
        self.bar_u = [c - hw + (k + 1) * 2.0 * hw / (BAR_N + 1) for k in range(BAR_N)]
        self.splits = [0.5 * (self.bar_u[k] + self.bar_u[k + 1]) for k in range(BAR_N - 1)]

    def theta(self, u, z):
        return math.atan2(z - self.sp, u - self.c) % TWO_PI

    def inner(self, th):
        """The outline at angle th: the head POLYGON for 0..pi, else the jamb/sill box."""
        c, sp, hw = self.c, self.sp, self.hw
        if th <= math.pi + EPS:
            step = math.pi / HEAD_SEG
            i = min(HEAD_SEG - 1, int(th / step))
            for k in (i, i + 1):
                if abs(th - k * step) < 1e-9:
                    return self.head[k]
            (ax, az), (bx, bz) = self.head[i], self.head[i + 1]
            dx, dz = math.cos(th), math.sin(th)
            ex, ez = bx - ax, bz - az
            det = dz * ex - dx * ez
            t = ((az - sp) * ex - (ax - c) * ez) / det
            return (c + t * dx, sp + t * dz)
        return mb._ray_box(c, sp, th, c - hw, c + hw, self.s, sp)

    def head_z(self, u):
        for i in range(HEAD_SEG):
            (ax, az), (bx, bz) = self.head[i], self.head[i + 1]
            if bx - EPS <= u <= ax + EPS:
                f = (u - ax) / (bx - ax)
                return az + f * (bz - az)
        raise ValueError("u off the head")


def _bay(m, b0, b1, ang, W0, WP, WF0, face):
    """The bay over columns b0..b1: box [0,L] x [SOCLE_Z, FRIEZE_Z[0]] on the
    chord, the cell cut in it, reveals, the barred sill, the back wall."""
    am = 0.5 * (ang(b0) + ang(b1))
    bay = _Bay(m, W0[b0], W0[b1], am)
    L = bay.L
    uk = dict((k, bay.u_of(m, W0[k])) for k in range(b0 + 1, b1))
    uL, uR = uk[b0 + 1], uk[b1 - 1]
    cell = _Cell(0.5 * (uL + uR), 0.5 * (uR - uL), SILL)
    c, hw, s, sp = cell.c, cell.hw, cell.s, cell.sp
    z0, z1 = SOCLE_Z, FRIEZE_Z[0]
    assert sp + hw < z1 - 0.1 and s > z0 + 0.1 and c - hw > 0.5 and c + hw < L - 0.5, "cell does not fit its bay"

    # the box perimeter's shared vertices: corners, the wall line's column
    # points top and bottom, the plinth line's side points
    known = {}
    pts = [(0.0, z0, W0[b0]), (L, z0, W0[b1]), (0.0, z1, WF0[b0]), (L, z1, WF0[b1]),
           (0.0, SILL, WP[b0]), (L, SILL, WP[b1])]
    pts += [(uk[k], z0, W0[k]) for k in uk] + [(uk[k], z1, WF0[k]) for k in uk]
    for (u, z, v) in pts:
        known[cell.theta(u, z)] = (v, (u, z))
    ths = set(known)
    ths |= set(math.pi * i / HEAD_SEG for i in range(HEAD_SEG + 1))
    ths |= set(cell.theta(u, s) for u in [c - hw, c + hw] + cell.splits)
    ths = sorted(ths)
    assert all(ths[k + 1] - ths[k] > 1e-4 for k in range(len(ths) - 1)), "two rays coincide"
    N = len(ths)

    pin, pout, vin, vout, vdeep = [], [], [], [], []
    ext = {"bottom": [], "top": [], "left": [], "right": []}   # the frame's new box-edge points
    for th in ths:
        p = cell.inner(th)
        pin.append(p)
        vin.append(m.v(bay.at(p[0], p[1])))
        vdeep.append(m.v(bay.at(p[0], p[1], DEPTH)))
        if th in known:
            v, q = known[th]
        else:
            q = mb._ray_box(c, sp, th, 0.0, L, z0, z1)
            v = m.v(bay.at(q[0], q[1]))
            if abs(q[1] - z0) < 1e-7:
                ext["bottom"].append((q[0], v))
            elif abs(q[1] - z1) < 1e-7:
                ext["top"].append((q[0], v))
            elif abs(q[0]) < 1e-7:
                ext["left"].append((q[1], v))
            elif abs(q[0] - L) < 1e-7:
                ext["right"].append((q[1], v))
            else:
                raise AssertionError("ray exit off the box")
        vout.append(v)
        pout.append(q)
    for key in ext:
        ext[key].sort()

    # the frame: rays from the springing centre, outline to box
    for k in range(N):
        j = (k + 1) % N
        zo = 0.5 * (pout[k][1] + pout[j][1])
        m.quad(vin[k], vin[j], vout[j], vout[k], bay.n_in, Z("plinth" if zo < SILL + EPS else face))

    # the reveal: every outline segment but the sill's
    on_sill = [abs(p[1] - s) < 1e-9 for p in pin]
    for k in range(N):
        j = (k + 1) % N
        if on_sill[k] and on_sill[j]:
            continue
        mu = 0.5 * (pin[k][0] + pin[j][0])
        mz = 0.5 * (pin[k][1] + pin[j][1])
        w = bay.dir(c - mu, sp - mz)
        m.quad(vin[k], vin[j], vdeep[j], vdeep[k], w, Z("shade"))

    # the sill, a rectangle per bar, each zippered onto its bar's foot
    sill_k = [k for k in range(N) if on_sill[k]]          # contiguous, u ascending
    bounds = [sill_k[0]]
    for u in cell.splits:
        th = cell.theta(u, s)
        bounds.append(min(sill_k, key=lambda k: abs(ths[k] - th)))
    bounds.append(sill_k[-1])
    feet = []
    for r in range(BAR_N):
        u = cell.bar_u[r]
        fl = m.v(bay.at(u - BHW, s, BAR_D - BHW))
        fr = m.v(bay.at(u + BHW, s, BAR_D - BHW))
        br = m.v(bay.at(u + BHW, s, BAR_D + BHW))
        bl = m.v(bay.at(u - BHW, s, BAR_D + BHW))
        feet.append((fl, fr, br, bl))
        idx = list(range(bounds[r], bounds[r + 1] + 1))
        loop = [vin[k] for k in idx] + [vdeep[k] for k in reversed(idx)]
        cx, cy, _ = bay.at(u, s, BAR_D)
        hb._zipper(m, _ccw(m, loop), _ccw(m, [fl, fr, br, bl]), cx, cy, UP, Z("shade"))

    # the bars: square pyramids off their feet, tips in the head
    for r in range(BAR_N):
        u = cell.bar_u[r]
        fl, fr, br, bl = feet[r]
        apex = m.v(bay.at(u, cell.head_z(u) + BAR_TIP, BAR_D))
        m.tri(fl, fr, apex, bay.n_in, Z("iron"))
        m.tri(br, bl, apex, bay.n_out, Z("iron"))
        m.tri(bl, fl, apex, bay.dir(-1.0, 0.0), Z("iron"))
        m.tri(fr, br, apex, bay.dir(1.0, 0.0), Z("iron"))

    # the dark back wall: a fan from its own centre (the outline carries
    # collinear runs, so no outline vertex can be the apex)
    ctr = m.v(bay.at(c, sp, DEPTH))
    for k in range(N):
        m.tri(ctr, vdeep[k], vdeep[(k + 1) % N], bay.n_in, Z("cellin"))
    ucol = dict(uk)
    ucol[b0], ucol[b1] = 0.0, L
    return (math.degrees(am), 2.0 * hw, sp + hw - s), ucol, ext


# =============================================================================
# THE WALL
# =============================================================================

def _wall(m, J, foot, top_in, top_out, bot_out, cols):
    n = len(cols)
    assert len(J) == hb.N_INT and all(J[k + 1] == J[k] + 1 for k in range(len(J) - 1))
    j0 = J[0]
    assert j0 + hb.N_INT < n, "the run must not wrap"

    def ang(c):
        return cols[c][0]

    def at_col(c, r, z):
        a = ang(c)
        return (r * math.cos(a), r * math.sin(a), z)

    def n_in(j):
        am = 0.5 * (ang(j) + ang(j + 1))
        return (-math.cos(am), -math.sin(am), 0.0)

    # the stock top and outer face over every interval: the wall stays closed
    for j in J:
        jn = j + 1
        w = n_in(j)
        m.quad(top_in[j], top_in[jn], top_out[jn], top_out[j], UP, Z("marble"))
        m.quad(top_out[j], top_out[jn], bot_out[jn], bot_out[j], (-w[0], -w[1], 0.0), Z("shade"))

    cA, cB = j0 + 1, j0 + hb.N_INT - 1          # the set-back run's end columns
    RF = hb.R_OUT + SETBACK
    bays = [(j0 + b0, j0 + b1) for (b0, b1) in BAYS]

    def wall_xy(c):
        """The wall line at column c: the polygon point, or the bay chord's."""
        for (b0, b1) in bays:
            if b0 < c < b1:
                p0, p1 = at_col(b0, RF, 0.0), at_col(b1, RF, 0.0)
                a = ang(c)
                dx, dy = p1[0] - p0[0], p1[1] - p0[1]
                t = -(p0[0] * math.sin(a) - p0[1] * math.cos(a)) / (dx * math.sin(a) - dy * math.cos(a))
                return (p0[0] + t * dx, p0[1] + t * dy)
        p = at_col(c, RF, 0.0)
        return (p[0], p[1])

    S, C0, W0, WP, WF0, WF1 = {}, {}, {}, {}, {}, {}
    for c in range(cA, cB + 1):
        S[c] = m.v(at_col(c, hb.R_OUT, SOCLE_Z))
        C0[c] = m.v(at_col(c, hb.R_OUT, CORNICE_Z0))
        x, y = wall_xy(c)
        W0[c] = m.v((x, y, SOCLE_Z))
        WP[c] = m.v((x, y, SILL))
        WF0[c] = m.v((x, y, FRIEZE_Z[0]))
        WF1[c] = m.v((x, y, FRIEZE_Z[1]))

    # the end piers: flat at r 50, full height; the seam edge stays one edge
    _poly(m, [foot[j0], foot[cA], S[cA], C0[cA], top_in[cA], top_in[j0]], n_in(j0), Z("column"))
    _poly(m, [foot[cB + 1], top_in[cB + 1], top_in[cB], C0[cB], S[cB], foot[cB]], n_in(cB), Z("column"))
    # ... and their returns into the set-back
    for c, sgn in ((cA, 1.0), (cB, -1.0)):
        a = ang(c)
        w = (-sgn * math.sin(a), sgn * math.cos(a), 0.0)
        _poly(m, [S[c], W0[c], WP[c], C0[c]], w, Z("marble"))     # in two: no sliver up to the top
        _poly(m, [WF0[c], WF1[c], C0[c], WP[c]], w, Z("marble"))

    # the bays first: their frames put points on the box edges the ledge,
    # frieze and neighbouring piers must share
    arches, info = [], {}
    for bi, (b0, b1) in enumerate(bays):
        arch, ucol, ext = _bay(m, b0, b1, ang, W0, WP, WF0, "marble" if bi == 0 else "marble2")
        arches.append(arch)
        info[b0] = (b1, ucol, ext)

    def bay_of(k):
        for b0 in info:
            if b0 <= k < info[b0][0]:
                return (b0,) + info[b0]
        return None

    def side(c, key):
        """The bay edge points on column c: 'left' of the bay starting there,
        'right' of the one ending there. (z, v) ascending."""
        for b0, (b1, _u, ext) in info.items():
            if (key == "left" and b0 == c) or (key == "right" and b1 == c):
                return ext[key]
        return []

    for k in range(cA, cB):
        kn = k + 1
        w = n_in(k)
        m.quad(foot[k], foot[kn], S[kn], S[k], w, Z("plinth"))               # socle
        bay = bay_of(k)
        if bay:
            _b0, _b1, ucol, ext = bay
            bot = [v for (u, v) in ext["bottom"] if ucol[k] < u < ucol[kn]]
            top = [v for (u, v) in ext["top"] if ucol[k] < u < ucol[kn]]
            _poly(m, [S[k], S[kn], W0[kn]] + bot[::-1] + [W0[k]], UP, Z("shade"))          # ledge
            _poly(m, [WF1[k], WF0[k]] + top + [WF0[kn], WF1[kn]], w, Z("frieze"))
        else:
            pier = Z("marble" if (k - cA) % 2 == 0 else "marble2")
            ls, rs = side(kn, "left"), side(k, "right")
            assert not (ls and rs), "a one-interval pier between bays"
            if rs:
                lo = [v for (z, v) in rs if z < SILL][::-1]
                hi = [v for (z, v) in rs if z > SILL][::-1]
                _poly(m, [W0[kn], WP[kn], WP[k]] + lo + [W0[k]], w, Z("plinth"))
                _poly(m, [WP[kn], WF0[kn], WF0[k]] + hi + [WP[k]], w, pier)
            else:
                lo = [v for (z, v) in ls if z < SILL]
                hi = [v for (z, v) in ls if z > SILL]
                _poly(m, [W0[k], W0[kn]] + lo + [WP[kn], WP[k]], w, Z("plinth"))         # plinth band
                _poly(m, [WP[k], WP[kn]] + hi + [WF0[kn], WF0[k]], w, pier)
            m.quad(S[k], S[kn], W0[kn], W0[k], UP, Z("shade"))                          # ledge
            m.quad(WF0[k], WF0[kn], WF1[kn], WF1[k], w, Z("frieze"))
        m.quad(WF1[k], WF1[kn], C0[kn], C0[k], DOWN, Z("shade"))             # cornice soffit
        m.quad(C0[k], C0[kn], top_in[kn], top_in[k], w, Z("band"))           # cornice front
    return arches


# =============================================================================
# THE THEME
# =============================================================================

class MarbleTheme(hb._Theme):
    key = "marble"
    jitter = hb.JITTER_STONE
    dais_zone = Z("plinth")

    def __init__(self):
        self.arches = []

    def floor_zone(self, r, a):
        return Z("floor")

    def wall_top(self, a):
        return WALL_TOP

    def wall_out(self, a):
        return hb.R_OUT + hb.WALL_T + WALL_THICK

    def wall_zone(self, am):
        return Z("marble")

    def claims_wall(self):
        return True

    def wall(self, m, J, foot, top_in, top_out, bot_out, cols):
        self.arches = _wall(m, J, foot, top_in, top_out, bot_out, cols)

    def images(self):
        albedo, emissive = mb.build_texture()
        albedo.name = "hub_marble_albedo"      # the hub's own paint of the marble atlas
        return albedo, emissive

    def material(self, albedo, emissive):
        return mb.stone_material("Marble", albedo, emissive)

    def unwrap(self, me, uvl, polys, zone, r):
        z = zone[1]
        mb._group_uv(me, uvl, polys, mb.ZONES[z], r, mb.FIT.get(z, ""), z in mb.ANCHORED)


THEME = MarbleTheme()


if __name__ == "__main__":
    ok = hb._check()
    for (b, w, h) in hb.hub_marble_build.THEME.arches:
        print("arch bearing=%.1f mouth=%.2f x %.2f m (sill %.1f, recess %.1f, %d bars)" % (b, w, h, SILL, DEPTH, BAR_N))
    sys.exit(0 if ok else 1)
