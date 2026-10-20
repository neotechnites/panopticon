"""
marble_trapdoor -- the walkway's trapdoor: an iron frame lining the hole marble_build cuts
(TRAPDOOR_CELLS lane cells round a pier in TRAPDOOR_BEARINGS, r 49.4 to wall foot), TWO stone flaps
hinged on the hole's lane-side edges (the lip chord and the wall chord) that part at a seam along the
lane and hang into the pit, spikes on the pit floor PIT_D down (Ryan 2026-10-20: "only two flaps,
you can make the pit much deeper for them to have a place to fold down into"). The pit is stepped: the lower tier's
cells are recessed to r 50.15 under the hole's inner band, so that band is a 1.4 m ledge and only the band from
SHAFT_R (52.0) out is the 10.4 m shaft; the inner flap is INNER_W wide and hangs into the ledge, the outer flap into the shaft.

ORIGIN: the deck point at r PIVOT_R (mid-hole) on the hole's centre bearing, z 0 the deck.
Godot +X radial outward, +Z toward INCREASING bearing (Blender -Y).

    TrapdoorFrame   iron rim inside the hole, its lane sides straight chords, top flush, knuckles proud
    TrapdoorLeaf00  the inner flap, hinged on the lip chord;  TrapdoorLeaf01  the outer, on the wall chord
    TrapdoorSpikes  a grid of pale spikes on both pit floors, clear of the hanging flaps

Each flap's ORIGIN sits on its hinge axis -- the hinge line's midpoint at the
flap's BOTTOM arris (z -LEAF_T), so the slab swings clear of the rim -- and its
local frame is +X along the hinge, +Y up, +Z (Godot) toward the free edge: a
+90 deg turn about local X hangs it in the pit. No colliders: the scene makes them.

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
PIVOT_R = mb.TRAPDOOR_R                 # 54.664: the prop's origin radius, mid-hole
R_IN = mb.DECK_RS[mb.TRAPDOOR_IN_K]     # 49.4: the hole's inner side; its outer side is the wall foot
STEP = math.radians(360.0 / (mb.NSIDE * mb.DECK_SUB))   # one lane cell: 2.8125 deg
HALF_CELLS = mb.TRAPDOOR_CELLS // 2
PIT_D = mb.DECK_Z - mb.PIT_Z            # 1.4: the inner LEDGE under the deck (the lower tier's cells are recessed to r 50.15 under it)
SHAFT_D = mb.DECK_Z - mb.SHAFT_Z        # 10.4: the shaft from SHAFT_R out, room for the outer flap to hang
INNER_W = 1.15                          # the inner flap, hinged on the lip chord: hangs into the ledge, clear of the cells below
FRAME_W = 0.28                          # the iron rim, inside the hole, at its narrowest: reads from 15 m
FRAME_D = 0.35                          # ... this deep
FRAME_SKIN = 0.002                      # its outer faces held off the pit's own walls
LEAF_T = 0.15                           # the stone leaves' thickness
GAP = 0.005                             # each flap this far off the seam (1 cm between)
STRAP_AT = (0.1, 0.3, 0.5, 0.7, 0.9)    # heavy strap hinges across each flap, fractions along the hinge
STRAP_W = 0.30
SEAM_W = 0.07                           # an iron lip on each free edge: the seams read dark
KNUCKLE_R = 0.07                        # hinge knuckles: proud of the beam by their radius
KNUCKLE_L = 0.50
KNUCKLE_AT = STRAP_AT                   # one knuckle at each strap
KNUCKLE_SIDES = 6
SPIKE_PITCH = 0.9                       # the floor grid, radial and along the lane
SPIKE_MARGIN = 0.45                     # the grid stops this short of the rim: the hanging flaps clear it
SPIKE_HW = 0.09
SPIKE_H = (0.85, 1.1)                   # pale stone, tips PIT_D-1.1 .. PIT_D-0.85 under the deck
LEAF_TINT = (0.62, 0.58, 0.53)          # the leaves' flags darker and worn against the deck's
SPIKE_PLATE = 0.04

UP, DOWN = mb.UP, mb.DOWN

SHEETS = {
    "floor": mb.tile("floor", "marble_floor", "box", 64, 64, mpt=2.7 / 64.0, tint=LEAF_TINT),
    "spike": mb.stone("spike", mode="box", mpt=tx.MPT),
    "iron": mb.iron_sheet(),
}


# =============================================================================
# 2D HELPERS (Blender x, y in the prop's frame)
# =============================================================================

def C(r, phi):
    """Radius r at relative game bearing phi (radians) -> Blender (x, y)."""
    return (r * math.cos(phi) - PIVOT_R, -r * math.sin(phi))


def _line(p, q):
    return p, (q[0] - p[0], q[1] - p[1])


def _meet(l1, l2):
    (p, d), (q, e) = l1, l2
    den = d[0] * e[1] - d[1] * e[0]
    t = ((q[0] - p[0]) * e[1] - (q[1] - p[1]) * e[0]) / den
    return (p[0] + d[0] * t, p[1] + d[1] * t)


def _offset(poly, w):
    """Convex CCW polygon moved in by w on every edge."""
    n = len(poly)
    lines = []
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        dx, dy = q[0] - p[0], q[1] - p[1]
        L = math.hypot(dx, dy)
        nx, ny = -dy / L, dx / L                      # inward for CCW
        lines.append(((p[0] + nx * w, p[1] + ny * w), (dx, dy)))
    return [_meet(lines[i - 1], lines[i]) for i in range(n)]


def _ccw(poly):
    a = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
            for i in range(len(poly)))
    return poly if a > 0 else list(reversed(poly))


def tangent(phi):
    """Unit Blender xy toward increasing bearing at relative bearing phi."""
    return (-math.sin(phi), -math.cos(phi))


def hole():
    """The cut: lip chords on every lane station, wall chords on every bay corner (CCW)."""
    lip = [C(R_IN, k * STEP) for k in range(-HALF_CELLS, HALF_CELLS + 1)]
    wall = [C(mb.WALL_R, k * STEP) for k in range(-HALF_CELLS, HALF_CELLS + 1, 2)]
    return _ccw(lip + list(reversed(wall)))


def _end_line(side):
    """The hole's radial end on `side` (-1: lower bearing, +1: higher), moved FRAME_W into the hole:
    (point, unit direction outward)."""
    phi = side * HALF_CELLS * STEP
    tg = tangent(phi)
    o = C(PIVOT_R, phi)
    off = -side * FRAME_W
    return (o[0] + tg[0] * off, o[1] + tg[1] * off), (math.cos(phi), -math.sin(phi))


def _lerp(p, q, t):
    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)


def _at_x(line, x):
    """Where (point, direction) crosses the Blender x = const line."""
    (p, d) = line
    tt = (x - p[0]) / d[0]
    return (x, p[1] + d[1] * tt)


def chords():
    """The rim's inner boundary on the lane sides, straight: x of the lip chord and of the wall chord.
    The lip chord sits FRAME_W inside the lip's middle station, the wall chord FRAME_W inside the wall's
    bay corners, so the rim is never narrower than FRAME_W and both hinges are straight lines."""
    x_lip = C(R_IN, 0.0)[0] + FRAME_W
    x_wall = C(mb.WALL_R, HALF_CELLS * STEP)[0] - FRAME_W
    return x_lip, x_wall


def inner_quad():
    """The rim's inner boundary: lip corners (-, +) and wall corners (+, -), CCW."""
    x_lip, x_wall = chords()
    lo, hi = _end_line(-1), _end_line(1)
    return [_at_x(lo, x_lip), _at_x(hi, x_lip), _at_x(hi, x_wall), _at_x(lo, x_wall)]


