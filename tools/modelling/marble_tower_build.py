"""
PANOPTICON -- marble_tower: the guard tower of Map 2, as the Bentham drawing
draws it (pass 4, to Ryan's verdict on pass 3). ONE SHAFT OF CONSTANT
DIAMETER from the spike floor to the roof: a plain round stone shaft on two
low steps, no wider room at the top. Near the top, at the guard floor, the
shaft opens into a colonnade -- sixteen VERY THIN columns on the shaft's own
line, open all round between them -- carrying a ring beam and a DOME that
sits directly on the columns. Round the shaft at the guard floor, a step
below the room, a narrow BALCONY with a real railing.

Origin = the guard-room datum, exactly as tower.glb: the scene's Tower node
stands at world y 25.35 and the ROOM FLOOR IS AT z 1.70 above the origin (the
guard's eye at 1.70 + 1.65 = 3.35, world 28.7, unchanged). The columns stand
at bearings 25 + 22.5k, so the sixteen openings are centred on 36.25 + 22.5k;
TowerVariant's 43 deg plugs at 25 + 45k each close the two openings either
side of a column. The foot lands on the spike floor (world y -1.0 = local
-26.35).

The balcony floor is BALCONY_Z, 0.6 m under the room floor: a 1.2 m ledge on
a 0.35 m slab, reached by stepping down between any two columns. Its railing
is 32 posts 0.10 square, a top rail 1.00 m over the ledge and a mid rail --
and the rail top (2.10) is UNDER the guard's sight line from the seat to the
lane's inner edge (2.35 at r 8.2), so the guard shoots over it. The collider
carries an invisible band at COLL_RAIL_R from the ledge to the rail top: the
railing is functional, nobody walks off.

Marble's atlas, same painter, same seed: stone courses on the shaft, fluting
on the columns, moulding on the ring beam and the slab's edge, the lane's
paving on the room floor in two rings of radial slabs round a plain
medallion, coffers under the dome, grey on the dome, iron on the railing.
ONE CONTIGUOUS MESH: mb._Mesh welds coincident vertices; the columns' feet
are cut out of the floor's outer band and their tops out of the ring beam's
underside, the posts' feet out of the ledge's outer band, the rails' ends ARE
the upper bands of the posts' side faces, the slab is zippered to the shaft,
the foot is closed with a cap, so _check() proves one component, every edge
on two faces.
MarbleTowerCollision rides in the .glb as a `-colonly` node: foot, steps,
shaft, the slab, the ledge, the invisible rail band, the room floor, the
columns, the ring beam closed with a flat ceiling. The dome is out of reach
and not in it.

    python3 tools/modelling/marble_tower_build.py --check
    tools/modelling/model build marble_tower

The column-0 `import x_build as y` lines are what tools/modelling/model ships
to the PC: keep them at column 0.
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

NS = 16                     # facets round the shaft; one column at every facet's centre
COL_PHASE = 25.0            # game bearing of column 0 (TowerVariant.WINDOW_PHASE_DEGREES): openings at 36.25 + 22.5k
NB = 32                     # facets round the balcony; one post at every facet's centre
POST_PHASE = COL_PHASE - 360.0 / (2 * NB)   # 19.375: the 32-gon's corners include the 16-gon's
FOOT_Z = mb.TOWER_FOOT_Z - 25.35   # -26.35: the spike floor
STEPS = ((8.0, FOOT_Z, FOOT_Z + 0.45), (7.5, FOOT_Z + 0.45, FOOT_Z + 0.9))   # radius, z0, z1
SHAFT_R = 7.0               # ONE diameter, foot to roof
SHAFT_Z0 = STEPS[1][2]      # the top step
SLAB_Z = (0.75, 1.10)       # the balcony slab: underside, top
BALCONY_Z = SLAB_Z[1]       # the ledge, 0.6 m under the room floor: its rail stays under the
                            # guard's sight line from the seat to the lane's inner edge (2.35 at r 8.2)
BALCONY_R = 8.2             # the ledge's edge: a 1.2 m walk outside the columns
SHAFT_BANDS = int(math.ceil((SLAB_Z[0] - SHAFT_Z0) / 3.0))   # 9 courses under 3 m, for the atlas
FLOOR_Z = 1.70              # the room floor
COL_W = 0.30                # the columns: 0.30 square, flush with the shaft's face
COL_Z1 = 7.00               # the ring beam's underside: the openings' crown (TowerVariant's plug top clears it)
BEAM = (COL_Z1, 7.50)       # the ring beam the dome sits on
DOME_Z0 = BEAM[1]
DOME_RISE = 5.4             # the dome: apex at 12.9
DOME_T = 0.30               # the shell: the inner dome springs from the beam's inner face
DOME_RINGS = 6
R_INSET = SHAFT_R - COL_W / math.cos(math.pi / NS)   # the columns' inner line at the corners: the room's wall line
PAVING_RS = (0.5, 2.2, 4.3, 6.3)   # the room floor: a grey rosette, two rings of slabs, a plain margin to the columns
# ---- the railing ---------------------------------------------------------------
POST_W = 0.10               # posts 0.10 square, one at every balcony facet's centre, flush with its edge
POST_TOP = BALCONY_Z + 1.00 # a 1.0 m railing
RAILS = ((BALCONY_Z + 0.45, BALCONY_Z + 0.51), (POST_TOP - 0.10, POST_TOP))   # mid rail, top rail
POST_ZS = sorted(set([BALCONY_Z, POST_TOP] + [z for r in RAILS for z in r]))
B_INSET = BALCONY_R - POST_W / math.cos(math.pi / NB)
COLL_RAIL_R = BALCONY_R - 0.08   # the collider: an invisible band here, ledge to rail top
GUARD_EYE = FLOOR_Z + mb.EYE_H   # 3.35: world 28.7


# =============================================================================
# GEOMETRY
# =============================================================================

def _centres(n=NS, phase=COL_PHASE):
    """Facet centre angles (Blender) of an n-gon, facet 0 at game bearing `phase`."""
    return [math.radians(-(phase + 360.0 / n * k)) for k in range(n)]


def _corners(n=NS, phase=COL_PHASE):
    """The n facet corner angles, in [0, 2pi) ascending."""
    half = math.pi / n
    return sorted((ac + half) % mb.TWO_PI for ac in _centres(n, phase))


class _Facet(object):
    """One flat facet of an n-gon at radius rad, centred on Blender angle ac."""

    def __init__(self, ac, rad, n=NS):
        half = math.pi / n
        a0, a1 = ac + half, ac - half              # p0 -> p1 runs clockwise seen from above
        self.p0 = (rad * math.cos(a0), rad * math.sin(a0))
        self.p1 = (rad * math.cos(a1), rad * math.sin(a1))
        dx, dy = self.p1[0] - self.p0[0], self.p1[1] - self.p0[1]
        self.L = math.hypot(dx, dy)
        self.u = (dx / self.L, dy / self.L)
        self.n_in = (-math.cos(ac), -math.sin(ac), 0.0)
        self.n_out = (math.cos(ac), math.sin(ac), 0.0)
        self.ac, self.n, self.rad = ac, n, rad

    def at(self, u, z, d=0.0):
        """The point u along the facet at height z, d inward of its line."""
        return (self.p0[0] + self.u[0] * u + self.n_in[0] * d,
                self.p0[1] + self.u[1] * u + self.n_in[1] * d, z)

    def dir(self, du, dz):
        return (self.u[0] * du, self.u[1] * du, dz)

    def post_us(self, w):
        """A post w wide at the facet's centre: its two side u's."""
        return self.L / 2.0 - w / 2.0, self.L / 2.0 + w / 2.0


def _ordered(pts):
    """Points of a ring sorted by angle, as (angles, points)."""
    ang = sorted((math.atan2(p[1], p[0]) % mb.TWO_PI, p) for p in pts)
    return [a for (a, _p) in ang], [p for (_a, p) in ang]


def _ringz(m, rad, z, n=NS, phase=COL_PHASE):
    return [m.v((rad * math.cos(a), rad * math.sin(a), z)) for a in _corners(n, phase)]


def _band(m, lo, hi, outward, zone):
    n = len(lo)
    for i in range(n):
        j = (i + 1) % n
        pa, pb = m.verts[lo[i]], m.verts[lo[j]]
        w = mb._unit((pa[0] + pb[0], pa[1] + pb[1], 0.0))
        if not outward:
            w = (-w[0], -w[1], 0.0)
        m.quad(lo[i], lo[j], hi[j], hi[i], w, zone)


def _annulus(m, r_in, r_out, z, up, zone, n=NS, phase=COL_PHASE):
    a = _ringz(m, r_in, z, n, phase)
    b = _ringz(m, r_out, z, n, phase)
    for i in range(n):
        j = (i + 1) % n
        m.quad(a[i], a[j], b[j], b[i], mb.UP if up else mb.DOWN, zone)


def _strip(m, f, us, z0, z1, want, zone):
    """Quads across a facet between z0 and z1, split at the u's."""
    for a in range(len(us) - 1):
        m.quad(m.v(f.at(us[a], z0)), m.v(f.at(us[a + 1], z0)),
               m.v(f.at(us[a + 1], z1)), m.v(f.at(us[a], z1)), want, zone)


