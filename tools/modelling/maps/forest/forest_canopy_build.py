"""
PANOPTICON -- forest_canopy: the wood's trees as MAP geometry, carrying the lane
roof as one layered canopy. One chunk, forest_canopy.glb, at identity.

Ryan: "now it just looks like the trees are dead; the roof doesn't look like
their leaves at all ... a bunch of skinny long branches going up into the roof."
"Make it look good, make it look like a proper forest."

Every tree in forest_trees.LAYOUT (bearing, radius, variant, spin, scale) is
built here at its exact place and scale against the REAL roof: forest_build's
_Ground is grown in this scene (its underside now dips over the trees) and
every leaf mass that reaches the roof is read off its actual triangles.

    trunk   forest_tree_prop_build's own first eight rings, unchanged -- the
            cover footprint and the collider -- then two more rings up to the
            FORK, half way to the roof, barely tapering
    boughs  two or three HEAVY boughs off the fork bands, short, sweeping out
            then up; each forks once more into a secondary; the trunk's own
            top carries on a little as a thick leader. No twigs.
    lobes   the foliage: irregular, stretched, skewed leaf masses -- a wobbly
            rim, a mid ring drifted sideways, a keel -- one on every bough tip
            (the bough runs INTO it, it sits on the bough), one round the
            leader's head, and one big crown mass over the trunk whose rim
            lies ON the roof (rims read off the mesh, buried LID_BURY). Any
            lobe whose top comes within LOBE_MERGE of the roof merges its rim
            into it too. Lobes of neighbouring trees overlap: one shared mass.
            Undersides and keels are "shade", flanks "leaf".

Collider: ForestCanopyCollision-colonly, every tree's own prop collider
(forest_tree_prop_build.build_collider) at that tree's transform -- the same
triangles the 113 prop instances gave the bake and the cover finder.

    tools/modelling/model build forest_canopy --views none
    tools/modelling/model build forest_canopy --views lane_up   # one EEVEE frame, lane eye looking ahead and up
    python3 tools/modelling/maps/forest/forest_canopy_build.py --check
"""

import math
import os
import shutil
import sys

try:
    import bpy
except ImportError:                       # --check on the Mac: geometry only
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import forest_tree_build as ft  # noqa: E402  the forest atlas, the mesh library
from forest_tree_build import (_Mesh, _Rng, UP, DOWN, add, sub, norm, dot,  # noqa: E402
                               lerp, bez, tube, socket_ring, pol)
import forest_tree_prop_build as ftp  # noqa: E402  the variants: trunk, sockets, collider
import forest_build as fb  # noqa: E402  the ground: the roof the trees end on
import forest_ceiling_build as fc  # noqa: E402
import forest_trees  # noqa: E402  LAYOUT: where every tree stands

if bpy is not None:
    import mdl  # noqa: E402
else:
    mdl = None

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "forest_canopy"
OBJECT_NAME = "ForestCanopy"
COLLIDER_NAME = "ForestCanopyCollision-colonly"
FACING_YAW = 0.0
LANE_Y = forest_trees.LANE_Y        # the props sank 0.05 m into the lane's relief; so do these
TREES = ("tree_a", "tree_b", "tree_c")
LETTER = {"tree_a": "a", "tree_b": "b", "tree_c": "c"}

