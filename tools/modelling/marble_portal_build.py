"""
PANOPTICON -- marble_portal: the way out of the ring on Map 2. Map 1's portal
is hell rock torn open round an ember; Map 2's rotunda is white marble, so the
same opening is DRESSED STONE -- an aedicule of the rotunda's own architecture
standing on the lane, with the finish's effect surface hung in its mouth.

The surround is the wall's vocabulary at prop scale: an ashlar PLINTH, two
FLUTED PILASTER JAMBS, an ARCHED HEAD on the rotunda's head radius, and a
CORNICE moulding over it. The plinth and the cornice are the proudest stone
(half depth 0.40); the pilaster fronts and the spandrel sit 0.10 back (0.30),
so the plinth washes and the cornice soffit are real surfaces, not a texture
saying so. Every inward face -- the jamb reveals, the arch soffit, the washes,
the soffit -- is "shade", the atlas cell the rotunda uses for every recess.

DROP-IN for portal.glb. scenes/ring/portal.tscn is NOT edited: its Gate Area3D
(a 4.0 x 3.6 x 1.0 box at local y 1.8) and its Glow omni at y 2.0 stay where
they are, so this model keeps portal_build's numbers to the centimetre --
4.5 x 4.0 x 0.8 m overall, a 2.7 m clear opening (IN_HALF_W 1.35), the head
springing at 2.6 and apexing at 3.15, the effect surface centred on 1.5.

Those three head numbers OVER-DETERMINE the arch: a true semicircle on a 1.35 m
half-span would crown at 3.95, not 3.15. The head is therefore the circular arc
that passes through all three -- radius 1.9318, which IS the rotunda's arch to
within 3.5 cm (mb.ARCH_W / 2 = 2.0), stilted rather than stopped. Six chords,
mb.HEAD_SEG, the same resolution as the wall's cells.

Origin = the base centre. Blender z = 0 is the ground the prop stands on;
Blender +Z -> Godot +Y, Blender +Y -> Godot -Z, Blender +X -> Godot +X. The
effect surface lies in the Blender XZ plane at y ~ 0 -- Godot local XY -- so a
runner passes through it along Godot local Z, exactly as on Map 1.

ONE CLOSED MANIFOLD SOLID. The opening is not a hole: the two effect-surface
faces stand at y = -0.02 and y = +0.02 and each side's reveal runs from its own
outer face IN to that plane, so the mouth is plugged by a 0.04 m lens and every
edge has exactly two faces. The surface is this module's own _paint_swirl --
Map 1's spiral in the rotunda's cold palette -- into marble's spare atlas cell
(2, 3), drawn with mb.stone_material at emission strength exactly 1.0.

MarblePortalCollision is a separate `-colonly` object: the marble uprights and
the arched head, the same silhouette extruded flat through the full 0.8 m. The
effect surface has NO collision -- a body walks through it, which is the point.

    python3 tools/modelling/marble_portal_build.py --check
    tools/modelling/model build marble_portal

The column-0 `import x_build as y` lines are what tools/modelling/model ships
to the PC: keep them at column 0.
"""

import math
import os
import sys

try:
    import bpy
except ImportError:
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, HERE + os.sep + "lib")

import marble_build as mb  # noqa: E402
# marble_build imports its two part modules at its foot; they ride along to the
# PC only when a column-0 `import x_build as y` names them in THIS script.
import marble_lane_build as _ml  # noqa: E402, F401
import marble_wall_build as _mw  # noqa: E402, F401

if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["views"] = ["threequarter", "front"]
    mdl.DEFAULTS["ground"] = True

# =============================================================================
# TUNABLES  (local z: the ground the prop stands on is 0)
# =============================================================================

NAME = "marble_portal"
OBJECT_NAME = "MarblePortal"
COLLIDER_NAME = "MarblePortalCollision-colonly"
FACING_YAW = 0.0
BEARING = 345.0             # the finish's game bearing on Map 2: the lane shot stands the prop there

HALF_W = 2.25               # 4.5 m wide, portal.glb's own footprint
HEIGHT = 4.0                # 4.0 m tall
HALF_D = 0.40               # 0.8 m deep: the plinth and the cornice, the proudest stone
FACE_D = 0.30               # the pilaster fronts and the spandrel, 0.10 m back from the plinth line
SURF_D = 0.02               # the effect surface: one face at -0.02, one at +0.02, the mouth plugged

