"""
PANOPTICON -- forest_tree_prop: a small family of loose trees for map 3's lane,
placed by hand as cover on the path, that rise into the lane roof and read as
the structure holding the canopy up. Three variants out of ONE script:

    a  slim      0.90 m across the trunk, straight, five limbs, 17.6 m to its top pad
    b  fat       1.59 m across, a heavy root flare, four thick limbs, 17.5 m
    c  leaning   1.15 m across, leans ~17 deg and forks at 5 m, eases upright, 17.6 m

Ryan: "what would it look like if the tree elements, instead of being complete
trees, went much higher into the roof where it looked like they help to create
the canopy? I don't just want it to look like a tree trunk going into a green
bush at the top, I want it to look like it expands to create the roof above the
running prisoners."

So: the trunk keeps its cover footprint at the deck, then rises clean to ~11 m;
from 6 m up its limbs fork off it, rise, and sweep out to horizontal as they
reach the roof (RISE limbs: a bezier that ends level, then a short hook up);
twigs fork sideways off the limbs' bends; the trunk's own top carries on as a
leader. Every tip ends in a PAD -- a wide flat leaf lens, 2..3 m across and
0.7 m thick, its underside a flat fan off the limb -- not a ball. The roof
(forest_ceiling_build) is 15 m over the grass and forest_trees.py scales a tree
0.85..1.25, so the lattice is deep: knees from 11.6 m to 16 m, pads from 12.5 m
to 17.6 m. At every scale the roof cuts through the lattice somewhere between
the forks and the top pad, and the leaf overhead belongs to the limbs below it.

Each variant is its OWN glb and its OWN single contiguous mesh -- three meshes
in one glb is not a model, it is a bag. The three thin wrappers
``forest_tree_prop_{a,b,c}_build.py`` exist because the pipeline builds
``<name>_build.py``; they hold nothing but the variant letter.

    tools/modelling/model build forest_tree_prop_a
    python3 tools/modelling/maps/forest/forest_tree_prop_build.py --check          # all three
    python3 tools/modelling/maps/forest/forest_tree_prop_build.py --check --variant b

Cover contract (docs/maps/forest.md, lane y 23.0, guard eye y 28.7):
  * the trunk is the cover. A standing prisoner is 1.8 m tall and 0.6 m across,
    so a trunk 0.9 m or wider hides one from the tower. Proved at z = 1.8. The
    collider is the trunk's first seven rings, unchanged by the canopy.
  * nothing of the crown -- no leaf, no branch, no socket -- sits below
    CROWN_MIN_Z = 3.0 m, so the guard's shallow look down the lane passes under
    every limb and only the narrow trunks break it. Proved as ``lowest_crown_z``.

Material, palette and atlas are the forest's own: this file imports
``forest_tree_build`` (which is where forest_build.py's atlas lives) and uses
its "bark" and "leaf" zones unchanged. No new colours.

Authored in Blender space (+Z up = Godot +Y), origin at the foot of the trunk
on the ground plane (z = 0), so the prop drops onto the lane at identity.
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
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import forest_tree_build as ft  # noqa: E402  the forest atlas, the mesh library
from forest_tree_build import (_Mesh, _Rng, UP, DOWN, add, sub, norm, dot, cross,  # noqa: E402
                               lerp, bez, tube, clump_end, socket_ring, loft, frames, _at)

if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["world_grey"] = 0.30
    mdl.DEFAULTS["world_strength"] = 0.85
else:
    mdl = None        # --check on the Mac: PART 4 is the only thing that wants it

# =============================================================================
# TUNABLES -- the family. One dict per variant; the parts below read nothing else.
# =============================================================================

CROWN_MIN_Z = 3.0           # nothing of the crown below this: the guard's sightline
EYE_H = 1.65                # the scale proxy's eye, for the eye-level render
PROXY_H = 1.80              # the human proxy beside the tree: 1.8 m, 0.6 m across
GROUND_COLOR = [0.36, 0.40, 0.21, 1.0]     # the lane's grass, for the render backdrop

MAX_TRIS = 2000             # the contract's ceiling per variant


def _limb(on, band, bearing, out, up, r, pad, sides=5, patch=(1, 2), segs=5):
    """One canopy limb. ``on`` is None (it grows from the trunk) or the index
    of an earlier limb in the list (it grows from that limb). ``band`` is the
    index of the quad band of the host it sockets into: band k is the ring of
    quads between host ring k and host ring k+1. ``patch`` is (bands, sides)
    of host quads the socket claims, centred on the side nearest ``bearing``.
    The limb RISES: it leaves the host square, climbs ``up`` metres and sweeps
    out ``out`` metres along ``bearing`` to a level knee, then hooks up into
    its ``pad`` = (radius, squash, metres above the tip): the flat leaf lens
    that closes it. ``r`` is (root, tip) radius; ``segs`` bezier segments."""
    return {"on": on, "band": band, "bearing": bearing, "out": out, "up": up,
            "r": r, "pad": pad, "sides": sides, "patch": patch, "segs": segs}


def _leader(bearing, out, up, r_tip, pad, rise=0.7, segs=5):
    """The trunk's own top carrying on: rises ``rise`` straight, then the same
    climb-and-sweep to a knee ``up`` higher and ``out`` along ``bearing``."""
    return {"bearing": bearing, "out": out, "up": up, "r_tip": r_tip, "pad": pad,
            "rise": rise, "segs": segs}


# Pads: (radius, squash, metres above the tip). A main limb's lens is 3 m
# across, a twig's 2.2 m, the leader's 3.2 m; all 0.3 squashed, so 0.7 m thick.
PAD_MAIN = (1.50, 0.30, 0.35)
PAD_TWIG = (1.10, 0.30, 0.28)
PAD_TOP = (1.60, 0.30, 0.35)

VARIANTS = {

    # ---- a: the slim one. 0.90 m across at chest height -- exactly enough to
    # hide a standing runner, and nothing to spare. Straight; the first seven
    # rings are the old trunk (and the collider), then it climbs to 11.2 m
    # tapering slowly. Four limbs off bands 7..10, staggered so their knees
    # land at 11.6, 12.4, 13.4 and 14.2 m; a twig off each bend; the leader
    # tops out at 17.6 m.
    "a": {
        "letter": "a",
        "name": "forest_tree_prop_a",
        "object": "ForestTreePropA",
        "collider": "ForestTreePropACollision-colonly",
        "seed": 5510311,
        "sides": 10,
        "path": [(0.00, 0.00, -0.35), (0.00, 0.00, 0.00), (0.02, 0.01, 0.75),
                 (0.06, 0.02, 1.80), (0.12, 0.01, 3.00), (0.18, -0.03, 4.10),
                 (0.25, -0.06, 5.00), (0.31, -0.08, 5.90), (0.36, -0.10, 7.30),
                 (0.40, -0.11, 8.70), (0.43, -0.11, 10.00), (0.45, -0.10, 11.20)],
        "radii": [0.70, 0.55, 0.49, 0.474, 0.41, 0.355, 0.30, 0.28, 0.26, 0.24, 0.22, 0.20],
        "wob": 0.055,
        "ang_jag": 0.05,
        "z_jag": 0.05,
        "clump_wob": 0.18,
        "limbs": [
            _limb(None, 7, 30.0, 2.60, 5.00, (0.16, 0.09), PAD_MAIN, sides=6, patch=(1, 4)),
            _limb(None, 8, 150.0, 2.40, 4.40, (0.16, 0.09), PAD_MAIN, sides=6, patch=(1, 4)),
            _limb(None, 9, 270.0, 2.60, 4.05, (0.16, 0.09), PAD_MAIN, sides=6, patch=(1, 4)),
            _limb(None, 10, 80.0, 2.20, 3.60, (0.15, 0.08), PAD_MAIN, sides=6, patch=(1, 4)),
            # twigs off the bends, forking sideways
            _limb(0, 3, 335.0, 1.70, 2.40, (0.08, 0.045), PAD_TWIG, segs=4),
            _limb(1, 3, 205.0, 1.60, 2.10, (0.08, 0.045), PAD_TWIG, segs=4),
            _limb(2, 3, 320.0, 1.60, 2.40, (0.08, 0.045), PAD_TWIG, segs=4),
            _limb(3, 3, 130.0, 1.40, 2.00, (0.08, 0.045), PAD_TWIG, segs=4),
            _limb(0, 5, 75.0, 1.50, 1.80, (0.08, 0.04), PAD_TWIG, segs=4),
        ],
        "leader": _leader(330.0, 1.60, 4.30, 0.10, PAD_TOP),
        "coll_sides": 8,
        "coll_inset": 0.96,
        "coll_top_band": 7,
    },

    # ---- b: the fat one. 1.60 m across: a runner can stand behind it sideways
    # on and be gone. The heavy flare, then a stout column to 11 m; four thick
    # limbs, knees at 11.5, 12.6, 13.6 and 14.4 m, a twig off each; the leader
    # to 17.5 m.
    "b": {
        "letter": "b",
        "name": "forest_tree_prop_b",
        "object": "ForestTreePropB",
        "collider": "ForestTreePropBCollision-colonly",
        "seed": 7720477,
        "sides": 12,
        "path": [(0.00, 0.00, -0.40), (0.00, 0.00, 0.00), (-0.02, 0.02, 0.70),
                 (-0.04, 0.03, 1.80), (-0.05, 0.02, 2.90), (-0.04, 0.00, 3.80),
                 (-0.02, -0.02, 4.60), (0.00, -0.03, 5.30), (0.03, -0.03, 6.80),
                 (0.06, -0.02, 8.30), (0.08, 0.00, 9.70), (0.09, 0.02, 11.00)],
        "radii": [1.28, 0.97, 0.85, 0.828, 0.72, 0.62, 0.52, 0.46, 0.41, 0.36, 0.31, 0.26],
        "wob": 0.06,
        "ang_jag": 0.06,
        "z_jag": 0.06,
        "clump_wob": 0.18,
        "limbs": [
            _limb(None, 7, 45.0, 2.80, 5.40, (0.22, 0.11), PAD_MAIN, sides=6, patch=(1, 4)),
            _limb(None, 8, 165.0, 2.60, 5.00, (0.22, 0.11), PAD_MAIN, sides=6, patch=(1, 4)),
            _limb(None, 9, 285.0, 2.80, 4.60, (0.21, 0.10), PAD_MAIN, sides=6, patch=(1, 4)),
            _limb(None, 10, 105.0, 2.40, 4.00, (0.20, 0.10), PAD_MAIN, sides=6, patch=(1, 4)),
            _limb(0, 4, 350.0, 1.80, 2.50, (0.09, 0.05), PAD_TWIG, segs=4),
            _limb(1, 3, 225.0, 1.70, 2.20, (0.09, 0.05), PAD_TWIG, segs=4),
            _limb(2, 3, 340.0, 1.70, 2.40, (0.09, 0.05), PAD_TWIG, segs=4),
            _limb(3, 3, 160.0, 1.50, 2.00, (0.09, 0.05), PAD_TWIG, segs=4),
        ],
        "leader": _leader(15.0, 1.70, 4.50, 0.12, PAD_TOP),
        "coll_sides": 8,
        "coll_inset": 0.96,
        "coll_top_band": 7,
    },

    # ---- c: the leaner. Leans ~17 deg off the vertical to 5 m, then eases
    # back toward upright by 11.3 m (a 12 m column at 17 deg would read as
    # falling). The fork stays: two thick limbs out of bands 6 and 7, one
    # carrying the lean, one throwing back against it, both rising to the roof;
    # two more off the upper trunk. Hand-place this one with its lean across
    # the path, not along it -- the fork hangs 3 m out that way.
    "c": {
        "letter": "c",
        "name": "forest_tree_prop_c",
        "object": "ForestTreePropC",
        "collider": "ForestTreePropCCollision-colonly",
        "seed": 9930613,
        "sides": 10,
        "path": [(-0.10, 0.02, -0.38), (-0.05, 0.01, 0.00), (0.12, -0.02, 0.80),
                 (0.42, -0.06, 1.80), (0.80, -0.10, 2.80), (1.12, -0.12, 3.60),
                 (1.42, -0.13, 4.40), (1.70, -0.13, 5.15), (1.98, -0.13, 6.60),
                 (2.20, -0.12, 8.20), (2.36, -0.11, 9.80), (2.45, -0.10, 11.30)],
        "radii": [0.86, 0.68, 0.612, 0.605, 0.52, 0.45, 0.36, 0.32, 0.29, 0.26, 0.23, 0.20],
        "wob": 0.06,
        "ang_jag": 0.05,
        "z_jag": 0.05,
        "clump_wob": 0.18,
        "limbs": [
            # the fork
            _limb(None, 6, 8.0, 3.00, 7.60, (0.20, 0.10), PAD_MAIN, sides=6, patch=(1, 4)),
            _limb(None, 7, 188.0, 2.60, 7.00, (0.19, 0.10), PAD_MAIN, sides=6, patch=(1, 4)),
            # the upper trunk's own
            _limb(None, 9, 100.0, 2.40, 4.20, (0.16, 0.09), PAD_MAIN, sides=6, patch=(1, 4)),
            _limb(None, 10, 280.0, 2.20, 3.40, (0.15, 0.08), PAD_MAIN, sides=6, patch=(1, 4)),
            _limb(0, 4, 60.0, 1.80, 2.40, (0.10, 0.05), PAD_TWIG, segs=4),
            _limb(0, 4, 319.0, 1.60, 2.20, (0.08, 0.045), PAD_TWIG, segs=4),
            _limb(1, 4, 240.0, 1.70, 2.20, (0.09, 0.05), PAD_TWIG, segs=4),
            _limb(2, 3, 150.0, 1.50, 2.10, (0.08, 0.045), PAD_TWIG, segs=4),
            _limb(3, 3, 330.0, 1.40, 2.00, (0.08, 0.045), PAD_TWIG, segs=4),
        ],
        "leader": _leader(20.0, 1.40, 4.20, 0.10, PAD_TOP),
        "coll_sides": 8,
        "coll_inset": 0.96,
        "coll_top_band": 7,
    },
}


FACING_YAW = 0.0            # authored facing +X; "front" looks down -X


# =============================================================================
# PART 1 -- THE TRUNK: the only part of the prop that is cover
# =============================================================================

# A ring may never eat more than this share of the gap to a neighbouring ring:
# rings that cross would fold the tube inside out and wreck the loft's winding.
_Z_JAG_SAFETY = 0.3


def build_trunk(m, rng, spec):
    """PART 1. Grow the trunk of ``spec`` into ``m``, every face zone "bark".
    See forest_tree_prop_build.build_trunk for the full contract."""
    n = spec["sides"]
    path_in = [tuple(float(c) for c in p) for p in spec["path"]]
    radii = [float(r) for r in spec["radii"]]

    # One angular offset per side, shared by every ring: the edges stay vertical.
    ang = [2.0 * math.pi * s / n + rng.sf() * spec["ang_jag"] for s in range(n)]

    # Ring heights: jitter each ring, clamped inside the gap to its neighbours.
    zs = [p[2] for p in path_in]
    for k in range(1, len(path_in)):
        below = zs[k] - zs[k - 1]
        above = path_in[k + 1][2] - zs[k] if k + 1 < len(path_in) else below
        room = _Z_JAG_SAFETY * min(below, above)
        dz = rng.sf() * spec["z_jag"]
        zs[k] += max(-room, min(room, dz))

    path = [(p[0], p[1], z) for p, z in zip(path_in, zs)]

    rings = []
    for k, (cx, cy, cz) in enumerate(path):
        ring = []
        for s in range(n):
            r = radii[k] * (1.0 + rng.sf() * spec["wob"])
            ring.append(m.v((cx + r * math.cos(ang[s]), cy + r * math.sin(ang[s]), cz)))
        rings.append(ring)

    def axis_xy(z):
        """The trunk's centreline at height ``z`` -- the leaners need it: outward
        is away from the LOCAL axis, not away from the foot."""
        if z <= path[0][2]:
            return path[0][0], path[0][1]
        for k in range(len(path) - 1):
            if path[k][2] <= z <= path[k + 1][2]:
                t = (z - path[k][2]) / (path[k + 1][2] - path[k][2])
                return (path[k][0] + t * (path[k + 1][0] - path[k][0]),
                        path[k][1] + t * (path[k + 1][1] - path[k][1]))
        return path[-1][0], path[-1][1]

    def want(c):
        ax, ay = axis_xy(c[2])
        return (c[0] - ax, c[1] - ay, 0.0)

    loft(m, rings, "bark", want_fn=want)

    # Cap the foot with a fan off a centre vertex: the volume is closed and the
    # cap sits below z=0, buried in the lane. The foot ring took no z jitter, so
    # the cap is planar and DOWN is its exact normal.
    foot = m.v(path[0])
    for s in range(n):
        m.tri(foot, rings[0][s], rings[0][(s + 1) % n], DOWN, "bark")

    flat = math.cos(math.pi / n)        # corner radius -> half-width across flats

    def width_at(z):
        """Metres across the flats at height ``z``, linear between rings. This is
        the cover number: what a prisoner can actually hide behind."""
        if z <= path[0][2]:
            return 2.0 * radii[0] * flat
        for k in range(len(path) - 1):
            if path[k][2] <= z <= path[k + 1][2]:
                t = (z - path[k][2]) / (path[k + 1][2] - path[k][2])
                return 2.0 * (radii[k] + t * (radii[k + 1] - radii[k])) * flat
        return 2.0 * radii[-1] * flat

    return {"rings": rings, "path": path, "radii": radii, "top_ring": rings[-1],
            "top_centre": path[-1], "top_r": radii[-1], "width_at": width_at}


# =============================================================================
# PART 2 -- THE CROWN: limbs welded into the trunk's own surface
# =============================================================================

STUB = 0.90             # collar length out of the host, in root radii
FLAT_MAX = 2.40         # the collar is never more than 2.4x as tall as wide
FLOOR_HEADROOM = 0.10   # metres the collar keeps clear of CROWN_MIN_Z


# ---- bearings and host quads ------------------------------------------------

def _dir_of(bearing_deg):
    """Game bearing -> unit Blender xy direction (forest_tree_build.radial)."""
    a = math.radians(-bearing_deg)
    return (math.cos(a), math.sin(a), 0.0)


def _band_quad(a, b, s):
    """The registered quad of the band between rings a and b at side s."""
    q = (s + 1) % len(a)
    return (a[s], a[q], b[q], b[s])


def _outward(m, a, b, s):
    """That quad's outward direction: its centroid away from the band's axis."""
    ids = _band_quad(a, b, s)
    return norm(sub(m.centroid(ids), lerp(m.centroid(a), m.centroid(b), 0.5)))


def _newell(pts):
    """Area normal of a polygon given in order (forest_tree_build's own, inline:
    socket_ring reads the plane off quads[0] in exactly this way)."""
    n = [0.0, 0.0, 0.0]
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return tuple(n)


def _face_normal(m, fi):
    """A stored triangle's normal, from its own winding."""
    a, b, c = (m.verts[j] for j in m.faces[fi])
    return cross(sub(b, a), sub(c, a))


