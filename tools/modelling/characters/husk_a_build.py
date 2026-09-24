"""
PANOPTICON -- husk_a, "the strung". A 1.8 m tall, stringy husk built from
scratch: a bent stalk lofted from irregular pentagons, rope arms hanging past
the knees, stilt legs ending in small pools, and a mane of strands. Nothing is
borrowed from the runner but the 16-joint rig (bone names, rest pose, ``Run``
clip); vertices bind to the nearest bone. Exported as ``assets/models/husk_a.glb``.

    tools/modelling/model build husk_a
    tools/modelling/model look  husk_a --cam 35,1,50 --margin 9 --res 1600x900

One 32x32 atlas: bone-pale body, near-black strands, pools and undersides.
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

NAME = "husk_a"
MESH_NAME = "HuskA"           # -> Armature/Skeleton3D/HuskA in Godot
ARMATURE_NAME = "Armature"
CLIP_NAME = "Run"
FACING_YAW = 180.0
HEIGHT = 1.800

# ---- atlas ------------------------------------------------------------------
TEX_SIZE = 32
TEX_SEED = 11
PALE = (208, 200, 178)
PALE_SPOTS = [(190, 184, 160), (222, 216, 194), (176, 172, 150)]
DARK = (46, 28, 34)
DARK_SPOTS = [(68, 42, 48), (32, 18, 24), (56, 34, 40)]
ZONE_PALE = (0, 0, 32, 16)
ZONE_DARK = (0, 16, 32, 32)
ROUGHNESS = 0.62
SPECULAR = 0.30
DARK_DOWNFACING = -0.75      # polygons with normal.z below this go dark
DARK_IN_PALE = 0.08          # chance a pale face runs dark: streaks
ROCK_GROUND = (0.11, 0.035, 0.035, 1.0)                   # render backdrop only

# ---- construction -----------------------------------------------------------
JITTER = 0.10                # radial wobble per ring vertex
P, D = ZONE_PALE, ZONE_DARK

# The stalk: one loft from crotch to crown, (z, y, rx, ry). It hunches, pinches
# into a neck, crests at 1.80 and curls over to hang, faceless, in front of the chest.
STALK = [(0.70,  0.00, 0.105, 0.095),
         (0.84,  0.01, 0.130, 0.110),
         (0.98,  0.00, 0.100, 0.090),
         (1.12,  0.03, 0.140, 0.115),
         (1.27,  0.07, 0.170, 0.125),
         (1.40,  0.08, 0.175, 0.120),
         (1.52,  0.04, 0.110, 0.100),
         (1.65, -0.04, 0.125, 0.130),
         (1.76, -0.14, 0.130, 0.135),
         (1.78, -0.26, 0.110, 0.115),
         (1.68, -0.36, 0.085, 0.090),
         (1.54, -0.40, 0.045, 0.050),
         (1.44, -0.40, 0.020, 0.025)]
STALK_SIDES = 5

# Stilt legs, ankle to hip: (z, x, y, r). A knot at the knee.
LEG = [(0.10, 0.110, 0.02, 0.040),
       (0.24, 0.120, 0.03, 0.045),
       (0.40, 0.130, 0.02, 0.062),
       (0.46, 0.130, 0.01, 0.050),
       (0.62, 0.120, 0.00, 0.048),
       (0.78, 0.100, 0.00, 0.066),
       (0.86, 0.080, 0.00, 0.082)]
LEG_SIDES = 4

# A small pool where each stilt meets the ground: (z, x, y, rx, ry).
FOOT = [(0.00, 0.110, -0.05, 0.105, 0.165),
        (0.07, 0.110, -0.02, 0.055, 0.075)]
FOOT_SIDES = 5

# Rope arms hanging from behind the shoulders, (z, x, y, r); the right one is shorter.
ARM = [(1.46, 0.150,  0.06, 0.055),
       (1.30, 0.230,  0.08, 0.050),
       (1.10, 0.265,  0.07, 0.042),
       (0.90, 0.255,  0.05, 0.038),
       (0.72, 0.230,  0.02, 0.052),
       (0.52, 0.205, -0.02, 0.034),
       (0.34, 0.185, -0.05, 0.024),
       (0.20, 0.175, -0.07, 0.012)]
ARM_R_SCALE = 0.86
ARM_SIDES = 4

# Strands: (root, length, root radius, zone). Three-sided; each bows outward
# from its root and then hangs straight down, thinning to a point.
STRANDS = [((0.06,  0.10, 1.66), 0.56, 0.028, P),
           ((-0.07, 0.10, 1.64), 0.58, 0.026, P),
           ((0.00,  0.12, 1.56), 0.60, 0.030, P),
           ((0.15,  0.09, 1.42), 0.58, 0.024, D),
           ((-0.15, 0.09, 1.42), 0.62, 0.024, P),
           ((0.09,  0.11, 1.28), 0.56, 0.022, P),
           ((-0.10, 0.11, 1.22), 0.56, 0.022, D),
           ((0.00,  0.12, 1.12), 0.52, 0.026, P),
           ((0.08, -0.36, 1.58), 0.40, 0.018, D),
           ((-0.07, -0.37, 1.56), 0.42, 0.018, D),
           ((0.10, -0.08, 0.84), 0.44, 0.020, P),
           ((-0.11, -0.07, 0.82), 0.46, 0.020, D),
           ((0.25,  0.05, 1.08), 0.46, 0.016, P),
           ((-0.25, 0.05, 1.10), 0.44, 0.016, D),
           ((0.19, -0.06, 0.22), 0.22, 0.012, D),
           ((-0.19, -0.06, 0.34), 0.26, 0.012, D)]
STRAND_SIDES = 3
STRAND_BOW = 0.12            # metres a strand bows outward before it hangs

# Nearest-bone binding: a bias (metres) pulls contested vertices onto the trunk.
BONE_BIAS = {"Hips": 0.12, "Spine": 0.12, "Neck": 0.05, "Head": 0.05}

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


def loft(body, rings, sides, zone, seed, jitter=JITTER, cap_lo=True, cap_hi=True):
    """Capped tube through ``rings`` [(centre, rx, ry)]; the section follows the curve."""
    r = _Rng(seed)
    n = len(rings)
    verts, faces, zones = [], [], []
    for i, (c, rx, ry) in enumerate(rings):
        p, q = Vector(rings[max(i - 1, 0)][0]), Vector(rings[min(i + 1, n - 1)][0])
        t = (q - p).normalized()
        ex = Vector((1.0, 0.0, 0.0))
        ex = (ex - t * ex.dot(t)).normalized()
        ez = t.cross(ex)
        for j in range(sides):
            a = 2.0 * math.pi * (j + 0.5) / sides
            k = 1.0 + jitter * r.sf()
            verts.append(tuple(Vector(c) + ex * (math.cos(a) * rx * k) + ez * (math.sin(a) * ry * k)))
    for i in range(n - 1):
        a, b = i * sides, (i + 1) * sides
        for j in range(sides):
            q = (j + 1) % sides
            faces.append((a + j, a + q, b + q, b + j))
            zones.append(zone)
    if cap_lo:
        faces.append(tuple(reversed(range(sides))))
        zones.append(zone)
    if cap_hi:
        faces.append(tuple(range((n - 1) * sides, n * sides)))
        zones.append(zone)
    body.add(verts, faces, zones)


def build_mesh():
    body = Body()
    loft(body, [(Vector((0.0, y, z)), rx, ry) for (z, y, rx, ry) in STALK], STALK_SIDES, P, 1)
    for side in (1.0, -1.0):
        s = 2 if side > 0 else 3
        loft(body, [(Vector((side * x, y, z)), r, r) for (z, x, y, r) in LEG], LEG_SIDES, P, 10 + s)
        loft(body, [(Vector((side * x, y, z)), rx, ry) for (z, x, y, rx, ry) in FOOT], FOOT_SIDES, D, 20 + s)
        az = lambda z: z if side > 0 else ARM[0][0] - (ARM[0][0] - z) * ARM_R_SCALE
        loft(body, [(Vector((side * x, y, az(z))), r, r) for (z, x, y, r) in ARM], ARM_SIDES, P, 30 + s)
    for i, (root, length, r0, zone) in enumerate(STRANDS):
        root = Vector(root)
        out = Vector((root.x, root.y, 0.0))
        out = out.normalized() if out.length > 1e-6 else Vector((0.0, 1.0, 0.0))
        down = Vector((0.0, 0.0, -length))
        rings = [(root, r0, r0),
                 (root + out * STRAND_BOW + down * 0.30, r0 * 0.8, r0 * 0.8),
                 (root + out * (STRAND_BOW * 0.9) + down * 0.65, r0 * 0.5, r0 * 0.5),
                 (root + out * (STRAND_BOW * 0.6) + down, r0 * 0.15, r0 * 0.15)]
        loft(body, rings, STRAND_SIDES, zone, 40 + i, jitter=0.05)
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