IN_HALF_W = 1.35            # the opening: 2.7 m clear at the ground (portal_build's IN_HALF_W)
IN_SPRING = 2.6             # ... the head springs here (portal_build's IN_SPRING)
IN_APEX = 3.15              # ... and crowns here (portal_build's IN_SPRING + IN_RISE)
DISC_CENTRE_Z = 1.5         # the swirl's centre: the painter puts it at this height of the mouth
SWIRL_ARMS = 3              # the effect surface, Map 1's numbers: three arms ...
SWIRL_TURNS = 2.6           # ... wrapping this many times from the rim to the core ...
SWIRL_WIDTH = 0.42          # ... and this much of each band bright
ARCH_SEG = mb.HEAD_SEG      # 6 chords over the head, the wall's own resolution

PLINTH_H = 0.32             # the plinth's top wash: the base course the jambs stand on
CORN_Z = 3.52               # the cornice soffit: 0.48 m of moulding over it, 0.37 m over the crown

PORTAL_CELL = mb._cell(2, 3)   # marble's spare atlas cell, repainted as the swirl
mb.ZONES["portal"] = PORTAL_CELL
mb.FIT["portal"] = "uv"        # the whole effect surface onto the whole cell, no offset, no flip

# the head: the circle through (+-IN_HALF_W, IN_SPRING) and (0, IN_APEX)
_RISE = IN_APEX - IN_SPRING
ARCH_R = (IN_HALF_W ** 2 + _RISE ** 2) / (2.0 * _RISE)     # 1.9318: mb.ARCH_W / 2 to 3.5 cm
ARCH_CZ = IN_APEX - ARCH_R                                 # 1.2182: the springing centre
ARCH_A = math.asin(min(1.0, IN_HALF_W / ARCH_R))           # half the arc, off the vertical


def _arch():
    """The head, left springing to right springing: ARCH_SEG + 1 points."""
    pts = []
    for k in range(ARCH_SEG + 1):
        th = -ARCH_A + 2.0 * ARCH_A * k / ARCH_SEG
        pts.append((ARCH_R * math.sin(th), ARCH_CZ + ARCH_R * math.cos(th)))
    pts[0] = (-IN_HALF_W, IN_SPRING)            # snap the springings: they weld onto the jambs
    pts[-1] = (IN_HALF_W, IN_SPRING)
    return pts


ARCH = _arch()
APEX_K = ARCH_SEG // 2                          # 3: the crown, x = 0

# The mouth, as (x, z), left foot -> up the left jamb -> over the head -> down
# the right jamb -> right foot. The plinth's top is a point on each jamb: the
# reveal steps back there, because the plinth is prouder than the pilaster.
OUT = ([(-IN_HALF_W, 0.0), (-IN_HALF_W, PLINTH_H)] + ARCH
       + [(IN_HALF_W, PLINTH_H), (IN_HALF_W, 0.0)])
N_OUT = len(OUT)                                # 11 points, 10 reveal segments
PLINTH_SEGS = (0, N_OUT - 2)                    # the two segments that start at the plinth face
CROWN_K = 2 + APEX_K                            # OUT index of the crown
RING = OUT[CROWN_K:] + OUT[:CROWN_K]            # the surface's fan starts at the crown: no sliver


# =============================================================================
# TEXTURE -- marble's atlas, with the rotunda's own swirl in the spare cell
# =============================================================================

