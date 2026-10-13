"""
marble_wall_arc -- a placeable ashlar wall CURVED with the lane: both faces concentric with the
ring at RADIUS, ARC_DEG wide, HEIGHT tall, THICKNESS thick. A plain-ashlar socle and end piers
(proud PROUD) hide the cut blocks, the brick between them runs in whole courses at the map's own
density, and a fluted cap (the tier cornices' band) closes the top.

ORIGIN: the base centre on the arc's mid bearing at RADIUS, z 0 the deck; Godot +X radial out,
+Z toward increasing bearing (Blender -Y). In the scene: rows (cos b, 0, -sin b | 0 1 0 | sin b,
0, cos b), origin (R cos b, 23, R sin b). VARIANTS name the sizes; `--variant lane` builds one.

    python3 tools/modelling/maps/marble/marble_wall_arc_build.py --check [--variant lane]
    tools/modelling/model build marble_wall_arc --pc [--variant lane]
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
    mdl.DEFAULTS["views"] = ["threequarter", "front"]
    mdl.DEFAULTS["ground"] = True

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "marble_wall_arc"
FACING_YAW = 0.0
VARIANTS = {
    "": dict(radius=47.3, arc_deg=11.4, height=7.6, thickness=0.75),       # the lip wall: a 9.4 m slab
    "long": dict(radius=47.3, arc_deg=19.7, height=7.6, thickness=0.75),   # ... the 16.2 m one
    "lane": dict(radius=51.45, arc_deg=11.25, height=4.6, thickness=0.75), # the sections' screen: 4 lane cells
}
SOCLE_H = 1.0               # plain ashlar, proud PROUD, the foot of the brick
PROUD = 0.10                # socle and end piers, both faces
PIER_W = 0.60               # each end pier, along the arc
CAP_H = 0.60                # the cap: CAP_EDGE of upright flutes, then a wash to the top
CAP_EDGE = 0.40
CAP_PROUD = 0.25
WASH_IN = 0.12
SEG_DEG = 1.0               # a station at most this far apart: 7 mm of sag at r 47
BRICK_UNIT = 3.0            # the brick tile's strong joints: a body of whole units ends on one
BRICK_JOINT_V = 0.08203     # that joint in the tile (row 235 of 256): the brick's foot lands on it
BAND_M = mb.COL_H * tx.MPT  # the cap's flutes repeat along the arc every 6.4 m, as the cornices'

UP, DOWN = mb.UP, mb.DOWN


def variant():
    """`--variant x` from argv (the check), else the build spec's."""
    if "--variant" in sys.argv:
        return sys.argv[sys.argv.index("--variant") + 1]
    if bpy is not None:
        return mdl.spec().get("variant", "") or ""
    return ""


def sheets(R):
    """The brick at the map's density, phased so the body's foot and top land on strong joints."""
    v0 = SOCLE_H - BRICK_JOINT_V * mb.COURSES
    return {
        "marble": mb.brick("marble", ref_r=R, phase=(0.0, v0)),
        "plinth": mb.brick("plinth", mpt_v=mb.COURSE_MPT / 2.0, tint=mb.TINT_PLINTH_WALL, ref_r=R,
                           phase=(0.0, SOCLE_H - 0.582 * mb.COURSES / 2.0)),
        "shade": mb.brick("shade", tint=mb.TINT_SHADE, ref_r=R, phase=(0.0, v0)),
        "band": mb.tile("band", "marble_column", "custom", mb.COL_W, mb.COL_H),
    }


class _Arc(object):
    """One wall's radii, heights and station angles (Blender radians, the mid bearing at 0)."""

    def __init__(self, p):
        self.R, self.T, self.H = p["radius"], p["thickness"], p["height"]
        self.A = math.radians(p["arc_deg"])
        self.ri, self.ro = self.R - self.T / 2.0, self.R + self.T / 2.0
        self.rip, self.rop = self.ri - PROUD, self.ro + PROUD
        self.ric, self.roc = self.ri - CAP_PROUD, self.ro + CAP_PROUD
        self.zc = self.H - CAP_H
        self.ze = self.zc + CAP_EDGE
        pier = PIER_W / self.R
        a0, a1 = -self.A / 2.0, self.A / 2.0
        n = max(1, int(math.ceil(math.degrees(a1 - a0 - 2.0 * pier) / SEG_DEG)))
        self.ang = [a0] + [a0 + pier + (a1 - a0 - 2.0 * pier) * k / n for k in range(n + 1)] + [a1]

    def body_m(self):
        return self.zc - SOCLE_H


