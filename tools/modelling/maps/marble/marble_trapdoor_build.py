"""
marble_trapdoor -- the walkway's trapdoor, an ARC SECTOR of the ring: a rim lining the hole marble_build
cuts (TRAPDOOR_CELLS lane cells round a pier in TRAPDOOR_BEARINGS, DECK_RS[TRAPDOOR_IN_K] to the wall foot),
its inner and outer edges concentric with the lane and its sides radial; TWO stone flaps hinged on the
lane-side arcs that part at a seam arc and hang into the pit; spikes on the pit floor PIT_D down
(Ryan 2026-10-20: "only two flaps ... make the pit much deeper"; 2026-10-25: "they don't fit on the ring
because they are rectangles").

CLOSED, THE TRAPDOOR IS A PIECE OF THE FLOOR (Ryan 2026-10-25: "the trap doors have hard black lines
through them, get rid of that"; "the color on the trap doors does not match the rest of the floor"): the
rim's top and both flaps wear the deck's own flags -- the floor tile on the lane's cell grid, the deck's
COLOR_0 (TINT_FLOOR x marble_build.weight(DECK_Z), the value the deck carries at y 23) on the same
COLOR_0 path, so there is no tint, no path and no AO between a flap and the cell beside it; from OUTER_R
(57.3) to the wall the deck is its margin, the brick at the wall's value, and the outer flap's last band
and the wall rim continue that ("margin", the deck's own cyl mapping). No iron shows
from above: the straps, the knuckles and the iron seam lips are gone; the seam between the flaps sits ON
the tile's own joint row (SEAM_V), so the two flaps draw one joint of the lane's weight with the 1 cm gap
in its dark core; the rim's top is the first texels of the deck's flags, its joints the lane's. The iron
("edge", near-black) is the rim's skin and the flaps' undersides and edges: it shows only when the pit is
open.

ORIGIN: the deck point at r PIVOT_R (mid-hole) on the hole's centre bearing, z 0 the deck.
Godot +X radial outward, +Z toward INCREASING bearing (Blender -Y).

    TrapdoorFrame   the rim inside the hole, its top the deck's flags, its skin iron: its outer edge the cut itself, its inner edge two arcs and two radial sides
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
FRAME_W = 0.28                          # the rim inside the hole at the lip and the radial sides
FRAME_W_WALL = 0.40                     # ... and at the wall: wider, so the outer flap hinged on it clears the pit floor
#                                         with the seam on the lane's joint (0.28 left it 4 cm into the floor)
FRAME_D = 0.35                          # the rim this deep
FRAME_SKIN = 0.002                      # its outer faces lean in by this from the top edge to the bottom
LEAF_T = 0.15                           # the stone leaves' thickness
GAP = 0.005                             # each flap this far off the seam (1 cm between)
SEAM_V = 43.0 / 64.0                    # the seam arc on the floor tile's second joint row (rows 42-43 of 64 are its
#                                         dark core): the flaps' free edges meet in the deck's own joint
SPIKE_PITCH = 0.9                       # the floor grid, radial and along the lane
SPIKE_MARGIN = 0.45                     # the grid stops this short of the hinge axes: the hanging flaps clear it
SPIKE_HW = 0.09
SPIKE_H = (0.85, 1.1)                   # pale stone, tips PIT_D-1.1 .. PIT_D-0.85 under the deck
LEAF_TINT = tuple(c * mb.weight(mb.DECK_Z) for c in mb.TINT_FLOOR)   # the deck's COLOR_0 at y 23: TINT_FLOOR x 0.93 (0.9263, 0.9030, 0.7905)

R_HINGE_IN = R_IN + FRAME_W             # 48.33: the inner flap's hinge arc
R_HINGE_OUT = R_WALL_MID - FRAME_W_WALL # 59.528: the outer flap's hinge arc (the rim 0.40 at a bay's middle, 0.47 at its corners)
RINGS = tuple(mb.DECK_RS[mb.TRAPDOOR_IN_K:]) + (R_WALL_MID,)   # the lane's paving rings over the hole; the margin one more
CENTRE = (-PIVOT_R, 0.0)                # the ring's axis in the prop's frame

UP, DOWN = mb.UP, mb.DOWN

# "edge" sorts before "floor": Godot 4.7 drops vertex_color_use_as_albedo on a mesh's FIRST surface (its tint
# rides as baseColorFactor instead), so the iron takes that slot and the flags ride COLOR_0 exactly as the deck's.
MARGIN_TINT = tuple(c * mb.weight(mb.DECK_Z) for c in mb.TINT_WALL)   # the deck's margin Col at y 23: TINT_WALL x 0.93 (0.6863, 0.6770, 0.5729)
MARGIN_R = mb.OUTER_R                   # 57.3: from here to the wall the deck is its MARGIN, the brick at the wall's value
#                                         (marble_lane_build._margin, class marble2), not the paving -- the trapdoor continues it
MARGIN_REF_R = mb.WALL_R                # the margin's bricks are measured on the wall ring (marble_build._wall_ref)
MARGIN_BEARING_REF = 90.0               # the brick's world phase is stated for a Section A door (67.5 + 22.5 k all share it:
#                                         22.5 deg is two of its 2-bay repeats); Section B's doors sit one bay off, one of the
#                                         tile's two alike bays
SHEETS = {
    "edge": mb.stone("edge", mode="box", tint=mb.TINT_IRON),
    "floor": mb.tile("floor", "marble_floor", "custom", 64, 64, mpt=2.7 / 64.0, tint=LEAF_TINT),
    "margin": tx.Sheet("margin", mode="custom", mpt=mb.COURSE_MPT, mpt_u=mb.WALL_MPT, size=mb.BRICK_H, width=mb.BRICK_W,
                       ref_r=MARGIN_REF_R, phase=(0.0, mb.FLOOR_Z), roughness=mb.ROUGHNESS, stem="marble_brick", tint=MARGIN_TINT),
    "spike": mb.stone("spike", mode="box", mpt=tx.MPT, tint=mb.TINT_SPIKE),
}
RING_MIDS = tuple(r for r in RINGS if R_IN < r < R_WALL_MID)   # 52.0, 54.6, 57.3: where the rim's side strips break


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
    the chord at R_WALL_MID), radial sides broken at the lane's rings (the rim's top is a strip of the
    deck's flags, one quad per cell and ring)."""
    lip = [C(R_IN, k * STEP) for k in range(-HALF_CELLS, HALF_CELLS + 1)]
    wall = [C(R_WALL if k % 2 == 0 else R_WALL_MID, k * STEP) for k in range(-HALF_CELLS, HALF_CELLS + 1)]
    side_hi = [C(r, HALF) for r in RING_MIDS]
    side_lo = [C(r, -HALF) for r in reversed(RING_MIDS)]
    poly = lip + side_hi + list(reversed(wall)) + side_lo
    assert _area(poly) > 0.0
    return poly