FORK_H = (0.46, 0.54)       # the trunk forks this share of the way to the roof ...
FORK_MIN = 0.8              # ... and never less than this (local m) above the prop's last ring
TRUNK_DRIFT = 0.6           # the extension keeps this much of the last band's lean
TRUNK_TAPER = 0.74          # fork-ring radius / ring-7 radius
BOUGHS = {"a": 3, "b": 3, "c": 2}
BOUGH_BANDS = (8, 7, 8)     # trunk bands the primaries socket into (rings 8 and 9 are the extension)
BOUGH_JITTER = 25.0         # degrees off an even spread
BOUGH_R = {"a": (0.62, 0.5), "b": (0.6, 0.5), "c": (0.7, 0.5)}   # (root as a share of ring-7 radius, tip as a share of root)
BOUGH_OUT = (2.0, 3.2)      # metres out along the bearing to the tip, local
BOUGH_UP = (1.2, 2.6)
BOUGH_SIDES = 7
BOUGH_SEGS = 4
BOUGH_CTRL = (0.7, 0.15)    # the bezier's control: this far out, this far up the rise -- out first, then up
SUBS = (2, 1, 1)            # secondaries off primary 0, 1, 2
SUB_BAND = 2
SUB_OUT = (1.3, 2.2)
SUB_UP = (0.7, 1.7)
SUB_ANGLE = (40.0, 80.0)    # degrees off the host bough's bearing, either side
SUB_R = 0.6                 # root radius as a share of the host's root
SUB_SIDES = 6
SUB_SEGS = 3
LEADER_UP = (2.2, 3.2)
LEADER_TAPER = 0.6
LEADER_SEGS = 3
LEADER_BEND = 0.5           # metres of sideways bow in the leader
LOBE_R = {"bough": (1.9, 2.8), "sub": (1.4, 2.1), "head": (2.0, 2.9), "crown": (2.6, 3.6)}   # WORLD metres, the short axis
LOBE_DEPTH = {"bough": (1.1, 1.7), "sub": (0.9, 1.4), "head": (1.4, 2.0), "crown": (1.9, 2.8)}
LOBE_N = 10                 # rim vertices
LOBE_WOB = 0.28             # rim radius wobble
LOBE_STRETCH = (1.25, 1.8)  # long axis over short
LOBE_MID = (0.8, 0.5)       # the mid ring: this share of the rim radius, this share of the depth down
LOBE_KEEL = (0.32, 4)       # the keel: this share of the rim radius, this many vertices
LOBE_SKEW = 0.22            # the mid rings and the keel drift sideways this share of the radius
LOBE_PUSH = 0.45            # a bough's lobe is centred this share of its radius past the tip
LOBE_TOP = 0.55             # a free lobe's rim sits this share of its depth above the tip it holds
LOBE_MERGE = 0.9            # a lobe whose top comes within this (world m) of the roof merges its rim into it
LOBE_HEAD_OFF = 0.3         # the head lobe's centre off the leader's tip, as a share of its radius
LID_BURY = 0.10             # world metres a merged rim sits up inside the roof sheet
LID_CLEAR = 0.6             # a bough tip stays this share of its lobe's depth under the roof
TIP_R = (fb.INNER_R - 0.5, fb.OUTER_R + 1.0)   # where a bough's tip may sit: over the lane, a little past its edges
WELL_CLEAR = 0.5            # a lobe keeps its centre this far outside a sun well's blob (plus its radius)
CROWN_MIN_Z = ftp.CROWN_MIN_Z
SEED = 4471021

MAX_TRIS = 150000


# =============================================================================
# THE ROOF -- the real underside, off the built ground
# =============================================================================

def _tri_z(tri, x, y):
    """z of the triangle's plane at (x, y) if (x, y) is inside it in plan, else None."""
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = tri
    d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(d) < 1e-12:
        return None
    u = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / d
    v = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / d
    w = 1.0 - u - v
    if u < -1e-6 or v < -1e-6 or w < -1e-6:
        return None
    return u * az + v * bz + w * cz


class _Roof(object):
    """The lane roof as forest.glb ships it: gallery quads by (band, column)."""

    def __init__(self):
        g = fb._Ground()
        g.build()
        self.g = g
        self.nc = len(g.gal[0])
        self.tris = {}
        for k in range(len(g.gal) - 1):
            for i in range(self.nc):
                fis = g.m.quads.get(frozenset(fc.gal_quad_ids(g, k, i)))
                if fis:
                    self.tris[(k, i)] = [tuple(g.m.verts[j] for j in g.m.faces[fi]) for fi in fis]
        self.wells = [(sh["centre"], sh["radius"]) for sh in g.shafts]
        self.top = max(g.m.verts[v][2] for row in g.gal for v in row)

    def z(self, x, y):
        """The underside's height over (x, y), read off its own triangles."""
        bearing = (-math.degrees(math.atan2(y, x))) % 360.0
        i0 = int(bearing / (360.0 / self.nc))
        rad = math.hypot(x, y)
        for k in range(len(fc.GALLERY_R) - 1):
            if not (fc.GALLERY_R[k + 1] - 0.8 <= rad <= fc.GALLERY_R[k] + 0.8):
                continue
            for di in (0, -1, 1, -2, 2):
                for tri in self.tris.get((k, (i0 + di) % self.nc), ()):
                    z = _tri_z(tri, x, y)
                    if z is not None:
                        return z
        return fc.gallery_z(self.g, x, y)

    def well_clear(self, x, y, margin):
        return all(math.hypot(x - c[0], y - c[1]) >= r * 1.7 + margin for (c, r) in self.wells)


