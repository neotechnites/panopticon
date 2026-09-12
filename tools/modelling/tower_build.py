"""tower -- Ryan's hand-edited TowerRock, cleaned.

tower_new.blend is the source of truth. His mesh is appended whole, repaired
(stray flaps cut, cracks filled, doubles merged, normals recalculated outward),
dissolved and re-triangulated. The room floor, ceiling, inner radius and window
bearings are MEASURED off his mesh and the collider is rebuilt to match. The
old grow/boolean pipeline is retired/tower_build_grown.py.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# The model hangs 37 m below its origin, so mdl's ground plane lands above the
# camera at low elevations and renders a black frame. World light replaces it.
mdl.DEFAULTS["ground"] = False
mdl.DEFAULTS["world_grey"] = 0.30
mdl.DEFAULTS["world_strength"] = 0.90

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "tower"
OBJECT_NAME = "TowerRock"
COLLIDER_NAME = "TowerCollision-colonly"
BLEND_PATH = r"C:\dev\panopticon\assets\models\tower_new.blend"

WELD       = 0.02      # merge by distance
DEGEN      = 1.0e-4    # edge length below which an edge is degenerate
DISSOLVE   = 3.0       # degrees
DISSOLVE_Z = -2.60     # ...applied only above here; his lower rock is untouched
FLAP_PASSES = 8

NSUB       = 32        # collider ring resolution
NBEAR      = 288       # bearings sampled when finding the window piers
SILL_MIN   = 1.20      # a kerb lower than this can be jumped (apex 1.11)
SILL_NEAR  = 20.0      # a kerb quad answers to every window within this many deg
EYE_H      = 1.65
BODY_H     = 1.80
PIER_TRIM  = 0.5       # sample-widths shaved off each pier end

# Atlas zones as (u0, v0, u1, v1), matching the packed HellRock atlas.
ZONE_ROCK  = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)
ZONE_CARVE = (0.5, 0.0, 1.0, 0.5)
UV_SCALE = 0.13
UV_PAD = 1.5 / 128.0

TAU = 2.0 * math.pi
SEED = 20260913

MEAS = {"floor": 0.17, "ceil": 7.25, "r_in": 7.0, "open": 0.0}


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
    """Group boundary edges into connected components."""
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
    cz = sum(c.z for c in cs) / len(cs)
    return ("bearing=%3.0fdeg r=%.2f z=%.2f..%.2f edges=%d perim=%.2f"
            % (math.degrees(math.atan2(cy, cx)) % 360.0, math.hypot(cx, cy),
               min(c.z for c in cs), max(c.z for c in cs), len(comp),
               sum(e.calc_length() for e in comp)))


def _tris(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


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
# 1  REPAIR -- doubles, flaps, cracks, normals
# =============================================================================

def _cut_flaps(bm):
    """A flap is loose skin laid over an edge that already had two faces.

    Rough editing leaves one at every window. Cut it; welding it in instead
    would leave the sliver standing proud of the reveal. A boundary loop that
    closes on itself and touches no over-used edge is a real hole, not a flap,
    and is left for _repair to fill.
    """
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

    # whatever crack is left is a real hole: fill it and say where it was
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


def _open_bearing(piers):
    """The middle of the first window, so the room camera looks out of one."""
    if len(piers) < 2:
        return 0.0
    edge = piers[0][0] + piers[0][1]
    return edge + 0.5 * ((piers[1][0] - edge) % TAU)


def _polish(bm):
    """Dissolve the needless verts his edit left, then go back to triangles."""
    verts = [v for v in bm.verts if v.co.z > DISSOLVE_Z]
    edges = [e for e in bm.edges if all(v.co.z > DISSOLVE_Z for v in e.verts)]
    n0 = len(bm.verts)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(DISSOLVE),
                             verts=verts, edges=edges)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    return n0 - len(bm.verts)


# =============================================================================
# 2  MEASURE -- his room, read off his mesh
# =============================================================================

def _bvh(ob):
    return BVHTree.FromPolygons([v.co.copy() for v in ob.data.vertices],
                                [list(p.vertices) for p in ob.data.polygons],
                                all_triangles=False, epsilon=0.0)


def _measure(ob):
    """Floor height per bearing, ceiling, inner radius, and the window piers."""
    bvh = _bvh(ob)
    bear = [TAU * i / NSUB for i in range(NSUB)]

    def down(x, y, z):
        hit = bvh.ray_cast(Vector((x, y, z)), Vector((0.0, 0.0, -1.0)), 80.0)
        return hit[0].z if hit[0] else None

    def out(z, a, lim=40.0):
        hit = bvh.ray_cast(Vector((0.0, 0.0, z)),
                           Vector((math.cos(a), math.sin(a), 0.0)), lim)
        return math.hypot(hit[0].x, hit[0].y) if hit[0] else None

    # ceiling first: cast up the axis from well inside the cavity
    probe = None
    for z in (2.0, 3.0, 4.0):
        hit = bvh.ray_cast(Vector((0.0, 0.0, z)), Vector((0.0, 0.0, 1.0)), 60.0)
        if hit[0]:
            probe = hit[0].z
            break
    ceil_z = probe if probe else 7.25

    # inner radius: a band that is solid all the way round, under the sills
    r_ring = []
    for a in bear:
        best = None
        for z in (ceil_z - 0.30, ceil_z - 0.50):
            rr = out(z, a)
            if rr and (best is None or rr < best):
                best = rr
        r_ring.append(best if best else 7.0)
    r_in = min(r_ring)

    # floor: straight down from under the ceiling, at the ring and at the axis
    f_ring = []
    for a in bear:
        rr = r_in * 0.94
        z = down(rr * math.cos(a), rr * math.sin(a), ceil_z - 0.30)
        f_ring.append(z if z is not None else 0.17)
    f_axis = down(0.0, 0.0, ceil_z - 0.30)
    if f_axis is None:
        f_axis = min(f_ring)

    # window piers: bearings that are solid across the whole opening band
    lo_z = max(f_ring) + 0.30
    zs = [lo_z + (ceil_z - 0.18 - lo_z) * k / 9.0 for k in range(10)]
    solid = []
    for i in range(NBEAR):
        a = TAU * i / NBEAR
        solid.append(all((out(z, a) or 99.0) < r_in + 0.9 for z in zs))

    piers, k = [], 0
    while k < NBEAR and solid[k]:
        k += 1                               # start on an opening
    if k == NBEAR:
        piers = [(0.0, TAU)]                 # no windows at all
    else:
        start = None
        for n in range(NBEAR + 1):
            i = (k + n) % NBEAR
            if solid[i] and start is None:
                start = n
            elif not solid[i] and start is not None:
                piers.append((TAU * (k + start + PIER_TRIM) / NBEAR,
                              TAU * (n - start - 2.0 * PIER_TRIM) / NBEAR))
                start = None
    windows = NBEAR - sum(1 for s in solid if s)

    # his visible sill, per window: the lowest z at which the wall opens.
    # The collider kerb tops out here -- a kerb any higher is an invisible
    # pane across the bottom of the opening, and it eats shots.
    def sill_at(a):
        lo, hi = max(f_ring), ceil_z - 0.10
        z = lo
        while z < hi and (out(z, a) or 99.0) < r_in + 0.9:
            z += 0.08
        if z >= hi:
            return None                       # never opens: a pier
        lo2 = z - 0.08
        for _ in range(7):                    # bisect onto the sill
            mid = 0.5 * (lo2 + z)
            if (out(mid, a) or 99.0) < r_in + 0.9:
                lo2 = mid
            else:
                z = mid
        return z

    wins = []
    for n in range(NBEAR):
        i, j = (k + n) % NBEAR, (k + n - 1) % NBEAR
        if not solid[i] and (n == 0 or solid[j]):
            run = []
            m = n
            while m < n + NBEAR and not solid[(k + m) % NBEAR]:
                run.append((k + m) % NBEAR)
                m += 1
            zs2 = [z for z in (sill_at(TAU * b / NBEAR) for b in run) if z]
            if not zs2:
                continue
            wins.append({"i0": run[0], "i1": run[-1],
                         "b0": TAU * run[0] / NBEAR, "b1": TAU * run[-1] / NBEAR,
                         "lo": min(zs2), "hi": max(zs2)})

    def kerb_at(b):
        """The lowest visible sill of any window this kerb quad faces."""
        near = []
        for w in wins:
            d0 = min((b - w["b0"]) % TAU, (w["b0"] - b) % TAU)
            d1 = min((b - w["b1"]) % TAU, (w["b1"] - b) % TAU)
            inside = ((b - w["b0"]) % TAU) <= ((w["b1"] - w["b0"]) % TAU)
            d = 0.0 if inside else min(d0, d1)
            near.append((d, w["lo"]))
        near.sort()
        cut = math.radians(SILL_NEAR)
        chosen = [z for d, z in near if d <= cut] or [near[0][1]]
        return min(chosen)

    if wins:
        kerb = [max(z + 0.05, kerb_at(b)) for b, z in zip(bear, f_ring)]
    else:
        kerb = [z + SILL_MIN for z in f_ring]
    short = [w for w in wins if w["lo"] < max(f_ring) + SILL_MIN]

    MEAS.update({"floor": max(f_ring), "ceil": ceil_z, "r_in": r_in,
                 "f_ring": f_ring, "f_axis": f_axis, "bear": bear,
                 "piers": piers, "kerb": kerb, "wins": wins})
    print("MDL STATS room floor=%.3f..%.3f axis=%.3f ceil=%.3f r_in=%.2f "
          "piers=%d open=%.0f%% headroom=%.2f"
          % (min(f_ring), max(f_ring), f_axis, ceil_z, r_in, len(piers),
             100.0 * windows / NBEAR, ceil_z - max(f_ring) - BODY_H))
    for i, w in enumerate(wins):
        print("MDL STATS   win%d bearing=%.0f..%.0fdeg visible_sill=%.3f..%.3f "
              "above_floor=%.3f" % (i, math.degrees(w["b0"]) % 360.0,
                                    math.degrees(w["b1"]) % 360.0,
                                    w["lo"], w["hi"], w["lo"] - max(f_ring)))
    for i, (b0, span) in enumerate(piers):
        print("MDL STATS   pier%d bearing=%.0f..%.0fdeg width=%.2fm"
              % (i, math.degrees(b0) % 360.0,
                 math.degrees(b0 + span) % 360.0, span * r_in))
    for w in short:
        print("MDL WARN sill short: window at bearing %.0f..%.0fdeg sits %.3f m "
              "above the floor, %.3f m under the %.2f m jump kerb -- the kerb "
              "was NOT raised, it would have blocked the opening"
              % (math.degrees(w["b0"]) % 360.0, math.degrees(w["b1"]) % 360.0,
                 w["lo"] - max(f_ring), max(f_ring) + SILL_MIN - w["lo"],
                 SILL_MIN))
    return MEAS


# =============================================================================
# 3  COLLIDER -- floor, sill all round, a quad per pier, ceiling
# =============================================================================

def _collider(m):
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

    # floor: a fan from the axis, riding his uneven rock
    hub = v((0.0, 0.0, m["f_axis"]))
    floor = [v((r_in * math.cos(b), r_in * math.sin(b), z))
             for b, z in zip(bear, f_ring)]
    for i in range(NSUB):
        emit([hub, floor[i], floor[(i + 1) % NSUB]], (0.0, 0.0, 1.0))

    # kerb: it tops out at the visible sill of the window it faces, never
    # above it. An invisible pane over the bottom of an opening eats shots.
    kerb_z = m["kerb"]
    sill = [v((r_in * math.cos(b), r_in * math.sin(b), z))
            for b, z in zip(bear, kerb_z)]
    for i in range(NSUB):
        j = (i + 1) % NSUB
        emit([floor[i], floor[j], sill[j], sill[i]],
             rad(bear[i] + 0.5 * TAU / NSUB))

    # inner wall: one quad per pier, from the kerb to the ceiling. Nothing
    # spans an opening, so a bullet and a body go straight through a window.
    spans = []
    for b0, span in m["piers"]:
        spans.append(span * r_in)
        lo = min(kerb_z)          # the pier is solid rock: starting low is free
        q = [v((r_in * math.cos(b0), r_in * math.sin(b0), lo)),
             v((r_in * math.cos(b0 + span), r_in * math.sin(b0 + span), lo)),
             v((r_in * math.cos(b0 + span), r_in * math.sin(b0 + span), ceil_z)),
             v((r_in * math.cos(b0), r_in * math.sin(b0), ceil_z))]
        emit(q, rad(b0 + 0.5 * span))

    ceil = [v((r_in * math.cos(b), r_in * math.sin(b), ceil_z)) for b in bear]
    hub2 = v((0.0, 0.0, ceil_z))
    for i in range(NSUB):
        emit([hub2, ceil[i], ceil[(i + 1) % NSUB]], (0.0, 0.0, -1.0))
    return mdl.mesh(COLLIDER_NAME, verts, faces), spans


# =============================================================================
# 4  UV -- his atlas kept; only the faces that lost theirs are re-projected
# =============================================================================

def _zone(c, n, ceil_z):
    rad = Vector((c.x, c.y, 0.0))
    d = n.dot(rad.normalized()) if rad.length > 1e-6 else 0.0
    if n.z > 0.55:
        return ZONE_ROCK if c.z > ceil_z else ZONE_SHADE
    if n.z < -0.55:
        return ZONE_SHADE
    if d > 0.15:
        return ZONE_ROCK
    if d < -0.15:
        return ZONE_SHADE
    return ZONE_CARVE


def _lost(me, uvl, poly):
    uvs = [uvl.data[li].uv for li in poly.loop_indices]
    if max(abs(u[0]) + abs(u[1]) for u in uvs) < 1e-6:
        return True
    du = max(u[0] for u in uvs) - min(u[0] for u in uvs)
    dv = max(u[1] for u in uvs) - min(u[1] for u in uvs)
    return du < 1e-6 and dv < 1e-6


def unwrap(ob, name, ceil_z):
    me = ob.data
    uvl = me.uv_layers.get(name)
    if uvl is None:
        print("MDL note: UV layer %r did not survive; his atlas is lost" % name)
        uvl = me.uv_layers.new(name=name)
    r = _Rng(SEED + len(me.polygons))
    done = 0
    for poly in me.polygons:
        if not _lost(me, uvl, poly):
            continue
        done += 1
        cos = [me.vertices[me.loops[li].vertex_index].co
               for li in poly.loop_indices]
        u0, v0, u1, v1 = _zone(poly.center, poly.normal, ceil_z)
        span_u, span_v = (u1 - u0) - 2.0 * UV_PAD, (v1 - v0) - 2.0 * UV_PAD
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


def _sample_normals(ob, m):
    """Outward on the outside, inward in the room. Counted, not assumed."""
    me = ob.data
    r_in, floor_z, ceil_z = m["r_in"], m["floor"], m["ceil"]
    tally = {"inner": [0, 0], "outer": [0, 0], "floor": [0, 0], "ceil": [0, 0]}
    for p in me.polygons:
        c, n = p.center, p.normal
        rr = math.hypot(c.x, c.y)
        rad = Vector((c.x, c.y, 0.0))
        rad = rad.normalized() if rad.length > 1e-6 else Vector((1.0, 0.0, 0.0))
        d = n.dot(rad)
        if abs(n.z) < 0.5 and abs(d) > 0.85 and floor_z + 0.4 < c.z < ceil_z - 0.4:
            if abs(rr - r_in) < 0.25:
                tally["inner"][d < 0.0] += 1
            elif rr > r_in + 0.55:
                tally["outer"][d > 0.0] += 1
        elif rr < r_in - 0.4 and abs(c.z - floor_z) < 0.20:
            tally["floor"][n.z > 0.0] += 1
        elif rr < r_in - 0.4 and abs(c.z - ceil_z) < 0.08:
            tally["ceil"][n.z < 0.0] += 1
    return tally


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

    # The rock is 47 m deep, so mdl's auto-fit renders the head as a speck.
    # These two frame the head and the column under it, which is what is judged.
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

def build():
    rock, mat, uvname = _append_rock()

    bm = bmesh.new()
    bm.from_mesh(rock.data)
    b_open = len([e for e in bm.edges if e.is_boundary])
    b_nm = len([e for e in bm.edges if not e.is_manifold])
    print("MDL STATS before open_edges=%d non_manifold=%d" % (b_open, b_nm))

    rep = _repair(bm)
    print("MDL STATS repair welded=%d degenerate=%d zero_area=%d flaps=%d "
          "loose=%d filled=%d reversed=%s volume=%.1f"
          % (rep["welded"], rep["degenerate_edges"], rep["zero_area_faces"],
             len(rep["flaps"]), rep["loose_verts"], len(rep["filled"]),
             rep["reversed"], rep["volume"]))
    for c, a in rep["flaps"]:
        print("MDL STATS   flap cut at (%.2f,%.2f,%.2f) bearing=%3.0fdeg r=%.2f "
              "area=%.3f" % (c.x, c.y, c.z,
                             math.degrees(math.atan2(c.y, c.x)) % 360.0,
                             math.hypot(c.x, c.y), a))
    for d in rep["filled"]:
        print("MDL STATS   hole filled %s" % d)
    print("MDL STATS after open_edges=%d non_manifold=%d watertight=%s"
          % (rep["open_edges"], rep["non_manifold"],
             rep["open_edges"] == 0 and rep["non_manifold"] == 0))

    n_dis = _polish(bm)
    print("MDL STATS dissolved_verts=%d" % n_dis)
    bm.to_mesh(rock.data)
    bm.free()
    # Flat shading must read the true face normals, not the custom split
    # normals his edit dragged along, or a fixed face still shades inside-out.
    for a in list(rock.data.attributes):
        if a.name == "custom_normal":
            rock.data.attributes.remove(a)
    rock.data.update()

    rock.name = OBJECT_NAME
    rock.data.name = OBJECT_NAME
    print("MDL STATS cleaned verts=%d tris=%d" % (len(rock.data.vertices),
                                                  _tris(rock)))

    m = _measure(rock)
    n_uv = unwrap(rock, uvname, m["ceil"])
    mdl.finish(rock, mat, flat=True, strip_uvs=False)

    coll_ob, spans = _collider(m)
    coll_ob.hide_render = True
    MEAS["open"] = _open_bearing(m["piers"])

    tally = _sample_normals(rock, m)
    coll_ob.data.calc_loop_triangles()
    print("MDL STATS visual_tris=%d collision_tris=%d reuv_faces=%d"
          % (_tris(rock), len(coll_ob.data.loop_triangles), n_uv))
    print("MDL STATS normals inner=%d/%d outer=%d/%d floor=%d/%d ceil=%d/%d "
          "(good/total)"
          % (tally["inner"][1], sum(tally["inner"]),
             tally["outer"][1], sum(tally["outer"]),
             tally["floor"][1], sum(tally["floor"]),
             tally["ceil"][1], sum(tally["ceil"])))
    print("MDL STATS floor=%.3f ceil=%.3f headroom=%.2f eye=%.3f "
          "kerb=%.3f..%.3f (%.2f..%.2f above floor) pier=%.2f..%.2f"
          % (m["floor"], m["ceil"], m["ceil"] - m["floor"] - BODY_H,
             m["floor"] + EYE_H, min(m["kerb"]), max(m["kerb"]),
             min(m["kerb"]) - m["floor"], max(m["kerb"]) - m["floor"],
             min(spans), max(spans)))
    for i, w in enumerate(m["wins"]):
        col = [z for b, z in zip(m["bear"], m["kerb"])
               if ((b - w["b0"]) % TAU) <= ((w["b1"] - w["b0"]) % TAU)]
        print("MDL STATS   win%d bearing=%.0f..%.0fdeg visible_sill=%.3f "
              "collider_sill=%.3f..%.3f proud=%+.3f"
              % (i, math.degrees(w["b0"]) % 360.0, math.degrees(w["b1"]) % 360.0,
                 w["lo"], min(col) if col else float("nan"),
                 max(col) if col else float("nan"),
                 (max(col) - w["lo"]) if col else float("nan")))
    return [rock, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=0.0, post=_extra_renders)