def inner_polyline():
    """The rim's inner boundary, one vertex per hole() vertex: the lip arc at R_HINGE_IN, the wall arc at
    R_HINGE_OUT, both on the station polyline, their ends on the moved-in sides, which break at the rings."""
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

    side_hi = [arc_pt(hi, r) for r in RING_MIDS]
    side_lo = [arc_pt(lo, r) for r in reversed(RING_MIDS)]
    return arc(R_HINGE_IN) + side_hi + list(reversed(arc(R_HINGE_OUT))) + side_lo


def _reach(r_h, r_f):
    """How far a flap's free arc stands from its hinge axis (the chord), at its farthest point."""
    lo, hi = end_lines()
    x_axis = arc_pt(lo, r_h)[0]
    pts = [arc_pt(lo, r_f), arc_pt(hi, r_f)] + [C(r_f, k * STEP) for k in range(-HALF_CELLS + 1, HALF_CELLS)]
    return max(abs(p[0] - x_axis) for p in pts)


def seam_r():
    """The seam arc's radius: the floor tile's joint row SEAM_V up the paving ring the hole's middle sits in,
    so the flaps' free edges meet in a joint of the deck's own grid."""
    for a, b in zip(RINGS, RINGS[1:]):
        if a <= PIVOT_R < b:
            return a + SEAM_V * (b - a)
    raise ValueError("the hole's middle is off the lane's rings")


