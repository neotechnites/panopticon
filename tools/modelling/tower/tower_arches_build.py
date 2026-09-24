"""tower_arches -- Ryan's tower with eight even Greek arches instead of his
rough windows.

Same source mesh, same clean-up, same crown and same column as tower_build.py.
His eight rough openings are FILLED back to solid wall (a Coons patch per
window, sampled off his own skin at the hole's rim, unioned in), then eight
identical round-headed arches are cut with one boolean: straight jambs, a true
semicircular head, planar reveals splayed 10 deg, a uniform sill all round.
Two plain string courses (sill line, springing line) and a keystone per arch
make it read as dressed stone. Everything above the arch heads and below the
sill band is his rock.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import mdl  # noqa: E402

mdl.DEFAULTS["ground"] = False
mdl.DEFAULTS["world_grey"] = 0.30
mdl.DEFAULTS["world_strength"] = 0.90

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "tower_arches"
OBJECT_NAME = "TowerRock"
COLLIDER_NAME = "TowerCollision-colonly"
BLEND_PATH = r"C:\dev\panopticon\tower\models\tower_new.blend"

WELD       = 0.02
DEGEN      = 1.0e-4
DISSOLVE   = 3.0
DISSOLVE_Z = -2.60
FLAP_PASSES = 8
SLIVER     = math.radians(3.0)   # a triangle thinner than this is re-cut
NEEDLE     = 0.03      # metres: the longest edge a needle merge may close

NSUB       = 32        # collider ring resolution
NBEAR      = 288       # bearings sampled when finding his windows
EYE_H      = 1.65
BODY_H     = 1.80

SILL_ABOVE = 0.65      # sill line above the room floor; Ryan: half height, jumping out is allowed
CROWN_Z    = 7.00      # top of the arch head (his ceiling is 7.25)
SPLAY      = 10.0      # reveal splay per side, widening outward
HEAD_SEG   = 12        # segments in the semicircular head
BAND_H     = 0.25      # string course height
BAND_PROUD = 0.08
BAND_SEG   = 48
KEY_W      = 0.80      # keystone
KEY_H      = 0.33
KEY_PROUD  = 0.15

PLUG_NB    = 8         # Coons patch grid across a filled window
PLUG_NZ    = 7
PLUG_EPS   = 0.02      # patch stands this far proud where his wall is a hole
PLUG_BURY  = 0.06      # ...and sits this far under it where his wall is there
PLUG_DB    = 1.5       # patch margin into the pier, degrees
PLUG_DZ    = 0.20      # patch margin above/below his opening

ZONE_ROCK  = (0.0, 0.5, 0.5, 1.0)
UV_SCALE = 0.13
UV_PAD = 1.5 / 128.0

FLECK_LUM = 0.001      # an atlas texel this bright in his emissive map is lava.
                       # His unlit cell is a hard zero, the fleck 0.0026 linear
                       # (0.025 if pixels[] ever hands back sRGB) -- clear of both
FLECK_M2PT = 0.05      # ...and magnification is what makes one read as a wedge:
                       # square metres of floor per atlas texel. The two facets
                       # the dissolve fans out run 0.88 and 0.146; every floor
                       # facet still carrying his own mapping is 0.012 or less
FLECK_FIT = (1.0, 0.98, 0.96, 0.94)   # uniform UV shrinks to try when no plain
                       # slide fits between his flecks -- one facet is three
                       # texels too tall for the gap and fits once it gives 2%
FLECK_MAX = 4          # more blown-up floor facets than this and the floor
                       # itself is wrong, not its UV: warn and touch nothing
FLECK_GUARD = 1        # texels of bilinear headroom to leave around a facet
FLECK_Z = 0.15         # his floor sags: how far a facet's centre may sit below
                       # MEAS["floor"] and still be floor (measured 1.593..1.702)

TAU = 2.0 * math.pi
SEED = 20260913

MEAS = {"floor": 1.70, "ceil": 7.25, "r_in": 6.9, "open": 0.0}


# =============================================================================
# HELPERS
# =============================================================================

class _Rng(object):
    """Deterministic LCG so the rock is byte-identical every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def f(self):
        return self.n() / float(0x7FFFFFFF)

    def i(self, a, b):
        return a + (self.n() >> 12) % (b - a + 1)


def _newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n.x += (a[1] - b[1]) * (a[2] + b[2])
        n.y += (a[2] - b[2]) * (a[0] + b[0])
        n.z += (a[0] - b[0]) * (a[1] + b[1])
    return n


def _components(edges):
    rem, out = set(edges), []
    while rem:
        e0 = rem.pop()
        comp, stack = {e0}, [e0]
        while stack:
            e = stack.pop()
            for v in e.verts:
                for e2 in list(v.link_edges):
                    if e2 in rem:
                        rem.discard(e2)
                        comp.add(e2)
                        stack.append(e2)
        out.append(comp)
    return out


def _describe(comp):
    vs = set(v for e in comp for v in e.verts)
    cs = [v.co for v in vs]
    cx = sum(c.x for c in cs) / len(cs)
    cy = sum(c.y for c in cs) / len(cs)
    return ("bearing=%3.0fdeg r=%.2f z=%.2f..%.2f edges=%d"
            % (math.degrees(math.atan2(cy, cx)) % 360.0, math.hypot(cx, cy),
               min(c.z for c in cs), max(c.z for c in cs), len(comp)))


def _tris(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def _solid(name, verts, faces):
    """A closed cutter/plug: no material, no UVs, normals recalculated out."""
    ob = mdl.mesh(name, verts, faces)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1.0e-5)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return ob


