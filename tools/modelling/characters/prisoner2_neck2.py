"""Lay the shirt's neck ring (hex and opening) onto the plane of the shoulder ring beside it so no shelf shows; AO re-baked.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_neck2.py -- --save characters/models/prisoner_joined.blend
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
OUTER = (231, 232, 233, 234, 26, 27)   # the shoulder ring the neck ring lands on
HEX = (235, 236, 237, 238, 28, 29)      # the shirt's top ring, outside the neck opening
RING = (239, 240, 241, 242, 243, 244)   # the neck opening


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    save = argv[argv.index("--save") + 1] if "--save" in argv else None
    ob = bpy.data.objects["Runner"]
    arm = bpy.data.objects["Armature"]
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    pts = [bm.verts[i].co.copy() for i in OUTER]   # plane z = a + b*x + c*y through the shoulder ring
    n = len(pts)
    sx, sy, sz = (sum(p[k] for p in pts) for k in (0, 1, 2))
    sxx, sxy, syy = sum(p.x * p.x for p in pts), sum(p.x * p.y for p in pts), sum(p.y * p.y for p in pts)
    sxz, syz = sum(p.x * p.z for p in pts), sum(p.y * p.z for p in pts)
    a, b, c = Matrix(((n, sx, sy), (sx, sxx, sxy), (sy, sxy, syy))).inverted() @ Vector((sz, sxz, syz))
    for i in HEX + RING:
        v = bm.verts[i]
        v.co.z = a + b * v.co.x + c * v.co.y
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
    print("NECK2 wrote", GLB)


main()
