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

ZONE_RIVER = ("river",)               # flow runs radially, wall -> lip
ZONE_FALL = ("fall",)                 # ... and straight down a wall
RIVER_TEX = 256
RIVER_ALBEDO = "map_base_river_albedo"
RIVER_EMISSIVE = "map_base_river_emissive"
RIVER_SEED = 7720133
FLOW_SPAN = 10.0
CROSS_SPAN = 10.0
CROSS_R = 52.0

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


def _field(r, amp, n=6):
    """A seeded 2-D height field: n plane waves, peak amp, metres."""
    ws = []
    for _ in range(n):
        a, L = r.f() * TWO_PI, FLOOR_L[0] + r.f() * (FLOOR_L[1] - FLOOR_L[0])
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
        if b > cut0 and a < cut1:               # under the river the rim is exact
            pbias[i][npit - 2] = 0.0            # too, so the channel welds to it
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

    # ---- the lava sea: what the pit floor is, and what lights it ------------
    _lava_sea(m, pit_wall, COURTYARD_Z, _Rng(LAVA_SEED), extra=lava_ts)

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
            return DECK_Z
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
        rows = IN_ROWS if in0 else OUT_ROWS
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

    def in_chan(t):
        return cut0 - 1e-9 <= t <= cut1 + 1e-9

    def river_pt(t, j, p, r_lip, r_foot):
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
        return WR(IN_ROWS[0], t) if in_chan(t) else WF(0, t)

    def DV(t, j, fine=False):
        """Deck vertex at station j: the deck's stations are fractions of the
        lip-to-foot run; the channel's are absolute radii (RST_RIVER), with
        the foot beyond them where the fall is cut back into the wall."""
        if j == 0:
            return PN(t, LAVA_Z) if bank0 - 1e-9 <= t <= bank1 + 1e-9 else pit_wall.W(t, chan_z(t))
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

    for ci in range(len(cols_all) - 1):
        t0, t1 = cols_all[ci], cols_all[ci + 1]
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
        for j in range(ceil_nv):
            m.quad(CE(t0, j), CE(t1, j), CE(t1, j + 1), CE(t0, j + 1),
                   (0.0, 0.0, -1.0), ZONE_ROCK)

    # ---- the cells, the river's run down the pit wall, then the faces they
    # were cut from -----------------------------------------------------------
    for c in _place_cells(_Rng(CELL_SEED), pit_wall, shaft):
        if c["z"] < DECK_Z:
            t = pit_wall._norm(c["s"] / INNER_R)
            if cut0 - 0.02 < t < cut1 + 0.02:
                continue                       # the channel runs down here
            _carve(m, pit_wall, c)
        else:
            _carve(m, shaft, c)
    _build_platforms(m, _Rng(LAKE_SEED))
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
    return m, ang, (len(sec_cols), pit_tris), (cut0, cut1)


# =============================================================================
# COLLISION -- flat deck, clean walls, courtyard floor. Nothing jittered.
# =============================================================================

def _collider(ang, cut0, cut1):
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
    dcols = _merge_cols(list(ang) + [ang[0] + TWO_PI], [cut0, cut1])
    cv = {}

    def CV(tag, ring, t, z=None):
        key = (tag, round(t, 7))
        if key not in cv:
            p = _chord(c, ring, ang, t)
            cv[key] = c.v(p if z is None else (p[0], p[1], z))
        return cv[key]

    for ci in range(len(dcols) - 1):
        t0, t1 = dcols[ci], dcols[ci + 1]
        inside = t0 >= cut0 - 1e-9 and t1 <= cut1 + 1e-9
        tz = LAVA_Z if inside else DECK_Z                  # the rim drops to the river
        am = 0.5 * (t0 + t1)
        inward = (-math.cos(am), -math.sin(am), 0.0)
        a0 = CV("lip%.2f" % tz, lip, t0, tz)
        a1 = CV("lip%.2f" % tz, lip, t1, tz)
        c.quad(CV("foot", pit_foot, t0), CV("foot", pit_foot, t1), a1, a0,
               inward, ZONE_SHADE)                                     # pit wall
        if inside:
            continue
        c.quad(a0, a1, CV("out", foot, t1), CV("out", foot, t0), UP, ZONE_ROCK)

    _lake_collider(c, _Rng(LAKE_SEED))
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
    if CELLS:
        cm, out, w, h = max([c for c in CELLS if c[0][2] < DECK_Z] or CELLS,
                            key=lambda c: c[3])
        eye = _v3(_v3(_v3(cm, out, -2.2 * h), UP, 0.35 * h), (-out[1], out[0], 0.0), 0.6 * h)
        shot("cell", eye, cm, 35.0, (1000, 800))
        shot("mouth", _v3(cm, out, -1.7 * h), cm, 40.0, (1000, 800))

    for ob in (cam, target, key):
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    rock, ang, river, cut = _rock(_Rng(SEED))
    coll = _collider(ang, cut[0], cut[1])

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
        elif z in ("river", "fall"):
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
    print("MDL STATS cells=%d pit=%d pit_top=%.1f uniform_to=%.0f above200=%d top=%.0f"
          % (len(CELLS), sum(1 for c in CELLS if c[0][2] < DECK_Z),
             max(c[0][2] + 0.5 * c[3] for c in CELLS if c[0][2] < DECK_Z), UNIFORM_TOP,
             sum(1 for c in CELLS if c[0][2] > 200.0), max(c[0][2] for c in CELLS)))
    print("MDL STATS deck r=%.1f..%.1f y=%.2f courtyard_y=%.2f ceiling_y=%.2f rim_y=%.1f ground_r=%.0f"
          % (INNER_R, OUTER_R, DECK_Z, COURTYARD_Z, CEIL_Z, RIM_Z, GROUND_RINGS[-1][0]))
    return [ob, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_deck_render)
