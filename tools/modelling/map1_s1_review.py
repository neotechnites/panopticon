"""map1_s1_review -- S1, the spire cave (game bearings 15..60), photographed
where it stands.

NOT A MODEL and not a post hook. S1 is sculpted INTO map 1's own mesh
(map_base_build.py, the S1 section), so there is no prop to place and nothing
here to export: this file is the camera crew, and it runs on its own --

    /Applications/Blender.app/Contents/MacOS/Blender -b -noaudio \\
        -P tools/modelling/map1_s1_review.py -- <tag> [map.glb]

<tag> names the pass (it goes in every filename); the optional second argument
is the .glb to photograph, so a candidate sculpt in /tmp can be shot against
the shipped one. Default: assets/models/map_base.glb.

It imports that map .glb at identity and assets/models/tower.glb at its
guard-room datum, then writes three shots into
~/Desktop/panopticon-renders/map1/sections/ --

    map_base_<tag>_lane.png     runner eye on the lane at bearing 12, looking
                                up the lap into the cave: what the runner sees
                                coming
    map_base_<tag>_guard.png    the guard's eye at the ring centre, 5.9 m over
                                the deck: what the tower sees of the same rock.
                                tower.glb is hidden for this one shot -- the
                                camera sits inside the guard room and a mullion
                                of the drum would else fill half the frame
    map_base_<tag>_aerial.png   over the pit, 32 m up: the whole 15..60 cave in
                                one frame, for reading the forest's layout

The lap runs toward INCREASING bearing, so the lane shot looks up the lap.

THE .GLB IS THE INPUT. map_base_build.py takes minutes to run; importing its
output takes seconds and cannot be broken by an edit in flight. If a spire is
missing from a shot, the .glb is behind the script -- rebuild it, do not
rebuild it here.

Every shot prints the camera, the aim and the first thing the ray from one to
the other hits, so "is the camera in open air, and is it pointed at rock?" is
answered in the log before anyone opens a PNG. The aerial also prints where
the cave's four ground corners (15 and 60 deg, the lip and the outer foot)
land in the frame: all four inside +-1.0 means the whole cave is in shot.

The fill light here is REVIEW ONLY -- white, bright, and never exported: it is
the same recipe map_base_build's own S1 review shots use, so a spire reads the
same in both. EEVEE only: never --cpu, never --samples.
"""

import math
import os
import sys

import bpy
import bpy_extras.object_utils as obj_utils
import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

# The arena's own numbers: DECK_Z, EYE_H, the ring radii, pol(). Read, never
# written -- this script builds no geometry.
import map_base_build as mb  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    os.pardir, os.pardir))
MAP_GLB = os.path.join(REPO, "assets", "models", "map_base.glb")
TOWER_GLB = os.path.join(REPO, "assets", "models", "tower.glb")
OUT_DIR = os.path.expanduser("~/Desktop/panopticon-renders/map1/sections")

TOWER_Y = 25.35                 # tower.glb's origin is the guard-room DATUM --
                                # bentham_ring.tscn's Tower node stands there
                                # and the model drops in at identity under it

LANE_R = 52.0                   # the walkable lane, mid deck
S1_B = (15.0, 60.0)             # the section, game bearings
AIM_B = 37.0                    # the middle of the cave: every shot's subject

LANE_CAM_B = 12.0               # a stride short of the cave mouth ...
LANE_AIM_B = 36.0               # ... looking up the lap into it
LANE_AIM_Z = 1.0                # aim a metre over the deck: spires, not floor
LANE_LENS = 24.0
LANE_RES = (1600, 900)

GUARD_EYE = (0.0, 0.0, 28.90)   # Godot (0, 28.9, 0): the guard's eye, 5.9 m
                                # over the deck at the ring centre
GUARD_AIM_B = 37.0
GUARD_AIM_Z = 0.5               # a crouched body's height on the lane
GUARD_LENS = 35.0
GUARD_RES = (1600, 900)

