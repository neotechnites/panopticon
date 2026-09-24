"""
PANOPTICON -- marble_spikes: a placeable patch of the rotunda's spike floor.

Ryan places these by hand on the marble gallery walkway. They are the SAME
spikes that carpet the pit 24 m below (marble_build.SPIKE_H / BASE_K /
SMALL_EVERY, marble_lane_build's pedestal-ring-and-pyramid cell), lifted out
of the floor and set on a thin slab so a patch of the pit can be dropped
anywhere on the lane.

TWO FOOTPRINTS, ONE SCRIPT -- `--variant`:

    round   a hexagonal patch 2.50 m across the corners (r 1.25), six cells
            round a small bare hub. Built as `marble_spikes`.
    strip   a 6.0 x 2.0 m bar, seven cells by two: a spiked threshold across
            a lane. Built as `marble_spikes_strip` (marble_spikes_strip_build.py
            is a four-line shim that calls run("strip", ...) here).

ORIGIN IS THE BASE CENTRE: Blender z = 0 is the gallery floor the slab sits
on, so the scene drops it at the walkway's own y and nothing else. Blender
+Z -> Godot +Y, +Y -> Godot -Z.

    slab .......  z 0.00 .. 0.10   (SLAB_T: thin, it reads as floor)
    pedestal ...  z 0.10 .. 0.22   (PEDESTAL: the pit's own plinth)
    spikes .....  cones 1.2 .. 2.2 m tall; tips at most z 2.42

HAZARD, NOT COVER. The collider is the SLAB ONLY -- the footprint prism,
0.10 m tall, purpose-built and shipped as a `-colonly` node. The spikes are
not colliders, exactly as they are not in the pit: a body runs onto the patch
and the scene's lethal volume kills it. The volume the map scene must put
over each footprint is written into the contract file.

Palette and atlas: marble_build's, imported, not copied -- one painted 256 px
atlas, zones "field" (the pit floor's stone: slab top and every pedestal),
"spike", "plinth" (the slab's side) and "shade" (its underside). Sampled off
the Temple of Time; see docs/maps/marble.md.

ONE CONTIGUOUS MESH. mb._Mesh.v() is the welding registry: the spikes are
stitched into the slab top's own cells (a cell becomes a pedestal ring and a
pyramid, the pit's construction), the skirt is built from the same grid-line
expressions as the top, and mb.audit() proves it -- one component, no
duplicate positions, no doubled or over-used edges, no boundary edge, no
degenerate face.

    python3 tools/modelling/marble_spikes_build.py --check
    python3 tools/modelling/marble_spikes_build.py --check --variant strip
    tools/modelling/model build marble_spikes
    tools/modelling/model build marble_spikes_strip
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

import marble_build as mb  # noqa: E402

if bpy is not None:
    import mdl  # noqa: E402
    # marble_build is a closed rotunda and turns the outside views off when it
    # is imported. This is a prop: give it back a prop's defaults.
    mdl.DEFAULTS["ground"] = True
    mdl.DEFAULTS["world_grey"] = 0.16
    mdl.DEFAULTS["world_strength"] = 0.45
    mdl.DEFAULTS["views"] = ["front", "threequarter"]

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "marble_spikes"
VARIANT = "round"
OBJECT_NAME = "MarbleSpikes"
COLLIDER_NAME = "MarbleSpikesCollision-colonly"
FACING_YAW = 0.0

SLAB_T = 0.10               # the base slab: thin, so the patch sits flush
PEDESTAL = 0.12             # marble_lane_build's: every spike stands on a plinth

# The spikes. Height is Ryan's 1.2 .. 2.2 m; everything about the SHAPE --
# the taper, the small spike at every third foot -- is the pit's, imported.
SPIKE_H = (1.2, 2.2)
H_JITTER = (0.85, 1.15)     # marble_lane_build's, then clamped back into SPIKE_H
BASE_FRAC = 0.48            # base half-width never over this of the cell's smaller side.
                            # The pit uses 0.40 across 2.6 m cells; a patch cell is
                            # 0.79 .. 1.00 m and needs 0.48 to carry a 2.2 m spike.
CENTRE_JIT = 0.6            # marble_lane_build's: the base wanders in the slack
MIN_CELL = 0.55             # no spike in a cell narrower than this
SPIKE_P = 1.0               # every cell. A patch is a hazard, and a bare cell in a
                            # 2.5 m patch is a foothold; the pit's clumping field is a
                            # 90 m effect and says nothing at this size.
SPIKE_SEED = 4417709

# ---- round: a hexagon 2.50 m across the corners ----------------------------
ROUND_R = 1.25
ROUND_HUB = 0.25            # the bare middle; cells run from here to the rim
ROUND_N = 6                 # cells round the ring: 1.00 m deep, 0.79 m wide

# ---- strip: 6.0 x 2.0 m, seven cells by two --------------------------------
STRIP_L, STRIP_W = 6.0, 2.0
STRIP_NX, STRIP_NY = 7, 2

UP, DOWN = mb.UP, mb.DOWN
TWO_PI = mb.TWO_PI


# =============================================================================
# THE SPIKE -- marble_lane_build._Spikes.cell, freed of the pit's polar cell
#
# Identical construction and identical proportions: the cell's four corners
# rise as a pedestal ring to a square base, and four triangles close on the
# apex. The pit addressed its cells by (radius, angle); a patch cell is any
# convex quad, so the basis is the cell's own two mid-edge directions. The
# pit's radial-band gate and its clumping field are the floor's business and
# are not here; nothing else changed.
# =============================================================================

class _Spikes(object):
    def __init__(self, seed=SPIKE_SEED):
        self.r = mb._Rng(seed)
        self.count = self.small = 0
        self.tip_max = -9.9
        self.tip_min = 9.9

    def cell(self, m, a, b, c, d, z0):
        """Decide and build the spike for one slab-top cell, welded into the
        four corner vertices a,b,c,d (in order around the cell). Returns False
        if the cell stays a plain quad -- the caller emits it."""
        r = self.r
        pa, pb, pc, pd = m.verts[a], m.verts[b], m.verts[c], m.verts[d]
        cx = 0.25 * (pa[0] + pb[0] + pc[0] + pd[0])
        cy = 0.25 * (pa[1] + pb[1] + pc[1] + pd[1])
        ux = 0.5 * (pb[0] + pc[0]) - 0.5 * (pa[0] + pd[0])
        uy = 0.5 * (pb[1] + pc[1]) - 0.5 * (pa[1] + pd[1])
        vx = 0.5 * (pc[0] + pd[0]) - 0.5 * (pa[0] + pb[0])
        vy = 0.5 * (pc[1] + pd[1]) - 0.5 * (pa[1] + pb[1])
        width = math.hypot(ux, uy)
        depth = math.hypot(vx, vy)
        if min(width, depth) < MIN_CELL:
            return False
        eu = (ux / width, uy / width)
        ev = (vx / depth, vy / depth)
        if r.f() > SPIKE_P:
            return False
        zb = z0 + PEDESTAL
        h = SPIKE_H[0] + (SPIKE_H[1] - SPIKE_H[0]) * r.f()
        h *= H_JITTER[0] + (H_JITTER[1] - H_JITTER[0]) * r.f()
        h = max(SPIKE_H[0], min(h, SPIKE_H[1]))
        small = (self.count + 1) % mb.SMALL_EVERY == 0    # every third spike is a small one
        if small:
            h *= mb.SMALL_H
        bw = mb.BASE_K[0] + mb.BASE_K[1] * h
        cap = BASE_FRAC * min(width, depth)
        if bw > cap:                                      # a fat spike in a small cell: shrink it whole
            bw = cap
            h = (bw - mb.BASE_K[0]) / mb.BASE_K[1]
        if h < 0.3:
            return False
        ou = CENTRE_JIT * (0.5 * width - bw) * r.sf()
        ov = CENTRE_JIT * (0.5 * depth - bw) * r.sf()
        bx = cx + eu[0] * ou + ev[0] * ov
        by = cy + eu[1] * ou + ev[1] * ov

        def at(su, sv):
            return (bx + eu[0] * su * bw + ev[0] * sv * bw,
                    by + eu[1] * su * bw + ev[1] * sv * bw, zb)

        b0, b1, b2, b3 = m.v(at(-1, -1)), m.v(at(1, -1)), m.v(at(1, 1)), m.v(at(-1, 1))
        m.quad(a, b, b1, b0, UP, "field")                 # the pedestal ring, rising to the base
        m.quad(b, c, b2, b1, UP, "field")
        m.quad(c, d, b3, b2, UP, "field")
        m.quad(d, a, b0, b3, UP, "field")
        apex = m.v((bx, by, zb + h))
        for (p, q, w) in ((b0, b1, (-ev[0], -ev[1])), (b1, b2, eu),
                          (b2, b3, ev), (b3, b0, (-eu[0], -eu[1]))):
            m.tri(p, q, apex, (w[0], w[1], 0.3), "spike")
        tip = zb + h
        self.count += 1
        self.small += 1 if small else 0
        self.tip_max = max(self.tip_max, tip)
        self.tip_min = min(self.tip_min, tip)
        return True


# =============================================================================
# ROUND -- a hexagon: a bare hub, one ring of ROUND_N cells, a skirt
# =============================================================================

def _ra(i):
    """The ring's station angles: one expression, so hub, top, rim and skirt
    all land on the same floats and mb._Mesh.v welds them."""
    return TWO_PI * i / ROUND_N


def _rp(i, rad, z):
    a = _ra(i)
    return (rad * math.cos(a), rad * math.sin(a), z)


def round_top(m, sp):
    """The slab top at z = SLAB_T: a hub fan inside ROUND_HUB, then one ring of
    ROUND_N cells out to ROUND_R, each a plain quad or a stitched spike."""
    z = SLAB_T
    hub = [m.v(_rp(i, ROUND_HUB, z)) for i in range(ROUND_N)]
    rim = [m.v(_rp(i, ROUND_R, z)) for i in range(ROUND_N)]
    m.fan(hub, UP, "field")
    for i in range(ROUND_N):
        j = (i + 1) % ROUND_N
        if not sp.cell(m, hub[i], hub[j], rim[j], rim[i], z):
            m.quad(hub[i], hub[j], rim[j], rim[i], UP, "field")
    return ROUND_N


def round_skirt(m):
    """The slab's side (z 0 .. SLAB_T, "plinth") and its closed underside
    ("shade"). Rim vertices come from _rp, so they are the top's own."""
    top = [m.v(_rp(i, ROUND_R, SLAB_T)) for i in range(ROUND_N)]
    foot = [m.v(_rp(i, ROUND_R, 0.0)) for i in range(ROUND_N)]
    for i in range(ROUND_N):
        j = (i + 1) % ROUND_N
        am = _ra(i) + math.pi / ROUND_N          # NOT the mean: _ra wraps at the last station
        m.quad(foot[i], foot[j], top[j], top[i], (math.cos(am), math.sin(am), 0.0), "plinth")
    m.fan(foot, DOWN, "shade")


