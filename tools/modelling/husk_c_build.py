"""
PANOPTICON -- husk_c, "the bound". A wrapped, ridged husk built from scratch
as columns of stacked wound bands: each band is a truncated cone whose narrow
top disappears inside the wide base of the next, so the body reads as a
bandaged cocoon with a dark ledge under every ridge, arms bound at the sides,
a few unravelled strips hanging loose. Nothing is borrowed from the runner but
the 16-joint rig (bone names, rest pose, ``Run`` clip); vertices bind to the
nearest bone. Exported as ``assets/models/husk_c.glb``.

    tools/modelling/model build husk_c
    tools/modelling/model look  husk_c --cam 35,1,50 --margin 9 --res 1600x900

One 32x32 atlas: pale bandage, dark rust in every ledge and every third band.
Authored in Blender space (+Z up, faces -Y).
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "husk_c"
MESH_NAME = "HuskC"           # -> Armature/Skeleton3D/HuskC in Godot
ARMATURE_NAME = "Armature"
CLIP_NAME = "Run"
FACING_YAW = 180.0
HEIGHT = 1.800

# ---- atlas ------------------------------------------------------------------
TEX_SIZE = 32
TEX_SEED = 37
PALE = (210, 200, 168)
PALE_SPOTS = [(192, 180, 148), (224, 216, 188), (178, 166, 138)]
DARK = (64, 32, 26)
DARK_SPOTS = [(88, 46, 36), (44, 20, 16), (72, 38, 30)]
ZONE_PALE = (0, 0, 32, 16)
ZONE_DARK = (0, 16, 32, 32)
ROUGHNESS = 0.62
SPECULAR = 0.30
DARK_DOWNFACING = -0.75      # polygons with normal.z below this go dark
DARK_IN_PALE = 0.04          # chance a pale face runs dark: streaks
ROCK_GROUND = (0.11, 0.035, 0.035, 1.0)                   # render backdrop only

# ---- construction -----------------------------------------------------------
JITTER = 0.11                # radial wobble per band vertex
P, D = ZONE_PALE, ZONE_DARK
TAPER = 0.78                 # a band's top radius as a fraction of the next band's base
OVERLAP = 0.03               # metres a band's top pokes up inside the next
TWIST = 11.0                 # degrees each band is wound on from the one below
WRAP_TWIST = 9.0             # degrees of wind within one band, base to top
DARK_EVERY = 3               # every n-th limb band is a dark one; the trunk stays pale
DRIP = 0.05                  # metres a band's lower edge sags unevenly, like wax

# Columns of stacked bands, base to top: (z, x, y, rx, ry).
TORSO = [(0.74, 0.00,  0.00, 0.200, 0.160),
         (0.88, 0.00,  0.01, 0.220, 0.170),
         (1.02, 0.00, -0.01, 0.200, 0.160),
         (1.16, 0.00,  0.00, 0.230, 0.180),
         (1.30, 0.00,  0.03, 0.270, 0.190),
         (1.42, 0.00,  0.04, 0.250, 0.180),
         (1.52, 0.00, -0.02, 0.140, 0.125),
         (1.62, 0.00, -0.08, 0.135, 0.135),
         (1.72, 0.00, -0.13, 0.115, 0.120),
         (1.80, 0.00, -0.16, 0.060, 0.070)]
LEG = [(0.00, 0.130, -0.03, 0.150, 0.190),
       (0.12, 0.130,  0.00, 0.110, 0.110),
       (0.30, 0.135,  0.01, 0.100, 0.100),
       (0.48, 0.135,  0.00, 0.110, 0.110),
       (0.66, 0.130,  0.00, 0.125, 0.120),
       (0.84, 0.120,  0.00, 0.100, 0.100)]
ARM = [(0.60, 0.310, -0.03, 0.060, 0.060),
       (0.76, 0.320, -0.01, 0.075, 0.075),
       (0.94, 0.320,  0.00, 0.080, 0.080),
       (1.12, 0.310,  0.00, 0.085, 0.085),
       (1.30, 0.300,  0.01, 0.090, 0.090),
       (1.46, 0.270,  0.02, 0.070, 0.070)]
TORSO_SIDES, LIMB_SIDES = 8, 6

# Unravelled ribbons hanging off the bands: (root, tip, width). Flat, four-sided, bowing out.
STRIPS = [(( 0.27,  0.05, 1.40), ( 0.30,  0.10, 0.96), 0.035),
          ((-0.28,  0.06, 1.32), (-0.31,  0.12, 0.86), 0.035),
          (( 0.17,  0.12, 0.90), ( 0.19,  0.18, 0.44), 0.030),
          ((-0.31, -0.06, 0.62), (-0.34, -0.08, 0.22), 0.026)]
STRIP_BOW = 0.06

# Nearest-bone binding: a bias (metres) pulls contested vertices onto the trunk.
BONE_BIAS = {"Hips": 0.14, "Spine": 0.12, "Neck": 0.03, "Head": 0.05}

# ---- rig (identical to runner_build.py) --------------------------------------
HIP_Z, SPINE_Z, NECK_Z, HEAD_Z = 0.900, 1.060, 1.400, 1.500
SHOULDER_X, SHOULDER_Z, ARM_SPLAY = 0.1676, 1.4233, 8.0
UPPERARM_LEN, LOWERARM_LEN, HAND_LEN = 0.340, 0.270, 0.220
HIP_X, HIP_JOINT_Z, LEG_SPLAY = 0.1047, 0.8827, 1.5
THIGH_LEN, SHIN_LEN, FOOT_LEN = 0.390, 0.375, 0.200
ANKLE_Y, ANKLE_Z, FOOT_PITCH = 0.020, 0.118, 66.2
HEAD_LEN, NECK_LEN = 0.300, 0.100

# ---- run cycle (identical to runner_build.py) -------------------------------
CYCLE_FRAMES = 20
FPS = 30
THIGH_SWING = 42.0
SHIN_BEND_MID, SHIN_BEND_AMP, SHIN_BEND_PHASE = -42.0, 32.0, 31.0
FOOT_PITCH_MID, FOOT_PITCH_AMP, FOOT_PITCH_PHASE = -8.0, 22.0, 68.8
ARM_SWING_MID, ARM_SWING_AMP, ARM_TUCK = -30.0, 33.0, -14.0
ELBOW_MID, ELBOW_AMP = 101.0, 17.0
HIP_ROLL, HIP_SWAY, HIP_BOB_MID, HIP_BOB_AMP = 7.0, 0.012, -0.045, 0.035
SPINE_LEAN, SPINE_COUNTER = 9.0, 9.0
NECK_TILT, HEAD_TILT, HEAD_ROLL = -2.7, -6.3, 3.6


# =============================================================================
# RIG -- one orientation rule: bone local +Z faces the front (-Y)
# =============================================================================

FRONT = (0.0, -1.0, 0.0)


def _local_x(direction):
    return Vector(direction).normalized().cross(Vector(FRONT)).normalized()


def _arm_dir(side):
    a = math.radians(ARM_SPLAY)
    return (side * math.sin(a), 0.0, -math.cos(a))


def _leg_dir(side):
    a = math.radians(LEG_SPLAY)
    return (side * math.sin(a), 0.0, -math.cos(a))


def _foot_dir(side):
    d = Vector(_leg_dir(side))
    return (Matrix.Rotation(math.radians(FOOT_PITCH), 3, _local_x(d)) @ d).normalized()


def bone_table():
    """(name, parent, head, direction, length) for all sixteen joints."""
    rows = [
        ("Hips",  None,    (0.0, 0.0, HIP_Z),   (0.0, 0.0, 1.0), SPINE_Z - HIP_Z),
        ("Spine", "Hips",  (0.0, 0.0, SPINE_Z), (0.0, 0.0, 1.0), NECK_Z - SPINE_Z),
        ("Neck",  "Spine", (0.0, 0.0, NECK_Z),  (0.0, 0.0, 1.0), NECK_LEN),
        ("Head",  "Neck",  (0.0, 0.0, HEAD_Z),  (0.0, 0.0, 1.0), HEAD_LEN),
    ]
    for suffix, side in (("L", 1.0), ("R", -1.0)):
        ad = _arm_dir(side)
        shoulder = (side * SHOULDER_X, 0.0, SHOULDER_Z)
        elbow = tuple(shoulder[i] + ad[i] * UPPERARM_LEN for i in range(3))
        wrist = tuple(elbow[i] + ad[i] * LOWERARM_LEN for i in range(3))
        rows += [
            ("UpperArm." + suffix, "Spine", shoulder, ad, UPPERARM_LEN),
            ("LowerArm." + suffix, "UpperArm." + suffix, elbow, ad, LOWERARM_LEN),
            ("Hand." + suffix,     "LowerArm." + suffix, wrist, ad, HAND_LEN),
        ]
        ld = _leg_dir(side)
        hip = (side * HIP_X, 0.0, HIP_JOINT_Z)
        knee = tuple(hip[i] + ld[i] * THIGH_LEN for i in range(3))
        ankle = (knee[0] + ld[0] * SHIN_LEN, ANKLE_Y, ANKLE_Z)
        rows += [
            ("Thigh." + suffix, "Hips", hip, ld, THIGH_LEN),
            ("Shin." + suffix,  "Thigh." + suffix, knee, ld, SHIN_LEN),
            ("Foot." + suffix,  "Shin." + suffix, ankle, _foot_dir(side), FOOT_LEN),
        ]
    return rows


def build_armature():
    bones = [(nm, parent, head, direction, length, _local_x(direction))
             for (nm, parent, head, direction, length) in bone_table()]
    connect = {"Spine", "Neck", "Head", "LowerArm.L", "Hand.L",
               "LowerArm.R", "Hand.R", "Shin.L", "Shin.R"}
    return mdl.armature(ARMATURE_NAME, bones, connect=connect)


# =============================================================================
# GEOMETRY -- lofts along curves, accumulated into one mesh
# =============================================================================

class _Rng(object):
    """Deterministic LCG: the model is byte-identical every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0xFFFFFFFF

    def f(self):
        self.s = (1664525 * self.s + 1013904223) & 0xFFFFFFFF
        return self.s / 4294967296.0

    def sf(self):
        return 2.0 * self.f() - 1.0

    def i(self, a, b):
        return a + int(self.f() * (b - a + 1))

    def pick(self, seq):
        return seq[self.i(0, len(seq) - 1)]


