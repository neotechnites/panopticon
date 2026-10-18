"""Neck rebuilt as a plain hex column, whole body mirrored +X onto -X, neck and shirt top re-UV'd at body density.

    blender -b characters/models/prisoner_joined.blend -P tools/modelling/characters/prisoner2_neck4.py -- --save characters/models/prisoner_joined.blend
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector, kdtree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "modelling", "lib"))
sys.path.insert(0, HERE)
import glb_textures  # noqa: E402
from prisoner2_face import bake_ao, multiply_materials  # noqa: E402

GLB = os.path.join(ROOT, "characters", "models", "prisoner2.glb")
TEX_URI = "../textures/prisoner2_albedo.png"
OLD_NECK = range(367, 415)
OPENING = {"bL": 240, "sL": 239, "fL": 244, "fR": 243, "sR": 242, "bR": 241}
LOOP_HALF = (74, 73, 72, 56, 360, 361, 362, 363)   # head underside, back centre to front centre on +X
TOP = set(range(231, 245)) | {26, 27, 28, 29}       # shirt top, shoulder ring up to the opening
SECTION = {"bc": (0.0, 0.054), "bL": (0.025, 0.054), "sL": (0.044, 0.002), "fL": (0.025, -0.054),
           "fc": (0.0, -0.054)}                      # hex section (x, y from centre), same on every ring
ORDER = ("bc", "bL", "sL", "fL", "fc", "fR", "sR", "bR")
C0, C2 = Vector((0.0, -0.1068, 0.0)), Vector((0.0, -0.174, 0.0))
Z2 = {"b": 1.460, "s": 1.454, "f": 1.448}         # top ring sits just under the head's underside
DENSITY = 0.376                                     # UV units per metre, the torso's
NECK_AT, SHIRT_AT = Vector((0.81, 0.80)), Vector((0.075, 0.46))   # spare right-sleeve skin; torso white


def section(key, centre):
    k = key if key in SECTION else key[0] + "L"
    x, y = SECTION[k]
    return centre.x + (x if key.endswith("L") or key[1] == "c" else -x), centre.y + y


def tri(bm, vs, out_from, tag_layer, tag, mat):
    n = (vs[1].co - vs[0].co).cross(vs[2].co - vs[0].co)
    c = sum((v.co for v in vs), Vector()) / 3
    if n.dot(c - out_from(c)) < 0:
        vs = [vs[0], vs[2], vs[1]]
    f = bm.faces.new(vs)
    f.material_index = mat
    f[tag_layer] = tag
    return f


def build_neck(bm, tag):
    bm.verts.ensure_lookup_table()
    dl = bm.verts.layers.deform.active
    v = bm.verts
    loop_half = [v[i] for i in LOOP_HALF]
    ring0 = {k: v[i] for k, i in OPENING.items()}
    for k in ("sL", "sR"):
        ring0[k].co.x, ring0[k].co.y = section(k, C0)
    head_g, neck_g, spine_g = (bpy.data.objects["Runner"].vertex_groups[n].index for n in ("Head", "Neck", "Spine"))
    for r in ring0.values():
        r[dl].clear()
        r[dl][spine_g], r[dl][neck_g] = 0.6, 0.4
    ring2 = {}
    for k in ORDER:
        x, y = section(k, C2)
        ring2[k] = bm.verts.new((x, y, Z2[k[0]]))
    ring1 = {}
    for k in ORDER:
        p0 = ring0[k].co if k in ring0 else (ring0[k[0] + "L"].co + ring0[k[0] + "R"].co) / 2
        ring1[k] = bm.verts.new((p0 + ring2[k].co) / 2)
    for r, w in ((ring1, {neck_g: 1.0}), (ring2, {neck_g: 0.5, head_g: 0.5})):
        for p in r.values():
            for g, x in w.items():
                p[dl][g] = x

    def axis(c):
        t = max(0.0, min(1.0, (c.z - 1.33) / 0.13))
        return Vector((0.0, C0.y + (C2.y - C0.y) * t, c.z))

    m1 = {ring1[a]: ring1[b] for a, b in (("bL", "bR"), ("sL", "sR"), ("fL", "fR"))}
    m1.update({b: a for a, b in list(m1.items())})
    m2 = {ring2[a]: ring2[b] for a, b in (("bL", "bR"), ("sL", "sR"), ("fL", "fR"))}
    m2.update({b: a for a, b in list(m2.items())})
    m0 = {ring0["bL"]: ring0["bR"], ring0["sL"]: ring0["sR"], ring0["fL"]: ring0["fR"]}
    m0.update({b: a for a, b in list(m0.items())})
    mirror_map = {**m0, **m1, **m2}

    def vs_m(x):
        return mirror_map.get(x, x)

    half = []
    r0, r1, r2 = ring0, ring1, ring2
    half += [(r0["bL"], r1["bL"], r1["bc"]), (r0["bL"], r1["bc"], r0["bR"])]
    half += [(r0["fL"], r1["fc"], r1["fL"]), (r0["fL"], r0["fR"], r1["fc"])]
    for a, b in (("bL", "sL"), ("sL", "fL")):
        half += [(r0[a], r0[b], r1[b]), (r0[a], r1[b], r1[a])]
    for a, b in (("bc", "bL"), ("bL", "sL"), ("sL", "fL"), ("fL", "fc")):
        half += [(r1[a], r1[b], r2[b]), (r1[a], r2[b], r2[a])]
    ra = [r2[k] for k in ORDER[:5]]
    i = j = 0
    while i < len(ra) - 1 or j < len(loop_half) - 1:
        adv_ring = j == len(loop_half) - 1 or (
            i < len(ra) - 1 and (ra[i + 1].co - loop_half[j].co).length < (ra[i].co - loop_half[j + 1].co).length)
        if adv_ring:
            half.append((ra[i], ra[i + 1], loop_half[j]))
            i += 1
        else:
            half.append((ra[i], loop_half[j + 1], loop_half[j]))
            j += 1
    loop_m = {}
    bm.verts.index_update()
    kd = kdtree.KDTree(len(bm.verts))
    for p in bm.verts:
        kd.insert(p.co, p.index)
    kd.balance()
    bm.verts.ensure_lookup_table()
    for p in loop_half:
        co = p.co.copy()
        co.x = -co.x
        loop_m[p] = bm.verts[kd.find(co)[1]]
    mirror_map.update(loop_m)
    faces = set()
    for t in half:
        faces.add(tuple(t))
        mt = tuple(vs_m(x) for x in t)
        if set(mt) != set(t):
            faces.add(mt)
    for t in faces:
        tri(bm, list(t), axis, tag, 1, 0)


def symmetrize(bm, ob):
    bmesh.ops.symmetrize(bm, input=bm.verts[:] + bm.edges[:] + bm.faces[:], direction="X", dist=0.0015)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3],
                          quad_method="BEAUTY", ngon_method="BEAUTY")
    dl = bm.verts.layers.deform.active
    names = {g.index: g.name for g in ob.vertex_groups}
    idx = {g.name: g.index for g in ob.vertex_groups}

    def other(n):
        return n[:-2] + (".R" if n.endswith(".L") else ".L")

    for v in bm.verts:
        d = v[dl]
        lr = {g: w for g, w in d.items() if names[g][-2:] in (".L", ".R")}
        if not lr:
            continue
        if v.co.x < -1e-5:
            new = {idx[other(names[g])]: w for g, w in lr.items()}
        elif abs(v.co.x) <= 1e-5:
            new = {}
            for g, w in lr.items():
                for n in (names[g], other(names[g])):
                    new[idx[n]] = new.get(idx[n], 0.0) + w / 2
        else:
            continue
        for g in lr:
            del d[g]
        for g, w in new.items():
            d[g] = w


def mirror_partner(bm):
    bm.verts.index_update()
    kd = kdtree.KDTree(len(bm.verts))
    for v in bm.verts:
        kd.insert(v.co, v.index)
    kd.balance()
    bm.verts.ensure_lookup_table()
    out = {}
    for v in bm.verts:
        co = v.co.copy()
        co.x = -co.x
        co2, i, d = kd.find(co)
        if d < 1e-4:
            out[v] = bm.verts[i]
    return out


def place_island(faces, uvl, up, at):
    """Rotate the island so +up maps to +v, scale it to DENSITY, centre it on at."""
    g = Vector((0.0, 0.0))
    a3 = a2 = 0.0
    for f in faces:
        ls = f.loops
        u = [l[uvl].uv.copy() for l in ls]
        s = [up(l.vert.co) for l in ls]
        e1, e2 = u[1] - u[0], u[2] - u[0]
        det = e1.x * e2.y - e1.y * e2.x
        if abs(det) < 1e-12:
            continue
        ds1, ds2 = s[1] - s[0], s[2] - s[0]
        g += Vector(((ds1 * e2.y - ds2 * e1.y) / det, (ds2 * e1.x - ds1 * e2.x) / det)) * abs(det) / 2
        a2 += abs(det) / 2
        a3 += f.calc_area()
    ang = math.pi / 2 - math.atan2(g.y, g.x)
    k = math.sqrt(a3 / a2) * DENSITY
    ca, sa = math.cos(ang) * k, math.sin(ang) * k
    pts = [l[uvl] for f in faces for l in f.loops]
    for p in pts:
        x, y = p.uv
        p.uv = (ca * x - sa * y, sa * x + ca * y)
    lo = Vector((min(p.uv.x for p in pts), min(p.uv.y for p in pts)))
    hi = Vector((max(p.uv.x for p in pts), max(p.uv.y for p in pts)))
    off = at - (lo + hi) / 2
    for p in pts:
        p.uv += off


def reuv(ob):
    me = ob.data
    bpy.context.view_layer.objects.active = ob
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(me)
    bm.select_mode = {"FACE"}
    tag = bm.faces.layers.int["tag"]
    for f in bm.faces:
        f.select_set(False)
    for f in bm.faces:
        if f[tag] in (1, 2) and f.calc_center_median().x > 0:
            f.select_set(True)
    bmesh.update_edit_mesh(me)
    bpy.ops.uv.unwrap(method="CONFORMAL", margin=0.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    bm = bmesh.new()
    bm.from_mesh(me)
    tag = bm.faces.layers.int["tag"]
    uvl = bm.loops.layers.uv.active
    pos = {t: [f for f in bm.faces if f[tag] == t and f.calc_center_median().x > 0] for t in (1, 2)}
    place_island(pos[1], uvl, lambda c: c.z, NECK_AT)
    place_island(pos[2], uvl, lambda c: c.y, SHIRT_AT)
    mp = mirror_partner(bm)
    by_verts = {frozenset(f.verts): f for t in (1, 2) for f in pos[t]}
    for f in bm.faces:
        if f[tag] in (1, 2) and f.calc_center_median().x < 0:
            src = by_verts[frozenset(mp[v] for v in f.verts)]
            uv = {l.vert: l[uvl].uv.copy() for l in src.loops}
            for l in f.loops:
                l[uvl].uv = uv[mp[l.vert]]
    for f in bm.faces:
        f.select_set(False)
    bm.to_mesh(me)
    bm.free()


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
    tag = bm.faces.layers.int.new("tag")
    for f in bm.faces:
        if all(v.index in TOP for v in f.verts):   # incl. two skin faces left on the front scoop
            f.material_index = 1
            f[tag] = 2
        elif f.material_index == 1 and all(v.co.y < -0.165 and v.co.z > 1.26 and abs(v.co.x) < 0.07 for v in f.verts):
            f[tag] = 2                               # front strip under the scoop sat on the old collar's skin bar
    old = [bm.verts[i] for i in OLD_NECK]
    build_neck(bm, tag)
    bmesh.ops.delete(bm, geom=old, context="VERTS")
    symmetrize(bm, ob)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.update()
    reuv(ob)
    me.attributes.remove(me.attributes["tag"])
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
    print("NECK4 wrote", GLB)


main()
