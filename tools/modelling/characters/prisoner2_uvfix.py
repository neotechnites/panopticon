"""Texture mapping repaired at the pits and shoulder fronts (Ryan's a3199db5 UVs back), collapsed and off-island UVs fixed; shape untouched.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_uvfix.py -- --save characters/models/prisoner_joined.blend
"""

import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector, kdtree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "modelling", "lib"))
import glb_textures  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX = os.path.join(ROOT, "characters", "textures", "prisoner2_albedo.png")
TEX_URI = "../textures/prisoner2_albedo.png"
HEM_Z = 0.95                # torn hems and cuffs lie below this
FRONT_U = (80, 160)         # atlas px columns of the chest island
RYAN_UV = {                 # shoulder-front corners as Ryan's mapping had them (atlas px), before the neck passes
    (507, 220): (315.5, 14.6),                                           # pit face: sleeve island, not the empty rows
    (485, 220): (128.0, 255.7), (485, 255): (148.1, 259.2), (485, 221): (142.4, 244.0),
    (417, 220): (128.0, 255.7), (417, 221): (142.4, 244.0), (417, 25): (126.2, 248.6),  # 25 unfolded off 485
}
TOP_Z, TOP_N, FOLD_Z = 1.1, 0.45, 1.3   # shoulder-top faces: above TOP_Z, facing up past TOP_N (or folded under, above FOLD_Z)
TOP_SKIP = {485}            # the front shoulder slope stays on Ryan's chest island
TOP_AT = (112.0, 272.0)     # atlas px of the top patch's front-inner corner, in the chest island's plain white
DENSITY = 0.376 * 512       # atlas px per metre, the body's
SLEEVE_U = 300              # atlas px column where the sleeve islands start
FACE_VERTS = {507: {220, 251, 255}, 485: {220, 255, 221}, 417: {220, 221, 25}}   # +X faces by their corners
FRONT_220 = (128.0, 255.7)  # the shoulder-front corner on the chest island, shared by every face there


def px(uv):
    return uv[0] * 512, (1 - uv[1]) * 512


class Atlas:
    def __init__(self):
        img = bpy.data.images.load(TEX, check_existing=True)
        w, h = img.size
        self.a = np.array(img.pixels[:]).reshape(h, w, 4)[::-1]   # row 0 = top
        empty = self.a[..., 3] < 0.5
        grown = empty.copy()
        grown[1:] |= empty[:-1]
        grown[:-1] |= empty[1:]
        grown[:, 1:] |= empty[:, :-1]
        grown[:, :-1] |= empty[:, 1:]
        self.edge = grown              # empty texels and the ring that linear filtering darkens

    def kind(self, u, v):
        x, y = int(min(511, max(0, u * 512))), int(min(511, max(0, (1 - v) * 512)))
        r, g, b, a = self.a[y, x] * 255
        if self.edge[y, x]:
            return "empty"
        if b > r + 15:
            return "blue"
        if r > 170 and g > 170 and b > 170 and abs(r - b) < 25:
            return "white"
        return "skin" if r > 140 else "brown"

    def samples(self, uvs):
        out = []
        for i in range(1, len(uvs) - 1):
            a, b, c = uvs[0], uvs[i], uvs[i + 1]
            for s in np.linspace(0.03, 0.94, 10):
                for t in np.linspace(0.03, 0.94, 10):
                    if s + t < 0.97:
                        p = a + (b - a) * s + (c - a) * t
                        out.append(self.kind(p.x, p.y))
        return out


