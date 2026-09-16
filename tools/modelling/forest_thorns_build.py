"""
PANOPTICON -- forest_thorns: ground-hugging thorn patches for Map 3.

Two placeable footprints of the SAME barbed brambles that fill the forest
pit. Nothing here invents a look: the plant is
``forest_pit_build._barbed_tube`` -- a three-sided tube whose every ring has
one vertex pushed out into a thorn, the side rotating ring to ring -- grown
out of a socketed ground quad exactly as the thicket's 1140 plants are, on
the forest atlas, in the thicket's own zone. Only the scale changes: these
are knee-high, so the heights, radii, thorns and ring pitch are the pit's
numbers divided by roughly ten (THORN_* below), and the rest is shared code.

    ForestThornsRound ... a disc ROUND_R * 2 across, for corners and gaps
    ForestThornsStrip ... STRIP_L x STRIP_W, for lining a lane

Both are authored at their own origin with the ground at z = 0, so either
node drops into a map at the transform Ryan puts it at.

THESE ARE A HAZARD, NOT COVER. At THORN_H they hide nobody (crouch cover is
1.3 m) and they are under the 1.11 m jump apex, so the 2 m strip is hopped
and the lane it lines is a choice, not a wall. The thorns themselves do not
hurt anybody: the shipped collider is a flat mat 0.06 m thick, the patch's
exact footprint, which you stand ON. What kills is a TrapVolume the map
scene puts over it -- see forest_thorns.contract.json for the node, the
size_metres and why a solid thorn bush would have been wrong.

The review half (the 1.8 m scale proxy, the shot from the lane) is at the
bottom of this file rather than beside it because tools/modelling/model ships
only sibling `*_build.py` files to the PC: a forest_thorns_review.py would
never arrive. hub_base_build.py keeps its own shots the same way.

    tools/modelling/model build forest_thorns --views threequarter,front
    python3 tools/modelling/forest_thorns_build.py --check
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

import forest_tree_build as ft  # noqa: E402  the atlas, the rng, the mesh, the unwrap
from forest_tree_build import _Mesh, _Rng, UP, add  # noqa: E402
import forest_pit_build as fp  # noqa: E402  the bramble generator itself
# _barbed_tube calls back into the module that owns the mesh (its _host) for
# the socket protocol. These three ARE that protocol, and they are the
# forest ground's own: importing them is what makes a thorn here identical
# to a thorn in the pit rather than a second implementation of one.
from forest_build import _patch_frame, _bridge_quality, _ring_at  # noqa: E402,F401

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "forest_thorns"
FACING_YAW = 0.0
SEED = 2270941                  # its own rng: editing the thorns diffs only the thorns

ROUND_NAME = "ForestThornsRound"
ROUND_COLLIDER = "ForestThornsRoundCollision-colonly"
STRIP_NAME = "ForestThornsStrip"
STRIP_COLLIDER = "ForestThornsStripCollision-colonly"

# ---- footprints: exact, because a scene volume has to match them ------------
ROUND_R = 1.25                  # 2.5 m across
ROUND_N = 16                    # columns: quads ~0.42 m on the rim, the thorns' sockets
ROUND_RINGS = (1.25, 0.88, 0.48)   # rim inward; a centre vertex closes it (a fan from a ring vertex is all slivers)
STRIP_L, STRIP_W = 6.0, 2.0
STRIP_COLS, STRIP_ROWS = 12, 4  # 0.5 m cells, so a thorn's socket is the same size in both footprints

PLATE_LIFT = 0.012              # the mat's rim over the ground it sits on: clears z-fighting, too low to trip on
PLATE_CROWN = 0.055             # ... rising to this in the middle: litter heaped, not a machined disc
PLATE_JITTER = 0.015            # interior vertices only; the rim stays exact so the footprint is a number
PLATE_ZONE = "earth"            # the pit's own earth: #4a3e2e / #44382a / #504432

# ---- the plants: forest_pit_build's brambles at knee height -----------------
# The pit's scrub is 2.5..6.5 m with r 0.2..0.08, thorns 0.35..0.65 out and a
# ring every 1.1 m. Everything below is that, to scale, so the silhouette is
# the same plant seen smaller and not a different one.
THORN_H = (0.60, 0.92)          # "about 0.8 m tall": the tallest tip still under the box the trap uses
THORN_R = (0.055, 0.042, 0.022)  # root, middle, tip
THORN_SPIKE = (0.09, 0.17)      # how far the barb vertex stands out: the pit's 1.6..3.1x the stem
THORN_STEP = 0.24               # metres between barbed rings -> 4 segments, 3 thorns a stem
THORN_LEAN = (0.35, 0.80)       # the tip sits this fraction of the height sideways: sprawling, not standing
THORN_DRIFT = (20.0, 90.0)      # degrees the lean swings round as it climbs, as the pit
THORN_WANDER = 0.035            # per-point jitter on the inner points
THORN_MARGIN = 0.17             # stems are confined this far inside the rim, so the BARBS end at it
ROUND_PLANTS = 20               # of ROUND_N * 2 = 32 sockets
STRIP_PLANTS = 34               # of STRIP_COLS * STRIP_ROWS = 48 sockets

COLLIDER_THICK = 0.06           # the mat you stand on. Not the bush: see the module docstring
COLLIDER_N = 12                 # sides of the round mat: cheap, and inside the drawn rim


# =============================================================================
# THE HOST -- what forest_pit_build's generator needs of whatever owns the mesh
# =============================================================================

class _Patch(object):
    """A mesh and nothing else. ``fp._barbed_tube`` reaches back through
    ``sys.modules[self.__class__.__module__]`` for the socket protocol, which
    is why this class lives in this file and not in a helper."""

    def __init__(self):
        self.m = _Mesh()


# =============================================================================
# THE GROUND MATS -- registered quads, which is what a thorn can be socketed to
# =============================================================================

def _plate_z(u, rng, edge):
    """Height of a mat vertex at crown factor ``u`` (0 at the rim, 1 in the
    middle). Rim vertices take no jitter: the footprint is a promise."""
    z = PLATE_LIFT + PLATE_CROWN * u
    return z if edge else z + rng.u(-PLATE_JITTER, PLATE_JITTER)


def _disc_plate(g, rng):
    """The round patch's mat: ROUND_RINGS lofted into quads, a centre fan.
    Returns the quads, each as (vertex ids, centroid)."""
    m = g.m
    rings = []
    for k, rad in enumerate(ROUND_RINGS):
        u = 1.0 - rad / ROUND_R
        ring = []
        for s in range(ROUND_N):
            a = 2.0 * math.pi * s / ROUND_N
            ring.append(m.v((rad * math.cos(a), rad * math.sin(a), _plate_z(u, rng, k == 0))))
        rings.append(ring)
    quads = []
    for j in range(len(rings) - 1):
        a, b = rings[j], rings[j + 1]
        for i in range(ROUND_N):
            q = (i + 1) % ROUND_N
            ids = (a[i], a[q], b[q], b[i])
            m.quad(ids[0], ids[1], ids[2], ids[3], UP, PLATE_ZONE)
            quads.append((ids, m.centroid(ids)))
    ft._cap(m, rings[-1], (0.0, 0.0, _plate_z(1.0, rng, False)), UP, PLATE_ZONE)
    return quads


def _strip_plate(g, rng):
    """The long strip's mat: a STRIP_COLS x STRIP_ROWS grid, crowned along
    both axes and falling to PLATE_LIFT on all four edges."""
    m = g.m
    grid = []
    for j in range(STRIP_ROWS + 1):
        y = -STRIP_W / 2.0 + STRIP_W * j / STRIP_ROWS
        row = []
        for i in range(STRIP_COLS + 1):
            x = -STRIP_L / 2.0 + STRIP_L * i / STRIP_COLS
            u = (1.0 - (2.0 * x / STRIP_L) ** 4) * (1.0 - (2.0 * y / STRIP_W) ** 2)
            edge = i in (0, STRIP_COLS) or j in (0, STRIP_ROWS)
            row.append(m.v((x, y, _plate_z(u, rng, edge))))
        grid.append(row)
    quads = []
    for j in range(STRIP_ROWS):
        for i in range(STRIP_COLS):
            ids = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
            m.quad(ids[0], ids[1], ids[2], ids[3], UP, PLATE_ZONE)
            quads.append((ids, m.centroid(ids)))
    return quads


# =============================================================================
# THE PLANTS
# =============================================================================

def _confine_disc(p):
    """Pull a stem point back inside the disc, less the barbs' reach. The
    pit does the same thing against its trunk: a plant that would leave the
    footprint leans along the rim instead of over it."""
    lim = ROUND_R - THORN_MARGIN
    rad = math.hypot(p[0], p[1])
    if rad <= lim or rad < 1e-9:
        return p
    return (p[0] * lim / rad, p[1] * lim / rad, p[2])


def _confine_strip(p):
    hx = STRIP_L / 2.0 - THORN_MARGIN
    hy = STRIP_W / 2.0 - THORN_MARGIN
    return (max(-hx, min(hx, p[0])), max(-hy, min(hy, p[1])), p[2])


def _thorn_path(rng, c, confine):
    """A stem out of ``c``: climbing to THORN_H, leaning sideways and twisting
    round as it climbs, jittered on its inner points, never leaving the
    footprint. forest_pit_build._plant_path with the pit's radius-driven
    height table and trunk clamp replaced by this patch's own."""
    h = rng.u(*THORN_H)
    lean = rng.u(*THORN_LEAN) * h
    a_lean = rng.u(0.0, 360.0)
    drift = rng.u(*THORN_DRIFT) * rng.pick((-1.0, 1.0))
    raw = [c, add(c, UP, 0.10)]
    steps = max(3, int(h / 0.22))
    for k in range(1, steps + 1):
        u = k / float(steps)
        a = math.radians(a_lean + drift * u)
        off = lean * u * u
        raw.append(confine((c[0] + off * math.cos(a), c[1] + off * math.sin(a), c[2] + h * u)))
    length = sum(math.sqrt(sum((raw[k][i] - raw[k - 1][i]) ** 2 for i in range(3)))
                 for k in range(1, len(raw)))
    npts = max(3, int(round(length / THORN_STEP)) + 1)
    path = fp._resample(raw, npts)
    for k in range(2, npts - 1):
        p = path[k]
        path[k] = confine((p[0] + rng.u(-1.0, 1.0) * THORN_WANDER,
                           p[1] + rng.u(-1.0, 1.0) * THORN_WANDER, p[2]))
    return path


