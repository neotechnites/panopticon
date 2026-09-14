"""tower_hollow -- the arches tower cut open for the hub: shaft, door, stairwell.

tower_arches_build.py builds the drum exactly as shipped; this then cuts it so
tower_interior.glb (drawn inside, at identity) can be walked:

    shaft ..... hollowed to the interior lining's facets + CLEAR, foot to shaft ceiling
    door ...... the arched passage from the lining out through the rock's face
    throat .... the raked soffit under the room floor over the last flight
    hole ...... the stairwell through the room floor; the floor collider loses it too

The interior's plan is recomputed with tower_interior_build.py on its own survey
of tower_new.blend, so every cut follows the shipped lining. Every cutter is
the interior surface pushed CLEAR outward along its normals: no z-fight. The
door passage IS the rock's cut (the interior draws only a reveal), its floor
flush with the courtyard. The collider carries every cut face as well as the
room. tower.glb and tower_arches.glb are never touched.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, HERE + os.sep + "lib")

import mdl  # noqa: E402
import tower_arches_build as ta  # noqa: E402
import tower_interior_build as ti  # noqa: E402

mdl.DEFAULTS["ground"] = False
mdl.DEFAULTS["world_grey"] = 0.30
mdl.DEFAULTS["world_strength"] = 0.90

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "tower_hollow"
OBJECT_NAME = ta.OBJECT_NAME
COLLIDER_NAME = ta.COLLIDER_NAME

CLEAR       = 0.05     # rock cut this far outside every interior surface
CLEAR_R     = CLEAR / math.cos(math.pi / ti.NS)   # facets are chords: CLEAR at mid-facet
FLOOR_BELOW = 0.08     # shaft cut this far under the interior's floor (its dish dips 0.06)
DOOR_IN     = 1.0      # door cutter reaches this far into the shaft past the lining
DOOR_OUT    = 1.5      # ...and this far past the rock's face
DOOR_FLOOR  = -0.02    # passage floor this far under the courtyard: the courtyard is the floor
CUT_EPS     = 0.012    # a rock face this close to a cutter's surface is a cut face
THROAT_STEP = 0.15     # metres of stair between throat cutter sections
THROAT_OVERLAP = 0.35  # throat cutter runs this far into the hole's span
HOLE_STEP   = 1.5      # degrees between hole cutter sections
FLOOR_CAP   = 0.03     # rock left between the throat soffit cut and the room floor
HOLE_ABOVE  = 0.12     # hole cutter tops out this far above the room floor
WALL_NB     = 72       # bearings in the wall-thickness survey

NSUB = ta.NSUB
TAU = ta.TAU
EYE_H = ta.EYE_H

PLAN = {}


# =============================================================================
# 1  THE INTERIOR'S PLAN -- its own survey, its own code, its own rock copy
# =============================================================================

def _interior_plan():
    rock = ti._append_rock()
    sv = ti.Survey(rock)
    sv.report()
    p = ti.make_plan(sv)
    me = rock.data
    bpy.data.objects.remove(rock, do_unlink=True)
    bpy.data.meshes.remove(me)

    # the lining's facet grid (p.pin) and the door's arch outline, off the
    # very calls that draw them
    m = ti._Mesh()
    ti._wall(m, p, ti._Rng(ti.SEED), sv)
    ti._door(m, p, sv)
    return sv, p, [m.verts[i] for i in p.door_outline_in]


def _ring_index(p, z):
    for k, zk in enumerate(p.Z):
        if abs(zk - z) < 1e-3:
            return k
    raise SystemExit("MDL ERROR: no lining ring at z=%.3f" % z)


def _facet_r(p, theta, k):
    """Radius of lining ring k's chord at this bearing."""
    a = (math.degrees(theta) % 360.0 - ti.ANG_OFF) / (360.0 / ti.NS)
    j = int(math.floor(a)) % ti.NS
    P0, P1 = p.pin[(j, k)], p.pin[((j + 1) % ti.NS, k)]
    u = (math.cos(theta), math.sin(theta))
    D = (P1[0] - P0[0], P1[1] - P0[1])
    den = D[0] * u[1] - D[1] * u[0]
    if abs(den) < 1e-9:
        return math.hypot(P0[0], P0[1])
    t = min(1.0, max(0.0, -(P0[0] * u[1] - P0[1] * u[0]) / den))
    return (P0[0] + t * D[0]) * u[0] + (P0[1] + t * D[1]) * u[1]


