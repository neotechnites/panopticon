"""
PANOPTICON -- marble_tower: the guard tower of Map 2, as the Bentham drawing
draws it. A tall round lodge: a plain marble shaft on two steps, a corbelled
balcony with a parapet, the lantern -- a gallery band of eight arched windows
at the guard's eye -- under a cornice and a conical cap.

Origin = the guard-room datum, exactly as tower.glb: the scene's Tower node
stands at world y 25.35 and the ROOM FLOOR IS AT z 1.70 above the origin (the
guard's eye at 1.70 + 1.65). The eight windows sit on Map 1's grid -- bearings
25 + 45k, inner radius 6.86, sill 2.35, crown 7.00 -- so TowerVariant's plugs
and the guard's flat view of the ring carry over unchanged. The foot lands on
the bed's lowest terrace (world y 16.9 = local -8.45).

Marble's atlas, same painter, same seed: pale ashlar on the shaft, the
rotunda's marble on the lantern, grey on the cap. ONE CONTIGUOUS MESH:
mb._Mesh welds coincident vertices, every ring is built from the same sixteen
corner angles, and the foot is closed with a cap, so _check() proves one
component, every edge on two faces. MarbleTowerCollision rides in the .glb as
a `-colonly` node: room floor, sill band, piers, window reveals, ceiling, the
lantern's outer face, balcony, parapet, corbel, shaft and steps. The cap is
out of reach and not in it.

    python3 tools/modelling/marble_tower_build.py --check
    tools/modelling/model build marble_tower
"""

import math
import os
import sys

try:
    import bpy
except ImportError:
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, HERE + os.sep + "lib")

import marble_build as mb  # noqa: E402
# marble_build imports its two part modules at its foot; they ride along to the
# PC only when a column-0 `import x_build as y` names them in THIS script.
import marble_lane_build as _ml  # noqa: E402, F401
import marble_wall_build as _mw  # noqa: E402, F401

if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["views"] = ["front", "threequarter", "side"]
    mdl.DEFAULTS["ground"] = False

# =============================================================================
# TUNABLES  (local z: the room floor is 1.70)
# =============================================================================

NAME = "marble_tower"
OBJECT_NAME = "MarbleTowerRock"
COLLIDER_NAME = "MarbleTowerCollision-colonly"
FACING_YAW = 0.0

NS = 16                     # facets round; 8 windows, 8 piers
WINDOW_PHASE = 25.0         # game bearing of window 0 (TowerVariant.WINDOW_PHASE_DEGREES)
FOOT_Z = mb.TOWER_FOOT_Z - 25.35   # -8.45: the lowest terrace of the spike bed
STEPS = ((8.0, FOOT_Z, FOOT_Z + 0.4), (7.3, FOOT_Z + 0.4, FOOT_Z + 0.8))   # radius, z0, z1
SHAFT_R = 6.6
SHAFT_Z1 = 0.0
SHAFT_BANDS = 3             # the shaft's courses in bands under 3 m, for the atlas
CORBEL_R, CORBEL_Z = 9.9, 1.0        # the balcony's outer edge and floor
PARAPET_R_IN, PARAPET_TOP = 9.5, 2.0
LANTERN_R_OUT = 8.6
LANTERN_R_IN = 6.86         # TowerVariant.DRUM_INNER_RADIUS
FLOOR_Z = 1.70
CEIL_Z = 8.95
WIN_SILL = 2.35             # floor + 0.65: jumping out is allowed
WIN_CROWN = 7.00
# Window half width, about 1.13 m (2.26 m wide): chosen so the ray from the
# springing centre through the sill corner passes exactly through the facet's
# floor corner -- then the frame has no sliver between those two rays.
_HALF_CHORD_IN = LANTERN_R_IN * math.sin(math.pi / NS)
WIN_HW = _HALF_CHORD_IN * ((WIN_CROWN - WIN_SILL) - _HALF_CHORD_IN) / 1.0   # placeholder, solved below


def _solve_hw():
    c = _HALF_CHORD_IN
    # sp = crown - hw; (sp - sill) / (sp - floor) = hw / c  ->  solve for hw
    lo, hi = 0.5, 1.5
    for _ in range(60):
        hw = 0.5 * (lo + hi)
        sp = WIN_CROWN - hw
        f = c * (sp - WIN_SILL) / (sp - FLOOR_Z) - hw
        if f > 0:
            lo = hw
        else:
            hi = hw
    return 0.5 * (lo + hi)


