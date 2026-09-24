"""
PANOPTICON -- prisoner2, the second prisoner. Same 16-joint rig, same five
clips, same node layout as the runner; a different body: slender, hunched,
long thin limbs, and a big angular wedge of a head.

    tools/modelling/model build prisoner2 --cpu --samples 24

The rig, the clip tables and the clip code below are the runner's, COPIED
rather than imported: the pipeline ships exactly one build script to the PC,
so ``from runner_build import ...`` cannot resolve there. Anything that the
game addresses -- node path ``Armature/Skeleton3D/Runner``, the five clips and
their frame counts, the sixteen bone names -- is byte-identical
in effect, so this .glb is a drop-in swap for runner.glb.

What differs from the runner: the REST pose carries the hunch (Spine and Neck
tilt forward, so the head sits ahead of the chest), the section tables are
thinner, limbs are longer, the head is an explicit hard-edged skull rather
than a tube, and the body is textured from its own 32x32 atlas instead of one
flat colour.

Authored in BLENDER space (+Z up, model faces -Y).
"""

import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "prisoner2"
MESH_NAME = "Runner"          # -> Armature/Skeleton3D/Runner, as the game asks
ARMATURE_NAME = "Armature"
CLIP_NAME = "Run"
JUMP_CLIP_NAME = "Jump"
DEATH_CLIP_NAME = "Death"
AIM_CLIP_NAME = "Aim"
SHOVE_CLIP_NAME = "Shove"
FACING_YAW = 180.0

# ---- atlas ------------------------------------------------------------------
SHIRT_MATERIAL = "Shirt"       # the surface MatchController tints per team
TEX_SIZE = 32
TEX_SEED = 23
ROUGHNESS = 0.88
SPECULAR = 0.18

# (x0, y0, x1, y1) zones of the atlas, and the colour each is dithered around.
ZONE_SKIN    = (0, 0, 16, 16)
ZONE_SHIRT   = (16, 0, 32, 16)
ZONE_TROUSER = (0, 16, 16, 32)
ZONE_DARK    = (16, 16, 32, 32)

SKIN    = (150, 156, 162)      # desaturated blue-grey
SHIRT   = (198, 200, 202)      # near-neutral: the team tint rides on this
TROUSER = (52, 56, 64)
DARK    = (28, 30, 36)

ZONE_SPOTS = {
    ZONE_SKIN:    [(138, 144, 152), (162, 168, 174), (128, 134, 142)],
    ZONE_SHIRT:   [(186, 188, 190), (212, 214, 216), (178, 180, 182)],
    ZONE_TROUSER: [(44, 48, 56), (62, 66, 74), (38, 42, 50)],
    ZONE_DARK:    [(22, 24, 30), (36, 38, 44), (18, 20, 26)],
}
JITTER = 7                     # per-texel dither, +/- this many 8-bit steps
DARK_DOWNFACING = -0.62        # faces looking this far down take the dark zone

PART_ZONE = {
    "Hips": ZONE_TROUSER, "Spine": ZONE_SHIRT, "Neck": ZONE_SKIN,
    "Head": ZONE_SKIN,
    "UpperArm": ZONE_SHIRT, "LowerArm": ZONE_SKIN, "Hand": ZONE_SKIN,
    "Thigh": ZONE_TROUSER, "Shin": ZONE_TROUSER, "Foot": ZONE_DARK,
}

# ---- master proportions (metres) -------------------------------------------
HEIGHT       = 1.790   # crown; the hunch spends the rest of the 1.8 envelope
HIP_Z        = 0.900
SPINE_Z      = 1.020

SPINE_TILT   = 18.0    # degrees the chest leans forward AT REST -- the hunch
SPINE_LEN    = 0.357
NECK_TILT    = 32.0    # the neck carries the head out ahead of the chest
NECK_LEN     = 0.110
HEAD_TILT    = 8.0
HEAD_LEN     = 0.300

SHOULDER_X   = 0.1080  # narrow shoulders -- narrower than the head is wide
SHOULDER_Y   = -0.075  # and set forward, riding the leaning chest
SHOULDER_Z   = 1.3150
ARM_SPLAY    = 7.0
UPPERARM_LEN = 0.325   # long, thin arms: the wrist hangs near the knee
LOWERARM_LEN = 0.300
HAND_LEN     = 0.200

HIP_X        = 0.0980
HIP_JOINT_Z  = 0.8850
LEG_SPLAY    = 1.5
THIGH_LEN    = 0.400
SHIN_LEN     = 0.385
FOOT_LEN     = 0.210
ANKLE_Y      = 0.022
ANKLE_Z      = 0.100
FOOT_PITCH   = 66.2

