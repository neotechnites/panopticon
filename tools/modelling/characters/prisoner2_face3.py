"""Pass-1's planed face on the original wedge, re-gridded finer with lips; pass-2's lofted neck and crotch cloth; AO re-baked.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_face3.py -- [--out <blend>]
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
from prisoner2_face import (COL_F, DEPTH, FACE_ROWS, JAW, ROW_Z, add_thumbs,  # noqa: E402
                            bake_ao, multiply_materials)
from prisoner2_face2 import F, SKIN, angle_about, close_crotch, on_ring, zipper  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"

RIM_X = [0.098, 0.115, 0.118, 0.070, 0.030]   # face front half width per original row
# Grid rows/columns in pass-1 lattice units (0..8); rows bunch round the mouth so the lips get their own loops.
ROWS_T = [0, .5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.35, 5.65, 5.9, 6.0, 6.12, 6.24, 6.5, 6.8, 7.1, 7.5, 8]
COLS_U = [i * 0.5 for i in range(17)]
LIP_UP = (5.75, 0.42, 0.011)    # upper lip: row centre, half height, forward (m)
LIP_LO = (6.5, 0.38, 0.013)     # lower lip, over the painted mouth
LIP_LINE = (6.12, 0.13, 0.012)  # the mouth line between them, pressed back
LIP_SULCUS = (6.85, 0.22, 0.006)  # the dip under the lower lip, before the chin
LIP_K = (1.35, 2.05)            # lips fade out between these columns from the midline
LINE_K = (1.7, 2.35)            # the line runs a little past the lips
NECK_RINGS = (0.2, 0.4, 0.6, 0.8)
NECK_SIDES = 12
NECK_FLARE = 0.25


def lattice(i, j):
    """Pass-1's sculpted 9x9 lattice point, extrapolated linearly past the edges."""
    if i < 0:
        return 2 * lattice(0, j) - lattice(1, j)
    if i > 8:
        return 2 * lattice(8, j) - lattice(7, j)
    if j < 0:
        return 2 * lattice(i, 0) - lattice(i, 1)
    if j > 8:
        return 2 * lattice(i, 8) - lattice(i, 7)
    hw = RIM_X[i // 2] if i % 2 == 0 else (RIM_X[i // 2] + RIM_X[i // 2 + 1]) / 2
    k = abs(j - 4)
    sx = 1 if j < 4 else -1
    p = Vector((sx * hw * COL_F[k], -DEPTH[i][k], ROW_Z[i]))
    if (i, j) == (4, 4):
        p.z -= 0.002
    return p


def cr(p0, p1, p2, p3, s):
    return 0.5 * (2 * p1 + (p2 - p0) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s * s + (3 * p1 - p0 - 3 * p2 + p3) * s ** 3)


def bump(d, r):
    q = (d / r) ** 2
    return (1 - q) ** 2 if q < 1 else 0.0


def fade(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return 1 - t * t * (3 - 2 * t)


def surface(t, u):
    i0, j0 = min(int(t), 7), min(int(u), 7)
    s, r = t - i0, u - j0
    rows = [cr(*(lattice(i0 + di, j0 + dj) for dj in (-1, 0, 1, 2)), r) for di in (-1, 0, 1, 2)]
    p = cr(*rows, s)
    if 0 < t < 8 and 0 < u < 8:
        k = abs(u - 4)
        lip = fade(*LIP_K, k)
        fwd = lip * (LIP_UP[2] * bump(t - LIP_UP[0], LIP_UP[1]) + LIP_LO[2] * bump(t - LIP_LO[0], LIP_LO[1]))
        fwd -= fade(*LINE_K, k) * LIP_LINE[2] * bump(t - LIP_LINE[0], LIP_LINE[1])
        fwd -= lip * LIP_SULCUS[2] * bump(t - LIP_SULCUS[0], LIP_SULCUS[1])
        p.y -= fwd
    return p


def split_at(bm, a, b, pts, weights):
    """Split edge a-b at points pts (ordered from a); each adjoining face's UVs lerped along the old edge."""
    uvl = bm.loops.layers.uv.active
    dfl = bm.verts.layers.deform.active
    e = bm.edges.get((a, b))
    seg = b.co - a.co
    keep = []
    for f in e.link_faces:
        ua = next(lp[uvl].uv.copy() for lp in f.loops if lp.vert is a)
        ub = next(lp[uvl].uv.copy() for lp in f.loops if lp.vert is b)
        keep.append((f, ua, ub))
    out, cur = [], a
    for p in pts:
        s = (p - a.co).dot(seg) / seg.length_squared
        ed = bm.edges.get((cur, b))
        rest = (b.co - cur.co).length
        _ne, nv = bmesh.utils.edge_split(ed, cur, min(max((p - cur.co).length / rest, 0.01), 0.99))
        nv.co = p
        for g, w in weights.items():
            nv[dfl][g] = w
        for f, ua, ub in keep:
            for lp in f.loops:
                if lp.vert is nv:
                    lp[uvl].uv = ua.lerp(ub, min(max(s, 0.0), 1.0))
        out.append(nv)
        cur = nv
    return out


def build_face(bm, head, orig):
    """Replace the face front with a finer grid on pass-1's sculpted surface; returns the chin row (+x to -x)."""
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
    smooth_flag = front[0].smooth
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

    grid = {}
    for ti, t in enumerate(ROWS_T):
        for ui, u in enumerate(COLS_U):
            if t % 2 == 0 and u % 2 == 0 and (t in (0, 8) or u in (0, 8)) and (t, u) not in ((8, 2), (8, 4), (8, 6)):
                v = orig[int(t) // 2][int(u) // 2]
                v.co = surface(t, u)
                grid[(ti, ui)] = v
    # rim splits: top row along u, both sides along t
    hw = {head: 1.0}
    for ui in range(0, len(COLS_U) - 1):
        u = COLS_U[ui]
        if u % 2 == 0:
            a, b = grid[(0, ui)], grid[(0, ui + 4)]
            new = split_at(bm, a, b, [surface(0, COLS_U[ui + k]) for k in (1, 2, 3)], hw)
            for k, v in enumerate(new):
                grid[(0, ui + k + 1)] = v
    for ui in (0, len(COLS_U) - 1):
        u = COLS_U[ui]
        tis = [ti for ti, t in enumerate(ROWS_T) if t % 2 == 0]
        for ta, tb in zip(tis, tis[1:]):
            new = split_at(bm, grid[(ta, ui)], grid[(tb, ui)], [surface(ROWS_T[ti], u) for ti in range(ta + 1, tb)], hw)
            for k, v in enumerate(new):
                grid[(ta + 1 + k, ui)] = v
    for ti, t in enumerate(ROWS_T):
        for ui, u in enumerate(COLS_U):
            if (ti, ui) not in grid:
                v = bm.verts.new(surface(t, u))
                v[dfl][head] = 1.0
                grid[(ti, ui)] = v
    faces = []
    nr, ncol = len(ROWS_T), len(COLS_U)
    for ti in range(nr - 1):
        for ui in range(ncol - 1):
            a, b, c, d = grid[(ti, ui)], grid[(ti, ui + 1)], grid[(ti + 1, ui + 1)], grid[(ti + 1, ui)]
            tm, um = (ROWS_T[ti] + ROWS_T[ti + 1]) / 2, (COLS_U[ui] + COLS_U[ui + 1]) / 2
            m = surface(tm, um)
            if ((a.co + c.co) / 2 - m).length <= ((b.co + d.co) / 2 - m).length:
                tris = [(a, b, c), (a, c, d)]
            else:
                tris = [(a, b, d), (b, c, d)]
            for tri in tris:
                f = bm.faces.new(tri)
                faces.append(f)
    inv = {v: k for k, v in grid.items()}
    for f in faces:
        f.material_index = 0
        f.smooth = smooth_flag
        for lp in f.loops:
            ti, ui = inv[lp.vert]
            lp[uvl].uv = uv_at(ROWS_T[ti], COLS_U[ui])
    return [grid[(nr - 1, ui)] for ui in range(ncol)], faces


def boundary_from(v0):
    """The boundary loop through v0, following face winding."""
    nxt = {}
    seen, stack = set(), [v0]
    while stack:
        v = stack.pop()
        if v in seen:
            continue
        seen.add(v)
        for e in v.link_edges:
            if e.is_boundary:
                a, b = e.verts
                lp = e.link_loops[0]
                if lp.vert is a:
                    nxt[b] = a
                else:
                    nxt[a] = b
                stack.append(e.other_vert(v))
    loop, v = [v0], nxt[v0]
    while v is not v0:
        loop.append(v)
        v = nxt[v]
    return loop


def build_neck(bm, collar, hole, gi):
    """Loft the neck from the collar ring up into the head's underside hole: one clean section, even rings."""
    dfl = bm.verts.layers.deform.active
    cc = sum((v.co for v in collar), Vector()) / len(collar)
    entry = sum((v.co for v in hole), Vector()) / len(hole)
    axis = (entry - cc).normalized()

    def ascending(ring, c):
        an = [angle_about(v.co, c, axis) for v in ring]
        turn = sum((an[(k + 1) % len(an)] - an[k] + math.pi) % (2 * math.pi) - math.pi for k in range(len(an)))
        return ring if turn > 0 else list(reversed(ring))
    collar, hole = ascending(collar, cc), ascending(hole, entry)
    fx = (F - axis * F.dot(axis)).normalized()
    xx = axis.cross(fx)
    length = (entry - cc).length
    rings = [[] for _ in NECK_RINGS]
    for k in range(NECK_SIDES):
        th = 2 * math.pi * k / NECK_SIDES
        d = fx * math.cos(th) + xx * math.sin(th)
        c0 = on_ring(collar, cc, axis, d)[0]
        c1 = on_ring(hole, entry, axis, d)[0]
        radial = c1 - entry
        radial -= axis * radial.dot(axis)
        t0 = axis * length
        t1 = (axis + radial.normalized() * NECK_FLARE).normalized() * length * 0.8
        for i, u in enumerate(NECK_RINGS):
            h00, h10, h01, h11 = 2 * u**3 - 3 * u**2 + 1, u**3 - 2 * u**2 + u, -2 * u**3 + 3 * u**2, u**3 - u**2
            rings[i].append(c0 * h00 + t0 * h10 + c1 * h01 + t1 * h11)
    vr = []
    for i, u in enumerate(NECK_RINGS):
        hd = max(0.0, min(1.0, (u - 0.15) / 0.85))
        hd = hd * hd * (3 - 2 * hd)
        sp = max(0.0, 0.5 * (1 - u / 0.5))
        ring = []
        for p in rings[i]:
            v = bm.verts.new(p)
            for g, w in (("Spine", sp), ("Head", hd), ("Neck", 1 - hd - sp)):
                if w > 0:
                    v[dfl][gi[g]] = w
            ring.append(v)
        vr.append(ring)
    faces = zipper(bm, collar, vr[0], cc, axis)
    for a, b in zip(vr, vr[1:]):
        for k in range(NECK_SIDES):
            k2 = (k + 1) % NECK_SIDES
            faces.append(bm.faces.new((a[k], a[k2], b[k2], b[k])))
    faces += zipper(bm, vr[-1], hole, entry, axis)
    return faces


def neck_uvs(bm, faces):
    """Box-map the neck onto the albedo's plain skin square."""
    uvl = bm.loops.layers.uv.active
    x0, y0, w, h = SKIN
    texel = min(w, h) / 0.22
    for f in faces:
        n = f.normal
        side = abs(n.x) > abs(n.y)
        for lp in f.loops:
            c = lp.vert.co
            a = (c.y + 0.25) if side else (c.x + 0.11)
            px = x0 + a * texel
            py = y0 + (1.50 - c.z) * texel
            lp[uvl].uv = (px / 512, 1 - py / 512)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[argv.index("--out") + 1] if "--out" in argv else None
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
    hole = chin + back
    neck_faces = build_neck(bm, collar, hole, gi)
    bm.normal_update()
    neck_uvs(bm, neck_faces)
    close_crotch(bm)
    add_thumbs(bm)
    new = set(face) | set(neck_faces)
    for f in bm.faces:
        if f in new:
            f.material_index = 0
            f.smooth = face[0].smooth
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3], quad_method="BEAUTY")
    bad = [e for e in bm.edges if not e.is_manifold]
    assert not bad, len(bad)
    bm.to_mesh(me)
    bm.free()
    me.update()
    bake_ao(me)
    multiply_materials(me)
    if out:
        bpy.ops.wm.save_as_mainfile(filepath=out, copy=True)
        print("FACE3 wrote", out, "tris", len(me.polygons))
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
    print("FACE3 wrote", GLB, "tris", len(me.polygons))


if __name__ == "__main__":
    main()
