"""
marble_trapdoor -- the walkway's trapdoor, an ARC SECTOR of the ring: an iron frame lining the hole
marble_build cuts (TRAPDOOR_CELLS lane cells round a pier in TRAPDOOR_BEARINGS, DECK_RS[TRAPDOOR_IN_K] to the
wall foot), its inner and outer edges concentric with the lane and its sides radial; TWO stone flaps hinged on
the lane-side arcs that part at a seam arc and hang into the pit; spikes on the pit floor PIT_D down
(Ryan 2026-10-20: "only two flaps ... make the pit much deeper"; 2026-10-25: "they don't fit on the ring
because they are rectangles").

ORIGIN: the deck point at r PIVOT_R (mid-hole) on the hole's centre bearing, z 0 the deck.
Godot +X radial outward, +Z toward INCREASING bearing (Blender -Y).

    TrapdoorFrame   iron rim inside the hole: its outer edge the cut itself, its inner edge two arcs and two radial sides
    TrapdoorLeaf00  the inner flap, hinged on the lip arc;  TrapdoorLeaf01  the outer, on the wall arc
    TrapdoorSpikes  pale spikes on the pit floor, clear of the hanging flaps

A flap's ORIGIN is its hinge axis: the chord through its hinge arc's ends at the flap's BOTTOM arris
(z -LEAF_T), under the rim, so the arc's bulge past the chord swings DOWN into the pit and never up.
Local frame +X along the hinge, +Y up, +Z (Godot) toward the free edge: +90 deg about local X hangs it.
Every arc is the lane's own station polyline (a chord per lane cell), so the flaps' flags sit on the
lane's grid and the frame's edges are parallel to the cut. No colliders: the scene makes them.

    python3 tools/modelling/maps/marble/marble_trapdoor_build.py --check
    tools/modelling/model build marble_trapdoor
"""

import math
import os
import sys

try:
    import bpy
except ImportError:                       # --check on the Mac: geometry only
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import marble_build as mb  # noqa: E402
import texel as tx  # noqa: E402
import marble_lane_build as _ml  # noqa: E402, F401
import marble_wall_build as _mw  # noqa: E402, F401

if bpy is not None:
    import mdl  # noqa: E402
    import vertex_ao  # noqa: E402
    mdl.DEFAULTS["views"] = ["threequarter", "top"]
    mdl.DEFAULTS["ground"] = False

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "marble_trapdoor"
FACING_YAW = 0.0
PIVOT_R = mb.TRAPDOOR_R                 # 53.989: the prop's origin radius, mid-hole
R_IN = mb.DECK_RS[mb.TRAPDOOR_IN_K]     # 48.05: the hole's inner edge, the lane's own station polyline
R_WALL = mb.WALL_R                      # 60: the hole's outer corners, the wall's bay corners
R_WALL_MID = mb.WALL_R * math.cos(math.pi / mb.NSIDE)   # 59.928: the wall chord at a bay's middle
STEP = math.radians(360.0 / (mb.NSIDE * mb.DECK_SUB))   # one lane cell: 2.8125 deg
HALF_CELLS = mb.TRAPDOOR_CELLS // 2
HALF = HALF_CELLS * STEP                # the hole's half-span, 5.625 deg
PIT_D = mb.DECK_Z - mb.PIT_Z            # 6.0: the pit floor under the deck, room for a flap to hang
FRAME_W = 0.28                          # the iron rim, inside the hole, at its narrowest: reads from 15 m
FRAME_D = 0.35                          # ... this deep
FRAME_SKIN = 0.002                      # its outer faces lean in by this from the top edge to the bottom
LEAF_T = 0.15                           # the stone leaves' thickness
GAP = 0.005                             # each flap this far off the seam (1 cm between)
STRAP_AT = (0.1, 0.3, 0.5, 0.7, 0.9)    # heavy strap hinges across each flap, fractions along the hinge arc
STRAP_W = 0.30
SEAM_W = 0.07                           # an iron lip on each free edge: the seam reads dark
KNUCKLE_R = 0.07                        # hinge knuckles on the rim at the hinge arc: proud by their radius
KNUCKLE_L = 0.50
KNUCKLE_AT = STRAP_AT
KNUCKLE_SIDES = 6
SPIKE_PITCH = 0.9                       # the floor grid, radial and along the lane
SPIKE_MARGIN = 0.45                     # the grid stops this short of the hinge axes: the hanging flaps clear it
SPIKE_HW = 0.09
SPIKE_H = (0.85, 1.1)                   # pale stone, tips PIT_D-1.1 .. PIT_D-0.85 under the deck
LEAF_TINT = tuple(0.85 * c for c in mb.TINT_FLOOR)   # the deck's floor value, the leaves' flags a little darker and worn against it

