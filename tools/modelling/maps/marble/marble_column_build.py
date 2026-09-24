"""marble_column -- a classic column for map 2, the marble rotunda.

Two variants out of this one script, chosen with ``--variant``:

  whole   0.80 m across the shaft, 5.00 m tall, on a 1.20 m square plinth,
          with a simple capital (astragal, necking, echinus, square abacus).
  broken  the same column snapped off at about 2.2 m with a jagged fracture
          cap -- standing cover a 1.8 m prisoner can hide behind.

    tools/modelling/model build marble_column
    tools/modelling/model build marble_column_broken     # the shim next door
    python3 tools/modelling/maps/marble/marble_column_build.py --check --variant broken

ORIGIN IS THE BASE CENTRE: z=0 (Godot y=0) is the ground it stands on.
Blender +Z -> Godot +Y. Authored 16-sided, because a 16-gon's radial
directions at 22.5 deg include the square plinth's four corners, so the
plinth top welds to the shaft's foot ring one-to-one with no T-junction.

FLUTING IS PAINTED, NOT CUT. The shaft borrows marble_build.py's own atlas --
the same painted 256 px Temple of Time sheet the rotunda is dressed in, so the
prop cannot drift from the map -- and each of the 16 facets takes a quarter of
the ``column`` cell, two flutes wide. 32 flutes on a 0.8 m shaft for 352
triangles; cutting them would cost thousands.

Contract: one mesh (one surface, one UV set) plus a `-colonly` collider drawn
from the column's own profile at 8 sides, not a box: the plinth's corners and
the capital's overhang are what a runner catches on.
"""

import math
import os
import sys

try:
    import bpy
except ImportError:                       # --check on the Mac: geometry only
    bpy = None

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

if bpy is not None:
    import mdl  # noqa: E402

# The map this prop belongs to: its atlas, its painters, its palette, its mesh
# accumulator and its contiguity audit. Column-0 `import x_build as y`:
# tools/modelling/model ships the siblings it sees written exactly like that.
import marble_build as mb  # noqa: E402

if bpy is not None:
    # marble_build shuts the render defaults down on import -- no ground, no
    # named views -- because its rotunda is a closed dome lit from inside. A
    # prop stands in the open and is looked at from outside.
    mdl.DEFAULTS["ground"] = True
    mdl.DEFAULTS["ground_color"] = [0.26, 0.26, 0.24, 1.0]
    mdl.DEFAULTS["views"] = ["threequarter", "front"]
    mdl.DEFAULTS["world_grey"] = 0.22
    mdl.DEFAULTS["world_strength"] = 0.80


# =============================================================================
# TUNABLES
# =============================================================================

NAME = "marble_column"
FACING_YAW = 0.0
SEED = 4471903

NSIDE = 16                  # facets round the shaft; 22.5 deg, so 45 deg is a station
COLL_SIDE = 8               # the collider's facets: the same profile, coarser
FLUTES_PER_FACET = 2        # of the `column` cell's eight: a quarter-cell window

PLINTH_HW = 0.60            # half width -> a 1.20 m square plinth
PLINTH_H = 0.30
ABACUS_HW = 0.60            # 1.20 m square, 0.08 m proud of the echinus
ABACUS_Z0 = 4.80
ABACUS_Z1 = 5.00            # the whole column's full height

# (radius, z) up the axis. The band BETWEEN ring k and ring k+1 takes
# BANDS[k]'s atlas cell. Ring 2 is r 0.400: the shaft is 0.80 m across.
WHOLE_RINGS = [
    (0.500, 0.30),   # 0  the base's foot, standing on the plinth
    (0.460, 0.42),   # 1  torus
    (0.400, 0.54),   # 2  the shaft starts
    (0.396, 1.40),   # 3  entasis: a slight swell, then the taper
    (0.380, 2.30),   # 4
    (0.358, 3.20),   # 5
    (0.340, 4.08),   # 6  the shaft's top
    (0.352, 4.20),   # 7  astragal, proud
    (0.336, 4.34),   # 8  necking, recessed and in shadow
    (0.360, 4.48),   # 9
    (0.520, 4.74),   # 10 echinus, flared
    (0.520, ABACUS_Z0),   # 11 the fillet under the abacus
]
WHOLE_BANDS = ["band", "band", "column", "column", "column", "column",
               "band", "shade", "band", "band", "band"]

BROKEN_RINGS = [
    (0.500, 0.30),
    (0.460, 0.42),
    (0.400, 0.54),
    (0.394, 1.20),
    (0.386, 1.75),
]
BROKEN_BANDS = ["band", "band", "column", "column"]

