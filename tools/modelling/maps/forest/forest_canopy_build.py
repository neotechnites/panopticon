"""
PANOPTICON -- forest_canopy: the wood's trees as MAP geometry, carrying the lane
roof as one layered canopy. One chunk, forest_canopy.glb, at identity.

Ryan: "the trees still look stupid ... the trees don't even rise high enough to
be part of the roof ... the stupid bubble you made goes right off the edge."
"Make it look good, make it look like a proper forest."

Every tree in forest_trees.LAYOUT (bearing, radius, variant, spin, scale) is
built here at its exact place and scale against the REAL roof: forest_build's
_Ground is grown in this scene (its underside dips over the trees, on the deck
only) and every crown reads the roof off its actual triangles. A tree is built
the way a broadleaf is:

    trunk   forest_tree_prop_build's own rings, unchanged where they are cover
            and collider, with a buttressed FLARE at the foot (one ring more,
            ridged), then carried on -- thick, straightening -- to the roof
            itself: its top ring sits up inside the roof sheet.
    boughs  three or four HEAVY primaries off the carried-on trunk at different
            heights, leaving at ~40 deg and sweeping up to a FORK about half
            way to the roof; past the fork each carries on, bending, to the
            roof, throws a side limb off the fork that climbs to the roof too,
            and (some of them) a thinner third limb higher up. Every limb ends
            IN the roof, never under it.
    crown   many smaller overlapping leaf clusters rather than one lump: one
            round the trunk's head, one round every limb's end, two loose ones
            hung between; every one has its rim ON the roof (read off the
            mesh, buried LID_BURY) and hangs a different depth, so the roof is
            visibly made of crowns, the underside is lobed, and no gap opens
            between crown and roof anywhere. Ryan: "still sticking out": every
            cluster is a broad SHALLOW lobe (CLUSTER), all "leaf", its rim over
            the roof's highest point under it, so no facet faces the sun.
    deck    nothing of a crown passes the pit lip or the wall foot: tips stay
            over the lane (TIP_R), clusters are centred in and clipped to
            CROWN_IN..OUTER_R (off the lip's fern band), and the roof's own dips
            (forest_ceiling_build.deck_window) end there too. Ryan: "the trees
            are still completely fucked at the edge": a tree within LIP_NEAR of
            the lip grows ONE-SIDED -- a limb aimed over the pit is turned to run
            along the lip (LIP_ALONG off the tangent, toward the lane), so its
            pit side carries nothing but the trunk.
    fringe  Ryan: "a huge gap on the wall side of the flat roof, and on the ring
            side there's still a very clear corner ... it should look like one
            surface modelled with intention." Past the crowns' clipped rims the
            roof is not left bare: ragged rows of smaller clusters (FRINGE) hang
            from it, three carpeting the lane between the crowns so the sheet
            never shows flat, thinning as they go (LIFT). Outward they run over the
            roof's cove (forest_ceiling_build.COVE_R) and down it into the
            wall's head, each hung along the cove's normal so the mass curves
            over and down with it; inward the roof itself ends the mass: at the
            lip the sheet rolls under and back (forest_ceiling_build.ROLL), so
            the last row stops where the roll begins. No straight line, no
            corner, no flat plane beside a mass, nothing low over the lip or the pit.
    uv      forest_tiles.dress: box-projected at texel.MPT, the map's own density;
            leaf and bark tiles, tinted per zone in COLOR_0.
    shade   Ryan: "the trees still have ugly sharp edges." Nothing here is
            flat-shaded: the chunk shades smooth (a bough is a rounded limb),
            and every cluster's normals lean out and DOWN from a centre above its
            rim (SOFT_OUT, SOFT_ABOVE) so the leaf mass shades as a soft volume
            the sun never catches; its mid rings are lobed
            (LOBE_BULGE, LOBE_SAG) so the silhouette is ragged from the shape.

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
import forest_tiles  # noqa: E402  the forest's tiles, tinted per zone
from forest_tree_build import (_Mesh, _Rng, UP, DOWN, add, sub, bez, tube,  # noqa: E402
                               socket_ring, pol)
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

DECK_R = (fb.INNER_R, fb.OUTER_R)   # the walkable annulus: every crown lives over it
DECK_EDGE = 0.25            # ... and comes no nearer its wall foot than this (world m)
CROWN_IN = fb.INNER_R + 0.9  # ... nor its lip than this: a crown's rim stops outside the lip's fern band
TIP_R = (fb.INNER_R + 2.3, fb.OUTER_R - 1.8)   # where a limb may end: over the lane, inside its own cluster's clipped rim
LIP_NEAR = 3.0              # a tree standing this near the lip (world m) grows one-sided ...
LIP_ALONG = 15.0            # ... a limb of its aimed over the pit runs along the lip instead, this far off the tangent toward the lane

FLARE = {"a": (1.22, 1.12, 0.18, 4), "b": (1.15, 1.08, 0.16, 5), "c": (1.22, 1.12, 0.18, 4)}
                            # (ring-1 swell, flare-ring swell, buttress ridge amplitude, ridges)
FLARE_Z = 0.32              # the flare ring's height (local m), between the prop's rings 1 and 2
PROP_TOP = 8                # the prop's top ring's index once the flare ring is in (its rings 0..7 -> 0..8)
EXT_RINGS = ((0.13, 0.97), (0.27, 0.92), (0.42, 0.85), (0.57, 0.77), (0.72, 0.69), (0.86, 0.61), (1.0, 0.55))
                            # (share of the climb prop top -> roof, radius / prop top radius): bands short enough not to sliver
EXT_DRIFT = (0.6, 0.5, 0.35, 0.25, 0.15, 0.08, 0.05)   # the share of the prop's lean each carried-on band keeps: it straightens
EXT_WANDER = 0.08           # local m of sideways wander per carried-on ring
TRUNK_BURY = 0.15           # world m the trunk's top ring sits up inside the roof

BOUGHS = {"a": 3, "b": 4, "c": 3}
BOUGH_BANDS = {"a": (8, 10, 12), "b": (8, 10, 12, 10), "c": (8, 10, 12)}   # carried-on trunk bands the primaries socket into
BOUGH_PATCH = {"a": 3, "b": 4, "c": 3}   # trunk sides a primary's socket claims (the ring must sit inside them)
BOUGH_JITTER = 20.0         # degrees off an even spread
BOUGH_R = 0.66              # a primary's root radius as a share of the trunk's there ...
BOUGH_TAPER = 0.78          # ... and its radius at the fork as a share of its root
BOUGH_OUT = (1.7, 2.6)      # local m out along the bearing to the fork
FORK_SHARE = (0.28, 0.45)   # the fork sits this share of the climb from the socket to the roof
BOUGH_CTRL = (0.45, 0.35)   # bezier control to the fork: this far out, this far up -- the bough leaves at ~40 deg
BOUGH_SIDES = 6
BOUGH_SEGS = (3, 3)         # bezier segments socket -> fork, fork -> roof
ON_OUT = (1.4, 2.6)         # past the fork the primary carries on this far out ...
ON_BEND = (18.0, 38.0)      # ... bending this many degrees either side ...
ON_TAPER = 0.6              # ... to this share of its fork radius where it enters the roof
SIDE_BAND = 3               # the side limb sockets into the band just under the fork ring (path index 4)
SIDE_OUT = (1.2, 2.4)
SIDE_ANGLE = (42.0, 75.0)   # degrees off the primary's bearing, away from its bend
SIDE_R = (0.72, 0.65)       # root as a share of the fork radius, tip as a share of root
SIDE_SIDES = 5
SIDE_SEGS = 3
TWIGS = {"a": 2, "b": 2, "c": 2}   # how many primaries carry a third, thinner limb off the carried-on part
TWIG_BAND = 5               # the band of the carried-on part it sockets into
TWIG_OUT = (0.9, 1.8)
TWIG_ANGLE = (40.0, 70.0)
TWIG_R = (0.52, 0.7)        # root as a share of the fork radius, tip as a share of root
TWIG_SIDES = 4
TWIG_SEGS = 2
UP_CTRL = 0.45              # a limb bound for the roof bows out this share of its rise before it climbs

# Ryan: "the models in the forest are still sticking out." A cluster is a broad,
# shallow lobe (depth <= ~0.7 x its radius), never a deep lump: its flanks slope under
# 52 deg, so the sun (52 deg up, through a roof that casts no shadow) never lights a
# facet pale, and its rim overlaps its neighbours' -- one lobed underside, no blobs.
CLUSTER = {                 # WORLD metres: (short radius lo, hi), (depth lo, hi), mid rings
    "head": ((2.3, 2.9), (1.2, 1.7), 2),
    "on": ((1.7, 2.4), (0.9, 1.3), 1),
    "side": ((1.4, 2.0), (0.7, 1.1), 1),
    "twig": ((1.1, 1.6), (0.55, 0.85), 1),
    "loose": ((1.0, 1.5), (0.5, 0.8), 1),
}
LOOSE = 1                   # loose clusters hung between the limbs, per tree
LOOSE_AT = (1.5, 3.5)       # local m off the trunk's head
LOBE_N = 7                  # rim vertices
LOBE_WOB = 0.28             # rim radius wobble
LOBE_STRETCH = (1.2, 1.6)   # long axis (along the lane) over short (across it)
LOBE_MID = (0.72, 0.5)      # the mid ring: this share of the rim radius, this share of the depth down
LOBE_KEEL = (0.36, 4)       # the keel: this share of the rim radius, this many vertices
LOBE_SKEW = 0.18            # the mid rings and the keel drift sideways this share of the radius
LOBE_PUSH = 0.15            # a limb's cluster is centred this share of its radius past the tip: the tip is well inside its lobe
# Ryan: "the trees still have ugly sharp edges." A cluster is lobed, not a convex
# polyhedron: its mid rings swell in and out (a two-lobe swell round the ring plus a
# per-vertex wobble, off the cluster's own sub-seed so no placement draw moves), and
# its normals are smooth, leaning out from its centre by SOFT_OUT so it shades as one
# soft volume the way low-poly crowns do. Boughs and trunks shade smooth along their length.
LOBE_BULGE = (0.10, 0.12)   # (two-lobe swell, per-vertex wobble) of a mid ring's radius: never past the rim
LOBE_SAG = 0.15             # a mid-ring vertex's hang wobbles this share of its own depth
KEEL_LIFT = 0.12            # a keel vertex rides up to this share of the depth: no flat underside
SOFT_OUT = 0.65             # a cluster vertex's normal: this much radial from its centre, the rest smooth
SOFT_ABOVE = 1.0            # that centre sits this many radii ABOVE the rim: every normal leans out and DOWN, none up into the sun
LID_BURY = 0.10             # world metres a rim sits up inside the roof sheet
WELL_CLEAR = 0.5            # a fork keeps this far outside a sun well's blob (plus its cluster's radius)
CROWN_MIN_Z = ftp.CROWN_MIN_Z
SEED = 4471021

# The fringe: rows of smaller clusters past the crowns' clipped rims, each row
# (seed index, centre radius, radial jitter), WORLD sizes ((short radius lo, hi), (depth lo, hi)),
# the step along the lane in metres (lo, hi) and the share of its places left empty.
# Ryan: "the edge side has these trees just overspilling again." No row over the lip
# band: the roof's own roll ends the mass there (forest_ceiling_build.ROLL) and the
# inner row's rims stop at CROWN_IN, their hang fading toward the lip over LIP_FADE.
# Nothing hangs past r 46.7 below the roof plane. The wall side is untouched.
# The lane rows (mid1..3) carpet the roof between the crowns: shallow lobes every few
# metres, overlapping, so no flat sheet shows between one crown and the next.
FRINGE = (
    ("mid1", 4, (50.3, 0.6), ((1.4, 2.1), (0.7, 1.1)), (2.2, 3.6), 0.10),
    ("mid2", 5, (52.3, 0.6), ((1.4, 2.1), (0.7, 1.1)), (2.2, 3.6), 0.10),
    ("mid3", 6, (54.3, 0.6), ((1.4, 2.1), (0.7, 1.1)), (2.2, 3.6), 0.10),
    ("out",  2, (56.6, 0.5), ((1.3, 1.9), (0.6, 1.0)), (2.4, 4.0), 0.12),   # where the roof turns down into the cove
    ("cove", 3, (58.3, 0.4), ((0.9, 1.4), (0.4, 0.7)), (1.8, 3.0), 0.15),   # down the cove, thinning into the wall's head
)
LIP_FADE = 1.6              # a fringe vertex's hang fades from full to nothing over this much approaching the lip
FRINGE_BAND = (CROWN_IN, 58.9)   # a fringe rim reaches the lip's fern band and this far down the cove (y ~36.7 there)
LIFT = ((46.7, 0.4), (49.0, 1.0), (56.5, 1.0), (58.0, 0.55), (58.9, 0.2))
                            # (world radius, share of a fringe cluster's depth): full over the lane, thinning
                            # toward the lip and down the cove: nothing low over the pit or the cells
WALL_FLOOR = 36.75          # no fringe keel under this on the cove: the third tier's apex row is 36.6
FRINGE_SEED = 5570119

MAX_TRIS = 185000           # canopy7 was 147k; the lane rows add ~330 shallow lobes


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

    def edge_z(self, x, y):
        """The roof's edge over the pit: its foot ring's height at this bearing."""
        t = ((-math.degrees(math.atan2(y, x))) % 360.0) / (360.0 / self.nc)
        i0 = int(t) % self.nc
        ring = self.g.gal[-1]
        z0, z1 = self.g.m.verts[ring[i0]][2], self.g.m.verts[ring[(i0 + 1) % self.nc]][2]
        return z0 + (z1 - z0) * (t - int(t))

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
        fx, fy = self.foot[0], self.foot[1]
        rr = math.hypot(fx, fy)
        tx, ty = -fy / rr, fx / rr                    # the lane's tangent at the foot, world ...
        self.tangent_a = math.atan2(-self.s * tx + self.c * ty, self.c * tx + self.s * ty)   # ... as a local angle
        self.lip = rr < DECK_R[0] + LIP_NEAR          # a lip tree: one-sided (_aim)

    def __call__(self, p):
        x = self.foot[0] + self.k * (self.c * p[0] - self.s * p[1])
        y = self.foot[1] + self.k * (self.s * p[0] + self.c * p[1])
        return (x, y, LANE_Y + self.k * p[2])

    def xy(self, x, y):
        return self((x, y, 0.0))[:2]

    def local_xy(self, wx, wy):
        dx, dy = wx - self.foot[0], wy - self.foot[1]
        return ((self.c * dx + self.s * dy) / self.k, (-self.s * dx + self.c * dy) / self.k)

    def local_dir(self, wx, wy):
        """A world plan displacement in the local frame (turned and scaled, not moved)."""
        return ((self.c * wx + self.s * wy) / self.k, (-self.s * wx + self.c * wy) / self.k)

    def lid(self, roof, lx, ly):
        """The roof's underside over local (lx, ly), as a local height."""
        wx, wy = self.xy(lx, ly)
        return (roof.z(wx, wy) - LANE_Y) / self.k