def _volume(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    v = bm.calc_volume(signed=True)
    bm.free()
    return v


def _boolean(ob, cutter, op):
    """Cut or weld, plainly first.

    The tolerant flags rescue a cut that re-opens the room cavity, but they
    also shred near-contact surfaces into thousands of slivers, so the plain
    solver is tried first and the mesh is rolled back if it comes out wrong.
    """
    keep = ob.data.copy()
    v0, n0 = _volume(ob), _tris(ob)
    # self-intersection alone before hole-tolerant: tolerance is what shreds
    for tol in ((False, False), (True, False), (True, True)):
        mod = ob.modifiers.new("bool", "BOOLEAN")
        mod.object = cutter
        mod.operation = op
        mod.solver = "EXACT"
        for flag, on in zip(("use_self", "use_hole_tolerant"), tol):
            try:
                setattr(mod, flag, on)
            except Exception:
                pass
        for o in bpy.context.selected_objects:
            o.select_set(False)
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        ob.data.update()
        v1, n1 = _volume(ob), _tris(ob)
        good = (n1 > 0.5 * n0 and v1 > 0.5 * v0
                and (v1 >= 0.98 * v0 if op == "UNION" else v1 <= 1.02 * v0))
        if good:
            break
        print("MDL WARN %s came back wrong (tris %d->%d volume %.0f->%.0f) with "
              "self=%s tolerant=%s; retrying" % (op, n0, n1, v0, v1, tol[0], tol[1]))
        old = ob.data
        ob.data = keep.copy()
        bpy.data.meshes.remove(old)
    bpy.data.meshes.remove(keep)
    bpy.data.objects.remove(cutter, do_unlink=True)
    ob.data.update()


# =============================================================================
# HIS BODY
# =============================================================================

def _append_rock():
    with bpy.data.libraries.load(BLEND_PATH, link=False) as (src, dst):
        names = [n for n in src.objects if n == OBJECT_NAME]
        if not names:
            raise SystemExit("MDL ERROR: %s has no object %r (has %s)"
                             % (BLEND_PATH, OBJECT_NAME, list(src.objects)))
        dst.objects = names
    ob = dst.objects[0]
    bpy.context.collection.objects.link(ob)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mat = ob.data.materials[0] if ob.data.materials else None
    if mat is None:
        raise SystemExit("MDL ERROR: %s carries no material" % OBJECT_NAME)
    imgs = []
    if mat.use_nodes:
        for nd in mat.node_tree.nodes:
            if nd.type == "TEX_IMAGE" and nd.image:
                if not nd.image.packed_file:
                    nd.image.pack()
                imgs.append("%s %dx%d" % (nd.image.name, nd.image.size[0],
                                          nd.image.size[1]))
    uvname = ob.data.uv_layers[0].name if ob.data.uv_layers else "UVMap"
    zs = [v.co.z for v in ob.data.vertices]
    print("MDL STATS his verts=%d tris=%d z=%.2f..%.2f mat=%s uv=%s tex=[%s]"
          % (len(ob.data.vertices), _tris(ob), min(zs), max(zs), mat.name,
             uvname, ", ".join(imgs)))
    return ob, mat, uvname


# =============================================================================
# 1  REPAIR -- doubles, flaps, cracks, normals   (as tower_build.py)
# =============================================================================

def _cut_flaps(bm):
    cut = []
    for _ in range(FLAP_PASSES):
        bad = set()
        for comp in _components([e for e in bm.edges if e.is_boundary]):
            vs = set(v for e in comp for v in e.verts)
            faces = set(f for e in comp for f in e.link_faces)
            over = any(len(e.link_faces) > 2 for f in faces for e in f.edges)
            if len(comp) == len(vs) and not over:
                continue
            for f in faces:
                nb = sum(1 for e in f.edges if e.is_boundary)
                if nb >= 2 or (nb >= 1
                               and any(len(e.link_faces) > 2 for e in f.edges)):
                    bad.add(f)
        if not bad:
            break
        for f in bad:
            cut.append((f.calc_center_median().copy(), f.calc_area()))
        bmesh.ops.delete(bm, geom=list(bad), context="FACES")
    return cut


def _repair(bm):
    rep = {}
    n0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=WELD)
    rep["welded"] = n0 - len(bm.verts)

    n0 = len(bm.edges)
    bmesh.ops.dissolve_degenerate(bm, dist=DEGEN, edges=list(bm.edges))
    rep["degenerate_edges"] = n0 - len(bm.edges)

    thin = [f for f in bm.faces if f.calc_area() < 1.0e-7]
    if thin:
        bmesh.ops.delete(bm, geom=thin, context="FACES")
    rep["zero_area_faces"] = len(thin)

    rep["flaps"] = _cut_flaps(bm)

    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    rep["loose_verts"] = len(loose)

    rep["filled"] = []
    for _ in range(3):
        comps = _components([e for e in bm.edges if e.is_boundary])
        if not comps:
            break
        for comp in comps:
            rep["filled"].append(_describe(comp))
            bmesh.ops.holes_fill(bm, edges=list(comp), sides=0)

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    vol = bm.calc_volume(signed=True)
    rep["reversed"] = vol < 0.0
    if rep["reversed"]:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        bm.normal_update()
        vol = -vol
    rep["volume"] = vol
    rep["open_edges"] = len([e for e in bm.edges if e.is_boundary])
    rep["non_manifold"] = len([e for e in bm.edges if not e.is_manifold])
    return rep


def _polish(bm):
    verts = [v for v in bm.verts if v.co.z > DISSOLVE_Z]
    edges = [e for e in bm.edges if all(v.co.z > DISSOLVE_Z for v in e.verts)]
    n0 = len(bm.verts)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(DISSOLVE),
                             verts=verts, edges=edges)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    return n0 - len(bm.verts)


def _shells(faces):
    seen, out = set(), []
    for f0 in faces:
        if f0 in seen:
            continue
        shell, stack = [], [f0]
        seen.add(f0)
        while stack:
            f = stack.pop()
            shell.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g not in seen:
                        seen.add(g)
                        stack.append(g)
        out.append(shell)
    return out