def _orient(m, ids, outward):
    """Wind a registered host quad's stored triangles outward before the socket
    claims them. A no-op on a host wound outward throughout; it matters only for
    faces the socket is about to drop, and it buys two things -- ``claim`` can
    walk ONE boundary loop across the patch (a quad stored the other way round
    hands it the shared edge twice in the same direction, and the walk dead-ends),
    and ``socket``'s bridge triangles come out facing the way the bark does."""
    fis = m.quads[frozenset(ids)]
    if dot(_face_normal(m, fis[0]), outward) < 0.0:
        for fi in fis:
            m.faces[fi] = tuple(reversed(m.faces[fi]))


def _patch(m, rings, band, bands, count, bearing):
    """``bands`` x ``count`` registered host quads, the run of ``count``
    adjacent sides whose mean outward direction is nearest ``bearing`` (so the
    patch is centred on the side facing it, whatever the parity of ``count``).
    Returned with the quad that best stands for the patch first: socket_ring
    projects the welded ring onto THAT quad's plane."""
    assert band + bands <= len(rings) - 1, "band %d+%d past the host's %d rings" % (
        band, bands, len(rings))
    n = len(rings[band])
    want = _dir_of(bearing)
    best, best_score = None, -2.0
    for s0 in range(n):
        sides = [(s0 + d) % n for d in range(count)]
        acc, ok = (0.0, 0.0, 0.0), True
        for k in range(band, band + bands):
            for s in sides:
                if not m.has_quad(_band_quad(rings[k], rings[k + 1], s)):
                    ok = False
                    break
                acc = add(acc, _outward(m, rings[k], rings[k + 1], s))
            if not ok:
                break
        if not ok:
            continue
        score = dot(norm(acc), want)
        if score > best_score:
            best_score, best = score, sides
    assert best is not None, "no unclaimed %dx%d patch at band %d" % (bands, count, band)

    quads, outs = [], []
    for k in range(band, band + bands):
        for s in best:
            ids = _band_quad(rings[k], rings[k + 1], s)
            out = _outward(m, rings[k], rings[k + 1], s)
            _orient(m, ids, out)
            quads.append(ids)
            outs.append(out)
    mean = norm([sum(o[i] for o in outs) for i in range(3)])
    order = sorted(range(len(quads)), key=lambda i: (-dot(outs[i], mean), i))
    quads = [quads[i] for i in order]
    ids = sorted(set(i for q in quads for i in q))
    # the plane socket_ring will project the ring onto, outward: quads[0]'s own
    plane_n = norm(_newell([m.verts[i] for i in quads[0]]))
    if dot(plane_n, outs[order[0]]) < 0.0:
        plane_n = (-plane_n[0], -plane_n[1], -plane_n[2])
    return quads, m.centroid(ids), plane_n


