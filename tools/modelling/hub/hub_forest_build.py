"""
PANOPTICON -- hub_forest: wedge 3 of the hub ring (bearings 72..108), dressed
as the forest (Map 3). Not a model of its own: hub_base_build imports THEME
and builds it into the one hub rock. See _Theme in hub_base_build.py.

    grass floor, the worn path along the ring round the dais (r 38), verges
    the dais on "edge"
    the wedge's slice of the outer wall raised to 7 m, 2.5 m thick: its inner
        face a jagged leaf sheet; one barred cell near bearing 96
    three ferns on the grass, each in its own hole in the floor grid

Every zone is ("forest", <ft.ZONES name>): the forest atlas, one material.

    python3 tools/modelling/hub_base_build.py --check
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import hub_base_build as hb  # noqa: E402
import forest_tree_build as ft  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

JITTER = 0.06
PATH_HALF = 1.2             # rings within this of the dais radius: "path" ...
VERGE_HALF = 2.4            # ... and within this: "verge"

WALL_TOP = 7.0
WALL_T = 2.5
ROWS = (0.5, 1.5, 2.4, 3.6, 4.8, 6.0)   # sheet rows between the foot (0) and the top (7)
WANDER_R = 0.45             # a sheet vertex's outward wander (into the wall)
WANDER_Z = 0.3

CELL_B = 96.0               # the cell's centre column: the stock column nearest this bearing
SILL_Z = 0.3
SILL_ROW, JAMB_ROW, APEX_ROW = 0, 2, 3    # ROWS indices: 0.3 (forced), 2.4, 3.6
CELL_D = 2.0
BARS = 6
BAR_R = 0.07
BAR_SIDES = 6
BAR_SET = 0.2               # bars stand this far behind the mouth
BAR_TIP = 0.1               # ... and this far into the roof
BAR_LEAN = 0.12
BAR_WOBBLE = 0.06
BAR_SEG = 1.2
FRONT_SPLIT = 0.1           # extra sill vertices this far either side of a bar ...
SIDE_DEPTHS = (0.1, 0.2, 0.3, 0.4, 0.8)   # ... and down each strip side: the zipper's outer loop
                            # steps under 30 deg round the foot, so no corner pairs with a hex edge it cannot see

# ---- the fern, as forest_build.py grows them --------------------------------
FERNS = ((82.0, 31.4), (98.5, 44.6), (78.0, 43.4))   # bearing, radius
FERN_BLADES = (5, 7)
FERN_L = (0.6, 1.0)
FERN_W = (0.2, 0.3)
FERN_BASE = 0.32            # the crown's 4-vertex base ring on the floor ...
FERN_RING = 0.18            # ... rises into this 8-ring well inside it (the 4-to-8 zipper never folds)
FERN_CROWN = (0.09, 0.08, 0.16, 0.22)   # inner ring radius; lifts of the 8-ring, the inner ring, the top
FERN_FLAT = 0.35            # a blade's thickness as a fraction of its half width
FERN_SOCKET = 0.28          # a blade's root ring: this far in from its crown quad's corners

SEED = 2261103
TWO_PI = 2.0 * math.pi
UP = (0.0, 0.0, 1.0)


def Z(name):
    return ("forest", name)


# =============================================================================
# HELPERS -- hub_base_build's pol() convention: (r cos a, r sin a)
# =============================================================================

def _radial(a):
    return (math.cos(a), math.sin(a), 0.0)


def _tangent(a):
    return (-math.sin(a), math.cos(a), 0.0)


def _back(p, d):
    """p pushed d metres radially outward (into the wall)."""
    a = math.atan2(p[1], p[0])
    return ft.add(p, _radial(a), d)


def _centroid(m, idx):
    n = float(len(idx))
    return tuple(sum(m.verts[j][k] for j in idx) / n for k in range(3))


def _ccw(m, loop, cx, cy):
    """The loop ordered anticlockwise about (cx, cy) as seen from above."""
    area = 0.0
    for k in range(len(loop)):
        x0, y0, _ = m.verts[loop[k]]
        x1, y1, _ = m.verts[loop[(k + 1) % len(loop)]]
        area += (x0 - cx) * (y1 - cy) - (x1 - cx) * (y0 - cy)
    return list(loop) if area > 0.0 else list(reversed(loop))


def _fan_from(m, apex, chain, want, zone):
    """Triangles (apex, chain[i], chain[i+1]): a polygon fanned from a vertex
    off the chain's line (hb's fan re-roots on the loop's winding)."""
    for i in range(len(chain) - 1):
        m.tri(apex, chain[i], chain[i + 1], want, zone)