# =============================================================================
# PLACEMENT -- forest_trees.place, in Blender's frame
# =============================================================================

class _Place(object):
    """Local Blender xyz of a prop -> world: rotate by yaw+spin, scale, stand at the foot."""

    def __init__(self, bearing, radius, spin, scale):
        phi = math.radians(-bearing + spin)
        self.c, self.s = math.cos(phi), math.sin(phi)
        self.k = scale
        self.foot = pol(bearing, radius, LANE_Y)

    def __call__(self, p):
        x = self.foot[0] + self.k * (self.c * p[0] - self.s * p[1])
        y = self.foot[1] + self.k * (self.s * p[0] + self.c * p[1])
        return (x, y, LANE_Y + self.k * p[2])

    def xy(self, x, y):
        return self((x, y, 0.0))[:2]

    def local_xy(self, wx, wy):
        dx, dy = wx - self.foot[0], wy - self.foot[1]
        return ((self.c * dx + self.s * dy) / self.k, (-self.s * dx + self.c * dy) / self.k)

    def lid(self, roof, lx, ly):
        """The roof's underside over local (lx, ly), as a local height."""
        wx, wy = self.xy(lx, ly)
        return (roof.z(wx, wy) - LANE_Y) / self.k


# =============================================================================
# ONE TREE, in its own local frame
# =============================================================================

def _trunk_spec(spec, fork_z):
    """The variant's trunk, its first eight rings untouched, two more up to the fork."""
    path = [tuple(p) for p in spec["path"]]
    radii = list(spec["radii"])
    p6, p7 = path[-2], path[-1]
    dz = p7[2] - p6[2]
    drift = ((p7[0] - p6[0]) / dz * TRUNK_DRIFT, (p7[1] - p6[1]) / dz * TRUNK_DRIFT)
    fork_z = max(fork_z, p7[2] + FORK_MIN)
    for t in (0.5, 1.0):
        z = p7[2] + (fork_z - p7[2]) * t
        path.append((p7[0] + drift[0] * (z - p7[2]), p7[1] + drift[1] * (z - p7[2]), z))
        radii.append(radii[7] * (1.0 - (1.0 - TRUNK_TAPER) * t))
    out = dict(spec)
    out["path"], out["radii"] = path, radii
    return out


def _fit_tip(place, tip_xy):
    """Pull a tip's plan position over the lane roof: between TIP_R, in world."""
    wx, wy = place.xy(*tip_xy)
    rad = math.hypot(wx, wy)
    if rad < TIP_R[0] or rad > TIP_R[1]:
        want = max(TIP_R[0], min(TIP_R[1], rad))
        wx, wy = wx * want / rad, wy * want / rad
    return place.local_xy(wx, wy)


def _aim(place, roof, root_xy, d, out, margin):
    """A bough that would leave the roof (into the drum or the wall) is mirrored
    across the lane's tangent before its socket is chosen; one over a sun well
    is turned off it."""
    def world_ok(dd):
        wx, wy = place.xy(root_xy[0] + dd[0] * out, root_xy[1] + dd[1] * out)
        rad = math.hypot(wx, wy)
        return TIP_R[0] <= rad <= TIP_R[1]
    if not world_ok(d):
        fx, fy = place.foot[0], place.foot[1]
        rr = math.hypot(fx, fy)
        radial = (fx / rr, fy / rr)
        wd = (place.c * d[0] - place.s * d[1], place.s * d[0] + place.c * d[1])   # world direction
        k = wd[0] * radial[0] + wd[1] * radial[1]
        wd = (wd[0] - 2.0 * k * radial[0], wd[1] - 2.0 * k * radial[1])          # radial part flipped
        d = (place.c * wd[0] + place.s * wd[1], -place.s * wd[0] + place.c * wd[1], 0.0)
    for _ in range(6):
        wx, wy = place.xy(root_xy[0] + d[0] * out, root_xy[1] + d[1] * out)
        if roof.well_clear(wx, wy, margin):
            break
        a = math.radians(35.0)
        d = (d[0] * math.cos(a) - d[1] * math.sin(a), d[0] * math.sin(a) + d[1] * math.cos(a), 0.0)
    return d


