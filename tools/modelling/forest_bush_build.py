"""
PANOPTICON -- forest_bush: cover for Map 3's lane. Two variants, one script.

    tools/modelling/model build forest_bush --variant low
    tools/modelling/model build forest_bush --variant tall
    python3 tools/modelling/forest_bush_build.py --check --variant low

    low ....... 1.3 m tall, 2.0 m across. A crouched runner (1.2 m) behind it
                is gone from the tower; a standing one (1.8 m) is not.
    tall ...... 2.2 m tall, 3.0 m across. Hides a standing runner.

A bush is a squat woody mound with leaf clumps grown out of it, never a ball.
The mound is a nine-sided lofted core; each clump is welded into a SOCKET on
one of the core's quads (`_Mesh.socket`, the weld the tree's own branches
use): the quad is deleted and its boundary sewn to the clump stub's first
ring, so the clump's vertices ARE the core's vertices. One connected
component, no duplicate vertex at any seam. The silhouette is lumpy because
the lobes are separate masses that overlap, not because a sphere was
jittered.

Every band of this model runs index-for-index between two rings in ONE frame
-- the socket's own plane -- and the stub's phase is solved so no ring vertex
lands on a socket corner's bearing. Those two rules are why `--check` reports
zero slivers: a sliver here was never bad luck, it was a frame mismatch or a
long thin stem, and both are gone by construction.

Origin at the base centre, z = 0 is the ground, Blender +Z = Godot +Y. One
material: the forest atlas from forest_tree_build (the same sheet the lane,
the tree and the leaf wall are painted with), zoned shade at the foot, leaf
through the body, sun on the crown, bark on the stems.

ForestBushCollision rides in the .glb as a `-colonly` node. It is not a box
and not a barrel of one radius: the drawn mesh is read into a grid of height
band x compass sector and every cell keeps its own widest vertex, pulled in by
COLL_INSET. A runner is stopped by the mass he can see, on the side he can see
it, and never by the leaf fringe he cannot.

An ad-hoc `--cam` view gets a 1.8 m human proxy standing beside the bush for
scale; the named views are the model alone.
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
if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["world_grey"] = 0.38
    mdl.DEFAULTS["world_strength"] = 1.0
    mdl.DEFAULTS["key_energy"] = 320.0
    mdl.DEFAULTS["ground_color"] = [0.30, 0.33, 0.20, 1.0]

import forest_tree_build as ft  # noqa: E402
from forest_tree_build import (_Mesh, _Rng, UP, DOWN, add, sub, cross, norm, dot,  # noqa: E402
                               lerp, plane_of)

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "forest_bush"
OBJECT_NAME = "ForestBush"
COLLIDER_NAME = "ForestBushCollision-colonly"
FACING_YAW = 0.0

CORE_SIDES = 9                    # nine, so no view down the prop is symmetric
STEM_SEGS = 4                     # four, to match the socket quad's four corners
CLUMP_LATS = (-48.0, 4.0, 48.0)   # the clump's latitude rings; the tip closes it
# The foot tucks in and every socket band above it narrows with height, so a
# socket's face always looks outward and UP and no clump is ever aimed into the
# soil. Band 0 carries no socket: it is the foot, and it is tucked so the
# leaves above overhang it instead of standing on a visible drum.
CORE_PROFILE = [(0.00, 0.78), (0.16, 1.00), (0.46, 0.95), (0.76, 0.84), (1.00, 0.44)]
SOCKET_BANDS = (1, 2, 3)
CORE_R = 0.54                     # of the bush's half-width
#  CORE_H is per variant: the tall bush is proportionally taller than the low
#  one, so its mound is too, and the crown lands on its own without stretching.
CORE_WOB = 0.10                   # per-vertex radial wobble on the core

SOCKET_R = 0.38                   # of the socket quad's shortest edge
STEM_LEN = 0.10                   # of the half-width: a stub, never a stick.
                                  # A long thin stem is a sliver factory -- its
                                  # band triangles are a tiny ring edge against
                                  # the whole length. Clumps sit ON the wood.
CLUMP_SQUASH = 0.74               # leaf clumps sit flatter than they are wide
CLUMP_WOB = 0.30

COLL_BANDS = 5
COLL_SIDES = 8
COLL_INSET = 0.86                 # leaves are soft; the mass a runner hits is not

# A lobe: (bearing deg, radius, height, clump radius, zone). The bearing,
# radius and height AIM the lobe -- they pick which of the core's quads it is
# welded into; the clump itself then grows square out of that quad's own face,
# because a clump grows where the wood is. Clump radius is a fraction of the
# half-width. Bearings are spread by hand, never evenly: an even ring of lobes
# reads as a cog from the tower.
LOBES_LOW = [
    (  8.0, 0.60, 0.33, 0.46, "leaf"),
    ( 74.0, 0.66, 0.28, 0.43, "leaf"),
    (142.0, 0.62, 0.35, 0.47, "leaf"),
    (203.0, 0.68, 0.26, 0.42, "leaf"),
    (268.0, 0.58, 0.36, 0.44, "leaf"),
    (318.0, 0.64, 0.30, 0.43, "sun"),
    ( 40.0, 0.30, 0.68, 0.42, "sun"),
    (170.0, 0.34, 0.64, 0.41, "sun"),
    (295.0, 0.28, 0.70, 0.40, "sun"),
]
LOBES_TALL = [
    ( 14.0, 0.63, 0.24, 0.41, "leaf"),
    ( 68.0, 0.68, 0.20, 0.39, "leaf"),
    (131.0, 0.65, 0.26, 0.42, "leaf"),
    (196.0, 0.70, 0.19, 0.39, "leaf"),
    (252.0, 0.62, 0.25, 0.41, "leaf"),
    (311.0, 0.67, 0.22, 0.40, "leaf"),
    ( 44.0, 0.55, 0.50, 0.41, "sun"),
    (108.0, 0.58, 0.46, 0.42, "leaf"),
    (172.0, 0.52, 0.53, 0.40, "sun"),
    (233.0, 0.57, 0.47, 0.41, "leaf"),
    (287.0, 0.54, 0.51, 0.41, "sun"),
    (338.0, 0.50, 0.44, 0.39, "leaf"),
    ( 22.0, 0.26, 0.76, 0.39, "sun"),
    (150.0, 0.30, 0.79, 0.38, "sun"),
    (262.0, 0.24, 0.74, 0.38, "sun"),
]

VARIANTS = {
    #        height  width  core_h  seed      lobes
    "low":  (1.30,  2.00,  0.62,   5310881,  LOBES_LOW),
    "tall": (2.20,  3.00,  0.70,   5310997,  LOBES_TALL),
}

PROXY_H = 1.80                    # the prisoner, for the scale shot only
PROXY_GAP = 0.55                  # clear of the leaf fringe


# =============================================================================
# VARIANT
# =============================================================================

def _variant():
    """`--variant low|tall`: the build spec on the PC, argv for --check here."""
    v = mdl.spec().get("variant") if bpy is not None else None
    if v is None:
        argv = sys.argv
        if "--variant" in argv and argv.index("--variant") + 1 < len(argv):
            v = argv[argv.index("--variant") + 1]
    if v not in VARIANTS:
        raise SystemExit("forest_bush: pass --variant %s (got %r). There is no "
                         "default: a bush that hides a crouched runner and one "
                         "that hides a standing one are different props."
                         % ("|".join(sorted(VARIANTS)), v))
    return v


class Params(object):
    def __init__(self, variant):
        h, w, core_h, seed, lobes = VARIANTS[variant]
        self.variant = variant
        self.height = h
        self.width = w
        self.radius = w * 0.5
        self.seed = seed
        self.lobes = lobes
        self.core_r = self.radius * CORE_R
        self.core_h = h * core_h


# =============================================================================
# GEOMETRY
# =============================================================================

def _bearing(deg):
    a = math.radians(-deg)
    return (math.cos(a), math.sin(a), 0.0)


def _core(m, p, rng):
    """The woody mound: a lofted nine-sided dome, closed top and bottom.

    Returns the side quads as (corner ids, centroid, outward normal, shortest
    edge) -- the sockets every leaf clump is welded into.
    """
    ang = [2.0 * math.pi * i / CORE_SIDES + 0.18 * rng.sf() for i in range(CORE_SIDES)]
    rings = []
    for k, (t, rf) in enumerate(CORE_PROFILE):
        ring = []
        for i in range(CORE_SIDES):
            wob = 1.0 + (CORE_WOB * rng.sf() if 0 < k < len(CORE_PROFILE) - 1 else 0.0)
            rr = p.core_r * rf * wob
            ring.append(m.v((rr * math.cos(ang[i]), rr * math.sin(ang[i]), p.core_h * t)))
        rings.append(ring)

    quads = []
    for k in range(len(CORE_PROFILE) - 1):
        lo, hi = rings[k], rings[k + 1]
        for i in range(CORE_SIDES):
            q = (i + 1) % CORE_SIDES
            ids = (lo[i], lo[q], hi[q], hi[i])
            want = sub(m.centroid(ids), (0.0, 0.0, m.centroid(ids)[2]))
            m.quad(ids[0], ids[1], ids[2], ids[3], want, "shade")
            pts = [m.verts[j] for j in ids]
            edge = min(math.dist(pts[j], pts[(j + 1) % 4]) for j in range(4))
            quads.append((ids, m.centroid(ids), norm(want), edge, k))
    m.fan(list(reversed(rings[0])), DOWN, "shade")
    m.fan(rings[-1], UP, "shade")
    return quads


def _socket_phase(corner_angles, segs):
    """The stem ring's phase, solved rather than assumed.

    `_Mesh.socket` sews the claimed quad's four corners to the stem's ring by
    bearing round the socket. A ring vertex that lands on a corner's own
    bearing makes a triangle with three collinear points -- which is what a
    sliver is, and one of the two ways this model used to grow them.
    Sample the phase and keep the one whose closest ring-to-corner gap is
    widest: 180 samples, deterministic, and it is paid once per lobe at build
    time.
    """
    two_pi = 2.0 * math.pi
    step = two_pi / segs
    best, best_gap = 0.0, -1.0
    for k in range(180):
        phi = step * k / 180.0
        gap = min(min(abs(((phi + step * s) - ca + math.pi) % two_pi - math.pi)
                      for ca in corner_angles) for s in range(segs))
        if gap > best_gap:
            best, best_gap = phi, gap
    return best


def _lobe(m, p, rng, quads, used, spec):
    """One leaf clump, welded into the core quad that faces it.

    Nothing here floats. The socket's quad is deleted and its boundary sewn to
    the stub's first ring, so the clump's vertices ARE the core's vertices; the
    stub is that same ring pushed straight out along the socket's normal, so it
    cannot twist; the clump is a lumpy ball grown off the stub's far ring.
    """
    bear, rf, zf, cf, zone = spec
    d = _bearing(bear)
    centre = (d[0] * p.radius * rf, d[1] * p.radius * rf, p.height * zf)
    clump_r = p.radius * cf * (1.0 + 0.06 * rng.sf())

    best, best_score = None, -9.0
    for qi, (ids, cen, nrm, edge, band) in enumerate(quads):
        if qi in used:
            continue
        if band not in SOCKET_BANDS:
            continue
        score = dot(norm(sub(centre, cen)), nrm)
        if score > best_score:
            best, best_score = qi, score
    if best is None:
        raise ValueError("forest_bush: more lobes than core quads")
    used.add(best)
    ids, cen, nrm, edge, band = quads[best]

    # One frame for the whole lobe: the socket's own plane. The stem's foot is
    # a circle in it, so the clump's columns are an exact 45 deg apart and two
    # of them can never collapse onto one bearing -- which is the only way a
    # ring-to-ring band of this shape can produce a sliver.
    c, n = plane_of(m, ids)
    ex = norm(cross(n, UP if abs(n[2]) < 0.9 else (1.0, 0.0, 0.0)))
    ey = cross(n, ex)
    ca = [math.atan2(dot(sub(m.verts[k], c), ey), dot(sub(m.verts[k], c), ex)) for k in ids]
    step = 2.0 * math.pi / STEM_SEGS
    phi = _socket_phase(ca, STEM_SEGS)
    stem_r = edge * SOCKET_R
    foot = [add(add(c, ex, stem_r * math.cos(phi + step * s)),
                ey, stem_r * math.sin(phi + step * s)) for s in range(STEM_SEGS)]
    ring0 = [m.v(q) for q in foot]
    m.socket([ids], ring0, "bark")

    # The clump is grown square out of the face, a stub's length off it: the
    # lobe table says which way a clump is wanted, the core's own wood says
    # where it starts.
    ang8 = [phi + 0.5 * step * k for k in range(2 * STEM_SEGS)]
    knee = add(c, n, STEM_LEN * p.radius)
    hub = add(knee, n, clump_r * 0.62)
    # The lowest clumps are meant to reach the grass, so they are aimed low and
    # then the whole lobe -- stub and clump together, rigid -- is lifted by
    # whatever it would otherwise have buried. Aiming them safely high instead
    # leaves the core standing out underneath like a plant pot.
    shape, tip = _clump_shape(hub, n, ex, ey, ang8, clump_r, rng)
    lift = max(0.0, -min(q[2] for ring in shape for q in ring), -tip[2])
    if lift > 0.0:
        knee = (knee[0], knee[1], knee[2] + lift)
        shape = [[(q[0], q[1], q[2] + lift) for q in ring] for ring in shape]
        tip = (tip[0], tip[1], tip[2] + lift)
    stem2 = stem_r * 0.86
    ring1 = [m.v(add(add(knee, ex, stem2 * math.cos(a)), ey, stem2 * math.sin(a)))
             for a in ang8]
    axis = lerp(c, knee, 0.5)
    for s in range(STEM_SEGS):                       # 4 -> 8, three tris a column
        a, b = ring0[s], ring0[(s + 1) % STEM_SEGS]
        pv, qv, rv = ring1[2 * s], ring1[2 * s + 1], ring1[(2 * s + 2) % len(ring1)]
        for tri in ((a, b, qv), (a, qv, pv), (b, rv, qv)):
            m.tri(tri[0], tri[1], tri[2], sub(m.centroid(tri), axis), "bark")
    _clump(m, ring1, ang8, shape, tip, hub, zone)


def _clump_shape(centre, along, cx, cy, ang, radius, rng):
    """Where a leaf clump's vertices go: latitude rings round the stem axis.

    Lumpiness is per COLUMN and per RING, never per vertex. A per-vertex
    jitter is what turns a band quad into two collinear triangles; a column
    that is fat all the way up and a ring that is fat all the way round give
    the same broken silhouette with every face still square on.

    Pure, and separate from the emit, so the caller can weigh the clump
    against the ground before a single vertex is committed.
    """
    k = [1.0 + CLUMP_WOB * rng.sf() for _ in ang]            # column: a lump up the side
    rings = []
    for lat in CLUMP_LATS:
        j = 1.0 + 0.55 * CLUMP_WOB * rng.sf()                # ring: a lump round it
        cl, sl = math.cos(math.radians(lat)), math.sin(math.radians(lat))
        rings.append([add(add(add(centre, along, radius * CLUMP_SQUASH * sl * j),
                              cx, radius * cl * k[s] * j * math.cos(ang[s])),
                          cy, radius * cl * k[s] * j * math.sin(ang[s]))
                      for s in range(len(ang))])
    tip = add(centre, along, radius * CLUMP_SQUASH * (1.0 + 0.4 * CLUMP_WOB * rng.sf()))
    return rings, tip


def _clump(m, base, ang, shape, tip_pt, centre, zone):
    """The clump, emitted: the stub's far ring, the latitude rings, a tip."""
    rings = [base] + [[m.v(q) for q in ring] for ring in shape]
    # Foliage is lit from above and dark underneath, and that is the whole of
    # why a bush reads as a bush and not as a rock: the tuck under the clump
    # takes the shaded sheet, the cap that faces the sky takes the sunlit one,
    # and only the band between them carries the lobe's own zone.
    for i in range(len(rings) - 1):
        z = "shade" if i == 0 else zone
        for s in range(len(ang)):
            t = (s + 1) % len(ang)
            idx = (rings[i][s], rings[i][t], rings[i + 1][t], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), centre), z)
    tip = m.v(tip_pt)
    cap = "shade" if zone == "shade" else "sun"
    for s in range(len(ang)):
        t = (s + 1) % len(ang)
        idx = (tip, rings[-1][s], rings[-1][t])
        m.tri(idx[0], idx[1], idx[2], sub(m.centroid(idx), centre), cap)