# =============================================================================
# ONE TREE, in its own local frame
# =============================================================================

def _rot(d, deg):
    a = math.radians(deg)
    return (d[0] * math.cos(a) - d[1] * math.sin(a), d[0] * math.sin(a) + d[1] * math.cos(a), 0.0)


def _fit_tip(place, tip_xy, band=TIP_R):
    """Pull a plan position over the lane: between ``band`` radii, in world."""
    wx, wy = place.xy(*tip_xy)
    rad = math.hypot(wx, wy)
    if rad < band[0] or rad > band[1]:
        want = max(band[0], min(band[1], rad))
        wx, wy = wx * want / rad, wy * want / rad
    return place.local_xy(wx, wy)


def _aim(place, roof, root_xy, d, out, margin):
    """A limb that would leave the lane (over the drop or into the wall) is
    mirrored across the lane's tangent before its socket is chosen; a lip tree's
    limb aimed over the pit runs along the lip instead; one over a sun well is turned off it."""
    def world_ok(dd):
        wx, wy = place.xy(root_xy[0] + dd[0] * out, root_xy[1] + dd[1] * out)
        rad = math.hypot(wx, wy)
        return TIP_R[0] <= rad <= TIP_R[1]
    fx, fy = place.foot[0], place.foot[1]
    rr = math.hypot(fx, fy)
    radial = (fx / rr, fy / rr)
    wd = (place.c * d[0] - place.s * d[1], place.s * d[0] + place.c * d[1])   # world direction
    k = wd[0] * radial[0] + wd[1] * radial[1]
    if place.lip and k < math.sin(math.radians(LIP_ALONG)):
        t = wd[0] * -radial[1] + wd[1] * radial[0]                              # its tangential sense
        t = 1.0 if t >= 0.0 else -1.0
        ca, sa = math.cos(math.radians(LIP_ALONG)), math.sin(math.radians(LIP_ALONG))
        wd = (sa * radial[0] - ca * t * radial[1], sa * radial[1] + ca * t * radial[0])
        d = (place.c * wd[0] + place.s * wd[1], -place.s * wd[0] + place.c * wd[1], 0.0)
    elif not world_ok(d):
        wd = (wd[0] - 2.0 * k * radial[0], wd[1] - 2.0 * k * radial[1])          # radial part flipped
        d = (place.c * wd[0] + place.s * wd[1], -place.s * wd[0] + place.c * wd[1], 0.0)
    for _ in range(6):
        wx, wy = place.xy(root_xy[0] + d[0] * out, root_xy[1] + d[1] * out)
        if roof.well_clear(wx, wy, margin):
            break
        d = _rot(d, 35.0)
    return d