def _paint_swirl(c, r, box):
    """A spiral of pale blue-white arms on deep blue-grey, near-white core,
    dark rim. Emissive. Map 1's geometry, the rotunda's colour."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    cx = x0 + w / 2.0
    cy = y0 + h * (DISC_CENTRE_Z / IN_APEX)
    for y in range(y0, y1):
        for x in range(x0, x1):
            dx, dy = (x + 0.5 - cx) / (w / 2.0), (y + 0.5 - cy) / (h / 2.0)
            rad = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            band = (ang * SWIRL_ARMS / (2.0 * math.pi) + rad * SWIRL_TURNS) % 1.0
            band = min(band, 1.0 - band) * 2.0            # 0 on the arm, 1 between
            if rad < 0.14:
                col = r.pick([(236, 242, 252), (214, 226, 244)])
            elif band < SWIRL_WIDTH * (1.0 - 0.5 * rad):
                col = r.pick([(152, 164, 186), (136, 150, 176), (170, 182, 202)])
            elif band < SWIRL_WIDTH * (1.0 - 0.5 * rad) + 0.22:
                col = r.pick([(104, 110, 122), (92, 100, 114)])
            else:
                col = r.pick([(54, 58, 70), (46, 50, 60), (60, 64, 76)])
            if rad > 0.9:
                col = tuple(int(v * 0.45) for v in col)
            c.put(x, y, col, col)


def _paint_portal(c, r, box):
    """Nothing, on purpose. mb.paint_atlas() whites the two spare cells AFTER
    it walks ZONES, so the swirl has to be painted last -- _texture() does it.
    This stands in the PAINTERS table only so that walk finds a painter for the
    zone this module registers, and it draws NO random: every marble cell then
    comes out pixel for pixel the rotunda's own."""
    return


mb.PAINTERS["portal"] = _paint_portal


def _texture():
    """(albedo, emissive): marble's atlas with this module's swirl on top."""
    c = mb.paint_atlas()
    _paint_swirl(c, mb._Rng(mb.TEX_SEED), mb._rect_of(PORTAL_CELL, mb.TEX_SIZE))
    out = []
    for name, buf in ((mb.TEX_ALBEDO, c.alb), (mb.TEX_EMISSIVE, c.emi)):
        img = bpy.data.images.new(name, mb.TEX_SIZE, mb.TEX_SIZE, alpha=False)
        img.colorspace_settings.name = "sRGB"
        img.pixels.foreach_set(buf)
        img.update()
        out.append(img)
    return out[0], out[1]


# =============================================================================
# GEOMETRY
# =============================================================================

def _one_face(m, k0):
    """Every triangle emitted since face k0 shares one atlas window."""
    gid = m.groups[k0]
    for k in range(k0, len(m.groups)):
        m.groups[k] = gid


def _xz(m, pts, y):
    """Vertex ids for a list of (x, z) at depth y."""
    return [m.v((x, y, z)) for (x, z) in pts]


def _yz(m, pts, x):
    """Vertex ids for a list of (y, z) at x."""
    return [m.v((x, y, z)) for (y, z) in pts]


def _xy(m, pts, z):
    """Vertex ids for a list of (x, y) at z."""
    return [m.v((x, y, z)) for (x, y) in pts]


def _inward(mx, mz):
    """The mouth's inward normal at (mx, mz): toward the springing centre.
    On the jambs that is not the face normal, but it is on its side of the
    plane, which is all _emit needs to fix a winding."""
    return (-mx, 0.0, ARCH_CZ - mz)