def _lobe(m, rng, place, roof, centre, top_z, R_w, depth_w, merge, mids=1, hold_z=None):
    """One leaf mass. ``centre`` is its plan centre (local), ``top_z`` its rim
    height unless ``merge`` (rim on the roof); its keel stays under ``hold_z``,
    the tip it sits on. Returns the number of shells (1)."""
    k = place.k
    R, depth = R_w / k, depth_w / k
    cx, cy = centre
    a0 = rng.f() * 2.0 * math.pi
    st = rng.u(*LOBE_STRETCH)
    ca, sa = math.cos(a0), math.sin(a0)
    skew = (rng.sf() * LOBE_SKEW * R, rng.sf() * LOBE_SKEW * R)
    n = LOBE_N
    rim, rim_z, offs = [], [], []
    for s in range(n):
        a = 2.0 * math.pi * (s + 0.5 * rng.f()) / n
        f = 1.0 + LOBE_WOB * rng.sf()
        ex, ey = math.cos(a) * st, math.sin(a)
        dx, dy = R * f * (ca * ex - sa * ey), R * f * (sa * ex + ca * ey)
        lx, ly = cx + dx, cy + dy
        z = place.lid(roof, lx, ly) + LID_BURY / k if merge else top_z + 0.12 * depth * rng.sf()
        rim.append(m.v((lx, ly, z)))
        rim_z.append(z)
        offs.append((dx, dy))
    if merge and hold_z is not None:
        depth = max(depth, min(rim_z) - hold_z + 0.45 * depth)    # the keel stays under the tip it holds
    # mid rings hang from their own rim vertex: a rim on a sloping roof never folds
    rings = [rim]
    for j in range(mids):
        u = (j + 1) / float(mids + 1)
        share = 1.0 - (1.0 - LOBE_MID[0]) * u / LOBE_MID[1]
        ring = []
        for s in range(n):
            z = rim_z[s] - depth * u * (1.0 + 0.12 * rng.sf())
            ring.append(m.v((cx + skew[0] * u * 2.0 + offs[s][0] * share * (1.0 + 0.08 * rng.sf()),
                             cy + skew[1] * u * 2.0 + offs[s][1] * share, z)))
        rings.append(ring)
    zk = min(rim_z) - depth
    kn = LOBE_KEEL[1]
    kx, ky = cx + skew[0], cy + skew[1]
    keel = []
    for s in range(kn):
        a = 2.0 * math.pi * (s + 0.3 * rng.f()) / kn + a0
        f = LOBE_KEEL[0] * R * (1.0 + 0.15 * rng.sf())
        keel.append(m.v((kx + f * math.cos(a) * st, ky + f * math.sin(a), zk + 0.1 * depth * rng.sf())))
    inner = (cx + skew[0] * 0.6, cy + skew[1] * 0.6, min(rim_z) - depth * 0.45)   # every face points away from here
    for j in range(len(rings) - 1):
        a_, b_ = rings[j], rings[j + 1]
        for s in range(n):
            q = (s + 1) % n
            idx = (a_[s], a_[q], b_[q], b_[s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), inner), "leaf")
    _zip(m, rings[-1], keel, inner, "shade")
    m.fan(keel, DOWN, "shade")
    m.fan(rim, UP, "leaf")
    return 1