# =============================================================================
# 2  CUTTERS -- a closed loft through rings, pushed CLEAR out along its normals
# =============================================================================

def _offset_shell(rings, name, push=CLEAR_R):
    verts, faces = [], []
    n = len(rings[0])
    for ring in rings:
        verts.extend(ring)
    for i in range(len(rings) - 1):
        b0, b1 = i * n, (i + 1) * n
        for a in range(n):
            b = (a + 1) % n
            faces.append((b0 + a, b0 + b, b1 + b, b1 + a))
    faces.append(tuple(reversed(range(n))))
    faces.append(tuple(range((len(rings) - 1) * n, len(rings) * n)))
    ob = ta._solid(name, verts, faces)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * push
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return ob


def _shaft_cutter(p, k_c):
    rings = []
    for k in range(k_c + 1):
        ring = []
        for j in range(ti.NS):
            x, y, z = p.pin[(j, k)]
            if k == 0:
                z = ti.FOOT_Z - FLOOR_BELOW
            elif k == k_c:
                z = p.z_c + 0.02
            ring.append((x, y, z))
        rings.append(ring)
    return _offset_shell(rings, "ShaftCutter")


def _sector(theta, r_i, r_o, z_lo, z_hi):
    c, s = math.cos(theta), math.sin(theta)
    return [(r_i * c, r_i * s, z_lo), (r_o * c, r_o * s, z_lo),
            (r_o * c, r_o * s, z_hi), (r_i * c, r_i * s, z_hi)]


def _throat_cutter(p, k_c, floor_lo):
    cap = floor_lo - FLOOR_CAP - CLEAR_R
    z_lo = p.z_c - 0.02

    def h_of(s):
        return min(p.nose(s) + ti.HEADROOM, p.z_floor - 0.05)

    rings = []
    s = p.s_throat - 0.3
    s_end = p.s_h0 + THROAT_OVERLAP
    while True:
        th = p.theta(s)
        r_o = max(_facet_r(p, th, k_c), _facet_r(p, th, k_c + 1))
        z_hi = max(min(h_of(s), cap), z_lo + 0.06)
        rings.append(_sector(th, p.r_cd, r_o, z_lo, z_hi))
        if s >= s_end:
            break
        s = min(s + THROAT_STEP, s_end)
    return _offset_shell(rings, "ThroatCutter")


def _hole_cutter(p, k_c, hole, floor_hi):
    z_lo, z_hi = p.z_c - 0.02, floor_hi + HOLE_ABOVE
    n = max(2, int(math.ceil(math.degrees(hole["t1"] - hole["t0"]) / HOLE_STEP)) + 1)
    rings = []
    for i in range(n):
        th = hole["t0"] + (hole["t1"] - hole["t0"]) * i / (n - 1)
        r_o = max(_facet_r(p, th, k_c), _facet_r(p, th, k_c + 1))
        rings.append(_sector(th, p.r_cd, r_o, z_lo, z_hi))
    return _offset_shell(rings, "HoleCutter")


def _door_cutter(outline, p):
    """The arch outline swept straight out through the rock's face; the floor
    edge is not pushed down, so the passage floor meets the courtyard flush."""
    d = ti._radial(math.radians(ti.DOOR_BEARING))

    def shifted(ring, along):
        return [(x + d[0] * along, y + d[1] * along, z) for (x, y, z) in ring]

    reach = p.door["x_rock"] + DOOR_OUT - min(x * d[0] + y * d[1] for (x, y, _z) in outline)
    ob = _offset_shell([shifted(outline, -DOOR_IN), outline, shifted(outline, reach)], "DoorCutter")
    for v in ob.data.vertices:
        if v.co.z < ti.FOOT_Z + 0.03:
            v.co.z = ti.FOOT_Z + DOOR_FLOOR
    ob.data.update()
    return ob


