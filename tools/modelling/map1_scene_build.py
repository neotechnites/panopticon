"""map1_scene -- map 1's four cross-lane walls, photographed where they stand.

NOT A MODEL, and no longer a post hook. The walls are sculpted INTO map 1's own
mesh (map_base_build.py), so there is no prop to place and nothing here to
export: this file is the camera crew, and it runs on its own --

    /Applications/Blender.app/Contents/MacOS/Blender -b -noaudio \
        -P tools/modelling/map1_scene_build.py

It imports the shipped assets/models/map_base.glb at identity -- the walls are
already in it -- and assets/models/tower.glb at its guard-room datum, then
writes four shots per wall into ~/Desktop/panopticon-renders/map1/ --

    map1_wall_<bearing>_approach.png  eye level on the lane, 9 deg back down
                                      the lap, looking into the mouth
    map1_wall_<bearing>_through.png   standing in the mouth, along the lap
    map1_wall_<bearing>_guard.png     the guard's eye, on the deck just past
                                      the wall: what cover the wall actually is
    map1_wall_<bearing>_lip.png       from the lane, inward at the spur whose
                                      mass is what makes that cover

THE .GLB IS THE INPUT. map_base_build.py is a quarter of a megabyte of sculpt
and takes minutes to run; importing its output takes seconds and cannot be
broken by an edit in flight. If a wall is missing from a shot, the shipped .glb
is behind the script -- rebuild and install it, do not rebuild it here.

Every shot prints the camera, the aim and the first thing the ray from one to
the other hits, so "is the camera in open air, and is it pointed at rock?" is
answered in the log before anyone opens a PNG.

EEVEE only: never --cpu, never --samples.
"""

import math
import os
import sys

import bpy
import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

# The arena's own numbers -- the deck, the lip, the outer wall, and the three
# review-render constants (REVIEW_SUN / REVIEW_WORLD / REVIEW_EXPOSURE) that
# map_base_build's own review passes light with. Read, never written: this
# script builds no geometry.
import map_base_build as mb  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    os.pardir, os.pardir))
MAP_GLB = os.path.join(REPO, "assets", "models", "map_base.glb")
TOWER_GLB = os.path.join(REPO, "assets", "models", "tower.glb")
OUT_DIR = os.path.expanduser("~/Desktop/panopticon-renders/map1")

TOWER_Y = 25.35                 # tower.glb's origin is the guard-room DATUM --
                                # bentham_ring.tscn's Tower node stands there
                                # and the model drops in at identity under it

# ---- the walls, as map_base_build sculpts them ------------------------------
LANE_R = 52.0                   # the walkable lane, end to end of the lap
WALL_R = (46.8, 58.3)           # radial span: both ends buried in the ring
WALL_Z = (22.2, 31.8)           # foot under the deck (23.0), crest into the
                                # ceiling (31.88) -- it closes the gallery
WALLS = (                       # bearing, mouth width, mouth head over the deck
    (13.0, 4.60, 4.80),         # the start gate: the whole field pours through it
    (204.0, 3.60, 3.70),        # S3 | S4
    (286.0, 3.60, 3.70),        # S4 | S5
)

# ---- where the cameras stand ------------------------------------------------
APPROACH_DEG = 9.0              # 9 deg at r 52 is 8.2 m: a runner's last stride
THROUGH_DEG = 26.0              # the way-through shot looks 23.6 m down the lap
PAST_DEG = 4.0                  # "just past the wall": 3.6 m beyond the mouth
LIP_DEG = 7.0                   # the lip shot stands 6.4 m short of the spur
MARK_R = (LANE_R, LANE_R + 2.5, LANE_R - 2.5, LANE_R + 4.5)
                                # the width of deck a mark may use, in the order
                                # it is tried: the lane first, then out towards
                                # the outer wall, then in towards the lip
BODY_Z = 0.90                   # a body's middle, for the guard's aim
GUARD_EYE_R = 9.0               # OUTSIDE the drum, in the void at the guard's
                                # own eye height. Measured in the shipped
                                # tower.glb: its rock reaches r 8.07 at this
                                # height and the window sills do not open until
                                # z 27.8, so a camera in the room renders
                                # nothing but parapet. Clear at all 72 bearings
                                # tested; forest_portal_build.py hangs its tower
                                # shot at r 9.5 for the same reason.
GUARD_EYE_Z = 28.70             # the guard's eye: the room's floor SURFACE is
                                # z 27.05 in the shipped model -- 1.70 over the
                                # datum, not at it -- plus a 1.65 m body.