# ---- section profiles ------------------------------------------------------
# (distance along the bone from its head, half-width in X, half-depth in Y).
# 6 sides for the torso, 4 for every limb: square-section limbs are what make
# the whole figure read as a handful of hard planes rather than tubes. Where a
# ring steps OUT and straight back in again -- collar, belt, cuff, knee, elbow
# -- that step is a deliberate plane break, not a bulge.
SIDES_BODY = 6
SIDES_LIMB = 4

HIPS_RINGS  = [(-0.085, 0.104, 0.092),
               (-0.010, 0.122, 0.108),
               ( 0.070, 0.112, 0.098),
               ( 0.092, 0.120, 0.104),   # belt, standing proud of the trousers
               ( 0.130, 0.106, 0.092)]

SPINE_RINGS = [(-0.045, 0.112, 0.092),   # narrow waist
               ( 0.150, 0.135, 0.106),   # ribs
               ( 0.290, 0.138, 0.100),   # shoulder shelf, flat front-to-back
               ( 0.318, 0.112, 0.090),
               ( 0.330, 0.118, 0.096),   # collar lip, proud of the shirt
               ( 0.352, 0.070, 0.066)]   # neck hole

NECK_RINGS  = [(-0.030, 0.052, 0.054),   # thin neck; the top ring runs on
               ( 0.190, 0.048, 0.050)]   # past the joint, INTO the skull

# ~0.065 m across the upper arm, ~0.055 the forearm.
UPPERARM_RINGS = [(0.015, 0.032, 0.034),
                  (0.075, 0.036, 0.038),   # small deltoid
                  (0.250, 0.029, 0.031),
                  (0.292, 0.035, 0.037),   # sleeve cuff
                  (0.320, 0.027, 0.029)]

LOWERARM_RINGS = [(0.000, 0.030, 0.032),
                  (0.055, 0.031, 0.033),
                  (0.230, 0.025, 0.027),
                  (0.295, 0.022, 0.024)]   # thin wrist

HAND_RINGS  = [(0.000, 0.026, 0.019),    # a mitten wedge, wider than the wrist
               (0.045, 0.048, 0.028),
               (0.145, 0.046, 0.026),
               (0.195, 0.030, 0.018)]

# ~0.09 m across the thigh, ~0.07 the shin, with a plane break at the knee.
THIGH_RINGS = [(-0.010, 0.046, 0.048),
               ( 0.100, 0.048, 0.050),
               ( 0.290, 0.038, 0.040),
               ( 0.372, 0.045, 0.047),   # knee
               ( 0.400, 0.036, 0.038)]

SHIN_RINGS  = [(-0.008, 0.040, 0.044),   # knee, from below
               ( 0.060, 0.035, 0.038),
               ( 0.150, 0.034, 0.037),   # calf
               ( 0.300, 0.029, 0.031),
               ( 0.385, 0.026, 0.028)]   # thin ankle

# Simple wedges: a long sole, a short top, so the front face slopes to the toe.
FOOT_SOLE  = dict(x=(0.022, 0.112), y=(-0.190, 0.050), z=0.000)
FOOT_ANKLE = dict(x=(0.032, 0.098), y=(-0.075, 0.052), z=0.112)

# ---- the head ---------------------------------------------------------------
# A face built out of planes, on a tall back-swept cranium. Three sections --
# the flat face, the cheekbone, the nape -- each authored as a 5-row by 5-column
# lattice, (z, half_width) per row; the 16 border points of one section stitch
# straight to the next, and the front section's 25 points ARE the face, so the
# brow, eye sockets, cheeks, mouth and chin are all separate hard quads.
#
#   row 0 brow    -- juts forward; the plane below it is the overhang
#   row 1 eye     -- pushed BACK except at the centre, so the sockets are hollows
#   row 2 cheek   -- the widest line on the whole model
#   row 3 mouth
#   row 4 chin    -- a small forward point
HEAD_COLS = [1.0, 0.44, 0.0, -0.44, -1.0]

HEAD_FACE_Y = -0.245
HEAD_FACE_ROWS = [(1.648, 0.098),   # brow
                  (1.598, 0.115),   # eye
                  (1.552, 0.118),   # cheek
                  (1.508, 0.070),   # mouth
                  (1.466, 0.030)]   # chin
