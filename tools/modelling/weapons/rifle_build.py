"""
PANOPTICON -- the warden's rifle: an old-prison bolt-action, low-poly view model.

A long rifle with a heavy walnut stock, blued iron, a brass peep sight and a
hand-worn finish; institutional, not military. Marked with the panopticon's
eye stamped on the left of the receiver and a numbered brass plate let into
the left of the butt -- the side the shooter sees. The 128x128 PS1-style atlas
is painted procedurally here (hard texels, four palettes, no gradients) and
lands in weapons/textures/ as the albedo the .glb links; there is no emissive.

Run through the pipeline (from the Mac, from the repo root)::

    tools/modelling/model build rifle --views none --regen-texture all
    tools/modelling/model look  rifle --views side --res 1600x760

COORDINATES
-----------
Authored in BLENDER space, then glTF-exported (Blender X,Y,Z -> glTF X,Z,-Y):

    Blender +Y  ->  Godot -Z   (FORWARD, the muzzle direction)
    Blender +Z  ->  Godot +Y   (UP)
    Blender +X  ->  Godot +X   (RIGHT)

ORIGIN
------
(0,0,0) sits ON THE BORE LINE at the REAR FACE OF THE RECEIVER, where the
stock wrist meets it. y=0 is the bore, so the shot line is the model's own
local -Z axis and the peep sight sits directly above the origin; the stock
runs BACK into +Z (toward the camera) and the barrel FORWARD into -Z, so
parenting this under Head needs no rotation. The muzzle lands at a round
local (0, 0, -MUZZLE_Z) for the tracer origin. Centred on x=0 (bore
centreline): the game owns the hand offset.

TEXTURING
---------
One 128x128 atlas: walnut and blued steel in the top half (64x64 each), brass
and hand-worn walnut in the bottom left (32x64 each), and the two marks -- the
eye stamp and the number plate -- in the bottom right, reached only by the two
faces that FIT onto them. Every other face takes a random window of its
material's zone (per-face planar projection, long axis of the gun along u so
wood grain runs the length of the stock). Nearest filtering, one material.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import mdl  # noqa: E402

# =============================================================================
# TUNABLES -- everything adjustable lives in this block
# =============================================================================

NAME = "rifle"          # -> weapons/models/rifle.glb
OBJECT_NAME = "Rifle"   # the MeshInstance3D name weapons/rifle.tscn sees

# ---- material / texture -----------------------------------------------------
TEX_SIZE      = 128         # PS1 budget: one small square atlas
TEX_ALBEDO    = "rifle_hell_albedo"   # file name kept: the .tscn and the sheet know it
TEX_SEED      = 6660613
BODY_ROUGHNESS = 0.68
BODY_METALLIC  = 0.0
UV_SCALE      = 7.0         # texels-per-metre feel: face_size * UV_SCALE of a zone
UV_PAD        = 1.5 / TEX_SIZE   # half-texel gutter so zones never bleed

# Atlas zones as (u0, v0, u1, v1). v=0 is the BOTTOM row of the image.
ZONE_WALNUT = (0.0,  0.5, 0.5,  1.0)   # dark oiled walnut, grain along u
ZONE_BLUED  = (0.5,  0.5, 1.0,  1.0)   # blued steel, edge wear and pits
ZONE_BRASS  = (0.0,  0.0, 0.25, 0.5)   # turned brass, tarnish
ZONE_WORN   = (0.25, 0.0, 0.5,  0.5)   # walnut rubbed pale by a hand or a cheek
# The marks, in texels (x0, y0, x1, y1): each is FIT onto exactly one face.
EYE_RECT   = (64, 40, 112, 64)         # 48x24: the eye, stamped in the steel
PLATE_RECT = (64, 16, 120, 36)         # 56x20: the brass number plate
MARKS_BOX  = (64, 0, 128, 64)          # the rest of that quarter is plain blued steel

# ---- master proportions (metres, Blender space: +Y forward, +Z up) ----------
BUTT_Y        = -0.340   # rear face of the butt plate
RECEIVER_Y0   = -0.020   # receiver/wrist junction  == THE ORIGIN PLANE
RECEIVER_Y1   =  0.300   # front ring of the receiver, where the barrel screws in
MUZZLE_Y      =  1.150   # tip of the barrel  -> Godot local z = -1.150
                          # overall length = MUZZLE_Y - BUTT_Y = 1.49 m

RECEIVER_HALF_W = 0.026  # flat-sided lower receiver
RECEIVER_Z0     = -0.032
RECEIVER_Z1     =  0.012
RECEIVER_RING_R = 0.024  # the round top of the action, 8-gon on the bore

BARREL_R0       = 0.024  # at the receiver ring
BARREL_R1       = 0.015  # at the muzzle
BARREL_SIDES    = 8

FOREND_Y1       = 0.860  # the wood stops here; bare barrel to the muzzle
BAND_Y          = ((0.560, 0.582), (0.832, 0.858))   # iron barrel bands

BOLT_Y          = (0.044, 0.066)   # bolt handle root, closed, above the trigger
BOLT_KNOB_X     = (0.070, 0.102)

PEEP_Z          = 0.080  # aperture centre above the bore
PEEP_R_OUT      = 0.014
PEEP_R_IN       = 0.006

# ---- views ------------------------------------------------------------------
FACING_YAW = 180.0       # the muzzle points +Y: "front" looks down the barrel


# =============================================================================
# TEXTURE -- hand-written texels, no gradients, no filtering
# =============================================================================

class _Rng(object):
    """Tiny deterministic LCG so the atlas is byte-identical every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def bits(self):
        return self.n() >> 12          # the low bits are short-period: corduroy

    def f(self):
        return self.n() / float(0x7FFFFFFF)

    def i(self, a, b):
        return a + self.bits() % (b - a + 1)

    def pick(self, seq):
        return seq[self.bits() % len(seq)]


