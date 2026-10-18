"""Drop the shirt's raised neck lip flat onto its top plane, open it to the neck's width, hand the bind weights over evenly; AO re-baked.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_neck.py -- --save characters/models/prisoner_joined.blend
"""

import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "modelling", "lib"))
sys.path.insert(0, HERE)
import glb_textures  # noqa: E402
from prisoner2_face import bake_ao, multiply_materials  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"
HEX = (235, 236, 237, 238, 28, 29)      # the shirt's top ring, outside the neck opening
RING = (239, 240, 241, 242, 243, 244)   # the neck opening
LOFT = (range(367, 379), range(379, 391), range(391, 403), range(403, 415))
LOFT_U = (0.2, 0.4, 0.6, 0.8)
OPEN_X = 0.714                          # the opening narrows to the neck's own width
SPINE_END = 0.6                         # the spine lets go of the neck by this height share


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    save = argv[argv.index("--save") + 1] if "--save" in argv else None
    ob = bpy.data.objects["Runner"]
    arm = bpy.data.objects["Armature"]
    me = ob.data
    gi = {n: ob.vertex_groups[n].index for n in ("Spine", "Neck", "Head")}
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    dfl = bm.verts.layers.deform.active
    pts = [bm.verts[i].co.copy() for i in HEX]   # plane z = a + b*x + c*y through the shirt's top ring
    n = len(pts)
    sx, sy, sz = (sum(p[k] for p in pts) for k in (0, 1, 2))
    sxx, sxy, syy = sum(p.x * p.x for p in pts), sum(p.x * p.y for p in pts), sum(p.y * p.y for p in pts)
    sxz, syz = sum(p.x * p.z for p in pts), sum(p.y * p.z for p in pts)
    a, b, c = Matrix(((n, sx, sy), (sx, sxx, sxy), (sy, sxy, syy))).inverted() @ Vector((sz, sxz, syz))
    for i in RING:
        v = bm.verts[i]
        v.co.x *= OPEN_X
        v.co.z = a + b * v.co.x + c * v.co.y
        v[dfl].clear()
        v[dfl][gi["Spine"]] = 1.0
    for rng, u in zip(LOFT, LOFT_U):
        hd = smooth((u - 0.15) / 0.85)
        sp = smooth(1 - u / SPINE_END)
        for i in rng:
            v = bm.verts[i]
            v[dfl].clear()
            for g, w in (("Spine", sp), ("Head", hd), ("Neck", 1 - hd - sp)):
                if w > 1e-4:
                    v[dfl][gi[g]] = w
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.update()
    bake_ao(me)
    multiply_materials(me)
    if save:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(save))
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=GLB, export_format="GLB", use_selection=True,
                              export_apply=False, export_yup=True, export_normals=True,
                              export_texcoords=True, export_vertex_color="ACTIVE")
    glb_textures.externalize(GLB, lambda n, data: TEX_URI)
    print("NECK wrote", GLB)


main()