def _zip(m, outer, inner_ring, inner_pt, zone):
    """Triangles between two loops matched by angle, every one facing away from ``inner_pt``."""
    c = m.centroid(inner_ring)

    def ang(vid):
        p = m.verts[vid]
        return math.atan2(p[1] - c[1], p[0] - c[0])

    O = sorted(outer, key=ang)
    I = sorted(inner_ring, key=ang)
    aO, aI = [ang(v) for v in O], [ang(v) for v in I]
    i = j = 0
    no, ni = len(O), len(I)
    while i < no or j < ni:
        next_o = aO[i + 1] if i + 1 < no else aO[0] + 2.0 * math.pi
        next_i = aI[j + 1] if j + 1 < ni else aI[0] + 2.0 * math.pi
        oi, ii = O[i % no], I[j % ni]
        if (i < no and next_o <= next_i) or j >= ni:
            tri = (oi, O[(i + 1) % no], ii)
            i += 1
        else:
            tri = (oi, I[(j + 1) % ni], ii)
            j += 1
        m.tri(tri[0], tri[1], tri[2], sub(m.centroid(tri), inner_pt), zone)


def _bough(m, rng, spec, host, band, patch, bearing, out, up, radii, sides, segs,
           kind, place, roof, flip):
    """One bough: socket in the host, sweep out then up, cap the tip and grow
    its lobe round it. Returns (rings, bearing, shells)."""
    d = ftp._dir_of(bearing)
    R_w = rng.u(*LOBE_R[kind])
    depth_w = rng.u(*LOBE_DEPTH[kind])
    c = m.centroid(host[band] + host[band + 1])
    if flip:
        d = _aim(place, roof, (c[0], c[1]), d, out, R_w + WELL_CLEAR)
        bearing = -math.degrees(math.atan2(d[1], d[0]))
    quads, root, plane_n = ftp._patch(m, host, band, patch[0], patch[1], bearing)
    tx, ty = _fit_tip(place, (root[0] + d[0] * out, root[1] + d[1] * out))
    depth = depth_w / place.k
    lid = place.lid(roof, tx, ty)
    tz = min(root[2] + up, lid - LID_CLEAR * depth - LID_BURY / place.k)
    tip = (tx, ty, tz)
    collar = add(root, plane_n, ftp.STUB * radii[0])
    reach = sub(tip, collar)
    ctrl = (collar[0] + reach[0] * BOUGH_CTRL[0], collar[1] + reach[1] * BOUGH_CTRL[0],
            collar[2] + reach[2] * BOUGH_CTRL[1])
    path = [root, collar] + bez(collar, ctrl, tip, segs)[1:]
    flat = ftp._collar(m, quads, bearing, root, radii[0])
    ring0 = socket_ring(m, quads, path, radii[0], sides, "bark", flat=flat, at_start=True)
    rings = tube(m, path, tuple(radii), sides, "bark", caps=(False, True),
                 wob=spec["wob"], rng=rng, first_ring=ring0)
    R = R_w / place.k
    centre = (tx + d[0] * LOBE_PUSH * R, ty + d[1] * LOBE_PUSH * R)
    top_z = tz + LOBE_TOP * depth
    merge = top_z >= lid - LOBE_MERGE / place.k
    shells = _lobe(m, rng, place, roof, centre, top_z, R_w, depth_w, merge, hold_z=tz)
    return rings, bearing, shells