# y offset per (row, col): negative is forward, positive is back into the skull.
HEAD_FACE_DY = [
    [-0.014, -0.014, -0.014, -0.014, -0.014],   # the brow ridge, overhanging
    [ 0.006,  0.034,  0.000,  0.034,  0.006],   # sockets back, nose bridge out;
    [ 0.010,  0.016,  0.000,  0.016,  0.010],   # the outer column stays put, or
    [ 0.020,  0.026,  0.026,  0.026,  0.020],   # the hollow cuts a groove round
    [ 0.014,  0.014,  0.014,  0.014,  0.014],   # the whole skull. Chin, forward
]                                               # of the mouth and under the brow

HEAD_SECTIONS = [
    (-0.120, [(1.702, 0.086), (1.634, 0.140), (1.566, 0.150),
              (1.512, 0.072), (1.478, 0.056)]),   # cheekbone: 0.30 across
    ( 0.105, [(1.790, 0.048), (1.716, 0.070), (1.626, 0.078),
              (1.570, 0.056), (1.548, 0.042)]),   # peak and nape
]

# Face quads that take the dark atlas cell: the two eye hollows under the brow,
# and the mouth. Indexed (row_band * 4 + column_band) into the face lattice.
HEAD_DARK_QUADS = (0, 3, 13, 14)

# The nose: a pyramid off the bridge, 0.075 m proud of the face, flat beneath.
HEAD_NOSE_TOP = (0.030, 1.598)     # half-width, z of the base's top edge
HEAD_NOSE_BOT = (0.042, 1.516)
HEAD_NOSE_TIP = (0.0, -0.320, 1.546)

# One flat wedge each side for an ear, 4 triangles apiece.
HEAD_EAR = [(0.145, -0.045, 1.640), (0.145, 0.010, 1.600),
            (0.145, -0.040, 1.560), (0.172, -0.030, 1.604)]

# ---- run cycle (the runner's, verbatim) -------------------------------------
CYCLE_FRAMES = 20
FPS = 30

THIGH_SWING     = 42.0
SHIN_BEND_MID   = -42.0
SHIN_BEND_AMP   =  32.0
SHIN_BEND_PHASE =  31.0
FOOT_PITCH_MID  =  -8.0
FOOT_PITCH_AMP  =  22.0
FOOT_PITCH_PHASE = 68.8

ARM_SWING_MID   = -30.0
ARM_SWING_AMP   =  33.0
ARM_TUCK        = -14.0
ELBOW_MID       = 101.0
ELBOW_AMP       =  17.0

HIP_ROLL        =  7.0
HIP_SWAY        =  0.012
HIP_BOB_MID     = -0.045
HIP_BOB_AMP     =  0.035
SPINE_LEAN      =  9.0
SPINE_COUNTER   =  9.0
RUN_NECK_TILT   = -2.7
HEAD_TILT_ANIM  = -6.3
HEAD_ROLL       =  3.6


# =============================================================================
# RIG
# =============================================================================

FRONT = (0.0, -1.0, 0.0)


def _local_x(direction):
    """The one orientation rule: local +Z faces front, so local +X = dir x front."""
    return Vector(direction).normalized().cross(Vector(FRONT)).normalized()


def _pitch(deg):
    """A unit direction tilted ``deg`` forward (towards -Y) off straight up."""
    a = math.radians(deg)
    return (0.0, -math.sin(a), math.cos(a))


def _arm_dir(side):
    a = math.radians(ARM_SPLAY)
    return (side * math.sin(a), 0.0, -math.cos(a))


def _leg_dir(side):
    a = math.radians(LEG_SPLAY)
    return (side * math.sin(a), 0.0, -math.cos(a))


def _foot_dir(side):
    d = Vector(_leg_dir(side))
    axis = _local_x(d)
    return (Matrix.Rotation(math.radians(FOOT_PITCH), 3, axis) @ d).normalized()


def _step(head, direction, length):
    return tuple(head[i] + direction[i] * length for i in range(3))