WIN_HW = _solve_hw()
LANTERN_TOP = 9.2
CORNICE = (9.2, 9.6, 0.4)   # z0, z1, proud
CAP_H = 6.5                 # the conical cap, cornice top to apex
CAP_R = LANTERN_R_OUT + CORNICE[2]   # the cap's eave sits on the cornice's edge


# =============================================================================
# GEOMETRY
# =============================================================================

def _centres():
    """Facet centre angles (Blender), window facets first at bearing 25 + 45k."""
    return [math.radians(-(WINDOW_PHASE + 22.5 * k)) for k in range(NS)]


class _Facet(object):
    """One flat facet of an NS-gon at radius rad, centred on Blender angle ac."""

    def __init__(self, ac, rad):
        half = math.pi / NS
        a0, a1 = ac + half, ac - half              # p0 -> p1 runs clockwise seen from above
        self.p0 = (rad * math.cos(a0), rad * math.sin(a0))
        self.p1 = (rad * math.cos(a1), rad * math.sin(a1))
        dx, dy = self.p1[0] - self.p0[0], self.p1[1] - self.p0[1]
        self.L = math.hypot(dx, dy)
        self.u = (dx / self.L, dy / self.L)
        self.n_in = (-math.cos(ac), -math.sin(ac), 0.0)
        self.n_out = (math.cos(ac), math.sin(ac), 0.0)

    def at(self, u, z):
        return (self.p0[0] + self.u[0] * u, self.p0[1] + self.u[1] * u, z)

    def dir(self, du, dz):
        return (self.u[0] * du, self.u[1] * du, dz)


def _rays(loop, centre, rect):
    """Where the ray from `centre` through each loop point leaves `rect` (2-D)."""
    u0, u1, z0, z1 = rect
    return [mb._ray_box(centre[0], centre[1], math.atan2(z - centre[1], u - centre[0]), u0, u1, z0, z1)
            for (u, z) in loop]


def _frame(m, f, loop, outer, want, zone):
    """The facet rectangle with a star-shaped hole `loop` cut in it; `outer` is
    the matching point on the rectangle's edge for every loop point. Returns
    the loop's vertex ids on the facet."""
    vin = [m.v(f.at(u, z)) for (u, z) in loop]
    vout = [m.v(f.at(u, z)) for (u, z) in outer]
    n = len(loop)
    for k in range(n):
        j = (k + 1) % n
        m.quad(vin[k], vin[j], vout[j], vout[k], want, zone)
    return vin


def _window_loop(f_in):
    """The window outline on the inner facet: head segments, rays to the
    facet's rectangle corners, the sill corners and middle. The outer facet's
    loop is this one scaled along the chord about the springing centre, which
    keeps every ray a ray, so the two frames' rays hit their corners alike."""
    c = f_in.L / 2.0
    sp = WIN_CROWN - WIN_HW
    ths = mb._arch_thetas(c, WIN_HW, WIN_SILL, sp, 0.0, f_in.L, FLOOR_Z, CEIL_Z)
    out = []
    for t in sorted(ths):
        if not out or t - out[-1] > 1e-4:        # the sill-corner and floor-corner rays coincide by design
            out.append(t)
    return [mb._arch_inner(c, WIN_HW, WIN_SILL, sp, t) for t in out], (c, sp)


def _edge_pts(outer, rect):
    """The frame's rectangle-edge points sorted along each edge, corners
    included, the corners' exact values kept and near-duplicates merged."""
    u0, u1, z0, z1 = rect
    eps = 1e-6

    def merge(vals, ends):
        out = list(ends)
        for v in sorted(vals):
            if all(abs(v - o) > 1e-4 for o in out):
                out.append(v)
        return sorted(out)

    return {"bottom": merge([u for (u, z) in outer if abs(z - z0) < eps], (u0, u1)),
            "top": merge([u for (u, z) in outer if abs(z - z1) < eps], (u0, u1)),
            "left": merge([z for (u, z) in outer if abs(u - u0) < eps], (z0, z1)),
            "right": merge([z for (u, z) in outer if abs(u - u1) < eps], (z0, z1))}


def _ordered(pts):
    """Points of a ring sorted by angle, as (angles, points)."""
    ang = sorted((math.atan2(p[1], p[0]) % mb.TWO_PI, p) for p in pts)
    return [a for (a, _p) in ang], [p for (_a, p) in ang]