def _et(a):
    return (-math.sin(a), math.cos(a), 0.0)


def _er(a):
    return (math.cos(a), math.sin(a), 0.0)


def wall(arc):
    m = mb._Mesh()
    S, zc, ze, H, W = SOCLE_H, arc.zc, arc.ze, arc.H, WASH_IN
    ri, ro, rip, rop, ric, roc = arc.ri, arc.ro, arc.rip, arc.rop, arc.ric, arc.roc

    def P(r, z, a):
        return m.v((r * math.cos(a), r * math.sin(a), z))

    last = len(arc.ang) - 2
    for k in range(last + 1):
        a, b = arc.ang[k], arc.ang[k + 1]
        am = 0.5 * (a + b)
        out, inn = _er(am), tuple(-c for c in _er(am))

        def ring(r, z0, z1, zone, want, uv=None):
            m.quad(P(r, z0, a), P(r, z0, b), P(r, z1, b), P(r, z1, a), want, zone, uv)

        def flat(r0, r1, z, zone, want):
            m.quad(P(r0, z, a), P(r1, z, a), P(r1, z, b), P(r0, z, b), want, zone)

        def band(r, want):
            ids = [P(r, zc, a), P(r, zc, b), P(r, ze, b), P(r, ze, a)]
            uv = {ids[0]: (0.0, a * r / BAND_M), ids[1]: (0.0, b * r / BAND_M),
                  ids[2]: (1.0, b * r / BAND_M), ids[3]: (1.0, a * r / BAND_M)}
            m.quad(ids[0], ids[1], ids[2], ids[3], want, "band", uv)

        pier = k == 0 or k == last
        flat(rip, rop, 0.0, "shade", DOWN)
        ring(rop, 0.0, S, "plinth", out)
        if pier:
            ring(rop, S, zc, "plinth", out)
        else:
            flat(ro, rop, S, "plinth", UP)
            ring(ro, S, zc, "marble", out)
            flat(ro, rop, zc, "shade", DOWN)
        flat(rop, roc, zc, "shade", DOWN)
        band(roc, out)
        m.quad(P(roc, ze, a), P(roc, ze, b), P(roc - W, H, b), P(roc - W, H, a), (out[0], out[1], 0.5), "shade")
        flat(ric + W, roc - W, H, "shade", UP)
        m.quad(P(ric, ze, a), P(ric, ze, b), P(ric + W, H, b), P(ric + W, H, a), (inn[0], inn[1], 0.5), "shade")
        band(ric, inn)
        flat(ric, rip, zc, "shade", DOWN)
        if pier:
            ring(rip, S, zc, "plinth", inn)
        else:
            flat(rip, ri, zc, "shade", DOWN)
            ring(ri, S, zc, "marble", inn)
            flat(rip, ri, S, "plinth", UP)
        ring(rip, 0.0, S, "plinth", inn)
    # the piers' side faces onto the body, and the two ends
    for s, want in ((arc.ang[1], _et(arc.ang[1])), (arc.ang[-2], tuple(-c for c in _et(arc.ang[-2])))):
        m.quad(P(ro, S, s), P(rop, S, s), P(rop, zc, s), P(ro, zc, s), want, "plinth")
        m.quad(P(ri, S, s), P(rip, S, s), P(rip, zc, s), P(ri, zc, s), want, "plinth")
    for s, want in ((arc.ang[0], tuple(-c for c in _et(arc.ang[0]))), (arc.ang[-1], _et(arc.ang[-1]))):
        m.quad(P(rip, 0.0, s), P(rop, 0.0, s), P(rop, S, s), P(rip, S, s), want, "plinth")
        m.quad(P(rip, S, s), P(rop, S, s), P(rop, zc, s), P(rip, zc, s), want, "plinth")
        m.tri(P(ric, zc, s), P(rip, zc, s), P(ric, ze, s), want, "shade")
        m.tri(P(rip, zc, s), P(roc, ze, s), P(ric, ze, s), want, "shade")
        m.tri(P(rip, zc, s), P(rop, zc, s), P(roc, ze, s), want, "shade")
        m.tri(P(rop, zc, s), P(roc, zc, s), P(roc, ze, s), want, "shade")
        m.quad(P(ric, ze, s), P(roc, ze, s), P(roc - W, H, s), P(ric + W, H, s), want, "shade")
    return m


