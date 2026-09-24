"""
PANOPTICON -- creature2, "the drowned". A 1.8 m waterlogged husk on the
runner's 16-joint rig (same bone names, rest pose and ``Run`` clip): thin,
arms too long with fingers fused into paddles, skin hanging in sheets off
the ribs, head thrown back, a slit for a mouth. Exported as
``assets/models/creature2.glb``.

    tools/modelling/model build creature2
    tools/modelling/model look  creature2 --cam 35,1,50 --margin 9 --res 1600x900

One 32x32 atlas material: pale grey-green skin, dark water-green in the
folds and on every down-facing polygon. Authored in Blender space (+Z up,
faces -Y).
"""

import math
import os
import sys
import zlib

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "creature2"
MESH_NAME = "Creature2"       # -> Armature/Skeleton3D/Creature2 in Godot
ARMATURE_NAME = "Armature"
CLIP_NAME = "Run"
FACING_YAW = 180.0

# ---- atlas ------------------------------------------------------------------
TEX_SIZE = 32
TEX_SEED = 11
SKIN = (176, 192, 178)                                    # pale grey-green
SKIN_SPOTS = [(160, 182, 166), (190, 204, 192), (150, 170, 160), (182, 190, 172)]
MELT = (76, 98, 92)                                       # deep water-green
MELT_SPOTS = [(58, 78, 74), (92, 114, 106), (68, 90, 84)]
ZONE_SKIN = (0, 0, 32, 16)                                # texel rect x0,y0,x1,y1
ZONE_MELT = (0, 16, 32, 32)
ROUGHNESS = 0.36                                          # wet
SPECULAR = 0.50
MELT_DOWNFACING = -0.70      # polygons with normal.z below this are dark
MELT_IN_SKIN = 0.08          # chance a skin-band face runs dark
SKIN_IN_MELT = 0.25          # chance a dark-band face stays pale
LUMP_T = 0.5                 # ring-vertex slide along the bone, x lump

ROCK_GROUND = (0.11, 0.035, 0.035, 1.0)                   # render backdrop only

# ---- master proportions (metres) -- the rig matches runner_build.py ----------
HEIGHT       = 1.800
HIP_Z        = 0.920
SPINE_Z      = 1.080
NECK_Z       = 1.440
HEAD_Z       = 1.540

SHOULDER_X   = 0.165    # narrow
SHOULDER_Y   = -0.010
SHOULDER_Z   = 1.445
ARM_SPLAY    = 8.0
UPPERARM_LEN = 0.470    # too long: paddles hang at the shins
LOWERARM_LEN = 0.440
HAND_LEN     = 0.300

HIP_X        = 0.1047
HIP_JOINT_Z  = 0.8827
LEG_SPLAY    = 1.5
THIGH_LEN    = 0.390
SHIN_LEN     = 0.375
FOOT_LEN     = 0.200
ANKLE_Y      = 0.020
ANKLE_Z      = 0.118
FOOT_PITCH   = 66.2

HEAD_LEN     = 0.260
NECK_LEN     = 0.100

# ---- section profiles ------------------------------------------------------
# ring = (t along bone, half-width, half-depth, world offset (x, y, z), lump, zone)
S, M = ZONE_SKIN, ZONE_MELT
O = (0.0, 0.0, 0.0)

HIPS_RINGS = [(-0.130, 0.135, 0.120, O, 0.05, M),
              (-0.030, 0.150, 0.130, O, 0.06, S),
              ( 0.160, 0.145, 0.120, O, 0.05, S)]

SPINE_RINGS = [(-0.040, 0.140, 0.115, O, 0.04, S),
               ( 0.110, 0.150, 0.120, (0.0, 0.010, 0.0), 0.05, M),   # hollow under the ribs
               ( 0.230, 0.185, 0.140, (0.0, 0.015, 0.0), 0.07, S),   # ribcage
               ( 0.330, 0.200, 0.135, (0.0, 0.010, 0.0), 0.06, S),   # shoulders
               ( 0.400, 0.120, 0.100, O, 0.05, S)]

NECK_RINGS  = [(-0.020, 0.070, 0.070, O, 0.04, M),
               ( 0.120, 0.062, 0.062, (0.0, 0.035, 0.0), 0.04, S)]   # leans back

