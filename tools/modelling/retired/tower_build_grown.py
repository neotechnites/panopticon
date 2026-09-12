"""tower -- Ryan's TowerRock, continued upward BY HAND and hollowed with booleans.

His body is appended from tower.blend, his old cap is deleted, and the open
boundary loop is EXTRUDED ring by ring with per-vertex noise, so every new face
inherits his own faceting. The room, the ceiling and the eight window mouths are
cut with Boolean modifiers. One manifold rock, one surface, no ring style.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

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
BLEND_PATH = r"C:\dev\panopticon\assets\models\tower.blend"

CAP_Z      = 5.00      # his old cap: every face entirely above this goes
MID_LO     = -0.60     # ...and everything between here and CAP_Z that is not
MID_HI     = 5.00      #    his floor n-gon
WELD       = 0.02
SMOOTH_Z   = -4.50     # his top rings, relaxed in XY to kill the rim bulge
SMOOTH_IT  = 3
SMOOTH_F   = 0.50
CUT_KEEP   = -2.60     # faces above this are deleted; the loop we extrude

STEPS      = 7                 # straight wall
STEP_DZ    = (1.40, 1.60)
STEP_SCALE = 0.985
JIT_R      = 0.18
JIT_Z      = 0.10
WANDER_R   = 0.45              # cap on a vertex's drift from its ring mean
WANDER_Z   = 0.30
ROUND      = ((0.85, 0.95), (0.62, 0.70), (0.34, 0.45))   # (scale, dz)
APEX_DZ    = 0.50

FLOOR_Z    = 0.17      # the room floor: the hollowing cylinder's bottom face
CEIL_Z     = 7.25      # ...and its top face
R_IN       = 7.00      # inner skin == collision radius
NSUB       = 32
SILL_H     = 1.40      # collider lip above the floor; jump apex is 1.11
EYE_H      = 1.65
BODY_H     = 1.80

N_HOLES    = 8
W_HOLE     = 5.20      # tangential, m
H_HOLE     = 5.22      # vertical, m
D_HOLE     = 6.00      # radial, through the wall
HOLE_JIT   = 0.10      # +/- on the radial depth
W_JIT      = 0.04      # ...tighter on width and height, whose ranges are set
H_JIT      = 0.04
SHRINK     = 1.06      # an icosphere is inscribed; widen x to hit the gap spec
Z_HOLE     = (3.20, 3.55)
GAP        = (0.70, 0.88)      # stone between two mouths
GAP_BIG    = 0.97              # ...two of them are at the wide end
HY         = (2.50, 2.72)      # half-height, bounded by the sill and the ceiling
R_WIN_C    = 7.60              # cutter centre radius

DISSOLVE   = 3.0       # degrees
SEED       = 20260913

# Atlas zones as (u0, v0, u1, v1), matching the packed HellRock atlas.
ZONE_ROCK  = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)
ZONE_CARVE = (0.5, 0.0, 1.0, 0.5)
UV_SCALE = 0.13
UV_PAD = 1.5 / 128.0

TAU = 2.0 * math.pi
OPEN_BEARING = 0.0


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

    def sf(self):
        return self.f() * 2.0 - 1.0

    def i(self, a, b):
        return a + (self.n() >> 12) % (b - a + 1)

    def rng(self, span):
        return span[0] + (span[1] - span[0]) * self.f()


def _newell(pts):
    n = Vector((0.0, 0.0, 0.0))
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n.x += (a[1] - b[1]) * (a[2] + b[2])
        n.y += (a[2] - b[2]) * (a[0] + b[0])
        n.z += (a[0] - b[0]) * (a[1] + b[1])
    return n


def _boundary_loops(bm):
    """Every open edge loop, as an ordered vertex ring."""
    bedges = [e for e in bm.edges if e.is_boundary]
    adj = {}
    for e in bedges:
        for v in e.verts:
            adj.setdefault(v, []).append(e)
    seen, loops = set(), []
    for e0 in bedges:
        if e0 in seen:
            continue
        seen.add(e0)
        v0 = e0.verts[0]
        loop, v = [v0], e0.verts[1]
        while v is not v0:
            loop.append(v)
            nxt = [x for x in adj.get(v, []) if x not in seen]
            if not nxt:
                break
            seen.add(nxt[0])
            v = nxt[0].other_vert(v)
        loops.append(loop)
    return loops


def _stats(loop):
    zs = [v.co.z for v in loop]
    rs = [math.hypot(v.co.x, v.co.y) for v in loop]
    return {"n": len(loop), "z0": min(zs), "z1": max(zs), "zm": sum(zs) / len(zs),
            "r0": min(rs), "r1": max(rs), "rm": sum(rs) / len(rs)}


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
    ob.data.calc_loop_triangles()
    zs = [v.co.z for v in ob.data.vertices]
    print("MDL STATS body verts=%d tris=%d z=%.2f..%.2f mat=%s uv=%s tex=[%s]"
          % (len(ob.data.vertices), len(ob.data.loop_triangles),
             min(zs), max(zs), mat.name, uvname, ", ".join(imgs)))
    return ob, mat, uvname


# =============================================================================
# 1..3  STRIP HIS CAP, RELAX THE KNUCKLE, EXTRUDE THE WALL
# =============================================================================

def _strip(bm):
    """His cap and his old room, gone. Returns the counts for the report."""
    cap = [f for f in bm.faces if all(v.co.z > CAP_Z for v in f.verts)]
    if cap:
        bmesh.ops.delete(bm, geom=cap, context="FACES")

    floor_ngon = None
    for f in bm.faces:
        zs = [v.co.z for v in f.verts]
        if len(f.verts) >= 12 and max(zs) - min(zs) < 0.25 \
                and MID_LO < sum(zs) / len(zs) < MID_HI:
            if floor_ngon is None or len(f.verts) > len(floor_ngon.verts):
                floor_ngon = f
    mid = [f for f in bm.faces
           if f is not floor_ngon
           and all(MID_LO < v.co.z < MID_HI for v in f.verts)]
    if mid:
        bmesh.ops.delete(bm, geom=mid, context="FACES")

    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    n0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=WELD)
    return len(cap), len(mid), len(loose), n0 - len(bm.verts), floor_ngon


def _relax(bm):
    """His top rings, smoothed in XY only: the rim bulge eases into the column."""
    vs = [v for v in bm.verts if v.co.z > SMOOTH_Z]
    for _ in range(SMOOTH_IT):
        bmesh.ops.smooth_vert(bm, verts=vs, factor=SMOOTH_F,
                              use_axis_x=True, use_axis_y=True, use_axis_z=False)
    return len(vs)


def _open_top(bm):
    """Delete above CUT_KEEP; cap every other hole; return the rim's edges."""
    doomed = [f for f in bm.faces if f.calc_center_median().z > CUT_KEEP]
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")

    loops = _boundary_loops(bm)
    if not loops:
        raise SystemExit("MDL ERROR: the cut left no open loop to extrude")
    rim = max(loops, key=len)
    filled = 0
    for lp in loops:
        if lp is rim or len(lp) < 3:
            continue
        vs = set(lp)
        edges = [e for e in bm.edges if e.is_boundary
                 and e.verts[0] in vs and e.verts[1] in vs]
        filled += len(bmesh.ops.holes_fill(bm, edges=edges, sides=0).get("faces", []))
    return rim, len(doomed), len(loops) - 1, filled


