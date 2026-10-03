"""
PANOPTICON -- ice: Map 4, the ice dome. First blockout: a clean shell Ryan builds the level on.

ONE CONTIGUOUS MESH, one profile turned round the axis: the pit's dark-ice floor, the pit bank,
the flat ice lane, the outer ice wall and, springing from the wall head, a blue see-through ice
dome. Wall and dome are one surface: the dome's profile is a quarter ellipse whose tangent at the
spring is the wall's own vertical, so the join is a broad cove (radius DOME_RISE^2 / OUTER_R),
no corner, no crevice. Nothing on the lane: no cover, no props (Ryan places those).

Authored in WORLD coordinates (Map 1's ring), instanced at identity:

    pit floor ......  y = FLOOR_Z (-11.0), r 0 .. INNER_R; the tower stands on it
    lane ...........  y = DECK_Z (23.0), r INNER_R (46.7) .. OUTER_R (57.3), open inner edge
    wall ...........  r = OUTER_R, y 23.0 .. SPRING_Z (35.0)
    dome ...........  springs at 35.0 from the wall head, apex 65.0; DOME_ALPHA opaque

Collision rides as a `-colonly` node: pit floor, bank, lane and wall to the spring.

    python3 tools/modelling/maps/ice/ice_build.py --check
    tools/modelling/model build ice
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
for _root in (os.path.dirname(HERE), os.path.dirname(os.path.dirname(HERE))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break
import ice_common as ic  # noqa: E402
if bpy is not None:
    import mdl  # noqa: E402
    import texel as tx  # noqa: E402
    mdl.DEFAULTS["ground"] = False
    mdl.DEFAULTS["views"] = []            # a closed shell: the outside says nothing

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "ice"
OBJECT_NAME = "IceShell"
COLLIDER_NAME = "IceCollision-colonly"
FACING_YAW = 0.0

NSEG = 128                  # stations round the ring: 2.8 m chords on the wall
FLOOR_Z = -11.0             # Map 1's courtyard
INNER_R = 46.7              # lane inner edge, open over the pit (Map 1)
OUTER_R = 57.3              # lane outer edge = the wall face (Map 1)
DECK_Z = 23.0               # the runner's feet (Map 1)
LANE_R = 52.0
SPRING_Z = 35.0             # wall head: 12 m of wall over the lane
DOME_RISE = 30.0            # apex y 65.0
DOME_RINGS = 16             # quarter-ellipse steps, spring to apex

FLOOR_RS = (INNER_R * 0.25, INNER_R * 0.5, INNER_R * 0.75, INNER_R)
BANK_ZS = (FLOOR_Z, -2.5, 6.0, 14.5, DECK_Z)
LANE_RS = (INNER_R, 49.35, LANE_R, 54.65, OUTER_R)
WALL_ZS = (DECK_Z, 26.0, 29.0, 32.0, SPRING_Z)


# =============================================================================
# THE PROFILE -- (r, z) from the axis on the pit floor out, up and over to the apex
# =============================================================================

def profile():
    """[(r, z, zone of the segment that starts here)]; the last point's zone is unused."""
    pts = [(0.0, FLOOR_Z, "dark")]
    pts += [(r, FLOOR_Z, "dark") for r in FLOOR_RS[:-1]]
    pts += [(INNER_R, z, "ice") for z in BANK_ZS[:-1]]
    pts += [(r, DECK_Z, "ice") for r in LANE_RS[:-1]]
    pts += [(OUTER_R, z, "ice") for z in WALL_ZS[:-1]]
    for k in range(DOME_RINGS):
        phi = 0.5 * math.pi * k / DOME_RINGS
        pts.append((OUTER_R * math.cos(phi), SPRING_Z + DOME_RISE * math.sin(phi), "dome"))
    pts.append((0.0, SPRING_Z + DOME_RISE, None))
    return pts


def revolve(pts, top_z=None):
    """The profile turned through NSEG stations; faces face the playable side (left of the walk)."""
    m = ic.Mesh()
    ang = [ic.TWO_PI * j / NSEG for j in range(NSEG)]
    for (r0, z0, zone), (r1, z1, _z) in zip(pts, pts[1:]):
        if top_z is not None and max(z0, z1) > top_z + 1e-6:
            break
        nr, nz = -(z1 - z0), (r1 - r0)
        for j in range(NSEG):
            a, b = ang[j], ang[(j + 1) % NSEG]
            am = a + 0.5 * (ic.TWO_PI / NSEG)
            want = (nr * math.cos(am), nr * math.sin(am), nz)
            ring = []
            for (r, z, t) in ((r0, z0, a), (r0, z0, b), (r1, z1, b), (r1, z1, a)):
                i = m.v((r * math.cos(t), r * math.sin(t), z))
                if i not in ring:
                    ring.append(i)
            m.face(ring, want, zone)
    return m


def build_geometry():
    return revolve(profile())


def build_collider():
    return revolve(profile(), top_z=SPRING_Z)


# =============================================================================
# BUILD / CHECK
# =============================================================================

def _ice_ref(c):
    """The lane's arc is measured on the lane line, the walls' on their own face."""
    return LANE_R if abs(c[2] - DECK_Z) < 1e-3 else math.hypot(c[0], c[1])


def sheets():
    return {"ice": ic.sheet(tx, "ice", ref_r=_ice_ref),
            "dark": ic.sheet(tx, "dark", mode="box"),
            "dome": ic.sheet(tx, "dome", ref_r=lambda c: math.hypot(c[0], c[1]))}


def build():
    m = build_geometry()
    a = ic.audit(m)
    if a["components"] != 1 or a["boundary"] or a["over"] or a["degenerate"] or a["dup_pos"]:
        raise RuntimeError("ice: the shell is not one closed contiguous mesh: %s" % a)
    ob = m.object(OBJECT_NAME)
    sh = sheets()
    tx.unwrap(ob, m.zones, sh)
    mats = tx.materials(NAME, sh)
    ic.see_through(mats["dome"], ic.DOME_ALPHA)
    order = tx.finish(ob, m.zones, mats)
    for p in ob.data.polygons:                   # the cove and the dome read as one smooth shell
        p.use_smooth = m.zones[p.index] == "dome"
    tx.report(sh)
    coll = build_collider().object(COLLIDER_NAME)
    coll.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d surfaces=%s components=%d boundary=%d"
          % (a["tris"], len(coll.data.polygons), ",".join(order), a["components"], a["boundary"]))
    return [ob, coll]


def _check():
    a = ic.audit(build_geometry())
    c = ic.audit(build_collider())
    print("shell %s" % a)
    print("coll  %s" % c)
    ok = a["components"] == 1 and not (a["boundary"] or a["over"] or a["degenerate"] or a["dup_pos"])
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW)