def _zip(m, outer_pts, inner_pts, want, zone):
    """Zipper two rings given as points (any station counts)."""
    oa, op = _ordered(outer_pts)
    ia, ip = _ordered(inner_pts)
    mb._zipper(m, [m.v(p) for p in op], oa, [m.v(p) for p in ip], ia, want, zone)


def _disc(m, ring_pts, z, want, zone):
    """A polygon fanned from a hub at the axis, one atlas window for the whole face."""
    _a, pts = _ordered(ring_pts)
    ids = [m.v(p) for p in pts]
    hub = m.v((0.0, 0.0, z))
    gid = len(m.groups)
    for i in range(len(ids)):
        m.tri(hub, ids[i], ids[(i + 1) % len(ids)], want, zone)
        m.groups[-1] = gid


def _split_band(m, n, phase, rad, w, z0, z1, outward, zone, split, depth=0.0):
    """A band of the n-gon face at rad between z0 and z1, one hexagon a facet:
    the edge named by `split` ("top" or "bottom") is split at a post's two
    sides -- so the posts' foot or top edges are its edges -- and the other
    edge is the plain corner-to-corner ring the next part welds to. `depth`:
    the band is the facet line set that far in (the columns' inner line), and
    the posts' u's are measured on the outer facet. The fan starts off the
    split edge, so no triangle is three collinear points."""
    for ac in _centres(n, phase):
        f = _Facet(ac, rad, n)
        ua, ub = _Facet(ac, rad + depth / math.cos(math.pi / n), n).post_us(w)
        dt = depth * math.tan(math.pi / n)
        ua, ub = ua - dt, ub - dt
        want = f.n_out if outward else f.n_in
        if split == "top":
            ring = [f.at(0.0, z0), f.at(f.L, z0), f.at(f.L, z1), f.at(ub, z1), f.at(ua, z1), f.at(0.0, z1)]
        else:
            ring = [f.at(f.L, z1), f.at(0.0, z1), f.at(0.0, z0), f.at(ua, z0), f.at(ub, z0), f.at(f.L, z0)]
        m.poly([m.v(p) for p in ring], want, zone)