def _leader(m, rng, spec, trunk, place, roof):
    """The trunk's top carries on, thick and bowing a little, into the head lobe."""
    top_ring, top_c = trunk["top_ring"], trunk["top_centre"]
    n = len(top_ring)
    ang = [math.atan2(m.verts[v][1] - top_c[1], m.verts[v][0] - top_c[0]) for v in top_ring]
    R_w = rng.u(*LOBE_R["head"])
    depth_w = rng.u(*LOBE_DEPTH["head"])
    depth = depth_w / place.k
    a = rng.f() * 2.0 * math.pi
    tx, ty = _fit_tip(place, (top_c[0] + 0.4 * math.cos(a), top_c[1] + 0.4 * math.sin(a)))
    lid = place.lid(roof, tx, ty)
    tz = min(top_c[2] + rng.u(*LEADER_UP), lid - LID_CLEAR * depth - LID_BURY / place.k)
    tip = (tx, ty, tz)
    b = a + math.pi / 2.0
    mid = lerp(top_c, tip, 0.5)
    ctrl = (mid[0] + LEADER_BEND * math.cos(b), mid[1] + LEADER_BEND * math.sin(b), mid[2])
    path = bez(top_c, ctrl, tip, LEADER_SEGS)
    r0, r1 = trunk["top_r"], trunk["top_r"] * LEADER_TAPER
    rings = [list(top_ring)]
    for i in range(1, len(path)):
        t = i / float(len(path) - 1)
        r = r0 + (r1 - r0) * t
        cx, cy, cz = path[i]
        rings.append([m.v((cx + r * (1.0 + spec["wob"] * rng.sf()) * math.cos(ang[s]),
                           cy + r * (1.0 + spec["wob"] * rng.sf()) * math.sin(ang[s]), cz))
                      for s in range(n)])
    for i in range(len(rings) - 1):
        axis = lerp(path[i], path[i + 1], 0.5)
        for s in range(n):
            q = (s + 1) % n
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), axis), "bark")
    m.fan(rings[-1], UP, "bark")
    R = R_w / place.k
    c = rng.f() * 2.0 * math.pi
    centre = (tx + LOBE_HEAD_OFF * R * math.cos(c), ty + LOBE_HEAD_OFF * R * math.sin(c))
    top_z = tz + LOBE_TOP * depth
    merge = top_z >= lid - LOBE_MERGE / place.k
    return _lobe(m, rng, place, roof, centre, top_z, R_w, depth_w, merge, hold_z=tz)


def _crown(m, rng, trunk, place, roof):
    """The big mass over the trunk, its rim on the roof, its underside two rings deep."""
    top_c = trunk["top_centre"]
    R_w = rng.u(*LOBE_R["crown"])
    depth_w = rng.u(*LOBE_DEPTH["crown"])
    R = R_w / place.k
    a = rng.f() * 2.0 * math.pi
    centre = (top_c[0] + 0.25 * R * math.cos(a), top_c[1] + 0.25 * R * math.sin(a))
    top_z = place.lid(roof, centre[0], centre[1])
    return _lobe(m, rng, place, roof, centre, top_z, R_w, depth_w, True, mids=2)


def build_tree(m, rng, spec, place, roof):
    """One tree in its local frame: trunk, boughs and their secondaries, the leader, the lobes."""
    first_v = len(m.verts)
    h_local = place.lid(roof, 0.0, 0.0)
    fork = rng.u(*FORK_H) * h_local
    trunk = ftp.build_trunk(m, rng, _trunk_spec(spec, fork))
    n_trunk = len(trunk["rings"]) * len(trunk["rings"][0]) + 1
    letter = spec["letter"]
    shells = 1
    base = rng.f() * 360.0
    r7 = spec["radii"][7]
    boughs, bearings = [], []
    count = BOUGHS[letter]
    root_share, tip_share = BOUGH_R[letter]
    for i in range(count):
        bearing = base + 360.0 * i / count + rng.sf() * BOUGH_JITTER
        r0 = r7 * root_share
        rings, bearing, sh = _bough(m, rng, spec, trunk["rings"], BOUGH_BANDS[i], (1, 3), bearing,
                                    rng.u(*BOUGH_OUT), rng.u(*BOUGH_UP), (r0, r0 * tip_share),
                                    BOUGH_SIDES, BOUGH_SEGS, "bough", place, roof, flip=True)
        boughs.append((rings, r0))
        bearings.append(bearing)
        shells += sh
    for i, (rings, r0) in enumerate(boughs):
        for _ in range(SUBS[i]):
            side = 1.0 if rng.f() < 0.5 else -1.0
            bearing = bearings[i] + side * rng.u(*SUB_ANGLE)
            rs = r0 * SUB_R
            _, _, sh = _bough(m, rng, spec, rings, SUB_BAND, (1, 2), bearing, rng.u(*SUB_OUT),
                              rng.u(*SUB_UP), (rs, rs * 0.55), SUB_SIDES, SUB_SEGS, "sub",
                              place, roof, flip=True)
            shells += sh
    shells += _leader(m, rng, spec, trunk, place, roof)
    shells += _crown(m, rng, trunk, place, roof)
    crown = m.verts[first_v + n_trunk:]
    lowest = min(p[2] for p in crown)
    assert lowest >= CROWN_MIN_Z - 1e-9, "crown reaches z=%.2f under CROWN_MIN_Z" % lowest
    return shells


