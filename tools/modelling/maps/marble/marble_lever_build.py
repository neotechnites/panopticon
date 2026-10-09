"""
marble_lever -- the trapdoor's lever: an iron handle on a stone post beside the lane.

ORIGIN: the post's base centre, z 0 the deck; Godot +Z the direction of travel.

    MarbleLeverPost       matched ashlar post POST_HW*2 square, POST_H tall, a plinth cap
    MarbleLeverHandle     near-black iron: pivot boss, bar, knob. ORIGIN AT THE PIVOT
                          (0, PIVOT_Z, 0), the bar up local +Y at rest; the scene tilts it
                          about local X
    MarbleLeverCollision  -boxcol, the post only (the handle's hitbox is the scene's)

    python3 tools/modelling/maps/marble/marble_lever_build.py --check
    tools/modelling/model build marble_lever --pc
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

NAME = "marble_lever"
FACING_YAW = 0.0
POST_HW = 0.20              # 0.40 m square shaft
POST_H = 0.90               # the shaft's top: the cap's foot
CAP_HW = 0.26               # the cap, proud of the shaft
PIVOT_Z = 1.00              # the cap's top, and the handle's pivot
BOSS = (0.12, 0.09, 0.09)   # pivot boss half sizes (x along the axle, y, z)
BAR_HW = 0.045              # the bar: 0.09 m square ...
BAR_L = 0.95                # ... this long from the pivot
KNOB_HW = 0.08             # the grip knob at its head
KNOB_H = 0.14

POST_TINT = (1.0, 0.9, 0.78)  # warmed: a post this small by the lip read blue-grey against the ashlar
UP, DOWN = mb.UP, mb.DOWN

SHEETS = {
    "marble": mb.ashlar_sheet("marble", 2.991, POST_TINT, mode="box", phase=(0.0, 0.0)),
    "plinth": mb.ashlar_sheet("plinth", 2.991, POST_TINT, mode="box", phase=(0.0, 0.0)),
    "shade": mb.shade_sheet("shade", mode="box"),
    "iron": mb.iron_sheet(),
}


def _box(m, lo, hi, zone, top=None, bottom=None):
    """A closed axis-aligned box; returns nothing. top/bottom override the cap faces' zone."""
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    v = {}
    for i, x in enumerate((x0, x1)):
        for j, y in enumerate((y0, y1)):
            for k, z in enumerate((z0, z1)):
                v[i, j, k] = m.v((x, y, z))
    m.quad(v[0, 0, 1], v[1, 0, 1], v[1, 1, 1], v[0, 1, 1], UP, top or zone)
    m.quad(v[0, 0, 0], v[1, 0, 0], v[1, 1, 0], v[0, 1, 0], DOWN, bottom or zone)
    m.quad(v[0, 0, 0], v[1, 0, 0], v[1, 0, 1], v[0, 0, 1], (0.0, -1.0, 0.0), zone)
    m.quad(v[0, 1, 0], v[1, 1, 0], v[1, 1, 1], v[0, 1, 1], (0.0, 1.0, 0.0), zone)
    m.quad(v[0, 0, 0], v[0, 1, 0], v[0, 1, 1], v[0, 0, 1], (-1.0, 0.0, 0.0), zone)
    m.quad(v[1, 0, 0], v[1, 1, 0], v[1, 1, 1], v[1, 0, 1], (1.0, 0.0, 0.0), zone)


def post():
    """Shaft and cap welded: the cap's soffit is an annulus round the shaft's top ring."""
    m = mb._Mesh()
    s, c = POST_HW, CAP_HW
    sq = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    foot = [m.v((x * s, y * s, 0.0)) for x, y in sq]
    neck = [m.v((x * s, y * s, POST_H)) for x, y in sq]
    soff = [m.v((x * c, y * c, POST_H)) for x, y in sq]
    capt = [m.v((x * c, y * c, PIVOT_Z)) for x, y in sq]
    m.quad(foot[0], foot[1], foot[2], foot[3], DOWN, "shade")
    for k in range(4):
        j = (k + 1) % 4
        out = (sq[k][0] + sq[j][0], sq[k][1] + sq[j][1], 0.0)
        m.quad(foot[k], foot[j], neck[j], neck[k], out, "marble")
        m.quad(neck[k], neck[j], soff[j], soff[k], DOWN, "shade")
        m.quad(soff[k], soff[j], capt[j], capt[k], out, "plinth")
    m.quad(capt[0], capt[1], capt[2], capt[3], UP, "plinth")
    return m


def handle():
    """In the pivot's own frame (pivot at the origin): boss, bar up +Z, knob."""
    m = mb._Mesh()
    bx, by, bz = BOSS
    _box(m, (-bx, -by, -bz), (bx, by, bz), "iron")
    _box(m, (-BAR_HW, -BAR_HW, bz), (BAR_HW, BAR_HW, BAR_L), "iron")
    _box(m, (-KNOB_HW, -KNOB_HW, BAR_L), (KNOB_HW, KNOB_HW, BAR_L + KNOB_H), "iron")
    return m


def collider():
    m = mb._Mesh()
    _box(m, (-POST_HW, -POST_HW, 0.0), (POST_HW, POST_HW, PIVOT_Z), "shade")
    return m


def _check():
    ok = True
    for name, m in (("post", post()), ("handle", handle()), ("collider", collider())):
        a = mb.audit(m, name)
        ok = ok and not (a["boundary_edges"] or a["doubled_edges"] or a["over_edges"]
                         or a["degenerate"] or a["duplicate_positions"])
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


def _finish(ob, m):
    tx.unwrap(ob, m.zones, SHEETS, seed=13, groups=m.groups)
    mats = tx.materials(NAME, SHEETS)
    for mat in mats.values():
        mat.diffuse_color = (0.78, 0.76, 0.72, 1.0)
    tx.finish(ob, m.zones, {z: mats[z] for z in set(m.zones)})
    vertex_ao.apply(ob, vertex_ao.bake(ob, dist=0.5))


def build():
    pm = post()
    p = pm.object("MarbleLeverPost")
    _finish(p, pm)
    hm = handle()
    h = hm.object("MarbleLeverHandle")
    h.location = (0.0, 0.0, PIVOT_Z)
    bpy.context.view_layer.update()
    _finish(h, hm)
    c = collider().object("MarbleLeverCollision-boxcol")
    c.hide_render = True
    print("MDL STATS post_tris=%d handle_tris=%d surfaces=%d+%d pivot_z=%.2f bar=%.2f"
          % (len(p.data.polygons), len(h.data.polygons), len(p.data.materials),
             len(h.data.materials), PIVOT_Z, BAR_L + KNOB_H))
    return [p, h, c]


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW)