def _grow(g, rng, quads, count, confine):
    """``count`` of ``quads`` chosen at random, one barbed bramble socketed
    into each. The mat's grid IS the spacing: one plant to a quad, never two.
    Returns how many took (a socket whose best bridging would fold is refused
    by the generator, and that plant is simply not grown)."""
    order = list(range(len(quads)))
    for k in range(len(order) - 1, 0, -1):          # deterministic Fisher-Yates
        j = rng.i(0, k)
        order[k], order[j] = order[j], order[k]
    spike, gate = fp.SPIKE, fp.SOCKET_MIN_DEG
    fp.SPIKE = THORN_SPIKE                          # the generator reads these off its module;
    try:                                            # a knee-high plant needs knee-high barbs
        grown = 0
        for idx in order[:count]:
            ids, c = quads[idx]
            path = _thorn_path(rng, c, confine)
            if fp._barbed_tube(g, rng, path, THORN_R, [ids], fp.STEM_ZONE) is not None:
                grown += 1
        return grown
    finally:
        fp.SPIKE, fp.SOCKET_MIN_DEG = spike, gate


def build_round():
    g = _Patch()
    rng = _Rng(SEED)
    grown = _grow(g, rng, _disc_plate(g, rng), ROUND_PLANTS, _confine_disc)
    return g.m, grown


