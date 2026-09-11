"""
PANOPTICON -- guard's .50 cal (Barrett M82 flavoured) low-poly view model.

HELL SKIN: scorched iron, brimstone cracks, bone furniture, rusted etchings.
The 128x128 PS1-style texture is generated procedurally by this script (no
gradients, hard texels, nearest-neighbour filtering) and written to
assets/textures/ alongside a matching emissive map for the ember glow.

Run through the pipeline (from the Mac, from the repo root)::

    tools/modelling/model build rifle --cpu --samples 36
    tools/modelling/model look  rifle --views side --res 1600x760
    tools/modelling/model look  rifle --cam 180,8,35      # first person

COORDINATES
-----------
Authored in BLENDER space, then glTF-exported (Blender X,Y,Z -> glTF X,Z,-Y):

    Blender +Y  ->  Godot -Z   (FORWARD, the muzzle direction)
    Blender +Z  ->  Godot +Y   (UP)
    Blender +X  ->  Godot +X   (RIGHT)

ORIGIN
------
(0,0,0) sits ON THE BORE LINE at the REAR FACE OF THE RECEIVER, where the
stock meets it. Chosen because:
  * y=0 is the bore, so the shot line is the model's own local -Z axis and the
    scope sits directly above the origin -- aiming maths needs no fudge factor.
  * The stock runs BACK from the origin into +Z (toward the camera) and the
    barrel runs FORWARD into -Z, so parenting this under Head and nudging it
    down/right gives a right-handed view model with no rotation at all.
  * The muzzle lands at a round local (0, 0, -MUZZLE_Z) for the tracer origin.
It is centred on x=0 (bore centreline), NOT pre-offset to the right, so the
game owns the hand offset.

TEXTURING
---------
One 128x128 atlas, quartered into four 64x64 zones. Every primitive declares
which zone it lives in; UVs are a per-face planar projection into a random
window of that zone, so faces get texel variety without a single seam and
without an unwrap. Nearest filtering, one material, one surface.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# =============================================================================
# TUNABLES -- everything adjustable lives in this block
# =============================================================================

NAME = "rifle"          # -> assets/models/rifle.glb
OBJECT_NAME = "Rifle"   # the MeshInstance3D name scenes/weapon/rifle.tscn sees

# ---- material / texture -----------------------------------------------------
TEX_SIZE      = 128         # PS1 budget: one small square atlas
TEX_ALBEDO    = "rifle_hell_albedo"
TEX_EMISSIVE  = "rifle_hell_emissive"
TEX_SEED      = 6660613
BODY_ROUGHNESS = 0.74
BODY_METALLIC  = 0.0
UV_SCALE      = 7.0         # texels-per-metre feel: face_size * UV_SCALE of a zone
UV_PAD        = 1.5 / TEX_SIZE   # half-texel gutter so zones never bleed

# Atlas zones as (u0, v0, u1, v1). v=0 is the BOTTOM row of the image.
ZONE_IRON  = (0.0, 0.5, 0.5, 1.0)   # scorched, pitted gun iron
ZONE_EMBER = (0.5, 0.5, 1.0, 1.0)   # cooled basalt split by brimstone cracks
ZONE_BONE  = (0.0, 0.0, 0.5, 0.5)   # grimy bone furniture
ZONE_RUST  = (0.5, 0.0, 1.0, 0.5)   # rust with crude etched marks

# ---- master proportions (metres, Blender space: +Y forward, +Z up) ----------
BUTT_Y        = -0.340   # rear face of the recoil pad
RECEIVER_Y0   = -0.020   # receiver/stock junction  == THE ORIGIN PLANE
RECEIVER_Y1   =  0.520   # front face of the receiver
BARREL_Y1     =  1.020   # where the barrel meets the muzzle brake
MUZZLE_Y      =  1.150   # tip of the brake  -> Godot local z = -1.150
                          # overall length = MUZZLE_Y - BUTT_Y = 1.49 m

RECEIVER_HALF_W = 0.047
RECEIVER_Z0     = -0.050  # bore sits above centre of the upper receiver
RECEIVER_Z1     =  0.056

BARREL_R        = 0.0330  # 12-gon, alternating radii to SUGGEST fluting
BARREL_R_FLUTE  = 0.0280
BARREL_SIDES    = 12
CHAMBER_R       = 0.043   # heavier section just ahead of the receiver

BRAKE_HALF_W_REAR  = 0.032
BRAKE_HALF_W_FRONT = 0.026
BRAKE_WING_SPAN    = 0.084   # half-span of the arrow "wings"
BRAKE_WING_HALF_H  = 0.031

RAIL_Z0, RAIL_Z1 = 0.056, 0.072

# ---- scope: a BRICK, not a tube and not a cube ------------------------------
# Halo 3 sniper flavour: one long heavy slab bolted FLUSH to the rail. It used
# to be a short square body floating on two ring posts, which read as a box on
# stilts; the posts are gone and the body now sits with its underside ON the
# rail (SCOPE_BOT_Z == RAIL_Z1), so the only gap is the rail's own 16 mm.
# Keep it much longer than it is tall -- that ratio is the whole look.
SCOPE_BOT_Z     = RAIL_Z1          # underside sits ON the rail: no stilts
SCOPE_HEIGHT    = 0.078            # slab depth
SCOPE_TOP_Z     = SCOPE_BOT_Z + SCOPE_HEIGHT
SCOPE_Z         = 0.5 * (SCOPE_BOT_Z + SCOPE_TOP_Z)   # bore-relative centre
SCOPE_Y0        = -0.090           # main slab, rear
SCOPE_Y1        =  0.290           # main slab, front  -> 0.380 long
# Wider than the receiver it sits on (RECEIVER_HALF_W = 0.047, full 0.094 m),
# not just wider than its own old self -- overhangs the receiver by 13 mm a
# side so it reads as a heavy chunk bolted on top, not a rail accessory.
# Height and length are untouched.
SCOPE_HALF_W    = RECEIVER_HALF_W + 0.013   # 0.060 -> full 0.120 m

SCOPE_OBJ_LEN   = 0.058            # front lens shroud: a lip, not a second lump
SCOPE_OBJ_HALF  = 0.037
SCOPE_OBJ_Z0    = SCOPE_BOT_Z - 0.006
SCOPE_OBJ_Z1    = SCOPE_TOP_Z + 0.006

SCOPE_EYE_LEN   = 0.058            # rear cup, sits down onto the cheek rest
SCOPE_EYE_HALF  = 0.034
SCOPE_EYE_Z0    = SCOPE_BOT_Z + 0.004
SCOPE_EYE_Z1    = SCOPE_TOP_Z - 0.004
# overall scope length = EYE_LEN + (Y1-Y0) + OBJ_LEN = 0.496 m, 6.4 : 1 on height

# ---- magazine: seats UP INTO the receiver through the magwell ---------------
LOWER_Y1     = 0.370            # trigger housing / magwell runs this far fwd
MAG_HALF_W   = 0.030
MAG_TOP_Z    = RECEIVER_Z0      # mouth ends flush with the receiver floor
MAG_TOP_Y    = (0.185, 0.345)   # magwell mouth, INSIDE the lower housing
MAG_BOT_Y    = (0.235, 0.390)   # rakes FORWARD as it drops -- M82 signature
MAG_BOT_Z    = -0.260

BIPOD_FOOT_Z   = -0.290
BIPOD_SPLAY_X  = 0.120          # how far the feet splay outboard

# ---- views ------------------------------------------------------------------
# The muzzle points +Y in Blender, so the model's "front" is half a turn from
# Blender's. With this set, `--views front` looks down the barrel and
# `--views side` gives the profile, which is the shot that matters for a gun.
FACING_YAW = 180.0


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
        # An LCG's LOW bits are short-period -- taking n() % 4 straight gives a
        # dither that repeats every 4 texels, which renders as corduroy. Use
        # the high bits.
        return self.n() >> 12

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
        self.emi = [0.0] * n
        for i in range(size * size):
            self.alb[i * 4 + 3] = 1.0
            self.emi[i * 4 + 3] = 1.0

    def put(self, x, y, rgb, glow=None):
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        o = (y * self.w + x) * 4
        r, g, b = _s2l(rgb)
        self.alb[o], self.alb[o + 1], self.alb[o + 2] = r, g, b
        if glow is not None:
            r, g, b = _s2l(glow)
            self.emi[o], self.emi[o + 1], self.emi[o + 2] = r, g, b

    def hline(self, x, y, n, rgb, glow=None):
        for d in range(n):
            self.put(x + d, y, rgb, glow)

    def vline(self, x, y, n, rgb, glow=None):
        for d in range(n):
            self.put(x, y + d, rgb, glow)

    def rect(self, x0, y0, x1, y1, rgb, glow=None):
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.put(x, y, rgb, glow)


def _rect_of(zone, size):
    u0, v0, u1, v1 = zone
    return (int(u0 * size), int(v0 * size), int(u1 * size), int(v1 * size))


def _paint_iron(c, r, box):
    """Scorched, pitted gun iron: cold charcoal eaten into by heat and rust."""
    x0, y0, x1, y1 = box
    shades = [(38, 35, 36), (48, 43, 42), (28, 26, 27), (58, 52, 49), (33, 30, 31)]
    for y in range(y0, y1):
        for x in range(x0, x1):
            c.put(x, y, r.pick(shades))
    for _ in range(26):                                   # heat bloom / rust bloom
        x, y = r.i(x0, x1 - 7), r.i(y0, y1 - 6)
        col = r.pick([(96, 46, 20), (72, 32, 14), (118, 62, 26), (20, 18, 19)])
        c.rect(x, y, x + r.i(3, 7), y + r.i(2, 6), col)
    for _ in range(18):                                   # soot streaks
        y = r.i(y0, y1 - 1)
        x = r.i(x0, x1 - 8)
        c.hline(x, y, min(r.i(10, 30), x1 - x), r.pick(
            [(15, 14, 15), (86, 40, 17), (66, 60, 55)]))
    for _ in range(14):                                   # bayonet scratches
        x = r.i(x0, x1 - 1)
        y = r.i(y0, y1 - 9)
        c.vline(x, y, min(r.i(4, 9), y1 - y), r.pick([(84, 78, 72), (18, 16, 17)]))
    for _ in range(26):                                   # pits and rivets
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        c.rect(x, y, x + 2, y + 2, r.pick([(11, 10, 11), (78, 72, 66)]))
    for _ in range(9):                                    # embers in the pits
        x, y = r.i(x0 + 2, x1 - 3), r.i(y0 + 2, y1 - 3)
        c.rect(x, y, x + 2, y + 2, (196, 70, 14), (176, 52, 6))


def _paint_ember(c, r, box):
    """Cooled basalt cracked wide open by brimstone. The only real light here."""
    x0, y0, x1, y1 = box
    shades = [(24, 17, 15), (34, 23, 18), (14, 10, 10), (44, 29, 21)]
    for y in range(y0, y1):
        for x in range(x0, x1):
            c.put(x, y, r.pick(shades))
    for _ in range(16):                                   # crack random-walks
        x, y = r.i(x0, x1 - 1), r.i(y0, y1 - 1)
        for _step in range(52):
            for dx in (-1, 0, 1):                         # 3x3 glowing halo
                for dy in (-1, 0, 1):
                    if x0 <= x + dx < x1 and y0 <= y + dy < y1:
                        c.put(x + dx, y + dy, (146, 48, 10), (104, 26, 3))
            hot = r.pick([(255, 152, 32), (255, 208, 84), (244, 104, 16)])
            c.put(x, y, hot, hot)
            x += r.i(-1, 1)
            y += r.i(-1, 1)
            if not (x0 <= x < x1 and y0 <= y < y1):
                break
    for _ in range(40):                                   # cold slag flecks
        c.put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), (8, 6, 7))


def _paint_bone(c, r, box):
    """Bone furniture: pale ivory, dirt worked into the grain, one kill tally."""
    x0, y0, x1, y1 = box
    shades = [(198, 188, 162), (178, 166, 138), (213, 205, 183), (163, 150, 123)]
    for y in range(y0, y1):
        for x in range(x0, x1):
            c.put(x, y, r.pick(shades))
    for _ in range(30):                                   # grime and old blood
        x, y = r.i(x0, x1 - 5), r.i(y0, y1 - 5)
        c.rect(x, y, x + r.i(2, 5), y + r.i(2, 5),
               r.pick([(124, 106, 80), (92, 74, 52), (146, 126, 96),
                       (108, 52, 34), (86, 38, 26)]))
    for _ in range(9):                                    # short grain cracks
        x, y = r.i(x0, x1 - 1), r.i(y0 + 2, y1 - 6)
        c.vline(x, y, r.i(2, 5), (84, 70, 52))
    for _ in range(6):                                    # scorch on the edges
        x, y = r.i(x0, x1 - 4), r.i(y0, y1 - 3)
        c.rect(x, y, x + r.i(2, 4), y + 2, (58, 44, 34))
    for k in range(5):                                    # kill tally, one corner
        c.vline(x0 + 4 + k * 3, y0 + 4, 7, (46, 34, 26))
    c.hline(x0 + 2, y0 + 7, 15, (46, 34, 26))


def _paint_rust(c, r, box):
    """Rust, and the sigil somebody scratched into the mag with a bayonet."""
    x0, y0, x1, y1 = box
    shades = [(94, 43, 18), (122, 59, 22), (66, 29, 12), (142, 76, 29), (80, 35, 15)]
    for y in range(y0, y1):
        for x in range(x0, x1):
            c.put(x, y, r.pick(shades))
    for _ in range(18):                                   # scabs of deep rust
        x, y = r.i(x0, x1 - 5), r.i(y0, y1 - 5)
        c.rect(x, y, x + r.i(3, 5), y + r.i(2, 5),
               r.pick([(52, 22, 9), (158, 90, 36), (38, 16, 8)]))
    ink = (17, 12, 10)
    cx, cy = x0 + 32, y0 + 32                             # inverted cross
    c.vline(cx, cy - 20, 40, ink)
    c.vline(cx + 1, cy - 20, 40, ink)
    c.hline(cx - 9, cy - 11, 20, ink)
    for k in range(8):                                    # ring of hash marks
        a = 2.0 * math.pi * k / 8.0
        hx = int(cx + 25 * math.cos(a))
        hy = int(cy + 25 * math.sin(a))
        c.vline(hx, hy, 3, ink)
    for _ in range(8):                                    # still-warm scratches
        x, y = r.i(x0, x1 - 4), r.i(y0, y1 - 1)
        c.hline(x, y, 3, (206, 92, 22), (150, 46, 6))


def build_texture():
    """Paint the atlas and hand back (albedo_image, emissive_image)."""
    c = _Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    _paint_iron(c, r, _rect_of(ZONE_IRON, TEX_SIZE))
    _paint_ember(c, r, _rect_of(ZONE_EMBER, TEX_SIZE))
    _paint_bone(c, r, _rect_of(ZONE_BONE, TEX_SIZE))
    _paint_rust(c, r, _rect_of(ZONE_RUST, TEX_SIZE))

    images = []
    for name, buf in ((TEX_ALBEDO, c.alb), (TEX_EMISSIVE, c.emi)):
        img = bpy.data.images.new(name, TEX_SIZE, TEX_SIZE, alpha=False)
        img.colorspace_settings.name = "sRGB"
        img.pixels.foreach_set(buf)
        img.update()
        images.append(img)
    return images[0], images[1]


def hell_material(name, albedo, emissive):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    for img, socket, y in ((albedo, "Base Color", 260), (emissive, "Emission Color", -220)):
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.interpolation = "Closest"          # hard texels; this is the look
        node.location = (-460, y)
        nt.links.new(node.outputs["Color"], bsdf.inputs[socket])
    bsdf.inputs["Roughness"].default_value = BODY_ROUGHNESS
    bsdf.inputs["Metallic"].default_value = BODY_METALLIC
    # Exactly 1.0 keeps glTF from writing KHR_materials_emissive_strength,
    # which Godot's importer would warn about -- and the verify bar is zero
    # warnings, not "no errors".
    bsdf.inputs["Emission Strength"].default_value = 1.0
    mat.diffuse_color = (0.22, 0.14, 0.12, 1.0)
    return mat


# =============================================================================
# GEOMETRY HELPERS
# =============================================================================
# Thin wrappers over mdl so that every primitive this file makes is registered
# for the final join -- and tagged with the atlas zone it is skinned from.

_OBJECTS = []
_ZONE = ZONE_IRON          # every primitive built lands in this zone


def _reg(ob):
    ob["zone"] = _ZONE
    _OBJECTS.append(ob)
    return ob


def zone(z):
    global _ZONE
    _ZONE = z


def frustum(name, a, b):                  return _reg(mdl.frustum(name, a, b))
def prism(name, y0, y1, r0, r1=None):     return _reg(mdl.prism(name, y0, y1, r0, r1))
def plate_z(name, quad, z0, z1):          return _reg(mdl.plate_z(name, quad, z0, z1))
def tube(name, y0, y1, radii, cz=0.0, cx=0.0, sides=8):
    return _reg(mdl.tube(name, y0, y1, radii, cz=cz, cx=cx, sides=sides))


def unwrap(ob, seed=0):
    """Per-face planar projection into a random window of the object's zone.

    Each face is projected on its own dominant axis and dropped somewhere
    inside its 64x64 zone. No shared UV space between faces means no seams to
    reason about and no unwrap to maintain, and the random window is what stops
    456 triangles all showing the same 8 texels.
    """
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    u0, v0, u1, v1 = ob["zone"]
    span_u = (u1 - u0) - 2.0 * UV_PAD
    span_v = (v1 - v0) - 2.0 * UV_PAD
    r = _Rng(TEX_SEED + seed * 7919 + len(me.polygons))
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        mi = min(co[ii] for co in cos)
        mj = min(co[jj] for co in cos)
        w = min((max(co[ii] for co in cos) - mi) * UV_SCALE, 1.0)
        h = min((max(co[jj] for co in cos) - mj) * UV_SCALE, 1.0)
        ou = r.f() * (1.0 - w)
        ov = r.f() * (1.0 - h)
        for li, co in zip(poly.loop_indices, cos):
            s = min(ou + (co[ii] - mi) * UV_SCALE, 1.0)
            t = min(ov + (co[jj] - mj) * UV_SCALE, 1.0)
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u,
                               v0 + UV_PAD + t * span_v)


def _geometry():
    RW = RECEIVER_HALF_W

    # ---- receiver -----------------------------------------------------------
    zone(ZONE_IRON)
    prism("receiver_upper", RECEIVER_Y0, RECEIVER_Y1,
          (-RW, RW, RECEIVER_Z0, RECEIVER_Z1))

    # ejection port + charging handle: right side, cheap silhouette breakers
    prism("rib_r", 0.020, 0.480, (RW, RW + 0.006, -0.032, -0.012))
    prism("rib_l", 0.020, 0.480, (-RW - 0.006, -RW, -0.032, -0.012))
    prism("ejection_port", 0.060, 0.200, (RW, RW + 0.010, -0.018, 0.030))
    prism("charging_handle", 0.210, 0.250, (RW, RW + 0.028, 0.005, 0.028))

    # ---- trigger housing / MAGWELL -----------------------------------------
    # Runs the full length from the receiver rear to past the magazine mouth,
    # so the magazine is seated into the gun instead of hanging off the guard.
    zone(ZONE_RUST)
    prism("lower_housing", RECEIVER_Y0, LOWER_Y1,
          (-0.042, 0.042, -0.098, -0.045))

    # ---- grip / trigger group ----------------------------------------------
    zone(ZONE_BONE)
    frustum("pistol_grip",
            [(-0.021, -0.020, -0.245), (0.021, -0.020, -0.245),
             (0.021,  0.050, -0.245), (-0.021, 0.050, -0.245)],
            [(-0.024,  0.020, -0.088), (0.024, 0.020, -0.088),
             (0.024,  0.092, -0.088), (-0.024, 0.092, -0.088)])
    zone(ZONE_IRON)
    prism("guard_bar",        0.088, 0.206, (-0.017, 0.017, -0.156, -0.136))
    prism("guard_post_rear",  0.088, 0.106, (-0.017, 0.017, -0.156, -0.096))
    prism("guard_post_front", 0.188, 0.206, (-0.017, 0.017, -0.156, -0.096))
    prism("trigger", 0.112, 0.130, (-0.008, 0.008, -0.130, -0.090))

    # ---- magazine: mouth ends INSIDE the magwell, body rakes forward -------
    zone(ZONE_RUST)
    frustum("magazine",
            [(-MAG_HALF_W, MAG_BOT_Y[0], MAG_BOT_Z), (MAG_HALF_W, MAG_BOT_Y[0], MAG_BOT_Z),
             (MAG_HALF_W, MAG_BOT_Y[1], MAG_BOT_Z), (-MAG_HALF_W, MAG_BOT_Y[1], MAG_BOT_Z)],
            [(-MAG_HALF_W, MAG_TOP_Y[0], MAG_TOP_Z), (MAG_HALF_W, MAG_TOP_Y[0], MAG_TOP_Z),
             (MAG_HALF_W, MAG_TOP_Y[1], MAG_TOP_Z), (-MAG_HALF_W, MAG_TOP_Y[1], MAG_TOP_Z)])

    # ---- stock --------------------------------------------------------------
    zone(ZONE_BONE)
    prism("stock_body", BUTT_Y + 0.040, RECEIVER_Y0,
          (-0.038, 0.038, -0.055, 0.042),
          (-0.045, 0.045, -0.075, 0.050))
    zone(ZONE_IRON)
    prism("butt_pad", BUTT_Y, BUTT_Y + 0.040, (-0.038, 0.038, -0.054, 0.046))
    zone(ZONE_BONE)
    prism("cheek_rest", -0.285, -0.060, (-0.034, 0.034, 0.042, 0.074))

    # ---- top: rail, carry handle, BOX scope ---------------------------------
    zone(ZONE_IRON)
    prism("rail", -0.040, 0.420, (-0.017, 0.017, RAIL_Z0, RAIL_Z1))
    # No carry handle and no scope rings any more -- the slab is the top of the
    # gun, and both would sit entirely inside it.
    prism("scope_body", SCOPE_Y0, SCOPE_Y1,
          (-SCOPE_HALF_W, SCOPE_HALF_W, SCOPE_BOT_Z, SCOPE_TOP_Z))
    zone(ZONE_EMBER)
    prism("scope_objective", SCOPE_Y1, SCOPE_Y1 + SCOPE_OBJ_LEN,
          (-SCOPE_OBJ_HALF, SCOPE_OBJ_HALF, SCOPE_OBJ_Z0, SCOPE_OBJ_Z1))
    prism("scope_eyepiece", SCOPE_Y0 - SCOPE_EYE_LEN, SCOPE_Y0,
          (-SCOPE_EYE_HALF, SCOPE_EYE_HALF, SCOPE_EYE_Z0, SCOPE_EYE_Z1))

    # ---- barrel -------------------------------------------------------------
    zone(ZONE_IRON)
    tube("chamber", 0.440, 0.580, CHAMBER_R, sides=8)
    flute = [BARREL_R if (i % 2 == 0) else BARREL_R_FLUTE for i in range(BARREL_SIDES)]
    tube("barrel", 0.560, BARREL_Y1, flute, sides=BARREL_SIDES)

    # ---- muzzle brake: the arrow ------------------------------------------
    prism("brake_body", BARREL_Y1 - 0.020, MUZZLE_Y,
          (-BRAKE_HALF_W_REAR, BRAKE_HALF_W_REAR, -BRAKE_HALF_W_REAR, BRAKE_HALF_W_REAR),
          (-BRAKE_HALF_W_FRONT, BRAKE_HALF_W_FRONT, -BRAKE_HALF_W_FRONT, BRAKE_HALF_W_FRONT))
    zone(ZONE_EMBER)
    wing_r = [(0.028, MUZZLE_Y - 0.050),
              (BRAKE_WING_SPAN, BARREL_Y1 - 0.012),
              (BRAKE_WING_SPAN, BARREL_Y1 - 0.040),
              (0.028, MUZZLE_Y - 0.100)]
    plate_z("brake_wing_r", wing_r, -BRAKE_WING_HALF_H, BRAKE_WING_HALF_H)
    plate_z("brake_wing_l", [(-x, y) for (x, y) in wing_r],
            -BRAKE_WING_HALF_H, BRAKE_WING_HALF_H)

    # ---- bipod --------------------------------------------------------------
    zone(ZONE_RUST)
    prism("bipod_mount", 0.500, 0.560, (-0.030, 0.030, -0.095, -0.045))
    for side, sgn in (("r", 1.0), ("l", -1.0)):
        top = [(sgn * 0.018, 0.505, -0.080), (sgn * 0.040, 0.505, -0.080),
               (sgn * 0.040, 0.545, -0.080), (sgn * 0.018, 0.545, -0.080)]
        foot_x0 = sgn * (BIPOD_SPLAY_X - 0.018)
        foot_x1 = sgn * BIPOD_SPLAY_X
        bot = [(foot_x0, 0.575, BIPOD_FOOT_Z), (foot_x1, 0.575, BIPOD_FOOT_Z),
               (foot_x1, 0.612, BIPOD_FOOT_Z), (foot_x0, 0.612, BIPOD_FOOT_Z)]
        frustum("bipod_leg_" + side, bot, top)


def build():
    _OBJECTS.clear()
    _geometry()

    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)

    for i, ob in enumerate(_OBJECTS):
        unwrap(ob, seed=i)

    ob = mdl.join(_OBJECTS, OBJECT_NAME)
    mdl.finish(ob, hell_material("RifleHell", albedo, emissive), strip_uvs=False)
    print("MDL STATS overall_length=%.3f muzzle_local_godot=(0, 0, %.3f)"
          % (MUZZLE_Y - BUTT_Y, -MUZZLE_Y))
    print("MDL STATS uv_layers=%d atlas=%dx%d" % (len(ob.data.uv_layers), TEX_SIZE, TEX_SIZE))
    return ob


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
