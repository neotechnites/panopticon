"""
PANOPTICON -- forest_tree_prop: a small family of loose trees for map 3's lane,
placed by hand as cover on the path. Three variants out of ONE script:

    a  slim      0.90 m across the trunk, 7.96 m tall, straight, 850 tris
    b  fat       1.59 m across, 7.61 m tall, a heavy root flare, 776 tris
    c  leaning   1.15 m across, leans ~17 deg and forks at 4 m, 7.44 m tall, 776 tris

Each variant is its OWN glb and its OWN single contiguous mesh -- three meshes
in one glb is not a model, it is a bag. The three thin wrappers
``forest_tree_prop_{a,b,c}_build.py`` exist because the pipeline builds
``<name>_build.py``; they hold nothing but the variant letter.

    tools/modelling/model build forest_tree_prop_a
    python3 tools/modelling/forest_tree_prop_build.py --check          # all three
    python3 tools/modelling/forest_tree_prop_build.py --check --variant b

Cover contract (docs/maps/forest.md, lane y 23.0, guard eye y 28.7):
  * the trunk is the cover. A standing prisoner is 1.8 m tall and 0.6 m across,
    so a trunk 0.9 m or wider hides one from the tower. Proved at z = 1.8.
  * the crown must not roof the lane over. Nothing of the crown -- no leaf, no
    branch, no socket -- sits below CROWN_MIN_Z = 3.0 m, so the guard's shallow
    look down the lane passes under every canopy and only the narrow trunks
    break it. Proved as ``lowest_crown_z``.

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
sys.path.insert(0, HERE + os.sep + "lib")

import forest_tree_build as ft  # noqa: E402  the forest atlas, the mesh library
from forest_tree_build import (_Mesh, _Rng, UP, DOWN, add, sub, norm, dot, cross,  # noqa: E402
                               lerp, bez, tube, clump_end, socket_ring, loft, frames)

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


def _limb(on, band, bearing, out, up, r, clump, sides=5, patch=(1, 2)):
    """One branch. ``on`` is None (it grows from the trunk) or the index of an
    earlier limb in the list (it grows from that limb). ``band`` is the index of
    the quad band of the host it sockets into: band k is the ring of quads
    between host ring k and host ring k+1. ``patch`` is (bands, sides) of host
    quads the socket claims, centred on the side nearest ``bearing``.
    ``out``/``up`` are metres horizontally along ``bearing`` and vertically from
    the socket centre to the tip. ``clump`` is (radius, metres beyond the tip)."""
    return {"on": on, "band": band, "bearing": bearing, "out": out, "up": up,
            "r": r, "clump": clump, "sides": sides, "patch": patch}


VARIANTS = {

    # ---- a: the slim one. 0.90 m across at chest height -- exactly enough to
    # hide a standing runner, and nothing to spare. Straight, a high airy crown.
    "a": {
        "letter": "a",
        "name": "forest_tree_prop_a",
        "object": "ForestTreePropA",
        "collider": "ForestTreePropACollision-colonly",
        "seed": 5510311,
        "sides": 10,
        "path": [(0.00, 0.00, -0.35), (0.00, 0.00, 0.00), (0.02, 0.01, 0.75),
                 (0.06, 0.02, 1.80), (0.12, 0.01, 3.00), (0.18, -0.03, 4.10),
                 (0.25, -0.06, 5.00), (0.31, -0.08, 5.90)],
        "radii": [0.70, 0.55, 0.49, 0.474, 0.41, 0.355, 0.30, 0.23],
        "wob": 0.055,
        "ang_jag": 0.05,
        "z_jag": 0.05,
        "clump_wob": 0.16,
        "limbs": [
            _limb(None, 4, 20.0, 0.85, 0.95, (0.19, 0.11), (1.05, 0.30)),
            _limb(None, 5, 145.0, 0.95, 0.85, (0.20, 0.12), (1.15, 0.32), patch=(1, 3)),
            _limb(None, 5, 265.0, 0.80, 1.00, (0.18, 0.11), (1.00, 0.30), patch=(1, 3)),
            _limb(None, 6, 70.0, 0.75, 1.05, (0.17, 0.10), (1.10, 0.30), patch=(1, 3)),
            _limb(None, 6, 200.0, 0.70, 1.10, (0.16, 0.10), (1.05, 0.30), patch=(1, 3)),
        ],
        "top_clump": (1.45, 0.95),
        "coll_sides": 8,
        "coll_inset": 0.96,
        "coll_top_band": 7,
    },

    # ---- b: the fat one. 1.60 m across: a runner can stand behind it sideways
    # on and be gone. Shorter, stouter, a heavy flare and a full low crown.
    "b": {
        "letter": "b",
        "name": "forest_tree_prop_b",
        "object": "ForestTreePropB",
        "collider": "ForestTreePropBCollision-colonly",
        "seed": 7720477,
        "sides": 12,
        "path": [(0.00, 0.00, -0.40), (0.00, 0.00, 0.00), (-0.02, 0.02, 0.70),
                 (-0.04, 0.03, 1.80), (-0.05, 0.02, 2.90), (-0.04, 0.00, 3.80),
                 (-0.02, -0.02, 4.60), (0.00, -0.03, 5.30)],
        "radii": [1.28, 0.97, 0.85, 0.828, 0.72, 0.62, 0.52, 0.40],
        "wob": 0.06,
        "ang_jag": 0.06,
        "z_jag": 0.06,
        "clump_wob": 0.16,
        "limbs": [
            _limb(None, 5, 35.0, 1.05, 0.85, (0.26, 0.15), (1.25, 0.34), patch=(1, 3)),
            _limb(None, 5, 195.0, 1.00, 0.90, (0.25, 0.15), (1.20, 0.34), patch=(1, 3)),
            _limb(None, 6, 110.0, 0.95, 0.95, (0.24, 0.14), (1.25, 0.32), patch=(1, 3)),
            _limb(None, 6, 290.0, 0.90, 1.00, (0.23, 0.14), (1.20, 0.32), patch=(1, 3)),
        ],
        "top_clump": (1.60, 1.00),
        "coll_sides": 8,
        "coll_inset": 0.96,
        "coll_top_band": 7,
    },

    # ---- c: the leaner. Leans ~17 deg off the vertical and forks at 4 m into
    # two limbs, each with its own crown: cover you can stand behind AND an
    # overhang that reads as a landmark from down the lane. The lean carries the
    # crown 4.6 m out over the lane, so hand-place this one with its lean across
    # the path, not along it.
    "c": {
        "letter": "c",
        "name": "forest_tree_prop_c",
        "object": "ForestTreePropC",
        "collider": "ForestTreePropCCollision-colonly",
        "seed": 9930613,
        "sides": 10,
        "path": [(-0.10, 0.02, -0.38), (-0.05, 0.01, 0.00), (0.12, -0.02, 0.80),
                 (0.42, -0.06, 1.80), (0.80, -0.10, 2.80), (1.12, -0.12, 3.60),
                 (1.42, -0.13, 4.40), (1.70, -0.13, 5.15)],
        "radii": [0.86, 0.68, 0.612, 0.605, 0.52, 0.45, 0.36, 0.26],
        "wob": 0.06,
        "ang_jag": 0.05,
        "z_jag": 0.05,
        "clump_wob": 0.16,
        "limbs": [
            # the fork: two thick limbs out of the last two bands, one carrying on
            # the lean, one throwing back against it
            _limb(None, 5, 8.0, 1.90, 2.00, (0.30, 0.18), (1.25, 0.45),
                  sides=6, patch=(1, 3)),
            _limb(None, 5, 188.0, 1.55, 1.75, (0.27, 0.16), (1.15, 0.42),
                  sides=6, patch=(1, 3)),
            # twigs off each fork limb
            _limb(0, 1, 95.0, 0.55, 0.60, (0.13, 0.08), (0.90, 0.26), sides=5, patch=(1, 2)),
            _limb(1, 1, 265.0, 0.50, 0.60, (0.12, 0.08), (0.85, 0.26), sides=5, patch=(1, 2)),
        ],
        "top_clump": (0.95, 0.70),
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

BEZ_SEGS = 6            # bezier segments after the collar
STUB = 0.90             # collar length out of the host, in root radii
FLAT_MAX = 1.70         # the collar is never more than 1.7x as tall as wide
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


def _clump(m, rng, spec, rings, tip, tangent, clump, zone="leaf"):
    """Close an open tube end with a leaf ball ``clump[1]`` metres beyond the
    tip along ``tangent``, radius ``clump[0]``."""
    centre = add(tip, tangent, clump[1])
    clump_end(m, _by_azimuth(m, rings[-1], centre), centre, clump[0], zone, rng,
              wob=spec["clump_wob"])


# ---- the part ---------------------------------------------------------------

def build_crown(m, rng, spec, trunk):
    """PART 2. Grow every limb in ``spec["limbs"]`` and the top clump into ``m``,
    branches in the "bark" zone and leaf clumps in the "leaf" zone.

    A limb sockets into its host: ``on`` None means the trunk (``trunk["rings"]``),
    an int means limb number ``on`` in the same list, whose rings this function
    returned earlier. It claims ``patch`` = (bands, sides) registered host quads
    starting at band ``band``, centred on the side whose outward direction is
    nearest ``bearing`` degrees, welds a ring there with ``socket_ring`` and
    runs a ``tube`` out of it along a slight upward bezier to the tip at
    (socket centre + out metres along ``bearing`` + up metres in z), radii read
    from ``r`` = (root, tip). ``clump_end`` closes it with a leaf ball of radius
    ``clump[0]`` centred ``clump[1]`` metres beyond the tip, wobble
    ``spec["clump_wob"]``. The trunk's open top ring is closed the same way with
    ``spec["top_clump"]`` = (radius, metres above the top ring).

    HARD RULE: no vertex this function creates, and no socket it claims, may sit
    below CROWN_MIN_Z (3.0 m). Assert it. The guard has to see the lane.

    Returns a dict:
        "limb_rings"  list, one entry per limb, of that limb's tube rings (lists
                      of vertex ids) so a later limb can socket into an earlier one
        "lowest_z"    the lowest z of anything this function made
        "crown_r"     the greatest horizontal distance from the trunk's foot
                      (path[0] x,y) of anything this function made
        "top_z"       the highest z
    """
    first_v = len(m.verts)
    limb_rings = []

    for i, limb in enumerate(spec["limbs"]):
        host = trunk["rings"] if limb["on"] is None else limb_rings[limb["on"]]
        assert limb["on"] is None or limb["on"] < i, "limb %d hosts on a later limb" % i
        bands, count = limb["patch"]
        quads, root, plane_n = _patch(m, host, limb["band"], bands, count,
                                      limb["bearing"])

        d = _dir_of(limb["bearing"])
        elbow = add(root, d, limb["out"])                    # out along the bearing
        tip = (elbow[0], elbow[1], elbow[2] + limb["up"])    # then up
        # leave square to the plane the ring is projected onto, the way _arch
        # leaves a pier: project_ring slides the ring along the tube's start
        # tangent, so a start that is not the plane's normal shears the ring
        # out over the patch boundary and socket() then bridges a fold. One
        # short stub square out, THEN the bend out along the bearing and up.
        collar = add(root, plane_n, STUB * limb["r"][0])
        path = [root, collar] + bez(collar, elbow, tip, BEZ_SEGS)[1:]

        sides = limb["sides"]
        flat = _collar(m, quads, limb["bearing"], root, limb["r"][0])
        ring0 = socket_ring(m, quads, path, limb["r"][0], sides, "bark", flat=flat,
                            at_start=True)
        rings = tube(m, path, tuple(limb["r"]), sides, "bark", caps=(False, False),
                     wob=spec["wob"], rng=rng, first_ring=ring0)
        _clump(m, rng, spec, rings, path[-1], frames(path)[-1][0], limb["clump"])
        limb_rings.append(rings)

    # the trunk's open top ring, closed by its own clump
    top_c = trunk["top_centre"]
    top = (top_c[0], top_c[1], top_c[2] + spec["top_clump"][1])
    clump_end(m, _by_azimuth(m, trunk["top_ring"], top), top, spec["top_clump"][0],
              "leaf", rng, wob=spec["clump_wob"])

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
            "top_z": max(p[2] for p in made)}


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
                ("height", 6.0 <= max(zs) <= 9.0, "6..9 m tall"),
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
