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
this reads as the rock the tower was cut from. Two surfaces: the rock, and
the lava sea on the pit floor, which has its own tiling sheet.

    tools/modelling/model look  map_base --cam 35,30,40
    tools/modelling/model build map_base --cam 35,30,40

Hand-placed shots come back with every run: runner (eye on the deck), guard
(void centre at deck height), shaft (courtyard looking up), cell and mouth
(one cell, angled and straight on).
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

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
# else the albedo glows); the same for lava_albedo.png / lava_emissive.png on
# the pit sea. Otherwise, and by default, the painted sheets below are used.

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
USE_TEXTURE_FILES = False             # True: texture files in TEX_DIR replace the painted sheets
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

# ---- the lava sea on the floor of the shaft --------------------------------
# Its own material and its own tiling sheet (not an atlas cell), so it repeats
# instead of stretching one window over 90 m of floor.
ZONE_LAVA      = ("lava",)
LAVA_TEX       = 512
LAVA_ALBEDO    = "map_base_lava_albedo"
LAVA_EMISSIVE  = "map_base_lava_emissive"
LAVA_SEED      = 7720133
LAVA_SPAN      = 104.0                # metres across the sheet: ONE window over the
                                      # whole sea, no tiling, so there is no repeat
                                      # and no seam anywhere to hide
LAVA_RINGS     = (1.0, 0.70, 0.42, 0.14)   # radius fractions of the pit foot
LAVA_SWELL     = 0.6                  # +- metres of slow molten swell
LAVA_STEP      = 0.3                  # swell snaps to this: flat crust plates
LAVA_FLAT_R    = 18.0                 # level under the tower's foot

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
S2_PLAT_R = 54.2                      # the chain's centre line
# The chain: boulders. Each is one heightfield on a polar grid: a flat
# landing, rounded shoulders down into the lava, and (hump) the tower-facing
# side rising in a rounded hump. (along, across: semi-axes at the waterline;
# top y; hump; off the centre line)
S2_PLATS = ((1.65, 1.85, 23.05, True, 0.10), (1.45, 1.55, 23.35, False, -0.20),
            (1.65, 1.85, 22.95, True, 0.20), (1.65, 1.85, 23.30, True, -0.10),
            (1.45, 1.55, 23.15, False, 0.15), (1.65, 1.85, 22.90, True, 0.0))
S2_GAPS = (4.6, 5.2, 4.7, 5.0, 5.9, 4.6)      # lava between standing edges: end bank first
S2_MASS_N, S2_MASS_P = 20, 2.3        # points round a boulder, its outline's exponent
S2_MASS_Q = (0.12, 0.3, 0.45, 0.58, 0.68, 0.76, 0.83, 0.89, 0.95, 1.0, 1.08, 1.2)   # rings, of the waterline
S2_FLAT_Q = 0.75                      # the landing: flat out to here
S2_WATER_D = 0.15                     # the shoulder reaches this far under the lava at the waterline ...
S2_BOTTOM_D = 0.8                     # ... and the bottom ring this far, at the last ring
S2_WOB = 0.07                         # the waterline wanders this much of its radius
S2_HUMP_H = (2.2, 2.4)                # hump height over the landing
S2_HUMP_V = 0.55                      # hump peak this far in, of the across semi-axis
S2_HUMP_U = 0.88                      # hump half length, of the along semi-axis
S2_HUMP_B = (1.0, 0.8)                # hump half depth, inner and outer face: it leans over the landing
S2_HUMP_P = (2.6, 1.4)                # hump section exponent along, and its profile's
S2_NOISE = 0.10                       # rock noise on everything but the landing, metres, peak
S2_NOISE_L = (0.7, 1.8)               # ... wavelengths
S2_SEED = 6180339
S2_TRAP_N = 7                         # TrapVolumes over the river, for the scene
S2_TRAP_R = (50.3, 57.5)              # ... their radial span
S2_INFO = {}                          # what the renders need: lip bearings, the masses
REVIEW_SUN = 5.0                      # review renders only: white fill sun, watts
REVIEW_WORLD = 1.6                    # ... world light strength
REVIEW_EXPOSURE = 1.5                 # ... stops over the arena look

ZONE_RIVER = ("river",)               # flow runs radially, wall -> lip
ZONE_RIVER_T = ("river_t",)           # ... and along the deck in S2
ZONE_FALL = ("fall",)                 # ... and straight down a wall
RIVER_TEX = 256
RIVER_ALBEDO = "map_base_river_albedo"
RIVER_EMISSIVE = "map_base_river_emissive"
RIVER_SEED = 7720133
FLOW_SPAN = 10.0
CROSS_SPAN = 10.0
CROSS_R = 52.0

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
S4_ROCKS = [(54.4, 0.2, 2.4), (53.8, 0.4, 2.3), (54.4, 0.1, 2.5)]   # radius, top over the deck, hump height
S4_REAR, S4_FRONT = 2.5, 2.0          # the standing top: 4.5 m along the flight, the centre 0.5 m forward
S4_HALF_ACROSS = 1.6                  # ... 3.2 m across to the standing edge on the wall side
S4_EDGE_Q = 0.87                      # the standing edge (shoulder at 45 deg) sits here, of the waterline
S4_FLAT_Q = 0.8                       # dead level out to here, of the waterline
S4_REAR_IN = 1.6                      # the rear-inner quadrant of the waterline is this much longer: the hump's tail
S4_HUMP_SIDE = 3.8                    # the waterline's across semi-axis on the tower side
S4_MASS_N, S4_MASS_P = 24, 2.3        # points round a boulder, its outline's exponent
S4_MASS_Q = (0.12, 0.3, 0.45, 0.58, 0.68, 0.76, 0.83, 0.89, 0.95, 1.0, 1.08, 1.2)   # rings, of the waterline
S4_WATER_D = 0.15                     # the shoulder reaches this far under the lava at the waterline ...
S4_BOTTOM_D = 0.8                     # ... and the bottom ring this far, at the last ring
S4_WOB = 0.04                         # the waterline wanders this much of its radius
S4_HUMP_V = 2.5                       # the hump's peak this far across (the landing flat ends at 1.6)
S4_HUMP_B = (1.2, 0.95)               # its half depth, inner and outer face: it leans over the landing
S4_HUMP_U = (-1.2, 3.6)               # its centre along, and half length
S4_HUMP_P = (4.0, 1.2)                # its section exponent along, and its profile's
S4_NOISE = 0.10                       # rock noise on everything but the landing, metres, peak
S4_NOISE_L = (0.7, 1.8)               # ... wavelengths
S4_LAND = 1.5                         # nominal landing this far past the next top's near edge
S4_EXIT_LAND = 1.5                    # ... and onto the exit deck, past the lava's edge
S4_PAD_BACK = 1.6                     # a rock's pad centre this far behind its front edge
S4_WALK_ON = 1.75                     # launch origin behind the pad centre: trigger face 1.5 + capsule 0.4 - one tick
S4_LAUNCH, S4_ANGLE, S4_G = 18.0, 45.0, 22.0
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