def _jitter(verts, r, scale, dz):
    """One extruded ring: scaled in, raised, and noised per vertex."""
    pol = []
    for v in verts:
        rr = math.hypot(v.co.x, v.co.y)
        pol.append((math.atan2(v.co.y, v.co.x), rr * scale + JIT_R * r.sf(),
                    v.co.z + dz + JIT_Z * r.sf()))
    rm = sum(p[1] for p in pol) / len(pol)
    zm = sum(p[2] for p in pol) / len(pol)
    for v, (a, rr, zz) in zip(verts, pol):
        rr = min(rm + WANDER_R, max(rm - WANDER_R, rr))
        zz = min(zm + WANDER_Z, max(zm - WANDER_Z, zz))
        v.co = Vector((rr * math.cos(a), rr * math.sin(a), zz))
    return rm, zm


def _grow(bm, r):
    """Extrude the rim upward: straight wall, rounded top, fan to an apex."""
    rings = []
    cur = [v for v in bm.verts if any(e.is_boundary for e in v.link_edges)]
    base_r = sum(math.hypot(v.co.x, v.co.y) for v in cur) / len(cur)

    # never let the wall pinch onto the room: r at the ceiling must clear R_IN
    taper = STEP_SCALE
    want = R_IN + 0.75
    if base_r * taper ** STEPS < want:
        taper = min(1.0, (want / base_r) ** (1.0 / STEPS))

    plan = [(taper, r.rng(STEP_DZ)) for _ in range(STEPS)] + list(ROUND)
    for scale, dz in plan:
        edges = [e for e in bm.edges if e.is_boundary]
        res = bmesh.ops.extrude_edge_only(bm, edges=edges)
        new = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
        rings.append(_jitter(new, r, scale, dz))

    top = [e for e in bm.edges if e.is_boundary]
    tv = set(v for e in top for v in e.verts)
    apex = bm.verts.new((0.22 * r.sf(), 0.22 * r.sf(),
                         max(v.co.z for v in tv) + APEX_DZ))
    for e in top:
        try:
            bm.faces.new((e.verts[0], e.verts[1], apex))
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return rings, base_r, taper, apex.co.z