BREAK_Z = 2.00              # the fracture's mean height
BREAK_TILT = 0.13           # it runs downhill across the shaft ...
BREAK_PHI = 0.9             # ... on this bearing, radians
BREAK_JAG = 0.13            # held in runs of 1-2 facets: steps, not noise
BREAK_JAG_RUN = (1, 2)
BREAK_CHIP = 0.055          # the rim bitten back off the shaft's face
BREAK_DISH = 0.09           # the broken face is dished, not a flat saw cut

# The collider: the same profile, 8-sided, the rings that carry the silhouette.
COLL_WHOLE_RINGS = [(0.500, 0.30), (0.400, 0.54), (0.340, 4.08), (0.520, ABACUS_Z0)]
COLL_BROKEN_RINGS = [(0.500, 0.30), (0.400, 0.54), (0.386, 1.95)]
COLL_BROKEN_TOP = 1.95

VARIANTS = {
    "whole": {
        "object": "MarbleColumn",
        "collider": "MarbleColumnCollision-colonly",
        "rings": WHOLE_RINGS, "bands": WHOLE_BANDS,
        "coll_rings": COLL_WHOLE_RINGS,
        "shot": {"az": 35.0, "el": -4.0, "lens": 45.0, "gap": 1.7},
    },
    "broken": {
        "object": "MarbleColumnBroken",
        "collider": "MarbleColumnBrokenCollision-colonly",
        "rings": BROKEN_RINGS, "bands": BROKEN_BANDS,
        "coll_rings": COLL_BROKEN_RINGS,
        "shot": {"az": 35.0, "el": 2.0, "lens": 45.0, "gap": 1.4},
    },
}

UP = (0.0, 0.0, 1.0)
DOWN = (0.0, 0.0, -1.0)
TWO_PI = 2.0 * math.pi


# =============================================================================
# GEOMETRY -- marble_build's _Mesh welds by position, so parts that name the
# same point share one vertex and the seams cannot come apart.
# =============================================================================

def _round_ring(m, rad, z, n):
    return [m.v((rad * math.cos(TWO_PI * i / n),
                 rad * math.sin(TWO_PI * i / n), z)) for i in range(n)]


def _square_ring(m, half, z, n):
    """The plinth's outline, sampled on the SAME n radial bearings as the
    shaft's rings. n divisible by 8 puts a vertex on each corner."""
    out = []
    for i in range(n):
        a = TWO_PI * i / n
        c, s = math.cos(a), math.sin(a)
        k = half / max(abs(c), abs(s))
        out.append(m.v((k * c, k * s, z)))
    return out


def _band(m, lo, hi, n, zone):
    """The wall between two rings; the normal must point outward."""
    for i in range(n):
        a = TWO_PI * (i + 0.5) / n
        m.quad(lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i],
               (math.cos(a), math.sin(a), 0.0), zone)


def _annulus(m, outer, inner, n, want, zone):
    for i in range(n):
        m.quad(outer[i], outer[(i + 1) % n], inner[(i + 1) % n], inner[i], want, zone)


def _cap(m, ring, n, z, want, zone):
    """Close a ring onto a centre vertex. A fan from ring[0] would be three
    collinear points wide on a square ring -- a degenerate triangle."""
    c = m.v((0.0, 0.0, z))
    gid = len(m.groups)
    for i in range(n):
        m.tri(ring[i], ring[(i + 1) % n], c, want, zone)
        m.groups[-1] = gid                # one atlas window for the whole cap


def _held(r, n, amp, run):
    """A per-facet offset held for runs of facets: stone steps, it does not
    fizz. Wraps: the last run is truncated so facet 0 and facet n-1 differ."""
    out = [0.0] * n
    k = 0
    while k < n:
        v = r.sf() * amp
        for kk in range(k, min(k + r.i(*run), n)):
            out[kk] = v
        k = kk + 1
    return out


def _stem(m, n, rings, bands):
    """Plinth + base + shaft, welded. Returns the ring index lists."""
    lo = _square_ring(m, PLINTH_HW, 0.0, n)
    hi = _square_ring(m, PLINTH_HW, PLINTH_H, n)
    _cap(m, lo, n, 0.0, DOWN, "shade")
    _band(m, lo, hi, n, "plinth")
    rg = [_round_ring(m, rad, z, n) for (rad, z) in rings]
    _annulus(m, hi, rg[0], n, UP, "plinth")       # the plinth's top, round the foot
    for k, zone in enumerate(bands):
        _band(m, rg[k], rg[k + 1], n, zone)
    return rg


def _capital(m, top, n):
    """The abacus: a square slab sitting on the echinus's fillet."""
    sq0 = _square_ring(m, ABACUS_HW, ABACUS_Z0, n)
    _annulus(m, sq0, top, n, DOWN, "shade")       # the overhang's soffit
    sq1 = _square_ring(m, ABACUS_HW, ABACUS_Z1, n)
    _band(m, sq0, sq1, n, "plinth")
    _cap(m, sq1, n, ABACUS_Z1, UP, "plinth")