def _loft(m, rings, path, zone):
    """Quads between successive rings of equal count, normals off the axis."""
    for i in range(len(rings) - 1):
        axis = ft.lerp(path[i], path[i + 1], 0.5)
        n = len(rings[i])
        for s in range(n):
            q = (s + 1) % n
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], ft.sub(_centroid(m, idx), axis), zone)


def _tube(m, path, radii, sides, zone, first_ring, wob=0.0, rng=None):
    """A tapered tube along ``path`` growing out of ``first_ring`` (ids already
    in the surface), capped at its far end. Returns the rings."""
    fr = ft.frames(path)
    n = len(path)
    rings = [list(first_ring)]
    for i in range(1, n):
        t, ex, ez = fr[i]
        r = ft._at(radii, i / float(n - 1))
        rings.append([m.v(p) for p in ft.ring_pts(path[i], ex, ez, r, sides, 1.0, wob, rng)])
    _loft(m, rings, path, zone)
    m.fan(rings[-1], fr[-1][0], zone)
    return rings


# =============================================================================
# THE FERN -- forest_build's crown and blades, closed, on a 4-ring the floor
# grid is zippered to
# =============================================================================

def _fern(m, r, cx, cy):
    """Returns the base ring (4 ids, CCW, z 0) for the floor hole."""
    ph = r.u(0.0, TWO_PI)
    base = [m.v((cx + FERN_BASE * math.cos(ph + TWO_PI * s / 4), cy + FERN_BASE * math.sin(ph + TWO_PI * s / 4), 0.0))
            for s in range(4)]
    ring, inner = [], []
    for s in range(8):
        a = ph + TWO_PI * (s + 0.5) / 8
        ring.append(m.v((cx + FERN_RING * math.cos(a), cy + FERN_RING * math.sin(a), FERN_CROWN[1])))
        inner.append(m.v((cx + FERN_CROWN[0] * math.cos(a), cy + FERN_CROWN[0] * math.sin(a), FERN_CROWN[2])))
    hb._zipper(m, base, ring, cx, cy, UP, Z("fern"))
    top = m.v((cx, cy, FERN_CROWN[3]))
    low = (cx, cy, -0.2)
    slots = list(range(8))
    while len(slots) > r.i(*FERN_BLADES):
        slots.pop(r.i(0, len(slots) - 1))
    for s in range(8):
        q = (s + 1) % 8
        crown = (ring[s], ring[q], inner[q], inner[s])
        m.tri(top, inner[s], inner[q], UP, Z("fern"))
        if s not in slots:
            m.quad(crown[0], crown[1], crown[2], crown[3], ft.sub(_centroid(m, crown), low), Z("fern"))
            continue
        _blade(m, r, crown, ph + TWO_PI * (s + 1.0) / 8, low)
    return base


def _blade(m, r, crown, a, low):
    """A blade out of a crown quad: a 4-ring inset in the quad (the quad's
    rim bridges to it, four to four), a thin flat tube bending up and over,
    capped at the tip."""
    c = [m.verts[i] for i in crown]
    f = FERN_SOCKET
    uv = ((f, f), (1.0 - f, f), (1.0 - f, 1.0 - f), (f, 1.0 - f))
    root_pts = []
    for (u, v) in uv:
        p = [((1 - u) * (1 - v)) * c[0][k] + (u * (1 - v)) * c[1][k] + (u * v) * c[2][k] + ((1 - u) * v) * c[3][k] for k in range(3)]
        root_pts.append(tuple(p))
    root = [m.v(p) for p in root_pts]
    for s in range(4):
        q = (s + 1) % 4
        idx = (crown[s], crown[q], root[q], root[s])
        m.quad(idx[0], idx[1], idx[2], idx[3], ft.sub(_centroid(m, idx), low), Z("fern"))
    bp = _centroid(m, root)
    a += r.u(-0.15, 0.15)
    el = math.radians(r.u(28.0, 58.0))
    L, W = r.u(*FERN_L), r.u(*FERN_W)
    d = (math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el))
    d2 = (math.cos(a) * math.cos(el * 0.35), math.sin(a) * math.cos(el * 0.35), math.sin(el * 0.35))
    mid = ft.add(bp, d, L * 0.5)
    tip = ft.add(mid, d2, L * 0.5)
    path = [bp, mid, tip]
    fr = ft.frames(path)
    t0, ex0, ez0 = fr[0]
    angs = [math.atan2(ft.dot(ft.sub(p, bp), ez0), ft.dot(ft.sub(p, bp), ex0)) for p in root_pts]
    rings = [root]
    for i, rad in ((1, W * 0.5), (2, W * 0.25)):
        _t, ex, ez = fr[i]
        rings.append([m.v(ft.add(ft.add(path[i], ex, rad * math.cos(t)), ez, rad * math.sin(t) * FERN_FLAT)) for t in angs])
    _loft(m, rings, path, Z("fern"))
    m.fan(rings[-1], fr[-1][0], Z("fern"))