def build_strip():
    g = _Patch()
    rng = _Rng(SEED + 1)
    grown = _grow(g, rng, _strip_plate(g, rng), STRIP_PLANTS, _confine_strip)
    return g.m, grown


# =============================================================================
# COLLIDERS -- the mat, not the bush
# =============================================================================

def _round_collider():
    """A flat disc mat at the patch's exact rim. You walk onto it; the thorns
    are not solid, because solid thorns would be cover the tower cannot see
    through and a wall the shipped bot brain would grind against."""
    c = _Mesh()
    ring = lambda z: [c.v((ROUND_R * math.cos(2.0 * math.pi * s / COLLIDER_N),
                           ROUND_R * math.sin(2.0 * math.pi * s / COLLIDER_N), z))
                      for s in range(COLLIDER_N)]
    lo, hi = ring(0.0), ring(COLLIDER_THICK)
    c.fan(hi, UP, PLATE_ZONE)
    c.fan(list(reversed(lo)), (0.0, 0.0, -1.0), PLATE_ZONE)
    for s in range(COLLIDER_N):
        q = (s + 1) % COLLIDER_N
        p = c.verts[lo[s]]
        c.quad(lo[s], lo[q], hi[q], hi[s], (p[0], p[1], 0.0), PLATE_ZONE)
    return c