def _seal(bm):
    """EXACT boolean needs a closed, outward solid. Make it one, and say so."""
    for _ in range(4):
        edges = [e for e in bm.edges if e.is_boundary]
        if not edges:
            break
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    vol = bm.calc_volume(signed=True)
    if vol < 0.0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        bm.normal_update()
    nonman = len([e for e in bm.edges if not e.is_manifold])
    return len([e for e in bm.edges if e.is_boundary]), nonman, vol


# =============================================================================
# 4..5  BOOLEANS -- the room, then the mouths
# =============================================================================

def _tris(ob):
    ob.data.calc_loop_triangles()
    return len(ob.data.loop_triangles)


def _apply_boolean(ob, cutter):
    mod = ob.modifiers.new("cut", "BOOLEAN")
    mod.object = cutter
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    # Without these two the EXACT solver annihilates this mesh: the room is an
    # internal cavity, and a window cut re-opens it. Non-negotiable here.
    for flag in ("use_self", "use_hole_tolerant"):
        try:
            setattr(mod, flag, True)
        except Exception:
            pass
    for o in bpy.context.selected_objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def _volume(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    v = bm.calc_volume(signed=True)
    nm = len([e for e in bm.edges if not e.is_manifold])
    bm.free()
    return v, nm


def _hollow(ob):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=NSUB, radius=R_IN, depth=CEIL_Z - FLOOR_Z,
        location=(0.0, 0.0, 0.5 * (FLOOR_Z + CEIL_Z)))
    _apply_boolean(ob, bpy.context.active_object)


def _wall_radius(ob, z0, z1):
    zs = [(math.hypot(v.co.x, v.co.y)) for v in ob.data.vertices if z0 < v.co.z < z1]
    return sum(zs) / max(1, len(zs))