def _collar(m, quads, bearing, centre, radius):
    """``flat`` for the socket ring: a round ring dropped into a 2:1 band leaves
    a spike at the far corner (``socket`` bridges loop to ring by angle, so a
    loop vertex out at the end of the long axis subtends almost nothing across
    the ring edge facing it -- a sliver). Proportion the ring to the patch
    instead, tall where the band is tall, which is what a real branch collar
    does anyway. Capped at FLAT_MAX, and capped again so the collar keeps
    FLOOR_HEADROOM above CROWN_MIN_Z -- PART 1 jitters its ring heights and the
    reference stub does not, so the 3.0 m floor is not spent on the collar."""
    ids = sorted(set(i for q in quads for i in q))
    d = _dir_of(bearing)
    across = cross((0.0, 0.0, 1.0), d)            # horizontal, along the band's sides
    zs = [m.verts[i][2] for i in ids]
    xs = [dot(m.verts[i], across) for i in ids]
    tall = (max(zs) - min(zs)) / max(1e-6, max(xs) - min(xs))
    room = (centre[2] - (CROWN_MIN_Z + FLOOR_HEADROOM)) / max(1e-6, radius)
    return max(1.0, min(FLAT_MAX, tall, room))


def _by_azimuth(m, ring, centre):
    """The ring's ids in rising xy azimuth about ``centre``: clump_end lays its
    own rings out by azimuth, so a tube's end ring must hand over in that order
    or the skirt quads come out twisted."""
    return sorted(ring, key=lambda v: math.atan2(m.verts[v][1] - centre[1],
                                                 m.verts[v][0] - centre[0]) % (2.0 * math.pi))