# =============================================================================
# THE CHUNK -- every tree, placed; one collider
# =============================================================================

def _append(dst, src, place):
    """src's faces into dst, its vertices through place."""
    base = len(dst.verts)
    for p in src.verts:
        dst.v(place(p))
    for f, z in zip(src.faces, src.zones):
        if f is None:
            continue
        dst.faces.append(tuple(i + base for i in f))
        dst.zones.append(z)


def tree_rows():
    return [r for r in forest_trees.LAYOUT if r[1] in TREES]


def build_geometry():
    """(canopy mesh, collider mesh, stats)."""
    roof = _Roof()
    m, c = _Mesh(), _Mesh()
    stats = {"trees": 0, "shells": 0, "per_kind": {}, "roof_top": roof.top}
    for idx, (section, kind, bearing, radius, aim, spin, scale) in enumerate(tree_rows()):
        assert aim == "radial", aim
        spec = ftp.spec_of(LETTER[kind])
        place = _Place(bearing, radius, spin, scale[0])
        local = _Mesh()
        rng = _Rng(SEED + spec["seed"] + 7919 * idx)
        stats["shells"] += build_tree(local, rng, spec, place, roof)
        local.compact()
        _append(m, local, place)
        _append(c, ftp.build_collider(spec).compact(), place)
        stats["trees"] += 1
        stats["per_kind"][kind] = stats["per_kind"].get(kind, 0) + 1
    return m, c, stats


def build():
    m, c, stats = build_geometry()
    albedo, emissive = ft.sheet("forest_atlas", ft.paint_atlas)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    ob = m.object(OBJECT_NAME)
    ft.unwrap(ob, m.zones)
    mdl.finish(ob, ft.atlas_material("ForestAtlas", albedo, emissive), strip_uvs=False)
    coll = c.object(COLLIDER_NAME)
    coll.hide_render = True
    zs = [v[2] for v in m.verts]
    print("MDL STATS trees=%d shells=%d %s visual_tris=%d collision_tris=%d top_y=%.2f roof_y=%.1f"
          % (stats["trees"], stats["shells"], stats["per_kind"], len(ob.data.polygons),
             len(coll.data.polygons), max(zs), fc.GALLERY_Z))
    return [ob, coll]


# =============================================================================
# THE FRAME -- a prisoner's eye on the lane, looking ahead and up
# =============================================================================

LANE_UP_BEARING = 196.0     # the eye stands mid-lane here ...
LANE_UP_AHEAD = 11.0        # ... looking this many degrees on round the lane ...
LANE_UP_RISE = 8.0          # ... at a point this far over the grass
LANE_UP_LENS = 18.0
LANE_UP_RES = (1400, 1500)
PC_OUT = r"C:\Users\ddd\Desktop\panopticon-renders\forest-canopy3"