def collider(arc):
    """A closed arc prism over the piers' footprint, the full height."""
    c = mb._Mesh()
    rip, rop, H = arc.rip, arc.rop, arc.H

    def P(r, z, a):
        return c.v((r * math.cos(a), r * math.sin(a), z))

    for k in range(len(arc.ang) - 1):
        a, b = arc.ang[k], arc.ang[k + 1]
        out = _er(0.5 * (a + b))
        inn = tuple(-x for x in out)
        c.quad(P(rip, 0.0, a), P(rop, 0.0, a), P(rop, 0.0, b), P(rip, 0.0, b), DOWN, "shade")
        c.quad(P(rip, H, a), P(rop, H, a), P(rop, H, b), P(rip, H, b), UP, "shade")
        c.quad(P(rop, 0.0, a), P(rop, 0.0, b), P(rop, H, b), P(rop, H, a), out, "shade")
        c.quad(P(rip, 0.0, a), P(rip, 0.0, b), P(rip, H, b), P(rip, H, a), inn, "shade")
    for s, want in ((arc.ang[0], tuple(-x for x in _et(arc.ang[0]))), (arc.ang[-1], _et(arc.ang[-1]))):
        c.quad(P(rip, 0.0, s), P(rop, 0.0, s), P(rop, H, s), P(rip, H, s), want, "shade")
    return c


def _shift(ob, dx):
    for v in ob.data.vertices:
        v.co.x += dx


def full_name(var):
    return NAME + ("_" + var if var else "")


def _check():
    ok = True
    var = variant()
    arc = _Arc(VARIANTS[var])
    for name, m in (("wall", wall(arc)), ("collider", collider(arc))):
        a = mb.audit(m, full_name(var) + " " + name)
        ok = ok and a["components"] == 1 and not (a["boundary_edges"] or a["doubled_edges"]
                                                  or a["over_edges"] or a["degenerate"]
                                                  or a["duplicate_positions"])
    units = arc.body_m() / BRICK_UNIT
    print("%s: r %.2f arc %.2f deg (%.2f m) h %.2f t %.2f body %.1f m = %.2f brick units stations %d"
          % (full_name(var), arc.R, math.degrees(arc.A), arc.R * arc.A, arc.H, arc.T, arc.body_m(), units,
             len(arc.ang)))
    ok = ok and abs(units - round(units)) < 1e-6
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


def build():
    var = variant()
    arc = _Arc(VARIANTS[var])
    m = wall(arc)
    ob = m.object("MarbleWallArc")
    sh = sheets(arc.R)
    tx.unwrap(ob, m.zones, sh, seed=17, face_uv=m.face_uv, groups=m.groups)   # unwrapped about the ring's axis ...
    mats = tx.materials(NAME, sh)
    for mat in mats.values():
        mat.diffuse_color = (0.78, 0.76, 0.72, 1.0)
    tx.finish(ob, m.zones, mats)
    _shift(ob, -arc.R)                                                       # ... then stood on the lane
    vertex_ao.apply(ob, vertex_ao.bake(ob, dist=0.6))
    c = collider(arc).object("MarbleWallArcCollision-colonly")
    _shift(c, -arc.R)
    c.hide_render = True
    tx.report(sh)
    print("MDL STATS %s tris=%d surfaces=%d r=%.2f arc=%.2f h=%.2f t=%.2f"
          % (full_name(var), len(ob.data.polygons), len(ob.data.materials), arc.R, math.degrees(arc.A),
             arc.H, arc.T))
    return [ob, c]


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(full_name(variant()), build, facing_yaw=FACING_YAW)