def _true_to_size(m, p):
    """Scale the finished bush onto the size it is advertised at.

    The lobes are laid out by hand in fractions of the prop, so the metres
    that come out are an outcome. A map-maker places against the metres, so
    they are made a guarantee instead: one factor across, one up.
    """
    lo = [min(v[k] for v in m.verts) for k in range(3)]
    hi = [max(v[k] for v in m.verts) for k in range(3)]
    if lo[2] < -1e-6:
        raise ValueError("forest_bush %s: %.3f m of bush below the ground. A prop "
                         "Ryan drops on the grass at identity has to sit ON it; "
                         "aim the low lobes higher or widen the skirt band."
                         % (p.variant, -lo[2]))
    sxy = p.width / max(hi[0] - lo[0], hi[1] - lo[1])
    sz = p.height / hi[2]
    m.verts = [(x * sxy, y * sxy, z * sz) for (x, y, z) in m.verts]
    print("TRUE %s across=%.3f up=%.3f" % (p.variant, sxy, sz))
    return m


def build_geometry(p):
    """The bush: one mesh, one component, clumps welded into the core."""
    m = _Mesh()
    rng = _Rng(p.seed)
    quads = _core(m, p, rng)
    used = set()
    for spec in p.lobes:
        _lobe(m, p, rng, quads, used, spec)
    return _true_to_size(m.compact(), p)