def _mend(bm):
    """Boolean fins: the faces on a non-manifold edge go, with any small sheet
    they held on, and the shell's holes are filled."""
    n0 = len(bm.faces)
    for _ in range(4):
        nm = [e for e in bm.edges if len(e.link_faces) > 2]
        if not nm:
            break
        dead = list({f for e in nm for f in e.link_faces})
        touched = {v for f in dead for v in f.verts}
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        shells = _shells(list(bm.faces))
        big = max(len(sh) for sh in shells)
        junk = [f for sh in shells if len(sh) < 0.1 * big
                and any(v in touched for f in sh for v in f.verts) for f in sh]
        if junk:
            bmesh.ops.delete(bm, geom=junk, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
        for comp in _components([e for e in bm.edges if e.is_boundary]):
            bmesh.ops.holes_fill(bm, edges=list(comp), sides=0)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    return n0 - len(bm.faces)


def _min_ang(f):
    return min(lp.calc_angle() for lp in f.loops)


def _tri_ang(p, q, r):
    return min((b - a).angle(c - a, 0.0) for a, b, c in ((p, q, r), (q, r, p), (r, p, q)))


def _flip_cap(bm, f, uv):
    """A cap on a flat patch: turn its long edge. Flat pairs only, so no shape moves."""
    lv = max(f.loops, key=lambda lp: lp.calc_angle())
    if lv.calc_angle() < math.radians(150.0):
        return False
    e, v = lv.link_loop_next.edge, lv.vert
    if len(e.link_faces) != 2:
        return False
    g = [x for x in e.link_faces if x is not f][0]
    if len(g.verts) != 3:
        return False
    d = [x for x in g.verts if x not in e.verts][0]
    if any(x.other_vert(v) is d for x in v.link_edges):
        return False
    f.normal_update()
    g.normal_update()
    if f.normal.angle(g.normal, math.pi) > math.radians(2.0):
        return False
    a, b = e.verts
    if (a.co - v.co).cross(d.co - v.co).dot((d.co - v.co).cross(b.co - v.co)) <= 0.0:
        return False
    old = min(_min_ang(f), _min_ang(g))
    if min(_tri_ang(v.co, a.co, d.co), _tri_ang(v.co, d.co, b.co)) <= old:
        return False
    ne = bmesh.ops.rotate_edges(bm, edges=[e], use_ccw=False)["edges"]
    for h in (ne[0].link_faces if ne else ()):
        for lp in h.loops:                # re-projected by unwrap, like a boolean face
            lp[uv].uv = (0.0, 0.0)
    return bool(ne)


def _collapse_needle(bm, f, needle):
    """A needle (one edge a tenth of the rest, under `needle` m): merge it at its midpoint."""
    es = sorted(f.edges, key=lambda e: e.calc_length())
    e = es[0]
    if e.calc_length() > min(needle, 0.1 * es[-1].calc_length()) or len(e.link_faces) != 2:
        return False
    a, b = e.verts
    common = ({x.other_vert(a) for x in a.link_edges}
              & {x.other_vert(b) for x in b.link_edges})
    opp = {x for g in e.link_faces for x in g.verts if x not in e.verts}
    if common != opp:
        return False                      # would pinch the surface into a fin
    mid = (a.co + b.co) * 0.5
    for g in set(a.link_faces) | set(b.link_faces):
        if a in g.verts and b in g.verts:
            continue
        g.normal_update()
        pts = [mid if x in (a, b) else x.co for x in g.verts]
        nn = (pts[1] - pts[0]).cross(pts[2] - pts[0])
        if nn.length < 1e-9 or nn.normalized().dot(g.normal) < 0.8:
            return False                  # a neighbour would fold over
    bmesh.ops.pointmerge(bm, verts=[a, b], merge_co=mid)
    return True


def _slivers(bm, needle=NEEDLE):
    """Re-cut the triangles under SLIVER degrees the booleans left: flip caps, merge needles."""
    uv = bm.loops.layers.uv.active or bm.loops.layers.uv.new()
    fixed = 0
    for _ in range(6):
        n0 = fixed
        for f in [f for f in bm.faces if _min_ang(f) < SLIVER]:
            if not f.is_valid or len(f.verts) != 3 or _min_ang(f) >= SLIVER:
                continue
            if _flip_cap(bm, f, uv) or _collapse_needle(bm, f, needle):
                fixed += 1
        if fixed == n0:
            break
    bmesh.ops.dissolve_degenerate(bm, dist=1.0e-6, edges=list(bm.edges))
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.normal_update()
    return fixed


# =============================================================================
# 2  MEASURE -- his room and his eight rough windows
# =============================================================================

class Probe(object):
    """Rays in and out of the drum, on whatever the rock is right now."""

    def __init__(self, ob):
        self.bvh = BVHTree.FromPolygons(
            [v.co.copy() for v in ob.data.vertices],
            [list(p.vertices) for p in ob.data.polygons],
            all_triangles=False, epsilon=0.0)

    def down(self, x, y, z):
        hit = self.bvh.ray_cast(Vector((x, y, z)), Vector((0, 0, -1)), 80.0)
        return hit[0].z if hit[0] else None

    def up(self, x, y, z):
        hit = self.bvh.ray_cast(Vector((x, y, z)), Vector((0, 0, 1)), 60.0)
        return hit[0].z if hit[0] else None

    def inner(self, b, z, lim=13.0):
        """Radius of the inner skin at this bearing, or None through a hole."""
        d = Vector((math.cos(b), math.sin(b), 0.0))
        hit = self.bvh.ray_cast(Vector((0, 0, z)), d, lim)
        if not hit[0]:
            return None
        r = hit[0].x * d.x + hit[0].y * d.y
        return r if r < lim else None

    def outer(self, b, z, r0=22.0):
        """Radius of the outer skin, cast from outside inward."""
        d = Vector((math.cos(b), math.sin(b), 0.0))
        hit = self.bvh.ray_cast(Vector((r0 * d.x, r0 * d.y, z)), -d, 2.0 * r0)
        if not hit[0]:
            return None
        r = hit[0].x * d.x + hit[0].y * d.y
        return r if 3.0 < r < 14.0 else None

    def skin(self, b, z):
        """(r_in, r_out) where the wall is solid, else None."""
        ri = self.inner(b, z)
        ro = self.outer(b, z)
        if ri is None or ro is None or ro < ri + 0.05:
            return None
        return (ri, ro)


def _measure(ob):
    p = Probe(ob)
    bear = [TAU * i / NSUB for i in range(NSUB)]

    ceil_z = None
    for z in (2.0, 3.0, 4.0):
        ceil_z = p.up(0.0, 0.0, z)
        if ceil_z:
            break
    ceil_z = ceil_z or 7.25

    r_ring = []
    for a in bear:
        best = None
        for z in (ceil_z - 0.30, ceil_z - 0.50):
            rr = p.inner(a, z)
            if rr and (best is None or rr < best):
                best = rr
        r_ring.append(best if best else 7.0)
    r_in = min(r_ring)

    f_ring = []
    for a in bear:
        rr = r_in * 0.94
        z = p.down(rr * math.cos(a), rr * math.sin(a), ceil_z - 0.30)
        f_ring.append(z if z is not None else 1.70)
    f_axis = p.down(0.0, 0.0, ceil_z - 0.30) or min(f_ring)
    floor = max(f_ring)

    # Where his wall is open: a grid of bearings by height, stopping short of
    # the ceiling -- above it a ray from the axis hits the outer skin first and
    # every bearing would read as a window.
    zs, z = [], floor + 0.30
    while z < ceil_z - 0.10:
        zs.append(z)
        z += 0.10
    grid = []
    for i in range(NBEAR):
        a = TAU * i / NBEAR
        grid.append([p.skin(a, z) is None for z in zs])

    any_open = [any(col) for col in grid]
    if not any(any_open) or all(any_open):
        raise SystemExit("MDL ERROR: his eight windows were not found")
    k = 0
    while any_open[k]:
        k += 1
    wins, start = [], None
    for n in range(NBEAR + 1):
        i = (k + n) % NBEAR
        if any_open[i] and start is None:
            start = n
        elif not any_open[i] and start is not None:
            idx = [(k + m) % NBEAR for m in range(start, n)]
            zo = [zs[j] for i2 in idx for j, o in enumerate(grid[i2]) if o]
            wins.append({"b0": TAU * idx[0] / NBEAR,
                         "b1": TAU * idx[-1] / NBEAR,
                         "bc": TAU * (idx[0] + 0.5 * (len(idx) - 1)) / NBEAR,
                         "span": TAU * len(idx) / NBEAR,
                         "z0": min(zo), "z1": max(zo), "idx": idx})
            start = None

    # his opening width, measured where his windows are at full width
    mid = 0.5 * (min(w["z0"] for w in wins) + max(w["z1"] for w in wins))
    spans, router = [], []
    for w in wins:
        for z in (mid - 0.5, mid, mid + 0.5):
            n = sum(1 for i in w["idx"] if p.skin(TAU * i / NBEAR, z) is None)
            if n:
                spans.append(TAU * n / NBEAR)
    for z in (mid - 1.5, mid, mid + 1.5, mid + 2.5):
        for i in range(NBEAR):
            s = p.skin(TAU * i / NBEAR, z)
            if s:
                router.append(s[1])
    span_mean = sum(spans) / len(spans)
    r_face = sum(router) / len(router)
    width = 2.0 * r_face * math.sin(0.5 * span_mean)

    MEAS.update({"floor": floor, "ceil": ceil_z, "r_in": r_in, "r_ring": r_ring,
                 "f_ring": f_ring, "f_axis": f_axis, "bear": bear,
                 "wins": wins, "r_face": r_face, "width": width,
                 "span_mean": span_mean, "probe": p})
    print("MDL STATS room floor=%.3f..%.3f axis=%.3f ceil=%.3f r_in=%.2f "
          "r_out=%.2f windows=%d" % (min(f_ring), max(f_ring), f_axis, ceil_z,
                                     r_in, r_face, len(wins)))
    for i, w in enumerate(wins):
        print("MDL STATS   his win%d bearing=%.0f..%.0fdeg span=%.1fdeg "
              "z=%.2f..%.2f" % (i, math.degrees(w["b0"]) % 360.0,
                                math.degrees(w["b1"]) % 360.0,
                                math.degrees(w["span"]), w["z0"], w["z1"]))
    print("MDL STATS his mean opening span=%.1fdeg width=%.2fm at r=%.2f"
          % (math.degrees(span_mean), width, r_face))
    return MEAS


# =============================================================================
# 3  FILL -- a Coons patch per window, unioned back into the drum
# =============================================================================

def _edge_sample(p, b, z, db, dz, tries=14):
    """His skin at (b, z); if that is a hole, walk out until it is not."""
    for k in range(tries):
        s = p.skin(b + k * db, z + k * dz)
        if s:
            return s
    return None


def _patch(p, w):
    """Coons interpolation of (r_in, r_out) across one filled window."""
    b0 = w["b0"] - math.radians(PLUG_DB)
    b1 = w["b1"] + math.radians(PLUG_DB)
    z0, z1 = w["z0"] - PLUG_DZ, w["z1"] + PLUG_DZ
    us = [i / float(PLUG_NB - 1) for i in range(PLUG_NB)]
    vs = [i / float(PLUG_NZ - 1) for i in range(PLUG_NZ)]
    bb = [b0 + (b1 - b0) * u for u in us]
    zz = [z0 + (z1 - z0) * v for v in vs]

    fallback = (MEAS["r_in"], MEAS["r_face"])
    bot = [_edge_sample(p, b, z0, 0.0, -0.06) or fallback for b in bb]
    top = [_edge_sample(p, b, z1, 0.0, 0.06) or fallback for b in bb]
    lef = [_edge_sample(p, b0, z, -0.004, 0.0) or fallback for z in zz]
    rig = [_edge_sample(p, b1, z, 0.004, 0.0) or fallback for z in zz]
    c00, c10 = lef[0], rig[0]
    c01, c11 = lef[-1], rig[-1]

    out = []
    for j, v in enumerate(vs):
        row = []
        for i, u in enumerate(us):
            vals = []
            for k in (0, 1):
                s = ((1 - v) * bot[i][k] + v * top[i][k]
                     + (1 - u) * lef[j][k] + u * rig[j][k]
                     - ((1 - u) * (1 - v) * c00[k] + u * (1 - v) * c10[k]
                        + (1 - u) * v * c01[k] + u * v * c11[k]))
                vals.append(s)
            # Where his wall is really there the patch is buried under it: two
            # near-coplanar skins would shred the boolean into slivers.
            here = p.skin(bb[i], zz[j])
            if here:
                b = min(PLUG_BURY, 0.5 * (here[1] - here[0]) - 0.03)
                vals = [here[0] + b, here[1] - b]
            else:
                vals = [vals[0] - PLUG_EPS, vals[1] + PLUG_EPS]
            row.append((bb[i], zz[j], vals[0], vals[1]))
        out.append(row)
    return out


def _plugs(m):
    """One closed solid per window, its skin matching his at the rim."""
    verts, faces = [], []

    def grid(rows, outer):
        base = len(verts)
        for row in rows:
            for (b, z, ri, ro) in row:
                r = ro if outer else ri
                verts.append((r * math.cos(b), r * math.sin(b), z))
        return base

    for w in m["wins"]:
        rows = _patch(m["probe"], w)
        a = grid(rows, True)
        c = grid(rows, False)
        nb, nz = PLUG_NB, PLUG_NZ

        def oi(j, i):
            return a + j * nb + i

        def ii(j, i):
            return c + j * nb + i

        for j in range(nz - 1):
            for i in range(nb - 1):
                faces.append((oi(j, i), oi(j, i + 1), oi(j + 1, i + 1),
                              oi(j + 1, i)))
                faces.append((ii(j, i), ii(j + 1, i), ii(j + 1, i + 1),
                              ii(j, i + 1)))
        for i in range(nb - 1):
            faces.append((oi(0, i), oi(0, i + 1), ii(0, i + 1), ii(0, i)))
            faces.append((oi(nz - 1, i), ii(nz - 1, i), ii(nz - 1, i + 1),
                          oi(nz - 1, i + 1)))
        for j in range(nz - 1):
            faces.append((oi(j, 0), ii(j, 0), ii(j + 1, 0), oi(j + 1, 0)))
            faces.append((oi(j, nb - 1), oi(j + 1, nb - 1), ii(j + 1, nb - 1),
                          ii(j, nb - 1)))
    return _solid("Plugs", verts, faces)


# =============================================================================
# 4  ARCHES -- one cutter, eight identical round-headed openings
# =============================================================================

def _bearings(m):
    """His eight window centres, evened onto one 45deg grid.

    The piers have to come out identical, and his centres wander by up to
    1.7deg; the grid is the circular mean of his own phase, so every arch
    still sits in his opening.
    """
    n = len(m["wins"])
    step = TAU / n
    sx = sum(math.cos(n * w["bc"]) for w in m["wins"])
    sy = sum(math.sin(n * w["bc"]) for w in m["wins"])
    phase = (math.atan2(sy, sx) / n) % step
    bear = [phase + step * k for k in range(n)]
    off = [min(abs(((b - w["bc"] + math.pi) % TAU) - math.pi) for b in bear)
           for w in m["wins"]]
    return bear, math.degrees(max(off))


def _arch_plan(m):
    """Every number the arch, the bands and the collider are built from."""
    width = m["width"]
    hw = 0.5 * width
    bear, drift = _bearings(m)
    plan = {"width": width, "hw": hw, "sill": m["floor"] + SILL_ABOVE,
            "crown": CROWN_Z, "spring": CROWN_Z - hw, "r_face": m["r_face"],
            "tan": math.tan(math.radians(SPLAY)),
            "bear": bear, "drift": drift}
    plan["jamb"] = plan["spring"] - plan["sill"]
    plan["hw_in"] = hw + (m["r_in"] - m["r_face"]) * plan["tan"]
    plan["half_in"] = math.asin(min(0.999, plan["hw_in"] / m["r_in"]))
    return plan


def _profile(plan, y):
    """The arch section at radial offset y: jambs, then a semicircular head."""
    hw = plan["hw"] + (y - plan["r_face"]) * plan["tan"]
    s = hw / plan["hw"]
    pts = [(hw, plan["sill"])]
    for k in range(HEAD_SEG + 1):
        t = math.pi * k / HEAD_SEG
        pts.append((s * plan["hw"] * math.cos(t),
                    plan["spring"] + plan["hw"] * math.sin(t)))
    pts.append((-hw, plan["sill"]))
    return pts


def _arches(m, plan):
    verts, faces = [], []
    y0, y1 = m["r_in"] - 1.20, m["r_face"] + 1.60
    for b in plan["bear"]:
        er = (math.cos(b), math.sin(b))
        et = (-math.sin(b), math.cos(b))
        base = len(verts)
        rings = []
        for y in (y0, y1):
            ring = []
            for (x, z) in _profile(plan, y):
                ring.append((er[0] * y + et[0] * x, er[1] * y + et[1] * x, z))
            rings.append(ring)
        n = len(rings[0])
        for ring in rings:
            verts.extend(ring)
        for i in range(n):
            j = (i + 1) % n
            faces.append((base + i, base + j, base + n + j, base + n + i))
        faces.append(tuple(range(base, base + n)))
        faces.append(tuple(reversed(range(base + n, base + 2 * n))))
    return _solid("Arches", verts, faces)


# =============================================================================
# 5  STRING COURSES and KEYSTONES
# =============================================================================

def _ring_radii(p, z0, z1, n):
    """Per-bearing (buried inner start, proud outer) for a string course.

    His skin is rough, so the band rides it rather than being a true circle:
    a max over half a segment either way keeps every segment standing proud
    instead of sinking into a facet.
    """
    zs = [z0 + (z1 - z0) * k / 4.0 for k in range(5)]
    si, so = [], []
    for i in range(2 * n):
        b = TAU * i / (2 * n)
        hits = [s for s in (p.skin(b, z) for z in zs) if s]
        si.append(max(h[0] for h in hits) if hits else MEAS["r_in"])
        so.append(max(h[1] for h in hits) if hits else MEAS["r_face"])
    ri, ro = [], []
    for i in range(n):
        k = 2 * i
        w = [(k + d) % (2 * n) for d in (-1, 0, 1)]
        ro.append(max(so[j] for j in w) + BAND_PROUD)
        ri.append(max(si[j] for j in w) + 0.04)
    ri = [min(ri[i], ro[i] - 0.10, MEAS["r_in"] + 0.40) for i in range(n)]
    return ri, ro


def _band(p, z_top, n=BAND_SEG):
    z0, z1 = z_top - BAND_H, z_top
    ri, ro = _ring_radii(p, z0, z1, n)
    verts, faces = [], []
    for i in range(n):
        b = TAU * i / n
        cb, sb = math.cos(b), math.sin(b)
        for r in (ri[i], ro[i]):
            for z in (z0, z1):
                verts.append((r * cb, r * sb, z))
    for i in range(n):
        j = (i + 1) % n
        a = 4 * i
        c = 4 * j
        faces.append((a + 2, a + 3, c + 3, c + 2))          # outer
        faces.append((a + 1, a + 0, c + 0, c + 1))          # inner
        faces.append((a + 1, c + 1, c + 3, a + 3))          # top
        faces.append((a + 0, a + 2, c + 2, c + 0))          # bottom
    return verts, faces


def _bands(m, plan):
    p = m["probe"]
    verts, faces = [], []
    for z_top in (plan["sill"], plan["spring"]):
        v, f = _band(p, z_top)
        base = len(verts)
        verts.extend(v)
        faces.extend([tuple(base + k for k in q) for q in f])
    return _solid("Bands", verts, faces)


def _keystones(m, plan):
    p = m["probe"]
    verts, faces = [], []
    z0, z1 = plan["crown"], plan["crown"] + KEY_H
    for b in plan["bear"]:
        hits = [s for s in (p.skin(b + t, z)
                            for t in (-0.05, 0.0, 0.05)
                            for z in (z0 + 0.02, z0 + 0.15)) if s]
        if not hits:
            continue
        y0 = min(h[0] for h in hits) - 0.10
        y1 = max(h[1] for h in hits) + KEY_PROUD
        er = (math.cos(b), math.sin(b))
        et = (-math.sin(b), math.cos(b))
        base = len(verts)
        for y in (y0, y1):
            for x in (-0.5 * KEY_W, 0.5 * KEY_W):
                for z in (z0, z1):
                    verts.append((er[0] * y + et[0] * x,
                                  er[1] * y + et[1] * x, z))
        q = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 2, 6, 4), (1, 5, 7, 3),
             (0, 4, 5, 1), (2, 3, 7, 6)]
        faces.extend([tuple(base + k for k in f) for f in q])
    return _solid("Keystones", verts, faces)