def _plan_holes(r, r_wall):
    """Eight mouths on irregular bearings, sized so the piers hit the spec."""
    circ = TAU * r_wall
    gaps = [r.rng(GAP) for _ in range(N_HOLES)]
    for k in (r.i(0, N_HOLES // 2 - 1), r.i(N_HOLES // 2, N_HOLES - 1)):
        gaps[k] = GAP_BIG + 0.08 * r.sf()
    hx = [0.5 * W_HOLE * SHRINK * (1.0 + W_JIT * r.sf()) for _ in range(N_HOLES)]
    k = (circ - sum(gaps)) / (2.0 * sum(hx))
    hx = [h * k for h in hx]

    holes, b = [], 0.0
    for i in range(N_HOLES):
        hy = min(HY[1], max(HY[0], 0.5 * H_HOLE * (1.0 + H_JIT * r.sf())))
        hz = 0.5 * D_HOLE * (1.0 + HOLE_JIT * r.sf())
        cz = r.rng(Z_HOLE)
        cz = max(cz, FLOOR_Z + SILL_H + hy + 0.02)
        cz = min(cz, CEIL_Z - 0.20 - hy)
        b += hx[i] / r_wall
        holes.append({"b": b, "hx": hx[i], "hy": hy, "hz": hz, "cz": cz,
                      "half": hx[i] / r_wall, "gap": gaps[i]})
        b += hx[i] / r_wall + gaps[i] / r_wall
    return holes, gaps, circ


def _punch(ob, holes):
    for h in holes:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1.0)
        cut = bpy.context.active_object
        b = h["b"]
        sb, cb = math.sin(b), math.cos(b)
        cut.matrix_world = Matrix((
            (-sb * h["hx"], 0.0, cb * h["hz"], R_WIN_C * cb),
            (cb * h["hx"], 0.0, sb * h["hz"], R_WIN_C * sb),
            (0.0, h["hy"], 0.0, h["cz"]),
            (0.0, 0.0, 0.0, 1.0)))
        n0 = _tris(ob)
        _apply_boolean(ob, cut)
        h["dt"] = _tris(ob) - n0


# =============================================================================
# 6  CLEAN
# =============================================================================

def _clean(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    edges = [e for e in bm.edges if all(v.co.z > CUT_KEEP for v in e.verts)]
    verts = [v for v in bm.verts if v.co.z > CUT_KEEP]
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(DISSOLVE),
                             verts=verts, edges=edges)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def _sample_normals(ob, r_wall):
    """Outward on the outside, inward in the room. Counted, not assumed."""
    me = ob.data
    tally = {"inner": [0, 0], "outer": [0, 0], "floor": [0, 0], "ceil": [0, 0]}
    for p in me.polygons:
        c, n = p.center, p.normal
        rr = math.hypot(c.x, c.y)
        rad = Vector((c.x, c.y, 0.0))
        rad = rad.normalized() if rad.length > 1e-6 else Vector((1.0, 0.0, 0.0))
        d = n.dot(rad)
        if abs(n.z) < 0.5 and abs(d) > 0.6 and FLOOR_Z + 0.4 < c.z < CEIL_Z - 0.4:
            if rr < R_IN + 0.25:
                tally["inner"][d < 0.0] += 1
            elif rr > r_wall - 0.45:
                tally["outer"][d > 0.0] += 1
        elif rr < R_IN - 0.4 and abs(c.z - FLOOR_Z) < 0.08:
            tally["floor"][n.z > 0.0] += 1
        elif rr < R_IN - 0.4 and abs(c.z - CEIL_Z) < 0.08:
            tally["ceil"][n.z < 0.0] += 1
    return tally


# =============================================================================
# 7  COLLIDER -- floor, a sill all round, a pier per gap, a ceiling
# =============================================================================

def _collider(holes):
    verts, faces = [], []
    sill_z = FLOOR_Z + SILL_H

    def v(p):
        verts.append(tuple(p))
        return len(verts) - 1

    def pt(b, z):
        return (R_IN * math.cos(b), R_IN * math.sin(b), z)

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

    bear = [TAU * i / NSUB for i in range(NSUB)]
    floor = [v(pt(b, FLOOR_Z)) for b in bear]
    for i in range(1, NSUB - 1):
        emit([floor[0], floor[i], floor[i + 1]], (0.0, 0.0, 1.0))
    sill = [v(pt(b, sill_z)) for b in bear]
    for i in range(NSUB):
        j = (i + 1) % NSUB
        emit([floor[i], floor[j], sill[j], sill[i]],
             rad(bear[i] + 0.5 * TAU / NSUB))

    piers = []
    for i, h in enumerate(holes):
        nxt = holes[(i + 1) % N_HOLES]
        b0 = h["b"] + h["half"]
        b1 = nxt["b"] - nxt["half"]
        span = (b1 - b0) % TAU
        piers.append(span * R_IN)
        q = [v(pt(b0, sill_z)), v(pt(b0 + span, sill_z)),
             v(pt(b0 + span, CEIL_Z)), v(pt(b0, CEIL_Z))]
        emit(q, rad(b0 + 0.5 * span))

    ceil = [v(pt(b, CEIL_Z)) for b in bear]
    for i in range(1, NSUB - 1):
        emit([ceil[0], ceil[i], ceil[i + 1]], (0.0, 0.0, -1.0))
    return mdl.mesh(COLLIDER_NAME, verts, faces), piers


# =============================================================================
# 8  UV -- per-face planar projection into that face's zone of the packed atlas
# =============================================================================

def _zone(c, n):
    rad = Vector((c.x, c.y, 0.0))
    d = n.dot(rad.normalized()) if rad.length > 1e-6 else 0.0
    if n.z > 0.55:
        return ZONE_ROCK if c.z > CEIL_Z else ZONE_SHADE
    if n.z < -0.55:
        return ZONE_SHADE
    if d > 0.15:
        return ZONE_ROCK
    if d < -0.15:
        return ZONE_SHADE
    return ZONE_CARVE


def unwrap(ob, name):
    """Everything above CUT_KEEP is ours; below it his own atlas UVs stand."""
    me = ob.data
    uvl = me.uv_layers.get(name)
    if uvl is None:
        print("MDL note: UV layer %r did not survive; his atlas is lost" % name)
        uvl = me.uv_layers.new(name=name)
    r = _Rng(SEED + len(me.polygons))
    done = 0
    for poly in me.polygons:
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        if max(c.z for c in cos) <= CUT_KEEP:
            continue
        done += 1
        u0, v0, u1, v1 = _zone(poly.center, poly.normal)
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


# =============================================================================
# EXTRA RENDER -- the room from inside, which is where the normals show
# =============================================================================

def _extra_renders(spec, objects):
    scene = bpy.context.scene
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

    ux, uy = math.cos(OPEN_BEARING), math.sin(OPEN_BEARING)
    fl = bpy.data.lights.new("RoomFill", type="POINT")
    fl.energy = 900.0
    fl.color = (1.0, 0.55, 0.40)
    lamp = mdl._link(bpy.data.objects.new("RoomFill", fl))
    lamp.location = (-ux * 1.8, -uy * 1.8, 2.6)

    cam.data.lens = 18.0
    cam.location = (-ux * 4.6, -uy * 4.6, FLOOR_Z + EYE_H)
    target.location = (ux * 24.0, uy * 24.0, FLOOR_Z + 2.3)
    scene.render.resolution_x, scene.render.resolution_y = 1000, 760
    bpy.context.view_layer.update()
    scene.render.filepath = os.path.join(spec.get("out_dir", "."), "%s_room.png" % NAME)
    bpy.ops.render.render(write_still=True)
    print("MDL RENDER %s_room.png (hand-placed camera)" % NAME)
    lamp.data.energy = 0.0

    # The rock is 45 m deep, so mdl's auto-fit renders the head as a speck.
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
    global OPEN_BEARING
    rock, mat, uvname = _append_rock()
    r = _Rng(SEED)

    bm = bmesh.new()
    bm.from_mesh(rock.data)

    n_cap, n_mid, n_loose, n_weld, fl = _strip(bm)
    print("MDL STATS cap_faces=%d mid_faces=%d loose=%d welded=%d floor_ngon=%s"
          % (n_cap, n_mid, n_loose, n_weld,
             ("%d-gon @ z%.2f" % (len(fl.verts),
                                  sum(v.co.z for v in fl.verts) / len(fl.verts)))
             if fl else "none"))

    n_sm = _relax(bm)
    rim, n_del, n_strays, n_fill = _open_top(bm)
    st = _stats(rim)
    print("MDL STATS smoothed=%d cut_faces=%d strays=%d stray_faces=%d"
          % (n_sm, n_del, n_strays, n_fill))
    print("MDL STATS loop n=%d z=%.2f..%.2f (mean %.2f) r=%.2f..%.2f (mean %.2f)"
          % (st["n"], st["z0"], st["z1"], st["zm"], st["r0"], st["r1"], st["rm"]))

    rings, base_r, taper, apex_z = _grow(bm, r)
    n_open, n_nonman, vol = _seal(bm)
    print("MDL STATS sealed open_edges=%d non_manifold=%d volume=%.1f" %
          (n_open, n_nonman, vol))
    bm.to_mesh(rock.data)
    bm.free()
    rock.data.update()
    print("MDL STATS rings=%d base_r=%.2f taper=%.4f apex_z=%.2f means=%s"
          % (len(rings), base_r, taper, apex_z,
             ",".join("%.2f@%.2f" % (m, z) for m, z in rings)))

    print("MDL STATS grown_tris=%d" % _tris(rock))
    _hollow(rock)
    _hv, _hn = _volume(rock)
    print("MDL STATS hollow_tris=%d volume=%.1f non_manifold=%d"
          % (_tris(rock), _hv, _hn))
    r_wall = _wall_radius(rock, 2.0, 5.0)
    holes, gaps, circ = _plan_holes(r, r_wall)
    _punch(rock, holes)
    print("MDL STATS punched_tris=%d per_hole=%s"
          % (_tris(rock), ",".join(str(h["dt"]) for h in holes)))
    _clean(rock)
    print("MDL STATS cleaned_tris=%d" % _tris(rock))

    rock.name = OBJECT_NAME
    rock.data.name = OBJECT_NAME
    n_uv = unwrap(rock, uvname)
    mdl.finish(rock, mat, flat=True, strip_uvs=False)

    coll_ob, piers = _collider(holes)
    coll_ob.hide_render = True
    OPEN_BEARING = holes[0]["b"]

    tally = _sample_normals(rock, r_wall)
    rock.data.calc_loop_triangles()
    coll_ob.data.calc_loop_triangles()
    open_w = sum(2.0 * h["hx"] for h in holes)
    sills = [h["cz"] - h["hy"] - FLOOR_Z for h in holes]
    heads = [h["cz"] + h["hy"] for h in holes]
    print("MDL STATS visual_tris=%d collision_tris=%d uv_faces=%d r_wall=%.2f"
          % (len(rock.data.loop_triangles), len(coll_ob.data.loop_triangles),
             n_uv, r_wall))
    print("MDL STATS holes=%d w=%.2f..%.2f h=%.2f..%.2f circ=%.1f open=%.1f%%"
          % (N_HOLES, min(2 * h["hx"] for h in holes),
             max(2 * h["hx"] for h in holes),
             min(2 * h["hy"] for h in holes), max(2 * h["hy"] for h in holes),
             circ, 100.0 * open_w / circ))
    print("MDL STATS sill=%.2f..%.2f head=%.2f..%.2f pier=%.2f..%.2f gap=%.2f..%.2f"
          % (min(sills), max(sills), min(heads), max(heads),
             min(piers), max(piers), min(gaps), max(gaps)))
    print("MDL STATS normals inner=%d/%d outer=%d/%d floor=%d/%d ceil=%d/%d "
          "(good/total)"
          % (tally["inner"][1], sum(tally["inner"]),
             tally["outer"][1], sum(tally["outer"]),
             tally["floor"][1], sum(tally["floor"]),
             tally["ceil"][1], sum(tally["ceil"])))
    print("MDL STATS floor=%.2f ceil=%.2f headroom=%.2f eye=%.2f jump_clear=%.2f"
          % (FLOOR_Z, CEIL_Z, CEIL_Z - FLOOR_Z - BODY_H, FLOOR_Z + EYE_H,
             min(sills) - 1.11))
    return [rock, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=0.0, post=_extra_renders)
