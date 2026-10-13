"""Pass-5's face at the body's level of detail: one vertex per lattice point, flat-shaded planes, AO re-baked.

    blender -b <a3199db5 prisoner_joined.blend> -P tools/modelling/characters/prisoner2_face6.py -- --save characters/models/prisoner_joined.blend
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
import prisoner2_face3 as f3  # noqa: E402
import prisoner2_face4 as f4  # noqa: E402
import prisoner2_face5 as f5  # noqa: E402
from prisoner2_face import FACE_ROWS, JAW, add_thumbs, bake_ao, multiply_materials  # noqa: E402
from prisoner2_face2 import close_crotch  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"

# One row per feature: brow, socket, bridge, cheekbone, nose tip, under nose, mouth line, chin, under chin.
ROWS_T = [0, 1, 2, 3, 4, 5, 6, 7, 8]
# Columns: rim, socket, inner eye, nose side, midline, mirrored.
COLS_U = [0, 1, 2, 3, 4, 5, 6, 7, 8]
UV_LIFT = (6.0, 2.1)   # faces from the mouth line down sample skin this many rows higher, off the painted mouth


def build_face(bm, head, orig):
    """Face front as one quad per lattice cell on pass-5's surface, split on its better diagonal; returns (chin row, faces)."""
    uvl = bm.loops.layers.uv.active
    dfl = bm.verts.layers.deform.active
    fset = {v for row in orig for v in row}
    uv0 = {}
    for v in fset:
        for lp in v.link_loops:
            if all(w in fset for w in lp.face.verts):
                uv0[v] = lp[uvl].uv.copy()
    front = [f for f in bm.faces if all(v in fset for v in f.verts)]
    assert len(front) == 32, len(front)
    bmesh.ops.delete(bm, geom=front, context="FACES_ONLY")
    inner = [orig[r][c] for r in range(1, 4) for c in range(1, 4)] + [orig[4][c] for c in (1, 2, 3)]
    bmesh.ops.delete(bm, geom=inner, context="VERTS")
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context="EDGES")

    def uv_at(t, u):
        r, c = min(t / 2, 3.9999), min(u / 2, 3.9999)
        r0, c0 = int(r), int(c)
        fr, fc = r - r0, c - c0
        q = [[uv0[orig[r0 + a][c0 + b]] for b in (0, 1)] for a in (0, 1)]
        return (q[0][0].lerp(q[0][1], fc)).lerp(q[1][0].lerp(q[1][1], fc), fr)

    surface = f3.surface
    grid = {}
    for t in ROWS_T:
        for u in COLS_U:
            if t % 2 == 0 and u % 2 == 0 and (t in (0, 8) or u in (0, 8)) and (t, u) not in ((8, 2), (8, 4), (8, 6)):
                v = orig[t // 2][u // 2]
                v.co = surface(t, u)
                grid[(t, u)] = v
    hw = {head: 1.0}
    for ua in range(0, 8, 2):   # the odd points on the brow rim and both side rims split the old rim edges
        grid[(0, ua + 1)] = f3.split_at(bm, grid[(0, ua)], grid[(0, ua + 2)], [surface(0, ua + 1)], hw)[0]
    for u in (0, 8):
        for ta in range(0, 8, 2):
            grid[(ta + 1, u)] = f3.split_at(bm, grid[(ta, u)], grid[(ta + 2, u)], [surface(ta + 1, u)], hw)[0]
    for t in ROWS_T:
        for u in COLS_U:
            if (t, u) not in grid:
                v = bm.verts.new(surface(t, u))
                v[dfl][head] = 1.0
                grid[(t, u)] = v
    faces = []
    for t in ROWS_T[:-1]:
        for u in COLS_U[:-1]:
            a, b, c, d = grid[(t, u)], grid[(t, u + 1)], grid[(t + 1, u + 1)], grid[(t + 1, u)]
            um = u if u < 4 else 7 - u   # pick on the +x half, mirror it, so the planes pair across the midline
            pa, pb, pc, pd = (surface(t + i, um + j) for i, j in ((0, 0), (0, 1), (1, 1), (1, 0)))
            m = surface(t + 0.5, um + 0.5)
            if (((pa + pc) / 2 - m).length <= ((pb + pd) / 2 - m).length) == (u < 4):
                tris = [(a, b, c), (a, c, d)]
            else:
                tris = [(a, b, d), (b, c, d)]
            faces += [bm.faces.new(tri) for tri in tris]
    inv = {v: k for k, v in grid.items()}
    for f in faces:
        f.material_index = 0
        for lp in f.loops:
            lp[uvl].uv = uv_at(*inv[lp.vert])
    return [grid[(8, u)] for u in COLS_U], faces


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    save = argv[argv.index("--save") + 1] if "--save" in argv else None
    f5.patch()
    f3.ROWS_T, f3.COLS_U, f4.UV_LIFT = ROWS_T, COLS_U, UV_LIFT
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
    chin, face = build_face(bm, gi["Head"], orig)
    neck_faces = f3.build_neck(bm, collar, chin + back, gi)
    bm.normal_update()
    f3.neck_uvs(bm, neck_faces)
    close_crotch(bm)
    add_thumbs(bm)
    for f in set(face) | set(neck_faces):
        f.material_index = 0
        f.smooth = False
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3], quad_method="BEAUTY")
    assert not [e for e in bm.edges if not e.is_manifold]
    grid = {}
    for v in {v for f in face for v in f.verts}:
        for t in ROWS_T:
            for u in COLS_U:
                if (v.co - f3.surface(t, u)).length < 1e-4:
                    grid[v] = (t, u)
    assert len(grid) == len(ROWS_T) * len(COLS_U), len(grid)
    f4.lift_uvs(bm, grid)
    bm.to_mesh(me)
    bm.free()
    me.update()
    bake_ao(me)
    multiply_materials(me)
    print("FACE6 tris", len(me.polygons))
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
    print("FACE6 wrote", GLB)


if __name__ == "__main__":
    main()