def build_collider(m, p):
    """The bush's own silhouette, measured cell by cell and pulled in.

    Not a box and not a barrel of one radius: the drawn mesh is read into a
    grid of (height band x compass sector) and each cell keeps its own widest
    vertex. A bush that leans is then blocked where it leans, and the collider
    never stands proud of the leaves on the thin side -- which a single radius
    off the widest point always does.
    """
    c = _Mesh()
    top = max(v[2] for v in m.verts)
    edges = [top * k / float(COLL_BANDS) for k in range(COLL_BANDS + 1)]
    ang = [2.0 * math.pi * (i + 0.5) / COLL_SIDES for i in range(COLL_SIDES)]

    cell = [[0.0] * COLL_SIDES for _ in range(COLL_BANDS + 1)]
    span = top / COLL_BANDS
    for v in m.verts:
        r = math.hypot(v[0], v[1])
        sec = int(((math.atan2(v[1], v[0]) - ang[0]) % (2.0 * math.pi))
                  / (2.0 * math.pi) * COLL_SIDES)
        for k in range(COLL_BANDS + 1):
            if abs(v[2] - edges[k]) <= span:
                cell[k][sec] = max(cell[k][sec], r)
    for k in range(COLL_BANDS + 1):                  # a sector with nothing in it
        for i in range(COLL_SIDES):                  # borrows from its neighbours
            if cell[k][i] <= 0.0:
                cell[k][i] = max(cell[k][(i - 1) % COLL_SIDES],
                                 cell[k][(i + 1) % COLL_SIDES])
    # No knife edges: a sector never pinches to less than a third of its band,
    # or two neighbouring radii make a face too thin to collide against.
    rad = [[max(x * COLL_INSET, 0.34 * max(row) * COLL_INSET, 0.04) for x in row]
           for row in cell]
    for i in range(COLL_SIDES):                      # the crown closes, never a lid
        rad[-1][i] = max(min(rad[-1][i], rad[-2][i] * 0.55), 0.04)

    rings = [[c.v((rad[k][i] * math.cos(ang[i]), rad[k][i] * math.sin(ang[i]), edges[k]))
              for i in range(COLL_SIDES)]
             for k in range(COLL_BANDS + 1)]
    for k in range(COLL_BANDS):
        for i in range(COLL_SIDES):
            q = (i + 1) % COLL_SIDES
            am = ang[i] + math.pi / COLL_SIDES
            c.quad(rings[k][i], rings[k][q], rings[k + 1][q], rings[k + 1][i],
                   (math.cos(am), math.sin(am), 0.0), "shade")
    # Capped from a centre vertex, not fanned from a corner: the rings are
    # irregular by design, and a corner fan across an irregular ring puts three
    # near-collinear points in one triangle.
    for ring, z, want in ((rings[0], edges[0], DOWN), (rings[-1], edges[-1], UP)):
        hub = c.v((0.0, 0.0, z))
        for i in range(COLL_SIDES):
            q = (i + 1) % COLL_SIDES
            c.tri(hub, ring[i], ring[q], want, "shade")
    return c.compact()