RISE_CTRL = 0.25            # the sweep's control point sits this far out along the run
HOOK = (0.22, 0.22, 0.33)   # out, up, then straight up: the tip turns vertical into its pad


def _rise(start, d, out, up, segs):
    """The climb-and-sweep after ``start``: a bezier that leaves it climbing and
    arrives level at the knee ``up`` higher and ``out`` along ``d``, then the
    hook, whose last leg is vertical so the tip ring lies flat under its pad."""
    ctrl = add(add(start, d, out * RISE_CTRL), UP, up)
    knee = add(ctrl, d, out * (1.0 - RISE_CTRL))
    pts = bez(start, ctrl, knee, segs)[1:]
    h1 = add(add(knee, d, HOOK[0]), UP, HOOK[1])
    return pts + [h1, add(h1, UP, HOOK[2])]


PAD_FLARE = (0.25, 0.05)    # the tip first flares to this share of the pad's radius, this high


def _pad(m, rng, spec, ring, tip, pad, zone="leaf"):
    """Close a vertical tube end with a flat leaf lens: ``pad`` = (radius,
    squash, metres above the tip). The tip flares to a collar ring first --
    straight from a 0.05 m tip edge to a 1 m lens ring is a sliver -- and the
    lens's first band off that collar is its flat underside."""
    centre = add(tip, UP, pad[2])
    tip_ring = _by_azimuth(m, ring, tip)
    fr = pad[0] * PAD_FLARE[0]
    flare = []
    for v in tip_ring:
        a = math.atan2(m.verts[v][1] - tip[1], m.verts[v][0] - tip[0])
        rr = fr * (1.0 + spec["clump_wob"] * rng.sf())
        flare.append(m.v((tip[0] + rr * math.cos(a), tip[1] + rr * math.sin(a),
                          tip[2] + PAD_FLARE[1])))
    loft(m, [tip_ring, flare], zone, want_fn=lambda c: (c[0] - tip[0], c[1] - tip[1], -0.5))
    clump_end(m, _by_azimuth(m, flare, centre), centre, pad[0], zone, rng,
              squash=pad[1], wob=spec["clump_wob"])
    return centre