R_HINGE_IN = R_IN + FRAME_W             # 48.33: the inner flap's hinge arc
R_HINGE_OUT = R_WALL_MID - FRAME_W      # 59.648: the outer flap's hinge arc (the rim 0.28 at a bay's middle, 0.35 at its corners)
RINGS = tuple(mb.DECK_RS[mb.TRAPDOOR_IN_K:]) + (R_WALL_MID,)   # the lane's paving rings over the hole; the margin one more
CENTRE = (-PIVOT_R, 0.0)                # the ring's axis in the prop's frame

UP, DOWN = mb.UP, mb.DOWN

SHEETS = {
    "floor": mb.tile("floor", "marble_floor", "custom", 64, 64, mpt=2.7 / 64.0, tint=LEAF_TINT),
    "spike": mb.stone("spike", mode="box", mpt=tx.MPT, tint=mb.TINT_SPIKE),
    "iron": mb.iron_sheet(),
}


# =============================================================================
# 2D HELPERS (Blender x, y in the prop's frame; bearings relative to the hole's centre)
# =============================================================================

def C(r, phi):
    """Radius r at relative game bearing phi (radians) -> Blender (x, y)."""
    return (r * math.cos(phi) - PIVOT_R, -r * math.sin(phi))


def bearing(p):
    return math.atan2(-p[1], p[0] - CENTRE[0])


def tangent(phi):
    """Unit Blender xy toward increasing bearing at relative bearing phi."""
    return (-math.sin(phi), -math.cos(phi))


def radial(phi):
    """The line through the axis at bearing phi: (point, unit direction outward)."""
    return (CENTRE, (math.cos(phi), -math.sin(phi)))


def offset_line(phi, w):
    """The radial at phi moved w along the tangent (w > 0 toward increasing bearing)."""
    t = tangent(phi)
    return ((CENTRE[0] + t[0] * w, CENTRE[1] + t[1] * w), (math.cos(phi), -math.sin(phi)))


def _meet(l1, l2):
    (p, d), (q, e) = l1, l2
    den = d[0] * e[1] - d[1] * e[0]
    t = ((q[0] - p[0]) * e[1] - (q[1] - p[1]) * e[0]) / den
    return (p[0] + d[0] * t, p[1] + d[1] * t)


def _at_x(line, x):
    """Where (point, direction) crosses the Blender x = const line."""
    (p, d) = line
    tt = (x - p[0]) / d[0]
    return (x, p[1] + d[1] * tt)


def _lerp(p, q, t):
    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)


def on_circle(line, r):
    """Where the line crosses the circle of radius r on the hole's side of the ring."""
    (p, d) = line
    px, py = p[0] - CENTRE[0], p[1] - CENTRE[1]
    a = d[0] * d[0] + d[1] * d[1]
    b = 2.0 * (px * d[0] + py * d[1])
    c = px * px + py * py - r * r
    s = math.sqrt(b * b - 4.0 * a * c)
    for t in ((-b + s) / (2.0 * a), (-b - s) / (2.0 * a)):
        q = (p[0] + d[0] * t, p[1] + d[1] * t)
        if abs(bearing(q)) < math.pi / 2.0:
            return q
    raise ValueError("line misses the hole's side of r %.3f" % r)


