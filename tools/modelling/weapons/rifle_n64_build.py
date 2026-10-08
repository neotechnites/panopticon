"""
PANOPTICON -- the guard's rifle the N64 way: rough geometry on a real rifle's traced side profile, one small
side-on picture (weapons/textures/rifle.ase, slice rifle_side_albedo) projected from the side onto both flanks.

The trace, its source photo and licence, and every number the scene holds are in rifle_n64_trace.py.

    tools/modelling/model build rifle_n64

Blender space: +Y the muzzle, +Z up, +X right; the origin is on the bore.
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import mdl  # noqa: E402
import rifle_n64_trace as T  # noqa: E402
import texel  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================
NAME = "rifle_n64"          # -> weapons/models/rifle_n64.glb
OBJECT_NAME = "Rifle"
FACING_YAW = 180.0          # the muzzle points +Y: "front" looks down the barrel
SHARP_DEGREES = 60.0        # an edge bent further than this stays hard; everything else shades smooth

SCOPE_SIDES = 8
BARREL_SIDES = 6
GUARD_HALF_W = 0.006
TRIGGER_HALF_W = 0.003
STRIP_THICK = 0.004         # how thick guard and trigger read from the side
BOLT_R = 0.005
KNOB_R = 0.011
BOLT_PATH = ((0.010, 0.000), (0.032, -0.006), (0.038, None))   # (x right, z over the root); None: the knob's height
BOLT_SWEEP = 0.009          # the knob sits this far behind the root
WINDAGE_OUT = 0.012         # the side turret's reach past the saddle


# =============================================================================
# THE MESH -- one accumulator: a vertex is (place, uv); faces carry a UV per corner
# =============================================================================

class Shape(object):
    def __init__(self):
        self.verts, self.faces, self.uvs = [], [], []

    def face(self, corners, away_from=None):
        """A face from (place, uv) corners; wound to turn away from the point away_from when one is given."""
        if away_from is not None:
            pts = [c[0] for c in corners]
            n = mdl._newell(pts)
            c = [sum(p[d] for p in pts) / len(pts) - away_from[d] for d in range(3)]
            if n.x * c[0] + n.y * c[1] + n.z * c[2] < 0.0:
                corners = list(reversed(corners))
        base = len(self.verts)
        self.verts.extend(tuple(c[0]) for c in corners)
        self.faces.append(tuple(range(base, base + len(corners))))
        self.uvs.append([tuple(c[1]) for c in corners])


def _centre(ring):
    return [sum(c[0][d] for c in ring) / len(ring) for d in range(3)]


def loft(s, rings, closed=True):
    """Quads through rings of (place, uv); an open ring is an arch."""
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        mid = [(p + q) * 0.5 for p, q in zip(_centre(a), _centre(b))]
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            s.face([a[i], a[j], b[j], b[i]], away_from=mid)


def cap(s, ring, cell, inside):
    """Closes a ring with one face wearing a cell, fitted to the ring's own width and height."""
    xs, zs = [c[0][0] for c in ring], [c[0][2] for c in ring]
    x0, z1 = min(xs), max(zs)
    w, h = max(max(xs) - x0, 1e-9), max(z1 - min(zs), 1e-9)
    s.face([(c[0], T.cell_uv(cell, (c[0][0] - x0) / w, (z1 - c[0][2]) / h)) for c in ring], away_from=inside)


def stock_ring(x, top, bottom, half_w, crown, keel):
    """Six points at photo column x: ridge, shoulders, flanks, keel; each wears the picture at its own height."""
    y, zt, zb = T.model_y(x), T.model_z(x, top), T.model_z(x, bottom, keel=True)

    def pt(px, z):
        return ((px, y, z), T.uv(x, top + (zt - z) / (zt - zb) * (bottom - top)))
    return [pt(0.0, zt), pt(half_w, zt - crown), pt(half_w, zb + keel), pt(0.0, zb),
            pt(-half_w, zb + keel), pt(-half_w, zt - crown)]


