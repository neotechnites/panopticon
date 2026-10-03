"""
PANOPTICON -- ice_tower: Map 4's guard tower. A PLACEHOLDER: a plain ice drum on Map 1's guard
platform datum and dimensions, until Ryan designs the real one.

One closed contiguous mesh: a round shaft from the pit floor up through a guard room with eight
square-headed openings at bearings 25 + 45k (TowerVariant's grid), a flat ceiling and a flat top.
Origin = the guard-room datum as tower_arches.glb (the scene's Tower node at y 25.35):

    foot ...........  z -36.35 (the pit floor, world y -11.0)
    room floor .....  z 1.70 (world 27.05); the guard's eye 1.65 over it, world 28.7
    openings .......  40 deg wide, sill z 2.35 (0.65 over the floor) to head z 7.00
    room ...........  r 6.86 inside (TowerVariant.DRUM_INNER_RADIUS), ceiling z 7.25
    drum ...........  r 7.80 outside, top z 9.60

Collision (`-colonly`) is the same drum with its sills raised to a 1.25 m kerb the guard cannot
jump (Map 1's), open above it so a shot goes straight out.

    tools/modelling/model build ice_tower
"""

import math
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
    mdl.DEFAULTS["ground"] = False
    mdl.DEFAULTS["views"] = []

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "ice_tower"
OBJECT_NAME = "IceTower"
COLLIDER_NAME = "IceTowerCollision-colonly"
FACING_YAW = 0.0

FOOT_Z = -36.35             # pit floor -11.0 under the datum at 25.35
FLOOR_Z = 1.70              # guard-room floor (Map 1)
SILL_Z = FLOOR_Z + 0.65     # Map 1's sill
KERB_Z = FLOOR_Z + 1.25     # the collider's sill: higher than the guard's 1.11 m jump
HEAD_Z = 7.00               # Map 1's arch crown
CEIL_Z = 7.25               # Map 1's ceiling
TOP_Z = 9.60                # Map 1's drum top
R_IN = 6.86
R_OUT = 7.80
WINDOW_PHASE = 25.0         # bearings 25 + 45k
WINDOW_DEG = 40.0           # opening width; the pier between two is 5 deg
WINDOW_CELLS = 4            # stations across one opening


def stations():
    """[(angle in radians, cell after it is open)] round the drum, Blender angle = -bearing."""
    out = []
    step = WINDOW_DEG / WINDOW_CELLS
    for k in range(8):
        c = WINDOW_PHASE + 45.0 * k
        for i in range(WINDOW_CELLS):
            out.append((-math.radians(c - 0.5 * WINDOW_DEG + i * step), True))
        out.append((-math.radians(c + 0.5 * WINDOW_DEG), False))
    return out


def drum(sill):
    m = ic.Mesh()
    st = stations()
    n = len(st)

    def p(a, r, z):
        return m.v((r * math.cos(a), r * math.sin(a), z))

    for j in range(n):
        a, is_open = st[j]
        b = st[(j + 1) % n][0]
        d = (b - a + math.pi) % ic.TWO_PI - math.pi  # the wrap at 360 deg
        am = a + 0.5 * d
        out = (math.cos(am), math.sin(am), 0.0)
        inn = (-out[0], -out[1], 0.0)
        bands_out = [(FOOT_Z, sill), (HEAD_Z, TOP_Z)] if is_open else [(FOOT_Z, TOP_Z)]
        bands_in = [(FLOOR_Z, sill), (HEAD_Z, CEIL_Z)] if is_open else [(FLOOR_Z, CEIL_Z)]
        for (z0, z1) in bands_out:
            for (za, zb) in _split(z0, z1, bands_in_zs(is_open, sill, outer=True)):
                m.face([p(a, R_OUT, za), p(b, R_OUT, za), p(b, R_OUT, zb), p(a, R_OUT, zb)], out, "ice")
        for (z0, z1) in bands_in:
            for (za, zb) in _split(z0, z1, bands_in_zs(is_open, sill, outer=False)):
                m.face([p(a, R_IN, za), p(b, R_IN, za), p(b, R_IN, zb), p(a, R_IN, zb)], inn, "ice")
        if is_open:
            m.face([p(a, R_OUT, sill), p(b, R_OUT, sill), p(b, R_IN, sill), p(a, R_IN, sill)], (0, 0, 1), "ice")
            m.face([p(a, R_OUT, HEAD_Z), p(b, R_OUT, HEAD_Z), p(b, R_IN, HEAD_Z), p(a, R_IN, HEAD_Z)],
                   (0, 0, -1), "ice")
        prev_open = st[(j - 1) % n][1]
        if is_open != prev_open:                 # a jamb at the station between a pier and an opening
            t = (math.sin(a), -math.cos(a), 0.0)  # into the opening: stations run to decreasing angle
            if not is_open:
                t = (-t[0], -t[1], 0.0)
            m.face([p(a, R_OUT, sill), p(a, R_OUT, HEAD_Z), p(a, R_IN, HEAD_Z), p(a, R_IN, sill)], t, "ice")
    rings = {"floor": (R_IN, FLOOR_Z, (0, 0, 1)), "ceil": (R_IN, CEIL_Z, (0, 0, -1)),
             "top": (R_OUT, TOP_Z, (0, 0, 1)), "foot": (R_OUT, FOOT_Z, (0, 0, -1))}
    for (r, z, want) in rings.values():
        c = m.v((0.0, 0.0, z))
        for j in range(n):
            m.face([c, p(st[j][0], r, z), p(st[(j + 1) % n][0], r, z)], want, "ice")
    return m


def bands_in_zs(is_open, sill, outer):
    """Every height a neighbouring face puts a vertex on this station's column: no T-junctions."""
    zs = {FOOT_Z, FLOOR_Z, sill, HEAD_Z, CEIL_Z, TOP_Z}
    return sorted(z for z in zs if (FOOT_Z if outer else FLOOR_Z) <= z <= (TOP_Z if outer else CEIL_Z))


def _split(z0, z1, cuts):
    zs = [z0] + [z for z in cuts if z0 < z < z1] + [z1]
    return list(zip(zs, zs[1:]))


def build():
    m = drum(SILL_Z)
    a = ic.audit(m)
    if a["components"] != 1 or a["boundary"] or a["over"] or a["degenerate"] or a["dup_pos"]:
        raise RuntimeError("ice_tower: not one closed contiguous mesh: %s" % a)
    ob = m.object(OBJECT_NAME)
    sh = {"ice": ic.sheet(tx, "ice", mode="box")}
    tx.unwrap(ob, m.zones, sh)
    tx.finish(ob, m.zones, tx.materials(NAME, sh))
    coll = drum(KERB_Z).object(COLLIDER_NAME)
    coll.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d components=%d boundary=%d"
          % (a["tris"], len(coll.data.polygons), a["components"], a["boundary"]))
    return [ob, coll]


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        a = ic.audit(drum(SILL_Z))
        print(a)
        sys.exit(0 if a["components"] == 1 and not a["boundary"] and not a["over"] else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW)