def _strip(m, f, us, z0, z1, want, zone):
    """Quads across a facet between z0 and z1, split at the u's."""
    for a in range(len(us) - 1):
        m.quad(m.v(f.at(us[a], z0)), m.v(f.at(us[a + 1], z0)),
               m.v(f.at(us[a + 1], z1)), m.v(f.at(us[a], z1)), want, zone)


def _lantern(m, coll=False):
    """The drum: eight window facets, eight piers, floor and ceiling. Every
    facet is subdivided where its neighbour's frame puts a vertex on the shared
    edge, so nothing is a T-junction. Returns the drum's outer-face foot and
    top rings (angles, points) for the body to zipper to."""
    k = LANTERN_R_OUT / LANTERN_R_IN
    cents = _centres()
    fi0, fo0 = _Facet(cents[0], LANTERN_R_IN), _Facet(cents[0], LANTERN_R_OUT)
    loop_in, centre = _window_loop(fi0)
    loop_out = [(u * k, z) for (u, z) in loop_in]
    centre_out = (centre[0] * k, centre[1])
    rect_in = (0.0, fi0.L, FLOOR_Z, CEIL_Z)
    rect_out = (0.0, fo0.L, FLOOR_Z, CEIL_Z)               # the same band outside: plain strips below and above
    outer_in = _rays(loop_in, centre, rect_in)
    outer_out = _rays(loop_out, centre_out, rect_out)
    ein, eout = _edge_pts(outer_in, rect_in), _edge_pts(outer_out, rect_out)
    pier_in = ein["left"]
    pier_out = sorted(set([CORBEL_Z, LANTERN_TOP] + eout["left"]))
    floor_pts, ceil_pts, foot_pts, top_pts = [], [], [], []
    for idx, ac in enumerate(cents):
        fi, fo = _Facet(ac, LANTERN_R_IN), _Facet(ac, LANTERN_R_OUT)
        if idx % 2 == 1:                                    # a pier, split at the neighbours' edge points
            for a in range(len(pier_in) - 1):
                _strip(m, fi, [0.0, fi.L], pier_in[a], pier_in[a + 1], fi.n_in, "marble")
            for a in range(len(pier_out) - 1):
                _strip(m, fo, [0.0, fo.L], pier_out[a], pier_out[a + 1], fo.n_out, "marble2")
            floor_pts.append(fi.at(0.0, FLOOR_Z))
            ceil_pts.append(fi.at(0.0, CEIL_Z))
            foot_pts.append(fo.at(0.0, CORBEL_Z))
            top_pts.append(fo.at(0.0, LANTERN_TOP))
            continue
        vin = _frame(m, fi, loop_in, outer_in, fi.n_in, "marble")
        vout = _frame(m, fo, loop_out, outer_out, fo.n_out, "marble2")
        _strip(m, fo, eout["bottom"], CORBEL_Z, FLOOR_Z, fo.n_out, "marble2")    # under the frame band
        _strip(m, fo, eout["top"], CEIL_Z, LANTERN_TOP, fo.n_out, "marble2")    # over it
        n = len(loop_in)
        for a in range(n):
            b = (a + 1) % n
            mu = 0.5 * (loop_in[a][0] + loop_in[b][0])
            mz = 0.5 * (loop_in[a][1] + loop_in[b][1])
            w = fi.dir(centre[0] - mu, centre[1] - mz)
            m.quad(vin[a], vin[b], vout[b], vout[a], w, "shade")
        floor_pts += [fi.at(u, FLOOR_Z) for u in ein["bottom"][:-1]]
        ceil_pts += [fi.at(u, CEIL_Z) for u in ein["top"][:-1]]
        foot_pts += [fo.at(u, CORBEL_Z) for u in eout["bottom"][:-1]]
        top_pts += [fo.at(u, LANTERN_TOP) for u in eout["top"][:-1]]
    hub = m.v((0.0, 0.0, FLOOR_Z))
    _ang, pts = _ordered(floor_pts)
    ids = [m.v(p) for p in pts]
    for i in range(len(ids)):
        m.tri(hub, ids[i], ids[(i + 1) % len(ids)], mb.UP, "floor")
    hub = m.v((0.0, 0.0, CEIL_Z))
    _ang, pts = _ordered(ceil_pts)
    ids = [m.v(p) for p in pts]
    for i in range(len(ids)):
        m.tri(hub, ids[i], ids[(i + 1) % len(ids)], mb.DOWN, "coffer")
    return _ordered(foot_pts), _ordered(top_pts)


