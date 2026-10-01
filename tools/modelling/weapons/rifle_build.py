"""
PANOPTICON -- the warden's rifle: an old-prison bolt-action, low-poly view model.

A long rifle with a heavy walnut stock, blued iron, a low one-inch riflescope
on two short rings and a hand-worn finish; institutional, not military. Marked with the panopticon's
eye stamped on the left of the receiver and a numbered brass plate let into
the left of the butt -- the side the shooter sees. The 128x128 PS1-style atlas
is weapons/textures/rifle_hell_albedo.png, drawn by hand; there is no emissive.

Run through the pipeline (from the Mac, from the repo root)::

    tools/modelling/model build rifle --views none
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
local -Z axis and the scope sits directly above the origin; the stock
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
GLASS_RECT = (64, 2, 96, 14)           # 32x12: the scope's dark lens glass

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

# The scope's axis is the ADS eye (scripts/weapon/rifle_ads.gd aim pose over scale 0.75): a real
# scope height, 45 mm over the bore. Rear faces near the eye sit outside its clear cone; the saddle ramps up.
ADS_SCALE       = 0.75
SCOPE_Z         = 0.03375 / ADS_SCALE    # eye height above the bore, model metres (0.045)
EYE_Y           = -0.14625 / ADS_SCALE   # eye, behind the origin, just ahead of the comb
CLEAR_TAN       = 0.475 * math.tan(math.radians(10.0)) * 1.06 / math.cos(math.pi / 8)
                                         # vignette clear+soft at 20 deg fov, 8-gon vertex, margin
TUBE_R          = 0.0127                 # the one-inch (25 mm) main tube
OCULAR_Y        = (-0.110, -0.090)       # eyepiece bell; its taper ends at OCULAR_TAPER
OCULAR_TAPER    = -0.074
OCULAR_R        = 0.0175
SADDLE_RAMP     = -0.046                 # the tube swells into the saddle from here, slope under R/d
SADDLE_Y        = (-0.008, 0.024)        # turret saddle between the rings
SADDLE_R        = 0.0155
FLARE_Y         = 0.150                  # the tube eases out into the objective from here
BELL_Y          = 0.300                  # objective front, over the receiver ring; slope under R/d
BELL_R          = 0.0175
RING_Y          = ((-0.062, -0.050), (0.070, 0.082))   # the two rings, back to front
RING_R          = 0.0150                 # clamp outside; inside just clears the tube
KNOB_Y          = 0.004                  # elevation up, windage right, on the saddle's flats
KNOB_R          = 0.0060
KNOB_H          = 0.008
BASE_Y          = (-0.068, 0.088)        # one low base, bolt shroud to action top
BASE_Z          = (0.018, 0.026)

# ---- views ------------------------------------------------------------------
FACING_YAW = 180.0       # the muzzle points +Y: "front" looks down the barrel


# =============================================================================
# TEXTURE -- the drawn atlas, referenced
# =============================================================================

class _Rng(object):
    """Tiny deterministic LCG: the unwrap's windows are the same every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def f(self):
        return self.n() / float(0x7FFFFFFF)


def build_texture():
    """The albedo image, weapons/textures/rifle_hell_albedo.png."""
    return mdl.texture(TEX_ALBEDO)


def warden_material(name, albedo):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = True        # the scope's open interior must cull from the ADS eye
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


def lathe(name, profile, cz, sides=8, cap=False, turn=0.0):
    """An OPEN n-gon shell along +Y through (y, r) profile points; cap closes the last ring facing +Y.
    turn=0.5 puts a flat, not a vertex, at the top and the right, so a knob can sit on it."""
    verts = []
    for y, rad in profile:
        for i in range(sides):
            t = 2.0 * math.pi * (i + turn) / sides
            verts.append((rad * math.sin(t), y, cz + rad * math.cos(t)))
    faces = []
    for k in range(len(profile) - 1):
        a, b = k * sides, (k + 1) * sides
        faces += [(a + i, a + (i + 1) % sides, b + (i + 1) % sides, b + i) for i in range(sides)]
    if cap:
        faces.append(tuple(range((len(profile) - 1) * sides, len(profile) * sides)))
    ob = _reg(mdl.mesh(name, verts, faces))
    ob["open"] = True
    return ob