def round_collider(c):
    """The slab only: a closed hexagonal prism, r ROUND_R, 0 .. SLAB_T."""
    top = [c.v(_rp(i, ROUND_R, SLAB_T)) for i in range(ROUND_N)]
    foot = [c.v(_rp(i, ROUND_R, 0.0)) for i in range(ROUND_N)]
    for i in range(ROUND_N):
        j = (i + 1) % ROUND_N
        am = _ra(i) + math.pi / ROUND_N          # NOT the mean: _ra wraps at the last station
        c.quad(foot[i], foot[j], top[j], top[i], (math.cos(am), math.sin(am), 0.0), "field")
    c.fan(top, UP, "field")
    c.fan(foot, DOWN, "field")


# =============================================================================
# STRIP -- 6.0 x 2.0 m, STRIP_NX x STRIP_NY cells
# =============================================================================

def _sx(i):
    """A grid line along the strip: one expression, shared by top and skirt."""
    return -0.5 * STRIP_L + STRIP_L * i / float(STRIP_NX)


def _sy(j):
    return -0.5 * STRIP_W + STRIP_W * j / float(STRIP_NY)


def strip_top(m, sp):
    """STRIP_NX x STRIP_NY cells at z = SLAB_T. Returns the cell count."""
    n = 0
    for i in range(STRIP_NX):
        x0, x1 = _sx(i), _sx(i + 1)
        for j in range(STRIP_NY):
            y0, y1 = _sy(j), _sy(j + 1)
            a = m.v((x0, y0, SLAB_T))             # a,b along x; b,c along y
            b = m.v((x1, y0, SLAB_T))
            c = m.v((x1, y1, SLAB_T))
            d = m.v((x0, y1, SLAB_T))
            if not sp.cell(m, a, b, c, d, SLAB_T):
                m.quad(a, b, c, d, UP, "field")   # no spike here: plain deck
            n += 1
    return n


