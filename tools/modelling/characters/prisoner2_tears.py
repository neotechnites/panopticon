"""Cut torn hems into the shirt and both pant cuffs of prisoner_joined.blend, then re-export prisoner2.glb.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_tears.py -- [--dry]

Each hem edge is split and the new verts pulled along the neighbouring face: down = tooth, negative = notch.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "modelling", "lib"))
import glb_textures  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"
REACH = 0.8        # a tooth never travels past this share of the way to the far vertex
UV_DV = 0.02       # keep tooth UVs this far inside their own swatch (up on the cloth side)

# Shirt hem: the ring 2..7 at z=0.89. Offsets per edge, metres, + down / - notch up.
SHIRT_EDGES = {
    (2, 3): [0.040, -0.016, 0.034, -0.012],
    (3, 4): [0.032, -0.014, 0.068, -0.020],
    (4, 5): [0.038, -0.018, 0.030, -0.010],
    (5, 6): [0.034, -0.012, 0.042, -0.016],
    (6, 7): [0.030, -0.020, 0.036, -0.012],
    (7, 2): [0.068, -0.014, 0.032, -0.018],
}
# Pant cuff: the ring at z=0.1 per leg, offsets per edge (a, b, ... in ring order). Mirrored by side.
CUFF_EDGES = [
    [0.036, -0.018, 0.028],
    [0.020, -0.012, 0.075],
    [0.032, -0.020, 0.026],
    [0.026, -0.014, 0.034],
]


def _weights(bm, v):
    lay = bm.verts.layers.deform.active
    return dict(v[lay])


def tear_edge(bm, a, b, offsets):
    """Replace the two faces on edge a-b with fans whose shared edge zig-zags by offsets."""
    uvl = bm.loops.layers.uv.active
    dfl = bm.verts.layers.deform.active
    edge = bm.edges.get((a, b))
    faces = list(edge.link_faces)
    assert len(faces) == 2, (a.index, b.index)

    def apex(f):
        return [v for v in f.verts if v not in (a, b)][0]

    up, dn = sorted(faces, key=lambda f: apex(f).co.z, reverse=True)
    n = len(offsets)
    ts = [(i + 1) / (n + 1) for i in range(n)]
    pts = []
    for t, off in zip(ts, offsets):
        p = a.co.lerp(b.co, t)
        far = apex(dn) if off > 0 else apex(up)
        d = far.co - p
        amt = min(abs(off), d.length * REACH)
        p = p + d.normalized() * amt
        v = bm.verts.new(p)
        wa, wb = _weights(bm, a), _weights(bm, b)
        for g in set(wa) | set(wb):
            v[dfl][g] = wa.get(g, 0.0) * (1 - t) + wb.get(g, 0.0) * t
        pts.append(v)
    chain = [a] + pts + [b]

    def uv_of(face, v):
        return [l[uvl].uv.copy() for l in face.loops if l.vert == v][0]

    def rebuild(face, dv):
        fwd = [l for l in face.loops if l.vert == a][0].link_loop_next.vert == b
        mat = face.material_index
        ap = apex(face)
        uvs = {v: uv_of(face, v) for v in (a, b, ap)}
        for t, v in zip(ts, pts):
            u = uvs[a].lerp(uvs[b], t)
            u.y += dv
            uvs[v] = u
        seq = chain if fwd else chain[::-1]
        for p, q in zip(seq[:-1], seq[1:]):
            f = bm.faces.new((p, q, ap))
            f.material_index = mat
            f.smooth = face.smooth
            for l in f.loops:
                l[uvl].uv = uvs[l.vert]

    rebuild(up, +UV_DV)
    rebuild(dn, -UV_DV)
    bmesh.ops.delete(bm, geom=[up, dn], context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[edge], context="EDGES")
    return pts


def cuff_ring(bm, side):
    ring = [v for v in bm.verts if abs(v.co.z - 0.1) < 0.003 and (v.co.x > 0) == (side > 0)
            and v.co.y > -0.04 and v.co.y < 0.04 and abs(v.co.x) > 0.05]
    assert len(ring) == 4, len(ring)
    return ring


def ordered(ring):
    c = sum((v.co for v in ring), Vector()) / 4
    return sorted(ring, key=lambda v: math.atan2(v.co.y - c.y, v.co.x - c.x))


def main():
    dry = "--dry" in sys.argv
    ob = bpy.data.objects["Runner"]
    arm = bpy.data.objects["Armature"]
    if not dry:
        me = ob.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.verts.ensure_lookup_table()
        orig = list(bm.verts)
        v = lambda i: orig[i]
        for (i, j), offs in SHIRT_EDGES.items():
            tear_edge(bm, v(i), v(j), offs)
        for side in (1, -1):
            ring = ordered(cuff_ring(bm, side))
            for k in range(4):
                a, b = ring[k], ring[(k + 1) % 4]
                if side < 0:
                    offs = CUFF_EDGES[(k + 2) % 4][::-1]
                else:
                    offs = CUFF_EDGES[k]
                tear_edge(bm, a, b, offs)
        bm.to_mesh(me)
        bm.free()
        me.update()
        bpy.ops.wm.save_mainfile()
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = arm
    path = GLB if not dry else os.path.join(os.environ.get("TMPDIR", "/tmp"), "prisoner2_dry.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=False, export_yup=True, export_normals=True,
                              export_texcoords=True)
    glb_textures.externalize(path, lambda n, data: TEX_URI)
    print("TEARS wrote", path, "tris", len(ob.data.polygons))


main()
