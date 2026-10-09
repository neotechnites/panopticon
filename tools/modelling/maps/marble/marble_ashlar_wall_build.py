"""
marble_ashlar_wall -- one placeable straight wall of the rotunda's ashlar: LENGTH x
HEIGHT x DEPTH with a cornice cap. Not marble_wall (the map's wall part).

ORIGIN: the base centre, z 0 the ground; the length runs along X. One closed mesh in
the map's own brick (1 m courses, a joint on the ground), the cap in the plinth's
tint; MarbleAshlarWallCollision is one -boxcol over the body.

    python3 tools/modelling/maps/marble/marble_ashlar_wall_build.py --check
    tools/modelling/model build marble_ashlar_wall --pc
"""

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

NAME = "marble_ashlar_wall"
FACING_YAW = 0.0
LENGTH = 4.0
HEIGHT = 2.0
DEPTH = 0.5
CAP_Z = 1.80                # the body's top: the cap's soffit
CAP_PROUD = 0.08            # the cap's overhang all round
CAP_EDGE = 0.12             # its upright face; above it a wash back to ...
WASH_IN = 0.04              # ... a top this far in from the overhang

UP, DOWN = mb.UP, mb.DOWN

SHEETS = {
    "marble": mb.ashlar_sheet("marble", 2.991, None, mode="box", phase=(0.0, 0.0)),
    "plinth": mb.ashlar_sheet("plinth", 2.991, mb.TINT_PLINTH, mode="box", phase=(0.0, 0.0)),
    "shade": mb.shade_sheet("shade", mode="box"),
}


def _rect(m, hx, hy, z):
    return [m.v((x * hx, y * hy, z)) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]


def _band(m, lo, hi, zone, tilt=0.0):
    sq = ((-1, -1), (1, -1), (1, 1), (-1, 1))
    for k in range(4):
        j = (k + 1) % 4
        out = ((sq[k][0] + sq[j][0]) * 0.5, (sq[k][1] + sq[j][1]) * 0.5, tilt)
        m.quad(lo[k], lo[j], hi[j], hi[k], out, zone)


def wall():
    m = mb._Mesh()
    hx, hy = LENGTH / 2.0, DEPTH / 2.0
    cx, cy = hx + CAP_PROUD, hy + CAP_PROUD
    foot = _rect(m, hx, hy, 0.0)
    neck = _rect(m, hx, hy, CAP_Z)
    soff = _rect(m, cx, cy, CAP_Z)
    edge = _rect(m, cx, cy, CAP_Z + CAP_EDGE)
    top = _rect(m, cx - WASH_IN, cy - WASH_IN, HEIGHT)
    m.quad(foot[0], foot[1], foot[2], foot[3], DOWN, "shade")
    _band(m, foot, neck, "marble")
    for k in range(4):
        j = (k + 1) % 4
        m.quad(neck[k], neck[j], soff[j], soff[k], DOWN, "shade")
    _band(m, soff, edge, "plinth")
    _band(m, edge, top, "plinth", tilt=1.0)
    m.quad(top[0], top[1], top[2], top[3], UP, "plinth")
    return m


def collider():
    m = mb._Mesh()
    hx, hy = LENGTH / 2.0, DEPTH / 2.0
    lo, hi = _rect(m, hx, hy, 0.0), _rect(m, hx, hy, HEIGHT)
    m.quad(lo[0], lo[1], lo[2], lo[3], DOWN, "shade")
    _band(m, lo, hi, "shade")
    m.quad(hi[0], hi[1], hi[2], hi[3], UP, "shade")
    return m


def _check():
    ok = True
    for name, m in (("wall", wall()), ("collider", collider())):
        a = mb.audit(m, name)
        ok = ok and a["components"] == 1 and not (a["boundary_edges"] or a["doubled_edges"]
                                                  or a["over_edges"] or a["degenerate"]
                                                  or a["duplicate_positions"])
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


def build():
    m = wall()
    ob = m.object("MarbleAshlarWall")
    tx.unwrap(ob, m.zones, SHEETS, seed=17, groups=m.groups)
    mats = tx.materials(NAME, SHEETS)
    for mat in mats.values():
        mat.diffuse_color = (0.78, 0.76, 0.72, 1.0)
    tx.finish(ob, m.zones, mats)
    vertex_ao.apply(ob, vertex_ao.bake(ob, dist=0.6))
    c = collider().object("MarbleAshlarWallCollision-boxcol")
    c.hide_render = True
    print("MDL STATS tris=%d surfaces=%d size=%.2fx%.2fx%.2f"
          % (len(ob.data.polygons), len(ob.data.materials), LENGTH, HEIGHT, DEPTH))
    return [ob, c]


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW)
