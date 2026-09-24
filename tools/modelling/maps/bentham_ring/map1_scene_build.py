"""map1_scene -- map 1's five lip walls, photographed where they stand.

NOT A MODEL, and not a post hook. The walls are sculpted INTO map 1's own
mesh (map_base_build.py, LIP_WALLS), so there is no prop to place and nothing
here to export: this file is the camera crew, and it runs on its own --

    /Applications/Blender.app/Contents/MacOS/Blender -b -noaudio \\
        -P tools/modelling/maps/bentham_ring/map1_scene_build.py [-- 066 139]

It imports the shipped maps/bentham_ring/models/map_base_*.glb at identity and
tower/models/tower.glb at its guard-room datum, then writes two shots per
wall into ~/Desktop/panopticon-renders/map1/sections/ --

    map_base_lipwall_<name>_approach.png  eye level on the lane, 9 deg back
                                          down the lap, looking at the wall
                                          the runner is about to pass on the
                                          right
    map_base_lipwall_<name>_guard.png     the guard's eye, on a body standing
                                          on the lane behind the wall: what
                                          cover the wall actually is

The lap runs toward INCREASING bearing (PrisonerStart at 5 deg, the finish
at 335), so "back down the lap" is a lower bearing.

THE .GLB IS THE INPUT. map_base_build.py takes a minute to run; importing its
output takes seconds and cannot be broken by an edit in flight. If a wall is
missing from a shot, the shipped .glb is behind the script -- rebuild and
install it, do not rebuild it here.

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
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

# The arena's own numbers and the LIP_WALLS table. Read, never written: this
# script builds no geometry.
import map_base_build as mb  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    os.pardir, os.pardir, os.pardir, os.pardir))
MAP_GLBS = [os.path.join(REPO, "maps", "bentham_ring", "models", "map_base_%s.glb" % c) for c in mb.CHUNKS]
TOWER_GLB = os.path.join(REPO, "tower", "models", "tower.glb")
OUT_DIR = os.path.expanduser("~/Desktop/panopticon-renders/map1/sections")

TOWER_Y = 25.35                 # tower.glb's origin is the guard-room DATUM --
                                # bentham_ring.tscn's Tower node stands there
                                # and the model drops in at identity under it

LANE_R = 52.0                   # the walkable lane, end to end of the lap
WALL_R = 0.5 * (mb.LIP_R_IN + mb.LIP_R_OUT)   # the walls' centre line, on the lip

# ---- where the cameras stand ------------------------------------------------
APPROACH_DEG = 9.0              # 9 deg at r 52 is 8.2 m: a runner's last stride
BODY_Z = 0.90                   # a body's middle, for the guard's aim
GUARD_EYE_R = 9.0               # OUTSIDE the drum, in the void at the guard's
                                # own eye height: the shipped tower.glb's rock
                                # reaches r 8.07 there and a camera in the room
                                # renders nothing but parapet
GUARD_EYE_Z = mb.LIP_EYE_Z      # the guard's eye, as the build's proof uses it
LENS = 20.0                     # eye-level: a runner's field of view
LENS_GUARD = 85.0               # the guard is 43 m off the lane; the wall is the subject
RES = (1400, 900)
SAMPLES = 64

SUN_B = 55.0                    # key sun, degrees up the lap from the wall
SUN_EL = 38.0
FILL_B = -120.0                 # one shadowless fill from the far side: the
FILL_EL = 20.0                  # gallery is a roofed cutout
LAMP_W = 3500.0                 # two shadowless lamps that rake the rock from
LAMP_FAR_W = 1600.0             # the lip and the outer wall
SKY = (0.55, 0.50, 0.48, 1.0)   # map_base's own review background


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
    """A shipped .glb at its datum. Returns every object it made. The importer's
    Y-up conversion is the inverse of the exporter's, so map_base.glb lands in
    the frame map_base_build authored it in: Blender +Z up, deck at z 23.0."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    made = []
    for ob in set(bpy.data.objects) - before:
        if ob.parent is None:
            ob.location = (0.0, 0.0, z)
        if "colonly" in ob.name:
            ob.hide_render = True          # a collider is never in a render nor
            ob.hide_viewport = True        # in the ray tests: it shadows the art
        made.append(ob)
    bpy.context.view_layer.update()
    print("MDL note map1_scene: %s -> %d objects at z=%.2f"
          % (os.path.basename(path), len(made), z))
    return made