def chord(r, k):
    """The arc polyline's segment k (lane stations k..k+1) at radius r, as a line."""
    p, q = C(r, k * STEP), C(r, (k + 1) * STEP)
    return (p, (q[0] - p[0], q[1] - p[1]))


def arc_pt(line, r):
    """Where the line crosses the station polyline of radius r (the lane's own facets)."""
    phi = bearing(on_circle(line, r))
    k = min(max(int(math.floor(phi / STEP)), -HALF_CELLS), HALF_CELLS - 1)
    return _meet(line, chord(r, k))


def end_lines():
    """The hole's two radial sides moved FRAME_W into it: (lower bearing, higher bearing)."""
    return offset_line(-HALF, FRAME_W), offset_line(HALF, -FRAME_W)


def hinge_span(r_h):
    """(bearing lo, bearing hi) of a hinge arc between the moved-in ends."""
    lo, hi = end_lines()
    return bearing(on_circle(lo, r_h)), bearing(on_circle(hi, r_h))


def _area(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                     for i in range(len(poly)))


def _shrink(poly, w):
    """CCW polygon moved in by w on every edge; a straight-through vertex just slides in."""
    n = len(poly)
    out = []
    for i in range(n):
        p0, p1, p2 = poly[i - 1], poly[i], poly[(i + 1) % n]
        e1 = (p1[0] - p0[0], p1[1] - p0[1])
        e2 = (p2[0] - p1[0], p2[1] - p1[1])
        l1, l2 = math.hypot(*e1), math.hypot(*e2)
        n1 = (-e1[1] / l1 * w, e1[0] / l1 * w)
        n2 = (-e2[1] / l2 * w, e2[0] / l2 * w)
        if abs(e1[0] * e2[1] - e1[1] * e2[0]) < 1e-9 * l1 * l2:
            out.append((p1[0] + n1[0], p1[1] + n1[1]))
        else:
            out.append(_meet(((p0[0] + n1[0], p0[1] + n1[1]), e1), ((p1[0] + n2[0], p1[1] + n2[1]), e2)))
    return out


def hole():
    """The cut, CCW: lane stations on the lip at R_IN, the wall's chords (corners at R_WALL, bay middles on
    the chord at R_WALL_MID), radial sides."""
    lip = [C(R_IN, k * STEP) for k in range(-HALF_CELLS, HALF_CELLS + 1)]
    wall = [C(R_WALL if k % 2 == 0 else R_WALL_MID, k * STEP) for k in range(-HALF_CELLS, HALF_CELLS + 1)]
    poly = lip + list(reversed(wall))
    assert _area(poly) > 0.0
    return poly


def inner_polyline():
    """The rim's inner boundary, one vertex per hole() vertex: the lip arc at R_HINGE_IN, the wall arc at
    R_HINGE_OUT, both on the station polyline, their ends on the moved-in sides."""
    lo, hi = end_lines()

    def arc(r):
        pts = []
        for k in range(-HALF_CELLS, HALF_CELLS + 1):
            if k == -HALF_CELLS:
                pts.append(arc_pt(lo, r))
            elif k == HALF_CELLS:
                pts.append(arc_pt(hi, r))
            else:
                pts.append(C(r, k * STEP))
        return pts

    return arc(R_HINGE_IN) + list(reversed(arc(R_HINGE_OUT)))


def _reach(r_h, r_f):
    """How far a flap's free arc stands from its hinge axis (the chord), at its farthest point."""
    lo, hi = end_lines()
    x_axis = arc_pt(lo, r_h)[0]
    pts = [arc_pt(lo, r_f), arc_pt(hi, r_f)] + [C(r_f, k * STEP) for k in range(-HALF_CELLS + 1, HALF_CELLS)]
    return max(abs(p[0] - x_axis) for p in pts)


