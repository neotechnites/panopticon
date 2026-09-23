"""
PANOPTICON -- forest: Map 3. A clearing under a closed canopy: a grass lane
round a ravine, a great tree in the middle (forest_tree.glb, the tower), a
wall of leaves you cannot see through, cells cut into it with branch bars,
and shafts of sun coming down through the leaves from one side.

Authored in WORLD coordinates so the scene instances it at identity
(Blender +Z -> Godot +Y, Blender +Y -> Godot -Z; bearings as map 1's pol()):

    pit floor ........  y -11.05  dark earth under the fog, r 42 (map 1's sea height)
    lane .............  y 23.0    grass, r 46.7..57.3, as map 1; a worn path down its middle
    leaf wall ........  r 57.3 at the foot, 60 at the gallery roof; bark pilasters bulge out
    gallery roof .....  y 36.0    dense leaf over the lane only, r 60 in to the pit lip
    wall above it ....  y 36..64  at r ~47: six more tiers of barred cells, over the ravine
    canopy dome ......  y 64 at that wall's head to 77.4 over the tree: the grand roof

ONE CONTIGUOUS mesh (ForestGround), one surface (the forest atlas). Every part shares vertices with what it grows from: the grids
share their seam rows, the water rings inward from the bank's last row, ferns,
hummocks, cell bars and the hanging roots are socketed into the
quads they stand on (_Mesh.socket), the forest trunks are wall columns pushed
toward the lane. Nothing merely overlaps its host.

The sun rays are two more nodes behind MESH_RAYS: ForestRaysSolid (pale
yellow shafts, alpha 0.35) and ForestRaysSoft (the same shafts, faint, for
the scene's DirectionalLight variant). A shaft is three vanes of a strip
crossed on the sun's line, tint and feather in the vertex colour (COLOR_0):
alpha peaks on the axis, is zero along both edges and at both ends, so a
shaft has no cap and no hard edge; it starts under the closed canopy and
runs into the ground it lands on. ForestCollision rides as a `-colonly` node: flat
lane, pit cone, water floor, flat wall with a prism per trunk, flat ceiling
annulus. The leafy visual mesh is never its own
collider.

Textures: one tiling sheet per class (lib/texel.py, SHEETS below: grass,
verge, path, edge, leaf, shade, sun, fern, bark, earth, cell, root), painted
here in forest_tree_build's palette, world-projected at texel.MPT m per texel;
textures/forest_<class>_albedo.png (+ _emissive.png) replaces a painted sheet
when ft.USE_TEXTURE_FILES is on. The props keep the forest atlas.
The leaf ceiling (sheet, shafts, limbs, clumps, vines) is forest_ceiling_build;
the pit's dark floor, fog layers (ForestFog: stacked translucent discs, alpha in
COLOR_0, for GL Compatibility) and thorny brambles are forest_pit_build.

    tools/modelling/model build forest
    python3 tools/modelling/forest_build.py --check
"""

import math
import os
import sys

try:
    import bpy
except ImportError:                       # --check on the Mac: geometry only
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, HERE + os.sep + "lib")
import texel as tx  # noqa: E402  one tiling sheet per class, world-projected
if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["ground"] = False
    mdl.DEFAULTS["world_grey"] = 0.34
    mdl.DEFAULTS["world_strength"] = 0.95

import forest_tree_build as ft  # noqa: E402
from forest_tree_build import (_Mesh, _Rng, UP, DOWN, pol, radial, tangent, add, sub, norm, dot,  # noqa: E402
                               lerp, bez, loft, zipper, plane_of)
import forest_ceiling_build as fc  # noqa: E402  the leaf ceiling: sheet, shafts, limbs, clumps, vines
import forest_pit_build as fp  # noqa: E402  the pit: dark floor, fog layers, thorny brambles

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "forest"
OBJECT_NAME = "ForestGround"
COLLIDER_NAME = "ForestCollision-colonly"
RAYS_SOLID_NAME = "ForestRaysSolid"
RAYS_SOFT_NAME = "ForestRaysSoft"
MESH_RAYS = True            # export the ray wedges (both nodes) in the .glb
FACING_YAW = 0.0

NC = 240                    # columns round the ring: 1.5 deg, 1.5 m at the wall foot
INNER_R = 46.7
OUTER_R = 57.3
DECK_Z = 23.0
WATER_Z = -11.05            # map 1's lava sea height: the pit is 34 m deep
WATER_R = 42.0
CEIL_Z = fc.GALLERY_Z       # the gallery roof over the lane (the dome and its shafts live in forest_ceiling_build)
SEED = 9110271
EYE_H = 1.65

DECK_RST = [46.7, 47.6, 49.0, 50.5, 52.0, 53.5, 55.6, 57.3]
DECK_AMP = 0.12             # the lane's 2-D relief, zero at both edges
PATH_BAND = (50.5, 53.5)    # the worn path down the lane's middle: zone "path"; "verge" one row either side
LIP_ROW, FOOT_ROW = 0, 6    # the deck bands that take ferns: the lip and the wall foot
LIP_FERN_R, FOOT_FERN_R = 47.15, 56.6      # where a fern's crown sits in those bands


def _pit_profile():
    """(r, z) rows lip to water: a 1 m round-over, 1.8 m rows to z 3.5, then 2.425 m
    rows to the water. The last row IS the water's outer ring."""
    rows = [(46.7, 23.0), (46.35, 22.88), (45.85, 22.55), (45.2, 21.5)]
    zs = [21.5 - 1.8 * k for k in range(1, 11)] + [3.5 - 2.425 * k for k in range(1, 6)]
    for z in zs:
        u = (z - WATER_Z) / (21.5 - WATER_Z)
        rows.append((round(WATER_R + (45.2 - WATER_R) * u ** 1.5, 3), round(z, 3)))
    rows.append((WATER_R, WATER_Z))
    return rows


PIT = _pit_profile()
PIT_JAG = (3, len(PIT) - 2, 0.35, 0.25)   # rows a..b get radial and z wander this big
PIT_ROOTS = 14              # root ribs down the bank: columns pushed out of it
PIT_ROOT_PUSH = 0.28
PIT_ROOT_ROWS = (3, len(PIT) - 2)

WALL = [(57.3, 23.0), (57.3, 23.3), (57.35, 25.05), (57.5, 26.8), (58.0, 28.6),
        (58.8, 30.6), (59.3, 31.8), (59.65, 33.6), (60.0, CEIL_Z)]   # (r, z) foot to the gallery roof
WALL_BULGE = 0.45           # outward-only on the low rows, both ways above
WALL_ZJAG = 0.3

SUN = (120.0, 52.0)         # the sun's bearing and elevation: rays come from this side
RAY_W = (0.9, 1.15)         # a shaft's half width at the top and at the foot for a 3 m source: 1.8 m,
                            # spreading gently to 2.3 over its fall; the source's own size scales both
RAY_IN = -0.45              # the shaft starts this far UNDER the closed canopy, so its source is never seen
RAY_OVER = 0.6              # ... and runs this far into whatever it lands on
RAY_FADE = (0.18, 0.82)     # along the shaft, alpha ramps up to here and back down from here
RAY_VANES = 3               # planes crossed on the axis: something faces every camera
RAY_SOLID = ((1.0, 0.93, 0.60), 0.14)   # tint, peak alpha PER VANE: three vanes overlap on the axis,
RAY_SOFT = ((1.0, 0.95, 0.72), 0.05)    # so a shaft reads at 0.25..0.35 (solid) and faint (soft)

# forest trunks: five wall columns each, pushed toward the lane as a bark pilaster
TRUNKS = [8.0, 38.0, 66.0, 92.0, 120.0, 148.0, 176.0, 204.0, 232.0, 258.0, 286.0, 342.0]
TRUNK_PUSH = 1.0            # the centre column's protrusion at the wall ...
TRUNK_PROFILE = (0.0, 0.707, 1.0, 0.707, 0.0)   # ... r = wall - PUSH * cos(t) across the five
TRUNK_FLARE = (1.3, 1.15)   # the root flare: wall rows 0 and 1 push this much more
TRUNK_WANDER = 0.06

WALL_CELLS = [22.0, 50.0, 78.0, 104.0, 131.0, 158.0, 186.0, 212.0, 240.0, 268.0, 296.0, 318.0]
WALL_CELL_ROWS = (1, 2, 3)  # sill, jamb, apex rows of WALL: the lane tier, sill 0.3 m over the grass
# the upper tier: two per bay between neighbouring TRUNKS, 6..7.5 deg either side of the bay's
# lower cell so the tiers stagger like brick; none between 328 and 12 deg (the portal, the bars)
# and none nearer a trunk than 4.5 deg (two bays only fit one, so the wide 286..342 bay takes four)
WALL_CELLS_UPPER = [15.0, 30.0, 43.5, 57.0, 72.0, 84.0, 97.5, 111.0, 124.5, 138.0, 153.0, 165.0,
                    180.0, 193.5, 219.0, 247.5, 262.5, 276.0, 291.0, 303.0, 310.5, 325.5]
WALL_CELL_ROWS_UPPER = (4, 5, 6)   # sill 28.6, jamb 30.6, apex 31.8: 4 m of leaf to the gallery roof
WALL_TIERS = ((WALL_CELLS, WALL_CELL_ROWS), (WALL_CELLS_UPPER, WALL_CELL_ROWS_UPPER))
WALL_CELL_D = 2.5

# The wall above the gallery roof: a leaf cliff at r ~47 standing on the roof's inner
# rim, carrying six more tiers of barred cells over the ravine -- map 1's wall above
# its deck. (r, z) rows: rim, then sill / jamb / apex per tier, then two plain leaf
# rows to the dome's spring.
UPPER = [(46.70, fc.GALLERY_Z), (46.73, 36.50), (46.85, 38.50), (46.92, 39.70),
         (46.99, 40.70), (47.11, 42.70), (47.18, 43.90),
         (47.24, 44.90), (47.36, 46.90), (47.43, 48.10),
         (47.49, 49.10), (47.61, 51.10), (47.69, 52.30),
         (47.75, 53.30), (47.87, 55.30), (47.94, 56.50),
         (48.00, 57.50), (48.12, 59.50), (48.19, 60.70),
         (48.28, 62.30), (fc.DOME[0][0], fc.DOME[0][1])]