def _cut(ob, cutter, label, min_frac, defects):
    """Boolean DIFFERENCE, plain solver first, tolerant second; loud if both fail.
    Returns the cutter's surface as a BVH, to find the faces it left behind."""
    keep = ob.data.copy()
    surface = ti._bvh(cutter)
    v0, n0 = ta._volume(ob), ta._tris(ob)
    vc = abs(ta._volume(cutter))
    ok = False
    for tol in (False, True):
        mod = ob.modifiers.new("bool", "BOOLEAN")
        mod.object = cutter
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        for flag in ("use_self", "use_hole_tolerant"):
            try:
                setattr(mod, flag, tol)
            except Exception:
                pass
        for o in bpy.context.selected_objects:
            o.select_set(False)
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        ob.data.update()
        v1, n1 = ta._volume(ob), ta._tris(ob)
        bo, nm = ta._shell(ob)
        removed = v0 - v1
        ok = (n1 > 0.3 * n0 and removed >= min_frac * vc and removed <= 1.02 * vc + 1.0
              and bo <= defects[0] and nm <= defects[1])
        print("MDL STATS cut %s tris %d->%d removed=%.1fm3 of cutter %.1fm3 "
              "open_edges=%d non_manifold=%d %s"
              % (label, n0, n1, removed, vc, bo, nm, "ok" if ok else "BAD"))
        if ok:
            break
        print("MDL WARN %s cut came back wrong; retrying tolerant" % label)
        old = ob.data
        ob.data = keep.copy()
        bpy.data.meshes.remove(old)
    bpy.data.meshes.remove(keep)
    bpy.data.objects.remove(cutter, do_unlink=True)
    ob.data.update()
    if not ok:
        raise SystemExit("MDL ERROR: %s cut failed twice" % label)
    return surface


def _cut_faces(rock, surfaces):
    """(verts, tris) of every rock face lying on one of the cutters' surfaces."""
    me = rock.data
    verts, faces, remap = [], [], {}
    for poly in me.polygons:
        c = poly.center
        on = False
        for bvh in surfaces:
            hit = bvh.find_nearest(c, CUT_EPS)
            if hit[0] is not None:
                on = True
                break
        if not on:
            continue
        idx = []
        for vi in poly.vertices:
            if vi not in remap:
                remap[vi] = len(verts)
                verts.append(tuple(me.vertices[vi].co))
            idx.append(remap[vi])
        faces.append(tuple(idx))
    return verts, faces


# =============================================================================
# 3  MEASURE -- his room floor over the hole, and the rock left round the shaft
# =============================================================================

def _floor_over_hole(rock, p, hole):
    probe = ta.Probe(rock)
    zs = []
    th_a = p.theta(p.s_throat)
    span = (hole["t1"] - th_a) % TAU
    n = max(4, int(math.ceil(math.degrees(span) / 2.0)))
    for i in range(n + 1):
        th = th_a + span * i / n
        for rr in (p.r_cd - 0.3, p.r_cd, 0.5 * (p.r_cd + p.R_top), p.R_top, p.R_top + 0.2):
            z = probe.down(rr * math.cos(th), rr * math.sin(th), p.z_floor + 1.5)
            if z is not None and abs(z - p.z_floor) < 1.0:
                zs.append(z)
    if not zs:
        raise SystemExit("MDL ERROR: no room floor found over the stairwell")
    return min(zs), max(zs)


