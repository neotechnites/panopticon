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

One tile, forest_tiles' rock: damp shade, lichen and moss are COLOR_0 tints
of it, so the rock belongs to the same forest and stays one surface.

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
import forest_tiles  # noqa: E402  the forest's tiles, tinted per zone
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
# BUILD / RENDER / CHECK
# =============================================================================

def build():
    v = VARIANTS[variant_name()]
    m = build_rock(v)
    c = build_collider(v)

    ob = m.object(OBJECT_NAME)
    forest_tiles.dress(ob, m.zones, "rock", prefix="ForestGranite")

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