class Body(object):
    """Vertex/face/zone accumulator; every part lands in the same mesh."""

    def __init__(self):
        self.verts, self.faces, self.zones, self.force = [], [], [], []

    def add(self, verts, faces, zones, bone=None):
        """``bone`` pins every vertex of the part to that bone instead of the nearest."""
        base = len(self.verts)
        self.verts.extend(verts)
        self.force.extend([bone] * len(verts))
        self.faces.extend(tuple(base + i for i in f) for f in faces)
        self.zones.extend(zones)

    def make(self, name):
        for i, v in enumerate(self.verts):
            self.verts[i] = (v[0], v[1], min(max(v[2], 0.0), HEIGHT))
        return mdl.mesh(name, self.verts, self.faces)


def _ring(c, rx, ry, sides, rot, r, jitter, drip=0.0):
    out = []
    for j in range(sides):
        a = 2.0 * math.pi * (j + 0.5) / sides + rot
        k = 1.0 + jitter * r.sf()
        out.append((c[0] + math.cos(a) * rx * k, c[1] + math.sin(a) * ry * k, c[2] - drip * r.f()))
    return out


def wrap(body, bot, top, sides, rot, zone, seed, cap_top=False):
    """One wound band: a truncated cone from ring ``bot`` up to ring ``top``, dark underside."""
    r = _Rng(seed)
    (bx, by, bz, brx, bry), (tx, ty, tz, trx, try_) = bot, top
    verts = _ring((bx, by, bz), brx, bry, sides, rot, r, JITTER, drip=DRIP)
    verts += _ring((tx, ty, tz), trx, try_, sides, rot + math.radians(WRAP_TWIST), r, JITTER)
    faces, zones = [], []
    for j in range(sides):
        q = (j + 1) % sides
        faces.append((j, q, sides + q, sides + j))
        zones.append(zone)
    faces.append(tuple(reversed(range(sides))))
    zones.append(D)
    if cap_top:
        faces.append(tuple(range(sides, 2 * sides)))
        zones.append(zone)
    body.add(verts, faces, zones)


