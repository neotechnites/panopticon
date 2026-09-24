"""PANOPTICON -- forest_rock: three faceted granite rocks for map 3, one script.

    tools/modelling/model build forest_rock --variant boulder|slab|outcrop
    python3 tools/modelling/maps/forest/forest_rock_build.py --check --variant slab

boulder  1.30 m tall x 2.00 m across -- crouch cover, hides a crouched runner
slab     2.10 m tall x 2.50 m across -- standing cover, 0.66 m thick, leaning
outcrop  0.70 m tall x 2.40 m across -- vaultable (the jump clears 1.11 m)

Origin is the base centre: z=0 is the ground it sits on, Blender +Z = Godot +Y.
One ring stack per rock: the column angles and each column's radial bias are
held for every ring, so the vertical edges stay straight and the sides read as
cleaved facets. Zones come off the face normal -- moss on what faces the sky,
lichen on the shoulders, granite on the sides, damp granite in the recesses.

Palette and atlas helpers are forest_tree_build's, so the rock belongs to the
same forest as the tree and the lane.

Contract: one mesh `ForestRock` (1 surface, 1 UV set) plus
`ForestRockCollision-colonly` -- the same columns and the same profile with the
jitter zeroed and a flat top, so it matches the drawn silhouette and nothing
snags on a facet.
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

import forest_tree_build as ft  # noqa: E402
from forest_tree_build import _Mesh, _Rng, UP, DOWN  # noqa: E402

if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["ground"] = True                      # a prop stands on ground
    mdl.DEFAULTS["ground_color"] = [0.11, 0.14, 0.09, 1.0]
    mdl.DEFAULTS["world_grey"] = 0.30
    mdl.DEFAULTS["world_strength"] = 0.95

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "forest_rock"
OBJECT_NAME = "ForestRock"
COLLIDER_NAME = "ForestRockCollision-colonly"
FACING_YAW = 0.0

# (t, radius as a fraction of RX/RY). t is the fraction of HEIGHT.
VARIANTS = {
    "boulder": dict(
        sides=12, height=1.30, rx=0.95, ry=0.88, lean=0.0, tilt=0.0,
        profile=[(0.00, 0.90), (0.16, 1.00), (0.40, 1.00),
                 (0.66, 0.93), (0.84, 0.82), (1.00, 0.52)],
        moss_cos=0.50, r_bias=0.17, seed=8140311),
    "slab": dict(
        sides=10, height=2.20, rx=1.14, ry=0.33, lean=0.13, tilt=0.085,
        profile=[(0.00, 1.00), (0.20, 0.995), (0.42, 0.98),
                 (0.62, 0.955), (0.82, 0.90), (1.00, 0.66)],
        moss_cos=0.50, r_bias=0.13, seed=8140737),
    "outcrop": dict(
        sides=14, height=0.73, rx=1.20, ry=1.00, lean=0.0, tilt=0.05,
        profile=[(0.00, 0.88), (0.20, 1.00), (0.46, 0.98),
                 (0.72, 0.90), (1.00, 0.62)],
        moss_cos=0.30, r_bias=0.19, seed=8141093),
}
DEFAULT_VARIANT = "boulder"

ANG_JAG = 0.26          # radians, per column, held for every ring: cleave lines stay vertical
R_JAG = 0.035           # per ring per column, fraction of radius: the collider tracks within this
Z_JAG = 0.040           # interior ring z, fraction of HEIGHT
TOP_DROP = 0.075        # crest ring drops this fraction of HEIGHT, never rises: the flat
                        # collider top stays the highest point, so nothing floats on it
LICHEN_COS = 0.26       # normal z over this is a shoulder
SHADE_BIAS = -0.55      # damp rock: a facet pulled in by this share of the variant's bias

# ---- atlas: our own 128 sheet, painted in forest_tree_build's palette -------
TEX_SIZE = 128
TEX_SEED = 5230411
TPM = 40.0                      # texels per metre: 2.5 cm grain, a 0.8 m facet gets 32
ZONES = {                       # (u0, v0, u1, v1)
    "granite": (0.0, 0.0, 0.5, 0.5),
    "shade": (0.5, 0.0, 1.0, 0.5),
    "moss": (0.0, 0.5, 0.5, 1.0),
    "lichen": (0.5, 0.5, 1.0, 1.0),
}
UV_PAD = 1.5 / TEX_SIZE

PROXY_H = 1.80          # the scale figure: render-only, never exported
PROXY_W = 0.55
PROXY_D = 0.30


def variant_name():
    """--variant off the command line (after Blender's --), else the default."""
    argv = sys.argv
    rest = argv[argv.index("--") + 1:] if "--" in argv else argv[1:]
    for i, a in enumerate(rest):
        if a == "--variant" and i + 1 < len(rest):
            return rest[i + 1]
        if a.startswith("--variant="):
            return a.split("=", 1)[1]
    return DEFAULT_VARIANT


# =============================================================================
# TEXTURE -- four zones of forest granite
# =============================================================================

# Forest granite: EARTH_STONE pulled cool and a step green, never the red of
# map 1's boulder. Painted as fine noise, one or two texels at a time: anything
# bigger reads as that facet's own patch, which is docs/maps/forest.md's rule
# for the lane and holds just as hard on a prop unwrapped a face at a time.
GRANITE_TONES = ((124, 126, 112), (114, 117, 104), (134, 136, 120), (106, 110, 98))
GRANITE_GREEN = ((120, 128, 104), (112, 120, 98))                  # the forest's cast in the rock
FELDSPAR = ((152, 154, 138), (142, 145, 130))                      # #989a8a #8e9182
BIOTITE = ((84, 88, 76), (74, 78, 68))                             # #54584c #4a4e44
GRANITE_CRACK = (62, 64, 56)                                       # #3e4038

SHADE_TONES = ((98, 102, 92), (90, 94, 86), (106, 110, 98), (84, 88, 80))
SHADE_GREEN = ((94, 102, 84), (88, 96, 80))
SHADE_FELDSPAR = ((124, 128, 116), (116, 120, 110))
SHADE_BIOTITE = ((66, 70, 62), (60, 64, 56))
SHADE_CRACK = (52, 56, 50)

MOSS_TONES = ((66, 90, 50), (58, 80, 46), (74, 98, 54), (62, 86, 48))   # EARTH_MOSS and neighbours
MOSS_CLUMP = ((84, 104, 60), (80, 106, 58))                        # BARK_MOSS, FERN_BASE
MOSS_DARK = (52, 72, 42)                                           # FERN_DARK #34482a
MOSS_LIT = (138, 152, 86)                                          # LEAF_LIT #8a9856

LICHEN_SAGE = ((146, 150, 122), (134, 140, 114))                   # #92967a #868c72
LICHEN_MIST = (146, 147, 75)                                       # OoT mist #92934b


def _specks(c, r, box, tones, count):
    """One-texel grain. Two texels at most: a granite crystal is not a patch."""
    x0, y0, x1, y1 = box
    for _ in range(count):
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        t = r.pick(tones)
        c.put(x, y, t)
        if r.i(0, 3) == 0:
            c.put(x + 1, y, t)


def _cracks(c, r, box, rgb, count, length):
    """Hairline cleavage: a one-texel random walk, never a blotch."""
    x0, y0, x1, y1 = box
    for _ in range(count):
        x, y = r.i(x0, x1 - 1), r.i(y0, y1 - 1)
        dx, dy = r.pick(((1, 0), (0, 1), (1, 1), (1, -1)))
        for _step in range(length):
            c.put(x, y, rgb)
            x += dx + r.i(-1, 1) * (dy != 0)
            y += dy + r.i(-1, 1) * (dx != 0)
            if not (x0 <= x < x1 and y0 <= y < y1):
                break


def paint_granite(c, r, box):
    """Cool grey-green granite: a fine noise ground, feldspar and biotite grain,
    a few hairline cleavage lines."""
    ft._noise_fill(c, r, box, GRANITE_TONES, cuts=(0.30, 0.56, 0.80), dither=6)
    _specks(c, r, box, GRANITE_GREEN, 160)
    _specks(c, r, box, FELDSPAR, 110)
    _specks(c, r, box, BIOTITE, 150)
    _cracks(c, r, box, GRANITE_CRACK, 5, 22)


def paint_shade(c, r, box):
    """The same rock damp and out of the sun: a third down and a shade cooler."""
    ft._noise_fill(c, r, box, SHADE_TONES, cuts=(0.30, 0.56, 0.80), dither=5)
    _specks(c, r, box, SHADE_GREEN, 170)
    _specks(c, r, box, SHADE_FELDSPAR, 100)
    _specks(c, r, box, SHADE_BIOTITE, 140)
    _cracks(c, r, box, SHADE_CRACK, 5, 22)


def paint_moss(c, r, box):
    """Dense forest moss, lit tips, a little granite grain still showing."""
    ft._noise_fill(c, r, box, MOSS_TONES, cuts=(0.30, 0.56, 0.80), dither=6)
    _specks(c, r, box, MOSS_CLUMP, 220)
    _specks(c, r, box, (MOSS_DARK,), 140)
    _specks(c, r, box, (MOSS_LIT,), 90)
    _specks(c, r, box, GRANITE_TONES, 40)


def paint_lichen(c, r, box):
    """The shoulder: granite with sage lichen grain and moss creeping in."""
    paint_granite(c, r, box)
    _specks(c, r, box, LICHEN_SAGE, 90)
    _specks(c, r, box, (LICHEN_MIST,), 50)
    _specks(c, r, box, MOSS_TONES, 280)
    _specks(c, r, box, MOSS_CLUMP, 120)


PAINTERS = {"granite": paint_granite, "shade": paint_shade,
            "moss": paint_moss, "lichen": paint_lichen}


def paint_atlas():
    c = ft._Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    for zone, fn in sorted(PAINTERS.items()):
        fn(c, r, ft._rect_of(ZONES[zone], TEX_SIZE))
    return ft._images(c, TEX_SIZE, ("forest_rock_albedo", "forest_rock_emissive"))


# =============================================================================
# GEOMETRY -- one ring stack, columns held, caps on a centre vertex
# =============================================================================

def _columns(v, r):
    """Per column: its angle and its radial bias, both held for every ring."""
    n = v["sides"]
    ang = [(i + 0.5) * 2.0 * math.pi / n + ANG_JAG * r.sf() for i in range(n)]
    bias = [v["r_bias"] * r.sf() for _ in range(n)]
    return ang, bias


def _rings(v, ang, bias, r, jitter):
    """The ring stack. ``jitter`` off gives the collider's smooth twin."""
    n, h = v["sides"], v["height"]
    out = []
    for k, (t, rf) in enumerate(v["profile"]):
        top = k == len(v["profile"]) - 1
        z = h * t
        if jitter and 0 < k and not top:
            z += h * Z_JAG * r.sf()
        ring = []
        for i in range(n):
            rr = rf + bias[i] + (R_JAG * r.sf() if jitter else 0.0)
            x = v["rx"] * rr * math.cos(ang[i])
            zz = z - (v["tilt"] * (x + v["rx"]) if top else 0.0)
            zz -= h * TOP_DROP * r.f() if (jitter and top) else 0.0
            ring.append((x, v["ry"] * rr * math.sin(ang[i]), zz))
        out.append(ring)
    return out


def _zone_of(m, idx, recess, moss_cos, r_bias):
    """Moss faces the sky, lichen the shoulder, damp granite the recesses."""
    n = ft._newell([m.verts[j] for j in idx])
    ln = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
    nz = n[2] / ln if ln > 1e-12 else 0.0
    if nz >= moss_cos:
        return "moss"
    if nz >= LICHEN_COS:
        return "lichen"
    return "shade" if recess < SHADE_BIAS * r_bias else "granite"


def _lean(p, v):
    return (p[0] + v["lean"] * p[2], p[1], p[2])


def build_rock(v, jitter=True):
    """The rock as one closed ring stack: side bands, a top cap, a base cap."""
    r = _Rng(v["seed"])
    ang, bias = _columns(v, r)
    rings = _rings(v, ang, bias, r, jitter)
    n, h = v["sides"], v["height"]
    m = _Mesh()
    ids = [[m.v(_lean(p, v)) for p in ring] for ring in rings]

    for k in range(len(rings) - 1):
        for i in range(n):
            q = (i + 1) % n
            am = 0.5 * (ang[i] + ang[q] + (2.0 * math.pi if q == 0 else 0.0))
            want = (math.cos(am) / v["rx"], math.sin(am) / v["ry"], 0.0)
            idx = [ids[k][i], ids[k][q], ids[k + 1][q], ids[k + 1][i]]
            m.quad(idx[0], idx[1], idx[2], idx[3], want,
                   _zone_of(m, idx, 0.5 * (bias[i] + bias[q]), v["moss_cos"], v["r_bias"]))

    crest = m.v(_lean((0.0, 0.0, h - v["tilt"] * v["rx"]), v))
    for i in range(n):
        m.tri(crest, ids[-1][i], ids[-1][(i + 1) % n], UP, "moss")
    foot = m.v((0.0, 0.0, 0.0))
    for i in range(n):
        m.tri(foot, ids[0][i], ids[0][(i + 1) % n], DOWN, "shade")
    return m


def build_collider(v):
    """The drawn columns and the drawn profile with the jitter zeroed and a flat
    top: the cover silhouette, with no facet to snag on."""
    return build_rock(v, jitter=False)


# =============================================================================
# UNWRAP -- per-face planar projection into a random window of its zone
# =============================================================================

def unwrap(ob, zones, seed=0):
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + seed * 7919 + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        u0, v0, u1, v1 = ZONES[zones[pi]]
        span_u = (u1 - u0) - 2.0 * UV_PAD
        span_v = (v1 - v0) - 2.0 * UV_PAD
        scale = TPM / ((u1 - u0) * TEX_SIZE)
        nrm = poly.normal
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
        fu = -1.0 if r.i(0, 1) else 1.0
        fv = -1.0 if r.i(0, 1) else 1.0
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        mi = min(co[ii] for co in cos)
        mj = min(co[jj] for co in cos)
        w = min((max(co[ii] for co in cos) - mi) * scale, 1.0)
        hh = min((max(co[jj] for co in cos) - mj) * scale, 1.0)
        ou = r.f() * (1.0 - w)
        ov = r.f() * (1.0 - hh)
        for li, co in zip(poly.loop_indices, cos):
            s = min(ou + (co[ii] - mi) * scale, 1.0)
            t = min(ov + (co[jj] - mj) * scale, 1.0)
            if fu < 0.0:
                s = 1.0 - s
            if fv < 0.0:
                t = 1.0 - t
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


# =============================================================================
# BUILD / RENDER / CHECK
# =============================================================================

def build():
    v = VARIANTS[variant_name()]
    m = build_rock(v)
    c = build_collider(v)

    albedo, emissive = paint_atlas()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)

    ob = m.object(OBJECT_NAME)
    unwrap(ob, m.zones)
    mdl.finish(ob, ft.atlas_material("ForestGranite", albedo, emissive), strip_uvs=False)

    coll = c.object(COLLIDER_NAME)
    coll.hide_render = True
    xs = [p[0] for p in m.verts]
    ys = [p[1] for p in m.verts]
    zs = [p[2] for p in m.verts]
    print("MDL STATS variant=%s visual_tris=%d collision_tris=%d "
          "width=%.2f depth=%.2f height=%.2f"
          % (variant_name(), len(ob.data.polygons), len(coll.data.polygons),
             max(xs) - min(xs), max(ys) - min(ys), max(zs)))
    return [ob, coll]