def _strip_collider():
    """The same mat, rectangular: a 12-triangle slab on the strip's exact
    footprint, which is also the footprint the scene's TrapVolume takes."""
    c = _Mesh()
    hx, hy, t = STRIP_L / 2.0, STRIP_W / 2.0, COLLIDER_THICK
    lo = [c.v(p) for p in ((-hx, -hy, 0.0), (hx, -hy, 0.0), (hx, hy, 0.0), (-hx, hy, 0.0))]
    hi = [c.v(p) for p in ((-hx, -hy, t), (hx, -hy, t), (hx, hy, t), (-hx, hy, t))]
    c.quad(hi[0], hi[1], hi[2], hi[3], UP, PLATE_ZONE)
    c.quad(lo[0], lo[1], lo[2], lo[3], (0.0, 0.0, -1.0), PLATE_ZONE)
    for s in range(4):
        q = (s + 1) % 4
        mid = c.centroid((lo[s], lo[q]))
        c.quad(lo[s], lo[q], hi[q], hi[s], (mid[0], mid[1], 0.0), PLATE_ZONE)
    return c


# =============================================================================
# BUILD / CHECK
# =============================================================================

def build():
    albedo, emissive = ft.sheet("forest_atlas", ft.paint_atlas)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    mat = ft.atlas_material("ForestAtlasThorns", albedo, emissive)
    out = []
    stats = []
    for (obj_name, coll_name, builder, collider) in (
            (ROUND_NAME, ROUND_COLLIDER, build_round, _round_collider),
            (STRIP_NAME, STRIP_COLLIDER, build_strip, _strip_collider)):
        m, grown = builder()
        zones = [z for z in m.zones if z is not None]
        ob = m.object(obj_name)
        ft.unwrap(ob, zones)
        mdl.finish(ob, mat, strip_uvs=False)
        co = collider().object(coll_name)
        co.hide_render = True
        out += [ob, co]
        stats.append((obj_name, len(ob.data.polygons), len(co.data.polygons), grown))
    for (n, t, ct, grown) in stats:
        print("MDL STATS %s visual_tris=%d collision_tris=%d thorns=%d" % (n, t, ct, grown))
    print("MDL STATS round_m=%.2f strip_m=%.1fx%.1f thorn_h=%.2f..%.2f"
          % (ROUND_R * 2.0, STRIP_L, STRIP_W, THORN_H[0], THORN_H[1]))
    return out


def _check():
    import forest_check
    for (label, builder, collider) in (("round", build_round, _round_collider),
                                       ("strip", build_strip, _strip_collider)):
        m, grown = builder()
        m.compact()
        forest_check.prove(m, label)
        cm = collider().compact()
        lo = [min(v[k] for v in m.verts) for k in range(3)]
        hi = [max(v[k] for v in m.verts) for k in range(3)]
        zones = {}
        for z in m.zones:
            zones[z] = zones.get(z, 0) + 1
        print("%s tris=%d verts=%d thorns=%d collider_tris=%d zones=%s bbox=%s..%s"
              % (label, len(m.faces), len(m.verts), grown, len(cm.faces), zones,
                 ["%.3f" % x for x in lo], ["%.3f" % x for x in hi]))


# =============================================================================
# REVIEW -- render-only: the scale proxy and the shot from the lane
# =============================================================================
# mdl exports the .glb BEFORE it calls post, so nothing below can reach the
# game. It answers the two questions the default orbit views cannot: is it the
# right SIZE (a 1.8 m proxy stands beside it) and does it read FROM THE LANE
# (one shot from a prisoner's eye, looking down at a knee-high hazard -- the
# only angle anyone will ever see it from). The rig is hub_base_build.py's
# shot() approach verbatim, so the two scripts' reviews compare side by side.

SHOT_NAME = "eye"               # -> forest_thorns_eye.png
REVIEW_OFFSET = (5.0, 0.0, 0.0)  # both patches are authored on x = y = 0, so for a render
                                 # they would sit inside one another: the strip is stood off
                                 # +X by its half-length plus the disc's radius plus a gap
PROXY_NAME = "ScaleProxy"
PROXY_WDH = (0.45, 0.30, 1.80)  # shoulders, chest, the game's character height
PROXY_AT = (5.0, -1.9)          # on the strip's centre line, 0.9 m clear of its y edge
PROXY_GREY = (0.42, 0.42, 0.44, 1.0)   # darker than the ground, lighter than the thorns
PROXY_ROUGHNESS = 0.95          # dead matte: a specular hit would imply it is a real prop
EYE_H = 1.65                    # the proxy's eye, as hub_base_build.py
CAM_LOC = (11.0, -6.0, EYE_H)   # stood on the lane 9.5 m off, oblique to the strip: it runs
                                # away to the left, the proxy is beside it and the disc beyond,
                                # so one frame answers "how tall" and "how much lane does it eat"