def _face(m, s):
    """One side of the surround: s = -1.0 the front, +1.0 the back."""
    n = (0.0, s, 0.0)
    od, fd = s * HALF_D, s * FACE_D
    for sx in (-1.0, 1.0):
        xo, xi = sx * HALF_W, sx * IN_HALF_W
        # the plinth, at the proud line, and its top wash back to the pilaster
        m.quad(m.v((xo, od, 0.0)), m.v((xi, od, 0.0)),
               m.v((xi, od, PLINTH_H)), m.v((xo, od, PLINTH_H)), n, "plinth")
        m.quad(m.v((xo, od, PLINTH_H)), m.v((xi, od, PLINTH_H)),
               m.v((xi, fd, PLINTH_H)), m.v((xo, fd, PLINTH_H)), mb.UP, "shade")
        # the pilaster: one face, one flute window, with the springing carried
        # on its inner edge so the reveal and the spandrel meet it cleanly
        k0 = len(m.faces)
        m.poly(_xz(m, [(xo, PLINTH_H), (xi, PLINTH_H), (xi, IN_SPRING),
                       (xi, CORN_Z), (xo, CORN_Z)], fd), n, "column")
        _one_face(m, k0)
    # the spandrel over the head: fanned from the two upper corners, so the
    # cornice soffit above it needs splitting only at the jamb lines
    t0, t1 = m.v((-IN_HALF_W, fd, CORN_Z)), m.v((IN_HALF_W, fd, CORN_Z))
    a = _xz(m, ARCH, fd)
    k0 = len(m.faces)
    for k in range(APEX_K):
        m.tri(a[k], a[k + 1], t0, n, "marble")
    for k in range(APEX_K, ARCH_SEG):
        m.tri(a[k], a[k + 1], t1, n, "marble")
    m.tri(t0, a[APEX_K], t1, n, "marble")
    _one_face(m, k0)
    # the cornice: soffit back to the pilaster line, then the moulding's front
    xs = (-HALF_W, -IN_HALF_W, IN_HALF_W, HALF_W)
    for k in range(3):
        x0, x1 = xs[k], xs[k + 1]
        m.quad(m.v((x0, fd, CORN_Z)), m.v((x1, fd, CORN_Z)),
               m.v((x1, od, CORN_Z)), m.v((x0, od, CORN_Z)), mb.DOWN, "shade")
        m.quad(m.v((x0, od, CORN_Z)), m.v((x1, od, CORN_Z)),
               m.v((x1, od, HEIGHT)), m.v((x0, od, HEIGHT)), n, "band")
    # the reveal: every mouth segment, from its own outer face in to the
    # surface plane. The two that start on the plinth step at the pilaster
    # line, so the wash's inner edge has a face on both sides of it.
    for k in range(N_OUT - 1):
        (x0, z0), (x1, z1) = OUT[k], OUT[k + 1]
        w = _inward(0.5 * (x0 + x1), 0.5 * (z0 + z1))
        ys = [od, fd, s * SURF_D] if k in PLINTH_SEGS else [fd, s * SURF_D]
        for j in range(len(ys) - 1):
            m.quad(m.v((x0, ys[j], z0)), m.v((x1, ys[j], z1)),
                   m.v((x1, ys[j + 1], z1)), m.v((x0, ys[j + 1], z0)), w, "shade")
    # the effect surface: the mouth's own outline, one face, one atlas window
    m.poly(_xz(m, RING, s * SURF_D), n, "portal")


def _shell(m):
    """The four outside faces and the two caps: shared by front and back."""
    for sx in (-1.0, 1.0):
        x = sx * HALF_W
        w = (sx, 0.0, 0.0)
        k0 = len(m.faces)
        m.poly(_yz(m, [(-HALF_D, 0.0), (HALF_D, 0.0), (HALF_D, PLINTH_H),
                       (FACE_D, PLINTH_H), (-FACE_D, PLINTH_H),
                       (-HALF_D, PLINTH_H)], x), w, "plinth")
        _one_face(m, k0)
        m.quad(m.v((x, -FACE_D, PLINTH_H)), m.v((x, FACE_D, PLINTH_H)),
               m.v((x, FACE_D, CORN_Z)), m.v((x, -FACE_D, CORN_Z)), w, "marble")
        k0 = len(m.faces)
        m.poly(_yz(m, [(-HALF_D, HEIGHT), (-HALF_D, CORN_Z), (-FACE_D, CORN_Z),
                       (FACE_D, CORN_Z), (HALF_D, CORN_Z), (HALF_D, HEIGHT)], x), w, "band")
        _one_face(m, k0)
    xs = (-HALF_W, -IN_HALF_W, IN_HALF_W, HALF_W)
    for k in range(3):
        m.quad(m.v((xs[k], -HALF_D, HEIGHT)), m.v((xs[k + 1], -HALF_D, HEIGHT)),
               m.v((xs[k + 1], HALF_D, HEIGHT)), m.v((xs[k], HALF_D, HEIGHT)), mb.UP, "marble2")
    # the underside, capped: the two jamb feet, each carrying the reveal's and
    # the plug's depth stations on its inner edge, and the plug between them
    for sx in (-1.0, 1.0):
        xo, xi = sx * HALF_W, sx * IN_HALF_W
        inner = [(xi, y) for y in (-HALF_D, -FACE_D, -SURF_D, SURF_D, FACE_D, HALF_D)]
        if sx > 0.0:
            inner.reverse()
        ring = [(xo, -HALF_D if sx < 0.0 else HALF_D)] + inner + \
               [(xo, HALF_D if sx < 0.0 else -HALF_D)]
        k0 = len(m.faces)
        m.poly(_xy(m, ring, 0.0), mb.DOWN, "shade")
        _one_face(m, k0)
    m.quad(m.v((-IN_HALF_W, -SURF_D, 0.0)), m.v((IN_HALF_W, -SURF_D, 0.0)),
           m.v((IN_HALF_W, SURF_D, 0.0)), m.v((-IN_HALF_W, SURF_D, 0.0)), mb.DOWN, "shade")