def column(body, profile, sides, seed, cap_top=False, mirror=1.0, dark_every=0):
    """Stack bands up a profile; each band's top hides inside the next band's base."""
    n = len(profile)
    for i in range(n - 1):
        z0, x0, y0, rx0, ry0 = profile[i]
        z1, x1, y1, rx1, ry1 = profile[i + 1]
        last = (i == n - 2)
        over = 0.0 if (last and cap_top) else OVERLAP
        zone = D if (dark_every and i % dark_every == dark_every - 1) else P
        wrap(body, (x0 * mirror, y0, z0, rx0, ry0),
             (x1 * mirror, y1, z1 + over, rx1 * TAPER, ry1 * TAPER),
             sides, math.radians(TWIST * i) * mirror, zone, seed + i,
             cap_top=(last and cap_top))


def build_mesh():
    body = Body()
    column(body, TORSO, TORSO_SIDES, 100, cap_top=True)
    for m in (1.0, -1.0):
        column(body, LEG, LIMB_SIDES, 200 if m > 0 else 300, mirror=m, dark_every=DARK_EVERY)
        column(body, ARM, LIMB_SIDES, 400 if m > 0 else 500, mirror=m, dark_every=DARK_EVERY)
    for i, (root, tip, w) in enumerate(STRIPS):
        mid = Vector(root).lerp(Vector(tip), 0.5)
        out = Vector((mid.x, mid.y, 0.0)).normalized()
        mid = tuple(mid + out * STRIP_BOW)
        wrap(body, tuple(tip) + (w * 0.4, w * 0.12), mid + (w * 0.9, w * 0.25), 4, 0.6, D, 600 + i)
        wrap(body, mid + (w * 0.9, w * 0.25), tuple(root) + (w, w * 0.3), 4, 0.6, D, 620 + i)
    ob = body.make(MESH_NAME)
    assert len(ob.data.polygons) == len(body.zones)
    return ob, body.zones, body.force


