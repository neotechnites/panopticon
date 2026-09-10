"""
PANOPTICON -- the prisoner. A 1.8 m low-poly humanoid on a 16-joint rig with a
looping run cycle, exported as ``assets/models/runner.glb``.

Run through the pipeline (from the Mac, from the repo root)::

    tools/modelling/model build runner
    tools/modelling/model build runner --frame 6 --views side,threequarter

or directly on the PC::

    blender.exe -b -noaudio -P runner_build.py -- --spec spec.json

WHY THIS FILE EXISTS
--------------------
The first runner was built in an ephemeral scratchpad and the script was lost,
which left a 72 KB binary in the repo that nobody could change: not the height,
not the stride, not the silhouette. This file was reconstructed from that
binary -- rest pose, bone table, section profiles and animation curves were all
read back out of the glTF -- and it is now the source of truth. The .glb is
output, not input.

THE CONTRACT THE GAME DEPENDS ON
--------------------------------
``scenes/player/prisoner_avatar.tscn`` and ``scripts/player/prisoner_avatar.gd``
address this model by name, so these are not cosmetic choices:

  * node path ``Armature/Skeleton3D/Runner`` and a sibling ``AnimationPlayer``
  * one clip called ``Run``
  * bones ``Hips Spine Neck Head UpperArm.{L,R} LowerArm.{L,R} Hand.{L,R}
    Thigh.{L,R} Shin.{L,R} Foot.{L,R}`` -- a bespoke naming, NOT Godot's
    humanoid SkeletonProfile, and deliberately so (see prisoner_avatar.gd)
  * one surface, one material
  * feet on z=0, head at z=1.8, model FACING -Y in Blender, which glTF turns
    into +Z in Godot; the avatar scene applies the half turn.

``tools/modelling/runner.contract.json`` states that machine-checkably and the
pipeline enforces it on the PC after every build.

COORDINATES
-----------
Authored in BLENDER space (+Z up, model faces -Y). glTF export maps
Blender (X, Y, Z) -> glTF (X, Z, -Y), so Blender -Y becomes Godot +Z.

EVERY BONE SHARES ONE ORIENTATION RULE
--------------------------------------
A bone's local +Z always points at the model's front (-Y in Blender), so its
local +X is ``direction x (0,-1,0)``. That single rule means:

    rotation about local X  ==  swing forward / back  (every joint)
    rotation about local Z  ==  roll sideways         (every joint)

for the hips, the spine and all four limbs alike. Roll angles are never typed
in; ``mdl.armature`` solves each one to satisfy the rule.
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
# TUNABLES -- everything adjustable lives in this block
# =============================================================================

NAME = "runner"
MESH_NAME = "Runner"          # -> Armature/Skeleton3D/Runner in Godot
ARMATURE_NAME = "Armature"
CLIP_NAME = "Run"
FACING_YAW = 180.0            # the model faces -Y; rotate the named views to match

# ---- material ---------------------------------------------------------------
BODY_COLOR = (0.300, 0.312, 0.330, 1.0)   # prison grey, one flat material
BODY_ROUGHNESS = 0.94
BODY_METALLIC = 0.0
BODY_SPECULAR = 0.24

# ---- master proportions (metres) -------------------------------------------
HEIGHT       = 1.800   # crown of the head; the avatar's collider assumes this
HIP_Z        = 0.900   # root bone height at rest
SPINE_Z      = 1.060
NECK_Z       = 1.400
HEAD_Z       = 1.500

SHOULDER_X   = 0.1676  # shoulder joint, out from the centreline
SHOULDER_Z   = 1.4233
ARM_SPLAY    = 8.0     # degrees the upper arm hangs outboard of vertical
UPPERARM_LEN = 0.340
LOWERARM_LEN = 0.270
HAND_LEN     = 0.220

HIP_X        = 0.1047  # hip joint, out from the centreline
HIP_JOINT_Z  = 0.8827
LEG_SPLAY    = 1.5     # degrees the thigh hangs outboard of vertical
THIGH_LEN    = 0.390
SHIN_LEN     = 0.375
FOOT_LEN     = 0.200
ANKLE_Y      = 0.020   # ankle sits slightly behind the shin line
ANKLE_Z      = 0.118
FOOT_PITCH   = 66.2    # degrees the foot bone is pitched forward off the shin

HEAD_LEN     = 0.300
NECK_LEN     = 0.100

# ---- section profiles ------------------------------------------------------
# Each part is a capped n-gon tube along its bone. A ring is
# (distance along the bone from its head, half-width in X, half-depth in Y).
# 6 sides for anything that should read as round; 4 for hands, which are slabs.
SIDES_BODY = 6
SIDES_HAND = 4

HIPS_RINGS  = [(-0.110, 0.168, 0.164),
               (-0.028, 0.202, 0.190),
               ( 0.160, 0.164, 0.162)]

SPINE_RINGS = [(-0.040, 0.160, 0.156),   # small of the back
               ( 0.175, 0.216, 0.212),   # ribcage
               ( 0.340, 0.232, 0.196),   # shoulders: widest, and flatter
               ( 0.410, 0.104, 0.110)]   # collar

NECK_RINGS  = [(-0.040, 0.094, 0.092),
               ( 0.130, 0.086, 0.086)]

HEAD_RINGS  = [(-0.045, 0.116, 0.144),   # jaw: deeper than it is wide
               ( 0.140, 0.140, 0.166),   # cranium
               ( 0.300, 0.114, 0.134)]   # crown, at z = HEIGHT

UPPERARM_RINGS = [(0.023, 0.067, 0.068),
                  (0.103, 0.085, 0.086),   # deltoid
                  (0.273, 0.073, 0.074),
                  (0.383, 0.058, 0.058)]

LOWERARM_RINGS = [(0.003, 0.059, 0.060),
                  (0.073, 0.071, 0.072),   # forearm belly
                  (0.203, 0.060, 0.060),
                  (0.308, 0.046, 0.046)]

HAND_RINGS  = [(0.013, 0.034, 0.028),
               (0.113, 0.045, 0.037),
               (0.198, 0.036, 0.030)]

THIGH_RINGS = [(-0.017, 0.086, 0.086),
               ( 0.083, 0.114, 0.114),   # quad
               ( 0.243, 0.100, 0.100),
               ( 0.413, 0.072, 0.072)]   # knee

SHIN_RINGS  = [(-0.027, 0.076, 0.076),
               ( 0.093, 0.092, 0.092),   # calf
               ( 0.243, 0.080, 0.080),
               ( 0.378, 0.062, 0.062)]   # ankle

# The foot is a wedge in world space, not a tube: a shoe read as a tapered tube
# looks like a flipper from the side, which is the one view that matters.
FOOT_SOLE  = dict(x=(0.053, 0.167), y=(-0.152, 0.032), z=0.000)
FOOT_ANKLE = dict(x=(0.059, 0.161), y=(-0.104, 0.040), z=0.158)

# ---- run cycle -------------------------------------------------------------
# 20 steps around the loop plus a duplicate of the first, so the clip closes.
# Every curve is a sinusoid in the cycle phase; the right side is the left side
# half a cycle later, which is the whole of what makes a run a run.
CYCLE_FRAMES = 20
FPS = 30

THIGH_SWING     = 42.0    # degrees, peak hip flexion either way
SHIN_BEND_MID   = -42.0   # knee sits bent through the whole cycle
SHIN_BEND_AMP   =  32.0
SHIN_BEND_PHASE =  31.0   # degrees the knee lags the hip
FOOT_PITCH_MID  =  -8.0   # relative to the pitched-forward rest foot
FOOT_PITCH_AMP  =  22.0
FOOT_PITCH_PHASE = 68.8

ARM_SWING_MID   = -30.0   # elbows lead; arms never hang straight in a run
ARM_SWING_AMP   =  33.0
ARM_TUCK        = -14.0   # upper arms held in towards the ribs
ELBOW_MID       = 101.0
ELBOW_AMP       =  17.0

HIP_ROLL        =  7.0    # pelvis rolls into the supporting leg
HIP_SWAY        =  0.012  # metres of lateral weight shift
HIP_BOB_MID     = -0.045  # metres the hips sit below rest through the cycle
HIP_BOB_AMP     =  0.035  # double bounce: the pelvis rises TWICE per stride,
                          # once per footfall, which is what sells the weight
SPINE_LEAN      =  9.0    # constant forward lean -- this is a sprint, not a jog
SPINE_COUNTER   =  9.0    # shoulders counter-rotate against the pelvis
NECK_TILT       = -2.7
HEAD_TILT       = -6.3    # eyes stay up while the chest is down
HEAD_ROLL       =  3.6


# =============================================================================
# RIG
# =============================================================================

FRONT = (0.0, -1.0, 0.0)     # the direction the model faces, in Blender


def _local_x(direction):
    """The one orientation rule: local +Z faces front, so local +X = dir x front."""
    return Vector(direction).normalized().cross(Vector(FRONT)).normalized()


def _arm_dir(side):
    a = math.radians(ARM_SPLAY)
    return (side * math.sin(a), 0.0, -math.cos(a))


def _leg_dir(side):
    a = math.radians(LEG_SPLAY)
    return (side * math.sin(a), 0.0, -math.cos(a))


def _foot_dir(side):
    """The shin direction pitched forward by FOOT_PITCH about the local X axis."""
    d = Vector(_leg_dir(side))
    axis = _local_x(d)
    return (Matrix.Rotation(math.radians(FOOT_PITCH), 3, axis) @ d).normalized()


def bone_table():
    """(name, parent, head, direction, length) for all sixteen joints."""
    rows = [
        ("Hips",  None,   (0.0, 0.0, HIP_Z),   (0.0, 0.0, 1.0), SPINE_Z - HIP_Z),
        ("Spine", "Hips", (0.0, 0.0, SPINE_Z), (0.0, 0.0, 1.0), NECK_Z - SPINE_Z),
        ("Neck",  "Spine", (0.0, 0.0, NECK_Z), (0.0, 0.0, 1.0), NECK_LEN),
        ("Head",  "Neck", (0.0, 0.0, HEAD_Z),  (0.0, 0.0, 1.0), HEAD_LEN),
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
    rows = bone_table()
    bones = [(nm, parent, head, direction, length, _local_x(direction))
             for (nm, parent, head, direction, length) in rows]
    connect = {"Spine", "Neck", "Head", "LowerArm.L", "Hand.L",
               "LowerArm.R", "Hand.R", "Shin.L", "Shin.R"}
    return mdl.armature(ARMATURE_NAME, bones, connect=connect)


# =============================================================================
# MESH
# =============================================================================

def build_mesh():
    """Sixteen rigid parts, one per bone, fused into a single-surface mesh."""
    rows = {r[0]: r for r in bone_table()}
    parts = []

    def tube(bone, rings, sides=SIDES_BODY):
        _, _, head, direction, _ = rows[bone]
        parts.append((bone, mdl.limb(bone, head, direction, rings, sides=sides)))

    tube("Hips", HIPS_RINGS)
    tube("Spine", SPINE_RINGS)
    tube("Neck", NECK_RINGS)
    tube("Head", HEAD_RINGS)

    for suffix, side in (("L", 1.0), ("R", -1.0)):
        # The section tables are symmetric; mirroring is carried entirely by the
        # bone direction, so there is one set of numbers for both sides.
        tube("UpperArm." + suffix, UPPERARM_RINGS)
        tube("LowerArm." + suffix, LOWERARM_RINGS)
        tube("Hand." + suffix, HAND_RINGS, sides=SIDES_HAND)
        tube("Thigh." + suffix, THIGH_RINGS)
        tube("Shin." + suffix, SHIN_RINGS)

        def wedge(spec):
            x0, x1 = spec["x"]
            y0, y1 = spec["y"]
            z = spec["z"]
            if side < 0:
                x0, x1 = -x1, -x0
            return [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]

        parts.append(("Foot." + suffix,
                      mdl.frustum("Foot." + suffix, wedge(FOOT_SOLE), wedge(FOOT_ANKLE))))

    return mdl.merge_parts(parts, MESH_NAME)


# =============================================================================
# ANIMATION
# =============================================================================

def _phase(i, n, offset_deg=0.0):
    return 2.0 * math.pi * i / (n - 1) + math.radians(offset_deg)


def run_curves():
    """bone -> f(frame_index, frame_count) -> {"euler": (...), "location": (...)}."""
    curves = {}

    def sway(i, n):
        # The Hips bone points +Z, so its own local Y is world UP and its
        # local X is world lateral: location is (sideways, up, forwards).
        return {"euler": (0.0, 0.0, HIP_ROLL * math.sin(_phase(i, n))),
                "location": (HIP_SWAY * math.sin(_phase(i, n)),
                             HIP_BOB_MID + HIP_BOB_AMP
                             * math.cos(2.0 * _phase(i, n)),
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
                              * math.sin(_phase(i, n, lag + SHIN_BEND_PHASE)),
                              0.0, 0.0)}

        def foot(i, n, lag=lag):
            return {"euler": (FOOT_PITCH_MID + FOOT_PITCH_AMP
                              * math.sin(_phase(i, n, lag + FOOT_PITCH_PHASE)),
                              0.0, 0.0)}

        def upper(i, n, lag=lag, sign=sign):
            # Arms are contralateral: the left arm goes back as the left leg
            # comes forward, which is why this reads +180 against the thigh.
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


# =============================================================================
# BUILD
# =============================================================================

def build():
    arm = build_armature()
    body, groups = build_mesh()
    mdl.finish(body, mdl.flat_material("runner_body", BODY_COLOR,
                                       roughness=BODY_ROUGHNESS,
                                       metallic=BODY_METALLIC,
                                       specular=BODY_SPECULAR))
    mdl.rigid_bind(body, arm, groups)

    mdl.bake_pose(
        arm, CLIP_NAME,
        frames=list(range(1, CYCLE_FRAMES + 2)),
        fps=FPS,
        curves=run_curves(),
    )

    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    print("MDL STATS bones=%d clip=%s frames=%d..%d fps=%d"
          % (len(arm.data.bones), CLIP_NAME, 1, CYCLE_FRAMES + 1, FPS))
    return [arm, body]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