def _leader_part(m, rng, spec, trunk):
    """The trunk's top ring carried on as a leader. Its rings keep the trunk
    ring's angular phase, so the band off the top ring is a clean loft."""
    lead = spec["leader"]
    top_c, top_ring, n = trunk["top_centre"], trunk["top_ring"], spec["sides"]
    d = _dir_of(lead["bearing"])
    start = add(top_c, UP, lead["rise"])
    path = [start] + _rise(start, d, lead["out"], lead["up"], lead["segs"])
    v0 = m.verts[top_ring[0]]
    # frames() puts ring angle 0 at world azimuth -90 deg for a vertical start
    phase = math.atan2(v0[1] - top_c[1], v0[0] - top_c[0]) + 0.5 * math.pi
    radii = (trunk["top_r"] * 0.95, lead["r_tip"])
    rings = [list(top_ring)]
    for i, ((t, ex, ez), p) in enumerate(zip(frames(path), path)):
        r = _at(radii, i / float(len(path) - 1))
        ring = []
        for s in range(n):
            a = 2.0 * math.pi * s / n + phase
            rr = r * (1.0 + spec["wob"] * rng.sf())
            ring.append(m.v(add(add(p, ex, rr * math.cos(a)), ez, rr * math.sin(a))))
        rings.append(ring)
    centres = [top_c] + path
    for k in range(len(rings) - 1):
        mid = lerp(centres[k], centres[k + 1], 0.5)
        loft(m, [rings[k], rings[k + 1]], "bark", want_fn=lambda c, mid=mid: sub(c, mid))
    return _pad(m, rng, spec, rings[-1], path[-1], lead["pad"])