def leaves():
    """(name, hinge radius, free radius) for the two flaps."""
    rs = seam_r()
    return [("TrapdoorLeaf00", R_HINGE_IN, rs - GAP), ("TrapdoorLeaf01", R_HINGE_OUT, rs + GAP)]


# =============================================================================
# THE FLAGS -- the deck's own tile windows, stated per vertex
# =============================================================================

def _ring_of(r):
    for a, b in zip(RINGS, RINGS[1:]):
        if a - 1e-9 <= r <= b + 1e-9:
            return a, b
    raise ValueError("r %.3f is off the lane's rings" % r)


def _radius(p):
    return math.hypot(p[0] - CENTRE[0], p[1] - CENTRE[1])


def _flag_uv(p, r_nom, cell, ring):
    """The deck's own 'fit' window: u across the lane cell by bearing, v up the ring by radius."""
    th = -bearing(p)                                   # Blender angle, the deck's u direction
    return ((th - cell * STEP) / STEP, (r_nom - ring[0]) / (ring[1] - ring[0]))


def _margin_uv(p, r_nom):
    """The deck's margin: texel.cyl_uv for a floor face on the wall ring -- u the arc at MARGIN_REF_R in whole
    repeats round the ring (the sheet's own closure), v the radius from FLOOR_Z in courses."""
    sheet = SHEETS["margin"]
    ref, period_u, _n = sheet.ring((MARGIN_REF_R, 0.0, 0.0))     # (60, 11.781 m, 32 repeats), as the deck's
    th = math.radians(-MARGIN_BEARING_REF) - bearing(p)      # the point's Blender angle in the world (a Section A door)
    return ((th * ref - sheet.phase[0]) / period_u, (r_nom - sheet.phase[1]) / sheet.metres)


def _flag_quad(m, V, A, B, Cc, D, rA, rB, rC, rD):
    """One quad of the deck's top, its UVs stated per vertex: the paving's flags on the cell and ring the quad's
    middle falls in, or the margin's bricks from MARGIN_R out. V maps a 2D point to a top vertex; rA..rD are
    the corners' nominal radii."""
    mid = _lerp(_lerp(A, B, 0.5), _lerp(D, Cc, 0.5), 0.5)
    if _radius(mid) >= MARGIN_R:
        uv = {V(A): _margin_uv(A, rA), V(B): _margin_uv(B, rB), V(Cc): _margin_uv(Cc, rC), V(D): _margin_uv(D, rD)}
        m.quad(V(A), V(B), V(Cc), V(D), UP, "margin", uv=uv)
        return
    cell = int(math.floor(-bearing(mid) / STEP))
    ring = _ring_of(min(max(_radius(mid), RINGS[0]), RINGS[-1]))
    uv = {V(A): _flag_uv(A, rA, cell, ring), V(B): _flag_uv(B, rB, cell, ring),
          V(Cc): _flag_uv(Cc, rC, cell, ring), V(D): _flag_uv(D, rD, cell, ring)}
    m.quad(V(A), V(B), V(Cc), V(D), UP, "floor", uv=uv)


# =============================================================================
# THE FRAME -- a rim whose top is the deck's flags and whose skin is iron
# =============================================================================

def _ring(m, outer_top, outer_bot, inner, z_top, z_bot):
    """The rim between two closed polylines: its top the deck's flags, its skin, inner faces and underside iron."""
    n = len(outer_top)
    o0 = [m.v((p[0], p[1], z_top)) for p in outer_top]
    i0 = [m.v((p[0], p[1], z_top)) for p in inner]
    o1 = [m.v((p[0], p[1], z_bot)) for p in outer_bot]
    i1 = [m.v((p[0], p[1], z_bot)) for p in inner]
    for k in range(n):
        j = (k + 1) % n
        A, B, Cc, D = outer_top[k], outer_top[j], inner[j], inner[k]
        _flag_quad(m, lambda p: m.v((p[0], p[1], z_top)), A, B, Cc, D,
                   _radius(A), _radius(B), _radius(Cc), _radius(D))
        m.quad(o1[k], o1[j], i1[j], i1[k], DOWN, "edge")
        e = (outer_top[j][0] - outer_top[k][0], outer_top[j][1] - outer_top[k][1])
        out = (e[1], -e[0], 0.0)                     # outward of a CCW edge
        m.quad(o0[k], o0[j], o1[j], o1[k], out, "edge")
        m.quad(i0[k], i0[j], i1[j], i1[k], (-out[0], -out[1], 0.0), "edge")


