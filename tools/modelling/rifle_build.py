"""
PANOPTICON -- guard's .50 cal (Barrett M82 flavoured) low-poly view model.

Run headless:
    blender.exe -b -noaudio -P rifle_build.py

Writes C:\\dev\\artwork\\rifle.glb plus three preview renders.

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
"""

import math
import os
import sys

import bpy
from mathutils import Vector

# =============================================================================
# TUNABLES -- everything adjustable lives in this block
# =============================================================================

OUT_DIR = r"C:\dev\artwork"
GLB_NAME = "rifle.glb"
OBJECT_NAME = "Rifle"

# ---- material ---------------------------------------------------------------
BODY_COLOR = (0.255, 0.265, 0.275, 1.0)   # gunmetal grey, flat, single material
BODY_ROUGHNESS = 0.55
BODY_METALLIC = 0.0

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

SCOPE_Z         = 0.140   # tube centre height above the bore
SCOPE_R         = 0.024
SCOPE_Y0        = -0.020
SCOPE_Y1        =  0.200
SCOPE_SIDES     = 8
SCOPE_OBJ_R     = 0.040   # clearly a bell, so the front of the scope reads
SCOPE_EYE_R     = 0.030

RAIL_Z0, RAIL_Z1 = 0.056, 0.072

MAG_HALF_W   = 0.030
MAG_TOP_Y    = (0.185, 0.345)   # magwell mouth, under the receiver
MAG_BOT_Y    = (0.235, 0.390)   # rakes FORWARD as it drops -- M82 signature
MAG_BOT_Z    = -0.260

BIPOD_FOOT_Z   = -0.290
BIPOD_SPLAY_X  = 0.120          # how far the feet splay outboard

# ---- render -----------------------------------------------------------------
RENDER_SAMPLES = 64
GROUND_Z       = -1.10
WORLD_GREY     = 0.22
WORLD_STRENGTH = 0.60
# Point lights: (name, location, watts). Omnidirectional, so nothing is aimed.
# Rig is roughly left/right symmetric with a strong overhead, because every
# view here is axis-aligned boxes: top-vs-side is the only cue that separates
# facets, and it has to work from a -X camera (3/4, first person) AND a +X one
# (side profile) without re-lighting per shot.
LIGHTS = (("top",   ( 0.00,  0.30, 2.60), 300.0),
          ("left",  (-2.20, -0.90, 0.80), 120.0),
          ("right", ( 2.20, -0.40, 0.70), 120.0),
          ("front", ( 0.30,  2.40, 1.00),  90.0))

RENDERS = [
    # name,                  cam loc,                  aim at,             lens/ortho,  res
    ("rifle_side.png",         ( 4.50, 0.400,  0.020), (0.0,  0.400, 0.010), ("ortho", 1.78), (1600, 760)),
    ("rifle_threequarter.png", (-1.70,-1.200,  0.950), (0.05, 0.280, 0.000), ("lens", 50.0),  (1400, 900)),
    # Over-the-shoulder from the guard's eye line: pulled back from a literal
    # eye position, because at true eye distance a 1.49 m rifle is nothing but
    # scope eyepiece. Same axis, same left-of-bore / above-bore offset.
    ("rifle_firstperson.png",  (-0.340,-1.150, 0.500), (-0.02,0.420,-0.020), ("lens", 34.0),  (1400, 800)),
]

# =============================================================================
# GEOMETRY HELPERS
# =============================================================================

_OBJECTS = []