def _fracture(m, top, n, r):
    """The snapped top: a tilted, stepped rim bitten back off the shaft's
    face, closed by a dished cap of raw stone."""
    jag = _held(r, n, BREAK_JAG, BREAK_JAG_RUN)
    chip = _held(r, n, BREAK_CHIP * 0.5, BREAK_JAG_RUN)
    rad0 = BROKEN_RINGS[-1][0]
    rim, zs = [], []
    for i in range(n):
        a = TWO_PI * i / n
        z = BREAK_Z + BREAK_TILT * math.cos(a - BREAK_PHI) + jag[i]
        rad = rad0 - BREAK_CHIP * 0.5 - abs(chip[i])
        rim.append(m.v((rad * math.cos(a), rad * math.sin(a), z)))
        zs.append(z)
    _band(m, top, rim, n, "column")
    _cap(m, rim, n, BREAK_Z - BREAK_DISH, UP, "spike")
    return min(zs), max(zs)


def _visual(variant):
    cfg = VARIANTS[variant]
    r = mb._Rng(SEED)
    m = mb._Mesh()
    rg = _stem(m, NSIDE, cfg["rings"], cfg["bands"])
    if variant == "whole":
        _capital(m, rg[-1], NSIDE)
        top = ABACUS_Z1
    else:
        _lo, top = _fracture(m, rg[-1], NSIDE, r)
    return m, top


def _collider(variant):
    """Drawn from the column's own faces at 8 sides -- the plinth's corners
    and the capital's overhang are what a runner catches on, so a box is a
    lie in both directions."""
    cfg = VARIANTS[variant]
    n = COLL_SIDE
    c = mb._Mesh()
    rings = cfg["coll_rings"]
    _stem(c, n, rings, ["shade"] * (len(rings) - 1))
    if variant == "whole":
        _capital(c, [c.v((0.520 * math.cos(TWO_PI * i / n),
                          0.520 * math.sin(TWO_PI * i / n), ABACUS_Z0)) for i in range(n)], n)
    else:
        _cap(c, [c.v((rings[-1][0] * math.cos(TWO_PI * i / n),
                      rings[-1][0] * math.sin(TWO_PI * i / n), COLL_BROKEN_TOP))
                 for i in range(n)], n, COLL_BROKEN_TOP, UP, "shade")
    return c


# =============================================================================
# UV -- marble_build's windows, with the shaft narrowed to two flutes
# =============================================================================

