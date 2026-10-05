"""
PANOPTICON -- the guard's rifle in the game's own style: rounded low-poly forms, smooth shaded.

The same bolt-action as rifle_lowpoly_build.py: its origin, bore, muzzle, scope axis, wrist and
fore-end are that model's, so weapons/rifle.tscn's muzzle, aim pose and palm anchors hold.
Two tiling tiles (wood, metal) at the maps' 0.05 m per texel, grain along the gun.

    tools/modelling/model build rifle_n64

Blender space: +Y the muzzle, +Z up, +X right; the origin is on the bore at the receiver's rear face.
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
import texel  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================
NAME = "rifle_n64"          # -> weapons/models/rifle_n64.glb
OBJECT_NAME = "Rifle"
FACING_YAW = 180.0          # the muzzle points +Y: "front" looks down the barrel

MPT = texel.MPT             # metres per texel: the maps' own
TILE = 32                   # texels per tile side
SPAN = TILE * MPT           # metres one tile covers
SHARP_DEGREES = 70.0        # an edge bent further than this stays hard; everything else shades smooth

WOOD, METAL = "wood", "metal"

# ---- held by the scene: do not move without moving weapons/rifle.tscn ----------
BUTT_Y = -0.340             # rear face of the butt
RECEIVER_Y = (-0.020, 0.300)
MUZZLE_Y = 1.150            # Godot local (0, 0, -1.150): ViewModel/Muzzle
FOREND_Y = 0.860            # the wood stops here
SCOPE_Z = 0.045             # the aim pose's eye height over the bore (rifle_ads.gd)
OCULAR_R = 0.0175
TUBE_R = 0.0127
BELL_R = 0.0175
# The scope's profile, (y, radius); open at both ends so the eye looks through it on the raise.
SCOPE = ((-0.110, OCULAR_R), (-0.090, OCULAR_R), (-0.074, TUBE_R), (0.150, TUBE_R), (0.300, BELL_R))

# ---- the stock: (y, half width, bottom, top, chamfer); GripHand sits on the wrist, ForeHand under 0.5
STOCK = (
    (BUTT_Y, 0.022, -0.100, 0.040, 0.010),
    (-0.325, 0.025, -0.104, 0.046, 0.011),
    (-0.200, 0.024, -0.083, 0.042, 0.011),
    (-0.120, 0.021, -0.058, 0.012, 0.009),
    (-0.020, 0.025, -0.046, 0.002, 0.009),
    (0.020, 0.028, -0.053, -0.006, 0.010),
    (0.300, 0.028, -0.052, -0.004, 0.010),
    (0.560, 0.024, -0.0445, 0.000, 0.009),
    (FOREND_Y, 0.019, -0.036, 0.002, 0.008),
)

# ---- receiver (an 8-point section, from the lower right round over the top) and barrel
RECEIVER = ((0.026, -0.020), (0.026, 0.006), (0.014, 0.024), (-0.014, 0.024),
            (-0.026, 0.006), (-0.026, -0.020), (-0.018, -0.032), (0.018, -0.032))
BARREL = ((0.318, 0.0200), (MUZZLE_Y, 0.0135))      # (y, radius)

BOLT_SHROUD = (-0.062, 0.012, 0.004)                # rear y, radius, height over the bore
BOLT_ROOT = (0.024, 0.055, 0.004)
BOLT_KNOB = (0.084, 0.055, -0.050)
BOLT_R = (0.0065, 0.0050)
KNOB_R = 0.015

MOUNT_Y = ((-0.062, -0.048), (0.068, 0.082))        # two blocks under the tube
MOUNT_HALF_W = 0.007
TURRET_Y = 0.004
TURRET_R = 0.0075
TURRET_H = 0.010

BANDS = ((0.560, 0.582, 0.027, -0.048, 0.023), (0.834, 0.862, 0.022, -0.040, 0.021))   # y0, y1, half w, bottom, top
GUARD = ((0.000, -0.050), (0.012, -0.082), (0.040, -0.094), (0.092, -0.094), (0.120, -0.078), (0.130, -0.050))
GUARD_HALF_W = 0.008
TRIGGER = ((0.062, -0.050), (0.056, -0.068), (0.062, -0.082))
TRIGGER_HALF_W = 0.004


# =============================================================================
# THE MESH -- one accumulator: faces carry a material and a UV per corner
# =============================================================================

class Shape(object):
    def __init__(self):
        self.verts, self.faces, self.uvs, self.mats = [], [], [], []

    def add(self, points):
        base = len(self.verts)
        self.verts.extend(tuple(p) for p in points)
        return list(range(base, base + len(points)))

    def face(self, idx, uvs, mat, away_from=None):
        """A face; wound to turn away from the point away_from when one is given."""
        if away_from is not None:
            pts = [self.verts[i] for i in idx]
            n = mdl._newell(pts)
            c = [sum(p[d] for p in pts) / len(pts) - away_from[d] for d in range(3)]
            if n.x * c[0] + n.y * c[1] + n.z * c[2] < 0.0:
                idx, uvs = list(reversed(idx)), list(reversed(uvs))
        self.faces.append(tuple(idx))
        self.uvs.append([tuple(uv) for uv in uvs])
        self.mats.append(mat)


def _centre(ring):
    return [sum(p[d] for p in ring) / len(ring) for d in range(3)]


def _dist(a, b):
    return math.sqrt(sum((a[d] - b[d]) ** 2 for d in range(3)))


def loft(shape, rings, mat, cap0=None, cap1=None, u0=0.0):
    """A skin through closed rings: u runs along the rings' centres, v round each ring, both in tiles.
    cap0/cap1 name the material that closes an end; None leaves it open."""
    n = len(rings[0])
    ids = [shape.add(r) for r in rings]
    centres = [_centre(r) for r in rings]
    us, vs = [u0], []
    for k in range(1, len(rings)):
        us.append(us[-1] + _dist(centres[k - 1], centres[k]) / SPAN)
    for r in rings:
        arc = [0.0]
        for i in range(n):
            arc.append(arc[-1] + _dist(r[i], r[(i + 1) % n]) / SPAN)
        vs.append(arc)
    for k in range(len(rings) - 1):
        mid = [(centres[k][d] + centres[k + 1][d]) * 0.5 for d in range(3)]
        for i in range(n):
            j = (i + 1) % n
            shape.face([ids[k][i], ids[k][j], ids[k + 1][j], ids[k + 1][i]],
                       [(us[k], vs[k][i]), (us[k], vs[k][i + 1]),
                        (us[k + 1], vs[k + 1][i + 1]), (us[k + 1], vs[k + 1][i])], mat, away_from=mid)
    for cap, k, other in ((cap0, 0, 1), (cap1, len(rings) - 1, len(rings) - 2)):
        if cap is None:
            continue
        c = centres[k]
        a = _unit(tuple(rings[k][0][d] - c[d] for d in range(3)))
        b = _cross(_unit(tuple(mdl._newell(rings[k]))), a)
        flat = [(sum((p[d] - c[d]) * a[d] for d in range(3)) / SPAN + 0.5,
                 sum((p[d] - c[d]) * b[d] for d in range(3)) / SPAN + 0.5) for p in rings[k]]
        shape.face(ids[k], flat, cap, away_from=centres[other])


def chamfered(y, half_w, z0, z1, ch):
    """A chamfered rectangle in the XZ plane at y, from the lower right up and over: the UV seam is lower right."""
    return [(half_w, y, z0 + ch), (half_w, y, z1 - ch), (half_w - ch, y, z1), (-half_w + ch, y, z1),
            (-half_w, y, z1 - ch), (-half_w, y, z0 + ch), (-half_w + ch, y, z0), (half_w - ch, y, z0)]


def circle(y, r, cz=0.0, cx=0.0, sides=8):
    """A regular ring in the XZ plane at y, flats to the sides, top and bottom; same turn as chamfered()."""
    half = math.pi / sides
    return [(cx + r * math.cos(-half + 2.0 * half * i), y, cz + r * math.sin(-half + 2.0 * half * i))
            for i in range(sides)]


def ring_about(centre, axis, r, sides=6):
    """A regular ring of radius r about centre, in the plane across the unit axis."""
    ax = axis
    ref = (0.0, 1.0, 0.0) if abs(ax[1]) < 0.9 else (1.0, 0.0, 0.0)
    a = _unit(_cross(ax, ref))
    b = _cross(ax, a)
    return [tuple(centre[d] + r * (math.cos(t) * a[d] + math.sin(t) * b[d]) for d in range(3))
            for t in (2.0 * math.pi * i / sides for i in range(sides))]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _unit(a):
    m = math.sqrt(sum(c * c for c in a))
    return tuple(c / m for c in a)


def ribbon(shape, path, half_w, mat):
    """A two-sided strip along a (y, z) path, half_w to each side of the bore plane."""
    u = 0.0
    prev = None
    for k, (y, z) in enumerate(path):
        if k:
            u += math.hypot(y - path[k - 1][0], z - path[k - 1][1]) / SPAN
        cur = (shape.add([(-half_w, y, z), (half_w, y, z)]), u)
        if prev is not None:
            (a, ua), (b, ub) = prev, cur
            w = 2.0 * half_w / SPAN
            shape.face([a[0], a[1], b[1], b[0]], [(ua, 0.0), (ua, w), (ub, w), (ub, 0.0)], mat)
        prev = cur


# =============================================================================
# THE RIFLE
# =============================================================================

def _geometry():
    s = Shape()

    # ---- the stock, butt to fore-end tip, one skin; the butt plate is its metal end
    loft(s, [chamfered(*row) for row in STOCK], WOOD, cap0=METAL, cap1=WOOD)

    # ---- receiver running into the barrel
    y0, y1 = RECEIVER_Y
    rings = [[(x, y, z) for (x, z) in RECEIVER] for y in (y0, y1)]
    rings += [circle(y, r) for (y, r) in BARREL]
    loft(s, rings, METAL, cap0=METAL, cap1=METAL)

    # ---- the bolt: shroud out the back, handle down to a ball
    shroud_y, shroud_r, shroud_z = BOLT_SHROUD
    loft(s, [circle(shroud_y, shroud_r * 0.8, cz=shroud_z, sides=6), circle(shroud_y + 0.012, shroud_r, cz=shroud_z, sides=6),
             circle(y0, shroud_r, cz=shroud_z, sides=6)], METAL, cap0=METAL)
    axis = _unit(tuple(BOLT_KNOB[d] - BOLT_ROOT[d] for d in range(3)))
    loft(s, [ring_about(BOLT_ROOT, axis, BOLT_R[0]), ring_about(BOLT_KNOB, axis, BOLT_R[1])], METAL)
    lat = 0.62
    pole = KNOB_R * 0.999
    loft(s, [ring_about(tuple(BOLT_KNOB[d] - axis[d] * pole for d in range(3)), axis, KNOB_R * 0.04),
             ring_about(tuple(BOLT_KNOB[d] - axis[d] * KNOB_R * math.sin(lat) for d in range(3)), axis, KNOB_R * math.cos(lat)),
             ring_about(tuple(BOLT_KNOB[d] + axis[d] * KNOB_R * math.sin(lat) for d in range(3)), axis, KNOB_R * math.cos(lat)),
             ring_about(tuple(BOLT_KNOB[d] + axis[d] * pole for d in range(3)), axis, KNOB_R * 0.04)],
         METAL, cap0=METAL, cap1=METAL)

    # ---- the scope: one open tube on the aim axis, two blocks under it, two turrets
    loft(s, [circle(y, r, cz=SCOPE_Z) for (y, r) in SCOPE], METAL)
    under = SCOPE_Z - TUBE_R * math.cos(math.pi / 8) - 0.0002
    for (a, b) in MOUNT_Y:
        w = MOUNT_HALF_W
        loft(s, [[(w, a, 0.020), (w, a, under), (-w, a, under), (-w, a, 0.020)],
                 [(w, b, 0.020), (w, b, under), (-w, b, under), (-w, b, 0.020)]], METAL, cap0=METAL, cap1=METAL)
    flat = TUBE_R * math.cos(math.pi / 8) - 0.001
    for axis in ((0.0, 0.0, 1.0), (1.0, 0.0, 0.0)):
        foot = (axis[0] * flat, TURRET_Y, SCOPE_Z + axis[2] * flat)
        head = tuple(foot[d] + axis[d] * TURRET_H for d in range(3))
        loft(s, [ring_about(foot, axis, TURRET_R), ring_about(head, axis, TURRET_R)], METAL, cap1=METAL)

    # ---- two iron bands round wood and barrel
    for (a, b, w, z0, z1) in BANDS:
        loft(s, [chamfered(a, w, z0, z1, 0.010), chamfered(b, w, z0, z1, 0.010)], METAL, cap0=METAL, cap1=METAL)

    # ---- trigger guard and trigger: two-sided strips
    ribbon(s, GUARD, GUARD_HALF_W, METAL)
    ribbon(s, TRIGGER, TRIGGER_HALF_W, METAL)
    return s


def _material(name, stem, two_sided):
    """One tile, REPEAT, fully rough; the import hook filters it bilinear."""
    return texel.material(name, mdl.texture(stem), None, roughness=1.0, metallic=0.0, cull=not two_sided)


def build():
    s = _geometry()
    ob = mdl.mesh(OBJECT_NAME, s.verts, s.faces)
    me = ob.data
    me.materials.append(_material("RifleWood", "rifle_wood_albedo", False))
    me.materials.append(_material("RifleMetal", "rifle_metal_albedo", True))     # the open scope and the strips show both faces
    uvl = me.uv_layers.new(name="UVMap")
    for poly, uvs, mat in zip(me.polygons, s.uvs, s.mats):
        poly.material_index = 0 if mat == WOOD else 1
        poly.use_smooth = True
        for li, uv in zip(poly.loop_indices, uvs):
            uvl.data[li].uv = uv

    # Hard only where the form turns hard: end caps and box corners.
    bm = bmesh.new()
    bm.from_mesh(me)
    limit = math.radians(SHARP_DEGREES)
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > limit)
    bm.to_mesh(me)
    bm.free()
    me.update()

    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    print("MDL STATS tris=%d materials=2 tile=%dpx metres_per_texel=%.3f" % (tris, TILE, MPT))
    print("MDL STATS overall_length=%.3f muzzle_local_godot=(0, 0, %.3f)" % (MUZZLE_Y - BUTT_Y, -MUZZLE_Y))
    return ob


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