def _add_mesh(name, verts, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    _OBJECTS.append(ob)
    return ob


def _newell(quad):
    n = Vector((0.0, 0.0, 0.0))
    for i in range(len(quad)):
        a = Vector(quad[i])
        b = Vector(quad[(i + 1) % len(quad)])
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n


def frustum(name, quad_a, quad_b):
    """Hull between two 4-point quads. quad_a[i] pairs with quad_b[i].
    Winding is auto-corrected so every normal points outward."""
    qa, qb = list(quad_a), list(quad_b)
    ca = sum((Vector(v) for v in qa), Vector()) / 4.0
    cb = sum((Vector(v) for v in qb), Vector()) / 4.0
    axis = cb - ca
    if _newell(qa).dot(axis) < 0.0:
        qa.reverse()
        qb.reverse()
    verts = qa + qb
    faces = [(3, 2, 1, 0), (4, 5, 6, 7)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append((i, j, 4 + j, 4 + i))
    return _add_mesh(name, verts, faces)


def prism(name, y0, y1, rect0, rect1=None):
    """Box/tapered-box extruded along +Y. rect = (x0, x1, z0, z1)."""
    if rect1 is None:
        rect1 = rect0
    def quad(y, r):
        return [(r[0], y, r[2]), (r[1], y, r[2]), (r[1], y, r[3]), (r[0], y, r[3])]
    return frustum(name, quad(y0, rect0), quad(y1, rect1))


def plate_z(name, xy_quad, z0, z1):
    """A flat 4-sided plate lying in XY, given thickness in Z."""
    qa = [(x, y, z0) for (x, y) in xy_quad]
    qb = [(x, y, z1) for (x, y) in xy_quad]
    return frustum(name, qa, qb)


def tube(name, y0, y1, radii, cz=0.0, cx=0.0, sides=8):
    """N-gon tube running along +Y. `radii` is a float or a per-vertex list."""
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * sides
    verts = []
    for y in (y0, y1):
        for i in range(sides):
            t = 2.0 * math.pi * i / sides
            r = radii[i % len(radii)]
            verts.append((cx + r * math.sin(t), y, cz + r * math.cos(t)))
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((i, j, sides + j, sides + i))
    faces.append(tuple(reversed(range(sides))))          # y0 cap, -Y
    faces.append(tuple(range(sides, 2 * sides)))         # y1 cap, +Y
    return _add_mesh(name, verts, faces)


def mirror_x(quad):
    return [(-x, y, z) for (x, y, z) in quad]


# =============================================================================
# BUILD
# =============================================================================

def build():
    RW = RECEIVER_HALF_W

    # ---- receiver -----------------------------------------------------------
    prism("receiver_upper", RECEIVER_Y0, RECEIVER_Y1,
          (-RW, RW, RECEIVER_Z0, RECEIVER_Z1))
    prism("lower_housing", RECEIVER_Y0, 0.260,
          (-0.042, 0.042, -0.098, -0.045))

    # ejection port + charging handle: right side, cheap silhouette breakers
    prism("rib_r", 0.020, 0.480, (RW, RW + 0.006, -0.032, -0.012))
    prism("rib_l", 0.020, 0.480, (-RW - 0.006, -RW, -0.032, -0.012))
    prism("ejection_port", 0.060, 0.200, (RW, RW + 0.010, -0.018, 0.030))
    prism("charging_handle", 0.210, 0.250, (RW, RW + 0.028, 0.005, 0.028))

    # ---- grip / trigger group ----------------------------------------------
    frustum("pistol_grip",
            [(-0.021, -0.020, -0.245), (0.021, -0.020, -0.245),
             (0.021,  0.050, -0.245), (-0.021, 0.050, -0.245)],
            [(-0.024,  0.020, -0.088), (0.024, 0.020, -0.088),
             (0.024,  0.092, -0.088), (-0.024, 0.092, -0.088)])
    prism("guard_bar",        0.088, 0.198, (-0.017, 0.017, -0.156, -0.136))
    prism("guard_post_rear",  0.088, 0.106, (-0.017, 0.017, -0.156, -0.096))
    prism("guard_post_front", 0.180, 0.198, (-0.017, 0.017, -0.156, -0.096))
    prism("trigger", 0.112, 0.130, (-0.008, 0.008, -0.130, -0.090))

    # ---- magazine: angled forward of the trigger ---------------------------
    frustum("magazine",
            [(-MAG_HALF_W, MAG_BOT_Y[0], MAG_BOT_Z), (MAG_HALF_W, MAG_BOT_Y[0], MAG_BOT_Z),
             (MAG_HALF_W, MAG_BOT_Y[1], MAG_BOT_Z), (-MAG_HALF_W, MAG_BOT_Y[1], MAG_BOT_Z)],
            [(-MAG_HALF_W, MAG_TOP_Y[0], -0.090), (MAG_HALF_W, MAG_TOP_Y[0], -0.090),
             (MAG_HALF_W, MAG_TOP_Y[1], -0.090), (-MAG_HALF_W, MAG_TOP_Y[1], -0.090)])

    # ---- stock --------------------------------------------------------------
    prism("stock_body", BUTT_Y + 0.040, RECEIVER_Y0,
          (-0.038, 0.038, -0.055, 0.042),
          (-0.045, 0.045, -0.075, 0.050))
    prism("butt_pad", BUTT_Y, BUTT_Y + 0.040, (-0.038, 0.038, -0.054, 0.046))
    prism("cheek_rest", -0.285, -0.060, (-0.034, 0.034, 0.042, 0.074))

    # ---- top: rail, carry handle, scope ------------------------------------
    prism("rail", -0.040, 0.420, (-0.017, 0.017, RAIL_Z0, RAIL_Z1))
    prism("carry_handle", 0.255, 0.400, (-0.019, 0.019, RAIL_Z1, 0.100))

    tube("scope_tube", SCOPE_Y0, SCOPE_Y1, SCOPE_R, cz=SCOPE_Z, sides=SCOPE_SIDES)
    tube("scope_objective", SCOPE_Y1, SCOPE_Y1 + 0.080, SCOPE_OBJ_R,
         cz=SCOPE_Z, sides=SCOPE_SIDES)
    tube("scope_eyepiece", SCOPE_Y0 - 0.070, SCOPE_Y0, SCOPE_EYE_R,
         cz=SCOPE_Z, sides=SCOPE_SIDES)
    prism("scope_ring_rear",  0.018, 0.058, (-0.024, 0.024, RAIL_Z1, SCOPE_Z))
    prism("scope_ring_front", 0.138, 0.178, (-0.024, 0.024, RAIL_Z1, SCOPE_Z))

    # ---- barrel -------------------------------------------------------------
    tube("chamber", 0.440, 0.580, CHAMBER_R, sides=8)
    flute = [BARREL_R if (i % 2 == 0) else BARREL_R_FLUTE for i in range(BARREL_SIDES)]
    tube("barrel", 0.560, BARREL_Y1, flute, sides=BARREL_SIDES)

    # ---- muzzle brake: the arrow ------------------------------------------
    prism("brake_body", BARREL_Y1 - 0.020, MUZZLE_Y,
          (-BRAKE_HALF_W_REAR, BRAKE_HALF_W_REAR, -BRAKE_HALF_W_REAR, BRAKE_HALF_W_REAR),
          (-BRAKE_HALF_W_FRONT, BRAKE_HALF_W_FRONT, -BRAKE_HALF_W_FRONT, BRAKE_HALF_W_FRONT))
    wing_r = [(0.028, MUZZLE_Y - 0.050),
              (BRAKE_WING_SPAN, BARREL_Y1 - 0.012),
              (BRAKE_WING_SPAN, BARREL_Y1 - 0.040),
              (0.028, MUZZLE_Y - 0.100)]
    plate_z("brake_wing_r", wing_r, -BRAKE_WING_HALF_H, BRAKE_WING_HALF_H)
    plate_z("brake_wing_l", [(-x, y) for (x, y) in wing_r],
            -BRAKE_WING_HALF_H, BRAKE_WING_HALF_H)

    # ---- bipod --------------------------------------------------------------
    prism("bipod_mount", 0.500, 0.560, (-0.030, 0.030, -0.095, -0.045))
    for side, sgn in (("r", 1.0), ("l", -1.0)):
        top = [(sgn * 0.018, 0.505, -0.080), (sgn * 0.040, 0.505, -0.080),
               (sgn * 0.040, 0.545, -0.080), (sgn * 0.018, 0.545, -0.080)]
        foot_x0 = sgn * (BIPOD_SPLAY_X - 0.018)
        foot_x1 = sgn * BIPOD_SPLAY_X
        bot = [(foot_x0, 0.575, BIPOD_FOOT_Z), (foot_x1, 0.575, BIPOD_FOOT_Z),
               (foot_x1, 0.612, BIPOD_FOOT_Z), (foot_x0, 0.612, BIPOD_FOOT_Z)]
        frustum("bipod_leg_" + side, bot, top)


def finish_mesh():
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    for ob in _OBJECTS:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = _OBJECTS[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = OBJECT_NAME
    me = ob.data
    me.name = OBJECT_NAME

    mat = bpy.data.materials.new("RifleBody")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = BODY_COLOR
        bsdf.inputs["Roughness"].default_value = BODY_ROUGHNESS
        bsdf.inputs["Metallic"].default_value = BODY_METALLIC
    mat.diffuse_color = BODY_COLOR
    me.materials.clear()
    me.materials.append(mat)

    try:
        me.shade_flat()
    except Exception:
        for p in me.polygons:
            p.use_smooth = False

    # no UVs, no vertex colours -- match the prisoner model
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])

    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    bb = [Vector(c) for c in ob.bound_box]
    lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    print("RIFLE tris=%d verts=%d" % (tris, len(me.vertices)))
    print("RIFLE bbox blender lo=%.3f,%.3f,%.3f hi=%.3f,%.3f,%.3f"
          % (lo.x, lo.y, lo.z, hi.x, hi.y, hi.z))
    print("RIFLE godot  length=%.3f  muzzle_local=(0, 0, %.3f)"
          % (hi.y - lo.y, -MUZZLE_Y))
    return ob


def export_glb(ob):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, GLB_NAME)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    kwargs = dict(filepath=path, export_format="GLB", use_selection=True,
                  export_apply=True, export_yup=True, export_normals=True,
                  export_texcoords=False)
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
                                  use_selection=True)
    print("RIFLE wrote %s (%d bytes)" % (path, os.path.getsize(path)))