def post(spec, objects):
    """--views lane_up: the map grown in this scene as the backdrop, one EEVEE frame."""
    if "lane_up" not in (spec.get("views") or []):
        spec["views"] = []              # the named views frame 120 m of forest as a rifle
        return
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 64)))
    mdl._try(scene.eevee, "use_shadows", True)
    mdl._try(scene.eevee, "use_raytracing", True)
    mdl._try(scene.eevee, "shadow_ray_count", 2)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")
    mdl._try(scene.view_settings, "exposure", fb.REVIEW_EXPOSURE)

    ground = fb.build()
    for ob in ground:
        if ob.name == fb.RAYS_SOLID_NAME:
            ob.hide_render = True
    tower = ft.build_render_copy(fb.INFO["albedo"], fb.INFO["emissive"])

    world = bpy.data.worlds.new("ForestSky")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (fb.REVIEW_SKY[0], fb.REVIEW_SKY[1], fb.REVIEW_SKY[2], 1.0)
    bg.inputs[1].default_value = fb.REVIEW_WORLD * fb.REVIEW_WORLD_VARIANT["light"]
    sb, se = fb.SUN
    aim = mdl._link(bpy.data.objects.new("ReviewAim", None))
    aim.location = (0.0, 0.0, 20.0)
    lights = []
    for (nm, energy, colour, shadow, b, e) in (("ReviewSun", fb.REVIEW_SUN, (1.0, 0.96, 0.84), True, sb, se),
                                               ("ReviewFill", fb.REVIEW_FILL, (0.9, 1.0, 0.9), False, sb + 180.0, 40.0)):
        ld = bpy.data.lights.new(nm, type="SUN")
        ld.energy, ld.color = energy, colour
        mdl._try(ld, "use_shadow", shadow)
        ob = mdl._link(bpy.data.objects.new(nm, ld))
        ob.location = add(aim.location, (math.cos(math.radians(e)) * math.cos(math.radians(-b)),
                                         math.cos(math.radians(e)) * math.sin(math.radians(-b)),
                                         math.sin(math.radians(e))), 120.0)
        con = ob.constraints.new(type="TRACK_TO")
        con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"
        lights.append(ob)

    mid_r = 0.5 * (forest_trees.NAV_INNER + forest_trees.NAV_OUTER)
    target = mdl._link(bpy.data.objects.new("ForestTarget", None))
    target.location = pol(LANE_UP_BEARING + LANE_UP_AHEAD, mid_r, fb.DECK_Z + LANE_UP_RISE)
    cam = mdl._link(bpy.data.objects.new("ForestCam", bpy.data.cameras.new("ForestCam")))
    cam.location = pol(LANE_UP_BEARING, mid_r, fb.DECK_Z + fb.EYE_H)
    cam.data.lens = LANE_UP_LENS
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    scene.render.resolution_x, scene.render.resolution_y = LANE_UP_RES
    bpy.context.view_layer.update()
    out_dir = spec.get("out_dir", ".")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "%s_lane_up.png" % NAME)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("MDL RENDER %s (lane eye at bearing %.1f, ahead and up)" % (os.path.basename(path), LANE_UP_BEARING))
    if os.path.isdir(os.path.dirname(PC_OUT)):
        os.makedirs(PC_OUT, exist_ok=True)
        shutil.copyfile(path, os.path.join(PC_OUT, "lane.png"))
        print("MDL RENDER copied to %s" % os.path.join(PC_OUT, "lane.png"))
    for ob in [cam, target, aim, tower] + lights + list(ground):
        bpy.data.objects.remove(ob, do_unlink=True)
    spec["views"] = []


# =============================================================================
# CHECK -- the geometry, on the Mac, no Blender
# =============================================================================

def _check():
    import forest_check
    m, c, stats = build_geometry()
    m.compact()
    c.compact()
    vis = forest_check.prove(m, NAME)
    col = forest_check.prove(c, NAME + "_collider")
    zs = [v[2] for v in m.verts]
    print("SIZE trees=%d shells=%d %s top_y=%.2f roof_top=%.2f" % (stats["trees"], stats["shells"], stats["per_kind"],
                                                                 max(zs), stats["roof_top"]))
    ok = True
    for label, cond, why in (
            ("components", vis["components"] == stats["shells"], "one shell per tree and per lobe"),
            ("duplicates", vis["duplicate_positions"] == 0, "no split seam"),
            ("degenerate", vis["degenerate"] == 0, "no degenerate faces"),
            ("open_edges", vis["open_edges"] == 0, "closed volumes"),
            ("tris", vis["tris"] <= MAX_TRIS, "<= %d tris" % MAX_TRIS),
            ("coll_components", col["components"] == stats["trees"], "one collider shell per tree"),
            ("under_roof", max(zs) <= stats["roof_top"] + LID_BURY + 0.5, "nothing through the ceiling"),
    ):
        if not cond:
            ok = False
            print("FAIL %s: %s" % (label, why))
    print("CHECK %s" % ("OK" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(_check())
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=post)