def _s2l(rgb):
    """sRGB 0-255 -> scene-linear, which is what image.pixels wants."""
    out = []
    for c in rgb:
        c /= 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return out


class _Canvas(object):
    def __init__(self, size):
        self.w = self.h = size
        n = size * size * 4
        self.alb = [0.0] * n
        for i in range(size * size):
            self.alb[i * 4 + 3] = 1.0
        self.clip = (0, 0, size, size)

    def put(self, x, y, rgb):
        x0, y0, x1, y1 = self.clip
        if not (x0 <= x < x1 and y0 <= y < y1):
            return
        o = (y * self.w + x) * 4
        self.alb[o], self.alb[o + 1], self.alb[o + 2] = _s2l(rgb)

    def hline(self, x, y, n, rgb):
        for d in range(n):
            self.put(x + d, y, rgb)

    def vline(self, x, y, n, rgb):
        for d in range(n):
            self.put(x, y + d, rgb)

    def rect(self, x0, y0, x1, y1, rgb):
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.put(x, y, rgb)

    def disc(self, cx, cy, rad, rgb):
        for dy in range(-rad, rad + 1):
            for dx in range(-rad, rad + 1):
                if dx * dx + dy * dy <= rad * rad + rad * 0.5:
                    self.put(cx + dx, cy + dy, rgb)


def _rect_of(zone, size):
    u0, v0, u1, v1 = zone
    return (int(u0 * size), int(v0 * size), int(u1 * size), int(v1 * size))


