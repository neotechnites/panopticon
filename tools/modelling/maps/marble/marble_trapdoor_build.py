"""
marble_trapdoor -- the walkway's trapdoor: an iron frame lining one lane cell's
hole (marble_build.TRAPDOOR_B, r 46.8..52.0, one 2.8125 deg station), two stone
leaves that drop on iron hinges, and iron spikes on the pit floor 1.4 m down.

ORIGIN: the deck point at r PIVOT_R on the hole's centre bearing, z 0 the deck.
Godot +X radial outward, +Z toward INCREASING bearing (Blender -Y).

    TrapdoorFrame   iron rim FRAME_W wide inside the hole, top flush, knuckles proud
    TrapdoorLeafA   the leaf on the phi = -delta side (Blender +Y); origin on its hinge
    TrapdoorLeafB   the leaf on the phi = +delta side (Blender -Y); origin on its hinge
    TrapdoorSpikes  a strip of iron spikes down the pit's middle, clear of the hanging leaves

Each leaf's ORIGIN sits on its hinge axis -- the hinge line's midpoint at the
leaf's BOTTOM arris (z -LEAF_T), so the slab swings clear of the frame -- and its
local frame is +X along the hinge, +Y up, +Z (Godot) toward the free edge: a
+90 deg turn about local X hangs it in the pit. No colliders: the scene makes them.

    python3 tools/modelling/maps/marble/marble_trapdoor_build.py --check
    tools/modelling/model build marble_trapdoor --pc
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
PIVOT_R = mb.DECK_RS[1]                 # 49.4: the prop's origin radius
R_IN, R_OUT = mb.DECK_RS[0], mb.DECK_RS[2]   # 46.8 .. 52.0: the hole the lane build cut
DELTA = math.radians(180.0 / (mb.NSIDE * mb.DECK_SUB))   # half a lane station: 1.40625 deg
PIT_D = mb.DECK_Z - mb.PIT_Z            # 1.4: the pit floor under the deck
FRAME_W = 0.10                          # the iron rim, inside the hole
FRAME_D = 0.30                          # ... this deep
FRAME_SKIN = 0.002                      # its outer faces held off the pit's own walls
LEAF_T = 0.15                           # the stone leaves' thickness
GAP = 0.005                             # each leaf this far off the meeting line (1 cm between)
STRAP_AT = (0.18, 0.82)                 # iron straps across each leaf, as fractions along the hinge
STRAP_W = 0.12
KNUCKLE_R = 0.04                        # hinge knuckles: proud of the frame by their radius
KNUCKLE_L = 0.30
KNUCKLE_AT = (0.15, 0.5, 0.85)
KNUCKLE_SIDES = 6
SPIKE_ROWS = (-0.25, 0.25)              # Blender y of the spike rows: clear of the hanging leaves
SPIKE_X = (-1.7, -1.0, -0.3, 0.4, 1.1, 1.8)
SPIKE_HW = 0.09
SPIKE_H = 0.75                          # tips at -1.4 + 0.75 = -0.65 under the deck
SPIKE_PLATE = 0.04

UP, DOWN = mb.UP, mb.DOWN

SHEETS = {
    "floor": mb.tile("floor", "marble_floor", "box", 64, 64, mpt=2.7 / 64.0),   # the paving's flags
    "shade": mb.shade_sheet("shade", mode="box"),
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


def hole():
    return _ccw([C(R_IN, -DELTA), C(R_OUT, -DELTA), C(R_OUT, DELTA), C(R_IN, DELTA)])


def _lerp(p, q, t):
    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)


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


def hinges():
    """(leaf, hinge start, hinge end, free-side unit normal in 2D) for both leaves."""
    inner = _offset(hole(), FRAME_W)
    out = []
    for leaf in ("A", "B"):
        # the frame's inner edge on this leaf's station line: its two inner corners on that side
        pts = sorted(inner, key=lambda p: -p[1] if leaf == "A" else p[1])[:2]
        pts.sort(key=lambda p: p[0])
        free = (0.0, -1.0) if leaf == "A" else (0.0, 1.0)
        out.append((leaf, pts[0], pts[1], free))
    return out


def frame():
    m = mb._Mesh()
    outer = _offset(hole(), FRAME_SKIN)
    inner = _offset(hole(), FRAME_W)
    _ring(m, outer, inner, 0.0, -FRAME_D, "iron")
    for _leaf, p, q, free in hinges():
        for t in KNUCKLE_AT:
            c = _lerp(p, q, t)
            L = math.hypot(q[0] - p[0], q[1] - p[1])
            d = ((q[0] - p[0]) / L, (q[1] - p[1]) / L)
            back = (c[0] - free[0] * 0.03, c[1] - free[1] * 0.03)    # sat on the frame's top
            a = (back[0] - d[0] * KNUCKLE_L / 2, back[1] - d[1] * KNUCKLE_L / 2, 0.0)
            b = (back[0] + d[0] * KNUCKLE_L / 2, back[1] + d[1] * KNUCKLE_L / 2, 0.0)
            _knuckle(m, a, b, "iron")
    return m


# =============================================================================
# THE LEAVES -- authored in the prop's frame, then moved into the hinge's own
# =============================================================================

def leaf_poly(leaf):
    """The leaf's top outline (Blender xy): the frame's inner opening on its side of the gap."""
    inner = _offset(hole(), FRAME_W)
    sign = 1.0 if leaf == "A" else -1.0
    # clip the opening to sign*y >= GAP
    out = []
    n = len(inner)
    for i in range(n):
        p, q = inner[i], inner[(i + 1) % n]
        fp, fq = sign * p[1] - GAP, sign * q[1] - GAP
        if fp >= 0.0:
            out.append(p)
        if (fp >= 0.0) != (fq >= 0.0):
            t = fp / (fp - fq)
            out.append(_lerp(p, q, t))
    return out


def leaf_frame(leaf):
    """(origin xyz, rotation_z) of the leaf's object: hinge midpoint at the bottom arris."""
    for name, p, q, _free in hinges():
        if name == leaf:
            mid = _lerp(p, q, 0.5)
            rot = DELTA if leaf == "A" else math.pi - DELTA
            return (mid[0], mid[1], -LEAF_T), rot
    raise KeyError(leaf)