LENS = 20.0                     # eye-level shots: a runner's field of view, and
                                # the only lens that holds an 11.5 m wall from
                                # the 8.2 m he meets it at
LENS_LIP = 24.0                 # the spur is 7.7 m off and 5 m of rock wide
LENS_GUARD = 85.0               # the guard is 43 m off the lane, and the wall
                                # is the subject, not the gallery
RES = (1400, 900)
SAMPLES = 64

SUN_B = 55.0                    # key sun, degrees up the lap from the wall
SUN_EL = 38.0
FILL_B = -120.0                 # one shadowless fill from the far side: the
FILL_EL = 20.0                  # gallery is a roofed cutout, so a shadowed
                                # light alone leaves the inside of it black
LAMP_W = 3500.0                 # and two shadowless lamps that rake the rock
LAMP_FAR_W = 1600.0             # from the lip and the outer wall -- without
                                # them the wall is one flat red shape, and at
                                # 43 m nothing separates it from the rock
                                # behind it. The arena's torches are scene
                                # nodes and are not in the .glb.
SKY = (0.55, 0.50, 0.48, 1.0)   # map_base's own review background


# =============================================================================
# BLENDER PLUMBING -- the two helpers this script would otherwise import
# =============================================================================

def _link(ob):
    bpy.context.collection.objects.link(ob)
    return ob


def _try(owner, attr, value):
    """Set it if this Blender has it. Renders must not die on a renamed flag."""
    try:
        setattr(owner, attr, value)
        return True
    except Exception as exc:
        print("MDL note: could not set %s.%s = %r (%s)"
              % (type(owner).__name__, attr, value, exc))
        return False


def _drop_in(path, z):
    """A shipped .glb at its datum. Returns every object it made.

    The importer's Y-up conversion is the inverse of the exporter's, so
    map_base.glb lands back in the frame map_base_build authored it in: Blender
    +Z up, the deck at z 23.0, `mb.pol` valid as written.
    """
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    made = []
    for ob in set(bpy.data.objects) - before:
        if ob.parent is None:
            ob.location = (0.0, 0.0, z)
        if "colonly" in ob.name:
            ob.hide_render = True          # a collider is never in a render ...
            ob.hide_viewport = True        # ... nor in the ray tests below: it
                                           # shadows the art mesh it copies and
                                           # every proof line would name it
                                           # instead of the rock you can see
        made.append(ob)
    bpy.context.view_layer.update()
    print("MDL note map1_scene: %s -> %d objects at z=%.2f"
          % (os.path.basename(path), len(made), z))
    return made


# =============================================================================
# THE RIG
# =============================================================================

def _world(scene):
    if not _try(scene.render, "engine", "BLENDER_EEVEE"):
        _try(scene.render, "engine", "BLENDER_EEVEE_NEXT")
    _try(scene.eevee, "taa_render_samples", SAMPLES)
    _try(scene.eevee, "use_shadows", True)
    _try(scene.eevee, "use_raytracing", True)
    _try(scene.eevee, "shadow_ray_count", 2)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    # AgX turns one-colour rock into mud; Standard is the honest transform, and
    # the exposure is map_base_build's own review number.
    _try(scene.view_settings, "view_transform", "Standard")
    _try(scene.view_settings, "exposure", mb.REVIEW_EXPOSURE)

    world = bpy.data.worlds.new("Map1Scene")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = SKY
    bg.inputs[1].default_value = mb.REVIEW_WORLD


def _sun(name, energy, shadow, aim_ob):
    """A sun is a DIRECTION: TRACK_TO aims it at the wall. Never
    rotation_euler -- `_stand` moves it per wall and the constraint re-solves."""
    ld = bpy.data.lights.new(name, type="SUN")
    ld.energy, ld.color = energy, (1.0, 0.96, 0.90)
    _try(ld, "use_shadow", shadow)
    _try(ld, "angle", math.radians(1.5))
    ob = _link(bpy.data.objects.new(name, ld))
    con = ob.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = aim_ob, "TRACK_NEGATIVE_Z", "UP_Y"
    return ob


def _lamp(name, watts):
    ld = bpy.data.lights.new(name, type="POINT")
    ld.energy, ld.color = watts, (1.0, 0.86, 0.72)
    ld.shadow_soft_size = 1.6
    _try(ld, "use_shadow", False)
    return _link(bpy.data.objects.new(name, ld))