# ---- the trunk ---------------------------------------------------------------

def _trunk_spec(spec, place, roof, rng):
    """The variant's trunk, its flare ring in, carried on to the roof: the prop's
    rings keep their place; the extension straightens, wanders, stays over the lane."""
    path = [tuple(p) for p in spec["path"]]
    radii = list(spec["radii"])
    swell1, swellf, _amp, _n = FLARE[spec["letter"]]
    p1, p2 = path[1], path[2]
    t = (FLARE_Z - p1[2]) / (p2[2] - p1[2])
    path.insert(2, (p1[0] + (p2[0] - p1[0]) * t, p1[1] + (p2[1] - p1[1]) * t, FLARE_Z))
    radii.insert(2, (radii[1] + (radii[2] - radii[1]) * t) * swellf)
    radii[1] *= swell1
    radii[0] *= 0.5 * (1.0 + swell1)
    top, below = path[PROP_TOP], path[PROP_TOP - 1]
    dz = top[2] - below[2]
    lean = ((top[0] - below[0]) / dz, (top[1] - below[1]) / dz)
    wander = [(rng.sf() * EXT_WANDER, rng.sf() * EXT_WANDER) for _ in EXT_RINGS]
    h = place.lid(roof, top[0], top[1]) - top[2]      # the climb, local m
    r_top = radii[PROP_TOP]
    f = 1.0
    for _ in range(8):                                # the lean's share, halved until the head is over the lane
        ext, x, y, z = [], top[0], top[1], top[2]
        for (share, rr), drift, (wx, wy) in zip(EXT_RINGS, EXT_DRIFT, wander):
            nz = top[2] + share * h
            x += lean[0] * drift * f * (nz - z) + wx
            y += lean[1] * drift * f * (nz - z) + wy
            z = nz
            ext.append((x, y, z))
        hx, hy = place.xy(ext[-1][0], ext[-1][1])
        if TIP_R[0] <= math.hypot(hx, hy) <= TIP_R[1]:
            break
        f *= 0.5
    hx, hy, _ = ext[-1]
    ext[-1] = (hx, hy, place.lid(roof, hx, hy) + TRUNK_BURY / place.k)
    path += ext
    radii += [r_top * rr for (_share, rr) in EXT_RINGS]
    out = dict(spec)
    out["path"], out["radii"] = path, radii
    return out