def round_ring(x, top, bottom, y, r, cz, sides):
    """A ring with a vertex on top; the picture's column is unrolled round each flank, top row to bottom row."""
    out = []
    for i in range(sides):
        a = math.pi * 0.5 - 2.0 * math.pi * i / sides
        t = 2.0 * (i if i <= sides // 2 else sides - i) / sides
        out.append(((r * math.cos(a), y, cz + r * math.sin(a)), T.uv(x, top + t * (bottom - top))))
    return out


def cell_tube(s, path, radii, sides, cell, cap_ends=True):
    """A tube along 3D points wearing a cell: along it across the cell, round it down the cell."""
    rings = []
    for k, (p, r) in enumerate(zip(path, radii)):
        a, b = path[max(k - 1, 0)], path[min(k + 1, len(path) - 1)]
        axis = _unit(tuple(b[d] - a[d] for d in range(3)))
        ref = (0.0, 1.0, 0.0) if abs(axis[1]) < 0.9 else (1.0, 0.0, 0.0)
        u = _unit(_cross(axis, ref))
        v = _cross(axis, u)
        rings.append([tuple(p[d] + r * (math.cos(t) * u[d] + math.sin(t) * v[d]) for d in range(3))
                      for t in (2.0 * math.pi * i / sides for i in range(sides))])
    last = max(len(path) - 1, 1)
    for k in range(len(rings) - 1):
        mid = [(path[k][d] + path[k + 1][d]) * 0.5 for d in range(3)]
        for i in range(sides):
            j = (i + 1) % sides
            s.face([(rings[k][i], T.cell_uv(cell, k / last, i / sides)),
                    (rings[k][j], T.cell_uv(cell, k / last, (i + 1) / sides)),
                    (rings[k + 1][j], T.cell_uv(cell, (k + 1) / last, (i + 1) / sides)),
                    (rings[k + 1][i], T.cell_uv(cell, (k + 1) / last, i / sides))], away_from=mid)
    if cap_ends:
        for k, other in ((0, 1), (len(rings) - 1, len(rings) - 2)):
            s.face([(p, T.cell_uv(cell, 0.5 + 0.5 * math.cos(2.0 * math.pi * i / sides),
                                  0.5 + 0.5 * math.sin(2.0 * math.pi * i / sides)))
                    for i, p in enumerate(rings[k])], away_from=path[other])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _unit(a):
    m = math.sqrt(sum(c * c for c in a))
    return tuple(c / m for c in a)


def ribbon(s, path, half_w, thick, cell):
    """A two-sided strip along a photo (x, y) path, and a flat web inside it so it reads from the side; both wear a cell."""
    pts = [(T.model_y(x), T.model_z(x, y)) for (x, y) in path]
    last = len(pts) - 1
    cy, cz = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
    inner = [(y + thick * (cy - y) / math.hypot(cy - y, cz - z), z + thick * (cz - z) / math.hypot(cy - y, cz - z)) for (y, z) in pts]
    for k in range(last):
        (ya, za), (yb, zb) = pts[k], pts[k + 1]
        s.face([((-half_w, ya, za), T.cell_uv(cell, k / last, 0.0)), ((half_w, ya, za), T.cell_uv(cell, k / last, 1.0)),
                ((half_w, yb, zb), T.cell_uv(cell, (k + 1) / last, 1.0)), ((-half_w, yb, zb), T.cell_uv(cell, (k + 1) / last, 0.0))])
        s.face([((0.0, ya, za), T.cell_uv(cell, k / last, 0.0)), ((0.0, yb, zb), T.cell_uv(cell, (k + 1) / last, 0.0)),
                ((0.0,) + inner[k + 1], T.cell_uv(cell, (k + 1) / last, 0.6)), ((0.0,) + inner[k], T.cell_uv(cell, k / last, 0.6))])


# =============================================================================
# THE RIFLE
# =============================================================================

def _action_top(y):
    """Height of the action's ridge at model y."""
    pts = [(T.model_y(x), T.model_z(x, top)) for (x, top, _w) in T.ACTION]
    return T._ramp(y, pts)


def _geometry():
    s = Shape()

    # ---- the stock, butt to fore-end tip, one skin; butt plate and tip are cells
    rings = [stock_ring(*row) for row in T.STOCK]
    loft(s, rings)
    cap(s, rings[0], "butt", _centre(rings[1]))
    cap(s, rings[-1], "wood", _centre(rings[-2]))

    # ---- the action: an arch standing on the wood line, cocking piece to receiver ring
    arches = []
    for (x, top, half_w) in T.ACTION:
        y, zt = T.model_y(x), T.model_z(x, top)
        wood = T._ramp(x, [(row[0], row[1]) for row in T.STOCK])
        zb = T.model_z(x, wood) - T.ACTION_SINK
        zm = zt - 0.38 * (zt - zb)
        foot, mid = T.uv(x, wood), T.uv(x, top + 0.38 * (wood - top))
        arches.append([((-half_w, y, zb), foot), ((-half_w, y, zm), mid), ((0.0, y, zt), T.uv(x, top)),
                       ((half_w, y, zm), mid), ((half_w, y, zb), foot)])
    loft(s, arches, closed=False)
    cap(s, arches[0], "steel", _centre(arches[1]))

    # ---- nose cap, then the bare barrel stepping down out of it to a muzzle ring
    (x0, x1), top, bottom, half_w, ch = T.NOSE
    nose = [stock_ring(x, top, bottom, half_w, ch, ch) for x in (x0, x1)]
    loft(s, nose)
    cap(s, nose[1], "steel", _centre(nose[0]))
    barrel = [round_ring(x, T.BARREL_PX[0], T.BARREL_PX[1], T.model_y(x), r, 0.0, BARREL_SIDES) for (x, r) in T.BARREL]
    loft(s, barrel)
    cap(s, barrel[-1], "bore", _centre(barrel[-2]))

    # ---- the bolt handle: out of the bridge, down to a ball
    bx, root_y, knob_y = T.BOLT_X
    y, z0 = T.model_y(bx), T.model_z(bx, root_y)
    drop = T.model_z(bx, knob_y) - z0
    path = [(px, y - BOLT_SWEEP * k / 2.0, z0 + (drop if dz is None else dz)) for k, (px, dz) in enumerate(BOLT_PATH)]
    cell_tube(s, path, (BOLT_R, BOLT_R, BOLT_R * 0.9), 4, "steel", cap_ends=False)
    axis = _unit(tuple(path[2][d] - path[1][d] for d in range(3)))
    lat = 0.55
    ball = [tuple(path[2][d] + axis[d] * KNOB_R * k for d in range(3)) for k in (-1.0, -math.sin(lat), math.sin(lat), 1.0)]
    cell_tube(s, ball, (KNOB_R * 0.05, KNOB_R * math.cos(lat), KNOB_R * math.cos(lat), KNOB_R * 0.05), 6, "steel")

    # ---- the scope: one tube on the aim axis, bells both ends glazed shut, a saddle and two turrets
    scope = [round_ring(x, top, bottom, y, r, T.SCOPE_Z, SCOPE_SIDES) for (x, top, bottom, y, r) in T.SCOPE]
    loft(s, scope)
    cap(s, scope[0], "bore", _centre(scope[1]))     # dark lenses: the scope is solid, never a tube to look through
    cap(s, scope[-1], "bore", _centre(scope[-2]))
    (tx0, tx1), (ty0, ty1), turret_y, turret_r, turret_h = T.TURRET
    saddle_r = max(r for (_x, _t, _b, y, r) in T.SCOPE if abs(y - turret_y) < 0.02)
    foot = T.SCOPE_Z + saddle_r * math.cos(math.pi / SCOPE_SIDES) - 0.001
    rings = []
    for z, row in ((foot, ty1), (foot + turret_h, ty0)):
        rings.append([((turret_r * math.sin(a), turret_y + turret_r * math.cos(a), z),
                       T.uv(tx0 + (tx1 - tx0) * (0.5 + 0.5 * math.cos(a)), row))
                      for a in (2.0 * math.pi * i / 6 for i in range(6))])
    loft(s, rings)
    s.face([(c[0], T.cell_uv("knob", 0.5 + 0.5 * math.sin(2.0 * math.pi * i / 6), 0.5 + 0.5 * math.cos(2.0 * math.pi * i / 6)))
            for i, c in enumerate(rings[1])], away_from=_centre(rings[0]))
    side = saddle_r * math.cos(math.pi / SCOPE_SIDES) - 0.001
    cell_tube(s, [(side, turret_y, T.SCOPE_Z), (side + WINDAGE_OUT, turret_y, T.SCOPE_Z)], (turret_r, turret_r), 6, "steel",
              cap_ends=False)
    s.face([((side + WINDAGE_OUT, turret_y + turret_r * math.cos(a), T.SCOPE_Z + turret_r * math.sin(a)),
             T.cell_uv("knob", 0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)))
            for a in (2.0 * math.pi * i / 6 for i in range(6))], away_from=(0.0, turret_y, T.SCOPE_Z))

    # ---- two mounts: flanks from the picture's ring feet, steel fore and aft, the top notched round the tube
    tube_foot = T.SCOPE_Z - T.TUBE_R
    shoulder = tube_foot + T.MOUNT_HALF_W * math.tan(math.pi / SCOPE_SIDES) + 0.0003
    for (px0, px1), (py0, py1), (y0, y1) in T.MOUNTS:
        w = T.MOUNT_HALF_W
        zb = min(_action_top(y0), _action_top(y1)) - 0.004
        mid = (0.0, (y0 + y1) * 0.5, (zb + shoulder) * 0.5)
        for sx in (-w, w):
            s.face([((sx, y0, zb), T.uv(px0, py1)), ((sx, y1, zb), T.uv(px1, py1)),
                    ((sx, y1, shoulder), T.uv(px1, py0)), ((sx, y0, shoulder), T.uv(px0, py0))], away_from=mid)
        for y in (y0, y1):
            s.face([((-w, y, zb), T.cell_uv("steel", 0.0, 1.0)), ((w, y, zb), T.cell_uv("steel", 1.0, 1.0)),
                    ((w, y, shoulder), T.cell_uv("steel", 1.0, 0.0)), ((0.0, y, tube_foot + 0.0003), T.cell_uv("steel", 0.5, 0.2)),
                    ((-w, y, shoulder), T.cell_uv("steel", 0.0, 0.0))], away_from=mid)

    # ---- trigger guard and trigger: two-sided strips
    ribbon(s, T.GUARD, GUARD_HALF_W, STRIP_THICK, "steel")
    ribbon(s, T.TRIGGER, TRIGGER_HALF_W, STRIP_THICK, "steel")
    return s


def build():
    s = _geometry()
    ob = mdl.mesh(OBJECT_NAME, s.verts, s.faces)
    me = ob.data
    # One picture, clamped to its edge colours by its own padding; two-sided for the open scope and the strips.
    me.materials.append(texel.material("RifleSide", mdl.texture("rifle_side_albedo"), None, roughness=1.0, metallic=0.0, cull=False))
    uvl = me.uv_layers.new(name="UVMap")
    for poly, uvs in zip(me.polygons, s.uvs):
        poly.use_smooth = True
        for li, uv in zip(poly.loop_indices, uvs):
            uvl.data[li].uv = uv

    # Faces are built loose so each keeps its own UVs; weld them, then keep hard only where the form turns hard.
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    limit = math.radians(SHARP_DEGREES)
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit)
    bm.to_mesh(me)
    bm.free()
    me.update()

    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    print("MDL STATS tris=%d materials=1 picture=%dx%d" % ((tris,) + T.PICTURE))
    print("MDL STATS overall_length=%.3f muzzle_local_godot=(0, 0, %.3f)" % (T.MUZZLE_Y - T.BUTT_Y, -T.MUZZLE_Y))
    return ob


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