# =============================================================================
# THE THEME
# =============================================================================

class ForestTheme(hb._Theme):
    key = "forest"
    jitter = JITTER
    dais_zone = Z("edge")

    def floor_zone(self, r, a):
        d = abs(r - hb.DAIS_RAD)
        if d < PATH_HALF:
            return Z("path")
        if d < VERGE_HALF:
            return Z("verge")
        return Z("grass")

    def features(self, m, w, coll=False):
        if coll:
            return []
        holes = []
        for k, (b, rad) in enumerate(FERNS):
            cx, cy, _ = hb.pol(b, rad)
            base = _fern(m, ft._Rng(SEED + 977 * k), cx, cy)
            holes.append((cx, cy, FERN_BASE + hb.HOLE_PAD, base, Z("grass")))
        return holes

    def wall_top(self, a):
        return WALL_TOP

    def wall_out(self, a):
        return hb.R_OUT + WALL_T

    def wall_zone(self, am):
        return Z("shade")

    def claims_wall(self):
        return True

    # -- the wall ------------------------------------------------------------
    def wall(self, m, J, foot, top_in, top_out, bot_out, cols):
        r = ft._Rng(SEED)
        C = list(J) + [J[-1] + 1]
        inner = C[1:-1]
        cM = min(C[2:-2], key=lambda c: abs(math.degrees(cols[c][0]) - CELL_B))
        cL, cR = cM - 1, cM + 1
        self.cell_bearing = math.degrees(cols[cM][0])
        fixed = set([(cL, SILL_ROW), (cM, SILL_ROW), (cR, SILL_ROW), (cM, APEX_ROW)])
        for k in range(SILL_ROW, JAMB_ROW + 1):
            fixed.add((cL, k))
            fixed.add((cR, k))
        # the sheet: per interior column, foot, ROWS, top
        V = {}
        for c in inner:
            a = cols[c][0]
            col = [foot[c]]
            for k, z in enumerate(ROWS):
                if (c, k) in fixed:
                    rad, zz = hb.R_OUT, (SILL_Z if k == SILL_ROW else z)
                else:
                    rad, zz = hb.R_OUT + r.u(0.0, WANDER_R), z + r.u(-WANDER_Z, WANDER_Z)
                col.append(m.v((rad * math.cos(a), rad * math.sin(a), zz)))
            col.append(top_in[c])
            V[c] = col
        sill_split = self._cell(m, r, V, cL, cM, cR, cols)
        leaf = Z("leaf")
        for j in J:
            jn = j + 1
            am = 0.5 * (cols[j][0] + cols[jn][0])
            want = (-math.cos(am), -math.sin(am), 0.0)
            if j == C[0]:
                self._end(m, foot[j], top_in[j], V[jn], want, leaf)
            elif jn == C[-1]:
                self._end(m, foot[jn], top_in[jn], V[j], want, leaf)
            else:
                A, B = V[j], V[jn]
                for k in range(len(A) - 1):
                    if j in (cL, cM):
                        kk = k - 1                     # ROWS index of the band's lower row
                        if kk == SILL_ROW - 1:         # under the sill: its edge carries the floor's splits
                            split = sill_split[0] if j == cL else sill_split[1]
                            _fan_from(m, A[k], [B[k], B[k + 1]] + list(reversed(split)) + [A[k + 1]], want, leaf)
                            continue
                        if SILL_ROW <= kk < JAMB_ROW:  # the mouth
                            continue
                        if kk == JAMB_ROW:             # the arch band: one triangle beside the point
                            if j == cL:
                                m.tri(A[k], A[k + 1], B[k + 1], want, leaf)
                            else:
                                m.tri(B[k], B[k + 1], A[k + 1], want, leaf)
                            continue
                    m.quad(A[k], B[k], B[k + 1], A[k + 1], want, leaf)
            m.quad(top_in[j], top_in[jn], top_out[jn], top_out[j], UP, leaf)
            m.quad(top_out[j], top_out[jn], bot_out[jn], bot_out[j], (math.cos(am), math.sin(am), 0.0), leaf)

    def _end(self, m, f, t, col, want, zone):
        """The interval against a seam column: that column has only its stock
        foot and top, so the sheet's rows fan to them."""
        k = APEX_ROW + 1                     # the row the two fans meet at
        for i in range(k):
            m.tri(f, col[i], col[i + 1], want, zone)
        m.tri(f, col[k], t, want, zone)
        for i in range(k, len(col) - 1):
            m.tri(t, col[i], col[i + 1], want, zone)

    def _cell(self, m, r, V, cL, cM, cR, cols):
        """The barred cell: a pointed-arch mouth in the sheet, recessed CELL_D
        to a dark back; the floor cut into one strip per bar and each strip
        zippered to its bar's foot ring, the bar's tip buried in the roof.
        Returns the sill's split ids, left half and right half, left to right."""
        P = lambda vid: m.verts[vid]
        sill = [V[cL][SILL_ROW + 1], V[cM][SILL_ROW + 1], V[cR][SILL_ROW + 1]]
        left = [V[cL][k + 1] for k in range(SILL_ROW, JAMB_ROW + 1)]
        right = [V[cR][k + 1] for k in range(SILL_ROW, JAMB_ROW + 1)]
        arch = [left[-1], V[cM][APEX_ROW + 1], right[-1]]
        mc = _centroid(m, [sill[0], sill[2], arch[0], arch[1], arch[2]])
        h = len(left) - 1

        def along(poly, t):
            return ft.lerp(P(poly[0]), P(poly[1]), t * 2.0) if t <= 0.5 else ft.lerp(P(poly[1]), P(poly[2]), (t - 0.5) * 2.0)

        def q(a, b, c, d, zn):
            m.quad(a, b, c, d, ft.sub(mc, _centroid(m, (a, b, c, d))), zn)

        width = math.sqrt(ft.dot(ft.sub(P(sill[2]), P(sill[0])), ft.sub(P(sill[2]), P(sill[0]))))
        pt = 1.0 / (BARS + 1)
        bars = [k * pt for k in range(1, BARS + 1)]
        T = sorted(set([0.0, 0.5, 1.0] + [round(b + 0.5 * pt, 9) for b in bars[:-1]]))
        U = sorted(set(T + [round(b + d, 9) for b in bars
                            for d in (-0.5 * pt, 0.5 * pt, -FRONT_SPLIT / width, FRONT_SPLIT / width)]))
        Fv = {}
        for t in U:
            Fv[t] = sill[0] if t == 0.0 else (sill[1] if t == 0.5 else (sill[2] if t == 1.0 else m.v(along(sill, t))))
        side = []                          # per strip boundary: the sill vertex, SIDE_DEPTHS back, the back
        for t in T:
            side.append([Fv[t]] + [m.v(_back(P(Fv[t]), d)) for d in SIDE_DEPTHS] + [m.v(_back(P(Fv[t]), CELL_D))])
        B = [sd[-1] for sd in side]
        lB = [B[0]] + [m.v(_back(P(left[k]), CELL_D)) for k in range(1, h)]
        gB = [B[-1]] + [m.v(_back(P(right[k]), CELL_D)) for k in range(1, h)]
        rB = [m.v(_back(P(v), CELL_D)) for v in arch]
        lB.append(rB[0])
        gB.append(rB[-1])
        shade, edge = Z("shade"), Z("edge")
        wl = ft.sub(mc, _centroid(m, (left[0], left[1], lB[1], lB[0])))
        _fan_from(m, left[1], [lB[1]] + list(reversed(side[0])), wl, shade)
        wr = ft.sub(mc, _centroid(m, (right[0], right[1], gB[1], gB[0])))
        _fan_from(m, right[1], [right[0]] + side[-1][1:] + [gB[1]], wr, shade)
        for k in range(1, h):
            q(left[k], left[k + 1], lB[k + 1], lB[k], shade)
            q(right[k], right[k + 1], gB[k + 1], gB[k], shade)
        for j in range(2):
            q(arch[j], arch[j + 1], rB[j + 1], rB[j], shade)
        loop = list(B) + gB[1:h] + list(reversed(rB)) + list(reversed(lB[1:h]))
        cb = m.v(_centroid(m, loop))
        for i in range(len(loop)):
            a, b = loop[i], loop[(i + 1) % len(loop)]
            m.tri(cb, a, b, ft.sub(mc, _centroid(m, (cb, a, b))), Z("cell"))
        # the bars: a hex foot ring in its floor strip, the strip zippered to it
        bmid = cols[cM][0]
        for k, t in enumerate(bars):
            j = [i for i in range(len(T) - 1) if T[i] < t < T[i + 1]][0]
            front = [Fv[u] for u in U if T[j] <= u <= T[j + 1]]
            poly = front + side[j + 1][1:] + list(reversed(side[j]))[:-1]
            fp = _back(along(sill, t), BAR_SET)
            tp = ft.add(_back(along(arch, t), BAR_SET + r.u(0.0, BAR_LEAN)), UP, BAR_TIP)
            mid = ft.add(ft.lerp(fp, tp, 0.5), _tangent(bmid), r.u(-BAR_WOBBLE, BAR_WOBBLE))
            nseg = max(2, int(math.ceil(math.sqrt(ft.dot(ft.sub(tp, fp), ft.sub(tp, fp))) / BAR_SEG)))
            path = ft.bez(fp, mid, tp, nseg)
            _t, ex, _ez = ft.frames(path)[0]
            ex = ft.norm((ex[0], ex[1], 0.0))
            ez = ft.cross(UP, ex)
            ring = [m.v(p) for p in ft.ring_pts(fp, ex, ez, BAR_R, BAR_SIDES)]
            hb._zipper(m, _ccw(m, poly, fp[0], fp[1]), _ccw(m, ring, fp[0], fp[1]), fp[0], fp[1], UP, edge)
            _tube(m, path, (BAR_R, BAR_R * 0.85), BAR_SIDES, Z("bark"), ring, wob=0.15, rng=r)
        return ([Fv[u] for u in U if 0.0 < u < 0.5], [Fv[u] for u in U if 0.5 < u < 1.0])

    # -- material ------------------------------------------------------------
    def images(self):
        return ft.sheet("forest_atlas", ft.paint_atlas)

    def material(self, albedo, emissive):
        return ft.atlas_material("ForestAtlas", albedo, emissive)

    def unwrap(self, me, uvl, polys, zone, r):
        """forest_tree_build.unwrap's per-polygon body: a planar projection
        into a random window of the zone at TPM texels per metre."""
        u0, v0, u1, v1 = ft.ZONES[zone[1]]
        span_u = (u1 - u0) - 2.0 * ft.UV_PAD
        span_v = (v1 - v0) - 2.0 * ft.UV_PAD
        scale = ft.TPM / ((u1 - u0) * ft.TEX_SIZE)
        scale_v = ft.TPM / ((v1 - v0) * ft.TEX_SIZE)
        for pi in polys:
            poly = me.polygons[pi]
            nrm = poly.normal
            ax = max(range(3), key=lambda i: abs(nrm[i]))
            ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
            fu = -1.0 if r.i(0, 1) else 1.0
            fv = -1.0 if (ax == 2 and r.i(0, 1)) else 1.0
            cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
            mi = min(co[ii] for co in cos)
            mj = min(co[jj] for co in cos)
            w = min((max(co[ii] for co in cos) - mi) * scale, 1.0)
            hh = min((max(co[jj] for co in cos) - mj) * scale_v, 1.0)
            ou = r.f() * (1.0 - w)
            ov = r.f() * (1.0 - hh)
            for li, co in zip(poly.loop_indices, cos):
                s = min(ou + (co[ii] - mi) * scale, 1.0)
                t = min(ov + (co[jj] - mj) * scale_v, 1.0)
                if fu < 0.0:
                    s = 1.0 - s
                if fv < 0.0:
                    t = 1.0 - t
                uvl.data[li].uv = (u0 + ft.UV_PAD + s * span_u, v0 + ft.UV_PAD + t * span_v)


THEME = ForestTheme()