def _flare(m, rng, spec, trunk):
    """Buttress ridges on the foot rings: the flare is not a cone."""
    _s1, _sf, amp, ridges = FLARE[spec["letter"]]
    phase = rng.f() * 2.0 * math.pi
    for k, weight in ((0, 1.0), (1, 1.0), (2, 0.55)):
        cx, cy, _cz = trunk["path"][k]
        for vid in trunk["rings"][k]:
            x, y, z = m.verts[vid]
            a = math.atan2(y - cy, x - cx)
            f = 1.0 + amp * weight * max(0.0, math.cos(ridges * a + phase)) ** 2
            m.verts[vid] = (cx + (x - cx) * f, cy + (y - cy) * f, z)


# ---- the limbs ---------------------------------------------------------------

def _climb(m, rng, spec, quads, root, plane_n, bearing, path_mid, tip, radii, sides):
    """Weld a limb into its patch and run it out along ``path_mid`` (the points
    after the collar) to ``tip``, capped there (inside the roof)."""
    collar = add(root, plane_n, ftp.STUB * radii[0])
    path = [root, collar] + path_mid
    flat = ftp._collar(m, quads, bearing, root, radii[0])
    ring0 = socket_ring(m, quads, path, radii[0], sides, "bark", flat=flat, at_start=True)
    return tube(m, path, tuple(radii), sides, "bark", caps=(False, True),
                wob=spec["wob"], rng=rng, first_ring=ring0), collar