# ---- the part ---------------------------------------------------------------

def build_crown(m, rng, spec, trunk):
    """PART 2. Grow every limb in ``spec["limbs"]`` and the leader into ``m``,
    limbs in the "bark" zone and their pads in the "leaf" zone.

    A limb sockets into its host: ``on`` None means the trunk (``trunk["rings"]``),
    an int means limb number ``on`` in the same list, whose rings this function
    returned earlier. It claims ``patch`` = (bands, sides) registered host quads
    starting at band ``band``, centred on the side whose outward direction is
    nearest ``bearing`` degrees, welds a ring there with ``socket_ring`` and
    runs a ``tube`` out of it: a short collar square to the patch, then
    ``_rise`` -- climbing ``up`` and sweeping ``out`` along the bearing to a
    level knee, hooking up -- and ``_pad`` closes it with a flat leaf lens.
    The trunk's open top ring carries on as ``spec["leader"]`` the same way.

    HARD RULE: no vertex this function creates, and no socket it claims, may sit
    below CROWN_MIN_Z (3.0 m). Assert it. The guard has to see the lane.

    Returns a dict:
        "limb_rings"  list, one entry per limb, of that limb's tube rings (lists
                      of vertex ids) so a later limb can socket into an earlier one
        "lowest_z"    the lowest z of anything this function made
        "crown_r"     the greatest horizontal distance from the trunk's foot
                      (path[0] x,y) of anything this function made
        "top_z"       the highest z
        "pad_z"       (lowest, highest) pad centre: where the leaf lattice lives
    """
    first_v = len(m.verts)
    limb_rings = []
    pads = []

    for i, limb in enumerate(spec["limbs"]):
        host = trunk["rings"] if limb["on"] is None else limb_rings[limb["on"]]
        assert limb["on"] is None or limb["on"] < i, "limb %d hosts on a later limb" % i
        bands, count = limb["patch"]
        quads, root, plane_n = _patch(m, host, limb["band"], bands, count,
                                      limb["bearing"])
        d = _dir_of(limb["bearing"])
        # leave square to the plane the ring is projected onto, the way _arch
        # leaves a pier: project_ring slides the ring along the tube's start
        # tangent, so a start that is not the plane's normal shears the ring
        # out over the patch boundary and socket() then bridges a fold. One
        # short stub square out, THEN the climb and the sweep.
        collar = add(root, plane_n, STUB * limb["r"][0])
        path = [root, collar] + _rise(collar, d, limb["out"], limb["up"], limb["segs"])

        sides = limb["sides"]
        flat = _collar(m, quads, limb["bearing"], root, limb["r"][0])
        ring0 = socket_ring(m, quads, path, limb["r"][0], sides, "bark", flat=flat,
                            at_start=True)
        rings = tube(m, path, tuple(limb["r"]), sides, "bark", caps=(False, False),
                     wob=spec["wob"], rng=rng, first_ring=ring0)
        pads.append(_pad(m, rng, spec, rings[-1], path[-1], limb["pad"]))
        limb_rings.append(rings)

    pads.append(_leader_part(m, rng, spec, trunk))

    made = m.verts[first_v:]
    assert made, "the crown made no geometry"
    foot = trunk["path"][0]
    lowest = min(p[2] for p in made)
    assert lowest >= CROWN_MIN_Z - 1e-9, (
        "crown reaches z=%.3f, below CROWN_MIN_Z=%.2f: the guard loses the lane"
        % (lowest, CROWN_MIN_Z))
    return {"limb_rings": limb_rings,
            "lowest_z": lowest,
            "crown_r": max(math.hypot(p[0] - foot[0], p[1] - foot[1]) for p in made),
            "top_z": max(p[2] for p in made),
            "pad_z": (min(p[2] for p in pads), max(p[2] for p in pads))}



# =============================================================================
# PART 3 -- THE COLLIDER: the trunk's silhouette, not a box
# =============================================================================

ZONE = "bark"       # the collider's faces are dropped on import; only the key matters


def build_collider(spec):
    """PART 3. The purpose-built collider: a new forest_tree_build._Mesh holding
    ONE closed ``spec["coll_sides"]``-gon prism that follows the trunk's own
    path from the foot ring to ring ``spec["coll_top_band"]`` - 1, at
    ``spec["coll_inset"]`` of the trunk's radius, capped top and bottom. It is
    the trunk's silhouette, not a box: a runner standing behind the trunk is
    behind the collider too, at every height a runner can occupy. No crown, no
    branches -- nothing above the trunk collides. Zone "bark" throughout (the
    collider's faces are dropped on import; the zone only has to be a valid key).
    Deterministic, no rng: the collider must not wobble off the visual.
    """
    m = _Mesh()
    n = spec["coll_sides"]
    inset = spec["coll_inset"]
    last = spec["coll_top_band"] - 1
    path = [tuple(p) for p in spec["path"][:last + 1]]
    radii = [r * inset for r in spec["radii"][:last + 1]]

    # Horizontal rings on the trunk's own centres, as the trunk builds them: the
    # lean lives in the centres, so the prism leans with it and stays vertical
    # where the trunk is vertical. One shared angular phase, so the side edges
    # run straight up the prism and no band twists.
    angles = [2.0 * math.pi * s / n for s in range(n)]
    rings = []
    for (cx, cy, cz), r in zip(path, radii):
        rings.append([m.v((cx + r * math.cos(a), cy + r * math.sin(a), cz))
                      for a in angles])

    # Loft band by band rather than in one call: "outward" has to be measured
    # from the band's own axis, not from the world origin, or a leaning trunk's
    # far side comes out inside-out.
    for k in range(len(rings) - 1):
        mx = 0.5 * (path[k][0] + path[k + 1][0])
        my = 0.5 * (path[k][1] + path[k + 1][1])
        loft(m, [rings[k], rings[k + 1]], ZONE,
             want_fn=lambda c, mx=mx, my=my: (c[0] - mx, c[1] - my, 0.0))

    # Caps by fan off a ring corner: a closed volume with no extra vertex, and
    # an n-gon's corner fan has no angle near a sliver at n = 8.
    m.fan(rings[0], DOWN, ZONE)
    m.fan(rings[-1], UP, ZONE)
    return m