def _stone():
    m = mb._Mesh()
    n0 = len(m.faces)
    _face(m, -1.0)
    n1 = len(m.faces)
    _face(m, 1.0)
    n2 = len(m.faces)
    _shell(m)
    return m, {"front": n1 - n0, "back": n2 - n1, "shell": len(m.faces) - n2}


# the collider's mouth: the same silhouette, no plinth step, no surface plane
COLL_OUT = [(-IN_HALF_W, 0.0)] + ARCH + [(IN_HALF_W, 0.0)]


def _collider():
    """The uprights and the arched head, extruded flat through the full depth.
    It matches the visual's silhouette; the effect surface is not in it."""
    c = mb._Mesh()
    for s in (-1.0, 1.0):
        y = s * HALF_D
        n = (0.0, s, 0.0)
        for sx in (-1.0, 1.0):
            xo, xi = sx * HALF_W, sx * IN_HALF_W
            c.poly(_xz(c, [(xo, 0.0), (xi, 0.0), (xi, IN_SPRING),
                           (xi, HEIGHT), (xo, HEIGHT)], y), n, "marble")
        t0, t1 = c.v((-IN_HALF_W, y, HEIGHT)), c.v((IN_HALF_W, y, HEIGHT))
        a = _xz(c, ARCH, y)
        for k in range(APEX_K):
            c.tri(a[k], a[k + 1], t0, n, "marble")
        for k in range(APEX_K, ARCH_SEG):
            c.tri(a[k], a[k + 1], t1, n, "marble")
        c.tri(t0, a[APEX_K], t1, n, "marble")
    for k in range(len(COLL_OUT) - 1):
        (x0, z0), (x1, z1) = COLL_OUT[k], COLL_OUT[k + 1]
        w = _inward(0.5 * (x0 + x1), 0.5 * (z0 + z1))
        c.quad(c.v((x0, -HALF_D, z0)), c.v((x1, -HALF_D, z1)),
               c.v((x1, HALF_D, z1)), c.v((x0, HALF_D, z0)), w, "marble")
    for sx in (-1.0, 1.0):
        x = sx * HALF_W
        c.quad(c.v((x, -HALF_D, 0.0)), c.v((x, HALF_D, 0.0)),
               c.v((x, HALF_D, HEIGHT)), c.v((x, -HALF_D, HEIGHT)), (sx, 0.0, 0.0), "marble")
        xi = sx * IN_HALF_W
        c.quad(c.v((x, -HALF_D, 0.0)), c.v((xi, -HALF_D, 0.0)),
               c.v((xi, HALF_D, 0.0)), c.v((x, HALF_D, 0.0)), mb.DOWN, "marble")
    xs = (-HALF_W, -IN_HALF_W, IN_HALF_W, HALF_W)
    for k in range(3):
        c.quad(c.v((xs[k], -HALF_D, HEIGHT)), c.v((xs[k + 1], -HALF_D, HEIGHT)),
               c.v((xs[k + 1], HALF_D, HEIGHT)), c.v((xs[k], HALF_D, HEIGHT)), mb.UP, "marble")
    return c


def head_radius_gap():
    """Metres this head's radius falls short of the rotunda's own (2.0)."""
    return mb.ARCH_W / 2.0 - ARCH_R


def gate_clearance():
    """The two numbers scenes/ring/portal.tscn depends on, as margins in metres.

    The Gate Area3D is a 4.0 x 3.6 x 1.0 box at local y 1.8 -- WIDER than the
    2.7 m mouth on purpose, since a body can only reach it through the mouth.
    What the stone must not do is (a) narrow the way a body walks in, or (b)
    stand outside the gate's 1.0 m depth, which would let a body touch marble
    without ever overlapping the gate. So: how much of the mouth is left over
    a 0.9 m runner at the axis, and how much of the gate's half depth is left
    over the deepest stone."""
    return 2.0 * IN_HALF_W - 0.9, 0.5 - HALF_D


# =============================================================================
# RENDERS
# =============================================================================

ROTUNDA_GLB = r"C:\Users\ddd\panopticon-modelling\jobs\marble\out\marble.glb"