def _to_roof(place, roof, start, d, out):
    """The end of a limb bound for the roof: ``out`` along ``d`` from ``start``
    in plan, pulled over the lane, its z up inside the roof sheet."""
    tx, ty = _fit_tip(place, (start[0] + d[0] * out, start[1] + d[1] * out))
    return (tx, ty, place.lid(roof, tx, ty) + LID_BURY / place.k)


def _limb(m, rng, spec, host, band, patch, bearing, out, radii, sides, segs, place, roof, kind):
    """A limb off a host tube that climbs to the roof: sockets in, bows out,
    then up; its end is inside the roof. Returns the tip record for its cluster."""
    d = ftp._dir_of(bearing)
    c = m.centroid(host[band] + host[band + 1])
    d = _aim(place, roof, (c[0], c[1]), d, out, 0.0)
    bearing = -math.degrees(math.atan2(d[1], d[0]))
    quads, root, plane_n = ftp._patch(m, host, band, patch[0], patch[1], bearing)
    tip = _to_roof(place, roof, root, d, out)
    collar = add(root, plane_n, ftp.STUB * radii[0])
    reach = sub(tip, collar)
    ctrl = (collar[0] + reach[0] * 0.6, collar[1] + reach[1] * 0.6, collar[2] + reach[2] * UP_CTRL)
    mid = bez(collar, ctrl, tip, segs)[1:]
    _climb(m, rng, spec, quads, root, plane_n, bearing, mid, tip, radii, sides)
    return (tip[0], tip[1], d, kind)


def _primary(m, rng, spec, trunk, band, bearing, place, roof):
    """One heavy bough: out at ~40 deg to its fork, on (bending) into the roof; a
    side limb off the fork and maybe a thinner one higher, both into the roof."""
    letter = spec["letter"]
    rings = trunk["rings"]
    d = ftp._dir_of(bearing)
    c = m.centroid(rings[band] + rings[band + 1])
    out = rng.u(*BOUGH_OUT)
    d = _aim(place, roof, (c[0], c[1]), d, out, CLUSTER["on"][0][1] + WELL_CLEAR)
    bearing = -math.degrees(math.atan2(d[1], d[0]))
    quads, root, plane_n = ftp._patch(m, rings, band, 1, BOUGH_PATCH[letter], bearing)
    r_host = 0.5 * (trunk["radii"][band] + trunk["radii"][band + 1])
    r0 = r_host * BOUGH_R
    rf = r0 * BOUGH_TAPER
    fx, fy = _fit_tip(place, (root[0] + d[0] * out, root[1] + d[1] * out))
    fz = root[2] + rng.u(*FORK_SHARE) * (place.lid(roof, fx, fy) - root[2])
    fork = (fx, fy, fz)
    collar = add(root, plane_n, ftp.STUB * r0)
    reach = sub(fork, collar)
    ctrl = (collar[0] + reach[0] * BOUGH_CTRL[0], collar[1] + reach[1] * BOUGH_CTRL[0],
            collar[2] + reach[2] * BOUGH_CTRL[1])
    mid = bez(collar, ctrl, fork, BOUGH_SEGS[0])[1:]
    side = 1.0 if rng.f() < 0.5 else -1.0
    d2 = _rot(d, side * rng.u(*ON_BEND))
    tip = _to_roof(place, roof, fork, d2, rng.u(*ON_OUT))
    ctrl2 = (fx + (tip[0] - fx) * 0.6, fy + (tip[1] - fy) * 0.6, fz + (tip[2] - fz) * UP_CTRL)
    mid += bez(fork, ctrl2, tip, BOUGH_SEGS[1])[1:]
    radii = (r0, r0, r0 * 0.93, r0 * 0.86, rf, rf * 0.85, rf * 0.68, rf * ON_TAPER)
    bough, _collar = _climb(m, rng, spec, quads, root, plane_n, bearing, mid, tip, radii, BOUGH_SIDES)
    tips = [(tip[0], tip[1], d2, "on")]
    rs = rf * SIDE_R[0]
    tips.append(_limb(m, rng, spec, bough, SIDE_BAND, (1, 2), bearing - side * rng.u(*SIDE_ANGLE),
                      rng.u(*SIDE_OUT), (rs, rs * SIDE_R[1]), SIDE_SIDES, SIDE_SEGS, place, roof, "side"))
    if trunk["twigs"]:
        trunk["twigs"] -= 1
        b2 = -math.degrees(math.atan2(d2[1], d2[0]))
        rt = rf * TWIG_R[0]
        tips.append(_limb(m, rng, spec, bough, TWIG_BAND, (1, 2), b2 + side * rng.u(*TWIG_ANGLE),
                          rng.u(*TWIG_OUT), (rt, rt * TWIG_R[1]), TWIG_SIDES, TWIG_SEGS, place, roof, "twig"))
    return tips


# ---- the clusters ------------------------------------------------------------

def _clip(place, lx, ly, band):
    """Local plan -> local plan with its world radius inside ``band``."""
    wx, wy = place.xy(lx, ly)
    rad = math.hypot(wx, wy)
    if band[0] <= rad <= band[1]:
        return lx, ly
    want = max(band[0], min(band[1], rad))
    return place.local_xy(wx * want / rad, wy * want / rad)


def _lift(rad):
    """A fringe cluster's share of its depth at world radius ``rad``: LIFT, piecewise."""
    if rad <= LIFT[0][0]:
        return LIFT[0][1]
    for (r0, f0), (r1, f1) in zip(LIFT, LIFT[1:]):
        if rad <= r1:
            return f0 + (f1 - f0) * (rad - r0) / (r1 - r0)
    return LIFT[-1][1]