def _wall_survey(rock, p):
    bvh = ti._bvh(rock)
    worst = None
    z = ti.FOOT_Z + 0.5
    while z < p.z_c - 0.2:
        for i in range(WALL_NB):
            a = TAU * i / WALL_NB
            ts = ti._crossings(bvh, (0.0, 0.0, z), (math.cos(a), math.sin(a), 0.0), 60.0)
            if len(ts) < 2 or len(ts) % 2:
                continue
            th = sum(ts[i + 1] - ts[i] for i in range(0, len(ts), 2))
            if worst is None or th < worst[0]:
                worst = (th, a, z, ts[0], ts[-1])
        z += 1.0
    return worst


# =============================================================================
# 4  COLLIDER -- as tower_arches, the floor fan minus the stairwell
# =============================================================================

def _collider(m, plan, hole, cut):
    verts, faces = list(cut[0]), list(cut[1])

    def v(pt):
        verts.append(tuple(pt))
        return len(verts) - 1

    def emit(idx, want):
        pts = [verts[k] for k in idx]
        if ta._newell(pts).dot(Vector(want)) < 0.0:
            idx = list(reversed(idx))
        if len(idx) == 4:
            faces.append((idx[0], idx[1], idx[2]))
            faces.append((idx[0], idx[2], idx[3]))
        else:
            faces.append(tuple(idx))

    def rad(a):
        return (-math.cos(a), -math.sin(a), 0.0)

    r_in, ceil_z, f_axis = m["r_in"], m["ceil"], m["f_axis"]
    bear, f_ring = m["bear"], m["f_ring"]
    sill_z = plan["sill"]
    t0, span = hole["t0"] % TAU, (hole["t1"] - hole["t0"]) % TAU

    def floor_z(b):
        x = (b % TAU) / TAU * NSUB
        i = int(math.floor(x)) % NSUB
        return f_ring[i] + (f_ring[(i + 1) % NSUB] - f_ring[i]) * (x - math.floor(x))

    def at(b, rr):
        return (rr * math.cos(b), rr * math.sin(b), f_axis + (floor_z(b) - f_axis) * rr / r_in)

    bs = sorted(set([b % TAU for b in bear] + [t0, (t0 + span) % TAU]))
    hub = v((0.0, 0.0, f_axis))
    ring = [v(at(b, r_in)) for b in bs]
    up = (0.0, 0.0, 1.0)
    for i in range(len(bs)):
        j = (i + 1) % len(bs)
        b0, b1 = bs[i], bs[j]
        db = (b1 - b0) % TAU
        if (b0 + 0.5 * db - t0) % TAU < span:
            # the fan stops at the hole's inner edge; a strip of his floor stays
            # between the hole's outer edge and the wall
            emit([hub, v(at(b0, hole["r_in"])), v(at(b1, hole["r_in"]))], up)
            emit([v(at(b0, hole["r_out"](b0))), v(at(b1, hole["r_out"](b1))),
                  ring[j], ring[i]], up)
        else:
            emit([hub, ring[i], ring[j]], up)

    sill = [v((r_in * math.cos(b), r_in * math.sin(b), sill_z)) for b in bs]
    for i in range(len(bs)):
        j = (i + 1) % len(bs)
        emit([ring[i], ring[j], sill[j], sill[i]], rad(bs[i] + 0.5 * ((bs[j] - bs[i]) % TAU)))

    arches = sorted(plan["bear"])
    half = plan["half_in"]
    for k in range(len(arches)):
        a0 = arches[k] + half
        sp = (arches[(k + 1) % len(arches)] - half - a0) % TAU
        q = [v((r_in * math.cos(a0), r_in * math.sin(a0), sill_z)),
             v((r_in * math.cos(a0 + sp), r_in * math.sin(a0 + sp), sill_z)),
             v((r_in * math.cos(a0 + sp), r_in * math.sin(a0 + sp), ceil_z)),
             v((r_in * math.cos(a0), r_in * math.sin(a0), ceil_z))]
        emit(q, rad(a0 + 0.5 * sp))

    ceil = [v((r_in * math.cos(b), r_in * math.sin(b), ceil_z)) for b in bear]
    hub2 = v((0.0, 0.0, ceil_z))
    for i in range(NSUB):
        emit([hub2, ceil[i], ceil[(i + 1) % NSUB]], (0.0, 0.0, -1.0))
    return mdl.mesh(COLLIDER_NAME, verts, faces)