# =============================================================================
# RENDER -- the scale proxy, on ad-hoc cameras only
# =============================================================================

def _proxy(p):
    """A 1.8 m blocked-in prisoner beside the bush: head, chest, legs. Render
    only -- it is built in `post`, after the .glb has already been written."""
    x = p.radius + PROXY_GAP
    h1 = PROXY_H
    boxes = [(0.34, 0.20, 0.50 * h1, 0.00 * h1),    # legs
             (0.42, 0.24, 0.32 * h1, 0.50 * h1),    # chest
             (0.22, 0.22, 0.18 * h1, 0.82 * h1),    # neck and head
             (0.62, 0.18, 0.08 * h1, 0.62 * h1)]    # arms
    parts = []
    for w, d, h, z0 in boxes:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, 0.0, z0 + h * 0.5))
        ob = bpy.context.active_object
        ob.scale = (w, d, h)
        parts.append(ob)
    ob = mdl.join(parts, "ScaleProxy")
    ob.data.materials.clear()
    ob.data.materials.append(mdl.flat_material("Proxy", [0.16, 0.10, 0.08, 1.0],
                                               roughness=0.9))
    return ob


def _post(spec, objects):
    if spec.get("cams"):
        _proxy(Params(_variant()))
        print("MDL note: scale proxy %.2f m added for the ad-hoc camera" % PROXY_H)


