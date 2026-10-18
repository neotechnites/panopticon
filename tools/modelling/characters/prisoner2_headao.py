"""Head's smooth per-vertex AO eased halfway to 1.0 (by Head weight), so sockets read without smudging.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_headao.py -- --save characters/models/prisoner_joined.blend
"""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "modelling", "lib"))
import glb_textures  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"
EASE = 0.5          # share of the way from the baked AO to 1.0 at full Head weight


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    save = argv[argv.index("--save") + 1] if "--save" in argv else None
    bpy.context.preferences.filepaths.save_version = 0
    ob = bpy.data.objects["Runner"]
    arm = bpy.data.objects["Armature"]
    me = ob.data
    hi = ob.vertex_groups["Head"].index
    col = me.color_attributes["Col"]
    head = {}
    for v in me.vertices:
        w = next((g.weight for g in v.groups if g.group == hi), 0.0)
        if w > 0.0:
            head[v.index] = min(w, 1.0)
    per_loop = col.domain == "CORNER"
    items = (((li, me.loops[li].vertex_index) for li in range(len(me.loops))) if per_loop
             else ((vi, vi) for vi in range(len(me.vertices))))
    lo = 1.0
    for i, vi in items:
        w = head.get(vi)
        if w is None:
            continue
        a = col.data[i].color[0]
        a = a + (1.0 - a) * EASE * w
        lo = min(lo, a)
        col.data[i].color = (a, a, a, 1.0)
    me.update()
    print("HEADAO verts", len(head), "domain", col.domain, "min", round(lo, 3))
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
    print("HEADAO wrote", GLB)


main()