# =============================================================================
# BINDING -- every vertex to its nearest bone segment (rigid)
# =============================================================================

def _seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def bind_groups(ob, force):
    segs = [(nm, Vector(head), Vector(head) + Vector(d).normalized() * L)
            for (nm, _, head, d, L) in bone_table()]
    groups = {}
    for v in ob.data.vertices:
        best, bd = force[v.index], 1e9
        for nm, a, b in segs:
            if best:
                break
            d = _seg_dist(v.co, a, b) - BONE_BIAS.get(nm, 0.0)
            if d < bd:
                best, bd = nm, d
        groups.setdefault(best, []).append(v.index)
    print("MDL STATS bound=%s" % ",".join("%s:%d" % (k, len(v)) for k, v in sorted(groups.items())))
    return groups


# =============================================================================
# ATLAS
# =============================================================================

def _s2l(rgb):
    out = []
    for c in rgb:
        c /= 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return out


def paint_atlas():
    r = _Rng(TEX_SEED)
    buf = [1.0] * (TEX_SIZE * TEX_SIZE * 4)

    def put(x, y, rgb):
        o = (y * TEX_SIZE + x) * 4
        buf[o:o + 3] = _s2l(rgb)

    for (x0, y0, x1, y1), base, spots in ((ZONE_PALE, PALE, PALE_SPOTS),
                                          (ZONE_DARK, DARK, DARK_SPOTS)):
        for y in range(y0, y1):
            for x in range(x0, x1):
                j = r.i(-7, 7)
                put(x, y, tuple(max(0, min(255, c + j)) for c in base))
        for _ in range(48):
            put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), r.pick(spots))
    img = bpy.data.images.new(NAME + "_albedo", TEX_SIZE, TEX_SIZE, alpha=False)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(buf)
    img.update()
    return img