# =============================================================================
# PART 4 -- THE SCALE RIG: render-only, never exported
# =============================================================================

PROXY_W = 0.60          # the prisoner's own box: 0.6 m across and 0.6 m deep
PROXY_GAP = 0.35        # daylight between the trunk's flare and the proxy's shoulder
PROXY_COLOR = (0.13, 0.62, 0.22, 1.0)   # reads as "not the model" at any exposure
SCALE_LENS = 35.0       # a standing eye's lens; a 50 pushes the camera so far
                        # back that standing at EYE_H stops meaning anything
SCALE_AZ = 0.0          # camera on -Y: see the module docstring, this is paired
                        # with the proxy's -X offset and neither moves alone
_EYE_PASSES = 4         # distance and elevation each depend on the other


def _trunk_at(spec, z):
    """The trunk's centre (x, y) and radius at height ``z``, straight off the
    variant's own path/radii so the proxy clears whatever the spec says the
    flare is. Linear between path points, which is how the trunk is lofted."""
    path, radii = spec["path"], spec["radii"]
    for k in range(len(path) - 1):
        if path[k][2] <= z <= path[k + 1][2]:
            t = (z - path[k][2]) / (path[k + 1][2] - path[k][2])
            return (path[k][0] + t * (path[k + 1][0] - path[k][0]),
                    path[k][1] + t * (path[k + 1][1] - path[k][1]),
                    radii[k] + t * (radii[k + 1] - radii[k]))
    end = -1 if z > path[-1][2] else 0
    return path[end][0], path[end][1], radii[end]


def post(spec_render, objects):
    """PART 4. Render-only extras, run after the glb is written and before the
    named views, so nothing here is exported. Sets the ground to the lane's
    grass, stands a 1.8 m x 0.6 m human proxy beside the trunk, and writes one
    extra eye-level frame ``<out_dir>/<NAME>_scale.png`` from a camera at
    ``EYE_H`` looking at the tree with the proxy beside it. Appends what it
    makes to ``objects`` so the named views show the proxy too.
    """
    import forest_tree_prop_build as ftp     # lazy: this module is one of its parts
    spec = ftp.spec_of(ftp.ACTIVE)

    # The proxy: beside the trunk, feet on the lane, clear of the flare.
    ax, ay, r0 = _trunk_at(spec, 0.0)
    px = ax - (r0 + PROXY_GAP + PROXY_W * 0.5)
    h = PROXY_W * 0.5
    verts = [(px + dx, ay + dy, z)
             for z in (0.0, ftp.PROXY_H)
             for (dx, dy) in ((-h, -h), (h, -h), (h, h), (-h, h))]
    proxy = mdl.mesh("ScaleProxy", verts,
                     [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                      (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)])
    proxy.data.materials.append(mdl.flat_material("ScaleProxy", PROXY_COLOR))
    objects.append(proxy)                    # the named views frame it too
    meshes = [o for o in objects if o.type == "MESH"]      # as render() filters

    # The scene rig, borrowed from mdl so the extra frame is lit and graded
    # exactly like the named ones, then torn down so render() builds its own.
    # mdl's own ground would sit on the buried flare, so it is switched off --
    # for the named views too, which is why this overrides the module's DEFAULT.
    spec_render["ground"] = False
    scene, cam, target, lights, lo, hi, centre, radius = mdl.setup_scene(spec_render, meshes)
    cam.data.type = "PERSP"
    cam.data.lens = SCALE_LENS

    # The lane, at the lane's height, and kept out of `objects`: it is 40 m of
    # backdrop and would blow the framing of every view that measured it.
    bpy.ops.mesh.primitive_plane_add(size=max(40.0, (hi - lo).length * 15.0),
                                     location=(centre.x, centre.y, 0.0))
    grass = bpy.context.active_object
    grass.name = "LaneGround"
    grass.data.materials.append(mdl.flat_material("LaneGrass", ftp.GROUND_COLOR,
                                                  roughness=0.95))

    # Solve the shot: the camera must both contain the tree and stand at EYE_H.
    # Elevation fixes the eye height, distance fixes the framing, and each needs
    # the other -- so iterate. The last elevation is solved from the distance
    # actually used, which is what makes the eye height exact rather than close.
    el = 0.0
    for _ in range(_EYE_PASSES):
        d = mdl._dir(SCALE_AZ, el)
        res = mdl._auto_resolution(lo, hi, d, int(spec_render.get("res_long_edge", 1200)))
        dist = mdl._fit_distance(lo, hi, d, SCALE_LENS, res[0], res[1],
                                 float(spec_render.get("margin", 1.12)))
        rise = (ftp.EYE_H - centre.z) / dist
        el = math.degrees(math.asin(max(-1.0, min(1.0, rise))))   # asin's domain

    d = mdl._dir(SCALE_AZ, el)
    cam.location = centre + d * dist
    target.location = centre
    mdl._place_lights(lights, centre, radius, SCALE_AZ, el)
    scene.render.resolution_x, scene.render.resolution_y = res
    bpy.context.view_layer.update()          # the TRACK_TO has not solved yet

    out_dir = spec_render.get("out_dir", ".")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "%s_scale.png" % spec["name"])
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("MDL RENDER %s  eye=%.2f el=%.1f dist=%.2f proxy_x=%.2f %dx%d"
          % (os.path.basename(path), cam.location.z, el, dist, px, res[0], res[1]))

    # render() calls setup_scene again and looks "CamTarget" up by name; two of
    # everything would light the named views twice and aim them at the wrong one.
    for ob in [cam, target] + [ob for _nm, ob in lights]:
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# ASSEMBLY -- the weld. One mesh, one material, one collider.
# =============================================================================