# =============================================================================
# EXTRA RENDERS -- the door with the interior behind it, the room from the
# stairwell, and a section through the door and the shaft
# =============================================================================

def _extra_renders(spec, objects):
    p, sv = PLAN["p"], PLAN["sv"]
    rock = objects[0]
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 48)))
    mdl._try(scene.eevee, "use_shadows", True)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")
    world = bpy.data.worlds.new("Hell")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.34, 0.11, 0.08, 1.0)
    bg.inputs[1].default_value = 0.55

    # the interior, drawn for the camera only: never exported from here
    m = ti._Mesh()
    r = ti._Rng(ti.SEED)
    ti._wall(m, p, r, sv)
    ti._door(m, p, sv)
    ti._flight(m, p)
    ti._ceiling(m, p)
    ti._floor(m, p, r)
    ti._chamber(m, p)
    ti._drips(m, p, r)
    albedo, emissive = ti.build_texture()
    interior = m.object("InteriorPreview")
    ti.unwrap(interior, m.zones)
    mdl.finish(interior, ti.rock_material("HellRockPreview", albedo, emissive),
               strip_uvs=False)
    culled = [(mat, mat.use_backface_culling) for mat in rock.data.materials if mat]
    for mat, _ in culled:
        mat.use_backface_culling = True

    target = mdl._link(bpy.data.objects.new("InTarget", None))
    cam = mdl._link(bpy.data.objects.new("InCam", bpy.data.cameras.new("InCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    cam.data.clip_end = 400.0

    lamps = []

    def lamp(loc, energy, size=0.8):
        ld = bpy.data.lights.new("Fill", type="POINT")
        ld.energy = energy
        ld.color = (1.0, 0.55, 0.40)
        ld.shadow_soft_size = size
        lo = mdl._link(bpy.data.objects.new("Fill", ld))
        lo.location = loc
        lamps.append(lo)
        return lo

    for z in (ti.FOOT_Z + 3.0, ti.FOOT_Z + 12.0, ti.FOOT_Z + 21.0, ti.FOOT_Z + 30.0, p.z_c - 2.0):
        lamp((0.0, 0.0, z), 5200.0)
    d = ti._radial(math.radians(ti.DOOR_BEARING))
    lamp((d[0] * (p.door["x_rock"] + 2.5), d[1] * (p.door["x_rock"] + 2.5) + 1.5, ti.FOOT_Z + 2.4), 900.0)
    lamp((d[0] * (p.door["x_rock"] - 3.0), d[1] * (p.door["x_rock"] - 3.0), ti.FOOT_Z + 1.9), 300.0)
    tw = p.theta(p.s_top - 1.5)
    lamp(((p.R_top - 2.6) * math.cos(tw), (p.R_top - 2.6) * math.sin(tw), p.z_floor + 1.6), 1200.0)
    lamp((0.0, 0.0, p.z_floor + 3.2), 1600.0)

    out = spec.get("out_dir", ".")

    def shot(tag, loc, aim, lens, res):
        cam.data.lens = lens
        cam.location = loc
        target.location = aim
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(out, "%s_%s.png" % (NAME, tag))
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s_%s.png (hand-placed)" % (NAME, tag))

    def on_stair(s, up=EYE_H):
        th = p.theta(s)
        rc = p.rc_of(p.nose(s))
        return (rc * math.cos(th), rc * math.sin(th), p.nose(s) + up)

    shot("door", (d[0] * (p.door["x_rock"] + 3.5), d[1] * (p.door["x_rock"] + 3.5) + 0.4,
                  ti.FOOT_Z + EYE_H),
         (d[0] * (p.door["R"] - 2.5), d[1] * (p.door["R"] - 2.5), ti.FOOT_Z + 1.3),
         24.0, (1000, 760))
    te = p.th_end
    shot("room", on_stair(p.s_top - 0.8), (2.4 * math.cos(te), 2.4 * math.sin(te), p.z_floor + 0.5),
         16.0, (1000, 760))

    # the section: both meshes bisected on the door's plane, the +y half dropped,
    # so the passage is cut lengthways and the stairwell sits straight ahead
    keep = []
    for src in (rock, interior):
        dup = src.copy()
        dup.data = src.data.copy()
        mdl._link(dup)
        bm = bmesh.new()
        bm.from_mesh(dup.data)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                               dist=1e-4, plane_co=(0.0, 0.0, 0.0),
                               plane_no=(0.0, 1.0, 0.0), clear_outer=True,
                               clear_inner=False)
        bm.to_mesh(dup.data)
        bm.free()
        for mat in dup.data.materials:
            if mat:
                mat.use_backface_culling = False
        src.hide_render = True
        keep.append(dup)
    for lo in lamps:
        lo.location = (lo.location.x, lo.location.y - 2.5, lo.location.z)
        lo.data.energy *= 1.6
    zc = 0.5 * (ti.FOOT_Z + p.z_floor)
    shot("cut", (0.0, 62.0, zc + 2.0), (0.0, 0.0, zc), 40.0, (820, 1400))

    for dup in keep:
        bpy.data.objects.remove(dup, do_unlink=True)
    rock.hide_render = False
    for mat, was in culled:
        mat.use_backface_culling = was
    bpy.data.objects.remove(interior, do_unlink=True)
    for ob in [cam, target] + lamps:
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    rock, old_coll = ta.build()
    old_me = old_coll.data
    bpy.data.objects.remove(old_coll, do_unlink=True)
    bpy.data.meshes.remove(old_me)
    m = ta.MEAS
    plan = ta._arch_plan(m)
    mat = rock.data.materials[0]
    uvname = rock.data.uv_layers[0].name
    culling = mat.use_backface_culling

    sv, p, door_outline = _interior_plan()
    k_c = _ring_index(p, p.z_c)
    # The opening through the floor starts where the throat's soffit reaches
    # the floor, not at the interior's nominal hole: a capsule's head meets the
    # floor plane 2.6 m of stair before that, and a body overlapping a
    # collider face from below is stuck in GodotPhysics.
    s_open = p.s_of_nose(p.z_floor - 0.05 - ti.HEADROOM)
    hole = {"t0": p.theta(s_open) - CLEAR / p.r_cd, "t1": p.th_end + CLEAR / p.r_cd,
            "r_in": p.r_cd - CLEAR,
            "r_out": lambda b: max(_facet_r(p, b, k_c), _facet_r(p, b, k_c + 1)) + CLEAR_R}
    floor_lo, floor_hi = _floor_over_hole(rock, p, hole)
    print("MDL STATS his floor over the stairwell %.3f..%.3f (interior z_floor=%.3f) "
          "shaft ceiling=%.3f lining top ring k=%d" % (floor_lo, floor_hi, p.z_floor, p.z_c, k_c))
    if floor_hi - floor_lo > 0.30:
        print("MDL WARN his floor is uneven over the stairwell: %.2f m" % (floor_hi - floor_lo))

    defects = ta._shell(rock)
    surfaces = [_cut(rock, _shaft_cutter(p, k_c), "shaft", 0.85, defects),
                _cut(rock, _throat_cutter(p, k_c, floor_lo), "throat", 0.5, defects),
                _cut(rock, _hole_cutter(p, k_c, hole, floor_hi), "hole", 0.15, defects),
                _cut(rock, _door_cutter(door_outline, p), "door", 0.4, defects)]

    n0 = ta._tris(rock)
    bm = bmesh.new()
    bm.from_mesh(rock.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1.0e-4)
    bmesh.ops.dissolve_degenerate(bm, dist=ta.DEGEN, edges=list(bm.edges))
    lo = m["floor"] - 1.5
    verts = [v for v in bm.verts if v.co.z > lo]
    edges = [e for e in bm.edges if all(v.co.z > lo for v in e.verts)]
    try:
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(ta.DISSOLVE),
                                 verts=verts, edges=edges, delimit={"UV"})
    except Exception as exc:
        print("MDL note: dissolve skipped (%s)" % exc)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    bm.to_mesh(rock.data)
    bm.free()
    rock.name = OBJECT_NAME
    rock.data.name = OBJECT_NAME
    rock.data.update()
    print("MDL STATS dissolved tris %d -> %d" % (n0, ta._tris(rock)))

    n_uv = ta.unwrap(rock, uvname)
    mdl.finish(rock, mat, flat=True, strip_uvs=False)
    mat.use_backface_culling = culling

    cut = _cut_faces(rock, surfaces)
    coll_ob = _collider(m, plan, hole, cut)
    coll_ob.hide_render = True
    print("MDL STATS collider cut_faces=%d of %d rock faces" % (len(cut[1]), len(rock.data.polygons)))
    coll_ob.data.calc_loop_triangles()
    PLAN.update({"p": p, "sv": sv})

    bo, nm = ta._shell(rock)
    print("MDL STATS visual_tris=%d collision_tris=%d reuv_faces=%d open_edges=%d "
          "non_manifold=%d" % (ta._tris(rock), len(coll_ob.data.loop_triangles), n_uv, bo, nm))
    worst = _wall_survey(rock, p)
    if worst:
        print("MDL STATS wall min=%.2fm rock along the ray at bearing=%.0fdeg z=%.1f (r %.2f..%.2f); "
              "slab over the throat >= %.2fm; rock under the passage floor %.2fm"
              % (worst[0], math.degrees(worst[1]) % 360.0, worst[2], worst[3], worst[4],
                 FLOOR_CAP, (ti.FOOT_Z - FLOOR_BELOW - CLEAR_R) - sv.z_min))
    corners = []
    for t in (hole["t0"], hole["t1"]):
        for rr in (hole["r_in"], hole["r_out"](t)):
            corners.append("(%.2f, %.2f, %.2f)" % (rr * math.cos(t), p.z_floor, -rr * math.sin(t)))
    print("MDL STATS hole bearing=%.1f..%.1fdeg (blender ccw from +x; godot angle = -this; "
          "interior's nominal hole from %.1f, throat from %.1f) r=%.2f..%.2f floor=%.2f "
          "godot_corners=%s"
          % (math.degrees(hole["t0"]) % 360.0, math.degrees(hole["t1"]) % 360.0,
             math.degrees(p.th_h0) % 360.0, math.degrees(p.theta(p.s_throat)) % 360.0,
             hole["r_in"], hole["r_out"](0.5 * (hole["t0"] + hole["t1"])), p.z_floor,
             " ".join(corners)))
    print("MDL STATS door bearing=%.0fdeg lining_R=%.2f rock_face=%.2f passage=%.1fm "
          "opening=%.2fx%.2fm floor z=%.2f (godot x=%.2f y=%.2f)"
          % (ti.DOOR_BEARING, p.door["R"], p.door["x_rock"], p.door["x_rock"] - p.door["R"],
             ti.DOOR_W, ti.DOOR_H, ti.FOOT_Z + DOOR_FLOOR, p.door["x_rock"], ti.FOOT_Z))
    print("MDL STATS stair start=%.0fdeg arrive=%.0fdeg climb=%.2f lining z:R=%s"
          % (ti.STAIR_START_DEG, math.degrees(p.th_end % TAU), p.climb,
             " ".join("%.1f:%.2f" % c for c in p.ctrl)))
    return [rock, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=0.0, post=_extra_renders)