# ---- palettes: four or five shades a material, nothing between them ---------
PAL_WALNUT  = [(88, 52, 28), (100, 62, 34), (76, 44, 24), (112, 72, 42)]
GRAIN       = [(52, 28, 14), (46, 24, 12), (130, 90, 50)]
PAL_WORN    = [(118, 84, 48), (130, 94, 56), (106, 74, 42), (140, 106, 64)]
WORN_GRAIN  = [(94, 62, 34), (166, 130, 84)]
PAL_BLUED   = [(46, 50, 60), (40, 44, 53), (52, 57, 68), (34, 37, 45)]
STEEL_WEAR  = [(104, 108, 114), (84, 88, 94), (126, 130, 136)]
PAL_BRASS   = [(170, 134, 54), (186, 150, 66), (152, 118, 44), (200, 166, 82)]
BRASS_DARK  = [(120, 92, 38), (98, 74, 30)]
BRASS_LIGHT = [(224, 194, 112)]
INK         = (44, 30, 12)             # engraved into brass
IRIS        = (128, 24, 18)            # the eye's iris, tower/models/eye.glb's red
IRIS_RIM    = (86, 14, 12)
SCLERA      = (22, 22, 26)             # its dark ball
PUPIL       = (8, 6, 8)


def _fill(c, r, box, shades):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            c.put(x, y, r.pick(shades))


def _grain(c, r, box, count, shades, wander):
    """Grain the whole width of the box along u, wandering a texel in v now and then."""
    x0, y0, x1, y1 = box
    for _ in range(count):
        y = r.i(y0, y1 - 1)
        col = r.pick(shades)
        for x in range(x0, x1):
            c.put(x, y, col)
            if r.f() < wander:
                y = min(max(y + r.i(-1, 1), y0), y1 - 1)


def _paint_walnut(c, r, box):
    """Dark oiled walnut: long grain, a knot or two, oil-dark patches."""
    c.clip = box
    x0, y0, x1, y1 = box
    _fill(c, r, box, PAL_WALNUT)
    _grain(c, r, box, 22, GRAIN, 0.12)
    for _ in range(6):                                    # oil-dark figure
        x, y = r.i(x0, x1 - 8), r.i(y0, y1 - 3)
        c.rect(x, y, x + r.i(4, 9), y + r.i(1, 3), (62, 36, 20))
    for _ in range(2):                                    # knots: rings in the grain
        kx, ky = r.i(x0 + 6, x1 - 7), r.i(y0 + 4, y1 - 5)
        c.disc(kx, ky, 3, (56, 32, 16))
        c.disc(kx, ky, 2, (104, 66, 36))
        c.disc(kx, ky, 1, (46, 24, 12))
    for _ in range(10):                                   # dings
        c.put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), (44, 22, 12))


def _paint_worn(c, r, box):
    """The same walnut rubbed pale where a hand and a cheek have lived on it."""
    c.clip = box
    x0, y0, x1, y1 = box
    _fill(c, r, box, PAL_WORN)
    _grain(c, r, box, 9, WORN_GRAIN, 0.10)
    for _ in range(7):                                    # polished high spots
        x, y = r.i(x0, x1 - 6), r.i(y0, y1 - 2)
        c.rect(x, y, x + r.i(3, 7), y + r.i(1, 2), (172, 134, 86))
    for _ in range(6):                                    # dirt in the pores
        x, y = r.i(x0, x1 - 3), r.i(y0, y1 - 2)
        c.rect(x, y, x + r.i(1, 3), y + 1, (90, 58, 32))


def _paint_blued(c, r, box, marks=False):
    """Blued steel: blue-black, machining lines, silver wear where hands and holsters rubbed."""
    c.clip = box
    x0, y0, x1, y1 = box
    _fill(c, r, box, PAL_BLUED)
    for _ in range(5):                                    # turning marks
        y = r.i(y0, y1 - 1)
        c.hline(x0, y, x1 - x0, (56, 61, 72))
    if marks:
        return
    for _ in range(12):                                   # bright wear
        x, y = r.i(x0, x1 - 8), r.i(y0, y1 - 1)
        c.hline(x, y, r.i(3, 8), r.pick(STEEL_WEAR))
    for _ in range(6):                                    # worn-through patches
        x, y = r.i(x0, x1 - 4), r.i(y0, y1 - 3)
        c.rect(x, y, x + r.i(2, 4), y + r.i(1, 2), (84, 88, 94))
    for _ in range(16):                                   # pits
        c.put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), (18, 20, 24))
    for _ in range(4):                                    # a little rust in the pits
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        c.rect(x, y, x + 2, y + 1, (78, 48, 30))


