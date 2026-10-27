"""semibot_ball -- the R.E.P.O. Semibot fully scrunched (head sunk into the ring, stub legs, arms tucked), one mesh.

Content-branch dribble object for the balling emote; same source and textures as semibot_build.py.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import mdl  # noqa: E402

NAME = "semibot_ball"
SOURCE = "characters/textures/semibot_source/semibot_repo.blend"
## About 0.5 m tall: cat-sized in the hands at the emote's 0.8 object scale.
SCALE = 0.6
## Scrunch (source metres, Z up): ring on stub legs, head sunk into the ring, short arms hanging close.
RING_FLOOR = 0.12
RING_LO = 0.570
RING_HI = 0.852
HEAD_LO = 1.213
HEAD_SINK = 0.07
LEG_TOP = 0.683
LEG_SHORT = 0.25
LEG_TUCK = 0.20
SHOULDER_Z = 0.34
ARM_OUT_DEG = 22.0
ARM_ROOT_X = 0.04
ARM_SHORT = 0.42
CENTRE_Y = 0.341
PARTS = ["mesh_body_bot", "mesh_leg_l", "mesh_leg_r", "mesh_arm_l", "mesh_arm_r", "mesh_head_bot_flat",
         "mesh_health", "mesh_health frame", "mesh_head_top", "mesh_eye_l", "mesh_eye_r", "mesh_pupil_l",
         "mesh_pupil_r"]
ARMS = {"mesh_arm_l": Vector((0.268, 0.341, 1.118)), "mesh_arm_r": Vector((-0.254, 0.341, 1.118))}


def _source_path():
    root = mdl._tex_spec()[0] or os.path.normpath(os.path.join(_HOME, "..", "..", ".."))
    return os.path.join(root, SOURCE)


def _materials():
    out = {}
    for name, tex_name, rough in (("SemibotBody", "semibot_body", 0.55), ("SemibotFace", "semibot_face", 0.35)):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = mdl.texture(tex_name)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = rough
        out[name] = mat
    health = mdl.flat_material("SemibotHealth", (0.033, 0.80, 0.0, 1.0), roughness=0.6)
    return {"Player Avatar - Body": out["SemibotBody"], "Player Avatar - Eye": out["SemibotFace"],
            "Player Avatar - Pupil": out["SemibotFace"], "Player Avatar - Health": health}


def _baked(src, mats, xform):
    """A plain mesh of [param src] as evaluated (rest pose), moved by [param xform], materials swapped."""
    dg = bpy.context.evaluated_depsgraph_get()
    data = bpy.data.meshes.new_from_object(src.evaluated_get(dg), depsgraph=dg)
    data.transform(xform @ src.matrix_world)
    for i, m in enumerate(data.materials):
        data.materials[i] = mats[m.name]
    ob = bpy.data.objects.new(src.name + "_baked", data)
    bpy.context.collection.objects.link(ob)
    return ob


def _scrunch(name):
    """Source-space transform that puts part [param name] in the full scrunch."""
    if name == "mesh_body_bot":
        return Matrix.Translation((0, 0, RING_FLOOR - RING_LO))
    if name in ("mesh_leg_l", "mesh_leg_r"):
        return (Matrix.Translation((0, 0, LEG_TUCK)) @ Matrix.Diagonal((1, 1, LEG_SHORT, 1))
                @ Matrix.Translation((0, 0, -LEG_TOP)))
    if name in ARMS:
        pivot = ARMS[name]
        side = -1.0 if pivot.x > 0 else 1.0
        turn = Matrix.Rotation(math.radians(ARM_OUT_DEG) * side, 4, "Y")
        short = Matrix.Diagonal((1, 1, ARM_SHORT, 1))
        return Matrix.Translation((pivot.x + side * ARM_ROOT_X, pivot.y, SHOULDER_Z)) @ turn @ short @ Matrix.Translation(-pivot)
    ring_top = RING_FLOOR + RING_HI - RING_LO
    return Matrix.Translation((0, 0, ring_top - HEAD_SINK - HEAD_LO))


def build():
    with bpy.data.libraries.load(_source_path(), link=False) as (src, dst):
        dst.objects = list(src.objects)
    for ob in dst.objects:
        bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.update()
    mats = _materials()
    place = Matrix.Diagonal((SCALE, SCALE, SCALE, 1)) @ Matrix.Translation((0, -CENTRE_Y, 0))
    parts = [_baked(bpy.data.objects[n], mats, place @ _scrunch(n)) for n in PARTS]
    for ob in dst.objects:
        bpy.data.objects.remove(ob, do_unlink=True)
    return [mdl.join(parts, "SemibotBall")]


mdl.main(NAME, build)