def strip_skirt(m):
    """The four sides (z 0 .. SLAB_T, "plinth") and the closed underside grid at
    z = 0 ("shade"). The rim verts are _sx/_sy values, so they are the very
    verts strip_top already made along the border: the shell closes with no
    seam split."""
    y_lo, y_hi = _sy(0), _sy(STRIP_NY)
    x_lo, x_hi = _sx(0), _sx(STRIP_NX)

    for i in range(STRIP_NX):                     # the two long sides
        x0, x1 = _sx(i), _sx(i + 1)
        for y, want in ((y_lo, (0.0, -1.0, 0.0)), (y_hi, (0.0, 1.0, 0.0))):
            m.quad(m.v((x0, y, SLAB_T)), m.v((x1, y, SLAB_T)),
                   m.v((x1, y, 0.0)), m.v((x0, y, 0.0)), want, "plinth")

    for j in range(STRIP_NY):                     # the two short ends
        y0, y1 = _sy(j), _sy(j + 1)
        for x, want in ((x_lo, (-1.0, 0.0, 0.0)), (x_hi, (1.0, 0.0, 0.0))):
            m.quad(m.v((x, y0, SLAB_T)), m.v((x, y1, SLAB_T)),
                   m.v((x, y1, 0.0)), m.v((x, y0, 0.0)), want, "plinth")

    for i in range(STRIP_NX):                     # the underside, same grid
        x0, x1 = _sx(i), _sx(i + 1)
        for j in range(STRIP_NY):
            y0, y1 = _sy(j), _sy(j + 1)
            m.quad(m.v((x0, y0, 0.0)), m.v((x1, y0, 0.0)),
                   m.v((x1, y1, 0.0)), m.v((x0, y1, 0.0)), DOWN, "shade")