HEAD_RINGS  = [(-0.030, 0.080, 0.075, (0.0, -0.075, 0.0), 0.05, M),  # jaw, thrust forward
               ( 0.070, 0.110, 0.120, (0.0, -0.045, 0.0), 0.07, S),  # face, turned up
               ( 0.170, 0.120, 0.130, (0.0,  0.050, 0.0), 0.07, S),
               ( 0.260, 0.075, 0.085, (0.0,  0.110, 0.0), 0.05, S)]  # crown, back, z = HEIGHT

UPPERARM_RINGS = [(0.000, 0.062, 0.062, O, 0.05, S),
                  (0.150, 0.058, 0.058, O, 0.06, S),
                  (0.320, 0.048, 0.050, O, 0.04, M),
                  (0.470, 0.044, 0.044, O, 0.04, S)]

LOWERARM_RINGS = [(0.000, 0.042, 0.042, O, 0.04, M),
                  (0.150, 0.044, 0.046, O, 0.05, S),
                  (0.300, 0.038, 0.038, O, 0.04, S),
                  (0.440, 0.034, 0.036, O, 0.04, S)]

HAND_RINGS  = [(0.000, 0.030, 0.040, O, 0.04, S),
               (0.150, 0.020, 0.090, O, 0.05, S),        # paddle spreads sideways
               (0.300, 0.010, 0.078, O, 0.04, M)]        # fused fingertip edge

THIGH_RINGS = [(-0.020, 0.080, 0.085, O, 0.05, S),
               ( 0.120, 0.082, 0.086, O, 0.05, S),
               ( 0.270, 0.066, 0.068, O, 0.04, S),
               ( 0.420, 0.058, 0.060, O, 0.05, M)]

SHIN_RINGS  = [(0.000, 0.052, 0.054, O, 0.04, M),
               (0.090, 0.060, 0.062, O, 0.05, S),
               (0.250, 0.052, 0.052, O, 0.04, S),
               (0.375, 0.050, 0.050, O, 0.04, S)]

FOOT_SOLE  = dict(x=(0.055, 0.150), y=(-0.200, 0.040), z=0.000)   # long, narrow
FOOT_ANKLE = dict(x=(0.070, 0.135), y=(-0.090, 0.040), z=0.140)

SIDES_BODY = 6
SIDES_TORSO = 8
SIDES_HAND = 4

# Skin sheets: thin slabs hanging off the ribs. (bone, top edge, bottom edge),
# each edge = dict(x=(x0, x1), y=(y0, y1), z); the bottom edge flares out.
SHEETS = [("Spine", dict(x=( 0.185,  0.197), y=(-0.070, 0.050), z=1.320),
                    dict(x=( 0.235,  0.247), y=(-0.100, 0.070), z=1.020)),
          ("Spine", dict(x=(-0.197, -0.185), y=(-0.060, 0.060), z=1.300),
                    dict(x=(-0.247, -0.235), y=(-0.090, 0.080), z=0.990)),
          ("Spine", dict(x=(-0.100,  0.100), y=(-0.150, -0.138), z=1.280),
                    dict(x=(-0.130,  0.120), y=(-0.200, -0.188), z=0.980)),
          ("Spine", dict(x=(-0.110,  0.110), y=( 0.130,  0.142), z=1.350),
                    dict(x=(-0.140,  0.130), y=( 0.190,  0.202), z=1.000))]

# Mouth slit: a dark sliver on the upturned face. (top edge, bottom edge).
MOUTH = ("Head", dict(x=(-0.050, 0.050), y=(-0.175, -0.150), z=1.640),
                 dict(x=(-0.050, 0.050), y=(-0.185, -0.160), z=1.625))

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
        shoulder = (side * SHOULDER_X, SHOULDER_Y, SHOULDER_Z)
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
# GEOMETRY
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


def blob(name, head, direction, rings, sides=6, side=1.0):
    """Lumpy capped tube along ``direction``; returns (object, per-face zones)."""
    ex, ey, ez = mdl._basis(direction)
    r = _Rng(zlib.crc32(name.encode("utf-8")))
    verts, faces, zones = [], [], []
    for (t, rx, rz, off, lump, _zone) in rings:
        centre = Vector(head) + ey * t + Vector((off[0] * side, off[1], off[2]))
        for (px, pz) in mdl._section(sides, rx, rz):
            k = 1.0 + lump * (0.7 * r.sf() + 0.3 * r.sf())
            dt = lump * LUMP_T * r.sf()
            verts.append(tuple(centre + ex * (px * k) + ez * (pz * k) + ey * dt))
    n = len(rings)
    for i in range(n - 1):
        a, b = i * sides, (i + 1) * sides
        for j in range(sides):
            q = (j + 1) % sides
            faces.append((a + j, a + q, b + q, b + j))
            zones.append(rings[i][5])
    faces.append(tuple(reversed(range(sides))))
    zones.append(rings[0][5])
    faces.append(tuple(range((n - 1) * sides, n * sides)))
    zones.append(rings[-1][5])
    return mdl.mesh(name, verts, faces), zones


