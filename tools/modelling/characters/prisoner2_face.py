"""Sculpt a faceless face in planes onto prisoner_joined.blend, add ears, thumbs, a softer neck, bake AO to vertex colour, re-export prisoner2.glb.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_face.py -- [--out <blend>]
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
from mathutils.geometry import barycentric_transform

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "modelling", "lib"))
import glb_textures  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"

# The face front as it shipped: five rows (brow edge to chin), each ordered +x to -x.
FACE_ROWS = [[36, 37, 38, 39, 40], [41, 42, 43, 44, 45], [46, 47, 48, 49, 50],
             [51, 52, 53, 54, 55], [56, 57, 58, 59, 60]]
# After one cut the front is a 9x9 lattice. Per lattice row: z, then depth (-y) from the midline out.
ROW_Z = [1.648, 1.623, 1.598, 1.572, 1.544, 1.528, 1.508, 1.487, 1.466]
DEPTH = [
    [.262, .266, .272, .264, .252],   # brow ridges over each eye, lower between them
    [.254, .250, .226, .236, .244],   # under the brow: nasion, socket roof
    [.256, .242, .208, .228, .238],   # eye line: bridge, socket floor deepest
    [.278, .246, .224, .242, .238],   # nose ridge, cheekbone
    [.304, .254, .238, .248, .235],   # nose tip, cheekbone
    [.256, .252, .240, .240, .230],   # under the nose, nostril wings
    [.234, .236, .240, .234, .225],   # mouth dent
    [.262, .256, .244, .234, .228],   # chin
    [.236, .234, .232, .231, .231],   # under the chin
]
COL_F = [0.0, 0.22, 0.48, 0.76, 1.0]  # column x as a share of the row's half width
JAW = {70: 0.084, 71: -0.084}          # jaw corners pushed out a little
NECK_RING = [30, 31, 32, 33, 34, 35]   # top of the neck: share the head's turn
NECK_HEAD = 0.3
AO_RAYS = 160
AO_DIST = 0.15
AO_GAIN = 2.2
AO_FLOOR = 0.28


def lattice_face(bm):
    """Cut the face front once and return {(row, col): vert} over the 9x9 lattice."""
    bm.verts.ensure_lookup_table()
    lat = {}
    for r, row in enumerate(FACE_ROWS):
        for c, i in enumerate(row):
            lat[bm.verts[i]] = (2 * r, 2 * c)
    fset = set(lat)
    faces = [f for f in bm.faces if all(v in fset for v in f.verts)]
    assert len(faces) == 32, len(faces)
    edges = {e for f in faces for e in f.edges}
    want = {rc: v.co.copy() for v, rc in lat.items()}
    for e in edges:
        a, b = e.verts
        (ra, ca), (rb, cb) = lat[a], lat[b]
        want[((ra + rb) // 2, (ca + cb) // 2)] = (a.co + b.co) / 2
    bmesh.ops.subdivide_edges(bm, edges=list(edges), cuts=1, use_grid_fill=True)
    kd = KDTree(len(bm.verts))
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        kd.insert(v.co, v.index)
    kd.balance()
    grid = {}
    for rc, p in want.items():
        _co, i, d = kd.find(p)
        assert d < 1e-5, (rc, d)
        grid[rc] = bm.verts[i]
    assert len(grid) == 81
    dfl = bm.verts.layers.deform.active
    head = bpy.data.objects["Runner"].vertex_groups["Head"].index
    for v in grid.values():
        if not v[dfl]:
            v[dfl][head] = 1.0
    return grid


def shape_face(grid):
    hw = {}
    for i in range(9):
        a, b = grid[(i, 0)].co.x, -grid[(i, 8)].co.x
        hw[i] = (a + b) / 2
    for (i, j), v in grid.items():
        k = abs(j - 4)
        sx = 1 if j < 4 else -1
        v.co.x = sx * hw[i] * COL_F[k]
        v.co.y = -DEPTH[i][k]
        v.co.z = ROW_Z[i]
    grid[(4, 4)].co.z -= 0.002


def _uv_at(bvh, src, p):
    """UV on the old surface nearest p."""
    loc, _n, fi, _d = bvh.find_nearest(p)
    f = src.faces[fi]
    uvl = src.loops.layers.uv.active
    tri = f.loops[:3]
    uv = barycentric_transform(loc, *(l.vert.co for l in tri),
                               *(Vector((l[uvl].uv.x, l[uvl].uv.y, 0)) for l in tri))
    return uv.x, uv.y


def add_ears(bm):
    """A small closed ear on each side, its root sunk into the head, its bowl dished."""
    src = bm.copy()
    src.faces.ensure_lookup_table()
    bvh = BVHTree.FromBMesh(src)
    uvl = bm.loops.layers.uv.active
    dfl = bm.verts.layers.deform.active
    head = bpy.data.objects["Runner"].vertex_groups["Head"].index
    bm.faces.ensure_lookup_table()
    smooth = bm.faces[0].smooth
    # Ear outline in (back, up) metres, around the root point.
    rim = [(-0.022, -0.030), (-0.020, 0.028), (0.006, 0.050), (0.030, 0.034), (0.028, -0.016), (0.006, -0.046)]
    for side in (1, -1):
        hit, n, _i, _d = bvh.ray_cast(Vector((side * 0.5, -0.02, 1.575)), Vector((-side, 0, 0)))
        assert hit is not None
        out = Vector((side, 0, 0))
        back, up = Vector((0, 1, 0)), Vector((0, 0, 1))
        ring_o, ring_i = [], []
        for bk, u in rim:
            flare = 0.014 + 0.016 * max(bk, 0) / 0.030
            p = hit + back * bk + up * u
            ring_o.append(bm.verts.new(p + out * flare))
            ring_i.append(bm.verts.new(hit + back * bk * 0.7 + up * u * 0.7 - out * 0.008))
        bowl = bm.verts.new(hit + back * 0.004 + out * 0.006)
        new = ring_o + ring_i + [bowl]
        for v in new:
            v[dfl][head] = 1.0
        fs = []
        m = len(rim)
        for k in range(m):
            a, b = k, (k + 1) % m
            fs.append(bm.faces.new((bowl, ring_o[a], ring_o[b])))
            fs.append(bm.faces.new((ring_o[a], ring_i[a], ring_i[b])))
            fs.append(bm.faces.new((ring_o[a], ring_i[b], ring_o[b])))
        bmesh.ops.recalc_face_normals(bm, faces=fs)
        c = sum((v.co for v in new), Vector()) / len(new)
        for f in fs:
            if f.normal.dot(f.calc_center_median() - c) < 0:
                f.normal_flip()
            f.material_index = 0
            f.smooth = smooth
            for l in f.loops:
                l[uvl].uv = _uv_at(bvh, src, l.vert.co)
    src.free()


def add_thumbs(bm):
    """Thumb off the front of each hand; the finger end curled toward the palm."""
    dfl = bm.verts.layers.deform.active
    ob = bpy.data.objects["Runner"]
    for name, sx in (("Hand.L", 1), ("Hand.R", -1)):
        g = ob.vertex_groups[name].index
        hand = [v for v in bm.verts if v[dfl].get(g, 0) > 0.99]
        front = [f for f in bm.faces if all(v in hand and v.co.y < -0.11 and 0.54 < v.co.z < 0.66 for v in f.verts)]
        assert len(front) == 2, (name, len(front))
        c = sum((f.calc_center_median() for f in front), Vector()) / 2
        uvl = bm.loops.layers.uv.active
        loops = [l for f in front for l in f.loops]
        skin = sum((l[uvl].uv for l in loops), Vector((0, 0))) / len(loops)
        ret = bmesh.ops.extrude_face_region(bm, geom=front)
        bmesh.ops.delete(bm, geom=front, context="FACES")
        tip = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
        for v in tip:
            d = v.co - c
            v.co = c + Vector((d.x * 0.5, d.y, d.z * 0.35)) + Vector((-sx * 0.010, -0.034, -0.036))
        for f in {f for v in tip for f in v.link_faces}:
            for l in f.loops:
                l[uvl].uv = skin
        zmin = min(v.co.z for v in hand)
        for v in hand:
            if v.co.z < zmin + 0.01:
                v.co.x -= sx * 0.016
                v.co.z += 0.008
            elif v.co.z < 0.56:
                v.co.x -= sx * 0.006


def soften_neck(bm):
    dfl = bm.verts.layers.deform.active
    ob = bpy.data.objects["Runner"]
    ng, hg = ob.vertex_groups["Neck"].index, ob.vertex_groups["Head"].index
    bm.verts.ensure_lookup_table()
    for i in NECK_RING:
        w = bm.verts[i][dfl]
        w[ng] = 1.0 - NECK_HEAD
        w[hg] = NECK_HEAD


def bake_ao(me):
    """Hemisphere occlusion per vertex, written to the 'Col' point colour (linear)."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    bvh = BVHTree.FromBMesh(bm)
    rnd = random.Random(7)
    dirs = []
    for _ in range(AO_RAYS):
        u, v = rnd.random(), rnd.random()
        r, t = math.sqrt(u), 2 * math.pi * v
        dirs.append(Vector((r * math.cos(t), r * math.sin(t), math.sqrt(1 - u))))
    vals = []
    for v in bm.verts:
        n = v.normal
        tz = n
        tx = (Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))).cross(tz).normalized()
        ty = tz.cross(tx)
        o = v.co + n * 0.002
        hits = 0
        for d in dirs:
            w = tx * d.x + ty * d.y + tz * d.z
            if bvh.ray_cast(o, w, AO_DIST)[0] is not None:
                hits += 1
        occ = hits / AO_RAYS
        vals.append(max(AO_FLOOR, 1.0 - AO_GAIN * occ))
    bm.free()
    for a in list(me.color_attributes):
        me.color_attributes.remove(a)
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for i, a in enumerate(vals):
        col.data[i].color = (a, a, a, 1.0)
    me.color_attributes.active_color = col
    me.color_attributes.render_color_index = 0


def multiply_materials(me):
    for m in me.materials:
        nt = m.node_tree
        if "AO" in nt.nodes:
            continue
        bsdf = nt.nodes["Principled BSDF"]
        img = [n for n in nt.nodes if n.type == "TEX_IMAGE"][0]
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.name = "AO"
        attr.layer_name = "Col"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(img.outputs["Color"], mix.inputs[6])
        nt.links.new(attr.outputs["Color"], mix.inputs[7])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[argv.index("--out") + 1] if "--out" in argv else None
    ob = bpy.data.objects["Runner"]
    arm = bpy.data.objects["Armature"]
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    for i, x in JAW.items():
        bm.verts[i].co.x = x
    soften_neck(bm)
    shape_face(lattice_face(bm))
    add_ears(bm)
    add_thumbs(bm)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    bm.to_mesh(me)
    bm.free()
    me.update()
    bake_ao(me)
    multiply_materials(me)
    if out:
        bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
        print("FACE wrote", out, "tris", len(me.polygons))
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
    print("FACE wrote", GLB, "tris", len(me.polygons))


if __name__ == "__main__":
    main()