def _lip_taper(rad):
    """A fringe vertex's share of its hang at world radius ``rad``: nothing at the lip, full LIP_FADE out."""
    u = max(0.0, min(1.0, (rad - DECK_R[0]) / LIP_FADE))
    return u * u * (3.0 - 2.0 * u)


def _fringe_rim(place, roof, lx, ly, near):
    """A fringe rim vertex at local plan (lx, ly): (local z, lx, ly) buried LID_BURY
    into the roof (its highest point over ``near``) along its normal (up on the flat, out and up on the cove)."""
    wx, wy = place.xy(lx, ly)
    wr = math.hypot(wx, wy)
    th = math.radians(fc.cove_theta(wr))
    z = max(place.lid(roof, x, y) for (x, y) in near) + LID_BURY * math.sin(th) / place.k
    out = LID_BURY * math.cos(th) / wr
    vx, vy = place.local_xy(wx + out * wx, wy + out * wy)
    return z, vx, vy


def _lobe_rng(place, cx, cy, R_w, depth_w):
    """A cluster's own rng for its lobing, seeded off its world place and size:
    the placement rng draws exactly what it drew, so nothing moves."""
    wx, wy = place.xy(cx, cy)
    return _Rng(SEED + int(abs(wx * 1013.0 + wy * 7919.0) * 100.0) + int((R_w + 3.0 * depth_w) * 1e4))


def _cluster(m, rng, place, roof, centre, kind, fringe=None):
    """One leaf cluster hung from the roof: rim ON the roof, long axis along the
    lane, bulging mid rings, a keel; centred in and clipped to the deck. 1 shell.
    A ``fringe`` one (its FRINGE sizes) is clipped to FRINGE_BAND, thins by LIFT
    and hangs along the roof's normal: down over the lane, in and down on the cove."""
    (r_lo, r_hi), (d_lo, d_hi), mids = CLUSTER[kind] if fringe is None else (fringe + (1,))
    k = place.k
    R_w, depth_w = rng.u(r_lo, r_hi), rng.u(d_lo, d_hi)
    hang = DOWN
    if fringe is None:
        edge = (CROWN_IN, DECK_R[1] - DECK_EDGE)
        reach = R_w * (1.0 + LOBE_WOB)
        if edge[1] - edge[0] < 2.0 * reach:
            R_w = 0.5 * (edge[1] - edge[0]) / (1.0 + LOBE_WOB)
            reach = R_w * (1.0 + LOBE_WOB)
        cx, cy = _clip(place, centre[0], centre[1], (edge[0] + reach, edge[1] - reach))
    else:
        cx, cy = centre
        edge = FRINGE_BAND
        wx, wy = place.xy(cx, cy)
        wr = math.hypot(wx, wy)
        depth_w *= _lift(wr)
        th = math.radians(fc.cove_theta(wr))
        if th < 0.5 * math.pi - 1e-9:
            hx, hy = place.local_dir(-math.cos(th) * wx / wr, -math.cos(th) * wy / wr)
            hang = (hx, hy, -math.sin(th))
    R, depth = R_w / k, depth_w / k
    a0 = place.tangent_a
    st = rng.u(*LOBE_STRETCH)
    ca, sa = math.cos(a0), math.sin(a0)
    skew = (rng.sf() * LOBE_SKEW * R, rng.sf() * LOBE_SKEW * R)
    n = LOBE_N
    lob = _lobe_rng(place, cx, cy, R_w, depth_w)   # the lobing's own draws: the placement's rng is untouched
    ph = lob.f() * 2.0 * math.pi
    rim, rim_z, offs, taper, angs = [], [], [], [], []
    plan = []
    for s in range(n):
        a = 2.0 * math.pi * (s + 0.5 * rng.f()) / n
        f = 1.0 + LOBE_WOB * rng.sf()
        ex, ey = math.cos(a) * st, math.sin(a)
        dx, dy = R * f * (ca * ex - sa * ey), R * f * (sa * ex + ca * ey)
        plan.append(_clip(place, cx + dx, cy + dy, edge))
        angs.append(a)
    for s in range(n):
        lx, ly = plan[s]
        # the rim sits over the roof's HIGHEST point under its chords and its cap, not just under
        # its own vertex: a lumped or dipping roof never cuts the cap into a sun-lit sliver below the sheet
        (px, py), (qx, qy) = plan[s - 1], plan[(s + 1) % n]
        near = ((lx, ly), (0.5 * (lx + px), 0.5 * (ly + py)), (0.5 * (lx + qx), 0.5 * (ly + qy)), (cx, cy))
        if fringe is None:
            z = max(place.lid(roof, x, y) for (x, y) in near) + LID_BURY / k
            rim.append(m.v((lx, ly, z)))
            taper.append(1.0)
        else:
            z, vx, vy = _fringe_rim(place, roof, lx, ly, near)
            rim.append(m.v((vx, vy, z)))
            taper.append(_lip_taper(math.hypot(*place.xy(lx, ly))))   # the lip side of the hang sinks into the roof
        rim_z.append(z)
        offs.append((lx - cx, ly - cy))
    if fringe is not None and wr > DECK_R[1]:       # on the cove: the keel stays over the cells' apex row
        floor = (WALL_FLOOR - LANE_Y) / k
        depth = max(0.15 / k, min(depth, (min(rim_z) - floor) / -hang[2]))
    dk = depth * (_lip_taper(math.hypot(*place.xy(cx + skew[0], cy + skew[1]))) if fringe is not None else 1.0)
    rings = [rim]
    for j in range(mids):
        u = (j + 1) / float(mids + 1)
        share = 1.0 - (1.0 - LOBE_MID[0]) * u / LOBE_MID[1]
        ring = []
        for s in range(n):
            dd = depth * u * (1.0 + 0.12 * rng.sf() + LOBE_SAG * lob.sf())
            bulge = 1.0 + LOBE_BULGE[0] * math.sin(2.0 * angs[s] + ph) + LOBE_BULGE[1] * lob.sf()
            z = rim_z[s] + hang[2] * dd
            lx, ly = _clip(place, cx + skew[0] * u * 2.0 + offs[s][0] * share * bulge * (1.0 + 0.08 * rng.sf()) + hang[0] * dd,
                           cy + skew[1] * u * 2.0 + offs[s][1] * share * bulge + hang[1] * dd, edge)
            if taper[s] < 1.0:                      # toward the lip: up into the roof over its own plan
                zl = place.lid(roof, lx, ly) + LID_BURY / k
                z = zl + (z - zl) * taper[s]
            ring.append(m.v((lx, ly, z)))
        rings.append(ring)
    kn = LOBE_KEEL[1]
    kx, ky = cx + skew[0] + hang[0] * dk, cy + skew[1] + hang[1] * dk
    keel = []
    zk = min(m.verts[v][2] for v in rings[-1])    # under the LOWEST mid vertex: on a sloping roof no keel face tips up into the sun
    rest = depth * (1.0 - mids / float(mids + 1))
    for s in range(kn):
        a = 2.0 * math.pi * (s + 0.3 * rng.f()) / kn + a0
        f = LOBE_KEEL[0] * R * (1.0 + 0.15 * rng.sf())
        lx, ly = _clip(place, kx + f * math.cos(a) * st, ky + f * math.sin(a), edge)
        z = zk + hang[2] * rest * (1.0 + 0.1 * rng.sf() - KEEL_LIFT * lob.f())
        tk = _lip_taper(math.hypot(*place.xy(lx, ly))) if fringe is not None else 1.0   # each keel vertex by its own radius
        if tk < 1.0:
            zl = place.lid(roof, lx, ly) + LID_BURY / k
            z = zl + (z - zl) * tk
        keel.append(m.v((lx, ly, z)))
    above = SOFT_ABOVE * R
    inner = (cx + skew[0] * 0.6 - hang[0] * above, cy + skew[1] * 0.6 - hang[1] * above,
             max(rim_z) - hang[2] * above)     # up inside the roof: every face points away from here, out and DOWN
    if hasattr(m, "clusters"):                  # its normals lean out from here (_soften)
        m.clusters.append((inner, [v for ring in rings for v in ring] + keel))
    for j in range(len(rings) - 1):
        a_, b_ = rings[j], rings[j + 1]
        for s in range(n):
            q = (s + 1) % n
            idx = (a_[s], a_[q], b_[q], b_[s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), inner), "leaf")
    _zip(m, rings[-1], keel, inner, "leaf", None if hang is DOWN else hang)
    m.fan(keel, hang, "leaf")
    m.fan(rim, UP, "leaf")
    return 1