def _paint_brass(c, r, box):
    """Turned brass: warm, tarnished in patches, a bright line where it was polished."""
    c.clip = box
    x0, y0, x1, y1 = box
    _fill(c, r, box, PAL_BRASS)
    for _ in range(8):                                    # tarnish
        x, y = r.i(x0, x1 - 5), r.i(y0, y1 - 4)
        c.rect(x, y, x + r.i(2, 5), y + r.i(2, 4), r.pick(BRASS_DARK))
    for _ in range(6):                                    # lathe lines
        y = r.i(y0, y1 - 1)
        c.hline(x0, y, x1 - x0, r.pick(BRASS_DARK + BRASS_LIGHT))
    for _ in range(10):                                   # glints
        c.put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), BRASS_LIGHT[0])


def _paint_eye(c, r, rect):
    """The panopticon's eye struck into the receiver: a lens outline, dark ball, red iris, black pupil."""
    c.clip = rect
    x0, y0, x1, y1 = rect
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    half_w, half_h = 22, 10
    for dx in range(-half_w, half_w + 1):
        h = int(round(half_h * (1.0 - (dx / float(half_w)) ** 2)))
        c.vline(cx + dx, cy - h, 2 * h + 1, SCLERA)
        c.put(cx + dx, cy + h + 1, (108, 112, 122))        # light catches the struck edge
        c.put(cx + dx, cy - h - 1, (108, 112, 122))
        c.put(cx + dx, cy + h, (12, 13, 16))
        c.put(cx + dx, cy - h, (12, 13, 16))
    c.disc(cx, cy, 8, IRIS_RIM)
    c.disc(cx, cy, 7, IRIS)
    c.disc(cx, cy, 4, PUPIL)
    c.put(cx - 3, cy + 4, (188, 96, 84))                  # one glint


_FONT = {                                                  # 3x5, rows top -> bottom
    "N": ["#.#", "###", "###", "#.#", "#.#"],
    "o": ["...", ".#.", "#.#", "#.#", ".#."],
    "0": ["###", "#.#", "#.#", "#.#", "###"],
    "7": ["###", "..#", ".#.", ".#.", ".#."],
    " ": ["...", "...", "...", "...", "..."],
}


def _glyphs(c, text, x, y_top, scale, rgb):
    for ch in text:
        rows = _FONT[ch]
        for ri, row in enumerate(rows):
            for ci, bit in enumerate(row):
                if bit == "#":
                    c.rect(x + ci * scale, y_top - (ri + 1) * scale + 1,
                           x + (ci + 1) * scale, y_top - ri * scale + 1, rgb)
        x += (3 + 1) * scale


def _paint_plate(c, r, rect):
    """The numbered brass plate: bordered, four screws, the number engraved."""
    c.clip = rect
    x0, y0, x1, y1 = rect
    _fill(c, r, rect, PAL_BRASS)
    c.rect(x0, y0, x1, y0 + 1, BRASS_DARK[1])
    c.rect(x0, y1 - 1, x1, y1, BRASS_LIGHT[0])
    c.rect(x0, y0, x0 + 1, y1, BRASS_LIGHT[0])
    c.rect(x1 - 1, y0, x1, y1, BRASS_DARK[1])
    for sx in (x0 + 3, x1 - 4):
        for sy in (y0 + 3, y1 - 4):
            c.put(sx, sy, BRASS_DARK[1])
            c.put(sx + 1, sy + 1, BRASS_LIGHT[0])
    _glyphs(c, "No 7", x0 + 12, y1 - 5, 2, INK)


