"""
PANOPTICON -- husk_b, "the pooled". A squat, heavy husk built from scratch as
a cluster of lumpy blobs: a wide puddle at the feet, thick leg columns, a
paunch, a hunched chest, a hump rising to 1.8 m with a faceless dome sunk in
front of it, and sack arms pooling at the ends. Nothing is borrowed from the
runner but the 16-joint rig (bone names, rest pose, ``Run`` clip); vertices
bind to the nearest bone. Exported as ``assets/models/husk_b.glb``.

    tools/modelling/model build husk_b
    tools/modelling/model look  husk_b --cam 35,1,50 --margin 9 --res 1600x900

One 32x32 atlas: pale sick-pink mass, near-black pool, knees and undersides.
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

NAME = "husk_b"
MESH_NAME = "HuskB"           # -> Armature/Skeleton3D/HuskB in Godot
ARMATURE_NAME = "Armature"
CLIP_NAME = "Run"
FACING_YAW = 180.0
HEIGHT = 1.800

# ---- atlas ------------------------------------------------------------------
TEX_SIZE = 32
TEX_SEED = 23
PALE = (214, 192, 172)
PALE_SPOTS = [(196, 172, 156), (226, 206, 188), (184, 160, 146)]
DARK = (52, 26, 30)
DARK_SPOTS = [(74, 40, 44), (36, 16, 20), (62, 32, 36)]
ZONE_PALE = (0, 0, 32, 16)
ZONE_DARK = (0, 16, 32, 32)
ROUGHNESS = 0.62
SPECULAR = 0.30
DARK_DOWNFACING = -0.75      # polygons with normal.z below this go dark
DARK_IN_PALE = 0.08          # chance a pale face runs dark: streaks
ROCK_GROUND = (0.11, 0.035, 0.035, 1.0)                   # render backdrop only

# ---- construction -----------------------------------------------------------
JITTER = 0.12                # radial wobble per blob vertex
P, D = ZONE_PALE, ZONE_DARK

# The blob cluster: (name, centre, (rx, ry, rz), sides, rings, zone, sag).
# A name ending in L is mirrored to R. sag stretches the lower half downward.
BLOBS = [("pool",      ( 0.00,  0.02, 0.09), (0.66, 0.50, 0.11), 8, 3, D, 0.0),
         ("footL",     ( 0.20, -0.06, 0.08), (0.24, 0.30, 0.10), 6, 2, D, 0.0),
         ("legL",      ( 0.16,  0.00, 0.40), (0.18, 0.17, 0.30), 7, 3, P, 0.2),
         ("kneeL",     ( 0.17, -0.04, 0.30), (0.16, 0.15, 0.09), 6, 2, D, 0.0),
         ("pelvis",    ( 0.00,  0.02, 0.84), (0.42, 0.33, 0.24), 8, 3, P, 0.3),
         ("belly",     ( 0.00, -0.08, 1.04), (0.36, 0.30, 0.20), 7, 3, P, 0.2),
         ("chest",     ( 0.00,  0.03, 1.30), (0.44, 0.31, 0.22), 8, 3, P, 0.1),
         ("hump",      ( 0.00,  0.12, 1.56), (0.31, 0.25, 0.26), 8, 3, P, 0.0),
         ("head",      ( 0.00, -0.15, 1.57), (0.17, 0.17, 0.16), 6, 3, P, 0.2),
         ("shoulderL", ( 0.40,  0.02, 1.38), (0.21, 0.18, 0.16), 6, 3, P, 0.2),
         ("armL",      ( 0.49,  0.00, 1.10), (0.12, 0.12, 0.25), 6, 3, P, 0.3),
         ("handL",     ( 0.51, -0.03, 0.78), (0.15, 0.14, 0.16), 6, 3, P, 0.3),
         ("dripA",     ( 0.24, -0.30, 0.98), (0.05, 0.05, 0.16), 4, 2, D, 0.6),
         ("dripB",     (-0.30,  0.10, 1.22), (0.05, 0.05, 0.14), 4, 2, D, 0.6)]

# Parts pinned to one bone: the pool drags with the hips instead of tearing between the feet.
PINNED = {"pool": "Hips", "footL": "Hips"}

# Nearest-bone binding: a bias (metres) pulls contested vertices onto the trunk.
BONE_BIAS = {"Hips": 0.15, "Spine": 0.12, "Neck": 0.00, "Head": 0.06}

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


def blob(body, centre, radii, sides, rings, zone, seed, sag=0.0, jitter=JITTER, bone=None):
    """Lumpy ellipsoid: ``rings`` staggered latitude rings between two poles."""
    r = _Rng(seed)
    c = Vector(centre)
    rx, ry, rz = radii
    verts, faces, zones = [], [], []
    verts.append((c.x, c.y, c.z - rz * (1.0 + sag)))
    for i in range(rings):
        phi = -math.pi / 2.0 + math.pi * (i + 1) / (rings + 1)
        cz, cr = math.sin(phi), math.cos(phi)
        zz = rz * cz * ((1.0 + sag) if cz < 0 else 1.0)
        for j in range(sides):
            a = 2.0 * math.pi * (j + 0.5 * (i % 2)) / sides
            k = 1.0 + jitter * r.sf()
            verts.append((c.x + rx * cr * math.cos(a) * k,
                          c.y + ry * cr * math.sin(a) * k,
                          c.z + zz + rz * 0.5 * jitter * r.sf()))
    top = len(verts)
    verts.append((c.x, c.y, c.z + rz))
    for j in range(sides):
        q = (j + 1) % sides
        faces.append((0, 1 + q, 1 + j))
        zones.append(zone)
    for i in range(rings - 1):
        a, b = 1 + i * sides, 1 + (i + 1) * sides
        for j in range(sides):
            q = (j + 1) % sides
            faces.append((a + j, a + q, b + q, b + j))
            zones.append(zone)
    a = 1 + (rings - 1) * sides
    for j in range(sides):
        q = (j + 1) % sides
        faces.append((top, a + j, a + q))
        zones.append(zone)
    body.add(verts, faces, zones, bone=bone)


def build_mesh():
    body = Body()
    for i, (nm, centre, radii, sides, rings, zone, sag) in enumerate(BLOBS):
        pin = PINNED.get(nm)
        blob(body, centre, radii, sides, rings, zone, 100 + i, sag, bone=pin)
        if nm.endswith("L"):
            cx, cy, cz = centre
            blob(body, (-cx, cy, cz), radii, sides, rings, zone, 200 + i, sag, bone=pin)
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
