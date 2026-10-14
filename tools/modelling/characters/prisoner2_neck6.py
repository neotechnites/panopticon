"""Front neck ledge removed: shirt top strip welded into the neck base, chest row pulled flush, folded shoulder slivers welded; AO re-baked.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_neck6.py -- --save characters/models/prisoner_joined.blend
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
WELD_CENTRE = {375: (388, 389, 390, 367), 379: (369,)}     # neck base front / chest row, centre line
WELD_SIDE = ((25, 27, 28, 29), (223, 227, 247, 249))        # (keep, drop) on +X then mirrored -X
CHEST_Y = -0.163                                            # chest row in the neck base's front plane, no step
SHOULDER_FRONT = ((222, 223, 25), (222, 259, 223))         # +X faces UV'd onto the trouser brown row; mirrored -X too
UV_EDGE = 0.49                                              # chest island tip at the shoulder corner, off the brown row's edge
UV_DROP = 0.06                                              # moves them down into the shirt white rows, shape kept
CORNER = (0.060, -0.163, 1.305)                             # shirt corner beside the neck, same front plane


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    save = argv[argv.index("--save") + 1] if "--save" in argv else None
    bpy.context.preferences.filepaths.save_version = 0
    ob = bpy.data.objects["Runner"]
    arm = bpy.data.objects["Armature"]
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    v = {i: bm.verts[i] for i in range(len(bm.verts))}
    for keep, drops in WELD_CENTRE.items():
        bmesh.ops.pointmerge(bm, verts=[v[keep]] + [v[d] for d in drops], merge_co=v[keep].co.copy())
    uv = bm.loops.layers.uv.active
    mirror = {222: 246, 223: 247, 25: 28, 259: 274}
    for tri in SHOULDER_FRONT:
        for side in (tri, tuple(mirror[i] for i in tri)):
            f = bm.faces.get([v[i] for i in side])
            for lp in f.loops:
                lp[uv].uv.y -= UV_DROP
    for i in (222, 246):
        for lp in v[i].link_loops:
            if lp[uv].uv.y > UV_EDGE:
                lp[uv].uv.y = UV_EDGE
    for kp, dp, km, dm in WELD_SIDE:
        mid = (v[kp].co + v[dp].co) / 2
        bmesh.ops.pointmerge(bm, verts=[v[kp], v[dp]], merge_co=mid)
        bmesh.ops.pointmerge(bm, verts=[v[km], v[dm]], merge_co=(-mid.x, mid.y, mid.z))
    for i in (379, 222, 246):
        v[i].co.y = CHEST_Y
    v[25].co = CORNER
    v[28].co = (-CORNER[0], CORNER[1], CORNER[2])
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-6)
    for s in (25, 28):
        e = next(e for e in v[s].link_edges if e.other_vert(v[s]) is v[375])
        bmesh.ops.rotate_edges(bm, edges=[e], use_ccw=False)
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
    print("NECK6 wrote", GLB)


main()