def inner_polyline(outer):
    """The rim's inner boundary with one vertex per outer vertex (for _ring): lip-side vertices on the lip
    chord, wall-side ones on the wall chord, each side's end vertices where its chord meets the moved-in ends."""
    x_lip, x_wall = chords()
    lip_end = max(abs(y) for (x, y) in outer if x < 0.0)
    wall_end = max(abs(y) for (x, y) in outer if x >= 0.0)
    out = []
    for (x, y) in outer:
        side = -1 if y > 0.0 else 1              # Blender -y is increasing bearing
        if x < 0.0:
            out.append(_at_x(_end_line(side), x_lip) if abs(y) > lip_end - 1e-6 else (x_lip, y))
        else:
            out.append(_at_x(_end_line(side), x_wall) if abs(y) > wall_end - 1e-6 else (x_wall, y))
    return out


def leaves():
    """(name, [hinge a, hinge b, free b, free a]) for the two flaps: the inner hinged on the lip chord, INNER_W wide
    (it hangs into the ledge over the cells' crowns), the outer on the wall chord, both free edges GAP off the seam."""
    x_lip, x_wall = chords()
    x_mid = x_lip + INNER_W
    lo, hi = _end_line(-1), _end_line(1)
    inner = [_at_x(lo, x_lip), _at_x(hi, x_lip), _at_x(hi, x_mid - GAP), _at_x(lo, x_mid - GAP)]
    outer = [_at_x(hi, x_wall), _at_x(lo, x_wall), _at_x(lo, x_mid + GAP), _at_x(hi, x_mid + GAP)]
    return [("TrapdoorLeaf00", inner), ("TrapdoorLeaf01", outer)]