def _rig(scene):
    """One rig for all four walls; `_stand` walks it round the lap."""
    aim = _link(bpy.data.objects.new("Map1SceneAim", None))
    target = _link(bpy.data.objects.new("Map1SceneTarget", None))
    cam = _link(bpy.data.objects.new("Map1SceneCam",
                                     bpy.data.cameras.new("Map1SceneCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")   # never rotation_euler, here
    con.target, con.track_axis, con.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    cam.data.clip_start = 0.04       # the way-through camera stands IN the mouth
    cam.data.clip_end = 900.0        # the pit wall carries on up to z 330
    return {"aim": aim, "target": target, "cam": cam,
            "sun": _sun("Map1SceneSun", mb.REVIEW_SUN, True, aim),
            "fill": _sun("Map1SceneFill", mb.REVIEW_SUN * 0.55, False, aim),
            "lamp": _lamp("Map1SceneLamp", LAMP_W),
            "lamp_far": _lamp("Map1SceneLampFar", LAMP_FAR_W)}


def _off(aim, bearing, elevation, dist=200.0):
    a, e = math.radians(-bearing), math.radians(elevation)
    return (aim[0] + dist * math.cos(e) * math.cos(a),
            aim[1] + dist * math.cos(e) * math.sin(a),
            aim[2] + dist * math.sin(e))


def _stand(rig, bearing, head_z):
    """Put the whole rig on the wall at this bearing."""
    aim = mb.pol(bearing, LANE_R, mb.DECK_Z + 0.5 * head_z)
    rig["aim"].location = aim
    rig["sun"].location = _off(aim, bearing + SUN_B, SUN_EL)
    rig["fill"].location = _off(aim, bearing + FILL_B, FILL_EL)
    rig["lamp"].location = mb.pol(bearing + 6.0, mb.INNER_R + 1.2,
                                  mb.DECK_Z + 4.5)
    rig["lamp_far"].location = mb.pol(bearing + 10.0, mb.OUTER_R - 1.4,
                                      mb.DECK_Z + 3.0)
    bpy.context.view_layer.update()


def _first(p, q):
    """What the ray from p to q hits first, and how far along: (name, metres).
    Nothing in the way returns (None, the whole distance)."""
    d = mathutils.Vector(q) - mathutils.Vector(p)
    hit, at, _n, _i, ob, _m = bpy.context.scene.ray_cast(
        bpy.context.view_layer.depsgraph, mathutils.Vector(p),
        d.normalized(), distance=d.length)
    return (ob.name, (at - mathutils.Vector(p)).length) if hit else (None, d.length)


def _fan(p, tgt, spread, vspread):
    """The aim, plus four points a mouth's-width around it, as the camera sees
    it: right, left, up, down. Five rays instead of one is the difference
    between "the centre of the mouth is visible" and "the mouth is visible" --
    a boulder filling half the frame leaves the middle ray clear."""
    p, q = mathutils.Vector(p), mathutils.Vector(tgt)
    d = (q - p).normalized()
    right = d.cross(mathutils.Vector((0.0, 0.0, 1.0)))
    right = right.normalized() if right.length > 1e-6 else mathutils.Vector((1.0, 0.0, 0.0))
    up = right.cross(d).normalized()
    return [q, q + right * spread, q - right * spread,
            q + up * vspread, q - up * vspread]


def _mark(bearing, deg, tgt, z, spread, vspread, min_free=None):
    """A mark on the deck, `deg` back down the lap, that can SEE the target.

    Map 1 is not a bare annulus: a section's own rock, a sunken river bed or
    the start's masses stand exactly where a camera 8 m back would go, and a
    camera inside rock renders a texture swatch. So the mark walks out from the
    asked-for offset -- nearer and further by turns, and across the width of
    the deck, which a runner also has -- and takes the first one from which the
    whole target is in the clear. Returns (location, offset, radius).

    ``min_free`` None means the rays must reach the target: the mouth is a hole
    and a shot of it is a shot through it. A number means the target IS rock
    (the spur) and the rays must reach it from at least that far off.

    The bar is the centre ray plus three of the four around it. Demanding all
    five rejects every oblique line -- from the side of the deck one edge of a
    3.2 m mouth is always behind its own jamb -- and demanding only the centre
    accepts a boulder filling half the frame.
    """
    offsets = [float(deg)]
    for k in range(1, 14):
        offsets += [float(d) for d in (deg - k, deg + k) if 2.5 <= d <= 24.0]
    for d in offsets:
        for r in MARK_R:
            p = mb.pol(bearing + d, r, z)
            rays = []
            for q in _fan(p, tgt, spread, vspread):
                nm, dist = _first(p, q)
                rays.append((nm is None) or (min_free is not None and dist >= min_free))
            if rays[0] and sum(rays[1:]) >= 3:
                if d != deg or r != LANE_R:
                    print("MDL note map1_scene: b=%.1f mark moved to %+.1f deg "
                          "r %.1f -- the deck is not clear on the line asked for"
                          % (bearing, d, r))
                return p, d, r
    nm, dist = _first(mb.pol(bearing + deg, LANE_R, z), tgt)
    print("MDL note map1_scene: b=%.1f no clear mark anywhere on the deck "
          "(%s at %.2f m) -- shooting from %+.1f deg anyway"
          % (bearing, nm, dist, deg))
    return mb.pol(bearing + deg, LANE_R, z), deg, LANE_R


def _shot(rig, bearing, view, loc, tgt, lens):
    scene = bpy.context.scene
    cam, target = rig["cam"], rig["target"]
    cam.data.lens = lens
    cam.location = loc
    target.location = tgt
    scene.render.resolution_x, scene.render.resolution_y = RES
    bpy.context.view_layer.update()      # constraints have not solved yet
    p, q = mathutils.Vector(loc), mathutils.Vector(tgt)
    d = q - p
    hit, at, _n, _i, ob, _m = scene.ray_cast(
        bpy.context.view_layer.depsgraph, p, d.normalized(), distance=d.length)
    path = os.path.join(OUT_DIR, "map1_wall_%.1f_%s.png" % (bearing, view))
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("MDL RENDER %s (b=%.1f lens=%.0f %dx%d cam=(%.2f,%.2f,%.2f) "
          "aim=(%.2f,%.2f,%.2f) %.1f m -> %s at %.2f m)"
          % (os.path.basename(path), bearing, lens, RES[0], RES[1],
             loc[0], loc[1], loc[2], tgt[0], tgt[1], tgt[2], d.length,
             ob.name if hit else "nothing", (at - p).length if hit else d.length))


# =============================================================================
# THE FOUR SHOTS, PER WALL
# =============================================================================

def shoot(rig, bearing, mouth_w, head_z):
    _stand(rig, bearing, head_z)
    eye = mb.DECK_Z + mb.EYE_H                    # 1.65 m over the deck
    mouth = mb.pol(bearing, LANE_R, mb.DECK_Z + 0.5 * head_z)

    # the last stride before the mouth, from where the whole mouth is in view
    stand, _deg, _r = _mark(bearing, APPROACH_DEG, mouth, eye,
                            0.35 * mouth_w, 0.30 * head_z)
    _shot(rig, bearing, "approach", stand, mouth, LENS)
    # inside the pass, looking the way the lap runs (falling bearing)
    _shot(rig, bearing, "through",
          mb.pol(bearing, LANE_R, eye),
          mb.pol(bearing - THROUGH_DEG, LANE_R, eye), LENS)
    # the guard, on a body standing on the deck just past the wall
    _shot(rig, bearing, "guard",
          mb.pol(bearing, GUARD_EYE_R, GUARD_EYE_Z),
          mb.pol(bearing - PAST_DEG, LANE_R, mb.DECK_Z + BODY_Z), LENS_GUARD)
    # the spur at the pit lip: the mass that makes the cover behind the wall.
    # The aim IS rock, so the mark only has to stand 2 m clear of it.
    spur = mb.pol(bearing, mb.INNER_R + 1.0, mb.DECK_Z + 1.2)
    stand, _deg, _r = _mark(bearing, LIP_DEG, spur, eye, 1.5, 0.8, min_free=2.0)
    _shot(rig, bearing, "lip", stand, spur, LENS_LIP)


def main():
    for path in (MAP_GLB, TOWER_GLB):
        if not os.path.isfile(path):
            raise SystemExit("MDL ERROR map1_scene: no %s -- build and install "
                             "the model first; this script only photographs it"
                             % path)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    _world(scene)
    _drop_in(MAP_GLB, 0.0)                        # the walls are already in it
    _drop_in(TOWER_GLB, TOWER_Y)
    rig = _rig(scene)
    print("MDL note map1_scene: walls at %s, r %.1f..%.1f, y %.1f..%.1f"
          % (", ".join("%.1f" % w[0] for w in WALLS),
             WALL_R[0], WALL_R[1], WALL_Z[0], WALL_Z[1]))
    for bearing, mouth_w, head_z in WALLS:
        print("MDL note map1_scene: wall b=%.1f mouth %.2f x %.2f m at r %.1f"
              % (bearing, mouth_w, head_z, LANE_R))
        shoot(rig, bearing, mouth_w, head_z)
    print("MDL DONE map1_scene (%d shots -> %s)" % (4 * len(WALLS), OUT_DIR))


if __name__ == "__main__":
    main()