def bone_table():
    """(name, parent, head, direction, length) for all sixteen joints.

    Same names and same parenting as the runner; the spine and neck are tilted
    forward so the hunch lives in the rest pose and every clip rides on top."""
    spine_head = (0.0, 0.0, SPINE_Z)
    spine_dir = _pitch(SPINE_TILT)
    neck_head = _step(spine_head, spine_dir, SPINE_LEN)
    neck_dir = _pitch(NECK_TILT)
    head_head = _step(neck_head, neck_dir, NECK_LEN)
    head_dir = _pitch(HEAD_TILT)

    rows = [
        ("Hips",  None,    (0.0, 0.0, HIP_Z), (0.0, 0.0, 1.0), SPINE_Z - HIP_Z),
        ("Spine", "Hips",  spine_head, spine_dir, SPINE_LEN),
        ("Neck",  "Spine", neck_head,  neck_dir,  NECK_LEN),
        ("Head",  "Neck",  head_head,  head_dir,  HEAD_LEN),
    ]
    for suffix, side in (("L", 1.0), ("R", -1.0)):
        ad = _arm_dir(side)
        shoulder = (side * SHOULDER_X, SHOULDER_Y, SHOULDER_Z)
        elbow = _step(shoulder, ad, UPPERARM_LEN)
        wrist = _step(elbow, ad, LOWERARM_LEN)
        rows += [
            ("UpperArm." + suffix, "Spine", shoulder, ad, UPPERARM_LEN),
            ("LowerArm." + suffix, "UpperArm." + suffix, elbow, ad, LOWERARM_LEN),
            ("Hand." + suffix,     "LowerArm." + suffix, wrist, ad, HAND_LEN),
        ]
        ld = _leg_dir(side)
        hip = (side * HIP_X, 0.0, HIP_JOINT_Z)
        knee = _step(hip, ld, THIGH_LEN)
        ankle = (knee[0] + ld[0] * SHIN_LEN, ANKLE_Y, ANKLE_Z)
        rows += [
            ("Thigh." + suffix, "Hips", hip, ld, THIGH_LEN),
            ("Shin." + suffix,  "Thigh." + suffix, knee, ld, SHIN_LEN),
            ("Foot." + suffix,  "Shin." + suffix, ankle, _foot_dir(side), FOOT_LEN),
        ]
    return rows


def build_armature():
    rows = bone_table()
    bones = [(nm, parent, head, direction, length, _local_x(direction))
             for (nm, parent, head, direction, length) in rows]
    connect = {"Spine", "Neck", "Head", "LowerArm.L", "Hand.L",
               "LowerArm.R", "Hand.R", "Shin.L", "Shin.R"}
    return mdl.armature(ARMATURE_NAME, bones, connect=connect)


# =============================================================================
# MESH
# =============================================================================

def _face_normal(poly):
    n = Vector((0.0, 0.0, 0.0))
    for i in range(len(poly)):
        a, b = Vector(poly[i]), Vector(poly[(i + 1) % len(poly)])
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n


def _outward(name, verts, faces):
    """Mesh with every face wound so its normal points away from the centroid."""
    centre = sum((Vector(v) for v in verts), Vector()) / len(verts)
    fixed = []
    for f in faces:
        poly = [verts[i] for i in f]
        mid = sum((Vector(p) for p in poly), Vector()) / len(poly)
        fixed.append(tuple(reversed(f)) if _face_normal(poly).dot(mid - centre) < 0.0
                     else tuple(f))
    return mdl.mesh(name, verts, fixed)


def _head_point(y, rows, r, c, dy=None):
    z, w = rows[r]
    return (w * HEAD_COLS[c], y + (dy[r][c] if dy else 0.0), z)


def _head_ring(first):
    """The 16 border indices of a 5x5 lattice, in one order round the section."""
    g = lambda r, c: first + r * 5 + c
    return ([g(0, c) for c in range(5)]
            + [g(r, 4) for r in (1, 2, 3)]
            + [g(4, c) for c in range(4, -1, -1)]
            + [g(r, 0) for r in (3, 2, 1)])