def build_texture():
    """Paint the atlas and hand back the albedo image."""
    c = _Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    _paint_walnut(c, r, _rect_of(ZONE_WALNUT, TEX_SIZE))
    _paint_blued(c, r, _rect_of(ZONE_BLUED, TEX_SIZE))
    _paint_brass(c, r, _rect_of(ZONE_BRASS, TEX_SIZE))
    _paint_worn(c, r, _rect_of(ZONE_WORN, TEX_SIZE))
    _paint_blued(c, r, MARKS_BOX, marks=True)
    _paint_eye(c, r, EYE_RECT)
    _paint_plate(c, r, PLATE_RECT)

    img = bpy.data.images.new(TEX_ALBEDO, TEX_SIZE, TEX_SIZE, alpha=False)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(c.alb)
    img.update()
    return img


def warden_material(name, albedo):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = albedo
    node.interpolation = "Closest"          # hard texels; this is the look
    node.location = (-460, 260)
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = BODY_ROUGHNESS
    bsdf.inputs["Metallic"].default_value = BODY_METALLIC
    bsdf.inputs["Emission Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 1.0   # exactly 1.0: no KHR warning
    mat.diffuse_color = (0.22, 0.14, 0.10, 1.0)
    return mat


# =============================================================================
# GEOMETRY HELPERS
# =============================================================================
# Thin wrappers over mdl so that every primitive this file makes is registered
# for the final join -- and tagged with the atlas zone it is skinned from.

_OBJECTS = []
_ZONE = ZONE_BLUED         # every primitive built lands in this zone


def _reg(ob, top=None, fit=None):
    ob["zone"] = _ZONE
    if top is not None:
        ob["zone_top"] = top       # upward faces take this zone instead (a cheek rest)
    if fit is not None:
        ob["fit"] = fit            # every face stretches over this texel rect (a mark)
    _OBJECTS.append(ob)
    return ob


def zone(z):
    global _ZONE
    _ZONE = z


def frustum(name, a, b):                       return _reg(mdl.frustum(name, a, b))
def prism(name, y0, y1, r0, r1=None, **kw):    return _reg(mdl.prism(name, y0, y1, r0, r1), **kw)
def tube(name, y0, y1, radii, cz=0.0, cx=0.0, sides=8):
    return _reg(mdl.tube(name, y0, y1, radii, cz=cz, cx=cx, sides=sides))


def taper(name, y0, y1, r0, r1, sides=8, cz=0.0):
    """An n-gon tube along +Y whose radius runs r0 -> r1: the barrel."""
    verts = []
    for y, rad in ((y0, r0), (y1, r1)):
        for i in range(sides):
            t = 2.0 * math.pi * i / sides
            verts.append((rad * math.sin(t), y, cz + rad * math.cos(t)))
    faces = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i) for i in range(sides)]
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple(range(sides, 2 * sides)))
    return _reg(mdl.mesh(name, verts, faces))


def washer(name, y0, y1, r_out, r_in, cz, sides=8):
    """A flat ring standing across the bore line, with a real hole: the peep."""
    verts = []
    for y in (y0, y1):
        for rad in (r_out, r_in):
            for i in range(sides):
                t = 2.0 * math.pi * i / sides
                verts.append((rad * math.sin(t), y, cz + rad * math.cos(t)))
    o0, i0, o1, i1 = 0, sides, 2 * sides, 3 * sides
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((o0 + i, o0 + j, o1 + j, o1 + i))          # outer wall
        faces.append((i1 + i, i1 + j, i0 + j, i0 + i))          # bore wall, facing in
        faces.append((o1 + i, o1 + j, i1 + j, i1 + i))          # front
        faces.append((o0 + j, o0 + i, i0 + i, i0 + j))          # back
    return _reg(mdl.mesh(name, verts, faces))


def guard_u(name, half_w, outline):
    """One solid extruded across X from a (y, z) outline listed counter-clockwise from +X."""
    n = len(outline)
    verts = [(-half_w, y, z) for (y, z) in outline] + [(half_w, y, z) for (y, z) in outline]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return _reg(mdl.mesh(name, verts, faces))