def _rotunda():
    """The rotunda at identity, for the lane shot only."""
    made = []
    if not os.path.isfile(ROTUNDA_GLB):
        print("MDL note: no %s; skipping the lane shot" % ROTUNDA_GLB)
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=ROTUNDA_GLB)
    for ob in set(bpy.data.objects) - before:
        if "colonly" in ob.name:
            ob.hide_render = True
        made.append(ob)
    bpy.context.view_layer.update()
    return made


def _render(spec, objects):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE" if spec.get("engine", "eevee") != "cycles" else "CYCLES"
    mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 64)))
    mdl._try(scene.eevee, "use_shadows", True)
    mdl._try(scene.view_settings, "view_transform", "Standard")
    mdl._try(scene.view_settings, "exposure", 0.0)
    made = []
    world = bpy.data.worlds.new("Rotunda")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.40, 0.41, 0.44, 1.0)
    bg.inputs[1].default_value = 0.55
    target = mdl._link(bpy.data.objects.new("ShotTarget", None))
    cam = mdl._link(bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam")))
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    scene.camera = cam
    made += [target, cam]
    out_dir = spec.get("out_dir", ".")

    def shot(name, loc, tgt, lens, res):
        cam.data.lens = lens
        cam.data.clip_end = 600.0
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    # 1. the scale shot: a 1.8 m human proxy standing beside the jamb
    sd = bpy.data.lights.new("ScaleSun", type="SUN")
    sd.energy = 3.0
    sun = mdl._link(bpy.data.objects.new("ScaleSun", sd))
    sun.rotation_euler = (math.radians(55.0), 0.0, math.radians(35.0))
    made.append(sun)
    px = HALF_W + 0.75
    verts, faces = [], []
    for dz in (0.0, 1.8):
        for (dx, dy) in ((-0.3, -0.15), (0.3, -0.15), (0.3, 0.15), (-0.3, 0.15)):
            verts.append((px + dx, dy, dz))
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    proxy = mdl.mesh("PlayerProxy", verts, faces)           # 0.6 x 0.3 x 1.8 m, render only
    proxy.data.materials.append(mdl.flat_material("ProxyGreen", (0.1, 0.9, 0.2, 1.0)))
    made.append(proxy)
    shot("scale", (-2.6, -7.4, mb.EYE_H), (0.0, 0.0, 1.8), 34.0, (1300, 900))
    bpy.data.objects.remove(proxy, do_unlink=True)
    made.remove(proxy)
    bpy.data.objects.remove(sun, do_unlink=True)
    made.remove(sun)

    # 2. the lane shot: the prop on the marble lane at its scene transform
    company = _rotunda()
    if company is not None:
        made += company
        ld = bpy.data.lights.new("Lantern", type="POINT")
        ld.energy, ld.color, ld.shadow_soft_size = mb.REVIEW_LANTERN_W, mb.LANTERN_RGB, mb.LANTERN_SOFT
        lantern = mdl._link(bpy.data.objects.new("Lantern", ld))
        lantern.location = mb.pol(0.0, 0.0, mb.TOWER_Y + mb.LANTERN_H)
        made.append(lantern)
        for k in range(12):
            fd = bpy.data.lights.new("ReviewFill%d" % k, type="POINT")
            fd.energy, fd.color, fd.use_shadow = mb.REVIEW_FILL_W, (0.90, 0.91, 0.94), False
            f = mdl._link(bpy.data.objects.new("ReviewFill%d" % k, fd))
            f.location = mb.pol(k * 30.0 + 15.0, 50.0, 38.0)
            made.append(f)
        was = [(ob, tuple(ob.location), tuple(ob.rotation_euler)) for ob in objects]
        for ob in objects:
            ob.location = mb.pol(BEARING, mb.LANE_R, mb.DECK_Z)
            ob.rotation_euler = (0.0, 0.0, math.radians(-BEARING))
        bpy.context.view_layer.update()
        eye = mb.DECK_Z + mb.EYE_H
        shot("lane", mb.pol(BEARING + 22.0, mb.LANE_R, eye),
             mb.pol(BEARING, mb.LANE_R, mb.DECK_Z + 1.8), 30.0, (1400, 900))
        # the effect surface close up, and the same surface from the guard's
        # eye: it has to read from the tower as well as from the lane.
        surf_z = mb.DECK_Z + DISC_CENTRE_Z
        shot("surface", mb.pol(BEARING + 3.6, mb.LANE_R, surf_z),
             mb.pol(BEARING, mb.LANE_R, surf_z), 35.0, (1000, 1000))
        shot("tower", mb.pol(BEARING, 6.0, mb.TOWER_Y + 3.95),
             mb.pol(BEARING, mb.LANE_R, surf_z), 35.0, (1400, 900))
        for (ob, loc, rot) in was:                  # the default views frame the prop at the origin
            ob.location, ob.rotation_euler = loc, rot
        bpy.context.view_layer.update()
    for ob in made:
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    stone, counts = _stone()
    coll = _collider()
    albedo, emissive = _texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    ob = stone.object(OBJECT_NAME)
    mb.unwrap(ob, stone.zones, stone.groups, seed=11)
    mdl.finish(ob, mb.stone_material("Marble", albedo, emissive), strip_uvs=False)
    coll_ob = coll.object(COLLIDER_NAME)          # Godot: StaticBody3D + ConcavePolygonShape3D
    coll_ob.hide_render = True
    a = mb.audit(stone, "portal")
    gw, gh = gate_clearance()
    print("MDL STATS visual_tris=%d collision_tris=%d front=%d back=%d shell=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons),
             counts["front"], counts["back"], counts["shell"]))
    print("MDL STATS contiguity components=%d boundary=%d doubled=%d over=%d degenerate=%d dup_pos=%d"
          % (a["components"], a["boundary_edges"], a["doubled_edges"], a["over_edges"],
             a["degenerate"], a["duplicate_positions"]))
    print("MDL STATS width=%.2f height=%.2f depth=%.2f clear_w=%.2f spring=%.2f apex=%.2f "
          "arch_r=%.4f rotunda_r=%.2f plinth=%.2f cornice=%.2f surface_z=%.2f gate_clear=%.2f,%.2f"
          % (2 * HALF_W, HEIGHT, 2 * HALF_D, 2 * IN_HALF_W, IN_SPRING, IN_APEX, ARCH_R,
             mb.ARCH_W / 2.0, PLINTH_H, CORN_Z, DISC_CENTRE_Z, gw, gh))
    return [ob, coll_ob]