def build_head():
    """The skull, as (object, per-face atlas zone). Every surface is a plane."""
    verts, faces, zones = [], [], []

    # The face: a 5x5 lattice of hard quads, brow to chin.
    for r in range(5):
        for c in range(5):
            verts.append(_head_point(HEAD_FACE_Y, HEAD_FACE_ROWS, r, c,
                                     HEAD_FACE_DY))
    for r in range(4):
        for c in range(4):
            faces.append((r * 5 + c, r * 5 + c + 1,
                          (r + 1) * 5 + c + 1, (r + 1) * 5 + c))
            zones.append(ZONE_DARK if len(faces) - 1 in HEAD_DARK_QUADS
                         else PART_ZONE["Head"])

    # Cheekbone and nape sections, stitched border to border.
    rings = [_head_ring(0)]
    for (y, rows) in HEAD_SECTIONS:
        first = len(verts)
        for r in range(5):
            for c in range(5):
                verts.append(_head_point(y, rows, r, c))
        rings.append(_head_ring(first))
    for a, b in zip(rings, rings[1:]):
        for i in range(16):
            j = (i + 1) % 16
            faces.append((a[i], a[j], b[j], b[i]))
            zones.append(PART_ZONE["Head"])
    faces.append(tuple(rings[-1]))          # the flat nape plane
    zones.append(ZONE_DARK)

    # The nose, a pyramid standing off the bridge with a flat underside.
    wt, zt = HEAD_NOSE_TOP
    wb, zb = HEAD_NOSE_BOT
    base = len(verts)
    verts += [(wt, HEAD_FACE_Y, zt), (-wt, HEAD_FACE_Y, zt),
              (-wb, HEAD_FACE_Y, zb), (wb, HEAD_FACE_Y, zb), HEAD_NOSE_TIP]
    tip = base + 4
    for i in range(4):
        faces.append((tip, base + i, base + (i + 1) % 4))
        zones.append(PART_ZONE["Head"])
    faces.append((base, base + 1, base + 2, base + 3))
    zones.append(PART_ZONE["Head"])

    # Ears: a flat wedge each side.
    for side in (1.0, -1.0):
        base = len(verts)
        verts += [(side * x, y, z) for (x, y, z) in HEAD_EAR]
        for f in ((0, 1, 2), (3, 0, 1), (3, 1, 2), (3, 2, 0)):
            faces.append(tuple(base + i for i in f))
            zones.append(PART_ZONE["Head"])

    ob = _outward("Head", verts, faces)
    return ob, zones


def build_mesh():
    """Sixteen rigid parts, one per bone. Returns (object, groups, zones)."""
    rows = {r[0]: r for r in bone_table()}
    parts = []          # (bone, object, zone)

    def tube(bone, rings, sides=SIDES_BODY):
        _, _, head, direction, _ = rows[bone]
        zone = PART_ZONE[bone.split(".")[0]]
        parts.append((bone, mdl.limb(bone, head, direction, rings, sides=sides), zone))

    tube("Hips", HIPS_RINGS)
    tube("Spine", SPINE_RINGS)
    tube("Neck", NECK_RINGS)
    head, head_zones = build_head()
    parts.append(("Head", head, head_zones))

    for suffix, side in (("L", 1.0), ("R", -1.0)):
        tube("UpperArm." + suffix, UPPERARM_RINGS, sides=SIDES_LIMB)
        tube("LowerArm." + suffix, LOWERARM_RINGS, sides=SIDES_LIMB)
        tube("Hand." + suffix, HAND_RINGS, sides=SIDES_LIMB)
        tube("Thigh." + suffix, THIGH_RINGS, sides=SIDES_LIMB)
        tube("Shin." + suffix, SHIN_RINGS, sides=SIDES_LIMB)

        def wedge(spec):
            x0, x1 = spec["x"]
            y0, y1 = spec["y"]
            z = spec["z"]
            if side < 0:
                x0, x1 = -x1, -x0
            return [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]

        parts.append(("Foot." + suffix,
                      mdl.frustum("Foot." + suffix, wedge(FOOT_SOLE), wedge(FOOT_ANKLE)),
                      PART_ZONE["Foot"]))

    # merge_parts concatenates in list order, so the per-face zone list built
    # here stays aligned with the merged mesh's polygons.
    zones = []
    for (_bone, ob, zone) in parts:
        n = len(ob.data.polygons)
        zones.extend(zone if isinstance(zone, list) else [zone] * n)
    body, groups = mdl.merge_parts([(b, o) for (b, o, _z) in parts], MESH_NAME)
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
    """Four flat zones, each dithered with a little per-texel noise and grit."""
    r = random.Random(TEX_SEED)
    buf = [1.0] * (TEX_SIZE * TEX_SIZE * 4)

    def put(x, y, rgb):
        o = (y * TEX_SIZE + x) * 4
        buf[o:o + 3] = _s2l(rgb)

    for zone, base in ((ZONE_SKIN, SKIN), (ZONE_SHIRT, SHIRT),
                       (ZONE_TROUSER, TROUSER), (ZONE_DARK, DARK)):
        x0, y0, x1, y1 = zone
        for y in range(y0, y1):
            for x in range(x0, x1):
                j = r.randint(-JITTER, JITTER)
                put(x, y, tuple(max(0, min(255, c + j)) for c in base))
        for _ in range(40):
            put(r.randrange(x0, x1), r.randrange(y0, y1), r.choice(ZONE_SPOTS[zone]))

    img = bpy.data.images.new(NAME + "_albedo", TEX_SIZE, TEX_SIZE, alpha=False)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(buf)
    img.update()
    return img