# =============================================================================
# THE FRAME
# =============================================================================

def _ring(m, outer, inner, z_top, z_bot, zone):
    n = len(outer)
    o0 = [m.v((p[0], p[1], z_top)) for p in outer]
    i0 = [m.v((p[0], p[1], z_top)) for p in inner]
    o1 = [m.v((p[0], p[1], z_bot)) for p in outer]
    i1 = [m.v((p[0], p[1], z_bot)) for p in inner]
    for k in range(n):
        j = (k + 1) % n
        m.quad(o0[k], o0[j], i0[j], i0[k], UP, zone)
        m.quad(o1[k], o1[j], i1[j], i1[k], DOWN, zone)
        e = (outer[j][0] - outer[k][0], outer[j][1] - outer[k][1])
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


def _box(m, quad2, z_top, z_bot, zone):
    """A closed vertical prism over a 2D quad."""
    pts = _ccw(list(quad2))
    t = [m.v((p[0], p[1], z_top)) for p in pts]
    b = [m.v((p[0], p[1], z_bot)) for p in pts]
    m.quad(t[0], t[1], t[2], t[3], UP, zone)
    m.quad(b[0], b[1], b[2], b[3], DOWN, zone)
    for k in range(4):
        j = (k + 1) % 4
        e = (pts[j][0] - pts[k][0], pts[j][1] - pts[k][1])
        m.quad(t[k], t[j], b[j], b[k], (e[1], -e[0], 0.0), zone)


def frame():
    m = mb._Mesh()
    outer = _offset(hole(), FRAME_SKIN)
    inner = inner_polyline(outer)
    _ring(m, outer, inner, 0.0, -FRAME_D, "iron")
    for _name, (h0, h1, f1, f0) in leaves():
        L = math.hypot(h1[0] - h0[0], h1[1] - h0[1])
        d = ((h1[0] - h0[0]) / L, (h1[1] - h0[1]) / L)
        fm, hm = _lerp(f0, f1, 0.5), _lerp(h0, h1, 0.5)
        bl = math.hypot(hm[0] - fm[0], hm[1] - fm[1])
        back = ((hm[0] - fm[0]) / bl, (hm[1] - fm[1]) / bl)          # away from the free edge, onto the rim
        for k in KNUCKLE_AT:
            c = _lerp(h0, h1, k)
            sat = (c[0] + back[0] * 0.03, c[1] + back[1] * 0.03)
            a = (sat[0] - d[0] * KNUCKLE_L / 2, sat[1] - d[1] * KNUCKLE_L / 2, 0.0)
            b = (sat[0] + d[0] * KNUCKLE_L / 2, sat[1] + d[1] * KNUCKLE_L / 2, 0.0)
            _knuckle(m, a, b, "iron")
    return m


# =============================================================================
# THE LEAVES -- authored in the prop's frame, then moved into the hinge's own
# =============================================================================

def leaf_frame(poly):
    """(origin xyz, rotation_z) of a flap's object: hinge midpoint at the bottom arris, local x along the
    hinge, the free edge at local -y."""
    h0, h1, _f1, f0 = poly
    mid = _lerp(h0, h1, 0.5)
    rot = math.atan2(h1[1] - h0[1], h1[0] - h0[0])
    if _to_local((f0[0], f0[1], 0.0), (mid[0], mid[1], 0.0), rot)[1] > 0.0:
        rot += math.pi
    return (mid[0], mid[1], -LEAF_T), rot


def _to_local(pt, origin, rot):
    x, y, z = pt[0] - origin[0], pt[1] - origin[1], pt[2] - origin[2]
    c, s = math.cos(-rot), math.sin(-rot)
    return (x * c - y * s, x * s + y * c, z)


