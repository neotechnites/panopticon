#!/usr/bin/env python3
"""Emit scenes/ring/bentham_ring.tscn: the three-level Bentham Ring.

THE LEVELS STACK. Ryan: "the levels should be right on top of one another, not
like a staircase." All three decks are the same annulus, r44 to r60; only the
height changes. Looking down from the tower you see one column of ring, which is
what makes it a panopticon and not a wedding cake.

WHAT STACKING COSTS, AND WHERE IT IS PAID. A deck directly above another deck is
a ceiling over it, and a guard on the axis is looking DOWN and OUTWARD, so their
line into the lower galleries has to pass under that ceiling and out through the
open inner edge before the ceiling's underside cuts it off. That single
requirement fixes almost every number in this file:

    Ro * (E - (H - S)) / (E - chest)  <  Ri

  -- the ray to the far corner of a gallery must still be inboard of the deck's
  inner edge by the time it reaches the ceiling. It is why the decks are 16 m
  wide and not 25, why the gap between floors is 8.5 m and not 3, and why the
  guard's eye sits at y=27 rather than higher: RAISING the tower makes that ray
  shallower and blinds the guard to the OUTSIDE of the bottom gallery, so the
  tower is as tall as it can be and no taller.

Every number is derived here, once, from the block below, so the geometry and
the RingRoute the match is scored against cannot disagree.
Re-run with:  python3 tools/modelling/gen_bentham_ring.py
"""
import math

OUT = "scenes/ring/bentham_ring.tscn"

# --- The stack ---------------------------------------------------------------
INNER_R = 44.0              # inner edge of every deck: the gallery rail
OUTER_R = 60.0              # outer edge of every deck: the wall
LANE_R = 52.0               # the circle the runner brain steers, on every level
CLEAR_CHANNEL = 2.5         # lane +/- this is where nothing lethal may stand
RISE = 9.0                  # floor-to-floor
SLAB = 0.5                  # deck thickness, so floor-to-CEILING is RISE - SLAB

# LEVELS picks the map. 1 (default): one deck built on the new rock model,
# assets/models/map_base.glb, which ships its own geometry and collision. 3:
# the original stacked three-level ring below, kept intact for a future map.
LEVELS = 1
LEVEL_COUNT = LEVELS

# --- The tower ---------------------------------------------------------------
# assets/models/tower.glb, and its datum is the thing to get right: the model's
# ORIGIN IS THE FLOOR OF THE GUARD ROOM. The rock hangs 36.4 m below it and the
# drum's top is 9.6 m above it, so instancing it at the Tower node's identity
# puts the guard on the room floor and everything else falls where the modeller
# put it.
TOWER_MODEL_FOOT = -36.4    # model-local y of the bottom of the rock
TOWER_MODEL_TOP = 9.6       # model-local y of the top of the drum
ROOM_RADIUS = 5.1           # the chamber's interior, from the model
GUARD_EYE_HEIGHT = 1.65     # scenes/player/player.tscn puts Head here

# THE TOP DECK IS AT THE GUARD'S EYE. Ryan: "raise the top one to eye level."
# So the ring is lifted until the top gallery's walking surface is level with a
# standing guard's eye in the chamber, and the two lower galleries fall away
# beneath it -- which is the panopticon read: the guard looks flat along the top
# deck and down into the two below it.
TOWER_FLOOR_Y = 25.35
EYE_Y = TOWER_FLOOR_Y + GUARD_EYE_HEIGHT
RING_LIFT = 23.0 if LEVELS == 1 else EYE_Y - RISE * (LEVEL_COUNT - 1)
BASE_Y = RING_LIFT - 1.0    # underside of level one
COURTYARD_Y = TOWER_FLOOR_Y + TOWER_MODEL_FOOT   # the rock stands on it

WALL_T = 2.0
WALL_TOP = EYE_Y + 8.0
# LEVELS==1: map_base.glb's courtyard floor is real ground at y=COURTYARD_Y
# (-11.05), so the roof has to sit below it or a prisoner standing there would
# be inside the trigger. LEVELS==3: unchanged, 2 m under the lowest deck.
KILL_ROOF = 8.0 if LEVELS == 1 else 2.0
KILL_DEPTH = 34.0

## Radial wall on each deck, five degrees behind where the ramp from below lands.
##
## [b]The thing that makes it three laps instead of a staircase.[/b] Every ramp
## bay sits at the same bearing, so without this a prisoner who came up onto a
## deck could simply walk thirty degrees BACKWARDS and straight onto the next
## ramp -- Ryan: "i can just walk up all three levels like a staircase." This
## wall stands across the whole gallery between the landing and the foot of the
## next ramp, so the only way from one to the other is the long way round. It is
## four metres tall against a 1.11 m jump, and it sits at a bearing where the
## ramp overhead is already seven metres up, so it blocks the deck without
## fouling the climb.
DIVIDER_BACK_DEG = 5.0
DIVIDER_HEIGHT = 4.0

# --- light in the roofed galleries -------------------------------------------
GALLERY_LIGHTS = 6
GALLERY_LIGHT_LIFT = 6.0    # under the ceiling at RISE - SLAB
GALLERY_LIGHT_RANGE = 60.0
GALLERY_LIGHT_ENERGY = 9.0
TAU_DEG_TO_M = 2.0 * math.pi

# --- the chamber's collision, which the glTF does not carry ------------------
SILL_SEGMENTS = 12
SILL_HEIGHT = 0.17

## Where the tracking eyeball floats, in the tower's own space.
##
## ABOVE the tower, on Ryan's ruling -- "the eye should float abot it" -- rather
## than in the gap it used to hang in between the old eye box and the light. The
## drum's top is at %s m, the ball's radius is 2.5, so this clears the stone by
## a comfortable margin and reads as a thing hovering over the tower from every
## gallery.
WATCHER_HEIGHT = 14.0
CHEST = 0.9                 # RunnerProfile.cover_test_height, what is aimed at

LAP_DEGREES = 330.0         # one level; the remaining 30 deg is the ramp bay
ENTRY_DEG = 5.0

COVER_HEIGHTS = [3.0, 2.6, 2.2]
COVER_INNER_R = 47.0
COVER_OUTER_R = 57.0
TRAP_INNER_R = 48.5
TRAP_OUTER_R = 55.5
PIT_INNER_R = 47.0
PIT_OUTER_R = 57.0
PIT_HOLE_R = 2.5

# Both ramps are centred on the gallery's own mid-radius, so a full-width ramp
# lands wall to wall at each end. They no longer need separating by radius --
# that was to stop the lower ramp's trench opening under the upper one's foot,
# and with the trench full-width the separation is angular instead: a foot at
# the level's exit is nineteen degrees clear of the trench at its entry.
RAMP_RADII = [(INNER_R + OUTER_R) * 0.5, (INNER_R + OUTER_R) * 0.5]
RAMP_WIDTH = OUTER_R - INNER_R   # the FULL width of the gallery, wall to wall
RAMP_THICK = 1.0
RAMP_WALL_H = 2.5
RAMP_WALL_T = 1.0
RAMP_HEADROOM = 2.7         # a body is 1.8 m; the trench opens before its crown

# Cover, traps and pits, per level. Same discipline on every deck -- every
# hazard flush against a shoulder the cover band already ends at, none within
# eleven degrees of a piece of cover, and the whole ramp bay clear -- but rotated
# level by level so climbing is not the same lap three times.
# Cover, traps and pits, at the same bearings on every level -- the levels are
# the same ring, so their furniture is on the same clock face -- but with the
# INNER and OUTER band swapped level by level, so climbing a ramp puts every
# piece of cover on the other side of the racing line and level two is not level
# one again. Angles: nothing within eleven degrees of anything else, thirty-seven
# degrees of clear track out of the start for the field to converge on the lane,
# and the last seventy-three degrees clear because that is the run out to the
# ramp plus the ramp bay itself.
COVER_ANGLES = [42.0 + 25.0 * k for k in range(11)]
TRAP_ANGLES = [54.5 + 50.0 * k for k in range(5)]

# Pits are SHAFTS: one hole cut through all three decks at the same bearing and
# radius, so a fall from the top level is a fall to the kill volume rather than a
# nine metre drop onto the deck below. It is also the only way a pit can mean the
# same thing on every level of a stacked arena -- which is why these, unlike the
# cover and the traps, do not alternate by level.
PIT_ANGLES = [79.5 + 50.0 * k for k in range(5)]

## How far before a level's exit the runner brain starts drifting off the lane
## towards the ramp. Must match RingRunner.RAMP_APPROACH_METRES: the drift
## crosses the deck, and anything lethal in the way of it is a bot that cannot
## climb.
APPROACH_METRES = 20.0


def band(index, level, inner, outer):
    """Inner or outer, swapped every level."""
    return inner if (index + level) % 2 == 0 else outer


