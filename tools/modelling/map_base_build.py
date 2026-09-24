"""
PANOPTICON -- the map base: a hole in the ground of hell, cut from the same
dark red rock as the tower. ONE ring gallery round a central void; below the
deck's inner edge the pit drops to the courtyard floor the tower stands on;
the gallery is a CUTOUT: rock ceiling CEIL_H over the deck, open only toward
the void; above it the pit wall carries on to a ragged rim and hell's ground.

Rock only. No cover, traps, pits, pads, ramps or tower -- those are scene work.

Authored in WORLD coordinates so the scene instances it at identity:

    lava sea .........  y = COURTYARD_Z  (tower foot lands on it)
    deck surface .....  y = DECK_Z       (runner's feet; guard's eye level)
    gallery ceiling ..  y = CEIL_Z
    rim ..............  y = RIM_Z

Blender +Z -> Godot +Y, Blender +Y -> Godot -Z.

Collision is purpose-built and rides in the .glb as a `-colonly` node, as the
tower's does: flat deck, clean pit wall, courtyard disc, outer wall and flat
ceiling. The jittered rock mesh is NEVER its own collider.

Texture: the tower's atlas, same painter, same seed -- byte-identical, so
this reads as the rock the tower was cut from. Three surfaces: the rock, the
lava river on its streaked sheet, and the lava sea on the pit floor on Ryan's
own tile (textures/lava_albedo.png), repeated at world scale.

    tools/modelling/model look  map_base --cam 35,30,40
    tools/modelling/model build map_base --cam 35,30,40
    tools/modelling/model build map_base --chunk s2     # one chunk's .glb only (CHUNKS)

Hand-placed shots come back with every run: runner (eye on the deck), guard
(void centre at deck height), shaft (courtyard looking up), cell and mouth
(one cell, angled and straight on).
"""

import json
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

from mathutils import Matrix, kdtree  # noqa: E402
import mdl  # noqa: E402
import texel as tx  # noqa: E402
import rock_bars_build as rb  # noqa: E402

# The model spans y = -11 .. +330; mdl's ground plane would sit under the
# courtyard and black out any low camera. Same override as the tower.
mdl.DEFAULTS["ground"] = False
mdl.DEFAULTS["world_grey"] = 0.30
mdl.DEFAULTS["world_strength"] = 0.90

# =============================================================================
# TUNABLES
# =============================================================================
# Texture files (opt-in, USE_TEXTURE_FILES): tools/modelling/textures/
# river_albedo.png is then the river's albedo (river_emissive.png beside it,
# else the albedo glows); lava_albedo.png is the pit sea's, tiled every
# LAVA_TILE_M metres (lava_emissive.png beside it, else the emissive is
# DERIVED from the albedo: the bright orange glows, the dark crust stays
# dark). The rock is one tiling sheet per class through lib/texel.py --
# map_base_<class>_albedo.png (+ _emissive.png) for rock, shade, carve, ember
# -- world-projected at TEXEL_MPT m per texel, no atlas windows; the atlas
# stays only for the S3 cracks' glow cell. Otherwise the painted sheets below
# are used.

NAME = "map_base"
OBJECT_NAME = "MapBaseRock"
COLLIDER_NAME = "MapBaseCollision-colonly"

SIDES = 32              # 32 x 22 bands-ish; ~11.8 m facets at the outer wall

INNER_R = 46.7          # deck inner edge: the lip of the void
OUTER_R = 57.3          # deck outer edge: foot of the outer wall
DECK_Z = 23.0           # world y of the deck surface (tower room floor is 25.35)
COURTYARD_Z = -11.05    # TOWER_FLOOR_Y + TOWER_MODEL_FOOT (gen_bentham_ring.py)
CEIL_H = 8.5            # the gallery is a CUTOUT: rock ceiling this far over the deck
CEIL_Z = DECK_Z + CEIL_H
RIM_Z = 330.0            # the pit wall carries on above the ceiling to here

PIT_RINGS_Z = [17.0, 6.0, -4.0]          # intermediate pit-wall rings, deck -> courtyard
WALL_RINGS_Z = [DECK_Z + 4.0]            # intermediate outer-wall ring, deck -> ceiling
UPPER_RINGS_Z = [45.0, 75.0, 105.0, 135.0, 165.0, 195.0, 225.0, 255.0, 285.0, 310.0]   # ceiling -> rim, ~11 m bands
GROUND_RINGS = [(56.0, 97.5), (74.0, 101.5)]   # (radius, z): a crater lip, not a plate

ANG_JAG  = 0.30         # per side, held for every ring: vertical edges stay vertical
PIT_JAG  = 0.06         # pit wall: two-sided below the deck, OUTWARD-ONLY above the ceiling
WALL_JAG = 0.05         # OUTWARD-ONLY on the outer wall, so the r=60 collider
                        # is never outside the rock the runner can see
JAG_RUN  = (1, 2)       # rings a jitter value is held for -- steps, like cleaved rock
Z_JAG    = 1.5          # intermediate ring height jitter
RIM_JAG  = 1.2          # ragged rim
GROUND_RJAG = 0.03
GROUND_ZJAG = [1.6, 2.6]

SHADE_T = 0.30          # recess (fraction of JAG) past which a facet goes dark
EMBER_T = 0.55          # ... and past this, low in the pit, it is a cleft
EMBER_BANDS = 2         # only the lowest N pit bands may glow

SEED = 9110271
EYE_H = 1.65

# ---- material / texture -- identical to tower_build.py --------------------
USE_TEXTURE_FILES = True             # True: texture files in TEX_DIR replace the painted sheets
TEX_DIR       = "textures"            # beside the running script, here or in the PC job dir
TEX_SIZE      = 128
TEX_ALBEDO    = "map_base_rock_albedo"
TEX_EMISSIVE  = "map_base_rock_emissive"
TEX_SEED      = 6661031
ROCK_ROUGHNESS = 0.95
ROCK_METALLIC  = 0.0
UV_SCALE      = 0.13
UV_PAD        = 1.5 / TEX_SIZE

ZONE_ROCK   = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE  = (0.5, 0.5, 1.0, 1.0)
ZONE_CARVE  = (0.5, 0.0, 1.0, 0.5)
ZONE_EMBER  = (0.0, 0.0, 0.5, 0.5)
ZONE_GLOW   = (0.5, 0.0, 1.0, 0.25)   # cell interiors: painted over the unused
                                      # lower half of CARVE, after the four
                                      # tower zones, so those stay byte-identical

# The deck is the one surface the red sun hits square on, so the wall tone
# read washed out on it. It takes SHADE (the darker hell-rock) at its own,
# finer tiling, projected radially so a facet's texel density comes from its
# real extent and not its world-xy bounding box.
ZONE_DECK      = ("deck",) + ZONE_SHADE
DECK_UV_SCALE  = 0.34                 # ~0.048 m/texel: speckle 0.2..0.5 m

# The S3 lip wall's faces: the same dark rock, projected COHERENTLY along the
# wall (arc, height) with one window every few metres instead of a random
# window per triangle -- per-triangle windows on a tall flat face read as a
# row of light and dark teeth, rock spilling onto the deck, which it is not.
ZONE_WALLFACE  = ("wallface",) + ZONE_SHADE
WALLFACE_R     = 47.2                 # arc metres measured at this radius

# ---- the lava sea on the floor of the shaft --------------------------------
# Its own material (LavaSea) and its own TILING sheet -- an atlas cell cannot
# repeat, and one window stretched over 90 m of floor is what Ryan called
# "the old texture". The sheet is his tile, textures/lava_albedo.png
# (Lava_tile_2: the dark crust network over orange), laid in world x,y and
# repeated every LAVA_TILE_M metres. The S3 cracks are NOT this: they keep the
# atlas's glow cell (Ryan: "i specifically said dont use that texture in the
# cracks").
ZONE_LAVA      = ("lava",)
LAVA_TILE_M    = 5.0                  # metres one repeat of the tile covers; 256 px -> 19.5 mm/texel.
                                      # The falls are laid at this same scale, in world space
LAVA_EMIT_LO   = 112.0 / 255.0        # a texel whose brightest channel is at or under this
                                      # emits nothing (the crust, (112,1,1))
LAVA_EMIT_HI   = 176.0 / 255.0        # ... and at or over this emits its whole albedo
                                      # (the orange, (176,50,7)); smoothstep between
LAVA_EMIT_FLOOR = 0.25                # the crust still emits this share of its albedo:
                                      # Ryan, "a faint glow to the lava", even in shadow
LAVA_ALBEDO    = "map_base_lava_albedo"
LAVA_EMISSIVE  = "map_base_lava_emissive"
LAVA_SEED      = 7720133
LAVA_TEX       = 512                  # the painted FALLBACK, only when there is no
LAVA_SPAN      = 104.0                # lava_albedo.png: painted for LAVA_SPAN metres
                                      # across, and repeated every LAVA_TILE_M like the file
LAVA_RINGS     = (1.0, 0.70, 0.42, 0.14)   # radius fractions of the pit foot
LAVA_SWELL     = 0.6                  # +- metres of slow molten swell
LAVA_STEP      = 0.3                  # swell snaps to this: flat crust plates
LAVA_FLAT_R    = 18.0                 # level under the tower's foot
LAVA_ASPECT    = 0.2                  # inner rings: arc between columns, per metre of ring gap
LAVA_SUB_M     = 2.0                  # the sea's rings are cut this fine, so the lava wave bends it
WAVE_RAMP      = 2.5                  # metres in from a lava edge the wave takes to reach full height
WAVE_MATS      = ("LavaSea", "LavaRiver", "LavaCrack")   # every lava surface: the wave shader's

# ---- the lava river: a channel recessed into the deck, the wall and the pit --
# Folded in from the retired lake_section model. A game bearing of b degrees is
# Blender angle -b. The river is not a sheet laid on anything: it is map_base's
# OWN faces, dropped RECESS_Z into the deck between two sloped banks and pushed
# RECESS_R back into the two walls, re-laid in the river's material.
LAKE_A0, LAKE_A1 = 292.3, 338.3       # the channel, bank to bank, game bearings
LAKE_BANK = 0.6                       # degrees of sloped bank at each end
WALL_A0, WALL_A1 = 293.0, 338.0       # pass 4's wall-run columns: the sea's rim keeps them
WALL_BANK = 0.7
LAVA_Z = 22.70                        # the channel floor: 0.3 m under the deck
WALL_LAVA_TOP = 28.80                 # the fall tops out here, 2.7 m under the ceiling
WALL_ROWS_OUT = (30.20, 30.70)        # the outer wall's own rows, kept as pass 4 laid them
RECESS_R = 0.40                       # how far the channel is cut into a wall
PIT_FADE = 2.0                        # metres the pit-wall channel takes to open
RST = [46.70, 47.60, 48.60, 50.00, 51.40, 52.80, 54.20, 55.40, 56.40, 57.30]
RST_RIVER = [46.70, 48.20, 49.00, 49.70, 50.40, 51.10, 51.80, 52.50, 53.20,
             53.90, 54.60, 55.30, 56.00, 56.70, 57.30]   # the channel's own stations,
                                      # absolute radii; the first is the lip, LIP_R out,
                                      # the last the wall foot, wherever that is
FLOOR_AMP = 0.15                      # the river floor's 2-D surface, metres, peak
FLOOR_L = (1.8, 4.0)                  # ... wavelengths
FALL_AMP = 0.06                       # the same on the wall fall, smaller
FALL_ROWS = (24.0, 25.0, 26.0, 27.0)  # fall rows between the foot and the lip
SLOT_H = 0.7                          # the recess over the shelf: a slot this tall, wall above
LIP_R = 1.0                           # both lips round over this far ...
LIP_ROWS = (0.15, 0.35)               # ... on rows this far below the flat
LIP_P = 1.5                           # the round-over's superellipse exponent
BANK_STEP = (0.1, 0.28)               # metres a bank edge steps in or out per run
BANK_OFF = (-0.3, 0.3)                # the deck edge wanders within this of its line
BANK_EDGE = (0.0, 0.45)               # the lava edge within this, into the river
BANK_RUN = (2, 4)                     # rows a step is held for
BANK_REACH = 3.0                      # metres of floor that follow a bank's line
COL_MERGE = 0.30                      # a river column this close to a wall column yields
SHELF_D = 2.5                         # the flat river cut back into the wall over the fall
FALL_CAP = 3.0                        # tallest fall row
FALL_WAVE_ROW = 1.0                   # ... and the pit fall's drawn rows, so the lava
                                      # shader's ripple bends it (scenes/ring/lava_wave.gdshader)

PLAT_OUT_R = 54.8                     # the run: 7 platforms, 7.00 m apart
PLAT_IN_R = 50.2
PLAT_STEP = 5.7676
PLAT_B0 = 298.0
PLAT_TOP_Z = 23.00                    # deck height, exactly
PLAT_HALF = 1.20                      # a 2.4 x 2.4 m square top
PLAT_YAW = 8.0                        # degrees off the run direction, at most
FIN_R = 48.50
FIN_TOP_Z = 27.30
FIN_HALF_T = 1.70
FIN_HALF_R = 0.42

LAVA_COLL_RST = [46.70, 48.20, 49.70, 51.20, 52.70, 54.20, 55.70, 57.30]

LAKE_SEED = 5140737

# ---- S2, the Lava Shelf: a river ALONG the deck with deck on both sides.
# Inner lane: plain deck, no cover. In the river: a chain of six rock masses,
# four with a crest grown up their tower-facing side. Past the river the
# outer bank rises straight into the wall: nothing to run on.
S2_A0, S2_A1 = 74.5, 130.5            # lip to lip, game bearings
S2_END = 1.5                          # degrees each end bank takes, lip to lava
S2_END_P = 1.6                        # ... its round-over exponent
S2_TAPER = 4.0                        # degrees each end the river narrows over ...
S2_END_W = 2.6                        # ... to a tongue this wide at the wall foot
S2_STEP = 1.0                         # degrees between the section's own columns
S2_LANE_R = (47.6, 48.6, 49.5)        # inner-lane stations: flat deck
S2_IN_R = 50.3                        # inner bank top line; wanders BANK_OFF
S2_IN_W = (0.45, 1.0)                 # inner bank, top to lava edge: width varies, so pitch does
S2_OUT_LEDGE = (0.22, 0.42)           # outer bank: the lava edge this far inside the wall foot
S2_IN_LIP = ((0.25, 0.08), (0.55, 0.30), (0.85, 0.70))   # inner round-over: (of the width, of the drop)
S2_OUT_LIP = ((0.45, 0.62), (0.80, 0.92))                # outer: steep, no ledge
S2_FLOOR_N = 6                        # floor quads across the river
S2_FLOOR_AMP = 0.12                   # the floor's 2-D field, metres, peak
S2_FLOOR_FADE = 0.7                   # metres from a foot the field takes to rise
S2_PLAT_R = 54.7                      # the chain's centre line
# The chain: flat-topped boulders, each one heightfield on a polar grid: a
# level landing, rounded shoulders down into the lava. (along, across:
# semi-axes at the waterline; top y; off the centre line)
S2_PLATS = ((1.72, 1.45, 23.05, 0.10), (1.65, 1.40, 23.35, -0.10),
            (1.72, 1.45, 22.95, 0.20), (1.68, 1.45, 23.30, -0.05),
            (1.65, 1.40, 23.15, 0.15), (1.72, 1.45, 22.90, 0.0))
S2_GAPS = (4.6, 5.1, 4.6, 5.0, 4.7, 5.2)      # lava between standing edges: end bank first
S2_MASS_N, S2_MASS_P = 20, 2.3        # points round a boulder, its outline's exponent
S2_MASS_Q = (0.12, 0.3, 0.45, 0.58, 0.68, 0.76, 0.83, 0.89, 0.95, 1.0, 1.08, 1.2)   # rings, of the waterline
S2_FLAT_Q = 0.78                      # the landing: flat out to here
S2_WATER_D = 0.15                     # the shoulder reaches this far under the lava at the waterline ...
S2_BOTTOM_D = 0.8                     # ... and the bottom ring this far, at the last ring
S2_WOB = 0.07                         # the waterline wanders this much of its radius
S2_NOISE = 0.10                       # rock noise on everything but the landing, metres, peak
S2_NOISE_L = (0.7, 1.8)               # ... wavelengths
# The cave wall: a ridge on the river's inner bank between the tower and the
# chain, the length of the chain, windows over three gaps, into the ceiling
# in front of two landings. The lane stays on its tower side, open.
S2_WALL_IN = 0.8                      # degrees inside each lip it starts and ends, sunk in the lava
S2_WALL_STEP = 1.0                    # degrees per column
S2_WALL_R = 51.0                      # its crest line's radius ...
S2_WALL_WANDER = 0.2                  # ... wandering this much
S2_WALL_W = (0.9, 1.05)              # half width at the foot
S2_WALL_H = (3.6, 5.0)                # height over the lava, wandering
S2_WALL_CRAG = 0.4                    # metres the crest steps up and down column to column
S2_WALL_JOIN, S2_WALL_JOIN_W = 9.2, 2.8   # up into the ceiling in front of these landings, over this reach
S2_WALL_JOIN_AT = (1, 4)
S2_WALL_WINDOW_AT = (1, 3, 5)         # windows over these gaps (0 = end bank to the first boulder) ...
S2_WALL_WINDOW = (1.7, 1.9, 1.8)      # ... sill over the lava ...
S2_WALL_WINDOW_W = 1.6                # ... half width, metres
S2_WALL_END = 1.6                     # metres each end takes to rise out of the lava
S2_WALL_SINK = 0.3                    # the feet this far under the lava
S2_SIGHT_N = 300                      # samples along a sight line
S2_SEED = 6180339
S2_TRAP_N = 7                         # TrapVolumes over the river, for the scene
S2_TRAP_R = (50.3, 57.5)              # ... their radial span
S2_INFO = {}                          # what the renders need: lip bearings, the masses
REVIEW_SUN = 5.0                      # review renders only: white fill sun, watts
REVIEW_WORLD = 1.6                    # ... world light strength
REVIEW_EXPOSURE = 1.5                 # ... stops over the arena look

# The river and the falls are the SAME LAVA as the sea, so they carry the sea's
# sheet at the sea's metres per texel -- Ryan: "the pit texture is bad because
# its at a different scale than the lava falls". They keep their own material
# (LavaRiver) and their own surface; only the projection differs, and only
# because the surface does: flat lava takes world x,y, a wall fall takes
# (arc, height). See _lava_uv and _flow_uv.
ZONE_RIVER = ("river",)               # the channel floor and the wall shelf: flat
ZONE_RIVER_T = ("river_t",)           # ... and along the deck in S2, flat
ZONE_FALL = ("fall",)                 # ... and straight down a wall
FALL_REF_R = (47.5, 57.5)             # a wall fall's arc is measured at ITS wall's radius --
FALL_REF_SPLIT = 53.0                 # the pit wall, the outer wall. Constant per wall (the
                                      # WALLFACE_R idiom): a radius taken per vertex would
                                      # turn the pit wall's own jag into a smear, because
                                      # d(theta*r)/dr is theta, and theta runs to 2.6 rad here.
                                      # No fall face lies within a metre of the split.
FALL_FLAT_NZ = 0.7071                 # a fall face this level takes world x,y instead: at 45
                                      # deg the two world-axis projections stretch alike, so
                                      # the crossover is the best either can do, and every
                                      # face gets the better of the two.
CROSS_R = 52.0                        # reference radius for column merging

# ---- S4 Demon Run: the deck is a lava field, pit lip to wall foot, crossed pad
# to pad over three landing rocks. Pads are scene nodes (BoostPad: 18 m/s at 45
# deg, gravity 22, a 3 x 3 m trigger); the launch OVERWRITES the run velocity
# (player_controller.gd: velocity = _pending_launch), so every flight is the
# same arc from wherever the body walked into the pad. The field's two cuts sit
# on side boundaries, so nothing outside them changes.
S4_CUT_SIDES = (13, 8)                # entry cut = ang[13] (212.9 deg), exit side boundary ang[8] (270.3)
S4_BANK = 0.7                         # degrees of rounded bank at each end
S4_BANK_MID = (0.45, 0.68)            # the bank's middle column: fraction across, fraction of the drop
S4_LANE_R = 52.0
S4_ENTRY_R, S4_EXIT_R = 52.6, 52.6    # the entry pad and the exit landing: the first and last flights
                                      # cross the lane so the end banks lie square to them
S4_ROCKS = [(54.4, 0.2, 0.0), (53.8, 0.4, 0.0), (54.4, 0.1, 0.0)]   # radius, top over the deck, (no hump: cover is the wall)
S4_REAR, S4_FRONT = 4.0, 2.0          # the standing top: 6.0 m along the flight, rear closed in on the
                                      # previous rock so a normal hit lands mid-top, not at the edge
S4_HALF_ACROSS = 1.6                  # ... 3.2 m across to the standing edge on the wall side
S4_EDGE_Q = 0.87                      # the standing edge (shoulder at 45 deg) sits here, of the waterline
S4_FLAT_Q = 0.8                       # dead level out to here, of the waterline
S4_REAR_IN = 1.0                      # the rear-inner quadrant of the waterline: no tail any more
S4_HUMP_SIDE = 1.6 / 0.87             # the waterline's across semi-axis on the tower side: the same as the wall side
S4_MASS_N, S4_MASS_P = 18, 2.3        # points round a boulder, its outline's exponent
S4_MASS_Q = (0.15, 0.4, 0.62, 0.8, 0.9, 1.0, 1.1, 1.2)   # rings, of the waterline
S4_WATER_D = 0.15                     # the shoulder reaches this far under the lava at the waterline ...
S4_BOTTOM_D = 0.8                     # ... and the bottom ring this far, at the last ring
S4_WOB = 0.04                         # the waterline wanders this much of its radius
S4_HUMP_V = 2.5                       # the hump's peak this far across (the landing flat ends at 1.6)
S4_HUMP_B = (1.2, 0.95)               # its half depth, inner and outer face: it leans over the landing
S4_HUMP_U = (-1.2, 3.6)               # its centre along, and half length
S4_HUMP_P = (4.0, 1.2)                # its section exponent along, and its profile's
S4_NOISE = 0.10                       # rock noise on everything but the landing, metres, peak
S4_NOISE_L = (0.7, 1.8)               # ... wavelengths
# ---- the cave wall: a ridge of rock between the tower and the flights ------
S4_WALL_B = (209.8, 271.6)            # bearings it runs between, sunk into the lava at each end
S4_WALL_STEP = 0.85                   # degrees per column (~0.72 m)
S4_WALL_R = 49.30                     # its crest line's radius: feet 47.20..51.40, clear of the pit lip
S4_WALL_WANDER = 0.35                 # ... wandering this much
S4_WALL_W = (1.35, 1.75)              # half width at the foot
S4_WALL_PULL = 5.0                    # metres each end takes to narrow onto its corner wall's footprint
S4_WALL_ARC_R = 48.7                  # arc metres for its crags, joins and windows: heights as before
S4_WALL_H = (4.6, 5.8)                # height over the lava, wandering
S4_WALL_JOIN, S4_WALL_JOIN_W = 9.2, 3.2   # up into the ceiling (8.8 m over the lava) in front of each landing, over this reach
S4_WALL_WINDOW_AT = 0.62              # a window on the falling side of each flight, this far along it ...
S4_WALL_WINDOW = (1.6, 1.8, -0.6, 1.7)  # ... its sill over the lava per hop (negative: a break)
S4_WALL_WINDOW_W = 2.4                # ... its half width, metres
S4_WALL_END = 2.5                     # metres each end takes to rise out of the lava
S4_WALL_SINK = 0.3                    # the feet this far under the lava (or the deck)
S4_WALL_PROF = 0.85                   # the ridge section: cos^this, rounded crest, sloping feet
S4_WALL_CRAG = 0.45                   # metres the crest steps up and down column to column
S4_WALL_ROWS = (-1.0, -0.82, -0.62, -0.4, -0.18, 0.05, 0.28, 0.5, 0.7, 0.86, 1.0)   # rows across, of the half width
S4_SIGHT_N = 300                      # samples along a sight line
S4_LAND = 3.0                         # nominal landing this far past the next top's near edge:
                                       # same physics reach as before (edge - LAND = 1.0 m of
                                       # rock behind the target, unchanged), now the enlarged
                                       # top's own midpoint rather than a bare edge clearance
S4_EXIT_LAND = 1.5                    # ... and onto the exit deck, past the lava's edge
S4_PAD_BACK = 1.6                     # a rock's pad centre this far behind its front edge
S4_WALK_ON = 1.75                     # launch origin behind the pad centre: trigger face 1.5 + capsule 0.4 - one tick
S4_LAUNCH, S4_ANGLE, S4_G = 18.0, 45.0, 22.0
S4_APEX = 3.68                        # the pad's apex over its take-off: (v sin a)^2 / 2g
S4_JUMP_V, S4_RUN, S4_SLIDE = 7.0, 11.0, 14.0
S4_GUARD_EYE = 27.0
S4_BODY_H = 1.8
S4_CHEST = 1.3
S4_FLOOR_AMP = 0.12
S4_EDGE_WANDER = (0.0, 0.15)          # the end banks' lava edge wanders this far into the field ...
S4_MID_WANDER = (-0.25, 0.25)         # ... and the bank's middle column this far either way
S4_TONGUE = (1.7, 0.5)                # the entry bank is level under the pad: half-width, blend
S4_TRAP_STEP = 5.8                    # degrees per TrapVolume box over the field
S4_REVIEW = (2.0, 0.36, 0.7, 0.0)     # review renders only: white sun W, fill grey, fill strength, exposure EV
S4_SEED = 6180339
S4 = {}                               # the layout, filled by _s4_layout()
S4_ROCK_MESH = []                     # (rock, ring list) for the collider

# ---- S3 Demon Pad Grid: the deck is FLAT at lane height and filled with demon
# pads in rows along the arc and columns across the width. One walkable path is
# cut through the grid by leaving cells pad-free, three pads are left IN the
# path and have to be jumped, and one half wall of the deck's own rock stands
# at the pit edge for the section's length. Ryan: "step 1 fill the section
# with demon pads. step 2 cut a path through it by removing demon pads. step 3
# a wall of cover at the pit edge, like all the other cover, short enough that
# a person jumping on a demon pad flies above it from the guard tower."
#
# Everything is laid out in the deck's GRID frame -- (game bearing, station
# radius) -- and the section's deck grid is true polar between the lip and the
# wall foot (those two rows stay the ring's own chord vertices, so the weld is
# unchanged), so pads, wall and proofs share one exact metric and the wall's
# top edges and feet fall on mesh lines. No lava and no TrapVolume in the
# section: a launch lands back on this deck.
S3_EYE_Z = 28.90                      # the guard's eye, TRACED IN THE RUNNING GAME:
                                      # Tower/TowerSpawn 27.30 + RingBake EYE_HEIGHT 1.60.
                                      # S1_EYE_Z and S4_GUARD_EYE still say 27.0; not
                                      # this section's to move.
S3_EXT = (143.0, 202.0)               # bearings S3 re-lays on its own grid
S3_FIELD = (145.0, 200.0)             # the pad field and the wall run between these
S3_LANE_R = 52.0                      # arc metres are measured at this radius
S3_ROWS = 17                          # pad rows along the arc ...
S3_ROW_B = (146.6, 198.4)             # ... first and last row centre: 3.24 deg = 2.94 m apart
S3_COLS = (49.15, 52.35, 55.55)       # pad column radii, 3.2 m apart: three 2.5 m plates and
                                      # the wall at the lip fill the 10.6 m deck with no gap a
                                      # body fits through (a fourth column would need 11 m)
S3_PAD = 2.5                          # the demon_pad trigger box, metres across (scene default)
S3_PAD_H = 1.0                        # ... and tall (scene default): unjumpable on a flat deck
S3_JUMP_PAD_H = 0.5                   # the three jump pads' trigger height: what a 1.11 m
                                      # jump clears with margin, where 1.0 m cannot be
S3_YAW_IN = 8.0                       # every pad aims this far inward of the tangent, so a
                                      # flight lands at its own radius rather than 2 m outward
                                      # (14.7 m of chord on a 52 m circle drifts out)
S3_PATH = (1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  0, 0, 0, 0, 0, 0, 0)   # the path's column per row:
                                      # the middle column, stepping to the inner one at row 9
                                      # (a bend costs one extra cell: sideways, then forward)
S3_JUMP_ROWS = (1, 4, 10)             # rows whose path cell keeps its pad: jump it. Each has
                                      # the next row cleared in its column (the 7 m jump lands
                                      # on the path) and rows +4 and +5 cleared in its column,
                                      # where its own flight lands: RingBake links a pad only
                                      # when its flight lands on open mesh, and the bots walk
                                      # the path, so these three must be LIVE, not carved
S3_BAKE_KEEP = 0.95                   # RingBake: agent radius 0.50 erodes the mesh round every
                                      # rim, wall foot and pad plate, then LAND_MARGIN 0.45
S3_WALL_FOOT = 0.88                   # the wall at the pit edge: one ragged rock rising from
                                      # the lip itself, its rock reaching at most this far from
                                      # the lip (the foot line S3_WALL_FOOT_R). It stands on
                                      # its own footprint: no talus, no spread, the deck flat
                                      # right up to a near-vertical face on the path side.
                                      # Ryan: "the wall is like coming out from where it is onto
                                      # the floor and it looks stupid" -- and "the wall is not
                                      # tall enough": its crest now hides a STANDING body on the
                                      # path from the guard's eye along the whole length, ragged
                                      # column by column inside the window that keeps every
                                      # crack launch's apex in the guard's sight.
S3_WALL_IN = 46.85                    # the inner top edge: the face off the lip rises 0.15 m in
S3_WALL_OUT = 47.55                   # the outer top edge, over the deck ...
S3_WALL_FOOT_R = 47.58                # ... and its foot, 0.03 m out: a near-vertical face
S3_WALL_ST = (46.85, 47.00, 47.15, 47.30, 47.45, 47.55, 47.58)   # stations across the wall:
                                      # the plateau every 0.15 m, the outer top edge, the foot
S3_WALL_CHAMFER = (0.92, 1.0)         # the outer top edge sits this much of the crest, per
                                      # column, held in runs: a ragged edge, above the deck only
S3_WALL_OVER = (0.20, 0.55)           # the crest stands this far over the standing sight line
                                      # at its lowest .. highest, per column
S3_WALL_END_SPUR = 0.25               # the S3|S4 divider's own lip spur reaches this far over
                                      # the wall's 200 end (unchanged rock outside the section);
                                      # the wall proofs report samples under it apart
S3_CRACK_SEED = 6180339               # the fissures: one _Rng per pad, seed + 7919 * index
S3_CRACK_FLOOR = 0.70                 # the lava floor's half width, of the fissure's top
S3_CRACK_MARGIN = 0.10                # a patch cell boundary keeps this far from an outline
S3_CRACK_ZONE_FLOOR = ZONE_GLOW       # the lava: every texel of that cell emits
S3_CRACK_ZONE_WALL = ZONE_EMBER       # the cleft's sides, upper band: near-black rock with
                                      # ember streaks; the band under it is lava too
S3_CRACK_LIP = 0.35                   # the dark upper band, of the depth
S3_COL_STEP = 0.5                     # plain lattice: arc metres between columns ...
S3_ST_STEP = 1.0                      # ... and metres between stations
S3_EDGE_BAND = 1.0                    # the first station in from the OUTER rim: one band takes
                                      # up the ring's chord sagitta (0.46 m at a side's middle)
S3_MERGE = 0.12                       # a lattice line this near an exact one yields
S3_LAUNCH, S3_ANGLE, S3_G = 18.0, 45.0, 22.0   # BoostPad defaults, gravity 22 (MovementProfile)
S3_APEX = (S3_LAUNCH * math.sin(math.radians(S3_ANGLE))) ** 2 / (2.0 * S3_G)   # 3.68 m
S3_BODY_R, S3_STAND, S3_CROUCH = 0.40, 1.80, 1.20   # capsule radius, standing and crouched height
S3_RUN, S3_JUMP_V = 11.0, 7.0         # ground speed, jump take-off speed
S3_BFS = 0.05                         # metres between the path proof's lattice points
S3_FLANK = 30.0                       # a facet leaning more than this off flat is wall, not deck
S3_REVIEW = (2.2, 0.55, 1.5)          # review renders only: white sun W, world grey, exposure EV
S3 = {}                               # the layout plus the columns it claimed

# ---- prison cells: stone screens cut into the pit faces ---------------------
# A cell is an arched mouth cut through the wall, a reveal stepping back to a
# flat stone SCREEN, and a plain glowing arch-section box behind. The screen carries
# 5..9 tall wavy SLOTS (8-12 verts each, no two alike); the stone between them
# is the bars. Positions come from seeded dart throwing on the wall in
# (arc, height); the mouth is cut into whichever facets it overlaps and every
# seam shares vertices (facets with extra edge vertices are fanned).
CELL_SEED   = 4420917
CELL_H      = (2.5, 5.5)      # mouth height, metres
SLOT_HW     = (0.10, 0.22)    # slot half width: 0.2..0.44 m openings
SLOT_LEAN   = 0.12            # metres, head vs foot
SLOT_WAVE   = 0.05            # per-level edge jitter
BAR_W       = (0.15, 0.30)    # stone left between slot lanes
SIDE_M      = (0.25, 0.40)    # stone left at the screen's sides
SILL        = (0.25, 0.45)
LINTEL      = (0.30, 0.60)
NL          = 7               # screen levels: 0 sill foot .. NL-1 lintel head
SCREEN_BACK = 0.15            # screen behind the deepest point of the mouth edge
BOX_EPS     = 0.03            # box outline past the screen edge, hidden behind it
CELL_DEPTH  = (4.0, 6.0)
CELL_RHO    = 0.0068          # cells per m^2: 60 % of v2's pit density
PIT_CLEAR   = 3.5             # no cell top nearer the deck than this
UNIFORM_TOP = COURTYARD_Z + (RIM_Z - COURTYARD_Z) / 4.5   # uniform density to here (~y 65)
TAIL_L      = 40.0            # e-folding height of the thinning above it
CELL_ZTOP   = RIM_Z - 20.0
EDGE_CLEAR  = 0.2             # mouth edges keep this far from facet boundaries
GAP_MIN, GAP_MAX = 0.4, 3.6   # spacing field: tight clusters .. empty stretches
PIT_SUB, PIT_CAP = 2, 7.0

CELLS = []                    # (centre, out, width, height) for the renders

FACING_YAW = 0.0


# =============================================================================
# TEXTURE -- copied from tower_build.py so the atlas is the same rock
# =============================================================================

class _Rng(object):
    """Deterministic LCG; the model is byte-identical every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def bits(self):
        return self.n() >> 12

    def f(self):
        return self.n() / float(0x7FFFFFFF)

    def sf(self):
        return self.f() * 2.0 - 1.0

    def i(self, a, b):
        return a + self.bits() % (b - a + 1)

    def pick(self, seq):
        return seq[self.bits() % len(seq)]


def _s2l(rgb):
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

    def wrap(self, x, y, rgb, glow=None):
        self.put(x % self.w, y % self.h, rgb, glow)

    def rect(self, x0, y0, x1, y1, rgb, glow=None):
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.put(x, y, rgb, glow)


def _rect_of(zone, size):
    u0, v0, u1, v1 = zone
    return (int(u0 * size), int(v0 * size), int(u1 * size), int(v1 * size))


def _fill(c, r, box, shades):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            c.put(x, y, r.pick(shades))


def _shatter(c, r, box, shades, count, minsz, maxsz):
    """Squarish blotches with no preferred direction."""
    x0, y0, x1, y1 = box
    for _ in range(count):
        w = r.i(minsz, maxsz)
        h = max(minsz, min(maxsz, w + r.i(-1, 1)))
        x, y = r.i(x0, x1 - w - 1), r.i(y0, y1 - h - 1)
        c.rect(x, y, x + w, y + h, r.pick(shades))


def _paint_rock(c, r, box):
    _fill(c, r, box, [(74, 27, 25), (58, 20, 19), (90, 35, 30), (46, 16, 16)])
    _shatter(c, r, box, [(96, 40, 33), (48, 16, 16), (110, 48, 38)], 20, 6, 15)
    _shatter(c, r, box, [(32, 11, 12), (118, 56, 43)], 12, 4, 9)
    x0, y0, x1, y1 = box
    for _ in range(6):
        x, y = r.i(x0 + 2, x1 - 4), r.i(y0 + 2, y1 - 4)
        c.rect(x, y, x + 2, y + 2, (172, 44, 12), (114, 22, 3))


def _paint_shade(c, r, box):
    _fill(c, r, box, [(34, 12, 12), (24, 8, 9), (44, 17, 15), (17, 6, 7)])
    _shatter(c, r, box, [(42, 16, 15), (10, 3, 4)], 20, 4, 11)
    x0, y0, x1, y1 = box
    for _ in range(4):
        x, y = r.i(x0 + 2, x1 - 4), r.i(y0 + 2, y1 - 4)
        c.rect(x, y, x + 2, y + 2, (140, 34, 9), (92, 16, 2))


def _paint_carve(c, r, box):
    _fill(c, r, box, [(84, 58, 53), (72, 48, 44), (96, 69, 63), (64, 42, 39)])
    _shatter(c, r, box, [(66, 43, 40), (102, 74, 68), (56, 35, 33)], 14, 5, 14)
    _shatter(c, r, box, [(74, 38, 27), (46, 27, 25)], 10, 4, 10)
    x0, y0, x1, y1 = box
    for _ in range(10):
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        c.rect(x, y, x + 2, y + 2, (52, 32, 30))
    for _ in range(3):
        x, y = r.i(x0 + 2, x1 - 4), r.i(y0 + 2, y1 - 4)
        c.rect(x, y, x + 2, y + 2, (152, 48, 14), (88, 18, 2))


def _paint_ember(c, r, box):
    x0, y0, x1, y1 = box
    _fill(c, r, box, [(11, 4, 5), (16, 6, 6), (7, 2, 3), (20, 8, 7)])
    for _ in range(15):
        x, y = r.i(x0, x1 - 1), r.i(y0, y1 - 1)
        for _step in range(60):
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if x0 <= x + dx < x1 and y0 <= y + dy < y1:
                        c.put(x + dx, y + dy, (58, 15, 4), (74, 15, 1))
            hot = r.pick([(255, 150, 30), (255, 212, 88), (248, 100, 14)])
            c.put(x, y, hot, hot)
            x += r.i(-1, 1)
            y += r.i(-1, 1)
            if not (x0 <= x < x1 and y0 <= y < y1):
                break
    for _ in range(30):
        c.put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), (7, 3, 4))
    for _ in range(10):
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        c.rect(x, y, x + 2, y + 2, (236, 92, 18), (194, 54, 5))


def _paint_glow(c, r, box):
    """The Nightosphere backlight: every texel emits red-orange."""
    x0, y0, x1, y1 = box
    shades = [(214, 44, 8), (196, 34, 6), (232, 60, 14), (178, 28, 6)]
    for y in range(y0, y1):
        for x in range(x0, x1):
            s = r.pick(shades)
            c.put(x, y, s, s)
    for _ in range(14):                       # dim vertical streaks: figures in the dark
        x, w = r.i(x0, x1 - 3), r.i(1, 2)
        yy, h = r.i(y0, y1 - 6), r.i(4, 10)
        c.rect(x, yy, x + w, min(y1, yy + h), (128, 18, 4), (104, 12, 2))
    for _ in range(12):
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        c.rect(x, y, x + 2, y + 2, (255, 128, 34), (255, 128, 34))


def build_texture():
    """Paint the atlas; returns (albedo_image, emissive_image)."""
    c = _Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    _paint_rock(c, r, _rect_of(ZONE_ROCK, TEX_SIZE))
    _paint_shade(c, r, _rect_of(ZONE_SHADE, TEX_SIZE))
    _paint_carve(c, r, _rect_of(ZONE_CARVE, TEX_SIZE))
    _paint_ember(c, r, _rect_of(ZONE_EMBER, TEX_SIZE))
    _paint_glow(c, r, _rect_of(ZONE_GLOW, TEX_SIZE))
    images = []
    for name, buf in ((TEX_ALBEDO, c.alb), (TEX_EMISSIVE, c.emi)):
        img = bpy.data.images.new(name, TEX_SIZE, TEX_SIZE, alpha=False)
        img.colorspace_settings.name = "sRGB"
        img.pixels.foreach_set(buf)
        img.update()
        images.append(img)
    return images[0], images[1]


# ---- the rock's tiling sheets (lib/texel.py): one per class, world-projected --
# Every class at TEXEL_MPT m per texel; a sheet repeats every TEXEL_TILE texels
# (12.8 m) and closes on itself round the ring. Painted at the same metre
# sizes the atlas cells had (an 8 m cell of 64 texels), so the rock reads the
# same from 6 m and stops smearing at 1 m.
TEXEL_MPT = tx.MPT
TEXEL_TILE = tx.TILE
_K = (TEXEL_TILE * TEXEL_MPT / 8.0) ** 2      # sheet area / old cell area: 2.56
_S = 0.125 / TEXEL_MPT                        # old texel / new texel: 2.5


def _n(count):
    return int(round(count * _K))


def _sz(texels):
    return max(1, int(round(texels * _S)))


def _specks(c, r, count, size, rgb, glow):
    for _ in range(_n(count)):
        x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
        c.rect(x, y, x + size, y + size, rgb, glow)


def _sheet_rock(c, r, s):
    tx.fill(c, r, c.box, [(74, 27, 25), (58, 20, 19), (90, 35, 30), (46, 16, 16)])
    tx.shatter(c, r, c.box, [(96, 40, 33), (48, 16, 16), (110, 48, 38)], _n(20), _sz(6), _sz(15))
    tx.shatter(c, r, c.box, [(32, 11, 12), (118, 56, 43)], _n(12), _sz(4), _sz(9))
    _specks(c, r, 6, _sz(2), (172, 44, 12), (114, 22, 3))


def _sheet_shade(c, r, s):
    tx.fill(c, r, c.box, [(34, 12, 12), (24, 8, 9), (44, 17, 15), (17, 6, 7)])
    tx.shatter(c, r, c.box, [(42, 16, 15), (10, 3, 4)], _n(20), _sz(4), _sz(11))
    _specks(c, r, 4, _sz(2), (140, 34, 9), (92, 16, 2))


def _sheet_carve(c, r, s):
    tx.fill(c, r, c.box, [(84, 58, 53), (72, 48, 44), (96, 69, 63), (64, 42, 39)])
    tx.shatter(c, r, c.box, [(66, 43, 40), (102, 74, 68), (56, 35, 33)], _n(14), _sz(5), _sz(14))
    tx.shatter(c, r, c.box, [(74, 38, 27), (46, 27, 25)], _n(10), _sz(4), _sz(10))
    _specks(c, r, 10, _sz(2), (52, 32, 30), None)
    _specks(c, r, 3, _sz(2), (152, 48, 14), (88, 18, 2))


def _sheet_ember(c, r, s):
    tx.fill(c, r, c.box, [(11, 4, 5), (16, 6, 6), (7, 2, 3), (20, 8, 7)])
    halo = _sz(1)
    for _ in range(_n(15)):                    # hot veins: a random walk with a dim halo
        x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
        for _step in range(int(60 * _S)):
            c.rect(x - halo, y - halo, x + halo + 1, y + halo + 1, (58, 15, 4), (74, 15, 1))
            hot = r.pick([(255, 150, 30), (255, 212, 88), (248, 100, 14)])
            c.rect(x, y, x + 2, y + 2, hot, hot)
            x += r.i(-1, 1)
            y += r.i(-1, 1)
    _specks(c, r, 30, 2, (7, 3, 4), None)
    _specks(c, r, 10, _sz(2), (236, 92, 18), (194, 54, 5))


def _hell_ref(centre):
    """The radius a face's arc is measured at: its own region's, so the
    projection is near-isometric and the ring closes without a seam."""
    rad = math.hypot(centre[0], centre[1])
    z = centre[2]
    if z > 90.0 and rad > 55.0:
        return 66.0                            # the crater lip outside
    if DECK_Z - 1.0 < z < CEIL_Z + 0.5:
        return 58.5 if rad > 57.0 else 52.0    # outer wall | deck, lip walls, ceiling
    return 47.0 if z >= CEIL_Z + 0.5 else 45.0 # the shaft above the gallery | the pit below it


SHEETS = {
    "rock": tx.Sheet("rock", _sheet_rock, ref_r=_hell_ref, roughness=ROCK_ROUGHNESS, seed=1),
    "shade": tx.Sheet("shade", _sheet_shade, ref_r=_hell_ref, roughness=ROCK_ROUGHNESS, seed=2),
    "carve": tx.Sheet("carve", _sheet_carve, ref_r=_hell_ref, roughness=ROCK_ROUGHNESS, seed=3),
    "ember": tx.Sheet("ember", _sheet_ember, ref_r=_hell_ref, roughness=ROCK_ROUGHNESS, seed=4),
}
_ZONE_CLASS = {ZONE_ROCK: "rock", ZONE_SHADE: "shade", ZONE_CARVE: "carve",
               ZONE_EMBER: "ember", ZONE_GLOW: "glow"}


def _class_of(zone):
    """Atlas zone -> texel class; the river keeps its own sheet and unwrap."""
    if zone[0] in ("lava", "river", "fall", "river_t"):
        return zone[0]
    if zone[0] in ("deck", "wallface"):
        return "shade"
    return _ZONE_CLASS[zone]


def rock_material(name, albedo, emissive):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    for img, socket, y in ((albedo, "Base Color", 260), (emissive, "Emission Color", -220)):
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.interpolation = "Closest"
        node.location = (-460, y)
        nt.links.new(node.outputs["Color"], bsdf.inputs[socket])
    bsdf.inputs["Roughness"].default_value = ROCK_ROUGHNESS
    bsdf.inputs["Metallic"].default_value = ROCK_METALLIC
    bsdf.inputs["Emission Strength"].default_value = 1.0   # exactly 1.0: no KHR warning
    mat.diffuse_color = (0.13, 0.04, 0.04, 1.0)
    return mat


def _lava_texture():
    """The sea, painted once at world scale: a dark rock crust with a faint
    ember glow, cut by 1..3 m molten channels and a few wide pools. One window
    covers the whole floor, so nothing repeats and nothing seams."""
    c = _Canvas(LAVA_TEX)
    r = _Rng(LAVA_SEED)
    n = LAVA_TEX
    mpp = LAVA_SPAN / n
    edge = 0.5 * n - 3.0

    def M(metres):
        return max(1, int(round(metres / mpp)))

    def blot(x, y, w, h, rgb, glow):
        c.rect(int(x), int(y), int(x) + w, int(y) + h, rgb, glow)

    hot = [(226, 70, 10), (255, 104, 20), (206, 52, 6), (255, 132, 30)]
    rock = [(48, 22, 18), (36, 15, 13), (60, 29, 23), (27, 11, 11)]
    ember = [(66, 19, 6), (50, 13, 4), (80, 25, 8)]       # crust emission ~ 0.05
    for y in range(n):                                    # the crust: rock, with grain
        for x in range(n):
            c.put(x, y, r.pick(rock), r.pick(ember))
    for _ in range(340):                                  # slabs: 2..9 m tonal blocks
        sh = r.pick(rock)
        blot(r.i(0, n - 1), r.i(0, n - 1), M(2.0) + r.i(0, M(7.0)),
             M(2.0) + r.i(0, M(7.0)), sh, r.pick(ember))
    for _ in range(260):                                  # cold cracks between slabs
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        for _step in range(M(9.0)):
            c.put(x, y, (12, 5, 5), (14, 3, 1))
            c.put(x + 1, y, (12, 5, 5), (14, 3, 1))
            x += r.i(-1, 1)
            y += r.i(-1, 1)

    def flow(x, y, a, steps, w, shades):
        """A molten channel: a heading that wanders, turned back at the rim."""
        for _step in range(steps):
            sh = r.pick(shades)
            blot(x - 0.5 * w, y - 0.5 * w, w, w, sh, sh)
            a += 0.26 * r.sf()
            x += math.cos(a)
            y += math.sin(a)
            if math.hypot(x - 0.5 * n, y - 0.5 * n) > edge:
                a += math.pi

    pools = []
    for _ in range(5):                                    # 8..15 m pools, walked round
        for _try in range(40):
            px, py = r.i(0, n - 1), r.i(0, n - 1)
            if math.hypot(px - 0.5 * n, py - 0.5 * n) > edge - M(9.0):
                continue
            if all(math.hypot(px - q[0], py - q[1]) > M(26.0) for q in pools):
                break
        pools.append((px, py))
        spread = M(3.0) + r.i(0, M(3.0))          # pool: 8..15 m across, bounded
        size = M(1.5) + r.i(0, M(1.5))
        for _step in range(90):
            dx, dy = r.i(-spread, spread), r.i(-spread, spread)
            if dx * dx + dy * dy > spread * spread:
                continue
            sh = r.pick(hot)
            blot(px + dx - 0.5 * size, py + dy - 0.5 * size, size, size, sh, sh)
        for _k in range(2):                               # channels drain each pool
            flow(px, py, r.f() * TWO_PI, 260, M(1.0) + r.i(0, M(1.2)), hot)
    for _ in range(14):                                   # the rest of the network
        flow(r.i(0, n - 1), r.i(0, n - 1), r.f() * TWO_PI, 240,
             M(1.0) + r.i(0, M(1.0)), hot)
    dim = [(150, 40, 6), (120, 30, 5), (176, 50, 9)]
    for _ in range(150):                                  # hairline cracks, still lit
        flow(r.i(0, n - 1), r.i(0, n - 1), r.f() * TWO_PI, 90, M(0.35), dim)
    for _ in range(70):                                   # white-hot cores in the molten
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        o = (y * n + x) * 4
        if c.emi[o] < 0.3:
            continue
        core = r.pick([(255, 214, 96), (255, 178, 60)])
        blot(x, y, M(0.6), M(0.6), core, core)
    images = []
    for name, buf in ((LAVA_ALBEDO, c.alb), (LAVA_EMISSIVE, c.emi)):
        img = bpy.data.images.new(name, LAVA_TEX, LAVA_TEX, alpha=False)
        img.colorspace_settings.name = "sRGB"
        img.pixels.foreach_set(buf)
        img.update()
        images.append(img)
    return images[0], images[1]


def _image_file(name):
    """A texture file beside the script, packed into the .glb; None if absent."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), TEX_DIR, name)
    if not os.path.isfile(path):
        return None
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "sRGB"
    img.pack()
    print("MDL TEXTURE %s from %s" % (img.name, path))
    return img


def _lava_emissive_from(alb):
    """The sea's emissive, derived from its albedo: each texel emits its own
    colour scaled by a smoothstep of its brightest channel from LAVA_EMIT_LO
    (LAVA_EMIT_FLOOR of it) to LAVA_EMIT_HI (all of it), so the glow follows the
    bright orange and the dark crust only faintly glows. Pixels are the file's own sRGB
    bytes, as Blender hands them back."""
    w, h = alb.size
    src = [0.0] * (w * h * 4)
    alb.pixels.foreach_get(src)
    out = list(src)
    span = max(LAVA_EMIT_HI - LAVA_EMIT_LO, 1e-6)
    for o in range(0, len(src), 4):
        t = (max(src[o], src[o + 1], src[o + 2]) - LAVA_EMIT_LO) / span
        t = min(1.0, max(0.0, t))
        k = LAVA_EMIT_FLOOR + (1.0 - LAVA_EMIT_FLOOR) * t * t * (3.0 - 2.0 * t)
        out[o], out[o + 1], out[o + 2] = src[o] * k, src[o + 1] * k, src[o + 2] * k
        out[o + 3] = 1.0
    img = bpy.data.images.new(LAVA_EMISSIVE, w, h, alpha=False)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(out)
    img.update()
    return img


def _lava_sheet():
    """(albedo, emissive) for the sea: Ryan's tile with a derived emissive,
    a lava_emissive.png beside it if he draws one, else the painted fallback."""
    alb = _image_file("lava_albedo.png") if USE_TEXTURE_FILES else None
    if alb is None:
        return _lava_texture()
    return alb, (_image_file("lava_emissive.png") or _lava_emissive_from(alb))


def river_material(name, albedo, emissive):
    """The river: single-sided, exactly as the deck and the walls it is cut into."""
    return rock_material(name, albedo, emissive)


# =============================================================================
# GEOMETRY HELPERS -- winding is checked, never assumed
# =============================================================================

def _newell(pts):
    nx = ny = nz = 0.0
    n = len(pts)
    for i in range(n):
        ax, ay, az = pts[i]
        bx, by, bz = pts[(i + 1) % n]
        nx += (ay - by) * (az + bz)
        ny += (az - bz) * (ax + bx)
        nz += (ax - bx) * (ay + by)
    return (nx, ny, nz)


class _Mesh(object):
    """Face accumulator: every face states the direction its normal must point."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.zones = []
        self.spans = {}            # element chunk -> (first face, end face)
        self.crack = set()         # the S3 cracks' lava faces: their own LavaCrack surface

    def span(self, name, fn, *args, **kw):
        """Run fn(self, ...) and record the faces it appends as element `name`."""
        f0 = len(self.faces)
        out = fn(self, *args, **kw)
        self.spans[name] = (f0, len(self.faces))
        return out

    def v(self, p):
        self.verts.append(tuple(p))
        return len(self.verts) - 1

    def _emit(self, idx, want, zone, best=False):
        pts = [self.verts[j] for j in idx]
        n = _newell(pts)
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        if len(idx) == 4:
            if best and _min_angle(self.verts, idx[1], idx[2], idx[3], idx[0]) \
                    > _min_angle(self.verts, idx[0], idx[1], idx[2], idx[3]):
                idx = idx[1:] + idx[:1]                 # the better diagonal
            self.faces.append((idx[0], idx[1], idx[2]))
            self.faces.append((idx[0], idx[2], idx[3]))
            self.zones.append(zone)
            self.zones.append(zone)
        else:
            self.faces.append(tuple(idx))
            self.zones.append(zone)

    def quad(self, a, b, c, d, want, zone, best=False):
        """best: split on whichever diagonal gives the fatter triangles."""
        self._emit([a, b, c, d], want, zone, best)

    def tri(self, a, b, c, want, zone):
        self._emit([a, b, c], want, zone)

    def fan(self, ring, want, zone):
        for i in range(1, len(ring) - 1):
            self.tri(ring[0], ring[i], ring[i + 1], want, zone)

    def band(self, lo, hi, ang, inward, zone_fn, nu=1, nv=1):
        """Quads between two rings; zone_fn(i) picks the atlas zone per side.

        nu/nv grid each side's quad (bilinear on its own four corners, no new
        jitter) so no facet outgrows the atlas texel budget.
        """
        n = len(lo)
        for i in range(n):
            j = (i + 1) % n
            am = 0.5 * (ang[i] + ang[i] + 2.0 * math.pi / n)
            w = (math.cos(am), math.sin(am), 0.0)
            want = (-w[0], -w[1], 0.0) if inward else w
            if nu > 1 or nv > 1:
                _grid(self, lo[i], lo[j], hi[j], hi[i], want, zone_fn(i), nu, nv)
            else:
                self.quad(lo[i], lo[j], hi[j], hi[i], want, zone_fn(i))

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


UP = (0.0, 0.0, 1.0)


def _min_angle(verts, a, b, c, d):
    """Smallest corner angle over the two triangles a-b-c, a-c-d."""
    def corner(p, q, r):
        u = _sub(q, p)
        v = _sub(r, p)
        lu, lv = math.sqrt(_dot(u, u)), math.sqrt(_dot(v, v))
        if lu < 1e-12 or lv < 1e-12:
            return 0.0
        return math.acos(max(-1.0, min(1.0, _dot(u, v) / (lu * lv))))
    out = math.pi
    for tri in ((a, b, c), (a, c, d)):
        P = [verts[i] for i in tri]
        for k in range(3):
            out = min(out, corner(P[k], P[(k + 1) % 3], P[(k + 2) % 3]))
    return out


def _held(r, nrings, jag, one_sided):
    """Per-side radial bias held for runs of rings: steps, like cleaved rock."""
    out = [[0.0] * nrings for _ in range(SIDES)]
    for i in range(SIDES):
        k = 0
        while k < nrings:
            run = r.i(*JAG_RUN)
            v = r.f() * jag if one_sided else r.sf() * jag
            for kk in range(k, min(k + run, nrings)):
                out[i][kk] = v
            k += run
    return out


def _ring(m, ang, radius, z):
    """radius(i), z(i) -> vertex ids for one ring."""
    return [m.v((radius(i) * math.cos(ang[i]), radius(i) * math.sin(ang[i]), z(i)))
            for i in range(SIDES)]


# ---- subdivision: same silhouette, smaller texel budget per facet ---------
# The bug this fixes: a face got ONE UV window regardless of its size, so the
# deck's 10 m+ facets stretched the same texel count the tower spends on a
# 4-6 m facet across more than twice the world space. ANG_SUB gives every
# side's arc a <=3 m facet at the outer wall; _nv does the same per gap.
#
# Only where a runner stands close -- deck, ceiling, outer wall, and the pit
# wall from the deck edge down to the courtyard -- earns that 3 m grid. The
# shaft above the ceiling (300 m to the rim) and the courtyard floor are 20 m+
# from anything anyone stands on, so they get a coarse FAR_CAP band instead:
# same fix in kind, a tenth the triangles.
ANG_SUB = 4
FAR_CAP = 25.0


def _nv(gap, cap=3.0):
    """Sub-bands needed to keep a gap of this size under ~`cap` metres."""
    return max(1, int(math.ceil(abs(gap) / cap)))


def _grid(m, a, b, c, d, want, zone, nu, nv, edge_ab=None):
    """Subdivide the coarse quad a-b-c-d into nu x nv sub-quads by bilinear
    interpolation of its four existing corners. No new jitter, no reshaping:
    same corners, more triangles, so each one fits the atlas texel budget.
    edge_ab: nu+1 existing vertex ids along a->b, shared with a neighbour.
    """
    pa, pb, pc, pd = m.verts[a], m.verts[b], m.verts[c], m.verts[d]

    def pt(u, v):
        return tuple((1 - u) * (1 - v) * pa[k] + u * (1 - v) * pb[k]
                      + u * v * pc[k] + (1 - u) * v * pd[k] for k in range(3))

    corners = {(0, 0): a, (nu, 0): b, (nu, nv): c, (0, nv): d}
    ids = [[corners[(iu, iv)] if (iu, iv) in corners
            else m.v(pt(iu / float(nu), iv / float(nv)))
            for iu in range(nu + 1)] for iv in range(nv + 1)]
    if edge_ab is not None:
        ids[0] = list(edge_ab)
    for iv in range(nv):
        for iu in range(nu):
            m.quad(ids[iv][iu], ids[iv][iu + 1], ids[iv + 1][iu + 1], ids[iv + 1][iu],
                   want, zone)


# =============================================================================
# PIT FACES -- a (theta, z) grid of bilinear facets; cell mouths are cut into it
# =============================================================================

def _v3(p, q, s=1.0):
    return (p[0] + q[0] * s, p[1] + q[1] * s, p[2] + q[2] * s)


def _sub(p, q):
    return (p[0] - q[0], p[1] - q[1], p[2] - q[2])


def _dot(p, q):
    return p[0] * q[0] + p[1] * q[1] + p[2] * q[2]


def _breaks(vals, lo, hi):
    """lo, the breakpoints strictly between, hi."""
    return [lo] + [v for v in vals if lo < v < hi] + [hi]


def _bisect(a, x):
    lo, hi = 0, len(a)
    while lo < hi:
        mid = (lo + hi) // 2
        if x < a[mid]:
            hi = mid
        else:
            lo = mid + 1
    return lo


def _bisect_left(a, x):
    lo, hi = 0, len(a)
    while lo < hi:
        mid = (lo + hi) // 2
        if a[mid] < x:
            lo = mid + 1
        else:
            hi = mid
    return lo


TWO_PI = 2.0 * math.pi
DOWN = (0.0, 0.0, -1.0)
EPS = 1e-9


def _norm_t(a0, t):
    """A Blender angle brought into a ring's own [a0, a0 + 2pi) domain."""
    return a0 + (t - a0) % TWO_PI


class _Wall(object):
    """One pit face between ascending level rings. W(theta, z) is a point on
    the coarse bilinear side-quads, so anything cut into a facet lies on it.
    Facets are emitted as polygons carrying every vertex a neighbour or a
    mouth put on their edges, fanned from a centre point: no T-junctions."""

    def __init__(self, m, ang, ring_z, rings, nu, cap, zone_fn):
        self.m, self.ang, self.ring_z, self.rings = m, ang, ring_z, rings
        self.zone_fn, self.nu = zone_fn, nu
        n = len(ang)
        self.a0 = ang[0]
        self.cols = []
        for i in range(n):
            a = ang[i]
            b = ang[i + 1] if i + 1 < n else ang[0] + TWO_PI
            self.cols += [a + (b - a) * su / nu for su in range(nu)]
        self.cols.append(ang[0] + TWO_PI)
        self.ncol = len(self.cols) - 1
        self.cols_ext = self.cols + [c + TWO_PI for c in self.cols[1:]]
        self.rows = []
        for k in range(len(ring_z) - 1):
            nv = _nv(ring_z[k + 1] - ring_z[k], cap)
            self.rows += [ring_z[k] + (ring_z[k + 1] - ring_z[k]) * sv / nv for sv in range(nv)]
        self.rows.append(ring_z[-1])
        self.nodes = {}
        for k, ids in enumerate(rings):
            for i in range(n):
                self.nodes[(round(ang[i], 6), round(ring_z[k], 6))] = ids[i]
        self.holes = {}     # (ci, ri) -> [(ta, tb, za, zb)] clipped to the facet
        self.xt = {}        # row boundary -> extra thetas on it
        self.xz = {}        # column boundary -> extra zs on it

    def _norm(self, t):
        return self.a0 + (t - self.a0) % TWO_PI

    def _side(self, t):
        t = self._norm(t)
        i = max(0, min(len(self.ang) - 1, _bisect(self.ang, t) - 1))
        a = self.ang[i]
        b = self.ang[i + 1] if i + 1 < len(self.ang) else self.ang[0] + TWO_PI
        return i, (t - a) / (b - a)

    def W(self, t, z):
        """Vertex id of the wall point at (theta, z); shared when repeated."""
        key = (round(self._norm(t), 6), round(z, 6))
        if key in self.nodes:
            return self.nodes[key]
        i, u = self._side(t)
        j = (i + 1) % len(self.ang)
        zs = self.ring_z
        k = max(0, min(len(zs) - 2, _bisect(zs, z) - 1))
        v = (z - zs[k]) / (zs[k + 1] - zs[k])
        pa, pb = self.m.verts[self.rings[k][i]], self.m.verts[self.rings[k][j]]
        pd, pc = self.m.verts[self.rings[k + 1][i]], self.m.verts[self.rings[k + 1][j]]
        p = tuple((1 - u) * (1 - v) * pa[c] + u * (1 - v) * pb[c]
                  + u * v * pc[c] + (1 - u) * v * pd[c] for c in range(3))
        self.nodes[key] = self.m.v(p)
        return self.nodes[key]

    def P(self, t, z):
        return self.m.verts[self.W(t, z)]

    def tbreaks(self, ta, tb):
        return _breaks(self.cols_ext, ta, tb)

    def zbreaks(self, za, zb):
        return _breaks(self.rows, za, zb)

    def add_xt(self, r, t):
        self.xt.setdefault(r, set()).add(round(self._norm(t), 6))

    def add_xz(self, c, z):
        self.xz.setdefault(c % self.ncol, set()).add(round(z, 6))

    def clear(self, ts, zs):
        """True if the cut lines sit inside the face with no facet boundary
        within EDGE_CLEAR of any of them."""
        if min(zs) < self.rows[0] + 0.5 or max(zs) > self.rows[-1] - 0.5:
            return False
        for t in ts:
            tn = self._norm(t)
            if any(abs(c - tn) * INNER_R < EDGE_CLEAR for c in self.cols):
                return False
        for z in zs:
            if any(abs(rz - z) < EDGE_CLEAR for rz in self.rows):
                return False
        return True

    def hole(self, ta, tb, za, zb):
        """Cut the (theta, z) rectangle out of every facet it overlaps."""
        w = tb - ta
        ta = self._norm(ta)
        tb = ta + w
        pieces = [(ta, tb)]
        top = self.a0 + TWO_PI
        if tb > top:
            pieces = [(ta, top), (self.a0, self.a0 + (tb - top))]
        for pa, pb in pieces:
            c0 = max(0, _bisect(self.cols, pa) - 1)
            c1 = min(self.ncol - 1, _bisect_left(self.cols, pb) - 1)
            r0 = max(0, _bisect(self.rows, za) - 1)
            r1 = min(len(self.rows) - 2, _bisect_left(self.rows, zb) - 1)
            for ci in range(c0, c1 + 1):
                for ri in range(r0, r1 + 1):
                    piece = (max(pa, self.cols[ci]), min(pb, self.cols[ci + 1]),
                             max(za, self.rows[ri]), min(zb, self.rows[ri + 1]))
                    self.holes.setdefault((ci, ri), []).append(piece)
                    for z in (piece[2], piece[3]):
                        if self.rows[ri] + EPS < z < self.rows[ri + 1] - EPS:
                            self.add_xz(ci, z)
                            self.add_xz(ci + 1, z)

    def emit(self):
        for ci in range(self.ncol):
            am = 0.5 * (self.cols[ci] + self.cols[ci + 1])
            want = (-math.cos(am), -math.sin(am), 0.0)
            side = ci // self.nu
            for ri in range(len(self.rows) - 1):
                k = max(0, min(len(self.ring_z) - 2, _bisect(self.ring_z, self.rows[ri]) - 1))
                zone = self.zone_fn(k, side)
                t0, t1 = self.cols[ci], self.cols[ci + 1]
                holes = self.holes.get((ci, ri), [])
                zs = sorted(set([self.rows[ri], self.rows[ri + 1]]
                                + [h[2] for h in holes] + [h[3] for h in holes]))
                for j in range(len(zs) - 1):
                    za, zb = zs[j], zs[j + 1]
                    zm = 0.5 * (za + zb)
                    present = sorted((h[0], h[1]) for h in holes if h[2] <= zm <= h[3])
                    x = t0
                    spans = []
                    for ha, hb in present:
                        if ha - x > EPS:
                            spans.append((x, ha))
                        x = hb
                    if t1 - x > EPS:
                        spans.append((x, t1))
                    for ta, tb in spans:
                        self._poly(ci, ri, ta, tb, za, zb, holes, want, zone)

    def _poly(self, ci, ri, ta, tb, za, zb, holes, want, zone):
        """One stone rectangle of a facet, with every vertex that sits on its
        edges: a quad when there are none, else a fan from its centre."""
        t0, t1, z0, z1 = self.cols[ci], self.cols[ci + 1], self.rows[ri], self.rows[ri + 1]
        bot, top, left, right = {ta, tb}, {ta, tb}, set(), set()
        if abs(za - z0) < EPS:
            bot |= set(t for t in self.xt.get(ri, ()) if ta < t < tb)
        if abs(zb - z1) < EPS:
            top |= set(t for t in self.xt.get(ri + 1, ()) if ta < t < tb)
        for h in holes:
            if abs(h[3] - za) < EPS:
                bot |= set(t for t in (h[0], h[1]) if ta < t < tb)
            if abs(h[2] - zb) < EPS:
                top |= set(t for t in (h[0], h[1]) if ta < t < tb)
        if abs(ta - t0) < EPS:
            left = set(z for z in self.xz.get(ci % self.ncol, ()) if za < z < zb)
        if abs(tb - t1) < EPS:
            right = set(z for z in self.xz.get((ci + 1) % self.ncol, ()) if za < z < zb)
        pts = [(t, za) for t in sorted(bot)] + [(tb, z) for z in sorted(right)] \
            + [(t, zb) for t in sorted(top, reverse=True)] + [(ta, z) for z in sorted(left, reverse=True)]
        ids = [self.W(t, z) for t, z in pts]
        if len(ids) == 4:
            self.m.quad(ids[0], ids[1], ids[2], ids[3], want, zone)
            return
        c = self.W(0.5 * (ta + tb), 0.5 * (za + zb))
        for i in range(len(ids)):
            self.m.tri(c, ids[i], ids[(i + 1) % len(ids)], want, zone)


def _zipper(m, outer, inner, want, zone):
    """Triangulate the ring between two loops, each a list of (angle, id)
    sorted by angle about a common centre: len(outer)+len(inner) tris."""
    no, ni = len(outer), len(inner)
    i = j = 0
    for _ in range(no + ni):
        oa = outer[(i + 1) % no][0] + TWO_PI * ((i + 1) // no)
        ia = inner[(j + 1) % ni][0] + TWO_PI * ((j + 1) // ni)
        if i < no and (j >= ni or oa <= ia):
            m.tri(outer[i % no][1], outer[(i + 1) % no][1], inner[j % ni][1], want, zone)
            i += 1
        else:
            m.tri(inner[j % ni][1], inner[(j + 1) % ni][1], outer[i % no][1], want, zone)
            j += 1


def _one_sided(m, tris, want, zone):
    """Emit triangles that are already wound the same way round as ONE
    surface with ONE front side: the side is chosen once, by the triangle
    whose own normal lies most nearly along ``want``, and every triangle is
    then handed _emit its own normal so no face can be flipped alone. Asking
    each face which side it is on lets a surface that turns away from
    ``want`` invert a single triangle, and an inverted triangle is
    backface-culled: a hole where the mesh has none.
    want/zone may be callables of the triangle's centroid."""
    best, flip, keep = -1.0, False, []
    for tri in tris:
        if len(set(tri)) < 3:
            continue
        pts = [m.verts[v] for v in tri]
        n = _newell(pts)
        ln = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
        if ln < 1e-12:
            continue
        c = tuple(sum(p[k] for p in pts) / 3.0 for k in range(3))
        w = want(c) if callable(want) else want
        lw = math.sqrt(w[0] * w[0] + w[1] * w[1] + w[2] * w[2])
        d = (n[0] * w[0] + n[1] * w[1] + n[2] * w[2]) / (ln * lw)
        if abs(d) > best:
            best, flip = abs(d), d < 0.0
        keep.append((tri, n, c))
    for tri, n, c in keep:
        m.tri(tri[0], tri[1], tri[2], tuple(-x for x in n) if flip else n,
              zone(c) if callable(zone) else zone)


def _fan_at(m, apex, chain, want, zone):
    """A fan from one apex over a chain of ids: one surface, one front side."""
    _one_sided(m, [(apex, a, b) for a, b in zip(chain, chain[1:])], want, zone)


def _strip(m, A, B, want, zone):
    """Triangles between two chains of (param, id), each ascending, that do
    not share vertices: every vertex of both is used, no T-junctions.
    want/zone may be callables of the triangle's centroid."""
    i = j = 0

    def dist(a, b):
        return math.dist(m.verts[a], m.verts[b])

    tris = []
    while i < len(A) - 1 or j < len(B) - 1:
        if j == len(B) - 1 or (i < len(A) - 1 and
                               dist(A[i + 1][1], B[j][1]) <= dist(A[i][1], B[j + 1][1])):
            tri = (A[i][1], A[i + 1][1], B[j][1])       # the shorter diagonal
            i += 1
        else:
            tri = (A[i][1], B[j + 1][1], B[j][1])       # same way round as above
            j += 1
        tris.append(tri)
    _one_sided(m, tris, want, zone)


def _lip(d):
    """A convex round-over: how far in front of the flat the surface is, d
    below it, on a quarter circle of LIP_R."""
    if d >= LIP_R:
        return 0.0
    return LIP_R * (1.0 - (1.0 - (1.0 - d / LIP_R) ** LIP_P) ** (1.0 / LIP_P))


def _field(r, amp, n=6, wl=FLOOR_L):
    """A seeded 2-D height field: n plane waves, peak amp, metres."""
    ws = []
    for _ in range(n):
        a, L = r.f() * TWO_PI, wl[0] + r.f() * (wl[1] - wl[0])
        ws.append((math.cos(a) * TWO_PI / L, math.sin(a) * TWO_PI / L, r.f() * TWO_PI, 0.5 + r.f()))
    k = amp / sum(w[3] for w in ws)

    def f(x, y):
        return k * sum(w[3] * math.sin(w[0] * x + w[1] * y + w[2]) for w in ws)
    return f


def _by_angle(pts, centre):
    """[(angle, id)] about centre, ascending, for [((x, y), id)]."""
    out = [(math.atan2(p[1] - centre[1], p[0] - centre[0]), i) for p, i in pts]
    out.sort()
    return out


# =============================================================================
# CELLS -- placement, the screen layout, then the cut, reveals, screen and box
# =============================================================================

def _gap_field(s, z):
    """Spacing between cells, metres: low in clumps, high in the empty stretches."""
    n = 0.5 + 0.25 * (math.sin(s * 0.043 + 1.1) + math.sin(z * 0.061 - 0.7)) \
        + 0.25 * math.sin(s * 0.017 - z * 0.029 + 2.0)
    return GAP_MIN + (GAP_MAX - GAP_MIN) * min(1.0, max(0.0, n))


def _taper(kind, u):
    if kind == "up":
        return 1.0 - 0.45 * u
    if kind == "down":
        return 0.55 + 0.45 * u
    if kind == "mid":
        return 0.65 + 0.35 * math.sin(math.pi * u)
    return 1.0


ARCH_SPRING, ARCH_SHOULDER = 0.55, (0.22, 0.88)   # v1's arch: spring height, shoulder (x, y)


def _arch(w, h):
    """The mouth outline, counter-clockwise from the bottom-left."""
    sx, sy = ARCH_SHOULDER
    return [(0.0, 0.0), (w, 0.0), (w, ARCH_SPRING * h), ((1 - sx) * w, sy * h), (0.5 * w, h),
            (sx * w, sy * h), (0.0, ARCH_SPRING * h)]


def _arch_y(w, h, x):
    """Height of the arch at x, along its upper chain."""
    chain = [_arch(w, h)[i] for i in (6, 5, 4, 3, 2)]
    x = min(max(x, 0.0), w)
    for (xa, ya), (xb, yb) in zip(chain, chain[1:]):
        if xa <= x <= xb:
            return ya + (yb - ya) * (x - xa) / (xb - xa)
    return chain[-1][1]


def _layout(r, h):
    """The screen: levels, slot lanes, and each slot's wavy left/right edge
    per level (held at its foot/head outside its own span). Returns the
    slots, the levels and the screen width."""
    n = max(5, min(9, int(round(5 + 4.0 * (h - CELL_H[0]) / (CELL_H[1] - CELL_H[0]) + r.sf() * 0.8))))
    y1 = SILL[0] + r.f() * (SILL[1] - SILL[0])
    y2 = h - (LINTEL[0] + r.f() * (LINTEL[1] - LINTEL[0]))
    step = (y2 - y1) / (NL - 3)
    levels = [0.0, y1] + [y1 + step * (i + 1) + r.sf() * 0.08 * step for i in range(NL - 4)] + [y2, h]
    x = SIDE_M[0] + r.f() * (SIDE_M[1] - SIDE_M[0])
    slots = []
    for k in range(n):
        hw = SLOT_HW[0] + r.f() * (SLOT_HW[1] - SLOT_HW[0])
        lean = r.sf() * SLOT_LEAN
        kind = r.pick(["none", "up", "up", "down", "mid"])
        lane = 2.0 * hw + abs(lean) + 2.0 * SLOT_WAVE
        b = 1 if r.f() < 0.8 else 2
        t = NL - 2 if r.f() < 0.75 else NL - 3
        mid = x + 0.5 * lane
        L, R = [0.0] * NL, [0.0] * NL
        for j in range(b, t + 1):
            u = (j - b) / float(t - b)
            c = mid + lean * (u - 0.5) + r.sf() * SLOT_WAVE
            hwj = hw * _taper(kind, u) * (1.0 + r.sf() * 0.15)
            L[j], R[j] = max(x, c - hwj), min(x + lane, c + hwj)
            if R[j] - L[j] < 0.10:
                L[j], R[j] = c - 0.05, c + 0.05
        for j in range(NL):
            if j < b:
                L[j], R[j] = L[b], R[b]
            elif j > t:
                L[j], R[j] = L[t], R[t]
        slots.append({"L": L, "R": R, "b": b, "t": t})
        x += lane + (BAR_W[0] + r.f() * (BAR_W[1] - BAR_W[0]) if k < n - 1 else 0.0)
    w = x + SIDE_M[0] + r.f() * (SIDE_M[1] - SIDE_M[0])
    return slots, levels, w


def _place_cells(r, pit_wall, shaft):
    """Seeded dart throwing in (arc, z): uniform density from the courtyard
    up to UNIFORM_TOP, thinning above; a clear band under the gallery."""
    circ = TWO_PI * INNER_R
    cells = []

    def throw(z_of):
        h = CELL_H[0] + (CELL_H[1] - CELL_H[0]) * r.f() ** 0.9
        slots, levels, w = _layout(r, h)
        s = r.f() * circ
        z = z_of(h)
        depth = CELL_DEPTH[0] + r.f() * (CELL_DEPTH[1] - CELL_DEPTH[0])
        if z is None:
            return False
        wall = pit_wall if z < DECK_Z else shaft
        ta = (s - 0.5 * w) / INNER_R
        tb = ta + w / INNER_R
        za = z - 0.5 * h
        if not wall.clear((ta, tb, 0.5 * (ta + tb)), (za, za + ARCH_SPRING * h, za + h)):
            return False
        gap = _gap_field(s, z)
        for c in cells:
            ds = abs(s - c["s"])
            ds = min(ds, circ - ds)
            if ds < 0.5 * (w + c["w"]) + gap and abs(z - c["z"]) < 0.5 * (h + c["h"]) + gap:
                return False
        cells.append({"s": s, "z": z, "w": w, "h": h, "slots": slots, "levels": levels,
                      "depth": depth})
        return True

    pit_lo, pit_hi = COURTYARD_Z + 1.5, DECK_Z - PIT_CLEAR
    uni_lo, uni_hi = CEIL_Z + 1.0, UNIFORM_TOP

    def pit_z(h):
        return pit_lo + 0.5 * h + r.f() * (pit_hi - pit_lo - h)

    def uni_z(h):
        return uni_lo + 0.5 * h + r.f() * (uni_hi - uni_lo - h)

    def tail_z(h):
        z = uni_hi + 0.5 * h - TAIL_L * math.log(1.0 - r.f() * 0.999)
        return z if z + 0.5 * h < CELL_ZTOP else None

    n_pit = int(round(CELL_RHO * circ * (pit_hi - pit_lo)))
    n_uni = int(round(CELL_RHO * circ * (uni_hi - uni_lo)))
    n_tail = int(round(CELL_RHO * circ * TAIL_L * (1.0 - math.exp(-(CELL_ZTOP - uni_hi) / TAIL_L))))
    for want, z_of in ((n_pit, pit_z), (n_uni, uni_z), (n_tail, tail_z)):
        got = tries = 0
        while got < want and tries < 8000:
            tries += 1
            got += throw(z_of)
    return cells


def _carve(m, wall, c):
    """Cut the arched mouth, step back to the screen, cut the slots, build
    the arch-section box behind."""
    Wm, Hm = c["w"], c["h"]
    za = c["z"] - 0.5 * Hm
    zb = za + Hm
    ta = wall._norm((c["s"] - 0.5 * Wm) / INNER_R)
    tb = ta + Wm / INNER_R
    tc = 0.5 * (ta + tb)
    out = (math.cos(tc), math.sin(tc), 0.0)
    xs = (-math.sin(tc), math.cos(tc), 0.0)
    want = (-out[0], -out[1], 0.0)

    def T(x):
        return ta + (tb - ta) * x / Wm

    def Z(y):
        return za + y

    arch = _arch(Wm, Hm)
    zsp, tap = Z(arch[2][1]), T(arch[4][0])
    # ---- the wall: three rectangles out, two spandrels back in -----------
    wall.hole(ta, tb, za, zsp)
    wall.hole(ta, tap, zsp, zb)
    wall.hole(tap, tb, zsp, zb)
    lsh, rsh = (T(arch[5][0]), Z(arch[5][1])), (T(arch[3][0]), Z(arch[3][1]))
    left = [(ta, z) for z in wall.zbreaks(zsp, zb)] + [(t, zb) for t in wall.tbreaks(ta, tap)[1:]]
    right = [(t, zb) for t in wall.tbreaks(tap, tb)] + \
        [(tb, z) for z in reversed(wall.zbreaks(zsp, zb)[:-1])]
    for chain, sh in ((left, lsh), (right, rsh)):
        ids = [wall.W(t, z) for t, z in chain]
        shid = wall.W(*sh)
        for i in range(len(ids) - 1):
            m.tri(shid, ids[i], ids[i + 1], want, ZONE_ROCK)

    # ---- the mouth outline on the wall, with the facet crossings ------------
    rim = [(ta, za)] + [(t, za) for t in wall.tbreaks(ta, tb)[1:]] \
        + [(tb, z) for z in wall.zbreaks(za, zsp)[1:]] + [rsh, (tap, zb), lsh] \
        + [(ta, z) for z in reversed(wall.zbreaks(za, zsp)[1:])]
    pts = [wall.P(t, z) for t, z in rim]
    box = [wall.P(ta, za), wall.P(tb, za), wall.P(tb, zb), wall.P(ta, zb)]   # centred, unlike the rim
    cw = tuple(sum(p[k] for p in box) / 4.0 for k in range(3))
    D = max(_dot(_sub(p, cw), out) for p in pts) + SCREEN_BACK
    s0 = _v3(_v3(_v3(cw, out, D), xs, -0.5 * Wm), UP, -0.5 * Hm)
    sv = {}

    def S(x, y):
        key = (round(x, 6), round(y, 6))
        if key not in sv:
            sv[key] = m.v(_v3(_v3(s0, xs, x), UP, y))
        return sv[key]

    def XY(t, z):
        return (t - ta) / (tb - ta) * Wm, z - za

    def inward(p, q):
        """Toward the mouth centre, in the screen plane."""
        mx, my = 0.5 * (p[0] + q[0]), 0.5 * (p[1] + q[1])
        dx, dy = 0.5 * Wm - mx, 0.5 * Hm - my
        return _v3((0.0, 0.0, dy), xs, dx)

    # ---- reveals: the wall's mouth edge back to the screen edge -------------
    rim2 = [XY(t, z) for t, z in rim]
    for i in range(len(rim)):
        j = (i + 1) % len(rim)
        m.quad(wall.W(*rim[i]), wall.W(*rim[j]), S(*rim2[j]), S(*rim2[i]),
               inward(rim2[i], rim2[j]), ZONE_SHADE if rim2[i][1] > 0.0 or rim2[j][1] > 0.0 else ZONE_ROCK)
    outer = [((k[0], k[1]), i) for k, i in sv.items()]

    # ---- the screen: levels scale to the arch, so slot tops follow it -------
    slots, lv = c["slots"], c["levels"]
    lintel = Hm - lv[NL - 2]

    def Y(j, x):
        top = _arch_y(Wm, Hm, x) - lintel
        return lv[1] + (lv[j] - lv[1]) * (top - lv[1]) / (lv[NL - 2] - lv[1])

    def P(x, j):
        return S(x, Y(j, x))

    n = len(slots)
    for j in range(1, NL - 2):
        for k, sl in enumerate(slots):
            if not (sl["b"] <= j < sl["t"]):
                m.quad(P(sl["L"][j], j), P(sl["R"][j], j), P(sl["R"][j + 1], j + 1),
                       P(sl["L"][j + 1], j + 1), want, ZONE_ROCK)
            if k < n - 1:
                nx = slots[k + 1]
                m.quad(P(sl["R"][j], j), P(nx["L"][j], j), P(nx["L"][j + 1], j + 1),
                       P(sl["R"][j + 1], j + 1), want, ZONE_ROCK)
    first, last = slots[0], slots[-1]
    loop = []
    for sl in slots:
        loop += [(sl["L"][1], 1), (sl["R"][1], 1)]
    loop += [(last["R"][j], j) for j in range(2, NL - 2)]
    for sl in reversed(slots):
        loop += [(sl["R"][NL - 2], NL - 2), (sl["L"][NL - 2], NL - 2)]
    loop += [(first["L"][j], j) for j in range(NL - 3, 1, -1)]
    inner = [((x, Y(j, x)), P(x, j)) for x, j in loop]
    centre = (0.5 * Wm, 0.5 * Hm)
    _zipper(m, _by_angle(outer, centre), _by_angle(inner, centre), want, ZONE_ROCK)

    # ---- the box: an arch-section prism of flat glowing faces ---------------
    d = c["depth"]
    F, B = [], []
    for x, y in arch:
        dx, dy = x - centre[0], y - centre[1]
        k = 1.0 + BOX_EPS / max(math.hypot(dx, dy), 1e-6)
        f = _v3(_v3(s0, xs, centre[0] + dx * k), UP, centre[1] + dy * k)
        F.append(m.v(f))
        B.append(m.v(_v3(f, out, d)))
    for i in range(len(arch)):
        j = (i + 1) % len(arch)
        m.quad(F[i], F[j], B[j], B[i], inward(arch[i], arch[j]), ZONE_GLOW)
    m.fan(B, want, ZONE_GLOW)
    CELLS.append((cw, out, Wm, Hm))


def _lava_sea(m, wall, z, r, extra=()):
    """The floor of the shaft, as a sea of lava. Concentric rings down from the
    wall's own foot vertices (so the seam is shared) to the centre; the rings
    swell on two low harmonics of theta, level again under the tower's foot."""
    n = len(wall.ang)
    nu = wall.nu
    cols = _merge_cols([wall.cols[i * nu + su] for i in range(n) for su in range(nu)],
                       list(extra))
    rim = [wall.W(t, z) for t in cols]
    rings = [[(t, v) for t, v in zip(cols, rim)]]
    prev_f = LAVA_RINGS[0]
    rmean = sum(math.hypot(m.verts[v][0], m.verts[v][1]) for v in rim) / len(rim)
    for frac in LAVA_RINGS[1:]:
        p0, p1 = r.f() * TWO_PI, r.f() * TWO_PI
        k0, k1 = r.i(2, 4), r.i(5, 8)
        # columns thin toward the centre so a ring's cells stay near LAVA_ASPECT wide per metre deep
        n = min(len(cols), max(12, int(round(TWO_PI * frac / (LAVA_ASPECT * (prev_f - frac))))))
        prev_f = frac
        ring = []
        for k in range(n):
            t = cols[0] + TWO_PI * k / n
            w = _wall_point(wall, t, z)
            rad = math.hypot(w[0], w[1]) * frac
            taper = min(1.0, max(0.0, (rad - LAVA_FLAT_R) / 8.0))
            dz = LAVA_SWELL * taper * (0.62 * math.sin(k0 * t + p0)
                                       + 0.38 * math.sin(k1 * t + p1))
            dz = LAVA_STEP * round(dz / LAVA_STEP)   # plateaus: crust plates, not swell
            ring.append((t, m.v((rad * math.cos(t), rad * math.sin(t), z + dz))))
        rings.append(ring)
    cid = m.v((0.0, 0.0, z))
    rings.append([(t, cid) for t, _v in rings[-1]])     # the centre, on the last ring's columns
    t0 = cols[0]

    def _at(ring, t):
        """Ring's surface at angle t: a lerp along its chord between the columns either side."""
        u = (t - t0) % TWO_PI
        us = [(tt - t0) % TWO_PI for tt, _v in ring] + [TWO_PI]
        k = max(i for i in range(len(ring)) if us[i] <= u + 1e-9)
        pa, pb = m.verts[ring[k][1]], m.verts[ring[(k + 1) % len(ring)][1]]
        s_ = (u - us[k]) / max(us[k + 1] - us[k], 1e-9)
        return tuple(x + (y - x) * s_ for x, y in zip(pa, pb))

    fine = [rings[0]]                   # each gap cut to LAVA_SUB_M, on the inner ring's columns
    fracs = list(LAVA_RINGS) + [0.0]
    rmax = max(math.hypot(m.verts[v][0], m.verts[v][1]) for v in rim)
    for fa, fb, a_, b_ in zip(fracs, fracs[1:], rings, rings[1:]):
        n_ = max(1, int(math.ceil(rmax * (fa - fb) / LAVA_SUB_M)))
        for s in range(1, n_):
            u = s / float(n_)
            fine.append([(t, m.v(tuple(pa + (pb - pa) * u for pa, pb in zip(_at(a_, t), m.verts[v]))))
                         for t, v in b_])
        fine.append(b_)
    for a_, b_ in zip(fine[:-2], fine[1:-1]):
        _zipper(m, a_, b_, UP, ZONE_LAVA)   # Ryan's tile, on its own surface
    last = [v for _t, v in fine[-2]]
    ncol = len(last)
    for k in range(ncol):
        m.tri(cid, last[k], last[(k + 1) % ncol], UP, ZONE_LAVA)




# =============================================================================
# THE LAVA RIVER -- one channel, cut into the deck and both walls
# =============================================================================

def _bear_t(deg):
    """Game bearing (degrees) -> Blender angle (radians)."""
    return math.radians(-deg)


def _bear_deg(t):
    return (-math.degrees(t)) % 360.0


def pol(bearing_deg, radius, z):
    a = math.radians(-bearing_deg)
    return (radius * math.cos(a), radius * math.sin(a), z)


def _radial(bearing_deg):
    a = math.radians(-bearing_deg)
    return (math.cos(a), math.sin(a), 0.0)


def _tangent(bearing_deg):
    a = math.radians(-bearing_deg)
    return (-math.sin(a), math.cos(a), 0.0)


def _merge_cols(cols, extra, tol=1e-7):
    out = list(cols)
    for t in extra:
        if all(abs(t - c) > tol for c in out):
            out.append(t)
    out.sort()
    return out


def _side_u(ang, t):
    """Side index and fraction along it for a Blender angle in the ring's domain."""
    i = max(0, min(len(ang) - 1, _bisect(ang, t) - 1))
    a = ang[i]
    b = ang[i + 1] if i + 1 < len(ang) else ang[0] + TWO_PI
    return i, (t - a) / (b - a)


def _chord(m, ring, ang, t):
    """The point on a ring's own chord at column angle t -- what every band and
    the deck already interpolate to, so anything built on it welds."""
    i, u = _side_u(ang, t)
    j = (i + 1) % len(ang)
    pa, pb = m.verts[ring[i]], m.verts[ring[j]]
    return tuple((1.0 - u) * pa[c] + u * pb[c] for c in range(3))


def _push(p, out):
    """A point moved `out` metres along its own radius."""
    rad = math.hypot(p[0], p[1])
    if rad < EPS or abs(out) < EPS:
        return p
    k = (rad + out) / rad
    return (p[0] * k, p[1] * k, p[2])


def _ramp(x, a, b):
    """0 at a, 1 at b, clamped."""
    if abs(b - a) < EPS:
        return 1.0 if x >= b else 0.0
    return min(1.0, max(0.0, (x - a) / (b - a)))


# -----------------------------------------------------------------------------
# the platforms in the river
# -----------------------------------------------------------------------------

def _platforms():
    out = []
    for k in range(7):
        b = PLAT_B0 + PLAT_STEP * k
        out.append((b, PLAT_OUT_R if k % 2 == 0 else PLAT_IN_R, k % 2 == 1))
    return out


def _plat_sect(r):
    """A square top, eight boundary points so the sides can facet without the
    top ever ceasing to be square. Yawed off the run direction by at most
    PLAT_YAW degrees."""
    h = PLAT_HALF
    pts = [(h, -h), (h, 0.0), (h, h), (0.0, h),
           (-h, h), (-h, 0.0), (-h, -h), (0.0, -h)]
    a = math.radians(PLAT_YAW * r.sf())
    ca, sa = math.cos(a), math.sin(a)
    return [(x * ca - y * sa, x * sa + y * ca) for (x, y) in pts]


def _fin_sect(r):
    pts = []
    for i in range(6):
        a = TWO_PI * (i + 0.22 * r.sf()) / 6
        pts.append((FIN_HALF_R * math.cos(a) * (0.8 + 0.2 * r.f()),
                    FIN_HALF_T * math.sin(a) * (0.85 + 0.15 * r.f())))
    return pts


def _lake_column(m, bearing, radius, sect, rings, r, top_zone, ragged=0.0, cap=True):
    """A faceted column, closed top and bottom. ``rings`` is [(z, scale[, jag])]
    bottom to top; jag pushes each vertex out on its own, which is what facets
    the sides and leaves the top ring exactly the shape it was given."""
    er, et = _radial(bearing), _tangent(bearing)
    base = pol(bearing, radius, 0.0)
    lvl = []
    for ring in rings:
        z, sc = ring[0], ring[1]
        jag = ring[2] if len(ring) > 2 else 0.0
        out = []
        for (dr, dt) in sect:
            k = sc * (1.0 + jag * r.sf())
            out.append(m.v((base[0] + er[0] * dr * k + et[0] * dt * k,
                            base[1] + er[1] * dr * k + et[1] * dt * k,
                            z + (ragged * r.sf() if ragged else 0.0))))
        lvl.append(out)
    ns = len(sect)
    for a in range(len(lvl) - 1):
        for i in range(ns):
            j = (i + 1) % ns
            mid = (0.5 * (sect[i][0] + sect[j][0]), 0.5 * (sect[i][1] + sect[j][1]))
            want = (er[0] * mid[0] + et[0] * mid[1], er[1] * mid[0] + et[1] * mid[1], 0.0)
            zc = 0.5 * (rings[a][0] + rings[a + 1][0])
            m.quad(lvl[a][i], lvl[a][j], lvl[a + 1][j], lvl[a + 1][i], want,
                   ZONE_EMBER if zc < LAVA_Z else ZONE_SHADE)
    m.fan(_cap(lvl[-1]), UP, top_zone)
    if cap:
        m.fan(_cap(lvl[0]), DOWN, ZONE_EMBER)
    return lvl


def _cap(ring):
    """A square section fanned from a side midpoint: no zero-area triangles."""
    return ring[1:] + ring[:1] if len(ring) == 8 else ring


PLAT_RINGS = [(21.20, 1.40, 0.16), (21.90, 1.28, 0.12),
              (22.50, 1.13, 0.08), (PLAT_TOP_Z, 1.0, 0.0)]
FIN_RINGS = [(22.20, 1.22), (23.40, 1.10), (24.90, 1.0),
             (26.20, 0.86), (FIN_TOP_Z, 0.70)]

LAKE_SECTS = {}     # platform index -> (platform section, fin section or None);
                    # the collider re-uses these rather than drawing new ones.


def _build_platforms(m, r):
    for k, (b, rad, inner) in enumerate(_platforms()):
        sect = _plat_sect(r)
        fs = _fin_sect(r) if inner else None
        LAKE_SECTS[k] = (sect, fs)
        _lake_column(m, b, rad, sect, PLAT_RINGS, r, ZONE_DECK)
        if inner:
            _lake_column(m, b, FIN_R, fs, FIN_RINGS, r, ZONE_SHADE, ragged=0.22)


# -----------------------------------------------------------------------------
# S4 Demon Run: a lava field the full width of the deck, crossed pad to pad
# -----------------------------------------------------------------------------

def _s4_range(h):
    """Metres a pad flight covers before the feet are h m ABOVE where they left."""
    vx = S4_LAUNCH * math.cos(math.radians(S4_ANGLE))
    vy = S4_LAUNCH * math.sin(math.radians(S4_ANGLE))
    return vx * (vy + math.sqrt(vy * vy - 2.0 * S4_G * h)) / S4_G


def _s4_jump(h, v):
    """The furthest a jump at ground speed v reaches, landing h m higher."""
    d = S4_JUMP_V * S4_JUMP_V - 2.0 * S4_G * h
    if d < 0.0:
        return 0.0
    return v * (S4_JUMP_V + math.sqrt(d)) / S4_G


def _fwd(bearing_deg):
    """Unit vector along the run (increasing bearing), Blender x-y."""
    b = math.radians(bearing_deg)
    return (-math.sin(b), -math.cos(b))


def _unit2(p, q):
    d = (q[0] - p[0], q[1] - p[1])
    n = math.hypot(*d)
    return (d[0] / n, d[1] / n)


def _side_angles():
    r = _Rng(SEED)
    return [2.0 * math.pi * (i + r.sf() * ANG_JAG) / SIDES for i in range(SIDES)]


def _smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3.0 - 2.0 * x)


def _s4_layout():
    """Pads, rocks, landings and the flight table, solved from the arc.

    Rock k: centre C, axis a (unit, the bisector of the flight in and the
    flight out), top z. Its pad sits S4_PAD_BACK behind its front edge on the
    axis; a runner walks into the pad's back face and leaves S4_WALK_ON behind
    the pad's centre. Each landing is S4_LAND past the next rock's near edge."""
    if S4:
        return S4
    ang = _side_angles()
    cut_e = _bear_deg(ang[S4_CUT_SIDES[0]])
    bank_e = cut_e + S4_BANK
    # the entry pad's front edge on the bank column: the bank flattens into a
    # tongue under the pad, so the pad sits on level deck to the lava's edge
    pad0 = pol(bank_e - math.degrees(1.5 / S4_ENTRY_R), S4_ENTRY_R, 0.0)
    n = len(S4_ROCKS)
    tops = [DECK_Z + rk[1] for rk in S4_ROCKS] + [DECK_Z]
    rads = [rk[0] for rk in S4_ROCKS] + [S4_EXIT_R]
    faces = [_fwd(bank_e)] * (n + 1)
    axes = [_fwd(bank_e)] * n
    bear = [bank_e] * (n + 1)
    for _it in range(8):
        pads = [(pad0[0], pad0[1], DECK_Z)]
        lands, cents, origins = [], [], []
        for k in range(n + 1):
            P = pads[-1]
            f = faces[k]
            O = (P[0] - S4_WALK_ON * f[0], P[1] - S4_WALK_ON * f[1], P[2])
            rng = _s4_range(tops[k] - P[2])
            back = (S4_REAR - S4_LAND) if k < n else 0.0
            ax = axes[k] if k < n else f
            lo, hi = bear[k - 1] if k else bank_e, (bear[k - 1] if k else bank_e) + 40.0
            for _b in range(60):
                mid = 0.5 * (lo + hi)
                c = pol(mid, rads[k], 0.0)
                L = (c[0] - back * ax[0], c[1] - back * ax[1])
                if math.hypot(L[0] - O[0], L[1] - O[1]) < rng:
                    lo = mid
                else:
                    hi = mid
            bear[k] = 0.5 * (lo + hi)
            c = pol(bear[k], rads[k], 0.0)
            L = (c[0] - back * ax[0], c[1] - back * ax[1], tops[k])
            lands.append(L)
            origins.append(O)
            cents.append((c[0], c[1], tops[k]))
            faces[k] = _unit2(O, L)
            if k < n:
                pads.append((c[0] + (S4_FRONT - S4_PAD_BACK) * ax[0], c[1] + (S4_FRONT - S4_PAD_BACK) * ax[1], tops[k]))
        for k in range(n):
            axes[k] = _unit2((0.0, 0.0), (faces[k][0] + faces[k + 1][0], faces[k][1] + faces[k + 1][1]))
    # the exit cut is the side boundary; the last flight must land 1.5..2.5 m
    # past the lava's edge there (the run is tuned until it does)
    exit_land_b = _bear_deg(math.atan2(lands[-1][1], lands[-1][0]))
    cut_x = _bear_deg(ang[S4_CUT_SIDES[1]])
    bank_x = cut_x - S4_BANK
    S4["exit_past_bank"] = math.radians(exit_land_b - bank_x) * S4_EXIT_R
    S4["exit_past_edge"] = S4["exit_past_bank"] - S4_EDGE_WANDER[1]  # past the lava's furthest wander
    rocks = []
    for k in range(n):
        C = cents[k]
        a = axes[k]
        nrm = (-a[1], a[0])
        if nrm[0] * C[0] + nrm[1] * C[1] > 0.0:        # across, toward the tower
            nrm = (-nrm[0], -nrm[1])
        f_in, f_out = faces[k], faces[k + 1]
        sgn = 1.0 if (nrm[0] == -a[1] and nrm[1] == a[0]) else -1.0
        rk = {"C": (C[0], C[1]), "a": a, "n": nrm, "top": tops[k], "r": rads[k],
              "b": _bear_deg(math.atan2(C[1], C[0])),
              "n_in": (sgn * -f_in[1], sgn * f_in[0]),
              "n_out": (sgn * -f_out[1], sgn * f_out[0])}
        rk.update(_s4_spec(_Rng(S4_SEED + 11 + k), S4_ROCKS[k][2]))
        rocks.append(rk)
    S4["rocks"] = rocks
    S4["pads"] = [(pads[k][0], pads[k][1], pads[k][2], faces[k]) for k in range(n + 1)]
    S4["lands"] = lands
    S4["origins"] = origins
    S4["cut_entry"], S4["bank_entry"] = cut_e, bank_e
    S4["bank_exit"], S4["cut_exit"] = bank_x, cut_x
    return S4


def _s4_across(rock, u):
    """The across direction at u along the rock: square to the flight in at
    the rear edge, to the flight out at the front, blended between."""
    f = _smooth((u / (S4_REAR if u < 0.0 else S4_FRONT) + 0.6) / 1.2)
    n0, n1 = rock["n_in"], rock["n_out"]
    x, y = n0[0] + (n1[0] - n0[0]) * f, n0[1] + (n1[1] - n0[1]) * f
    d = math.hypot(x, y)
    return (x / d, y / d)


def _s4_world(rock, u, v):
    """World x-y of local (u along the axis, v across toward the tower)."""
    n = _s4_across(rock, u)
    return (rock["C"][0] + u * rock["a"][0] + v * n[0],
            rock["C"][1] + u * rock["a"][1] + v * n[1])


def _s4_local(rock, p):
    """(u, v) of a world x-y point: the bent frame inverted by iteration."""
    dx, dy = p[0] - rock["C"][0], p[1] - rock["C"][1]
    u = dx * rock["a"][0] + dy * rock["a"][1]
    v = dx * rock["n"][0] + dy * rock["n"][1]
    for _ in range(4):
        n = _s4_across(rock, u)
        na = n[0] * rock["a"][0] + n[1] * rock["a"][1]
        nn = n[0] * rock["n"][0] + n[1] * rock["n"][1]
        v = (dx * rock["n"][0] + dy * rock["n"][1]) / nn
        u = (dx * rock["a"][0] + dy * rock["a"][1]) - v * na
    return (u, v)


def _s4_spec(r, hump):
    """One boulder's own numbers: its waterline R(theta) -- a superellipse
    with its own semi-axis in each quadrant (long at the rear on the tower
    side, where the hump's tail is), wandering -- the hump's height, noise."""
    p1, p2 = r.f() * TWO_PI, r.f() * TWO_PI
    jit = [r.sf() * 0.02 for _ in range(S4_MASS_N)]
    ang = [TWO_PI * (i + 0.5 + 0.25 * r.sf()) / S4_MASS_N for i in range(S4_MASS_N)]
    au_f, au_r = S4_FRONT / S4_EDGE_Q, S4_REAR / S4_EDGE_Q
    av_out = S4_HALF_ACROSS / S4_EDGE_Q

    def R(th):
        c, sn = math.cos(th), math.sin(th)
        au = au_f if c >= 0.0 else (au_r * S4_REAR_IN if sn > 0.0 else au_r)
        av = S4_HUMP_SIDE if sn >= 0.0 else av_out
        rr = 1.0 / ((abs(c) / au) ** S4_MASS_P + (abs(sn) / av) ** S4_MASS_P) ** (1.0 / S4_MASS_P)
        return rr * (1.0 + S4_WOB * (0.6 * math.sin(2.0 * th + p1) + 0.4 * math.sin(3.0 * th + p2)))
    return {"R": R, "ang": ang, "jit": jit, "h": hump,
            "noise": _field(_Rng(r.n()), S4_NOISE, 5, S4_NOISE_L)}


def _s4_q(rock, u, v):
    """How far out a local point is, of the waterline: 1 at the waterline."""
    rr = math.hypot(u, v)
    if rr < EPS:
        return 0.0
    return rr / rock["R"](math.atan2(v, u))


def _s4_hump(rock, u, v):
    """The hump's height over the landing at local (u, v)."""
    uh, ah = S4_HUMP_U
    dv = v - S4_HUMP_V
    bh = S4_HUMP_B[0] if dv > 0.0 else S4_HUMP_B[1]
    d2 = (abs(u - uh) / ah) ** S4_HUMP_P[0] + (dv / bh) ** 2
    if d2 >= 1.0:
        return 0.0
    return rock["h"] * (1.0 - d2) ** S4_HUMP_P[1]


def _s4_z(rock, u, v, q=None, noise=True):
    """(z, landing) of the boulder at local (u, v): a flat landing, rounded
    shoulders down under the lava, the hump on top, rock noise off the flat."""
    if q is None:
        q = _s4_q(rock, u, v)
    # the base drops behind the standing edges whatever the waterline does
    # there: the long rear-inner quadrant carries only the hump's tail
    H = _s4_hump(rock, u, v)
    hn = H / max(rock["h"], EPS)
    q = max(q, (1.0 - hn) * max(-u / (S4_REAR / S4_EDGE_Q), u / (S4_FRONT / S4_EDGE_Q)))
    top = rock["top"]
    water = LAVA_Z - S4_WATER_D
    if q <= S4_FLAT_Q:
        zs = top
    elif q <= 1.0:
        t = (q - S4_FLAT_Q) / (1.0 - S4_FLAT_Q)
        zs = top - (top - water) * math.sin(0.5 * math.pi * t) ** 2
    else:
        zs = water - (q - 1.0) / (S4_MASS_Q[-1] - 1.0) * (S4_BOTTOM_D - S4_WATER_D)
    land = _ramp(S4_FLAT_Q - q, 0.0, 0.08) * _ramp(0.03 - H / max(rock["h"], EPS), 0.0, 0.03)
    z = zs + H
    if noise:
        z += (1.0 - land) * rock["noise"](u, v)
    return z, land


def _s4_crest(rock, u, v):
    """Height of the rock over its landing top at local (u, v), for the
    sight-line checks: the hump, less the shoulder's drop."""
    return _s4_z(rock, u, v, noise=False)[0] - rock["top"]


def _s4_inside(rock, p, q_max=1.0):
    """True when a world x-y point is over the boulder out to q_max of the
    waterline (1: the waterline, S4_EDGE_Q: the standing edge)."""
    u, v = _s4_local(rock, p)
    return _s4_q(rock, u, v) <= q_max


def _s4_rock(m, r, rock, coll=False):
    """One landing rock: a closed heightfield on a polar grid in the bent
    frame -- landing, hump, shoulders and stem one surface, the same mesh for
    the collider."""
    R, ang, jit = rock["R"], rock["ang"], rock["jit"]
    zc, _l = _s4_z(rock, 0.0, 0.0, 0.0)
    C = rock["C"]
    centre = m.v((C[0], C[1], zc))
    rings, info = [], []
    for q in S4_MASS_Q:
        ids, row = [], []
        for th, j in zip(ang, jit):
            rr = q * R(th) * (1.0 + j)
            u, v = rr * math.cos(th), rr * math.sin(th)
            z, land = _s4_z(rock, u, v, q)
            x, y = _s4_world(rock, u, v)
            ids.append(m.v((x, y, z)))
            row.append((z, land))
        rings.append(ids)
        info.append(row)

    def zone(z, land):
        if coll:
            return ZONE_ROCK
        if z < LAVA_Z:
            return ZONE_EMBER
        return ZONE_DECK if land > 0.5 else ZONE_SHADE
    n = S4_MASS_N
    for i in range(n):
        j = (i + 1) % n
        m.tri(centre, rings[0][i], rings[0][j], UP, zone(zc, 1.0))
    for a in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            zm = 0.25 * (info[a][i][0] + info[a][j][0] + info[a + 1][i][0] + info[a + 1][j][0])
            lm = 0.25 * (info[a][i][1] + info[a][j][1] + info[a + 1][i][1] + info[a + 1][j][1])
            m.quad(rings[a][i], rings[a][j], rings[a + 1][j], rings[a + 1][i], UP, zone(zm, lm),
                   best=True)
    m.fan(rings[-1], DOWN, ZONE_ROCK if coll else ZONE_EMBER)


def _s4_bank_line(r):
    """(middle-column wander, lava-edge wander) per row, metres. The cut
    column is a side boundary and never moves."""
    n = BANK_WALL + BANK_DECK + BANK_PIT
    mid = _walk(r, n, *S4_MID_WANDER)
    edge = _walk(r, n, *S4_EDGE_WANDER)
    return [(mid[i], edge[i]) for i in range(n)]


def _s4_tongue(rad):
    """1 where the entry bank is level under the entry pad, 0 elsewhere."""
    half, blend = S4_TONGUE
    return _smooth((rad - (S4_ENTRY_R - half - blend)) / blend) \
        * _smooth(((S4_ENTRY_R + half + blend) - rad) / blend)


def _s4_wall_spec():
    """The cave wall: a ridge of rock on the tower side of the field, r
    S4_WALL_R, from the deck before the entry pad to just short of the exit
    bank. Per column (bearing): centre radius, half width, height over its
    base, base z. Full height in front of every landing, up to the ceiling
    at the rocks, a window (or a break) on the falling side of each flight,
    sunk into the lava at both ends."""
    if "wall" in S4:
        return S4["wall"]
    lay = _s4_layout()
    r = _Rng(S4_SEED + 21)
    p1, p2, p3 = r.f() * TWO_PI, r.f() * TWO_PI, r.f() * TWO_PI
    b0, b1 = S4_WALL_B
    n = int(round((b1 - b0) / S4_WALL_STEP))
    windows = []
    for k in range(len(lay["pads"])):
        O, L = lay["origins"][k], lay["lands"][k]
        f = S4_WALL_WINDOW_AT
        wx, wy = O[0] + (L[0] - O[0]) * f, O[1] + (L[1] - O[1]) * f
        windows.append((_bear_deg(math.atan2(wy, wx)), S4_WALL_WINDOW[k]))
    joins = [rk["b"] for rk in lay["rocks"]]
    cols = []
    for i in range(n + 1):
        bb = b0 + (b1 - b0) * i / n
        s_m = math.radians(bb) * S4_WALL_ARC_R              # arc position, metres
        rc = S4_WALL_R + S4_WALL_WANDER * (0.6 * math.sin(0.61 * s_m + p1) + 0.4 * math.sin(1.37 * s_m + p2))
        W = S4_WALL_W[0] + 0.5 * (S4_WALL_W[1] - S4_WALL_W[0]) * (1.0 + math.sin(0.83 * s_m + p3))
        H = S4_WALL_H[0] + 0.5 * (S4_WALL_H[1] - S4_WALL_H[0]) * (1.0 + 0.7 * math.sin(0.9 * s_m + p2)
                                                                  + 0.3 * math.sin(2.3 * s_m + p1))
        H += S4_WALL_CRAG * (r.sf() + 0.5 * math.sin(4.1 * s_m + p3))   # a craggy top edge
        for jb in joins:                                     # up to the ceiling at the landings
            d = abs(bb - jb) * math.radians(1.0) * S4_WALL_ARC_R
            H += (S4_WALL_JOIN - H) * _smooth((S4_WALL_JOIN_W - d) / 1.5) if d < S4_WALL_JOIN_W else 0.0
        for wb, depth in windows:                            # windows and the break
            d = abs(bb - wb) * math.radians(1.0) * S4_WALL_ARC_R
            if d < S4_WALL_WINDOW_W:
                H += (depth - H) * _smooth((S4_WALL_WINDOW_W - d) / 1.2)
        for eb, sgn in ((b0, 1.0), (b1, -1.0)):              # sunk at both ends
            d = (bb - eb) * sgn * math.radians(1.0) * S4_WALL_ARC_R
            if d < S4_WALL_END:
                H += (-0.6 - H) * (1.0 - _smooth(d / S4_WALL_END))
        for eb, sgn, wn in ((b0, 1.0, "204"), (b1, -1.0, "286")):   # never past the corner walls
            g = 1.0 - _smooth((bb - eb) * sgn * math.radians(1.0) * S4_WALL_ARC_R / S4_WALL_PULL)
            lw = next(w for w in LIP_WALLS if w["name"] == wn)
            ri, ro = lw.get("r_in", LIP_R_IN), lw.get("r_out", LIP_R_OUT)
            rc, W = rc + (0.5 * (ri + ro) - rc) * g, W + (0.5 * (ro - ri) - W) * g
        on_deck = _ramp(lay["bank_entry"] + 0.3 - bb, 0.0, 0.6)  # standing on the deck before the field
        base = LAVA_Z + (DECK_Z - LAVA_Z) * on_deck
        cols.append({"b": bb, "rc": rc, "W": W, "H": H, "base": base})
    S4["wall"] = {"cols": cols, "windows": windows,
                  "noise": _field(_Rng(S4_SEED + 22), S4_NOISE, 5, S4_NOISE_L)}
    return S4["wall"]


def _s4_wall_prof(x):
    """Ridge section: 1 on the crest, 0 at the foot, rounded top, no wall."""
    return math.cos(0.5 * math.pi * min(1.0, abs(x))) ** S4_WALL_PROF


def _s4_wall_z(x, y, noise=True):
    """The wall's surface height at world x-y, or None off its footprint."""
    wall = _s4_wall_spec()
    cols = wall["cols"]
    bb = _bear_deg(math.atan2(y, x))
    if bb < cols[0]["b"] or bb > cols[-1]["b"]:
        return None
    fi = (bb - cols[0]["b"]) / (cols[-1]["b"] - cols[0]["b"]) * (len(cols) - 1)
    i = min(len(cols) - 2, int(fi))
    t = fi - i
    c0, c1 = cols[i], cols[i + 1]
    rc = c0["rc"] + (c1["rc"] - c0["rc"]) * t
    W = c0["W"] + (c1["W"] - c0["W"]) * t
    H = c0["H"] + (c1["H"] - c0["H"]) * t
    base = c0["base"] + (c1["base"] - c0["base"]) * t
    d = (math.hypot(x, y) - rc) / W
    if abs(d) > 1.0:
        return None
    z = base - S4_WALL_SINK + (H + S4_WALL_SINK) * _s4_wall_prof(d)
    if noise:
        z += wall["noise"](x, y) * (1.0 - abs(d) ** 4)
    return z


def _s4_wall(m, coll=False):
    """The wall as one closed strip: rows across the ridge from the outer
    foot (under the lava) over the crest to the inner foot, a flat bottom."""
    wall = _s4_wall_spec()
    cols = wall["cols"]
    D = S4_WALL_ROWS
    rows = []
    for c in cols:
        row = []
        for d in D:
            rad = c["rc"] + d * c["W"]
            p = pol(c["b"], rad, 0.0)
            z = c["base"] - S4_WALL_SINK + (c["H"] + S4_WALL_SINK) * _s4_wall_prof(d)
            if not coll:
                z += wall["noise"](p[0], p[1]) * (1.0 - abs(d) ** 4)
            row.append(m.v((p[0], p[1], z)))
        bot = [m.v((pol(c["b"], c["rc"] + d * c["W"], 0.0)[0], pol(c["b"], c["rc"] + d * c["W"], 0.0)[1],
                    c["base"] - S4_WALL_SINK - 0.5)) for d in (-1.0, 1.0)]
        rows.append(row + bot)
    nd = len(D)
    for i in range(len(rows) - 1):
        A, B = rows[i], rows[i + 1]
        for j in range(nd - 1):
            zm = 0.25 * sum(m.verts[v][2] for v in (A[j], A[j + 1], B[j], B[j + 1]))
            zone = ZONE_ROCK if coll else (ZONE_EMBER if zm < LAVA_Z else ZONE_SHADE)
            m.quad(A[j], A[j + 1], B[j + 1], B[j], UP, zone, best=True)
        er = _radial(0.5 * (cols[i]["b"] + cols[i + 1]["b"]))
        m.quad(A[0], B[0], B[nd], A[nd], (-er[0], -er[1], 0.0), ZONE_EMBER)     # outer foot skirt
        m.quad(A[nd - 1], B[nd - 1], B[nd + 1], A[nd + 1], er, ZONE_EMBER)      # inner foot skirt
        m.quad(A[nd], B[nd], B[nd + 1], A[nd + 1], DOWN, ZONE_EMBER)            # bottom
    for i, sgn in ((0, -1.0), (len(rows) - 1, 1.0)):                             # the ends
        row = rows[i]
        et = _tangent(cols[i]["b"])
        want = (et[0] * sgn, et[1] * sgn, 0.0)
        m.fan(row[:nd] + [row[nd + 1], row[nd]], want, ZONE_EMBER)


def _s4_block(target, eye):
    """How far under rock the sight line from the eye to the target passes:
    max over the line of (surface - line), over the landing rocks and the
    wall; <= 0 means the target is in view."""
    lay = _s4_layout()
    best = -9.0
    for k in range(1, S4_SIGHT_N):
        f = k / float(S4_SIGHT_N)
        p = (eye[0] + (target[0] - eye[0]) * f, eye[1] + (target[1] - eye[1]) * f,
             eye[2] + (target[2] - eye[2]) * f)
        zw = _s4_wall_z(p[0], p[1], noise=False)
        if zw is not None:
            best = max(best, zw - p[2])
        for rk in lay["rocks"]:
            if _s4_inside(rk, p):
                u, v = _s4_local(rk, p)
                best = max(best, _s4_z(rk, u, v, noise=False)[0] - p[2])
    return best


def _s4_proxy(name, centre, size, colour):
    """A render-only box: a body standing at centre (feet), size (w, d, h)."""
    w, d, h = size
    x, y, z = centre
    verts = [(x + sx * 0.5 * w, y + sy * 0.5 * d, z + sz * h)
             for sz in (0, 1) for sy in (-1, 1) for sx in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = mdl._link(bpy.data.objects.new(name, me))
    ob.data.materials.append(mdl.flat_material(name + "Mat", colour))
    return ob


def _s4_review(scene, shot, ld, key, bg, objects):
    """Review renders only, lit as S2's: a white fill sun, brighter world,
    exposure up, the real materials; proxies for a body on a landing and a
    body in the air. Exported before this runs; put back after."""
    lay = _s4_layout()
    rocks = lay["rocks"]
    p0 = lay["pads"][0]

    def on(rock, u, v, dz=0.0):
        x, y = _s4_world(rock, u, v)
        return (x, y, rock["top"] + dz)

    rl = bpy.data.lights.new("S4ReviewFill", type="SUN")
    rl.energy = REVIEW_SUN
    rl.color = (1.0, 0.96, 0.92)
    fill = mdl._link(bpy.data.objects.new("S4ReviewFill", rl))
    fill.rotation_euler = (math.radians(35.0), math.radians(-20.0), math.radians(40.0))
    key.hide_render = True
    was_bg = (tuple(bg.inputs[0].default_value), bg.inputs[1].default_value)
    bg.inputs[0].default_value = (0.55, 0.50, 0.48, 1.0)
    bg.inputs[1].default_value = REVIEW_WORLD
    mdl._try(scene.view_settings, "exposure", REVIEW_EXPOSURE)

    green = (0.2, 1.0, 0.3, 1.0)
    body = _s4_proxy("S4ReviewBody", on(rocks[1], -1.4, -0.4), (0.6, 0.6, S4_BODY_H), green)
    O, f = lay["origins"][2], lay["pads"][2][3]
    apex = (O[0] + 7.0 * f[0], O[1] + 7.0 * f[1], O[2] + 3.68)
    flyer = _s4_proxy("S4ReviewFlyer", apex, (0.6, 0.6, S4_BODY_H), green)

    shot("review_s4_entry", (p0[0], p0[1], DECK_Z + EYE_H), on(rocks[1], 0.0, 1.0, 0.8), 24.0, (1400, 800))
    p2 = lay["pads"][2]
    shot("review_s4_r1", on(rocks[0], -1.5, -0.5, EYE_H), (p2[0], p2[1], p2[2] + 0.3), 24.0, (1400, 800))
    O1, f1 = lay["origins"][1], lay["pads"][1][3]
    shot("review_s4_flight", (O1[0] - 5.0 * f1[0], O1[1] - 5.0 * f1[1], O1[2] + 3.0),
         (O1[0] + 8.0 * f1[0], O1[1] + 8.0 * f1[1], O1[2] + 2.5), 24.0, (1400, 800))
    shot("review_s4_guard", (0.0, 0.0, S4_GUARD_EYE), pol(242.0, 52.0, DECK_Z), 35.0, (1400, 900))
    shot("review_s4_high", pol(241.5, 20.0, 60.0), pol(241.5, 52.0, DECK_Z), 24.0, (1500, 1000))
    shot("review_s4_cover", (0.0, 0.0, S4_GUARD_EYE), on(rocks[1], -1.0, 0.0, 0.9), 100.0, (1200, 800))
    shot("review_s4_outer", pol(216.0, 56.4, DECK_Z + EYE_H), pol(248.0, 56.9, LAVA_Z), 28.0, (1400, 800))
    shot("review_s4_wall", pol(229.0, 55.5, DECK_Z + 2.5), pol(246.0, 49.5, LAVA_Z + 3.0), 26.0, (1400, 800))

    for ob in (body, flyer, fill):
        bpy.data.objects.remove(ob, do_unlink=True)
    key.hide_render = False
    bg.inputs[0].default_value = was_bg[0]
    bg.inputs[1].default_value = was_bg[1]
    mdl._try(scene.view_settings, "exposure", 0.0)


def _s4_stats():
    """The flight table, the gaps, the cover, and what the scene needs."""
    lay = _s4_layout()
    eye = (0.0, 0.0, S4_GUARD_EYE)

    def godot(x, y, z):
        return (x, z, -y)

    print("MDL STATS s4 field bearings: entry cut %.2f bank %.2f | exit bank %.2f cut %.2f; exit lands %.2f m past the bank column, %.2f m past the lava's furthest wander; lava_y=%.2f"
          % (lay["cut_entry"], lay["bank_entry"], lay["bank_exit"], lay["cut_exit"],
             lay["exit_past_bank"], lay["exit_past_edge"], LAVA_Z))
    rocks = lay["rocks"]
    edges = []      # walkable-top outlines in flight order: entry lava edge, rocks, exit lava edge
    for k, (x, y, z, f) in enumerate(lay["pads"]):
        O, L = lay["origins"][k], lay["lands"][k]
        gx, gy, gz = godot(x, y, z)
        fg = (f[0], -f[1])
        rng = math.hypot(L[0] - O[0], L[1] - O[1])
        h = L[2] - O[2]
        t = (S4_LAUNCH * math.sin(math.radians(S4_ANGLE))
             + math.sqrt((S4_LAUNCH * math.sin(math.radians(S4_ANGLE))) ** 2 - 2.0 * S4_G * h)) / S4_G
        apex = (S4_LAUNCH * math.sin(math.radians(S4_ANGLE))) ** 2 / (2.0 * S4_G)
        print("MDL STATS s4 hop%d pad Transform3D(%.6f, 0, %.6f, 0, 1, 0, %.6f, 0, %.6f, %.4f, %.3f, %.4f) "
              "bearing=%.2f r=%.2f | origin (%.2f, %.2f, %.2f) -> landing (%.2f, %.2f, %.2f) "
              "range=%.2f m rise=%+.2f flight=%.2f s apex=+%.2f m"
              % (k + 1, -fg[1], -fg[0], fg[0], -fg[1], gx, gy, gz,
                 _bear_deg(math.atan2(y, x)), math.hypot(x, y), O[0], O[1], O[2],
                 L[0], L[1], L[2], rng, h, t, apex))
    wall = _s4_wall_spec()
    print("MDL STATS s4 wall bearings %.1f..%.1f r=%.1f +-%.1f, %d columns, height over lava %.1f..%.1f m, "
          "up to the ceiling at %s, windows at %s (sill height %s)"
          % (S4_WALL_B[0], S4_WALL_B[1], S4_WALL_R, S4_WALL_WANDER, len(wall["cols"]),
             min(c["H"] for c in wall["cols"] if c["H"] > 0.0), max(c["H"] for c in wall["cols"]),
             ", ".join("%.1f" % rk["b"] for rk in rocks),
             ", ".join("%.1f" % w[0] for w in wall["windows"]), ", ".join("%.1f" % w[1] for w in wall["windows"])))
    for k, rk in enumerate(rocks):
        L = lay["lands"][k]
        u, v = _s4_local(rk, L)
        f = lay["pads"][k][3]
        E = S4_EDGE_Q

        def stand(p):
            uu, vv = _s4_local(rk, p)
            return max(_s4_q(rk, uu, vv), -uu / (S4_REAR / E), uu / (S4_FRONT / E)) <= E
        short = long_ = side = 0.0
        while stand((L[0] - (short + 0.05) * f[0], L[1] - (short + 0.05) * f[1])):
            short += 0.05
        while stand((L[0] + (long_ + 0.05) * f[0], L[1] + (long_ + 0.05) * f[1])):
            long_ += 0.05
        nrm = (-f[1], f[0])
        while stand((L[0] + (side + 0.05) * nrm[0], L[1] + (side + 0.05) * nrm[1])) \
                and stand((L[0] - (side + 0.05) * nrm[0], L[1] - (side + 0.05) * nrm[1])):
            side += 0.05
        # the whole landing flat and the pad, a 1.8 m body anywhere on it
        margin, worst = 9.0, None
        for iu in range(0, 19):
            for iv in range(0, 13):
                uu = -S4_REAR + (S4_REAR + S4_FRONT) * iu / 18.0
                vv = -S4_HALF_ACROSS + 3.2 * iv / 12.0
                x, y = _s4_world(rk, uu, vv)
                mg = _s4_block((x, y, rk["top"] + S4_BODY_H), eye)
                if mg < margin:
                    margin, worst = mg, (uu, vv)
        tallest = max(_s4_z(rk, uu / 4.0, vv / 4.0, noise=False)[0] - rk["top"]
                      for uu in range(-10, 9) for vv in range(-7, 7))
        print("MDL STATS s4 rock%d bearing=%.2f r=%.2f top=%.2f (+%.2f) axis_godot=(%.4f, 0, %.4f) "
              "landing local u=%.2f v=%.2f: %.2f m past the near edge, tolerance -%.2f/+%.2f m along, "
              "+-%.2f m across | nothing on it over %.2f m | landing+pad hidden from the guard by %.2f m "
              "at worst (local u=%.2f v=%.2f)"
              % (k + 1, rk["b"], rk["r"], rk["top"], rk["top"] - DECK_Z, rk["a"][0], -rk["a"][1],
                 u, v, u + S4_REAR, short, long_, side, tallest, margin, worst[0], worst[1]))
    # gaps between consecutive standing tops, along the flight lines
    def outline(rk):
        pts = []
        for k in range(120):
            th = TWO_PI * k / 120.0
            rr = S4_EDGE_Q * rk["R"](th)
            u, v = rr * math.cos(th), rr * math.sin(th)
            pts.append(_s4_world(rk, min(max(u, -S4_REAR), S4_FRONT), v))
        return pts

    def arc(bearing):
        return [pol(bearing, 46.7 + 10.6 * k / 30.0, 0.0)[:2] for k in range(31)]

    chains = [arc(lay["bank_entry"] + math.degrees(S4_EDGE_WANDER[1] / INNER_R))] \
        + [outline(rk) for rk in rocks] + [arc(lay["bank_exit"] - math.degrees(S4_EDGE_WANDER[1] / INNER_R))]
    gaps = []
    for k in range(len(chains) - 1):
        gaps.append(min(math.hypot(p[0] - q[0], p[1] - q[1]) for p in chains[k] for q in chains[k + 1]))
    heights = [DECK_Z] + [rk["top"] for rk in rocks] + [DECK_Z]
    for k, d in enumerate(gaps):
        drop = heights[k] - heights[k + 1]
        print("MDL STATS s4 gap%d=%.2f m (lava between standing tops) vs slide-jump reach %.2f m, run-jump %.2f m"
              % (k + 1, d, _s4_jump(-drop, S4_SLIDE), _s4_jump(-drop, S4_RUN)))
    print("MDL STATS s4 min_gap=%.2f m" % min(gaps))
    # the runner in the air: what fraction of each flight the body's centre
    # is behind rock, and the arc's clearance from the wall
    vy = S4_LAUNCH * math.sin(math.radians(S4_ANGLE))
    for k in range(len(lay["pads"])):
        O, L = lay["origins"][k], lay["lands"][k]
        f = lay["pads"][k][3]
        T = (vy + math.sqrt(vy * vy - 2.0 * S4_G * (L[2] - O[2]))) / S4_G
        vx = S4_LAUNCH * math.cos(math.radians(S4_ANGLE))
        hidden = 0
        clear = 99.0
        N = 40
        for i in range(N):
            t = T * (i + 0.5) / N
            x, y = O[0] + vx * t * f[0], O[1] + vx * t * f[1]
            z = O[2] + vy * t - 0.5 * S4_G * t * t
            if _s4_block((x, y, z + 0.9), eye) > 0.0:
                hidden += 1
            rad = math.hypot(x, y)
            bb = _bear_deg(math.atan2(y, x))
            for c in wall["cols"]:
                if abs(c["b"] - bb) < 2.0 and c["H"] > -0.3:
                    clear = min(clear, rad - (c["rc"] + c["W"]))
        print("MDL STATS s4 hop%d body hidden for %.0f%% of the %.2f s flight; arc clear of the wall by %.2f m"
              % (k + 1, 100.0 * hidden / N, T, clear))
    # trap volumes: bank to bank, feet only, boxes with overlap
    b0 = lay["bank_entry"] + math.degrees(S4_EDGE_WANDER[1] / S4_LANE_R)
    b1 = lay["bank_exit"] - math.degrees(S4_EDGE_WANDER[1] / S4_LANE_R)
    n = int(math.ceil((b1 - b0) / S4_TRAP_STEP))
    for k in range(n):
        a, b = b0 + (b1 - b0) * k / n, b0 + (b1 - b0) * (k + 1) / n
        bm = 0.5 * (a + b)
        w = 2.0 * OUTER_R * math.tan(math.radians(0.5 * (b - a))) + 0.6
        gx, gy, gz = godot(*pol(bm, 0.5 * (INNER_R + OUTER_R), LAVA_Z))
        sb, cb = math.sin(math.radians(bm)), math.cos(math.radians(bm))
        print("MDL STATS s4 trap%d bearings %.2f..%.2f Transform3D(%.6f, 0, %.6f, 0, 1, 0, %.6f, 0, %.6f, %.4f, %.2f, %.4f) "
              "size_metres=Vector3(%.2f, 0.4, %.2f) feet_only=true"
              % (k + 1, a, b, sb, cb, -cb, sb, gx, gy, gz, w, OUTER_R - INNER_R))

# -----------------------------------------------------------------------------
# the run down the pit wall: map_base's own wall faces, holed out, pushed back
# and re-laid in the river's material, with the rock rim banking down to them
# -----------------------------------------------------------------------------

def _pit_lava(m, wall, ta, tb, cut_a, cut_b, cols, rim, lines):
    """``ta``..``tb`` is the channel; ``cut_a``..``cut_b`` the wider span whose
    rim comes down to it. The fall runs on ``cols`` (the deck's columns); the
    sea's rim keeps ``rim`` and the sill zips the two. Returns the lava tris."""
    za = wall.ring_z[0]
    wall.hole(ta, tb, za, LAVA_Z)                  # the channel itself
    wall.hole(cut_a, cut_b, LAVA_Z, DECK_Z)        # the rim, down to the river
    rim_ts = _merge_cols(wall.tbreaks(ta, tb), [t for t in rim if ta < t < tb])
    ts = _merge_cols([ta, tb], [t for t in cols if ta < t < tb])
    zc = wall.zbreaks(za, LAVA_Z)                  # the pit wall's own rows
    zs = []
    for z0, z1 in zip(zc, zc[1:]):
        nv = _nv(z1 - z0, FALL_CAP)
        zs += [z0 + (z1 - z0) * k / nv for k in range(nv)]
    zs = sorted(zs + [LAVA_Z - d for d in LIP_ROWS] + [zc[-1]])
    row_of = {round(z, 6): BANK_WALL + BANK_DECK - 2 + k for k, z in enumerate(reversed(zs))}
    fine = []                                      # FALL_WAVE_ROW rows for the shader's
    for z0, z1 in zip(zs, zs[1:]):                 # ripple; banks keep the coarse rows' line
        nv = _nv(z1 - z0, FALL_WAVE_ROW)
        fine += [z0 + (z1 - z0) * k / nv for k in range(nv)]
    fine.append(zs[-1])
    coarse = zs

    def row_at(z):
        """Bank-line row of a fine row: linear between its two coarse rows."""
        for z0, z1 in zip(coarse, coarse[1:]):
            if z0 - 1e-9 <= z <= z1 + 1e-9:
                f = (z - z0) / (z1 - z0) if z1 > z0 else 0.0
                return row_of[round(z0, 6)] + (row_of[round(z1, 6)] - row_of[round(z0, 6)]) * f
        return row_of[round(z, 6)]

    def bank_da(line, side, i, rad):
        i0 = int(math.floor(i + 1e-9))
        f = i - i0
        a = _bank_da(line, side, i0, rad)
        return a if f < 1e-9 else a + (_bank_da(line, side, i0 + 1, rad) - a) * f

    zs = fine

    def rec(z):
        return max(_lip(LAVA_Z - z), RECESS_R * _ramp(LAVA_Z - z, 0.0, PIT_FADE))

    node = {}

    def N(t, z):
        """The fall's own vertex: the bank line's edge at this row, the
        columns between following it, all recessed rec(z)."""
        key = (round(t, 6), round(z, 6))
        if key not in node:
            i = row_at(z)
            rad = INNER_R
            if abs(t - ta) < 1e-9:
                da = bank_da(lines[0], 0, i, rad)
            elif abs(t - tb) < 1e-9:
                da = bank_da(lines[1], 1, i, rad)
            else:
                da = (bank_da(lines[0], 0, i, rad) * max(0.0, 1.0 - (t - ta) * rad / BANK_REACH)
                      + bank_da(lines[1], 1, i, rad) * max(0.0, 1.0 - (tb - t) * rad / BANK_REACH))
            node[key] = m.v(_push(wall.P(t + da, z), rec(z)))
        return node[key]

    tris = 0
    for i in range(len(ts) - 1):
        am = 0.5 * (ts[i] + ts[i + 1])
        want = (-math.cos(am), -math.sin(am), 0.0)
        for j in range(len(zs) - 1):
            m.quad(N(ts[i], zs[j]), N(ts[i + 1], zs[j]),
                   N(ts[i + 1], zs[j + 1]), N(ts[i], zs[j + 1]), want, ZONE_FALL, best=True)
            tris += 2
    for t, into in ((ta, 1.0), (tb, -1.0)):        # the two banks: each
        # faces along the channel, into the span ta..tb, not out of it
        want = (-math.sin(t) * into, math.cos(t) * into, 0.0)
        _strip(m, [(z, wall.W(t, z)) for z in zc], [(z, N(t, z)) for z in zs],
               want, ZONE_SHADE)
    _strip(m, [(t, wall.W(t, za)) for t in rim_ts], [(t, N(t, za)) for t in ts],
           UP, ZONE_SHADE)                         # the sill at the sea
    return tris, N


def _pit_bank_ends(m, wall, cut_a, cut_b, ta, tb, N):
    """The triangles that close the deck's sloped bank against the pit wall,
    where the rim steps from the deck down to the river's rounded lip."""
    for cut, t in ((cut_a, ta), (cut_b, tb)):
        want = (-math.cos(cut), -math.sin(cut), 0.0)   # a patch of the pit wall
        chain = [wall.W(cut, LAVA_Z), wall.W(t, LAVA_Z)]
        if N(t, LAVA_Z) != wall.W(t, LAVA_Z):
            chain.append(N(t, LAVA_Z))
        _fan_at(m, wall.W(cut, DECK_Z), chain, want, ZONE_SHADE)


# -----------------------------------------------------------------------------
# collision
# -----------------------------------------------------------------------------

def _in_platform(p, b, rad, sect):
    """True when a world point sits under a platform's top, in its own frame."""
    er, et = _radial(b), _tangent(b)
    base = pol(b, rad, 0.0)
    dx, dy = p[0] - base[0], p[1] - base[1]
    u = dx * er[0] + dy * er[1]
    v = dx * et[0] + dy * et[1]
    return (abs(u) <= max(abs(s[0]) for s in sect)
            and abs(v) <= max(abs(s[1]) for s in sect))


def _lake_collider(c, r):
    """What a body stands on: the river surface, flat, minus the platform
    footprints, then the platform tops and sides and the fins. Both walls keep
    the flat collision the rock had -- the TrapVolume owns the kill."""
    cols = [LAKE_A0 + 1.0 * k for k in range(int(LAKE_A1 - LAKE_A0) + 1)]
    plats = [(b, rad, LAKE_SECTS[k][0]) for k, (b, rad, _i) in enumerate(_platforms())]
    nr = len(LAVA_COLL_RST)
    grid = [[c.v(pol(b, rr, LAVA_Z)) for rr in LAVA_COLL_RST] for b in cols]
    for i in range(len(cols) - 1):
        for j in range(nr - 1):
            mid = pol(0.5 * (cols[i] + cols[i + 1]),
                      0.5 * (LAVA_COLL_RST[j] + LAVA_COLL_RST[j + 1]), 0.0)
            if any(_in_platform(mid, *p) for p in plats):
                continue
            c.quad(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1],
                   UP, ZONE_ROCK)
    for k, (b, rad, inner) in enumerate(_platforms()):
        sect, fs = LAKE_SECTS[k]
        _lake_column(c, b, rad, sect, [(22.20, 1.08), (PLAT_TOP_Z, 1.0)], r, ZONE_ROCK)
        if inner:
            _lake_column(c, b, FIN_R, fs, [(22.20, 1.16), (FIN_TOP_Z, 0.70)], r, ZONE_ROCK)


def _walk(r, n, lo, hi):
    """A seeded random walk held in runs: n values within lo..hi."""
    out, v = [], 0.5 * (lo + hi) if lo < 0.0 else lo
    while len(out) < n:
        step = BANK_STEP[0] + r.f() * (BANK_STEP[1] - BANK_STEP[0])
        if v + step > hi or (v - step >= lo and r.f() < 0.5):
            step = -step
        v = min(hi, max(lo, v + step))
        out += [v] * r.i(*BANK_RUN)
    return out[:n]


BANK_WALL, BANK_DECK, BANK_PIT = 9, 15, 40    # rows on the wall fall, deck stations, pit rows


def _bank_line(r):
    """ONE bank line per side: (deck-edge offset, lava-edge offset) in metres
    per row, from the shelf lip down the wall fall (rows 0..8, 8 = the foot),
    along the deck (8..22, 22 = the pit lip) and down the pit fall (22..)."""
    n = BANK_WALL + BANK_DECK + BANK_PIT
    edge = _walk(r, n, *BANK_EDGE)
    offs = _walk(r, n, *BANK_OFF)
    foot, lip = BANK_WALL - 1, BANK_WALL + BANK_DECK - 2
    out = []
    for i in range(n):
        k = min(_ramp(i, foot, foot + 2), _ramp(i, lip, lip - 2))   # only the deck's
        out.append((offs[i] * k, edge[i]))                         # own edge wanders
    return out


def _bank_da(line, side, i, rad):
    """Angular offset of a side's lava edge on row i, at radius rad."""
    return (line[i][1] / rad) * (1.0 if side == 0 else -1.0)


# -----------------------------------------------------------------------------
# S2, the Lava Shelf: a river along the deck between two wandering banks and
# a chain of rock masses standing in it
# -----------------------------------------------------------------------------

S2_KIND = ["deck"] * 4 + ["bank"] * 4 + ["floor"] * S2_FLOOR_N + ["bank"] * 3
S2_NST = len(S2_KIND) + 1             # stations, pit lip .. wall foot
S2_MASSES = []                        # what _s2_mass built, for the collider and the stats


def _s2_setup(T, base_cols):
    """The river's columns: the deck's own inside it, each lip snapped onto
    one when it is within COL_MERGE, the section's own columns between; and
    the chain, its gaps laid end to end from the near end bank's foot."""
    lips = []
    for b in (S2_A0, S2_A1):
        t = T(b)
        near = [c for c in base_cols if abs(c - t) * CROSS_R <= COL_MERGE]
        lips.append(near[0] if near else t)
    s1, s0 = lips
    a0, a1 = _bear_deg(s1), _bear_deg(s0)
    keep = [c for c in base_cols if s0 < c < s1] + [s0, s1]
    cols = [T(a0 + k * S2_STEP) for k in range(1, int((a1 - a0) / S2_STEP) + 1)]
    cols = [t for t in cols if s0 < t < s1
            and all(abs(t - k) * CROSS_R > COL_MERGE for k in keep)]
    k = 180.0 / (math.pi * S2_PLAT_R)
    rm = _Rng(S2_SEED + 1)
    plats, s = [], 0.0
    for (au, av, top, dr), gap in zip(S2_PLATS, S2_GAPS):
        sp = _s2_spec(rm, au, av, top)
        qe = _s2_edge_q(top, au)
        s += gap + qe * sp["R"](math.pi)
        sp.update(b=a0 + S2_END + s * k, rad=S2_PLAT_R + dr, qe=qe)
        s += qe * sp["R"](0.0)
        plats.append(sp)
    return {"a0": a0, "a1": a1, "s0": s0, "s1": s1, "cols": _merge_cols(cols, [s0, s1]),
            "plats": plats, "far_gap": (a1 - a0 - 2.0 * S2_END) / k - s, "T": T}


def _s2_lines(s2, cols_all):
    """The bank lines, per column in bearing order: inner deck-edge offset,
    inner bank width, outer ledge; and the floor's field."""
    span = [t for t in cols_all if s2["s0"] - 1e-9 <= t <= s2["s1"] + 1e-9]
    span.reverse()
    n = len(span)
    r = _Rng(S2_SEED)
    off, wid, led = _walk(r, n, *BANK_OFF), _walk(r, n, *S2_IN_W), _walk(r, n, *S2_OUT_LEDGE)
    s2["lines"] = {round(t, 7): (off[i], wid[i], led[i]) for i, t in enumerate(span)}
    s2["field"] = _field(_Rng(S2_SEED + 2), S2_FLOOR_AMP)
    s2["span"] = span


def _s2_f(s2, t):
    """0 on the lips, 1 in the river; the end banks round over between."""
    b = _bear_deg(t)
    s = min(1.0, max(0.0, min(b - s2["a0"], s2["a1"] - b) / S2_END))
    return 1.0 - (1.0 - s ** S2_END_P) ** (1.0 / S2_END_P)


def _s2_taper(s2, t, r_wall):
    """How far the inner bank swings out toward the wall at the river's ends."""
    b = _bear_deg(t)
    s = 1.0 - min(1.0, max(0.0, min(b - s2["a0"], s2["a1"] - b) / S2_TAPER))
    return s * s * (r_wall - S2_END_W - S2_IN_R)


def _s2_profile(s2, t, r_wall, field=True):
    """(radius, z) of stations 1..S2_NST-2 at column t: the lane, the inner
    bank, the floor, the outer bank. The lip and the wall foot are the deck's."""
    f = _s2_f(s2, t)
    off, wid, led = s2["lines"][round(t, 7)]
    drop = (DECK_Z - LAVA_Z) * f
    top_in = S2_IN_R + off + _s2_taper(s2, t, r_wall)
    foot_in, foot_out = top_in + wid, r_wall - led
    out = [(rr, DECK_Z) for rr in S2_LANE_R] + [(top_in, DECK_Z)]
    for fw, fd in S2_IN_LIP:
        out.append((top_in + fw * wid, DECK_Z - fd * drop))
    for k in range(S2_FLOOR_N + 1):
        rad = foot_in + (foot_out - foot_in) * k / float(S2_FLOOR_N)
        z = DECK_Z - drop
        if field and f > 1e-9:
            fade = _ramp(rad - foot_in, 0.0, S2_FLOOR_FADE) * _ramp(foot_out - rad, 0.0, S2_FLOOR_FADE)
            z += f * fade * s2["field"](rad * math.cos(t), rad * math.sin(t))
        out.append((rad, z))
    for fw, fd in S2_OUT_LIP:
        out.append((foot_out + fw * led, DECK_Z - drop * (1.0 - fd)))
    return out


def _s2_zone(j, f0, f1):
    kind = S2_KIND[j]
    if kind == "floor" and min(f0, f1) > 1.0 - 1e-6:
        return ZONE_RIVER_T
    if kind != "deck" and max(f0, f1) > 1e-9:
        return ZONE_SHADE
    return ZONE_DECK


def _s2_frame(b, rad):
    er, et = _radial(b), _tangent(b)
    base = pol(b, rad, 0.0)

    def P(u, v, z):
        return (base[0] + et[0] * u + er[0] * v, base[1] + et[1] * u + er[1] * v, z)
    return P


def _s2_spec(r, au, av, top):
    """One boulder's own numbers: its waterline R(theta) and noise."""
    p1, p2 = r.f() * TWO_PI, r.f() * TWO_PI
    jit = [r.sf() * 0.02 for _ in range(S2_MASS_N)]
    ang = [TWO_PI * (i + 0.5 + 0.25 * r.sf()) / S2_MASS_N for i in range(S2_MASS_N)]

    def R(th):
        c, s = abs(math.cos(th)), abs(math.sin(th))
        rr = 1.0 / ((c / au) ** S2_MASS_P + (s / av) ** S2_MASS_P) ** (1.0 / S2_MASS_P)
        return rr * (1.0 + S2_WOB * (0.6 * math.sin(2.0 * th + p1) + 0.4 * math.sin(3.0 * th + p2)))
    return {"au": au, "av": av, "top": top, "R": R, "ang": ang, "jit": jit,
            "noise": _field(_Rng(r.n()), S2_NOISE, 5, S2_NOISE_L)}


def _s2_edge_q(top, a):
    """Where the shoulder's pitch along the run reaches 45 deg: the standing edge."""
    drop = top - (LAVA_Z - S2_WATER_D)
    s = min(1.0, (1.0 - S2_FLAT_Q) * a / (drop * 0.5 * math.pi))
    return S2_FLAT_Q + (1.0 - S2_FLAT_Q) * math.asin(s) / math.pi


def _s2_z(sp, u, v, q):
    """(z, landing) of a boulder at local (u, v), q of the waterline out."""
    top = sp["top"]
    water = LAVA_Z - S2_WATER_D
    if q <= S2_FLAT_Q:
        zs = top
    elif q <= 1.0:
        t = (q - S2_FLAT_Q) / (1.0 - S2_FLAT_Q)
        zs = top - (top - water) * math.sin(0.5 * math.pi * t) ** 2
    else:
        zs = water - (q - 1.0) / (S2_MASS_Q[-1] - 1.0) * (S2_BOTTOM_D - S2_WATER_D)
    land = _ramp(S2_FLAT_Q - q, 0.0, 0.08)
    return zs + (1.0 - land) * sp["noise"](u, v), land


def _s2_local(sp, p):
    """A world point in a boulder's frame: (u along, v across, q of the waterline)."""
    er, et = _radial(sp["b"]), _tangent(sp["b"])
    base = pol(sp["b"], sp["rad"], 0.0)
    dx, dy = p[0] - base[0], p[1] - base[1]
    u, v = dx * et[0] + dy * et[1], dx * er[0] + dy * er[1]
    return u, v, math.hypot(u, v) / sp["R"](math.atan2(v, u))


def _s2_mass(m, sp):
    """One boulder in the river, a closed heightfield: a centre, rings out to
    a bottom ring under the lava, all one surface -- landing, shoulders and
    stem are the same rock. The collider gets the identical mesh."""
    P = _s2_frame(sp["b"], sp["rad"])
    R, ang, jit = sp["R"], sp["ang"], sp["jit"]
    zc, _l = _s2_z(sp, 0.0, 0.0, 0.0)
    centre = m.v(P(0.0, 0.0, zc))
    rings, info = [], []
    for q in S2_MASS_Q:
        ids, row = [], []
        for th, j in zip(ang, jit):
            rr = q * R(th) * (1.0 + j)
            u, v = rr * math.cos(th), rr * math.sin(th)
            z, land = _s2_z(sp, u, v, q)
            ids.append(m.v(P(u, v, z)))
            row.append((z, land))
        rings.append(ids)
        info.append(row)

    def zone(z, land):
        if z < LAVA_Z:
            return ZONE_EMBER
        return ZONE_DECK if land > 0.5 else ZONE_SHADE
    n = S2_MASS_N
    for i in range(n):
        j = (i + 1) % n
        m.tri(centre, rings[0][i], rings[0][j], UP, zone(zc, 1.0))
    for a in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            zm = 0.25 * (info[a][i][0] + info[a][j][0] + info[a + 1][i][0] + info[a + 1][j][0])
            lm = 0.25 * (info[a][i][1] + info[a][j][1] + info[a + 1][i][1] + info[a + 1][j][1])
            m.quad(rings[a][i], rings[a][j], rings[a + 1][j], rings[a + 1][i], UP, zone(zm, lm),
                   best=True)
    m.fan(rings[-1], DOWN, ZONE_EMBER)


def _s2_build(m, s2, r):
    for sp in s2["plats"]:
        _s2_mass(m, sp)
    S2_MASSES[:] = s2["plats"]
    S2_INFO.update(a0=s2["a0"], a1=s2["a1"], masses=S2_MASSES)


def _s2_wall_spec():
    """The cave wall's columns: per bearing, crest radius, half width,
    height over the lava. Windows over three gaps, up to the ceiling in
    front of two landings, sunk into the lava at both ends."""
    if "wall" in S2_INFO:
        return S2_INFO["wall"]
    r = _Rng(S2_SEED + 21)
    p1, p2, p3 = r.f() * TWO_PI, r.f() * TWO_PI, r.f() * TWO_PI
    b0, b1 = S2_INFO["a0"] + S2_WALL_IN, S2_INFO["a1"] - S2_WALL_IN
    k = 180.0 / (math.pi * S2_PLAT_R)
    plats = S2_INFO["masses"]
    ends = [S2_INFO["a0"] + S2_END] + [None] * len(plats) + [S2_INFO["a1"] - S2_END]
    windows = []
    for g, sill in zip(S2_WALL_WINDOW_AT, S2_WALL_WINDOW):
        lo = ends[0] if g == 0 else plats[g - 1]["b"] + plats[g - 1]["qe"] * plats[g - 1]["R"](0.0) * k
        hi = ends[-1] if g == len(plats) else plats[g]["b"] - plats[g]["qe"] * plats[g]["R"](math.pi) * k
        windows.append((0.5 * (lo + hi), sill))
    joins = [plats[i]["b"] for i in S2_WALL_JOIN_AT]
    n = int(round((b1 - b0) / S2_WALL_STEP))
    cols = []
    for i in range(n + 1):
        bb = b0 + (b1 - b0) * i / n
        s_m = math.radians(bb) * S2_WALL_R
        rc = S2_WALL_R + S2_WALL_WANDER * (0.6 * math.sin(0.61 * s_m + p1) + 0.4 * math.sin(1.37 * s_m + p2))
        W = S2_WALL_W[0] + 0.5 * (S2_WALL_W[1] - S2_WALL_W[0]) * (1.0 + math.sin(0.83 * s_m + p3))
        H = S2_WALL_H[0] + 0.5 * (S2_WALL_H[1] - S2_WALL_H[0]) * (1.0 + 0.7 * math.sin(0.9 * s_m + p2)
                                                                  + 0.3 * math.sin(2.3 * s_m + p1))
        H += S2_WALL_CRAG * (r.sf() + 0.5 * math.sin(4.1 * s_m + p3))
        for jb in joins:
            d = abs(bb - jb) / k
            if d < S2_WALL_JOIN_W:
                H += (S2_WALL_JOIN - H) * _smooth((S2_WALL_JOIN_W - d) / 1.5)
        for wb, sill in windows:
            d = abs(bb - wb) / k
            if d < S2_WALL_WINDOW_W:
                H += (sill - H) * _smooth((S2_WALL_WINDOW_W - d) / 1.0)
        for eb, sgn in ((b0, 1.0), (b1, -1.0)):
            d = (bb - eb) * sgn / k
            if d < S2_WALL_END:
                H += (-0.6 - H) * (1.0 - _smooth(d / S2_WALL_END))
        cols.append({"b": bb, "rc": rc, "W": W, "H": H})
    S2_INFO["wall"] = {"cols": cols, "windows": windows, "joins": joins,
                       "noise": _field(_Rng(S2_SEED + 22), S2_NOISE, 5, S2_NOISE_L)}
    return S2_INFO["wall"]


def _s2_wall_col(bb):
    """(rc, W, H) of the wall at a bearing, or None off its run."""
    cols = _s2_wall_spec()["cols"]
    if bb < cols[0]["b"] or bb > cols[-1]["b"]:
        return None
    fi = (bb - cols[0]["b"]) / (cols[-1]["b"] - cols[0]["b"]) * (len(cols) - 1)
    i = min(len(cols) - 2, int(fi))
    t = fi - i
    c0, c1 = cols[i], cols[i + 1]
    return tuple(c0[key] + (c1[key] - c0[key]) * t for key in ("rc", "W", "H"))


def _s2_wall_z(x, y, noise=True):
    """The wall's surface height at world x-y, or None off its footprint."""
    col = _s2_wall_col(_bear_deg(math.atan2(y, x)))
    if col is None:
        return None
    rc, W, H = col
    d = (math.hypot(x, y) - rc) / W
    if abs(d) > 1.0:
        return None
    z = LAVA_Z - S2_WALL_SINK + (H + S2_WALL_SINK) * _s4_wall_prof(d)
    if noise:
        z += S2_INFO["wall"]["noise"](x, y) * (1.0 - abs(d) ** 4)
    return z


def _s2_wall(m, coll=False):
    """The wall as one closed strip, S4's way: rows across the ridge from the
    outer foot (in the lava) over the crest to the inner foot (in the deck)."""
    wall = _s2_wall_spec()
    cols = wall["cols"]
    D = S4_WALL_ROWS
    rows = []
    for c in cols:
        row = []
        for d in D:
            p = pol(c["b"], c["rc"] + d * c["W"], 0.0)
            z = LAVA_Z - S2_WALL_SINK + (c["H"] + S2_WALL_SINK) * _s4_wall_prof(d)
            if not coll:
                z += wall["noise"](p[0], p[1]) * (1.0 - abs(d) ** 4)
            row.append(m.v((p[0], p[1], z)))
        bot = [m.v(pol(c["b"], c["rc"] + d * c["W"], LAVA_Z - S2_WALL_SINK - 0.5)) for d in (-1.0, 1.0)]
        rows.append(row + bot)
    nd = len(D)
    for i in range(len(rows) - 1):
        A, B = rows[i], rows[i + 1]
        for j in range(nd - 1):
            zm = 0.25 * sum(m.verts[v][2] for v in (A[j], A[j + 1], B[j], B[j + 1]))
            zone = ZONE_ROCK if coll else (ZONE_EMBER if zm < LAVA_Z else ZONE_SHADE)
            m.quad(A[j], A[j + 1], B[j + 1], B[j], UP, zone, best=True)
        er = _radial(0.5 * (cols[i]["b"] + cols[i + 1]["b"]))
        m.quad(A[0], B[0], B[nd], A[nd], (-er[0], -er[1], 0.0), ZONE_EMBER)
        m.quad(A[nd - 1], B[nd - 1], B[nd + 1], A[nd + 1], er, ZONE_EMBER)
        m.quad(A[nd], B[nd], B[nd + 1], A[nd + 1], DOWN, ZONE_EMBER)
    for i, sgn in ((0, -1.0), (len(rows) - 1, 1.0)):
        row = rows[i]
        et = _tangent(cols[i]["b"])
        m.fan(row[:nd] + [row[nd + 1], row[nd]], (et[0] * sgn, et[1] * sgn, 0.0), ZONE_EMBER)


def _s2_block(target, eye):
    """How far under rock the sight line from the eye to the target passes:
    max over the line of (surface - line) over the wall and the boulders;
    <= 0 means the target is in view."""
    best = -9.0
    for k in range(1, S2_SIGHT_N):
        f = k / float(S2_SIGHT_N)
        p = (eye[0] + (target[0] - eye[0]) * f, eye[1] + (target[1] - eye[1]) * f,
             eye[2] + (target[2] - eye[2]) * f)
        zw = _s2_wall_z(p[0], p[1], noise=False)
        if zw is not None:
            best = max(best, zw - p[2])
        for sp in S2_MASSES:
            u, v, q = _s2_local(sp, p)
            if q < 1.0:
                best = max(best, _s2_z(sp, u, v, q)[0] - p[2])
    return best


def _s2_collider(c, s2, ang, lip, foot, CV):
    """The river's collision on the same bank lines: lane, inner bank, floor
    flat at the lava, outer bank; then the boulders and the wall."""
    keep = (2, 3, 5, 7, 10, 13, 14)          # lane end, bank top, mid, foot, floor, foot, mid
    grid = []
    for t in s2["span"]:
        wf = CV("out", foot, t)
        prof = _s2_profile(s2, t, math.hypot(*c.verts[wf][:2]), field=False)
        ids = [CV("lip%.2f" % DECK_Z, lip, t)]
        ids += [c.v((rr * math.cos(t), rr * math.sin(t), z)) for rr, z in (prof[j] for j in keep)]
        ids.append(wf)
        grid.append(ids)
    for a, b in zip(grid, grid[1:]):
        for j in range(len(a) - 1):
            c.quad(a[j], b[j], b[j + 1], a[j + 1], UP, ZONE_ROCK)
    for sp in S2_MASSES:
        _s2_mass(c, sp)
    c.span("cover_s2", _s2_wall, coll=True)


def _s2_stats(s2):
    """The chain as built: gaps between standing edges (the 45-degree line on
    the shoulders); from the guard's eye, how deep under rock each landing
    and each jump sit, and that the lane is in plain view."""
    eye = (0.0, 0.0, 27.0)
    wall = _s2_wall_spec()
    edges = []
    for sp in S2_MASSES:
        P = _s2_frame(sp["b"], sp["rad"])
        edges.append([P(sp["qe"] * sp["R"](th) * math.cos(th), sp["qe"] * sp["R"](th) * math.sin(th), sp["top"])
                      for th in sp["ang"]])
    ends = (pol(s2["a0"] + S2_END, S2_PLAT_R, DECK_Z), pol(s2["a1"] - S2_END, S2_PLAT_R, DECK_Z))
    chain = [[ends[0]]] + edges + [[ends[1]]]
    pairs = [min(((p, q) for p in a for q in b), key=lambda pq: math.dist(pq[0][:2], pq[1][:2]))
             for a, b in zip(chain, chain[1:])]
    gaps = [math.dist(p[:2], q[:2]) for p, q in pairs]
    live = [c["H"] for c in wall["cols"] if c["H"] > 0.0 and c["H"] < S2_WALL_JOIN - 1.0]
    print("MDL STATS s2 river=%.2f..%.2f deg lava_y=%.2f boulders=%d far_gap=%.2f cols=%d | wall %.1f..%.1f deg r=%.1f+-%.1f "
          "%d cols, height over lava %.1f..%.1f m, into the ceiling at %s, windows at %s (sills %s), inner foot r>=%.2f "
          "(lane %.1f m wide)"
          % (s2["a0"], s2["a1"], LAVA_Z, len(S2_MASSES), s2["far_gap"], len(s2["span"]),
             wall["cols"][0]["b"], wall["cols"][-1]["b"], S2_WALL_R, S2_WALL_WANDER, len(wall["cols"]),
             min(live), max(live), ", ".join("%.1f" % b for b in wall["joins"]),
             ", ".join("%.1f" % w[0] for w in wall["windows"]), ", ".join("%.1f" % w[1] for w in wall["windows"]),
             min(c["rc"] - c["W"] for c in wall["cols"]), min(c["rc"] - c["W"] for c in wall["cols"]) - INNER_R))
    for k, sp in enumerate(S2_MASSES):
        au, av, top = sp["au"], sp["av"], sp["top"]
        P = _s2_frame(sp["b"], sp["rad"])
        margin, tallest, lava = 9.0, 0.0, 9.0
        for iu in range(-8, 9):
            for iv in range(-8, 9):
                u, v = S2_FLAT_Q * au * iu / 8.0, S2_FLAT_Q * av * iv / 8.0
                th = math.atan2(v, u)
                if math.hypot(u, v) > S2_FLAT_Q * sp["R"](th):
                    continue
                x, y, _z = P(u, v, 0.0)
                margin = min(margin, _s2_block((x, y, top + 1.8), eye))
                tallest = max(tallest, _s2_z(sp, u, v, math.hypot(u, v) / sp["R"](th))[0] - top)
        for th in sp["ang"]:
            x, y, _z = P(sp["R"](th) * math.cos(th), sp["R"](th) * math.sin(th), 0.0)
            col = _s2_wall_col(_bear_deg(math.atan2(y, x)))
            if col:
                lava = min(lava, math.hypot(x, y) - (col[0] + col[1]))
        print("MDL STATS s2boulder%d bearing=%.2f r=%.2f top=%.2f water=%.1fx%.1f stand=%.1f flat=%.1fx%.1f "
              "gap_before=%.2f gap_after=%.2f | nothing on the landing over %.2f m | 1.8 m body anywhere on it "
              "hidden from the guard by %.2f m at worst | lava between the wall's foot and the waterline %.2f m"
              % (k + 1, sp["b"], sp["rad"], top, 2 * au, 2 * av, 2 * sp["qe"] * au, 2 * S2_FLAT_Q * au,
                 2 * S2_FLAT_Q * av, gaps[k], gaps[k + 1], tallest, margin, lava))
    for k, (p, q) in enumerate(pairs):
        f = ((q[0] - p[0]) / gaps[k], (q[1] - p[1]) / gaps[k])
        h = q[2] - p[2]
        T = (7.0 + math.sqrt(max(0.0, 49.0 - 2.0 * 22.0 * h))) / 22.0
        hidden, N = 0, 40
        for i in range(N):
            t = T * (i + 0.5) / N
            x, y = p[0] + 11.0 * t * f[0], p[1] + 11.0 * t * f[1]
            z = p[2] + 7.0 * t - 11.0 * t * t
            if _s2_block((x, y, z + 0.9), eye) > 0.0:
                hidden += 1
        print("MDL STATS s2gap%d=%.2f m rise=%+.2f flight=%.2f s (run-jump reach %.2f m) body hidden for %.0f%% of it"
              % (k + 1, gaps[k], h, T, 11.0 * T, 100.0 * hidden / N))
    worst, at = -99.0, None
    for ib in range(int(s2["a1"] - s2["a0"]) + 1):
        for rr in (46.9, 47.6, 48.3, 49.0, 49.5):
            p = pol(s2["a0"] + ib, rr, DECK_Z + 0.05)
            bl = _s2_block(p, eye)
            if bl > worst:
                worst, at = bl, (s2["a0"] + ib, rr)
    print("MDL STATS s2 lane r 46.9..49.5 every degree: deepest anything sits under rock on the line "
          "from the guard's eye to a lane point's feet = %.2f m (at %.1f deg r %.1f); <= 0 is plain view" % (worst, at[0], at[1]))
    for k in range(S2_TRAP_N):
        b = s2["a0"] + (k + 0.5) * (s2["a1"] - s2["a0"]) / S2_TRAP_N
        along = 2.0 * S2_TRAP_R[1] * math.sin(math.radians(0.5 * (s2["a1"] - s2["a0"]) / S2_TRAP_N)) + 0.2
        rm = 0.5 * (S2_TRAP_R[0] + S2_TRAP_R[1])
        sb, cb = math.sin(math.radians(b)), math.cos(math.radians(b))
        print("MDL STATS s2trap%d transform=Transform3D(%.6f, 0, %.6f, 0, 1, 0, %.6f, 0, %.6f, %.4f, %.2f, %.4f) size=Vector3(%.2f, 0.4, %.2f)"
              % (k + 1, sb, cb, -cb, sb, rm * cb, LAVA_Z, rm * sb, along, S2_TRAP_R[1] - S2_TRAP_R[0]))


# -----------------------------------------------------------------------------
# S3, the Demon Pad Grid: a flat deck filled with pads, one path cut through
# the grid, three pads in the path that must be jumped, one half wall of rock
# at the pit edge. One layout, in the grid frame, read by the mesh, the
# collider, the scene's pad nodes and the proofs.
# -----------------------------------------------------------------------------

def _s3_arc(b_deg):
    """Arc metres at the lane for a bearing: the along axis of the grid frame."""
    return math.radians(b_deg) * S3_LANE_R


def _s3_seg_dist(u, r, a, b):
    """Distance from (u, r) to the segment a-b, all in (arc, station) metres."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    L2 = dx * dx + dy * dy
    s = 0.0 if L2 < EPS else max(0.0, min(1.0, ((u - a[0]) * dx + (r - a[1]) * dy) / L2))
    return math.hypot(u - a[0] - s * dx, r - a[1] - s * dy)


def _s3_lattice(lo, hi, step, exact, merge):
    """lo..hi every `step`, the `exact` values in, any lattice value within
    `merge` of an exact one dropped; lo and hi always survive."""
    out = [v for v in exact if lo < v < hi]
    k = 1
    while lo + k * step < hi - merge:
        v = lo + k * step
        if all(abs(v - e) > merge for e in out):
            out.append(v)
        k += 1
    return sorted(set(out + [lo, hi]))




# ---- the cracks: ONE network across the deck. Ryan: "instead of a demon pad,
# either create an element, or hard model into the map, cracks that have like,
# wavy hotness coming out of them ... make it look like theres lava under the
# cracks" and then "can you make them tile so that they look like one thing
# instead?" So the 36 pad cells are not 36 fissures: a seeded spanning tree of
# the cell grid (every pad cell, never a path cell) picks which neighbours
# join, each joined pair shares one PORT on its common cell edge -- one
# cross-section of six vertices both cells' fissures end on -- and inside a
# cell one main fissure runs port to port with the other ports and a splinter
# or two branching off it through T-mouths that reuse the main's own side
# vertices. One tree, one island, one outline: the deck round it is one
# polygon with one hole, welded on the grid's own vertices.
S3_CRACK_W = (0.09, 0.22)             # a fissure's half width at the deck, interior stations:
                                      # never a hairline, so it reads from the tower
S3_CRACK_D = (0.14, 0.26)             # ... and its floor depth, wider is deeper
S3_CRACK_PORT_W = (0.12, 0.22)        # half width where two cells' fissures meet
S3_CRACK_PORT_D = (0.12, 0.18)
S3_CRACK_INSET = 0.18                 # interior stations keep this far inside the cell's edges
S3_CRACK_WALL_CLEAR = 0.40            # ... and this far out from the lip wall's foot line: the deck
                                      # patch round the cracks starts at the foot, never inside
                                      # the wall (a patch boundary up on the wall's plateau once
                                      # spanned fill triangles from the crest down to the cracks:
                                      # the "rock spilling onto the floor" Ryan saw)
S3_CRACK_PORT_IN = (0.30, 0.55)       # the first station in from a port, metres straight in
S3_CRACK_STEP = (0.20, 0.45)          # metres between stations along a fissure
S3_CRACK_KICK = (0.10, 0.40)          # lateral jag of an interior station off the line
S3_CRACK_ANGLE = 60.0                 # no station sharper than this
S3_CRACK_MOUTH = (0.18, 0.60)         # a host segment this long may take a branch
S3_CRACK_GAP = 0.08                   # fissures that do not join keep this apart
S3_CRACK_SPLINTER = (0.35, 1.25)      # a dead-end splinter's reach off its host
S3_CRACK_BRIDGES = (2, 4)             # fissures a cell runs from one fissure to another, so the
                                      # crust breaks into plates with lava all round them
S3_CRACK_BRIDGE_L = (0.6, 1.7)        # ... between mouths this far apart
S3_CRACK_REFINE = 1.2                 # no deck triangle round the cracks keeps an edge longer
                                      # than this: a long facet drops its texel density
S3_CRACK_TRIES = 80                   # draws per cell before the build gives up
S3_CRACK_PER_CELL = (14, 18)          # fissures a cell is crazed with: main, port branches,
                                      # then dead-end splinters off any of them ...
S3_CRACK_DEPTH_MAX = 3                # ... splinters off splinters, this deep


def _s3n_u(v):
    L = math.hypot(v[0], v[1]) or 1.0
    return (v[0] / L, v[1] / L)


def _s3n_perp(v):
    return (-v[1], v[0])


def _s3n_add(a, b, s=1.0):
    return (a[0] + s * b[0], a[1] + s * b[1])


def _s3n_dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def _s3n_cross(a, b):
    return a[0] * b[1] - a[1] * b[0]


def _s3n_dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _s3n_pt_seg(x, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    dd = dx * dx + dy * dy
    if dd <= 1e-12:
        return _s3n_dist(x, a)
    t = max(0.0, min(1.0, ((x[0] - a[0]) * dx + (x[1] - a[1]) * dy) / dd))
    return math.hypot(x[0] - (a[0] + t * dx), x[1] - (a[1] + t * dy))


def _s3n_angle(c, i):
    """Degrees at c[i] between c[i-1] and c[i+1]; 180 is straight."""
    ux, uy = c[i - 1][0] - c[i][0], c[i - 1][1] - c[i][1]
    vx, vy = c[i + 1][0] - c[i][0], c[i + 1][1] - c[i][1]
    return math.degrees(math.atan2(abs(ux * vy - uy * vx), ux * vx + uy * vy))


def _s3n_outline(f):
    """A fissure's top outline as plan points: left side forward, right side
    back. Ends: a tip is one point, a port is p +- n w, a mouth is the two
    host vertices it takes (their positions are recorded on the fissure)."""
    pts, w, nrm = f["pts"], f["w"], f["nrm"]
    n = len(pts)
    left, right = [], []
    for i in range(n):
        if i == 0 and f["e0"][0] == "mouth":
            left.append(f["mouth0"][0])
            right.append(f["mouth0"][1])
        elif i == n - 1 and f["e1"][0] == "mouth":
            left.append(f["mouth1"][0])
            right.append(f["mouth1"][1])
        else:
            left.append(_s3n_add(pts[i], nrm[i], w[i]))
            right.append(_s3n_add(pts[i], nrm[i], -w[i]))
    ring = []
    for q in left + list(reversed(right)):
        if not ring or _s3n_dist(ring[-1], q) > 1e-9:
            ring.append(q)
    if len(ring) > 1 and _s3n_dist(ring[0], ring[-1]) <= 1e-9:
        ring.pop()
    return ring


def _s3n_normals(f, ports):
    """Per-station normals (the fissure's LEFT), a port station's forced to
    the port's cross-section line, signed to the fissure's left."""
    pts = f["pts"]
    n = len(pts)
    out = []
    for i in range(n):
        p, q = pts[max(0, i - 1)], pts[min(n - 1, i + 1)]
        left = _s3n_perp(_s3n_u((q[0] - p[0], q[1] - p[1])))
        end = f["e0"] if i == 0 else (f["e1"] if i == n - 1 else None)
        if end is not None and end[0] == "port":
            pn = ports[end[1]]["n"]
            left = pn if _s3n_dot(left, pn) >= 0.0 else (-pn[0], -pn[1])
        out.append(left)
    f["nrm"] = out
    return out


def _s3n_chain(rng, p0, d0, p1, d1, inside, back0=0.0, back1=0.0):
    """A jagged polyline from p0 to p1. d0: the direction it must leave p0
    along (None: free); d1: the direction it must arrive at p1 along (None:
    free); back0/back1: extra metres the first/last interior station stands
    off its end (a host's half width, when the end is a mouth on it).
    Interior stations inside(). None when no draw fits."""
    for _ in range(12):
        c = [p0]
        if d0 is not None:
            k = back0 + S3_CRACK_PORT_IN[0] + rng.f() * (S3_CRACK_PORT_IN[1] - S3_CRACK_PORT_IN[0])
            side = _s3n_perp(d0)
            c.append(_s3n_add(_s3n_add(p0, d0, k), side, rng.sf() * 0.12))
        last = None
        if d1 is not None:
            k = back1 + S3_CRACK_PORT_IN[0] + rng.f() * (S3_CRACK_PORT_IN[1] - S3_CRACK_PORT_IN[0])
            side = _s3n_perp(d1)
            last = _s3n_add(_s3n_add(p1, d1, -k), side, rng.sf() * 0.12)
        a = c[-1]
        b = last if last is not None else p1
        L = _s3n_dist(a, b)
        along = _s3n_u((b[0] - a[0], b[1] - a[1]))
        side = _s3n_perp(along)
        nmid = max(0, int(L / (0.5 * (S3_CRACK_STEP[0] + S3_CRACK_STEP[1])) + rng.f() - 0.3))
        if last is None and d0 is None:
            nmid = max(nmid, 3)
        fr = sorted(0.12 + 0.76 * rng.f() for _ in range(nmid))
        for t in fr:
            kick = S3_CRACK_KICK[0] + rng.f() * (S3_CRACK_KICK[1] - S3_CRACK_KICK[0])
            kick *= 1.0 if rng.f() < 0.5 else -1.0
            if rng.f() < 0.25:
                kick *= 0.15                     # a near-straight station now and then
            c.append(_s3n_add(_s3n_add(a, along, t * L), side, kick))
        if last is not None:
            c.append(last)
        c.append(p1)
        ok = len(c) >= 3
        for i in range(1, len(c) - 1):
            if not inside(c[i]) or _s3n_angle(c, i) < S3_CRACK_ANGLE:
                ok = False
                break
        for i in range(len(c) - 1):
            if _s3n_dist(c[i], c[i + 1]) < 0.15:
                ok = False
        if ok:
            return c
    return None


def _s3n_widths(rng, f, ports):
    """Half widths and depths per station: ports theirs, tips nought, one
    waist somewhere along, the rest irregular; a mouth end's are the host's."""
    pts = f["pts"]
    n = len(pts)
    w, d = [0.0] * n, [0.0] * n
    inner = [i for i in range(n) if 0 < i < n - 1]
    waist = rng.pick(inner) if len(inner) > 2 else -1
    lo, hi = S3_CRACK_W
    cap = f.get("wcap", hi)
    for i in inner:
        if i == waist:
            w[i] = lo + rng.f() * 0.02
        else:
            w[i] = min(cap, lo + 0.03 + rng.f() * (hi - lo - 0.03))
        t = (w[i] - lo) / (hi - lo)
        d[i] = S3_CRACK_D[0] + (S3_CRACK_D[1] - S3_CRACK_D[0]) * t * (0.8 + 0.3 * rng.f())
        d[i] = max(S3_CRACK_D[0], min(S3_CRACK_D[1], d[i]))
    for i, end in ((0, f["e0"]), (n - 1, f["e1"])):
        if end[0] == "port":
            w[i], d[i] = ports[end[1]]["w"], ports[end[1]]["d"]
        elif end[0] == "mouth":
            w[i], d[i] = 0.0, 0.0                  # unused: the host's vertices
    f["w"], f["d"] = w, d


def _s3n_mouth_pts(host, k, side):
    """The two host top vertices a branch takes on host segment k: (the
    branch's left end, its right end), per the outline walk's rule."""
    o = host["nrm"]
    pts, w = host["pts"], host["w"]
    L = [_s3n_add(pts[i], o[i], w[i]) for i in (k, k + 1)]
    R = [_s3n_add(pts[i], o[i], -w[i]) for i in (k, k + 1)]
    if side > 0:                                   # enters the host's left side
        return L[1], L[0]
    return R[0], R[1]


def _s3n_fits(new, ring, made, rings, in_box, ports, base):
    """Whether a freshly drawn fissure may join the cell: its outline simple
    and inside the inset box (a port's own two vertices may sit on the
    edge), clear of every other fissure by S3_CRACK_GAP, and against its
    host touching only at the two mouth vertices it shares."""
    if not _s3c_simple(ring):
        return False
    pks = [e[1] for e in (new["e0"], new["e1"]) if e[0] == "port"]
    for q in ring:
        if not in_box(q, S3_CRACK_INSET - 0.06):
            if not any(_s3n_dist(q, ports[pk]["p"]) <= ports[pk]["w"] + 1e-6 for pk in pks):
                return False
    hosts = {}
    for end, key in ((new["e0"], "mouth0"), (new["e1"], "mouth1")):
        if end[0] == "mouth":
            hosts[end[1] - base] = new[key]              # global index -> this cell's
    shared_pts = [q for mm in hosts.values() for q in mm]
    for hi, (f, r) in enumerate(zip(made, rings)):
        if hi in hosts:
            if not _s3n_ring_clear(ring, r, shared_pts, 0.06):
                return False
        else:
            # a sibling on the next segment of the same host shares a vertex
            common = [q for q in ring if any(_s3n_dist(q, x) < 1e-9 for x in r)]
            if common:
                if not _s3n_ring_clear(ring, r, common, 0.06):
                    return False
            elif _s3c_poly_gap(ring, r) < S3_CRACK_GAP:
                return False
    return True


def _s3n_ring_clear(ring, other, shared, dmin):
    """Two outlines that meet only at `shared` vertices: every other point
    of `ring` keeps dmin from `other`, and no edge of one crosses or touches
    an edge of the other unless they share an endpoint."""
    no = len(other)
    for q in ring:
        if any(_s3n_dist(q, x) < 1e-9 for x in shared):
            continue
        if min(_s3n_pt_seg(q, other[i], other[(i + 1) % no]) for i in range(no)) < dmin:
            return False
    nb = len(ring)
    for i in range(nb):
        pa, pb = ring[i], ring[(i + 1) % nb]
        for j in range(no):
            pc, pd = other[j], other[(j + 1) % no]
            if any(_s3n_dist(x, y) < 1e-9 for x in (pa, pb) for y in (pc, pd)):
                continue
            if _s3c_seg_gap(pa, pb, pc, pd) < 0.02:
                return False
    return True


def _s3n_mouth_on(rng, host, target, want_side, used):
    """A segment of `host` that may take a mouth: 1..n-3 (never a segment on
    an end station), S3_CRACK_MOUTH long, not already used on that side nor
    next to a used one. With a target: the nearest such segment on the
    target's side, at least 0.45 m off; without: a random one."""
    pts = host["pts"]
    n = len(pts)
    cands = []
    for k in range(1, n - 2):
        seg = _s3n_dist(pts[k], pts[k + 1])
        if not (S3_CRACK_MOUTH[0] <= seg <= S3_CRACK_MOUTH[1]):
            continue
        mid = _s3n_add(pts[k], pts[k + 1])
        mid = (0.5 * mid[0], 0.5 * mid[1])
        dirv = _s3n_u((pts[k + 1][0] - pts[k][0], pts[k + 1][1] - pts[k][1]))
        for side in ((1, -1) if want_side is None else (want_side,)):
            if target is not None:
                if (1 if _s3n_cross(dirv, _s3n_add(target, mid, -1.0)) > 0.0 else -1) != side:
                    continue
            if any(kk == k and ss == side for kk, ss in used):
                continue
            dd = _s3n_dist(target, mid) if target is not None else 0.0
            if target is not None and dd < 0.45:
                continue
            cands.append((dd, k, side, mid, dirv))
    if not cands:
        return None
    if target is not None:
        return min(cands, key=lambda c: c[0])
    return rng.pick(cands)


def _s3n_cell(rng, F, plist, base):
    """One cell's fissures: a main between its two farthest ports (or port
    to tip, or tip to tip), a branch from every other port to a T-mouth on
    the main, then a crazing of dead-end splinters off every fissure, three
    deep, until the cell holds S3_CRACK_PER_CELL of them. Ryan: "its needs
    to be significantly more cracked with clearer edges." Every fissure is
    fitted (_s3n_fits) as it is drawn; the cell is redrawn only when its
    port connections cannot be made."""
    c, a, o, ha, hr = F["c"], F["a"], F["o"], F["ha"], F["hr"]

    def local(p):
        d = _s3n_add(p, c, -1.0)
        return _s3n_dot(d, a), _s3n_dot(d, o)

    def inside(p):
        u, v = local(p)
        return (abs(u) <= ha - S3_CRACK_INSET and abs(v) <= hr - S3_CRACK_INSET
                and math.hypot(p[0], p[1]) >= S3_WALL_FOOT_R + S3_CRACK_WALL_CLEAR)

    def in_box(p, slack=0.0):
        u, v = local(p)
        return (abs(u) <= ha - S3_CRACK_INSET + slack and abs(v) <= hr - S3_CRACK_INSET + slack
                and math.hypot(p[0], p[1]) >= S3_WALL_FOOT_R + S3_CRACK_WALL_CLEAR - slack)

    ports = F["ports"]
    why = {}
    for attempt in range(S3_CRACK_TRIES):
        made, rings = [], []

        def add(f):
            f.setdefault("used", [])
            f.setdefault("depth", 0)
            _s3n_normals(f, ports)
            _s3n_widths(rng, f, ports)
            ring = _s3n_outline(f)
            if not _s3n_fits(f, ring, made, rings, in_box, ports, base):
                return False
            made.append(f)
            rings.append(ring)
            return True

        # ---- the main
        if len(plist) >= 2:
            best = None
            for i in range(len(plist)):
                for j in range(i + 1, len(plist)):
                    dd = _s3n_dist(ports[plist[i][0]]["p"], ports[plist[j][0]]["p"])
                    if best is None or dd > best[0]:
                        best = (dd, i, j)
            i, j = best[1], best[2]
            (k0, in0), (k1, in1) = plist[i], plist[j]
            pts = _s3n_chain(rng, ports[k0]["p"], in0, ports[k1]["p"], (-in1[0], -in1[1]), inside)
            rest = [plist[q] for q in range(len(plist)) if q not in (i, j)]
            e0, e1 = ("port", k0), ("port", k1)
        elif len(plist) == 1:
            (k0, in0) = plist[0]
            tip = _s3n_add(c, in0, 0.35 * (ha if abs(_s3n_dot(in0, a)) > 0.5 else hr) * rng.f())
            tip = _s3n_add(tip, _s3n_perp(in0), rng.sf() * 0.6)
            pts = _s3n_chain(rng, ports[k0]["p"], in0, tip, None, inside)
            rest = []
            e0, e1 = ("port", k0), ("tip",)
        else:
            ang = rng.f() * TWO_PI
            dv = (math.cos(ang), math.sin(ang))
            pts = _s3n_chain(rng, _s3n_add(c, dv, -0.9), None, _s3n_add(c, dv, 0.9), None, inside)
            rest = []
            e0, e1 = ("tip",), ("tip",)
        if pts is None or not add(dict(pts=pts, e0=e0, e1=e1, cell=F["cell"], role="main")):
            why["main"] = why.get("main", 0) + 1
            continue
        main = made[0]
        # ---- branches: every other port joins the main through a mouth
        ok = True
        for (kp, inp) in rest:
            done = False
            for _try in range(6):
                pick = _s3n_mouth_on(rng, main, ports[kp]["p"], None, main["used"])
                if pick is None:
                    break
                _dd, k, side, mid, dirv = pick
                nrm = _s3n_perp(dirv)
                approach = (nrm[0] * side, nrm[1] * side)
                bpts = _s3n_chain(rng, ports[kp]["p"], inp, mid, (-approach[0], -approach[1]), inside,
                                  back1=0.5 * (main["w"][k] + main["w"][k + 1]))
                if bpts is None:
                    continue
                br = dict(pts=bpts, e0=("port", kp), e1=("mouth", base, k, side), cell=F["cell"],
                          role="branch", wcap=0.20)
                br["mouth1"] = _s3n_mouth_pts(main, k, side)
                if add(br):
                    main["used"].append((k, side))
                    done = True
                    break
            if not done:
                ok = False
                break
        if not ok:
            why["branch"] = why.get("branch", 0) + 1
            continue
        # ---- bridges: fissure to fissure, so the crust breaks into plates
        for _b in range(rng.i(S3_CRACK_BRIDGES[0], S3_CRACK_BRIDGES[1])):
            for _try in range(12):
                if len(made) < 1:
                    break
                ia = rng.i(0, len(made) - 1)
                A = made[ia]
                pa_ = _s3n_mouth_on(rng, A, None, None, A["used"])
                if pa_ is None:
                    continue
                _d, ka, sa, mida, dira = pa_
                awaya = _s3n_perp(dira)
                awaya = (awaya[0] * sa, awaya[1] * sa)
                others = [q for q in range(len(made)) if q != ia]
                if not others:
                    break
                ib = rng.pick(others)
                B = made[ib]
                pb_ = _s3n_mouth_on(rng, B, mida, None, B["used"])
                if pb_ is None:
                    continue
                _d, kb, sb, midb, dirb = pb_
                L = _s3n_dist(mida, midb)
                if not (S3_CRACK_BRIDGE_L[0] <= L <= S3_CRACK_BRIDGE_L[1]):
                    continue
                if _s3n_dot(awaya, _s3n_u(_s3n_add(midb, mida, -1.0))) < 0.3:
                    continue                          # B must lie out on A's open side
                awayb = _s3n_perp(dirb)
                awayb = (awayb[0] * sb, awayb[1] * sb)
                bpts = _s3n_chain(rng, mida, awaya, midb, (-awayb[0], -awayb[1]), inside,
                                  back0=0.5 * (A["w"][ka] + A["w"][ka + 1]),
                                  back1=0.5 * (B["w"][kb] + B["w"][kb + 1]))
                if bpts is None:
                    continue
                bg = dict(pts=bpts, e0=("mouth", base + ia, ka, sa), e1=("mouth", base + ib, kb, sb),
                          cell=F["cell"], role="bridge", wcap=0.20, depth=1)
                m0 = _s3n_mouth_pts(A, ka, sa)
                bg["mouth0"] = (m0[1], m0[0])
                bg["mouth1"] = _s3n_mouth_pts(B, kb, sb)
                if add(bg):
                    A["used"].append((ka, sa))
                    B["used"].append((kb, sb))
                    break
        # ---- crazing: dead-end splinters off every fissure, breadth first
        budget = rng.i(S3_CRACK_PER_CELL[0], S3_CRACK_PER_CELL[1])
        queue = list(range(len(made)))
        rounds = 0
        while len(made) < budget and rounds < 10:
            if not queue:                                # another pass over every host
                queue = list(range(len(made)))
                rounds += 1
            hi = queue.pop(0)
            host = made[hi]
            depth = host["depth"]
            if depth >= S3_CRACK_DEPTH_MAX:
                continue
            want = rng.i(2, 3) if depth == 0 else rng.i(1, 2)
            for _child in range(want):
                if len(made) >= budget:
                    break
                for _try in range(24):
                    pick = _s3n_mouth_on(rng, host, None, None, host["used"])
                    if pick is None:
                        break
                    _dd, k, side, mid, dirv = pick
                    nrm = _s3n_perp(dirv)
                    away = (nrm[0] * side, nrm[1] * side)
                    lo, hi_ = S3_CRACK_SPLINTER
                    # the tip: of several throws, the one farthest from every
                    # fissure already drawn, so the crazing spreads over the
                    # whole cell instead of clotting round the main
                    tip, best = None, -1.0
                    for _throw in range(6):
                        reach = (lo + rng.f() * (hi_ - lo)) * (1.0 if depth == 0 else 0.75)
                        cand = _s3n_add(_s3n_add(mid, away, reach), dirv, rng.sf() * 0.6)
                        if not inside(cand):
                            continue
                        clear = min(_s3n_pt_seg(cand, r[i], r[(i + 1) % len(r)])
                                    for r in rings for i in range(len(r)))
                        if clear > best:
                            tip, best = cand, clear
                    if tip is None or best < 0.3:
                        continue
                    spts = _s3n_chain(rng, mid, away, tip, None, inside,
                                      back0=0.5 * (host["w"][k] + host["w"][k + 1]))
                    if spts is None:
                        continue
                    sp = dict(pts=spts, e0=("mouth", base + hi, k, side), e1=("tip",), cell=F["cell"],
                              role="splinter", wcap=0.15 if depth == 0 else 0.13, depth=depth + 1)
                    m0 = _s3n_mouth_pts(host, k, side)
                    sp["mouth0"] = (m0[1], m0[0])                 # leaving, not entering
                    if add(sp):
                        host["used"].append((k, side))
                        queue.append(len(made) - 1)
                        break
        return made
    raise RuntimeError("s3 cracks: cell %s found no layout in %d draws: %s ports %d"
                       % (str(F["cell"]), S3_CRACK_TRIES, str(why), len(plist)))


def _s3_crack_network():
    """The whole network: cells, the spanning tree, the ports, every cell's
    fissures with global host indices. Cached in S3["net"]."""
    if "net" in S3:
        return S3["net"]
    lay = S3["lay"]
    rows, step = lay["rows"], lay["step"]
    rng = _Rng(S3_CRACK_SEED)
    cells = {}
    for p in _s3_pads():
        i, j = p["row"], p["col"]
        b, rho = rows[i], S3_COLS[j]
        c = pol(b, rho, 0.0)[:2]
        along = _s3n_u(_s3n_add(pol(b + 0.01, rho, 0.0)[:2], pol(b - 0.01, rho, 0.0)[:2], -1.0))
        out = _s3n_u(_s3n_add(pol(b, rho + 0.5, 0.0)[:2], pol(b, rho - 0.5, 0.0)[:2], -1.0))
        cells[(i, j)] = dict(cell=(i, j), c=c, a=along, o=out, b=b, rho=rho, name=p["name"],
                             ha=0.5 * math.radians(step) * rho, hr=0.5 * (S3_COLS[1] - S3_COLS[0]))
    edges = []
    for (i, j) in sorted(cells):
        if (i + 1, j) in cells:
            edges.append(((i, j), (i + 1, j)))
        if (i, j + 1) in cells:
            edges.append(((i, j), (i, j + 1)))
    order = list(edges)
    for k in range(len(order) - 1, 0, -1):          # Fisher-Yates on the seeded LCG
        q = rng.i(0, k)
        order[k], order[q] = order[q], order[k]
    tree = order                                    # every neighbouring pair joins: the crust
    ports = []                                      # breaks into plates, not into one tree
    for A, B in tree:
        fa, fb = cells[A], cells[B]
        w = S3_CRACK_PORT_W[0] + rng.f() * (S3_CRACK_PORT_W[1] - S3_CRACK_PORT_W[0])
        d = S3_CRACK_PORT_D[0] + rng.f() * (S3_CRACK_PORT_D[1] - S3_CRACK_PORT_D[0])
        if B[0] == A[0] + 1:                          # the next row: a radial edge
            bm = 0.5 * (fa["b"] + fb["b"])
            rho_p = fa["rho"] + rng.sf() * (fa["hr"] - 0.9)
            p = pol(bm, rho_p, 0.0)[:2]
            n = _s3n_u(_s3n_add(pol(bm, rho_p + 0.5, 0.0)[:2], pol(bm, rho_p - 0.5, 0.0)[:2], -1.0))
            along = _s3n_u(_s3n_add(pol(bm + 0.01, rho_p, 0.0)[:2], pol(bm - 0.01, rho_p, 0.0)[:2], -1.0))
            inA, inB = (-along[0], -along[1]), along
        else:                                          # the next column: an arc edge
            rho_m = 0.5 * (fa["rho"] + fb["rho"])
            bp = fa["b"] + math.degrees(rng.sf() * (fa["ha"] - 0.9) / rho_m)
            p = pol(bp, rho_m, 0.0)[:2]
            n = _s3n_u(_s3n_add(pol(bp + 0.01, rho_m, 0.0)[:2], pol(bp - 0.01, rho_m, 0.0)[:2], -1.0))
            out = _s3n_u(_s3n_add(pol(bp, rho_m + 0.5, 0.0)[:2], pol(bp, rho_m - 0.5, 0.0)[:2], -1.0))
            inA, inB = (-out[0], -out[1]), out
        ports.append(dict(p=p, n=n, w=w, d=d, A=A, B=B, inA=inA, inB=inB))
    cell_ports = {cc: [] for cc in cells}
    for k, pt in enumerate(ports):
        cell_ports[pt["A"]].append((k, pt["inA"]))
        cell_ports[pt["B"]].append((k, pt["inB"]))
    fissures = []
    for cc in sorted(cells):
        F = dict(cells[cc])
        F["ports"] = ports
        fissures += _s3n_cell(rng, F, cell_ports[cc], len(fissures))
    fissures = _s3n_off_wall(fissures)
    S3["net"] = dict(cells=cells, tree=tree, ports=ports, fissures=fissures)
    return S3["net"]


def _s3n_edge_r(p):
    """The deck's outer edge (the outer wall's foot chord) at p's bearing."""
    x, y = S3["deck_xy"](S3["L"]["T"](_bear_deg(math.atan2(p[1], p[0]))), OUTER_R)
    return math.hypot(x, y)


def _s3n_off_wall(fissures):
    """Splinters that ran past the outer wall's foot tore holes in the deck patch: drop
    each with every splinter grown off it, and renumber the hosts the rest name."""
    def off(f):
        return any(math.hypot(q[0], q[1]) > _s3n_edge_r(q) - S3_CRACK_MARGIN for q in _s3n_outline(f))
    drop = set(k for k, f in enumerate(fissures) if off(f))
    grew = True
    while grew:
        grew = False
        for k, f in enumerate(fissures):
            if k not in drop and any(e[0] == "mouth" and e[1] in drop for e in (f["e0"], f["e1"])):
                drop.add(k)
                grew = True
    for k in drop:
        if any(e[0] == "port" for e in (fissures[k]["e0"], fissures[k]["e1"])):
            raise RuntimeError("s3 cracks: a port fissure runs past the outer wall")
    new = {}
    for k in range(len(fissures)):
        if k not in drop:
            new[k] = len(new)
    out = []
    for k, f in enumerate(fissures):
        if k in drop:
            continue
        for key in ("e0", "e1"):
            if f[key][0] == "mouth":
                f[key] = (f[key][0], new[f[key][1]]) + tuple(f[key][2:])
        out.append(f)
    return out


def _s3c_simple(poly):
    """true iff simple: no zero edge, non-adjacent edges never touch, adjacent meet only at the shared end."""

    def orient(a, b, p):
        d = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
        if d > 0.0:
            return 1
        if d < 0.0:
            return -1
        return 0

    def on_seg(a, b, p):
        return (min(a[0], b[0]) <= p[0] <= max(a[0], b[0])
                and min(a[1], b[1]) <= p[1] <= max(a[1], b[1]))

    def touch(p, q, r, s):
        d1 = orient(r, s, p)
        d2 = orient(r, s, q)
        d3 = orient(p, q, r)
        d4 = orient(p, q, s)
        if d1 * d2 < 0 and d3 * d4 < 0:
            return True
        if d1 == 0 and on_seg(r, s, p):
            return True
        if d2 == 0 and on_seg(r, s, q):
            return True
        if d3 == 0 and on_seg(p, q, r):
            return True
        if d4 == 0 and on_seg(p, q, s):
            return True
        return False

    n = len(poly)
    if n < 3:
        return False
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        if a[0] == b[0] and a[1] == b[1]:
            return False
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        c = poly[(i + 2) % n]
        if orient(a, b, c) == 0 and (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1]) < 0.0:
            return False
    for i in range(n):
        for j in range(i + 1, n):
            if j == i + 1 or (i == 0 and j == n - 1):
                continue
            if touch(poly[i], poly[(i + 1) % n], poly[j], poly[(j + 1) % n]):
                return False
    return True


def _s3c_seg_gap(p, q, r, s):
    """shortest distance between segments pq and rs; 0.0 if they intersect."""

    def orient(a, b, x):
        d = (b[0] - a[0]) * (x[1] - a[1]) - (b[1] - a[1]) * (x[0] - a[0])
        if d > 0.0:
            return 1
        if d < 0.0:
            return -1
        return 0

    def on_seg(a, b, x):
        return (min(a[0], b[0]) <= x[0] <= max(a[0], b[0])
                and min(a[1], b[1]) <= x[1] <= max(a[1], b[1]))

    def pt_seg(x, a, b):
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        dd = dx * dx + dy * dy
        if dd <= 1e-12:
            return math.hypot(x[0] - a[0], x[1] - a[1])
        t = ((x[0] - a[0]) * dx + (x[1] - a[1]) * dy) / dd
        if t < 0.0:
            t = 0.0
        elif t > 1.0:
            t = 1.0
        return math.hypot(x[0] - (a[0] + t * dx), x[1] - (a[1] + t * dy))

    d1 = orient(r, s, p)
    d2 = orient(r, s, q)
    d3 = orient(p, q, r)
    d4 = orient(p, q, s)
    if d1 * d2 < 0 and d3 * d4 < 0:
        return 0.0
    if d1 == 0 and on_seg(r, s, p):
        return 0.0
    if d2 == 0 and on_seg(r, s, q):
        return 0.0
    if d3 == 0 and on_seg(p, q, r):
        return 0.0
    if d4 == 0 and on_seg(p, q, s):
        return 0.0
    return min(pt_seg(p, r, s), pt_seg(q, r, s), pt_seg(r, p, q), pt_seg(s, p, q))


def _s3c_poly_gap(a, b):
    """shortest distance between two closed polygons' boundaries; 0.0 if they cross or one contains the other."""

    def inside(poly, x):
        n = len(poly)
        hit = False
        for i in range(n):
            px, py = poly[i]
            qx, qy = poly[(i + 1) % n]
            if (py > x[1]) != (qy > x[1]):
                cx = px + (x[1] - py) * (qx - px) / (qy - py)
                if cx > x[0]:
                    hit = not hit
        return hit

    na = len(a)
    nb = len(b)
    g = float("inf")
    for i in range(na):
        for j in range(nb):
            d = _s3c_seg_gap(a[i], a[(i + 1) % na], b[j], b[(j + 1) % nb])
            if d < g:
                g = d
            if g <= 1e-12:
                return 0.0
    if inside(b, a[0]) or inside(a, b[0]):
        return 0.0
    return g


# ---- one pad's fissures: drawn, then solved to a width ----------------------




# ---- the lip wall: ragged rock, not a hallway (Ryan: "its not a fucking
# hallway. its just fucking cover, its just a fucking rock wall"). A per-column
# crag on the crest, top and foot wandering, faces cleaved in runs of 1-3
# columns like rock_wall_build.py; the crest is spent INSIDE the window the
# guard's sight lines cut (crouched on the path hidden, standing seen), so the
# raggedness never costs the sight line. Every value is a seeded hash of the
# column index: no state, the same rock at any bearing in any order.

S3_WALL_SEED = 3310691
S3_WALL_MARGIN = 0.03        # metres of clearance kept at BOTH window edges
S3_WALL_T = (0.15, 0.25)     # half width of the flat top, wandering in runs
S3_WALL_W = (0.36, 0.52)     # half width at the foot; the inner foot IS the lip
S3_WALL_CRAG = (0.10, 0.25)  # peak-to-peak crag on the crest, per run
S3_WALL_FACE = 0.04          # cleaved facet relief, flanks only, never the top
S3_WALL_TAPER = 0.6          # metres past S3_FIELD the ends die out over
S3_WALL_KSTEP = 0.5          # arc metres per column: the crag's grain
S3_WALL_BAND_PROOF = 0.5     # the sight proof tests a row's columns this far past
                             # half a row pitch either side of the row; the crest
                             # honours them one column step further out
S3_WALL_CELL = 0.9           # half a pad cell plus a body: the path cell's sides
S3_WALL_EPS = 1.0e-9



def _s3_wall_hash(k, salt):
    """0.0 <= h < 1.0 from a column index and a channel salt. No state: the
    wall can be sampled at any bearing, in any order, forever."""
    h = (int(k) * 2654435761 + int(salt) * 40503 + S3_WALL_SEED) & 0xFFFFFFFF
    h ^= h >> 16
    h = (h * 2246822519) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 3266489917) & 0xFFFFFFFF
    h ^= h >> 16
    return h / 4294967296.0


def _s3_wall_edge(j, salt):
    """Is column j the start of a run? A third of columns break outright; a
    column also breaks when neither of the two before it did. That second
    clause is what caps a run at 3 -- it cannot be extended by luck."""
    if int(_s3_wall_hash(j, salt) * 3.0) == 0:
        return True
    return (int(_s3_wall_hash(j - 1, salt) * 3.0) != 0
            and int(_s3_wall_hash(j - 2, salt) * 3.0) != 0)


def _s3_wall_run(k, salt):
    """The leader of k's run. One of k, k-1, k-2 always breaks (if k and k-1
    both held, then h(k-1) != 0 forced h(k-2) == 0), so this never falls
    through and every column in a run reads one value: cleaved, not smooth."""
    for m in (0, 1, 2):
        if _s3_wall_edge(k - m, salt):
            return k - m
    return k - 2


def _s3_wall_held(k, salt):
    """The run's own 0..1, held flat across its 1-3 columns."""
    return _s3_wall_hash(_s3_wall_run(k, salt), salt)



def _s3_wall_spec(lay):
    """The lip wall's shape, as callables over bearing. `lay` is _s3_layout()'s
    dict: rows (bearings), path (column per row), spans (the cleared columns
    per row, which is what the guard must NOT see a body standing in, and
    must see a launched one over)."""
    rows = list(lay["rows"])
    spans = list(lay["spans"])
    u_lo, u_hi = _s3_arc(S3_FIELD[0]), _s3_arc(S3_FIELD[1])
    eye = S3_EYE_Z - DECK_Z          # 5.90 m of eye over this deck

    def _k(b):
        """Column index: the grain the whole wall is cut on."""
        return int(math.floor((_s3_arc(b) - u_lo) / S3_WALL_KSTEP))

    def T(b):
        return 0.5 * (S3_WALL_OUT - S3_WALL_IN)

    def W(b):
        return S3_WALL_FOOT_R - INNER_R

    def rc(b):
        """The plateau's centre line."""
        return 0.5 * (S3_WALL_IN + S3_WALL_OUT)

    half_row = 0.5 * (rows[1] - rows[0])

    def _cols_near(b, band):
        """The path columns of every row within half a row pitch plus `band`
        metres of b: the crest at b must serve all of them."""
        out = set()
        reach = half_row + math.degrees(band / S3_LANE_R)
        for i, rb in enumerate(rows):
            if abs(rb - b) <= reach + 1.0e-9:
                out.update(range(spans[i][0], spans[i][1] + 1))
        return out

    def window(b, band=S3_WALL_BAND_PROOF):
        """(L, U) over the deck: the crest must hide a STANDING body on the
        path -- the line from the eye to its top (S3_STAND) at the path
        cell's far side, taken at the inner top edge -- and must not hide a
        launched body at its apex over ANY column -- the line to the apex
        over each column, taken at the outer top edge."""
        L, U = -1.0e9, 1.0e9
        for j in _cols_near(b, band):
            far = S3_COLS[j] + S3_WALL_CELL      # the path cell's far side
            L = max(L, eye - (eye - S3_STAND) * S3_WALL_IN / far)
        for rho in S3_COLS:
            U = min(U, eye - (eye - S3_APEX) * S3_WALL_OUT / rho)
        return L, U

    def crest(b):
        """Crest height over the deck: S3_WALL_OVER above the standing line,
        per column in runs, never nearer the apex line than S3_WALL_MARGIN."""
        L, U = window(b, S3_WALL_BAND_PROOF + S3_WALL_KSTEP)
        j = _s3_wall_run(_k(b), 37)
        lo, hi = S3_WALL_OVER
        h = L + S3_WALL_MARGIN + lo + _s3_wall_hash(j, 89) * (hi - lo)
        return min(h, U - S3_WALL_MARGIN)

    def chamfer(b):
        lo, hi = S3_WALL_CHAMFER
        return lo + _s3_wall_held(_k(b), 11) * (hi - lo)

    def _taper(b):
        d = min(_s3_arc(b) - u_lo, u_hi - _s3_arc(b))
        return 1.0 if d >= 0.0 else max(0.0, 1.0 + d / S3_WALL_TAPER)

    def height(b, rho, noise=True):
        """Rock over DECK_Z at (bearing, station): nothing at the lip, the
        crest from the inner top edge across the plateau, the chamfered
        outer top edge, nothing from the foot out. Piecewise linear between
        those knots, so any station reads the same rock."""
        h = crest(b) * _taper(b)
        knots = ((INNER_R, 0.0), (S3_WALL_IN, h), (S3_WALL_OUT - 0.10, h),
                 (S3_WALL_OUT, h * chamfer(b)), (S3_WALL_FOOT_R, 0.0))
        if rho <= INNER_R + S3_WALL_EPS or rho >= S3_WALL_FOOT_R - S3_WALL_EPS:
            return 0.0
        for (r0, h0), (r1, h1) in zip(knots, knots[1:]):
            if r0 - S3_WALL_EPS <= rho <= r1 + S3_WALL_EPS:
                f = (rho - r0) / (r1 - r0)
                return h0 + (h1 - h0) * max(0.0, min(1.0, f))
        return 0.0

    return dict(crest=crest, T=T, W=W, rc=rc, window=window, height=height, chamfer=chamfer)


def _s3_layout():
    """The section's one layout: rows, the path's spans, the pads, the wall
    polyline, the height field over the deck and the grid lines that sample
    it exactly. Pure geometry in the grid frame; cached in S3["lay"]."""
    if "lay" in S3:
        return S3["lay"]
    n = S3_ROWS
    step = (S3_ROW_B[1] - S3_ROW_B[0]) / (n - 1)
    rows = [S3_ROW_B[0] + i * step for i in range(n)]
    path = list(S3_PATH)
    # a row's cleared span: its own path cell, plus the cell it steps across
    # to before the next row, so the runner moves sideways, then forward
    spans = []
    for i in range(n):
        nxt = path[i + 1] if i + 1 < n else path[i]
        spans.append((min(path[i], nxt), max(path[i], nxt)))
    pads = []
    for i in range(n):
        for j in range(len(S3_COLS)):
            cleared = spans[i][0] <= j <= spans[i][1]
            jump = i in S3_JUMP_ROWS and j == path[i]
            if cleared and not jump:
                continue
            pads.append({"row": i, "col": j, "b": rows[i], "rho": S3_COLS[j], "jump": jump,
                         "hx": 0.5 * S3_PAD, "hz": 0.5 * S3_PAD})
    # the wall: one ragged rock at the pit edge, its inner foot on the lip
    # itself. dist() measures from the LIP arc between the field's ends, so
    # "a body clear of the wall" is dist > S3_WALL_FOOT + the body's radius.
    pts = [(S3_FIELD[0], INNER_R), (S3_FIELD[1], INNER_R)]
    segs = [((_s3_arc(pts[0][0]), pts[0][1]), (_s3_arc(pts[1][0]), pts[1][1]))]

    def dist(b, rho):
        u = _s3_arc(b)
        return min(_s3_seg_dist(u, rho, a, c) for a, c in segs)

    lay = dict(rows=rows, step=step, path=path, spans=spans, pads=pads, pts=pts, segs=segs,
               dist=dist, ext=S3_EXT)
    wall = _s3_wall_spec(lay)
    lay["wall"] = wall
    lay["height"] = wall["height"]
    lay["rho_w"] = [wall["rc"](b) for b in rows]
    # grid lines: the field's ends exactly, a plain lattice between; across
    # the wall the fixed stations S3_WALL_ST, then the plain lattice. The
    # wall's inner foot is the lip vertex itself (station INNER_R, height 0).
    exact_b = [S3_FIELD[0], S3_FIELD[1]]
    exact_r = list(S3_WALL_ST)
    cols = _s3_lattice(S3_EXT[0], S3_EXT[1], math.degrees(S3_COL_STEP / S3_LANE_R), exact_b,
                       math.degrees(S3_MERGE / S3_LANE_R))
    stations = sorted(set([INNER_R, OUTER_R] + _s3_lattice(INNER_R, OUTER_R - S3_EDGE_BAND,
                                                          S3_ST_STEP, exact_r, S3_MERGE)))
    lay.update(exact_b=exact_b, cols=cols, stations=stations)
    S3["lay"] = lay
    return S3["lay"]


def _s3_setup(T, base_cols):
    """S3's columns: the deck's own inside the section, each end snapped onto
    one when it is within COL_MERGE, and the section's own between -- so the
    deck, the outer wall and the ceiling all break on the same lines and
    nothing T-junctions. Same shape as _s2_setup."""
    L = dict(_s3_layout())
    ends = []
    for b in L["ext"]:
        t = T(b)
        near = [c for c in base_cols if abs(c - t) * CROSS_R <= COL_MERGE]
        ends.append(near[0] if near else t)
    s1, s0 = ends                     # the LOW bearing is the HIGH Blender angle
    keep = [c for c in base_cols if s0 < c < s1] + [s0, s1]
    # the wall's own edge columns are kept whatever the base deck has near
    # them; only the plain lattice yields to a base column
    exact = [T(b) for b in L["exact_b"] if s0 < T(b) < s1]
    cols = [t for t in exact if all(abs(t - k) > 1e-7 for k in keep)]
    cols += [t for t in (T(b) for b in L["cols"]) if s0 < t < s1
             and all(abs(t - e) > 1e-7 for e in exact)
             and all(abs(t - k) * CROSS_R > COL_MERGE for k in keep)]
    slivers = sum(1 for e in exact for k in keep if 1e-7 < abs(e - k) * CROSS_R < 0.1)
    if slivers:
        print("MDL note s3 %d wall edge column(s) within 0.1 m of a deck column" % slivers)
    L.update(s0=s0, s1=s1, cols=_merge_cols(keep, cols), T=T)
    return L


def _s3_h(L, t, rho):
    """The section's rock over DECK_Z at a GRID point: Blender column angle t,
    station radius rho. The deck grid and the collider sample this."""
    return L["height"](_bear_deg(t), rho)


def _s3_zone(m, ids):
    """A facet flat enough to be floor takes the deck's radial projection; a
    wall flank takes the rock zone, or the radial projection collapses on it
    and the texture smears vertically."""
    pts = [m.verts[i] for i in ids]
    n = _newell(pts)
    mag = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
    if mag < EPS:
        return ZONE_DECK
    if abs(n[2]) / mag >= math.cos(math.radians(S3_FLANK)):
        return ZONE_DECK
    return ZONE_WALLFACE


def _s3_collider(c):
    """The section's deck and wall: one grid on the same surface the art mesh
    uses, every column and every station. Art and collision are the SAME
    surface in this section."""
    L = S3["L"]
    cols, st = L["cols"], L["stations"]
    deck_xy = S3["deck_xy"]
    grid = []
    for t in cols:
        col = []
        for rad in st:
            x, y = deck_xy(t, rad)
            col.append(c.v((x, y, DECK_Z + _s3_h(L, t, rad))))
        grid.append(col)
    for i in range(len(cols) - 1):
        for j in range(len(st) - 1):
            c.quad(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1],
                   UP, ZONE_ROCK)
    S3["coll_tris"] = 2 * (len(cols) - 1) * (len(st) - 1)


# ---- the cracks: fissures cut into the deck where each plate was ------------

def _s3_patch_rects(L):
    """The one deck patch the crack network takes over: the rectangle of
    grid cells (column span, station span) holding every fissure with
    S3_CRACK_MARGIN to spare. Cached in S3["patches"]."""
    if "patches" in S3:
        return S3["patches"]
    T, cols, st = L["T"], L["cols"], L["stations"]
    net = _s3_crack_network()
    ts, rs = [], []
    for f in net["fissures"]:
        for (x, y) in _s3n_outline(f):
            ts.append(T(_bear_deg(math.atan2(y, x))))
            rs.append(math.hypot(x, y))
    mt = S3_CRACK_MARGIN / min(rs)
    i0 = max(i for i, t in enumerate(cols) if t <= min(ts) - mt)
    i1 = min(i for i, t in enumerate(cols) if t >= max(ts) + mt)
    j0 = max(j for j in range(len(st)) if st[j] <= min(rs) - S3_CRACK_MARGIN)
    j1 = min(j for j in range(len(st)) if st[j] >= max(rs) + S3_CRACK_MARGIN)
    assert st[j0] >= S3_WALL_FOOT_R - 1e-6, \
        "s3 cracks: the deck patch would start inside the lip wall (station %.2f)" % st[j0]
    S3["patches"] = [dict(i0=i0, i1=i1, j0=j0, j1=j1, tlo=cols[i0], thi=cols[i1],
                          ci=list(range(i0, i1 + 1)))]
    return S3["patches"]


def _s3_in_patch(t0, t1, j):
    """Whether the deck cell (columns t0..t1, stations j..j+1) belongs to the
    crack patch and is laid by _s3_patches instead of the plain grid."""
    for pr in S3["patches"]:
        if pr["tlo"] - 1e-9 <= t0 and t1 <= pr["thi"] + 1e-9 and pr["j0"] <= j < pr["j1"]:
            return True
    return False


def _s3_net_mesh(m):
    """Every fissure of the network as mesh: six vertices per station (top
    left/right, the dark lip's lower edge, the lava floor), shared at a port
    by both cells' fissures, taken from the host at a mouth; then the side
    bands and the floor per segment, the host's side band under a mouth left
    out. Returns (hole loops as vertex-id rings, lava area, lip area, tris,
    islands)."""
    net = _s3_crack_network()
    F, ports = net["fissures"], net["ports"]
    order = list(range(len(F)))                    # a host always precedes its branches
    V = {}
    port_v = {}
    suppressed = set()

    def station(p, nrm, w, d):
        tl = m.v((p[0] + nrm[0] * w, p[1] + nrm[1] * w, DECK_Z))
        tr = m.v((p[0] - nrm[0] * w, p[1] - nrm[1] * w, DECK_Z))
        fw = w * S3_CRACK_FLOOR
        fl = m.v((p[0] + nrm[0] * fw, p[1] + nrm[1] * fw, DECK_Z - d))
        fr = m.v((p[0] - nrm[0] * fw, p[1] - nrm[1] * fw, DECK_Z - d))
        ml = m.v(tuple(m.verts[tl][k] + S3_CRACK_LIP * (m.verts[fl][k] - m.verts[tl][k]) for k in range(3)))
        mr = m.v(tuple(m.verts[tr][k] + S3_CRACK_LIP * (m.verts[fr][k] - m.verts[tr][k]) for k in range(3)))
        return dict(TL=tl, TR=tr, ML=ml, MR=mr, FL=fl, FR=fr)

    for idx in order:
        f = F[idx]
        pts, nrm, w, d = f["pts"], f["nrm"], f["w"], f["d"]
        n = len(pts)
        cols = dict(TL=[], TR=[], ML=[], MR=[], FL=[], FR=[])
        for i in range(n):
            end = f["e0"] if i == 0 else (f["e1"] if i == n - 1 else None)
            if end is None:
                st = station(pts[i], nrm[i], w[i], d[i])
            elif end[0] == "tip":
                t = m.v((pts[i][0], pts[i][1], DECK_Z))
                st = dict(TL=t, TR=t, ML=t, MR=t, FL=t, FR=t)
            elif end[0] == "port":
                k = end[1]
                if k not in port_v:
                    pt = ports[k]
                    port_v[k] = station(pt["p"], pt["n"], pt["w"], pt["d"])
                pv = port_v[k]
                if _s3n_dot(nrm[i], ports[k]["n"]) >= 0.0:
                    st = dict(pv)
                else:
                    st = dict(TL=pv["TR"], TR=pv["TL"], ML=pv["MR"], MR=pv["ML"], FL=pv["FR"], FR=pv["FL"])
            else:                                      # a mouth on host h, segment k, side
                _kind, h, k, side = end
                H = V[h]
                entering = i == n - 1
                if side > 0:
                    a_, b_ = ("L", k + 1), ("L", k)      # entering the left: (left end, right end)
                else:
                    a_, b_ = ("R", k), ("R", k + 1)
                if not entering:
                    a_, b_ = b_, a_
                st = {}
                for band in ("T", "M", "F"):
                    st[band + "L"] = H[band + a_[0]][a_[1]]
                    st[band + "R"] = H[band + b_[0]][b_[1]]
                suppressed.add((h, k, side))
            for key in cols:
                cols[key].append(st[key])
        V[idx] = cols
    # ---- faces
    before = len(m.faces)
    lava = lip = 0.0
    for idx, f in enumerate(F):
        C = V[idx]
        n = len(f["pts"])
        for i in range(n - 1):
            k = min(max(i, 1), n - 2)
            wl = _s3_crack_want(m, C["TL"][k], C["TR"][k])
            wr = _s3_crack_want(m, C["TR"][k], C["TL"][k])
            faces = []
            if (idx, i, 1) not in suppressed:
                faces += [((C["TL"][i], C["TL"][i + 1], C["ML"][i + 1], C["ML"][i]), wl, S3_CRACK_ZONE_WALL),
                          ((C["ML"][i], C["ML"][i + 1], C["FL"][i + 1], C["FL"][i]), wl, S3_CRACK_ZONE_FLOOR)]
            if (idx, i, -1) not in suppressed:
                faces += [((C["TR"][i], C["MR"][i], C["MR"][i + 1], C["TR"][i + 1]), wr, S3_CRACK_ZONE_WALL),
                          ((C["MR"][i], C["FR"][i], C["FR"][i + 1], C["MR"][i + 1]), wr, S3_CRACK_ZONE_FLOOR)]
            faces.append(((C["FL"][i], C["FR"][i], C["FR"][i + 1], C["FL"][i + 1]), UP, S3_CRACK_ZONE_FLOOR))
            for quad, want, zone in faces:
                uniq = []
                for v in quad:
                    if v not in uniq:
                        uniq.append(v)
                if len(uniq) < 3:
                    continue
                f0 = len(m.faces)
                if len(uniq) == 4:
                    m.quad(uniq[0], uniq[1], uniq[2], uniq[3], want, zone, best=True)
                else:
                    m.tri(uniq[0], uniq[1], uniq[2], want, zone)
                if zone == S3_CRACK_ZONE_FLOOR:
                    m.crack.update(range(f0, len(m.faces)))
                area = _s3_poly_area(m, uniq)
                if zone == S3_CRACK_ZONE_FLOOR:
                    lava += area
                else:
                    lip += area
    tris = len(m.faces) - before
    # ---- the outline: directed boundary edges, one out of and one into every
    # top vertex, walked into loops. One loop per island.
    nxt = {}
    for idx, f in enumerate(F):
        C = V[idx]
        n = len(f["pts"])
        for i in range(n - 1):
            if (idx, i, 1) not in suppressed and C["TL"][i] != C["TL"][i + 1]:
                assert C["TL"][i] not in nxt, "s3 cracks: two outline edges leave one vertex"
                nxt[C["TL"][i]] = C["TL"][i + 1]
            if (idx, i, -1) not in suppressed and C["TR"][i + 1] != C["TR"][i]:
                assert C["TR"][i + 1] not in nxt, "s3 cracks: two outline edges leave one vertex"
                nxt[C["TR"][i + 1]] = C["TR"][i]
    seen = set()
    loops = []
    for start in list(nxt):
        if start in seen:
            continue
        ring, v = [], start
        while v not in seen:
            seen.add(v)
            ring.append(v)
            v = nxt[v]
        assert v == start, "s3 cracks: an outline that does not close"
        loops.append(ring)
    return loops, lava, lip, tris


def _pf_area2(P, ring):
    return sum(P[ring[i]][0] * P[ring[(i + 1) % len(ring)]][1]
               - P[ring[(i + 1) % len(ring)]][0] * P[ring[i]][1] for i in range(len(ring)))


def _pf_cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _pf_seg_hit(a, b, c, d):
    """Proper crossing of segments a-b and c-d (shared end points do not count)."""
    d1, d2 = _pf_cross(c, d, a), _pf_cross(c, d, b)
    d3, d4 = _pf_cross(a, b, c), _pf_cross(a, b, d)
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0)) and d1 * d2 < 0 and d3 * d4 < 0


def _pf_bridge(P, outer, hole):
    """Splice a hole (clockwise) into the outer ring (anticlockwise) through
    the shortest diagonal from the hole's rightmost vertex that crosses nothing."""
    segs = [(outer[i], outer[(i + 1) % len(outer)]) for i in range(len(outer))]
    segs += [(hole[i], hole[(i + 1) % len(hole)]) for i in range(len(hole))]
    hk = max(range(len(hole)), key=lambda k: (P[hole[k]][0], -P[hole[k]][1]))
    for hk_try in [hk] + sorted(range(len(hole)), key=lambda k: -P[hole[k]][0]):
        h = P[hole[hk_try]]
        cand = sorted(range(len(outer)), key=lambda k: (P[outer[k]][0] - h[0]) ** 2 + (P[outer[k]][1] - h[1]) ** 2)
        for ok in cand[:200]:
            o = P[outer[ok]]
            if o == h:
                continue
            # the diagonal must leave o into the interior
            prv, nxt = P[outer[ok - 1]], P[outer[(ok + 1) % len(outer)]]
            if _pf_cross(prv, o, nxt) >= 0:
                if not (_pf_cross(prv, o, h) > 0 and _pf_cross(o, nxt, h) > 0):
                    continue
            elif _pf_cross(prv, o, h) <= 0 and _pf_cross(o, nxt, h) <= 0:
                continue
            if any(_pf_seg_hit(h, o, P[a], P[b]) for a, b in segs):
                continue
            k = hk_try
            return outer[:ok + 1] + hole[k:] + hole[:k + 1] + outer[ok:]
    raise RuntimeError("fill: no bridge to a hole")


def _pf_earclip(P, ring):
    """Ear clipping of one simple anticlockwise ring; reflex corners bucketed on a grid."""
    n = len(ring)
    prev = [(i - 1) % n for i in range(n)]
    nxt = [(i + 1) % n for i in range(n)]
    alive = n
    xs = [P[v][0] for v in ring]
    ys = [P[v][1] for v in ring]
    cell = max(max(xs) - min(xs), max(ys) - min(ys)) / max(1.0, math.sqrt(n)) + 1e-9
    grid = {}

    def gk(p):
        return (int(math.floor(p[0] / cell)), int(math.floor(p[1] / cell)))

    def reflex(i):
        return _pf_cross(P[ring[prev[i]]], P[ring[i]], P[ring[nxt[i]]]) <= 0.0

    for i in range(n):
        grid.setdefault(gk(P[ring[i]]), set()).add(i)
    out = []

    def is_ear(i):
        a, b, c = P[ring[prev[i]]], P[ring[i]], P[ring[nxt[i]]]
        if _pf_cross(a, b, c) <= 1e-12:
            return False
        x0, x1 = min(a[0], b[0], c[0]), max(a[0], b[0], c[0])
        y0, y1 = min(a[1], b[1], c[1]), max(a[1], b[1], c[1])
        g0, g1 = gk((x0, y0)), gk((x1, y1))
        for gx in range(g0[0], g1[0] + 1):
            for gy in range(g0[1], g1[1] + 1):
                for j in grid.get((gx, gy), ()):
                    if j in (prev[i], i, nxt[i]):
                        continue
                    p = P[ring[j]]
                    if p == a or p == b or p == c or not reflex(j):   # a bridge's twin corner
                        continue
                    if _pf_cross(a, b, p) >= 0 and _pf_cross(b, c, p) >= 0 and _pf_cross(c, a, p) >= 0:
                        return False
        return True

    i = 0
    stall = 0
    while alive > 3:
        if is_ear(i):
            out.append((ring[prev[i]], ring[i], ring[nxt[i]]))
            grid[gk(P[ring[i]])].discard(i)
            p, q = prev[i], nxt[i]
            nxt[p], prev[q] = q, p
            alive -= 1
            stall = 0
            i = p
        else:
            i = nxt[i]
            stall += 1
            if stall > alive + 2:
                raise RuntimeError("fill: ear clipping stalled with %d left" % alive)
    out.append((ring[prev[i]], ring[i], ring[nxt[i]]))
    return out


def _pf_flip(P, tris, fixed):
    """Lawson flips to a constrained Delaunay: no edge in `fixed` moves."""
    def key(a, b):
        return (a, b) if a < b else (b, a)
    tris = [list(t) for t in tris]
    edge = {}
    for ti, t in enumerate(tris):
        for k in range(3):
            edge.setdefault(key(t[k], t[(k + 1) % 3]), []).append(ti)
    stack = [e for e, ts in edge.items() if len(ts) == 2 and e not in fixed]
    guard = 0
    while stack and guard < 200000:
        guard += 1
        e = stack.pop()
        ts = edge.get(e)
        if not ts or len(ts) != 2 or e in fixed:
            continue
        t0, t1 = tris[ts[0]], tris[ts[1]]
        a, b = e
        c = [v for v in t0 if v not in e][0]
        d = [v for v in t1 if v not in e][0]
        pa, pb, pc, pd = P[a], P[b], P[c], P[d]
        # d inside the circumcircle of (a, b, c)?
        if _pf_cross(pa, pb, pc) < 0:
            pa, pb = pb, pa
            a, b = b, a
        ax, ay = pa[0] - pd[0], pa[1] - pd[1]
        bx, by = pb[0] - pd[0], pb[1] - pd[1]
        cx, cy = pc[0] - pd[0], pc[1] - pd[1]
        det = ((ax * ax + ay * ay) * (bx * cy - cx * by) - (bx * bx + by * by) * (ax * cy - cx * ay)
               + (cx * cx + cy * cy) * (ax * by - bx * ay))
        if det <= 1e-12:
            continue
        # the quad a-d-b-c must be convex for c-d to replace a-b
        if _pf_cross(pc, pd, pa) * _pf_cross(pc, pd, pb) >= 0 or _pf_cross(pa, pb, pc) * _pf_cross(pa, pb, pd) >= 0:
            continue
        i0, i1 = ts
        n0 = [c, a, d] if _pf_cross(P[c], P[a], P[d]) > 0 else [c, d, a]
        n1 = [c, d, b] if _pf_cross(P[c], P[d], P[b]) > 0 else [c, b, d]
        for t, ti in ((t0, i0), (t1, i1)):
            for k in range(3):
                edge[key(t[k], t[(k + 1) % 3])].remove(ti)
        del edge[key(a, b)]
        tris[i0], tris[i1] = n0, n1
        for t, ti in ((n0, i0), (n1, i1)):
            for k in range(3):
                edge.setdefault(key(t[k], t[(k + 1) % 3]), []).append(ti)
        for ee in (key(a, c), key(c, b), key(b, d), key(d, a)):
            if ee not in fixed:
                stack.append(ee)
    return [tuple(t) for t in tris]


def _fill2d(rings):
    """rings[0] the outline, the rest holes, as lists of (x, y); returns index
    triples into the flattened rings, anticlockwise, every ring edge kept."""
    P, idx = [], []
    for r in rings:
        idx.append(list(range(len(P), len(P) + len(r))))
        P += [tuple(p[:2]) for p in r]
    outer = idx[0]
    if _pf_area2(P, outer) < 0:
        outer = outer[::-1]
    holes = []
    for h in idx[1:]:
        holes.append(h if _pf_area2(P, h) < 0 else h[::-1])
    holes.sort(key=lambda h: -max(P[v][0] for v in h))
    ring = outer
    for h in holes:
        ring = _pf_bridge(P, ring, h)
    tris = _pf_earclip(P, ring)
    fixed = set()
    for r in idx:
        for i in range(len(r)):
            a, b = r[i], r[(i + 1) % len(r)]
            fixed.add((a, b) if a < b else (b, a))
    return _pf_flip(P, tris, fixed)


def _heal(m):
    """Split every face whose open edge runs through another face's corner (a
    T-junction slit), so seams share vertices; element spans stay whole."""
    Q = 1e-5
    total = 0
    for _ in range(6):
        K = [(round(p[0] / Q), round(p[1] / Q), round(p[2] / Q)) for p in m.verts]
        rep = {}
        for i, k in enumerate(K):
            rep.setdefault(k, i)
        cnt, own = {}, {}
        for fi, f in enumerate(m.faces):
            for e in range(3):
                a, b = K[f[e]], K[f[(e + 1) % 3]]
                if a != b:
                    u = (a, b) if a < b else (b, a)
                    cnt[u] = cnt.get(u, 0) + 1
                    own[u] = (fi, e)
        bnd = [u for u, n in cnt.items() if n == 1]
        C, tol, grid = 0.5, 2e-4, {}
        for k in set(k for u in bnd for k in u):
            p = m.verts[rep[k]]
            grid.setdefault(tuple(int(math.floor(p[c] / C)) for c in range(3)), []).append(k)
        splits = {}
        for u in bnd:
            fi, e = own[u]
            f = m.faces[fi]
            a, b = m.verts[f[e]], m.verts[f[(e + 1) % 3]]
            d = _sub(b, a)
            L2 = _dot(d, d)
            if L2 < 1e-12:
                continue
            lo = [int(math.floor((min(a[c], b[c]) - tol) / C)) for c in range(3)]
            hi = [int(math.floor((max(a[c], b[c]) + tol) / C)) for c in range(3)]
            hits = []
            for gx in range(lo[0], hi[0] + 1):
                for gy in range(lo[1], hi[1] + 1):
                    for gz in range(lo[2], hi[2] + 1):
                        for k in grid.get((gx, gy, gz), ()):
                            if k in u:
                                continue
                            w = m.verts[rep[k]]
                            t = _dot(_sub(w, a), d) / L2
                            if 1e-6 < t < 1.0 - 1e-6:
                                q = _sub(_v3(a, d, t), w)
                                if _dot(q, q) < tol * tol:
                                    hits.append((t, rep[k]))
            if hits and fi not in splits:
                splits[fi] = (e, sorted(hits))
        if not splits:
            break
        faces, zones, start = [], [], []
        for fi, f in enumerate(m.faces):
            start.append(len(faces))
            if fi not in splits:
                faces.append(f)
                zones.append(m.zones[fi])
                continue
            e, hits = splits[fi]
            chain = [f[e]] + [w for _t, w in hits] + [f[(e + 1) % 3]]
            for i in range(len(chain) - 1):
                faces.append((chain[i], chain[i + 1], f[(e + 2) % 3]))
                zones.append(m.zones[fi])
            total += len(chain) - 2
        start.append(len(faces))
        m.spans = {k: (start[f0], start[f1]) for k, (f0, f1) in m.spans.items()}
        m.crack = {g for fi in m.crack for g in range(start[fi], start[fi + 1])}
        m.faces, m.zones = faces, zones
    return total


def _cull_buried(m, reach=3.0):
    """Drop the faces of every loose piece (a rock, a platform, a wall set into the
    deck) that sit wholly under the map's own floor, sealed above and open to nothing below."""
    Q = 1e-4
    K = [(round(p[0] / Q), round(p[1] / Q), round(p[2] / Q)) for p in m.verts]
    par = {}

    def find(x):
        while par.setdefault(x, x) != x:
            par[x] = par[par[x]]
            x = par[x]
        return x

    for f in m.faces:
        a = find(K[f[0]])
        for i in f[1:]:
            b = find(K[i])
            if a != b:
                par[b] = a
    root = [find(K[f[0]]) for f in m.faces]
    size = {}
    for r_ in root:
        size[r_] = size.get(r_, 0) + 1
    main = max(size, key=size.get)
    C, grid = 1.0, {}
    for fi, f in enumerate(m.faces):
        if root[fi] != main:
            continue
        P = [m.verts[i] for i in f]
        for gx in range(int(math.floor(min(p[0] for p in P) / C)), int(math.floor(max(p[0] for p in P) / C)) + 1):
            for gy in range(int(math.floor(min(p[1] for p in P) / C)), int(math.floor(max(p[1] for p in P) / C)) + 1):
                grid.setdefault((gx, gy), []).append(fi)

    def column(x, y):
        """(height, facing up) of every main face over or under (x, y)."""
        out = []
        for fi in grid.get((int(math.floor(x / C)), int(math.floor(y / C))), ()):
            (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = [m.verts[i] for i in m.faces[fi]]
            d = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
            if abs(d) < 1e-12:
                continue
            a = ((y1 - y2) * (x - x2) + (x2 - x1) * (y - y2)) / d
            b = ((y2 - y0) * (x - x2) + (x0 - x2) * (y - y2)) / d
            if min(a, b, 1.0 - a - b) < -1e-9:
                continue
            out.append((a * z0 + b * z1 + (1.0 - a - b) * z2, d > 0.0))
        return out

    def hidden(p):
        col = column(p[0], p[1])
        above = [c for c in col if c[0] > p[2] + 1e-4]
        below = [c for c in col if c[0] < p[2] - 1e-4]
        if not above:
            return False
        top = min(above)
        if not top[1] or top[0] - p[2] > reach:
            return False
        return not below or not max(below)[1]

    under = {}
    for f in m.faces:
        for i in f:
            if i not in under:
                under[i] = hidden(m.verts[i])
    set_in = set(root[fi] for fi, f in enumerate(m.faces)
                 if root[fi] != main and not all(under[i] for i in f))   # it stands out of the floor
    keep = []
    for fi, f in enumerate(m.faces):
        P = [m.verts[i] for i in f]
        cen = tuple(sum(p[c] for p in P) / 3.0 for c in range(3))
        keep.append(root[fi] not in set_in or not (all(under[i] for i in f) and hidden(cen)))
    start, faces, zones = [], [], []
    for fi, f in enumerate(m.faces):
        start.append(len(faces))
        if keep[fi]:
            faces.append(f)
            zones.append(m.zones[fi])
    start.append(len(faces))
    m.spans = {k: (start[f0], start[f1]) for k, (f0, f1) in m.spans.items()}
    m.crack = {start[fi] for fi in m.crack if keep[fi]}
    dropped = len(m.faces) - len(faces)
    m.faces, m.zones = faces, zones
    return dropped


def _s3_patches(m, S3V):
    """The crack patch: the rectangle of deck cells is one polygon whose
    boundary is the grid's own vertices (so the patch welds to the deck with
    no duplicate and no T-junction) and whose holes are the network's
    islands; _fill2d triangulates the deck between."""
    L = S3["L"]
    cols = L["cols"]
    loops, lava, lip, ftris = _s3_net_mesh(m)
    holes, plates = [], []
    for ring in loops:
        P = [(m.verts[i][0], m.verts[i][1]) for i in ring]
        assert _s3c_simple(P), "s3 cracks: an outline crosses itself"
        area = 0.5 * sum(P[i][0] * P[(i + 1) % len(P)][1] - P[(i + 1) % len(P)][0] * P[i][1]
                         for i in range(len(P)))
        # the walk keeps the crack on its right: clockwise round a crack
        # network's outside (a hole in the deck), anticlockwise round a plate
        # of crust the cracks enclose (deck again, on its own)
        (holes if area < 0.0 else plates).append(ring)

    def fill(rings):
        flat = [i for ring in rings for i in ring]
        tri = _fill2d([[m.verts[i][:2] for i in ring] for ring in rings])
        return [(flat[a], flat[b], flat[c]) for a, b, c in tri if len({flat[a], flat[b], flat[c]}) == 3]
    stats = []
    for pr in _s3_patch_rects(L):
        ci, j0, j1 = pr["ci"], pr["j0"], pr["j1"]
        loop = [S3V(cols[i], j0) for i in ci]
        loop += [S3V(cols[ci[-1]], j) for j in range(j0 + 1, j1 + 1)]
        loop += [S3V(cols[i], j1) for i in reversed(ci[:-1])]
        loop += [S3V(cols[ci[0]], j) for j in range(j1 - 1, j0, -1)]
        tris = fill([loop] + holes)
        for ring in plates:
            tris += fill([ring])
        tris = _s3_refine(m, tris, S3_CRACK_REFINE)
        before = len(m.faces)
        for a, b, c in tris:
            m.tri(a, b, c, UP, ZONE_DECK)
        net = _s3_crack_network()
        stats.append(("network: %d cells, %d joins, %d fissures, %d plate(s) of crust enclosed"
                      % (len(net["cells"]), len(net["tree"]), len(net["fissures"]), len(plates)),
                      lava, lip, len(m.faces) - before, ftris, len(holes)))
    S3["crack_stats"] = stats
    S3["crack_islands"] = len(holes)
    return stats


def _s3_refine(m, tris, longest):
    """Longest-edge bisection until no edge is over `longest`: the two
    triangles on an edge split together, so the patch stays conforming, and
    an edge on the patch's boundary is a lattice edge or a crack edge, both
    already short, so the boundary never moves."""
    tris = [tuple(t) for t in tris]
    mids = {}

    def key(a, b):
        return (a, b) if a < b else (b, a)

    def length(a, b):
        return math.dist(m.verts[a], m.verts[b])
    changed = True
    while changed:
        changed = False
        by_edge = {}
        for ti, t in enumerate(tris):
            for e in range(3):
                by_edge.setdefault(key(t[e], t[(e + 1) % 3]), []).append(ti)
        worst = None
        for e, owners in by_edge.items():
            L = length(*e)
            if L > longest and (worst is None or L > worst[0]):
                worst = (L, e, owners)
        if worst is None:
            break
        _L, e, owners = worst
        if e not in mids:
            a, b = m.verts[e[0]], m.verts[e[1]]
            mids[e] = m.v(((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5))
        mid = mids[e]
        for ti in sorted(owners, reverse=True):
            t = tris[ti]
            apex = [v for v in t if v not in e][0]
            i = t.index(apex)
            u, v = t[(i + 1) % 3], t[(i + 2) % 3]      # the split edge, in the triangle's order
            tris[ti] = (apex, u, mid)
            tris.append((apex, mid, v))
        changed = True
    return tris


def _s3_crack_want(m, top, other):
    """The direction a fissure side's normal must face: into the cleft (from
    this side's top edge toward the other side's) and up."""
    a, c = m.verts[top], m.verts[other]
    dx, dy = c[0] - a[0], c[1] - a[1]
    L = math.hypot(dx, dy) or 1.0
    return (dx / L, dy / L, 0.6)


def _s3_poly_area(m, ids):
    pts = [m.verts[i] for i in ids]
    n = _newell(pts)
    return 0.5 * math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])


# ---- the plan: grid -> Godot ------------------------------------------------

def _s3_plan(b, rho):
    """Godot plan (gx, gz) of a grid point."""
    x, y = S3["deck_xy"](S3["L"]["T"](b), rho)
    return x, -y


def _s3_grid_of(gx, gz):
    """A Godot plan point back to the grid: (bearing, radius). The grid's
    interior is true polar, so this is exact."""
    return math.degrees(math.atan2(gz, gx)) % 360.0, math.hypot(gx, gz)


def _s3_facing(gx, gz):
    """A pad's launch direction in the Godot plan: the tangent toward higher
    bearing, turned S3_YAW_IN toward the axis."""
    a = math.atan2(gz, gx) + math.radians(S3_YAW_IN)
    return -math.sin(a), math.cos(a)


def _s3_land(o, f, v):
    """Where a body launched from plan point o along f at v m/s lands, on the
    flat deck: the 45 degree range v^2/g."""
    R = v * v * math.sin(math.radians(2.0 * S3_ANGLE)) / S3_G
    return o[0] + R * f[0], o[1] + R * f[1]


def _s3_bake_land(o, f, v):
    """Where RingBake's ballistic flight ends: it takes off from the plate's
    BACK edge, half a plate behind the origin (pad_takeoff), and its air
    control never engages above max_air_speed, so this is the exact point
    the bake tests for a live pad."""
    R = v * v * math.sin(math.radians(2.0 * S3_ANGLE)) / S3_G - 0.5 * S3_PAD
    return o[0] + R * f[0], o[1] + R * f[1]


def _s3_pads():
    """Every pad's Godot plan geometry: origin, facing, the shipped launch
    speed and both landings. Cached."""
    if "pads" in S3:
        return S3["pads"]
    out = []
    for pad in S3["lay"]["pads"]:
        o = _s3_plan(pad["b"], pad["rho"])
        f = _s3_facing(*o)
        v = S3_LAUNCH
        land = _s3_land(o, f, v)
        p = dict(pad)
        p.update(o=o, f=f, v=v, land=land, land_grid=_s3_grid_of(*land),
                 bake_land=_s3_bake_land(o, f, v),
                 name="LavaCrack_r%02d_c%d_%03ddeg" % (pad["row"], pad["col"], round(pad["b"])))
        out.append(p)
    S3["pads"] = out
    return out


def _s3_pad_transform(p):
    """The pad node's Godot Transform3D: it launches along local -Z, so the
    basis' third COLUMN is minus the facing and the .tscn's twelve floats are
    that basis by ROWS, then the origin."""
    (ox, oz), (fx, fz) = p["o"], p["f"]
    return ("Transform3D(%.6f, 0, %.6f, 0, 1, 0, %.6f, 0, %.6f, %.4f, %.3f, %.4f)"
            % (-fz, -fx, fx, -fz, ox, DECK_Z, oz))


def _s3_box_dist(p, gx, gz):
    """Plan distance from a point to a pad's trigger box (0 inside)."""
    dx, dz = gx - p["o"][0], gz - p["o"][1]
    fx, fz = p["f"]
    along, across = dx * fx + dz * fz, dx * -fz + dz * fx
    return math.hypot(max(abs(along) - p["hz"], 0.0), max(abs(across) - p["hx"], 0.0))


def _s3_scene_block():
    """The .tscn node block for the section's pads, one node per pad under
    Sections/S3_Minefield. unique_id is a stable hash of the name."""
    import hashlib
    lines = []
    for p in _s3_pads():
        uid = (int(hashlib.md5(p["name"].encode()).hexdigest()[:8], 16) & 0x3fffffff) | 1
        lines.append('[node name="%s" parent="Sections/S3_Minefield" unique_id=%d '
                     'instance=ExtResource("23_lava_crack_scene")]' % (p["name"], uid))
        lines.append("transform = " + _s3_pad_transform(p))
        if p["jump"]:
            lines.append("footprint_metres = Vector3(%.1f, %.1f, %.1f)" % (S3_PAD, S3_JUMP_PAD_H, S3_PAD))
        lines.append("")
    return "\n".join(lines)


# ---- proofs -----------------------------------------------------------------

def _s3_prove_path():
    """Walk the section on a lattice of the grid frame: a body's centre may
    stand where it is a radius clear of the lip, the outer wall, the half
    wall's rock and every pad's trigger box. Entry (bearing < 143.5) must
    reach exit (> 201.5) with the three jump pads passable, and must NOT with
    them blocked -- so the only way through is the path and the pads on it
    are jumped, not walked round. Returns (length with jumps, reachable
    without jumps)."""
    from collections import deque
    lay = S3["lay"]
    pads = _s3_pads()
    by_cell = {}
    for p in pads:
        by_cell.setdefault((p["row"], p["col"]), []).append(p)
    step_b = math.degrees(S3_BFS / S3_LANE_R)
    nb = int((S3_EXT[1] + 0.5 - (S3_EXT[0] - 0.5)) / step_b) + 1
    nr = int((OUTER_R - INNER_R) / S3_BFS) + 1
    row_step, r0 = lay["step"], lay["rows"][0]
    keep = S3_WALL_FOOT + S3_BODY_R
    free = bytearray(nb * nr)          # 1 free, 2 a jump pad's keep-out (passable when jumped)
    T = S3["L"]["T"]
    for ib in range(nb):
        b = S3_EXT[0] - 0.5 + ib * step_b
        t = T(b)
        pa, pb = S3["deck_xy"](t, INNER_R), S3["deck_xy"](t, OUTER_R)
        ri = int(round((b - r0) / row_step))
        cand = []
        for rr in (ri - 1, ri, ri + 1):
            for cc in range(len(S3_COLS)):
                cand += by_cell.get((rr, cc), [])
        for ir in range(nr):
            rho = INNER_R + ir * S3_BFS
            if rho < INNER_R + S3_BODY_R or rho > OUTER_R - S3_BODY_R:
                continue
            if lay["dist"](b, rho) < keep:
                continue
            fr = (rho - INNER_R) / (OUTER_R - INNER_R)
            gx = pa[0] + fr * (pb[0] - pa[0])
            gz = -(pa[1] + fr * (pb[1] - pa[1]))
            state = 1
            for p in cand:
                if _s3_box_dist(p, gx, gz) < S3_BODY_R:
                    state = 2 if p["jump"] else 0
                    if state == 0:
                        break
            free[ib * nr + ir] = state

    def run(jump_ok):
        dist = [None] * (nb * nr)
        dq = deque()
        for ir in range(nr):
            for ib in range(int(1.0 / step_b)):     # the half degree before the section
                if free[ib * nr + ir] == 1:
                    dist[ib * nr + ir] = 0.0
                    dq.append((ib, ir))
        best = None
        goal_ib = nb - int(1.0 / step_b)
        while dq:
            ib, ir = dq.popleft()
            d = dist[ib * nr + ir]
            if ib >= goal_ib:
                best = d if best is None else min(best, d)
                continue
            rho = INNER_R + ir * S3_BFS
            du = S3_BFS * rho / S3_LANE_R
            for db, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                jb, jr = ib + db, ir + dr
                if not (0 <= jb < nb and 0 <= jr < nr):
                    continue
                st = free[jb * nr + jr]
                if st == 0 or (st == 2 and not jump_ok):
                    continue
                nd = d + (du if db else S3_BFS)
                if dist[jb * nr + jr] is None or nd < dist[jb * nr + jr] - 1e-9:
                    dist[jb * nr + jr] = nd
                    dq.append((jb, jr))
        return best
    return run(True), run(False)


def _s3_prove_wall():
    """The wall as BUILT: a ray down onto the rock mesh every 0.05 m along
    the crest line must land inside the sight window at that bearing -- no
    gap, no dip under the crouched line, no crag over the standing line.
    Returns (crest metres, samples, min hit, max hit, where, where, samples
    outside the window, mean, std, samples on the crest within 0.01 of the
    spec)."""
    import mathutils
    ob = bpy.data.objects[OBJECT_NAME]
    wall = S3["lay"]["wall"]
    lo, hi, n, lo_at, hi_at, bad, spur, on_spec = 9e9, -9e9, 0, 0.0, 0.0, 0, 0, 0
    u0, u1 = _s3_arc(S3_FIELD[0]), _s3_arc(S3_FIELD[1])
    m = int((u1 - u0) / 0.05) + 1
    zs = []
    for i in range(m):
        b = S3_FIELD[0] + (S3_FIELD[1] - S3_FIELD[0]) * i / (m - 1.0)
        gx, gz = _s3_plan(b, wall["rc"](b))
        hit, loc, _nrm, _idx = ob.ray_cast(mathutils.Vector((gx, -gz, DECK_Z + 6.0)),
                                          mathutils.Vector((0.0, 0.0, -1.0)))
        z = (loc.z - DECK_Z) if hit else -9.0
        L, U = wall["window"](b)
        if not (L <= z <= U):
            # the S3|S4 divider's own lip spur (unchanged, outside this
            # section's rock) rises over the wall's 200 end: reported apart
            if min(b - S3_FIELD[0], S3_FIELD[1] - b) * math.radians(1.0) * S3_LANE_R <= S3_WALL_END_SPUR:
                spur += 1
            else:
                bad += 1
                print("MDL note s3 wall sample outside the window: %.2f deg, ray %.3f, window %.3f..%.3f, "
                      "spec crest %.3f" % (b, z, L, U, wall["crest"](b)))
        if abs(z - wall["crest"](b)) <= 0.01:
            on_spec += 1
        zs.append(z)
        if z < lo:
            lo, lo_at = z, b
        if z > hi:
            hi, hi_at = z, b
        n += 1
    mean = sum(zs) / n
    std = math.sqrt(sum((z - mean) ** 2 for z in zs) / n)
    return u1 - u0, n, lo, hi, lo_at, hi_at, bad, mean, std, on_spec, spur


def _s3_sight(ob, target, standing):
    """Whether the guard's eye sees a world point, raycast on the BUILT rock:
    (blocked, metres the straight line passes under (negative) or over the
    wall's crest at the top edge that binds: the inner edge for a crouched
    body that must be hidden, the outer edge for a standing one that must be
    seen)."""
    import mathutils
    wall = S3["lay"]["wall"]
    eye = mathutils.Vector((0.0, 0.0, S3_EYE_Z))
    tgt = mathutils.Vector(target)
    d = tgt - eye
    hit, loc, _n, _i = ob.ray_cast(eye, d.normalized())
    blocked = hit and (loc - eye).length < d.length - 0.02
    b = _bear_deg(math.atan2(tgt.y, tgt.x))
    edge = wall["rc"](b) + (wall["T"](b) if standing else -wall["T"](b))
    f = edge / math.hypot(tgt.x, tgt.y)
    margin = (S3_EYE_Z + f * (tgt.z - S3_EYE_Z)) - (DECK_Z + wall["crest"](b))
    return blocked, margin


def _s3_prove_cover():
    """Raycast from the guard's eye against the BUILT rock, every row: a body
    on the path (against the wall side of its cell, its centre, its far side),
    crouched (capsule top 1.2 m) and standing (1.8 m); and a body at a pad's
    apex over each column. Returns per-row (bearing, crouched hidden at all
    three, standing seen at all three, worst crouched margin, worst standing
    margin), the count of apex bodies seen of those tested, and the fine
    proof: the same three stances every 0.25 m along the whole path (both
    columns where the path steps across), as (samples, crouched seen,
    standing hidden) -- the ragged crest must hold BETWEEN the rows too."""
    ob = bpy.data.objects[OBJECT_NAME]
    lay = S3["lay"]
    wall = lay["wall"]
    out = []
    apex_seen = apex_n = 0
    for i, b in enumerate(lay["rows"]):
        rp = S3_COLS[lay["spans"][i][0]]
        hidden, seen, worst_c, worst_s = True, True, -9e9, -9e9
        for rho in (rp - 0.9, rp, rp + 0.9):
            gx, gz = _s3_plan(b, rho)
            for h, crouched in ((S3_CROUCH, True), (S3_STAND, False)):
                blocked, margin = _s3_sight(ob, (gx, -gz, DECK_Z + h), False)
                if crouched:
                    hidden = hidden and blocked
                    worst_c = max(worst_c, margin)
                else:
                    seen = seen and blocked           # "seen" now records: standing HIDDEN
                    worst_s = max(worst_s, margin)
        out.append((b, hidden, seen, worst_c, worst_s))
        for rc in S3_COLS:                       # a launched body at its apex, feet up
            gx, gz = _s3_plan(b, rc)
            blocked, _m = _s3_sight(ob, (gx, -gz, DECK_Z + S3_APEX), True)
            apex_n += 1
            apex_seen += 0 if blocked else 1
            if blocked:
                print("MDL note s3 apex HIDDEN at %.2f deg r %.2f, crest %.3f" % (b, rc, wall["crest"](b)))
    fine_n = fine_c = fine_s = fine_spur = 0
    step_b = math.degrees(0.25 / S3_LANE_R)
    rows, half = lay["rows"], 0.5 * lay["step"]
    nb = int((S3_FIELD[1] - S3_FIELD[0]) / step_b) + 1
    for k in range(nb):
        b = S3_FIELD[0] + k * step_b
        cols = set()
        for i, rb in enumerate(rows):
            if abs(b - rb) <= half + 1e-9:
                cols.update(range(lay["spans"][i][0], lay["spans"][i][1] + 1))
        for c in cols:
            rp = S3_COLS[c]
            for rho in (rp - 0.9, rp, rp + 0.9):
                gx, gz = _s3_plan(b, rho)
                fine_n += 1
                blocked, _m = _s3_sight(ob, (gx, -gz, DECK_Z + S3_CROUCH), False)
                fine_c += 0 if blocked else 1
                blocked, _m = _s3_sight(ob, (gx, -gz, DECK_Z + S3_STAND), False)
                fine_s += 0 if blocked else 1
                if not blocked:
                    print("MDL note s3 standing body SEEN at %.2f deg r %.2f (column %d), crest there %.3f, "
                          "window %.3f..%.3f" % (b, rho, c, wall["crest"](b), *wall["window"](b)))
    return out, apex_seen, apex_n, (fine_n, fine_c, fine_s, fine_spur)


def _s3_prove_launch():
    """Where every flight ends, and that the three JUMP pads are live for
    RingBake. A flight either (deck) lands on this deck before the S3|S4
    divider's near face, a body radius clear of both rims; or it reaches the
    divider: (caught) with the body's top above the mouth's head, or outside
    the mouth's width, so the divider's rock stops it and it drops on the
    deck in front; or (mouth) low enough and central enough to pass the
    mouth, in which case it must land short of S4's lava. A jump pad's
    back-edge flight must also land on open mesh at least S3_BAKE_KEEP from
    every rim, wall foot and other pad's plate (the grid pads land on pads,
    which is the minefield; the bake carves those and the bots walk the
    path). Returns (bad names, deck/caught/mouth counts, nearest rim past
    the body, divider face bearing, lava bearing, the jump pads' least
    clearance and which)."""
    lay = S3["lay"]
    pads = _s3_pads()
    lava_b = _s4_layout()["cut_entry"]
    face_b = lava_b - math.degrees(1.0 / S3_LANE_R)   # the dividers are lip walls now
                                # (r < 48.2): nothing catches a flight, so a landing
                                # is on this deck a metre short of S4's lava, or bad
    vh = S3_LAUNCH * math.cos(math.radians(S3_ANGLE))
    vv = S3_LAUNCH * math.sin(math.radians(S3_ANGLE))
    bad, rim, jclear, jwho = [], 9e9, 9e9, ""
    n_deck = n_caught = n_mouth = 0
    for p in pads:
        b, rho = p["land_grid"]
        if b <= face_b:
            rim = min(rim, rho - INNER_R - S3_BODY_R, OUTER_R - rho - S3_BODY_R)
            if rho < INNER_R + S3_BODY_R or rho > OUTER_R - S3_BODY_R:
                bad.append(p["name"])
            else:
                n_deck += 1
        else:
            bad.append(p["name"])                              # into S4's lava
        if not p["jump"]:
            continue
        gx, gz = p["bake_land"]
        bb, br = _s3_grid_of(gx, gz)
        clear = min(br - INNER_R, OUTER_R - br, lay["dist"](bb, br) - S3_WALL_FOOT)
        for q in pads:
            if q is not p:
                clear = min(clear, _s3_box_dist(q, gx, gz))
        if clear < jclear:
            jclear, jwho = clear, p["name"]
        if clear < S3_BAKE_KEEP or bb > face_b - math.degrees(S3_BAKE_KEEP / S3_LANE_R):
            bad.append(p["name"])
    return bad, n_deck, n_caught, n_mouth, rim, face_b, lava_b, jclear, jwho


def _s3_jump_numbers(box_h):
    """A running jump over a pad of trigger height box_h on flat deck. The
    capsule overlaps the box in plan over 2 * (box half extent along the
    path + body radius); feet must be over box_h for all of it. Returns
    (overlap span, window where feet clear box_h, clearance at the span's
    ends for a jump centred on the pad); a negative clearance or a window
    shorter than the span is a pad that cannot be jumped."""
    th = math.radians(S3_YAW_IN)
    half = 0.5 * S3_PAD * (math.cos(th) + math.sin(th))
    span = 2.0 * (half + S3_BODY_R)
    a, c = S3_JUMP_V / S3_RUN, S3_G / (2.0 * S3_RUN * S3_RUN)   # feet y(s) = a s - c s^2
    disc = a * a - 4.0 * c * box_h
    window = math.sqrt(disc) / c if disc > 0.0 else 0.0
    apex_s = a / (2.0 * c)
    s = apex_s - 0.5 * span
    clear = (a * s - c * s * s) - box_h
    return span, window, clear


def _s3_stats():
    """Every number the section claims, printed from the built model."""
    lay = S3["lay"]
    pads = _s3_pads()
    L = S3["L"]
    n_jump = sum(1 for p in pads if p["jump"])
    print("MDL STATS s3 grid %d rows x %d columns = %d cells, %d pads (%d jump, all at %.0f m/s), "
          "%d path cells cleared, row pitch %.2f deg = %.2f m at r %.0f, column pitch %.2f m"
          % (S3_ROWS, len(S3_COLS), S3_ROWS * len(S3_COLS), len(pads), n_jump, S3_LAUNCH,
             S3_ROWS * len(S3_COLS) - len(pads) + n_jump, lay["step"],
             math.radians(lay["step"]) * S3_LANE_R, S3_LANE_R, S3_COLS[1] - S3_COLS[0]))
    print("MDL STATS s3 mesh %d columns x %d stations, collider %d tris, flat deck at y=%.1f, "
          "no lava and no trap volume in the section"
          % (len(L["cols"]), len(L["stations"]), S3.get("coll_tris", 0), DECK_Z))
    for p in pads:
        lb, lr = p["land_grid"]
        print("MDL STATS s3 pad %s %s%s | lands bearing %.2f r %.2f%s"
              % (p["name"], _s3_pad_transform(p),
                 " box_h=%.1f" % S3_JUMP_PAD_H if p["jump"] else "", lb, lr,
                 " JUMP" if p["jump"] else ""))
    gap, gap_who = 9e9, ""
    for i, p in enumerate(pads):
        for q in pads[i + 1:]:
            if abs(p["row"] - q["row"]) <= 1 and abs(p["col"] - q["col"]) <= 1:
                fx, fz = q["f"]
                for su in (-q["hz"], q["hz"]):
                    for sv in (-q["hx"], q["hx"]):
                        cx = q["o"][0] + su * fx + sv * -fz
                        cz = q["o"][1] + su * fz + sv * fx
                        d = _s3_box_dist(p, cx, cz)
                        if d < gap:
                            gap, gap_who = d, p["name"] + "/" + q["name"]
    wall_gap, wall_who = 9e9, ""
    for p in pads:
        fx, fz = p["f"]
        for su in (-p["hz"], 0.0, p["hz"]):
            for sv in (-p["hx"], 0.0, p["hx"]):
                cx = p["o"][0] + su * fx + sv * -fz
                cz = p["o"][1] + su * fz + sv * fx
                b, rho = _s3_grid_of(cx, cz)
                d = lay["dist"](b, rho) - S3_WALL_FOOT
                if d < wall_gap:
                    wall_gap, wall_who = d, p["name"]
    print("MDL STATS s3 pads: nearest corner-to-box gap between neighbours %.3f m (%s), nearest box "
          "point to the wall's widest foot %.3f m (%s); both must be > 0 and under a body's %.1f m"
          % (gap, gap_who, wall_gap, wall_who, 2.0 * S3_BODY_R))
    with_j, without_j = _s3_prove_path()
    print("MDL STATS s3 path: entry->exit %s with the jump pads jumped; %s with them blocked "
          "(the pads on the path cannot be walked round)"
          % ("%.1f m walkable" % with_j if with_j is not None else "NOT WALKABLE",
             "STILL REACHABLE" if without_j is not None else "unreachable"))
    for box_h, what in ((S3_JUMP_PAD_H, "a jump pad"), (S3_PAD_H, "an ordinary pad")):
        span, window, clear = _s3_jump_numbers(box_h)
        print("MDL STATS s3 jump over %s (box %.1f m): capsule overlaps the box for %.2f m, feet are "
              "over it for %.2f m of the flight, clearance %+.3f m at the overlap's ends (centred "
              "jump), take-off window %+.2f m -> %s"
              % (what, box_h, span, window, clear, window - span,
                 "CLEARED" if clear > 0.0 and window > span else "cannot be jumped"))
    length, n, lo, hi, lo_at, hi_at, bad, mean, std, on_spec, spur = _s3_prove_wall()
    wall = lay["wall"]
    ws = [wall["window"](b) for b in (S3_FIELD[0] + (S3_FIELD[1] - S3_FIELD[0]) * k / 200.0
                                      for k in range(201))]
    print("MDL STATS s3 wall: %.1f m of ragged crest along the pit edge, %d ray samples down the built "
          "rock every 0.05 m: %.3f (at %.2f deg)..%.3f m (at %.2f deg) over the deck, mean %.3f, std "
          "%.3f, %d samples outside the sight window (must be 0; %d more in the last %.2f m at the 200 end "
          "are the S3|S4 divider's own lip spur over the wall's end, unchanged), %d on the spec's crest "
          "within 0.01 m; window (standing line at the inner top edge .. apex line at the outer) "
          "%.2f..%.2f m at the middle-column rows, %.2f..%.2f m at the inner-column rows"
          % (length, n, lo, lo_at, hi, hi_at, mean, std, bad, spur, S3_WALL_END_SPUR, on_spec,
             ws[0][0], ws[0][1], ws[-1][0], ws[-1][1]))
    for stat in S3.get("crack_stats", []):
        net = _s3_crack_network()
        per = {}
        for f in net["fissures"]:
            per[f["cell"]] = per.get(f["cell"], 0) + 1
        parent = {cc: cc for cc in net["cells"]}

        def find(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x
        for A, B in net["tree"]:
            parent[find(A)] = find(B)
        blocks = len(set(find(cc) for cc in net["cells"]))
        print("MDL STATS s3 cracks: %s, %d island(s) of crack surface (one per contiguous block of pad "
              "cells: %d block(s)), lava %.1f m2 (emissive: floor and lower sides), dark lip %.1f m2, "
              "deck patch %d tris, fissure %d tris; fissures per cell %d..%d"
              % (stat[0], stat[5], blocks, stat[1], stat[2], stat[3], stat[4],
                 min(per.values()), max(per.values())))
    cover, apex_seen, apex_n, fine = _s3_prove_cover()
    ok_c = sum(1 for c in cover if c[1])
    ok_s = sum(1 for c in cover if c[2])
    print("MDL STATS s3 cover: eye (0, %.2f, 0) raycast on the built rock, 3 stances x %d rows on the "
          "path: crouched capsule (%.1f m) hidden in %d/%d rows, standing (%.1f m) HIDDEN in %d/%d; the "
          "sight line to a standing top is under the crest by >= %.3f m (inner top edge); a body at a "
          "pad's apex (%.2f m up) seen in %d/%d column-rows (must be all); every 0.25 m along the whole "
          "path, 3 stances: %d samples, crouched seen in %d, standing seen in %d (both must be 0)"
          % (S3_EYE_Z, len(cover), S3_CROUCH, ok_c, len(cover), S3_STAND, ok_s, len(cover),
             -max(c[4] for c in cover), S3_APEX, apex_seen, apex_n, fine[0], fine[1], fine[2]))
    bad, n_deck, n_caught, n_mouth, rim, face_b, lava_b, jclear, jwho = _s3_prove_launch()
    print("MDL STATS s3 launch: %d flights land on this deck by %.2f deg, a metre short of S4's lava at "
          "%.1f deg (nearest rim %.2f m past the body); no divider catches a flight any more (%d caught, "
          "%d through a mouth); the %d jump pads are live for the bake, their back-edge landings >= %.2f m "
          "from any rim, wall foot or plate (least %.2f m, %s)%s"
          % (n_deck, face_b, lava_b, rim, n_caught, n_mouth, n_jump, S3_BAKE_KEEP, jclear, jwho,
             "" if not bad else " BAD (flights into S4's lava): " + " ".join(bad)))
    out_dir = "."
    for k, a in enumerate(sys.argv):
        if a == "--spec" and k + 1 < len(sys.argv):
            with open(sys.argv[k + 1]) as fh:
                out_dir = json.load(fh).get("out_dir", ".")
    path = os.path.join(out_dir, "map_base_s3_pads.tscn.part")
    with open(path, "w") as fh:
        fh.write(_s3_scene_block())
    print("MDL note s3 pad nodes -> %s" % path)


# =============================================================================
# S1 -- THE SPIRES (game bearings 15..60): a stalactite cave grown into the
# rock. Between the deck columns nearest S1_EXT the deck, the ceiling, the
# outer wall and the pit lip are re-laid on a finer grid whose boundary
# columns keep the coarse chains, so nothing outside moves; stalagmites,
# stalactites and full columns are welded into that grid through holes.
# Its own seed; the main rock RNG is never consulted in here.
# =============================================================================

S1_EXT = (12.0, 63.0)        # the section plus its ease-in, game bearings
S1_FADE = 4.0                # degrees the relief eases in over at each end
S1_SEED = 3170519
S1_CELL = 0.70               # tangential cell at the lane radius, metres
S1_NS = 16                   # deck stations, lip -> foot
S1_NC = 11                   # ceiling stations, lip -> wall head
S1_CEIL_ROWS = (1, 3, 5, 7, 9)   # ceiling stations drawn, of S1_NC; every other sub-column
S1_CORNER = 0.6              # a station this far either side of the ceiling-wall corner
S1_WALL_H = (1.8, 3.4, 5.2, 7.0)     # wall rows, metres below the ceiling
S1_DECK_AMP, S1_DECK_L = 0.22, (2.5, 6.0)  # flowstone undulation: peak, wavelengths
S1_MOUND = (0.05, 0.10, 1.0, 2.5)   # a low flowstone mound under each fixture: height a + b*R, radius a + b*R
S1_CEIL_SAG, S1_CEIL_L = 0.40, (3.0, 6.0)  # the ceiling sags 0..2x this
S1_DRIP = (0.15, 0.45, 0.9, 1.5)           # drip cone round a stalactite: height lo/hi, radius lo/hi
S1_FILLET = 1.2              # ceiling-to-wall corner round-over radius
S1_RIB = {"depth": (0.3, 0.8), "width": (0.3, 0.55), "gap": (1.0, 2.2), "wander": 0.25}
S1_FOREST_N = 26             # fixtures thrown at the deck, columns included ...
S1_FOREST_COLS = 4           # ... this many floor-to-ceiling columns ...
S1_FOREST_MIX = (0.45, 0.35, 0.20)   # ... the rest short / medium / tall
S1_FOREST_B = (15.5, 59.5)   # thrown between these bearings ...
S1_FOREST_R = (47.8, 56.2)   # ... and radii: the whole deck
S1_CLUMPS = 3                # small ones set at the feet of medium or tall ones
S1_SHORT = (1.2, 2.4, 0.12, 0.20)    # height lo/hi, body radius lo/hi
S1_MEDIUM = (2.4, 3.8, 0.18, 0.28)
S1_TALL = (3.8, 6.0, 0.22, 0.32)
S1_COVER_H = 2.4             # fixtures this tall or more are cover, and keep S1_FOREST_GAP apart
S1_FOOT_GAP = 0.5            # clear air between any two feet at 0.3 m: skirts may touch, shafts never
S1_FOREST_GAP = 2.4          # clear air between two cover fixtures at chest height
S1_ROUTE_GAP = 1.8           # ... and between their feet: a body and a half (0.7 m runner) passes anywhere
S1_CHEST = 1.3               # chest height: no fixture wider than 1.0 m here
S1_FLARE = 2.6               # a foot skirt: this times the shaft radius at the floor, an apron tangent to it ...
S1_SKIRT = (0.5, 1.0, 0.3)   # ... steepening into the shaft over clamp(H * c, lo, hi) metres of height
S1_SKIRT_P = 2.5             # the apron: height = skirt * (1 - w) ** p over the radial fraction w
S1_RIM_JITTER = 0.3          # the skirt's outline wanders this much of its extent, vertex to vertex
S1_RIPPLE = (0.55, 0.5, 0.02, 0.06, 0.25, 0.08)   # floor ripples: first at this beyond the skirt, spacing, height range, half width, wander
S1_RIPPLE_R = 0.24           # feet of shafts this thick or more get ripples
S1_RIDGE_Z = 0.8             # drip ridges start above this height
S1_COL_R = (0.22, 0.32)      # full column waist radius: 0.45..0.65 m across
S1_OVER = 3                  # the tallest stalagmites get a stalactite dripping over them
S1_TITES = (22, 1.0, 5.5, 0.10, 0.30)    # stalactites: count, length lo/hi, base radius lo/hi
S1_TITE_FLARE = 2.0
S1_TIP_CLEAR = 3.0           # a stalactite tip keeps this over the deck: a jumping body (1.8 + 1.11 m) passes anywhere
S1_LOD = {                   # drawn sides, fillet rings (radial fraction, edge -> shaft), body rings (height fraction)
    "short": (7, (1.0, 0.8, 0.5, 0.22), (0.48, 0.66, 0.84, 1.0)),
    "medium": (8, (1.0, 0.8, 0.5, 0.22), (0.42, 0.58, 0.74, 0.9, 1.0)),
    "tall": (9, (1.0, 0.8, 0.5, 0.22), (0.4, 0.54, 0.68, 0.82, 0.93, 1.0)),
    "column": (10, (1.0, 0.8, 0.5, 0.22), (0.3, 0.45, 0.6, 0.75, 0.87, 0.95, 1.0)),
}
S1_TITE_LOD = ((5, 6), (0.0, 0.045, 0.14, 0.4, 0.7, 1.0))   # sides thin / thick, rings
S1_RIPPLE_STEP = 1.6         # ripple nodes this far apart round a foot
S1_EYE_Z = 27.0
S1_REVIEW = True             # review-only lights and a player proxy; never exported
S1_RREF = 0.5 * (INNER_R + OUTER_R)
S1_SIGHT_H = (0.2, 0.6, 1.0, 1.4, 1.8)   # a body is hidden when every one of these is
S1_SAMPLE = 0.5              # the deck is sampled on this grid, r 48..56 ...
S1_SAMPLE_R = (48.0, 56.0)
S1_SHIFT = 2.5               # ... from the centre eye and from eyes this far to either side
S1_BANDS = ((47.3, 51.5), (49.8, 54.2), (52.5, 56.7))   # inner, middle, outer routes (they may weave)
S1 = {}                      # handed from the sculpt to the collider, stats and renders


def _s1_waves(r, L, n=6):
    """A seeded sum of n plane waves, about -1..1, wavelengths in L."""
    ws = []
    for _ in range(n):
        a, wl = r.f() * TWO_PI, L[0] + r.f() * (L[1] - L[0])
        ws.append((math.cos(a) * TWO_PI / wl, math.sin(a) * TWO_PI / wl, r.f() * TWO_PI, 0.5 + r.f()))
    k = 1.0 / sum(w[3] for w in ws)

    def f(x, y):
        return k * sum(w[3] * math.sin(w[0] * x + w[1] * y + w[2]) for w in ws)
    return f


def _s1_grooves(r, s0, s1, spec):
    """Rounded vertical ribs on a wall: the recess between them, metres, at (arc, z)."""
    gs = []
    s = s0 + r.f() * spec["gap"][1]
    while s < s1:
        gs.append((s, spec["depth"][0] + r.f() * (spec["depth"][1] - spec["depth"][0]),
                   spec["width"][0] + r.f() * (spec["width"][1] - spec["width"][0]),
                   TWO_PI / (2.5 + 3.0 * r.f()), r.f() * TWO_PI))
        s += spec["gap"][0] + r.f() * (spec["gap"][1] - spec["gap"][0])
    wander = spec["wander"]

    def f(s, z):
        rec = 0.0
        for (sc, d, w, k, ph) in gs:
            ds = s - sc - wander * math.sin(k * z + ph)
            if abs(ds) < 3.0 * w:
                rec += d * math.exp(-(ds / w) ** 2)
        return min(rec, spec["depth"][1])
    return f


def _s1_delaunay(pts):
    """Bowyer-Watson over a few dozen 2-D points; index triples."""
    n = len(pts)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    cx, cy = 0.5 * (min(xs) + max(xs)), 0.5 * (min(ys) + max(ys))
    d = 60.0 * max(max(xs) - min(xs), max(ys) - min(ys)) + 1.0
    P = list(pts) + [(cx - d, cy - d), (cx + d, cy - d), (cx, cy + d)]
    tris = [(n, n + 1, n + 2)]

    def inside(t, p):
        ax, ay = P[t[0]][0] - p[0], P[t[0]][1] - p[1]
        bx, by = P[t[1]][0] - p[0], P[t[1]][1] - p[1]
        cx_, cy_ = P[t[2]][0] - p[0], P[t[2]][1] - p[1]
        det = ((ax * ax + ay * ay) * (bx * cy_ - cx_ * by)
               - (bx * bx + by * by) * (ax * cy_ - cx_ * ay)
               + (cx_ * cx_ + cy_ * cy_) * (ax * by - bx * ay))
        orient = (bx - ax) * (cy_ - ay) - (by - ay) * (cx_ - ax)
        return det * orient > 0.0

    for i in range(n):
        p = P[i]
        bad = [t for t in tris if inside(t, p)]
        count = {}
        for t in bad:
            for e in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
                key = (min(e), max(e))
                count[key] = count.get(key, 0) + 1
        keep = [t for t in tris if t not in bad]
        for t in bad:
            for e in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
                if count[(min(e), max(e))] == 1:
                    keep.append((e[0], e[1], i))
        tris = keep
    return [t for t in tris if max(t) < n]


def _s1_seg_dist(p, a, b):
    """Distance from p to the segment a-b, all 2-D."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 < 1e-12 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L2))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


def _s1_inpoly(p, poly):
    x, y = p
    inside = False
    n = len(poly)
    for i in range(n):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % n]
        if (y0 > y) != (y1 > y):
            if x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
                inside = not inside
    return inside


def _s1_fill(m, loop, rings, want, zone, tag, extra=()):
    """Triangulate a rectangular hole (loop: [(param, id)] round it) minus the
    rings inside it (each [(param, id)], closed), welding every vertex; extra
    points inside the hole (the grid nodes clear of the rings) keep the relief.
    Every loop and ring edge must come out of the triangulation, or the build fails."""
    pts, ids = [p for p, _ in loop], [i for _, i in loop]
    spans = []
    for ring in rings:
        k0 = len(pts)
        pts += [p for p, _ in ring]
        ids += [i for _, i in ring]
        spans.append((k0, len(pts)))
    pts += [p for p, _ in extra]
    ids += [i for _, i in extra]
    tris = _s1_delaunay(pts)
    polys = [[pts[k] for k in range(k0, k1)] for (k0, k1) in spans]
    keep, edges = [], set()
    for t in tris:
        c = (sum(pts[k][0] for k in t) / 3.0, sum(pts[k][1] for k in t) / 3.0)
        if any(_s1_inpoly(c, poly) for poly in polys):
            continue
        keep.append(t)
        for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            edges.add((min(a, b), max(a, b)))
    nb = len(loop)
    chains = [[(k, (k + 1) % nb) for k in range(nb)]]
    for (k0, k1) in spans:
        chains.append([(k, k0 + (k - k0 + 1) % (k1 - k0)) for k in range(k0, k1)])
    for chain in chains:
        for a, b in chain:
            if (min(a, b), max(a, b)) not in edges:
                raise RuntimeError("S1 fill %s: edge %d-%d missing" % (tag, a, b))

    def area(poly):
        return 0.5 * abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1]
                             - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly))))
    want_a = area(pts[:nb]) - sum(area(p) for p in polys)
    got_a = sum(area([pts[k] for k in t]) for t in keep)
    if abs(got_a - want_a) > 1e-6 * max(1.0, want_a):
        raise RuntimeError("S1 fill %s: area %.4f vs %.4f" % (tag, got_a, want_a))
    for t in keep:
        m.tri(ids[t[0]], ids[t[1]], ids[t[2]], want, zone)
    return len(keep)


class _S1Spike(object):
    """A stalagmite ('mite'), stalactite ('tite') or full column: an n-sided
    tube of rings up a bent axis, organic radius per vertex and per ring, a
    flowstone flare into the surface it grows from, drip ridges, a fused lobe
    on one side for the cover clusters. Offsets are (radial, tangential)."""

    U_MITE = (0.0, 0.035, 0.08, 0.15, 0.24, 0.34, 0.44, 0.54, 0.64, 0.74, 0.84, 0.92, 0.97, 1.0)
    U_SAT = (0.0, 0.05, 0.13, 0.3, 0.55, 0.8, 0.95, 1.0)
    U_SMALL = (0.0, 0.07, 0.25, 0.55, 0.82, 0.95, 1.0)
    U_TITE = (0.0, 0.04, 0.11, 0.22, 0.34, 0.47, 0.6, 0.73, 0.86, 1.0)
    U_COL = (0.0, 0.03, 0.07, 0.13, 0.22, 0.32, 0.42, 0.5, 0.58, 0.68, 0.78, 0.87, 0.93, 0.97, 1.0)

    SKIRT_W = (1.0, 0.86, 0.72, 0.58, 0.44, 0.31, 0.19, 0.09)   # fillet rings by radial fraction, edge to shaft
    BODY_MITE = (0.34, 0.44, 0.54, 0.64, 0.74, 0.84, 0.92, 0.97, 1.0)
    BODY_COL = (0.22, 0.32, 0.42, 0.5, 0.58, 0.68, 0.78, 0.87, 0.93, 0.97, 1.0)

    def __init__(self, kind, b, rad, H, R, sides, r, us, flare, lobe=None, bend=0.08, nridge=3,
                 ridge_amp=(0.09, 0.22), jitter=0.07, skirt_w=None, ridge_z=None, body_us=None):
        self.kind, self.b, self.rad, self.H, self.R, self.sides = kind, b, rad, H, R, sides
        self.skirt = min(S1_SKIRT[1], max(S1_SKIRT[0], S1_SKIRT[2] * H))
        self.ref = None                                  # the pass-7 shape this one stands in for
        if us is None:                                   # skirt rings by the apron, body rings by fraction
            sk = [self.skirt * (1.0 - w) ** S1_SKIRT_P / H for w in (skirt_w or self.SKIRT_W)]
            body = body_us or (self.BODY_MITE if kind == "mite" else self.BODY_COL)
            us = tuple(sk + [u for u in body if u > sk[-1] + 0.06])
        self.us, self.flare, self.lobe = us, flare, lobe
        self.angs = [TWO_PI * (i + 0.28 * r.sf()) / sides for i in range(sides)]
        self.fac = [1.0 + 0.13 * r.sf() for _ in range(sides)]
        self.jit = [[1.0 + (0.0 if ridge_z is not None and u * H < self.skirt else jitter) * r.sf() for _ in range(sides)]
                    for u in us]
        self.rim = [1.0 + S1_RIM_JITTER * r.sf() for _ in range(sides)] if ridge_z is not None else [1.0] * sides
        self.rock_z = [0.15 + 0.6 * ((v - 1.0) / (2.0 * S1_RIM_JITTER) + 0.5) for v in self.rim]   # where the floor's texture ends
        self.bend = (r.f() * TWO_PI, bend * (0.6 + 0.4 * r.f()), r.f() * TWO_PI)
        body = [u for u in us if max(0.2, (ridge_z or 0.0) / H) < u < 0.9]
        self.ridges = []
        for _ in range(nridge):
            if body:
                u = r.pick(body)
                body = [v for v in body if abs(v - u) > 0.05]
                self.ridges.append((u, ridge_amp[0] + (ridge_amp[1] - ridge_amp[0]) * r.f(), 0.11))
        self.centre = None      # (s, rho) param of the base, set by the allocator
        self.top = None         # for columns: the ceiling param centre
        self.cxy = None         # the base centre, world
        self.base = None        # (z, [(x, y)]) the base ring as built
        self.rings = []         # [(z, [(x, y)])] the rings above it, for the silhouette
        self.over = None        # a stalactite dripping over this stalagmite
        self.deck_z = DECK_Z
        self.tip_z = None

    def body(self, u):
        """Body radius at u, before the flare and the lobe."""
        if self.kind == "tite":
            base = 1.0 - 0.86 * u ** 1.15
        elif self.kind == "column":
            base = 1.0
        else:
            base = 1.0 - 0.72 * u ** 1.4 - 0.12 * max(0.0, (u - 0.92) / 0.08)   # a rounded crown
        ridge = 1.0
        for (uk, ak, wk) in self.ridges:
            ridge += ak * max(0.0, 1.0 - ((u - uk) / wk) ** 2)
        return self.R * base * ridge

    def flare_f(self, u):
        if self.kind == "tite":
            return 1.0 + (self.flare - 1.0) * math.exp(-u / 0.045)
        h = u * self.H                                   # the foot apron: flat at its edge, steep at the shaft
        f = 1.0 + (self.flare - 1.0) * (1.0 - min(1.0, h / self.skirt) ** (1.0 / S1_SKIRT_P))
        if self.kind == "column":
            f += 0.9 * math.exp(-(1.0 - u) / 0.06)                                    # ... and the ceiling flare
        return f

    def lobe_f(self, i, u):
        if not self.lobe:
            return 0.0
        a0, amp, uh = self.lobe
        w = max(0.0, math.cos(self.angs[i] - a0)) ** 3
        v = u / uh
        return amp * w * math.sqrt(max(0.0, 1.0 - v * v))

    def radius(self, i, u, k=None):
        """Vertex i's radius at u; ring k's own jitter when given."""
        j = self.jit[k][i] if k is not None else 1.0
        rim = 1.0 if self.kind == "tite" else self.rim[i]
        return self.body(u) * self.fac[i] * j * (1.0 + (self.flare_f(u) - 1.0) * rim + self.lobe_f(i, u))

    def offsets(self, k):
        u = self.us[k]
        return [(self.radius(i, u, k) * math.cos(self.angs[i]), self.radius(i, u, k) * math.sin(self.angs[i]))
                for i in range(self.sides)]

    def axis(self, u):
        """The axis' lateral wander at u: (radial, tangential), metres."""
        ph, amp, ph2 = self.bend
        a = amp * self.H * u ** 1.6
        s = 0.05 * self.H * math.sin(TWO_PI * u + ph2) * u * (1.0 - u)
        return (a * math.cos(ph) + s * math.cos(ph2), a * math.sin(ph) + s * math.sin(ph2))

    def section(self, u, frame):
        """World-xy offsets of the cross-section at u round the bent axis."""
        er, et = frame
        ax, ay = self.axis(u)
        return [(er[0] * (ax + self.radius(i, u) * math.cos(self.angs[i])) + et[0] * (ay + self.radius(i, u) * math.sin(self.angs[i])),
                 er[1] * (ax + self.radius(i, u) * math.cos(self.angs[i])) + et[1] * (ay + self.radius(i, u) * math.sin(self.angs[i])))
                for i in range(self.sides)]


def _s1_frustum(c, cx, cy, rings, angs, frame):
    """Collider: a closed stack of polygon rings [(z, [(dx, dy)])] (world offsets)."""
    er, et = frame
    lvl = [[c.v((cx + dx, cy + dy, z)) for (dx, dy) in offs] for (z, offs) in rings]
    n = len(angs)
    for a in range(len(lvl) - 1):
        for i in range(n):
            j = (i + 1) % n
            am = 0.5 * (angs[i] + (angs[j] if j else angs[0] + TWO_PI))
            want = (er[0] * math.cos(am) + et[0] * math.sin(am), er[1] * math.cos(am) + et[1] * math.sin(am), 0.0)
            c.quad(lvl[a][i], lvl[a][j], lvl[a + 1][j], lvl[a + 1][i], want, ZONE_ROCK)
    c.fan(lvl[-1], UP, ZONE_ROCK)
    c.fan(lvl[0], DOWN, ZONE_ROCK)


def _wall_point(wall, t, z):
    """Where a _Wall's coarse bilinear surface is at (theta, z): W() without
    registering a vertex."""
    i, u = wall._side(t)
    j = (i + 1) % len(wall.ang)
    zs = wall.ring_z
    k = max(0, min(len(zs) - 2, _bisect(zs, z) - 1))
    v = (z - zs[k]) / (zs[k + 1] - zs[k])
    m = wall.m
    pa, pb = m.verts[wall.rings[k][i]], m.verts[wall.rings[k][j]]
    pd, pc = m.verts[wall.rings[k + 1][i]], m.verts[wall.rings[k + 1][j]]
    return tuple((1 - u) * (1 - v) * pa[c] + u * (1 - v) * pb[c]
                 + u * v * pc[c] + (1 - u) * v * pd[c] for c in range(3))


def _s1_sculpt(m, ang, cols_all, lo, hi, pit_wall, shaft, pit_top, wall, upper, WF, WR, CE, DV, ceil_nv, out_rows):
    """Everything in S1. Returns the (lo, hi) column angles it owns."""
    r = _Rng(S1_SEED)
    R_REF = S1_RREF

    def T(deg):
        return _norm_t(ang[0], _bear_t(deg))

    inside = [t for t in cols_all if lo - 1e-9 <= t <= hi + 1e-9]
    b_lo, b_hi = _bear_deg(hi), _bear_deg(lo)          # bearings: b_lo < b_hi

    # ---- the sub-columns: the coarse columns inside, each split to ~S1_CELL --
    sc = []
    for t0, t1 in zip(inside, inside[1:]):
        k = max(1, int(round((t1 - t0) * R_REF / S1_CELL)))
        sc += [t0 + (t1 - t0) * q / k for q in range(k)]
    sc.append(hi)
    n = len(sc)
    scb = [_bear_deg(t) for t in sc]
    S1["lo"], S1["hi"], S1["sc"] = lo, hi, sc

    def fade_s(b):
        return min(_ramp(b - b_lo, 0.0, S1_FADE), _ramp(b_hi - b, 0.0, S1_FADE), 1.0)

    def bearing(x, y):
        return (-math.degrees(math.atan2(y, x))) % 360.0

    # ---- surfaces: the coarse rock sampled at any column, plus the relief ----
    def deck_xy(t, rho):
        pa, pb = _chord(m, pit_top, ang, t), _chord(m, wall[0], ang, t)
        f = (rho - INNER_R) / (OUTER_R - INNER_R)
        return ((1 - f) * pa[0] + f * pb[0], (1 - f) * pa[1] + f * pb[1])

    def ceil_xy(t, rho):
        pa, pb = _chord(m, upper[0], ang, t), _chord(m, wall[-1], ang, t)
        f = (rho - INNER_R) / (OUTER_R - INNER_R)
        return ((1 - f) * pa[0] + f * pb[0], (1 - f) * pa[1] + f * pb[1])

    def wall_pt(t, z):
        """The coarse outer wall at (column, z): between its rings' chords."""
        pts = [_chord(m, wall[k], ang, t) for k in range(len(wall))]
        for k in range(len(pts) - 1):
            if z <= pts[k + 1][2] + 1e-9 or k == len(pts) - 2:
                f = _ramp(z, pts[k][2], pts[k + 1][2])
                return tuple((1 - f) * pts[k][c] + f * pts[k + 1][c] for c in range(3))

    deck_waves = _s1_waves(_Rng(S1_SEED + 1), S1_DECK_L)
    ceil_waves = _s1_waves(_Rng(S1_SEED + 2), S1_CEIL_L)
    mounds, drips = [], []          # (x, y, height, radius)
    ripples = []                    # (x, y, skirt radius, [(distance beyond it, height, wander phase)])

    def ripple_d(rp, x, y):
        """Distance beyond the skirt and the angle round the foot, in its frame."""
        rx, ry, rr = rp[0], rp[1], rp[2]
        er, et = _radial(_bear_deg(math.atan2(ry, rx))), _tangent(_bear_deg(math.atan2(ry, rx)))
        dr = (x - rx) * er[0] + (y - ry) * er[1]
        dt = (x - rx) * et[0] + (y - ry) * et[1]
        return math.hypot(dr, dt) - rr, math.atan2(dt, dr)

    def ripple(x, y):
        out = 0.0
        hw, wob = S1_RIPPLE[4], S1_RIPPLE[5]
        for rp in ripples:
            d, a = ripple_d(rp, x, y)
            if d < S1_RIPPLE[0] - hw - wob or d > rp[3][-1][0] + hw + wob:
                continue
            for (c, amp, ph) in rp[3]:
                cc = c + wob * math.sin(2.0 * a + ph)
                if abs(d - cc) < hw:
                    out += amp * math.cos(0.5 * math.pi * (d - cc) / hw) ** 2
        return out

    def bump(x, y, lst):
        out = 0.0
        for (mx, my, h, rad) in lst:
            d = math.hypot(x - mx, y - my)
            if d < rad:
                v = d / rad
                out += h * (1.0 - v * v) ** 2
        return out

    def H(x, y):
        """The deck's rise over DECK_Z."""
        rho = math.hypot(x, y)
        fr = min(_ramp(rho - INNER_R, 0.0, 1.2), _ramp(OUTER_R - rho, 0.0, 1.2))
        return fade_s(bearing(x, y)) * fr * (S1_DECK_AMP * deck_waves(x, y) + bump(x, y, mounds) + ripple(x, y))

    def C(x, y):
        """The ceiling's drop under CEIL_Z: sags, and a drip cone per stalactite."""
        rho = math.hypot(x, y)
        fr = min(_ramp(rho - INNER_R, 0.0, 1.5), _ramp(OUTER_R - rho, 0.3, 1.3))
        return fade_s(bearing(x, y)) * fr * (S1_CEIL_SAG * (1.0 + ceil_waves(x, y)) + bump(x, y, drips))

    ribs = _s1_grooves(_Rng(S1_SEED + 3), lo * OUTER_R - 3.0, hi * OUTER_R + 3.0, S1_RIB)
    wob = _s1_waves(_Rng(S1_SEED + 5), (2.0, 4.0), 4)
    LC = OUTER_R - INNER_R          # path length across the ceiling
    F = S1_FILLET

    def wc_pos(t, q):
        """Ceiling-and-wall point at path distance q: 0 at the lip, LC at the
        corner, LC + CEIL_H at the foot. Relief, ribs and the corner fillet."""
        fs = fade_s(_bear_deg(t))
        er = (math.cos(t), math.sin(t))
        if q <= LC + 1e-9:
            x, y = ceil_xy(t, INNER_R + q)
            z = CEIL_Z - C(x, y)
            dcorner = LC - q
            uf = F - dcorner if dcorner < F else None
            orig = (-dcorner, 0.0)
        else:
            h = q - LC
            x, y, z = wall_pt(t, CEIL_Z - h)
            uf = F + h if h < F else None
            orig = (0.0, -h)
            env = _ramp(h, 0.0, 0.5) * _ramp(CEIL_H - h, 0.0, 0.9) * fs
            rec = env * (ribs(t * OUTER_R, z) + 0.08 * (1.0 + wob(t * OUTER_R, z)))
            if uf is not None:
                rec *= 0.5
            x, y = x + er[0] * rec, y + er[1] * rec
        if uf is not None:
            th = 0.5 * math.pi * uf / (2.0 * F)
            tgt = (-F + F * math.sin(th), -F + F * math.cos(th))
            dr, dz = (tgt[0] - orig[0]) * fs, (tgt[1] - orig[1]) * fs
            x, y, z = x + er[0] * dr, y + er[1] * dr, z + dz
        return (x, y, z)

    # ---- the plan: a forest. Full columns first, then thin stalagmites, thrown
    # over the whole deck with clear air between their surfaces; every base
    # claims the cells under it, and overlapping claims merge into one hole so
    # the fill welds several rings at once. -----------------------------------
    rho = [INNER_R + (OUTER_R - INNER_R) * j / S1_NS for j in range(S1_NS + 1)]
    used_d, used_c = {}, {}          # cell -> the block that claimed it
    cstep = LC / S1_NC
    dstep = (OUTER_R - INNER_R) / S1_NS

    def interior(used, i, j):
        blocks = set(used.get(c) for c in ((i - 1, j - 1), (i, j - 1), (i - 1, j), (i, j)))
        return len(blocks) == 1 and None not in blocks

    def rng(lo_, hi_):
        return lo_ + r.f() * (hi_ - lo_)

    def ring_param(sp, centre, k):
        s0, r0 = centre
        return [(s0 + dt * R_REF / r0, r0 + dr) for (dr, dt) in sp.offsets(k)]

    def cells_under(pp, rows, jmax, margin=0.25, clamp=False):
        """The cells whose rectangle meets a param polygon's box plus margin;
        None when that runs into a boundary strip, the lip or the wall (or,
        clamped, as much of the box as stays clear of them)."""
        rc = sum(p[1] for p in pp) / len(pp)
        ms = margin * R_REF / rc
        s0, s1 = min(p[0] for p in pp) - ms, max(p[0] for p in pp) + ms
        r0, r1 = min(p[1] for p in pp) - margin, max(p[1] for p in pp) + margin
        i0 = max(i for i in range(n) if sc[i] * R_REF <= s0) if sc[0] * R_REF <= s0 else -1
        i1 = min(i for i in range(n) if sc[i] * R_REF >= s1) if sc[-1] * R_REF >= s1 else n
        j0 = max(j for j in range(len(rows)) if rows[j] <= r0) if rows[0] <= r0 else -1
        j1 = min(j for j in range(len(rows)) if rows[j] >= r1) if rows[-1] >= r1 else len(rows)
        if clamp:
            return (max(1, i0), min(n - 2, i1), max(1, j0), min(jmax, j1))
        if i0 < 1 or i1 > n - 2 or j0 < 1 or j1 > jmax:
            return None
        return (i0, i1, j0, j1)

    def merge(blocks):
        """Overlapping blocks become one, the box round both, until stable."""
        changed = True
        while changed:
            changed, out = False, []
            for blk, sps in blocks:
                for k, (b2, s2) in enumerate(out):
                    if blk[0] < b2[1] and b2[0] < blk[1] and blk[2] < b2[3] and b2[2] < blk[3]:
                        out[k] = ((min(blk[0], b2[0]), max(blk[1], b2[1]), min(blk[2], b2[2]), max(blk[3], b2[3])), s2 + sps)
                        changed = True
                        break
                else:
                    out.append((blk, sps))
            blocks = out
        return blocks

    def claim(used, blocks):
        for blk, _sps in blocks:
            for i in range(blk[0], blk[1]):
                for j in range(blk[2], blk[3]):
                    used[(i, j)] = blk

    spikes, tites, fixtures = [], [], []
    dblocks, cblocks = [], []

    def widest(sp, h):
        u = min(1.0, h / sp.H)
        return max(sp.radius(i, u) for i in range(sp.sides))

    def base_r(sp):
        return max(math.hypot(dr, dt) for (dr, dt) in sp.offsets(0))

    def fits(sp, x, y, clump=False):
        sp = sp.ref or sp                                # placement judged on the pass-7 shape
        cover = sp.kind == "column" or sp.H >= S1_COVER_H
        for o in fixtures:
            o = o.ref or o
            d = math.hypot(x - o.cxy[0], y - o.cxy[1])
            if cover and (o.kind == "column" or o.H >= S1_COVER_H) \
                    and d < S1_FOREST_GAP + widest(sp, S1_CHEST) + widest(o, S1_CHEST):
                return False
            if d < (S1_FOOT_GAP if clump else S1_ROUTE_GAP) + widest(sp, 0.3) + widest(o, 0.3):
                return False                                  # feet keep a runner's gap; a clump's small one may touch
            if d < base_r(sp) + base_r(o) + 0.55:            # base rings stay apart for the fill
                return False
        return True

    def spec(kind):
        return {"short": S1_SHORT, "medium": S1_MEDIUM, "tall": S1_TALL}[kind]

    def make(kind, b, rad):
        t = T(b)
        x, y = deck_xy(t, rad)
        old_w = (1.0, 0.9, 0.78, 0.64, 0.5, 0.36, 0.22, 0.1)
        if kind == "column":                             # the pass-7 draws, so the approved layout stands
            ref = _S1Spike("column", b, rad, CEIL_H, rng(*S1_COL_R), 8, r, None, S1_FLARE, bend=0.03, nridge=4,
                           skirt_w=old_w)
        else:
            lo_h, hi_h, lo_r, hi_r = spec(kind)
            ref = _S1Spike("mite", b, rad, rng(lo_h, hi_h), rng(lo_r, hi_r), r.pick((6, 7, 8)), r, None,
                           S1_FLARE, bend=0.07, nridge=4, skirt_w=old_w)
        seed = S1_SEED * 3 + int(b * 977.0) + int(rad * 131.0)          # the shape is its own
        cshape = _Rng(seed)                                                # the pass-8 shape: the collider stands
        coll = _S1Spike(ref.kind, b, rad, ref.H, ref.R, cshape.pick((10, 11, 12, 13)), cshape, None, S1_FLARE,
                        bend=0.03 if kind == "column" else 0.07, nridge=4, ridge_z=S1_RIDGE_Z)
        sides, skirt_w, body_us = S1_LOD[kind]                            # the drawn shape: the diet
        sp = _S1Spike(ref.kind, b, rad, ref.H, ref.R, sides, _Rng(seed), None, S1_FLARE,
                      bend=0.03 if kind == "column" else 0.07, nridge=4,
                      ridge_z=S1_RIDGE_Z, skirt_w=skirt_w, body_us=body_us)
        sp.ref, sp.coll = ref, coll
        sp.centre, sp.cxy = ref.centre, ref.cxy = (t * R_REF, rad), (x, y)
        return sp

    def fit_ring(sp, k, centre, blk, rows, margin=0.3):
        """Pull ring k's rim in, vertex by vertex, until the ring sits inside
        the block with the margin cells_under wanted; the rim is the only knob."""
        s0, r0 = centre
        ms = margin * R_REF / r0
        lo_s, hi_s = sc[blk[0]] * R_REF + ms, sc[blk[1]] * R_REF - ms
        lo_r, hi_r = rows[blk[2]] + margin, rows[blk[3]] - margin
        u = sp.us[k]
        for i in range(sp.sides):
            ca, sa = math.cos(sp.angs[i]), math.sin(sp.angs[i])
            allow = 9.0
            if ca > 1e-9:
                allow = min(allow, (hi_r - r0) / ca)
            elif ca < -1e-9:
                allow = min(allow, (r0 - lo_r) / -ca)
            if sa > 1e-9:
                allow = min(allow, (hi_s - s0) * r0 / R_REF / sa)
            elif sa < -1e-9:
                allow = min(allow, (s0 - lo_s) * r0 / R_REF / -sa)
            if sp.radius(i, u, k) > allow:
                core = sp.body(u) * sp.fac[i] * sp.jit[k][i]
                sp.rim[i] = min(sp.rim[i], max(0.0, (allow / core - 1.0 - sp.lobe_f(i, u)) / (sp.flare_f(u) - 1.0)))

    def place(sp, x, y, clump=False):
        if not fits(sp, x, y, clump):
            return False
        ref = sp.ref or sp
        blk = cells_under(ring_param(ref, sp.centre, 0), rho, S1_NS - 1)
        if blk is None:
            return False
        crows = [INNER_R + j * cstep for j in range(S1_NC + 1)]
        if sp.kind == "column":
            sp.top = ref.top = sp.centre
            cblk = cells_under(ring_param(ref, sp.top, len(ref.us) - 1), crows, S1_NC - 1)
            if cblk is None:
                return False
        if ref is not sp:                                # the real shapes keep inside the pass-7 blocks
            for sh in (sp, sp.coll):
                fit_ring(sh, 0, sp.centre, blk, rho)
                if sp.kind == "column":
                    fit_ring(sh, len(sh.us) - 1, sp.top, cblk, crows)
        if sp.kind == "column":
            cblocks.append((cblk, [sp]))
        fixtures.append(sp)
        spikes.append(sp)
        if sp.R >= S1_RIPPLE_R:                          # room in the fill for the ripples round it
            reach = S1_RIPPLE[0] + S1_RIPPLE[1] * 3.2 + S1_RIPPLE[4] + S1_RIPPLE[5]
            blk = cells_under(ring_param(sp, sp.centre, 0), rho, S1_NS - 1, margin=0.25 + reach, clamp=True)
        dblocks.append((blk, [sp]))
        mounds.append((x, y, S1_MOUND[0] + S1_MOUND[1] * sp.R, S1_MOUND[2] + S1_MOUND[3] * sp.R))
        if sp.R >= S1_RIPPLE_R:                          # the floor builds up round the bigger feet
            shape = _Rng(S1_SEED * 5 + int(sp.b * 977.0))
            nk = shape.i(2, 4)
            d0, sp_, h0, h1 = S1_RIPPLE[:4]
            ripples.append((x, y, base_r(sp.coll), [(d0 + sp_ * (k + 0.2 * shape.sf()), (h0 + (h1 - h0) * shape.f()) * (1.0 - 0.1 * k),
                                                shape.f() * TWO_PI) for k in range(nk)]))
        return True

    rest = S1_FOREST_N - S1_FOREST_COLS
    quota = [("column", S1_FOREST_COLS), ("tall", int(round(S1_FOREST_MIX[2] * rest))),
             ("medium", int(round(S1_FOREST_MIX[1] * rest)))]
    quota.append(("short", rest - quota[1][1] - quota[2][1]))
    for kind, want in quota:
        got = tries = 0
        while got < want and tries < 6000:
            tries += 1
            b, rad = rng(*S1_FOREST_B), rng(*S1_FOREST_R)
            sp = make(kind, b, rad)
            if place(sp, sp.cxy[0], sp.cxy[1]):
                got += 1
    hosts = [f for f in fixtures if f.kind == "mite" and f.H >= S1_COVER_H]
    got = tries = 0
    while got < S1_CLUMPS and hosts and tries < 400:            # a small one at a big one's feet
        tries += 1
        host = r.pick(hosts)
        a = r.f() * TWO_PI
        sp = make("short", host.b, host.rad)
        d = base_r(host.ref) + base_r(sp.ref) + 0.6 + 0.2 * r.f()     # its skirt against the host's skirt
        x, y = host.cxy[0] + d * math.cos(a), host.cxy[1] + d * math.sin(a)
        sp = make("short", _bear_deg(math.atan2(y, x)), math.hypot(x, y))
        sp.H = sp.ref.H = sp.coll.H = min(sp.H, 1.8)
        if place(sp, sp.cxy[0], sp.cxy[1], True):
            got += 1
    dblocks = merge(dblocks)
    claim(used_d, dblocks)
    cblocks = merge(cblocks)
    claim(used_c, cblocks)

    def block_ceil(b, rad, w, h):
        ic = min(range(n), key=lambda i: abs(scb[i] - (b + (0.5 * (scb[0] - scb[1]) if w % 2 else 0.0))))
        jc = int(round((rad - INNER_R) / cstep))
        i0, j0 = ic - w // 2, jc - h // 2
        j0 = max(1, min(S1_NC - 1 - h, j0))
        if i0 < 1 or i0 + w > n - 2 or j0 + h > S1_NC - 1:
            return None
        cells = [(i, j) for i in range(i0, i0 + w) for j in range(j0, j0 + h)]
        if any(c in used_c for c in cells):
            return None
        blk = (i0, i0 + w, j0, j0 + h)
        for c in cells:
            used_c[c] = blk
        return blk

    def centre_c(blk):
        return (0.5 * (sc[blk[0]] + sc[blk[1]]) * R_REF, INNER_R + 0.5 * (blk[2] + blk[3]) * cstep)

    # stalactites: a few over the tallest stalagmites, the rest thrown at the ceiling
    def add_tite(b, rad, L, R, blk):
        _S1Spike("tite", b, rad, L, R, 7 if R > 0.26 else r.pick((5, 6, 6)), r, _S1Spike.U_TITE,
                 S1_TITE_FLARE, bend=0.08, nridge=3, ridge_amp=(0.18, 0.38), jitter=0.11)   # the pass-8 draws
        shape = _Rng(S1_SEED * 7 + int(b * 977.0) + int(rad * 131.0))                        # the shape is its own
        sp = _S1Spike("tite", b, rad, L, R, S1_TITE_LOD[0][1 if R > 0.26 else 0], shape, S1_TITE_LOD[1],
                      S1_TITE_FLARE, bend=0.08, nridge=3, ridge_amp=(0.18, 0.38), jitter=0.11)
        sp.centre = centre_c(blk)
        x, y = ceil_xy(sp.centre[0] / R_REF, sp.centre[1])
        k = _ramp(R, S1_TITES[3], S1_TITES[4])
        drips.append((x, y, S1_DRIP[0] + k * (S1_DRIP[1] - S1_DRIP[0]),
                      S1_DRIP[2] + k * (S1_DRIP[3] - S1_DRIP[2])))
        spikes.append(sp)
        tites.append(sp)
        cblocks.append((blk, [sp]))
        return sp

    for main in sorted([f for f in fixtures if f.kind == "mite"], key=lambda s: -s.H)[:S1_OVER]:
        blk = block_ceil(_bear_deg(main.centre[0] / R_REF), main.centre[1], 3, 3)
        if blk is None:
            continue
        sp = add_tite(main.b, main.rad, 1.0, rng(0.24, 0.34), blk)
        sp.over = main           # its length is settled once the deck is known
    got = tries = 0
    while got < S1_TITES[0] and tries < 2000:
        tries += 1
        b = rng(b_lo + 2.5, b_hi - 2.5)
        rad = rng(47.4, 56.6)
        R = S1_TITES[3] + (S1_TITES[4] - S1_TITES[3]) * r.f() ** 1.6
        blk = block_ceil(b, rad, 3 if R > 0.2 else 2, 3 if R > 0.28 else 2)
        if blk is None:
            continue
        L = S1_TITES[1] + (S1_TITES[2] - S1_TITES[1]) * r.f() ** 2.2   # mostly short, a few long
        L = max(S1_TITES[1], min(L, 2.2 + 12.0 * R))       # thin ones stay short
        add_tite(b, rad, L, R, blk)
        got += 1

    # ---- the grids' vertices, now every mound and drip cone is known --------
    G, WG, param, extra_d = {}, {}, {}, {}
    coarse = [i for i, t in enumerate(sc) if any(abs(t - c) < 1e-9 for c in inside)]
    for i, t in enumerate(sc):
        s = t * R_REF
        boundary = i in (0, n - 1)
        if not boundary:
            shaft.add_xt(0, t)
        for j in range(S1_NS + 1):
            param[(i, j)] = (s, rho[j])
            if j == 0:
                if i in coarse:                          # the lip keeps the pit wall's own vertices
                    G[(i, j)] = pit_wall.W(t, DECK_Z)
            elif j == S1_NS:
                G[(i, j)] = WF(0, t)
            elif not boundary:
                if interior(used_d, i, j):
                    blk = used_d[(i, j)]
                    sps = [sp for bb, ss in dblocks if bb == blk for sp in ss]
                    pp = [ring_param(sp, sp.centre, 0) for sp in sps]
                    if any(_s1_inpoly((s, rho[j]), poly) for poly in pp):
                        continue
                    if any(_s1_seg_dist(((s * rho[j] / R_REF), rho[j]), (q0[0] * rho[j] / R_REF, q0[1]),
                                        (q1[0] * rho[j] / R_REF, q1[1])) < 0.4
                           for poly in pp for q0, q1 in zip(poly, poly[1:] + poly[:1])):
                        continue                         # clear of every ring edge: the fill keeps them
                    extra_d.setdefault(blk, []).append((i, j))
                x, y = deck_xy(t, rho[j])
                G[(i, j)] = m.v((x, y, DECK_Z + H(x, y)))
    # the ceiling and the wall are drawn on every other sub-column (the coarse
    # ones kept, so the wall foot lies on the deck's chords), on S1_CEIL_ROWS,
    # the corner round-over and S1_WALL_H; the holes snap out to that grid
    ec = sorted((set(range(1, n - 1, 2)) | set(coarse) | {n - 2}) - {0, n - 1})
    ne = len(ec)
    er = list(S1_CEIL_ROWS) + [(LC - S1_CORNER) / cstep, float(S1_NC)]
    KC = len(er)                                         # qs index of the corner
    qs = [0.0] + [j * cstep for j in er] + [LC + h for h in (S1_CORNER,) + S1_WALL_H] + [LC + CEIL_H]
    NQ = len(qs) - 1

    def snap(blk):
        i0, i1, j0, j1 = blk
        return (max(a for a in range(ne) if ec[a] <= i0), min(a for a in range(ne) if ec[a] >= i1),
                max(k for k in range(1, KC + 1) if er[k - 1] <= j0 + 1e-9),
                min(k for k in range(1, KC + 1) if er[k - 1] >= j1 - 1e-9))

    cblocks = merge([(snap(blk), sps) for blk, sps in cblocks])
    used_e = {}
    claim(used_e, cblocks)
    for k, q in enumerate(qs):
        if k == 0:
            for i, t in enumerate(sc):
                WG[(i, k)] = shaft.W(t, CEIL_Z)
        elif k == NQ:
            for i in range(n):
                WG[(i, k)] = G[(i, S1_NS)]
        else:
            for a, i in enumerate(ec):
                if not interior(used_e, a, k):
                    WG[(i, k)] = m.v(wc_pos(sc[i], q))
    WGe = {(a, k): WG[(i, k)] for a, i in enumerate(ec) for k in range(NQ + 1) if (i, k) in WG}
    S1["deck_xy"], S1["H"], S1["fade"] = deck_xy, H, fade_s

    # ---- base rings on the deck and the ceiling, the holes filled round them
    def loop_of(blk, P, V):
        i0, i1, j0, j1 = blk
        path = [(i, j0) for i in range(i0, i1)] + [(i1, j) for j in range(j0, j1)] \
            + [(i, j1) for i in range(i1, i0, -1)] + [(i0, j) for j in range(j1, j0, -1)]
        return [(P(i, j), V[(i, j)]) for (i, j) in path]

    base_ids = {}
    fill_tris = 0
    for (blk, sps) in dblocks:
        rings, polys = [], []
        for sp in sps:
            pp = ring_param(sp, sp.centre, 0)
            pts = [deck_xy(s / R_REF, rr) for (s, rr) in pp]
            ids = [m.v((x, y, DECK_Z + H(x, y))) for (x, y) in pts]
            base_ids[(sp, "deck")] = ids
            sp.base = (DECK_Z + H(*deck_xy(sp.centre[0] / R_REF, sp.centre[1])), pts)
            rings.append(list(zip(pp, ids)))
            polys.append(pp)
        grid = [(param[c], G[c]) for c in extra_d.get(blk, ())]
        extra, taken = [], []
        s_lo, s_hi = sc[blk[0]] * R_REF, sc[blk[1]] * R_REF
        r_lo, r_hi = rho[blk[2]], rho[blk[3]]
        for sp in sps:                                   # ripple nodes: the floor resolves the spread
            rp = [q for q in ripples if q[0] == sp.cxy[0] and q[1] == sp.cxy[1]]
            if not rp:
                continue
            rp = rp[0]
            s0, r0 = sp.centre
            stations = []
            for (c, amp, ph) in rp[3]:
                stations.append((c, ph, 1.0))                  # the crest
                stations.append((c + S1_RIPPLE[4], ph, 1.0))   # the trough beyond it
            stations.insert(0, (rp[3][0][0] - S1_RIPPLE[4], rp[3][0][2], 1.0))
            for (c, ph, _) in stations:
                nq = max(5, min(12, int(round(TWO_PI * (rp[2] + c) / S1_RIPPLE_STEP))))
                for q in range(nq):
                    a = TWO_PI * (q + 0.37) / nq
                    rr = rp[2] + c + S1_RIPPLE[5] * math.sin(2.0 * a + ph)
                    pq = (s0 + rr * math.sin(a) * R_REF / r0, r0 + rr * math.cos(a))
                    if not (s_lo + 0.3 < pq[0] < s_hi - 0.3 and r_lo + 0.3 < pq[1] < r_hi - 0.3):
                        continue
                    pm = (pq[0] * pq[1] / R_REF, pq[1])   # metres
                    if any(_s1_seg_dist(pm, (a0[0] * pq[1] / R_REF, a0[1]), (a1[0] * pq[1] / R_REF, a1[1])) < 0.4
                           for poly in polys for a0, a1 in zip(poly, poly[1:] + poly[:1])):
                        continue
                    if any(math.hypot((pq[0] - t[0]) * pq[1] / R_REF, pq[1] - t[1]) < 0.2 for t in taken):
                        continue
                    x, y = deck_xy(pq[0] / R_REF, pq[1])
                    extra.append((pq, m.v((x, y, DECK_Z + H(x, y)))))
                    taken.append(pq)
        for (i, j), (pq, vid) in zip(extra_d.get(blk, ()), grid):   # the grid's own nodes where the ripples leave room, every other one
            if (i + j) % 2 == 0 and not any(math.hypot((pq[0] - t[0]) * pq[1] / R_REF, pq[1] - t[1]) < 0.3 for t in taken):
                extra.append((pq, vid))
        fill_tris += _s1_fill(m, loop_of(blk, lambda i, j: param[(i, j)], G), rings, UP, ZONE_DECK,
                              "deck %s" % (blk,), extra)
    for (blk, sps) in cblocks:
        rings = []
        for sp in sps:
            c = sp.top if sp.kind == "column" else sp.centre
            pp = ring_param(sp, c, len(sp.us) - 1 if sp.kind == "column" else 0)
            ids = []
            for (s, rr) in pp:
                x, y = ceil_xy(s / R_REF, rr)
                ids.append(m.v((x, y, CEIL_Z - C(x, y))))
            base_ids[(sp, "ceil")] = ids
            rings.append(list(zip(pp, ids)))
        fill_tris += _s1_fill(m, loop_of(blk, lambda a, k: (sc[ec[a]] * R_REF, INNER_R + qs[k]), WGe),
                              rings, DOWN, ZONE_ROCK, "ceil %s" % (blk,))

    # ---- the spikes ---------------------------------------------------------
    def emit_tube(sp, lvl, frame, tip):
        ns = sp.sides
        er, et = frame
        for a in range(len(lvl) - 1):
            um = 0.5 * (sp.us[a] + sp.us[a + 1])
            if sp.kind == "tite":                        # the flat bands: a root flares along the ceiling ...
                wz = -1.0 if um < 0.15 else 0.0
            else:                                        # ... an apron along the floor, a column both
                wz = 1.0 if um * sp.H < sp.skirt else (-1.0 if sp.kind == "column" and um > 0.9 else 0.0)
            hm = um * sp.H
            for i in range(ns):
                j = (i + 1) % ns
                am = 0.5 * (sp.angs[i] + (sp.angs[j] if j else sp.angs[0] + TWO_PI))
                # the low fillet is floor; the change to rock wanders 0.15..0.75 m up it, face by face
                zone = ZONE_DECK if sp.kind != "tite" and hm < sp.rock_z[i] else ZONE_ROCK
                want = (er[0] * math.cos(am) + et[0] * math.sin(am),
                        er[1] * math.cos(am) + et[1] * math.sin(am), wz)
                m.quad(lvl[a][i], lvl[a][j], lvl[a + 1][j], lvl[a + 1][i], want, zone, best=True)
        if tip is not None:                              # the last ring is the point: a cone from the ring below
            top, apex = lvl[-1], m.v(tip)
            for i in range(ns):
                m.tri(top[i], top[(i + 1) % ns], apex, (0.0, 0.0, -1.0 if sp.kind == "tite" else 1.0), ZONE_ROCK)

    def tip_of(sp, cx, cy, frame, z):
        """The point of a spike: on the bent axis at u = 1, just past the crown."""
        er, et = frame
        ax, ay = sp.axis(1.0)
        d = (0.4 if sp.kind == "tite" else 0.25) * sp.body(1.0) + 0.04
        return (cx + er[0] * ax + et[0] * ay, cy + er[1] * ax + et[1] * ay, z - d if sp.kind == "tite" else z + d)

    prisms = []

    def on_floor(sp, u, pts, z):
        """A ring's vertices in the fillet follow the floor under them, the
        floor's share fading out up the skirt, so the apron lies on the deck
        it grows from instead of on the deck at the centre."""
        w = min(1.0, u * sp.H / sp.skirt)
        w = w * w * (3.0 - 2.0 * w)
        if w >= 1.0:
            return [z] * len(pts)
        return [z + (1.0 - w) * (H(x, y) - (sp.deck_z - DECK_Z)) for (x, y) in pts]

    for sp in spikes:
        t_c = sp.centre[0] / R_REF
        frame = ((math.cos(t_c), math.sin(t_c)), (-math.sin(t_c), math.cos(t_c)))
        sp.frame = frame
        cx, cy = deck_xy(t_c, sp.centre[1])
        sp.cxy = (cx, cy)
        sp.deck_z = DECK_Z + H(cx, cy)
        if sp.kind == "column":
            tx, ty = ceil_xy(sp.top[0] / R_REF, sp.top[1])
            z1 = CEIL_Z - C(tx, ty)
            lvl = [base_ids[(sp, "deck")]]
            for k in range(1, len(sp.us) - 1):
                u = sp.us[k]
                z = sp.deck_z + (z1 - sp.deck_z) * u
                pts = [(cx + (tx - cx) * u + dx, cy + (ty - cy) * u + dy) for (dx, dy) in sp.section(u, frame)]
                sp.rings.append((z, pts))
                lvl.append([m.v((x, y, zi)) for (x, y), zi in zip(pts, on_floor(sp, u, pts, z))])
            lvl.append(base_ids[(sp, "ceil")])
            emit_tube(sp, lvl, frame, None)
            prisms.append(sp)
            continue
        if sp.kind == "tite":
            cx, cy = ceil_xy(t_c, sp.centre[1])
            sp.cxy = (cx, cy)
            zc = CEIL_Z - C(cx, cy)
            deck_here = DECK_Z + H(cx, cy)
            if sp.over is not None:
                sp.H = zc - (sp.over.deck_z + sp.over.H + rng(0.5, 1.2))
            sp.H = max(S1_TITES[1], min(sp.H, zc - deck_here - S1_TIP_CLEAR))
            sp.base_z, sp.tip_z = zc, zc - sp.H
            sp.base = (zc, [ceil_xy(s / R_REF, rr) for (s, rr) in ring_param(sp, sp.centre, 0)])
            lvl = [base_ids[(sp, "ceil")]]
            for k in range(1, len(sp.us)):
                u = sp.us[k]
                z = zc - u * sp.H
                pts = [(cx + dx, cy + dy) for (dx, dy) in sp.section(u, frame)]
                sp.rings.append((z, pts))
                if k < len(sp.us) - 1:
                    lvl.append([m.v((x, y, z)) for (x, y) in pts])
            emit_tube(sp, lvl, frame, tip_of(sp, cx, cy, frame, zc - sp.H))
            if sp.tip_z - deck_here < 2.3:
                prisms.append(sp)
            continue
        lvl = [base_ids[(sp, "deck")]]
        for k in range(1, len(sp.us)):
            u = sp.us[k]
            z = sp.deck_z + u * sp.H
            pts = [(cx + dx, cy + dy) for (dx, dy) in sp.section(u, frame)]
            sp.rings.append((z, pts))
            if k < len(sp.us) - 1:
                lvl.append([m.v((x, y, zi)) for (x, y), zi in zip(pts, on_floor(sp, u, pts, z))])
        emit_tube(sp, lvl, frame, tip_of(sp, cx, cy, frame, sp.deck_z + sp.H))
        if sp.H >= 1.0:
            prisms.append(sp)

    # ---- the deck grid and its boundary strips ------------------------------
    deck_cells = 0
    for i in range(1, n - 2):
        for j in range(1, S1_NS):
            if (i, j) in used_d:
                continue
            m.quad(G[(i, j)], G[(i + 1, j)], G[(i + 1, j + 1)], G[(i, j + 1)], UP, ZONE_DECK, best=True)
            deck_cells += 1
    _strip(m, [(sc[i] * R_REF, G[(i, 0)]) for i in coarse],            # the lip row: coarse lip to fine row 1
           [(sc[i] * R_REF, G[(i, 1)]) for i in range(1, n - 1)], UP, ZONE_DECK)
    for (ib, ii) in ((0, 1), (n - 1, n - 2)):
        A = [(RST[j] - INNER_R, DV(sc[ib], j)) for j in range(len(RST))]
        B = [(rho[j] - INNER_R, G[(ii, j)]) for j in range(1, S1_NS + 1)]
        _strip(m, A, B, UP, ZONE_DECK)

    # ---- the ceiling-and-wall grid and its boundary strips ------------------
    def wc_want(c):
        if c[2] > CEIL_Z - 0.55 * F and math.hypot(c[0], c[1]) < OUTER_R - 0.55 * F:
            return DOWN
        a = math.atan2(c[1], c[0])
        return (-math.cos(a), -math.sin(a), 0.0)

    _strip(m, [(sc[i] * R_REF, WG[(i, 0)]) for i in range(n)],            # the lip row: fine shaft to row 1
           [(sc[i] * R_REF, WG[(i, 1)]) for i in ec], DOWN, ZONE_ROCK)
    for a in range(ne - 1):
        for k in range(1, NQ):
            if (a, k) in used_e:
                continue
            ids = (WGe[(a, k)], WGe[(a + 1, k)], WGe[(a + 1, k + 1)], WGe[(a, k + 1)])
            if k + 1 < KC:
                want, zone = DOWN, ZONE_ROCK
            else:
                c = tuple(sum(m.verts[v][q] for v in ids) / 4.0 for q in range(3))
                want = wc_want(c)
                zone = ZONE_ROCK
                if k >= KC:
                    t, z = 0.5 * (sc[ec[a]] + sc[ec[a + 1]]), CEIL_Z - (0.5 * (qs[k] + qs[k + 1]) - LC)
                    zone = ZONE_SHADE if ribs(t * OUTER_R, z) > 0.45 else ZONE_ROCK
            m.quad(ids[0], ids[1], ids[2], ids[3], want, zone, best=True)
    for (ib, ii) in ((0, 1), (n - 1, n - 2)):
        t = sc[ib]
        A = [(LC * j / ceil_nv, CE(t, j)) for j in range(ceil_nv + 1)]
        for row in reversed(out_rows[:-1]):
            v = WR(row, t)
            A.append((LC + (CEIL_Z - m.verts[v][2]), v))
        B = [(qs[k], WG[(ii, k)]) for k in range(1, NQ + 1)]
        _strip(m, A, B, wc_want, ZONE_ROCK)

    # ---- what the collider, the stats and the renders need -----------------
    S1["spikes"], S1["fixtures"], S1["prisms"], S1["tites"] = spikes, fixtures, prisms, tites
    S1["counts"] = {"deck_cells": deck_cells, "fill_tris": fill_tris, "subcols": n,
                    "fixtures": len(fixtures), "columns": sum(1 for f in fixtures if f.kind == "column"),
                    "short": sum(1 for f in fixtures if f.kind == "mite" and f.H < S1_COVER_H),
                    "medium": sum(1 for f in fixtures if f.kind == "mite" and S1_COVER_H <= f.H < 3.8),
                    "tall": sum(1 for f in fixtures if f.kind == "mite" and f.H >= 3.8),
                    "tites": len(tites), "over": sum(1 for t in tites if t.over is not None),
                    "deck_holes": len(dblocks), "ceil_holes": len(cblocks)}
    S1["widths"] = sorted(2.0 * widest(f, S1_CHEST) for f in fixtures)
    S1["forest"] = _s1_forest(fixtures, H, lambda b, rad: deck_xy(T(b), rad))
    return lo, hi


def _s1_collider(c):
    """The section's deck follows the flowstone; a frustum stack under every
    stalagmite of a metre or more, every column and every low stalactite tip."""
    sc, H, deck_xy = S1["sc"], S1["H"], S1["deck_xy"]
    cols = list(sc)
    NJ = S1_NS
    rho = [INNER_R + (OUTER_R - INNER_R) * j / NJ for j in range(NJ + 1)]
    grid = []
    for t in cols:
        col = []
        for rr in rho:
            x, y = deck_xy(t, rr)
            col.append(c.v((x, y, DECK_Z + H(x, y))))
        grid.append(col)
    for i in range(len(cols) - 1):
        for j in range(NJ):
            c.quad(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1], UP, ZONE_ROCK)
    before = len(c.faces)
    for sp in S1["prisms"]:
        cx, cy = sp.cxy
        if sp.kind == "tite":
            lv = []
            for (z, scale) in ((sp.tip_z - 0.05, 0.3), (sp.tip_z + 0.7, 0.8), (sp.tip_z + 1.5, 1.0)):
                u = max(0.0, min(1.0, (sp.base_z - z) / sp.H))
                lv.append((z, [(dx * scale, dy * scale) for (dx, dy) in sp.section(u, sp.frame)]))
        else:
            hs = [0.3, 1.0, 2.2, 4.5, 7.0, 8.2] if sp.kind == "column" else \
                ([0.3, 1.0, 2.0, 0.92 * sp.H] if sp.H > 2.4 else [0.3, 0.6 * sp.H, 0.92 * sp.H])
            sh = sp.coll                                 # the pass-8 shape: the collider stands
            lv = []
            for k, h in enumerate(hs):
                u = min(1.0, h / sh.H)
                z = sp.deck_z - 0.1 if k == 0 else sp.deck_z + h
                lv.append((z, sh.section(u, sp.frame)))
        _s1_frustum(c, cx, cy, lv, sh.angs if sp.kind != "tite" else sp.angs, sp.frame)
    S1["coll_tris"] = len(c.faces) - before + 2 * (len(cols) - 1) * NJ


def _s1_blocked(eye, tgt, fixtures):
    """Does the sight line from eye to tgt pass through a fixture? Each is
    tested where the line passes nearest its axis, against its cross-section
    polygon at that height (and just before and after)."""
    dx, dy = tgt[0] - eye[0], tgt[1] - eye[1]
    L2 = dx * dx + dy * dy
    for sp in fixtures:
        f = ((sp.cxy[0] - eye[0]) * dx + (sp.cxy[1] - eye[1]) * dy) / L2
        if f < 0.7 or f > 1.02:
            continue
        px, py = eye[0] + dx * f, eye[1] + dy * f
        if math.hypot(px - sp.cxy[0], py - sp.cxy[1]) > 1.1:
            continue
        rings = [sp.base] + sp.rings
        for df in (-0.3 / math.sqrt(L2), 0.0, 0.3 / math.sqrt(L2)):
            g = f + df
            q = (eye[0] + dx * g, eye[1] + dy * g, eye[2] + (tgt[2] - eye[2]) * g)
            for (za, pa), (zb, pb) in zip(rings, rings[1:]):
                if za - 1e-9 <= q[2] <= zb + 1e-9 and zb > za:
                    w = (q[2] - za) / (zb - za)
                    poly = [((1 - w) * a[0] + w * c[0], (1 - w) * a[1] + w * c[1]) for a, c in zip(pa, pb)]
                    if _s1_inpoly((q[0], q[1]), poly):
                        return True
                    break
    return False


def _s1_forest(fixtures, H, deck_xy):
    """The forest property. The deck r S1_SAMPLE_R, 15..60 deg, on an
    S1_SAMPLE grid; a body (S1_SIGHT_H) is hidden when every sight line is
    blocked. From the centre eye: the fraction hidden and the largest
    connected hidden blob (metres across). From eyes S1_SHIFT to either side:
    the fraction of the centre-hidden samples that come into view. Then the
    routes: a 0.7 m runner along each of S1_BANDS from 15 to 60 deg with no
    gap under S1_ROUTE_GAP between feet."""
    et = _tangent(37.5)
    eyes = [(0.0, 0.0, S1_EYE_Z), (S1_SHIFT * et[0], S1_SHIFT * et[1], S1_EYE_Z),
            (-S1_SHIFT * et[0], -S1_SHIFT * et[1], S1_EYE_Z)]
    db = S1_SAMPLE / (math.radians(1.0) * 52.0)
    nb = int(round(45.0 / db))
    rs = []
    rr = S1_SAMPLE_R[0]
    while rr <= S1_SAMPLE_R[1] + 1e-9:
        rs.append(rr)
        rr += S1_SAMPLE
    hidden = {}
    for ib in range(nb + 1):
        b = 15.0 + 45.0 * ib / nb
        for ir, rad in enumerate(rs):
            x, y = deck_xy(b, rad)
            z0 = DECK_Z + H(x, y)
            near = [sp for sp in fixtures if abs(_bear_deg(math.atan2(sp.cxy[1], sp.cxy[0])) - b) < 4.0]
            hid = []
            for eye in eyes:
                hid.append(all(_s1_blocked(eye, (x, y, z0 + h), near) for h in S1_SIGHT_H))
            hidden[(ib, ir)] = hid
    total = len(hidden)
    centre = [k for k, v in hidden.items() if v[0]]
    frac = len(centre) / float(total)
    seen = sum(1 for k in centre if not hidden[k][1] or not hidden[k][2])
    shift = seen / float(len(centre)) if centre else 1.0
    # the largest connected hidden blob, 4-neighbour
    left = set(centre)
    blob = (0.0, 0.0)
    while left:
        k0 = left.pop()
        comp, stack = [k0], [k0]
        while stack:
            ib, ir = stack.pop()
            for nk in ((ib + 1, ir), (ib - 1, ir), (ib, ir + 1), (ib, ir - 1)):
                if nk in left:
                    left.remove(nk)
                    comp.append(nk)
                    stack.append(nk)
        across = ((max(c[0] for c in comp) - min(c[0] for c in comp) + 1) * S1_SAMPLE,
                  (max(c[1] for c in comp) - min(c[1] for c in comp) + 1) * S1_SAMPLE)
        if across[0] * across[1] > blob[0] * blob[1]:
            blob = across
    # routes: a free-space grid at 0.1 m, the runner's centre 0.6 m from any foot (a cell's tolerance allowed)
    step = 0.1
    feet = []
    for sp in fixtures:
        u = min(1.0, 0.3 / sp.H)
        feet.append((sp.cxy[0], sp.cxy[1], max(sp.radius(i, u) for i in range(sp.sides))))
    routes = []
    for (r0, r1) in S1_BANDS:
        nr = int(round((r1 - r0) / step))
        dbb = step / (math.radians(1.0) * 52.0)
        nbb = int(round(45.0 / dbb))
        free = {}
        for ib in range(nbb + 1):
            b = 15.0 + 45.0 * ib / nbb
            for ir in range(nr + 1):
                rad = r0 + (r1 - r0) * ir / nr
                x, y = deck_xy(b, rad)
                gap = min([2.0 * (math.hypot(x - fx, y - fy) - fr) for (fx, fy, fr) in feet] + [9.0])
                if gap >= S1_ROUTE_GAP - 1.5 * step:
                    free[(ib, ir)] = gap
        start = [(0, ir) for ir in range(nr + 1) if (0, ir) in free]
        best = {k: 9.0 for k in start}
        frontier = list(start)
        while frontier:
            nxt = []
            for (ib, ir) in frontier:
                for nk in ((ib + 1, ir), (ib - 1, ir), (ib, ir + 1), (ib, ir - 1)):
                    if nk in free:
                        g = min(best[(ib, ir)], free[nk])
                        if g > best.get(nk, -1.0):
                            best[nk] = g
                            nxt.append(nk)
            frontier = nxt
        ends = [best[(nbb, ir)] for ir in range(nr + 1) if (nbb, ir) in best]
        routes.append((bool(ends), max(ends) if ends else 0.0))
    return {"hidden": frac, "shift_seen": shift, "blob": blob, "routes": routes, "samples": total,
            "grid": hidden, "nb": nb, "rs": rs}



# =============================================================================
# THE ROCK
# =============================================================================

def _rock(r):
    m = _Mesh()
    ang = [2.0 * math.pi * (i + r.sf() * ANG_JAG) / SIDES for i in range(SIDES)]

    def T(deg):
        return _norm_t(ang[0], _bear_t(deg))

    cut0, cut1 = T(LAKE_A1), T(LAKE_A0)              # the channel's two banks
    bank0, bank1 = T(LAKE_A1 - LAKE_BANK), T(LAKE_A0 + LAKE_BANK)
    wl0, wl1 = T(WALL_A1), T(WALL_A0)                # the run down the shaft wall
    wb0, wb1 = T(WALL_A1 - WALL_BANK), T(WALL_A0 + WALL_BANK)

    # ---- S4: entry cut on a side boundary, exit cut where the last flight
    # lands (snapped to a base column when within COL_MERGE), a rounded bank
    # of two columns at each end ------------------------------------------
    lay = _s4_layout()
    s4w = math.radians(S4_BANK)
    s4c1 = ang[S4_CUT_SIDES[0]]                      # both cuts on side boundaries: exact
    s4c0 = ang[S4_CUT_SIDES[1]]
    assert 1.5 <= lay["exit_past_edge"] <= 2.5, "S4 exit lands %.2f m past the lava" % lay["exit_past_edge"]
    s4b0, s4b1 = s4c0 + s4w, s4c1 - s4w
    s4m0, s4m1 = s4c0 + S4_BANK_MID[0] * s4w, s4c1 - S4_BANK_MID[0] * s4w


    # ---- pit wall: courtyard up to the deck lip. Rings are level (their
    # radius steps, like cleaved rock) so a cell mouth is a rectangle in
    # (theta, z) and cuts cleanly across facet boundaries.
    pit_z = [COURTYARD_Z] + sorted(PIT_RINGS_Z) + [DECK_Z]
    npit = len(pit_z)
    pbias = _held(r, npit, PIT_JAG, one_sided=False)
    for i in range(SIDES):
        pbias[i][npit - 1] = 0.0                # the lip is exactly INNER_R
        a = ang[i]
        b = ang[i + 1] if i + 1 < SIDES else ang[0] + TWO_PI
        if (b > cut0 and a < cut1) or (s4c0 < a < s4c1):   # under the river and the field
            pbias[i][npit - 2] = 0.0            # the rim is exact too, so the channel welds to it
    pit = [_ring(m, ang, lambda i, k=k: INNER_R * (1.0 + pbias[i][k]), lambda i, k=k: pit_z[k])
           for k in range(npit)]

    def pit_zone(k, i):
        b = 0.5 * (pbias[i][k] + pbias[i][k + 1])   # +ve = back under the deck
        if b > EMBER_T * PIT_JAG and k < EMBER_BANDS:
            return ZONE_EMBER
        if b > SHADE_T * PIT_JAG:
            return ZONE_SHADE
        return ZONE_ROCK

    pit_wall = _Wall(m, ang, pit_z, pit, PIT_SUB, PIT_CAP, pit_zone)

    # ---- one column list for the deck and the outer wall. Inside the river
    # section it is the section's own, so nothing T-junctions anywhere. -------
    base_cols = []
    for i in range(SIDES):
        a = ang[i]
        b = ang[i + 1] if i + 1 < SIDES else ang[0] + TWO_PI
        base_cols += [a + (b - a) * su / ANG_SUB for su in range(ANG_SUB)]
    base_cols.append(ang[0] + TWO_PI)
    keep = _merge_cols([c for c in pit_wall.cols if cut0 < c < cut1]
                       + [c for c in base_cols if cut0 < c < cut1],
                       [cut0, cut1, bank0, bank1, wb0, wb1])
    sec_cols = _merge_cols(
        [T(LAKE_A0 + k) for k in range(int(LAKE_A1 - LAKE_A0) + 1)],
        keep + [wl0, wl1])
    # a bank stays one column wide, or it stops reading as a bank
    sec_cols = [t for t in sec_cols if not (cut0 < t < bank0 or bank1 < t < cut1)]
    lava_ts = _merge_cols(pit_wall.tbreaks(bank0, bank1),
                          [t for t in sec_cols if bank0 < t < bank1])   # the sea's rim
    # the deck, walls and fall: a river column within COL_MERGE of a wall
    # column yields to it, or the strip between them is a sliver
    sec_cols = [t for t in sec_cols
                if any(abs(t - k) < 1e-7 for k in keep)
                or all(abs(t - k) * CROSS_R > COL_MERGE for k in keep)]
    cols_all = _merge_cols([c for c in base_cols if not (cut0 < c < cut1)], sec_cols)
    s2 = _s2_setup(T, base_cols)                   # S2's river: its own columns too
    cols_all = _merge_cols(cols_all, s2["cols"])
    _s2_lines(s2, cols_all)
    s3 = _s3_setup(T, base_cols)                   # S3's minefield: its own columns too
    S3["L"] = s3
    cols_all = _merge_cols(cols_all, s3["cols"])
    s1_in = [t for t in cols_all if T(S1_EXT[1]) <= t <= T(S1_EXT[0])]
    s1_lo, s1_hi = s1_in[0], s1_in[-1]           # S1 re-lays everything between these

    def in_s1(t0, t1):
        return s1_lo - 1e-9 <= t0 and t1 <= s1_hi + 1e-9

    s4_fixed = [s4c0, s4m0, s4b0, s4b1, s4m1, s4c1]
    s4_keep = _merge_cols([c for c in pit_wall.cols if s4c0 < c < s4c1]
                          + [c for c in base_cols if s4c0 < c < s4c1], s4_fixed)
    s4_cols = [s4b1 - math.radians(1.0) * k for k in range(1, int((s4b1 - s4b0) / math.radians(1.0)) + 1)]
    s4_cols = [t for t in s4_cols if s4b0 < t < s4b1
               and all(abs(t - k) * CROSS_R > COL_MERGE for k in s4_keep)]
    s4_cols = _merge_cols(s4_keep, s4_cols)
    s4_cols = [t for t in s4_cols if not (s4c0 < t < s4b0 or s4b1 < t < s4c1) or t in (s4m0, s4m1)]
    s4_lava_ts = _merge_cols(pit_wall.tbreaks(s4b0, s4b1), [t for t in s4_cols if s4b0 < t < s4b1])
    cols_all = _merge_cols([c for c in cols_all if not (s4c0 < c < s4c1)], s4_cols)

    def s4_in(t):
        return s4c0 - 1e-9 <= t <= s4c1 + 1e-9

    def s4_z(t):
        """The field's floor height: the deck outside, the lava between the
        banks, a rounded two-column bank at each end."""
        if t <= s4c0 + 1e-9 or t >= s4c1 - 1e-9:
            return DECK_Z
        if s4b0 - 1e-9 <= t <= s4b1 + 1e-9:
            return LAVA_Z
        cut, mid, bank = (s4c0, s4m0, s4b0) if t < s4b0 else (s4c1, s4m1, s4b1)
        fm = S4_BANK_MID[1]
        if (t - mid) * (bank - mid) >= 0.0:
            f = fm + (1.0 - fm) * _ramp((t - mid) / (bank - mid), 0.0, 1.0)
        else:
            f = fm * _ramp((t - cut) / (mid - cut), 0.0, 1.0)
        return DECK_Z + (LAVA_Z - DECK_Z) * f

    # ---- the lava sea: what the pit floor is, and what lights it ------------
    _lava_sea(m, pit_wall, COURTYARD_Z, _Rng(LAVA_SEED), extra=lava_ts + s4_lava_ts)

    # ---- outer wall: deck up to the gallery ceiling ------------------------
    wall_z = [DECK_Z] + WALL_RINGS_Z + [CEIL_Z]
    nwall = len(wall_z)
    wbias = _held(r, nwall, WALL_JAG, one_sided=True)
    for i in range(SIDES):
        wbias[i][0] = wbias[i][nwall - 1] = 0.0     # foot and head exactly OUTER_R
    wzj = [[0.0 if k in (0, nwall - 1) else r.sf() * Z_JAG for k in range(nwall)]
           for _ in range(SIDES)]
    wall = [_ring(m, ang,
                  lambda i, k=k: OUTER_R * (1.0 + wbias[i][k]),
                  lambda i, k=k: wall_z[k] + wzj[i][k])
            for k in range(nwall)]

    def wall_zone(k):
        def zone(i):
            b = 0.5 * (wbias[i][k] + wbias[i][k + 1])
            return ZONE_SHADE if b > SHADE_T * WALL_JAG else ZONE_ROCK
        return zone

    # ---- upper pit wall: ceiling lip up to the rim ---------------------------
    up_z = [CEIL_Z] + UPPER_RINGS_Z + [RIM_Z]
    nup = len(up_z)
    ubias = _held(r, nup, PIT_JAG, one_sided=True)
    for i in range(SIDES):
        ubias[i][0] = 0.0                       # the lip is exactly INNER_R
    uzj = [[r.sf() * RIM_JAG if k == nup - 1 else 0.0 for k in range(nup)] for _ in range(SIDES)]
    upper = [_ring(m, ang,
                   lambda i, k=k: INNER_R * (1.0 + ubias[i][k]),
                   lambda i, k=k: up_z[k] + uzj[i][k])
             for k in range(nup)]

    def upper_zone(k, i):
        b = 0.5 * (ubias[i][k] + ubias[i][k + 1])
        return ZONE_SHADE if b > SHADE_T * PIT_JAG else ZONE_ROCK

    shaft = _Wall(m, ang, up_z, upper, 1, FAR_CAP, upper_zone)

    wfv = {}

    def WF(k, t):
        """Vertex on outer-wall ring k at a column angle; shared."""
        key = (k, round(t, 7))
        if key not in wfv:
            i, u = _side_u(ang, t)
            if u < 1e-9:
                wfv[key] = wall[k][i]
            elif u > 1.0 - 1e-9:
                wfv[key] = wall[k][(i + 1) % SIDES]
            else:
                wfv[key] = m.v(_chord(m, wall[k], ang, t))
        return wfv[key]

    # ---- the channel's floor height, and how far it is cut into the wall -----
    def chan_z(t):
        if t <= cut0 + 1e-9 or t >= cut1 - 1e-9:
            return s4_z(t)
        if bank0 - 1e-9 <= t <= bank1 + 1e-9:
            return LAVA_Z
        f = _ramp(t, cut0, bank0) if t < bank0 else _ramp(t, cut1, bank1)
        return DECK_Z + (LAVA_Z - DECK_Z) * f

    def wall_colf(t):
        """0 on the cut columns, 1 from the bank chains in: the wall's lava
        edge is the deck's own bank line."""
        if bank0 - 1e-9 <= t <= bank1 + 1e-9:
            return 1.0
        return 0.0


    # rows: (label, depth). Outside the river the wall keeps pass 4's rows;
    # inside, the fall's own rows: foot, FALL_ROWS, the rounded lip, the
    # shelf, the slot's roof, then plain wall up to the ceiling.
    OUT_ROWS = [((0, 0.0), 0.0), ((0, 0.5), 0.0), ((1, 0.0), 0.0), ((1, 0.5), 0.0),
                (("out", 0), 0.0), (("out", 1), 0.0), ((1, 1.0), 0.0)]
    IN_ROWS = [("low", RECESS_R), ((0, 0.0), RECESS_R)] \
        + [(("z", z), RECESS_R) for z in FALL_ROWS] \
        + [(("z", WALL_LAVA_TOP - d), RECESS_R + _lip(d)) for d in reversed(LIP_ROWS)] \
        + [(("z", WALL_LAVA_TOP), RECESS_R + LIP_R), ("shelf", SHELF_D), ("roof", SHELF_D),
           ("roof2", 0.0), ((1, 1.0), 0.0)]
    IN_ROW_I = {row[0]: BANK_WALL - 1 - k for k, row in enumerate(IN_ROWS[:BANK_WALL])}
    S4_ROWS = [("low", 0.0)] + OUT_ROWS          # the field: the foot drops to the lava, plain wall above
    fall_field = _field(_Rng(LAKE_SEED + 3), FALL_AMP)
    lines = (_bank_line(_Rng(LAKE_SEED + 1)), _bank_line(_Rng(LAKE_SEED + 4)))
    wrv = {}

    def wall_rec(row, t):
        return row[1] * wall_colf(t)

    def wall_da(i, t):
        """Angular offset of a lava column on bank-line row i."""
        if t <= cut0 + 1e-9 or t >= cut1 - 1e-9:
            return 0.0
        if abs(t - bank0) < 1e-9:
            return _bank_da(lines[0], 0, i, OUTER_R)
        if abs(t - bank1) < 1e-9:
            return _bank_da(lines[1], 1, i, OUTER_R)
        return (_bank_da(lines[0], 0, i, OUTER_R) * max(0.0, 1.0 - (t - bank0) * OUTER_R / BANK_REACH)
                + _bank_da(lines[1], 1, i, OUTER_R) * max(0.0, 1.0 - (bank1 - t) * OUTER_R / BANK_REACH))

    def WR(row, t):
        """A wall vertex. Outside the river: on the wall's own rings. Inside:
        a straight drop at the foot's radius plus the row's depth, the lava
        columns swung by the bank line on that row."""
        lab, _depth = row
        d = wall_rec(row, t)
        if lab == (0, 0.0) and d < EPS:
            return WF(0, t)
        if lab == (1, 1.0):
            return WF(nwall - 1, t)
        if lab == "low" and d < EPS and abs(chan_z(t) - DECK_Z) < 1e-9:
            return WF(0, t)
        if lab[0] in ("out", 0, 1):                   # pass 4's rows, on the rings
            if lab[0] == "out":
                za, zb = m.verts[WF(1, t)][2], m.verts[WF(nwall - 1, t)][2]
                k, f = 1, (WALL_ROWS_OUT[lab[1]] - za) / (zb - za)
            else:
                k, f = lab
            pa, pb = m.verts[WF(k, t)], m.verts[WF(k + 1, t)]
            key = (k, round(f, 7), round(d, 5), round(t, 7))
            if key not in wrv:
                wrv[key] = m.v(_push(tuple((1.0 - f) * pa[c] + f * pb[c] for c in range(3)), d))
            return wrv[key]
        key = (lab, round(d, 5), round(t, 7))
        if key not in wrv:
            foot = m.verts[WF(0, t)]
            if lab == "low":
                z = chan_z(t)
            elif lab == "shelf":
                z = WALL_LAVA_TOP
            elif lab in ("roof", "roof2"):
                z = WALL_LAVA_TOP + SLOT_H
            else:
                z = lab[1]
            rad = math.hypot(foot[0], foot[1]) + d
            i = IN_ROW_I.get(lab, 0)
            a = t + wall_da(i, t)
            p = (rad * math.cos(a), rad * math.sin(a), z)
            if lab[0] == "z" and lab[1] in FALL_ROWS and bank0 + 1e-9 < t < bank1 - 1e-9:
                p = _push(p, fall_field(t * OUTER_R, z))
            wrv[key] = m.v(p)
        return wrv[key]

    # ---- outer wall. Over the river the deck is gone, so the wall carries on
    # down to the channel; over WALL_A0..WALL_A1 its lower 8 m are cut back
    # RECESS_R and re-laid in the river's material, banks and all; at the top
    # of the fall a flat shelf of river runs SHELF_D back under the ceiling. --
    def row_z(row, t):
        return m.verts[WR(row, t)][2]

    for ci in range(len(cols_all) - 1):
        t0, t1 = cols_all[ci], cols_all[ci + 1]
        if in_s1(t0, t1):
            continue
        am = 0.5 * (t0 + t1)
        want = (-math.cos(am), -math.sin(am), 0.0)
        side = _side_u(ang, am)[0]
        in0 = cut0 + 1e-9 < t0 < cut1 - 1e-9          # the cut columns carry the
        in1 = cut0 + 1e-9 < t1 < cut1 - 1e-9          # wall's own rows
        if in0 != in1:
            # a cut column carries the wall's rows, its neighbour the fall's:
            # zip the two chains, the bank of the channel between them
            rows0 = IN_ROWS if in0 else OUT_ROWS
            rows1 = IN_ROWS if in1 else OUT_ROWS
            A = [(row_z(row, t0), WR(row, t0)) for row in rows0]
            B = [(row_z(row, t1), WR(row, t1)) for row in rows1]
            roof = WALL_LAVA_TOP + 0.5 * SLOT_H
            _strip(m, A, B, (-math.cos(am), -math.sin(am), 0.0),
                   lambda c: ZONE_ROCK if c[2] > roof else ZONE_SHADE)
            continue
        rows = S4_ROWS if (s4_in(t0) or s4_in(t1)) else (IN_ROWS if in0 else OUT_ROWS)
        for ri in range(len(rows) - 1):
            lo, hi = rows[ri], rows[ri + 1]
            a0, a1 = WR(lo, t0), WR(lo, t1)
            b0, b1 = WR(hi, t0), WR(hi, t1)
            if a0 == b0 and a1 == b1:
                continue
            face_want = want
            if hi[0] == "shelf":                       # the shelf: flat river
                face_want, zone = UP, ZONE_RIVER
            elif lo[0] == "shelf":                     # the back of the slot
                zone = ZONE_SHADE
            elif lo[0] == "roof":                      # the slot's roof
                face_want, zone = DOWN, ZONE_ROCK
            elif lo[0] == "roof2":                     # plain wall over the slot
                zone = wall_zone(1)(side)
            else:
                recs = [wall_rec(lo, t0), wall_rec(lo, t1), wall_rec(hi, t0), wall_rec(hi, t1)]
                if min(recs) > RECESS_R - EPS:
                    zone = ZONE_FALL
                elif max(recs) > EPS:
                    zone = ZONE_SHADE                  # a bank of the channel
                else:
                    lab = lo[0]
                    ring = 0 if lab == "low" else (int(lab[1] > WALL_RINGS_Z[0]) if lab[0] == "z"
                                                   else (1 if lab[0] == "out" else lab[0]))
                    zone = wall_zone(ring)(side)
            if a0 == b0:
                m.tri(a0, a1, b1, face_want, zone)
            elif a1 == b1:
                m.tri(a0, a1, b0, face_want, zone)
            else:
                m.quad(a0, a1, b1, b0, face_want, zone, best=in0)

    # ---- the deck: a flat annulus on the river's own radial stations, its
    # surface dropped RECESS_Z into a channel between two sloped banks --------
    rf_out = [(rr - INNER_R) / (OUTER_R - INNER_R) for rr in RST]
    for t in cols_all[:-1]:
        pit_wall.add_xt(len(pit_wall.rows) - 1, t)
    floor_field = _field(_Rng(LAKE_SEED + 2), FLOOR_AMP)
    pit_tris, PN = _pit_lava(m, pit_wall, bank0, bank1, cut0, cut1,
                             [t for t in cols_all if bank0 <= t <= bank1], lava_ts, lines)
    _pit_bank_ends(m, pit_wall, cut0, cut1, bank0, bank1, PN)
    s4_lines = (_s4_bank_line(_Rng(S4_SEED + 1)), _s4_bank_line(_Rng(S4_SEED + 4)))
    s4_field = _field(_Rng(S4_SEED + 2), S4_FLOOR_AMP)
    s4_pit_tris, S4PN = _pit_lava(m, pit_wall, s4b0, s4b1, s4c0, s4c1,
                                  [t for t in cols_all if s4b0 <= t <= s4b1], s4_lava_ts, s4_lines)
    for cut, mid, bank in ((s4c0, s4m0, s4b0), (s4c1, s4m1, s4b1)):
        # the bank's end at the pit lip: a fan from the cut's rim vertex over
        # the wall's hole edge and the bank's own lip chain. Every vertex but
        # the bank's lip is on the pit wall, so the wall's own way out is the
        # confident one -- the tangent is near enough edge-on to be a guess.
        want = (-math.cos(cut), -math.sin(cut), 0.0)
        chain = [pit_wall.W(cut, LAVA_Z), pit_wall.W(bank, LAVA_Z)]
        if S4PN(bank, LAVA_Z) != pit_wall.W(bank, LAVA_Z):
            chain.append(S4PN(bank, LAVA_Z))
        chain.append(pit_wall.W(mid, s4_z(mid)))
        _fan_at(m, pit_wall.W(cut, DECK_Z), chain, want, ZONE_SHADE)

    def in_chan(t):
        """Columns on the channels' own stations. S4's cuts are side
        boundaries and keep the deck's stations, so the deck outside is the
        deck it was; its bank is the strip from there to the middle column."""
        return cut0 - 1e-9 <= t <= cut1 + 1e-9 or (s4c0 + 1e-9 < t < s4c1 - 1e-9)

    def s4_pt(t, j, p, r_lip, r_foot):
        """A field vertex: the two end banks wander on their own lines, the
        lava carries its own 2-D field, flat at the lip and the foot."""
        rad = math.hypot(p[0], p[1])
        i = BANK_WALL - 1 + (len(RST_RIVER) - 1 - j)
        z = p[2]
        tongue = _s4_tongue(rad)
        if abs(t - s4c0) < 1e-9 or abs(t - s4c1) < 1e-9:
            da = 0.0                                   # the cut is a side boundary: the deck's own
        elif abs(t - s4m0) < 1e-9:
            da = 0.5 * _bank_da(s4_lines[0], 0, i, rad) + s4_lines[0][i][0] / rad
        elif abs(t - s4m1) < 1e-9:
            da = 0.5 * _bank_da(s4_lines[1], 1, i, rad) - s4_lines[1][i][0] / rad
            da += ((s4b1 - 0.1 / rad - s4m1) - da) * tongue    # under the pad: level to the lava
            z += (DECK_Z - z) * tongue
        elif abs(t - s4b0) < 1e-9:
            da = _bank_da(s4_lines[0], 0, i, rad)
        elif abs(t - s4b1) < 1e-9:
            da = _bank_da(s4_lines[1], 1, i, rad) * (1.0 - tongue)
        else:
            da = (_bank_da(s4_lines[0], 0, i, rad) * max(0.0, 1.0 - (t - s4b0) * rad / BANK_REACH)
                  + _bank_da(s4_lines[1], 1, i, rad) * max(0.0, 1.0 - (s4b1 - t) * rad / BANK_REACH))
        a = t + da
        x, y = rad * math.cos(a), rad * math.sin(a)
        if s4_z(t) < LAVA_Z + 1e-9:
            z += _ramp(rad - r_lip, 0.0, 0.8) * _ramp(r_foot - rad, 0.0, 0.8) * s4_field(x, y)
        return (x, y, z)

    def river_pt(t, j, p, r_lip, r_foot):
        if s4_in(t):
            return s4_pt(t, j, p, r_lip, r_foot)
        """A channel vertex: its column's line wanders with the nearer bank,
        and the floor carries the 2-D field, flat at the lip and the foot."""
        rad = math.hypot(p[0], p[1])
        i = BANK_WALL - 1 + (len(RST_RIVER) - 1 - j)       # bank-line row of this station
        if abs(t - cut0) < 1e-9:
            da = lines[0][i][0] / rad
        elif abs(t - cut1) < 1e-9:
            da = -lines[1][i][0] / rad
        elif abs(t - bank0) < 1e-9:
            da = _bank_da(lines[0], 0, i, rad)
        elif abs(t - bank1) < 1e-9:
            da = _bank_da(lines[1], 1, i, rad)
        else:
            da = (_bank_da(lines[0], 0, i, rad) * max(0.0, 1.0 - (t - bank0) * rad / BANK_REACH)
                  + _bank_da(lines[1], 1, i, rad) * max(0.0, 1.0 - (bank1 - t) * rad / BANK_REACH))
        a = t + da
        x, y = rad * math.cos(a), rad * math.sin(a)
        z = p[2]
        if chan_z(t) < LAVA_Z + 1e-9:
            z += _ramp(rad - r_lip, 0.0, 0.8) * _ramp(r_foot - rad, 0.0, 0.8) * floor_field(x, y)
        return (x, y, z)

    dv = {}

    def foot(t):
        if s4_in(t):
            return WR(S4_ROWS[0], t)
        return WR(IN_ROWS[0], t) if in_chan(t) else WF(0, t)

    def DV(t, j, fine=False):
        """Deck vertex at station j: the deck's stations are fractions of the
        lip-to-foot run; the channel's are absolute radii (RST_RIVER), with
        the foot beyond them where the fall is cut back into the wall."""
        if j == 0:
            if bank0 - 1e-9 <= t <= bank1 + 1e-9:
                return PN(t, LAVA_Z)
            if s4b0 - 1e-9 <= t <= s4b1 + 1e-9:
                return S4PN(t, LAVA_Z)
            return pit_wall.W(t, chan_z(t))
        key = (round(t, 7), j, fine)
        if key in dv:
            return dv[key]
        pa, pb = m.verts[DV(t, 0)], m.verts[foot(t)]
        if not fine:
            if j == len(RST) - 1:
                return foot(t)
            f = rf_out[j]
            dv[key] = m.v(tuple((1.0 - f) * pa[c] + f * pb[c] for c in range(3)))
            return dv[key]
        r_foot = math.hypot(pb[0], pb[1])
        if j == len(RST_RIVER) - 1:
            return foot(t)
        p = (RST_RIVER[j] * math.cos(t), RST_RIVER[j] * math.sin(t), chan_z(t))
        dv[key] = m.v(river_pt(t, j, p, math.hypot(pa[0], pa[1]), r_foot))
        return dv[key]

    s3v = {}
    S3_ST = s3["stations"]

    def s3_xy(t, rho):
        """The plan point of a station at column t. The lip and the wall foot
        are the ring's own chord points, so the section's grid meets the
        ring's rings exactly and the collider built from it lands on the art
        mesh rather than beside it. Every station between is TRUE polar: the
        ring's sides are jittered 32-gon chords, so a chord-interpolated frame
        is up to 7 % short of a metre and a 2.5 m pad laid in it would not fit
        its 2.7 m column; the band at each edge absorbs the chord's sagitta."""
        if INNER_R + EPS < rho < OUTER_R - EPS:
            return (rho * math.cos(t), rho * math.sin(t))
        pa, pb = _chord(m, pit[npit - 1], ang, t), _chord(m, wall[0], ang, t)
        f = (rho - INNER_R) / (OUTER_R - INNER_R)
        return ((1 - f) * pa[0] + f * pb[0], (1 - f) * pa[1] + f * pb[1])

    S3["deck_xy"] = s3_xy
    _s3_patch_rects(s3)                 # which deck cells the cracks take over

    def S3V(t, j):
        """A minefield station's vertex at column t. The pit lip and the wall
        foot are the deck's own vertices, so the section welds to the ring
        outside it without a single duplicate position."""
        if j == 0:
            return DV(t, 0)
        if j == len(S3_ST) - 1:
            return foot(t)
        key = (round(t, 7), j)
        if key not in s3v:
            x, y = s3_xy(t, S3_ST[j])
            s3v[key] = m.v((x, y, DECK_Z + _s3_h(s3, t, S3_ST[j])))
        return s3v[key]

    def s3_chain(t, inside):
        if inside:
            return [(S3_ST[j], S3V(t, j)) for j in range(len(S3_ST))]
        return [(RST[j], DV(t, j)) for j in range(len(RST))]

    s2v, s2p = {}, {}

    def S2V(t, j):
        """A river station's vertex at column t; lip and wall foot are the deck's own."""
        if j == 0:
            return DV(t, 0)
        if j == S2_NST - 1:
            return foot(t)
        key = (round(t, 7), j)
        if key not in s2v:
            if round(t, 7) not in s2p:
                fw = m.verts[foot(t)]
                s2p[round(t, 7)] = _s2_profile(s2, t, math.hypot(fw[0], fw[1]))
            rad, z = s2p[round(t, 7)][j - 1]
            s2v[key] = m.v((rad * math.cos(t), rad * math.sin(t), z))
        return s2v[key]

    def s2_chain(t, inside):
        if inside:
            return [(j, S2V(t, j)) for j in range(S2_NST)]
        return [(RST[j], DV(t, j)) for j in range(len(RST))]

    for ci in range(len(cols_all) - 1):
        t0, t1 = cols_all[ci], cols_all[ci + 1]
        if in_s1(t0, t1):
            continue
        s3in0 = s3["s0"] - 1e-9 <= t0 <= s3["s1"] + 1e-9
        s3in1 = s3["s0"] - 1e-9 <= t1 <= s3["s1"] + 1e-9
        if s3in0 and s3in1:                            # S3: the minefield's field
            for j in range(len(S3_ST) - 1):
                if _s3_in_patch(t0, t1, j):            # a crack patch lays this cell
                    continue
                ids = (S3V(t0, j), S3V(t1, j), S3V(t1, j + 1), S3V(t0, j + 1))
                m.quad(ids[0], ids[1], ids[2], ids[3], UP, _s3_zone(m, ids), best=True)
            continue
        if s3in0 or s3in1:                             # its ends meet the plain deck
            _strip(m, s3_chain(t0, s3in0), s3_chain(t1, s3in1), UP, ZONE_DECK)
            continue
        s2in0 = s2["s0"] - 1e-9 <= t0 <= s2["s1"] + 1e-9
        s2in1 = s2["s0"] - 1e-9 <= t1 <= s2["s1"] + 1e-9
        if s2in0 and s2in1:                            # S2: the river along the deck
            f0, f1 = _s2_f(s2, t0), _s2_f(s2, t1)
            for j in range(S2_NST - 1):
                m.quad(S2V(t0, j), S2V(t1, j), S2V(t1, j + 1), S2V(t0, j + 1),
                       UP, _s2_zone(j, f0, f1), best=True)
            continue
        if s2in0 or s2in1:                             # its lips meet the plain deck
            _strip(m, s2_chain(t0, s2in0), s2_chain(t1, s2in1), UP, ZONE_DECK)
            continue
        z0, z1 = chan_z(t0), chan_z(t1)
        if z0 < LAVA_Z + 1e-9 and z1 < LAVA_Z + 1e-9:
            zone = ZONE_RIVER
        elif z0 < DECK_Z - 1e-9 or z1 < DECK_Z - 1e-9:
            zone = ZONE_SHADE                          # the channel's end banks
        else:
            zone = ZONE_DECK
        in0, in1 = in_chan(t0), in_chan(t1)
        if in0 and in1:
            n = len(RST_RIVER)
            for j in range(n - 1):
                m.quad(DV(t0, j, True), DV(t1, j, True), DV(t1, j + 1, True),
                       DV(t0, j + 1, True), UP, zone, best=True)
        elif in0 or in1:                               # the channel's fine stations
            _strip(m, [((RST_RIVER if in0 else RST)[j], DV(t0, j, in0))
                       for j in range(len(RST_RIVER if in0 else RST))],
                   [((RST_RIVER if in1 else RST)[j], DV(t1, j, in1))
                    for j in range(len(RST_RIVER if in1 else RST))], UP, zone)
        else:
            for j in range(len(RST) - 1):
                m.quad(DV(t0, j), DV(t1, j), DV(t1, j + 1), DV(t0, j + 1), UP, zone)

    _s3_patches(m, S3V)                 # the cracks, welded into the grid's own vertices

    S4["edges"] = {}
    for side, (cut, mid, bank) in enumerate(((s4c0, s4m0, s4b0), (s4c1, s4m1, s4b1))):
        S4["edges"][side] = [[(RST_RIVER[j] * math.cos(cut), RST_RIVER[j] * math.sin(cut), DECK_Z)]
                             + [m.verts[DV(t, j, True)] for t in (mid, bank)]
                             for j in range(len(RST_RIVER))]

    # ---- the gallery ceiling: a flat annulus on the same columns as the wall
    # it meets, so its head seam carries no T-junction either -----------------
    ceil_nv = _nv(OUTER_R - INNER_R)
    for t in cols_all[:-1]:
        shaft.add_xt(0, t)
    cev = {}

    def CE(t, j):
        if j == 0:
            return shaft.W(t, CEIL_Z)
        if j == ceil_nv:
            return WF(nwall - 1, t)
        key = (round(t, 7), j)
        if key not in cev:
            pa, pb = m.verts[shaft.W(t, CEIL_Z)], m.verts[WF(nwall - 1, t)]
            f = j / float(ceil_nv)
            cev[key] = m.v(tuple((1.0 - f) * pa[c] + f * pb[c] for c in range(3)))
        return cev[key]

    for ci in range(len(cols_all) - 1):
        t0, t1 = cols_all[ci], cols_all[ci + 1]
        if in_s1(t0, t1):
            continue
        for j in range(ceil_nv):
            m.quad(CE(t0, j), CE(t1, j), CE(t1, j + 1), CE(t0, j + 1),
                   (0.0, 0.0, -1.0), ZONE_ROCK)

    # ---- S1: the stalactite cave, grown into all of the above ---------------
    _s1_sculpt(m, ang, cols_all, s1_lo, s1_hi, pit_wall, shaft, pit[npit - 1], wall, upper, WF, WR, CE, DV, ceil_nv, OUT_ROWS)

    # ---- the cells, the river's run down the pit wall, then the faces they
    # were cut from -----------------------------------------------------------
    for c in _place_cells(_Rng(CELL_SEED), pit_wall, shaft):
        if c["z"] < DECK_Z:
            t = pit_wall._norm(c["s"] / INNER_R)
            if cut0 - 0.02 < t < cut1 + 0.02:
                continue                       # the channel runs down here
            hw = 0.5 * c["w"] / INNER_R
            if t - hw < s4b1 and t + hw > s4b0:
                continue                       # ... and the field's fall
            _carve(m, pit_wall, c)
        else:
            _carve(m, shaft, c)
    _build_platforms(m, _Rng(LAKE_SEED))
    _s2_build(m, s2, _Rng(S2_SEED + 1))
    m.span("cover_s2", _s2_wall)
    s4r = _Rng(S4_SEED + 5)
    for rock in lay["rocks"]:
        _s4_rock(m, s4r, rock)
    m.span("cover_s4", _s4_wall)
    pit_wall.emit()
    shaft.emit()

    # ---- hell's ground above the rim ---------------------------------------
    prev = upper[nup - 1]
    for g, (gr, gz) in enumerate(GROUND_RINGS):
        rj = [r.sf() * GROUND_RJAG for _ in range(SIDES)]
        zj = [r.sf() * GROUND_ZJAG[g] for _ in range(SIDES)]
        ring = _ring(m, ang, lambda i: gr * (1.0 + rj[i]), lambda i: gz + zj[i])
        for i in range(SIDES):
            j = (i + 1) % SIDES
            m.quad(prev[i], prev[j], ring[j], ring[i], UP, ZONE_ROCK)
        prev = ring
    _lip_walls(m)
    print("MDL STATS healed_t_junctions=%d" % _heal(m))
    print("MDL STATS buried_faces_dropped=%d" % _cull_buried(m))
    return m, ang, (len(sec_cols), pit_tris), (cut0, cut1), s2, (s4c0, s4b0, s4b1, s4c1)


# =============================================================================
# COLLISION -- flat deck, clean walls, courtyard floor. Nothing jittered.
# =============================================================================

def _s4_collider(c, r, s4):
    """S4: a flat surface at the lava height, lip to foot, bank to bank, minus
    the rocks' footprints; then the rocks, crest and all, straight-sided."""
    s4c0, s4b0, s4b1, s4c1 = s4
    lay = _s4_layout()
    for side in (0, 1):                     # the end banks: deck to the middle column, a step down
        chain = lay["edges"][side]
        top = [[c.v((p[0], p[1], DECK_Z)) for p in row[:2]] for row in chain]
        low = [[c.v((p[0], p[1], LAVA_Z)) for p in row[1:]] for row in chain]
        for j in range(len(chain) - 1):
            c.quad(top[j][0], top[j][1], top[j + 1][1], top[j + 1][0], UP, ZONE_ROCK, best=True)
            c.quad(low[j][0], low[j][1], low[j + 1][1], low[j + 1][0], UP, ZONE_ROCK, best=True)
            c.quad(top[j][1], top[j + 1][1], low[j + 1][0], low[j][0],
                   _tangent(0.0) if side else _tangent(180.0), ZONE_ROCK, best=True)
    step = math.radians(1.0)
    ts = [s4b1 - step * k for k in range(1, int((s4b1 - s4b0) / step) + 1)]
    ts = _merge_cols([t for t in ts if (t - s4b0) * CROSS_R > COL_MERGE
                      and (s4b1 - t) * CROSS_R > COL_MERGE], [s4b0, s4b1])
    grid = [[c.v((rr * math.cos(t), rr * math.sin(t), LAVA_Z)) for rr in LAVA_COLL_RST] for t in ts]
    nr = len(LAVA_COLL_RST)
    for i in range(len(ts) - 1):
        for j in range(nr - 1):
            mid = (0.5 * (LAVA_COLL_RST[j] + LAVA_COLL_RST[j + 1]) * math.cos(0.5 * (ts[i] + ts[i + 1])),
                   0.5 * (LAVA_COLL_RST[j] + LAVA_COLL_RST[j + 1]) * math.sin(0.5 * (ts[i] + ts[i + 1])))
            if any(_s4_inside(rk, mid, q_max=0.9) for rk in lay["rocks"]):
                continue
            c.quad(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1], UP, ZONE_ROCK)
    for rk in lay["rocks"]:
        _s4_rock(c, r, rk, coll=True)
    c.span("cover_s4", _s4_wall, coll=True)


def _collider(ang, cut0, cut1, s2, s4):
    c = _Mesh()
    lip = _ring(c, ang, lambda i: INNER_R, lambda i: DECK_Z)
    foot = _ring(c, ang, lambda i: OUTER_R, lambda i: DECK_Z)
    pit_foot = _ring(c, ang, lambda i: INNER_R, lambda i: COURTYARD_Z)
    head = _ring(c, ang, lambda i: OUTER_R, lambda i: CEIL_Z)
    ceil_lip = _ring(c, ang, lambda i: INNER_R, lambda i: CEIL_Z)
    for i in range(SIDES):
        j = (i + 1) % SIDES
        c.quad(ceil_lip[i], ceil_lip[j], head[j], head[i],
               (0.0, 0.0, -1.0), ZONE_SHADE)                           # ceiling
    c.fan(pit_foot, UP, ZONE_SHADE)                                    # courtyard
    c.band(foot, head, ang, True, lambda i: ZONE_ROCK)                 # outer wall

    # Deck and pit wall are cut where the river runs: no deck collision over it
    # and the lip comes down to the trench, so nothing invisible dams the lava.
    dcols = _merge_cols(list(ang) + [ang[0] + TWO_PI],
                        [cut0, cut1, s2["s0"], s2["s1"], s4[0], s4[3],
                         S3["L"]["s0"], S3["L"]["s1"]])
    cv = {}

    def CV(tag, ring, t, z=None):
        key = (tag, round(t, 7))
        if key not in cv:
            p = _chord(c, ring, ang, t)
            cv[key] = c.v(p if z is None else (p[0], p[1], z))
        return cv[key]

    s1_lo, s1_hi = S1["lo"], S1["hi"]
    dcols = _merge_cols(dcols, [s1_lo, s1_hi])
    for ci in range(len(dcols) - 1):
        t0, t1 = dcols[ci], dcols[ci + 1]
        inside = (t0 >= cut0 - 1e-9 and t1 <= cut1 + 1e-9) \
            or (t0 >= s4[0] - 1e-9 and t1 <= s4[3] + 1e-9)
        tz = LAVA_Z if inside else DECK_Z                  # the rim drops to the river
        am = 0.5 * (t0 + t1)
        inward = (-math.cos(am), -math.sin(am), 0.0)
        a0 = CV("lip%.2f" % tz, lip, t0, tz)
        a1 = CV("lip%.2f" % tz, lip, t1, tz)
        c.quad(CV("foot", pit_foot, t0), CV("foot", pit_foot, t1), a1, a0,
               inward, ZONE_SHADE)                                     # pit wall
        if (inside or (t0 >= s2["s0"] - 1e-9 and t1 <= s2["s1"] + 1e-9)
                or (S3["L"]["s0"] - 1e-9 <= t0 and t1 <= S3["L"]["s1"] + 1e-9)
                or (s1_lo - 1e-9 <= t0 and t1 <= s1_hi + 1e-9)):
            continue                                       # the rivers, S1 and S3 lay their own
        c.quad(a0, a1, CV("out", foot, t1), CV("out", foot, t0), UP, ZONE_ROCK)

    _lake_collider(c, _Rng(LAKE_SEED))
    _s2_collider(c, s2, ang, lip, foot, CV)
    _s1_collider(c)
    _s3_collider(c)
    _s4_collider(c, _Rng(S4_SEED + 5), s4)
    _shelf_box(c)
    _lip_walls(c, coll=True)
    return c


# =============================================================================
# THE LIP WALLS -- one at each section boundary, and the big one at the start
# =============================================================================
# Ryan: "the fucking cover between sections are still fucking tunnel. ive said
# multiple times now not tunnels ... it just needs to be a fucking wall on the
# right side." The lap runs toward rising bearing (PrisonerStart at 5, the
# finish at 335) and forward x up points at the axis, so the runner's RIGHT is
# the pit lip. Each boundary therefore carries a wall standing ON the lip,
# tangential to the ring, in the map's own rock: the rock_wall prop's language
# (about 8 m long, 3 m tall, 1.3 m thick, a ragged top), no mouth, no arch,
# nothing across the deck, nothing near the ceiling. The runner passes it on
# the outer side and it is cover from the tower while they cross the boundary:
# the guard's eye is (0, 28.90, 0), a standing head on the lane is 24.80, and
# that line crosses r 47.55 at 2.15 m over the deck -- under a 3 m wall by
# 0.85 m, with the whole deck width behind it (at r 57 the line is 2.48 m).
# The screen at the start (-8..14, 4.6 m tall) was already this: it stays as
# the big one, and the 13 deg gate that stood across the lane is gone with
# the other four tunnels.
#
# The bearings are the boundaries the dividers stood at; 8 m at r 47.55 is
# 9.64 deg. Where the 204 wall's sinking end (199.2..200.7) overlaps the last
# 0.8 deg of S3's own half wall (r 46.7..47.45, to 200.0) the two grow into
# one another; nothing of S3's is touched.
LIP_WALLS = [                 # name, first and last bearing, head z, deg of taper
    #                           at each end, head jitter (up only), seed
    dict(name="013", b0=-8.0, b1=14.0, top=27.60, taper=2.0, jag_z=0.12, seed=4180933),
    dict(name="066", b0=61.7, b1=71.3, top=26.00, taper=1.5, jag_z=0.35, seed=4170923),   # S1 | S2
    dict(name="139", b0=134.2, b1=143.8, top=26.00, taper=1.5, jag_z=0.35, seed=6290381), # S2 | S3
    # S3 | S4. Ryan: "the cover on section 4 is too far towards the inner part
    # of the ring, and it jets out of the corner, either move it in a little
    # bit or thin it out." Its inner face is already on the lip, so it is
    # thinned: r_out 48.20 -> 47.50 puts its drawn face (47.56..47.76) on S3's
    # own half wall's line (47.56..47.58) instead of 0.78-0.86 m out into the
    # path's inner column at the corner.
    dict(name="204", b0=199.2, b1=208.8, top=26.00, taper=1.5, jag_z=0.35,
         r_out=47.50, seed=5310947),
    # S4 | S5: 1.3 m thick as it was, moved 0.5 m out so its inner face is clear of the lip.
    dict(name="286", b0=281.2, b1=290.8, top=26.00, taper=1.5, jag_z=0.35,
         r_in=47.40, r_out=48.70, seed=7720261),
]
LIP_EYE_Z = 28.90             # the guard's eye, as RingBake and S3 trace it
LIP_R_IN = 46.90              # inner face: on the lip (INNER_R 46.70), unless a row carries its own r_in
LIP_R_OUT = 48.20             # outer face: 1.3 m thick, unless a row carries its own r_out
                              # (204 and 286 do). Ryan's 50.40 is on the start line --
                              # the field is dealt sideways from lane r 52.0 at 2.0 m, so the
                              # innermost body dealt stands at r 49.0 and is 0.4 m wide
LIP_BASE_Z = 22.20            # foot, buried: under the deck and under every sunken floor
LIP_END_Z = DECK_Z - 0.15     # the tapered ends finish under the deck surface
LIP_STEP = 1.10               # deg per column ...
LIP_COARSE = 3                # ... times this for the collider
LIP_HEAD = (-1.0, -0.4, 0.25, 1.0)    # rows across the head, of the half thickness
LIP_CROWN = 0.40              # the head is domed over the head z, never under it ...
LIP_CROWN_END = 0.25          # ... and keeps this much of it where it sinks, so no
                              # three points of an end cap are ever in line
LIP_MID = 0.55                # each face carries a row at this fraction of its height
LIP_SKIN_IN = 0.14            # the drawn faces stand this far proud of the envelope ...
LIP_SKIN_OUT = 0.26
LIP_JAG_IN = 0.10             # ... and each column recesses back into it by up to this,
LIP_JAG_OUT = 0.20            # so the collider is never outside the rock that is drawn
LIP_JAG_RUN = (1, 3)          # columns a jitter value is held for
LIP_PROVE_STEP = 0.05         # metres between crest samples in the proof
LIP_PROVE_R = (50.2, 52.0, 53.8)      # the lane, edge to edge: where a body stands behind a wall
LIP_BODY_Z = (0.4, 1.0, 1.65, 1.8)    # ... and the points of it that must all be hidden
LIP_PAST = 1.5                # deg past each end where the lane must be open and is looked at


def _lip_walls(m, coll=False):
    """Every lip wall, appended last so the rest of the map is untouched. Each
    carries its own seed and draws nothing from the map's own random streams,
    so the geometry before this call is triangle-identical with the walls in
    or out."""
    tris = 0
    for w in LIP_WALLS:
        tris += m.span("lip" + w["name"], _lip_screen, w, coll=coll)
    print("MDL STATS lip_walls n=%d %s_tris=%d" % (len(LIP_WALLS), "collision" if coll else "visual", tris))
    return tris


def _lip_prove(ob):
    """Raycast on the BUILT rock, per wall: the crest by a ray down every
    LIP_PROVE_STEP along its full-height run; every standing body on the lane
    behind that run hidden from the guard's eye at every one of its points;
    the lane a body's stride past each end at deck height and in the eye's
    view, so the wall is a wall and not a gate."""
    import mathutils
    eye = mathutils.Vector((0.0, 0.0, LIP_EYE_Z))

    def down(b, rad):
        hit, loc, _n, _i = ob.ray_cast(mathutils.Vector(pol(b, rad, CEIL_Z - 0.5)),
                                       mathutils.Vector((0.0, 0.0, -1.0)))
        return loc.z - DECK_Z if hit else None

    def seen(b, rad, z):
        tgt = mathutils.Vector(pol(b, rad, DECK_Z + z))
        d = tgt - eye
        hit, loc, _n, _i = ob.ray_cast(eye, d.normalized())
        return not (hit and (loc - eye).length < d.length - 0.02)

    for w in LIP_WALLS:
        rm = 0.5 * (w.get("r_in", LIP_R_IN) + w.get("r_out", LIP_R_OUT))
        f0, f1 = w["b0"] + w["taper"], w["b1"] - w["taper"]
        n = max(2, int(math.radians(f1 - f0) * rm / LIP_PROVE_STEP))
        crest = [down(f0 + (f1 - f0) * k / (n - 1), rm) for k in range(n)]
        crest = [c for c in crest if c is not None]
        bodies = hidden = 0
        seen_pts = 0
        nb = max(2, int((f1 - f0) / 0.2))
        for k in range(nb):
            b = f0 + (f1 - f0) * k / (nb - 1)
            for rad in LIP_PROVE_R:
                bodies += 1
                s = sum(1 for z in LIP_BODY_Z if seen(b, rad, z))
                seen_pts += s
                hidden += 0 if s else 1
        open_ok = 0
        for b in (w["b0"] - LIP_PAST, w["b1"] + LIP_PAST):
            for rad in LIP_PROVE_R:
                z = down(b, rad)
                if z is not None and abs(z) < 0.02:
                    open_ok += 1
        past_seen = sum(1 for b in (w["b0"] - LIP_PAST, w["b1"] + LIP_PAST)
                        if seen(b, 52.0, 1.0))
        print("MDL STATS lip_wall %s b=%.1f..%.1f full height %.1f..%.1f: crest %d rays down every %.2f m "
              "%.2f..%.2f m over the deck (spec %.2f); eye (0, %.2f, 0) vs %d standing bodies on the lane "
              "r %.1f..%.1f behind it: %d hidden at every point, %d points seen (must be 0); lane %.1f deg "
              "past each end at deck height %d/6, a body there in the eye's view %d/2"
              % (w["name"], w["b0"], w["b1"], f0, f1, len(crest), LIP_PROVE_STEP, min(crest), max(crest),
                 w["top"] - DECK_Z, LIP_EYE_Z, bodies, LIP_PROVE_R[0], LIP_PROVE_R[-1], hidden, seen_pts,
                 LIP_PAST, open_ok, past_seen))


def _lip_screen(m, w, coll=False):
    """One wall on the pit lip, from its LIP_WALLS row: one closed
    cross-section loop per column, quadded to its neighbour and capped at
    both ends."""
    r = _Rng(w["seed"])
    b0, b1, top_z, taper = w["b0"], w["b1"], w["top"], w["taper"]
    # The collider's columns are coarser, but never coarser than the taper:
    # a column step wider than the taper turns the drawn 1.5 deg end into a
    # ramp the width of the step, and the collider then sits UNDER drawn rock
    # there -- a ray at head height slips over it through rock you can see.
    step = min(LIP_STEP * LIP_COARSE, taper) if coll else LIP_STEP
    n = max(1, int(round((b1 - b0) / step)))

    def held(jag):
        """One recess per column, held for runs: steps, like cleaved rock."""
        if coll:
            return [0.0] * (n + 1)
        out = []
        while len(out) <= n:
            out += [r.f() * jag] * r.i(*LIP_JAG_RUN)
        return out[:n + 1]

    jin, jout, jz = held(LIP_JAG_IN), held(LIP_JAG_OUT), held(w["jag_z"])
    cols, loops = [], []
    for i in range(n + 1):
        b = b0 + (b1 - b0) * i / n
        f = _smooth(min(b - b0, b1 - b) / taper)
        ri, ro = w.get("r_in", LIP_R_IN), w.get("r_out", LIP_R_OUT)
        if not coll:
            ri -= LIP_SKIN_IN - jin[i]
            ro += LIP_SKIN_OUT - jout[i]
        top = LIP_END_Z + (top_z - LIP_END_Z) * f + jz[i] * f
        mid = LIP_BASE_Z + LIP_MID * (top - LIP_BASE_Z)
        crown = 0.0 if coll else LIP_CROWN * (LIP_CROWN_END + (1.0 - LIP_CROWN_END) * f)
        sec = [(ri, LIP_BASE_Z)] + ([] if coll else [(ri, mid)])
        for d in ((-1.0, 1.0) if coll else LIP_HEAD):
            sec.append((ri + 0.5 * (d + 1.0) * (ro - ri), top + crown * (1.0 - d * d)))
        sec += ([] if coll else [(ro, mid)]) + [(ro, LIP_BASE_Z)]
        cols.append({"b": b, "sec": sec, "ri": ri, "ro": ro})
        loops.append([m.v(pol(b, rad, z)) for rad, z in sec])

    before = len(m.faces)
    L = len(loops[0])
    for i in range(n):
        A, B, ca, cb = loops[i], loops[i + 1], cols[i], cols[i + 1]
        er = _radial(0.5 * (ca["b"] + cb["b"]))
        for k in range(L):
            k2 = (k + 1) % L
            dr = 0.5 * (ca["sec"][k2][0] - ca["sec"][k][0] + cb["sec"][k2][0] - cb["sec"][k][0])
            dz = 0.5 * (ca["sec"][k2][1] - ca["sec"][k][1] + cb["sec"][k2][1] - cb["sec"][k][1])
            zone = ZONE_ROCK
            if not coll and abs(ca["sec"][k2][0] - ca["sec"][k][0]) < EPS:
                inner = ca["sec"][k][0] < 0.5 * (ca["ri"] + ca["ro"])
                jg = 0.5 * ((jin[i] + jin[i + 1]) if inner else (jout[i] + jout[i + 1]))
                zone = ZONE_SHADE if jg > SHADE_T * (LIP_JAG_IN if inner else LIP_JAG_OUT) else ZONE_ROCK
            m.quad(A[k], B[k], B[k2], A[k2], (-dz * er[0], -dz * er[1], dr), zone)
    j = 0 if coll else 3                          # anchor the cap on the head: the
    for i, sgn in ((0, 1.0), (n, -1.0)):          # faces are flat, and fan them and
        et = _tangent(cols[i]["b"])               # the cap's own first tri is degenerate
        m.fan(loops[i][j:] + loops[i][:j], (et[0] * sgn, et[1] * sgn, 0.0), ZONE_ROCK)

    tris = len(m.faces) - before
    print("MDL STATS lip_wall %s %s_tris=%d cols=%d b=%.1f..%.1f (taper %.1f deg at each end) "
          "r=%.2f..%.2f z=%.2f..%.2f head %.2f m over the deck, %.2f m under the ceiling"
          % (w["name"], "collision" if coll else "visual", tris, n + 1, b0, b1, taper,
             w.get("r_in", LIP_R_IN), w.get("r_out", LIP_R_OUT), LIP_BASE_Z, top_z, top_z - DECK_Z, CEIL_Z - top_z))
    return tris


def _shelf_box(c):
    """A curved box over the wall's shelf slot: the wall stays solid there."""
    n = 10
    bs = [WALL_A1 + (WALL_A0 - WALL_A1) * k / n for k in range(n + 1)]
    r0, r1 = OUTER_R - 0.05, OUTER_R + SHELF_D + 0.5
    z0, z1 = WALL_LAVA_TOP - 0.3, WALL_LAVA_TOP + SLOT_H + 0.3
    lo = [[c.v(pol(b, rad, z0)) for rad in (r0, r1)] for b in bs]
    hi = [[c.v(pol(b, rad, z1)) for rad in (r0, r1)] for b in bs]
    for k in range(n):
        er = _radial(0.5 * (bs[k] + bs[k + 1]))
        c.quad(lo[k][0], lo[k + 1][0], hi[k + 1][0], hi[k][0], (-er[0], -er[1], 0.0), ZONE_ROCK)
        c.quad(lo[k][1], lo[k + 1][1], hi[k + 1][1], hi[k][1], er, ZONE_ROCK)
        c.quad(lo[k][0], lo[k + 1][0], lo[k + 1][1], lo[k][1], DOWN, ZONE_ROCK)
        c.quad(hi[k][0], hi[k + 1][0], hi[k + 1][1], hi[k][1], UP, ZONE_ROCK)
    for k, sgn in ((0, -1.0), (n, 1.0)):
        et = _tangent(bs[k])
        c.quad(lo[k][0], lo[k][1], hi[k][1], hi[k][0], (et[0] * sgn, et[1] * sgn, 0.0), ZONE_ROCK)


# =============================================================================
# UV -- per-face planar projection into a random window of its zone
# =============================================================================

def _lava_uv(me, uvl, poly):
    """The sea: world x,y straight into the tile, one repeat every LAVA_TILE_M
    metres (the sampler wraps), so every face shares one continuous projection
    and no ring seam carries a jump in the pattern."""
    for li in poly.loop_indices:
        co = me.vertices[me.loops[li].vertex_index].co
        uvl.data[li].uv = (co[0] / LAVA_TILE_M, co[1] / LAVA_TILE_M)


def _flow_uv(me, uvl, poly, vertical):
    """A fall, on the SEA's tile at the SEA's world scale (Ryan: "the pit
    texture is bad because its at a different scale than the lava falls"). A
    wall fall projects (arc, height), the arc at its wall's FALL_REF_R, so a
    metre down or across the wall is a metre in the tile exactly as it is on
    the sea below; a flat one -- the channel floor, the wall shelf, and a fall
    face that has rolled over past FALL_FLAT_NZ -- is the sea's own world x,y.
    The reference is constant over a wall, so both are continuous functions of
    world position: neighbouring faces share their vertex UVs and no seam
    carries a jump. atan2 cuts at game bearing 180, where there is no lava."""
    if not vertical or abs(poly.normal[2]) > FALL_FLAT_NZ:
        _lava_uv(me, uvl, poly)
        return
    cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
    rc = sum(math.hypot(c[0], c[1]) for c in cos) / len(cos)
    ref = FALL_REF_R[1] if rc > FALL_REF_SPLIT else FALL_REF_R[0]
    for li, co in zip(poly.loop_indices, cos):
        uvl.data[li].uv = (-math.atan2(co[1], co[0]) * ref / LAVA_TILE_M,
                           co[2] / LAVA_TILE_M)


def _flow_uv_along(me, uvl, poly):
    """S2's river runs ALONG the deck: it lies flat, so it takes the sea's own
    world x,y projection at the sea's scale, like every other flat lava face."""
    _lava_uv(me, uvl, poly)


def _deck_uv(me, uvl, poly, zone, r):
    """Deck facets project in (radius, arc), not world x-y: a facet's own extent
    sets its texel density, so the ring's grain is even all the way round."""
    u0, v0, u1, v1 = zone
    span_u = (u1 - u0) - 2.0 * UV_PAD
    span_v = (v1 - v0) - 2.0 * UV_PAD
    cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
    ac = math.atan2(sum(c[1] for c in cos), sum(c[0] for c in cos))
    rc = sum(math.hypot(c[0], c[1]) for c in cos) / len(cos)
    pts = []
    for co in cos:
        rad = math.hypot(co[0], co[1])
        th = math.atan2(co[1], co[0])
        th = ac + (th - ac + math.pi) % TWO_PI - math.pi
        pts.append((rad * DECK_UV_SCALE, (th - ac) * rc * DECK_UV_SCALE))
    mi = min(p[0] for p in pts)
    mj = min(p[1] for p in pts)
    w = max(p[0] for p in pts) - mi
    h = max(p[1] for p in pts) - mj
    k = min(1.0, 1.0 / max(w, h, EPS))     # widest deck facets: coarsen, never smear
    pts = [(k * (p[0] - mi), k * (p[1] - mj)) for p in pts]
    mi = mj = 0.0
    w, h = k * w, k * h
    ou, ov = r.f() * (1.0 - w), r.f() * (1.0 - h)
    fu = -1.0 if r.i(0, 1) else 1.0
    fv = -1.0 if r.i(0, 1) else 1.0
    for li, p in zip(poly.loop_indices, pts):
        s = min(ou + p[0] - mi, 1.0)
        t = min(ov + p[1] - mj, 1.0)
        if fu < 0.0:
            s = 1.0 - s
        if fv < 0.0:
            t = 1.0 - t
        uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


def _wallface_uv(me, uvl, poly, zone):
    """A steep S3 wall facet: u along the wall's arc, v up its height, at
    UV_SCALE, the window chosen by where the facet starts along the wall so
    neighbouring facets share it; a seam only where a window runs out."""
    u0, v0, u1, v1 = zone
    span_u = (u1 - u0) - 2.0 * UV_PAD
    span_v = (v1 - v0) - 2.0 * UV_PAD
    cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
    ac = math.atan2(sum(c[1] for c in cos), sum(c[0] for c in cos))
    arcs, zs = [], []
    for co in cos:
        th = math.atan2(co[1], co[0])
        th = ac + (th - ac + math.pi) % TWO_PI - math.pi
        arcs.append(th * WALLFACE_R * UV_SCALE)
        zs.append((co[2] - DECK_Z) * UV_SCALE)
    lo = min(arcs)
    ou = (lo % span_u)
    if ou + (max(arcs) - lo) > span_u:           # the window runs out: start it over
        ou = 0.0
    for li, a, z in zip(poly.loop_indices, arcs, zs):
        s = min(max(ou + (a - lo), 0.0), span_u)
        t = min(max(z, 0.0), span_v)
        uvl.data[li].uv = (u0 + UV_PAD + s, v0 + UV_PAD + t)


def unwrap(ob, zones, seed=0):
    """Identical to tower_build.py's unwrap: fixed UV_SCALE texel density, no
    per-face scale reduction. Every face here is now <=3 m, so nothing needs
    the density dropped to fit -- that drop was the washed-out-grey bug.
    """
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + seed * 7919 + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        zone = zones[pi]
        if zone[0] == "lava":                    # own sheet, tiled in world x,y
            for _draw in range(4):               # the four draws the atlas path spends per
                r.n()                            # face (flip u, flip v, window u, window v):
            _lava_uv(me, uvl, poly)              # burned, so every other face keeps the
            continue                             # window it had before the sea left the atlas
        if zone[0] == "river":                   # the river: streaked along the flow
            _flow_uv(me, uvl, poly, False)
            continue
        if zone[0] == "fall":
            _flow_uv(me, uvl, poly, True)
            continue
        if zone[0] == "river_t":
            _flow_uv_along(me, uvl, poly)
            continue
        if zone[0] == "deck":                    # radial/tangential, finer tiling
            _deck_uv(me, uvl, poly, zone[1:], r)
            continue
        if zone[0] == "wallface":                # along the wall, one window per stretch
            _wallface_uv(me, uvl, poly, zone[1:])
            continue
        u0, v0, u1, v1 = zone
        span_u = (u1 - u0) - 2.0 * UV_PAD
        span_v = (v1 - v0) - 2.0 * UV_PAD
        nrm = poly.normal
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
        fu = -1.0 if r.i(0, 1) else 1.0
        fv = -1.0 if r.i(0, 1) else 1.0
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
            if fu < 0.0:
                s = 1.0 - s
            if fv < 0.0:
                t = 1.0 - t
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


# =============================================================================
# EXTRA RENDERS -- from the deck, which mdl's rig cannot reach
# =============================================================================

def _deck_render(spec, objects):
    """Arena light (bentham_ring's red sun), hand-placed cameras via TRACK_TO."""
    scene = bpy.context.scene
    # EEVEE needs a GPU and a console session; --cpu runs over plain ssh, where
    # it takes the process down mid-render. Follow the spec, as mdl does.
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

    world = bpy.data.worlds.new("Hell")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.30, 0.06, 0.05, 1.0)
    bg.inputs[1].default_value = 0.70
    ld = bpy.data.lights.new("KeyRed", type="SUN")
    ld.energy = 6.5
    ld.color = (1.0, 0.36, 0.28)
    key = mdl._link(bpy.data.objects.new("KeyRed", ld))
    key.rotation_euler = (math.radians(18.0), math.radians(12.0), 0.0)   # 75 deg steep in Blender Z-up

    target = mdl._link(bpy.data.objects.new("DeckTarget", None))
    cam = mdl._link(bpy.data.objects.new("DeckCam", bpy.data.cameras.new("DeckCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    out_dir = spec.get("out_dir", ".")

    def shot(name, loc, tgt, lens, res):
        cam.data.lens = lens
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    lane = 0.5 * (INNER_R + OUTER_R)
    shot("tex_wall_1m", pol(40.0, 56.3, DECK_Z + EYE_H), pol(40.0, 57.4, DECK_Z + EYE_H), 18.0, (1200, 675))
    shot("tex_wall_6m", pol(40.0, 51.3, DECK_Z + EYE_H), pol(40.0, 57.4, DECK_Z + EYE_H), 18.0, (1200, 675))
    shot("tex_s3wall_1m", pol(172.0, 48.6, DECK_Z + EYE_H), pol(172.0, 47.5, DECK_Z + 1.4), 18.0, (1200, 675))
    shot("runner", (lane, 0.0, DECK_Z + EYE_H), (38.0, 46.0, DECK_Z + 3.0),
         24.0, (1200, 750))
    shot("guard", (0.0, 0.0, DECK_Z), (lane, 30.0, DECK_Z - 4.0), 24.0, (1200, 750))
    shot("shaft", (0.0, -10.0, COURTYARD_Z + EYE_H), (0.0, 26.0, 160.0), 16.0, (900, 1200))
    shot("pit", (INNER_R - 0.6, 0.0, DECK_Z + EYE_H), (14.0, 6.0, COURTYARD_Z),
         22.0, (1200, 900))
    shot("floor", (lane, 0.0, DECK_Z + 5.0), (lane - 3.0, 7.0, DECK_Z),
         30.0, (1200, 900))
    shot("run", pol(290.0, 52.5, DECK_Z + EYE_H), pol(312.0, 52.0, 22.7),
         26.0, (1400, 800))
    shot("top", pol(315.0, 10.0, 58.0), pol(315.3, 52.0, 22.4), 32.0, (1200, 1000))
    shot("fall", pol(316.0, 8.0, 9.0), pol(314.0, 44.0, 6.0), 18.0, (1400, 900))
    shot("deck290", pol(290.0, 52.0, DECK_Z + EYE_H), pol(302.0, 52.0, 23.4),
         34.0, (1400, 800))
    shot("wide", pol(315.3, 6.0, 96.0), pol(315.3, 50.0, 18.0), 24.0, (1500, 1000))
    _s4_review(scene, shot, ld, key, bg, objects)
    if CELLS:
        cm, out, w, h = max([c for c in CELLS if c[0][2] < DECK_Z] or CELLS,
                            key=lambda c: c[3])
        eye = _v3(_v3(_v3(cm, out, -2.2 * h), UP, 0.35 * h), (-out[1], out[0], 0.0), 0.6 * h)
        shot("cell", eye, cm, 35.0, (1000, 800))
        shot("mouth", _v3(cm, out, -1.7 * h), cm, 40.0, (1000, 800))
    if S1_REVIEW:
        _s1_review(scene, shot)
    _s3_review(scene, shot)

    # ---- S2 review shots: render-only lighting (white fill, grey world,
    # more exposure) so the rock reads mid-grey and the lava still glows;
    # a 0.6 x 0.6 x 1.8 m proxy body behind one crest, render-only too.
    rl = bpy.data.lights.new("ReviewFill", type="SUN")
    rl.energy = REVIEW_SUN
    rl.color = (1.0, 0.96, 0.92)
    fill = mdl._link(bpy.data.objects.new("ReviewFill", rl))
    fill.rotation_euler = (math.radians(35.0), math.radians(-20.0), math.radians(40.0))
    key.hide_render = True
    bg.inputs[0].default_value = (0.55, 0.50, 0.48, 1.0)
    bg.inputs[1].default_value = REVIEW_WORLD
    mdl._try(scene.view_settings, "exposure", REVIEW_EXPOSURE)
    a0, a1 = S2_INFO["a0"], S2_INFO["a1"]
    ms = S2_INFO["masses"][2]
    P = _s2_frame(ms["b"], ms["rad"])
    verts = [P(u, v, ms["top"] + z) for z in (0.0, 1.8) for (u, v) in
             ((-0.3, -0.3), (0.3, -0.3), (0.3, 0.3), (-0.3, 0.3))]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    proxy = mdl.mesh("ReviewProxy", verts, faces)
    proxy.data.materials.append(mdl.flat_material("ReviewGreen", (0.2, 1.0, 0.3, 1.0)))
    shot("review_s2_chain", pol(a0 - 3.0, S2_PLAT_R, DECK_Z + EYE_H), pol(a0 + 14.0, S2_PLAT_R, DECK_Z),
         28.0, (1400, 800))
    shot("review_s2_lane", pol(a0 + 1.0, 48.3, DECK_Z + EYE_H), pol(a0 + 24.0, 48.8, DECK_Z),
         28.0, (1400, 800))
    shot("review_s2_guard", (0.0, 0.0, 27.0), pol(102.0, 54.0, DECK_Z), 35.0, (1400, 900))
    shot("review_s2_high", pol(a0 - 4.0, 56.3, CEIL_Z - 0.9), pol(a0 + 20.0, 53.5, DECK_Z), 22.0, (1500, 1000))
    shot("review_s2_cover", (0.0, 0.0, 27.0), P(0.0, 0.0, ms["top"] + 0.9), 85.0, (1200, 900))
    shot("review_s2_outer", pol(a0 + 2.0, 56.85, DECK_Z + 1.2), pol(a0 + 20.0, 57.0, DECK_Z - 0.2),
         30.0, (1400, 800))

    for ob in (cam, target, key, fill, proxy):
        bpy.data.objects.remove(ob, do_unlink=True)


def _s3_proxy(name, px, py, pz, h, colour):
    """A render-only body: 0.6 m across the sight line, 0.3 m deep, h tall,
    standing on the rock at (px, py, pz). Never exported."""
    b = _bear_deg(math.atan2(py, px))
    er, et = _radial(b), _tangent(b)
    verts = []
    for dz in (-0.05, h):
        for (dr, dt) in ((-0.15, -0.3), (0.15, -0.3), (0.15, 0.3), (-0.15, 0.3)):
            verts.append((px + er[0] * dr + et[0] * dt, py + er[1] * dr + et[1] * dt, pz + dz))
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    ob = mdl.mesh(name, verts, faces)
    ob.data.materials.append(mdl.flat_material(name + "Mat", colour))
    return ob


def _s3_on_path(i, frac=0.5):
    """A Blender plan point on the path at row i: frac 0 is the wall side of
    the path cell, 1 its far side."""
    lay = S3["lay"]
    rp = S3_COLS[lay["spans"][i][0]]
    x, y = S3["deck_xy"](S3["L"]["T"](lay["rows"][i]), rp - 0.9 + frac * 1.8)
    return x, y


def _s3_review(scene, shot):
    """Review-only: a white fill over the grid, exposure up, the pad plates,
    and two proxy bodies on the path -- one standing, one crouched -- so the
    raycast numbers in the MDL STATS s3 lines can be read off the guard's
    picture. Everything made here is removed after."""
    lay = S3["lay"]
    made = []
    sd = bpy.data.lights.new("ReviewSun", type="SUN")
    sd.energy, sd.color = S3_REVIEW[0], (1.0, 1.0, 1.0)
    # No shadows from the review lights: the arena casts none (bentham_ring
    # has no shadow caster), and the ragged crest's sun shadow lay on the deck
    # at the wall's foot as a row of dark teeth that read as rock spilling
    # onto the floor -- lighting, not geometry, and not the game's.
    mdl._try(sd, "use_shadow", False)
    sun = mdl._link(bpy.data.objects.new("ReviewSun", sd))
    aim = mdl._link(bpy.data.objects.new("ReviewAim", None))
    sun.location, aim.location = (0.0, 0.0, 110.0), pol(172.0, 52.0, DECK_Z)
    con = sun.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"
    made += [sun, aim]
    for b in (150.0, 162.0, 174.0, 186.0, 197.0):
        ld = bpy.data.lights.new("ReviewFill", type="POINT")
        ld.energy, ld.color, ld.shadow_soft_size = 5200.0, (1.0, 1.0, 1.0), 3.0
        mdl._try(ld, "use_shadow", False)
        f = mdl._link(bpy.data.objects.new("ReviewFill", ld))
        f.location = pol(b, 52.0, DECK_Z + 4.5)
        made.append(f)
    mdl._try(scene.view_settings, "exposure", S3_REVIEW[2])

    sx, sy = _s3_on_path(6, 0.5)
    cx, cy = _s3_on_path(8, 0.5)
    made.append(_s3_proxy("StandProxy", sx, sy, DECK_Z, S3_STAND, (0.1, 0.9, 0.2, 1.0)))
    made.append(_s3_proxy("CrouchProxy", cx, cy, DECK_Z, S3_CROUCH, (0.2, 0.5, 1.0, 1.0)))

    rows = lay["rows"]
    ex, ey = S3["deck_xy"](S3["L"]["T"](S3_EXT[0] + 0.5), S3_COLS[lay["path"][0]] + 0.3)
    tx, ty = _s3_on_path(5, 0.5)
    shot("s3f_entry", (ex, ey, DECK_Z + EYE_H), (tx, ty, DECK_Z + 0.8), 24.0, (1500, 850))
    px, py = _s3_on_path(2, 0.6)
    qx, qy = _s3_on_path(9, 0.5)
    shot("s3f_path", (px, py, DECK_Z + EYE_H), (qx, qy, DECK_Z + 0.9), 28.0, (1500, 850))
    wx, wy = S3["deck_xy"](S3["L"]["T"](rows[3]), 54.0)
    ww, wv = S3["deck_xy"](S3["L"]["T"](rows[8]), lay["rho_w"][8])
    shot("s3f_wall", (wx, wy, DECK_Z + EYE_H), (ww, wv, DECK_Z + 1.2), 30.0, (1500, 850))
    jrow = S3_JUMP_ROWS[len(S3_JUMP_ROWS) // 2]
    jx, jy = _s3_on_path(jrow - 1, 0.5)
    jump = [p for p in _s3_pads() if p["jump"] and p["row"] == jrow][0]
    shot("s3f_jump", (jx, jy, DECK_Z + EYE_H), (jump["o"][0], -jump["o"][1], DECK_Z + 0.2),
         30.0, (1500, 850))
    cx2, cy2 = S3["deck_xy"](S3["L"]["T"](rows[3]), 54.5)
    tx2, ty2 = S3["deck_xy"](S3["L"]["T"](rows[8]), 54.0)
    shot("s3f_crack", (cx2, cy2, DECK_Z + 3.2), (tx2, ty2, DECK_Z), 28.0, (1500, 850))
    shot("s3f_guard", (0.0, 0.0, S3_EYE_Z), pol(172.0, 52.0, DECK_Z), 35.0, (1600, 900))
    shot("s3f_pit", pol(158.0, 51.0, DECK_Z + 7.0), pol(176.0, 28.0, DECK_Z - 22.0), 22.0, (1500, 850))
    shot("s3f_aerial", pol(172.0, 14.0, 62.0), pol(172.0, 52.0, DECK_Z), 26.0, (1600, 1000))
    mdl._try(scene.view_settings, "exposure", 0.0)
    for ob in made:
        bpy.data.objects.remove(ob, do_unlink=True)

def _s1_review(scene, shot):
    """Review-only: white light into the cave, exposure up, a 0.6 x 1.8 m player
    proxy behind one cluster. Everything made here is removed after."""
    made = []
    sd = bpy.data.lights.new("ReviewSun", type="SUN")
    sd.energy, sd.color = 2.0, (1.0, 1.0, 1.0)
    sun = mdl._link(bpy.data.objects.new("ReviewSun", sd))
    aim = mdl._link(bpy.data.objects.new("ReviewAim", None))
    sun.location, aim.location = (0.0, 0.0, 35.0), pol(37.0, 52.0, DECK_Z)
    con = sun.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"
    made += [sun, aim]
    for b in (20.0, 31.0, 42.0, 53.0):
        ld = bpy.data.lights.new("ReviewFill", type="POINT")
        ld.energy, ld.color, ld.shadow_soft_size = 4500.0, (1.0, 1.0, 1.0), 2.5
        f = mdl._link(bpy.data.objects.new("ReviewFill", ld))
        f.location = pol(b, 51.5, DECK_Z + 4.0)
        made.append(f)
    cands = [f for f in S1["fixtures"] if f.kind == "mite" and f.H >= 3.5]
    spire = min(cands, key=lambda f: abs(_bear_deg(math.atan2(f.cxy[1], f.cxy[0])) - 37.0)
                + 0.3 * abs(math.hypot(*f.cxy) - 52.0) - 8.0 * f.R)      # near 37 deg, mid deck, wide
    x, y = spire.cxy
    rad = math.hypot(x, y)
    er, et = (x / rad, y / rad), (-y / rad, x / rad)
    px, py = x + er[0] * 0.9, y + er[1] * 0.9                     # 0.9 m behind it from the centre eye
    pz = DECK_Z + S1["H"](px, py)
    verts, faces = [], []
    for dz in (-0.05, 1.8):
        for (dr, dt) in ((-0.15, -0.3), (0.15, -0.3), (0.15, 0.3), (-0.15, 0.3)):
            verts.append((px + er[0] * dr + et[0] * dt, py + er[1] * dr + et[1] * dt, pz + dz))
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    proxy = mdl.mesh("PlayerProxy", verts, faces)          # 0.6 m across the sightline, 0.3 m deep
    proxy.data.materials.append(mdl.flat_material("ProxyGreen", (0.1, 0.9, 0.2, 1.0)))
    made.append(proxy)
    for (loc, en) in ((pol(37.0, 38.0, 25.0), 9000.0), (pol(37.0, 26.0, 6.0), 30000.0)):   # the pit wall
        pf = bpy.data.lights.new("ReviewPitFill", type="POINT")
        pf.energy, pf.color, pf.shadow_soft_size = en, (1.0, 1.0, 1.0), 3.0
        f = mdl._link(bpy.data.objects.new("ReviewPitFill", pf))
        f.location = loc
        made.append(f)
    mdl._try(scene.view_settings, "exposure", 0.7)
    mid = (px, py, pz + 1.0)
    shot("review_s1_run", pol(13.0, 52.0, DECK_Z + EYE_H), pol(36.0, 52.0, 24.0), 24.0, (1400, 800))
    shot("review_s1_run2", pol(41.5, 54.6, DECK_Z + EYE_H), pol(18.0, 51.5, 24.0), 24.0, (1400, 800))
    shot("review_s1_guard", (0.0, 0.0, S1_EYE_Z), pol(37.0, 52.0, 24.0), 35.0, (1600, 900))
    st = _tangent(37.5)
    shifted = (S1_SHIFT * st[0], S1_SHIFT * st[1], S1_EYE_Z)
    shot("review_s1_guard_shift", shifted, pol(37.0, 52.0, 24.0), 35.0, (1600, 900))
    shot("review_s1_high", pol(20.0, 34.0, 30.8), pol(42.0, 52.0, 23.5), 22.0, (1500, 900))
    shot("review_s1_cover", (0.0, 0.0, S1_EYE_Z), mid, 80.0, (1200, 900))
    shot("review_s1_cover_shift", shifted, mid, 80.0, (1200, 900))
    fx = S1["fixtures"]
    tall = min([f for f in fx if f.kind == "mite" and f.H >= 3.8], key=lambda f: abs(_bear_deg(math.atan2(f.cxy[1], f.cxy[0])) - 30.0))
    near = sorted([f for f in fx if f is not tall], key=lambda f: math.hypot(f.cxy[0] - tall.cxy[0], f.cxy[1] - tall.cxy[1]))
    med = next(f for f in near if f.kind == "mite" and 2.4 <= f.H < 3.8)
    sht = next(f for f in near if f.kind == "mite" and f.H < 2.4)
    cx = (tall.cxy[0] + med.cxy[0] + sht.cxy[0]) / 3.0
    cy = (tall.cxy[1] + med.cxy[1] + sht.cxy[1]) / 3.0
    ax, ay = sht.cxy[0] - tall.cxy[0], sht.cxy[1] - tall.cxy[1]
    an = math.hypot(ax, ay) or 1.0
    nx, ny = -ay / an, ax / an
    if nx * cx + ny * cy < 0:                                   # from the tower side, looking outward
        nx, ny = -nx, -ny
    dist = 2.0 + 0.6 * an
    shot("review_s1_feet", (cx - nx * dist, cy - ny * dist, DECK_Z + 0.6), (cx, cy, DECK_Z + 0.45), 28.0, (1400, 900))
    shot("review_s1_pitwall", pol(37.0, 22.0, COURTYARD_Z + 3.0), pol(37.0, 46.7, 10.0), 20.0, (1400, 900))
    shot("review_s1_ceiling", pol(16.0, 52.5, DECK_Z + EYE_H), pol(34.0, 52.0, 29.5), 18.0, (1400, 900))
    mdl._try(scene.view_settings, "exposure", 0.0)
    for ob in made:
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

# =============================================================================
# CHUNKS -- one sculpt, exported per section and per element (decision 84)
# =============================================================================
# The whole map is built as one mesh, as before; export cuts it into one .glb
# per chunk. A section takes every face whose centre lies in its bearings; an
# element takes the faces its own builder appended (Mesh.span). Chunks share
# the boundary vertices of the one mesh, so the seams are exact.
#   tools/modelling/model build map_base --chunk s3     # rebuilds map_base_s3.glb only
SECTIONS = [                  # chunk, first bearing (the next one's is its last)
    ("s1", 342.0), ("s2", 66.5), ("s3", 139.0), ("s4", 204.0), ("s5", 286.0),
]
ELEMENTS = ["lip" + w["name"] for w in LIP_WALLS] + ["cover_s2", "cover_s4", "gate"]
CHUNKS = [c for c, _b in SECTIONS] + ELEMENTS
# The gate (rock_bars_build's cave wall with slots) where Ryan placed RockBars
# in bentham_ring.tscn: its Transform3D as written (basis rows, then origin).
GATE_NODE = (0.984808, 0, 0.173648, 0, 1, 0, -0.173648, 0, 0.984808, 51.7418, 23, -9.1235)
MAPBASE_NODE_ORIGIN = (0.014858246, 0.0, -0.01688385)
CHUNK_OF = {}                 # "vis"/"col" -> chunk name per face, set by build()


def _chunk_label(chunk):
    return "MapBase" + "".join(p[:1].upper() + p[1:] for p in chunk.split("_"))


def _section_of(bearing):
    best = SECTIONS[-1][0]
    for chunk, b0 in SECTIONS:                      # the last one whose start is passed
        if (bearing - SECTIONS[0][1]) % 360.0 >= (b0 - SECTIONS[0][1]) % 360.0:
            best = chunk
    return best


def _assign(m):
    """Chunk name per face of a _Mesh: its element span, else its section."""
    out = [None] * len(m.faces)
    for name, (f0, f1) in m.spans.items():
        for fi in range(f0, f1):
            out[fi] = name
    for fi, f in enumerate(m.faces):
        if out[fi] is None:
            x = sum(m.verts[j][0] for j in f) / len(f)
            y = sum(m.verts[j][1] for j in f) / len(f)
            out[fi] = _section_of(_bear_deg(math.atan2(y, x)))
    return out


def _gate():
    """rock_bars' gate, built into this scene at its placed transform."""
    ob, coll_ob = rb.build()
    g = GATE_NODE
    o = MAPBASE_NODE_ORIGIN
    # Godot node transform (x right, y up, z back) -> Blender (x, -z, y).
    mg = Matrix(((g[0], g[1], g[2], g[9] - o[0]),       # into MapBase's frame
                 (g[3], g[4], g[5], g[10] - o[1]),
                 (g[6], g[7], g[8], g[11] - o[2]),
                 (0.0, 0.0, 0.0, 1.0)))
    cv = Matrix(((1.0, 0.0, 0.0, 0.0), (0.0, 0.0, -1.0, 0.0), (0.0, 1.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0)))
    mb_ = cv @ mg @ cv.inverted()
    label = _chunk_label("gate")
    ob.name, coll_ob.name = label + "Rock", label + "Collision-colonly"
    for o_ in (ob, coll_ob):
        o_.data.transform(mb_)
        o_.data.update()
    return ob, coll_ob


def _split(src, keep, name):
    """A new object holding only the faces keep[] marks: the same vertex
    positions, loop UVs, material slots and indices, flat shaded."""
    sm = src.data
    remap, verts, faces, mids = {}, [], [], []
    uvls = [(l.name, l.data) for l in sm.uv_layers]
    uvs = [[] for _ in uvls]
    for poly in sm.polygons:
        if not keep[poly.index]:
            continue
        f = []
        for li in poly.loop_indices:
            vi = sm.loops[li].vertex_index
            if vi not in remap:
                remap[vi] = len(verts)
                verts.append(tuple(sm.vertices[vi].co))
            f.append(remap[vi])
            for k, (_n, d) in enumerate(uvls):
                uvs[k].append(tuple(d[li].uv))
        faces.append(f)
        mids.append(poly.material_index)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    for mat in sm.materials:
        me.materials.append(mat)
    me.polygons.foreach_set("material_index", mids)
    for (lname, _d), luv in zip(uvls, uvs):
        layer = me.uv_layers.new(name=lname)
        layer.data.foreach_set("uv", [c for uv in luv for c in uv])
    if uvls:
        me.uv_layers[0].active = True
        me.uv_layers[0].active_render = True
    for p_ in me.polygons:
        p_.use_smooth = False
    me.update()
    return mdl._link(bpy.data.objects.new(name, me))


def _footprint_box_dist(p, b, rad, sect):
    """Signed planar distance (m) from p to a footprint box in the (radial,
    tangential) frame `_in_platform` tests against: <=0 inside."""
    er, et = _radial(b), _tangent(b)
    base = pol(b, rad, 0.0)
    dx, dy = p[0] - base[0], p[1] - base[1]
    u, v = dx * er[0] + dy * er[1], dx * et[0] + dy * et[1]
    hu, hv = max(abs(s[0]) for s in sect), max(abs(s[1]) for s in sect)
    qx, qy = abs(u) - hu, abs(v) - hv
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0)


def _footprint_radial_dist(u, v, R):
    """Signed planar distance (m) from local (u, v) to a radial footprint's
    own boundary R(theta), as `_s2_local`/`_s4_local` give it: <=0 inside."""
    r = math.hypot(u, v)
    return (r - R(0.0)) if r < EPS else (r - R(math.atan2(v, u)))


def _wave_uv(me):
    """UV2.x: the share of the lava wave a vertex takes, 0 on every lava edge, under the
    tower's foot and under every lake platform, fin and S2/S4 boulder standing in the
    lava, 1 at WAVE_RAMP in. A function of position only, so split vertices agree."""
    slots = {i for i, mt in enumerate(me.materials) if mt.name in WAVE_MATS}
    uses, lava_v = {}, set()
    for p in me.polygons:
        if p.material_index in slots:
            for ek in p.edge_keys:
                uses[ek] = uses.get(ek, 0) + 1
            lava_v.update(p.vertices)
    pts = []
    for (a, b), n in uses.items():
        if n == 1:                                     # a lava face's edge no other lava face shares
            A, B = me.vertices[a].co, me.vertices[b].co
            k = max(1, int(math.ceil((B - A).length / 0.05)))
            pts += [A.lerp(B, s / float(k)) for s in range(k + 1)]
    tree = kdtree.KDTree(max(1, len(pts)))
    for i, co in enumerate(pts):
        tree.insert(co, i)
    tree.balance()
    boxes = []                                          # every lake platform and its fin
    for k, (b, rad, inner) in enumerate(_platforms()):
        sect, fs = LAKE_SECTS[k]
        boxes.append((b, rad, sect))
        if inner:
            boxes.append((b, FIN_R, fs))
    s2_rocks, s4_rocks = S2_MASSES, _s4_layout()["rocks"]
    w = {}
    for vi in lava_v:
        co = me.vertices[vi].co
        p = (co.x, co.y)
        d = tree.find(co)[2] if pts else WAVE_RAMP
        cap = min([math.hypot(co.x, co.y) - LAVA_FLAT_R]
                  + [_footprint_box_dist(p, *bx) for bx in boxes]
                  + [_footprint_radial_dist(*_s2_local(sp, p)[:2], sp["R"]) for sp in s2_rocks]
                  + [_footprint_radial_dist(*_s4_local(rk, p), rk["R"]) for rk in s4_rocks])
        w[vi] = max(0.0, min(1.0, d / WAVE_RAMP, cap / WAVE_RAMP))
    layer = me.uv_layers.new(name="Wave")
    layer.data.foreach_set("uv", [c for lp in me.loops for c in (w.get(lp.vertex_index, 0.0), 0.0)])
    me.uv_layers[0].active = True
    me.uv_layers[0].active_render = True
    print("MDL STATS wave lava_verts=%d edge_samples=%d full=%d"
          % (len(lava_v), len(pts), sum(1 for x in w.values() if x >= 1.0)))


def _export_chunks(out_dir, objects, spec):
    """One .glb per chunk (only spec["chunk"] when it names one), and a
    manifest the model tool verifies and installs from."""
    want = spec.get("chunk") or ""
    if want and want not in CHUNKS:
        raise SystemExit("MDL ERROR no chunk %r; chunks are %s" % (want, ", ".join(CHUNKS)))
    ob, coll_ob, gate_ob, gate_coll = objects
    if (len(CHUNK_OF["vis"]) != len(ob.data.polygons)
            or len(CHUNK_OF["col"]) != len(coll_ob.data.polygons)):
        raise SystemExit("MDL ERROR chunk labels no longer match the mesh's faces")
    made = []
    for chunk in ([want] if want else CHUNKS):
        label = _chunk_label(chunk)
        if chunk == "gate":
            vis, col = gate_ob, gate_coll
        else:
            vis = _split(ob, [c == chunk for c in CHUNK_OF["vis"]], label + "Rock")
            col = _split(coll_ob, [c == chunk for c in CHUNK_OF["col"]], label + "Collision-colonly")
        col.hide_render = True
        path = os.path.join(out_dir, "%s_%s.glb" % (NAME, chunk))
        mdl.export_glb(path, [vis, col])
        print("MDL EXPORT %s (%d bytes) visual_tris=%d collision_tris=%d"
              % (path, os.path.getsize(path), len(vis.data.polygons), len(col.data.polygons)))
        made.append({"chunk": chunk, "glb": os.path.basename(path),
                     "contract": {"node_paths": [label + "Rock", label + "Collision",
                                                 label + "Collision/CollisionShape3D"],
                                  "max_tris": 110000}})
        for o_ in ((vis, col) if chunk != "gate" else ()):
            me = o_.data
            bpy.data.objects.remove(o_, do_unlink=True)
            bpy.data.meshes.remove(me)
    with open(os.path.join(out_dir, NAME + ".chunks.json"), "w") as fh:
        json.dump({"chunks": made}, fh, indent=1)
    return [os.path.join(out_dir, c["glb"]) for c in made]


def _post(spec, objects):
    """Review renders, skipped when no views are asked for (--chunk, --views none)."""
    if "views" in spec and not spec["views"] and not spec.get("cams"):
        return
    _deck_render(spec, objects)


def build():
    rock, ang, river, cut, s2, s4 = _rock(_Rng(SEED))
    coll = _collider(ang, cut[0], cut[1], s2, s4)

    lava_albedo, lava_emissive = _lava_sheet()
    mdl.save_texture(lava_albedo)
    mdl.save_texture(lava_emissive)
    albedo, emissive = build_texture()             # the atlas: the S3 cracks' cell
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)

    ob = rock.object(OBJECT_NAME)
    # The atlas is painted for the S3 cracks alone: main's unwrap runs into a
    # scratch layer and the crack faces copy their windows from it, so their
    # UVs and texels are exactly what they were. Every other rock face is a
    # texel sheet; the sea and the falls are both Ryan's tile, at one scale.
    me = ob.data
    unwrap(ob, rock.zones)
    scratch = me.uv_layers[-1]
    scratch.name = "Scratch"
    classes = ["crack" if fi in rock.crack else _class_of(z) for fi, z in enumerate(rock.zones)]

    def _from_scratch(me_, uvl, poly):
        for li in poly.loop_indices:
            uvl.data[li].uv = scratch.data[li].uv

    custom = {"river": lambda me_, uvl, poly: _flow_uv(me_, uvl, poly, False),
              "fall": lambda me_, uvl, poly: _flow_uv(me_, uvl, poly, True),
              "river_t": _flow_uv_along, "lava": _lava_uv, "glow": _from_scratch,
              "crack": _from_scratch}
    tx.unwrap(ob, classes, SHEETS, seed=1, custom=custom)
    me.uv_layers.remove(me.uv_layers["Scratch"])
    me.uv_layers[0].name = "UVMap"
    me.uv_layers[0].active = True
    me.uv_layers[0].active_render = True
    mats = tx.materials(NAME, SHEETS, use_files=USE_TEXTURE_FILES,
                        tex_dir=os.path.join(os.path.dirname(os.path.abspath(__file__)), TEX_DIR),
                        names={"rock": "HellRock", "shade": "HellShade", "carve": "HellCarve",
                               "ember": "HellEmber"})
    for m in mats.values():
        m.diffuse_color = (0.13, 0.04, 0.04, 1.0)
    mats["glow"] = rock_material("HellGlow", albedo, emissive)
    mats["river"] = river_material("LavaRiver", lava_albedo, lava_emissive)
    mats["lava"] = rock_material("LavaSea", lava_albedo, lava_emissive)
    mats["crack"] = rock_material("LavaCrack", albedo, emissive)   # the atlas's glow cell, as before
    slots = ["river" if c in ("river", "fall", "river_t") else c for c in classes]   # one LavaRiver slot
    order = tx.finish(ob, slots, mats)
    _wave_uv(me)
    tx.report(SHEETS)
    lava_tris = sum(1 for c in classes if c == "lava")
    river_tris = sum(1 for c in classes if c in ("river", "fall", "river_t"))
    print("MDL STATS surfaces=%d order=%s" % (len(me.materials), ",".join(order)))

    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d lava_tris=%d river_tris=%d deck_uv=%.2f "
          "lava_tile_m=%.1f lava_sheet=%dx%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), lava_tris, river_tris,
             DECK_UV_SCALE, LAVA_TILE_M, lava_albedo.size[0], lava_albedo.size[1]))
    print("MDL STATS river=%.1f..%.1f deg lava_y=%.2f cols=%d bank=%.1f deg recess=%.2f "
          "wall_lava=%.1f..%.1f deg to y=%.2f pit_run_tris=%d"
          % (LAKE_A0, LAKE_A1, LAVA_Z, river[0], LAKE_BANK, RECESS_R,
             WALL_A0, WALL_A1, WALL_LAVA_TOP, river[1]))
    for k, (b, rad, inner) in enumerate(_platforms()):
        print("MDL STATS platform%d bearing=%.3f r=%.1f top=%.2f square=%.1f %s"
              % (k + 1, b, rad, PLAT_TOP_Z, 2.0 * PLAT_HALF, "inner+fin" if inner else "outer"))
    _s2_stats(s2)
    _s3_stats()
    _s4_stats()
    _lip_prove(ob)
    print("MDL STATS cells=%d pit=%d pit_top=%.1f uniform_to=%.0f above200=%d top=%.0f"
          % (len(CELLS), sum(1 for c in CELLS if c[0][2] < DECK_Z),
             max(c[0][2] + 0.5 * c[3] for c in CELLS if c[0][2] < DECK_Z), UNIFORM_TOP,
             sum(1 for c in CELLS if c[0][2] > 200.0), max(c[0][2] for c in CELLS)))
    fo = S1["forest"]
    print("MDL STATS s1 forest samples=%d hidden_centre=%.1f%% seen_from_shifted=%.1f%% largest_blob=%.1fx%.1f m "
          "(across x along) routes(inner,middle,outer)=%s chest_widths=%.2f..%.2f m"
          % (fo["samples"], 100.0 * fo["hidden"], 100.0 * fo["shift_seen"], fo["blob"][0], fo["blob"][1],
             " ".join("%s/%.1f" % ("ok" if ok else "BLOCKED", g) for ok, g in fo["routes"]),
             S1["widths"][0], S1["widths"][-1]))
    sp = S1["spikes"]
    print("MDL STATS s1 %s prisms=%d coll_tris=%d mites=%s tites=%s"
          % (" ".join("%s=%s" % kv for kv in sorted(S1["counts"].items())), len(S1["prisms"]), S1["coll_tris"],
             " ".join("%.1f" % s.H for s in sp if s.kind == "mite"),
             " ".join("%.1f" % s.H for s in sp if s.kind == "tite")))
    print("MDL STATS deck r=%.1f..%.1f y=%.2f courtyard_y=%.2f ceiling_y=%.2f rim_y=%.1f ground_r=%.0f"
          % (INNER_R, OUTER_R, DECK_Z, COURTYARD_Z, CEIL_Z, RIM_Z, GROUND_RINGS[-1][0]))
    CHUNK_OF["vis"] = _assign(rock)
    CHUNK_OF["col"] = _assign(coll)
    gate_ob, gate_coll = _gate()
    return [ob, coll_ob, gate_ob, gate_coll]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_post, export=_export_chunks)