def unwrap(ob, seed=0):
    """Per-face planar projection into a random window of the object's zone.

    Each face is projected on its own dominant axis with the gun's long axis
    (Blender +Y) along u, so grain runs the length of the wood on every face,
    and dropped somewhere inside its zone. A "fit" object instead stretches
    every face over one texel rect, mirrored on -X faces so a mark reads the
    right way round from the shooter's side.
    """
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    fit = ob.get("fit")
    r = _Rng(TEX_SEED + seed * 7919 + len(me.polygons))
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        ii, jj = ((1, 2), (0, 2), (1, 0))[ax]
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        mi = min(co[ii] for co in cos)
        mj = min(co[jj] for co in cos)
        wi = max(co[ii] for co in cos) - mi
        wj = max(co[jj] for co in cos) - mj
        if fit is not None:
            tx0, ty0, tx1, ty1 = fit
            flip = ax == 0 and n[0] < 0.0
            for li, co in zip(poly.loop_indices, cos):
                s = (co[ii] - mi) / wi if wi > 1e-9 else 0.0
                t = (co[jj] - mj) / wj if wj > 1e-9 else 0.0
                if flip:
                    s = 1.0 - s
                uvl.data[li].uv = ((tx0 + 0.5 + s * (tx1 - tx0 - 1.0)) / TEX_SIZE,
                                   (ty0 + 0.5 + t * (ty1 - ty0 - 1.0)) / TEX_SIZE)
            continue
        z = ob["zone_top"] if (ob.get("zone_top") is not None and n[2] > 0.7) else ob["zone"]
        u0, v0, u1, v1 = z
        span_u = (u1 - u0) - 2.0 * UV_PAD
        span_v = (v1 - v0) - 2.0 * UV_PAD
        w = min(wi * UV_SCALE, 1.0)
        h = min(wj * UV_SCALE, 1.0)
        ou = r.f() * (1.0 - w)
        ov = r.f() * (1.0 - h)
        for li, co in zip(poly.loop_indices, cos):
            s = min(ou + (co[ii] - mi) * UV_SCALE, 1.0)
            t = min(ov + (co[jj] - mj) * UV_SCALE, 1.0)
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u,
                               v0 + UV_PAD + t * span_v)