def _tex_material(name, img):
    mat = bpy.data.materials.new(name)
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
    mat.diffuse_color = (0.5, 0.53, 0.56, 1.0)
    return mat


def skin_material(img):
    return _tex_material("Prisoner2Skin", img)


def shirt_material(img):
    """Surface 1: the shirt alone, so the match can tint it without the skin."""
    return _tex_material(SHIRT_MATERIAL, img)


def unwrap(ob, zones):
    """Each face -> a random 2x2 texel window of its zone; undersides go dark.

    Returns the zone each face actually landed in, which is what splits the
    shirt surface off -- an underside is dark cloth, not tintable shirt.
    """
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = random.Random(TEX_SEED * 31 + len(me.polygons))
    final = []
    for pi, poly in enumerate(me.polygons):
        zone = ZONE_DARK if poly.normal.z < DARK_DOWNFACING else zones[pi]
        final.append(zone)
        x0, y0, x1, y1 = zone
        tx, ty = r.randrange(x0, x1 - 2), r.randrange(y0, y1 - 2)
        corners = [(tx + 0.5, ty + 0.5), (tx + 1.5, ty + 0.5),
                   (tx + 1.5, ty + 1.5), (tx + 0.5, ty + 1.5)]
        for k, li in enumerate(poly.loop_indices):
            u, v = corners[k % 4]
            uvl.data[li].uv = (u / TEX_SIZE, v / TEX_SIZE)
    return final


def split_shirt(ob, final_zones, material):
    """Move every shirt-zone face onto its own material slot. Returns its index."""
    me = ob.data
    me.materials.append(material)
    index = len(me.materials) - 1
    for poly, zone in zip(me.polygons, final_zones):
        if zone == ZONE_SHIRT:
            poly.material_index = index
    return index


# =============================================================================
# ANIMATION -- the runner's five clips, verbatim
# =============================================================================

def _phase(i, n, offset_deg=0.0):
    return 2.0 * math.pi * i / (n - 1) + math.radians(offset_deg)


def run_curves():
    curves = {}

    def sway(i, n):
        return {"euler": (0.0, 0.0, HIP_ROLL * math.sin(_phase(i, n))),
                "location": (HIP_SWAY * math.sin(_phase(i, n)),
                             HIP_BOB_MID + HIP_BOB_AMP
                             * math.cos(2.0 * _phase(i, n)),
                             0.0)}

    curves["Hips"] = sway
    curves["Spine"] = lambda i, n: {
        "euler": (SPINE_LEAN, 0.0, -SPINE_COUNTER * math.sin(_phase(i, n)))}
    curves["Neck"] = lambda i, n: {"euler": (RUN_NECK_TILT, 0.0, 0.0)}
    curves["Head"] = lambda i, n: {
        "euler": (HEAD_TILT_ANIM, 0.0, HEAD_ROLL * math.sin(_phase(i, n)))}

    for suffix, lag in (("L", 0.0), ("R", 180.0)):
        sign = 1.0 if suffix == "L" else -1.0

        def thigh(i, n, lag=lag):
            return {"euler": (THIGH_SWING * math.sin(_phase(i, n, lag)), 0.0, 0.0)}

        def shin(i, n, lag=lag):
            return {"euler": (SHIN_BEND_MID + SHIN_BEND_AMP
                              * math.sin(_phase(i, n, lag + SHIN_BEND_PHASE)),
                              0.0, 0.0)}

        def foot(i, n, lag=lag):
            return {"euler": (FOOT_PITCH_MID + FOOT_PITCH_AMP
                              * math.sin(_phase(i, n, lag + FOOT_PITCH_PHASE)),
                              0.0, 0.0)}

        def upper(i, n, lag=lag, sign=sign):
            return {"euler": (ARM_SWING_MID - ARM_SWING_AMP
                              * math.sin(_phase(i, n, lag)), 0.0, sign * ARM_TUCK)}

        def elbow(i, n, lag=lag):
            return {"euler": (ELBOW_MID - ELBOW_AMP * math.sin(_phase(i, n, lag)),
                              0.0, 0.0)}

        curves["Thigh." + suffix] = thigh
        curves["Shin." + suffix] = shin
        curves["Foot." + suffix] = foot
        curves["UpperArm." + suffix] = upper
        curves["LowerArm." + suffix] = elbow

    return curves


def _lerp_pose(t, keys):
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, p0), (t1, p1) in zip(keys, keys[1:]):
        if t <= t1:
            f = (t - t0) / max(t1 - t0, 1e-9)
            names = set(p0) | set(p1)
            return {b: p0.get(b, 0.0) + (p1.get(b, 0.0) - p0.get(b, 0.0)) * f
                    for b in names}
    return keys[-1][1]