def seam_r():
    """The seam arc's radius: where both flaps reach the same depth hanging (every arc bows one way, so
    the outer flap's free corners stand farther from its axis than the inner flap's middle does)."""
    a, b = R_HINGE_IN, R_HINGE_OUT
    for _ in range(60):
        r = 0.5 * (a + b)
        if _reach(R_HINGE_IN, r - GAP) < _reach(R_HINGE_OUT, r + GAP):
            a = r
        else:
            b = r
    return 0.5 * (a + b)


def leaves():
    """(name, hinge radius, free radius) for the two flaps."""
    rs = seam_r()
    return [("TrapdoorLeaf00", R_HINGE_IN, rs - GAP), ("TrapdoorLeaf01", R_HINGE_OUT, rs + GAP)]


# =============================================================================
# THE FRAME
# =============================================================================

def _ring(m, outer_top, outer_bot, inner, z_top, z_bot, zone):
    n = len(outer_top)
    o0 = [m.v((p[0], p[1], z_top)) for p in outer_top]
    i0 = [m.v((p[0], p[1], z_top)) for p in inner]
    o1 = [m.v((p[0], p[1], z_bot)) for p in outer_bot]
    i1 = [m.v((p[0], p[1], z_bot)) for p in inner]
    for k in range(n):
        j = (k + 1) % n
        m.quad(o0[k], o0[j], i0[j], i0[k], UP, zone)
        m.quad(o1[k], o1[j], i1[j], i1[k], DOWN, zone)
        e = (outer_top[j][0] - outer_top[k][0], outer_top[j][1] - outer_top[k][1])
        out = (e[1], -e[0], 0.0)                     # outward of a CCW edge
        m.quad(o0[k], o0[j], o1[j], o1[k], out, zone)
        m.quad(i0[k], i0[j], i1[j], i1[k], (-out[0], -out[1], 0.0), zone)


def _knuckle(m, a, b, zone):
    """A closed n-gon prism along a..b (3D points), radius KNUCKLE_R."""
    d = [b[i] - a[i] for i in range(3)]
    L = math.sqrt(sum(x * x for x in d))
    d = [x / L for x in d]
    u = (-d[1], d[0], 0.0)
    w = (0.0, 0.0, 1.0)
    n = KNUCKLE_SIDES
    ra, rb = [], []
    for k in range(n):
        t = 2.0 * math.pi * k / n
        off = [KNUCKLE_R * (math.cos(t) * u[i] + math.sin(t) * w[i]) for i in range(3)]
        ra.append(m.v(tuple(a[i] + off[i] for i in range(3))))
        rb.append(m.v(tuple(b[i] + off[i] for i in range(3))))
    for k in range(n):
        j = (k + 1) % n
        t = 2.0 * math.pi * (k + 0.5) / n
        out = tuple(math.cos(t) * u[i] + math.sin(t) * w[i] for i in range(3))
        m.quad(ra[k], ra[j], rb[j], rb[k], out, zone)
    m.poly(ra, tuple(-x for x in d), zone)
    m.poly(rb, tuple(d), zone)


def frame():
    m = mb._Mesh()
    outer = hole()
    _ring(m, outer, _shrink(outer, FRAME_SKIN), inner_polyline(), 0.0, -FRAME_D, "iron")
    for _name, r_h, r_f in leaves():
        lo, hi = hinge_span(r_h)
        r_c = r_h - 0.03 if r_f > r_h else r_h + 0.03      # a hair back onto the rim
        for k in KNUCKLE_AT:
            phi = lo + (hi - lo) * k
            c = C(r_c, phi)
            t = tangent(phi)
            a = (c[0] - t[0] * KNUCKLE_L / 2, c[1] - t[1] * KNUCKLE_L / 2, 0.0)
            b = (c[0] + t[0] * KNUCKLE_L / 2, c[1] + t[1] * KNUCKLE_L / 2, 0.0)
            _knuckle(m, a, b, "iron")
    return m