def _cut_band(m, n, phase, rad, r_inset, w, z, want, zone):
    """The outer band (w deep) of a horizontal face at z: per facet two quads
    either side of a post's foot, w square at the facet's centre and flush
    with its outer line. Returns the band's inner line, 3n points, for the
    inner face to zipper to."""
    line = []
    for ac in _centres(n, phase):
        f = _Facet(ac, rad, n)
        ua, ub = f.post_us(w)
        c0 = (r_inset * math.cos(ac + math.pi / n), r_inset * math.sin(ac + math.pi / n), z)
        c1 = (r_inset * math.cos(ac - math.pi / n), r_inset * math.sin(ac - math.pi / n), z)
        m.quad(m.v(f.at(0.0, z)), m.v(f.at(ua, z)), m.v(f.at(ua, z, w)), m.v(c0), want, zone)
        m.quad(m.v(f.at(ub, z)), m.v(f.at(f.L, z)), m.v(c1), m.v(f.at(ub, z, w)), want, zone)
        line += [c0, f.at(ua, z, w), f.at(ub, z, w)]
    return line


def _posts(m, n, phase, rad, w, zs, rails, zone, top=True):
    """n square posts at the facet centres, flush with the outer line, their
    faces split at every z in zs; the side (radial) faces are left out over
    each rail interval, where the rail's end closes them. Returns per post
    (facet, ua, ub)."""
    out = []
    rail_set = set(rails)
    for ac in _centres(n, phase):
        f = _Facet(ac, rad, n)
        ua, ub = f.post_us(w)

        def P(u, z, d=0.0):
            return m.v(f.at(u, z, d))

        for a in range(len(zs) - 1):
            za, zb = zs[a], zs[a + 1]
            m.quad(P(ua, za), P(ub, za), P(ub, zb), P(ua, zb), f.n_out, zone)
            m.quad(P(ua, za, w), P(ub, za, w), P(ub, zb, w), P(ua, zb, w), f.n_in, zone)
            if (za, zb) in rail_set:
                continue
            m.quad(P(ub, za), P(ub, za, w), P(ub, zb, w), P(ub, zb), f.dir(1.0, 0.0), zone)
            m.quad(P(ua, za), P(ua, za, w), P(ua, zb, w), P(ua, zb), f.dir(-1.0, 0.0), zone)
        if top:
            zt = zs[-1]
            m.quad(P(ua, zt), P(ub, zt), P(ub, zt, w), P(ua, zt, w), mb.UP, zone)
        out.append((f, ua, ub))
    return out