def skin_material(img):
    mat = bpy.data.materials.new("HuskSkin")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = img
    node.interpolation = "Closest"
    node.location = (-460, 260)
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = ROUGHNESS
    bsdf.inputs["Metallic"].default_value = 0.0
    for key in ("Specular IOR Level", "Specular"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = SPECULAR
            break
    mat.diffuse_color = (0.7, 0.66, 0.55, 1.0)
    return mat


def unwrap(ob, zones):
    """Each face -> a random 2x2 texel window of its zone; undersides go dark."""
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED * 7919 + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        zone = zones[pi]
        if zone == P and r.f() < DARK_IN_PALE:
            zone = D
        x0, y0, x1, y1 = D if poly.normal.z < DARK_DOWNFACING else zone
        tx, ty = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        corners = [(tx + 0.5, ty + 0.5), (tx + 1.5, ty + 0.5),
                   (tx + 1.5, ty + 1.5), (tx + 0.5, ty + 1.5)]
        for k, li in enumerate(poly.loop_indices):
            u, v = corners[k % 4]
            uvl.data[li].uv = (u / TEX_SIZE, v / TEX_SIZE)


# =============================================================================
# ANIMATION -- the runner's Run, verbatim
# =============================================================================

def _phase(i, n, offset_deg=0.0):
    return 2.0 * math.pi * i / (n - 1) + math.radians(offset_deg)


def run_curves():
    curves = {}

    def sway(i, n):
        return {"euler": (0.0, 0.0, HIP_ROLL * math.sin(_phase(i, n))),
                "location": (HIP_SWAY * math.sin(_phase(i, n)),
                             HIP_BOB_MID + HIP_BOB_AMP * math.cos(2.0 * _phase(i, n)),
                             0.0)}

    curves["Hips"] = sway
    curves["Spine"] = lambda i, n: {
        "euler": (SPINE_LEAN, 0.0, -SPINE_COUNTER * math.sin(_phase(i, n)))}
    curves["Neck"] = lambda i, n: {"euler": (NECK_TILT, 0.0, 0.0)}
    curves["Head"] = lambda i, n: {
        "euler": (HEAD_TILT, 0.0, HEAD_ROLL * math.sin(_phase(i, n)))}

    for suffix, lag in (("L", 0.0), ("R", 180.0)):
        sign = 1.0 if suffix == "L" else -1.0

        def thigh(i, n, lag=lag):
            return {"euler": (THIGH_SWING * math.sin(_phase(i, n, lag)), 0.0, 0.0)}

        def shin(i, n, lag=lag):
            return {"euler": (SHIN_BEND_MID + SHIN_BEND_AMP
                              * math.sin(_phase(i, n, lag + SHIN_BEND_PHASE)), 0.0, 0.0)}

        def foot(i, n, lag=lag):
            return {"euler": (FOOT_PITCH_MID + FOOT_PITCH_AMP
                              * math.sin(_phase(i, n, lag + FOOT_PITCH_PHASE)), 0.0, 0.0)}

        def upper(i, n, lag=lag, sign=sign):
            return {"euler": (ARM_SWING_MID - ARM_SWING_AMP
                              * math.sin(_phase(i, n, lag)), 0.0, sign * ARM_TUCK)}

        def elbow(i, n, lag=lag):
            return {"euler": (ELBOW_MID - ELBOW_AMP * math.sin(_phase(i, n, lag)), 0.0, 0.0)}

        curves["Thigh." + suffix] = thigh
        curves["Shin." + suffix] = shin
        curves["Foot." + suffix] = foot
        curves["UpperArm." + suffix] = upper
        curves["LowerArm." + suffix] = elbow

    return curves


# =============================================================================
# BUILD
# =============================================================================

def build():
    arm = build_armature()
    body, zones, force = build_mesh()
    albedo = paint_atlas()
    mdl.save_texture(albedo)
    unwrap(body, zones)
    mdl.finish(body, skin_material(albedo), strip_uvs=False)
    mdl.rigid_bind(body, arm, bind_groups(body, force))

    mdl.bake_pose(arm, CLIP_NAME, frames=list(range(1, CYCLE_FRAMES + 2)),
                  fps=FPS, curves=run_curves())
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    print("MDL STATS bones=%d clip=%s frames=%d..%d fps=%d"
          % (len(arm.data.bones), CLIP_NAME, 1, CYCLE_FRAMES + 1, FPS))
    return [arm, body]


def post(spec, objects):
    """Render only: hell-rock ground, and a rock wall behind the model for a single ad-hoc cam."""
    spec["ground_color"] = list(ROCK_GROUND)
    cams = spec.get("cams") or []
    if len(cams) != 1 or spec.get("views"):
        return
    rock = mdl.flat_material("Backdrop", ROCK_GROUND, roughness=0.95)
    az = math.radians(float(cams[0][0]) + FACING_YAW)
    d = Vector((math.sin(az), -math.cos(az), 0.0))
    bpy.ops.mesh.primitive_plane_add(size=1.0)
    wall = bpy.context.active_object
    wall.name = "Backdrop"
    wall.scale = (80.0, 30.0, 1.0)
    wall.location = -d * 8.0 + Vector((0.0, 0.0, 12.0))
    wall.rotation_euler = (math.pi / 2.0, 0.0, az)
    wall.data.materials.append(rock)
    bpy.ops.mesh.primitive_plane_add(size=240.0, location=(0.0, 0.0, -0.001))
    floor = bpy.context.active_object
    floor.name = "BackdropFloor"
    floor.data.materials.append(rock)
    print("MDL note: backdrop wall + floor added for the distance test")


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=post)