ACTIVE = "a"        # the wrappers set this before calling build()


def spec_of(letter):
    return VARIANTS[letter]


def build_geometry(spec):
    """The whole tree as one _Mesh: trunk, then crown welded into its sockets."""
    rng = _Rng(spec["seed"])
    m = _Mesh()
    trunk = build_trunk(m, rng, spec)
    crown = build_crown(m, rng, spec, trunk)
    return m, trunk, crown


def build():
    spec = spec_of(ACTIVE)
    m, trunk, crown = build_geometry(spec)
    c = build_collider(spec)

    albedo, emissive = ft.sheet("forest_atlas", ft.paint_atlas)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)

    ob = m.object(spec["object"])
    ft.unwrap(ob, m.zones)
    mdl.finish(ob, ft.atlas_material("ForestAtlas", albedo, emissive), strip_uvs=False)

    coll = c.object(spec["collider"])
    coll.hide_render = True

    zs = [v[2] for v in m.verts]
    print("MDL STATS visual_tris=%d collision_tris=%d height=%.2f width_1.8=%.2f "
          "lowest_crown_z=%.2f crown_r=%.2f"
          % (len(ob.data.polygons), len(coll.data.polygons), max(zs),
             trunk["width_at"](1.8), crown["lowest_z"], crown["crown_r"]))
    return [ob, coll]


# =============================================================================
# CHECK -- the proof, on the Mac, with no Blender
# =============================================================================

def _check(letters):
    import forest_check
    ok = True
    for letter in letters:
        spec = spec_of(letter)
        m, trunk, crown = build_geometry(spec)
        m.compact()
        c = build_collider(spec).compact()
        print("---- %s ----" % spec["name"])
        vis = forest_check.prove(m, spec["name"])
        col = forest_check.prove(c, spec["name"] + "_collider")
        zs = [v[2] for v in m.verts]
        xs = [v[0] for v in m.verts]
        ys = [v[1] for v in m.verts]
        w18 = trunk["width_at"](1.8)
        w10 = trunk["width_at"](1.0)
        print("SIZE %s height=%.2f trunk_width@1.0=%.2f @1.8=%.2f crown_low=%.2f "
              "crown_r=%.2f bbox_x=%.2f..%.2f bbox_y=%.2f..%.2f"
              % (spec["name"], max(zs), w10, w18, crown["lowest_z"], crown["crown_r"],
                 min(xs), max(xs), min(ys), max(ys)))
        for label, cond, why in (
                ("components", vis["components"] == 1, "one connected mesh"),
                ("duplicates", vis["duplicate_positions"] == 0, "no split seam"),
                ("nonmanifold", vis["nonmanifold_edges"] == 0, "manifold"),
                ("slivers", vis["slivers"] == 0, "no sliver triangles"),
                ("degenerate", vis["degenerate"] == 0, "no degenerate faces"),
                ("open_edges", vis["open_edges"] == 0, "closed volume"),
                ("tris", vis["tris"] <= MAX_TRIS, "<= %d tris" % MAX_TRIS),
                ("coll_components", col["components"] == 1, "one collider shell"),
                ("coll_open", col["open_edges"] == 0, "closed collider"),
                ("cover", w18 >= 0.88, "hides a 0.6 m runner at 1.8 m"),
                ("crown_min", crown["lowest_z"] >= CROWN_MIN_Z, "crown above 3.0 m"),
                ("height", 16.5 <= max(zs) <= 19.0, "16.5..19 m: into the roof at every scene scale"),
        ):
            if not cond:
                ok = False
                print("FAIL %s: %s" % (label, why))
    print("CHECK %s" % ("OK" if ok else "FAILED"))
    return 0 if ok else 1


def main_for(letter):
    """The wrappers' entry point."""
    global ACTIVE
    ACTIVE = letter
    spec = spec_of(letter)
    if bpy is None or "--check" in sys.argv:
        sys.exit(_check([letter]))
    mdl.main(spec["name"], build, facing_yaw=FACING_YAW, post=post)


if __name__ == "__main__":
    letters = sorted(VARIANTS)
    if "--variant" in sys.argv:
        letters = [sys.argv[sys.argv.index("--variant") + 1]]
    if bpy is None or "--check" in sys.argv:
        sys.exit(_check(letters))
    ACTIVE = letters[0]
    mdl.main(spec_of(ACTIVE)["name"], build, facing_yaw=FACING_YAW, post=post)