def _rails(m, posts, w, rails, zone):
    """Each rail runs STRAIGHT from a post's side face to the next post's,
    cutting the corner; its four quads close it, sharing the posts' edges."""
    n = len(posts)
    for (z0, z1) in rails:
        for i in range(n):
            fa, _ua, ub = posts[i]                            # this post's p1-ward side face ...
            fb, ua, _ub = posts[(i + 1) % n]                  # ... to the next post's p0-ward one
            corner = mb._unit((fa.n_out[0] + fb.n_out[0], fa.n_out[1] + fb.n_out[1], 0.0))

            def A(z, d=0.0):
                return m.v(fa.at(ub, z, d))

            def B(z, d=0.0):
                return m.v(fb.at(ua, z, d))

            m.quad(A(z0), A(z1), B(z1), B(z0), corner, zone)                                   # outer
            m.quad(A(z0, w), A(z1, w), B(z1, w), B(z0, w), (-corner[0], -corner[1], 0.0), zone)
            m.quad(A(z1), A(z1, w), B(z1, w), B(z1), mb.UP, zone)                              # top
            m.quad(A(z0), A(z0, w), B(z0, w), B(z0), mb.DOWN, zone)                            # underside


def _shaft(m):
    """The closed foot, two steps and the shaft up to the balcony slab."""
    foot = _ringz(m, STEPS[0][0], STEPS[0][1])
    m.fan(list(reversed(foot)), mb.DOWN, "plinth")           # the closed foot, on the spike floor
    for (rad, z0, z1) in STEPS:
        _band(m, _ringz(m, rad, z0), _ringz(m, rad, z1), True, "plinth")
    _annulus(m, STEPS[1][0], STEPS[0][0], STEPS[0][2], True, "plinth")
    _annulus(m, SHAFT_R, STEPS[1][0], STEPS[1][2], True, "plinth")
    z = SHAFT_Z0
    for b in range(SHAFT_BANDS):
        z_next = SHAFT_Z0 + (SLAB_Z[0] - SHAFT_Z0) * (b + 1) / SHAFT_BANDS
        _band(m, _ringz(m, SHAFT_R, z), _ringz(m, SHAFT_R, z_next), True, "stone")
        z = z_next