def leaf(poly2):
    """The slab in its hinge's local frame: local x along the hinge, free edge toward local -y."""
    origin, rot = leaf_frame(poly2)
    loc = [_to_local((p[0], p[1], 0.0), origin, rot) for p in poly2]
    # hinge edge: the two points with local y ~ 0 (the bottom arris is at local z 0, top at LEAF_T)
    hx = sorted([p for p in loc if abs(p[1]) < 1e-6], key=lambda p: p[0])
    fx = sorted([p for p in loc if abs(p[1]) >= 1e-6], key=lambda p: p[0])
    assert len(hx) == 2 and len(fx) == 2, (hx, fx)
    h0, h1, f0, f1 = hx[0], hx[1], fx[0], fx[1]
    L = h1[0] - h0[0]
    cuts = [0.0]
    for t in STRAP_AT:
        cuts += [t - STRAP_W / 2.0 / L, t + STRAP_W / 2.0 / L]
    cuts.append(1.0)

    def hinge_at(t):
        return (h0[0] + (h1[0] - h0[0]) * t, 0.0)

    def free_at(t):
        x = h0[0] + (h1[0] - h0[0]) * t                # the same local x on the free edge
        u = (x - f0[0]) / (f1[0] - f0[0])
        return (x, f0[1] + (f1[1] - f0[1]) * u)

    m = mb._Mesh()
    top, bot = LEAF_T, 0.0
    H = [hinge_at(t) for t in cuts]
    F = [free_at(t) for t in cuts]
    S = [(f[0], f[1] + SEAM_W) for f in F]          # the seam lip's inner line (free edge is local -y)
    for k in range(len(cuts) - 1):
        zone_top = "iron" if k % 2 == 1 else "floor"
        a, b, c, d = H[k], H[k + 1], F[k + 1], F[k]
        sb, sa = S[k + 1], S[k]
        T = [m.v((p[0], p[1], top)) for p in (a, b, c, d)]
        Ts = [m.v((p[0], p[1], top)) for p in (sb, sa)]
        B = [m.v((p[0], p[1], bot)) for p in (a, b, c, d)]
        m.quad(T[0], T[1], Ts[0], Ts[1], UP, zone_top)
        m.quad(Ts[1], Ts[0], T[2], T[3], UP, "iron")
        m.quad(B[0], B[1], B[2], B[3], DOWN, "iron")
        m.quad(T[0], T[1], B[1], B[0], (0.0, 1.0, 0.0), "iron")          # the hinge face
        e = (c[0] - d[0], c[1] - d[1])
        m.quad(T[3], T[2], B[2], B[3], (e[1], -e[0], 0.0), "iron")       # the free edge
    for (a, sa, d, out) in ((H[0], S[0], F[0], (-1.0, 0.0, 0.0)), (H[-1], S[-1], F[-1], (1.0, 0.0, 0.0))):
        m.poly([m.v((d[0], d[1], bot)), m.v((a[0], a[1], bot)), m.v((a[0], a[1], top)),
                m.v((sa[0], sa[1], top)), m.v((d[0], d[1], top))], out, "iron")
    width = max(abs(F[0][1]), abs(F[-1][1]))
    return m, origin, rot, width


# =============================================================================
# THE SPIKES
# =============================================================================

def spikes():
    """Pale stone spikes on a SPIKE_PITCH grid over both pit floors (the ledge at -PIT_D in to SHAFT_R, the shaft
    at -SHAFT_D from it), SPIKE_MARGIN in from the rim and the step (the hanging flaps clear them), heights from a fixed stream."""
    m = mb._Mesh()
    r = mb._Rng(7711)
    x_lip, x_wall = chords()
    x_step = C(mb.SHAFT_R, 0.0)[0]
    lo, hi = _end_line(-1), _end_line(1)
    for (xa, xb, z0) in ((x_lip + SPIKE_MARGIN, x_step - 0.3, -PIT_D), (x_step + 0.3, x_wall - SPIKE_MARGIN, -SHAFT_D)):
        nx = max(1, int((xb - xa) / SPIKE_PITCH))
        for i in range(nx + 1):
            x = xa + (xb - xa) * (i / float(nx))
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
    for name, poly in leaves():
        m, origin, rot, _w = leaf(poly)
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
    for name, poly in leaves():
        _m, _o, _r, w = leaf(poly)
        hang = LEAF_T + w
        depth = PIT_D if name.endswith("00") else SHAFT_D   # the inner flap hangs into the ledge, the outer into the shaft
        ok = ok and hang < depth
        print("%s width %.3f, hangs to %.3f (floor %.2f)" % (name, w, hang, depth))
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


def build():
    objs = []
    for name, m, origin, rot in parts():
        ob = m.object(name)
        ob.location = origin
        ob.rotation_euler = (0.0, 0.0, rot)
        bpy.context.view_layer.update()
        tx.unwrap(ob, m.zones, SHEETS, seed=11, groups=m.groups)
        mats = tx.materials(NAME, SHEETS)
        for mat in mats.values():
            mat.diffuse_color = (0.78, 0.76, 0.72, 1.0)
        tx.finish(ob, m.zones, {z: mats[z] for z in set(m.zones)})
        vertex_ao.apply(ob, vertex_ao.bake(ob, dist=0.6))
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