def strip_collider(c):
    """The slab only: a closed box, +-STRIP_L/2 x +-STRIP_W/2 x 0 .. SLAB_T."""
    corners = ((_sx(0), _sy(0)), (_sx(STRIP_NX), _sy(0)),
               (_sx(STRIP_NX), _sy(STRIP_NY)), (_sx(0), _sy(STRIP_NY)))
    lo = [c.v((x, y, 0.0)) for x, y in corners]
    hi = [c.v((x, y, SLAB_T)) for x, y in corners]
    c.quad(hi[0], hi[1], hi[2], hi[3], UP, "field")
    c.quad(lo[0], lo[1], lo[2], lo[3], DOWN, "field")
    outward = ((0.0, -1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (-1.0, 0.0, 0.0))
    for k in range(4):
        n = (k + 1) % 4
        c.quad(hi[k], hi[n], lo[n], lo[k], outward[k], "field")


# =============================================================================
# RENDER HOOK -- one hand-placed scale shot, then out of the way
#
# mdl.main(..., post=_render) calls this BEFORE mdl renders its own two views,
# into a scene that has no camera, no world and no lights yet. So everything
# below is made here and every bit of it is destroyed here: mdl.setup_scene()
# then builds its own rig on a clean scene and the front / threequarter sheets
# come out exactly as they would if this hook did not exist.
#
# The shot answers one question a turntable cannot: is this thing the right
# SIZE. A 1.8 m green box stands one metre in front of the patch, the camera is
# a player's eye at 1.65 m, and the lens is 35 mm because that is roughly what
# the game's own FOV shows. Read the picture, not the bounding box.
# =============================================================================

PROXY_SIZE = (0.6, 0.3, 1.8)      # a body: shoulders, depth, height
PROXY_GAP = 0.5                   # metres clear of the footprint's +X edge: the
                                  # proxy stands BESIDE the patch, never in front
                                  # of it, or it hides the thing being measured
PROXY_RGB = (0.14, 0.85, 0.24, 1.0)
EYE_H = 1.65                      # camera height: the player's eye
CAM_LENS = 35.0
CAM_RES = (1400, 800)
CAM_HALF_TAN = 0.5139             # tan of 35 mm's half-angle across a 36 mm gate
CAM_PAD = 1.0                     # metres of air past the widest thing in frame
AIM_Z = 1.05                      # aim at the middle of a spike, not at its tip
KEY_W = 4.0                       # sun, shadowed: the one that models the cones
FILL_W = 1.1                      # sun, unshadowed, from behind-right
WORLD_RGB = (0.54, 0.55, 0.58, 1.0)
WORLD_W = 0.55                    # pale stone against pale air, no blown highlights
GROUND_RGB = (0.34, 0.34, 0.36, 1.0)


def _render(spec, objects):
    """Hand-placed scale shot: the patch with a 1.8 m body proxy beside it.

    Everything this makes -- proxy, camera, target, lights, world -- is removed
    before returning, because mdl's own two views render straight after.
    """
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
    mdl._try(scene.view_settings, "exposure", 0.0)

    made = []

    # ---- the body proxy: 0.6 x 0.3 x 1.8 m, standing ON the floor (z = 0),
    # one metre clear of the footprint's -Y edge so it never hides a spike.
    sx, sy, sz = PROXY_SIZE
    px = HALF_X + PROXY_GAP + 0.5 * sx
    proxy = mdl.box("ScaleProxy",
                    (px - 0.5 * sx, -0.5 * sy, 0.0),
                    (px + 0.5 * sx, 0.5 * sy, sz))
    proxy.data.materials.append(mdl.flat_material("ScaleProxyGreen", PROXY_RGB,
                                                  roughness=0.85))
    made.append(proxy)

    # ---- a floor. mdl.setup_scene() lays its own for the two sheets that
    # follow, but this shot happens before that, and a patch that MEANS "the
    # ground you are about to run over" cannot be photographed floating.
    ground = mdl.box("ScaleGround", (-40.0, -40.0, -0.04), (40.0, 40.0, 0.0))
    ground.data.materials.append(mdl.flat_material("ScaleGroundGrey", GROUND_RGB))
    made.append(ground)

    # ---- light: one shadowed key down the front-left, one unshadowed fill from
    # behind-right so the far side of a cone is grey rather than black. Sun, not
    # area: a 2.5 m prop lit by an area lamp reads as a lamp-lit tabletop model.
    kd = bpy.data.lights.new("ScaleKey", type="SUN")
    kd.energy = KEY_W
    kd.color = (1.0, 0.98, 0.95)
    kd.angle = math.radians(3.0)
    key = mdl._link(bpy.data.objects.new("ScaleKey", kd))
    key.rotation_euler = (math.radians(52.0), 0.0, math.radians(-35.0))
    made.append(key)

    fd = bpy.data.lights.new("ScaleFill", type="SUN")
    fd.energy = FILL_W
    fd.color = (0.90, 0.92, 0.97)
    mdl._try(fd, "use_shadow", False)
    fill = mdl._link(bpy.data.objects.new("ScaleFill", fd))
    fill.rotation_euler = (math.radians(-46.0), 0.0, math.radians(28.0))
    made.append(fill)

    world = bpy.data.worlds.new("ScaleAir")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = WORLD_RGB
    bg.inputs[1].default_value = WORLD_W

    # ---- camera: aimed with a TRACK_TO on an empty, never with typed euler.
    target = mdl._link(bpy.data.objects.new("ScaleTarget", None))
    cam = mdl._link(bpy.data.objects.new("ScaleCam", bpy.data.cameras.new("ScaleCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    made += [target, cam]
    out_dir = spec.get("out_dir", ".")
    os.makedirs(out_dir, exist_ok=True)

    def shot(name, loc, tgt, lens, res):
        cam.data.lens = lens
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()      # the constraint has not solved yet
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    # 35 mm at 1400x800 is a half-angle of 27.2 deg across (tan 0.5139) and
    # 16.4 deg up. The frame has to hold the patch AND the proxy beside it, so
    # the distance is computed from the footprint rather than typed: a hexagon
    # 2.5 m across and a 6 m strip then come out at the same size on the page,
    # which is the only way two renders of two footprints compare.
    right, left = px + 0.5 * sx, -HALF_X
    cx = 0.5 * (right + left)                    # the frame's own middle
    dist = (0.5 * (right - left) + CAM_PAD) / CAM_HALF_TAN
    shot("scale", (cx, -(HALF_Y + dist), EYE_H), (cx, 0.0, AIM_Z), CAM_LENS, CAM_RES)

    # ---- leave nothing behind. mdl.setup_scene() makes its own world, ground,
    # camera, target and three area lamps; a leftover sun or a leftover green
    # box would silently poison both of the sheets that follow.
    for ob in made:
        bpy.data.objects.remove(ob, do_unlink=True)
    scene.world = None
    bpy.data.worlds.remove(world, do_unlink=True)


# =============================================================================
# THE MODEL
# =============================================================================

VARIANTS = {
    "round": (round_top, round_skirt, round_collider, ROUND_R, ROUND_R),
    "strip": (strip_top, strip_skirt, strip_collider, 0.5 * STRIP_L, 0.5 * STRIP_W),
}

HALF_X, HALF_Y = ROUND_R, ROUND_R         # the render hook's framing; run() resets it


def _stone():
    top, skirt, _coll, _hx, _hy = VARIANTS[VARIANT]
    m = mb._Mesh()
    sp = _Spikes()
    cells = top(m, sp)
    skirt(m)
    info = {"cells": cells, "spikes": sp.count, "small": sp.small,
            "tip_lo": round(sp.tip_min, 3), "tip_hi": round(sp.tip_max, 3)}
    return m, info


def _collider():
    c = mb._Mesh()
    VARIANTS[VARIANT][2](c)
    return c


def _proof(a, label):
    """The contiguity bar: one component, welded, closed, clean."""
    return (a["components"] == 1 and a["duplicate_positions"] == 0
            and a["doubled_edges"] == 0 and a["over_edges"] == 0
            and a["degenerate"] == 0 and a["boundary_edges"] == 0)


def build():
    stone, info = _stone()
    coll = _collider()
    a = mb.audit(stone, "stone")
    ac = mb.audit(coll, "coll")
    albedo, emissive = mb._sheet("marble", mb.build_texture)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)

    ob = stone.object(OBJECT_NAME)
    mb.unwrap(ob, stone.zones, stone.groups)
    mdl.finish(ob, mb.stone_material("MarbleSpikes", albedo, emissive), strip_uvs=False)
    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True

    print("MDL STATS variant=%s visual_tris=%d collision_tris=%d"
          % (VARIANT, len(ob.data.polygons), len(coll_ob.data.polygons)))
    print("MDL STATS %s" % " ".join("%s=%s" % kv for kv in sorted(info.items())))
    print("MDL STATS contiguity components=%d manifold=%d boundary=%d doubled=%d over=%d degenerate=%d dup_pos=%d"
          % (a["components"], a["manifold_edges"], a["boundary_edges"], a["doubled_edges"],
             a["over_edges"], a["degenerate"], a["duplicate_positions"]))
    if not _proof(a, "stone") or not _proof(ac, "coll"):
        raise RuntimeError("%s: not one closed contiguous mesh" % NAME)
    return [ob, coll_ob]


def _check():
    """--check: build without Blender and prove the mesh is one contiguous model."""
    stone, info = _stone()
    coll = _collider()
    a = mb.audit(stone, "stone")
    ac = mb.audit(coll, "coll")
    print("%s %s" % (VARIANT, " ".join("%s=%s" % kv for kv in sorted(info.items()))))
    print("boundary loops: %s" % (mb.boundary_loops(stone)[:3],))
    lo = min(min(v[k] for v in stone.verts) for k in (0, 1))
    hi = max(max(v[k] for v in stone.verts) for k in (0, 1))
    print("footprint %.2f .. %.2f m   height %.2f m"
          % (lo, hi, max(v[2] for v in stone.verts)))
    ok = _proof(a, "stone") and _proof(ac, "coll")
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    if bpy is None:
        c = mb.paint_atlas()
        print("atlas %dx%d painted" % (c.w, c.h))
    return ok


def run(variant, name):
    """The entry point both variants use: marble_spikes_strip_build.py is a
    shim that calls run("strip", "marble_spikes_strip")."""
    global VARIANT, NAME, HALF_X, HALF_Y
    VARIANT, NAME = variant, name
    HALF_X, HALF_Y = VARIANTS[variant][3], VARIANTS[variant][4]
    if bpy is None or "--check" in sys.argv:
        return 0 if _check() else 1
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_render)
    return 0


if __name__ == "__main__":
    v = "round"
    if "--variant" in sys.argv:
        v = sys.argv[sys.argv.index("--variant") + 1]
    sys.exit(run(v, "marble_spikes" if v == "round" else "marble_spikes_" + v))