def _balcony(m, coll=False):
    """The slab round the shaft at the guard floor, the ledge and (model) the
    railing's feet cut out of its outer band, or (collider) a plain ledge to
    COLL_RAIL_R and an invisible band there, ledge to rail top."""
    z0, z1 = SLAB_Z
    shaft_pts = lambda z: [(SHAFT_R * math.cos(a), SHAFT_R * math.sin(a), z) for a in _corners()]
    edge_pts = lambda rad, z: [(rad * math.cos(a), rad * math.sin(a), z) for a in _corners(NB, POST_PHASE)]
    _zip(m, edge_pts(BALCONY_R, z0), shaft_pts(z0), mb.DOWN, "shade")             # underside
    if coll:
        _band(m, _ringz(m, BALCONY_R, z0, NB, POST_PHASE), _ringz(m, BALCONY_R, POST_TOP, NB, POST_PHASE),
              True, "band")
        _annulus(m, COLL_RAIL_R, BALCONY_R, POST_TOP, True, "band", NB, POST_PHASE)
        _band(m, _ringz(m, COLL_RAIL_R, z1, NB, POST_PHASE), _ringz(m, COLL_RAIL_R, POST_TOP, NB, POST_PHASE),
              False, "band")
        _zip(m, edge_pts(COLL_RAIL_R, z1), shaft_pts(z1), mb.UP, "marble2")
        return
    _split_band(m, NB, POST_PHASE, BALCONY_R, POST_W, z0, z1, True, "band", "top")   # the slab's edge
    line = _cut_band(m, NB, POST_PHASE, BALCONY_R, B_INSET, POST_W, z1, mb.UP, "marble2")
    _zip(m, line, shaft_pts(z1), mb.UP, "marble2")                                  # the ledge


def _room(m, coll=False):
    """The shaft between the ledge and the room floor, the room floor with the
    columns' feet cut out of its outer band, and the columns."""
    _split_band(m, NS, COL_PHASE, SHAFT_R, COL_W, SLAB_Z[1], FLOOR_Z, True, "stone", "top")
    line = _cut_band(m, NS, COL_PHASE, SHAFT_R, R_INSET, COL_W, FLOOR_Z, mb.UP, "plinth")
    if coll:
        _disc(m, line, FLOOR_Z, mb.UP, "floor")
    else:
        rings = [[(r * math.cos(a), r * math.sin(a), FLOOR_Z) for a in _corners()] for r in PAVING_RS]
        _zip(m, line, rings[-1], mb.UP, "shade")                                   # the plain margin
        for k in range(len(rings) - 1, 0, -1):                                     # radial slabs, one cell each ...
            a, b = [m.v(p) for p in rings[k - 1]], [m.v(p) for p in rings[k]]
            for i in range(NS):
                j = (i + 1) % NS
                m.quad(a[i], a[j], b[j], b[i], mb.UP, "floor" if k > 1 else "shade")   # ... the rosette's wedges plain grey
        m.poly([m.v(p) for p in rings[0]], mb.UP, "shade")                         # its centre: no vertex on the axis,
                                                                                   # where the polar unwrap has no frame
    _posts(m, NS, COL_PHASE, SHAFT_R, COL_W, [FLOOR_Z, COL_Z1], (), "column", top=False)


def _crown(m, coll=False):
    """The ring beam on the columns' tops, and the dome on the beam."""
    z0, z1 = BEAM
    line = _cut_band(m, NS, COL_PHASE, SHAFT_R, R_INSET, COL_W, z0, mb.DOWN, "shade")   # the beam's underside
    _split_band(m, NS, COL_PHASE, SHAFT_R, COL_W, z0, z1, True, "band", "bottom")      # its outer face ...
    _split_band(m, NS, COL_PHASE, R_INSET, COL_W, z0, z1, False, "band", "bottom", depth=COL_W)   # ... and inner
    if coll:                                                                           # closed flat: a lid over the beam, a ceiling under it
        _disc(m, [(SHAFT_R * math.cos(a), SHAFT_R * math.sin(a), z1) for a in _corners()], z1, mb.UP, "band")
        _disc(m, [(R_INSET * math.cos(a), R_INSET * math.sin(a), z1) for a in _corners()], z1, mb.DOWN, "shade")
        return
    for (rad, rise, outward, zone, cap_zone) in ((SHAFT_R, DOME_RISE, True, "shade", "shade"),
                                                  (R_INSET, DOME_RISE - DOME_T, False, "coffer", "shade")):
        prev = _ringz(m, rad, z1)
        for k in range(1, DOME_RINGS):
            t = 0.5 * math.pi * k / DOME_RINGS
            ring = _ringz(m, rad * math.cos(t), z1 + rise * math.sin(t))
            for i in range(NS):
                j = (i + 1) % NS
                pa, pb = m.verts[prev[i]], m.verts[prev[j]]
                er = mb._unit((pa[0] + pb[0], pa[1] + pb[1], 0.0))
                w = (er[0] * rise, er[1] * rise, rad)
                if not outward:
                    w = (-w[0], -w[1], -w[2])
                m.quad(prev[i], prev[j], ring[j], ring[i], w, zone)
            prev = ring
        apex = m.v((0.0, 0.0, z1 + rise))
        for i in range(NS):
            j = (i + 1) % NS
            m.tri(prev[i], prev[j], apex, mb.UP if outward else mb.DOWN, cap_zone)