# =============================================================================
# 6  COLLIDER -- floor fan, uniform kerb, pier quads, ceiling
# =============================================================================

def _collider(m, plan):
    verts, faces = [], []

    def v(p):
        verts.append(tuple(p))
        return len(verts) - 1

    def emit(idx, want):
        pts = [verts[k] for k in idx]
        if _newell(pts).dot(Vector(want)) < 0.0:
            idx = list(reversed(idx))
        if len(idx) == 4:
            faces.append((idx[0], idx[1], idx[2]))
            faces.append((idx[0], idx[2], idx[3]))
        else:
            faces.append(tuple(idx))

    def rad(a):
        return (-math.cos(a), -math.sin(a), 0.0)

    r_in, ceil_z = m["r_in"], m["ceil"]
    bear, f_ring = m["bear"], m["f_ring"]
    sill_z = plan["sill"]

    hub = v((0.0, 0.0, m["f_axis"]))
    floor = [v((r_in * math.cos(b), r_in * math.sin(b), z))
             for b, z in zip(bear, f_ring)]
    for i in range(NSUB):
        emit([hub, floor[i], floor[(i + 1) % NSUB]], (0.0, 0.0, 1.0))

    sill = [v((r_in * math.cos(b), r_in * math.sin(b), sill_z)) for b in bear]
    for i in range(NSUB):
        j = (i + 1) % NSUB
        emit([floor[i], floor[j], sill[j], sill[i]],
             rad(bear[i] + 0.5 * TAU / NSUB))

    spans, bs = [], sorted(plan["bear"])
    half = plan["half_in"]
    for k in range(len(bs)):
        a0 = bs[k] + half
        a1 = bs[(k + 1) % len(bs)] - half
        span = (a1 - a0) % TAU
        spans.append(span * r_in)
        q = [v((r_in * math.cos(a0), r_in * math.sin(a0), sill_z)),
             v((r_in * math.cos(a0 + span), r_in * math.sin(a0 + span), sill_z)),
             v((r_in * math.cos(a0 + span), r_in * math.sin(a0 + span), ceil_z)),
             v((r_in * math.cos(a0), r_in * math.sin(a0), ceil_z))]
        emit(q, rad(a0 + 0.5 * span))

    ceil = [v((r_in * math.cos(b), r_in * math.sin(b), ceil_z)) for b in bear]
    hub2 = v((0.0, 0.0, ceil_z))
    for i in range(NSUB):
        emit([hub2, ceil[i], ceil[(i + 1) % NSUB]], (0.0, 0.0, -1.0))
    return mdl.mesh(COLLIDER_NAME, verts, faces), spans