def lscm(faces, pins, uvl):
    """Least-squares conformal UVs for faces, pinned verts held; handedness picked to match the pins."""
    verts = sorted({v for f in faces for v in f.verts}, key=lambda v: v.index)
    free = [v for v in verts if v not in pins]
    idx = {v: i for i, v in enumerate(free)}
    best = None
    for hand in (1, -1):
        rows, rhs = [], []
        for f in faces:
            vs = list(f.verts)
            for k in range(1, len(vs) - 1):
                tri = (vs[0], vs[k], vs[k + 1])
                e1, e2 = tri[1].co - tri[0].co, tri[2].co - tri[0].co
                n = e1.cross(e2)
                area = n.length / 2
                if area < 1e-10:
                    continue
                x = e1.normalized()
                y = n.normalized().cross(x) * hand
                p = [((q.co - tri[0].co).dot(x), (q.co - tri[0].co).dot(y)) for q in tri]
                w = 1 / np.sqrt(area)
                W = [complex(p[(j + 2) % 3][0] - p[(j + 1) % 3][0], p[(j + 2) % 3][1] - p[(j + 1) % 3][1]) * w
                     for j in range(3)]
                re, im = np.zeros(2 * len(free)), np.zeros(2 * len(free))
                cre = cim = 0.0
                for j, q in enumerate(tri):
                    a, b = W[j].real, W[j].imag
                    if q in pins:
                        u, v = pins[q]
                        cre += a * u - b * v
                        cim += a * v + b * u
                    else:
                        i = idx[q]
                        re[2 * i], re[2 * i + 1] = a, -b
                        im[2 * i], im[2 * i + 1] = b, a
                rows += [re, im]
                rhs += [-cre, -cim]
        A, r = np.array(rows), np.array(rhs)
        sol, *_ = np.linalg.lstsq(A, r, rcond=None)
        err = np.linalg.norm(A @ sol - r)
        if best is None or err < best[0]:
            best = (err, sol)
    sol = best[1]
    uv = dict(pins)
    for v, i in idx.items():
        uv[v] = Vector((sol[2 * i], sol[2 * i + 1]))
    for f in faces:
        for lp in f.loops:
            lp[uvl].uv = uv[lp.vert]


def centre_px(f, uvl):
    return sum((Vector(px(lp[uvl].uv)) for lp in f.loops), Vector((0, 0))) / len(f.loops)


def pins_from(anchors, region, uvl):
    rv = {v for f in region for v in f.verts}
    pins = {}
    for f in anchors:
        for lp in f.loops:
            if lp.vert in rv and lp.vert not in pins:
                pins[lp.vert] = lp[uvl].uv.copy()
    return pins


def mirror_uvs(bm, faces, uvl):
    """Copy each fixed +X face's UVs onto its -X twin, vertex for vertex."""
    kd = kdtree.KDTree(len(bm.verts))
    for v in bm.verts:
        kd.insert(v.co, v.index)
    kd.balance()
    bm.verts.ensure_lookup_table()
    twin = lambda v: bm.verts[kd.find(Vector((-v.co.x, v.co.y, v.co.z)))[1]]  # noqa: E731
    n = 0
    for f in faces:
        if f.calc_center_median().x < 0.002:
            continue
        mv = [twin(v) for v in f.verts]
        g = bm.faces.get(mv)
        if g is None:
            continue
        src = {lp.vert: lp[uvl].uv.copy() for lp in f.loops}
        for lp in g.loops:
            lp[uvl].uv = src[twin(lp.vert)]
        n += 1
    return n


def restore_shoulders(bm, uvl):
    """Pit and shoulder-front faces back on Ryan's UVs, the chest island's corner vertex made one point again."""
    faces = {}
    for (fi, vi), (x, y) in RYAN_UV.items():
        f = next(f for f in bm.verts[vi].link_faces if {v.index for v in f.verts} == FACE_VERTS[fi])
        for lp in f.loops:
            if lp.vert.index == vi:
                lp[uvl].uv = (x / 512, 1 - y / 512)
        faces[fi] = f
    for f in bm.verts[220].link_faces:
        if f.material_index == 1 and FRONT_U[0] <= centre_px(f, uvl).x < FRONT_U[1]:
            for lp in f.loops:
                if lp.vert.index == 220:
                    lp[uvl].uv = (FRONT_220[0] / 512, 1 - FRONT_220[1] / 512)
            faces[f.index] = f
    return list(faces.values())