def _rock():
    m = mb._Mesh()
    _shaft(m)
    n1 = len(m.faces)
    _balcony(m)
    posts = _posts(m, NB, POST_PHASE, BALCONY_R, POST_W, POST_ZS, RAILS, "iron")
    _rails(m, posts, POST_W, RAILS, "iron")
    n2 = len(m.faces)
    _room(m)
    n3 = len(m.faces)
    _crown(m)
    return m, {"shaft": n1, "balcony": n2 - n1, "room": n3 - n2, "crown": len(m.faces) - n3}


def _collider():
    c = mb._Mesh()
    _shaft(c)
    _balcony(c, coll=True)
    _room(c, coll=True)
    _crown(c, coll=True)
    return c


def sightline_clearance():
    """Metres the guard's sight line from the seat (eye GUARD_EYE at the axis)
    to the lane's inner edge passes OVER the rail top at the balcony's edge."""
    lane_z = mb.DECK_Z - 25.35
    z_at_rail = GUARD_EYE + (lane_z - GUARD_EYE) * (BALCONY_R / mb.INNER_R)
    return z_at_rail - POST_TOP


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
    open0 = COL_PHASE + 180.0 / NS                             # the first opening's centre
    shot("from_lane", mb.pol(30.0, 40.0, eye), (0.0, 0.0, 4.0), 40.0, (1000, 1200))
    shot("window", (0.0, 0.0, GUARD_EYE), mb.pol(open0, 20.0, FLOOR_Z + 0.5), 24.0, (1200, 800))
    # the room at eye level: the floor, the columns, the dome inside
    shot("room", mb.pol(200.0, 4.6, GUARD_EYE), mb.pol(20.0, 2.5, FLOOR_Z + 0.3), 16.0, (1400, 900))
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
    print("MDL STATS visual_tris=%d collision_tris=%d shaft=%d balcony=%d room=%d crown=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), counts["shaft"], counts["balcony"],
             counts["room"], counts["crown"]))
    print("MDL STATS contiguity components=%d boundary=%d doubled=%d over=%d degenerate=%d dup_pos=%d"
          % (a["components"], a["boundary_edges"], a["doubled_edges"], a["over_edges"], a["degenerate"],
             a["duplicate_positions"]))
    print("MDL STATS floor_z=%.2f eye_z=%.2f shaft_r=%.1f columns=%d col_w=%.2f openings_crown=%.2f "
          "balcony_z=%.2f balcony_r=%.1f rail_top=%.2f sightline_clear=%.2f dome=%.2f..%.2f foot_z=%.2f"
          % (FLOOR_Z, GUARD_EYE, SHAFT_R, NS, COL_W, COL_Z1, BALCONY_Z, BALCONY_R, POST_TOP,
             sightline_clearance(), DOME_Z0, DOME_Z0 + DOME_RISE, FOOT_Z))
    return [ob, coll_ob]


def _check():
    """--check: build without Blender; prove one closed contiguous mesh."""
    rock, counts = _rock()
    coll = _collider()
    a = mb.audit(rock, "tower")
    c = mb.audit(coll, "coll")
    zs = [v[2] for v in rock.verts]
    print("counts=%s z=%.2f..%.2f loops=%s" % (counts, min(zs), max(zs), mb.boundary_loops(rock)[:3]))
    print("coll loops=%s" % (mb.boundary_loops(coll)[:3],))
    print("sightline clears the rail top by %.2f m (rail %.2f at r %.1f)" % (sightline_clearance(), POST_TOP, BALCONY_R))
    ok = a["components"] == 1 and a["boundary_edges"] == 0 and a["doubled_edges"] == 0 \
        and a["over_edges"] == 0 and a["degenerate"] == 0 and a["duplicate_positions"] == 0 \
        and c["boundary_edges"] == 0 and c["over_edges"] == 0 and sightline_clearance() > 0.0
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_render)