UPPER_BULGE = 0.35          # outward-only: the leaf never overhangs the rim
UPPER_ZJAG = 0.25
UPPER_TIER_ROWS = ((1, 2, 3), (4, 5, 6), (7, 8, 9), (10, 11, 12), (13, 14, 15), (16, 17, 18))
_UP_STEP = 360.0 / 17.0
# 17 a tier, one every 17 m of wall; every other tier half a bay off, like brick
UPPER_CELLS = [[off + _UP_STEP * k for k in range(17)] for off in (10.6, 0.0) * 3]
UPPER_TIERS = tuple(zip(UPPER_CELLS, UPPER_TIER_ROWS))
UPPER_CELL_D = 2.0          # shallower and coarser than the lane's: they are read at 50..95 m
UPPER_BAR_R = (0.06, 0.08)
UPPER_BAR_PITCH = 0.8
_PIT_CELL_ROWS = [(7, 1), (12, 2), (16, 1), (9, 1), (14, 1), (18, 1),
                  (6, 1), (11, 2), (15, 1), (8, 2), (13, 1), (17, 1)]   # (sill row of PIT, bands tall)
PIT_CELLS = [(k * 10.0 + (0.0, 3.5, 6.5)[k % 3],) + _PIT_CELL_ROWS[k % 12] for k in range(36)]
PIT_CELL_D = 2.2
BAR_R = (0.055, 0.075)      # the leaf wall's bars ...
PIT_BAR_R = (0.08, 0.1)     # ... and the pit's, thicker: their spans are longer
BAR_PITCH = 0.5
PIT_BAR_PITCH = 0.75
BAR_SET = 0.2               # bars stand this far behind the mouth plane
BAR_SHELF = 0.45            # the recess floor / roof / jamb strip the bars socket into
BAR_SEG = 1.2               # metres per bar segment

FERNS_WALL = 33
FERNS_LIP = 22
FERN_BLADES = (5, 7)
FERN_L = (0.6, 1.0)
FERN_W = (0.2, 0.3)
FERN_BASE = 0.32            # the crown's 4-vertex socket ring on the deck ...
FERN_RING = 0.18            # ... rises into this 8-ring well inside it (the 4-to-8 zipper never folds)
FERN_CROWN = (0.09, 0.08, 0.16, 0.22)   # inner ring radius; lifts of the 8-ring, the inner ring, the top
FERN_FLAT = 0.35            # a blade's thickness as a fraction of its half width
HUMMOCKS = 22
HUMMOCK_BASE = 0.5          # the 4-vertex socket ring ...
HUMMOCK_RING = 0.3          # ... rises into this 8-ring well inside it
HUMMOCK_H = 0.32
HANG_ROOTS = 10

REVIEW_SUN = 6.0            # review renders only: the sun from SUN, watts, shadows on (light variant)
REVIEW_FILL = 1.1           # ... a second sun from the far side, no shadows
REVIEW_WORLD = 1.0
REVIEW_WORLD_VARIANT = {"solid": 1.2, "light": 0.75}   # the mesh-only variant has no sun to help it
REVIEW_SKY = (0.72, 0.80, 0.70)   # the world's fill light, pale and a little green
REVIEW_SEEN = (0.30, 0.38, 0.33)  # the sky a camera ray that clears the canopy sees: pale and a little green once REVIEW_EXPOSURE (stops) has lifted it
REVIEW_EXPOSURE = 0.9

TWO_PI = 2.0 * math.pi
INFO = {}                   # what the renders and the stats need


# =============================================================================
# FIELDS
# =============================================================================

def _field(r, n=6, wl=(2.5, 7.0)):
    """A smooth 2-D field of unit amplitude: a sum of n sines at random headings."""
    waves = []
    for _ in range(n):
        a = r.f() * TWO_PI
        L = r.u(*wl)
        waves.append((math.cos(a) * TWO_PI / L, math.sin(a) * TWO_PI / L, r.f() * TWO_PI))

    def f(x, y):
        return sum(math.sin(kx * x + ky * y + ph) for (kx, ky, ph) in waves) / n

    return f


def _col_bearing(i):
    return (i % NC) * 360.0 / NC


def _col_of(bearing):
    return int(round(bearing / (360.0 / NC))) % NC


def _bearing_of(p):
    return -math.degrees(math.atan2(p[1], p[0]))


def dist(p, q):
    return math.sqrt(sum((p[k] - q[k]) ** 2 for k in range(3)))


def _on_plane(plane, p, along):
    """Where the line p + s*along meets the plane (point, normal)."""
    c, n = plane
    d = dot(along, n)
    if abs(d) < 1e-6:
        return p
    return add(p, along, dot(sub(c, p), n) / d)


def _near(b, target, deg):
    return abs(((b - target) + 180.0) % 360.0 - 180.0) < deg


# =============================================================================
# WELDED TUBES -- end rings phased so the socket bridging has no slivers or folds
# =============================================================================

def _min_angle(pts):
    out = math.pi
    for k in range(3):
        p, q, s = pts[k], pts[(k + 1) % 3], pts[(k + 2) % 3]
        u, v = sub(q, p), sub(s, p)
        lu, lv = math.sqrt(dot(u, u)), math.sqrt(dot(v, v))
        if lu < 1e-12 or lv < 1e-12:
            return 0.0
        out = min(out, math.acos(max(-1.0, min(1.0, dot(u, v) / (lu * lv)))))
    return out


def _patch_frame(m, patch):
    """socket()'s own view of a patch: its mean normal, the angular frame it sorts
    in, and the patch's vertex ids (all on the boundary for the strips used here)."""
    nsum = (0.0, 0.0, 0.0)
    ids = []
    for q in patch:
        for fi in m.quads[frozenset(q)]:
            nsum = add(nsum, ft._newell([m.verts[j] for j in m.faces[fi]]))
        for v in q:
            if v not in ids:
                ids.append(v)
    n = norm(nsum)
    ex = norm(ft.cross(n, (0.0, 0.0, 1.0) if abs(n[2]) < 0.9 else (1.0, 0.0, 0.0)))
    ey = ft.cross(n, ex)
    return n, ex, ey, ids


def _bridge_quality(loop_pts, ring_pts, n, ex, ey):
    """The smallest angle socket() would make bridging this ring to this loop;
    zero if any bridging triangle folds against the patch."""
    c = tuple(sum(p[k] for p in ring_pts) / len(ring_pts) for k in range(3))

    def ang(p):
        d = sub(p, c)
        return math.atan2(dot(d, ey), dot(d, ex))

    L = sorted(loop_pts, key=ang)
    R = sorted(ring_pts, key=ang)
    aL, aR = [ang(p) for p in L], [ang(p) for p in R]
    i = j = 0
    nl, nr = len(L), len(R)
    worst = math.pi
    while i < nl or j < nr:
        next_l = aL[i + 1] if i + 1 < nl else aL[0] + TWO_PI
        next_r = aR[j + 1] if j + 1 < nr else aR[0] + TWO_PI
        li, ri = L[i % nl], R[j % nr]
        if (i < nl and next_l <= next_r) or j >= nr:
            tri = (li, L[(i + 1) % nl], ri)
            i += 1
        else:
            tri = (li, R[(j + 1) % nr], ri)
            j += 1
        worst = min(worst, _min_angle(tri))
        if dot(ft._newell(tri), n) <= 0.0:
            return 0.0
    return worst


def _best_ring(m, patch, pts_fn, zone, steps=24):
    """Create a ring on ``patch`` at the phase (of ``steps`` round the circle)
    whose bridging is best, and socket it. pts_fn(phase) -> the ring's points,
    on the patch. Returns (ids, phase)."""
    n, ex, ey, loop = _patch_frame(m, patch)
    loop_pts = [m.verts[v] for v in loop]
    best = None
    for k in range(steps):
        ph = TWO_PI * k / steps
        pts = pts_fn(ph)
        q = _bridge_quality(loop_pts, pts, n, ex, ey)
        if best is None or q > best[0]:
            best = (q, ph, pts)
    ids = [m.v(p) for p in best[2]]
    m.socket(patch, ids, zone)
    return ids, best[1]


def _ring_at(centre, ex, ez, radius, sides, flat, phase, wob=0.0, rng=None):
    pts = []
    for s in range(sides):
        a = phase + TWO_PI * s / sides
        rr = radius * (1.0 + wob * rng.sf()) if (wob and rng) else radius
        pts.append(add(add(centre, ex, rr * math.cos(a)), ez, rr * math.sin(a) * flat))
    return pts


def _ptube(m, path, radii, sides, zone, start=None, end=None, flat=1.0, wob=0.0, rng=None,
           caps=(True, True), twist="spread"):
    """A tapered n-gon tube along ``path`` whose ends grow out of surfaces:
    ``start`` / ``end`` are (patch quads, bridging zone); that end's ring is
    projected onto the patch along the tube and socketed there, at the phase
    that bridges best. The rings between follow the phase, twisting gently from
    one end's to the other's ("spread") or only in the last segment ("end").
    ``flat`` squashes the rings (a table along the path, or one value). Free
    ends are capped when ``caps`` says so. Returns the rings."""
    n = len(path)
    fr = ft.frames(path)
    rings = [None] * n
    ph0 = ph1 = None
    sym = TWO_PI / sides
    flat_at = (lambda u: ft._at(flat, u)) if isinstance(flat, (tuple, list)) else (lambda u: flat)

    def weld(i, spec, radius, fl):
        t, ex, ez = fr[i]
        patch, zn = spec
        pn, _sx, _sy, loop = _patch_frame(m, patch)
        plane = (m.centroid(loop), pn)
        pts_fn = lambda ph: ft.project_ring(_ring_at(path[i], ex, ez, radius, sides, fl, ph), t, plane)
        return _best_ring(m, patch, pts_fn, zn)

    if start is not None:
        rings[0], ph0 = weld(0, start, ft._at(radii, 0.0), flat_at(0.0))
    if end is not None:
        rings[-1], ph1 = weld(n - 1, end, ft._at(radii, 1.0), flat_at(1.0))
    if ph0 is None:
        ph0 = 0.0 if (ph1 is None or twist == "end") else ph1
    if ph1 is None:
        ph1 = ph0
    d = (ph1 - ph0) % sym                    # the short way round, the ring's symmetry allowing
    if d > sym * 0.5:
        d -= sym
    if end is not None:                      # re-index the end ring to the phase the tube arrives at
        k = int(round((ph0 + d - ph1) / sym)) % sides
        rings[-1] = rings[-1][k:] + rings[-1][:k]
    for i in range(n):
        if rings[i] is not None:
            continue
        u = i / float(n - 1)
        if twist == "end":
            ph = ph0 if i < n - 1 else ph0 + d
        else:
            ph = ph0 + d * u
        t, ex, ez = fr[i]
        rings[i] = [m.v(p) for p in _ring_at(path[i], ex, ez, ft._at(radii, u), sides, flat_at(u), ph, wob, rng)]
    for i in range(n - 1):
        axis = lerp(path[i], path[i + 1], 0.5)
        for s in range(sides):
            q = (s + 1) % sides
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), axis), zone)
    if caps[0] and start is None:
        m.fan(rings[0], (-fr[0][0][0], -fr[0][0][1], -fr[0][0][2]), zone)
    if caps[1] and end is None:
        m.fan(rings[-1], fr[-1][0], zone)
    return rings