def _pose_sequence_curves(keys, hip_drop=None):
    names = set()
    for _, pose in keys:
        names.update(pose)

    curves = {}
    for bone in names:
        def fn(i, n, bone=bone):
            t = i / (n - 1) if n > 1 else 1.0
            return {"euler": (_lerp_pose(t, keys).get(bone, 0.0), 0.0, 0.0)}
        curves[bone] = fn

    if hip_drop is not None:
        base = curves.get("Hips")

        def hips(i, n):
            t = i / (n - 1) if n > 1 else 1.0
            out = base(i, n) if base else {"euler": (0.0, 0.0, 0.0)}
            out["location"] = (0.0, _lerp_pose(t, hip_drop).get("y", 0.0), 0.0)
            return out
        curves["Hips"] = hips
    return curves


JUMP_FRAMES = 12

JUMP_KEYS = [
    (0.00, {}),
    (0.25, {"Spine": 10.0, "Neck": -8.0, "Head": -6.0,
            "UpperArm.L": -30.0, "LowerArm.L": -30.0,
            "UpperArm.R": -30.0, "LowerArm.R": -30.0,
            "Thigh.L": -55.0, "Shin.L": 80.0, "Foot.L": -25.0,
            "Thigh.R": -55.0, "Shin.R": 80.0, "Foot.R": -25.0,
            "Hips": -4.0}),
    (0.45, {"Spine": -8.0, "Neck": 4.0, "Head": 4.0,
            "UpperArm.L": -50.0, "LowerArm.L": -20.0,
            "UpperArm.R": -50.0, "LowerArm.R": -20.0,
            "Thigh.L": 15.0, "Shin.L": -10.0, "Foot.L": 10.0,
            "Thigh.R": 15.0, "Shin.R": -10.0, "Foot.R": 10.0,
            "Hips": 6.0}),
    (0.70, {"Hips": -6.0, "Spine": 10.0, "Neck": -8.0, "Head": -6.0,
            "UpperArm.L": 35.0, "LowerArm.L": -40.0,
            "UpperArm.R": -60.0, "LowerArm.R": -55.0,
            "Thigh.L": -50.0, "Shin.L": 75.0, "Foot.L": -20.0,
            "Thigh.R": 18.0, "Shin.R": 60.0, "Foot.R": 15.0}),
    (1.00, {"Spine": 14.0, "Neck": -10.0, "Head": -8.0,
            "UpperArm.L": -20.0, "LowerArm.L": -35.0,
            "UpperArm.R": -20.0, "LowerArm.R": -35.0,
            "Thigh.L": -60.0, "Shin.L": 95.0, "Foot.L": -30.0,
            "Thigh.R": -60.0, "Shin.R": 95.0, "Foot.R": -30.0,
            "Hips": -8.0}),
]


def jump_curves():
    return _pose_sequence_curves(JUMP_KEYS)


DEATH_FRAMES = 20

DEATH_KEYS = [
    (0.00, {}),
    (0.12, {"Spine": -12.0, "Neck": -10.0, "Head": -14.0,
            "UpperArm.L": -20.0, "LowerArm.L": -10.0,
            "UpperArm.R": -20.0, "LowerArm.R": -10.0}),
    (0.40, {"Hips": 25.0, "Spine": 20.0, "Neck": 10.0, "Head": 8.0,
            "UpperArm.L": 15.0, "LowerArm.L": 30.0,
            "UpperArm.R": 15.0, "LowerArm.R": 30.0,
            "Thigh.L": -35.0, "Shin.L": 55.0, "Foot.L": -15.0,
            "Thigh.R": -35.0, "Shin.R": 55.0, "Foot.R": -15.0}),
    (0.70, {"Hips": 60.0, "Spine": 15.0, "Neck": 5.0, "Head": 5.0,
            "UpperArm.L": 30.0, "LowerArm.L": 45.0,
            "UpperArm.R": 30.0, "LowerArm.R": 45.0,
            "Thigh.L": -20.0, "Shin.L": 40.0, "Foot.L": -10.0,
            "Thigh.R": -20.0, "Shin.R": 40.0, "Foot.R": -10.0}),
    (1.00, {"Hips": 88.0, "Spine": 8.0, "Neck": 3.0, "Head": 3.0,
            "UpperArm.L": 20.0, "LowerArm.L": 30.0,
            "UpperArm.R": 20.0, "LowerArm.R": 30.0,
            "Thigh.L": -10.0, "Shin.L": 20.0, "Foot.L": 0.0,
            "Thigh.R": -10.0, "Shin.R": 20.0, "Foot.R": 0.0}),
]