def _corners():
    """The sixteen facet corner angles, in [0, 2pi) ascending."""
    half = math.pi / NS
    return sorted((ac + half) % mb.TWO_PI for ac in _centres())


def _ringz(m, rad, z):
    return [m.v((rad * math.cos(a), rad * math.sin(a), z)) for a in _corners()]


def _band(m, lo, hi, outward, zone):
    n = len(lo)
    for i in range(n):
        j = (i + 1) % n
        pa, pb = m.verts[lo[i]], m.verts[lo[j]]
        w = mb._unit((pa[0] + pb[0], pa[1] + pb[1], 0.0))
        if not outward:
            w = (-w[0], -w[1], 0.0)
        m.quad(lo[i], lo[j], hi[j], hi[i], w, zone)


def _annulus(m, r_in, r_out, z, up, zone):
    a = _ringz(m, r_in, z)
    b = _ringz(m, r_out, z)
    for i in range(NS):
        j = (i + 1) % NS
        m.quad(a[i], a[j], b[j], b[i], mb.UP if up else mb.DOWN, zone)


def _body(m, foot_ring, top_ring, coll=False):
    """Steps, shaft, corbel, balcony, parapet, cornice, conical cap; the foot
    is capped so the shell is closed. foot_ring / top_ring: the drum's outer
    face edges (angles, points), which the balcony and the cornice zipper to."""
    foot = _ringz(m, STEPS[0][0], STEPS[0][1])
    m.fan(list(reversed(foot)), mb.DOWN, "plinth")           # the closed foot, under the bed
    for (rad, z0, z1) in STEPS:
        _band(m, _ringz(m, rad, z0), _ringz(m, rad, z1), True, "plinth")
    _annulus(m, 7.3, 8.0, STEPS[0][2], True, "plinth")
    _annulus(m, SHAFT_R, 7.3, STEPS[1][2], True, "plinth")
    z = STEPS[1][2]
    for b in range(SHAFT_BANDS):
        z_next = z + (SHAFT_Z1 - STEPS[1][2]) / SHAFT_BANDS
        _band(m, _ringz(m, SHAFT_R, z), _ringz(m, SHAFT_R, z_next), True, "plinth")
        z = z_next
    # the corbel: a cone out to the balcony's edge
    lo, hi = _ringz(m, SHAFT_R, SHAFT_Z1), _ringz(m, CORBEL_R, CORBEL_Z)
    for i in range(NS):
        j = (i + 1) % NS
        pa, pb = m.verts[lo[i]], m.verts[lo[j]]
        er = mb._unit((pa[0] + pb[0], pa[1] + pb[1], 0.0))
        dr, dz = CORBEL_R - SHAFT_R, CORBEL_Z - SHAFT_Z1     # the cone's slope ...
        w = (er[0] * dz, er[1] * dz, -dr)                     # ... its outward, downward normal
        m.quad(lo[i], lo[j], hi[j], hi[i], w, "band")
    # balcony floor (zippered to the drum's foot), parapet
    p_ang = _corners()
    p_ids = [m.v((PARAPET_R_IN * math.cos(a), PARAPET_R_IN * math.sin(a), CORBEL_Z)) for a in sorted(p_ang)]
    f_ids = [m.v(p) for p in foot_ring[1]]
    mb._zipper(m, p_ids, sorted(p_ang), f_ids, foot_ring[0], mb.UP, "floor")
    _band(m, _ringz(m, PARAPET_R_IN, CORBEL_Z), _ringz(m, PARAPET_R_IN, PARAPET_TOP), False, "marble")
    _annulus(m, PARAPET_R_IN, CORBEL_R, PARAPET_TOP, True, "shade")
    _band(m, _ringz(m, CORBEL_R, CORBEL_Z), _ringz(m, CORBEL_R, PARAPET_TOP), True, "band")
    if coll:
        return
    # cornice
    z0, z1, proud = CORNICE
    ro = LANTERN_R_OUT + proud
    c_ids = [m.v((ro * math.cos(a), ro * math.sin(a), z0)) for a in sorted(p_ang)]
    t_ids = [m.v(p) for p in top_ring[1]]
    mb._zipper(m, c_ids, sorted(p_ang), t_ids, top_ring[0], mb.DOWN, "shade")
    _band(m, _ringz(m, ro, z0), _ringz(m, ro, z1), True, "band")
    # the cap: a cone from the cornice's edge to a point
    eave = _ringz(m, ro, z1)
    apex = m.v((0.0, 0.0, z1 + CAP_H))
    for i in range(NS):
        j = (i + 1) % NS
        pa, pb = m.verts[eave[i]], m.verts[eave[j]]
        er = mb._unit((pa[0] + pb[0], pa[1] + pb[1], 0.0))
        m.tri(eave[i], eave[j], apex, (er[0] * CAP_H, er[1] * CAP_H, ro), "shade")