# =============================================================================
# THE LEAVES -- authored in the prop's frame, then moved into the hinge's own
# =============================================================================

def leaf_frame(r_h, r_f):
    """(origin xyz, rotation_z) of a flap's object: the hinge chord's midpoint at the bottom arris, local x
    along the chord, the free edge at local -y."""
    lo, hi = end_lines()
    h0, h1 = arc_pt(lo, r_h), arc_pt(hi, r_h)
    mid = _lerp(h0, h1, 0.5)
    rot = math.atan2(h1[1] - h0[1], h1[0] - h0[0])
    f = C(r_f, 0.0)
    if _to_local((f[0], f[1], 0.0), (mid[0], mid[1], 0.0), rot)[1] > 0.0:
        rot += math.pi
    return (mid[0], mid[1], -LEAF_T), rot


def _to_local(pt, origin, rot):
    x, y, z = pt[0] - origin[0], pt[1] - origin[1], pt[2] - origin[2]
    c, s = math.cos(-rot), math.sin(-rot)
    return (x * c - y * s, x * s + y * c, z)


def side_lines(r_h):
    """The flap's side lines in bearing order with the class of the strip after each: the moved-in ends,
    the straps' edges and the lane's stations (the flags break there, as the deck's do)."""
    lo_e, hi_e = end_lines()
    lo, hi = hinge_span(r_h)
    lines = [(lo_e, "end"), (hi_e, "end")]
    for t in STRAP_AT:
        phi = lo + (hi - lo) * t
        lines.append((offset_line(phi, -STRAP_W / 2.0), "strap_in"))
        lines.append((offset_line(phi, STRAP_W / 2.0), "strap_out"))
    for k in range(-HALF_CELLS + 1, HALF_CELLS):
        lines.append((radial(k * STEP), "station"))
    r_mid = 0.5 * (R_HINGE_IN + R_HINGE_OUT)
    lines.sort(key=lambda lk: bearing(on_circle(lk[0], r_mid)))
    out, strap = [], False
    for line, kind in lines:
        if out and abs(bearing(on_circle(line, r_mid)) - bearing(on_circle(out[-1][0], r_mid))) < 1e-5:
            continue
        if kind == "strap_in":
            strap = True
        elif kind == "strap_out":
            strap = False
        out.append((line, "iron" if strap else "floor"))
    return out


def bands(r_h, r_f):
    """Radii across the flap from the hinge to the free edge, with the class of each band: the lane's rings
    break the flags, the last SEAM_W at the free edge is the iron lip."""
    seam = r_f - SEAM_W if r_f > r_h else r_f + SEAM_W
    rs = {r_h, r_f, seam} | {r for r in RINGS if min(r_h, r_f) < r < max(r_h, r_f)}
    rs = sorted(rs, reverse=r_f < r_h)
    out = []
    for a, b in zip(rs, rs[1:]):
        lip = min(a, b) >= min(seam, r_f) - 1e-9 and max(a, b) <= max(seam, r_f) + 1e-9
        out.append((a, b, "iron" if lip else "floor"))
    return out


def _ring_of(r):
    for a, b in zip(RINGS, RINGS[1:]):
        if a - 1e-9 <= r <= b + 1e-9:
            return a, b
    raise ValueError("r %.3f is off the lane's rings" % r)


def _flag_uv(p, r_nom, cell, ring):
    """The deck's own 'fit' window: u across the lane cell by bearing, v up the ring by radius."""
    th = -bearing(p)                                   # Blender angle, the deck's u direction
    return ((th - cell * STEP) / STEP, (r_nom - ring[0]) / (ring[1] - ring[0]))