# =============================================================================
# 7  UV -- his atlas kept; the boolean's new faces go into the rock zone
# =============================================================================

def _lost(me, uvl, poly):
    uvs = [uvl.data[li].uv for li in poly.loop_indices]
    if max(abs(u[0]) + abs(u[1]) for u in uvs) < 1e-6:
        return True
    du = max(u[0] for u in uvs) - min(u[0] for u in uvs)
    dv = max(u[1] for u in uvs) - min(u[1] for u in uvs)
    return du < 1e-6 and dv < 1e-6


def unwrap(ob, name):
    me = ob.data
    uvl = me.uv_layers.get(name)
    if uvl is None:
        print("MDL note: UV layer %r did not survive; his atlas is lost" % name)
        uvl = me.uv_layers.new(name=name)
    r = _Rng(SEED + len(me.polygons))
    u0, v0, u1, v1 = ZONE_ROCK
    span_u, span_v = (u1 - u0) - 2.0 * UV_PAD, (v1 - v0) - 2.0 * UV_PAD
    done = 0
    for poly in me.polygons:
        if not _lost(me, uvl, poly):
            continue
        done += 1
        cos = [me.vertices[me.loops[li].vertex_index].co
               for li in poly.loop_indices]
        nrm = poly.normal
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
        fu = -1.0 if r.i(0, 1) else 1.0
        fv = -1.0 if r.i(0, 1) else 1.0
        mi, mj = min(c[ii] for c in cos), min(c[jj] for c in cos)
        w = min((max(c[ii] for c in cos) - mi) * UV_SCALE, 1.0)
        h = min((max(c[jj] for c in cos) - mj) * UV_SCALE, 1.0)
        ou, ov = r.f() * (1.0 - w), r.f() * (1.0 - h)
        for li, co in zip(poly.loop_indices, cos):
            s = min(ou + (co[ii] - mi) * UV_SCALE, 1.0)
            t = min(ov + (co[jj] - mj) * UV_SCALE, 1.0)
            if fu < 0.0:
                s = 1.0 - s
            if fv < 0.0:
                t = 1.0 - t
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)
    return done