def knob(name, base, axis, rad, height, sides=6):
    """An n-gon turret knob standing on ``base`` along +Z ("z") or +X ("x"); its buried foot is left open."""
    bx, by, bz = base
    verts = []
    for h in (0.0, height):
        for i in range(sides):
            t = 2.0 * math.pi * (i + 0.5) / sides
            if axis == "z":
                verts.append((bx + rad * math.cos(t), by + rad * math.sin(t), bz + h))
            else:
                verts.append((bx + h, by + rad * math.cos(t), bz + rad * math.sin(t)))
    faces = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i) for i in range(sides)]
    faces.append(tuple(range(sides, 2 * sides)))
    ob = _reg(mdl.mesh(name, verts, faces))
    ob["open"] = True
    return ob


def sleeve(name, y0, y1, rect):
    """A box's four walls along +Y, no ends: a ring foot whose top and bottom are buried."""
    x0, x1, z0, z1 = rect
    verts = [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1),
             (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]
    faces = [(0, 1, 2, 3), (5, 4, 7, 6), (1, 5, 6, 2), (4, 0, 3, 7)]
    ob = _reg(mdl.mesh(name, verts, faces))
    ob["open"] = True
    return ob


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

    # ---- scope: low base, two short rings, eyepiece bell, saddle with knobs, one-inch tube ----
    zs, hole, flat = SCOPE_Z, CLEAR_TAN * (OCULAR_Y[0] - EYE_Y), math.cos(math.pi / 8)
    prism("scope_base", BASE_Y[0], BASE_Y[1], (-0.010, 0.010, BASE_Z[0], BASE_Z[1]))
    lathe("scope_body", [(OCULAR_Y[0], OCULAR_R), (OCULAR_Y[1], OCULAR_R),
                         (OCULAR_TAPER, TUBE_R), (SADDLE_RAMP, TUBE_R), (SADDLE_Y[0], SADDLE_R),
                         (SADDLE_Y[1], SADDLE_R), (SADDLE_Y[1], TUBE_R), (FLARE_Y, TUBE_R),
                         (BELL_Y, BELL_R)], zs, turn=0.5)
    for k, (y0, y1) in enumerate(RING_Y):
        rin = TUBE_R + 0.0002
        lathe("ring%d" % k, [(y0, rin), (y0, RING_R), (y1, RING_R)], zs, turn=0.5)
        sleeve("ring_foot%d" % k, y0 + 0.001, y1 - 0.001,
               (-0.007, 0.007, BASE_Z[1] - 0.001, zs - RING_R * flat + 0.0005))
    knob("knob_elev", (0.0, KNOB_Y, zs + SADDLE_R * flat - 0.0005), "z", KNOB_R, KNOB_H)
    knob("knob_wind", (SADDLE_R * flat - 0.0005, KNOB_Y, zs), "x", KNOB_R, KNOB_H)
    lathe("ocular_glass", [(OCULAR_Y[0], hole), (OCULAR_Y[0], OCULAR_R)], zs, turn=0.5)["fit"] = GLASS_RECT
    lathe("objective_glass", [(BELL_Y, BELL_R)], zs, cap=True, turn=0.5)["fit"] = GLASS_RECT

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


def _outward(ob):
    """Closed solids get outward normals so back-face culling never eats one."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def build():
    _OBJECTS.clear()
    _geometry()

    albedo = build_texture()

    for i, ob in enumerate(_OBJECTS):
        if not ob.get("open"):
            _outward(ob)
        unwrap(ob, seed=i)

    ob = mdl.join(_OBJECTS, OBJECT_NAME)
    mdl.finish(ob, warden_material("RifleWarden", albedo), strip_uvs=False)
    print("MDL STATS overall_length=%.3f muzzle_local_godot=(0, 0, %.3f)"
          % (MUZZLE_Y - BUTT_Y, -MUZZLE_Y))
    print("MDL STATS uv_layers=%d atlas=%dx%d" % (len(ob.data.uv_layers), TEX_SIZE, TEX_SIZE))
    return ob


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
