"""
PANOPTICON -- marble_tower: the guard tower of Map 2, as the Bentham drawing
draws it (pass 5, to Ryan's verdict on pass 4: "the columns aren't just
holding a dome, they are arches"). ONE SHAFT OF CONSTANT DIAMETER from the
spike floor to the roof: a plain round stone shaft on two low steps, no wider
room at the top. Near the top, at the guard floor, the shaft opens into an
ARCADE -- the same sixteen VERY THIN columns on the shaft's own line, now
JOINED BY ROUND ARCHES: each column rises 3.20 m to a springing at z 4.90 and
the arches turn from it, span 2.43 m, rise 1.22 m, crowning at 6.12 on the
corner lines, with a 0.88 m spandrel over each crown up to the ring beam at
7.00. The beam and the DOME sit on the arches, not on bare columns. Round the
shaft at the guard floor, a step below the room, a narrow BALCONY with a real
railing.

Origin = the guard-room datum, exactly as tower.glb: the scene's Tower node
stands at world y 25.35 and the ROOM FLOOR IS AT z 1.70 above the origin (the
guard's eye at 1.70 + 1.65 = 3.35, world 28.7, unchanged). The columns stand
at bearings 25 + 22.5k, so the sixteen arched openings are centred on
36.25 + 22.5k -- on the facet CORNERS, so every facet carries HALF an arch at
each end and two halves across a corner make one arch; TowerVariant's 43 deg
plugs at 25 + 45k each close the two openings either side of a column,
unchanged. The foot lands on the spike floor (world y -1.0 = local -26.35).

The balcony floor is FLAT with the room floor (Ryan, pass 4): one level,
FLOOR_Z, through the columns onto a 1.2 m ledge on a 0.35 m slab. Its
railing is 32 posts 0.10 square, a top rail 1.00 m over the ledge and a mid
rail. The rail top (2.70) would cross the guard's sight line from a seat on
the floor, so the seat stands on a 0.6 m DAIS (the floor's rosette, r 2.2):
the eye at 3.95 (world 29.3) clears the rail top by 0.14 m to the lane's
inner edge, 0.26 m to the lane. The collider
carries an invisible band at COLL_RAIL_R from the ledge to the rail top: the
railing is functional, nobody walks off.

Each facet is one PIERCED SCREEN 0.30 deep: the outer face on the facet chord
at r 7.0, the inner face in the r 6.694 facet's own frame (half arch
ua_inner = ua - 0.30*tan(pi/16), so its corner points ARE the shared inner
corners and the arch soffit is a slightly warped ruled surface, which is what
a round arch turned through a polygon's corner is). Jamb reveals run floor to
springing, the intrados round the head, a spandrel strip over each half arch.

Texture: ONE TILING SHEET PER MATERIAL CLASS (lib/texel.py, SHEETS below),
world-projected at the rotunda's own density -- no atlas, no per-face random
window. The shaft's courses therefore run round all sixteen facets at one
height, on the same world 1 m grid the rotunda's wall courses use, and their
vertical joints stand on the facet corners; the dome is a "custom" sheet
whose v is the meridian's ARC LENGTH, so a coffer is the same size at the
spring and at the crown. USE_TEXTURE_FILES swaps a painted class for
textures/marble_tower_<class>_albedo.png when one is there.
ONE CONTIGUOUS MESH: mb._Mesh welds coincident vertices; the columns' feet
are cut out of the floor's outer band, the screen's head is SOLID corner to
corner (so the ring beam has no exposed underside -- its two faces carry the
panel's top edge, split at every arch and column station), the posts' feet
are cut out of the ledge's outer band, the rails' ends ARE the upper bands of
the posts' side faces, the slab is zippered to the shaft, the foot is closed
with a cap, so _check() proves one component, every edge on two faces.
MarbleTowerCollision rides in the .glb as a `-colonly` node: foot, steps,
shaft, the slab, the ledge, the invisible rail band, the room floor, plain
full-height column boxes (a body cannot walk into an arch's head, so the
collider keeps the cheap colonnade), the ring beam closed with a flat
ceiling. The dome is out of reach and not in it.

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
import texel as tx  # noqa: E402  one tiling sheet per class, world-projected
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
FLOOR_Z = 1.70              # the room floor
SLAB_Z = (FLOOR_Z - 0.35, FLOOR_Z)   # the balcony slab: underside, top -- the ledge is FLAT with the room floor
BALCONY_Z = SLAB_Z[1]       # one level through the columns, no step (Ryan, pass 4)
BALCONY_R = 8.2             # the ledge's edge: a 1.2 m walk outside the columns
SHAFT_BANDS = int(math.ceil((SLAB_Z[0] - SHAFT_Z0) / 3.0))   # 9 courses under 3 m, for the atlas
COL_W = 0.30                # the columns: 0.30 square, flush with the shaft's face
COL_Z1 = 7.00               # the ring beam's underside: the arcade's head (TowerVariant's plug top clears it)
SPRING_Z = FLOOR_Z + 3.2    # 4.90: the arches spring here, off the columns' sides
ARCH_SEG = 5                # segments in each HALF arch (one facet carries half an arch at each end)
BEAM = (COL_Z1, 7.50)       # the ring beam the dome sits on
DOME_Z0 = BEAM[1]
DOME_RISE = 5.4             # the dome: apex at 12.9
DOME_T = 0.30               # the shell: the inner dome springs from the beam's inner face
DOME_RINGS = 6
R_INSET = SHAFT_R - COL_W / math.cos(math.pi / NS)   # the columns' inner line at the corners: the room's wall line
PAVING_RS = (0.5, 2.2, 4.25, 6.3)  # the room floor: a grey rosette, two EQUAL rings of slabs, a plain margin to the columns
PAVE_SUB = 3                # a paving cell is 3 x 3 slabs: its joints are real edges on true rings and radials
DAIS_H = 0.6                # the rosette is a DAIS: the seat stands on it, so the guard's eye clears the rail top
DAIS_R = PAVING_RS[1]
# ---- the railing ---------------------------------------------------------------
POST_W = 0.10               # posts 0.10 square, one at every balcony facet's centre, flush with its edge
POST_TOP = BALCONY_Z + 1.00 # a 1.0 m railing
RAILS = ((BALCONY_Z + 0.45, BALCONY_Z + 0.51), (POST_TOP - 0.10, POST_TOP))   # mid rail, top rail
POST_ZS = sorted(set([BALCONY_Z, POST_TOP] + [z for r in RAILS for z in r]))
B_INSET = BALCONY_R - POST_W / math.cos(math.pi / NB)
COLL_RAIL_R = BALCONY_R - 0.08   # the collider: an invisible band here, ledge to rail top
GUARD_EYE = FLOOR_Z + DAIS_H + mb.EYE_H   # 3.95: world 29.3 (pass 3: 28.7)


# =============================================================================
# TEXTURE  (lib/texel.py: one tiling sheet per class, world cylindrical)
# =============================================================================
# The tower wears the rotunda's stone at the rotunda's density: WALL_MPT
# (0.046 m) a texel, a sheet 12 courses of 1.0 m tall, phased on FOOT_Z -- the
# spike floor -- so every course line lands on the world 1 m grid the wall's
# own courses use (tower local z = world y - 25.35). Across, a shaft sheet is
# 60 texels = 2.761 m and texel's ring() closes that at exactly 16 repeats
# round r 7.0: ONE REPEAT PER FACET, its vertical joints on the facet corners
# (U0_SHAFT puts u = 0 there), 2.749/60 = 0.0458 m a texel, 0.4 % off the
# vertical. The balcony's sheet is 35 texels = 1.611 m: 32 repeats at r 8.2,
# one per post facet. Band, column, iron and the floor slab are fitted to the
# face exactly as the rotunda fits them; the dome is "custom" (see _dome_vs).

USE_TEXTURE_FILES = True
TEX_DIR = mb.TEX_DIR
MPT = mb.WALL_MPT                    # 0.046019 m a texel: the rotunda's wall density
SHEET_H = mb.WALL_H                  # 261 texels = 12 courses of 1.0 m
SHEET_M = SHEET_H * MPT              # 12.01 m: the sheet's period up
COURSES = 12
SHAFT_PX = 60                        # one facet across at r 7.0 -> ring() closes at 16
BAL_PX = 35                          # one balcony facet across at r 8.2 -> 32 repeats
U0_SHAFT = SHAFT_R * math.radians(-(COL_PHASE + 180.0 / NS))       # u = 0 on a facet corner
U0_BAL = BALCONY_R * math.radians(-(POST_PHASE + 180.0 / NB))      # ... on a balcony corner
V0 = FOOT_Z                          # v = 0 on the spike floor: courses on the world grid


def _dome_profile(rad, rise):
    """The shell's meridian: (radius, height over the spring) per ring, ring
    DOME_RINGS the apex, rings EQUALLY SPACED BY ARC so every row is one height."""
    fine = [(rad * math.cos(0.5 * math.pi * q / 4096.0), rise * math.sin(0.5 * math.pi * q / 4096.0))
            for q in range(4097)]
    run = [0.0]
    for q in range(4096):
        run.append(run[-1] + math.hypot(fine[q + 1][0] - fine[q][0], fine[q + 1][1] - fine[q][1]))
    pts, q = [], 0
    for k in range(DOME_RINGS + 1):
        want = run[-1] * k / DOME_RINGS
        while q < 4095 and run[q + 1] < want:
            q += 1
        f = (want - run[q]) / max(1e-12, run[q + 1] - run[q])
        pts.append((fine[q][0] + f * (fine[q + 1][0] - fine[q][0]),
                    fine[q][1] + f * (fine[q + 1][1] - fine[q][1])))
    pts[-1] = (0.0, rise)
    arc = [0.0]
    for k in range(DOME_RINGS):
        arc.append(arc[-1] + math.hypot(pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1]))
    return pts, arc


DOME_ARC = _dome_profile(SHAFT_R, DOME_RISE)[1][-1]                     # the skin's meridian
COFFER_ARC = _dome_profile(R_INSET, DOME_RISE - DOME_T)[1][-2]          # the coffered soffit's, to the crown
COFFER_ROWS = DOME_RINGS - 1                                            # one coffer a ring band; the crown is plain
COFFER_PX = int(round((COFFER_ARC / COFFER_ROWS) / MPT))                # ... at MPT up the arc


def _dome_vs(rad, rise, cls):
    """v per ring for a dome shell: the meridian's ARC LENGTH at the sheet's
    own density, so a texel is the same size at the spring and at the crown
    (an angle would stretch it, a face fit would shrink it toward the apex).
    The skin continues the shaft's courses across the beam; the coffers start
    a row at the spring and close one at the apex."""
    arc = _dome_profile(rad, rise)[1]
    if cls == "coffer":
        return [float(k) for k in range(len(arc))]      # ring k IS coffer row k: joints on the rings
    return [(DOME_Z0 - V0 + s) / SHEET_M for s in arc]


# ---- the painters: the palette docs/maps/marble.md records, unchanged -------

def _ashlar(c, r, shades, joint, verticals=True, courses=COURSES):
    """Coursed blocks on a sheet one facet wide: a joint line on every course,
    a vertical joint on the facet corner (u = 0) every course, the courses
    half-bonded between, so a joint never stops at a face edge."""
    tx.fill(c, r, c.box, shades)
    rows = [int(round(k * c.h / float(courses))) for k in range(courses)]
    for k, y0 in enumerate(rows):
        y1 = rows[k + 1] if k + 1 < len(rows) else c.h
        c.rect(0, y0, c.w, y0 + 1, joint)
        if not verticals:
            continue
        for x in ([0, c.w // 2] if k % 2 == 0 else [0, c.w // 4, (3 * c.w) // 4]):
            c.rect(x, y0 + 1, x + 1, y1, joint)
    tx.shatter(c, r, c.box, [shades[0], shades[-1]], 16, 4, 9)


def _sheet_stone(c, r, s):
    """The shaft: tower ashlar #8b8160, joints #625b44."""
    _ashlar(c, r, [(139, 129, 96), (135, 125, 92), (143, 133, 100), (137, 127, 94)], (98, 91, 68))