def unwrap(ob, zones, groups):
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = mb._Rng(SEED + len(me.polygons))
    by_group = {}
    for pi in range(len(me.polygons)):
        by_group.setdefault(groups[pi], []).append(pi)
    for gid in sorted(by_group):
        polys = by_group[gid]
        z = zones[polys[0]]
        rect = mb.ZONES[z]
        if z == "column":
            # The `column` cell paints eight flutes. A facet takes a window of
            # FLUTES_PER_FACET of them, on a flute boundary so the arrises meet
            # the geometry's own arrises at the facet edges.
            u0, _v0, u1, _v1 = rect
            step = (u1 - u0) * FLUTES_PER_FACET / 8.0
            k = gid % (8 // FLUTES_PER_FACET)
            rect = (u0 + k * step, rect[1], u0 + (k + 1) * step, rect[3])
        mb._group_uv(me, uvl, polys, rect, r, mb.FIT.get(z, ""), z in mb.ANCHORED)


# =============================================================================
# BUILD
# =============================================================================

def _prove(m, coll, variant):
    a = mb.audit(m, "%s visual" % variant)
    mb.audit(coll, "%s collider" % variant)
    bad = (a["components"] != 1 or a["boundary_edges"] or a["doubled_edges"]
           or a["over_edges"] or a["degenerate"] or a["duplicate_positions"])
    if bad:
        raise RuntimeError("marble_column %s: not one closed contiguous mesh" % variant)
    return a


def build(variant):
    cfg = VARIANTS[variant]
    m, top = _visual(variant)
    coll = _collider(variant)
    a = _prove(m, coll, variant)

    albedo, emissive = mb._sheet("marble", mb.build_texture)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    ob = m.object(cfg["object"])
    unwrap(ob, m.zones, m.groups)
    mdl.finish(ob, mb.stone_material("Marble", albedo, emissive), strip_uvs=False)
    coll_ob = coll.object(cfg["collider"])
    coll_ob.hide_render = True

    print("MDL STATS variant=%s visual_tris=%d collision_tris=%d height=%.2f "
          "shaft_across=%.2f plinth=%.2f facets=%d"
          % (variant, len(ob.data.polygons), len(coll_ob.data.polygons), top,
             cfg["rings"][2][0] * 2.0, PLINTH_HW * 2.0, NSIDE))
    print("MDL STATS contiguity components=%d duplicate_positions=%d boundary=%d "
          "doubled=%d over=%d degenerate=%d manifold=%d"
          % (a["components"], a["duplicate_positions"], a["boundary_edges"],
             a["doubled_edges"], a["over_edges"], a["degenerate"], a["manifold_edges"]))
    return [ob, coll_ob]


def _check(variant):
    """--check: build the geometry without Blender and prove it welded."""
    m, top = _visual(variant)
    coll = _collider(variant)
    a = mb.audit(m, "%s visual" % variant)
    b = mb.audit(coll, "%s collider" % variant)
    ok = True
    for who, x in (("visual", a), ("collider", b)):
        bad = (x["components"] != 1 or x["boundary_edges"] or x["doubled_edges"]
               or x["over_edges"] or x["degenerate"] or x["duplicate_positions"]
               or x["unused_verts"])
        ok = ok and not bad
    print("marble_column %s: height=%.2f shaft_across=%.2f plinth=%.2f visual_tris=%d "
          "collision_tris=%d" % (variant, top, VARIANTS[variant]["rings"][2][0] * 2.0,
                                 PLINTH_HW * 2.0, len(m.faces), len(coll.faces)))
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


# =============================================================================
# RENDERS -- the three-quarter and front shots are mdl's; this adds the
# eye-level one with a 1.8 m prisoner beside it, and leaves no scaffolding
# =============================================================================

# 1.8 m standing human, as three stacked boxes: (x_size, y_size, z0, z1).
_PROXY_BOXES = (
    ("ProxyLegs",  0.36, 0.26, 0.00, 0.88),
    ("ProxyTorso", 0.46, 0.30, 0.88, 1.52),
    ("ProxyHead",  0.24, 0.24, 1.52, 1.80),
)
_PROXY_GREY = (0.15, 0.16, 0.145, 1.0)   # the key clips anything lighter to white


def scale_shot(spec, objects, name, facing_yaw=0.0, az=35.0, el=-4.0, lens=45.0, gap=1.6):
    """Render <out_dir>/<name>_scale.png: `objects` plus a 1.8 m human proxy
    standing `gap` metres away on +X, framed near eye level."""
    objects = list(objects)
    before = set(bpy.data.objects)          # snapshot BEFORE anything is made
    keep = before | set(objects)
    out_dir = spec.get("out_dir", ".")
    try:
        _lo, hi = mdl._bounds(objects)
        px = hi.x + float(gap)
        parts = []
        for (part, sx, sy, z0, z1) in _PROXY_BOXES:
            parts.append((part, mdl.box(part,
                                        (px - sx * 0.5, -sy * 0.5, z0),
                                        (px + sx * 0.5, sy * 0.5, z1))))
        proxy, _groups = mdl.merge_parts(parts, "ScaleProxy")
        mdl.finish(proxy, mdl.flat_material("ScaleProxyGrey", _PROXY_GREY))

        sub = dict(spec)
        sub["views"] = []
        sub["cams"] = [[float(az), float(el), float(lens)]]
        sub["turntable"] = 0
        written = mdl.render(sub, objects + [proxy], name, facing_yaw)

        src = written[0] if written else os.path.join(
            out_dir, "%s_cam1_az%g_el%g.png" % (name, float(az), float(el)))
        dst = os.path.join(out_dir, "%s_scale.png" % name)
        os.replace(src, dst)
        print("MDL RENDER %s_scale.png (1.8 m proxy at +X %.2f m)" % (name, px))
        return dst
    finally:
        # setup_scene() adds a ground "Plane", "CamTarget", "Cam" and the three
        # area lights on EVERY call. Anything here that was neither in the
        # snapshot nor handed to us goes, or the next render is lit twice.
        for ob in list(bpy.data.objects):
            if ob not in keep:
                bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# ENTRY POINT
# =============================================================================

def variant_from_argv(default="whole"):
    argv = sys.argv
    if "--variant" in argv:
        which = argv[argv.index("--variant") + 1]
        if which not in VARIANTS:
            raise SystemExit("marble_column: unknown --variant %r (want %s)"
                             % (which, "/".join(sorted(VARIANTS))))
        return which
    return default


def run(name, variant):
    """Build and render one variant under `name`. The shim next door calls
    this too, because `model build <name>` wants a <name>_build.py."""
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check(variant) else 1)
    shot = VARIANTS[variant]["shot"]
    mdl.main(name, lambda: build(variant), facing_yaw=FACING_YAW,
             post=lambda spec, objects: scale_shot(spec, objects, name,
                                                   FACING_YAW, **shot))


if __name__ == "__main__":
    run(NAME, variant_from_argv())
