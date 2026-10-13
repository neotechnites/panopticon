"""Head AO re-baked flat per face (one tone per plane, crisp edges) into a face-corner 'Col'; body keeps its per-vertex AO.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_faceao.py -- --save characters/models/prisoner_joined.blend
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "modelling", "lib"))
sys.path.insert(0, HERE)
import glb_textures  # noqa: E402
from prisoner2_face import AO_DIST, AO_FLOOR, AO_GAIN, AO_RAYS  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"
HEAD_W = 0.5        # a face is the head's when every corner is weighted past this to Head
SPREAD = 0.5        # sample points: centroid plus halfway to each corner


def hemisphere():
    rnd = random.Random(7)
    out = []
    for _ in range(AO_RAYS):
        u, v = rnd.random(), rnd.random()
        r, t = math.sqrt(u), 2 * math.pi * v
        out.append(Vector((r * math.cos(t), r * math.sin(t), math.sqrt(1 - u))))
    return out


def face_ao(f, bvh, dirs):
    """Occlusion averaged over the face, every ray round the face's own normal."""
    n = f.normal
    tx = (Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))).cross(n).normalized()
    ty = n.cross(tx)
    c = f.calc_center_median()
    pts = [c] + [c.lerp(v.co, SPREAD) for v in f.verts]
    hits = 0
    for p in pts:
        o = p + n * 0.002
        for d in dirs:
            if bvh.ray_cast(o, tx * d.x + ty * d.y + n * d.z, AO_DIST)[0] is not None:
                hits += 1
    return max(AO_FLOOR, 1.0 - AO_GAIN * hits / (AO_RAYS * len(pts)))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    save = argv[argv.index("--save") + 1] if "--save" in argv else None
    bpy.context.preferences.filepaths.save_version = 0
    ob = bpy.data.objects["Runner"]
    arm = bpy.data.objects["Armature"]
    me = ob.data
    hi = ob.vertex_groups["Head"].index
    point = [c.color[0] for c in me.color_attributes["Col"].data]
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    dl = bm.verts.layers.deform.active
    bvh = BVHTree.FromBMesh(bm)
    dirs = hemisphere()
    flat = {f.index: face_ao(f, bvh, dirs) for f in bm.faces
            if all(v[dl].get(hi, 0.0) > HEAD_W for v in f.verts)}
    bm.free()
    me.color_attributes.remove(me.color_attributes["Col"])
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for p in me.polygons:
        for li in p.loop_indices:
            a = flat.get(p.index, point[me.loops[li].vertex_index])
            col.data[li].color = (a, a, a, 1.0)
    me.color_attributes.active_color = col
    me.color_attributes.render_color_index = 0
    for p in me.polygons:
        if p.index in flat:
            p.use_smooth = False
    me.update()
    print("FACEAO head faces", len(flat), "range", round(min(flat.values()), 3), round(max(flat.values()), 3))
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
    print("FACEAO wrote", GLB)


main()