def _geometry():
    RW = RECEIVER_HALF_W

    # ---- receiver: flat-sided lower, round action on top ----------------------
    zone(ZONE_BLUED)
    prism("receiver", RECEIVER_Y0, RECEIVER_Y1, (-RW, RW, RECEIVER_Z0, RECEIVER_Z1))
    tube("action", RECEIVER_Y0, RECEIVER_Y1, RECEIVER_RING_R, sides=8)
    # the eye, struck into the left wall -- the wall the shooter looks at
    prism("eye_stamp", 0.090, 0.174, (-RW - 0.0008, -RW + 0.004, -0.031, 0.011), fit=EYE_RECT)

    # ---- bolt: shroud out the back, handle down the right side ----------------
    tube("bolt_shroud", -0.062, RECEIVER_Y0, 0.016, cz=0.003, sides=8)
    by0, by1 = BOLT_Y
    frustum("bolt_handle",
            [(RW - 0.004, by0, 0.014), (RW - 0.004, by1, 0.014),
             (RW - 0.004, by1, -0.008), (RW - 0.004, by0, -0.008)],
            [(BOLT_KNOB_X[0] + 0.008, by0 + 0.002, -0.030), (BOLT_KNOB_X[0] + 0.008, by1 - 0.002, -0.030),
             (BOLT_KNOB_X[0] + 0.008, by1 - 0.002, -0.048), (BOLT_KNOB_X[0] + 0.008, by0 + 0.002, -0.048)])
    prism("bolt_knob", by0 - 0.007, by1 + 0.007, (BOLT_KNOB_X[0], BOLT_KNOB_X[1], -0.072, -0.034))

    # ---- barrel, front sight ----------------------------------------------------
    taper("barrel", RECEIVER_Y1, MUZZLE_Y, BARREL_R0, BARREL_R1, sides=BARREL_SIDES)
    prism("sight_base", 1.070, 1.110, (-0.008, 0.008, 0.006, 0.020))
    prism("sight_blade", 1.085, 1.095, (-0.003, 0.003, 0.012, 0.038))

    # ---- peep sight: brass post and ring on the tang ---------------------------
    zone(ZONE_BRASS)
    prism("peep_post", -0.006, 0.010, (-0.005, 0.005, 0.020, PEEP_Z - PEEP_R_OUT + 0.004))
    washer("peep_ring", -0.004, 0.008, PEEP_R_OUT, PEEP_R_IN, PEEP_Z)

    # ---- stock: wrist, comb, butt -- one piece of walnut ----------------------
    zone(ZONE_WORN)
    prism("wrist", -0.120, RECEIVER_Y0,
          (-0.021, 0.021, -0.058, 0.012),
          (-RW, RW, -0.040, 0.004))
    zone(ZONE_WALNUT)
    prism("comb", -0.200, -0.120,
          (-0.024, 0.024, -0.082, 0.044),
          (-0.021, 0.021, -0.058, 0.012), top=ZONE_WORN)
    prism("butt", -0.328, -0.200,
          (-0.024, 0.024, -0.100, 0.046),
          (-0.024, 0.024, -0.082, 0.044))
    zone(ZONE_BLUED)
    prism("butt_plate", BUTT_Y, -0.328, (-0.025, 0.025, -0.102, 0.048))
    zone(ZONE_BRASS)
    prism("number_plate", -0.292, -0.240, (-0.0248, -0.022, -0.040, -0.022), fit=PLATE_RECT)

    # ---- belly and forend: the wood the action beds into, out to the bands ----
    zone(ZONE_WALNUT)
    prism("belly", RECEIVER_Y0, RECEIVER_Y1, (-RW - 0.001, RW + 0.001, -0.052, -0.030))
    prism("forend", RECEIVER_Y1 - 0.002, FOREND_Y1,
          (-RW - 0.001, RW + 0.001, -0.052, 0.002),
          (-0.020, 0.020, -0.036, 0.004))
    zone(ZONE_BLUED)
    prism("band_rear", BAND_Y[0][0], BAND_Y[0][1], (-0.027, 0.027, -0.050, 0.025))
    prism("band_front", BAND_Y[1][0], BAND_Y[1][1], (-0.022, 0.022, -0.040, 0.022))

    # ---- trigger group and magazine floorplate ---------------------------------
    guard_u("trigger_guard", 0.011, [(0.000, -0.050), (0.125, -0.050), (0.125, -0.092),
                                     (0.110, -0.092), (0.110, -0.064), (0.015, -0.064),
                                     (0.015, -0.092), (0.000, -0.092)])
    prism("trigger", 0.044, 0.058, (-0.005, 0.005, -0.082, -0.052))
    prism("floorplate", 0.135, 0.265, (-0.020, 0.020, -0.060, -0.050))


def build():
    _OBJECTS.clear()
    _geometry()

    albedo = build_texture()
    mdl.save_texture(albedo)

    for i, ob in enumerate(_OBJECTS):
        unwrap(ob, seed=i)

    ob = mdl.join(_OBJECTS, OBJECT_NAME)
    mdl.finish(ob, warden_material("RifleWarden", albedo), strip_uvs=False)
    print("MDL STATS overall_length=%.3f muzzle_local_godot=(0, 0, %.3f)"
          % (MUZZLE_Y - BUTT_Y, -MUZZLE_Y))
    print("MDL STATS uv_layers=%d atlas=%dx%d" % (len(ob.data.uv_layers), TEX_SIZE, TEX_SIZE))
    return ob


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