def _rock():
    m = mb._Mesh()
    foot, top = _lantern(m)
    n1 = len(m.faces)
    _body(m, foot, top)
    return m, {"lantern": n1, "body": len(m.faces) - n1}


def _collider():
    c = mb._Mesh()
    foot, top = _lantern(c, coll=True)
    _body(c, foot, top, coll=True)
    return c


# =============================================================================
# RENDERS
# =============================================================================

def _render(spec, objects):
    scene = bpy.context.scene
    target = mdl._link(bpy.data.objects.new("ShotTarget", None))
    cam = mdl._link(bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam")))
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE" if spec.get("engine", "eevee") != "cycles" else "CYCLES"
    mdl._try(scene.view_settings, "view_transform", "Standard")
    world = bpy.data.worlds.new("Grey")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.40, 0.42, 0.45, 1.0)
    bg.inputs[1].default_value = 0.7
    sd = bpy.data.lights.new("Sun", type="SUN")
    sd.energy = 1.6
    sun = mdl._link(bpy.data.objects.new("Sun", sd))
    sun.rotation_euler = (math.radians(50.0), 0.0, math.radians(30.0))
    ld = bpy.data.lights.new("Room", type="POINT")
    ld.energy = 3000.0
    room = mdl._link(bpy.data.objects.new("Room", ld))
    room.location = (0.0, 0.0, FLOOR_Z + 4.0)
    out_dir = spec.get("out_dir", ".")

    def shot(name, loc, tgt, lens, res):
        cam.data.lens = lens
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    eye = mb.DECK_Z + mb.EYE_H - 25.35
    shot("from_lane", mb.pol(30.0, 40.0, eye), (0.0, 0.0, 4.0), 40.0, (1000, 1200))
    shot("window", (0.0, 0.0, FLOOR_Z + 1.65), mb.pol(WINDOW_PHASE, 20.0, FLOOR_Z + 0.5), 24.0, (1200, 800))
    for ob in (target, cam, sun, room):
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    rock, counts = _rock()
    coll = _collider()
    albedo, emissive = mb._sheet("marble", mb.build_texture)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    ob = rock.object(OBJECT_NAME)
    mb.unwrap(ob, rock.zones, rock.groups, seed=3)
    mdl.finish(ob, mb.stone_material("Marble", albedo, emissive), strip_uvs=False)
    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    a = mb.audit(rock, "tower")
    print("MDL STATS visual_tris=%d collision_tris=%d lantern=%d body=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), counts["lantern"], counts["body"]))
    print("MDL STATS contiguity components=%d boundary=%d doubled=%d over=%d degenerate=%d dup_pos=%d"
          % (a["components"], a["boundary_edges"], a["doubled_edges"], a["over_edges"], a["degenerate"],
             a["duplicate_positions"]))
    print("MDL STATS floor_z=%.2f ceil_z=%.2f r_in=%.2f r_out=%.1f windows=8 phase=%.0f sill=%.2f crown=%.2f foot_z=%.2f"
          % (FLOOR_Z, CEIL_Z, LANTERN_R_IN, LANTERN_R_OUT, WINDOW_PHASE, WIN_SILL, WIN_CROWN, FOOT_Z))
    return [ob, coll_ob]


def _check():
    """--check: build without Blender; prove one closed contiguous mesh."""
    rock, counts = _rock()
    coll = _collider()
    a = mb.audit(rock, "tower")
    mb.audit(coll, "coll")
    zs = [v[2] for v in rock.verts]
    print("counts=%s z=%.2f..%.2f loops=%s" % (counts, min(zs), max(zs), mb.boundary_loops(rock)[:3]))
    ok = a["components"] == 1 and a["boundary_edges"] == 0 and a["doubled_edges"] == 0 \
        and a["over_edges"] == 0 and a["degenerate"] == 0 and a["duplicate_positions"] == 0
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_render)