def leaf(r_h, r_f):
    """The flap in its hinge's local frame: local x along the hinge chord, free edge toward local -y."""
    origin, rot = leaf_frame(r_h, r_f)
    m = mb._Mesh()
    top, bot = 0.0, -LEAF_T

    def V(p, z):
        return m.v(_to_local((p[0], p[1], z), origin, rot))

    def W(w):
        c, s = math.cos(-rot), math.sin(-rot)
        return (w[0] * c - w[1] * s, w[0] * s + w[1] * c, w[2])

    lines = side_lines(r_h)
    bds = bands(r_h, r_f)
    outward = 1.0 if r_f > r_h else -1.0                # +1: the free edge is outboard of the hinge
    for (la, cls_a), (lb, _cls_b) in zip(lines, lines[1:]):
        # the top, one quad per band
        for (ra, rb, cls_r) in bds:
            A, B, Cc, D = arc_pt(la, ra), arc_pt(lb, ra), arc_pt(lb, rb), arc_pt(la, rb)
            zone = "iron" if cls_a == "iron" or cls_r == "iron" else "floor"
            uv = None
            if zone == "floor":
                mid = _lerp(_lerp(A, B, 0.5), _lerp(D, Cc, 0.5), 0.5)
                cell = int(math.floor(-bearing(mid) / STEP))
                ring = _ring_of(0.5 * (ra + rb))
                uv = {V(A, top): _flag_uv(A, ra, cell, ring), V(B, top): _flag_uv(B, ra, cell, ring),
                      V(Cc, top): _flag_uv(Cc, rb, cell, ring), V(D, top): _flag_uv(D, rb, cell, ring)}
            m.quad(V(A, top), V(B, top), V(Cc, top), V(D, top), UP, zone, uv=uv)
        # the underside, the hinge face and the free face, one quad each per strip
        H0, H1, F0, F1 = arc_pt(la, r_h), arc_pt(lb, r_h), arc_pt(la, r_f), arc_pt(lb, r_f)
        m.quad(V(H0, bot), V(H1, bot), V(F1, bot), V(F0, bot), DOWN, "iron")
        phi = bearing(_lerp(H0, H1, 0.5))
        rad = (math.cos(phi), -math.sin(phi), 0.0)
        m.quad(V(H0, top), V(H1, top), V(H1, bot), V(H0, bot), W(tuple(-outward * c for c in rad)), "iron")
        m.quad(V(F0, top), V(F1, top), V(F1, bot), V(F0, bot), W(tuple(outward * c for c in rad)), "iron")
    # the two ends: the top edge carries every band's vertex
    for line, want in ((lines[0][0], (0.0, 1.0, 0.0)), (lines[-1][0], (0.0, -1.0, 0.0))):
        ring = [V(arc_pt(line, r_f), bot), V(arc_pt(line, r_h), bot), V(arc_pt(line, r_h), top)]
        ring += [V(arc_pt(line, rb), top) for (_ra, rb, _c) in bds]
        m.poly(ring, W(want), "iron")
    return m, origin, rot, _reach(r_h, r_f)


# =============================================================================
# THE SPIKES
# =============================================================================