def repr_desc(text):
    """A Godot string literal for an editor_description."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def pt(angle_deg, radius):
    a = math.radians(angle_deg)
    return (math.cos(a) * radius, math.sin(a) * radius)


def yaw(rad):
    c, s = math.cos(rad), math.sin(rad)
    return (c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c)


def t3(basis, origin):
    """A Transform3D literal. [param basis] is nine numbers in the ROW order a
    .tscn uses -- see [ramp_basis] for what assuming otherwise costs."""
    return "Transform3D(%s, %s, %s, %s)" % (
        ", ".join("%.6g" % v for v in basis[0:3]),
        ", ".join("%.6g" % v for v in basis[3:6]),
        ", ".join("%.6g" % v for v in basis[6:9]),
        ", ".join("%.6g" % v for v in origin),
    )


def tangential(angle_deg):
    """Basis for a box laid ALONG the track: local X tangential, local Z radial.

    The shipped ring authored every cover box and every trap this way -- size is
    (along the track, up, across the track) -- and getting it wrong turns a 6 m
    wall presenting its face to the tower into a 6 m wall lying across the
    racing line. Which it did, once.
    """
    return yaw(math.radians(90.0 - angle_deg))


def facing_down_track(angle_deg):
    """Basis for a Marker3D whose -Z points the way the lap runs."""
    return yaw(math.radians(180.0 - angle_deg))


def deck_y(level):
    return RING_LIFT + RISE * level


def exit_deg():
    return (ENTRY_DEG + LAP_DEGREES) % 360.0


def ramp_frame(level):
    """Foot, top, pitch, length and inboard normal of the ramp off `level`."""
    radius = RAMP_RADII[level]
    fx, fz = pt(exit_deg(), radius)
    tx, tz = pt(ENTRY_DEG, radius)
    run = math.hypot(tx - fx, tz - fz)
    length = math.hypot(run, RISE)
    heading = math.atan2(tz - fz, tx - fx)
    pitch = math.atan2(RISE, run)
    px, pz = -(tz - fz) / run, (tx - fx) / run
    mx, mz = (fx + tx) * 0.5, (fz + tz) * 0.5
    if math.hypot(mx + px, mz + pz) > math.hypot(mx - px, mz - pz):
        px, pz = -px, -pz
    return dict(
        foot=(fx, deck_y(level), fz), top=(tx, deck_y(level + 1), tz),
        run=run, length=length, heading=heading, pitch=pitch,
        inboard=(px, pz), mid=(mx, mz), radius=radius,
    )


def ramp_basis(frame):
    """Basis for the pitched ramp slab: local X climbs it, local Z is its width.

    WRITTEN AS ROWS, because that is what a .tscn Transform3D literal is, and
    getting it wrong writes the TRANSPOSE -- the inverse rotation. For a box
    rotated only about Y that is merely the opposite yaw and mostly survives;
    for a slab pitched about two axes it is a ramp that comes out lying almost
    flat in mid-air, which is what happened, and which no assertion in the suite
    could have caught because the scene still loads and the numbers still look
    like a rotation. The three axes are named below and then transposed once,
    here, so the mistake cannot be made again by hand.
    """
    h, p = frame["heading"], frame["pitch"]
    ch, sh = math.cos(h), math.sin(h)
    cp, sp = math.cos(p), math.sin(p)
    x_axis = (ch * cp, sp, sh * cp)      # along the climb
    y_axis = (-ch * sp, cp, -sh * sp)    # the ramp's own up
    z_axis = (-sh, 0.0, ch)              # across its width
    return (x_axis[0], y_axis[0], z_axis[0],
            x_axis[1], y_axis[1], z_axis[1],
            x_axis[2], y_axis[2], z_axis[2])


def trench_span(level):
    """Where the ramp off `level` has to break through the deck above it.

    The fraction of the climb at which a runner's crown would otherwise meet the
    ceiling, so the slot opens before anybody hits their head on it rather than
    at the moment the ramp surface itself fouls the slab.
    """
    ceiling = deck_y(level + 1) - SLAB
    opens_at = ceiling - RAMP_HEADROOM - deck_y(level)
    return max(0.0, min(1.0, opens_at / RISE))


lines = []
W = lines.append

W('[gd_scene load_steps=%d format=3]' % (23 if LEVELS == 1 else 20))
W('')
W('[ext_resource type="Script" path="res://scripts/match/kill_volume.gd" id="1_kill_volume"]')
W('[ext_resource type="Script" path="res://scripts/match/trap_volume.gd" id="2_trap_volume"]')
W('[ext_resource type="Script" path="res://scripts/ring/tower_light.gd" id="3_tower_light"]')
W('[ext_resource type="Resource" path="res://scenes/ring/default_tower_light_profile.tres" id="4_tower_light_profile"]')
W('[ext_resource type="Script" path="res://scripts/ring/ring_route.gd" id="5_ring_route"]')
W('[ext_resource type="Script" path="res://scripts/ring/ring_level.gd" id="6_ring_level"]')
W('[ext_resource type="PackedScene" path="res://scenes/tower/watching_eye.tscn" id="7_watching_eye"]')
W('[ext_resource type="PackedScene" path="res://assets/models/tower.glb" id="8_tower_model"]')
W('[ext_resource type="Resource" path="res://scenes/ring/floating_watching_eye_profile.tres" id="9_watcher_profile"]')
if LEVELS == 1:
    W('[ext_resource type="PackedScene" path="res://assets/models/map_base.glb" id="10_map_base_model"]')
    W('[ext_resource type="Texture2D" path="res://assets/models/tower_tower_rock_albedo.png" id="11_rock_albedo"]')
W('')
for name, colour, rough in [("MatDeck", "0.42, 0.42, 0.44, 1.0", 0.95),
                            ("MatStructure", "0.27, 0.27, 0.29, 1.0", 0.95),
                            ("MatCover", "0.58, 0.57, 0.54, 1.0", 0.95),
                            ("MatRamp", "0.5, 0.48, 0.4, 1.0", 0.9),
                            ("MatStart", "0.22, 0.52, 0.28, 1.0", 0.85),
                            ("MatEnd", "0.62, 0.42, 0.14, 1.0", 0.85)]:
    W('[sub_resource type="StandardMaterial3D" id="%s"]' % name)
    W('albedo_color = Color(%s)' % colour)
    W('roughness = %s' % rough)
    W('metallic = 0.0')
    W('')
if LEVELS == 1:
    W('[sub_resource type="StandardMaterial3D" id="MatRock"]')
    W('albedo_texture = ExtResource("11_rock_albedo")')
    W('uv1_triplanar = true')
    W('roughness = 0.95')
    W('')
W('[sub_resource type="StandardMaterial3D" id="MatTrap"]')
W('resource_name = "Trap"')
W('shading_mode = 0')
W('albedo_color = Color(0.86, 0.06, 0.06, 1.0)')
W('')
W('[sub_resource type="ProceduralSkyMaterial" id="SkyMat"]')
W('sky_top_color = Color(0.05, 0.03, 0.04, 1.0)')
W('sky_horizon_color = Color(0.14, 0.06, 0.06, 1.0)')
W('ground_bottom_color = Color(0.02, 0.02, 0.02, 1.0)')
W('ground_horizon_color = Color(0.08, 0.04, 0.04, 1.0)')
W('')
W('[sub_resource type="Sky" id="Sky"]')
W('sky_material = SubResource("SkyMat")')
W('')
W('[sub_resource type="Environment" id="Env"]')
W('background_mode = 2')
W('sky = SubResource("Sky")')
W('ambient_light_source = 3')
W('ambient_light_color = Color(0.5, 0.2, 0.16, 1.0)')
W('ambient_light_energy = 0.7')
W('tonemap_mode = 2')
W('')

ceiling_gap = RISE - SLAB
lap_arc = math.radians(LAP_DEGREES)
W('[node name="BenthamRing" type="Node3D"]')
if LEVELS == 1:
    W('editor_description = %s' % repr_desc(
        "THE BENTHAM RING, one level, built on assets/models/map_base.glb -- deck annulus "
        "r=%.0f to r=%.0f at y=%.1f, pit wall down to the courtyard at y=%.1f, outer wall up to "
        "the rim. The model ships its own collision, so this generator adds no deck CSG, walls, "
        "ramps or trench for it: only the tower, cover, traps, pits, lights and markers.\n\n"
        "A prisoner runs one %.0f deg lap at r=%.0f, about %.0f m, and reaches the end pad, "
        "which takes the tower.\n\n"
        "The three-level stack this replaces is still in tools/modelling/gen_bentham_ring.py, "
        "selected by setting LEVELS = 3."
        % (INNER_R, OUTER_R, deck_y(0), COURTYARD_Y, LAP_DEGREES, LANE_R, lap_arc * LANE_R)))
else:
    W('editor_description = %s' % repr_desc(
        """THE BENTHAM RING, three levels, stacked.

A prisoner runs a full circuit of level one, takes a ramp up, runs level two, ramps up again, runs level three, and only then reaches the end pad and can take the tower. Three 360s, one route, about %.0f m of running.

THE LEVELS ARE THE SAME RING AT THREE HEIGHTS. Ryan: "the levels should be right on top of one another, not like a staircase." Every deck is the annulus r=%.0f to r=%.0f; only the height changes. From the tower you look out at one column of gallery, three storeys of it, which is Bentham's drawing rather than a wedding cake.

THE %.1f M GAP BETWEEN FLOORS IS A SIGHTLINE, NOT HEADROOM. Stack two decks and the upper one is a ceiling over the lower; the guard is on the axis looking down and out, so their line into a lower gallery has to get under that ceiling and out through the open inner edge before the slab cuts it off. The ray to the FAR corner of level one clears the ceiling at r=%.1f, which is %.1f m inboard of the gallery's own inner edge -- so the whole of every deck is visible, and the margin is the only thing between this arena and a bottom level with no game in it. Four numbers hold it: the gap, the deck's width, its inner radius, and the height of the eye. Change any of them and re-run the generator, which prints the check.