def _river_texture():
    """The river: molten, STREAKED along +U, which every river face maps to its
    own flow direction. Wraps on both axes so it tiles."""
    c = _Canvas(RIVER_TEX)
    r = _Rng(RIVER_SEED)
    n = RIVER_TEX
    hot = [(232, 74, 10), (255, 110, 22), (212, 56, 6), (255, 140, 34)]
    warm = [(178, 46, 6), (150, 34, 4), (200, 58, 10)]
    crust = [(34, 12, 10), (24, 8, 8), (46, 18, 14)]

    for y in range(n):
        for x in range(n):
            s = r.pick(hot)
            c.put(x, y, s, s)
    for _ in range(90):                       # crust rafts, drawn out by the flow
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        w, h = r.i(18, 70), r.i(2, 7)
        sh = r.pick(crust)
        for dy in range(h):
            for dx in range(w):
                c.wrap(x + dx, y + dy + (dx // 26), sh, (0, 0, 0))
    for _ in range(150):                      # dark filaments: the shear lines
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        sh = r.pick(crust)
        for dx in range(r.i(30, 110)):
            c.wrap(x + dx, y, sh, (6, 2, 2))
            if r.i(0, 6) == 0:
                y += r.i(-1, 1)
    for _ in range(200):                      # warm streaks either side of them
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        sh = r.pick(warm)
        for dx in range(r.i(20, 90)):
            c.wrap(x + dx, y, sh, sh)
            if r.i(0, 8) == 0:
                y += r.i(-1, 1)
    for _ in range(120):                      # white-hot cores, long and thin
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        core = r.pick([(255, 216, 104), (255, 184, 64), (255, 232, 150)])
        for dx in range(r.i(8, 46)):
            c.wrap(x + dx, y, core, core)
            if r.i(0, 10) == 0:
                y += r.i(-1, 1)
    images = []
    for name, buf in ((RIVER_ALBEDO, c.alb), (RIVER_EMISSIVE, c.emi)):
        img = bpy.data.images.new(name, RIVER_TEX, RIVER_TEX, alpha=False)
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


def _sheet(stem, painted):
    """(albedo, emissive): the files when opted in and present, else painted."""
    alb = _image_file(stem + "_albedo.png") if USE_TEXTURE_FILES else None
    if alb is None:
        return painted()
    return alb, (_image_file(stem + "_emissive.png") or alb)


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


def _strip(m, A, B, want, zone):
    """Triangles between two chains of (param, id), each ascending, that do
    not share vertices: every vertex of both is used, no T-junctions.
    want/zone may be callables of the triangle's centroid."""
    i = j = 0

    def dist(a, b):
        return math.dist(m.verts[a], m.verts[b])

    while i < len(A) - 1 or j < len(B) - 1:
        if j == len(B) - 1 or (i < len(A) - 1 and
                               dist(A[i + 1][1], B[j][1]) <= dist(A[i][1], B[j + 1][1])):
            tri = (A[i][1], A[i + 1][1], B[j][1])       # the shorter diagonal
            i += 1
        else:
            tri = (A[i][1], B[j][1], B[j + 1][1])
            j += 1
        if len(set(tri)) == 3:
            c = tuple(sum(m.verts[v][k] for v in tri) / 3.0 for k in range(3))
            m.tri(tri[0], tri[1], tri[2], want(c) if callable(want) else want,
                  zone(c) if callable(zone) else zone)


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
    rad0 = [math.hypot(m.verts[v][0], m.verts[v][1]) for v in rim]
    rings = [rim]
    for frac in LAVA_RINGS[1:]:
        p0, p1 = r.f() * TWO_PI, r.f() * TWO_PI
        k0, k1 = r.i(2, 4), r.i(5, 8)
        ring = []
        for k, t in enumerate(cols):
            rad = rad0[k] * frac
            taper = min(1.0, max(0.0, (rad - LAVA_FLAT_R) / 8.0))
            dz = LAVA_SWELL * taper * (0.62 * math.sin(k0 * t + p0)
                                       + 0.38 * math.sin(k1 * t + p1))
            dz = LAVA_STEP * round(dz / LAVA_STEP)   # plateaus: crust plates, not swell
            ring.append(m.v((rad * math.cos(t), rad * math.sin(t), z + dz)))
        rings.append(ring)
    ncol = len(cols)
    for a, b in zip(rings, rings[1:]):
        for k in range(ncol):
            j = (k + 1) % ncol
            m.quad(a[k], a[j], b[j], b[k], UP, ZONE_LAVA)
    cid = m.v((0.0, 0.0, z))
    last = rings[-1]
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


def _s4_hidden(rock, body, eye):
    """Clearance (m) by which the crest hides the top of a 1.8 m body standing
    at local (u, v) on the rock from the eye; positive = hidden."""
    x, y = _s4_world(rock, *body)
    head = (x, y, rock["top"] + S4_BODY_H)
    best = -9.0
    for k in range(1, 400):
        f = k / 400.0
        p = (eye[0] + (head[0] - eye[0]) * f, eye[1] + (head[1] - eye[1]) * f,
             eye[2] + (head[2] - eye[2]) * f)
        if not _s4_inside(rock, p):
            continue
        u, v = _s4_local(rock, p)
        best = max(best, rock["top"] + _s4_crest(rock, u, v) - p[2])
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
    """Review renders only: a white sun, grey fill, the rock flat mid-grey so
    form reads, the lava still glowing; proxies for a body. The glb was
    exported before this runs and everything here is put back after."""
    lay = _s4_layout()
    rocks = lay["rocks"]
    p0 = lay["pads"][0]

    def on(rock, u, v, dz=0.0):
        x, y = _s4_world(rock, u, v)
        return (x, y, rock["top"] + dz)

    shot("s4_lit", (p0[0], p0[1], DECK_Z + EYE_H), on(rocks[1], 0.0, 1.0, 0.8), 24.0, (1400, 800))
    shot("s4_lit_r1", on(rocks[0], -1.5, -0.5, EYE_H), (lay["pads"][2][0], lay["pads"][2][1], lay["pads"][2][2] + 0.3),
         24.0, (1400, 800))
    sun_w, grey, fill, ev = S4_REVIEW
    ld.energy, ld.color = sun_w, (1.0, 1.0, 1.0)
    key.rotation_euler = (math.radians(40.0), math.radians(25.0), 0.0)
    bg.inputs[0].default_value = (grey, grey, grey, 1.0)
    bg.inputs[1].default_value = fill
    mdl._try(scene.view_settings, "exposure", ev)
    rock_ob = objects[0]
    was = rock_ob.data.materials[0]
    rock_ob.data.materials[0] = mdl.flat_material("ReviewGrey", (0.42, 0.42, 0.42, 1.0))

    yellow = (1.0, 0.85, 0.1, 1.0)
    body = _s4_proxy("ReviewBody", on(rocks[1], -1.4, -0.4), (0.6, 0.6, S4_BODY_H), yellow)
    O, f = lay["origins"][2], lay["pads"][2][3]
    apex = (O[0] + 7.0 * f[0], O[1] + 7.0 * f[1], O[2] + 3.68)
    flyer = _s4_proxy("ReviewFlyer", apex, (0.6, 0.6, S4_BODY_H), yellow)

    shot("review_entry", (p0[0], p0[1], DECK_Z + EYE_H), on(rocks[1], 0.0, 1.0, 0.8), 24.0, (1400, 800))
    p2 = lay["pads"][2]
    shot("review_r1", on(rocks[0], -1.5, -0.5, EYE_H), (p2[0], p2[1], p2[2] + 0.3), 24.0, (1400, 800))
    shot("review_guard", (0.0, 0.0, S4_GUARD_EYE), pol(242.0, 52.0, DECK_Z), 35.0, (1400, 900))
    shot("review_high", pol(241.5, 20.0, 60.0), pol(241.5, 52.0, DECK_Z), 24.0, (1500, 1000))
    shot("review_cover", (0.0, 0.0, S4_GUARD_EYE), on(rocks[1], -1.0, 0.0, 0.9), 100.0, (1200, 800))
    shot("review_outer", pol(216.0, 56.4, DECK_Z + EYE_H), pol(248.0, 56.9, LAVA_Z), 28.0, (1400, 800))

    for ob in (body, flyer):
        bpy.data.objects.remove(ob, do_unlink=True)
    rock_ob.data.materials[0] = was
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
    for k, rk in enumerate(rocks):
        L = lay["lands"][k]
        u, v = _s4_local(rk, L)
        # tolerance along the flight: how far short/long still lands on the top
        f = lay["pads"][k][3]
        short = long_ = 0.0
        E = S4_EDGE_Q

        def stand(p):
            uu, vv = _s4_local(rk, p)
            qq = max(_s4_q(rk, uu, vv), -uu / (S4_REAR / E), uu / (S4_FRONT / E))
            return qq <= E and _s4_hump(rk, uu, vv) < 0.3
        while stand((L[0] - (short + 0.05) * f[0], L[1] - (short + 0.05) * f[1])):
            short += 0.05
        while stand((L[0] + (long_ + 0.05) * f[0], L[1] + (long_ + 0.05) * f[1])):
            long_ += 0.05
        side = 0.0
        nrm = (-f[1], f[0])
        while stand((L[0] + (side + 0.05) * nrm[0], L[1] + (side + 0.05) * nrm[1])) \
                and stand((L[0] - (side + 0.05) * nrm[0], L[1] - (side + 0.05) * nrm[1])):
            side += 0.05
        vs = [x / 100.0 for x in range(0, 500)]
        chest_vs = [vv for vv in vs if _s4_crest(rk, u, vv) >= S4_CHEST]
        width = (chest_vs[-1] - chest_vs[0]) if chest_vs else 0.0
        peak = max(_s4_crest(rk, u, vv) for vv in vs)
        hidden = min(_s4_hidden(rk, (uu, vv2), eye)
                     for uu in (-S4_REAR + 0.4, u, u + 0.8)
                     for vv2 in (-S4_HALF_ACROSS + 0.5, 0.0, S4_HALF_ACROSS - 0.6))
        print("MDL STATS s4 rock%d bearing=%.2f r=%.2f top=%.2f (+%.2f) axis_godot=(%.4f, 0, %.4f) "
              "landing local u=%.2f v=%.2f: %.2f m past the near edge, tolerance -%.2f/+%.2f m along, "
              "+-%.2f m across | hump +%.2f m over the landing, %.2f m thick at chest, hides a %.1f m body by %.2f m"
              % (k + 1, rk["b"], rk["r"], rk["top"], rk["top"] - DECK_Z, rk["a"][0], -rk["a"][1],
                 u, v, u + S4_REAR, short, long_, side, peak, width, S4_BODY_H, hidden))
    # gaps between consecutive walkable tops, along the flight lines
    def outline(rk):
        """Where a body can land and stand: out to the standing edge, and on
        the tower side only to the hump's ridge (its inner face sheds into
        the lava)."""
        pts = []
        for k in range(120):
            th = TWO_PI * k / 120.0
            rr = S4_EDGE_Q * rk["R"](th)
            u, v = rr * math.cos(th), rr * math.sin(th)
            v = min(v, S4_HUMP_V)
            u = min(max(u, -S4_REAR), S4_FRONT)        # the tail and the shoulders beyond are no landing
            pts.append(_s4_world(rk, u, v))
        return pts

    def arc(bearing):
        return [pol(bearing, 46.7 + 10.6 * k / 30.0, 0.0)[:2] for k in range(31)]

    chains = [arc(lay["bank_entry"] + math.degrees(S4_EDGE_WANDER[1] / INNER_R))] \
        + [outline(rk) for rk in rocks] + [arc(lay["bank_exit"] - math.degrees(S4_EDGE_WANDER[1] / INNER_R))]
    gaps = []
    for k in range(len(chains) - 1):
        d = min(math.hypot(p[0] - q[0], p[1] - q[1]) for p in chains[k] for q in chains[k + 1])
        gaps.append(d)
    heights = [DECK_Z] + [rk["top"] for rk in rocks] + [DECK_Z]
    for k, d in enumerate(gaps):
        drop = heights[k] - heights[k + 1]
        print("MDL STATS s4 gap%d=%.2f m (lava between walkable tops) vs slide-jump reach %.2f m, run-jump %.2f m"
              % (k + 1, d, _s4_jump(-drop, S4_SLIDE), _s4_jump(-drop, S4_RUN)))
    print("MDL STATS s4 min_gap=%.2f m" % min(gaps))
    # the runner in the air: the apex of every hop against the crests
    for k in range(len(lay["pads"])):
        O, L = lay["origins"][k], lay["lands"][k]
        f = lay["pads"][k][3]
        apx = (O[0] + 7.0 * f[0], O[1] + 7.0 * f[1], O[2] + 3.68)
        blocked = 0.0
        for rk in rocks:
            for kk in range(1, 400):
                ff = kk / 400.0
                p = (eye[0] + (apx[0] - eye[0]) * ff, eye[1] + (apx[1] - eye[1]) * ff,
                     eye[2] + (apx[2] - eye[2]) * ff)
                if _s4_inside(rk, p):
                    uu, vv = _s4_local(rk, p)
                    blocked = max(blocked, rk["top"] + _s4_crest(rk, uu, vv) - p[2])
        print("MDL STATS s4 hop%d apex y=%.2f: crest over the guard's sight line by %.2f m (<=0 exposed)"
              % (k + 1, apx[2], blocked))
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

    def rec(z):
        return max(_lip(LAVA_Z - z), RECESS_R * _ramp(LAVA_Z - z, 0.0, PIT_FADE))

    node = {}
    row_of = {round(z, 6): BANK_WALL + BANK_DECK - 2 + k for k, z in enumerate(reversed(zs))}

    def N(t, z):
        """The fall's own vertex: the bank line's edge at this row, the
        columns between following it, all recessed rec(z)."""
        key = (round(t, 6), round(z, 6))
        if key not in node:
            i = row_of[round(z, 6)]
            rad = INNER_R
            if abs(t - ta) < 1e-9:
                da = _bank_da(lines[0], 0, i, rad)
            elif abs(t - tb) < 1e-9:
                da = _bank_da(lines[1], 1, i, rad)
            else:
                da = (_bank_da(lines[0], 0, i, rad) * max(0.0, 1.0 - (t - ta) * rad / BANK_REACH)
                      + _bank_da(lines[1], 1, i, rad) * max(0.0, 1.0 - (tb - t) * rad / BANK_REACH))
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
    for t, into in ((ta, -1.0), (tb, 1.0)):        # the two banks
        want = (-math.sin(t) * into, math.cos(t) * into, 0.0)
        _strip(m, [(z, wall.W(t, z)) for z in zc], [(z, N(t, z)) for z in zs],
               want, ZONE_SHADE)
    _strip(m, [(t, wall.W(t, za)) for t in rim_ts], [(t, N(t, za)) for t in ts],
           UP, ZONE_SHADE)                         # the sill at the sea
    return tris, N


def _pit_bank_ends(m, wall, cut_a, cut_b, ta, tb, N):
    """The triangles that close the deck's sloped bank against the pit wall,
    where the rim steps from the deck down to the river's rounded lip."""
    for cut, t, sgn in ((cut_a, ta, 1.0), (cut_b, tb, -1.0)):
        want = (-math.sin(cut) * sgn, math.cos(cut) * sgn, 0.0)
        m.tri(wall.W(cut, DECK_Z), wall.W(cut, LAVA_Z), wall.W(t, LAVA_Z), want, ZONE_SHADE)
        if N(t, LAVA_Z) != wall.W(t, LAVA_Z):
            m.tri(wall.W(cut, DECK_Z), wall.W(t, LAVA_Z), N(t, LAVA_Z), want, ZONE_SHADE)


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
    for (au, av, top, hump, dr), gap in zip(S2_PLATS, S2_GAPS):
        sp = _s2_spec(rm, au, av, top, hump)
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


def _s2_spec(r, au, av, top, hump):
    """One boulder's own numbers: its waterline R(theta), hump and noise."""
    p1, p2 = r.f() * TWO_PI, r.f() * TWO_PI
    jit = [r.sf() * 0.02 for _ in range(S2_MASS_N)]
    ang = [TWO_PI * (i + 0.5 + 0.25 * r.sf()) / S2_MASS_N for i in range(S2_MASS_N)]

    def R(th):
        c, s = abs(math.cos(th)), abs(math.sin(th))
        rr = 1.0 / ((c / au) ** S2_MASS_P + (s / av) ** S2_MASS_P) ** (1.0 / S2_MASS_P)
        return rr * (1.0 + S2_WOB * (0.6 * math.sin(2.0 * th + p1) + 0.4 * math.sin(3.0 * th + p2)))
    return {"au": au, "av": av, "top": top, "R": R, "ang": ang, "jit": jit,
            "h": (S2_HUMP_H[0] + r.f() * (S2_HUMP_H[1] - S2_HUMP_H[0])) if hump else 0.0,
            "vh": -S2_HUMP_V * av, "ah": S2_HUMP_U * au,
            "noise": _field(_Rng(r.n()), S2_NOISE, 5, S2_NOISE_L)}


def _s2_edge_q(top, a):
    """Where the shoulder's pitch along the run reaches 45 deg: the standing edge."""
    drop = top - (LAVA_Z - S2_WATER_D)
    s = min(1.0, (1.0 - S2_FLAT_Q) * a / (drop * 0.5 * math.pi))
    return S2_FLAT_Q + (1.0 - S2_FLAT_Q) * math.asin(s) / math.pi


def _s2_z(sp, u, v, q):
    """(z, landing) of a boulder at local (u, v), q of the waterline out."""
    top, H = sp["top"], sp["h"]
    water = LAVA_Z - S2_WATER_D
    if q <= S2_FLAT_Q:
        zs = top
    elif q <= 1.0:
        t = (q - S2_FLAT_Q) / (1.0 - S2_FLAT_Q)
        zs = top - (top - water) * math.sin(0.5 * math.pi * t) ** 2
    else:
        zs = water - (q - 1.0) / (S2_MASS_Q[-1] - 1.0) * (S2_BOTTOM_D - S2_WATER_D)
    D = 0.0
    if H:
        dv = v - sp["vh"]
        bh = S2_HUMP_B[0] if dv < 0.0 else S2_HUMP_B[1]
        d2 = (abs(u) / sp["ah"]) ** S2_HUMP_P[0] + (dv / bh) ** 2
        if d2 < 1.0:
            D = (1.0 - d2) ** S2_HUMP_P[1]
    land = _ramp(S2_FLAT_Q - q, 0.0, 0.08) * _ramp(0.03 - D, 0.0, 0.03)
    return zs + H * D + (1.0 - land) * sp["noise"](u, v), land


def _s2_mass(m, sp):
    """One boulder in the river, a closed heightfield: a centre, rings out to
    a bottom ring under the lava, all one surface -- landing, hump, shoulders
    and stem are the same rock. The collider gets the identical mesh."""
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


def _s2_collider(c, s2, ang, lip, foot, CV):
    """The river's collision on the same bank lines: lane, inner bank, floor
    flat at the lava, outer bank; then the masses with straight sides."""
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


def _s2_stats(s2):
    """The chain as built: gaps between standing edges (the 45-degree line on
    the shoulders), and the cover line from the guard's eye over each hump
    to a 1.8 m body on the landing behind it."""
    eye = (0.0, 0.0, 27.0)
    edges = []
    for sp in S2_MASSES:
        P = _s2_frame(sp["b"], sp["rad"])
        edges.append([P(sp["qe"] * sp["R"](th) * math.cos(th), sp["qe"] * sp["R"](th) * math.sin(th), 0.0)
                      for th in sp["ang"]])
    ends = (pol(s2["a0"] + S2_END, S2_PLAT_R, DECK_Z), pol(s2["a1"] - S2_END, S2_PLAT_R, DECK_Z))
    chain = [[ends[0]]] + edges + [[ends[1]]]
    gaps = [min(math.dist(p[:2], q[:2]) for p in a for q in b) for a, b in zip(chain, chain[1:])]
    print("MDL STATS s2 river=%.2f..%.2f deg lava_y=%.2f masses=%d far_gap=%.2f cols=%d"
          % (s2["a0"], s2["a1"], LAVA_Z, len(S2_MASSES), s2["far_gap"], len(s2["span"])))
    for k, sp in enumerate(S2_MASSES):
        au, av, top = sp["au"], sp["av"], sp["top"]
        line = "MDL STATS s2mass%d bearing=%.2f r=%.2f top=%.2f water=%.1fx%.1f stand=%.1f flat=%.1fx%.1f gap_before=%.2f gap_after=%.2f" % (
            k + 1, sp["b"], sp["rad"], top, 2 * au, 2 * av, 2 * sp["qe"] * au,
            2 * S2_FLAT_Q * au, S2_FLAT_Q * av - (sp["vh"] + S2_HUMP_B[1]) if sp["h"] else 2 * S2_FLAT_Q * av,
            gaps[k], gaps[k + 1])
        if sp["h"]:
            rb = sp["rad"] + sp["vh"] + S2_HUMP_B[1] + 0.35            # the body: 0.05 m behind the foot
            worst = 1e9
            for iu in range(-7, 8):
                u = 0.05 * iu
                block = -1e9
                for iv in range(0, 60):
                    v = sp["vh"] - 1.3 + 0.025 * iv
                    q = math.hypot(u, v) / sp["R"](math.atan2(v, u))
                    z, _l = _s2_z(sp, u, v, q)
                    block = max(block, eye[2] + (z - eye[2]) * (rb / (sp["rad"] + v)))
                worst = min(worst, block)
            peak = max(_s2_z(sp, 0.0, sp["vh"] + 0.02 * i, 0.5)[0] for i in range(-20, 21)) - top
            line += " hump_h=%.2f base_d=%.1f sight_clear=%.2f" % (peak, S2_HUMP_B[0] + S2_HUMP_B[1],
                                                                 worst - (top + 1.8))
        print(line)
    for k in range(S2_TRAP_N):
        b = s2["a0"] + (k + 0.5) * (s2["a1"] - s2["a0"]) / S2_TRAP_N
        along = 2.0 * S2_TRAP_R[1] * math.sin(math.radians(0.5 * (s2["a1"] - s2["a0"]) / S2_TRAP_N)) + 0.2
        rm = 0.5 * (S2_TRAP_R[0] + S2_TRAP_R[1])
        sb, cb = math.sin(math.radians(b)), math.cos(math.radians(b))
        print("MDL STATS s2trap%d transform=Transform3D(%.6f, 0, %.6f, 0, 1, 0, %.6f, 0, %.6f, %.4f, %.2f, %.4f) size=Vector3(%.2f, 0.4, %.2f)"
              % (k + 1, sb, cb, -cb, sb, rm * cb, LAVA_Z, rm * sb, along, S2_TRAP_R[1] - S2_TRAP_R[0]))


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
S1_NW = 8                    # wall rows, head -> foot
S1_LIP_Z = 17.0              # the pit-lip relief band: the pit wall's own top row
S1_LIP_D = (0.25, 0.6, 1.2, 2.0, 3.0, 4.2, 5.3)   # its rows, metres under the deck
S1_DECK_AMP, S1_DECK_L = 0.22, (2.5, 6.0)  # flowstone undulation: peak, wavelengths
S1_MOUND = (0.10, 2.2)       # a low mound under each cluster: height, radius
S1_CEIL_SAG, S1_CEIL_L = 0.40, (3.0, 6.0)  # the ceiling sags 0..2x this
S1_DRIP = (0.15, 0.45, 0.9, 1.5)           # drip cone round a stalactite: height lo/hi, radius lo/hi
S1_FILLET = 1.2              # ceiling-to-wall corner round-over radius
S1_RIB = {"depth": (0.3, 0.8), "width": (0.3, 0.55), "gap": (1.0, 2.2), "wander": 0.25}
S1_LIP = {"depth": (0.3, 0.6), "width": (0.3, 0.55), "gap": (0.9, 2.0), "wander": 0.15}
S1_CLUSTERS = [(20.0, 48.4), (25.0, 55.4), (30.0, 53.5), (35.0, 48.4), (40.0, 55.4),
               (45.0, 53.5), (50.0, 48.4), (55.0, 55.4), (58.0, 53.5)]
S1_MAIN_H = (3.3, 5.5)
S1_MAIN_R = (0.40, 0.45)     # body radius at the foot, before the flare
S1_FLARE = 1.95              # base ring radius over body radius
S1_LOBE = (0.85, 1.1)        # the fused side lobe, in body radii at the foot ...
S1_LOBE_H = (0.58, 0.72)     # ... gone by this fraction of the height
S1_SAT = (0.9, 2.0, 0.18, 0.27)          # satellites: height lo/hi, body radius lo/hi
S1_SMALL = (14, 0.4, 1.2, 0.10, 0.18)    # scattered small ones: count, height, radius
S1_COLUMNS = [(23.0, 48.3), (35.5, 55.9), (39.5, 48.3), (51.0, 55.9)]
S1_COL_R = (0.34, 0.48)      # full column waist radius
S1_TITES = (30, 1.0, 6.0, 0.12, 0.36)    # stalactites: count, length lo/hi, base radius lo/hi
S1_TITE_FLARE = 2.0
S1_OVER = (20.0, 35.0, 50.0) # clusters with a stalactite dripping over the main spire
S1_LANE_CLEAR = 2.7          # a tip over the lane keeps this over the deck ...
S1_OFF_CLEAR = 1.6           # ... off the lane this, with a collider under 2.3
S1_LANE = [(10.0, 52.0), (27.0, 52.0), (28.2, 50.7), (31.8, 50.7), (33.0, 52.0), (42.0, 52.0),
           (43.2, 50.7), (46.8, 50.7), (48.0, 52.0), (55.0, 52.0), (56.2, 50.7), (59.8, 50.7),
           (63.0, 52.0)]
S1_LANE_W = 3.0
S1_EYE_Z = 27.0
S1_COVER_H = 1.6             # the silhouette is measured from the deck up to here
S1_REVIEW = True             # review-only lights and a player proxy; never exported
S1_RREF = 0.5 * (INNER_R + OUTER_R)
S1 = {}                      # handed from the sculpt to the collider, stats and renders


def _s1_lane_r(b):
    pts = S1_LANE
    if b <= pts[0][0]:
        return pts[0][1]
    for (b0, r0), (b1, r1) in zip(pts, pts[1:]):
        if b0 <= b <= b1:
            return r0 + (r1 - r0) * (b - b0) / (b1 - b0)
    return pts[-1][1]


def _s1_in_lane(b, rad, margin=0.0):
    return abs(rad - _s1_lane_r(b)) < 0.5 * S1_LANE_W + margin


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


def _s1_fill(m, loop, rings, want, zone, tag):
    """Triangulate a rectangular hole (loop: [(param, id)] round it) minus the
    rings inside it (each [(param, id)], closed), welding every vertex. Every
    loop and ring edge must come out of the triangulation, or the build fails."""
    pts, ids = [p for p, _ in loop], [i for _, i in loop]
    spans = []
    for ring in rings:
        k0 = len(pts)
        pts += [p for p, _ in ring]
        ids += [i for _, i in ring]
        spans.append((k0, len(pts)))
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

    def __init__(self, kind, b, rad, H, R, sides, r, us, flare, lobe=None, bend=0.08, nridge=3,
                 ridge_amp=(0.09, 0.22), jitter=0.07):
        self.kind, self.b, self.rad, self.H, self.R, self.sides = kind, b, rad, H, R, sides
        self.us, self.flare, self.lobe = us, flare, lobe
        self.angs = [TWO_PI * (i + 0.28 * r.sf()) / sides for i in range(sides)]
        self.fac = [1.0 + 0.13 * r.sf() for _ in range(sides)]
        self.jit = [[1.0 + jitter * r.sf() for _ in range(sides)] for _ in us]
        self.bend = (r.f() * TWO_PI, bend * (0.6 + 0.4 * r.f()), r.f() * TWO_PI)
        body = [u for u in us if 0.2 < u < 0.9]
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
            base = 1.0 + 1.1 * math.exp(-u / 0.06) + 0.9 * math.exp(-(1.0 - u) / 0.06)
        else:
            base = 1.0 - 0.72 * u ** 1.4 - 0.12 * max(0.0, (u - 0.92) / 0.08)   # a rounded crown
        ridge = 1.0
        for (uk, ak, wk) in self.ridges:
            ridge += ak * max(0.0, 1.0 - ((u - uk) / wk) ** 2)
        return self.R * base * ridge

    def flare_f(self, u):
        if self.kind == "column":
            return 1.0
        return 1.0 + (self.flare - 1.0) * math.exp(-u / 0.045)

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
        return self.body(u) * self.fac[i] * j * (self.flare_f(u) + self.lobe_f(i, u))

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
        return fade_s(bearing(x, y)) * fr * (S1_DECK_AMP * deck_waves(x, y) + bump(x, y, mounds))

    def C(x, y):
        """The ceiling's drop under CEIL_Z: sags, and a drip cone per stalactite."""
        rho = math.hypot(x, y)
        fr = min(_ramp(rho - INNER_R, 0.0, 1.5), _ramp(OUTER_R - rho, 0.3, 1.3))
        return fade_s(bearing(x, y)) * fr * (S1_CEIL_SAG * (1.0 + ceil_waves(x, y)) + bump(x, y, drips))

    ribs = _s1_grooves(_Rng(S1_SEED + 3), lo * OUTER_R - 3.0, hi * OUTER_R + 3.0, S1_RIB)
    lipg = _s1_grooves(_Rng(S1_SEED + 4), lo * INNER_R - 3.0, hi * INNER_R + 3.0, S1_LIP)
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

    def lip_pos(t, d):
        """Pit-lip band point d under the deck: an undercut lip, ribs below."""
        fs = fade_s(_bear_deg(t))
        z = DECK_Z - d
        x, y, _ = _wall_point(pit_wall, t, z)
        env = _ramp(d, 0.0, 0.5) * _ramp(DECK_Z - S1_LIP_Z - d, 0.0, 1.2) * fs
        rec = env * (0.3 + lipg(t * INNER_R, z))
        return (x + math.cos(t) * rec, y + math.sin(t) * rec, z)

    # ---- the plan: what grows where. Blocks of cells are claimed on the deck
    # and ceiling grids so every base has a hole of its own to weld into. -----
    rho = [INNER_R + (OUTER_R - INNER_R) * j / S1_NS for j in range(S1_NS + 1)]
    used_d, used_c = {}, {}          # cell -> the block that claimed it
    cstep = LC / S1_NC
    dstep = (OUTER_R - INNER_R) / S1_NS

    def col_of(b, w=2):
        if w % 2:
            b += 0.5 * (scb[0] - scb[1])          # an odd block is centred on a column
        return min(range(n), key=lambda i: abs(scb[i] - b))

    def claim(used, i0, i1, j0, j1, jmax, lane_margin):
        if i0 < 1 or i1 > n - 2 or j0 < 1 or j1 > jmax:
            return False
        cells = [(i, j) for i in range(i0, i1) for j in range(j0, j1)]
        if any(c in used for c in cells):
            return False
        if lane_margin is not None:
            for (i, j) in cells:
                if _s1_in_lane(0.5 * (scb[i] + scb[i + 1]), INNER_R + (j + 0.5) * dstep, lane_margin):
                    return False
        for c in cells:
            used[c] = (i0, i1, j0, j1)
        return True

    def interior(used, i, j):
        blocks = set(used.get(c) for c in ((i - 1, j - 1), (i, j - 1), (i - 1, j), (i, j)))
        return len(blocks) == 1 and None not in blocks

    def block_deck(b, rad, w, h, lane_margin=0.2):
        ic, jc = col_of(b, w), int(round((rad - INNER_R) / dstep))
        i0, j0 = ic - w // 2, jc - h // 2
        j0 = max(1, min(S1_NS - 1 - h, j0))
        if not claim(used_d, i0, i0 + w, j0, j0 + h, S1_NS - 1, lane_margin):
            return None
        return (i0, i0 + w, j0, j0 + h)

    def block_ceil(b, rad, w, h):
        ic, jc = col_of(b, w), int(round((rad - INNER_R) / cstep))
        i0, j0 = ic - w // 2, jc - h // 2
        j0 = max(1, min(S1_NC - 1 - h, j0))
        if not claim(used_c, i0, i0 + w, j0, j0 + h, S1_NC - 1, None):
            return None
        return (i0, i0 + w, j0, j0 + h)

    def centre_d(blk):
        return (0.5 * (sc[blk[0]] + sc[blk[1]]) * R_REF, 0.5 * (rho[blk[2]] + rho[blk[3]]))

    def centre_c(blk):
        return (0.5 * (sc[blk[0]] + sc[blk[1]]) * R_REF, INNER_R + 0.5 * (blk[2] + blk[3]) * cstep)

    def rng(lo_, hi_):
        return lo_ + r.f() * (hi_ - lo_)

    spikes, clusters, tites = [], [], []
    dblocks, cblocks = [], []       # (block, [spikes with a base ring in it])

    # full columns first: the landmarks
    for (b, rad) in S1_COLUMNS:
        bd = block_deck(b, rad, 4, 4, 0.0)
        bc = block_ceil(b, rad, 4, 3)
        if bd is None or bc is None:
            raise RuntimeError("S1: column @%.0f r%.1f does not fit" % (b, rad))
        sp = _S1Spike("column", b, rad, CEIL_H, rng(*S1_COL_R), 8, r, _S1Spike.U_COL, 1.0,
                      bend=0.03, nridge=4)
        sp.centre, sp.top = centre_d(bd), centre_c(bc)
        spikes.append(sp)
        dblocks.append((bd, [sp]))
        cblocks.append((bc, [sp]))

    # the nine cover clusters: a main spire with a fused lobe, satellites beside
    plan = []
    for (b, rad) in S1_CLUSTERS:
        bd = block_deck(b, rad, 4, 4, 0.0)
        if bd is None:
            raise RuntimeError("S1: cluster @%.0f r%.1f does not fit" % (b, rad))
        side = 1.0 if r.f() < 0.5 else -1.0          # +1: the lobe toward +tangential (higher column index)
        lobe = (side * 0.5 * math.pi + 0.25 * r.sf(), rng(*S1_LOBE), rng(*S1_LOBE_H))
        main = _S1Spike("mite", b, rad, rng(*S1_MAIN_H), rng(*S1_MAIN_R), 8, r,
                        _S1Spike.U_MITE, S1_FLARE, lobe=lobe, bend=0.07, nridge=4)
        s0, r0 = centre_d(bd)
        main.centre = (s0 - side * 0.22 * R_REF / r0, r0)     # the lobe side keeps its fill margin
        cx, cy = deck_xy(main.centre[0] / R_REF, main.centre[1])
        mounds.append((cx, cy, S1_MOUND[0], S1_MOUND[1]))
        spikes.append(main)
        dblocks.append((bd, [main]))
        plan.append((b, rad, bd, side, main))
    for (b, rad, bd, side, main) in plan:            # satellites once every main block is claimed
        members = [main]
        nsat = r.i(1, 3)
        edge = {1.0: bd[1], -1.0: bd[0]}             # the next free column on each side
        inner = rad < _s1_lane_r(b)
        for k in range(nsat):
            sd = -side if k % 2 == 0 else side       # the first satellite faces the lobe
            placed = None
            for w in ((3, 2) if r.f() < 0.6 else (2,)):
                i0 = edge[sd] if sd > 0 else edge[sd] - w
                rows = [bd[2], bd[2] + 1, bd[3] - w] if inner else [bd[3] - w, bd[3] - w + 1, bd[2] + 1]
                for j0 in rows:
                    if claim(used_d, i0, i0 + w, j0, j0 + w, S1_NS - 1, 0.2):
                        placed = (i0, w, j0)
                        break
                if placed:
                    break
            if placed is None and not inner and rad < 55.0:   # a mid cluster: behind the main spire
                for w in (3, 2):
                    i0 = bd[0] + r.i(0, 4 - w)
                    if claim(used_d, i0, i0 + w, bd[3], bd[3] + w, S1_NS - 1, 0.2):
                        placed = (i0, w, bd[3])
                        break
            if placed is None:
                continue
            i0, w, j0 = placed
            if j0 < bd[3]:
                edge[sd] = i0 + w if sd > 0 else i0
            blk = (i0, i0 + w, j0, j0 + w)
            Hs = rng(S1_SAT[0], S1_SAT[1]) if w == 3 else rng(S1_SAT[0], 1.3)
            sat = _S1Spike("mite", b, rad, Hs, rng(S1_SAT[2], S1_SAT[3]) * (1.0 if w == 3 else 0.8),
                           6, r, _S1Spike.U_SAT, 1.9, bend=0.06, nridge=1)
            sat.centre = centre_d(blk)
            members.append(sat)
            spikes.append(sat)
            dblocks.append((blk, [sat]))
        clusters.append((b, rad, members))

    # scattered small ones by the walls
    small = []
    tries = 0
    while len(small) < S1_SMALL[0] and tries < 400:
        tries += 1
        b = rng(b_lo + 3.0, b_hi - 3.0)
        rad = rng(47.3, 48.9) if r.f() < 0.5 else rng(55.1, 56.7)
        blk = block_deck(b, rad, 2, 2)
        if blk is None:
            continue
        sp = _S1Spike("mite", b, rad, rng(S1_SMALL[1], S1_SMALL[2]), rng(S1_SMALL[3], S1_SMALL[4]),
                      5, r, _S1Spike.U_SMALL, 1.8, bend=0.05, nridge=1)
        sp.centre = centre_d(blk)
        spikes.append(sp)
        small.append(sp)
        dblocks.append((blk, [sp]))

    # stalactites: a few over their stalagmite, the rest thrown at the ceiling
    def add_tite(b, rad, L, R, blk):
        sp = _S1Spike("tite", b, rad, L, R, 7 if R > 0.26 else r.pick((5, 6, 6)), r, _S1Spike.U_TITE,
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

    for (b, rad, members) in clusters:
        if b not in S1_OVER:
            continue
        main = members[0]
        blk = block_ceil(_bear_deg(main.centre[0] / R_REF), main.centre[1], 3, 3)
        if blk is None:
            continue
        sp = add_tite(b, rad, 1.0, rng(0.24, 0.34), blk)
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
        L = S1_TITES[1] + (S1_TITES[2] - S1_TITES[1]) * r.f() ** 1.4
        L = max(S1_TITES[1], min(L, 2.2 + 12.0 * R))       # thin ones stay short
        add_tite(b, rad, L, R, blk)
        got += 1

    # ---- the grids' vertices, now every mound and drip cone is known --------
    G, WG, PG, param = {}, {}, {}, {}
    for i, t in enumerate(sc):
        s = t * R_REF
        boundary = i in (0, n - 1)
        if not boundary:
            pit_wall.add_xt(len(pit_wall.rows) - 1, t)
            shaft.add_xt(0, t)
        for j in range(S1_NS + 1):
            param[(i, j)] = (s, rho[j])
            if j == 0:
                G[(i, j)] = pit_wall.W(t, DECK_Z)
            elif j == S1_NS:
                G[(i, j)] = WF(0, t)
            elif not boundary and not interior(used_d, i, j):
                x, y = deck_xy(t, rho[j])
                G[(i, j)] = m.v((x, y, DECK_Z + H(x, y)))
    q_c = [LC * j / S1_NC for j in range(S1_NC + 1)]
    qs = q_c + [LC + CEIL_H * k / S1_NW for k in range(1, S1_NW + 1)]
    NQ = len(qs) - 1
    for i, t in enumerate(sc):
        boundary = i in (0, n - 1)
        for k, q in enumerate(qs):
            if k == 0:
                WG[(i, k)] = shaft.W(t, CEIL_Z)
            elif k == NQ:
                WG[(i, k)] = G[(i, S1_NS)]
            elif k == S1_NC and boundary:
                WG[(i, k)] = WF(len(wall) - 1, t)
            elif not boundary and not interior(used_c, i, k):
                WG[(i, k)] = m.v(wc_pos(t, q))
    S1["deck_xy"], S1["H"], S1["fade"] = deck_xy, H, fade_s

    # ---- base rings on the deck and the ceiling, the holes filled round them
    def ring_param(sp, centre, k):
        s0, r0 = centre
        return [(s0 + dt * R_REF / r0, r0 + dr) for (dr, dt) in sp.offsets(k)]

    def loop_of(blk, P, V):
        i0, i1, j0, j1 = blk
        path = [(i, j0) for i in range(i0, i1)] + [(i1, j) for j in range(j0, j1)] \
            + [(i, j1) for i in range(i1, i0, -1)] + [(i0, j) for j in range(j1, j0, -1)]
        return [(P(i, j), V[(i, j)]) for (i, j) in path]

    base_ids = {}
    fill_tris = 0
    for (blk, sps) in dblocks:
        rings = []
        for sp in sps:
            pp = ring_param(sp, sp.centre, 0)
            pts = [deck_xy(s / R_REF, rr) for (s, rr) in pp]
            ids = [m.v((x, y, DECK_Z + H(x, y))) for (x, y) in pts]
            base_ids[(sp, "deck")] = ids
            sp.base = (DECK_Z + H(*deck_xy(sp.centre[0] / R_REF, sp.centre[1])), pts)
            rings.append(list(zip(pp, ids)))
        fill_tris += _s1_fill(m, loop_of(blk, lambda i, j: param[(i, j)], G), rings, UP, ZONE_DECK,
                              "deck %s" % (blk,))
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
        fill_tris += _s1_fill(m, loop_of(blk, lambda i, j: (sc[i] * R_REF, INNER_R + j * cstep), WG),
                              rings, DOWN, ZONE_ROCK, "ceil %s" % (blk,))

    # ---- the spikes ---------------------------------------------------------
    def emit_tube(sp, lvl, frame, tip_dir):
        ns = sp.sides
        er, et = frame
        for a in range(len(lvl) - 1):
            for i in range(ns):
                j = (i + 1) % ns
                am = 0.5 * (sp.angs[i] + (sp.angs[j] if j else sp.angs[0] + TWO_PI))
                want = (er[0] * math.cos(am) + et[0] * math.sin(am),
                        er[1] * math.cos(am) + et[1] * math.sin(am), 0.0)
                m.quad(lvl[a][i], lvl[a][j], lvl[a + 1][j], lvl[a + 1][i], want, ZONE_ROCK, best=True)
        if tip_dir is not None:
            top = lvl[-1]
            c = tuple(sum(m.verts[v][k] for v in top) / ns for k in range(3))
            apex = m.v((c[0], c[1], c[2] + tip_dir * ((0.4 if sp.kind == "tite" else 0.25) * sp.body(1.0) + 0.04)))
            for i in range(ns):
                m.tri(top[i], top[(i + 1) % ns], apex, (0.0, 0.0, tip_dir), ZONE_ROCK)

    prisms = []
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
                lvl.append([m.v((x, y, z)) for (x, y) in pts])
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
            clear = S1_LANE_CLEAR if _s1_in_lane(sp.b, sp.rad, 1.0) else S1_OFF_CLEAR
            sp.H = max(S1_TITES[1], min(sp.H, zc - deck_here - clear))
            sp.base_z, sp.tip_z = zc, zc - sp.H
            sp.base = (zc, [ceil_xy(s / R_REF, rr) for (s, rr) in ring_param(sp, sp.centre, 0)])
            lvl = [base_ids[(sp, "ceil")]]
            for k in range(1, len(sp.us)):
                u = sp.us[k]
                z = zc - u * sp.H
                pts = [(cx + dx, cy + dy) for (dx, dy) in sp.section(u, frame)]
                sp.rings.append((z, pts))
                lvl.append([m.v((x, y, z)) for (x, y) in pts])
            emit_tube(sp, lvl, frame, -1.0)
            if sp.tip_z - deck_here < 2.3:
                prisms.append(sp)
            continue
        lvl = [base_ids[(sp, "deck")]]
        for k in range(1, len(sp.us)):
            u = sp.us[k]
            z = sp.deck_z + u * sp.H
            pts = [(cx + dx, cy + dy) for (dx, dy) in sp.section(u, frame)]
            sp.rings.append((z, pts))
            lvl.append([m.v((x, y, z)) for (x, y) in pts])
        emit_tube(sp, lvl, frame, 1.0)
        if sp.H >= 1.0:
            prisms.append(sp)

    # ---- the deck grid and its boundary strips ------------------------------
    deck_cells = 0
    for i in range(1, n - 2):
        for j in range(S1_NS):
            if (i, j) in used_d:
                continue
            m.quad(G[(i, j)], G[(i + 1, j)], G[(i + 1, j + 1)], G[(i, j + 1)], UP, ZONE_DECK, best=True)
            deck_cells += 1
    for (ib, ii) in ((0, 1), (n - 1, n - 2)):
        A = [(RST[j] - INNER_R, DV(sc[ib], j)) for j in range(len(RST))]
        B = [(rho[j] - INNER_R, G[(ii, j)]) for j in range(S1_NS + 1)]
        _strip(m, A, B, UP, ZONE_DECK)

    # ---- the ceiling-and-wall grid and its boundary strips ------------------
    def wc_want(c):
        if c[2] > CEIL_Z - 0.55 * F and math.hypot(c[0], c[1]) < OUTER_R - 0.55 * F:
            return DOWN
        a = math.atan2(c[1], c[0])
        return (-math.cos(a), -math.sin(a), 0.0)

    for i in range(1, n - 2):
        for k in range(NQ):
            if k < S1_NC and (i, k) in used_c:
                continue
            ids = (WG[(i, k)], WG[(i + 1, k)], WG[(i + 1, k + 1)], WG[(i, k + 1)])
            if k < S1_NC - 1:
                want, zone = DOWN, ZONE_ROCK
            else:
                c = tuple(sum(m.verts[v][q] for v in ids) / 4.0 for q in range(3))
                want = wc_want(c)
                zone = ZONE_ROCK
                if k >= S1_NC:
                    t, z = 0.5 * (sc[i] + sc[i + 1]), CEIL_Z - (0.5 * (qs[k] + qs[k + 1]) - LC)
                    zone = ZONE_SHADE if ribs(t * OUTER_R, z) > 0.45 else ZONE_ROCK
            m.quad(ids[0], ids[1], ids[2], ids[3], want, zone, best=True)
    for (ib, ii) in ((0, 1), (n - 1, n - 2)):
        t = sc[ib]
        A = [(LC * j / ceil_nv, CE(t, j)) for j in range(ceil_nv + 1)]
        for row in reversed(out_rows[:-1]):
            v = WR(row, t)
            A.append((LC + (CEIL_Z - m.verts[v][2]), v))
        B = [(qs[k], WG[(ii, k)]) for k in range(NQ + 1)]
        _strip(m, A, B, wc_want, ZONE_ROCK)

    # ---- the pit lip: a band cut out of the pit wall and re-laid ------------
    pit_wall.hole(lo, hi, S1_LIP_Z, DECK_Z)
    for k, z in enumerate(pit_wall.rows):        # the row under the band fans to its ends
        if abs(z - S1_LIP_Z) < 1e-6:
            pit_wall.add_xt(k, lo)
            pit_wall.add_xt(k, hi)
    ds = list(S1_LIP_D)
    for i, t in enumerate(sc):
        PG[(i, 0)] = G[(i, 0)]
        if i in (0, n - 1):
            continue
        for k, d in enumerate(ds):
            PG[(i, k + 1)] = m.v(lip_pos(t, d))

    def lip_want(c):
        a = math.atan2(c[1], c[0])
        return (-math.cos(a), -math.sin(a), 0.0)

    for i in range(1, n - 2):
        for k in range(len(ds)):
            am = 0.5 * (sc[i] + sc[i + 1])
            z = DECK_Z - 0.5 * ((ds[k - 1] if k else 0.0) + ds[k])
            zone = ZONE_SHADE if lipg(am * INNER_R, z) > 0.32 else ZONE_ROCK
            m.quad(PG[(i, k)], PG[(i + 1, k)], PG[(i + 1, k + 1)], PG[(i, k + 1)],
                   (-math.cos(am), -math.sin(am), 0.0), zone, best=True)
    bottom = [(t, pit_wall.W(t, S1_LIP_Z)) for t in pit_wall.tbreaks(lo, hi)]
    _strip(m, bottom, [(sc[i], PG[(i, len(ds))]) for i in range(1, n - 1)], lip_want, ZONE_ROCK)
    for (ib, ii) in ((0, 1), (n - 1, n - 2)):
        t = sc[ib]
        A = [(S1_LIP_Z, pit_wall.W(t, S1_LIP_Z)), (DECK_Z, pit_wall.W(t, DECK_Z))]
        B = [(DECK_Z - (ds[k - 1] if k else 0.0), PG[(ii, k)]) for k in range(len(ds), -1, -1)]
        _strip(m, A, B, lip_want, ZONE_ROCK)

    # ---- what the collider, the stats and the renders need -----------------
    S1["spikes"], S1["clusters"], S1["prisms"], S1["tites"] = spikes, clusters, prisms, tites
    S1["counts"] = {"deck_cells": deck_cells, "fill_tris": fill_tris, "subcols": n,
                    "small": len(small), "sats": sum(len(c[2]) - 1 for c in clusters),
                    "tites": len(tites), "columns": len(S1_COLUMNS),
                    "over": sum(1 for t in tites if t.over is not None)}
    S1["silhouette"] = _s1_silhouette(clusters)
    return lo, hi


def _s1_silhouette(clusters):
    """Per cluster, from the guard's eye: the combined width (metres at its
    distance) of every member's cross-section per 0.1 m of height over the
    deck up to S1_COVER_H; the narrowest, whether it is one unbroken
    silhouette all the way up, and its reach left/right of the main axis at
    1.0 m. [(bearing, min_width, unbroken, widths, left, right)]"""
    out = []
    for (b, rad, members) in clusters:
        main = members[0]
        am = math.atan2(main.cxy[1], main.cxy[0])
        dist = math.hypot(*main.cxy)
        widths, unbroken = [], True
        left = right = 0.0
        for kh in range(2, int(round(S1_COVER_H * 10)) + 1):
            z = main.deck_z + 0.1 * kh
            ivals = []
            for sp in members:
                rings = [sp.base] + sp.rings
                for (za, pa), (zb, pb) in zip(rings, rings[1:]):
                    if za - 1e-9 <= z <= zb + 1e-9 and zb > za:
                        f = (z - za) / (zb - za)
                        pts = [((1 - f) * p[0] + f * q[0], (1 - f) * p[1] + f * q[1]) for p, q in zip(pa, pb)]
                        angs = [(math.atan2(p[1], p[0]) - am + math.pi) % TWO_PI - math.pi for p in pts]
                        ivals.append((min(angs), max(angs)))
                        break
            ivals.sort()
            merged = []
            for a, c in ivals:
                if merged and a <= merged[-1][1] + 1e-9:
                    merged[-1] = (merged[-1][0], max(merged[-1][1], c))
                else:
                    merged.append((a, c))
            core = [iv for iv in merged if iv[0] <= 0.0 <= iv[1]]
            if not core:
                widths.append(0.0)
                unbroken = False
                continue
            a, c = core[0]
            widths.append((c - a) * dist)
            if kh == 10:
                left, right = -a * dist, c * dist
        out.append((b, min(widths), unbroken, widths, left, right, 0.5 * (right - left)))
    return out


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
            lv = []
            for k, h in enumerate(hs):
                u = min(1.0, h / sp.H)
                z = sp.deck_z - 0.1 if k == 0 else sp.deck_z + h
                lv.append((z, sp.section(u, sp.frame)))
        _s1_frustum(c, cx, cy, lv, sp.angs, sp.frame)
    S1["coll_tris"] = len(c.faces) - before + 2 * (len(cols) - 1) * NJ


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
            up = (-math.cos(am) + 0.0, -math.sin(am), 0.6)
            roof = WALL_LAVA_TOP + 0.5 * SLOT_H
            r_wall = math.hypot(*m.verts[WF(0, t0)][:2])

            def roofish(c):
                return c[2] > roof and math.hypot(c[0], c[1]) - r_wall > 0.5
            _strip(m, A, B,
                   lambda c: DOWN if roofish(c) else up,
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
    for cut, mid, bank, sgn in ((s4c0, s4m0, s4b0, 1.0), (s4c1, s4m1, s4b1, -1.0)):
        # the bank's end at the pit lip: a fan from the cut's rim vertex over
        # the wall's hole edge and the bank's own lip chain
        want = (-math.sin(cut) * sgn, math.cos(cut) * sgn, 0.0)
        chain = [pit_wall.W(cut, LAVA_Z), pit_wall.W(bank, LAVA_Z)]
        if S4PN(bank, LAVA_Z) != pit_wall.W(bank, LAVA_Z):
            chain.append(S4PN(bank, LAVA_Z))
        chain.append(pit_wall.W(mid, s4_z(mid)))
        apex = pit_wall.W(cut, DECK_Z)
        for a, b in zip(chain, chain[1:]):
            m.tri(apex, a, b, want, ZONE_SHADE)

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
            if t + hw > s1_lo and t - hw < s1_hi and c["z"] + 0.5 * c["h"] > S1_LIP_Z:
                S1["cells_skipped"] = S1.get("cells_skipped", 0) + 1
                continue                       # S1's pit-lip band is re-laid here
            if t - hw < s4b1 and t + hw > s4b0:
                continue                       # ... and the field's fall
            _carve(m, pit_wall, c)
        else:
            _carve(m, shaft, c)
    _build_platforms(m, _Rng(LAKE_SEED))
    _s2_build(m, s2, _Rng(S2_SEED + 1))
    s4r = _Rng(S4_SEED + 5)
    for rock in lay["rocks"]:
        _s4_rock(m, s4r, rock)
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
    dcols = _merge_cols(list(ang) + [ang[0] + TWO_PI], [cut0, cut1, s2["s0"], s2["s1"], s4[0], s4[3]])
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
                or (s1_lo - 1e-9 <= t0 and t1 <= s1_hi + 1e-9)):
            continue                                       # the rivers and S1 lay their own
        c.quad(a0, a1, CV("out", foot, t1), CV("out", foot, t0), UP, ZONE_ROCK)

    _lake_collider(c, _Rng(LAKE_SEED))
    _s2_collider(c, s2, ang, lip, foot, CV)
    _s1_collider(c)
    _s4_collider(c, _Rng(S4_SEED + 5), s4)
    _shelf_box(c)
    return c


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
    """One window over the whole sea: world x,y straight into the sheet."""
    for li in poly.loop_indices:
        co = me.vertices[me.loops[li].vertex_index].co
        uvl.data[li].uv = (0.5 + co[0] / LAVA_SPAN, 0.5 + co[1] / LAVA_SPAN)


def _flow_uv(me, uvl, poly, vertical):
    """The river's own sheet. U runs along the flow -- radially inward across
    the trench, straight down on the fall -- so the streaks always follow it."""
    for li in poly.loop_indices:
        co = me.vertices[me.loops[li].vertex_index].co
        rad = math.hypot(co[0], co[1])
        ang = math.atan2(co[1], co[0])
        u = ((LAVA_Z - co[2]) + (OUTER_R - INNER_R)) if vertical else (OUTER_R - rad)
        uvl.data[li].uv = (u / FLOW_SPAN, (-ang * CROSS_R) / CROSS_SPAN)


def _flow_uv_along(me, uvl, poly):
    """S2's river runs along the deck: U follows the bearing, V the radius."""
    for li in poly.loop_indices:
        co = me.vertices[me.loops[li].vertex_index].co
        u = -math.atan2(co[1], co[0]) * S2_PLAT_R
        uvl.data[li].uv = (u / FLOW_SPAN, (math.hypot(co[0], co[1]) - INNER_R) / CROSS_SPAN)


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
        if zone[0] == "lava":                    # own sheet: its own window per face
            _lava_uv(me, uvl, poly)
            continue
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
    covered = [ms for ms in S2_INFO["masses"] if ms["h"]]
    ms = covered[1]
    P = _s2_frame(ms["b"], ms["rad"])
    vb = ms["vh"] + S2_HUMP_B[1] + 0.35
    verts = [P(u, vb + v, ms["top"] + z) for z in (0.0, 1.8) for (u, v) in
             ((-0.3, -0.3), (0.3, -0.3), (0.3, 0.3), (-0.3, 0.3))]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    proxy = mdl.mesh("ReviewProxy", verts, faces)
    proxy.data.materials.append(mdl.flat_material("ReviewGreen", (0.2, 1.0, 0.3, 1.0)))
    shot("review_chain", pol(a0 - 3.0, S2_PLAT_R, DECK_Z + EYE_H), pol(a0 + 14.0, S2_PLAT_R, DECK_Z),
         28.0, (1400, 800))
    shot("review_lane", pol(a0 + 1.0, 48.5, DECK_Z + EYE_H), pol(a0 + 24.0, 50.5, DECK_Z),
         28.0, (1400, 800))
    shot("review_guard", (0.0, 0.0, 27.0), pol(102.0, 54.0, DECK_Z), 35.0, (1400, 900))
    shot("review_high", pol(0.5 * (a0 + a1) - 22.0, 24.0, 46.0), pol(0.5 * (a0 + a1) + 2.0, 52.5, DECK_Z),
         18.0, (1500, 1000))
    shot("review_cover", (0.0, 0.0, 27.0), P(0.0, 0.0, ms["top"] + 0.9), 85.0, (1200, 900))
    shot("review_outer", pol(a0 + 2.0, 56.85, DECK_Z + 1.2), pol(a0 + 20.0, 57.0, DECK_Z - 0.2),
         30.0, (1400, 800))

    for ob in (cam, target, key, fill, proxy):
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
    main = max((c[2][0] for c in S1["clusters"]), key=lambda s: s.H)
    off = [s[6] for s in S1["silhouette"] if s[0] == main.b][0]   # the silhouette's centre at 1 m
    x, y = main.cxy
    rad = math.hypot(x, y)
    er, et = (x / rad, y / rad), (-y / rad, x / rad)
    px, py = x + er[0] * 1.3 + et[0] * off, y + er[1] * 1.3 + et[1] * off   # 1.3 m behind it
    verts, faces = [], []
    for dz in (-0.05, 1.8):
        for (dr, dt) in ((-0.15, -0.3), (0.15, -0.3), (0.15, 0.3), (-0.15, 0.3)):
            verts.append((px + er[0] * dr + et[0] * dt, py + er[1] * dr + et[1] * dt, main.deck_z + dz))
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    proxy = mdl.mesh("PlayerProxy", verts, faces)          # 0.6 m across the sightline, 0.3 m deep
    proxy.data.materials.append(mdl.flat_material("ProxyGreen", (0.1, 0.9, 0.2, 1.0)))
    made.append(proxy)
    pf = bpy.data.lights.new("ReviewPitFill", type="POINT")   # the pit lip, for the guard's view
    pf.energy, pf.color, pf.shadow_soft_size = 9000.0, (1.0, 1.0, 1.0), 3.0
    f = mdl._link(bpy.data.objects.new("ReviewPitFill", pf))
    f.location = pol(37.0, 38.0, 25.0)
    made.append(f)
    mdl._try(scene.view_settings, "exposure", 0.7)
    mid = (x, y, main.deck_z + 1.0)
    shot("review_run", pol(13.0, 52.0, DECK_Z + EYE_H), pol(36.0, 52.0, 24.0), 24.0, (1400, 800))
    shot("review_run2", pol(40.0, 52.0, DECK_Z + EYE_H), pol(18.0, 51.5, 24.0), 24.0, (1400, 800))
    shot("review_guard", (0.0, 0.0, S1_EYE_Z), pol(37.0, 52.0, 24.0), 35.0, (1600, 900))
    shot("review_high", pol(20.0, 34.0, 30.8), pol(42.0, 52.0, 23.5), 22.0, (1500, 900))
    shot("review_cover", (0.0, 0.0, S1_EYE_Z), mid, 80.0, (1200, 900))
    shot("review_ceiling", pol(16.0, 52.5, DECK_Z + EYE_H), pol(34.0, 52.0, 29.5), 18.0, (1400, 900))
    mdl._try(scene.view_settings, "exposure", 0.0)
    for ob in made:
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    rock, ang, river, cut, s2, s4 = _rock(_Rng(SEED))
    coll = _collider(ang, cut[0], cut[1], s2, s4)

    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    lava_albedo, lava_emissive = _sheet("lava", _lava_texture)
    mdl.save_texture(lava_albedo)
    mdl.save_texture(lava_emissive)
    river_albedo, river_emissive = _sheet("river", _river_texture)
    mdl.save_texture(river_albedo)
    mdl.save_texture(river_emissive)

    ob = rock.object(OBJECT_NAME)
    unwrap(ob, rock.zones)
    mdl.finish(ob, rock_material("HellRock", albedo, emissive), strip_uvs=False)
    ob.data.materials.append(rock_material("LavaSea", lava_albedo, lava_emissive))
    ob.data.materials.append(river_material("LavaRiver", river_albedo, river_emissive))
    lava_tris = river_tris = 0
    for pi, poly in enumerate(ob.data.polygons):
        z = rock.zones[pi][0]
        if z == "lava":
            poly.material_index = 1
            lava_tris += 1
        elif z in ("river", "fall", "river_t"):
            poly.material_index = 2
            river_tris += 1

    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d lava_tris=%d river_tris=%d deck_uv=%.2f"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), lava_tris, river_tris,
             DECK_UV_SCALE))
    print("MDL STATS river=%.1f..%.1f deg lava_y=%.2f cols=%d bank=%.1f deg recess=%.2f "
          "wall_lava=%.1f..%.1f deg to y=%.2f pit_run_tris=%d"
          % (LAKE_A0, LAKE_A1, LAVA_Z, river[0], LAKE_BANK, RECESS_R,
             WALL_A0, WALL_A1, WALL_LAVA_TOP, river[1]))
    for k, (b, rad, inner) in enumerate(_platforms()):
        print("MDL STATS platform%d bearing=%.3f r=%.1f top=%.2f square=%.1f %s"
              % (k + 1, b, rad, PLAT_TOP_Z, 2.0 * PLAT_HALF, "inner+fin" if inner else "outer"))
    _s2_stats(s2)
    _s4_stats()
    print("MDL STATS cells=%d pit=%d pit_top=%.1f uniform_to=%.0f above200=%d top=%.0f"
          % (len(CELLS), sum(1 for c in CELLS if c[0][2] < DECK_Z),
             max(c[0][2] + 0.5 * c[3] for c in CELLS if c[0][2] < DECK_Z), UNIFORM_TOP,
             sum(1 for c in CELLS if c[0][2] > 200.0), max(c[0][2] for c in CELLS)))
    for (b, wmin, ok, ws, left, right, _off) in S1["silhouette"]:
        print("MDL STATS s1 cover @%.0f min_width=%.2f unbroken=%s at1m left=%.2f right=%.2f widths=%s"
              % (b, wmin, ok, left, right, " ".join("%.2f" % w for w in ws)))
    sp = S1["spikes"]
    print("MDL STATS s1 %s prisms=%d coll_tris=%d mites=%s tites=%s"
          % (" ".join("%s=%s" % kv for kv in sorted(S1["counts"].items())), len(S1["prisms"]), S1["coll_tris"],
             " ".join("%.1f" % s.H for s in sp if s.kind == "mite" and s.sides == 8),
             " ".join("%.1f" % s.H for s in sp if s.kind == "tite")))
    print("MDL STATS deck r=%.1f..%.1f y=%.2f courtyard_y=%.2f ceiling_y=%.2f rim_y=%.1f ground_r=%.0f"
          % (INNER_R, OUTER_R, DECK_Z, COURTYARD_Z, CEIL_Z, RIM_Z, GROUND_RINGS[-1][0]))
    return [ob, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_deck_render)