def _check():
    """--check: build without Blender; prove one closed contiguous mesh."""
    stone, counts = _stone()
    coll = _collider()
    a = mb.audit(stone, "portal")
    c = mb.audit(coll, "coll")
    xs = [v[0] for v in stone.verts]
    ys = [v[1] for v in stone.verts]
    zs = [v[2] for v in stone.verts]
    print("counts=%s x=%.2f..%.2f y=%.2f..%.2f z=%.2f..%.2f loops=%s"
          % (counts, min(xs), max(xs), min(ys), max(ys), min(zs), max(zs),
             mb.boundary_loops(stone)[:3]))
    print("coll loops=%s" % (mb.boundary_loops(coll)[:3],))
    gw, gh = gate_clearance()
    print("head: %d chords on r %.4f (the rotunda's %.2f less %.3f), spring %.2f crown %.2f, "
          "cornice %.2f, clear %.2f x %.2f, gate clears by %.2f, %.2f"
          % (ARCH_SEG, ARCH_R, mb.ARCH_W / 2.0, head_radius_gap(), IN_SPRING, IN_APEX,
             CORN_Z, 2 * IN_HALF_W, IN_APEX, gw, gh))
    size = (abs(max(xs) - min(xs) - 2 * HALF_W) < 1e-9 and abs(max(zs) - HEIGHT) < 1e-9
            and abs(min(zs)) < 1e-9 and abs(max(ys) - min(ys) - 2 * HALF_D) < 1e-9)
    ok = a["components"] == 1 and a["boundary_edges"] == 0 and a["doubled_edges"] == 0 \
        and a["over_edges"] == 0 and a["degenerate"] == 0 and a["duplicate_positions"] == 0 \
        and c["components"] == 1 and c["boundary_edges"] == 0 and c["doubled_edges"] == 0 \
        and c["over_edges"] == 0 and c["degenerate"] == 0 and c["duplicate_positions"] == 0 \
        and size and gw > 0.0 and gh > 0.0
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_render)