CAM_TGT = (3.5, -0.2, 0.70)     # between the two patches, at thorn height
CAM_LENS = 38.0                 # ~51 deg horizontal. The layout subtends 30 deg from CAM_LOC,
                                # so nothing is near an edge; shorter than this starts to
                                # flatter the footprint, which on a hazard would be a lie
SHOT_RES = (1400, 900)          # the lane is wide, not tall
REVIEW_SUN = 3.0                # hard key, so the thorns cast separable shadows
REVIEW_WORLD = 1.0              # ambient enough that the shadow sides stay readable
REVIEW_EXPOSURE = 0.6           # the Standard transform clips at 1.0 on flat colours
REVIEW_SKY = (0.50, 0.48, 0.47, 1.0)   # neutral: no cast on a grey proxy
SUN_LOC = (-6.0, -14.0, 16.0)   # over the camera's left shoulder: shadows fall toward us
SUN_AIM = (3.0, 0.0, 0.4)       # between the two patches
SUN_COLOR = (1.0, 0.96, 0.92)


def _proxy():
    """A 1.8 m box on the ground beside the strip, feet at z 0 -- the whole
    comparison rests on it starting where the thorns start."""
    w, d, h = PROXY_WDH
    x0, x1 = PROXY_AT[0] - w * 0.5, PROXY_AT[0] + w * 0.5
    y0, y1 = PROXY_AT[1] - d * 0.5, PROXY_AT[1] + d * 0.5
    verts = [(x0, y0, 0.0), (x1, y0, 0.0), (x1, y1, 0.0), (x0, y1, 0.0),
             (x0, y0, h), (x1, y0, h), (x1, y1, h), (x0, y1, h)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7),
             (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return mdl.finish(mdl.mesh(PROXY_NAME, verts, faces),
                      mdl.flat_material(PROXY_NAME, PROXY_GREY, roughness=PROXY_ROUGHNESS))


def _eye_shot(spec):
    """One hand-placed perspective render, then the rig is torn back down:
    mdl.render() builds its own world, lights and camera for the named views
    the moment post returns, and a leftover sun would light those twice."""
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
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")
    was_exposure = getattr(scene.view_settings, "exposure", 0.0)   # setup_scene sets the
    mdl._try(scene.view_settings, "exposure", REVIEW_EXPOSURE)     # transform, never this

    world = bpy.data.worlds.new("ThornsReview")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = REVIEW_SKY
    bg.inputs[1].default_value = REVIEW_WORLD

    sd = bpy.data.lights.new("ThornsSun", type="SUN")
    sd.energy, sd.color = REVIEW_SUN, SUN_COLOR
    sun = mdl._link(bpy.data.objects.new("ThornsSun", sd))
    aim = mdl._link(bpy.data.objects.new("ThornsAim", None))
    sun.location = SUN_LOC
    aim.location = SUN_AIM
    con = sun.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"

    target = mdl._link(bpy.data.objects.new("ThornsTarget", None))
    cam = mdl._link(bpy.data.objects.new("ThornsCam", bpy.data.cameras.new("ThornsCam")))
    was_camera = scene.camera
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    cam.data.type = "PERSP"
    cam.data.lens = CAM_LENS
    cam.location = CAM_LOC
    target.location = CAM_TGT
    scene.render.resolution_x, scene.render.resolution_y = SHOT_RES
    bpy.context.view_layer.update()          # TRACK_TO has not solved yet

    out_dir = spec.get("out_dir", ".")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "%s_%s.png" % (NAME, SHOT_NAME))
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("MDL RENDER %s (hand-placed camera, eye z=%.2f lens=%.0f)"
          % (os.path.basename(path), EYE_H, CAM_LENS))

    for ob in (cam, target, sun, aim):
        bpy.data.objects.remove(ob, do_unlink=True)
    scene.camera = was_camera
    mdl._try(scene.view_settings, "exposure", was_exposure)


def _review(spec, objects):
    """mdl.main(post=...): lay the two patches out side by side, stand a proxy
    beside them and take the shot from the lane. Render-only, every bit of it."""
    for ob in objects:
        if ob.name == STRIP_NAME:
            ob.location = REVIEW_OFFSET
            print("MDL note: %s offset to %r for the renders only" % (STRIP_NAME, REVIEW_OFFSET))
    objects.append(_proxy())     # the named views want the scale as much as the eye shot
    bpy.context.view_layer.update()
    _eye_shot(spec)


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_review)
