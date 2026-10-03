"""
PANOPTICON -- ice_gate: Map 4's barrier across the lane at 353 deg, between the finish and the
start, in the same place and role as every map's bars (RingBake must not link start to finish
backwards). A plain solid ice slab: this map has no see-through cover.

    envelope ......  10.9 m across the lane (X) x 0.8 m (Y) x 8.5 m tall (Z), origin the base centre
    placement .....  centre r 52.15: from the lane's open edge (46.7) 0.3 m into the wall (57.3)

Collision is the one box, shipped `-boxcol` (Godot: IceGateCollision/IceGateCollisionShape).

    tools/modelling/model build ice_gate
"""

import os
import sys

try:
    import bpy
except ImportError:
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
for _root in (os.path.dirname(HERE), os.path.dirname(os.path.dirname(HERE))):
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break
import ice_common as ic  # noqa: E402
if bpy is not None:
    import mdl  # noqa: E402
    import texel as tx  # noqa: E402
    mdl.DEFAULTS["views"] = []

NAME = "ice_gate"
OBJECT_NAME = "IceGate"
COLLIDER_NAME = "IceGateCollision-boxcol"
FACING_YAW = 0.0

HALF_W = 5.45               # 46.7 .. 57.6 about r 52.15
HALF_D = 0.4
HEIGHT = 8.5


def box():
    m = ic.Mesh()
    xs, ys, zs = (-HALF_W, HALF_W), (-HALF_D, HALF_D), (0.0, HEIGHT)
    for axis in range(3):
        for side in (0, 1):
            want = [0.0, 0.0, 0.0]
            want[axis] = 1.0 if side else -1.0
            pts = []
            for (u, v) in ((0, 0), (1, 0), (1, 1), (0, 1)):
                c = [0, 0, 0]
                c[axis] = side
                c[(axis + 1) % 3], c[(axis + 2) % 3] = u, v
                pts.append(m.v((xs[c[0]], ys[c[1]], zs[c[2]])))
            m.face(pts, want, "ice")
    return m


def build():
    m = box()
    ob = m.object(OBJECT_NAME)
    sh = {"ice": ic.sheet(tx, "ice", mode="box")}
    tx.unwrap(ob, m.zones, sh)
    tx.finish(ob, m.zones, tx.materials(NAME, sh))
    coll = box().object(COLLIDER_NAME)
    coll.hide_render = True
    return [ob, coll]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