THE TOWER IS AS TALL AS IT CAN BE AND NO TALLER. Raising the eye makes that ray SHALLOWER and blinds the guard to the outside of the bottom gallery. At y=%.1f the eye is %.1f m above the top deck -- enough to look down on it and shoot into it -- and still steep enough to see the bottom one.

GENERATED. Every number comes from tools/modelling/gen_bentham_ring.py, which also emits the Route node the match is SCORED against, so the geometry and the scoring cannot drift apart."""
    % (lap_arc * LANE_R * LEVEL_COUNT, INNER_R, OUTER_R, ceiling_gap,
       OUTER_R * (EYE_Y - ceiling_gap) / (EYE_Y - CHEST),
       INNER_R - OUTER_R * (EYE_Y - ceiling_gap) / (EYE_Y - CHEST),
       EYE_Y, EYE_Y - deck_y(LEVEL_COUNT - 1))))
W('')
W('[node name="Environment" type="Node3D" parent="."]')
W('')
W('[node name="WorldEnvironment" type="WorldEnvironment" parent="Environment"]')
W('environment = SubResource("Env")')
W('')

# ------------------------------------------------------------------ ring ----
W('[node name="Ring" type="Node3D" parent="."]')
W('')

if LEVELS == 1:
    # No deck CSG: assets/models/map_base.glb is the deck, ships its own mesh
    # and collision. Pits keep their bearings and bands but become fall
    # triggers -- there is no CSG slab left to cut a hole through.
    top = deck_y(0)
    W('[node name="Pits" type="Node3D" parent="Ring"]')
    W('editor_description = "Same bearings and bands as the shaft pits used to be. Triggers now, '
      'not cut holes -- the deck is baked into map_base.glb and this cannot cut it."')
    W('')
    for index, angle in enumerate(PIT_ANGLES):
        radius = PIT_INNER_R if index % 2 == 0 else PIT_OUTER_R
        x, z = pt(angle, radius)
        name = "Pit_%03ddeg" % int(round(angle))
        W('[node name="%s" type="Area3D" parent="Ring/Pits" groups=["deck_pits"]]' % name)
        W('editor_description = %s' % repr_desc(
            "%.0f deg, r=%.2f: falls a body through to the kill volume on contact, same as the "
            "shaft pits did." % (angle, radius)))
        W('collision_layer = 0')
        W('collision_mask = 1048577')
        W('monitorable = false')
        W('transform = %s' % t3(yaw(0.0), (x, top, z)))
        W('script = ExtResource("2_trap_volume")')
        W('size_metres = Vector3(%.4f, 3.0, %.4f)' % (PIT_HOLE_R * 2.0, PIT_HOLE_R * 2.0))
        W('')
        W('[node name="Shape" type="CollisionShape3D" parent="Ring/Pits/%s"]' % name)
        W('editor_description = "Deliberately empty. TrapVolume._build_shape writes a BoxShape3D over it on ready from size_metres on the parent."')
        W('')
    W('[node name="MapBase" parent="." instance=ExtResource("10_map_base_model")]')
    W('editor_description = "assets/models/map_base.glb: the one deck -- annulus, pit wall down '
      'to the courtyard, outer wall up to the rim. Ships its own collision (MapBaseCollision-'
      'colonly), so nothing here duplicates it."')
    W('')

for level in range(LEVEL_COUNT if LEVELS == 3 else 0):
    top = deck_y(level)
    bottom = BASE_Y if level == 0 else top - SLAB
    height = top - bottom
    name = "Level%d" % (level + 1)
    W('[node name="%s" type="CSGCombiner3D" parent="Ring"]' % name)
    W('editor_description = %s' % repr_desc(
        "Level %d. The same annulus as every other level -- r=%.1f to r=%.1f -- at y=%.1f. "
        "Racing line r=%.1f, clear channel r%.2f-r%.2f. One lap is %.0f deg = %.0f m.\n\n"
        "%s"
        % (level + 1, INNER_R, OUTER_R, top, LANE_R,
           LANE_R - CLEAR_CHANNEL, LANE_R + CLEAR_CHANNEL, LAP_DEGREES, lap_arc * LANE_R,
           ("Its inner edge is open to the void and its outer edge is the wall, so it is a "
            "gallery: the guard sees into it across the middle of the map, and the only ways "
            "off it are the ramp, a pit shaft, or over the kerb into the courtyard."
            if level == 0 else
            "The slab is also the CEILING of the level below, which is why it is only %.1f m "
            "thick: every centimetre of it eats the guard's line into the gallery underneath."
            % SLAB))))
    W('use_collision = true')
    W('')
    W('[node name="Solid" type="CSGCylinder3D" parent="Ring/%s"]' % name)
    W('radius = %.4f' % OUTER_R)
    W('height = %.4f' % height)
    W('sides = 96')
    W('material = SubResource("MatDeck")')
    W('transform = %s' % t3(yaw(0.0), (0.0, (top + bottom) * 0.5, 0.0)))
    W('')
    W('[node name="Bore" type="CSGCylinder3D" parent="Ring/%s"]' % name)
    W('editor_description = "Subtract: opens the void the tower stands in and the guard looks across."')
    W('operation = 2')
    W('radius = %.4f' % INNER_R)
    W('height = %.4f' % (height + 4.0))
    W('sides = 96')
    W('transform = %s' % t3(yaw(0.0), (0.0, (top + bottom) * 0.5, 0.0)))
    W('')
    for index, angle in enumerate(PIT_ANGLES):
        radius = PIT_INNER_R if index % 2 == 0 else PIT_OUTER_R
        x, z = pt(angle, radius)
        W('[node name="Pit_%03ddeg" type="CSGCylinder3D" parent="Ring/%s" groups=["deck_pits"]]'
          % (int(round(angle)), name))
        W('editor_description = %s' % repr_desc(
            "%.0f deg, r=%.2f, %.1f m across: r%.2f-r%.2f, flush against the shoulder the cover "
            "band already ends at, so the racing line r%.2f-r%.2f is not narrowed by a "
            "centimetre.\n\n"
            "IT IS A SHAFT, NOT A HOLE. The same cut is made through all three decks at this "
            "bearing and this radius. On a stacked arena a pit that only opened one floor would "
            "be a nine metre drop onto the deck below -- a shortcut backwards, not a hazard -- "
            "and a fall from the top level would never reach the kill volume. Cut through, it "
            "means the same thing on every level and ends in the same place."
            % (angle, radius, PIT_HOLE_R * 2.0, radius - PIT_HOLE_R, radius + PIT_HOLE_R,
               LANE_R - CLEAR_CHANNEL, LANE_R + CLEAR_CHANNEL)))
        W('operation = 2')
        W('radius = %.4f' % PIT_HOLE_R)
        W('height = %.4f' % (height + 6.0))
        W('sides = 24')
        W('transform = %s' % t3(yaw(0.0), (x, (top + bottom) * 0.5, z)))
        W('')
    if level > 0:
        frame = ramp_frame(level - 1)
        t0 = trench_span(level - 1)
        fx, _, fz = frame["foot"]
        tx, _, tz = frame["top"]
        ex, ez = fx + (tx - fx) * t0, fz + (tz - fz) * t0
        cx, cz = (ex + tx) * 0.5, (ez + tz) * 0.5
        run_len = math.hypot(tx - ex, tz - ez) + 3.0
        W('[node name="RampTrench" type="CSGBox3D" parent="Ring/%s"]' % name)
        W('editor_description = %s' % repr_desc(
            "Subtract: the slot the ramp from level %d climbs out through, %.1f m of deck "
            "opened %.1f m wide against a %.1f m ramp.\n\n"
            "IT OPENS EARLY ON PURPOSE. Not where the ramp surface would foul this slab, but "
            "where a RUNNER ON IT would meet the ceiling -- %.1f m of headroom, which is a "
            "1.8 m body and room to jump. A trench cut to the slab alone is a doorway people "
            "walk into.\n\n"
            "IT SITS IN THE RAMP BAY. The %.0f degrees between this level's finish and its "
            "start are the one stretch of the lap that is never run, and every ramp, trench and "
            "pad lives in it. A body on the racing line never crosses this."
            % (level, run_len, RAMP_WIDTH + 0.4, RAMP_WIDTH, RAMP_HEADROOM,
               360.0 - LAP_DEGREES)))
        W('operation = 2')
        W('size = Vector3(%.4f, %.4f, %.4f)' % (run_len, 14.0, RAMP_WIDTH + 0.4))
        W('transform = %s' % t3(yaw(-math.atan2(tz - ez, tx - ex)), (cx, top - 5.0, cz)))
        W('')

# --- kerbs -------------------------------------------------------------------
# LEVELS==1: no kerb -- map_base.glb's own pit lip is the gallery rail.
for level in range(LEVEL_COUNT if LEVELS == 3 else 0):
    top = deck_y(level)
    ray_at_kerb = EYE_Y - (EYE_Y - (top + CHEST)) * (INNER_R + 1.0) / LANE_R - top
    W('[node name="Kerb%d" type="CSGCombiner3D" parent="Ring"]' % (level + 1))
    W('editor_description = %s' % repr_desc(
        "Level %d's gallery rail, 0.5 m tall -- the same reasoning the original kerb shipped "
        "with, and it matters more now that the inner edge is a %.1f m drop into the courtyard "
        "or onto the level below. It has to read as an edge without shadowing the deck behind "
        "it: the guard's line to a chest on this level's racing line is still %.2f m above the "
        "deck as it crosses r=%.1f."
        % (level + 1, top - COURTYARD_Y if level == 0 else RISE, ray_at_kerb, INNER_R + 1.0)))
    W('use_collision = true')
    W('')
    W('[node name="Solid" type="CSGCylinder3D" parent="Ring/Kerb%d"]' % (level + 1))
    W('radius = %.4f' % (INNER_R + 1.0))
    W('height = 0.5')
    W('sides = 96')
    W('material = SubResource("MatStructure")')
    W('transform = %s' % t3(yaw(0.0), (0.0, top + 0.25, 0.0)))
    W('')
    W('[node name="Bore" type="CSGCylinder3D" parent="Ring/Kerb%d"]' % (level + 1))
    W('operation = 2')
    W('radius = %.4f' % INNER_R)
    W('height = 2.5')
    W('sides = 96')
    W('transform = %s' % t3(yaw(0.0), (0.0, top + 0.25, 0.0)))
    W('')

# --- wall, courtyard, column -------------------------------------------------
# LEVELS==1: map_base.glb carries the wall and the courtyard floor already.
if LEVELS == 3:
    W('[node name="OuterWall" type="CSGCombiner3D" parent="Ring"]')
    W('editor_description = %s' % repr_desc(
        "r=%.1f to r=%.1f, from under level one up to y=%.1f. It is the outer wall of all three "
        "galleries at once and what their decks stand on -- one solid doing the job three separate "
        "risers did when the levels were stepped. Jump apex on the tuned movement profile is "
        "1.11 m, so no gallery can be left over it, and it is entirely outboard of every deck so it "
        "can never occlude the tower's view of ground."
        % (OUTER_R, OUTER_R + WALL_T, WALL_TOP)))
    W('use_collision = true')
    W('')
    W('[node name="WallSolid" type="CSGCylinder3D" parent="Ring/OuterWall"]')
    W('radius = %.4f' % (OUTER_R + WALL_T))
    W('height = %.4f' % (WALL_TOP - BASE_Y))
    W('sides = 96')
    W('material = SubResource("MatStructure")')
    W('transform = %s' % t3(yaw(0.0), (0.0, (WALL_TOP + BASE_Y) * 0.5, 0.0)))
    W('')
    W('[node name="WallBore" type="CSGCylinder3D" parent="Ring/OuterWall"]')
    W('operation = 2')
    W('radius = %.4f' % OUTER_R)
    W('height = %.4f' % (WALL_TOP - BASE_Y + 4.0))
    W('sides = 96')
    W('transform = %s' % t3(yaw(0.0), (0.0, (WALL_TOP + BASE_Y) * 0.5, 0.0)))
    W('')
    W('[node name="Courtyard" type="CSGCylinder3D" parent="Ring"]')
    W('editor_description = %s' % repr_desc(
        "Courtyard floor %.1f m below level one, filling the void the tower stands in. The middle of "
        "the map is a drop, not a shortcut, and it sits inside KillBox's roof so it is no hiding "
        "place either."
        % (-COURTYARD_Y)))
    W('use_collision = true')
    W('radius = %.4f' % INNER_R)
    W('height = 1.0')
    W('sides = 96')
    W('material = SubResource("MatStructure")')
    W('transform = %s' % t3(yaw(0.0), (0.0, COURTYARD_Y - 0.5, 0.0)))
    W('')
# --- the level dividers ------------------------------------------------------
# Level one only. Every level above it has a full-width trench cut through its
# deck in the same bay -- the slot the ramp climbs out of -- and a hole in the
# floor stops a prisoner walking backwards rather better than a wall does.
# LEVELS==1: no ramp, so no staircase to block -- nothing to emit.
for level in range(1 if LEVELS == 3 else 0):
    top = deck_y(level)
    angle = ENTRY_DEG - DIVIDER_BACK_DEG
    x, z = pt(angle, (INNER_R + OUTER_R) * 0.5)
    W('[node name="Divider%d" type="CSGBox3D" parent="Ring"]' % (level + 1))
    W('editor_description = %s' % repr_desc(
        "Level %d's back wall: a radial slab at %.0f deg, r=%.1f to r=%.1f, %.1f m tall.\n\n"
        "WITHOUT IT THE ARENA IS A STAIRCASE. Every ramp bay is at the same bearing, so a "
        "prisoner who came up onto this deck at %.0f deg could turn round, walk thirty degrees "
        "backwards, and step straight onto the next ramp -- three levels climbed without running "
        "a metre of any of them. This stands between the landing and the foot of the next ramp, "
        "across the whole gallery, so the only route from one to the other is the whole lap. "
        "Four metres against a 1.11 m jump.\n\n"
        "It clears the climb: the ramp off this level is already %.1f m overhead by the time it "
        "reaches this bearing, so the wall blocks the deck and nothing else."
        % (level + 1, angle, INNER_R, OUTER_R, DIVIDER_HEIGHT, ENTRY_DEG,
           RISE * (360.0 - LAP_DEGREES - DIVIDER_BACK_DEG) / (360.0 - LAP_DEGREES))))
    W('use_collision = true')
    W('size = Vector3(%.4f, %.4f, 1.0)' % (OUTER_R - INNER_R, DIVIDER_HEIGHT))
    W('material = SubResource("MatStructure")')
    W('transform = %s' % t3(tangential(angle + 90.0), (x, top + DIVIDER_HEIGHT * 0.5, z)))
    W('')

# --- the light in the lower galleries ----------------------------------------
# LEVELS==1: map_base.glb's deck has a rock ceiling too (deck + 8.5), which
# blocks KeyLight exactly as a stacked gallery's slab does. Ryan: "because the
# ring has a ceiling, its not bright enough... hard to see as the runner."
if LEVELS == 1:
    W('[node name="GalleryLights" type="Node3D" parent="Ring"]')
    W('editor_description = %s' % repr_desc(
        "Under the rock ceiling, which KeyLight cannot reach through. Twelve omnis at r=%.1f, "
        "30 deg apart, matching KeyLight and TowerLightProfile's colour." % LANE_R))
    W('')
    for index in range(12):
        angle = 30.0 * index
        x, z = pt(angle, LANE_R)
        W('[node name="Gallery1_%03ddeg" type="OmniLight3D" parent="Ring/GalleryLights"]'
          % int(round(angle)))
        W('transform = %s' % t3(yaw(0.0), (x, deck_y(0) + 7.5, z)))
        W('light_color = Color(1.0, 0.44, 0.34, 1.0)')
        W('light_energy = %.2f' % GALLERY_LIGHT_ENERGY)
        W('omni_range = %.2f' % GALLERY_LIGHT_RANGE)
        W('omni_attenuation = 0.7')
        W('shadow_enabled = false')
        W('')
if LEVELS == 3:
    W('[node name="GalleryLights" type="Node3D" parent="Ring"]')
    W('editor_description = %s' % repr_desc(
        "LIGHT FOR THE ROOFED GALLERIES, and it exists because stacking the decks put the bottom "
        "two of them in the dark. Ryan, twice: \"still cant see light on the bottom floors.\"\n\n"
        "KeyLight is a DirectionalLight3D over the tower and it lights the TOP gallery, which is "
        "open to the sky. It cannot reach the two below it, because the deck above each of them is "
        "a solid roof -- that is what stacking means, and no amount of energy on a light above the "
        "tower will get under it. So each roofed gallery carries its own ring of six omnis, hung "
        "%.1f m up under its own ceiling at the racing line, %.0f degrees apart, which is about "
        "%.0f m of arc between neighbours against a %.0f m range.\n\n"
        "SHADOWS OFF, DELIBERATELY. Twelve shadow-casting omnis over CSG is not a cost this greybox "
        "should pay, and the price of leaving them off is that a light in one gallery bleeds faintly "
        "through the slab into the next. In a red-lit greybox that reads as bounce; with shadows on "
        "it would read as a framerate. Reddish, matching KeyLight and TowerLightProfile, so the "
        "whole arena stays one mood.\n\n"
        "UNVERIFIED: nobody has seen these running -- Godot must not be launched on Ryan's Mac."
        % (GALLERY_LIGHT_LIFT, 360.0 / GALLERY_LIGHTS,
           TAU_DEG_TO_M * LANE_R / GALLERY_LIGHTS, GALLERY_LIGHT_RANGE)))
    W('')
for level in range(LEVEL_COUNT - 1 if LEVELS == 3 else 0):
    for index in range(GALLERY_LIGHTS):
        angle = 360.0 * float(index) / float(GALLERY_LIGHTS) + 15.0
        x, z = pt(angle, LANE_R)
        W('[node name="Gallery%d_%03ddeg" type="OmniLight3D" parent="Ring/GalleryLights"]'
          % (level + 1, int(round(angle))))
        W('transform = %s' % t3(yaw(0.0), (x, deck_y(level) + GALLERY_LIGHT_LIFT, z)))
        W('light_color = Color(1.0, 0.44, 0.34, 1.0)')
        W('light_energy = %.2f' % GALLERY_LIGHT_ENERGY)
        W('omni_range = %.2f' % GALLERY_LIGHT_RANGE)
        W('omni_attenuation = 0.7')
        W('shadow_enabled = false')
        W('')

# --- ramps -------------------------------------------------------------------
# LEVELS==1: one level, no climb -- no Ramps node at all.
if LEVELS == 3:
    W('[node name="Ramps" type="Node3D" parent="."]')
    W('editor_description = %s' % repr_desc(
        "How a prisoner gets up a level, and Ryan's ruling on it: \"travel between levels can just "
        "be a simple ramp from one to the next, behind cover.\"\n\n"
        "One ramp per transition, no more. Each starts at its level's FINISH, so the arc is "
        "complete before the climb begins and a level cannot be skipped by finding the ramp early. "
        "Each is a straight pitched slab inside the same annulus the decks are -- there is nowhere "
        "else for it to be, now that the levels are stacked -- so it climbs the %.0f degree bay "
        "between a level's finish and its start and breaks up through a trench in the deck above.\n\n"
        "THE TWO RAMPS ARE AT DIFFERENT RADII (r=%.0f and r=%.0f) so that the trench the lower one "
        "punches through level two does not open underneath the foot of the upper one.\n\n"
        "EACH CARRIES A WALL ALONG ITS TOWER-FACING EDGE, pitched with it so it covers the whole "
        "climb rather than the first third. That is the \"behind cover\" half, and it is not "
        "decoration: a ramp is a long straight slow piece of ground with the guard looking straight "
        "down the length of it, and without the wall it would simply be the place everybody dies."
        % (360.0 - LAP_DEGREES, RAMP_RADII[0], RAMP_RADII[1])))
    W('')
for level in range(LEVEL_COUNT - 1 if LEVELS == 3 else 0):
    frame = ramp_frame(level)
    basis = ramp_basis(frame)
    cx = (frame["foot"][0] + frame["top"][0]) * 0.5
    cy = (frame["foot"][1] + frame["top"][1]) * 0.5
    cz = (frame["foot"][2] + frame["top"][2]) * 0.5
    W('[node name="Ramp%dto%d" type="CSGBox3D" parent="Ramps"]' % (level + 1, level + 2))
    W('editor_description = %s' % repr_desc(
        "Level %d to level %d. Foot at %.0f deg on the lower deck, top at %.0f deg on the upper "
        "one, both at r=%.1f: %.1f m of run for %.1f m of rise, a %.1f degree slope, well inside "
        "anything the character controller treats as floor.\n\n"
        "It is one box, pitched, its top face the walking surface, and it is the FULL WIDTH of "
        "the gallery -- Ryan: \"theres no reason for the ramp not to be the full thickness of "
        "the level.\" A narrow chute inside a sixteen metre deck was a thing to miss and a "
        "thing to be funnelled into; wall to wall, the ramp simply IS the floor for the length "
        "of the bay, and the walls on it are the gallery's own edges. Being a straight chord "
        "across a %.0f degree bay it sags %.1f m inboard at the middle, so its inner lip "
        "overhangs the void by that much halfway up, and its centreline is r=%.1f."
        % (level + 1, level + 2, exit_deg(), ENTRY_DEG, frame["radius"],
           frame["run"], RISE, math.degrees(frame["pitch"]), 360.0 - LAP_DEGREES,
           frame["radius"] * (1.0 - math.cos(math.radians((360.0 - LAP_DEGREES) * 0.5))),
           frame["radius"])))
    W('use_collision = true')
    W('size = Vector3(%.4f, %.4f, %.4f)' % (frame["length"] + 2.0, RAMP_THICK, RAMP_WIDTH))
    W('material = SubResource("MatRamp")')
    W('transform = %s' % t3(basis, (cx, cy - RAMP_THICK * 0.5, cz)))
    W('')
    px, pz = frame["inboard"]
    for side, sign in (("Cover", 1.0), ("Rail", -1.0)):
        ox = cx + px * sign * (RAMP_WIDTH * 0.5 - RAMP_WALL_T * 0.5)
        oz = cz + pz * sign * (RAMP_WIDTH * 0.5 - RAMP_WALL_T * 0.5)
        W('[node name="Ramp%dto%d%s" type="CSGBox3D" parent="Ramps"]'
          % (level + 1, level + 2, side))
        if sign > 0.0:
            W('editor_description = %s' % repr_desc(
                "The cover on the ramp: %.1f m tall, standing on the climb's TOWER-FACING edge "
                "and pitched with it, so it covers the whole ascent rather than the first "
                "third. This is Ryan's \"behind cover\" half -- a ramp is a long straight slow "
                "piece of ground with the guard looking down the length of it, and without this "
                "it is simply the place everybody dies. Its height is capped by the ceiling the "
                "ramp climbs towards: any taller and it would be buried in the slab above "
                "before the trench opens." % RAMP_WALL_H))
        else:
            W('editor_description = %s' % repr_desc(
                "The rail on the ramp's outboard edge, the same %.1f m. With this and the cover "
                "opposite, the ramp is a CHUTE: the only ways on and off it are its two ends. "
                "That is not tidiness -- Ryan: \"there no walls on the ramps. i can just walk up "
                "all three levels like a staircase.\" An open-sided ramp is a ledge you can step "
                "onto anywhere along its length, which turns three laps into three steps."
                % RAMP_WALL_H))
        W('use_collision = true')
        W('size = Vector3(%.4f, %.4f, %.4f)'
          % (frame["length"] - 2.0, RAMP_WALL_H, RAMP_WALL_T))
        W('material = SubResource("MatCover")')
        W('transform = %s' % t3(basis, (ox, cy + RAMP_WALL_H * 0.5, oz)))
        W('')

# --- kill volume -------------------------------------------------------------
W('[node name="KillBox" type="Area3D" parent="."]')
if LEVELS == 1:
    W('editor_description = %s' % repr_desc(
        "The kill box under the one-level ring. Roof at y=-%.1f -- raised from the deeper roof "
        "this used to have so a body falling off the outer rim is caught before it lands on rock "
        "and gets stuck, rather than only one that falls all the way past the courtyard.\n\n"
        "It is a trigger and nothing else: no collision of its own, monitorable off, mask 1048577 "
        "(bit 0, a living body's layer, plus bit 20, MatchController.GHOST_HAZARD_LAYER) so a "
        "ghost is seen falling too.\n\n"
        "WHAT IT DOES IS NOT DECIDED HERE. scripts/match/kill_volume.gd resolves whatever entered "
        "to a participant and hands it to MatchController.handle_fall() -- the same door the "
        "rifle, the pit triggers and the red traps kill through."
        % KILL_ROOF))
else:
    W('editor_description = %s' % repr_desc(
        "The kill box under the arena, and the one node that had to grow with the levels rather "
        "than gain a copy per level.\n\n"
        "RADIUS %.1f, WHICH IS THE OUTER WALL. Everything that walks in PANOPTICON walks on one of "
        "four surfaces -- three galleries and the guard's platform -- and %d shafts are cut clean "
        "through all three decks, the outermost reaching r=%.1f. The roof is at y=-%.1f: the lowest "
        "structure in the arena bottoms out at y=%.1f and there is no walkable surface between "
        "them, so ONE roof answers a fall from ANY level. A prisoner who drops through a shaft on "
        "level three falls %.1f m into it without touching a thing.\n\n"
        "It is a trigger and nothing else: no collision of its own, monitorable off, and a mask of "
        "1048577 (bit 0, the layer a living body is on, plus bit 20, "
        "MatchController.GHOST_HAZARD_LAYER) so a prisoner and a ghost are both seen falling in. "
        "The courtyard floor is inside it too, which is what makes the middle of the map a drop.\n\n"
        "WHAT IT DOES IS NOT DECIDED HERE. scripts/match/kill_volume.gd resolves whatever entered "
        "to a participant and hands it to MatchController.handle_fall() -- the same door the rifle "
        "and the red traps kill through."
        % (OUTER_R + WALL_T, len(PIT_ANGLES), PIT_OUTER_R + PIT_HOLE_R, KILL_ROOF, BASE_Y,
           deck_y(LEVEL_COUNT - 1) + KILL_ROOF)))
W('collision_layer = 0')
W('collision_mask = 1048577')
W('monitorable = false')
W('script = ExtResource("1_kill_volume")')
W('radius_metres = %.4f' % (OUTER_R + WALL_T))
W('roof_depth_metres = %.4f' % KILL_ROOF)
W('depth_metres = %.4f' % KILL_DEPTH)
W('')
W('[node name="Shape" type="CollisionShape3D" parent="KillBox"]')
W('editor_description = "Deliberately empty. KillVolume._build_shape writes a CylinderShape3D over it on ready, from the exports on the parent."')
W('')

# --- start and end -----------------------------------------------------------
sx, sz = pt(ENTRY_DEG, LANE_R)
ex, ez = pt(exit_deg(), LANE_R)
top_y = deck_y(LEVEL_COUNT - 1)
W('[node name="StartEnd" type="Node3D" parent="."]')
if LEVELS == 1:
    W('editor_description = %s' % repr_desc(
        "One level, one lap: start and finish are both on the deck at y=%.1f, %.0f deg apart "
        "around the ring -- the gap is the old ramp bay, unused now."
        % (top_y, 360.0 - LAP_DEGREES)))
else:
    W('editor_description = %s' % repr_desc(
        "The start is on level one and the end is on level three, directly above it. That is the "
        "whole change in one sentence: a prisoner no longer finishes a few metres behind where they "
        "set off, they finish %.0f m above it, level with the tower they are running at."
        % top_y))
W('')
W('[node name="StartPad" type="CSGBox3D" parent="StartEnd"]')
W('editor_description = "Visual decal only -- use_collision is off so this 0.1 m plate is never a step the character controller has to climb."')
W('size = Vector3(6.0, 0.1, 6.0)')
W('material = SubResource("MatStart")')
W('transform = %s' % t3(tangential(ENTRY_DEG), (sx, deck_y(0) + 0.05, sz)))
W('')
W('[node name="PrisonerStart" type="Marker3D" parent="StartEnd"]')
W('editor_description = %s' % repr_desc(
    "%.1f deg on level one's racing line, y=%.1f. Its ANGLE is what places the field -- "
    "MatchController deals them sideways across the width of the track from here -- but its "
    "HEIGHT is load-bearing too, and was the one number missed when the ring was lifted to put "
    "its top deck at the guard's eye: a marker left on the old datum is a start line nine "
    "metres under the floor, and every body dealt onto it falls out of the world before it has "
    "taken a step."
    % (ENTRY_DEG, deck_y(0))))
W('transform = %s' % t3(facing_down_track(ENTRY_DEG), (sx, deck_y(0), sz)))
W('')
W('[node name="EndPad" type="CSGBox3D" parent="StartEnd"]')
W('editor_description = "Visual decal only, as StartPad. %s"'
  % ("It is on the same deck as the start." if LEVELS == 1 else "It is on LEVEL THREE."))
W('size = Vector3(6.0, 0.1, 6.0)')
W('material = SubResource("MatEnd")')
W('transform = %s' % t3(tangential(exit_deg()), (ex, top_y + 0.05, ez)))
W('')
W('[node name="PrisonerEnd" type="Marker3D" parent="StartEnd"]')
W('editor_description = %s' % repr_desc(
    "%.1f deg on %s's racing line, y=%.1f. This is the end of the whole route, not the "
    "end of a lap: reaching it is what takes the tower."
    % (exit_deg(), "the level" if LEVELS == 1 else "level three", top_y)))
W('transform = %s' % t3(facing_down_track(exit_deg()), (ex, top_y, ez)))
W('')

# --- start/finish wall --------------------------------------------------------
# LEVELS==1 only: the route runs LAP_DEGREES of the ring, so 360-LAP_DEGREES is a
# gap between finish and start a runner could otherwise walk backwards through.
if LEVELS == 1:
    gap_deg = 360.0 - LAP_DEGREES
    gap_mid = (exit_deg() + ENTRY_DEG + 360.0) * 0.5 % 360.0
    wx, wz = pt(gap_mid, (INNER_R + OUTER_R) * 0.5)
    wall_h = ceiling_gap
    W('[node name="StartFinishWall" type="CSGBox3D" parent="."]')
    W('editor_description = %s' % repr_desc(
        "Blocks the %.0f deg gap between finish (%.0f deg) and start (%.0f deg) -- without it a "
        "runner can walk backwards through it from start to finish."
        % (gap_deg, exit_deg(), ENTRY_DEG)))
    W('use_collision = true')
    W('size = Vector3(%.4f, %.4f, 1.0)' % (OUTER_R - INNER_R, wall_h))
    W('material = SubResource("MatRock")')
    W('transform = %s' % t3(tangential(gap_mid + 90.0), (wx, deck_y(0) + wall_h * 0.5, wz)))
    W('')

# --- cover -------------------------------------------------------------------
W('[node name="Cover" type="Node3D" parent="."]')
if LEVELS == 1:
    W('editor_description = %s' % repr_desc(
        "Cover on the one deck, two radial bands at r=%.0f and r=%.0f -- one either side of the "
        "racing line, which is what a %.0f m deck has room for. Height %.1f m: far above the "
        "1.11 m jump, so it cannot be hopped, and tuned to the guard's %.0f degree look down from "
        "the tower so a piece's shadow stays a few metres, not a corridor."
        % (COVER_INNER_R, COVER_OUTER_R, OUTER_R - INNER_R, COVER_HEIGHTS[0],
           math.degrees(math.atan2(EYE_Y - deck_y(0) - CHEST, LANE_R)))))
else:
    W('editor_description = %s' % repr_desc(
        "Cover on all three levels, grouped by level, two radial bands per level at r=%.0f and "
        "r=%.0f -- one either side of the racing line, which is what a %.0f m deck has room for.\n\n"
        "COVER GETS SHORTER AS THE LEVELS RISE, AND THAT IS ARITHMETIC RATHER THAN TASTE. The "
        "shadow a box throws is set by how steeply the guard looks down on it. Level one sits %.1f m "
        "under the eye, a %.0f degree look; level three sits only %.1f m under it, a %.0f degree "
        "look. Give all three the same 3 m box and level three's shadows run three times as long as "
        "level one's, and the top of the arena becomes one continuous covered corridor -- a level "
        "the guard can see and can never shoot into, which is as dead as one they cannot see at "
        "all. Heights of %.1f / %.1f / %.1f m hold the shadow behind a piece to roughly the same "
        "few metres on every level. All three are far above the 1.11 m jump, so none can be hopped."
        % (COVER_INNER_R, COVER_OUTER_R, OUTER_R - INNER_R,
           EYE_Y, math.degrees(math.atan2(EYE_Y - CHEST, LANE_R)),
           EYE_Y - deck_y(LEVEL_COUNT - 1),
           math.degrees(math.atan2(EYE_Y - deck_y(LEVEL_COUNT - 1) - CHEST, LANE_R)),
           COVER_HEIGHTS[0], COVER_HEIGHTS[1], COVER_HEIGHTS[2])))
W('')
for level in range(LEVEL_COUNT):
    top = deck_y(level)
    height = COVER_HEIGHTS[level]
    W('[node name="Level%d" type="Node3D" parent="Cover"]' % (level + 1))
    if LEVELS == 1:
        W('editor_description = "Cover on the deck: %d pieces, 6.0 x %.1f x 1.5 m, faces tangential so each presents its full width to the tower."'
          % (len(COVER_ANGLES), height))
    else:
        W('editor_description = "Cover on level %d: %d pieces, 6.0 x %.1f x 1.5 m, faces tangential so each presents its full width to the tower. Rotated off the level below so a climb is not the same lap again."'
          % (level + 1, len(COVER_ANGLES), height))
    W('')
    for index, angle in enumerate(COVER_ANGLES):
        radius = band(index, level, COVER_INNER_R, COVER_OUTER_R)
        x, z = pt(angle, radius)
        W('[node name="Cover_%03ddeg" type="CSGBox3D" parent="Cover/Level%d"]'
          % (int(round(angle)), level + 1))
        W('editor_description = "%.0f deg, r=%.1f on level %d. The 6 m face is tangential to the track."'
          % (angle, radius, level + 1))
        W('use_collision = true')
        W('size = Vector3(6.0, %.4f, 1.5)' % height)
        W('material = SubResource("MatCover")')
        W('transform = %s' % t3(tangential(angle), (x, top + height * 0.5, z)))
        W('')

# --- traps -------------------------------------------------------------------
W('[node name="Traps" type="Node3D" parent="."]')
if LEVELS == 1:
    W('editor_description = %s' % repr_desc(
        "Red blocks that kill on contact. Read them with Ring/Pits: eleven places on the route "
        "are lethal a couple of metres off the racing line, six standing up in red and five fall "
        "triggers.\n\n"
        "NO RACING LINE IS NARROWED. The shipped RingRunner baseline has no obstacle avoidance: it "
        "faces a point on the lane circle a few metres ahead and holds full forward. So every "
        "trap and pit is flush against a shoulder the cover band already ends at, and the clear "
        "channel is r%.2f-r%.2f. No trap is within eleven degrees of a piece of cover.\n\n"
        "WHAT A TRAP DOES IS NOT DECIDED HERE: scripts/match/trap_volume.gd hands the body to "
        "MatchController.handle_fall(). Touching red and being shot are the same death. The blocks "
        "carry no collision, so they are not cover and they occlude nothing."
        % (LANE_R - CLEAR_CHANNEL, LANE_R + CLEAR_CHANNEL)))
else:
    W('editor_description = %s' % repr_desc(
        "Red blocks that kill on contact, on every level -- hazards live across the levels and not "
        "only on the bottom one. Read them with the pit shafts: at eighteen places on the route the "
        "deck is lethal a couple of metres off the racing line, six of them standing up in red on "
        "each floor and six of them holes cut through all three.\n\n"
        "NO RACING LINE IS NARROWED, ON ANY LEVEL. The shipped RingRunner baseline has no obstacle "
        "avoidance whatsoever: it faces a point on its level's lane circle a few metres ahead and "
        "holds full forward. Anything standing on that circle would stop a bot dead and break the "
        "game. So every trap and every shaft is flush against a shoulder the cover band already "
        "ends at, and the clear channel is r%.2f-r%.2f on all three levels. tests/test_traps.gd "
        "asserts it for every level in the route rather than for one radius.\n\n"
        "ANGLES. No trap is within eleven degrees of a piece of cover, and the ramp bay is clear on "
        "every level so the run out to a ramp is never blocked.\n\n"
        "WHAT A TRAP DOES IS NOT DECIDED HERE: scripts/match/trap_volume.gd hands the body to "
        "MatchController.handle_fall(). Touching red and being shot are the same death. The blocks "
        "carry no collision, so they are not cover and they occlude nothing."
        % (LANE_R - CLEAR_CHANNEL, LANE_R + CLEAR_CHANNEL)))
W('')
for level in range(LEVEL_COUNT):
    top = deck_y(level)
    for index, angle in enumerate(TRAP_ANGLES):
        radius = band(index, level, TRAP_INNER_R, TRAP_OUTER_R)
        x, z = pt(angle, radius)
        name = "Trap_L%d_%03ddeg" % (level + 1, int(round(angle)))
        W('[node name="%s" type="Area3D" parent="Traps"]' % name)
        W('editor_description = %s' % repr_desc(
            "%.0f deg on level %d, r=%.2f, so it spans r%.2f-r%.2f and stops dead on the "
            "shoulder the cover band already ends at. The clear channel r%.2f-r%.2f is "
            "untouched. 2.2 m tall: the tuned MovementProfile jumps 1.11 m, so it cannot be "
            "hopped and has to be gone around."
            % (angle, level + 1, radius, radius - 1.0, radius + 1.0,
               LANE_R - CLEAR_CHANNEL, LANE_R + CLEAR_CHANNEL)))
        W('collision_layer = 0')
        W('collision_mask = 1048577')
        W('monitorable = false')
        W('transform = %s' % t3(tangential(angle), (x, top + 1.1, z)))
        W('script = ExtResource("2_trap_volume")')
        W('size_metres = Vector3(5.0, 2.2, 2.0)')
        W('')
        W('[node name="Shape" type="CollisionShape3D" parent="Traps/%s"]' % name)
        W('editor_description = "Deliberately empty. TrapVolume._build_shape writes a BoxShape3D over it on ready from size_metres on the parent."')
        W('')
        W('[node name="Block" type="CSGBox3D" parent="Traps/%s"]' % name)
        W('editor_description = "The red you see. use_collision is off on purpose -- a solid block would be new cover, a new occluder, and something the avoidance-free runner brain could grind against."')
        W('material = SubResource("MatTrap")')
        W('')

# --- the route ---------------------------------------------------------------
W('[node name="Route" type="Node3D" parent="."]')
if LEVELS == 1:
    W('editor_description = %s' % repr_desc(
        "WHAT PROGRESS IS: the arc swept so far on the one lap, taken at the lane radius. "
        "IT IS DATA, AND IT LIVES ON THE MAP. The deck height, radial band, lane radius, entry "
        "angle and exit angle are here, and MatchLapTracker, RingRunner, the HUD and the round "
        "card all read them from here rather than from a second copy."))
else:
    W('editor_description = %s' % repr_desc(
        "WHAT PROGRESS IS, now that there are three levels. One monotonic distance along a "
        "three-lap route: the metres banked for every level finished, plus the arc swept so far on "
        "the current one taken at that level's own lane radius. Arc alone stopped being an answer "
        "the moment a second deck existed at the SAME angle and the same radius, nine metres up -- "
        "which, the levels being stacked, is every angle. A raw metre count of the path walked was "
        "never one: a prisoner who paces about behind cover would out-score one who ran.\n\n"
        "A level is finished when BOTH tests pass: the arc for that level is swept, AND the body is "
        "standing at the height of the level above. The arc alone would let a runner who found the "
        "ramp early bank a level they had not run; the height alone would let one who walked up the "
        "bay from the start bank two. Together they say exactly what Ryan asked for -- you have to "
        "complete three 360s to get to the tower.\n\n"
        "IT IS DATA, AND IT LIVES ON THE MAP. Every level's deck height, radial band, lane radius, "
        "entry angle, exit angle and ramp radii are here, and MatchLapTracker, RingRunner, the HUD "
        "and the round card all read them from here. A flat one-lap arena carries no Route node at "
        "all and MatchController builds a single-level route from MatchRules.track_radius and the "
        "markers, so there is exactly one code path and a second map does not need a second one."))
W('script = ExtResource("5_ring_route")')
W('')
for level in range(LEVEL_COUNT):
    name = "Level%d" % (level + 1)
    has_ramp = level < LEVEL_COUNT - 1
    W('[node name="%s" type="Node3D" parent="Route"]' % name)
    W('editor_description = %s' % repr_desc(
        "Level %d: deck y=%.1f, r%.1f-r%.1f, lane r=%.1f, %.0f deg to %.0f deg = %.0f deg of "
        "lap, %.0f m.%s"
        % (level + 1, deck_y(level), INNER_R, OUTER_R, LANE_R, ENTRY_DEG, exit_deg(),
           LAP_DEGREES, lap_arc * LANE_R,
           (" The exit is the foot of the ramp up, at r=%.1f, landing on the level above at the "
            "same radius." % RAMP_RADII[level]) if has_ramp else
            " Its exit is the finish of the whole route.")))
    W('script = ExtResource("6_ring_level")')
    W('deck_height = %.4f' % deck_y(level))
    W('inner_radius = %.4f' % INNER_R)
    W('outer_radius = %.4f' % OUTER_R)
    W('lane_radius = %.4f' % LANE_R)
    W('entry_angle_degrees = %.4f' % ENTRY_DEG)
    W('exit_angle_degrees = %.4f' % exit_deg())
    W('ramp_foot_radius = %.4f' % (RAMP_RADII[level] if has_ramp else 0.0))
    W('ramp_landing_radius = %.4f' % (RAMP_RADII[level] if has_ramp else 0.0))
    W('')

# --- tower -------------------------------------------------------------------
W('[node name="Tower" type="Node3D" parent="."]')
if LEVELS == 1:
    W('editor_description = %s' % repr_desc(
        "The tower, and its origin is the FLOOR OF THE GUARD ROOM at y=%.2f. That is the model's "
        "own datum: assets/models/tower.glb hangs its rock %.1f m below this point and carries the "
        "top of its drum %.1f m above it, so the model drops in at identity and TowerSpawn, the "
        "lights and the Watcher all hang off the same floor.\n\n"
        "THE GUARD IS INSIDE IT NOW. A hollow chamber %.1f m across with eight openings.\n\n"
        "THE DECK IS AT THE GUARD'S EYE. Ryan: \"raise the top one to eye level.\" The eye is this "
        "floor plus %.2f m = y=%.2f, and the deck's walking surface is exactly there, so the guard "
        "looks flat along the whole ring."
        % (TOWER_FLOOR_Y, -TOWER_MODEL_FOOT, TOWER_MODEL_TOP, 2.0 * ROOM_RADIUS,
           GUARD_EYE_HEIGHT, EYE_Y)))
else:
    W('editor_description = %s' % repr_desc(
        "The tower, and its origin is the FLOOR OF THE GUARD ROOM at y=%.2f. That is the model's "
        "own datum: assets/models/tower.glb hangs its rock %.1f m below this point and carries the "
        "top of its drum %.1f m above it, so the model drops in at identity and TowerSpawn, the "
        "lights and the Watcher all hang off the same floor. Raising or lowering the whole tower is "
        "one number on this transform and nothing inside has to be re-authored.\n\n"
        "THE GUARD IS INSIDE IT NOW. A hollow chamber %.1f m across with eight openings; the walls "
        "do the hiding that the old box of eyes used to do, which is why that box is gone.\n\n"
        "THE TOP GALLERY IS AT THE GUARD'S EYE. Ryan: \"raise the top one to eye level.\" The eye "
        "is this floor plus %.2f m = y=%.2f, and level three's walking surface is exactly there. "
        "Level two is %.0f m below the eye and level one %.0f m below it, so the guard looks flat "
        "along the top deck and down into the two beneath."
        % (TOWER_FLOOR_Y, -TOWER_MODEL_FOOT, TOWER_MODEL_TOP, 2.0 * ROOM_RADIUS,
           GUARD_EYE_HEIGHT, EYE_Y, EYE_Y - deck_y(1), EYE_Y - deck_y(0))))
W('transform = %s' % t3(yaw(0.0), (0.0, TOWER_FLOOR_Y, 0.0)))
W('')
W('[node name="Rock" parent="Tower" instance=ExtResource("8_tower_model")]')
W('editor_description = %s' % repr_desc(
    "assets/models/tower.glb: the column, the drum and the hollow chamber, one mesh. It carries "
    "its OWN collision (a -colonly shape in the glTF), so the guard stands on the model's floor "
    "and is stopped by the model's stone -- there is no second, invisible copy of either in this "
    "scene, and nothing here can drift out of agreement with what you can see.\n\n"
    "Its origin is the floor of the guard room, which is why it drops in at identity: see the "
    "Tower node above."))
W('')
W('[node name="TowerSpawn" type="Marker3D" parent="Tower"]')
W('editor_description = "On the chamber floor, 0.25 m up. The clearance is deliberate: spawning a capsule with its feet exactly on the collision plane overlaps it, and depenetration launches the body across the arena. The model\'s origin IS this floor, so this is origin + 0.25 and nothing else."')
W('transform = %s' % t3(yaw(0.0), (0.0, 0.25, 0.0)))
W('')
W('[node name="KeyLight" type="DirectionalLight3D" parent="Tower"]')
W('editor_description = %s' % repr_desc(
    "THE MAIN LIGHT. A DirectionalLight3D has no range falloff at all, so it cannot fail to "
    "reach the deck at any radius. Angled 15 degrees off vertical so it still throws long "
    "outward-raking shadows off cover instead of flat noon light. Reddish, matching "
    "TowerLightProfile.color so the arena stays one mood.\n\n"
    "Its local transform is unchanged by the tower's rise; a directional light has no position, "
    "so moving its parent changes nothing about it."
    if LEVELS == 1 else
    "THE MAIN LIGHT. A DirectionalLight3D has no range falloff at all, so it cannot fail to "
    "reach a deck at any radius or any height -- which matters more now that there are three of "
    "them and the bottom two are roofed. Angled 15 degrees off vertical so it still throws long "
    "outward-raking shadows off cover instead of flat noon light. Reddish, matching "
    "TowerLightProfile.color so the arena stays one mood.\n\n"
    "Its local transform is unchanged by the tower's rise; a directional light has no position, "
    "so moving its parent changes nothing about it."))
W('transform = %s' % t3((1.0, 0.0, 0.0, 0.0, 0.258819, 0.965926, 0.0, -0.965926, 0.258819),
                        (0.0, 20.0, 0.0)))
W('light_color = Color(1.0, 0.36, 0.28, 1.0)')
W('light_energy = 3.4')
W('shadow_enabled = true')
W('')
W('[node name="TowerLight" type="OmniLight3D" parent="Tower"]')
W('editor_description = %s' % repr_desc(
    "LOCAL GLOW ONLY, not the arena's main light -- see KeyLight. A small hot point above the "
    "platform so the tower still visibly reads as a light source up close. Colour, energy, "
    "range, attenuation and height are TowerLightProfile fields applied by TowerLight.gd at "
    "ready; the light_* properties here are placeholders for the editor view. It rides the "
    "tower's rise, which is the point."))
W('transform = %s' % t3(yaw(0.0), (0.0, 10.0, 0.0)))
W('light_color = Color(0.9, 0.14, 0.08, 1.0)')
W('light_energy = 30.0')
W('omni_range = 25.0')
W('omni_attenuation = 1.0')
W('shadow_enabled = true')
W('omni_shadow_mode = 1')
W('script = ExtResource("3_tower_light")')
W('profile = ExtResource("4_tower_light_profile")')
W('')
W('[node name="Watcher" parent="Tower" instance=ExtResource("7_watching_eye")]')
W('editor_description = %s' % repr_desc(
    "THE EYE THAT FOLLOWS YOU. assets/models/eye.glb -- a 5 m ball with a glowing iris -- "
    "hanging over the guard's stand and turned so its pupil points at whoever is looking at it. "
    "Ryan played it and kept it.\n\n"
    "HEIGHT: WatchingEyeProfile.height_metres is 7.2, and it did not need retuning. The node "
    "places itself at (0, height, 0) in THIS NODE'S space, and the tower's local frame is "
    "exactly what it was -- the whole rise is the Tower transform. So the ball still floats 7.2 "
    "m above the platform surface: world y=%.2f, spanning y=%.2f to y=%.2f, which is %.1f m "
    "clear of the guard's crown below it and far under KeyLight above it. It is the only thing "
    "in the tower's space between the guard and the light now that the box of eyes is gone, and "
    "at that height it is in clear sky from %s.\n\n"
    "IT LEAKS NOTHING. It orients toward the local Viewport's own camera, so on every client it "
    "resolves to that client's player and every prisoner sees the pupil on themselves. The "
    "orientation is a pure function of the POSITION of the local camera -- not its direction, "
    "not the guard, not the seat, not the rifle -- so it carries zero bits about anybody except "
    "the person reading it. A camera inside the tower's own column is not watched at all.\n\n"
    "NOT EDITED HERE. scenes/tower/ and scripts/tower/ belong to the eye; this scene owns the "
    "instance and its parent, and nothing else."
    % (TOWER_FLOOR_Y + WATCHER_HEIGHT, TOWER_FLOOR_Y + WATCHER_HEIGHT - 2.5,
       TOWER_FLOOR_Y + WATCHER_HEIGHT + 2.5, WATCHER_HEIGHT - 2.5 - TOWER_MODEL_TOP,
       "the deck" if LEVELS == 1 else "all three galleries")))
W('profile = ExtResource("9_watcher_profile")')
W('')

open(OUT, "w").write("\n".join(lines).rstrip() + "\n")
print("wrote %s (%d lines)" % (OUT, len(lines)))

# --- derived facts -----------------------------------------------------------
print("\nroute: %d levels of %.0f deg at r=%.1f = %.0f m each, %.0f m total"
      % (LEVEL_COUNT, LAP_DEGREES, LANE_R, lap_arc * LANE_R, lap_arc * LANE_R * LEVEL_COUNT))
print("decks at y = %s   floor-to-ceiling %.1f m"
      % (", ".join("%.1f" % deck_y(i) for i in range(LEVEL_COUNT)), ceiling_gap))
print("\nramps:")
for level in range(LEVEL_COUNT - 1):
    frame = ramp_frame(level)
    sag = frame["radius"] * (1.0 - math.cos(math.radians((360.0 - LAP_DEGREES) * 0.5)))
    print("  %d->%d  r=%.1f  run %.1f m  rise %.1f m  slope %.1f deg  chord sag %.2f m  "
          "inner edge reaches r=%.1f  trench opens at %.0f%% of the climb"
          % (level + 1, level + 2, frame["radius"], frame["run"], RISE,
             math.degrees(frame["pitch"]), sag, frame["radius"] - sag - RAMP_WIDTH * 0.5,
             trench_span(level) * 100.0))

print("\nSIGHTLINES from the guard's eye at y=%.2f (chamber floor %.2f):"
      % (EYE_Y, TOWER_FLOOR_Y))
for level in range(LEVEL_COUNT):
    chest = deck_y(level) + CHEST
    line = "  L%d y=%5.1f  eye %5.1f m above it" % (level + 1, deck_y(level), EYE_Y - deck_y(level))
    if level < LEVEL_COUNT - 1:
        ceiling = deck_y(level + 1) - SLAB
        crosses = OUTER_R * (EYE_Y - ceiling) / (EYE_Y - chest)
        line += ("   ray to the far corner crosses the ceiling at r=%.1f (%s by %.1f m)"
                 % (crosses, "CLEAR" if crosses < INNER_R else "BLOCKED",
                    abs(INNER_R - crosses)))
    else:
        line += "   open to the sky, and level with the eye"
    print(line)

print("\ncover shadow (metres a runner may stand back of a piece and stay hidden):")
for level in range(LEVEL_COUNT):
    chest = deck_y(level) + CHEST
    crown = deck_y(level) + COVER_HEIGHTS[level]
    for radius in (COVER_INNER_R, COVER_OUTER_R):
        depth = (EYE_Y - chest) * radius / (EYE_Y - crown) - radius
        print("  L%d r=%.0f height %.1f -> %5.1f m" % (level + 1, radius, COVER_HEIGHTS[level], depth))

print("\nhazard clearance of the racing line r%.2f-r%.2f:"
      % (LANE_R - CLEAR_CHANNEL, LANE_R + CLEAR_CHANNEL))
for label, radius, half in (("trap inner", TRAP_INNER_R, 1.0), ("trap outer", TRAP_OUTER_R, 1.0),
                            ("pit inner", PIT_INNER_R, PIT_HOLE_R),
                            ("pit outer", PIT_OUTER_R, PIT_HOLE_R),
                            ("cover inner", COVER_INNER_R, 0.75),
                            ("cover outer", COVER_OUTER_R, 0.75)):
    low, high = radius - half, radius + half
    ok = high <= LANE_R - CLEAR_CHANNEL or low >= LANE_R + CLEAR_CHANNEL
    print("  %-12s r%.2f-r%.2f  %s" % (label, low, high, "clear" if ok else "ON THE LINE"))
for level in range(LEVEL_COUNT):
    for trap in TRAP_ANGLES:
        for cover in COVER_ANGLES:
            gap = abs((trap - cover + 180) % 360 - 180)
            if gap < 11.0:
                print("  L%d trap %d is only %.0f deg from cover %d" % (level + 1, trap, gap, cover))
# The bay AND the run-in to it: a hazard in either is a bot that cannot climb.
bay_low = exit_deg() - math.degrees(APPROACH_METRES / LANE_R)
bay_high = ENTRY_DEG + 360.0
print("\nramp bay and run-in: %.1f deg to %.1f deg must be clear" % (bay_low, bay_high - 360.0))
for level in range(LEVEL_COUNT):
    for angle in COVER_ANGLES + TRAP_ANGLES + PIT_ANGLES:
        a = angle if angle >= bay_low else angle + 360.0
        if bay_low < a < bay_high:
            print("  L%d something at %.1f deg is inside the ramp bay" % (level + 1, angle))