AER_B = 37.0                    # over the pit on the cave's own bearing ...
AER_R = 22.0
AER_UP = 32.0                   # ... 32 m over the deck, looking out and down
AER_LENS = 28.0
AER_RES = (1600, 1100)

SKY = (0.55, 0.50, 0.48, 1.0)   # map_base's own review background
SKY_STRENGTH = 0.9
EXPOSURE = 0.7                  # as _s1_review uses: the cave, not the arena
SUN_W = 2.0                     # white review sun, down the shaft
FILL_B = (20.0, 31.0, 42.0, 53.0)   # four fills walked along the cave ...
FILL_R, FILL_UP, FILL_W = 51.5, 4.0, 4500.0
PIT_FILL = ((AIM_B, 38.0, 25.0, 9000.0),    # ... and two into the pit, so the
            (AIM_B, 26.0, 6.0, 30000.0))    # aerial's foreground is not black
SAMPLES = 64


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
    print("MDL note map1_s1_review: %s -> %d objects at z=%.2f"
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
    _try(scene.view_settings, "exposure", EXPOSURE)
    world = bpy.data.worlds.new("Map1S1Review")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = SKY
    bg.inputs[1].default_value = SKY_STRENGTH


def _lights():
    """Review only, never exported: a white sun down the shaft, four point
    fills walked along the cave and two more thrown into the pit."""
    aim = _link(bpy.data.objects.new("ReviewAim", None))
    aim.location = mb.pol(AIM_B, LANE_R, mb.DECK_Z)
    sd = bpy.data.lights.new("ReviewSun", type="SUN")
    sd.energy, sd.color = SUN_W, (1.0, 1.0, 1.0)
    sun = _link(bpy.data.objects.new("ReviewSun", sd))
    sun.location = (0.0, 0.0, 35.0)
    con = sun.constraints.new(type="TRACK_TO")   # a sun is a DIRECTION
    con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"
    for b in FILL_B:
        ld = bpy.data.lights.new("ReviewFill", type="POINT")
        ld.energy, ld.color, ld.shadow_soft_size = FILL_W, (1.0, 1.0, 1.0), 2.5
        _try(ld, "use_shadow", False)
        _link(bpy.data.objects.new("ReviewFill", ld)).location = \
            mb.pol(b, FILL_R, mb.DECK_Z + FILL_UP)
    for (b, r, z, w) in PIT_FILL:
        ld = bpy.data.lights.new("ReviewPitFill", type="POINT")
        ld.energy, ld.color, ld.shadow_soft_size = w, (1.0, 1.0, 1.0), 3.0
        _try(ld, "use_shadow", False)
        _link(bpy.data.objects.new("ReviewPitFill", ld)).location = mb.pol(b, r, z)
    bpy.context.view_layer.update()


def _rig(scene):
    """One camera on a TRACK_TO; `_shot` walks it round the cave."""
    target = _link(bpy.data.objects.new("S1ReviewTarget", None))
    cam = _link(bpy.data.objects.new("S1ReviewCam",
                                     bpy.data.cameras.new("S1ReviewCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")   # never rotation_euler, here
    con.target, con.track_axis, con.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    cam.data.clip_start = 0.04
    cam.data.clip_end = 900.0        # the pit wall carries on up to z 330
    return {"target": target, "cam": cam}


def _shot(rig, tag, view, loc, tgt, lens, res, hide=()):
    """`hide`: objects taken out of this shot and out of its ray test, so the
    log reports what the PNG shows. They are put straight back."""
    scene = bpy.context.scene
    cam = rig["cam"]
    for ob in hide:
        ob.hide_render = ob.hide_viewport = True
    cam.data.lens = lens
    cam.location = loc
    rig["target"].location = tgt
    scene.render.resolution_x, scene.render.resolution_y = res
    bpy.context.view_layer.update()      # constraints have not solved yet
    p, q = mathutils.Vector(loc), mathutils.Vector(tgt)
    d = q - p
    hit, at, _n, _i, ob, _m = scene.ray_cast(
        bpy.context.view_layer.depsgraph, p, d.normalized(), distance=d.length)
    path = os.path.join(OUT_DIR, "map_base_%s_%s.png" % (tag, view))
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for ob in hide:
        if "colonly" not in ob.name:            # a collider stays hidden
            ob.hide_render = ob.hide_viewport = False
    bpy.context.view_layer.update()
    print("MDL RENDER %s (lens=%.0f %dx%d cam=(%.2f,%.2f,%.2f) aim=(%.2f,%.2f,%.2f) "
          "%.1f m -> %s at %.2f m)"
          % (os.path.basename(path), lens, res[0], res[1], loc[0], loc[1], loc[2],
             tgt[0], tgt[1], tgt[2], d.length,
             ob.name if hit else "nothing", (at - p).length if hit else d.length))
    return cam


def _in_frame(cam, points):
    """Where each world point lands in the camera's frame: 0..1 across and up,
    so 0..1 on both axes and in front of the lens is in shot. Printed for the
    aerial, which has to hold the whole cave."""
    scene = bpy.context.scene
    out = []
    for (name, co) in points:
        v = obj_utils.world_to_camera_view(scene, cam, mathutils.Vector(co))
        ok = 0.0 <= v.x <= 1.0 and 0.0 <= v.y <= 1.0 and v.z > 0.0
        out.append((name, v.x, v.y, ok))
        print("MDL note map1_s1_review: corner %-12s frame (%.3f, %.3f) %s"
              % (name, v.x, v.y, "IN" if ok else "OUT OF FRAME"))
    if all(o[3] for o in out):
        print("MDL note map1_s1_review: the whole %.0f..%.0f cave is in the aerial"
              % S1_B)
    else:
        print("MDL WARN map1_s1_review: the aerial does not hold the whole cave")
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not argv:
        raise SystemExit("MDL ERROR map1_s1_review: need a tag -- "
                         "-P tools/modelling/map1_s1_review.py -- <tag> [map.glb]")
    tag = argv[0]
    map_glb = os.path.abspath(argv[1]) if len(argv) > 1 else MAP_GLB
    for path in (map_glb, TOWER_GLB):
        if not os.path.isfile(path):
            raise SystemExit("MDL ERROR map1_s1_review: no %s -- build and install "
                             "the model first; this script only photographs it" % path)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    _world(scene)
    _drop_in(map_glb, 0.0)                        # the spires are already in it
    tower = _drop_in(TOWER_GLB, TOWER_Y)
    _lights()
    rig = _rig(scene)
    print("MDL note map1_s1_review: tag %s, map %s, deck z %.2f, lane r %.1f"
          % (tag, os.path.basename(map_glb), mb.DECK_Z, LANE_R))

    eye = mb.DECK_Z + mb.EYE_H                    # 1.65 m over the deck
    _shot(rig, tag, "lane",
          mb.pol(LANE_CAM_B, LANE_R, eye),
          mb.pol(LANE_AIM_B, LANE_R, mb.DECK_Z + LANE_AIM_Z),
          LANE_LENS, LANE_RES)
    _shot(rig, tag, "guard", GUARD_EYE,
          mb.pol(GUARD_AIM_B, LANE_R, mb.DECK_Z + GUARD_AIM_Z),
          GUARD_LENS, GUARD_RES, hide=tower)
    cam = _shot(rig, tag, "aerial",
                mb.pol(AER_B, AER_R, mb.DECK_Z + AER_UP),
                mb.pol(AIM_B, LANE_R, mb.DECK_Z),
                AER_LENS, AER_RES)
    _in_frame(cam, [("b%.0f lip" % b, mb.pol(b, mb.INNER_R, mb.DECK_Z))
                    for b in S1_B]
                 + [("b%.0f foot" % b, mb.pol(b, mb.OUTER_R, mb.DECK_Z))
                    for b in S1_B])
    print("MDL DONE map1_s1_review (3 shots, tag %s -> %s)" % (tag, OUT_DIR))


if __name__ == "__main__":
    main()