def add_proxy(spec, objects):
    """A 1.8 m block beside the rock, for the eye-level scale shot. It is made
    after the export, so it is rendered and never shipped; a `--cam` run asks
    for it, the named views do not."""
    if not spec.get("cams"):
        return
    v = VARIANTS[variant_name()]
    x0 = v["rx"] * 1.05 + 0.45
    hw, hd = 0.5 * PROXY_W, 0.5 * PROXY_D
    verts = [(x0 - hw, -hd, 0.0), (x0 + hw, -hd, 0.0), (x0 + hw, hd, 0.0), (x0 - hw, hd, 0.0),
             (x0 - hw, -hd, PROXY_H), (x0 + hw, -hd, PROXY_H),
             (x0 + hw, hd, PROXY_H), (x0 - hw, hd, PROXY_H)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
             (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    proxy = mdl.mesh("ScaleProxy", verts, faces)
    proxy.data.materials.append(mdl.flat_material("ProxyGrey", (0.30, 0.29, 0.27, 1.0)))
    objects.append(proxy)


def _check():
    import forest_check
    name = variant_name()
    v = VARIANTS[name]
    m = build_rock(v).compact()
    c = build_collider(v).compact()
    forest_check.prove(m, name)
    forest_check.prove(c, name + "_collider")
    for tag, mm in (("rock", m), ("coll", c)):
        zones = {}
        for z in mm.zones:
            zones[z] = zones.get(z, 0) + 1
        lo = [min(p[k] for p in mm.verts) for k in range(3)]
        hi = [max(p[k] for p in mm.verts) for k in range(3)]
        print("%s %s tris=%d width=%.2f depth=%.2f height=%.2f zones=%s"
              % (name, tag, len(mm.faces), hi[0] - lo[0], hi[1] - lo[1], hi[2],
                 dict(sorted(zones.items()))))
    gap = max(abs(a[k] - b[k]) for a, b in zip(m.verts, c.verts) for k in range(3))
    print("%s collider_max_offset=%.3f m" % (name, gap))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME + "_" + variant_name(), build,
                 facing_yaw=FACING_YAW, post=add_proxy)