# =============================================================================
# THE GROUND -- one mesh, built as grids that share their seam vertices
# =============================================================================

class _Ground(object):
    def __init__(self):
        self.m = _Mesh()
        self.r = _Rng(SEED)
        self.deck_f = _field(self.r)
        self.bank_f = _field(self.r, wl=(3.0, 9.0))
        self.wall_f = _field(self.r, wl=(2.0, 5.0))
        self.ceil_f = _field(self.r, wl=(3.0, 8.0))
        self.ceil_pole = None
        self.deck = []      # deck[j][i] vertex ids, j over DECK_RST
        self.pit = []       # pit[j][i], j over PIT
        self.wall = []      # wall[j][i], j over WALL
        self.gal = []       # gal[k][i], k over fc.GALLERY_R: the roof over the lane
        self.upper = []     # upper[j][i], j over UPPER: the wall above that roof
        self.dome = []      # dome[k][i], k over fc.DOME (its own count each)
        self.wall_cells = []
        self.upper_cells = []
        self.pit_cells = []
        self.pit_root_cols = set()
        self.trunk_cols = {}        # wall column -> index into TRUNK_PROFILE
        self.bark_cols = set()      # wall quads (by their left column) that are bark
        for b in TRUNKS:
            c0 = _col_of(b)
            for k in range(5):
                self.trunk_cols[(c0 + k - 2) % NC] = k
            for k in range(4):
                self.bark_cols.add((c0 + k - 2) % NC)
        self.taken = set()  # deck quads (row, col) that carry a fern or a hummock
        self.split = {}     # (id a, id b) -> ids lying on that grid edge, a to b: the bar strips' boundaries
        self.hollow = {"pit": set(), "wall": set(), "upper": set()}   # grid (row, col) inside a mouth: no vertex there
        for (b, s, h) in PIT_CELLS:
            for k in range(1, h + 1):
                self.hollow["pit"].add((s - k, (_col_of(b) + 1) % NC))
        for (cells, rows) in WALL_TIERS:                 # the jamb row's middle vertex of every mouth
            for b in cells:
                self.hollow["wall"].add((rows[1], (_col_of(b) + 1) % NC))
        self.hollow["upper"] = set()
        for (cells, rows) in UPPER_TIERS:
            for b in cells:
                self.hollow["upper"].add((rows[1], (_col_of(b) + 1) % NC))
        self.rays = []      # (a shaft source's four corner points, its half width at the top) per shaft: fc fills it

    def _trunk_push(self, i, j):
        """How far wall column i is pushed toward the lane at wall row j: the pilasters."""
        k = self.trunk_cols.get(i)
        if k is None or TRUNK_PROFILE[k] == 0.0:
            return 0.0
        f = TRUNK_FLARE[j] if j < len(TRUNK_FLARE) else 1.0
        return TRUNK_PUSH * TRUNK_PROFILE[k] * f + TRUNK_WANDER * self.r.sf()

    # ---- grids -------------------------------------------------------------
    def _deck_rows(self):
        m = self.m
        last = len(DECK_RST) - 1
        for j, rad in enumerate(DECK_RST):
            row = []
            w = math.sin(math.pi * (rad - INNER_R) / (OUTER_R - INNER_R))
            for i in range(NC):
                rr = rad - (self._trunk_push(i, 0) if j == last else 0.0)
                p = pol(_col_bearing(i), rr, DECK_Z)
                z = DECK_Z + DECK_AMP * w * self.deck_f(p[0], p[1])
                row.append(m.v((p[0], p[1], z)))
            self.deck.append(row)

    def _pit_rows(self):
        m = self.m
        lo, hi, rj, zj = PIT_JAG
        self.pit.append(self.deck[0])                        # the lip is the deck's edge
        for j, (rad, z) in enumerate(PIT[1:], start=1):
            row = []
            for i in range(NC):
                if (j, i) in self.hollow["pit"]:
                    row.append(None)
                    continue
                b = _col_bearing(i)
                rr, zz = rad, z
                if lo <= j <= hi:
                    p = pol(b, rad, z)
                    rr += rj * self.bank_f(p[0] * 0.6, z * 0.8)
                    zz += zj * self.bank_f(p[1] * 0.6, z * 0.8 + 40.0)
                    if i in self.pit_root_cols and PIT_ROOT_ROWS[0] <= j <= PIT_ROOT_ROWS[1]:
                        rr -= PIT_ROOT_PUSH * math.sin(math.pi * (j - PIT_ROOT_ROWS[0]) / (PIT_ROOT_ROWS[1] - PIT_ROOT_ROWS[0]))
                row.append(m.v(pol(b, rr, zz)))
            self.pit.append(row)

    def _wall_rows(self):
        m = self.m
        mouths = set()      # (row, col) on a mouth's outline, sill to apex, either tier: no bulge there
        for (cells, rows) in WALL_TIERS:
            for b in cells:
                c0 = _col_of(b)
                for j in range(rows[0], rows[2] + 1):
                    for i in (c0, c0 + 1, c0 + 2):
                        mouths.add((j, i % NC))
        self.wall.append(self.deck[-1])                      # the foot is the deck's edge
        for j, (rad, z) in enumerate(WALL[1:], start=1):
            row = []
            for i in range(NC):
                if (j, i) in self.hollow["wall"]:
                    row.append(None)
                    continue
                b = _col_bearing(i)
                rr, zz = rad, z
                push = self._trunk_push(i, j)
                if push > 0.0:
                    rr -= push
                elif (j, i) not in mouths:
                    p = pol(b, rad, z)
                    f = self.wall_f(p[0] * 0.7, z * 0.9)
                    rr += WALL_BULGE * (0.5 + 0.5 * f) if j <= 3 else WALL_BULGE * f
                    if 2 <= j < len(WALL) - 1:
                        zz += WALL_ZJAG * self.wall_f(p[1] * 0.7, z + 30.0)
                row.append(m.v(pol(b, rr, zz)))
            self.wall.append(row)

    def _upper_rows(self):
        """The wall above the gallery roof: rows standing on the roof's inner rim,
        leaning out a little so nothing overhangs, its own leaf bulge."""
        m = self.m
        mouths = set()
        for (cells, rows) in UPPER_TIERS:
            for b in cells:
                c0 = _col_of(b)
                for j in range(rows[0], rows[2] + 1):
                    for i in (c0, c0 + 1, c0 + 2):
                        mouths.add((j, i % NC))
        self.upper.append(self.gal[-1])                     # the gallery roof's inner rim
        for j, (rad, z) in enumerate(UPPER[1:], start=1):
            row = []
            for i in range(NC):
                if (j, i) in self.hollow["upper"]:
                    row.append(None)
                    continue
                b = _col_bearing(i)
                rr, zz = rad, z
                if (j, i) not in mouths:
                    p = pol(b, rad, z)
                    f = self.wall_f(p[0] * 0.7, z * 0.9 + 70.0)
                    rr += UPPER_BULGE * (0.5 + 0.5 * f)
                    if j < len(UPPER) - 1:
                        zz += UPPER_ZJAG * self.wall_f(p[1] * 0.7, z + 90.0)
                row.append(m.v(pol(b, rr, zz)))
            self.upper.append(row)

    # ---- faces -------------------------------------------------------------
    def _deck_quad(self, j, i):
        q = (i + 1) % NC
        return (self.deck[j][i], self.deck[j][q], self.deck[j + 1][q], self.deck[j + 1][i])

    def _deck_faces(self):
        m = self.m
        for j in range(len(DECK_RST) - 1):
            if DECK_RST[j] >= PATH_BAND[0] - 0.01 and DECK_RST[j + 1] <= PATH_BAND[1] + 0.01:
                zone = "path"
            elif DECK_RST[j + 1] >= PATH_BAND[0] - 0.01 and DECK_RST[j] <= PATH_BAND[1] + 0.01:
                zone = "verge"               # the band either side of the path
            else:
                zone = "grass"
            for i in range(NC):
                ids = self._deck_quad(j, i)
                m.quad(ids[0], ids[1], ids[2], ids[3], UP, zone)

    def _cell_faces(self, grid, cells, depth, dirn, zone_wall, mouth_zone, bar_r, pitch, rung):
        """Grid faces for a wall with pointed-arch cells cut into it. ``cells`` is
        [(col, sill_row, h)], the mouth 2 columns wide and h bands tall; ``dirn``
        is +1 when row indices climb (the leaf wall), -1 when they descend (the
        pit bank): the jamb row is sill + h dirn, the apex one band on. Both
        walls face the axis. Returns the cells as (mouth ids, back ids, bearing)."""
        m = self.m
        skip = {}
        for (c0, s, h) in cells:
            jamb, apex = s + h * dirn, s + (h + 1) * dirn
            for i in (c0, c0 + 1):
                for k in range(h):
                    skip[(i % NC, min(s + k * dirn, s + (k + 1) * dirn))] = ("mouth",)
                skip[(i % NC, min(jamb, apex))] = ("arch", c0 % NC, jamb)
        made = []
        for (c0, s, h) in cells:              # first: the recesses split the sill and arch lines
            made.append(self._recess(grid, c0, s, h, depth, dirn, mouth_zone, bar_r, pitch, rung))
        for j in range(len(grid) - 1):
            for i in range(NC):
                q = (i + 1) % NC
                key = (i, j)
                if key in skip:
                    if skip[key][0] == "mouth":
                        continue
                    _, c0, jamb = skip[key]
                    self._arch_tris(grid, i, c0, jamb, dirn, zone_wall(j, i))
                    continue
                ids = (grid[j][i], grid[j][q], grid[j + 1][q], grid[j + 1][i])
                c = m.centroid(ids)
                want = (-c[0], -c[1], 0.0)
                lo = self._edge(ids[0], ids[1])
                hi = self._edge(ids[2], ids[3])
                if lo:
                    self._fan_poly([ids[3], ids[0]] + lo + [ids[1], ids[2]], want, zone_wall(j, i))
                elif hi:
                    self._fan_poly([ids[0], ids[1], ids[2]] + hi + [ids[3]], want, zone_wall(j, i))
                else:
                    m.quad(ids[0], ids[1], ids[2], ids[3], want, zone_wall(j, i))
        return made

    def _fan_poly(self, loop, want, zone):
        """A polygon fanned from loop[0]."""
        for k in range(1, len(loop) - 1):
            self.m.tri(loop[0], loop[k], loop[k + 1], want, zone)

    def _edge(self, a, b):
        """The ids strictly between a and b along a split grid edge, a to b."""
        if (a, b) in self.split:
            return self.split[(a, b)]
        return list(reversed(self.split.get((b, a), [])))

    def _arch_tris(self, grid, i, c0, jamb, dirn, zone):
        """The band between the jamb row and the apex row over a mouth: the wall
        keeps one triangle either side of the pointed arch."""
        m = self.m
        apex = jamb + dirn
        c1, c2 = (c0 + 1) % NC, (c0 + 2) % NC
        if i == c0:
            loop = [grid[apex][c0], grid[apex][c1]] + self._edge(grid[apex][c1], grid[jamb][c0]) + [grid[jamb][c0]]
        else:
            loop = [grid[apex][c2], grid[jamb][c2]] + self._edge(grid[jamb][c2], grid[apex][c1]) + [grid[apex][c1]]
        c = m.centroid(loop)
        self._fan_poly(loop, (-c[0], -c[1], 0.0), zone)

    def _recess(self, grid, c0, s, h, depth, dirn, zone, bar_r, pitch, rung):
        """The pocket behind a mouth: floor, jambs, arched roof, back wall, and
        the branch bars across it. The floor and the roof are cut into one strip
        per bar (boundaries midway between bars) with a shelf BAR_SHELF deep at
        the front; each bar's end rings are socketed into its shelf quads, the
        rung's into the jambs. Every face wants its normal toward the mouth."""
        m, r = self.m, self.r
        jamb, apex = s + h * dirn, s + (h + 1) * dirn
        c1, c2 = (c0 + 1) % NC, (c0 + 2) % NC
        c0 %= NC
        sill = [grid[s][c0], grid[s][c1], grid[s][c2]]
        left = [grid[s + k * dirn][c0] for k in range(h + 1)]      # sill up to the jamb
        right = [grid[s + k * dirn][c2] for k in range(h + 1)]
        arch = [left[-1], grid[apex][c1], right[-1]]               # jambL, apex, jambR
        bmid = _col_bearing(c1)
        floor_zone = "earth" if grid is self.pit else "edge"
        mc = m.centroid([sill[0], sill[2], arch[0], arch[1], arch[2]])
        P = lambda vid: m.verts[vid]

        def back(p, d):
            return add(p, radial(_bearing_of(p)), d)

        def along(poly, t):
            """A point on a 2-segment polyline of ids, t in 0..1, the middle at 0.5."""
            return lerp(P(poly[0]), P(poly[1]), t * 2.0) if t <= 0.5 else lerp(P(poly[1]), P(poly[2]), (t - 0.5) * 2.0)

        width = dist(P(sill[0]), P(sill[2]))
        nbars = max(3, int(round(width / pitch)))
        bars = [k / float(nbars + 1) for k in range(1, nbars + 1)]
        T = sorted(set([0.0, 0.5, 1.0] + [round(0.5 * (bars[k] + bars[k + 1]), 9) for k in range(nbars - 1)]))

        def rail(poly):
            """Per boundary t: the id on the mouth line (the grid's own at 0, 0.5, 1),
            its copy BAR_SHELF back and its copy at the back wall."""
            F, M, B = [], [], []
            for t in T:
                vid = poly[0] if t == 0.0 else (poly[1] if t == 0.5 else (poly[2] if t == 1.0 else m.v(along(poly, t))))
                F.append(vid)
                M.append(m.v(back(P(vid), BAR_SHELF)))
                B.append(m.v(back(P(vid), depth)))
            return F, M, B

        fF, fM, fB = rail(sill)
        rF, rM, rB = rail(arch)
        half = T.index(0.5)
        self.split[(sill[0], sill[1])] = fF[1:half]
        self.split[(sill[1], sill[2])] = fF[half + 1:-1]
        self.split[(arch[0], arch[1])] = rF[1:half]
        self.split[(arch[1], arch[2])] = rF[half + 1:-1]
        lM, lB = [None] * (h + 1), [None] * (h + 1)
        gM, gB = [None] * (h + 1), [None] * (h + 1)
        for k in range(1, h):
            lM[k], lB[k] = m.v(back(P(left[k]), BAR_SHELF)), m.v(back(P(left[k]), depth))
            gM[k], gB[k] = m.v(back(P(right[k]), BAR_SHELF)), m.v(back(P(right[k]), depth))
        lM[0], lB[0], gM[0], gB[0] = fM[0], fB[0], fM[-1], fB[-1]
        lM[-1], lB[-1], gM[-1], gB[-1] = rM[0], rB[0], rM[-1], rB[-1]

        def q(a, b, c, d, zn):
            m.quad(a, b, c, d, sub(mc, m.centroid((a, b, c, d))), zn)

        for j in range(len(T) - 1):
            q(fF[j], fF[j + 1], fM[j + 1], fM[j], floor_zone)
            q(fM[j], fM[j + 1], fB[j + 1], fB[j], floor_zone)
            q(rF[j], rF[j + 1], rM[j + 1], rM[j], zone)
            q(rM[j], rM[j + 1], rB[j + 1], rB[j], zone)
        for k in range(h):
            q(left[k], left[k + 1], lM[k + 1], lM[k], zone)
            q(lM[k], lM[k + 1], lB[k + 1], lB[k], zone)
            q(right[k], right[k + 1], gM[k + 1], gM[k], zone)
            q(gM[k], gM[k + 1], gB[k + 1], gB[k], zone)
        loop = list(fB) + gB[1:h] + list(reversed(rB)) + list(reversed(lB[1:h]))
        cb = m.v(m.centroid(loop))
        for i in range(len(loop)):
            a, b = loop[i], loop[(i + 1) % len(loop)]
            m.tri(cb, a, b, sub(mc, m.centroid((cb, a, b))), zone)

        # the bars: foot ring in the floor shelf strip, top ring in the roof shelf strip
        for k, t in enumerate(bars):
            lo = 0.0 if k == 0 else 0.5 * (bars[k - 1] + t)
            hi = 1.0 if k == nbars - 1 else 0.5 * (t + bars[k + 1])
            js = [j for j in range(len(T) - 1) if T[j] >= lo - 1e-6 and T[j + 1] <= hi + 1e-6]
            fq = [(fF[j], fF[j + 1], fM[j + 1], fM[j]) for j in js]
            rq = [(rF[j], rF[j + 1], rM[j + 1], rM[j]) for j in js]
            foot = back(along(sill, t), BAR_SET)
            top = back(along(arch, t), BAR_SET)
            mid = add(lerp(foot, top, 0.5), tangent(bmid), r.u(-0.06, 0.06))
            nseg = max(2, int(math.ceil(dist(foot, top) / BAR_SEG)))
            path = bez(foot, mid, top, nseg)
            rr = r.u(*bar_r)
            _ptube(m, path, (rr, rr * 0.85), 4, "bark", start=(fq, floor_zone), end=(rq, zone), wob=0.15, rng=r)
        if rung:                            # one rung, a little under the jambs
            f = 0.62 * h
            k = min(h - 1, int(f))
            loc = f - k
            a = back(lerp(P(left[k]), P(left[k + 1]), loc), BAR_SET)
            b = back(lerp(P(right[k]), P(right[k + 1]), loc), BAR_SET)
            path = [a, add(lerp(a, b, 0.5), (0.0, 0.0, -0.03)), b]
            _ptube(m, path, (BAR_R[1], BAR_R[1]), 4, "bark", wob=0.1, rng=r,
                   start=([(left[k], left[k + 1], lM[k + 1], lM[k])], zone),
                   end=([(right[k], right[k + 1], gM[k + 1], gM[k])], zone))
        mouth5 = [sill[0], sill[2], arch[2], arch[1], arch[0]]
        back5 = [fB[0], fB[-1], rB[-1], rB[len(T) // 2], rB[0]]
        return (mouth5, back5, bmid)

    def _pit_faces(self):
        cells = [(_col_of(b), s, h) for (b, s, h) in PIT_CELLS]
        zone = lambda j, i: ("edge" if j == 0 else ("root" if (i in self.pit_root_cols and PIT_ROOT_ROWS[0] <= j < PIT_ROOT_ROWS[1]) else "earth"))
        self.pit_cells = self._cell_faces(self.pit, cells, PIT_CELL_D, -1, zone, "cell", PIT_BAR_R, PIT_BAR_PITCH, False)

    def _wall_faces(self):
        cells = [(_col_of(b), rows[0], 1) for (tier, rows) in WALL_TIERS for b in tier]   # the lane tier first
        zone = lambda j, i: ("bark" if i in self.bark_cols else ("edge" if j == 0 else "leaf"))
        self.wall_cells = self._cell_faces(self.wall, cells, WALL_CELL_D, 1, zone, "cell", BAR_R, BAR_PITCH, True)

    def _upper_faces(self):
        """The wall above the gallery: three tiers of barred cells, recessed outward
        into the leaf over the roof, every mouth facing the tower."""
        cells = [(_col_of(b), rows[0], 1) for (tier, rows) in UPPER_TIERS for b in tier]
        zone = lambda j, i: "leaf"
        self.upper_cells = self._cell_faces(self.upper, cells, UPPER_CELL_D, 1, zone, "cell",
                                            UPPER_BAR_R, UPPER_BAR_PITCH, False)

    # ---- dressing: everything socketed into the quad it stands on --------------
    def _plane_pt(self, plane, x, y):
        """(x, y, z) on the plane."""
        c, n = plane
        z = c[2] - (n[0] * (x - c[0]) + n[1] * (y - c[1])) / n[2] if abs(n[2]) > 1e-6 else c[2]
        return (x, y, z)

    def _spot(self, row, avoid_trunks):
        """An unclaimed deck quad in the row, off the pilasters."""
        r = self.r
        for _ in range(60):
            i = r.i(0, NC - 1)
            if avoid_trunks and (i in self.trunk_cols or (i + 1) % NC in self.trunk_cols):
                continue
            if (row, i) in self.taken or not self.m.has_quad(self._deck_quad(row, i)):
                continue
            self.taken.add((row, i))
            return i
        return None

    def _fern(self, row, i, rc):
        """A fern: a 4-vertex base ring socketed into the deck quad (four to four,
        aligned: the bridging cannot fold), zipped up to an 8-ring inside its
        footprint (a rounded square: nothing overhangs the base, so no culled
        skirt ever shows the hole under the crown), an inner ring and a top; a
        blade per chosen crown quad, a thin flat closed tube grown out of a
        socket there, bending up and over."""
        m, r = self.m, self.r
        quad = self._deck_quad(row, i)
        plane = plane_of(m, quad)
        b = _col_bearing(i) + 180.0 / NC
        c = pol(b, rc, 0.0)
        cz = self._plane_pt(plane, c[0], c[1])
        pts_fn = lambda ph: [self._plane_pt(plane, c[0] + FERN_BASE * math.cos(ph + TWO_PI * s / 4), c[1] + FERN_BASE * math.sin(ph + TWO_PI * s / 4)) for s in range(4)]
        base, ph = _best_ring(m, [quad], pts_fn, "edge")
        ring, inner = [], []
        for s in range(8):
            a = ph + TWO_PI * (s + 0.5) / 8
            rr = FERN_RING
            p = self._plane_pt(plane, c[0] + rr * math.cos(a), c[1] + rr * math.sin(a))
            ring.append(m.v((p[0], p[1], p[2] + FERN_CROWN[1])))
            p = self._plane_pt(plane, c[0] + FERN_CROWN[0] * math.cos(a), c[1] + FERN_CROWN[0] * math.sin(a))
            inner.append(m.v((p[0], p[1], p[2] + FERN_CROWN[2])))
        zipper(m, base, ring, UP, "fern", centre=cz)
        top = m.v((cz[0], cz[1], cz[2] + FERN_CROWN[3]))
        low = (cz[0], cz[1], cz[2] - 0.2)
        for s in range(8):
            q = (s + 1) % 8
            ids = (ring[s], ring[q], inner[q], inner[s])
            m.quad(ids[0], ids[1], ids[2], ids[3], sub(m.centroid(ids), low), "fern")
            m.tri(top, inner[s], inner[q], UP, "fern")
        chord = (FERN_RING + FERN_CROWN[0]) * math.sin(math.pi / 8)
        a0 = 0.36 * chord
        slots = list(range(8))
        while len(slots) > r.i(*FERN_BLADES):
            slots.pop(r.i(0, len(slots) - 1))
        for s in slots:
            q = (s + 1) % 8
            crown = (ring[s], ring[q], inner[q], inner[s])
            bp = m.centroid(crown)
            a = ph + TWO_PI * (s + 1.0) / 8 + r.u(-0.15, 0.15)
            el = math.radians(r.u(28.0, 58.0))
            L = r.u(*FERN_L)
            W = r.u(*FERN_W)
            d = (math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el))
            d2 = (math.cos(a) * math.cos(el * 0.35), math.sin(a) * math.cos(el * 0.35), math.sin(el * 0.35))
            mid = add(bp, d, L * 0.5)
            tip = add(mid, d2, L * 0.5)
            _ptube(m, [bp, mid, tip], (a0, W * 0.5, W * 0.25), 4, "fern", start=([crown], "fern"),
                   flat=(1.0, FERN_FLAT, FERN_FLAT), caps=(False, True))

    def _hummock(self, i):
        """A grass dome: a 4-ring socketed into a wall-foot deck quad, zipped up
        to an 8-ring inside its footprint that rises and shrinks to a top."""
        m, r = self.m, self.r
        quad = self._deck_quad(FOOT_ROW, i)
        plane = plane_of(m, quad)
        b = _col_bearing(i) + 180.0 / NC
        c = pol(b, FOOT_FERN_R - 0.05, 0.0)
        cz = self._plane_pt(plane, c[0], c[1])
        pts_fn = lambda ph: [self._plane_pt(plane, c[0] + HUMMOCK_BASE * math.cos(ph + TWO_PI * s / 4), c[1] + HUMMOCK_BASE * math.sin(ph + TWO_PI * s / 4)) for s in range(4)]
        base, ph = _best_ring(m, [quad], pts_fn, "edge")
        ring, ring2 = [], []
        for s in range(8):
            a = ph + TWO_PI * (s + 0.5) / 8
            rr = HUMMOCK_RING * (1.0 + 0.05 * r.sf())
            p = self._plane_pt(plane, c[0] + rr * math.cos(a), c[1] + rr * math.sin(a))
            ring.append(m.v((p[0], p[1], p[2] + HUMMOCK_H * 0.3)))
            rr *= 0.55 * (1.0 + 0.08 * r.sf())
            p = self._plane_pt(plane, c[0] + rr * math.cos(a), c[1] + rr * math.sin(a))
            ring2.append(m.v((p[0], p[1], p[2] + HUMMOCK_H * 0.72)))
        zipper(m, base, ring, UP, "edge", centre=cz)
        top = m.v((cz[0], cz[1], cz[2] + HUMMOCK_H))
        low = (cz[0], cz[1], cz[2] - 0.3)
        for s in range(8):
            q = (s + 1) % 8
            ids = (ring[s], ring[q], ring2[q], ring2[s])
            m.quad(ids[0], ids[1], ids[2], ids[3], sub(m.centroid(ids), low), "edge")
            m.tri(top, ring2[s], ring2[q], UP, "edge")

    def _ferns(self):
        for _ in range(FERNS_LIP):
            i = self._spot(LIP_ROW, False)
            if i is not None:
                self._fern(LIP_ROW, i, LIP_FERN_R)
        for _ in range(FERNS_WALL):
            i = self._spot(FOOT_ROW, True)
            if i is not None:
                self._fern(FOOT_ROW, i, FOOT_FERN_R)
        for _ in range(HUMMOCKS):
            i = self._spot(FOOT_ROW, True)
            if i is not None:
                self._hummock(i)

    def _hanging_roots(self):
        """Roots out of the lip's round-over (bank rows 2..3), hanging over the pit."""
        m, r = self.m, self.r
        made = 0
        tries = 0
        while made < HANG_ROOTS and tries < 200:
            tries += 1
            i = r.i(0, NC - 1)
            q = (i + 1) % NC
            quad = (self.pit[2][i], self.pit[2][q], self.pit[3][q], self.pit[3][i])
            if not m.has_quad(quad):
                continue
            b = _col_bearing(i) + 180.0 / NC
            p0 = m.centroid(quad)
            r0, z0 = math.hypot(p0[0], p0[1]), p0[2]
            path = [p0, pol(b, r0 - 1.0, z0 - 0.4), pol(b + r.u(-0.5, 0.5), r0 - 1.5, z0 - 2.0),
                    pol(b + r.u(-0.8, 0.8), r0 - 1.7, z0 - 3.6), pol(b + r.u(-1.0, 1.0), r0 - 1.7, z0 - r.u(4.8, 5.4))]
            _ptube(m, path, (0.2, 0.17, 0.15, 0.13, 0.11), 4, "root", start=([quad], "earth"), caps=(False, True), wob=0.1, rng=r)
            made += 1

    # ---- sun rays ----------------------------------------------------------------
    def ray_lines(self):
        """(top, foot, S, scale) per shaft, world coordinates: the shaft's axis runs
        from ``top`` (RAY_IN up the sun line from the source's centre, so it
        begins under the leaves) down the sun direction to ``foot`` -- the first thing it meets, the
        dome, the gallery roof's top, the tree, the bank or the pit floor, plus
        RAY_OVER into it."""
        out = []
        sb, se = SUN
        S = (math.cos(math.radians(se)) * math.cos(math.radians(-sb)),
             math.cos(math.radians(se)) * math.sin(math.radians(-sb)),
             math.sin(math.radians(se)))
        for (pts, half_w) in self.rays:
            c = tuple(sum(p[k] for p in pts) / float(len(pts)) for k in range(3))
            lo, hi, step = 0.0, None, 0.5
            t = 0.0
            while t < 140.0:
                t += step
                if not _open(add(c, S, -t)):
                    lo, hi = t - step, t
                    break
            if hi is None:
                foot = add(c, S, -t)
            else:
                for _ in range(30):
                    mid = 0.5 * (lo + hi)
                    if _open(add(c, S, -mid)):
                        lo = mid
                    else:
                        hi = mid
                foot = add(c, S, -lo)
            out.append((add(c, S, RAY_IN), add(foot, S, -RAY_OVER), S, half_w / RAY_W[0]))
        return out

    # ---- build -------------------------------------------------------------
    def build(self):
        r = self.r
        cols = list(range(NC))
        cell_cols = set()
        for (b, s, h) in PIT_CELLS:
            c0 = _col_of(b)
            cell_cols.update({c0 % NC, (c0 + 1) % NC, (c0 + 2) % NC, (c0 - 1) % NC, (c0 + 3) % NC})
        while len(self.pit_root_cols) < PIT_ROOTS:
            i = r.pick(cols)
            if i not in cell_cols:
                self.pit_root_cols.add(i)
        self._deck_rows()
        self._pit_rows()
        self._wall_rows()
        fc.gallery_rows(self)       # the leaf roof over the lane, off the wall's top row
        self._upper_rows()          # the wall above it, off the roof's inner rim
        fc.dome_rows(self)          # the grand canopy dome, off that wall's head
        self._deck_faces()
        self._pit_faces()
        self._wall_faces()
        fc.gallery_faces(self)
        self._upper_faces()         # six more tiers of cells over the ravine
        fc.dome_faces(self)         # the dome, its organic shaft sources (self.rays), the pole
        fp.pit_floor(self)          # the dark floor grown inward off the bank's last row
        self._ferns()
        self._hanging_roots()
        fc.dress(self)              # leaf clumps round the shaft sources, high in the canopy
        fp.brambles(self)           # the thicket: thorny branches out of the pit floor, rising from the fog
        return self.m


def _bank_r(z):
    """The pit bank's radius at height z, water to lip: the PIT profile."""
    if z >= PIT[0][1]:
        return PIT[0][0]
    for k in range(len(PIT) - 1):
        (r0, z0), (r1, z1) = PIT[k], PIT[k + 1]
        if z1 <= z <= z0:
            return r0 + (r1 - r0) * (z0 - z) / (z0 - z1)
    return WATER_R


def _open(p):
    """Is p in the clearing's air? Above the gallery roof only the dome is open;
    over the lane the whole room is; under the lane only inside the bank. The
    tree stands in the middle of it, so a shaft can land on its crown."""
    rad, z = math.hypot(p[0], p[1]), p[2]
    if z < WATER_Z:
        return False
    if 33.0 <= z <= 36.4 and rad <= 11.0:           # the tree's leaf disc ...
        return False
    if 36.4 < z <= 37.4 and rad <= 8.0:             # ... and its crown
        return False
    if z <= 27.6 and rad <= 7.2:                    # the trunk and the guard's platform
        return False
    if z > fc.GALLERY_Z:
        return rad <= fc.dome_r(z) - 0.2
    if z >= DECK_Z:
        return rad <= OUTER_R
    return rad <= _bank_r(z)


def cross3(p, q):
    return (p[1] * q[2] - p[2] * q[1], p[2] * q[0] - p[0] * q[2], p[0] * q[1] - p[1] * q[0])


class _RayMesh(_Mesh):
    """A _Mesh that also carries one RGBA per vertex (the shaft's tint and feather)."""

    def __init__(self):
        _Mesh.__init__(self)
        self.colors = []

    def cv(self, p, rgba):
        self.colors.append(tuple(rgba))
        return self.v(p)


def _ray_mesh(lines, tint, peak):
    """RAY_VANES planes crossed on each shaft's axis, each a strip three vertices
    wide (edge, axis, edge) and four rows long (top, fade-in, fade-out, foot).
    Alpha is ``peak`` on the axis between the fade rows and zero everywhere
    else, so the strip has no visible end and no hard edge; the width tapers
    RAY_W[0] to RAY_W[1]."""
    m = _RayMesh()
    rows = (0.0, RAY_FADE[0], RAY_FADE[1], 1.0)
    for (top, foot, S, wscale) in lines:
        axis = sub(foot, top)
        ex = norm(cross3(S, UP))
        ez = norm(cross3(ex, S))
        for vane in range(RAY_VANES):
            a = math.pi * vane / RAY_VANES
            side = add((ex[0] * math.cos(a), ex[1] * math.cos(a), ex[2] * math.cos(a)), ez, math.sin(a))
            grid = []
            for t in rows:
                w = (RAY_W[0] + (RAY_W[1] - RAY_W[0]) * t) * wscale
                c = add(top, axis, t)
                on = peak if RAY_FADE[0] - 1e-9 <= t <= RAY_FADE[1] + 1e-9 else 0.0
                grid.append([m.cv(add(c, side, -w), tint + (0.0,)),
                             m.cv(c, tint + (on,)),
                             m.cv(add(c, side, w), tint + (0.0,))])
            for k in range(len(rows) - 1):
                for col in range(2):
                    a0, a1 = grid[k][col], grid[k][col + 1]
                    b0, b1 = grid[k + 1][col], grid[k + 1][col + 1]
                    m.quad(a0, a1, b1, b0, norm(cross3(side, S)), "ray")
    return m


def _ray_object(m, name):
    """The shaft mesh as a Blender object with its RGBA in a colour attribute
    the material reads (Base Color and Alpha), which is what makes the glTF
    exporter write it as COLOR_0."""
    ob = m.object(name)
    me = ob.data
    attr = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    flat = []
    for rgba in m.colors:
        flat.extend(rgba)
    attr.data.foreach_set("color", flat)
    me.color_attributes.active_color_index = 0
    me.color_attributes.render_color_index = 0
    return ob


# =============================================================================
# COLLIDER -- flat lane, pit cone, water floor, wall + trunk prisms, ceiling
# =============================================================================

# =============================================================================
# SHEETS -- the forest's classes, one tiling image each (lib/texel.py)
# =============================================================================
# Counts and sizes carry the atlas cells' density per metre: a 64 px cell at
# 12 texels/m was 5.33 m; a sheet at texel.MPT is 12.8 m square.
_CELL_M = 64.0 / ft.TPM
_K = (tx.TILE * tx.MPT / _CELL_M) ** 2         # sheet area / cell area: 5.76
_S = (1.0 / ft.TPM) / tx.MPT                   # old texel / new texel: 1.67


def _n(count, cell_px=64):
    return int(round(count * _K * (64.0 / cell_px) ** 2))


def _sz(texels):
    return max(1, int(round(texels * _S)))


def _noise(tones, cuts, nblades, blade_shades, cell_px=(128, 64)):
    def paint(c, r, s):
        tx.noise_fill(c, r, c.box, tones, cuts=cuts, cells=(_sz(10), _sz(4)))
        tx.blades(c, r, c.box, int(round(nblades * (c.w * c.h) / float(cell_px[0] * cell_px[1]))), blade_shades)
    return paint


def _leaves(base, blobs, lit, count, sz, cell_px):
    def paint(c, r, s):
        tx.fill(c, r, c.box, list(base))
        for _ in range(_n(count, cell_px)):
            w = r.i(_sz(sz[0]), _sz(sz[1]))
            h = max(2, w - r.i(0, 2))
            x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
            c.rect(x, y, x + w, y + h, r.pick(list(blobs)))
            c.rect(x, y + h - 1, x + max(2, w // 2), y + h, lit)      # the lit edge of every leaf
    return paint


def _sheet_fern(c, r, s):
    tx.fill(c, r, c.box, list(ft.FERN_BASE))
    for _ in range(_n(9)):                       # fronds: a stem with side ticks
        x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
        n = r.i(_sz(8), _sz(16))
        dx = r.pick([-1, 1])
        for k in range(n):
            xx, yy = x + (k * dx) // 2, y + k
            c.put(xx, yy, ft.FERN_FROND[0])
            if k % 2 == 0:
                c.put(xx - 1, yy, ft.FERN_FROND[1])
                c.put(xx + 1, yy, ft.FERN_FROND[1])
    tx.blades(c, r, c.box, _n(30), [ft.FERN_DARK])


def _bark(base):
    def paint(c, r, s):
        tx.fill(c, r, c.box, list(base))
        tx.streaks(c, r, c.box, _n(26), list(ft.BARK_STREAKS), (_sz(6), _sz(18)), (1, _sz(2)))
        tx.streaks(c, r, c.box, _n(12), [ft.BARK_CRACK], (_sz(4), _sz(9)), (1, 1), wander=1)
        for _ in range(_n(8)):
            x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
            c.rect(x, y, x + _sz(2), y + _sz(2), ft.BARK_MOSS)
    return paint


def _sheet_earth(c, r, s):
    tx.fill(c, r, c.box, list(ft.EARTH_BASE))
    tx.shatter(c, r, c.box, list(ft.EARTH_BLOTCH), _n(30), _sz(3), _sz(9))
    for _ in range(_n(8)):                       # root streaks, top to bottom, wrapping
        x = r.i(0, c.w - 1)
        for k in range(c.h):
            c.put(x, k, ft.EARTH_ROOT)
            if k % 3 == 0:
                x += r.i(-1, 1)
    for count, col in ((14, ft.EARTH_STONE), (10, ft.EARTH_MOSS)):
        for _ in range(_n(count)):
            x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
            c.rect(x, y, x + _sz(2), y + _sz(2), col)


def _sheet_cell(c, r, s):
    tx.fill(c, r, c.box, [(14, 16, 12), (18, 20, 14), (12, 14, 10), (20, 24, 16)])
    tx.shatter(c, r, c.box, [(24, 28, 18), (10, 12, 8)], _n(12), _sz(3), _sz(8))
    for _ in range(_n(3)):                       # something pale, far back
        x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
        c.rect(x, y, x + _sz(2), y + 1, (52, 60, 44))


def _forest_ref(centre):
    """The radius a face's arc is measured at, by region, so every region's
    projection is near-isometric and closes round the ring."""
    rad = math.hypot(centre[0], centre[1])
    z = centre[2]
    if z >= 64.0:
        return 30.0                              # the canopy dome
    if z >= CEIL_Z + 0.5:
        return 47.0                              # the cell wall over the ravine
    if z > DECK_Z - 1.0:
        return 58.5 if rad > 57.0 else 52.0      # leaf wall | lane, gallery roof
    return 45.0                                  # the pit bank and floor


def _sheet(name, paint, **kw):
    return tx.Sheet(name, paint, ref_r=_forest_ref, roughness=ft.ROUGHNESS, **kw)


_BLADES = [(168, 172, 82), (160, 160, 70), (86, 102, 58)]
SHEETS = {
    "grass": _sheet("grass", _noise(ft.LANE_GREENS, (0.38, 0.66), 160, _BLADES), seed=1),
    "verge": _sheet("verge", _noise(ft.VERGE_TONES, (0.42, 0.74), 60, [(160, 164, 78), (112, 104, 60)]), seed=2),
    "path": _sheet("path", _noise(ft.PATH_TONES, (0.40, 0.72), 70, [(118, 96, 58), (104, 88, 54), (132, 140, 70)]), seed=3),
    "edge": _sheet("edge", _noise(ft.EDGE_GREENS, (0.38, 0.66), 60, [(130, 140, 68), (58, 44, 30)], (64, 64)), seed=4),
    "leaf": _sheet("leaf", _leaves(ft.LEAF_BASE, ft.LEAF_BLOBS, ft.LEAF_LIT, 520, (3, 5), 128), seed=5),
    "shade": _sheet("shade", _leaves(ft.SHADE_BASE, ft.SHADE_BLOBS, ft.SHADE_LIT, 110, (3, 5), 64), seed=6),
    "sun": _sheet("sun", _leaves(ft.SUN_BASE, ft.SUN_BLOBS, ft.SUN_LIT, 110, (3, 5), 64), seed=7),
    "fern": _sheet("fern", _sheet_fern, seed=8),
    "bark": _sheet("bark", _bark(ft.BARK_BASE), seed=9),
    "earth": _sheet("earth", _sheet_earth, seed=10),
    "cell": _sheet("cell", _sheet_cell, seed=11),
    "root": _sheet("root", _bark(ft.ROOT_BASE), seed=12),
}


def build_collider():
    c = _Mesh()
    n = 48
    ring = lambda rad, z: [c.v(pol(360.0 * s / n, rad, z)) for s in range(n)]
    lip = ring(INNER_R, DECK_Z)
    foot = ring(OUTER_R, DECK_Z)
    loft(c, [lip, foot], "grass", want_fn=lambda p: UP)
    pit = [lip, ring(45.2, 21.5), ring(44.2, 14.0), ring(43.0, 3.5), ring(WATER_R, WATER_Z), ring(WATER_R - 0.5, WATER_Z - 2.45)]
    loft(c, pit, "earth", want_fn=lambda p: (-p[0], -p[1], 0.0))
    c.fan(pit[-1], UP, "earth")
    wall = [foot, ring(OUTER_R, CEIL_Z)]
    loft(c, wall, "leaf", want_fn=lambda p: (-p[0], -p[1], 0.0))
    ceil = [wall[1], ring(UPPER[0][0], CEIL_Z)]              # the gallery roof over the lane
    loft(c, ceil, "shade", want_fn=lambda p: DOWN)
    up = [ceil[1], ring(UPPER[-1][0], UPPER[-1][1])]         # the wall above it
    loft(c, up, "leaf", want_fn=lambda p: (-p[0], -p[1], 0.0))
    dome = [up[1]] + [ring(rad, z) for (rad, z, _n) in fc.DOME[1:]]
    loft(c, dome, "shade", want_fn=lambda p: DOWN)
    c.fan(dome[-1], DOWN, "shade")
    # a prism per forest trunk: the bark pilaster's half-hexagon, deck to ceiling
    for b in TRUNKS:
        c0 = _col_of(b)
        pts = [pol(_col_bearing(c0 + k - 2), OUTER_R - TRUNK_PUSH * TRUNK_PROFILE[k] * TRUNK_FLARE[0], 0.0) for k in range(5)]
        lo = [c.v((p[0], p[1], DECK_Z)) for p in pts]
        hi = [c.v((p[0], p[1], CEIL_Z)) for p in pts]
        for k in range(4):
            idx = (lo[k], lo[k + 1], hi[k + 1], hi[k])
            cc = c.centroid(idx)
            c.quad(idx[0], idx[1], idx[2], idx[3], (-cc[0], -cc[1], 0.0), "bark")
    return c


def _ray_material(name, colour):
    """Unlit, blended: Base Color and Alpha come from the vertex colour, the
    glow is the tint. Godot shows these nodes through the scene's overrides
    (unshaded, mixed / additive, vertex colour as albedo); this material is
    for the review render and for the exporter."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    col.location = (-640, 200)
    # Base Color = vertex colour x black: the exporter reads the pattern as
    # "COLOR_0 times a factor" and writes the vertex colour; the render gets no
    # diffuse, so the glow is the shaft's whole brightness, as it is in Godot.
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.location = (-420, 200)
    a_in = [i for i in mix.inputs if i.identifier == "A_Color"][0]
    b_in = [i for i in mix.inputs if i.identifier == "B_Color"][0]
    out = [o for o in mix.outputs if o.identifier == "Result_Color"][0]
    mix.inputs["Factor"].default_value = 1.0
    b_in.default_value = (0.0, 0.0, 0.0, 1.0)
    nt.links.new(col.outputs["Color"], a_in)
    nt.links.new(out, bsdf.inputs["Base Color"])
    nt.links.new(col.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Emission Color"].default_value = (colour[0], colour[1], colour[2], 1.0)
    bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    mdl._try(mat, "surface_render_method", "BLENDED")
    mdl._try(mat, "blend_method", "BLEND")
    mdl._try(mat, "use_transparency_overlap", True)
    mat.use_backface_culling = False
    mat.diffuse_color = (colour[0], colour[1], colour[2], 0.5)
    return mat


# =============================================================================
# REVIEW RENDERS -- bright, hand-placed cameras, the tree in place
# =============================================================================

def _forest_render(spec, objects):
    scene = bpy.context.scene
    if spec.get("engine", "eevee").lower() == "cycles":
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = int(spec.get("samples", 64))
        scene.cycles.use_denoising = True
    else:
        scene.render.engine = "BLENDER_EEVEE"
        mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 64)))
        mdl._try(scene.eevee, "use_shadows", True)
        mdl._try(scene.eevee, "use_raytracing", True)
        mdl._try(scene.eevee, "shadow_ray_count", 2)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")
    mdl._try(scene.view_settings, "exposure", REVIEW_EXPOSURE)

    world = bpy.data.worlds.new("ForestSky")
    scene.world = world
    world.use_nodes = True
    wnt = world.node_tree
    bg = wnt.nodes["Background"]
    bg.inputs[0].default_value = (REVIEW_SKY[0], REVIEW_SKY[1], REVIEW_SKY[2], 1.0)
    bg.inputs[1].default_value = REVIEW_WORLD
    # What a camera ray that clears the canopy sees is the sky at the scene's
    # brightness (REVIEW_SEEN), not the fill the world pours in: the sky reads as
    # a patch of pale green, never a white slab.
    seen = wnt.nodes.new("ShaderNodeBackground")
    seen.inputs[0].default_value = (REVIEW_SEEN[0], REVIEW_SEEN[1], REVIEW_SEEN[2], 1.0)
    seen.inputs[1].default_value = 1.0
    path = wnt.nodes.new("ShaderNodeLightPath")
    mixw = wnt.nodes.new("ShaderNodeMixShader")
    wout = wnt.nodes["World Output"]
    wnt.links.new(path.outputs["Is Camera Ray"], mixw.inputs["Fac"])
    wnt.links.new(bg.outputs["Background"], mixw.inputs[1])
    wnt.links.new(seen.outputs["Background"], mixw.inputs[2])
    wnt.links.new(mixw.outputs["Shader"], wout.inputs["Surface"])

    sb, se = SUN
    sd = bpy.data.lights.new("ReviewSun", type="SUN")
    sd.energy, sd.color = REVIEW_SUN, (1.0, 0.96, 0.84)
    mdl._try(sd, "use_shadow", True)
    mdl._try(sd, "angle", math.radians(1.5))
    sun = mdl._link(bpy.data.objects.new("ReviewSun", sd))
    aim = mdl._link(bpy.data.objects.new("ReviewAim", None))
    aim.location = (0.0, 0.0, 20.0)
    sun.location = add(aim.location, (math.cos(math.radians(se)) * math.cos(math.radians(-sb)),
                                      math.cos(math.radians(se)) * math.sin(math.radians(-sb)),
                                      math.sin(math.radians(se))), 120.0)
    con = sun.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"
    fd = bpy.data.lights.new("ReviewFill", type="SUN")
    fd.energy, fd.color = REVIEW_FILL, (0.9, 1.0, 0.9)
    mdl._try(fd, "use_shadow", False)
    fill = mdl._link(bpy.data.objects.new("ReviewFill", fd))
    fill.location = add(aim.location, (math.cos(math.radians(40.0)) * math.cos(math.radians(-(sb + 180.0))),
                                       math.cos(math.radians(40.0)) * math.sin(math.radians(-(sb + 180.0))),
                                       math.sin(math.radians(40.0))), 120.0)
    con = fill.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"

    tree = ft.build_render_copy(INFO["albedo"], INFO["emissive"])
    rays = {ob.name: ob for ob in objects if ob.name in (RAYS_SOLID_NAME, RAYS_SOFT_NAME)}
    solid, soft = rays.get(RAYS_SOLID_NAME), rays.get(RAYS_SOFT_NAME)
    for ob in objects:              # the fog stays in every shot
        if ob.name == fp.FOG_NAME:
            ob.hide_render = False

    target = mdl._link(bpy.data.objects.new("ForestTarget", None))
    cam = mdl._link(bpy.data.objects.new("ForestCam", bpy.data.cameras.new("ForestCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    out_dir = spec.get("out_dir", ".")

    # --views <hand shot names>: render only those (the fast loop for one section, e.g.
    # --views pit_fog,pit). The named views (front/side/threequarter) are mdl's, not ours.
    sel = set(spec.get("views") or []) - {"front", "side", "threequarter"}

    def shot(name, loc, tgt, lens, res):
        if sel and name not in sel and "rays" not in sel:
            return
        cam.data.lens = lens
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    def variant(which):
        """'solid': the mesh-only shafts, no sun, the world a little brighter.
        'light': the sun through the leaves, shadows on, and the faint shafts."""
        if solid:
            solid.hide_render = which != "solid"
        if soft:
            soft.hide_render = which != "light"
        sun.hide_render = which == "solid"
        bg.inputs[1].default_value = REVIEW_WORLD * REVIEW_WORLD_VARIANT[which]

    def compare(name, loc, tgt, lens, res):
        """Both variants from one camera, side by side in one image, the
        mesh-only shafts on the left and the sun-and-faint-shafts on the right."""
        if sel and name not in sel and "rays" not in sel:
            return
        halves = []
        for which in ("solid", "light"):
            variant(which)
            shot("rays_%s" % which, loc, tgt, lens, res)
            halves.append(os.path.join(out_dir, "%s_rays_%s.png" % (NAME, which)))
        import numpy as np
        imgs = [bpy.data.images.load(h) for h in halves]
        w, h = imgs[0].size
        pix = []
        for img in imgs:
            buf = np.empty(w * h * 4, dtype=np.float32)
            img.pixels.foreach_get(buf)
            pix.append(buf.reshape(h, w, 4))
        gutter = np.ones((h, 8, 4), dtype=np.float32) * np.array([0.05, 0.05, 0.05, 1.0], dtype=np.float32)
        both = np.concatenate((pix[0], gutter, pix[1]), axis=1)
        out = bpy.data.images.new("ForestRaysCompare", both.shape[1], h, alpha=False)
        out.pixels.foreach_set(both.ravel())
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        out.filepath_raw = path
        out.file_format = "PNG"
        out.save()
        for img in imgs:
            bpy.data.images.remove(img)
        bpy.data.images.remove(out)
        print("MDL RENDER %s (solid | light, one camera)" % os.path.basename(path))

    eye = DECK_Z + EYE_H
    only = spec.get("views") or []
    if "rays" in only:                   # --views rays: the ray comparison alone, for tuning
        compare("rays_compare", pol(200.0, 54.5, eye), pol(160.0, 49.0, DECK_Z + 3.0), 22.0, (1400, 800))
    else:
        variant("light")
        shot("lane", pol(200.0, 52.0, eye), pol(232.0, 50.5, DECK_Z + 1.0), 22.0, (1400, 800))
        shot("lane_tree", pol(60.0, 53.5, eye), (0.0, 0.0, 24.0), 24.0, (1400, 900))
        shot("guard", (0.0, 0.0, ft.FLOOR_Y + EYE_H), pol(150.0, 52.0, DECK_Z), 24.0, (1400, 800))
        shot("guard_seat", pol(300.0, 13.0, ft.FLOOR_Y + 2.2), (0.0, 0.0, ft.FLOOR_Y + 2.4), 30.0, (1200, 900))
        shot("seat", pol(330.0, 1.2, ft.FLOOR_Y + EYE_H), pol(150.0, 40.0, DECK_Z + 1.0), 16.0, (1400, 800))
        shot("pit_fog", pol(250.0, 48.6, eye + 0.4), pol(238.0, 20.0, -6.0), 24.0, (1400, 900))    # from the lane, looking down into the thicket
        shot("aerial", pol(330.0, 132.0, 122.0), (0.0, 0.0, 26.0), 30.0, (1500, 1100))
        shot("tower", pol(180.0, 56.5, eye), (0.0, 0.0, 14.0), 20.0, (900, 1300))
        shot("pit", pol(292.0, 6.4, ft.FLOOR_Y + 0.55 + EYE_H), pol(300.0, 22.0, -6.0), 24.0, (1400, 900))   # from the tower, standing on the lip in an arch (from the floor the lip hides the drop)
        shot("enclosure", pol(200.0, 55.5, DECK_Z + 4.5), (0.0, 0.0, 52.0), 12.0, (1500, 1000))
        # the roof, from the lane: the gallery of leaves overhead, its rim, and the dome beyond
        shot("roof", pol(196.0, 53.5, eye), pol(186.0, 42.0, 41.0), 18.0, (1400, 1000))
        # the wall above the gallery: six tiers of cells over the ravine, seen from the pit lip
        # across the ring (a chord, so the tree does not stand in front of it -- from the guard's
        # own eye the tree's canopy belly at y 33 is the ceiling and the wall above is hidden)
        shot("wall_above", pol(315.0, 46.9, eye), pol(200.0, 47.5, 50.0), 40.0, (1400, 900))
        if INFO.get("wall_cells"):
            mouth, back, bmid = INFO["wall_cells"][0]
            mc = tuple(sum(p[k] for p in mouth) / 5.0 for k in range(3))
            bc = tuple(sum(p[k] for p in back) / 5.0 for k in range(3))
            inside = lerp(bc, mc, 0.15)
            inside = (inside[0], inside[1], mc[2] + 0.3)
            shot("cell", inside, pol(bmid + 25.0, 30.0, 20.0), 20.0, (1200, 900))
            shot("cell_front", pol(bmid - 6.0, 53.5, eye), (mc[0], mc[1], mc[2] + 0.4), 30.0, (1200, 900))
        if len(INFO.get("wall_cells", [])) > len(WALL_CELLS):     # the upper tier, from the lane looking up
            uppers = INFO["wall_cells"][len(WALL_CELLS):]
            mouth, _back, bmid = min(uppers, key=lambda c: abs(c[2] - 138.0))   # a lower cell one side, a trunk the other
            mc = tuple(sum(p[k] for p in mouth) / 5.0 for k in range(3))
            shot("cell_upper", pol(bmid + 10.0, 51.5, eye), (mc[0], mc[1], mc[2] - 0.5), 26.0, (1200, 900))
        compare("rays_compare", pol(200.0, 54.5, eye), pol(160.0, 49.0, DECK_Z + 3.0), 22.0, (1400, 800))
        variant("solid")
        shot("rays_solid_tree", pol(300.0, 54.0, eye), (0.0, 0.0, 22.0), 26.0, (1400, 900))
        variant("light")
        shot("rays_light_tree", pol(300.0, 54.0, eye), (0.0, 0.0, 22.0), 26.0, (1400, 900))

    for ob in (cam, target, sun, aim, fill, tree):
        bpy.data.objects.remove(ob, do_unlink=True)
    if solid:
        solid.hide_render = False
    if soft:
        soft.hide_render = False
    if not spec.get("cams"):
        spec["views"] = []          # the named views frame 120 m of forest as a rifle; skip them


# =============================================================================
# BUILD / CHECK
# =============================================================================

def build_geometry():
    """(ground, collider, {node name: shaft mesh})."""
    g = _Ground()
    m = ft._prune(g.build())     # a socket patch two quads tall leaves its inner vertices unused
    lines = g.ray_lines()
    INFO["wall_cells"] = [([m.verts[v] for v in mouth], [m.verts[v] for v in back], bmid)
                          for (mouth, back, bmid) in g.wall_cells]
    INFO["upper_cells"] = [([m.verts[v] for v in mouth], [m.verts[v] for v in back], bmid)
                           for (mouth, back, bmid) in g.upper_cells]
    INFO["rays"] = lines
    rays = {name: _ray_mesh(lines, tint, peak)
            for name, (tint, peak) in ((RAYS_SOLID_NAME, RAY_SOLID), (RAYS_SOFT_NAME, RAY_SOFT))}
    rays[fp.FOG_NAME] = fp.fog_mesh(_RayMesh, g)
    return m, build_collider(), rays


def build():
    m, c, rays = build_geometry()
    albedo, emissive = ft.sheet("forest_atlas", ft.paint_atlas)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    INFO["albedo"], INFO["emissive"] = albedo, emissive

    ob = m.object(OBJECT_NAME)
    classes = list(m.zones)
    tx.unwrap(ob, classes, SHEETS, seed=1)
    mats = tx.materials(NAME, SHEETS, use_files=ft.USE_TEXTURE_FILES, tex_dir=os.path.join(HERE, ft.TEX_DIR))
    order = tx.finish(ob, classes, mats)
    tx.report(SHEETS)
    print("MDL STATS surfaces=%d order=%s" % (len(ob.data.materials), ",".join(order)))

    coll = c.object(COLLIDER_NAME)
    coll.hide_render = True
    out = [ob, coll]
    if MESH_RAYS:
        for name, (colour, _peak) in ((RAYS_SOLID_NAME, RAY_SOLID), (RAYS_SOFT_NAME, RAY_SOFT)):
            rob = _ray_object(rays[name], name)
            mdl.finish(rob, _ray_material(name + "Mat", colour), strip_uvs=False)
            out.append(rob)
    fog = _ray_object(rays[fp.FOG_NAME], fp.FOG_NAME)
    # the review material glows at 0.45 x the tint: the review's exposure and world would otherwise
    # show the layers a stop paler than Godot's unshaded vertex colour under its Reinhard tonemap
    mdl.finish(fog, _ray_material(fp.FOG_NAME + "Mat", tuple(c * 0.45 for c in fp.FOG_TINT)), strip_uvs=False)
    out.append(fog)
    print("MDL STATS visual_tris=%d collision_tris=%d ray_tris=%d rays=%d fog_tris=%d"
          % (len(ob.data.polygons), len(coll.data.polygons), len(rays[RAYS_SOLID_NAME].faces), len(INFO["rays"]),
             len(rays[fp.FOG_NAME].faces)))
    print("MDL STATS lane r=%.1f..%.1f y=%.1f pit_floor_y=%.1f r=%.1f gallery_y=%.1f wall_above=%.1f..%.1f dome_y=%.1f "
          "wall_cells=%d upper_cells=%d pit_cells=%d trunks=%d shafts=%d sun=%s"
          % (INNER_R, OUTER_R, DECK_Z, WATER_Z, WATER_R, fc.GALLERY_Z, UPPER[0][1], UPPER[-1][1], fc.DOME_TOP,
             len(WALL_CELLS) + len(WALL_CELLS_UPPER), sum(len(t) for t in UPPER_CELLS),
             len(PIT_CELLS), len(TRUNKS), len(fc.SHAFTS), SUN))
    for k, (top, foot, _s, _w) in enumerate(INFO["rays"]):
        print("MDL STATS ray%d top=(%.1f, %.1f, %.1f) foot=(%.1f, %.1f, %.1f) r=%.1f"
              % (k, top[0], top[1], top[2], foot[0], foot[1], foot[2], math.hypot(foot[0], foot[1])))
    return out


def _check():
    import forest_check
    m, c, ray_set = build_geometry()
    rays = ray_set[RAYS_SOLID_NAME]
    m.compact()
    c.compact()
    rays.compact()
    forest_check.prove(m, "ground")
    forest_check.components_report(m)
    fog = ray_set[fp.FOG_NAME]
    fog.compact()
    for name, mm in (("ground", m), ("coll", c), ("rays", rays), ("fog", fog)):
        degen = 0
        for f in mm.faces:
            n = ft._newell([mm.verts[i] for i in f])
            if math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) < 1e-7:
                degen += 1
        zones = {}
        for z in mm.zones:
            zones[z] = zones.get(z, 0) + 1
        lo = [min(v[k] for v in mm.verts) for k in range(3)] if mm.verts else [0.0] * 3
        hi = [max(v[k] for v in mm.verts) for k in range(3)] if mm.verts else [0.0] * 3
        print("%s tris=%d verts=%d degenerate=%d zones=%s bbox=%s..%s"
              % (name, len(mm.faces), len(mm.verts), degen, zones,
                 ["%.1f" % x for x in lo], ["%.1f" % x for x in hi]))
    alphas = sorted(set(round(c[3], 3) for c in rays.colors))
    print("rays vanes=%d verts_per_ray=%d alphas=%s" % (RAY_VANES, len(rays.verts) // len(INFO["rays"]), alphas))
    for k, (top, foot, _s, _w) in enumerate(INFO["rays"]):
        print("ray%d top=(%.1f, %.1f, %.1f) foot=(%.1f, %.1f, %.1f) r=%.1f"
              % (k, top[0], top[1], top[2], foot[0], foot[1], foot[2], math.hypot(foot[0], foot[1])))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_forest_render)