DEATH_HIP_DROP = [
    (0.00, {"y": 0.0}),
    (0.40, {"y": -0.20}),
    (0.70, {"y": -0.45}),
    (1.00, {"y": -0.62}),
]


def death_curves():
    return _pose_sequence_curves(DEATH_KEYS, hip_drop=DEATH_HIP_DROP)


AIM_CYCLE_FRAMES = 44
AIM_BREATH_DEG = 2.5

AIM_POSE_DEGREES = {
    "Spine": 6.0,
    "Neck": 9.0,
    "Head": 13.0,
    "UpperArm.L": 68.0,
    "LowerArm.L": 108.0,
    "UpperArm.R": 68.0,
    "LowerArm.R": 108.0,
}


def aim_curves():
    curves = {}
    for bone, deg in AIM_POSE_DEGREES.items():
        if bone == "Spine":
            continue

        def fn(i, n, deg=deg):
            return {"euler": (deg, 0.0, 0.0)}
        curves[bone] = fn

    def spine(i, n):
        breath = AIM_BREATH_DEG * math.sin(_phase(i, n))
        return {"euler": (AIM_POSE_DEGREES["Spine"] + breath, 0.0, 0.0)}

    curves["Spine"] = spine
    return curves


SHOVE_FRAMES = 8

SHOVE_KEYS = [
    (0.00, {"Spine": -6.0, "Neck": 4.0, "Head": 4.0,
            "UpperArm.L": 40.0, "LowerArm.L": 100.0,
            "UpperArm.R": 40.0, "LowerArm.R": 100.0}),
    (0.43, {"Spine": 14.0, "Neck": -6.0, "Head": -4.0,
            "UpperArm.L": 86.0, "LowerArm.L": 6.0,
            "UpperArm.R": 86.0, "LowerArm.R": 6.0}),
    (1.00, {"Spine": 2.0, "Neck": 0.0, "Head": 0.0,
            "UpperArm.L": 18.0, "LowerArm.L": 55.0,
            "UpperArm.R": 18.0, "LowerArm.R": 55.0}),
]


def shove_curves():
    return _pose_sequence_curves(SHOVE_KEYS)


# =============================================================================
# BUILD
# =============================================================================

def build():
    arm = build_armature()
    body, groups, zones = build_mesh()
    albedo = paint_atlas()
    mdl.save_texture(albedo)
    final_zones = unwrap(body, zones)
    mdl.finish(body, skin_material(albedo), strip_uvs=False)
    split_shirt(body, final_zones, shirt_material(albedo))
    mdl.rigid_bind(body, arm, groups)

    mdl.bake_pose(arm, CLIP_NAME, frames=list(range(1, CYCLE_FRAMES + 2)),
                  fps=FPS, curves=run_curves())
    mdl.bake_pose(arm, JUMP_CLIP_NAME, frames=list(range(1, JUMP_FRAMES + 1)),
                  fps=FPS, curves=jump_curves())
    mdl.bake_pose(arm, DEATH_CLIP_NAME, frames=list(range(1, DEATH_FRAMES + 1)),
                  fps=FPS, curves=death_curves())
    mdl.bake_pose(arm, AIM_CLIP_NAME, frames=list(range(1, AIM_CYCLE_FRAMES + 2)),
                  fps=FPS, curves=aim_curves())
    mdl.bake_pose(arm, SHOVE_CLIP_NAME, frames=list(range(1, SHOVE_FRAMES + 1)),
                  fps=FPS, curves=shove_curves())

    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    print("MDL STATS bones=%d clip=%s frames=%d..%d fps=%d"
          % (len(arm.data.bones), CLIP_NAME, 1, CYCLE_FRAMES + 1, FPS))
    print("MDL STATS clip=%s frames=1..%d fps=%d" % (JUMP_CLIP_NAME, JUMP_FRAMES, FPS))
    print("MDL STATS clip=%s frames=1..%d fps=%d" % (DEATH_CLIP_NAME, DEATH_FRAMES, FPS))
    print("MDL STATS clip=%s frames=1..%d fps=%d" % (AIM_CLIP_NAME, AIM_CYCLE_FRAMES + 1, FPS))
    print("MDL STATS clip=%s frames=1..%d fps=%d" % (SHOVE_CLIP_NAME, SHOVE_FRAMES, FPS))
    return [arm, body]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