def _to_local(pt, origin, rot):
    x, y, z = pt[0] - origin[0], pt[1] - origin[1], pt[2] - origin[2]
    c, s = math.cos(-rot), math.sin(-rot)
    return (x * c - y * s, x * s + y * c, z)


def leaf(leafname):
    """The slab in its hinge's local frame: local x along the hinge, free edge toward local -y."""
    origin, rot = leaf_frame(leafname)
    poly2 = leaf_poly(leafname)
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
    for k in range(len(cuts) - 1):
        zone_top = "iron" if k % 2 == 1 else "floor"
        zone_side = "iron" if k % 2 == 1 else "shade"
        a, b, c, d = H[k], H[k + 1], F[k + 1], F[k]
        T = [m.v((p[0], p[1], top)) for p in (a, b, c, d)]
        B = [m.v((p[0], p[1], bot)) for p in (a, b, c, d)]
        m.quad(T[0], T[1], T[2], T[3], UP, zone_top)
        m.quad(B[0], B[1], B[2], B[3], DOWN, "shade")
        m.quad(T[0], T[1], B[1], B[0], (0.0, 1.0, 0.0), zone_side)          # the hinge face
        e = (c[0] - d[0], c[1] - d[1])
        m.quad(T[3], T[2], B[2], B[3], (e[1], -e[0], 0.0), zone_side)       # the free edge
    for (a, d, out) in ((H[0], F[0], (-1.0, 0.0, 0.0)), (H[-1], F[-1], (1.0, 0.0, 0.0))):
        m.quad(m.v((a[0], a[1], top)), m.v((d[0], d[1], top)), m.v((d[0], d[1], bot)),
               m.v((a[0], a[1], bot)), out, "shade")
    width = max(abs(F[0][1]), abs(F[-1][1]))
    return m, origin, rot, width


# =============================================================================
# THE SPIKES
# =============================================================================

def spikes():
    m = mb._Mesh()
    z0 = -PIT_D
    for y in SPIKE_ROWS:
        for x in SPIKE_X:
            b = [m.v((x + sx * SPIKE_HW, y + sy * SPIKE_HW, z0 + 0.001))
                 for (sx, sy) in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            apex = m.v((x, y, z0 + SPIKE_H))
            m.quad(b[0], b[1], b[2], b[3], DOWN, "iron")
            for k in range(4):
                p, q = b[k], b[(k + 1) % 4]
                mx = 0.5 * (m.verts[p][0] + m.verts[q][0]) - x
                my = 0.5 * (m.verts[p][1] + m.verts[q][1]) - y
                m.tri(p, q, apex, (mx, my, 0.3), "iron")
    return m


# =============================================================================
# BUILD
# =============================================================================

def parts():
    out = [("TrapdoorFrame", frame(), (0.0, 0.0, 0.0), 0.0)]
    for name in ("A", "B"):
        m, origin, rot, _w = leaf(name)
        out.append(("TrapdoorLeaf" + name, m, origin, rot))
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
    for name in ("A", "B"):
        _m, _o, _r, w = leaf(name)
        hang = LEAF_T + w
        print("leaf %s width %.3f, hangs to %.3f (pit %.2f)" % (name, w, hang, PIT_D))
        ok = ok and hang < PIT_D
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