def _zip(m, outer, inner_ring, inner_pt, zone, axis=None):
    """Triangles between two loops matched by angle (in plan, or about ``axis``),
    every one facing away from ``inner_pt``."""
    c = m.centroid(inner_ring)
    if axis is not None:
        e1 = (axis[1], -axis[0], 0.0)                 # across the hang, level
        L = math.hypot(e1[0], e1[1]) or 1.0
        e1 = (e1[0] / L, e1[1] / L, 0.0)
        e2 = (axis[1] * e1[2] - axis[2] * e1[1], axis[2] * e1[0] - axis[0] * e1[2], axis[0] * e1[1] - axis[1] * e1[0])

    def ang(vid):
        p = m.verts[vid]
        if axis is None:
            return math.atan2(p[1] - c[1], p[0] - c[0])
        d = sub(p, c)
        return math.atan2(d[0] * e2[0] + d[1] * e2[1] + d[2] * e2[2], d[0] * e1[0] + d[1] * e1[1] + d[2] * e1[2])

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


# ---- the tree ----------------------------------------------------------------

def build_tree(m, rng, spec, place, roof):
    """One tree in its local frame: flared trunk into the roof, the primaries with
    their forks and limbs, a cluster on every end, the head and a loose one."""
    first_v = len(m.verts)
    letter = spec["letter"]
    trunk = ftp.build_trunk(m, rng, _trunk_spec(spec, place, roof, rng))
    _flare(m, rng, spec, trunk)
    m.fan(trunk["top_ring"], UP, "bark")            # closed up inside the roof
    trunk["twigs"] = TWIGS[letter]
    n_trunk = len(trunk["rings"]) * len(trunk["rings"][0]) + 1
    shells = 1
    base = rng.f() * 360.0
    count = BOUGHS[letter]
    tips = []
    for i in range(count):
        bearing = base + 360.0 * i / count + rng.sf() * BOUGH_JITTER
        tips += _primary(m, rng, spec, trunk, BOUGH_BANDS[letter][i], bearing, place, roof)
    head = trunk["top_centre"]
    shells += _cluster(m, rng, place, roof, (head[0], head[1]), "head")
    for (tx, ty, d, kind) in tips:
        R = 0.5 * sum(CLUSTER[kind][0]) / place.k
        shells += _cluster(m, rng, place, roof, (tx + d[0] * LOBE_PUSH * R, ty + d[1] * LOBE_PUSH * R), kind)
    for _ in range(LOOSE):
        a = rng.f() * 2.0 * math.pi
        r = rng.u(*LOOSE_AT)
        lx, ly = _fit_tip(place, (head[0] + r * math.cos(a), head[1] + r * math.sin(a)))
        wx, wy = place.xy(lx, ly)
        if roof.well_clear(wx, wy, CLUSTER["loose"][0][1]):
            shells += _cluster(m, rng, place, roof, (lx, ly), "loose")
    crown = m.verts[first_v + n_trunk:]
    lowest = min(p[2] for p in crown)
    assert lowest >= CROWN_MIN_Z - 1e-9, "crown reaches z=%.2f under CROWN_MIN_Z" % lowest
    return shells