def lay_top(bm, uvl):
    """Shoulder tops, +X: one patch of plain shirt seen from above at body density, so they meet without jumps."""
    top = [f for f in bm.faces if f.material_index == 1 and f.index not in TOP_SKIP
           and f.calc_center_median().x > -0.001 and f.calc_center_median().z > TOP_Z
           and centre_px(f, uvl).x < SLEEVE_U
           and (f.normal.z > TOP_N or (f.normal.z < -TOP_N and f.calc_center_median().z > FOLD_Z))]
    vs = {v for f in top for v in f.verts}
    x0, y0 = min(v.co.x for v in vs), min(v.co.y for v in vs)
    for f in top:
        for lp in f.loops:
            co = lp.vert.co
            lp[uvl].uv = ((TOP_AT[0] + (co.x - x0) * DENSITY) / 512, 1 - (TOP_AT[1] + (co.y - y0) * DENSITY) / 512)
    print("UVFIX shoulder tops", sorted(f.index for f in top))
    return top


def degenerate(f, uvl):
    a, b, c = (lp[uvl].uv for lp in list(f.loops)[:3])
    return abs((b - a).cross(c - a)) < 1e-9


def relay_collapsed(bm, uvl, skip):
    """Faces whose UVs collapsed to a point or a line (thumbs, crotch gusset, a head facet): unfolded from their neighbours."""
    bad = [f for f in bm.faces if f not in skip and f.calc_center_median().x > -0.001
           and degenerate(f, uvl)]
    bad_set = set(bad)
    done = []
    seen = set()
    for f in bad:
        if f in seen:
            continue
        patch, stack = [], [f]
        while stack:
            g = stack.pop()
            if g in seen:
                continue
            seen.add(g)
            patch.append(g)
            stack += [h for e in g.edges for h in e.link_faces if h in bad_set and h not in seen]
        ring = [h for g in patch for e in g.edges for h in e.link_faces
                if h not in bad_set and h.material_index == g.material_index]
        isl = {}
        for h in ring:
            c = centre_px(h, uvl)
            isl.setdefault((int(c.x // 40), int(c.y // 40)), []).append(h)
        anchors = max(isl.values(), key=len) if isl else []
        pins = pins_from(anchors, patch, uvl)
        if len(pins) < 2:
            print("UVFIX skip collapsed patch", [g.index for g in patch])
            continue
        lscm(patch, pins, uvl)
        done += patch
        print("UVFIX collapsed patch", [g.index for g in patch], "pins", len(pins))
    return done


def pull_in(faces, uvl, atlas):
    """Corners that reach off the painted island (or into its filtered rim) are drawn back inside it."""
    moved = []
    for f in faces:
        for _ in range(16):
            uvs = [lp[uvl].uv.copy() for lp in f.loops]
            if "empty" not in atlas.samples(uvs):
                break
            worst = max(f.loops, key=lambda lp: sum(atlas.kind(*(lp[uvl].uv.lerp(sum(uvs, Vector((0, 0))) / len(uvs), t)))
                                                     == "empty" for t in (0.0, 0.15, 0.3)))
            old = worst[uvl].uv.copy()
            c = sum((lp[uvl].uv for lp in f.loops if lp is not worst), Vector((0, 0))) / (len(uvs) - 1)
            new = old.lerp(c, 0.25)
            for lp in worst.vert.link_loops:
                if (lp[uvl].uv - old).length < 1e-6:
                    lp[uvl].uv = new
                    moved.append(lp.face)
    return list(set(moved))


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
    bm.normal_update()
    uvl = bm.loops.layers.uv.active
    atlas = Atlas()
    fixed = restore_shoulders(bm, uvl)
    fixed += lay_top(bm, uvl)
    fixed += relay_collapsed(bm, uvl, set(fixed))
    edge = [f for f in bm.faces if f.calc_center_median().x > -0.001 and f.calc_center_median().z < HEM_Z]
    pulled = pull_in(edge, uvl, atlas)
    print("UVFIX pulled in", len(pulled))
    print("UVFIX mirrored", mirror_uvs(bm, set(fixed + pulled), uvl), "faces onto -X")
    vol = sum(f.calc_center_median().dot(f.normal) * f.calc_area() for f in bm.faces) / 3
    print("UVFIX signed volume", round(vol, 5))
    bm.to_mesh(me)
    bm.free()
    me.update()
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
    print("UVFIX wrote", GLB)


main()
