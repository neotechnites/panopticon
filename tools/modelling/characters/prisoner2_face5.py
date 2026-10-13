"""Pass-3's build on a coarser grid: sockets under the painted eye patches, a shallow carved mouth line, smooth-shaded head, AO re-baked.

    blender -b <a3199db5 prisoner_joined.blend> -P tools/modelling/characters/prisoner2_face5.py -- --save characters/models/prisoner_joined.blend
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "modelling", "lib"))
sys.path.insert(0, HERE)
import glb_textures  # noqa: E402
import prisoner2_face3 as f3  # noqa: E402
import prisoner2_face4 as f4  # noqa: E402
from prisoner2_face import FACE_ROWS, JAW, add_thumbs, bake_ao, multiply_materials  # noqa: E402
from prisoner2_face2 import close_crotch  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"

# Rows in lattice units: fine through the sockets (t 0..2, where the painted patches sit), sparse down the cheeks.
ROWS_T = [0, .5, 1, 1.5, 2, 3, 3.5, 4, 5, 5.5, 6, 6.5, 7, 8]
# Depth (-y) per lattice row, midline out; sockets deepest at (1, 3), under the painted patch centres, the brow over them.
DEPTH = [
    [.258, .262, .268, .268, .254],   # brow ridge, over each socket
    [.250, .240, .228, .214, .238],   # nasion; socket deepest
    [.258, .244, .230, .226, .236],   # bridge; socket floor rising
    [.278, .248, .238, .246, .238],   # nose ridge, cheekbone
    [.304, .254, .240, .250, .235],   # nose tip, cheekbone
    [.256, .248, .240, .240, .230],   # under the nose
    [.246, .244, .240, .234, .225],   # mouth: front kept flat, no dent
    [.254, .250, .242, .234, .228],   # chin
    [.236, .234, .232, .231, .231],   # under the chin
]
LINE = (6.0, 0.3, 0.006)   # carved mouth line: row, half height, depth back (m)
LINE_K = (1.0, 1.8)        # the line fades out across these columns from the midline
UV_LIFT = (5.5, 2.1)       # faces from this row down sample skin this many rows higher, off the painted mouth
SMOOTH_DEG = 42.0

_surface = f3.surface


def surface(t, u):
    p = _surface(t, u)
    if 0 < t < 8 and 0 < u < 8:
        p.y += LINE[2] * f3.fade(*LINE_K, abs(u - 4)) * f3.bump(t - LINE[0], LINE[1])
    return p


def patch():
    f3.ROWS_T = ROWS_T
    f3.DEPTH = DEPTH
    for n in ("LIP_UP", "LIP_LO", "LIP_LINE", "LIP_SULCUS"):
        a, b, _c = getattr(f3, n)
        setattr(f3, n, (a, b, 0.0))
    f3.surface = surface
    f4.UV_LIFT = UV_LIFT


def smooth_head(me, hi):
    """Per-corner normals averaged over head faces within SMOOTH_DEG; everything else keeps its normals."""
    corner_n = [Vector(c.vector) for c in me.corner_normals]
    hidx = {v.index for v in me.vertices if any(g.group == hi and g.weight > 0.999 for g in v.groups)}
    hf = [p for p in me.polygons if all(i in hidx for i in p.vertices)]
    around = {}
    for p in hf:
        for i in p.vertices:
            around.setdefault(i, []).append(p)
    cos_lim = math.cos(math.radians(SMOOTH_DEG))
    for p in hf:
        for li in p.loop_indices:
            vi = me.loops[li].vertex_index
            corner_n[li] = sum((q.normal * q.area for q in around[vi] if q.normal.dot(p.normal) >= cos_lim),
                               Vector()).normalized()
        p.use_smooth = True
    me.normals_split_custom_set(corner_n)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    save = argv[argv.index("--save") + 1] if "--save" in argv else None
    patch()
    ob = bpy.data.objects["Runner"]
    arm = bpy.data.objects["Armature"]
    me = ob.data
    gi = {n: ob.vertex_groups[n].index for n in ("Spine", "Neck", "Head")}
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    for i, x in JAW.items():
        bm.verts[i].co.x = x
    back = [bm.verts[i] for i in (76, 75, 74, 73, 72)]
    neck = [bm.verts[i] for i in range(30, 36)]
    collar = [bm.verts[i] for i in range(239, 245)]
    orig = [[bm.verts[i] for i in row] for row in FACE_ROWS]
    bmesh.ops.delete(bm, geom=neck, context="VERTS")
    chin, face = f3.build_face(bm, gi["Head"], orig)
    neck_faces = f3.build_neck(bm, collar, chin + back, gi)
    bm.normal_update()
    f3.neck_uvs(bm, neck_faces)
    close_crotch(bm)
    add_thumbs(bm)
    for f in set(face) | set(neck_faces):
        f.material_index = 0
        f.smooth = face[0].smooth
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3], quad_method="BEAUTY")
    assert not [e for e in bm.edges if not e.is_manifold]
    fv = {v for f in face for v in f.verts}
    grid = {}
    for v in fv:
        for t in ROWS_T:
            for u in f3.COLS_U:
                if (v.co - surface(t, u)).length < 1e-4:
                    grid[v] = (t, u)
    assert len(grid) == len(ROWS_T) * len(f3.COLS_U), len(grid)
    f4.lift_uvs(bm, grid)
    bm.to_mesh(me)
    bm.free()
    me.update()
    smooth_head(me, gi["Head"])
    bake_ao(me)
    multiply_materials(me)
    print("FACE5 tris", len(me.polygons))
    if save:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(save))
    if "--no-export" in argv:
        return
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=GLB, export_format="GLB", use_selection=True,
                              export_apply=False, export_yup=True, export_normals=True,
                              export_texcoords=True, export_vertex_color="ACTIVE")
    glb_textures.externalize(GLB, lambda n, data: TEX_URI)
    print("FACE5 wrote", GLB)


if __name__ == "__main__":
    main()
