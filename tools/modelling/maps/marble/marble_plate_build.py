"""
marble_plate -- the sniper-only trapdoor trigger: a square iron plate with a bronze boss and four
rivets, bolted high on a lane wall's tower-facing side. The scene's hitbox is what the rifle hits.

ORIGIN: the plate's back-face centre on the wall; the plate stands out along +X (Godot and
Blender). No colliders: nobody can reach it.

    python3 tools/modelling/maps/marble/marble_plate_build.py --check
    tools/modelling/model build marble_plate --pc
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
    mdl.DEFAULTS["ground"] = False

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "marble_plate"
FACING_YAW = 0.0
SIZE = 1.0                  # the plate, square
T = 0.08                    # ... and thick
BOSS_R = 0.28               # the bronze boss: an octagon ...
BOSS_H = 0.07               # ... this proud of the plate
RIVET_HW = 0.05             # four rivets, 0.10 square ...
RIVET_H = 0.04
RIVET_IN = 0.12             # ... this far in from the plate's edges
TINT_BRONZE = (0.62, 0.42, 0.20)   # the plain stone warmed to bronze: the target reads from the tower

UP, DOWN = mb.UP, mb.DOWN

SHEETS = {
    "iron": mb.iron_sheet(),
    "bronze": mb.stone("bronze", mode="box", tint=TINT_BRONZE),
}


def _box(m, lo, hi, zone):
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    v = {}
    for i, x in enumerate((x0, x1)):
        for j, y in enumerate((y0, y1)):
            for k, z in enumerate((z0, z1)):
                v[i, j, k] = m.v((x, y, z))
    m.quad(v[0, 0, 1], v[1, 0, 1], v[1, 1, 1], v[0, 1, 1], UP, zone)
    m.quad(v[0, 0, 0], v[1, 0, 0], v[1, 1, 0], v[0, 1, 0], DOWN, zone)
    m.quad(v[1, 0, 0], v[1, 1, 0], v[1, 1, 1], v[1, 0, 1], (1, 0, 0), zone)
    m.quad(v[0, 0, 0], v[0, 1, 0], v[0, 1, 1], v[0, 0, 1], (-1, 0, 0), zone)
    m.quad(v[0, 1, 0], v[1, 1, 0], v[1, 1, 1], v[0, 1, 1], (0, 1, 0), zone)
    m.quad(v[0, 0, 0], v[1, 0, 0], v[1, 0, 1], v[0, 0, 1], (0, -1, 0), zone)


def _prism(m, x0, x1, r, n, zone):
    """An n-gon prism along X, centred on the Y/Z origin."""
    a = [m.v((x0, r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n))) for k in range(n)]
    b = [m.v((x1, r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n))) for k in range(n)]
    for k in range(n):
        j = (k + 1) % n
        t = 2 * math.pi * (k + 0.5) / n
        m.quad(a[k], a[j], b[j], b[k], (0.0, math.cos(t), math.sin(t)), zone)
    m.poly(a, (-1, 0, 0), zone)
    m.poly(b, (1, 0, 0), zone)


def plate():
    m = mb._Mesh()
    h = SIZE / 2.0
    _box(m, (0.0, -h, -h), (T, h, h), "iron")
    _prism(m, T, T + BOSS_H, BOSS_R, 8, "bronze")
    for sy in (-1, 1):
        for sz in (-1, 1):
            cy, cz = sy * (h - RIVET_IN), sz * (h - RIVET_IN)
            _box(m, (T, cy - RIVET_HW, cz - RIVET_HW), (T + RIVET_H, cy + RIVET_HW, cz + RIVET_HW), "bronze")
    return m


def _check():
    a = mb.audit(plate(), "plate")
    ok = a["components"] == 6 and not (a["boundary_edges"] or a["doubled_edges"] or a["over_edges"]
                                        or a["degenerate"] or a["duplicate_positions"])
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


def build():
    m = plate()
    ob = m.object("MarblePlate")
    tx.unwrap(ob, m.zones, SHEETS, seed=5, groups=m.groups)
    mats = tx.materials(NAME, SHEETS)
    for mat in mats.values():
        mat.diffuse_color = (0.3, 0.28, 0.26, 1.0)
    tx.finish(ob, m.zones, mats)
    vertex_ao.apply(ob, vertex_ao.bake(ob, dist=0.3))
    print("MDL STATS tris=%d surfaces=%d size=%.2f" % (len(ob.data.polygons), len(ob.data.materials), SIZE))
    return [ob]


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW)