def _sheet_plinth(c, r, s):
    _ashlar(c, r, [(146, 142, 112), (142, 138, 108), (150, 146, 116), (144, 140, 110)], (108, 105, 80))


def _sheet_shade(c, r, s):
    """Grey-olive #6b6b55: reveals, soffits, undersides. Courses only."""
    _ashlar(c, r, [(107, 107, 85), (103, 103, 81), (111, 111, 89), (99, 99, 78)], (80, 80, 66),
            verticals=False)


def _sheet_marble2(c, r, s):
    """The balcony ledge, one repeat a post facet."""
    _ashlar(c, r, [(146, 142, 112), (142, 138, 108), (150, 146, 116), (138, 134, 104)], (102, 99, 74),
            courses=COURSES)


def _sheet_coffer(c, r, s):
    """One sunk coffer, a whole cell of the sheet: #9a9676 stepping down to
    #565542 with a boss, in a grey-olive rib the next coffer shares."""
    W, H = c.w, c.h
    steps = [(154, 150, 118), (130, 127, 100), (108, 106, 84), (86, 85, 66), (96, 95, 76)]
    tx.fill(c, r, c.box, [(107, 107, 85), (103, 103, 81)])
    mx, my = max(2, W // 10), max(2, H // 10)
    for k, col in enumerate(steps):
        dx, dy = mx + (W // 2 - mx) * k // 6, my + (H // 2 - my) * k // 6
        c.rect(dx, dy, W - dx, H - dy, col)
    bw, bh = max(2, W // 14), max(2, H // 14)
    c.rect(W // 2 - bw, H // 2 - bh, W // 2 + bw, H // 2 + bh, (146, 142, 112))
    c.rect(W // 2 - bw // 2, H // 2 - bh // 2, W // 2 + bw // 2, H // 2 + bh // 2, (170, 166, 131))
    tx.blades(c, r, c.box, 30, [(140, 136, 108), (96, 95, 76)])


def _sheet_medallion(c, r, s):
    """The dais' centre, drawn ONCE in a 1 m box the disc fills: a rosette of
    sixteen spokes. Its face is a ring of vertices ABOUT the axis, where a
    polar projection has no frame and would smear one row of texels across it."""
    W, H = c.w, c.h
    cx, cy = W / 2.0, H / 2.0
    pale, olive, mid, dark = (154, 150, 118), (107, 107, 85), (146, 142, 112), (86, 85, 66)
    for y in range(H):
        for x in range(W):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy) / (W * 0.5)
            spoke = int((math.atan2(dy, dx) + math.pi) / (math.pi / 8)) % 2
            if d > 0.94:
                col = olive
            elif d > 0.82:
                col = pale
            elif d > 0.30:
                col = olive if spoke else mid
            elif d > 0.17:
                col = dark
            else:
                col = pale
            c.put(x, y, col)
    tx.blades(c, r, c.box, 40, [(140, 136, 108)])


def _wall(name, paint, seed, width=SHAFT_PX, ref_r=SHAFT_R, u0=U0_SHAFT):
    return tx.Sheet(name, paint, mpt=MPT, size=SHEET_H, width=width, ref_r=ref_r,
                    phase=(u0, V0), roughness=mb.ROUGHNESS, seed=seed)


SHEETS = {
    "stone": _wall("stone", _sheet_stone, 1),                                  # the shaft, the spandrels
    "plinth": _wall("plinth", _sheet_plinth, 2),                               # foot, steps, room floor band, dais
    "shade": _wall("shade", _sheet_shade, 3),                                  # reveals, soffits, undersides
    "marble2": _wall("marble2", _sheet_marble2, 4, BAL_PX, BALCONY_R, U0_BAL),  # the ledge
    "band": tx.Sheet("band", mb._sheet_band, mode="fit_v", width=256, size=64,
                     roughness=mb.ROUGHNESS, seed=5),                          # ring beam, slab edge
    "column": tx.Sheet("column", mb._sheet_column, mode="fit_u", width=64, size=256,
                       roughness=mb.ROUGHNESS, seed=6),
    "iron": tx.Sheet("iron", mb._sheet_iron, mode="fit_u", width=64, size=256,
                     roughness=mb.ROUGHNESS, seed=7),
    "floor": tx.Sheet("floor", mb._sheet_floor, mode="custom", size=64, mpt=2.7 / 64.0,
                      roughness=mb.ROUGHNESS, seed=8),                         # one paving cell a ring band, UVs per vertex
    "medallion": tx.Sheet("medallion", _sheet_medallion, mode="box", size=64,
                          mpt=2.0 * PAVING_RS[0] / 64.0,
                          phase=(-PAVING_RS[0], -PAVING_RS[0]),
                          roughness=mb.ROUGHNESS, seed=9),
    "coffer": tx.Sheet("coffer", _sheet_coffer, mpt=MPT, size=COFFER_PX, width=SHAFT_PX,
                       mode="custom", roughness=mb.ROUGHNESS, seed=10),        # the dome inside
    "dome": tx.Sheet("dome", _sheet_stone, mpt=MPT, size=SHEET_H, width=SHAFT_PX,
                     mode="custom", roughness=mb.ROUGHNESS, seed=11),          # ... and outside
}
# Two faces wear a class their zone does not name, because their PROJECTION
# differs, not their stone: the dome's skin (zone "shade") is "dome", and the
# dais' centre disc (zone "shade") is "medallion".


def _classify(m, n0, cls):
    """Every face emitted since n0 belongs to class `cls`."""
    for pi in range(n0, len(m.faces)):
        m.face_class[pi] = cls



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


# ---- the arcade: the columns are joined by round arches -------------------------

def _arch_us(f, w=COL_W):
    """A facet's head stations, corner to corner: each half arch's segment ends
    and the column's two sides. The pierced panel's TOP edge and the ring
    beam's bottom edge are made of these, and of nothing else."""
    ua = f.post_us(w)[0]
    us = [ua * math.sin(0.5 * math.pi * k / ARCH_SEG) for k in range(ARCH_SEG + 1)]
    return us + [f.L - u for u in reversed(us)]


def _arch_pts(f, w=COL_W):
    """The facet's two HALF arches as (u, z) lists, k = 0 the crown on the
    corner line, k = ARCH_SEG the springing at the column's side: quarter
    circles of radius ua about (0, SPRING_Z) and (L, SPRING_Z). The columns
    stand at the facet centres and the openings straddle the CORNERS, so each
    opening is one round arch of span 2*ua and rise ua, its two halves cut by
    the corner between two facets."""
    ua = f.post_us(w)[0]
    left, right = [], []
    for k in range(ARCH_SEG + 1):
        t = 0.5 * math.pi * k / ARCH_SEG
        u, z = ua * math.sin(t), SPRING_Z + ua * math.cos(t)
        left.append((u, z))
        right.append((f.L - u, z))
    return left, right


def _screen_face(m, f, want):
    """One face of a facet's pierced screen: the column at the facet's centre
    as two stacked panels split at the springing, and the spandrel over each
    half arch, a strip of quads from the arch curve up to the beam."""
    ua, ub = f.post_us(COL_W)

    def P(u, z):
        return m.v(f.at(u, z))

    m.quad(P(ua, FLOOR_Z), P(ub, FLOOR_Z), P(ub, SPRING_Z), P(ua, SPRING_Z), want, "column")
    m.quad(P(ua, SPRING_Z), P(ub, SPRING_Z), P(ub, COL_Z1), P(ua, COL_Z1), want, "column")
    for half in _arch_pts(f):
        for k in range(ARCH_SEG):
            (u0, z0), (u1, z1) = half[k], half[k + 1]
            m.quad(P(u0, z0), P(u1, z1), P(u1, COL_Z1), P(u0, COL_Z1), want, "stone")


def _arcade(m):
    """The colonnade as an ARCADE (Ryan, pass 5: the drawing's columns are
    arches). Per facet a pierced screen COL_W deep between FLOOR_Z and COL_Z1:
    the outer face on the facet chord at SHAFT_R, the inner face in the
    R_INSET facet's OWN frame -- half arch ua_inner = ua - COL_W*tan(pi/NS), so
    its corner points are the shared R_INSET corners and the intrados is a
    slightly warped ruled surface. The jamb reveals run floor to springing, the
    soffit round the head; the panel's top edge is solid corner to corner, so
    the ring beam has no exposed underside and sits on the arches."""
    for ac in _centres():
        f, fi = _Facet(ac, SHAFT_R), _Facet(ac, R_INSET)
        _screen_face(m, f, f.n_out)
        _screen_face(m, fi, fi.n_in)
        ua, ub = f.post_us(COL_W)
        uai, ubi = fi.post_us(COL_W)                       # == ua - COL_W*tan(pi/NS), ub - ...
        for (uo, ui, s) in ((ua, uai, -1.0), (ub, ubi, 1.0)):
            m.quad(m.v(f.at(uo, FLOOR_Z)), m.v(f.at(uo, SPRING_Z)),                  # the jamb reveal
                   m.v(fi.at(ui, SPRING_Z)), m.v(fi.at(ui, FLOOR_Z)), f.dir(s, 0.0), "shade")
        ho, hi = _arch_pts(f), _arch_pts(fi)
        for (a, b, cu) in ((ho[0], hi[0], 0.0), (ho[1], hi[1], f.L)):
            for k in range(ARCH_SEG):                                                # the arch soffit
                (u0, z0), (u1, z1) = a[k], a[k + 1]
                (v0, w0), (v1, w1) = b[k], b[k + 1]
                want = f.dir(cu - 0.5 * (u0 + u1), SPRING_Z - 0.5 * (z0 + z1))       # toward the springing centre
                m.quad(m.v(f.at(u0, z0)), m.v(f.at(u1, z1)),
                       m.v(fi.at(v1, w1)), m.v(fi.at(v0, w0)), want, "shade")


def _head_band(m, f, z0, z1, want, zone):
    """A facet's ring-beam band: its BOTTOM edge is split at the arcade's head
    stations, where the pierced panel's top edge meets it, and its top edge is
    the plain corner-to-corner ring the dome springs from. One polygon, fanned
    from the far top corner, so no triangle is three collinear points."""
    ring = [f.at(f.L, z1), f.at(0.0, z1)] + [f.at(u, z0) for u in _arch_us(f)]
    m.poly([m.v(p) for p in ring], want, zone)


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
    foot_pts = []                                             # the shaft line at the ledge, split at the columns' feet
    for ac in _centres():
        f = _Facet(ac, SHAFT_R)
        ua, ub = f.post_us(COL_W)
        foot_pts += [f.at(0.0, z1), f.at(ua, z1), f.at(ub, z1)]
    edge_pts = lambda rad, z: [(rad * math.cos(a), rad * math.sin(a), z) for a in _corners(NB, POST_PHASE)]
    _zip(m, edge_pts(BALCONY_R, z0), shaft_pts(z0), mb.DOWN, "shade")             # underside
    if coll:
        _band(m, _ringz(m, BALCONY_R, z0, NB, POST_PHASE), _ringz(m, BALCONY_R, POST_TOP, NB, POST_PHASE),
              True, "band")
        _annulus(m, COLL_RAIL_R, BALCONY_R, POST_TOP, True, "band", NB, POST_PHASE)
        _band(m, _ringz(m, COLL_RAIL_R, z1, NB, POST_PHASE), _ringz(m, COLL_RAIL_R, POST_TOP, NB, POST_PHASE),
              False, "band")
        _zip(m, edge_pts(COLL_RAIL_R, z1), foot_pts, mb.UP, "marble2")
        return
    _split_band(m, NB, POST_PHASE, BALCONY_R, POST_W, z0, z1, True, "band", "top")   # the slab's edge
    line = _cut_band(m, NB, POST_PHASE, BALCONY_R, B_INSET, POST_W, z1, mb.UP, "marble2")
    _zip(m, line, foot_pts, mb.UP, "marble2")                                       # the ledge


def _paving(m, inner, outer):
    """One ring band of cells, each split on its slab joints so every joint is an
    edge: rings stay concentric, radials run straight to the axis."""
    n, q = len(inner), PAVE_SUB
    for i in range(n):
        j = (i + 1) % n
        grid = [[m.v(tuple(inner[i][d] + (inner[j][d] - inner[i][d]) * a / q
                           + ((outer[i][d] + (outer[j][d] - outer[i][d]) * a / q)
                              - (inner[i][d] + (inner[j][d] - inner[i][d]) * a / q)) * b / q for d in range(3)))
                 for a in range(q + 1)] for b in range(q + 1)]
        for b in range(q):
            for a in range(q):
                vs = (grid[b][a], grid[b][a + 1], grid[b + 1][a + 1], grid[b + 1][a])
                uv = ((a / q, b / q), ((a + 1) / q, b / q), ((a + 1) / q, (b + 1) / q), (a / q, (b + 1) / q))
                n0 = len(m.faces)
                m.quad(vs[0], vs[1], vs[2], vs[3], mb.UP, "floor", dict(zip(vs, uv)))
                _classify(m, n0, "floor")


def _room(m, coll=False):
    """The room floor, flat with the ledge, with the columns' feet cut out of
    its outer band; the dais under the seat; the arcade (collider: plain
    full-height column boxes, which is all a body can walk into)."""
    line = _cut_band(m, NS, COL_PHASE, SHAFT_R, R_INSET, COL_W, FLOOR_Z, mb.UP, "plinth")
    ring = lambda r, z: [(r * math.cos(a), r * math.sin(a), z) for a in _corners()]
    top = FLOOR_Z + DAIS_H
    if coll:
        _zip(m, line, ring(DAIS_R, FLOOR_Z), mb.UP, "floor")
        _band(m, _ringz(m, DAIS_R, FLOOR_Z), _ringz(m, DAIS_R, top), True, "plinth")
        _disc(m, ring(DAIS_R, top), top, mb.UP, "floor")
    else:
        rings = [ring(r, FLOOR_Z) for r in PAVING_RS]
        _zip(m, line, rings[-1], mb.UP, "shade")                                   # the plain margin
        for k in range(len(rings) - 1, 1, -1):                                     # radial slabs, one cell each
            _paving(m, rings[k - 1], rings[k])
        _band(m, _ringz(m, DAIS_R, FLOOR_Z), _ringz(m, DAIS_R, top), True, "plinth")   # the dais' wall ...
        a, b = [m.v(p) for p in ring(PAVING_RS[0], top)], [m.v(p) for p in ring(DAIS_R, top)]
        for i in range(NS):                                                        # ... its top: the rosette's wedges, plain grey
            j = (i + 1) % NS
            m.quad(a[i], a[j], b[j], b[i], mb.UP, "shade")
        n0 = len(m.faces)
        m.poly(a, mb.UP, "shade")                                                  # its centre: no vertex on the axis,
        _classify(m, n0, "medallion")                                              # where the polar unwrap has no frame
    if coll:
        _posts(m, NS, COL_PHASE, SHAFT_R, COL_W, [FLOOR_Z, COL_Z1], (), "column", top=False)
    else:
        _arcade(m)


def _crown(m, coll=False):
    """The ring beam on the arches' heads, and the dome on the beam."""
    z0, z1 = BEAM
    if coll:                                   # the collider keeps the plain colonnade: a soffit between the column boxes ...
        _cut_band(m, NS, COL_PHASE, SHAFT_R, R_INSET, COL_W, z0, mb.DOWN, "shade")
        _split_band(m, NS, COL_PHASE, SHAFT_R, COL_W, z0, z1, True, "band", "bottom")
        _split_band(m, NS, COL_PHASE, R_INSET, COL_W, z0, z1, False, "band", "bottom", depth=COL_W)
        # ... closed flat: a lid over the beam, a ceiling under it
        _disc(m, [(SHAFT_R * math.cos(a), SHAFT_R * math.sin(a), z1) for a in _corners()], z1, mb.UP, "band")
        _disc(m, [(R_INSET * math.cos(a), R_INSET * math.sin(a), z1) for a in _corners()], z1, mb.DOWN, "shade")
        return
    for ac in _centres():          # the arcade's head is solid corner to corner: NO soffit is exposed,
        f, fi = _Facet(ac, SHAFT_R), _Facet(ac, R_INSET)   # the beam's two faces carry the panel's top edge
        _head_band(m, f, z0, z1, f.n_out, "band")
        _head_band(m, fi, z0, z1, fi.n_in, "band")
    # The two shells state their own UVs (SHEETS "dome" and "coffer" are
    # "custom"): u is the AZIMUTH, one repeat a facet, continuing the shaft's
    # -- so the band closes round with no seam -- and v is the meridian's ARC
    # LENGTH, so a texel is the same size at the spring and at the crown. Each
    # cap triangle gives the apex its OWN u, halfway between its two feet: one
    # pole vertex with one UV is what smears a crown.
    for (rad, rise, outward, zone, cls) in ((SHAFT_R, DOME_RISE, True, "shade", "dome"),
                                            (R_INSET, DOME_RISE - DOME_T, False, "coffer", "coffer")):
        vs = _dome_vs(rad, rise, cls)
        prof = _dome_profile(rad, rise)[0]
        prev = _ringz(m, rad, z1)
        for k in range(1, DOME_RINGS):
            ring = _ringz(m, prof[k][0], z1 + prof[k][1])
            for i in range(NS):
                j = (i + 1) % NS
                pa, pb = m.verts[prev[i]], m.verts[prev[j]]
                er = mb._unit((pa[0] + pb[0], pa[1] + pb[1], 0.0))
                w = (er[0] * rise, er[1] * rise, rad)
                if not outward:
                    w = (-w[0], -w[1], -w[2])
                # a cell fans from its centre: one diagonal kinks a trapezoid's texture, four keep it straight
                cell = (prev[i], prev[j], ring[j], ring[i])
                cuv = ((float(i), vs[k - 1]), (i + 1.0, vs[k - 1]), (i + 1.0, vs[k]), (float(i), vs[k]))
                c = m.v(tuple(sum(m.verts[x][d] for x in cell) / 4.0 for d in range(3)))
                for e in range(4):
                    a, b = cell[e], cell[(e + 1) % 4]
                    n0 = len(m.faces)
                    m.tri(a, b, c, w, zone)
                    m.face_uv[n0] = {a: cuv[e], b: cuv[(e + 1) % 4], c: (i + 0.5, 0.5 * (vs[k - 1] + vs[k]))}
                    _classify(m, n0, cls)
            prev = ring
        apex = m.v((0.0, 0.0, z1 + rise))
        crown_r = prof[-2][0]
        for i in range(NS):
            j = (i + 1) % NS
            n0 = len(m.faces)
            m.tri(prev[i], prev[j], apex, mb.UP if outward else mb.DOWN, "shade")
            if cls == "coffer":        # the crown is plain rib stone, laid flat: a coffer squeezed to a point is pinched
                m.face_uv[n0] = {x: (0.05 + 0.03 * m.verts[x][0] / crown_r, 0.05 + 0.03 * m.verts[x][1] / crown_r)
                                 for x in (prev[i], prev[j], apex)}
            else:
                m.face_uv[n0] = {prev[i]: (float(i), vs[-2]), prev[j]: (i + 1.0, vs[-2]),
                                 apex: (i + 0.5, vs[-1])}
            _classify(m, n0, cls)


def _rock():
    m = mb._Mesh()
    m.face_class = {}                     # face -> the class it wears, when its zone does not name it
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
    c.face_class = {}
    _shaft(c)
    _balcony(c, coll=True)
    _room(c, coll=True)
    _crown(c, coll=True)
    return c


def arch_span():
    """The arches, as numbers: (span, rise, crown z). An opening straddles a
    facet corner, so its half span is that facet's own ua on either side."""
    ua = _Facet(_centres()[0], SHAFT_R).post_us(COL_W)[0]
    return 2.0 * ua, ua, SPRING_Z + ua


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
    shot("room", mb.pol(200.0, 4.6, FLOOR_Z + mb.EYE_H), mb.pol(20.0, 2.5, FLOOR_Z + 0.3), 16.0, (1400, 900))
    # the dome from under it, the guard's own view of the coffers and the crown
    shot("dome", mb.pol(200.0, 6.0, FLOOR_Z + mb.EYE_H), (0.0, 0.0, DOME_Z0 + 0.35 * DOME_RISE), 16.0, (1400, 900))
    for ob in (target, cam, sun, room):
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    rock, counts = _rock()
    coll = _collider()
    ob = rock.object(OBJECT_NAME)
    classes = [rock.face_class.get(pi, z) for pi, z in enumerate(rock.zones)]
    tx.unwrap(ob, classes, SHEETS, seed=3, face_uv=rock.face_uv, groups=rock.groups)
    mats = tx.materials(NAME, SHEETS, use_files=USE_TEXTURE_FILES, tex_dir=os.path.join(HERE, TEX_DIR))
    for mat in mats.values():
        mat.diffuse_color = (0.78, 0.76, 0.72, 1.0)
    order = tx.finish(ob, classes, mats)
    tx.report(SHEETS)
    print("MDL STATS surfaces=%d order=%s" % (len(ob.data.materials), ",".join(order)))
    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    a = mb.audit(rock, "tower")
    print("MDL STATS visual_tris=%d collision_tris=%d shaft=%d balcony=%d room=%d crown=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), counts["shaft"], counts["balcony"],
             counts["room"], counts["crown"]))
    print("MDL STATS contiguity components=%d boundary=%d doubled=%d over=%d degenerate=%d dup_pos=%d"
          % (a["components"], a["boundary_edges"], a["doubled_edges"], a["over_edges"], a["degenerate"],
             a["duplicate_positions"]))
    span, rise, crown = arch_span()
    print("MDL STATS floor_z=%.2f dais=%.2f eye_z=%.2f shaft_r=%.1f columns=%d col_w=%.2f arches=%d "
          "spring_z=%.2f arch_span=%.2f arch_rise=%.2f arch_crown=%.2f spandrel=%.2f beam_z=%.2f "
          "balcony_z=%.2f balcony_r=%.1f rail_top=%.2f sightline_clear=%.2f dome=%.2f..%.2f foot_z=%.2f"
          % (FLOOR_Z, DAIS_H, GUARD_EYE, SHAFT_R, NS, COL_W, NS, SPRING_Z, span, rise, crown,
             COL_Z1 - crown, COL_Z1, BALCONY_Z, BALCONY_R, POST_TOP,
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
    span, rise, crown = arch_span()
    print("arcade: %d round arches, span %.2f rise %.2f, spring %.2f crown %.2f, spandrel %.2f to the beam at %.2f"
          % (NS, span, rise, SPRING_Z, crown, COL_Z1 - crown, COL_Z1))
    print("sightline clears the rail top by %.2f m (rail %.2f at r %.1f)" % (sightline_clearance(), POST_TOP, BALCONY_R))
    for cls in sorted(SHEETS):
        sh = SHEETS[cls]
        if sh.mode == "cyl":
            sh.ring((sh.ref_r, 0.0, 0.0))
    tx.report(SHEETS)
    print("dome skin: arc %.2f m, %.4f m/texel up the meridian, %.4f m across at the spring"
          % (DOME_ARC, SHEET_M / SHEET_H, mb.TWO_PI * SHAFT_R / NS / SHAFT_PX))
    print("coffers: arc %.2f m, %d rows of %.2f m (%d texels), %.4f m/texel up the meridian"
          % (COFFER_ARC, COFFER_ROWS, COFFER_ARC / COFFER_ROWS, COFFER_PX,
             (COFFER_ARC / COFFER_ROWS) / COFFER_PX))
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