def spikes():
    """Pale stone spikes on a SPIKE_PITCH grid over the pit floor, SPIKE_MARGIN in from the hinge axes (the
    hanging flaps clear them), heights from a fixed stream."""
    m = mb._Mesh()
    r = mb._Rng(7711)
    z0 = -PIT_D
    lo, hi = end_lines()
    x_lip, x_wall = arc_pt(lo, R_HINGE_IN)[0], arc_pt(lo, R_HINGE_OUT)[0]
    nx = int((x_wall - x_lip - 2.0 * SPIKE_MARGIN) / SPIKE_PITCH)
    for i in range(nx + 1):
        x = x_lip + SPIKE_MARGIN + (x_wall - x_lip - 2.0 * SPIKE_MARGIN) * (i / float(nx))
        y_lo, y_hi = _at_x(lo, x)[1], _at_x(hi, x)[1]            # y_lo > y_hi (Blender -y is +bearing)
        span = abs(y_lo - y_hi) - 2.0 * SPIKE_MARGIN
        ny = int(span / SPIKE_PITCH)
        for j in range(ny + 1):
            y = y_lo - SPIKE_MARGIN - span * (j / float(ny))
            h = SPIKE_H[0] + (SPIKE_H[1] - SPIKE_H[0]) * r.f()
            b = [m.v((x + sx * SPIKE_HW, y + sy * SPIKE_HW, z0 + 0.001))
                 for (sx, sy) in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            apex = m.v((x, y, z0 + h))
            m.quad(b[0], b[1], b[2], b[3], DOWN, "spike")
            for e in range(4):
                p, q2 = b[e], b[(e + 1) % 4]
                mx = 0.5 * (m.verts[p][0] + m.verts[q2][0]) - x
                my = 0.5 * (m.verts[p][1] + m.verts[q2][1]) - y
                m.tri(p, q2, apex, (mx, my, 0.3), "spike")
    return m


# =============================================================================
# BUILD
# =============================================================================

def parts():
    out = [("TrapdoorFrame", frame(), (0.0, 0.0, 0.0), 0.0)]
    for name, r_h, r_f in leaves():
        m, origin, rot, _w = leaf(r_h, r_f)
        out.append((name, m, origin, rot))
    out.append(("TrapdoorSpikes", spikes(), (0.0, 0.0, 0.0), 0.0))
    return out


def _check():
    ok = True
    for name, m, origin, rot in parts():
        a = mb.audit(m, name)
        bad = a["boundary_edges"] or a["doubled_edges"] or a["over_edges"] or a["degenerate"] \
            or a["duplicate_positions"]
        if name.startswith("TrapdoorLeaf") and a["components"] != 1:
            bad = True
        ok = ok and not bad
        print("%s origin=(%.4f, %.4f, %.4f) rot_z=%.4f deg" % (name, origin[0], origin[1], origin[2],
                                                                math.degrees(rot)))
    print("hole: lip r %.3f, wall r %.3f (%.3f at a bay's middle), sides +-%.4f deg; rim %.2f; seam r %.4f"
          % (R_IN, R_WALL, R_WALL_MID, math.degrees(HALF), FRAME_W, seam_r()))
    for name, r_h, r_f in leaves():
        _m, o, _r, w = leaf(r_h, r_f)
        hang = LEAF_T + w
        ok = ok and hang < PIT_D                             # clears the pit floor
        b0, b1 = hinge_span(r_h)
        print("%s hinge arc r %.3f over %.4f..%.4f deg, axis (chord) at r %.4f, free arc r %.4f; hangs to %.3f (pit %.2f)"
              % (name, r_h, math.degrees(b0), math.degrees(b1), o[0] + PIVOT_R, r_f, hang, PIT_D))
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


def build():
    objs = []
    for name, m, origin, rot in parts():
        ob = m.object(name)
        ob.location = origin
        ob.rotation_euler = (0.0, 0.0, rot)
        bpy.context.view_layer.update()
        tx.unwrap(ob, m.zones, SHEETS, seed=11, groups=m.groups, face_uv=m.face_uv)
        mats = tx.materials(NAME, SHEETS)
        for mat in mats.values():
            mat.diffuse_color = (0.78, 0.76, 0.72, 1.0)
        tx.finish(ob, m.zones, {z: mats[z] for z in set(m.zones)})
        # keep the first surface's class: Godot 4.7 drops vertex_color_use_as_albedo on a mesh's first
        # surface, so its tint rides as baseColorFactor (it rendered untinted: raw tile, iron as stone).
        vertex_ao.apply(ob, vertex_ao.bake(ob, dist=0.6), keep=(ob.data.materials[0].name,))
        print("MDL STATS %s tris=%d surfaces=%d origin=(%.4f,%.4f,%.4f) rot_z=%.4f"
              % (name, len(ob.data.polygons), len(ob.data.materials), origin[0], origin[1], origin[2],
                 math.degrees(rot)))
        objs.append(ob)
    tx.report(SHEETS)
    return objs


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW)