def frame():
    m = mb._Mesh()
    outer = hole()
    _ring(m, outer, _shrink(outer, FRAME_SKIN), inner_polyline(), 0.0, -FRAME_D)
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
    """The flap's side lines in bearing order: the moved-in ends and the lane's stations (the flags break
    there, as the deck's do)."""
    lo_e, hi_e = end_lines()
    lines = [lo_e, hi_e] + [radial(k * STEP) for k in range(-HALF_CELLS + 1, HALF_CELLS)]
    r_mid = 0.5 * (R_HINGE_IN + R_HINGE_OUT)
    lines.sort(key=lambda ln: bearing(on_circle(ln, r_mid)))
    return lines


def bands(r_h, r_f):
    """Radii across the flap from the hinge to the free edge: the lane's rings break the flags."""
    rs = {r_h, r_f} | {r for r in RINGS if min(r_h, r_f) < r < max(r_h, r_f)}
    rs = sorted(rs, reverse=r_f < r_h)
    return list(zip(rs, rs[1:]))


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
    for la, lb in zip(lines, lines[1:]):
        # the top, one flag quad per band
        for (ra, rb) in bds:
            A, B, Cc, D = arc_pt(la, ra), arc_pt(lb, ra), arc_pt(lb, rb), arc_pt(la, rb)
            _flag_quad(m, lambda p: V(p, top), A, B, Cc, D, ra, ra, rb, rb)
        # the underside, the hinge face and the free face, one quad each per strip
        H0, H1, F0, F1 = arc_pt(la, r_h), arc_pt(lb, r_h), arc_pt(la, r_f), arc_pt(lb, r_f)
        m.quad(V(H0, bot), V(H1, bot), V(F1, bot), V(F0, bot), DOWN, "edge")
        phi = bearing(_lerp(H0, H1, 0.5))
        rad = (math.cos(phi), -math.sin(phi), 0.0)
        m.quad(V(H0, top), V(H1, top), V(H1, bot), V(H0, bot), W(tuple(-outward * c for c in rad)), "edge")
        m.quad(V(F0, top), V(F1, top), V(F1, bot), V(F0, bot), W(tuple(outward * c for c in rad)), "edge")
    # the two ends: the top edge carries every band's vertex
    for line, want in ((lines[0], (0.0, 1.0, 0.0)), (lines[-1], (0.0, -1.0, 0.0))):
        ring = [V(arc_pt(line, r_f), bot), V(arc_pt(line, r_h), bot), V(arc_pt(line, r_h), top)]
        ring += [V(arc_pt(line, rb), top) for (_ra, rb) in bds]
        m.poly(ring, W(want), "edge")
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
    print("hole: lip r %.3f, wall r %.3f (%.3f at a bay's middle), sides +-%.4f deg; rim %.2f (%.2f at the wall); "
          "seam r %.4f (tile row %.1f of 64 up ring %s)"
          % (R_IN, R_WALL, R_WALL_MID, math.degrees(HALF), FRAME_W, FRAME_W_WALL, seam_r(), SEAM_V * 64.0, _ring_of(seam_r())))
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
        # keep the first surface's class ("edge" where there is one, the spikes' own): Godot 4.7 drops
        # vertex_color_use_as_albedo on a mesh's first surface, so its tint rides as baseColorFactor. The
        # flags take COLOR_0 = LEAF_TINT x 1.0 -- the deck's own Col, no contact shade (the deck's flags
        # carry none either): only the iron darkens in its corners.
        vertex_ao.apply(ob, vertex_ao.bake(ob, dist=0.6), keep=(ob.data.materials[0].name,), only=("edge",))
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
