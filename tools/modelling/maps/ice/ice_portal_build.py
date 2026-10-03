"""
PANOPTICON -- ice_portal: Map 4's finish portal. A plain ice frame round portal.glb's opening,
and the swirl every portal hangs in it (lib/portal_disc.py), on the ice sheet's own swirl slice.

    envelope ......  4.5 m wide (X) x 4.0 m tall (Z) x 0.8 m deep (Y), origin the base centre
    opening .......  2.7 m wide at the ground, springing z 2.6, a segmental head to apex z 3.15;
                     the runner passes through along Blender Y (Godot local Z)
    collider ......  the frame with a flat head at 3.15: |x| <= 1.35 clear to z 3.15

One mesh, two surfaces: ice, and the swirl (IcePortalSwirl, portal_wave.gdshader at import). The
swirl's rim vertices are the frame's own y = 0 row, so nothing floats.

    tools/modelling/model build ice_portal
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
import portal_disc as pd  # noqa: E402
if bpy is not None:
    import mdl  # noqa: E402
    import texel as tx  # noqa: E402
    mdl.DEFAULTS["views"] = []

NAME = "ice_portal"
OBJECT_NAME = "IcePortal"
COLLIDER_NAME = "IcePortalCollision-colonly"
SWIRL_MAT = "IcePortalSwirl"
SWIRL_STEM = "ice_portal_swirl_albedo"
FACING_YAW = 0.0

HALF_W = 2.25
HEIGHT = 4.0
HALF_D = 0.4
IN_HALF_W = 1.35
IN_SPRING = 2.6
APEX_Z = 3.15
HEAD_SEG = 6
DISC_CENTRE_Z = 1.5


def opening(arched):
    """The opening's outline, ground-left up, over and down to ground-right."""
    pts = [(-IN_HALF_W, 0.0), (-IN_HALF_W, IN_SPRING if arched else APEX_Z)]
    if arched:
        rise = APEX_Z - IN_SPRING
        rad = (IN_HALF_W ** 2 + rise ** 2) / (2.0 * rise)
        cz = APEX_Z - rad
        half = math.asin(IN_HALF_W / rad)
        for k in range(1, HEAD_SEG):
            t = -half + 2.0 * half * k / HEAD_SEG
            pts.append((rad * math.sin(t), cz + rad * math.cos(t)))
        pts.append((IN_HALF_W, IN_SPRING))
    else:
        pts.append((IN_HALF_W, APEX_Z))
    pts.append((IN_HALF_W, 0.0))
    return pts