def _soften(ob, clusters):
    """Smooth shading over the whole chunk (a bough is a rounded limb); every leaf
    cluster's vertex normals lean SOFT_OUT from its centre, so it shades as one soft volume."""
    from mathutils import Vector
    me = ob.data
    me.shade_smooth()
    me.update()
    normals = [Vector(v.normal) for v in me.vertices]
    for (centre, ids) in clusters:
        c = Vector(centre)
        for vid in ids:
            d = me.vertices[vid].co - c
            if d.length < 1e-6:
                continue
            n = normals[vid].lerp(d.normalized(), SOFT_OUT)
            if n.length > 1e-6:
                normals[vid] = n.normalized()
    me.normals_split_custom_set_from_vertices(normals)
    print("MDL STATS soft clusters=%d smooth_polys=%d" % (len(clusters), sum(1 for p in me.polygons if p.use_smooth)))


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
    for (centre, ids) in getattr(src, "clusters", ()):
        dst.clusters.append((place(centre), [i + base for i in ids]))


def tree_rows():
    return [r for r in forest_trees.LAYOUT if r[1] in TREES]


def build_fringe(m, roof):
    """The FRINGE rows round the lane: a cluster every ragged step, each in its
    own frame at its own radius, none under a sun well. Returns (shells, clusters
    whose rims were clipped to the lip)."""
    shells = clipped = 0
    for (name, row, (r0, dr), size, step, empty) in FRINGE:
        rng = _Rng(FRINGE_SEED + 104729 * row)
        margin = size[0][1] * (1.0 + LOBE_WOB)     # its short radius: the wells stay open, the light comes through
        deg = 360.0 / (2.0 * math.pi * r0)         # degrees per metre along the row
        b = rng.f() * step[0] * deg
        while b < 360.0:
            bearing, radius = b, r0 + rng.sf() * dr
            b += rng.u(*step) * deg
            if rng.f() < empty:
                continue
            place = _Place(bearing, radius, 0.0, 1.0)
            if not roof.well_clear(place.foot[0], place.foot[1], margin):
                continue
            local = _Mesh()
            local.clusters = []
            shells += _cluster(local, rng, place, roof, (0.0, 0.0), name, fringe=size)
            local.compact()
            if min(math.hypot(*place(p)[:2]) for p in local.verts) <= FRINGE_BAND[0] + 1e-6:
                clipped += 1
            _append(m, local, place)
    return shells, clipped


def build_geometry():
    """(canopy mesh, collider mesh, stats)."""
    roof = _Roof()
    m, c = _Mesh(), _Mesh()
    m.clusters = []             # (centre, vertex ids) per leaf cluster, for _soften
    stats = {"trees": 0, "shells": 0, "per_kind": {}, "roof_top": roof.top}
    stats["fringe"], stats["lip_clipped"] = build_fringe(m, roof)
    stats["shells"] += stats["fringe"]
    for idx, (section, kind, bearing, radius, aim, spin, scale) in enumerate(tree_rows()):
        assert aim == "radial", aim
        spec = ftp.spec_of(LETTER[kind])
        place = _Place(bearing, radius, spin, scale[0])
        local = _Mesh()
        local.clusters = []
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
    ob = m.object(OBJECT_NAME)
    forest_tiles.dress(ob, m.zones, "atlas", flat=False)
    _soften(ob, m.clusters)
    coll = c.object(COLLIDER_NAME)
    coll.hide_render = True
    zs = [v[2] for v in m.verts]
    print("MDL STATS trees=%d shells=%d fringe=%d lip_clipped=%d %s visual_tris=%d collision_tris=%d top_y=%.2f roof_y=%.1f"
          % (stats["trees"], stats["shells"], stats["fringe"], stats["lip_clipped"], stats["per_kind"],
             len(ob.data.polygons), len(coll.data.polygons), max(zs), fc.GALLERY_Z))
    return [ob, coll]


# =============================================================================
# THE FRAME -- a prisoner's eye on the lane, looking ahead and up
# =============================================================================

LANE_UP_BEARING = 196.0     # the eye stands mid-lane here ...
LANE_UP_AHEAD = 11.0        # ... looking this many degrees on round the lane ...
LANE_UP_RISE = 8.0          # ... at a point this far over the grass
LANE_UP_LENS = 18.0
LANE_UP_RES = (1400, 1500)
PC_OUT = r"C:\Users\ddd\Desktop\panopticon-renders\forest-canopy4"


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
    tower = ft.build_render_copy()

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
    print("SIZE trees=%d shells=%d fringe=%d lip_clipped=%d %s top_y=%.2f roof_top=%.2f"
          % (stats["trees"], stats["shells"], stats["fringe"], stats["lip_clipped"], stats["per_kind"],
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