# =============================================================================
# 7b  FLECKS -- one floor facet magnified a lava fleck into a wedge
# =============================================================================

def _flecks(mat):
    """Texels of his emissive atlas that carry lava, as (x, y), plus its size."""
    img = None
    if mat.use_nodes:
        for nd in mat.node_tree.nodes:
            if nd.type == "TEX_IMAGE" and nd.image and "emissive" in nd.image.name:
                img = nd.image
                break
    if img is None:
        return None, 0, 0
    w, h = img.size
    px = list(img.pixels)
    hot = []
    for i in range(w * h):
        lum = (0.2126 * px[4 * i] + 0.7152 * px[4 * i + 1]
               + 0.0722 * px[4 * i + 2])
        if lum > FLECK_LUM:
            hot.append((i % w, i // w))
    return hot, w, h


def _uv_area(uvs):
    """Shoelace area of a face in UV units."""
    a = 0.0
    for k in range(len(uvs)):
        u0, v0 = uvs[k]
        u1, v1 = uvs[(k + 1) % len(uvs)]
        a += u0 * v1 - u1 * v0
    return abs(a) * 0.5


def _in_face(uvs, pu, pv):
    """Is (pu, pv) inside the face, fanned from its first loop?"""
    for k in range(1, len(uvs) - 1):
        (ax, ay), (bx, by), (cx, cy) = uvs[0], uvs[k], uvs[k + 1]
        d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) < 1.0e-12:
            continue
        r = ((by - cy) * (pu - cx) + (cx - bx) * (pv - cy)) / d
        t = ((cy - ay) * (pu - cx) + (ax - cx) * (pv - cy)) / d
        if r >= 0.0 and t >= 0.0 and r + t <= 1.0:
            return True
    return False


def _fleck_lava(uvs, hot, w, h):
    """Lava texels whose centre falls inside the face."""
    return sum(1 for x, y in hot if _in_face(uvs, (x + 0.5) / w, (y + 0.5) / h))


def _fleck_clear(bb, lava, w, h, du, dv):
    """No lava texel inside the shifted rect, widened by FLECK_GUARD texels."""
    x0 = int((bb[0] + du) * w) - FLECK_GUARD
    x1 = int((bb[2] + du) * w) + FLECK_GUARD
    y0 = int((bb[1] + dv) * h) - FLECK_GUARD
    y1 = int((bb[3] + dv) * h) + FLECK_GUARD
    for x, y in lava:
        if x0 <= x <= x1 and y0 <= y <= y1:
            return False
    return True


def _fleck_cell(uvs):
    """The quarter of the atlas a face is mapped into."""
    cu = 0.0 if 0.5 * (min(u[0] for u in uvs) + max(u[0] for u in uvs)) < 0.5 else 0.5
    cv = 0.0 if 0.5 * (min(u[1] for u in uvs) + max(u[1] for u in uvs)) < 0.5 else 0.5
    return cu, cv


def _fleck_place(uvs, hot, w, h):
    """Smallest change that lifts a face off every lava texel in its own cell.

    A plain slide first. His flecks are spread so that the widest lava-free
    window 44 texels tall is only 29 wide, and the larger of the two fanned
    facets needs 33 x 46 -- three texels too tall to fit anywhere. So if no
    slide fits, give up two per cent of the face's UV about its own centre and
    try again; at that size it drops into the 48 x 43 window between them.
    """
    cu, cv = _fleck_cell(uvs)
    lava = [(x, y) for x, y in hot
            if cu <= (x + 0.5) / w <= cu + 0.5 and cv <= (y + 0.5) / h <= cv + 0.5]
    mu = sum(u[0] for u in uvs) / len(uvs)
    mv = sum(u[1] for u in uvs) / len(uvs)
    for sc in FLECK_FIT:
        suv = [(mu + (u - mu) * sc, mv + (v - mv) * sc) for u, v in uvs]
        bb = (min(u[0] for u in suv), min(u[1] for u in suv),
              max(u[0] for u in suv), max(u[1] for u in suv))
        best = None
        for a in range(-w, w + 1):
            du = a / float(w)
            if bb[0] + du < cu + UV_PAD or bb[2] + du > cu + 0.5 - UV_PAD:
                continue
            for b in range(-h, h + 1):
                if best is not None and abs(a) + abs(b) >= best[0]:
                    continue
                dv = b / float(h)
                if bb[1] + dv < cv + UV_PAD or bb[3] + dv > cv + 0.5 - UV_PAD:
                    continue
                if _fleck_clear(bb, lava, w, h, du, dv):
                    best = (abs(a) + abs(b), sc, du, dv, a, b)
        if best:
            return best[1], best[2], best[3], best[4], best[5]
    return None


def unfleck(ob, name, mat, floor_z):
    """Lift every blown-up guard-room floor facet off his lava flecks.

    His atlas hides four 2x2 lava flecks in the otherwise unlit cell the room
    floor is mapped into -- bright in the base colour AND in the emissive map,
    so a facet covering one glows whether the room is lit or not. The dissolve
    at the end of build() merges the floor into a single n-gon and triangulates
    it into a fan, which leaves two facets carrying 32 and 49 square metres of
    floor on 37 and 333 texels of his UV. At 0.88 and 0.15 m2 per texel they
    render a fleck as a wedge; every floor facet still on his own mapping runs
    0.012 m2 per texel or finer and renders the same fleck as the grain it was
    drawn to be. So the test is magnification, and lava, not area: move the
    facets that are both, leave his mapping alone everywhere else.
    """
    hot, w, h = _flecks(mat)
    if hot is None:
        print("MDL note: no emissive atlas; fleck pass skipped")
        return 0
    me = ob.data
    uvl = me.uv_layers.get(name)
    if uvl is None:
        return 0
    cand = []
    for poly in me.polygons:
        if abs(poly.normal.z) < 0.9:
            continue
        if abs(poly.center.z - floor_z) > FLECK_Z:
            continue
        uvs = [tuple(uvl.data[li].uv) for li in poly.loop_indices]
        tx = _uv_area(uvs) * w * h
        if tx <= 0.0 or poly.area / tx <= FLECK_M2PT:
            continue
        n = _fleck_lava(uvs, hot, w, h)
        if n:
            cand.append((poly, uvs, poly.area / tx, tx, n))
    if len(cand) > FLECK_MAX:
        print("MDL WARN unfleck found %d blown-up floor facets on lava, over "
              "the %d cap -- nothing moved" % (len(cand), FLECK_MAX))
        for poly, uvs, mpt, tx, n in sorted(cand, key=lambda c: -c[2]):
            print("MDL WARN   area=%.2fm2 texels=%.1f %.5f m2/texel lava=%d"
                  % (poly.area, tx, mpt, n))
        return 0
    moved = 0
    for poly, uvs, mpt, tx, n in cand:
        put = _fleck_place(uvs, hot, w, h)
        if put is None:
            print("MDL WARN floor facet %.2fm2 at %.5f m2/texel has nowhere "
                  "clear to go -- left on %d lava texel(s)"
                  % (poly.area, mpt, n))
            continue
        sc, du, dv, a, b = put
        mu = sum(u[0] for u in uvs) / len(uvs)
        mv = sum(u[1] for u in uvs) / len(uvs)
        for li in poly.loop_indices:
            u, v = uvl.data[li].uv
            uvl.data[li].uv = (mu + (u - mu) * sc + du, mv + (v - mv) * sc + dv)
        new = [tuple(uvl.data[li].uv) for li in poly.loop_indices]
        moved += 1
        print("MDL STATS unflecked area=%.2fm2 texels=%.1f %.4f m2/texel "
              "lava=%d->%d scale=%.2f shift=(%+d,%+d) u %.4f..%.4f v %.4f..%.4f"
              " -> u %.4f..%.4f v %.4f..%.4f"
              % (poly.area, tx, mpt, n, _fleck_lava(new, hot, w, h), sc, a, b,
                 min(u[0] for u in uvs), max(u[0] for u in uvs),
                 min(u[1] for u in uvs), max(u[1] for u in uvs),
                 min(u[0] for u in new), max(u[0] for u in new),
                 min(u[1] for u in new), max(u[1] for u in new)))
    return moved


# =============================================================================
# EXTRA RENDERS -- the room from inside, and the head framed by hand
# =============================================================================

def _extra_renders(spec, objects):
    scene = bpy.context.scene
    floor_z = MEAS["floor"]
    if spec.get("engine", "eevee").lower() == "cycles":
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = int(spec.get("samples", 24))
        scene.cycles.use_denoising = True
    else:
        scene.render.engine = "BLENDER_EEVEE"
        mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 64)))
        mdl._try(scene.eevee, "use_shadows", True)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")

    world = bpy.data.worlds.new("Hell")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.34, 0.11, 0.08, 1.0)
    bg.inputs[1].default_value = 0.65

    target = mdl._link(bpy.data.objects.new("InTarget", None))
    cam = mdl._link(bpy.data.objects.new("InCam", bpy.data.cameras.new("InCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"

    ux, uy = math.cos(MEAS["open"]), math.sin(MEAS["open"])
    fl = bpy.data.lights.new("RoomFill", type="POINT")
    fl.energy = 900.0
    fl.color = (1.0, 0.55, 0.40)
    lamp = mdl._link(bpy.data.objects.new("RoomFill", fl))
    lamp.location = (-ux * 1.8, -uy * 1.8, floor_z + 2.4)

    cam.data.lens = 18.0
    cam.location = (-ux * 4.6, -uy * 4.6, floor_z + EYE_H)
    target.location = (ux * 24.0, uy * 24.0, floor_z + 2.3)
    scene.render.resolution_x, scene.render.resolution_y = 1000, 760
    bpy.context.view_layer.update()
    scene.render.filepath = os.path.join(spec.get("out_dir", "."), "%s_room.png" % NAME)
    bpy.ops.render.render(write_still=True)
    print("MDL RENDER %s_room.png (hand-placed camera)" % NAME)
    lamp.data.energy = 0.0

    key = bpy.data.lights.new("Sun", type="SUN")
    key.energy = 3.2
    sun = mdl._link(bpy.data.objects.new("Sun", key))
    sun.rotation_euler = (math.radians(58.0), 0.0, math.radians(38.0))
    bg.inputs[1].default_value = 1.15
    cam.data.lens = 50.0
    scene.render.resolution_x, scene.render.resolution_y = 1100, 1000
    for tag, az, el in (("out1_az90_el4", 90.0, 4.0), ("out2_az30_el20", 30.0, 20.0)):
        a, e = math.radians(az), math.radians(el)
        d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e),
                    math.sin(e)))
        target.location = (0.0, 0.0, 0.6)
        cam.location = target.location + d * 46.0
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(spec.get("out_dir", "."),
                                             "%s_%s.png" % (NAME, tag))
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s_%s.png (hand-framed on the head)" % (NAME, tag))

    for ob in (cam, target, lamp, sun):
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def _shell(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    n = (len([e for e in bm.edges if e.is_boundary]),
         len([e for e in bm.edges if not e.is_manifold]))
    bm.free()
    return n


def build():
    rock, mat, uvname = _append_rock()

    bm = bmesh.new()
    bm.from_mesh(rock.data)
    print("MDL STATS before open_edges=%d non_manifold=%d"
          % (len([e for e in bm.edges if e.is_boundary]),
             len([e for e in bm.edges if not e.is_manifold])))
    rep = _repair(bm)
    print("MDL STATS repair welded=%d degenerate=%d zero_area=%d flaps=%d "
          "loose=%d filled=%d reversed=%s volume=%.1f"
          % (rep["welded"], rep["degenerate_edges"], rep["zero_area_faces"],
             len(rep["flaps"]), rep["loose_verts"], len(rep["filled"]),
             rep["reversed"], rep["volume"]))
    print("MDL STATS after open_edges=%d non_manifold=%d watertight=%s"
          % (rep["open_edges"], rep["non_manifold"],
             rep["open_edges"] == 0 and rep["non_manifold"] == 0))
    n_dis = _polish(bm)
    bm.to_mesh(rock.data)
    bm.free()
    for a in list(rock.data.attributes):
        if a.name == "custom_normal":
            rock.data.attributes.remove(a)
    rock.data.update()
    rock.name = OBJECT_NAME
    rock.data.name = OBJECT_NAME
    print("MDL STATS cleaned verts=%d tris=%d dissolved=%d"
          % (len(rock.data.vertices), _tris(rock), n_dis))

    m = _measure(rock)
    plan = _arch_plan(m)

    n0 = _tris(rock)
    _boolean(rock, _plugs(m), "UNION")
    print("MDL STATS filled windows tris %d -> %d open_edges=%d non_manifold=%d"
          % (n0, _tris(rock), _shell(rock)[0], _shell(rock)[1]))

    m["probe"] = Probe(rock)
    still = [w for w in m["wins"]
             if m["probe"].skin(w["bc"], 0.5 * (w["z0"] + w["z1"])) is None]
    if still:
        print("MDL WARN %d window(s) still open after the fill" % len(still))

    n0 = _tris(rock)
    _boolean(rock, _bands(m, plan), "UNION")
    print("MDL STATS string courses tris %d -> %d" % (n0, _tris(rock)))

    n0 = _tris(rock)
    _boolean(rock, _arches(m, plan), "DIFFERENCE")
    print("MDL STATS arches cut tris %d -> %d" % (n0, _tris(rock)))

    n0 = _tris(rock)
    _boolean(rock, _keystones(m, plan), "UNION")
    print("MDL STATS keystones tris %d -> %d" % (n0, _tris(rock)))

    # The booleans leave needless verts strewn over flat rock. Dissolve them
    # at his own 3deg, never across a UV island, then go back to triangles.
    n0 = _tris(rock)
    bm = bmesh.new()
    bm.from_mesh(rock.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1.0e-4)
    bmesh.ops.dissolve_degenerate(bm, dist=DEGEN, edges=list(bm.edges))
    lo = MEAS["floor"] - 1.5
    verts = [v for v in bm.verts if v.co.z > lo]
    edges = [e for e in bm.edges if all(v.co.z > lo for v in e.verts)]
    try:
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(DISSOLVE),
                                 verts=verts, edges=edges, delimit={"UV"})
    except Exception as exc:
        print("MDL note: dissolve skipped (%s)" % exc)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    n_fin = _mend(bm)
    n_sl = _slivers(bm)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    bm.to_mesh(rock.data)
    bm.free()
    rock.data.name = OBJECT_NAME
    rock.data.update()
    print("MDL STATS dissolved tris %d -> %d mended=%d slivers_fixed=%d"
          % (n0, _tris(rock), n_fin, n_sl))

    n_uv = unwrap(rock, uvname)
    n_fleck = unfleck(rock, uvname, mat, m["floor"])
    mdl.finish(rock, mat, flat=True, strip_uvs=False)

    coll_ob, spans = _collider(m, plan)
    coll_ob.hide_render = True
    MEAS["open"] = plan["bear"][0]

    coll_ob.data.calc_loop_triangles()
    bo, nm = _shell(rock)
    print("MDL STATS visual_tris=%d collision_tris=%d reuv_faces=%d "
          "unflecked=%d open_edges=%d non_manifold=%d"
          % (_tris(rock), len(coll_ob.data.loop_triangles), n_uv, n_fleck,
             bo, nm))
    print("MDL STATS arch width=%.2fm hw=%.2f sill=%.2f (floor+%.2f) "
          "spring=%.2f crown=%.2f jamb=%.2f splay=%.0fdeg"
          % (plan["width"], plan["hw"], plan["sill"],
             plan["sill"] - m["floor"], plan["spring"], plan["crown"],
             plan["jamb"], SPLAY))
    print("MDL STATS pier inner_width=%.2f..%.2fm (half_angle=%.1fdeg) "
          "bands top=%.2f,%.2f h=%.2f proud=%.2f arch_drift=%.1fdeg"
          % (min(spans), max(spans), math.degrees(plan["half_in"]),
             plan["sill"], plan["spring"], BAND_H, BAND_PROUD, plan["drift"]))
    print("MDL STATS bearings=%s"
          % " ".join("%.0f" % (math.degrees(b) % 360.0) for b in plan["bear"]))
    print("MDL STATS floor=%.3f ceil=%.3f headroom=%.2f eye=%.3f kerb=%.2f "
          "above floor (guard apex 1.11)"
          % (m["floor"], m["ceil"], m["ceil"] - m["floor"] - BODY_H,
             m["floor"] + EYE_H, plan["sill"] - m["floor"]))
    return [rock, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=0.0, post=_extra_renders)