def _world(scene):
    if not _try(scene.render, "engine", "BLENDER_EEVEE"):
        _try(scene.render, "engine", "BLENDER_EEVEE_NEXT")
    _try(scene.eevee, "taa_render_samples", SAMPLES)
    _try(scene.eevee, "use_shadows", True)
    _try(scene.eevee, "use_raytracing", True)
    _try(scene.eevee, "shadow_ray_count", 2)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    _try(scene.view_settings, "view_transform", "Standard")
    _try(scene.view_settings, "exposure", mb.REVIEW_EXPOSURE)
    world = bpy.data.worlds.new("Map1Scene")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = SKY
    bg.inputs[1].default_value = mb.REVIEW_WORLD


def _sun(name, energy, shadow, aim_ob):
    """A sun is a DIRECTION: TRACK_TO aims it at the wall. Never rotation_euler."""
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
    """One rig for all the walls; `_stand` walks it round the lap."""
    aim = _link(bpy.data.objects.new("Map1SceneAim", None))
    target = _link(bpy.data.objects.new("Map1SceneTarget", None))
    cam = _link(bpy.data.objects.new("Map1SceneCam",
                                     bpy.data.cameras.new("Map1SceneCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")   # never rotation_euler, here
    con.target, con.track_axis, con.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    cam.data.clip_start = 0.04
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
    aim = mb.pol(bearing, WALL_R, mb.DECK_Z + 0.5 * head_z)
    rig["aim"].location = aim
    rig["sun"].location = _off(aim, bearing + SUN_B, SUN_EL)
    rig["fill"].location = _off(aim, bearing + FILL_B, FILL_EL)
    rig["lamp"].location = mb.pol(bearing + 6.0, mb.INNER_R + 1.2, mb.DECK_Z + 4.5)
    rig["lamp_far"].location = mb.pol(bearing + 10.0, mb.OUTER_R - 1.4, mb.DECK_Z + 3.0)
    bpy.context.view_layer.update()


def _shot(rig, name, view, loc, tgt, lens):
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
    path = os.path.join(OUT_DIR, "map_base_lipwall_%s_%s.png" % (name, view))
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("MDL RENDER %s (lens=%.0f %dx%d cam=(%.2f,%.2f,%.2f) aim=(%.2f,%.2f,%.2f) "
          "%.1f m -> %s at %.2f m)"
          % (os.path.basename(path), lens, RES[0], RES[1], loc[0], loc[1], loc[2],
             tgt[0], tgt[1], tgt[2], d.length,
             ob.name if hit else "nothing", (at - p).length if hit else d.length))


def shoot(rig, w):
    bearing = 0.5 * (w["b0"] + w["b1"])
    head_z = w["top"] - mb.DECK_Z
    _stand(rig, bearing, head_z)
    eye = mb.DECK_Z + mb.EYE_H                    # 1.65 m over the deck
    # the last stride before the wall, from the lane, the wall on the right
    _shot(rig, w["name"], "approach",
          mb.pol(bearing - APPROACH_DEG, LANE_R, eye),
          mb.pol(bearing, WALL_R, mb.DECK_Z + 0.5 * head_z), LENS)
    # the guard, on a body standing on the lane behind the wall
    _shot(rig, w["name"], "guard",
          mb.pol(bearing, GUARD_EYE_R, GUARD_EYE_Z),
          mb.pol(bearing, LANE_R, mb.DECK_Z + BODY_Z), LENS_GUARD)


def main():
    for path in MAP_GLBS + [TOWER_GLB]:
        if not os.path.isfile(path):
            raise SystemExit("MDL ERROR map1_scene: no %s -- build and install "
                             "the model first; this script only photographs it" % path)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    _world(scene)
    for path in MAP_GLBS:                         # the walls are already in it
        _drop_in(path, 0.0)
    _drop_in(TOWER_GLB, TOWER_Y)
    rig = _rig(scene)
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    walls = [w for w in mb.LIP_WALLS if not only or w["name"] in only]
    print("MDL note map1_scene: lip walls %s, r %.2f..%.2f"
          % (", ".join(w["name"] for w in walls), mb.LIP_R_IN, mb.LIP_R_OUT))
    for w in walls:
        print("MDL note map1_scene: wall %s b=%.1f..%.1f head %.2f m over the deck"
              % (w["name"], w["b0"], w["b1"], w["top"] - mb.DECK_Z))
        shoot(rig, w)
    print("MDL DONE map1_scene (%d shots -> %s)" % (2 * len(walls), OUT_DIR))


if __name__ == "__main__":
    main()
