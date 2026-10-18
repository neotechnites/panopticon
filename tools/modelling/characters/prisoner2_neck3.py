"""Shape the shirt top like a body: shoulders rise into the trapezius, neck opening high at the back and scooped low in front; AO re-baked.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_neck3.py -- --save characters/models/prisoner_joined.blend
"""

import os
import sys

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "modelling", "lib"))
sys.path.insert(0, HERE)
import glb_textures  # noqa: E402
from prisoner2_face import bake_ao, multiply_materials  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"
Z = {}   # vertex index -> new z; sides of both shoulder rings stay put
Z.update({i: 1.358 for i in (232, 233, 236, 237)})   # upper back, trapezius crest
Z.update({i: 1.346 for i in (239, 242)})             # neck opening, sides
Z.update({i: 1.372 for i in (240, 241)})             # neck opening, back
Z.update({i: 1.298 for i in (243, 244)})             # neck opening, front scoop


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    save = argv[argv.index("--save") + 1] if "--save" in argv else None
    ob = bpy.data.objects["Runner"]
    arm = bpy.data.objects["Armature"]
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    for i, z in Z.items():
        bm.verts[i].co.z = z
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
    print("NECK3 wrote", GLB)


main()