def frame(arched):
    """(mesh, rim_xz): the frame, and with the arch the swirl sheet welded to its y = 0 row."""
    m = ic.Mesh()
    outline = opening(arched)
    zs = IN_SPRING if arched else APEX_Z
    rim = pd.rim(outline) if arched else [(x, z, k) for k, (x, z) in enumerate(outline)]
    inner = []                                   # the opening's stations, foot-left to foot-right
    for (x, z, k) in rim:
        inner.append((x, z))
        if k == len(outline) - 1:
            break
    jamb_l = [(x, z) for (x, z) in inner if x < 0 and abs(x + IN_HALF_W) < 1e-9 and z <= zs + 1e-9]
    jamb_r = [(x, z) for (x, z) in inner if x > 0 and abs(x - IN_HALF_W) < 1e-9 and z <= zs + 1e-9]
    head = inner[len(jamb_l) - 1:len(inner) - len(jamb_r) + 1]
    ys = (-HALF_D, 0.0, HALF_D)

    def v(x, y, z):
        return m.v((x, y, z))

    for (x0, z0), (x1, z1) in zip(inner, inner[1:]):        # the opening's own faces, through the depth
        want = (-0.5 * (x0 + x1), 0.0, 1.0 - 0.5 * (z0 + z1))
        for ya, yb in zip(ys, ys[1:]):
            m.face([v(x0, ya, z0), v(x1, ya, z1), v(x1, yb, z1), v(x0, yb, z0)], want, "ice")
    for y, want in ((-HALF_D, (0.0, -1.0, 0.0)), (HALF_D, (0.0, 1.0, 0.0))):
        for jamb in (jamb_l, jamb_r):
            s = math.copysign(1.0, jamb[0][0])
            for (_x, za), (_x2, zb) in zip(jamb, jamb[1:]):
                m.face([v(s * HALF_W, y, za), v(s * IN_HALF_W, y, za),
                        v(s * IN_HALF_W, y, zb), v(s * HALF_W, y, zb)], want, "ice")
            m.face([v(s * HALF_W, y, zs), v(s * IN_HALF_W, y, zs),
                    v(s * IN_HALF_W, y, HEIGHT), v(s * HALF_W, y, HEIGHT)], want, "ice")
        for (xa, za), (xb, zb) in zip(head, head[1:]):
            m.face([v(xa, y, za), v(xb, y, zb), v(xb, y, HEIGHT), v(xa, y, HEIGHT)], want, "ice")
    ring = ([(-HALF_W, z) for (_x, z) in jamb_l] + [(-HALF_W, HEIGHT)] + [(x, HEIGHT) for (x, _z) in head]
            + [(HALF_W, HEIGHT)] + [(HALF_W, z) for (_x, z) in jamb_r])
    for (xa, za), (xb, zb) in zip(ring, ring[1:]):          # the outer sides and the top
        want = (xa, 0.0, 0.0) if xa == xb else (0.0, 0.0, 1.0)
        m.face([v(xa, -HALF_D, za), v(xb, -HALF_D, zb), v(xb, HALF_D, zb), v(xa, HALF_D, za)], want, "ice")
    for s in (-1.0, 1.0):                                    # the feet
        m.face([v(s * HALF_W, -HALF_D, 0.0), v(s * IN_HALF_W, -HALF_D, 0.0), v(s * IN_HALF_W, 0.0, 0.0),
                v(s * IN_HALF_W, HALF_D, 0.0), v(s * HALF_W, HALF_D, 0.0)], (0.0, 0.0, -1.0), "ice")
    rim_xz = None
    if arched:
        rim_xz = [(x, z) for (x, z, _k) in rim]
        _sheet(m, [m.v((x, 0.0, z)) for (x, z) in rim_xz], rim_xz)
    return m, rim_xz


def _sheet(m, rim_ids, rim_xz):
    """portal_disc.sheet on this module's Mesh: rings in from the rim to a centre."""
    class _Adapter(object):
        def v(self, p):
            return m.v(p)

        def quad(self, a, b, c, d, want, zone):
            m.face([a, b, c, d], want, zone)

        def tri(self, a, b, c, want, zone):
            m.face([a, b, c], want, zone)
    pd.sheet(_Adapter(), rim_ids, rim_xz, DISC_CENTRE_Z, "swirl")


def build():
    m, rim_xz = frame(True)
    ob = m.object(OBJECT_NAME)
    sh = {"ice": ic.sheet(tx, "ice", mode="box")}
    tx.unwrap(ob, [z if z != "swirl" else "ice" for z in m.zones], sh)
    uvl = ob.data.uv_layers["UVMap"]
    rise = APEX_Z
    for p in ob.data.polygons:                   # the swirl: its slice once across the opening, planar
        if m.zones[p.index] != "swirl":
            continue
        for li in p.loop_indices:
            co = ob.data.vertices[ob.data.loops[li].vertex_index].co
            uvl.data[li].uv = ((co.x + IN_HALF_W) / (2.0 * IN_HALF_W), co.z / rise)
    mats = tx.materials(NAME, sh)
    swirl = tx.image(SWIRL_STEM)
    mats["swirl"] = tx.material(SWIRL_MAT, swirl, swirl, 0.9, 0.0, False)
    pd.see_through(mats["swirl"])
    tx.finish(ob, m.zones, mats)
    pd.wave_uv(ob, SWIRL_MAT, rim_xz)
    coll = frame(False)[0].object(COLLIDER_NAME)
    coll.hide_render = True
    a = ic.audit(m)
    print("MDL STATS visual_tris=%d collision_tris=%d components=%d boundary=%d"
          % (a["tris"], len(coll.data.polygons), a["components"], a["boundary"]))
    return [ob, coll]


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        for arched in (True, False):
            print(arched, ic.audit(frame(arched)[0]))
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW)
