"""Pass-3's head with a thin carved mouth in flat planes, the under-nose recess filled, the head lightly relaxed and smooth-shaded.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_face4.py -- [--out <blend>]
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
from prisoner2_face import bake_ao  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"

# Midline depth (y, m; more negative is forward) of the mouth planes, by face row t: philtrum, upper lip, line, lower lip, shelf, chin.
MOUTH_Y = [(4.5, -0.283), (5.0, -0.266), (5.35, -0.262), (5.65, -0.259), (5.9, -0.257), (6.0, -0.253),
           (6.12, -0.250), (6.24, -0.253), (6.5, -0.255), (6.8, -0.257), (7.1, -0.262)]
FILL_K = (1.9, 3.4)     # the planes fade out across these columns from the midline
LINE_K = (1.25, 1.9)    # the carved line and lip shelf, a narrower band
LINE_T = (5.95, 6.3)    # rows the line owns; outside the band they keep the fill only
RELAX = (0.25, 1)       # factor, passes on the face front only: slight
UV_LIFT = (5.9, 2.1)    # faces below this row sample skin this many rows higher, off the old painted mouth
SMOOTH_DEG = 42.0       # head normals smoothed across folds sharper than this stay creased


def mid_y(t):
    for (ta, ya), (tb, yb) in zip(MOUTH_Y, MOUTH_Y[1:]):
        if ta <= t <= tb:
            return ya + (yb - ya) * (t - ta) / (tb - ta)
    return None


def base(t, u):
    saved = f3.LIP_UP, f3.LIP_LO, f3.LIP_LINE, f3.LIP_SULCUS
    f3.LIP_UP, f3.LIP_LO, f3.LIP_LINE, f3.LIP_SULCUS = [(a, b, 0.0) for a, b, _c in saved]
    p = f3.surface(t, u)
    f3.LIP_UP, f3.LIP_LO, f3.LIP_LINE, f3.LIP_SULCUS = saved
    return p


def mouth(t, u):
    """Base surface with the mouth planes: the recess filled flat, the line and shelves carved shallow."""
    p = base(t, u)
    target = mid_y(t)
    if target is None:
        return p
    k = abs(u - 4)
    fill_t = t if t < LINE_T[0] or t > LINE_T[1] else None
    smooth_t = mid_y(LINE_T[0]) + (mid_y(LINE_T[1]) - mid_y(LINE_T[0])) * (t - LINE_T[0]) / (LINE_T[1] - LINE_T[0])
    plane = target if fill_t is not None else smooth_t
    d_fill = plane - base(t, 4).y
    d_line = target - plane
    p.y += f3.fade(*FILL_K, k) * d_fill + f3.fade(*LINE_K, k) * d_line
    return p


def lift_uvs(bm, grid):
    """Faces under the mouth line re-sample clean skin higher up the face, so the painted mouth no longer shows."""
    uvl = bm.loops.layers.uv.active
    at = {grid[lp.vert]: lp[uvl].uv.copy() for v in grid for lp in v.link_loops
          if all(w in grid for w in lp.face.verts)}

    def uv(t, u):
        rows = f3.ROWS_T
        k = max(i for i, r in enumerate(rows) if r <= t)
        if k == len(rows) - 1:
            return at[(t, u)]
        s = (t - rows[k]) / (rows[k + 1] - rows[k])
        return at[(rows[k], u)].lerp(at[(rows[k + 1], u)], s)
    for f in bm.faces:
        if all(v in grid and grid[v][0] >= UV_LIFT[0] for v in f.verts):
            for lp in f.loops:
                t, u = grid[lp.vert]
                lp[uvl].uv = uv(t - UV_LIFT[1], u)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[argv.index("--out") + 1] if "--out" in argv else None
    ob = bpy.data.objects["Runner"]
    arm = bpy.data.objects["Armature"]
    me = ob.data
    hi = ob.vertex_groups["Head"].index
    corner_n = [Vector(c.vector) for c in me.corner_normals]
    ao0 = [tuple(c.color) for c in me.color_attributes["Col"].data]
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    dfl = bm.verts.layers.deform.active
    head = {v for v in bm.verts if v[dfl].get(hi, 0.0) > 0.999}
    grid = {}
    for v in head:
        for t in f3.ROWS_T:
            for u in f3.COLS_U:
                if (v.co - f3.surface(t, u)).length < 1e-4:
                    grid[v] = (t, u)
    assert len(grid) == len(f3.ROWS_T) * len(f3.COLS_U), len(grid)
    carved = {v for v, (t, u) in grid.items() if mid_y(t) is not None and abs(u - 4) < FILL_K[1]}
    ridge = {v for v, (t, u) in grid.items() if 2.5 <= t <= 4.5 and abs(u - 4) <= 1.0}
    free = [v for v, (t, u) in grid.items() if 0 < t < 8 and 0 < u < 8 and v not in carved | ridge]
    for _ in range(RELAX[1]):
        avg = {v: sum((e.other_vert(v).co for e in v.link_edges), Vector()) / len(v.link_edges) for v in free}
        for v in free:
            v.co = v.co.lerp(avg[v], RELAX[0])
    for v in carved:
        v.co = mouth(*grid[v])
    lift_uvs(bm, grid)
    bm.to_mesh(me)
    bm.free()
    me.update()

    # smooth-shade the head: per-corner normals averaged over head faces within SMOOTH_DEG; everything else keeps its normals
    hidx = {v.index for v in me.vertices if any(g.group == hi and g.weight > 0.999 for g in v.groups)}
    hf = [p for p in me.polygons if all(i in hidx for i in p.vertices)]
    around = {}
    for p in hf:
        for i in p.vertices:
            around.setdefault(i, []).append(p)
    cos_lim = math.cos(math.radians(SMOOTH_DEG))
    normals = list(corner_n)
    for p in hf:
        for li in p.loop_indices:
            vi = me.loops[li].vertex_index
            n = sum((q.normal * q.area for q in around[vi] if q.normal.dot(p.normal) >= cos_lim), Vector())
            normals[li] = n.normalized()
    for p in hf:
        p.use_smooth = True
    me.normals_split_custom_set(normals)

    bake_ao(me)
    col = me.color_attributes["Col"].data
    for i, c in enumerate(ao0):
        if i not in hidx:
            col[i].color = c
    if out:
        bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
        print("FACE4 wrote", out, "tris", len(me.polygons))
        return
    bpy.ops.wm.save_mainfile()
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=GLB, export_format="GLB", use_selection=True,
                              export_apply=False, export_yup=True, export_normals=True,
                              export_texcoords=True, export_vertex_color="ACTIVE")
    glb_textures.externalize(GLB, lambda n, data: TEX_URI)
    print("FACE4 wrote", GLB, "tris", len(me.polygons))


if __name__ == "__main__":
    main()