def slab(name, top, bottom):
    """Thin hull between two edge rectangles; a sheet of skin or a slit."""
    def quad(e):
        x0, x1 = e["x"]
        y0, y1 = e["y"]
        z = e["z"]
        return [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
    return mdl.frustum(name, quad(top), quad(bottom))


def build_mesh():
    """One lumpy part per bone plus sheets and the mouth, fused into one mesh."""
    rows = {r[0]: r for r in bone_table()}
    parts, zones = [], []

    def add(bone, ob, z):
        assert len(ob.data.polygons) == len(z), bone
        parts.append((bone, ob))
        zones.extend(z)

    def tube(bone, rings, sides=SIDES_BODY, side=1.0):
        _, _, head, direction, _ = rows[bone]
        ob, z = blob(bone, head, direction, rings, sides=sides, side=side)
        add(bone, ob, z)

    tube("Hips", HIPS_RINGS)
    tube("Spine", SPINE_RINGS, sides=SIDES_TORSO)
    tube("Neck", NECK_RINGS)
    tube("Head", HEAD_RINGS)

    for suffix, side in (("L", 1.0), ("R", -1.0)):
        tube("UpperArm." + suffix, UPPERARM_RINGS, side=side)
        tube("LowerArm." + suffix, LOWERARM_RINGS, side=side)
        tube("Hand." + suffix, HAND_RINGS, sides=SIDES_HAND, side=side)
        tube("Thigh." + suffix, THIGH_RINGS, side=side)
        tube("Shin." + suffix, SHIN_RINGS, side=side)

        def wedge(spec):
            x0, x1 = spec["x"]
            y0, y1 = spec["y"]
            z = spec["z"]
            if side < 0:
                x0, x1 = -x1, -x0
            return [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]

        foot = mdl.frustum("Foot." + suffix, wedge(FOOT_SOLE), wedge(FOOT_ANKLE))
        add("Foot." + suffix, foot, [S] * len(foot.data.polygons))

    for i, (bone, top, bottom) in enumerate(SHEETS):
        ob = slab("Sheet%d" % i, top, bottom)
        add(bone, ob, [S] * len(ob.data.polygons))

    bone, top, bottom = MOUTH
    ob = slab("Mouth", top, bottom)
    add(bone, ob, [M] * len(ob.data.polygons))

    body, groups = mdl.merge_parts(parts, MESH_NAME)
    assert len(body.data.polygons) == len(zones)
    return body, groups, zones

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

    for (x0, y0, x1, y1), base, spots in ((ZONE_SKIN, SKIN, SKIN_SPOTS),
                                          (ZONE_MELT, MELT, MELT_SPOTS)):
        for y in range(y0, y1):
            for x in range(x0, x1):
                j = r.i(-7, 7)
                put(x, y, tuple(max(0, min(255, c + j)) for c in base))
        for _ in range(48):
            put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), r.pick(spots))
    img = bpy.data.images.new("creature2_albedo", TEX_SIZE, TEX_SIZE, alpha=False)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(buf)
    img.update()
    return img


def skin_material(img):
    mat = bpy.data.materials.new("Creature2Skin")
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
    mat.diffuse_color = (0.62, 0.55, 0.40, 1.0)
    return mat


def unwrap(ob, zones):
    """Each face -> a random 2x2 texel window of its zone; undersides go melt."""
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED * 7919 + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        zone = zones[pi]
        if zone == S and r.f() < MELT_IN_SKIN:
            zone = M
        elif zone == M and r.f() < SKIN_IN_MELT:
            zone = S
        x0, y0, x1, y1 = M if poly.normal.z < MELT_DOWNFACING else zone
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
    body, groups, zones = build_mesh()
    albedo = paint_atlas()
    mdl.save_texture(albedo)
    unwrap(body, zones)
    mdl.finish(body, skin_material(albedo), strip_uvs=False)
    mdl.rigid_bind(body, arm, groups)

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