# =============================================================================
# BUILD
# =============================================================================

def build():
    p = Params(_variant())
    m = build_geometry(p)
    c = build_collider(m, p)

    albedo, emissive = ft.sheet("forest_atlas", ft.paint_atlas)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)

    ob = m.object(OBJECT_NAME)
    ft.unwrap(ob, m.zones)
    mdl.finish(ob, ft.atlas_material("ForestAtlas", albedo, emissive), strip_uvs=False)

    coll = c.object(COLLIDER_NAME)
    coll.hide_render = True

    xs = [v[0] for v in m.verts]
    ys = [v[1] for v in m.verts]
    zs = [v[2] for v in m.verts]
    print("MDL STATS variant=%s visual_tris=%d collision_tris=%d width=%.2f depth=%.2f height=%.2f"
          % (p.variant, len(ob.data.polygons), len(coll.data.polygons),
             max(xs) - min(xs), max(ys) - min(ys), max(zs)))
    return [ob, coll]


def _check():
    import forest_check
    v = _variant()
    p = Params(v)
    m = build_geometry(p)
    c = build_collider(m, p)
    forest_check.prove(m, "bush_" + v)
    forest_check.prove(c, "coll_" + v)
    forest_check.components_report(m)
    for name, mm in (("bush", m), ("coll", c)):
        zones = {}
        for z in mm.zones:
            zones[z] = zones.get(z, 0) + 1
        lo = [min(x[k] for x in mm.verts) for k in range(3)]
        hi = [max(x[k] for x in mm.verts) for k in range(3)]
        print("%s_%s tris=%d verts=%d zones=%s width=%.2f depth=%.2f height=%.2f"
              % (name, v, len(mm.faces), len(mm.verts), zones,
                 hi[0] - lo[0], hi[1] - lo[1], hi[2]))
    hides_crouched = max(x[2] for x in c.verts) >= 1.20
    hides_standing = max(x[2] for x in c.verts) >= 1.80
    print("COVER %s crouched(1.20 m)=%s standing(1.80 m)=%s"
          % (v, hides_crouched, hides_standing))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME + "_" + _variant(), build, facing_yaw=FACING_YAW, post=_post)