# =============================================================================
# RENDER
# =============================================================================

def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = RENDER_SAMPLES
    scene.cycles.use_denoising = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"   # AgX desaturates

    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (WORLD_GREY, WORLD_GREY, WORLD_GREY * 1.06, 1.0)
    bg.inputs[1].default_value = WORLD_STRENGTH

    # ground, well below the rifle so it only catches a shadow
    bpy.ops.mesh.primitive_plane_add(size=24.0, location=(0.0, 0.3, GROUND_Z))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("Ground")
    gm.use_nodes = True
    gb = gm.node_tree.nodes.get("Principled BSDF")
    if gb:
        gb.inputs["Base Color"].default_value = (0.34, 0.34, 0.36, 1.0)
        gb.inputs["Roughness"].default_value = 0.9
    ground.data.materials.append(gm)

    # point lights: omnidirectional, so nothing has to be aimed
    for name, loc, power in LIGHTS:
        ld = bpy.data.lights.new(name, type="POINT")
        ld.energy = power
        ld.shadow_soft_size = 0.35
        lo = bpy.data.objects.new(name, ld)
        lo.location = loc
        bpy.context.collection.objects.link(lo)

    tgt = bpy.data.objects.new("CamTarget", None)
    bpy.context.collection.objects.link(tgt)

    cd = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cd)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = tgt
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    return scene, cam, tgt


def do_renders():
    scene, cam, tgt = setup_render()
    for name, loc, aim, (mode, val), (rx, ry) in RENDERS:
        cam.location = loc
        tgt.location = aim
        if mode == "ortho":
            cam.data.type = "ORTHO"
            cam.data.ortho_scale = val
        else:
            cam.data.type = "PERSP"
            cam.data.lens = val
        scene.render.resolution_x = rx
        scene.render.resolution_y = ry
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(OUT_DIR, name)
        bpy.ops.render.render(write_still=True)
        print("RIFLE rendered %s" % name)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _OBJECTS.clear()
    build()
    ob = finish_mesh()
    export_glb(ob)
    do_renders()
    print("RIFLE done")


if __name__ == "__main__":
    main()
