"""
PANOPTICON -- forest_tree: Map 3's tower. A great tree grown to be a tower.

Origin is the Tower node (world y 25.35), like tower.glb: the model drops in
at identity under scenes/ring/forest.tscn's Tower. Authored in WORLD
coordinates (Blender z = Godot y) and shifted on export.

    water ......... y -11.05   the trunk stands in it, eight buttress roots out to r ~9
    trunk ......... y -13..27.05, r 8 at the foot to 5.2 at y 20, then a goblet
                    flare out to r 7.0 at the floor; cos(8a) fluting with a ridge
                    on every pier bearing, so the piers continue the trunk's ridges
    floor ......... y 27.05 (origin + 1.70, as map 1), flat r 5, the top of the trunk;
                    a bark rim r 5.0..7.0 rises 0.55 m round it (the goblet's lip)
    piers ......... eight blade piers (r 0.9 -> 0.6, oval) out of sockets in the rim
                    top, leaning out to r 8 and into sockets in the canopy belly at
                    y 33.0: the guard's windows. One twig rail per opening at
                    floor + 0.95; a pointed arch between neighbours springs at
                    y ~29.85 and peaks at r 8.3, y 32.5. Nothing else sits in an
                    opening between y 28.2 and 29.5: the guard's sightline
    ceiling ....... the canopy belly, y 33.0 at r 9 sagging to 32.5 at the centre,
                    eight ribs from beside each pier's landing to a keystone boss:
                    a vault
    canopy ........ the leaf disc from the belly rim up to a lumpy crown at y 37.2,
                    eight-lobed rim r ~11; six short thick branches out of the top
                    ending in leaf clumps (the roof), tops ~y 39.4
    roof .......... Ryan: "make the roof higher, so make it like a dome that
                    collapses in the middle where the tree is". The crown's rim
                    (r 11, y 34.1) is that collapse: from it the leaf sheet
                    sweeps OUT AND UP to a crest ring (r 41.5, y 53.5) and
                    springs down onto the level's seam at r 47.6, y 50.0
                    (forest_seam, 240 shared points): one smooth curve, concave
                    from below, a dome off its wall. Rings on that curve,
                    split where a band would be a ribbon, billowing up to
                    +-0.46 m, the billow handing over to the seam's own wave
                    over the last 9 m; a coarse top skin runs back from the same
                    seam ring into the crown, so the sheet is a closed leaf mass
                    and no edge carries three faces. Its underside is many tree
                    tops of all sizes and shapes (CROWNS), creased where they meet,
                    the tower's crown one of them, the outer ones growing on over
                    the drum's head. Nothing the sheet carries comes
                    below y 32.7: the guard's eye is 28.7 and his downward
                    sightline to the lane is clear.

One material (the forest atlas, painted or textures/forest_atlas_albedo.png),
one mesh, no rig. ForestTreeCollision rides as a `-colonly` node: the trunk
cylinder r 5, the floor, the rim, the canopy's outer slope, and the sheet as a
24-gon ring on every forest_seam.SHEET radius, so a shot fired up over the
ravine stops on the dome's own curve. Nothing else is touched.

This file also holds what forest_build.py shares: the rng, the face
accumulator, the atlas painter, the tube/blob helpers, the unwrap.

    tools/modelling/model build forest_tree
    python3 tools/modelling/forest_tree_build.py --check
"""

import math
import os
import sys

try:
    import bpy
except ImportError:                       # --check on the Mac: geometry only
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, HERE + os.sep + "lib")
import forest_seam  # noqa: E402   the ring the level's roof and this crown share
if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["ground"] = False
    mdl.DEFAULTS["world_grey"] = 0.34
    mdl.DEFAULTS["world_strength"] = 0.95

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "forest_tree"
OBJECT_NAME = "ForestTree"
COLLIDER_NAME = "ForestTreeCollision-colonly"
FACING_YAW = 0.0

ORIGIN_Y = forest_seam.TOWER_ORIGIN_Y   # the Tower node: the model's origin, world y.
                            # forest_seam owns it: the seam only lands on one float in both
                            # models if the shift is the same number on both sides (settle)
WATER_Y = -11.05            # the map's water (map 1's lava sea level)
FLOOR_Y = ORIGIN_Y + 1.70   # the guard's floor, as map 1's room floor
FLOOR_R = 5.0
FLOOR_RINGS = ((3.4, 28), (1.6, 14))   # (r, verts): the flat floor gridded in, halving the count; no sliver fan
FOOT_Y = -13.0

PIERS = 8
TRUNK_SIDES = 48            # 6 per pier: a vertex on every pier bearing carries the ridge
# (y, r, flute share): the trunk profile, foot to the floor edge. The goblet flares
# to r 7.0 at the floor, the rim rises 0.55 over it and drops back to the floor.
TRUNK = [(-13.0, 8.0, 1.0), (-11.0, 7.5, 1.0), (-8.0, 6.9, 1.0), (-4.0, 6.5, 1.0), (0.0, 6.2, 1.0),
         (4.0, 5.95, 1.0), (8.0, 5.7, 1.0), (12.0, 5.5, 1.0), (16.0, 5.32, 1.0), (20.0, 5.2, 1.0),
         (22.5, 5.3, 1.0), (24.5, 5.7, 1.0), (26.0, 6.4, 1.0), (FLOOR_Y, 7.0, 1.0),
         (FLOOR_Y + 0.35, 7.05, 1.0), (FLOOR_Y + 0.55, 6.8, 1.0),       # the lip's chamfer: the piers' socket patch takes it and the top
         (FLOOR_Y + 0.55, 5.2, 0.6), (FLOOR_Y + 0.35, 5.05, 0.3), (FLOOR_Y, 5.0, 0.0)]   # the kerb down to the floor
RIM_TOP = 15                # TRUNK index of the lip's outer ring: bands 14 (chamfer) and 15 (top) take the pier sockets
TRUNK_FLUTE = 0.045         # cos(8a) fluting, ridge on every pier bearing
ROOT_LOBE = (0.45, 0.0, 1.4)   # buttress roots: (amplitude at the foot, the y they fade out at, the power)
PIER_BASE_SIDES = 4         # trunk sides per pier socket, centred on the bearing vertex

PIER_SIDES = 8              # a side faces the neighbour: the arch and rail sockets sit on it
PIER_SQUASH = 0.75          # the pier's radial thickness as a share of its width: a blade, wide toward its neighbours
PIER_PATH = [(6.1, FLOOR_Y + 0.55), (6.42, 28.5), (6.62, 29.2), (7.02, 30.5), (7.35, 31.4), (7.68, 32.2), (8.0, 33.0)]   # (r, y)
PIER_R = (0.9, 0.85, 0.8, 0.73, 0.67, 0.63, 0.6)
PIER_LAND_SIDES = 4         # belly grid sides per landing socket, centred on the bearing vertex
RAIL_SEG = 0                # the pier segment the rail crosses from (y 27.6..28.5)
RAIL_Y = FLOOR_Y + 0.95     # the twig rail: its top at 28.2 is the bottom of the guard's clear sightline
RAIL_R = 0.2
RAIL_SAG = 0.1
ARM_SEG = 2                 # the pier segment the arches spring from (y 29.2..30.5)
ARM_Y = 29.9                # the spring: the arm's underside at 29.5, the top of the clear band
ARM_R = (0.4, 0.36, 0.32)   # root to apex, mirrored down the other side
ARM_STUB = 0.35             # the arm leaves the pier square to its side this far, then bends up toward ARM_PULL
ARM_OUT = 0.0               # ... from the side facing the neighbour (a bias here would pull the patch onto the rail's or the far arch's sides)
APEX = (8.3, 32.5)          # (r, y) where the two halves meet, under the belly
ARM_PULL = (12.0, 7.5, 32.0)  # the arm's control point: degrees toward the apex, r, y

CANOPY_N = 56               # 7 per pier; the grid is a half step off so a vertex sits at every pier bearing
BELLY = [(9.0, 33.0), (7.2, 33.0), (5.5, 32.86), (3.8, 32.7), (2.4, 32.58)]   # (r, y) the ceiling: the piers land on band 0, the ribs root in band 1
BOSS_N = 24
BOSS = ((1.7, 32.55), (1.55, 31.75), (1.0, 31.4))   # (r, y) the keystone hanging at the centre; the ribs run into band 0
BOSS_Y = 31.25
RIB_R = 0.28
RIB_SIDES = 6
RIB_BAND = 1                # the belly band the rib's outer socket sits in
RIB_PATH = [(6.15, 32.5), (4.8, 32.28), (3.2, 32.22), (2.35, 32.18)]   # (r, y) between the sockets, under the belly

CANOPY = [(33.45, 0.93, 0.5), (34.1, 1.0, 1.0), (34.9, 0.97, 0.85), (35.6, 0.88, 0.7), (36.1, 0.76, 0.55),
          (36.5, 0.61, 0.45), (36.8, 0.45, 0.35), (37.0, 0.26, 0.2)]   # (y, of R, share of the lobes): the leaf disc over the belly rim
CANOPY_TOP_Y = 37.2
CANOPY_R = 11.0
CANOPY_LOBES = (8, 0.12, 8, 0.0)     # (harmonic, amp) x 2: a lobe over every pier (56 verts alias anything above ~10)
CANOPY_JITTER = (0.015, 0.1, 0.2)   # (r share, y below the crown, y in the crown) lumps

ROOF_N = 6
ROOF_SIDES = 7
ROOF_SEGS = 2               # short branches: two segments, the twig roots in the upper one
ROOF_BAND = 4               # the CANOPY band (rings 4..5, y 36.1..36.5, r 8.4..6.7) the branches root in
ROOF_P = ((0.3, 36.9), (0.8, 37.0))   # (r beyond the root, y) bezier pull and tip: short, the clump sits on the crown's shoulder
ROOF_R = (0.5, 0.48, 0.46, 0.45)   # a stub, thick to its end: its last ring is near the clump's first, no thin bridging
ROOF_CLUMP = (1.8, 0.45)    # the end clump: radius, its centre this far over the tip (clear of the disc, top ~39.1)
TWIG_T = 0.5                # where along the roof branch the side twig grows
TWIG_R = 0.09
TWIG_CLUMP = (1.0, 0.65)    # the twig's clump: radius, over the twig's end

# ---- the roof sheet: the crown carried out to the level's seam -------------
SHEET_N = 160               # verts per sheet ring: the rim's 56 zip up to it, the seam's 240 down from it
SHEET_WAVES = 6             # the billow: a sum of this many sines (forest_build's _field)
SHEET_WL = (11.0, 30.0)     # their wavelengths, m
SHEET_IN_LUMP = 0.30        # the inner rings billow less: they hang off the fixed rim
SHEET_ASPECT = 3.0          # the longest a sheet band may be as a multiple of its own quad
                            # width. forest_seam.SHEET is spaced for the contract's profile,
                            # not for this one: the dome climbs 15.9 m over its span and its
                            # inner bands would be 6:1 ribbons too coarse to carry an 11 m
                            # billow. Any band over this is split into equal steps on the
                            # same curve, so the spacing follows the contract, never fights it.
SHEET_FOLD = 0.45           # a ring billows at most this share of the clearance to its
                            # neighbours. The old roof fell 1.3 m over 36 m, so nothing could
                            # cross; a dome that climbs can, and a ring past the next one out
                            # reads as a hole in the leaves. Two rings at this share sum to
                            # 0.9 of the rise between them: the sheet cannot fold.
SEAM_BLEND = 9.0            # over the last this many metres of radius the sheet's own billow
                            # hands over to the seam's SEAM_WAVES, so the rings nearest the
                            # seam rise and fall WITH it rather than against it -- the lumps
                            # run through the join instead of stopping at it.
SHEET_THICK = 0.80          # the leaf mass's thickness at the rim, nothing at the seam (the
                            # unseen top skin). Measured along the sheet's normal: on a dome
                            # at 48 degrees a plain vertical offset would read as half of it.
SHEET_RIM_RISE = 0.25       # and it stands at least this far above the highest the rim can
                            # jitter to. The lobe fixes the band's PLAN; this fixes its
                            # SECTION: a first band that falls anywhere round the ring is the
                            # same coin toss as one that leans back, and loses the same way.
SHEET_LOBE_OUT = 16.0       # the crown's rim is eight-lobed and reaches r 12.5 over every
                            # pier, but the sheet's rings were circles: the first one sat at a
                            # flat r 12.0, so over every lobe the sheet's first band ran INWARD
                            # as it rose 1.1 m. A band that leans back like that is near
                            # vertical, its "down" side is a coin toss, and the toss came up
                            # facing the axis -- eight panels round the crown whose front was
                            # turned away from the lane, and backface culling shows the sky
                            # through every one of them. So the sheet's inner rings carry the
                            # rim's OWN lobe and fade it out by this radius: the first band is
                            # then the same width all the way round, it never leans back, and
                            # the crown's shape runs on into the roof instead of stopping at it.
SHEET_TOP = ((12.8, 40), (16.0, 40), (21.0, 48), (27.0, 48),
             (34.0, 56), (41.0, 60), (44.5, 80))   # (r, verts) the top skin's rings: coarse,
                            # but no band over SHEET_ASPECT and none of them near-vertical
                            # where the crown's lobed shoulder reaches out to r 11.8
                            # (0.96 m of radius between them at worst)
SHEET_CLUMPS = 16           # leaf masses hung from the sheet's own quads
SHEET_CLUMP_R = (1.0, 1.8)
SHEET_CLUMP_HANG = (0.30, 0.55)
STEM_SIDES = 6
STEM_R = 0.22               # and its neck, at the clump
STEM_IN = 0.45              # the foot is the sheet quad's outline drawn this far in

# ---- the canopy: the roof is many tree tops, the tower's crown one of them -----
# Ryan: "i want it to look like it blends into a roof created from all sorts of other tree tops."
CROWN_SEED = 5170313
CROWN_TRIES = 70            # tops tried, biggest first; one that will not fit is skipped
CROWN_R = (2.6, 8.0)        # a top's radius, m
CROWN_DEPTH = (0.26, 0.42)  # how far a top hangs under the dome, as a share of its radius
CROWN_DEEPEST = 3.0         # and never more than this, m: the drum's cells stay in view
CROWN_STRETCH = (0.75, 1.30)   # oval tops: long axis over short, sqrt of it each way
CROWN_LOBES = ((3, 6), (0.0, 0.15))   # (harmonic range, amplitude range) of a top's outline
CROWN_GAP = 0.80            # two tops' centres at least this share of their summed radii apart
CROWN_TOWER_R = 12.0        # the tower's crown counts as a top this wide: neighbours crowd it
CROWN_SPAN = (12.5, 45.5)   # where a top's centre may sit
CROWN_FADE_IN = (12.0, 15.0)   # tops fade in off the crown's rim ...
CROWN_FADE_OUT = (45.0, 47.6)  # ... and over the drum's head: they grow on over the wall, clear of its top cells
CROWN_LEAF = (2.5, 5.0)     # the leafy lumps on a top: their wavelengths, m
CROWN_LUMP = 0.12           # and their share of its depth
CROWN_EDGE = 0.12           # a face hung less than this share of its top's depth is a crease: shade
CROWN_SUN = 0.35            # the share of tops in the lighter leaf
SHEET_STEP = 1.5            # no sheet band longer than this, m: a small top still has vertices in it
CLUMP_CLEAR = 0.30          # a hung clump's top sits this far under the sheet
CLUMP_SQUASH = 0.60
LEAF_FLOOR = 30.45          # nothing the sheet carries hangs below this: the guard's sightline is clear at r > 11
ROOM_Z = 33.4               # the guard room proof: no vertex under this, inside ROOM_R, may move or appear
ROOM_R = 11.2

SEED = 3140271
EYE_H = 1.65

# ---- the forest atlas (shared with forest_build.py) -------------------------
USE_TEXTURE_FILES = True        # textures/forest_atlas_albedo.png replaces the painted sheet
TEX_DIR = "textures"
TEX_SIZE = 256
TEX_SEED = 7710233
TPM = 12.0                      # texels per metre on the atlas
ZONES = {                       # (u0, v0, u1, v1)
    "grass": (0.0, 0.0, 0.5, 0.25),
    "verge": (0.0, 0.25, 0.5, 0.375),
    "path": (0.0, 0.375, 0.5, 0.5),
    "leaf": (0.5, 0.5, 1.0, 1.0),
    "shade": (0.0, 0.5, 0.25, 0.75),
    "sun": (0.25, 0.5, 0.5, 0.75),
    "fern": (0.0, 0.75, 0.25, 1.0),
    "edge": (0.25, 0.75, 0.5, 1.0),
    "bark": (0.5, 0.0, 0.75, 0.25),
    "earth": (0.75, 0.0, 1.0, 0.25),
    "cell": (0.5, 0.25, 0.75, 0.5),
    "root": (0.75, 0.25, 1.0, 0.5),
}
UV_PAD = 1.5 / TEX_SIZE
ROUGHNESS = 0.95


# =============================================================================
# RNG, CANVAS, ATLAS
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

    def u(self, a, b):
        return a + (b - a) * self.f()

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


def _blotch(c, r, box, shades, count, minsz, maxsz):
    x0, y0, x1, y1 = box
    for _ in range(count):
        w = r.i(minsz, maxsz)
        h = max(minsz, min(maxsz, w + r.i(-1, 1)))
        x, y = r.i(x0, x1 - w - 1), r.i(y0, y1 - h - 1)
        c.rect(x, y, x + w, y + h, r.pick(shades))


def _leaves(c, r, box, base, shades, lit, count, sz):
    """Dense foliage: a dark ground, many small leaf blobs, a lit pixel on each."""
    _fill(c, r, box, base)
    x0, y0, x1, y1 = box
    for _ in range(count):
        w = r.i(sz[0], sz[1])
        h = max(2, w - r.i(0, 1))
        x, y = r.i(x0, x1 - w - 1), r.i(y0, y1 - h - 1)
        s = r.pick(shades)
        c.rect(x, y, x + w, y + h, s)
        c.put(x, y + h - 1, lit)
        if w > 3:
            c.put(x + 1, y + h - 1, lit)


# The palette, leaning Ocarina of Time (Kokiri Forest: gold-olive grass under a
# misty gold-green sky, grey-brown trunks, foliage that goes dark and blue-green
# in the shade) and away from Castle Crashers' flat saturated green. Sampled
# from the refs (BotW Korok forest: lit grass #99c03d, shaded #679030, ferns
# #63843f, canopy in shade #5a7c54; OoT Kokiri: grass #696910, mist #92934b,
# trunks #75745e, deep foliage #353b24) and then muted a step darker so the sun
# shafts and the lit leaf tops carry the light. Every hex is in
# docs/maps/forest.md. Every lane zone is painted as fine noise over these (a
# smooth field picks the green, a per-texel jitter breaks it up), never as
# blotches: the deck is unwrapped a quad at a time at a random offset, and any
# shape bigger than a texel or two reads as that quad's own patch.
LANE_GREENS = ((138, 148, 64), (122, 138, 60), (102, 128, 58))     # #8a9440 #7a8a3c #66803a
PATH_TONES = ((124, 116, 72), (110, 98, 68), (111, 126, 66))       # #7c7448 #6e6244 #6f7e42
VERGE_TONES = ((134, 144, 62), (120, 130, 60), (118, 112, 68))     # #86903e #78823c #767044
EDGE_GREENS = ((108, 124, 60), (92, 110, 56), (78, 96, 52))        # #6c7c3c #5c6e38 #4e6034
LEAF_BASE = ((58, 74, 44), (52, 68, 42), (64, 80, 48))             # #3a4a2c #344428 #405030
LEAF_BLOBS = ((92, 112, 64), (104, 122, 72), (80, 102, 56), (90, 110, 62))   # #5c7040 #687a48 #506638 #5a6e3e
LEAF_LIT = (138, 152, 86)                                          # #8a9856
SHADE_BASE = ((38, 50, 31), (34, 44, 28))                          # #26321f #222c1c
SHADE_BLOBS = ((56, 72, 44), (48, 64, 42), (60, 78, 48))           # #38482c #30402a #3c4e30
SHADE_LIT = (76, 94, 58)                                           # #4c5e3a
SUN_BASE = ((102, 120, 62), (96, 114, 58))                         # #66783e #60723a
SUN_BLOBS = ((134, 150, 80), (152, 166, 92), (122, 140, 74), (142, 158, 86))  # #869650 #98a65c #7a8c4a #8e9e56
SUN_LIT = (176, 184, 108)                                          # #b0b86c
FERN_BASE = ((74, 98, 54), (68, 92, 50), (80, 106, 58))            # #4a6236 #445c32 #506a3a
FERN_FROND = ((108, 136, 72), (124, 150, 82))                      # #6c8848 #7c9652
FERN_DARK = (52, 72, 42)                                           # #34482a
BARK_BASE = ((94, 84, 64), (88, 78, 60), (100, 90, 70))            # #5e5440 #584e3c #645a46
BARK_STREAKS = ((72, 64, 48), (112, 102, 80), (66, 58, 44))        # #484030 #706650 #423a2c
BARK_CRACK = (50, 44, 32)                                          # #322c20
BARK_MOSS = (84, 104, 60)                                          # #54683c
EARTH_BASE = ((74, 62, 46), (68, 56, 42), (80, 68, 50), (62, 52, 40))   # #4a3e2e #44382a #504432 #3e3428
EARTH_BLOTCH = ((60, 50, 38), (90, 78, 58), (56, 46, 36))          # #3c3226 #5a4e3a #382e24
EARTH_ROOT = (96, 82, 60)                                          # #60523c
EARTH_STONE = (104, 98, 86)                                        # #686256
EARTH_MOSS = (66, 90, 50)                                          # #425a32
ROOT_BASE = ((98, 80, 58), (92, 74, 54), (106, 88, 64))            # #62503a #5c4a36 #6a5840


def _value_field(r, w, h, cell):
    """Smooth value noise over a w x h texel box: a random lattice every
    ``cell`` texels, bilinear between, wrapping so the box tiles."""
    nx, ny = max(1, w // cell), max(1, h // cell)
    lat = [[r.f() for _ in range(nx)] for _ in range(ny)]
    out = [[0.0] * w for _ in range(h)]
    for y in range(h):
        fy = y * ny / float(h)
        j0 = int(fy) % ny
        j1 = (j0 + 1) % ny
        ty = fy - int(fy)
        ty = ty * ty * (3.0 - 2.0 * ty)
        for x in range(w):
            fx = x * nx / float(w)
            i0 = int(fx) % nx
            i1 = (i0 + 1) % nx
            tx = fx - int(fx)
            tx = tx * tx * (3.0 - 2.0 * tx)
            a = lat[j0][i0] + (lat[j0][i1] - lat[j0][i0]) * tx
            b = lat[j1][i0] + (lat[j1][i1] - lat[j1][i0]) * tx
            out[y][x] = a + (b - a) * ty
    return out


def _noise_fill(c, r, box, tones, cuts=(0.38, 0.66), jitter=0.22, dither=4):
    """Fine noise in two or three tones: a two-octave field plus a per-texel
    jitter picks the tone by ``cuts``; ``dither`` shifts every texel's value
    a little so no two neighbours are quite the same."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    f1 = _value_field(r, w, h, 10)
    f2 = _value_field(r, w, h, 4)
    for y in range(h):
        for x in range(w):
            v = 0.65 * f1[y][x] + 0.35 * f2[y][x] + r.u(-jitter, jitter)
            k = 0
            for cut in cuts:
                if v >= cut:
                    k += 1
            tone = tones[min(k, len(tones) - 1)]
            d = r.i(-dither, dither)
            c.put(x0 + x, y0 + y, tuple(max(0, min(255, ch + d)) for ch in tone))


def _blades(c, r, box, count, shades):
    """Single texels, a lighter or darker blade tip each."""
    x0, y0, x1, y1 = box
    for _ in range(count):
        c.put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), r.pick(shades))


def _paint_grass(c, r, box):
    _noise_fill(c, r, box, LANE_GREENS)
    _blades(c, r, box, 160, [(168, 172, 82), (160, 160, 70), (86, 102, 58)])


def _paint_verge(c, r, box):
    """Between the grass and the path: the greens with the path's worn tone
    creeping in, so the path has no hard shoulder."""
    _noise_fill(c, r, box, VERGE_TONES, cuts=(0.42, 0.74))
    _blades(c, r, box, 60, [(160, 164, 78), (112, 104, 60)])


def _paint_path(c, r, box):
    """The worn line down the middle of the lane: brown-green, bare earth showing."""
    _noise_fill(c, r, box, PATH_TONES, cuts=(0.40, 0.72))
    _blades(c, r, box, 70, [(118, 96, 58), (104, 88, 54), (132, 140, 70)])


def _paint_edge(c, r, box):
    """The lip, the wall foot, hummocks and cell floors: the lane's greens in shade."""
    _noise_fill(c, r, box, EDGE_GREENS)
    _blades(c, r, box, 60, [(130, 140, 68), (58, 44, 30)])


def _paint_leaf(c, r, box):
    _leaves(c, r, box, list(LEAF_BASE), list(LEAF_BLOBS), LEAF_LIT, 520, (3, 5))


def _paint_shade(c, r, box):
    _leaves(c, r, box, list(SHADE_BASE), list(SHADE_BLOBS), SHADE_LIT, 110, (3, 5))


def _paint_sun(c, r, box):
    _leaves(c, r, box, list(SUN_BASE), list(SUN_BLOBS), SUN_LIT, 110, (3, 5))


def _paint_fern(c, r, box):
    _fill(c, r, box, list(FERN_BASE))
    x0, y0, x1, y1 = box
    for _ in range(9):                       # fronds: a stem with side ticks
        x, y = r.i(x0 + 4, x1 - 5), r.i(y0 + 2, y1 - 2)
        n = r.i(8, 16)
        dx = r.pick([-1, 1])
        for k in range(n):
            xx, yy = x + (k * dx) // 2, y + k
            if not (x0 <= xx < x1 and y0 <= yy < y1):
                break
            c.put(xx, yy, FERN_FROND[0])
            if k % 2 == 0:
                c.put(xx - 1, yy, FERN_FROND[1])
                c.put(xx + 1, yy, FERN_FROND[1])
    for _ in range(30):
        c.put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), FERN_DARK)


def _paint_bark(c, r, box, base=BARK_BASE):
    _fill(c, r, box, list(base))
    x0, y0, x1, y1 = box
    for _ in range(26):                      # vertical streaks
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 8)
        c.rect(x, y, x + r.i(1, 2), min(y1, y + r.i(6, 18)), r.pick(list(BARK_STREAKS)))
    for _ in range(12):                      # cracks
        x, y = r.i(x0, x1 - 1), r.i(y0, y1 - 6)
        for k in range(r.i(4, 9)):
            c.put(x, y + k, BARK_CRACK)
            x += r.i(-1, 1)
    for _ in range(8):
        x, y = r.i(x0, x1 - 3), r.i(y0, y1 - 3)
        c.rect(x, y, x + 2, y + 2, BARK_MOSS)    # moss


def _paint_earth(c, r, box):
    _fill(c, r, box, list(EARTH_BASE))
    _blotch(c, r, box, list(EARTH_BLOTCH), 30, 3, 9)
    x0, y0, x1, y1 = box
    for _ in range(8):                       # root streaks
        x, y = r.i(x0 + 1, x1 - 2), y0
        for k in range(y1 - y0):
            c.put(x, y + k, EARTH_ROOT)
            if k % 3 == 0:
                x += r.i(-1, 1)
            x = max(x0, min(x1 - 1, x))
    for _ in range(14):                      # stones
        x, y = r.i(x0, x1 - 3), r.i(y0, y1 - 3)
        c.rect(x, y, x + 2, y + 2, EARTH_STONE)
    for _ in range(10):
        x, y = r.i(x0, x1 - 3), r.i(y0, y1 - 3)
        c.rect(x, y, x + 2, y + 2, EARTH_MOSS)    # moss


def _paint_cell(c, r, box):
    _fill(c, r, box, [(14, 16, 12), (18, 20, 14), (12, 14, 10), (20, 24, 16)])
    _blotch(c, r, box, [(24, 28, 18), (10, 12, 8)], 12, 3, 8)
    x0, y0, x1, y1 = box
    for _ in range(3):                       # something pale, far back
        x, y = r.i(x0 + 4, x1 - 6), r.i(y0 + 4, y1 - 6)
        c.rect(x, y, x + 2, y + 1, (52, 60, 44))


def _paint_root(c, r, box):
    _paint_bark(c, r, box, base=ROOT_BASE)


PAINTERS = {
    "grass": _paint_grass, "verge": _paint_verge, "path": _paint_path, "edge": _paint_edge, "leaf": _paint_leaf,
    "shade": _paint_shade, "sun": _paint_sun, "fern": _paint_fern,
    "bark": _paint_bark, "earth": _paint_earth, "cell": _paint_cell,
    "root": _paint_root,
}


def _images(c, size, names):
    out = []
    for name, buf in ((names[0], c.alb), (names[1], c.emi)):
        img = bpy.data.images.new(name, size, size, alpha=False)
        img.colorspace_settings.name = "sRGB"
        img.pixels.foreach_set(buf)
        img.update()
        out.append(img)
    return out[0], out[1]


def paint_atlas():
    """The forest atlas: every zone painted in place; returns (albedo, emissive)."""
    c = _Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    for zone, fn in sorted(PAINTERS.items()):
        fn(c, r, _rect_of(ZONES[zone], TEX_SIZE))
    return _images(c, TEX_SIZE, ("forest_atlas_albedo", "forest_atlas_emissive"))


def image_file(name):
    """A texture file beside the script, packed into the .glb; None if absent."""
    path = os.path.join(HERE, TEX_DIR, name)
    if not os.path.isfile(path):
        return None
    img = bpy.data.images.load(path)
    img.colorspace_settings.name = "sRGB"
    img.pack()
    print("MDL TEXTURE %s from %s" % (img.name, path))
    return img


def sheet(stem, painted):
    """(albedo, emissive): the files when opted in and present, else painted."""
    alb = image_file(stem + "_albedo.png") if USE_TEXTURE_FILES else None
    if alb is None:
        return painted()
    return alb, (image_file(stem + "_emissive.png") or alb)


def atlas_material(name, albedo, emissive, cull=True):
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
    bsdf.inputs["Roughness"].default_value = ROUGHNESS
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Emission Strength"].default_value = 1.0   # exactly 1.0: no KHR warning
    mat.use_backface_culling = cull
    mat.diffuse_color = (0.3, 0.45, 0.2, 1.0)
    return mat


# =============================================================================
# GEOMETRY -- the face accumulator; winding is checked, never assumed
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
    """Face accumulator: every face states the direction its normal must point.

    Quads are registered by their vertex set so an attachment can later claim
    one (``socket``): the quad's triangles are dropped and its boundary is
    bridged to the attachment's own ring, which is how every twig, fern and
    branch shares vertices with what it grows from. ``compact`` drops the
    claimed faces before export."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.zones = []
        self.quads = {}          # frozenset(vertex ids) -> [face indices]

    def v(self, p):
        self.verts.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.verts) - 1

    def _emit(self, idx, want, zone):
        pts = [self.verts[j] for j in idx]
        if callable(zone):
            zone = zone(pts)
        n = _newell(pts)
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        if len(idx) == 4:
            self.faces.append((idx[0], idx[1], idx[2]))
            self.faces.append((idx[0], idx[2], idx[3]))
            self.zones.append(zone)
            self.zones.append(zone)
            self.quads[frozenset(idx)] = [len(self.faces) - 2, len(self.faces) - 1]
        else:
            self.faces.append(tuple(idx))
            self.zones.append(zone)

    def quad(self, a, b, c, d, want, zone):
        self._emit([a, b, c, d], want, zone)

    def tri(self, a, b, c, want, zone):
        self._emit([a, b, c], want, zone)

    def fan(self, ring, want, zone):
        for i in range(1, len(ring) - 1):
            self.tri(ring[0], ring[i], ring[i + 1], want, zone)

    def centroid(self, idx):
        n = float(len(idx))
        return tuple(sum(self.verts[j][k] for j in idx) / n for k in range(3))

    def has_quad(self, ids):
        return frozenset(ids) in self.quads

    def quad_corners(self, ids):
        """The four corner ids of a registered quad, in face order."""
        fi = self.quads[frozenset(ids)]
        a, b, c = self.faces[fi[0]]
        d = [x for x in self.faces[fi[1]] if x not in (a, b, c)][0]
        return (a, b, c, d)

    def claim(self, quad_ids_list):
        """Drop the registered quads in ``quad_ids_list``; returns their directed
        boundary loop (vertex ids, in the faces' own winding) and mean normal."""
        edges = {}
        nsum = [0.0, 0.0, 0.0]
        for ids in quad_ids_list:
            key = frozenset(ids)
            for fi in self.quads.pop(key):
                f = self.faces[fi]
                if f is None:
                    raise ValueError("quad already claimed")
                n = _newell([self.verts[j] for j in f])
                nsum = [nsum[k] + n[k] for k in range(3)]
                for k in range(3):
                    e = (f[k], f[(k + 1) % 3])
                    edges[e] = edges.get(e, 0) + 1
                self.faces[fi] = None
                self.zones[fi] = None
        loop_edges = {}
        for (a, b), cnt in edges.items():
            if cnt == 1 and edges.get((b, a), 0) == 0:
                loop_edges[a] = b
        start = next(iter(loop_edges))
        loop = [start]
        cur = loop_edges[start]
        while cur != start:
            loop.append(cur)
            cur = loop_edges[cur]
            if len(loop) > len(loop_edges):
                raise ValueError("socket patch boundary is not one loop")
        return loop, norm(nsum)

    def socket(self, quad_ids_list, ring_ids, zone):
        """Claim a patch of quads and bridge its boundary to ``ring_ids`` (a ring
        of vertices lying on the patch, inside it). The ring becomes part of
        the surface: whatever is built on it shares these vertices."""
        loop, n = self.claim(quad_ids_list)
        c = self.centroid(ring_ids)
        ex = norm(cross(n, (0.0, 0.0, 1.0) if abs(n[2]) < 0.9 else (1.0, 0.0, 0.0)))
        ey = cross(n, ex)

        def ang(vid):
            d = sub(self.verts[vid], c)
            return math.atan2(dot(d, ey), dot(d, ex))

        L = sorted(loop, key=ang)
        R = sorted(ring_ids, key=ang)
        aL = [ang(v) for v in L]
        aR = [ang(v) for v in R]
        i = j = 0
        nl, nr = len(L), len(R)
        want = n
        while i < nl or j < nr:
            next_l = aL[i + 1] if i + 1 < nl else aL[0] + 2.0 * math.pi
            next_r = aR[j + 1] if j + 1 < nr else aR[0] + 2.0 * math.pi
            li, ri = L[i % nl], R[j % nr]
            if (i < nl and next_l <= next_r) or j >= nr:
                self.tri(li, L[(i + 1) % nl], ri, want, zone)
                i += 1
            else:
                self.tri(li, R[(j + 1) % nr], ri, want, zone)
                j += 1
        return loop

    def compact(self):
        keep = [k for k, f in enumerate(self.faces) if f is not None]
        self.faces = [self.faces[k] for k in keep]
        self.zones = [self.zones[k] for k in keep]
        self.quads = {}
        return self

    def object(self, name, shift=(0.0, 0.0, 0.0)):
        self.compact()
        verts = [(x + shift[0], y + shift[1], z + shift[2]) for (x, y, z) in self.verts]
        return mdl.mesh(name, verts, self.faces)


UP = (0.0, 0.0, 1.0)
DOWN = (0.0, 0.0, -1.0)


def pol(bearing_deg, radius, z):
    """Game bearing (as the scene's markers) -> Blender xyz."""
    a = math.radians(-bearing_deg)
    return (radius * math.cos(a), radius * math.sin(a), z)


def radial(bearing_deg):
    a = math.radians(-bearing_deg)
    return (math.cos(a), math.sin(a), 0.0)


def tangent(bearing_deg):
    a = math.radians(-bearing_deg)
    return (-math.sin(a), math.cos(a), 0.0)


def add(p, q, s=1.0):
    return (p[0] + q[0] * s, p[1] + q[1] * s, p[2] + q[2] * s)


def sub(p, q):
    return (p[0] - q[0], p[1] - q[1], p[2] - q[2])


def dot(p, q):
    return p[0] * q[0] + p[1] * q[1] + p[2] * q[2]


def cross(p, q):
    return (p[1] * q[2] - p[2] * q[1], p[2] * q[0] - p[0] * q[2], p[0] * q[1] - p[1] * q[0])


def norm(p):
    l = math.sqrt(dot(p, p))
    return (p[0] / l, p[1] / l, p[2] / l) if l > 1e-12 else (0.0, 0.0, 1.0)


def lerp(p, q, t):
    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t)


def bez(p0, p1, p2, n):
    """Quadratic bezier, n+1 points."""
    out = []
    for k in range(n + 1):
        t = k / float(n)
        a = lerp(p0, p1, t)
        b = lerp(p1, p2, t)
        out.append(lerp(a, b, t))
    return out


def _at(vals, t):
    """Piecewise-linear lookup of a radius table along t in 0..1."""
    if len(vals) == 1:
        return vals[0]
    x = t * (len(vals) - 1)
    k = min(len(vals) - 2, max(0, int(math.floor(x))))
    return vals[k] + (vals[k + 1] - vals[k]) * (x - k)


def _field(r, n=None, wl=None):
    """A smooth 2-D field of unit bound: a sum of sines at random headings.
    forest_build._field, so the tower's billow speaks the map roof's language."""
    two_pi = 2.0 * math.pi
    waves = []
    for _ in range(n or SHEET_WAVES):
        a = r.f() * two_pi
        L = r.u(*(wl or SHEET_WL))
        waves.append((math.cos(a) * two_pi / L, math.sin(a) * two_pi / L, r.f() * two_pi))

    def f(x, y):
        return sum(math.sin(kx * x + ky * y + ph) for (kx, ky, ph) in waves) / len(waves)

    return f


def _pw(table, x):
    """Piecewise-linear lookup over a table of (x, value)."""
    if x <= table[0][0]:
        return table[0][1]
    for k in range(len(table) - 1):
        (x0, v0), (x1, v1) = table[k], table[k + 1]
        if x0 <= x <= x1:
            return v0 + (v1 - v0) * (x - x0) / (x1 - x0)
    return table[-1][1]


def frames(path):
    """Parallel-transported (tangent, ex, ez) per path point: rings never twist."""
    n = len(path)
    tangents = []
    for i in range(n):
        a = path[max(0, i - 1)]
        b = path[min(n - 1, i + 1)]
        tangents.append(norm(sub(b, a)))
    t0 = tangents[0]
    up = (0.0, 0.0, 1.0) if abs(t0[2]) < 0.9 else (1.0, 0.0, 0.0)
    ex = norm(cross(up, t0))
    out = []
    for i in range(n):
        t = tangents[i]
        ex = norm(sub(ex, (t[0] * dot(ex, t), t[1] * dot(ex, t), t[2] * dot(ex, t))))
        out.append((t, ex, cross(t, ex)))
    return out


def ring_pts(centre, ex, ez, radius, sides, flat=1.0, wob=0.0, rng=None):
    pts = []
    for s in range(sides):
        a = 2.0 * math.pi * s / sides
        rr = radius * (1.0 + wob * rng.sf()) if (wob and rng) else radius
        pts.append(add(add(centre, ex, rr * math.cos(a)), ez, rr * math.sin(a) * flat))
    return pts


def plane_of(m, quad_ids):
    """(point, unit normal) of a registered quad's best plane."""
    pts = [m.verts[i] for i in quad_ids]
    c = m.centroid(quad_ids)
    return c, norm(_newell(pts))


def project_ring(pts, along, plane):
    """Slide ring points along ``along`` onto the plane (a socket ring must lie
    on the host); falls back to the normal when the tube is tangential."""
    c, n = plane
    out = []
    d = dot(along, n)
    for p in pts:
        if abs(d) > 0.2:
            s = dot(sub(c, p), n) / d
            out.append(add(p, along, s))
        else:
            s = dot(sub(c, p), n)
            out.append(add(p, n, s))
    return out


def tube(m, path, radii, sides, zone, caps=(True, True), wob=0.0, rng=None, flat=1.0,
         first_ring=None, last_ring=None):
    """A tapered n-gon tube along a polyline. ``radii`` is a table read along
    the path. ``first_ring`` / ``last_ring`` are existing vertex ids (a socket
    ring) used in place of the tube's own end ring, so the tube grows out of,
    or into, the surface that owns them. Returns the rings."""
    n = len(path)
    fr = frames(path)
    rings = []
    for i in range(n):
        if i == 0 and first_ring is not None:
            rings.append(list(first_ring))
            continue
        if i == n - 1 and last_ring is not None:
            rings.append(list(last_ring))
            continue
        t, ex, ez = fr[i]
        r = _at(radii, i / float(max(1, n - 1)))
        rings.append([m.v(p) for p in ring_pts(path[i], ex, ez, r, sides, flat, wob, rng)])
    for i in range(n - 1):
        axis = lerp(path[i], path[i + 1], 0.5)
        for s in range(sides):
            q = (s + 1) % sides
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            want = sub(m.centroid(idx), axis)
            m.quad(idx[0], idx[1], idx[2], idx[3], want, zone)
    if caps[0] and first_ring is None:
        m.fan(rings[0], (-fr[0][0][0], -fr[0][0][1], -fr[0][0][2]), zone)
    if caps[1] and last_ring is None:
        m.fan(rings[-1], fr[-1][0], zone)
    return rings


def end_ring(m, path, radius, sides, flat=1.0, at_start=False):
    """Ring points for a tube end, in the tube's own frame at that end."""
    fr = frames(path)
    t, ex, ez = fr[0] if at_start else fr[-1]
    return ring_pts(path[0] if at_start else path[-1], ex, ez, radius, sides, flat), t


def socket_ring(m, quads, path, radius, sides, zone, flat=1.0, at_start=True):
    """Claim ``quads`` (registered quad id tuples, a connected patch) and weld a
    ring for a tube end there; returns the ring ids for tube(first_ring=..)
    or tube(last_ring=..). The tube end must sit on the patch."""
    pts, t = end_ring(m, path, radius, sides, flat, at_start)
    plane = plane_of(m, quads[0]) if len(quads) == 1 else (m.centroid([i for q in quads for i in q]), norm(_newell([m.verts[i] for i in quads[0]])))
    pts = project_ring(pts, t, plane)
    ids = [m.v(p) for p in pts]
    m.socket(quads, ids, zone)
    return ids


def clump_end(m, last_ring, centre, radius, zone, rng, squash=0.75, wob=0.25):
    """A leaf clump grown off a tube's last ring: rings up round a ball, top fan."""
    segs = len(last_ring)
    rings = [list(last_ring)]
    for lat in (-35.0, 5.0, 40.0, 68.0):
        ring = []
        cl, sl = math.cos(math.radians(lat)), math.sin(math.radians(lat))
        for s in range(segs):
            a = 2.0 * math.pi * s / segs + rng.f() * 0.25
            rr = radius * (1.0 + wob * rng.sf())
            ring.append(m.v((centre[0] + rr * cl * math.cos(a), centre[1] + rr * cl * math.sin(a),
                             centre[2] + rr * sl * squash)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(segs):
            q = (s + 1) % segs
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), centre), zone)
    top = m.v((centre[0], centre[1], centre[2] + radius * squash * (1.0 + wob * rng.sf())))
    for s in range(segs):
        q = (s + 1) % segs
        m.tri(top, rings[-1][s], rings[-1][q], sub(m.centroid((top, rings[-1][s], rings[-1][q])), centre), zone)
    return rings


def blob(m, centre, radius, zone, rng, segs=7, squash=0.75, wob=0.28):
    """A leaf clump: a lumpy low-poly ball, squashed a little."""
    lats = (-58.0, -20.0, 22.0, 58.0)
    rings = []
    for lat in lats:
        ring = []
        cl, sl = math.cos(math.radians(lat)), math.sin(math.radians(lat))
        for s in range(segs):
            a = 2.0 * math.pi * s / segs + rng.f() * 0.3
            rr = radius * (1.0 + wob * rng.sf())
            ring.append(m.v((centre[0] + rr * cl * math.cos(a),
                             centre[1] + rr * cl * math.sin(a),
                             centre[2] + rr * sl * squash)))
        rings.append(ring)
    bot = m.v((centre[0], centre[1], centre[2] - radius * squash * (1.0 + wob * rng.sf())))
    top = m.v((centre[0], centre[1], centre[2] + radius * squash * (1.0 + wob * rng.sf())))
    for i in range(len(rings) - 1):
        for s in range(segs):
            q = (s + 1) % segs
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), centre), zone)
    for s in range(segs):
        q = (s + 1) % segs
        m.tri(bot, rings[0][s], rings[0][q], sub(m.centroid((bot, rings[0][s], rings[0][q])), centre), zone)
        m.tri(top, rings[-1][s], rings[-1][q], sub(m.centroid((top, rings[-1][s], rings[-1][q])), centre), zone)


def zipper(m, outer, inner, want, zone, centre=None):
    """Triangles between two closed loops of any two counts, matched by angle
    round ``centre`` (default the inner loop's centroid) in the xy plane."""
    c = centre or m.centroid(inner)

    def ang(vid):
        p = m.verts[vid]
        return math.atan2(p[1] - c[1], p[0] - c[0])

    O = sorted(outer, key=ang)
    I = sorted(inner, key=ang)
    aO, aI = [ang(v) for v in O], [ang(v) for v in I]
    i = j = 0
    no, ni = len(O), len(I)
    while i < no or j < ni:
        next_o = aO[i + 1] if i + 1 < no else aO[0] + 2.0 * math.pi
        next_i = aI[j + 1] if j + 1 < ni else aI[0] + 2.0 * math.pi
        oi, ii = O[i % no], I[j % ni]
        if (i < no and next_o <= next_i) or j >= ni:
            m.tri(oi, O[(i + 1) % no], ii, want, zone)
            i += 1
        else:
            m.tri(oi, I[(j + 1) % ni], ii, want, zone)
            j += 1


def loft(m, rings, zone, want_fn=None):
    """Quads between successive rings of equal length; want = away from the axis."""
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        n = len(a)
        for s in range(n):
            q = (s + 1) % n
            idx = (a[s], a[q], b[q], b[s])
            c = m.centroid(idx)
            want = want_fn(c) if want_fn else (c[0], c[1], 0.0)
            m.quad(idx[0], idx[1], idx[2], idx[3], want, zone)


# =============================================================================
# THE TREE -- one surface: every part grows out of a socket in what carries it
# =============================================================================

_WELDS = []     # (tag, margin): how far inside its patch every socket ring sits
_PROOF = {}     # what --check reports about the roof sheet: the seam, the new geometry


def _pier_bearing(k):
    return k * 360.0 / PIERS + 22.5


def _pier_theta0():
    """Pier 0's bearing as a Blender xy angle: the phase of every 8-fold term."""
    return math.radians(-_pier_bearing(0))


def _canopy_theta(s, n=None):
    """The canopy family's angular grid, a half step off the pier grid: with
    CANOPY_N = 7 * PIERS a vertex sits exactly at every pier bearing."""
    return 2.0 * math.pi * (s + 0.5) / float(n or CANOPY_N)


def _canopy_R(theta, share=1.0):
    """The lobed rim radius: a lobe over every pier, a scallop between."""
    h1, a1, h2, a2 = CANOPY_LOBES
    t = theta - _pier_theta0()
    return CANOPY_R * (1.0 + share * (a1 * math.cos(h1 * t) + a2 * math.cos(h2 * t)))


def _cap(m, ring, centre, want, zone):
    """A fan from a new centre vertex: every triangle opens 360/n degrees."""
    c = m.v(centre)
    n = len(ring)
    for s in range(n):
        m.tri(c, ring[s], ring[(s + 1) % n], want, zone)
    return c


def _circle(m, rad, y, n, rng=None, jr=0.0, jy=0.0):
    ring = []
    for s in range(n):
        th = _canopy_theta(s, n)
        rr = rad * (1.0 + jr * rng.sf()) if (jr and rng) else rad
        yy = y + jy * rng.sf() if (jy and rng) else y
        ring.append(m.v((rr * math.cos(th), rr * math.sin(th), yy)))
    return ring


def _band_quad(a, b, s):
    """The registered quad between rings a and b at side s, in cyclic order."""
    q = (s + 1) % len(a)
    return (a[s], a[q], b[q], b[s])


def _patch(m, a, b, sides):
    """Adjacent quads of the band a..b at ``sides``, the one whose plane best
    stands for the patch first (socket_ring projects the ring onto it)."""
    quads = [_band_quad(a, b, s) for s in sides]
    if len(quads) == 1:
        return quads
    normals = [norm(_newell([m.verts[i] for i in q])) for q in quads]
    mean = norm([sum(n[k] for n in normals) for k in range(3)])
    order = sorted(range(len(quads)), key=lambda i: -dot(normals[i], mean))
    return [quads[i] for i in order]


def _patch_mid(m, a, b, sides):
    """A patch of an odd number of sides with the middle one first: the ring
    is projected onto the plane of the side it is centred on, not onto a
    folded neighbour's (which is what _patch's normal-vote can pick on a
    fat, curving tube)."""
    quads = [_band_quad(a, b, s) for s in sides]
    mid = len(sides) // 2
    return [quads[mid]] + quads[:mid] + quads[mid + 1:]


def _patch_centre(m, quads):
    return m.centroid(sorted(set(i for q in quads for i in q)))


def _facing(m, rings, seg, direction, count):
    """The ``count`` adjacent sides of tube segment ``seg`` whose quads best
    face ``direction``: an odd count is centred on a side, an even one on a
    vertex."""
    a, b = rings[seg], rings[seg + 1]
    n = len(a)
    axis = lerp(m.centroid(a), m.centroid(b), 0.5)
    if count % 2:
        best = max(range(n), key=lambda s: dot(norm(sub(m.centroid(_band_quad(a, b, s)), axis)), direction))
        return [(best + d) % n for d in range(-(count // 2), count // 2 + 1)]
    best = max(range(n), key=lambda s: dot(norm(sub(lerp(m.verts[a[s]], m.verts[b[s]], 0.5), axis)), direction))
    return [(best + d) % n for d in range(-(count // 2), count // 2)]


def _seg_axis(m, rings, seg):
    return lerp(m.centroid(rings[seg]), m.centroid(rings[seg + 1]), 0.5)


def _grid_sides(v, n, count):
    """``count`` adjacent sides of an n-ring centred on vertex v (even count)
    or on side v (odd count)."""
    if count % 2:
        return [(v + d) % n for d in range(-(count // 2), count // 2 + 1)]
    return [(v + d) % n for d in range(-(count // 2), count // 2)]


def _loop_of(m, quads):
    """The directed boundary loop of a patch (what claim() will return)."""
    edges = {}
    for q in quads:
        c = m.quad_corners(q)
        for k in range(4):
            e = (c[k], c[(k + 1) % 4])
            edges[e] = edges.get(e, 0) + 1
    nxt = dict((a, b) for (a, b), cnt in edges.items() if cnt == 1 and (b, a) not in edges)
    start = next(iter(nxt))
    loop, cur = [start], nxt[start]
    while cur != start:
        loop.append(cur)
        cur = nxt[cur]
    return loop


def _margin(poly, p):
    """Signed distance of 2D point p to polygon poly: positive inside."""
    inside = False
    best = 1e9
    n = len(poly)
    for i in range(n):
        (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % n]
        if (y0 > p[1]) != (y1 > p[1]):
            xi = x0 + (p[1] - y0) * (x1 - x0) / (y1 - y0)
            if p[0] < xi:
                inside = not inside
        dx, dy = x1 - x0, y1 - y0
        l2 = dx * dx + dy * dy
        t = max(0.0, min(1.0, ((p[0] - x0) * dx + (p[1] - y0) * dy) / l2)) if l2 > 1e-12 else 0.0
        best = min(best, math.hypot(p[0] - (x0 + t * dx), p[1] - (y0 + t * dy)))
    return best if inside else -best


def _weld_pts(m, quads, pts, along, zone, tag):
    """Weld an explicit ring (points on or near the patch, slid along ``along``
    onto its plane) into a patch of quads, plus the proof that it landed inside
    the patch: the margin (in the patch plane) is kept for the --check report."""
    loop = _loop_of(m, quads)
    if len(quads) == 1:
        plane = plane_of(m, quads[0])
    else:
        plane = (m.centroid([i for q in quads for i in q]), norm(_newell([m.verts[i] for i in quads[0]])))
    pts = project_ring(pts, along, plane)
    ids = [m.v(p) for p in pts]
    m.socket(quads, ids, zone)
    n = plane[1]
    c = m.centroid(ids)
    ex = norm(cross(n, UP if abs(n[2]) < 0.9 else (1.0, 0.0, 0.0)))
    ey = cross(n, ex)
    flat = lambda v: (dot(sub(m.verts[v], c), ex), dot(sub(m.verts[v], c), ey))
    poly = [flat(v) for v in loop]
    _WELDS.append((tag, min(_margin(poly, flat(v)) for v in ids)))
    return ids


def _weld(m, quads, path, radius, sides, zone, at_start, tag):
    """A tube end's ring welded into a patch (see _weld_pts): the ring ids for
    tube(first_ring=..) or tube(last_ring=..)."""
    pts, t = end_ring(m, path, radius, sides, 1.0, at_start)
    return _weld_pts(m, quads, pts, t, zone, tag)


def _by_azimuth(m, ring, centre):
    """The ring's ids in rising xy azimuth round ``centre``: clump_end lays its
    rings out by azimuth, so a tube's end ring hands over in the same order."""
    return sorted(ring, key=lambda v: math.atan2(m.verts[v][1] - centre[1], m.verts[v][0] - centre[0]) % (2.0 * math.pi))


# ---- trunk, rim, floor ------------------------------------------------------

def _trunk(m, r):
    """One loft, foot to floor edge: the fluted trunk (a ridge on every pier
    bearing), the buttress roots growing toward the foot on the same eight
    bearings, the goblet flare, the lip, the rim top the piers stand on, the
    kerb down to the flat floor. Returns the rings, TRUNK's order."""
    th0 = _pier_theta0()
    amp0, fade_y, powr = ROOT_LOBE
    rings = []
    for (y, rad, share) in TRUNK:
        amp = amp0 * max(0.0, (fade_y - y) / (fade_y - FOOT_Y)) ** powr
        ring = []
        for s in range(TRUNK_SIDES):
            a = 2.0 * math.pi * s / TRUNK_SIDES
            c8 = math.cos(PIERS * (a - th0))
            lobe = ((1.0 + c8) / 2.0) ** 2        # 0..1, mean 3/8
            rr = rad * (1.0 + share * TRUNK_FLUTE * c8) * (1.0 + amp * (lobe - 0.375)) * (1.0 + 0.012 * share * r.sf())
            ring.append(m.v((rr * math.cos(a), rr * math.sin(a), y)))
        rings.append(ring)
    split = max(i for i, (y, _, _) in enumerate(TRUNK) if y < 0.0)
    loft(m, rings[:split + 1], "root")
    loft(m, rings[split:RIM_TOP], "bark")                                    # the trunk and the lip's outer face
    loft(m, rings[RIM_TOP - 1:RIM_TOP + 2], "bark", want_fn=lambda c: UP)   # the lip's bevel and the rim top
    loft(m, rings[RIM_TOP + 1:], "bark", want_fn=lambda c: (-c[0], -c[1], 4.0))   # the kerb: inward and up
    _cap(m, rings[0], (0.0, 0.0, FOOT_Y), DOWN, "root")
    prev = rings[-1]
    for (rad, nf) in FLOOR_RINGS:
        ring = _circle(m, rad, FLOOR_Y, nf)
        zipper(m, prev, ring, UP, "bark")
        prev = ring
    _cap(m, prev, (0.0, 0.0, FLOOR_Y), UP, "bark")
    return rings


# ---- ceiling and canopy -----------------------------------------------------

def _canopy(m, r):
    """The belly (the room's ceiling: round rings sagging to the centre, a
    keystone boss hanging there), then the leaf disc from the belly rim out
    and up over the lobed rim to the crown. Returns (belly, boss, disc rings)."""
    n = CANOPY_N
    belly = [_circle(m, rad, y, n) for (rad, y) in BELLY]
    loft(m, belly, "shade", want_fn=lambda c: DOWN)
    boss = [_circle(m, rad, y, BOSS_N) for (rad, y) in BOSS]
    zipper(m, belly[-1], boss[0], DOWN, "shade")
    loft(m, boss, "bark", want_fn=lambda c: (c[0], c[1], -1.2))
    _cap(m, boss[-1], (0.0, 0.0, BOSS_Y), DOWN, "bark")
    jr, jy, jc = CANOPY_JITTER
    disc = [belly[0]]
    for i, (y, frac, share) in enumerate(CANOPY):
        ring = []
        for s in range(n):
            th = _canopy_theta(s)
            sock = ROOF_BAND <= i <= ROOF_BAND + 1        # the branches' socket band: regular, so the rings land inside
            rr = _canopy_R(th, share) * frac * (1.0 + (0.0 if sock else jr) * r.sf())
            ring.append(m.v((rr * math.cos(th), rr * math.sin(th), y + (0.04 if sock else jc if i > ROOF_BAND + 1 else jy) * r.sf())))
        disc.append(ring)
    out_up = lambda c: (c[0], c[1], 0.4 * math.hypot(c[0], c[1]))
    loft(m, disc[:3], "shade", want_fn=lambda c: (c[0], c[1], -0.3 * math.hypot(c[0], c[1])))   # the skirt under the rim
    loft(m, disc[3:6], "leaf", want_fn=out_up)   # band (2,3) is the sheet's top skin: see _sheet
    loft(m, disc[5:], "sun", want_fn=out_up)   # the crown, lit
    _cap(m, disc[-1], (0.0, 0.0, CANOPY_TOP_Y), UP, "sun")
    return belly, boss, disc


# ---- the piers: out of the rim, up into the belly ---------------------------

def _pier_ring(b, path, i, radius):
    """Pier ring points at path point i in the pier's own frame: ex toward the
    neighbours (a side centred on it, where the arches and rails socket), ez
    radial and squashed (a blade). The path lies in one vertical plane, so
    the frame never twists. Returns (points, tangent)."""
    n = len(path)
    t = norm(sub(path[min(n - 1, i + 1)], path[max(0, i - 1)]))
    rad = radial(b)
    ez = norm(sub(rad, (t[0] * dot(rad, t), t[1] * dot(rad, t), t[2] * dot(rad, t))))
    ex = cross(t, ez)
    pts = []
    for s in range(PIER_SIDES):
        a = 2.0 * math.pi * (s + 0.5) / PIER_SIDES
        pts.append(add(add(path[i], ex, radius * math.cos(a)), ez, radius * PIER_SQUASH * math.sin(a)))
    return pts, t


def _pier(m, r, k, trunk, belly):
    """Pier k: its base ring a socket in the rim top (PIER_BASE_SIDES sides of
    the lip's top and bevel bands, centred on the bearing vertex, so the pier
    is the trunk's ridge carrying on), its top ring a socket in the belly's
    outer band (centred on the bearing vertex there too)."""
    b = _pier_bearing(k)
    path = [pol(b, rad, y) for (rad, y) in PIER_PATH]
    v = int(round(-b / 360.0 * TRUNK_SIDES)) % TRUNK_SIDES
    sides = _grid_sides(v, TRUNK_SIDES, PIER_BASE_SIDES)
    base = _patch(m, trunk[RIM_TOP], trunk[RIM_TOP + 1], sides) + _patch(m, trunk[RIM_TOP - 1], trunk[RIM_TOP], sides)
    base = sorted(base, key=lambda q: -dot(norm(_newell([m.verts[i] for i in q])), UP))
    vc = int(round(-b / 360.0 * CANOPY_N - 0.5)) % CANOPY_N
    land = _patch(m, belly[0], belly[1], _grid_sides(vc, CANOPY_N, PIER_LAND_SIDES))
    path[0] = _patch_centre(m, base)
    path[-1] = _patch_centre(m, land)
    pts, t = _pier_ring(b, path, 0, PIER_R[0])
    first = _weld_pts(m, base, pts, t, "bark", "pier base")
    pts, t = _pier_ring(b, path, len(path) - 1, PIER_R[-1])
    last = _weld_pts(m, land, pts, t, "shade", "pier top")
    rings = [first]
    for i in range(1, len(path) - 1):
        pts, _ = _pier_ring(b, path, i, _at(PIER_R, i / float(len(path) - 1)) * (1.0 + 0.03 * r.sf()))
        rings.append([m.v(p) for p in pts])
    rings.append(last)
    for i in range(len(path) - 1):
        axis = lerp(path[i], path[i + 1], 0.5)
        for s in range(PIER_SIDES):
            q = (s + 1) % PIER_SIDES
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), axis), "bark")
    return rings


def _apex(k):
    """Where the arch between piers k and k+1 peaks."""
    return pol(_pier_bearing(k) + 180.0 / PIERS, APEX[0], APEX[1])


def _arch(m, r, k, piers):
    """One pointed arch: from a socket (3 sides of the pier's 8, centred on the
    side facing the neighbour) in pier k at ARM_Y, up through the apex (a
    bezier corner) and down into the matching socket in pier k+1."""
    apex = _apex(k)
    radii = ARM_R + tuple(reversed(ARM_R[:-1]))
    halves = []
    for (kk, sgn) in ((k, 1.0), ((k + 1) % PIERS, -1.0)):
        rings = piers[kk]
        b = _pier_bearing(kk)
        axis = _seg_axis(m, rings, ARM_SEG)
        side = norm(sub((apex[0], apex[1], axis[2]), axis))
        rad = radial(b)
        face = norm(add(sub(side, (rad[0] * dot(side, rad), rad[1] * dot(side, rad), 0.0)), rad, ARM_OUT))
        patch = _patch_mid(m, rings[ARM_SEG], rings[ARM_SEG + 1], _facing(m, rings, ARM_SEG, face, 3))
        root = _patch_centre(m, patch)
        root = (root[0], root[1], ARM_Y)
        out = norm(_newell([m.verts[i] for i in patch[0]]))    # the plane the ring is projected onto: leave square to it
        if dot(out, sub(root, axis)) < 0.0:
            out = (-out[0], -out[1], -out[2])
        q = add(root, out, ARM_STUB)      # square out of the pier (the socket ring stays round), then the bend up
        pull = pol(b + sgn * ARM_PULL[0], ARM_PULL[1], ARM_PULL[2])
        halves.append((patch, [root, q] + bez(q, pull, apex, 5)[1:]))
    (pa, ha), (pb, hb) = halves
    path = ha + list(reversed(hb))[1:]
    first = _weld(m, pa, path, ARM_R[0], 6, "bark", True, "arm root")
    last = _weld(m, pb, path, ARM_R[0], 6, "bark", False, "arm root")
    tube(m, path, radii, 6, "bark", caps=(False, False), wob=0.05, rng=r, first_ring=first, last_ring=last)


def _rail(m, r, k, piers):
    """The twig rail across the opening on pier k's clockwise side, at RAIL_Y:
    both ends are sockets in the piers' facing sides (3 of the pier's 8)."""
    ra, rc = piers[k], piers[(k + 1) % PIERS]
    seg = RAIL_SEG
    aa, cc = _seg_axis(m, ra, seg), _seg_axis(m, rc, seg)
    ta, tc = tangent(_pier_bearing(k)), tangent(_pier_bearing((k + 1) % PIERS))
    d = (cc[0] - aa[0], cc[1] - aa[1], 0.0)
    da = ta if dot(ta, d) > 0.0 else (-ta[0], -ta[1], 0.0)      # square to each pier: the side facing its neighbour
    dc = tc if dot(tc, d) < 0.0 else (-tc[0], -tc[1], 0.0)
    pa = _patch_mid(m, ra[seg], ra[seg + 1], _facing(m, ra, seg, da, 3))
    pc = _patch_mid(m, rc[seg], rc[seg + 1], _facing(m, rc, seg, dc, 3))
    a, c = _patch_centre(m, pa), _patch_centre(m, pc)
    a, c = (a[0], a[1], RAIL_Y), (c[0], c[1], RAIL_Y)
    mid = lerp(a, c, 0.5)
    path = bez(a, (mid[0], mid[1], mid[2] - RAIL_SAG), c, 3)
    first = _weld(m, pa, path, RAIL_R, 4, "bark", True, "rail")
    last = _weld(m, pc, path, RAIL_R, 4, "bark", False, "rail")
    tube(m, path, (RAIL_R, RAIL_R * 0.9), 4, "bark", caps=(False, False), wob=0.0, rng=r,
         first_ring=first, last_ring=last)


def _rib(m, r, k, belly, boss):
    """Vault rib k: out of a socket in the belly band inboard of pier k's
    landing, swinging down under the ceiling and into the keystone boss's
    side (2 sides of its 24, centred on the bearing vertex)."""
    b = _pier_bearing(k)
    n = CANOPY_N
    vc = int(round(-b / 360.0 * n - 0.5)) % n
    outer = _patch(m, belly[RIB_BAND], belly[RIB_BAND + 1], _grid_sides(vc, n, 4))
    vb = int(round(-b / 360.0 * BOSS_N - 0.5)) % BOSS_N
    inner = _patch(m, boss[0], boss[1], _grid_sides(vb, BOSS_N, 2))
    a, c = _patch_centre(m, outer), _patch_centre(m, inner)
    path = [a] + [pol(b, rad, y) for (rad, y) in RIB_PATH] + [c]
    first = _weld(m, outer, path, RIB_R, RIB_SIDES, "shade", True, "rib")
    last = _weld(m, inner, path, RIB_R, RIB_SIDES, "bark", False, "rib boss")
    tube(m, path, (RIB_R, RIB_R * 0.95, RIB_R * 0.9), RIB_SIDES, "bark", caps=(False, False), wob=0.04, rng=r,
         first_ring=first, last_ring=last)


# ---- roof -------------------------------------------------------------------

def _clump(m, ring, centre, radius, zone, r):
    clump_end(m, _by_azimuth(m, ring, centre), centre, radius, zone, r, wob=0.18)


def _roof(m, r, disc):
    """ROOF_N short thick branches out of sockets in the canopy top's ROOF_BAND,
    leaning out and up, each ending in a leaf clump; one side twig each,
    ending in a smaller clump: the crown's lumps."""
    outer, inner = disc[ROOF_BAND + 1], disc[ROOF_BAND + 2]
    n = CANOPY_N
    for k in range(ROOF_N):
        b = k * 360.0 / ROOF_N + 30.0 + r.u(-6.0, 6.0)
        v = int(round(-b / 360.0 * n - 0.5)) % n
        b = -math.degrees(_canopy_theta(v))     # snapped to the band's vertex
        patch = _patch(m, outer, inner, [(v - 1) % n, v])
        root = _patch_centre(m, patch)
        rr = math.hypot(root[0], root[1])
        pull = pol(b, rr + ROOF_P[0][0], ROOF_P[0][1])
        tip = pol(b + r.u(-2.0, 2.0), rr + ROOF_P[1][0], ROOF_P[1][1])   # near enough straight up that the socket ring stays round
        path = bez(root, pull, tip, ROOF_SEGS)
        first = _weld(m, patch, path, ROOF_R[0], ROOF_SIDES, "leaf", True, "roof branch")
        rings = tube(m, path, ROOF_R, ROOF_SIDES, "bark", caps=(False, False), wob=0.06, rng=r, first_ring=first)
        _clump(m, rings[-1], add(tip, UP, ROOF_CLUMP[1]), ROOF_CLUMP[0], "sun", r)
        # the side twig: out of the branch's side, bending up, widened to six for its clump
        seg = int(round(TWIG_T * ROOF_SEGS))
        axis = _seg_axis(m, rings, seg)
        want = tangent(b) if r.f() < 0.5 else (-tangent(b)[0], -tangent(b)[1], 0.0)   # a tangential side: its normal is level, so the twig leaves sideways, not down into the leaves
        tp = _patch_mid(m, rings[seg], rings[seg + 1], _facing(m, rings, seg, want, 3))   # centred on a side: the ring sits flat on it
        troot = _patch_centre(m, tp)
        out = norm(sub(troot, axis))
        tpath = [troot, add(troot, out, 0.35), add(add(troot, out, 0.55), UP, 0.45), add(add(troot, out, 0.6), UP, 0.95)]
        tfirst = _weld(m, tp, tpath, TWIG_R, 4, "bark", True, "twig")
        trings = tube(m, tpath, (TWIG_R, TWIG_R * 0.8, TWIG_R * 0.6), 4, "bark", caps=(False, False), first_ring=tfirst)
        end = tpath[-1]
        six = [m.v((end[0] + 0.45 * math.cos(_canopy_theta(s, 6)), end[1] + 0.45 * math.sin(_canopy_theta(s, 6)), end[2] + 0.12))
               for s in range(6)]     # r 0.45: near enough the clump's first ring that no bridging triangle goes thin
        zipper(m, six, _by_azimuth(m, trings[-1], end), UP, "sun", centre=end)
        _clump(m, six, add(end, UP, TWIG_CLUMP[1]), TWIG_CLUMP[0], "sun", r)


# ---- the roof sheet: the crown becomes the ravine's roof --------------------

def _leaf_zone(f):
    """Leaf where the sheet bulges down into the light, shade in the hollows
    (forest_ceiling_build._leafy, so both sides of the seam read the same)."""
    def z(pts):
        n = float(len(pts))
        return "leaf" if f(sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n) < 0.0 else "shade"
    return z


def _sheet_slope(rad):
    """dz/dr of the contract's profile at radius rad: how steeply the dome climbs
    (or, past the crest, falls) there."""
    h = 0.05
    return (forest_seam.sheet_z(rad + h) - forest_seam.sheet_z(rad - h)) / (2.0 * h)


def _sheet_blend(rad):
    """How much of the seam's own SEAM_WAVES this radius carries instead of its
    own billow: nothing until SEAM_BLEND metres short of the seam, all of it at
    the seam. The handover is what keeps the lumps running through the join."""
    return max(0.0, min(1.0, (rad - (forest_seam.SEAM_R - SEAM_BLEND)) / SEAM_BLEND))


def _rim_r(th, bound=False):
    """The crown's rim (CANOPY[1], the ring the sheet grows out of) at Blender
    angle th. ``bound`` adds the whole swing of the jitter, so the answer is an
    upper bound on where a rim vertex can actually be rather than a mean."""
    _y, frac, share = CANOPY[1]
    r = _canopy_R(th, share) * frac
    return r * (1.0 + CANOPY_JITTER[0]) if bound else r


def _sheet_lobe(rad, th):
    """How far out the sheet's ring at nominal radius ``rad`` is pushed at angle
    th: the crown rim's own lobe, at full size where the sheet leaves the rim and
    gone by SHEET_LOBE_OUT. In phase with the rim, so the first band keeps its
    width all the way round and neighbouring rings can never cross (their radii
    differ by the nominal spacing less the difference of two decays)."""
    r0 = forest_seam.CROWN_RIM[0]
    t = max(0.0, min(1.0, (SHEET_LOBE_OUT - rad) / (SHEET_LOBE_OUT - r0)))
    return t * (_rim_r(th, bound=True) - _rim_r(math.pi / (2.0 * CANOPY_LOBES[0]) + _pier_theta0(), bound=True))


def _sheet_r(rad, th):
    """The sheet's ring radius at (nominal radius, angle): never inside the
    contract's own inner radius, and never inside the crown's rim."""
    return max(forest_seam.CROWN_RIM[0], rad + _sheet_lobe(rad, th))


def _rim_z_max():
    """The highest a vertex of the crown's rim can be, jitter included."""
    return CANOPY[1][0] + CANOPY_JITTER[1]


def _sheet_profile():
    """The sheet's rings, crown rim to seam: [(radius, nominal z, billow amplitude)].

    Every ring sits on forest_seam.sheet_z's curve, one every SHEET_STEP of slant,
    closer near the rim where a band would be over SHEET_ASPECT quad widths.

    The amplitude is then capped per ring so no ring can billow past a neighbour:
    the clearance to a neighbour is the slant between them less whatever the seam's
    own wave can open up between their two blends, and a ring takes SHEET_FOLD of
    the smaller clearance either side."""
    S = forest_seam.SHEET
    radii, rad, run, dr = [S[0][0]], S[0][0], 0.0, 0.01
    while rad < S[-1][0] - 1e-9:        # walk the curve: a ring every SHEET_STEP of slant, closer where rings are narrow
        nxt = min(S[-1][0], rad + dr)
        run += math.hypot(nxt - rad, forest_seam.sheet_z(nxt) - forest_seam.sheet_z(rad))
        rad = nxt
        if run >= min(SHEET_STEP, SHEET_ASPECT * forest_seam.TWO_PI * radii[-1] / SHEET_N):
            radii.append(rad)
            run = 0.0
    if radii[-1] < S[-1][0] - 1e-9:     # the last short piece joins the band before it
        radii[-1] = S[-1][0]
    prof = [(rad, forest_seam.sheet_z(rad)) for rad in radii[:-1]] + [(S[-1][0], S[-1][1])]
    swing = sum(amp for (_k, amp, _ph) in forest_seam.SEAM_WAVES)   # the seam's whole wave
    blend = [_sheet_blend(rad) for (rad, _z) in prof]
    a, b = S[1][0], S[2][0]
    out = []
    for i, (rad, z) in enumerate(prof):
        if i == 0 or i == len(prof) - 1:      # the crown's rim and the seam are given, not billowed
            out.append((rad, z, 0.0))
            continue
        t = max(0.0, min(1.0, (rad - a) / (b - a)))
        cap = SHEET_IN_LUMP + (forest_seam.SHEET_LUMP - SHEET_IN_LUMP) * t
        for j in (i - 1, i + 1):
            clear = math.hypot(prof[j][0] - rad, prof[j][1] - z) - swing * abs(blend[i] - blend[j])
            cap = min(cap, SHEET_FOLD * clear)
        out.append((rad, z, max(0.0, cap)))
    return out


SHEET_RINGS = _sheet_profile()                             # (r, z, amplitude), rim to seam
SHEET_AMP = [(rad, amp) for (rad, _z, amp) in SHEET_RINGS]  # the amplitude read at any radius


def _sheet_amp(rad):
    """How far the sheet billows at radius rad: SHEET_RINGS' capped amplitudes,
    read between the rings, so what hangs from the sheet sees the same numbers."""
    return _pw(SHEET_AMP, rad)


def _ramp(x, a, b):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def _place_crowns():
    """The tree tops over the ravine, biggest first, none crowding another or the
    tower's crown closer than CROWN_GAP: each an oval, lobed dome of its own."""
    r = _Rng(CROWN_SEED)
    radii = sorted((r.u(*CROWN_R) for _ in range(CROWN_TRIES)), reverse=True)
    lo, hi = CROWN_SPAN
    tops = []
    for R in radii:
        for _try in range(60):
            rc = math.sqrt(r.u(lo * lo, hi * hi))
            a = r.u(0.0, 2.0 * math.pi)
            x, y = rc * math.cos(a), rc * math.sin(a)
            if rc < CROWN_GAP * (CROWN_TOWER_R + R):
                continue
            if any(math.hypot(x - t["x"], y - t["y"]) < CROWN_GAP * (R + t["R"]) for t in tops):
                continue
            tops.append({"x": x, "y": y, "R": R, "D": min(CROWN_DEEPEST, R * r.u(*CROWN_DEPTH)),
                         "sx": math.sqrt(r.u(*CROWN_STRETCH)), "phi": r.u(0.0, math.pi),
                         "k": r.i(*CROWN_LOBES[0]), "amp": r.u(*CROWN_LOBES[1]), "ph": r.u(0.0, 6.28),
                         "zone": "sun" if r.f() < CROWN_SUN else "leaf"})
            break
    return tops, _field(r, 6, CROWN_LEAF)


CROWNS, CROWN_FIELD = _place_crowns()


def _crown_fade(rad):
    return _ramp(rad, *CROWN_FADE_IN) * (1.0 - _ramp(rad, *CROWN_FADE_OUT))


def _canopy_at(x, y):
    """(drop, top, share): how far the tree tops hang under the dome at (x, y), the
    top that hangs lowest there, and how deep into it (1 at its middle, 0 at a crease)."""
    fade = _crown_fade(math.hypot(x, y))
    if fade <= 0.0:
        return 0.0, None, 0.0
    best, top = 0.0, None
    for t in CROWNS:
        dx, dy = x - t["x"], y - t["y"]
        if abs(dx) > 1.6 * t["R"] or abs(dy) > 1.6 * t["R"]:
            continue
        ca, sa = math.cos(t["phi"]), math.sin(t["phi"])
        u, v = (dx * ca + dy * sa) / t["sx"], (dy * ca - dx * sa) * t["sx"]
        d = math.hypot(u, v) / (t["R"] * (1.0 + t["amp"] * math.cos(t["k"] * math.atan2(v, u) + t["ph"])))
        if d < 1.0:
            h = t["D"] * (1.0 - d * d) ** 0.6
            if h > best:
                best, top = h, t
    if top is None:
        return 0.0, None, 0.0
    return fade * best * (1.0 + CROWN_LUMP * CROWN_FIELD(x, y)), top, best / top["D"]


def _canopy_zone(f):
    """The top's own leaf in its middle, shade in the creases where tops meet; off
    the canopy's span the sheet's old billow picks, as the lane roof's does."""
    old = _leaf_zone(f)

    def z(pts):
        n = float(len(pts))
        x, y = sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n
        if _crown_fade(math.hypot(x, y)) < 0.5:
            return old(pts)
        _drop, top, share = _canopy_at(x, y)
        return "shade" if top is None or share < CROWN_EDGE else top["zone"]
    return z


def _sheet_under(f, rad, th, tops=True):
    """The sheet's underside at (radius, Blender angle): the dome's profile, its
    own billow, and -- near the seam -- the seam's own wave taking that billow's
    place, so the last band arrives on the shared ring already lumped like it.
    ``tops`` hangs the tree tops from it; the top skin rides above without them."""
    if rad >= forest_seam.SEAM_R:
        return forest_seam.seam_z(th)
    t = _sheet_blend(rad)
    x, y = rad * math.cos(th), rad * math.sin(th)
    own = _sheet_amp(rad) * f(x, y)
    drop = _canopy_at(x, y)[0] if tops else 0.0
    return forest_seam.sheet_z(rad) + (1.0 - t) * own + t * (forest_seam.seam_z(th) - forest_seam.SEAM_Z) - drop


def _sheet_top_z(f, rad, th):
    """The unseen top skin: the same field, lifted by the leaf mass's thickness,
    so the two skins are parallel and never cross. The lift is measured along the
    sheet's normal and applied in z, which on a rising dome is the vertical
    thickness hypot(1, slope) -- straight up it would read thinner as it steepens."""
    r0, r1 = forest_seam.CROWN_RIM[0], forest_seam.SEAM_R
    taper = max(0.0, (r1 - rad) / (r1 - r0))
    return _sheet_under(f, rad, th, tops=False) + SHEET_THICK * taper * math.hypot(1.0, _sheet_slope(rad))


def _sheet(m, r, disc):
    """The crown's rim carried out over the ravine to the level's seam.

    The underside (what the lane sees) runs from the rim ring, 56 verts, out
    through SHEET_RINGS at SHEET_N and ends in forest_seam.seam_ring() vertex
    for vertex: the level's roof carries on from these exact floats. The dome
    climbs the whole way, so it is the RIM that is the low point and the seam
    the high one, and every band is measured against a fold, not a sag.
    A coarse top skin runs back from the same seam ring into the crown, taking
    over the crown's first top band, so the sheet is a closed leaf mass: every
    edge still carries two faces. Returns (underside rings, seam ids, field)."""
    f = _field(r)
    zone = _canopy_zone(f)
    rings = []
    for (rad, _z, _amp) in SHEET_RINGS[1:-1]:
        ring = []
        for s in range(SHEET_N):
            th = _canopy_theta(s, SHEET_N)
            rr = _sheet_r(rad, th)      # the crown's lobe, fading out: see SHEET_LOBE_OUT
            zz = max(_sheet_under(f, rr, th), _rim_z_max() + SHEET_RIM_RISE)
            ring.append(m.v((rr * math.cos(th), rr * math.sin(th), zz)))
        rings.append(ring)
    seam = [m.v(p) for p in forest_seam.seam_ring()]       # verbatim, in seam order
    zipper(m, disc[2], rings[0], DOWN, zone)
    loft(m, rings, zone, want_fn=lambda c: DOWN)
    zipper(m, rings[-1], seam, DOWN, zone)
    top = []
    for (rad, n) in SHEET_TOP:
        ring = []
        for s in range(n):
            th = _canopy_theta(s, n)
            ring.append(m.v((rad * math.cos(th), rad * math.sin(th), _sheet_top_z(f, rad, th))))
        top.append(ring)
    zipper(m, disc[3], top[0], DOWN, "leaf")      # the top skin wants DOWN with the sheet: nothing is ever
    for i in range(len(top) - 1):                 # above it in play, and a view from over the ravine culls it
        zipper(m, top[i], top[i + 1], DOWN, "leaf")
    zipper(m, top[-1], seam, DOWN, "leaf")
    _PROOF["bands"] = (("under", [disc[2]] + rings + [seam]), ("top", [disc[3]] + top + [seam]))
    return rings, seam, f


def _oval(centre, ex, ey, radii, sides, phase=0.0):
    """A closed ring of ``sides`` points, ``radii`` = (along ex, along ey)."""
    out = []
    for s in range(sides):
        a = 2.0 * math.pi * s / sides + phase
        out.append(add(add(centre, ex, radii[0] * math.cos(a)), ey, radii[1] * math.sin(a)))
    return out


def _socket_loop(m, quads, sides, shrink, ex=None, along=None):
    """A socket ring that is the patch's own boundary drawn in toward its centre,
    sampled at ``sides`` points by arc length. socket() bridges the two loops by
    angle, so a ring shaped like its patch gives a frame of short trapezoids;
    a small round ring in a long patch gives a fan of slivers. ``along`` fixes
    the ring's winding (the tube's direction) and ``ex`` its first point."""
    loop = _loop_of(m, quads)
    pts = [m.verts[i] for i in loop]
    c = m.centroid(loop)
    n = len(pts)
    lens = [math.sqrt(dot(sub(pts[(i + 1) % n], pts[i]), sub(pts[(i + 1) % n], pts[i]))) for i in range(n)]
    total = sum(lens)
    out = []
    for k in range(sides):
        t = (k + 0.5) * total / sides
        acc, i = 0.0, 0
        while i < n - 1 and acc + lens[i] < t:
            acc += lens[i]
            i += 1
        f = (t - acc) / lens[i] if lens[i] > 1e-9 else 0.0
        out.append(lerp(c, lerp(pts[i], pts[(i + 1) % n], f), shrink))
    if along is not None and dot(_newell(out), along) < 0.0:
        out.reverse()
    if ex is not None:
        k = max(range(sides), key=lambda i: dot(norm(sub(out[i], c)), ex))
        out = out[k:] + out[:k]
    return out


def _fit(z, radius, squash):
    """The largest clump radius that still hangs clear of LEAF_FLOOR."""
    return max(0.35, min(radius, (z - LEAF_FLOOR) / squash))


def _hung(m, r, last_ring, end, centre, radius, zone, squash=CLUMP_SQUASH):
    """A leaf clump hung on the end of a tube that arrives along the clump's own
    axis. A collar ring the size of the clump's first ring sits at the tube's
    end, as the crown's twigs do: bridging a 0.2 m ring straight onto a 1.2 m
    one is what makes a thin triangle."""
    n = len(last_ring)
    ring = _by_azimuth(m, last_ring, end)
    a0 = math.atan2(m.verts[ring[0]][1] - end[1], m.verts[ring[0]][0] - end[0])
    collar = [m.v((centre[0] + 0.45 * radius * math.cos(a0 + 2.0 * math.pi * (s + 0.5) / n),
                   centre[1] + 0.45 * radius * math.sin(a0 + 2.0 * math.pi * (s + 0.5) / n), end[2]))
              for s in range(n)]      # half a step off the tube's own ring: the zipper never ties
    zipper(m, collar, ring, UP if end[2] > centre[2] else DOWN, zone, centre=end)
    clump_end(m, collar, centre, radius, zone, r, squash=squash, wob=0.2)


def _sheet_clumps(m, r, rings):
    """Leaf masses on short stems out of the sheet's own quads, so the underside
    reads as foliage and not a plane (forest_ceiling_build._rim_clump's trick)."""
    taken = set()
    placed = tries = 0
    while placed < SHEET_CLUMPS and tries < 600:
        tries += 1
        band = r.i(0, len(rings) - 2)
        s = r.i(0, SHEET_N - 1)
        if (band, s) in taken:
            continue
        quads = [_band_quad(rings[band], rings[band + 1], (s + d) % SHEET_N) for d in (0, 1)]
        if not all(m.has_quad(q) for q in quads):
            continue
        c = _patch_centre(m, quads)
        rad = math.hypot(c[0], c[1])
        if not (15.0 <= rad <= 44.5) or _canopy_at(c[0], c[1])[2] >= CROWN_EDGE:
            continue                    # small tops in the creases between the big ones
        crad = r.u(*SHEET_CLUMP_R)
        cz = c[2] - r.u(*SHEET_CLUMP_HANG) - crad * CLUMP_SQUASH
        crad = _fit(cz, crad, CLUMP_SQUASH)
        centre = (c[0], c[1], cz)
        top = centre[2] + 0.55 * crad * CLUMP_SQUASH
        er = norm((c[0], c[1], 0.0))
        et = (-er[1], er[0], 0.0)
        foot = _socket_loop(m, quads, STEM_SIDES, STEM_IN, ex=er, along=DOWN)
        ring0 = _weld_pts(m, quads, foot, DOWN, "shade", "sheet clump")
        neck = _oval((c[0], c[1], top), er, et, (STEM_R, STEM_R), STEM_SIDES)
        mid = [lerp(m.verts[ring0[k]], neck[k], 0.62) for k in range(STEM_SIDES)]
        srings = [ring0, [m.v(q) for q in mid], [m.v(q) for q in neck]]
        loft(m, srings, "bark", want_fn=lambda q: (q[0] - c[0], q[1] - c[1], 0.0))
        _hung(m, r, srings[-1], (c[0], c[1], top), centre, crad, "sun" if r.f() < 0.5 else "leaf")
        taken.add((band, s))
        for d in (-2, -1, 0, 1, 2):
            taken.add((band, (s + d) % SHEET_N))
        placed += 1
    return placed


def build_tree_geometry():
    del _WELDS[:]
    m = _Mesh()
    r = _Rng(SEED)
    trunk = _trunk(m, r)
    belly, boss, disc = _canopy(m, r)
    piers = [_pier(m, r, k, trunk, belly) for k in range(PIERS)]
    for k in range(PIERS):
        _arch(m, r, k, piers)
        _rail(m, r, k, piers)
        _rib(m, r, k, belly, boss)
    _roof(m, r, disc)
    _PROOF["first_new"] = len(m.verts)
    sheet, seam, field = _sheet(m, r, disc)
    _PROOF["first_limb"] = len(m.verts)
    _PROOF["clumps"] = _sheet_clumps(m, r, sheet)
    _PROOF["seam"] = [m.verts[i] for i in seam]
    _PROOF["new"] = [m.verts[i] for i in range(_PROOF["first_new"], len(m.verts))]
    _PROOF["skin"] = [m.verts[i] for i in range(_PROOF["first_new"], _PROOF["first_limb"])]
    # Everything the build made before the sheet -- trunk, floor, rim, piers,
    # arches, rails, belly, boss, ribs, canopy disc, roof branches -- as it
    # stands in the finished mesh, every socket carved in it included. Nothing
    # above the crown may move one float of it: this is the proof that it did not.
    _PROOF["limbs"] = [m.verts[i] for i in range(_PROOF["first_limb"], len(m.verts))]
    _PROOF["bands"] = tuple((tag, [[m.verts[i] for i in ring] for ring in rings])
                            for (tag, rings) in _PROOF["bands"])
    n = _PROOF["first_new"]
    _PROOF["pre"] = ([tuple(q) for q in m.verts[:n]],
                     [(tuple(f), m.zones[i]) for i, f in enumerate(m.faces)
                      if f is not None and max(f) < n])
    return _prune(m)


def _prune(m):
    """Drop the vertices no face references: a socket patch two bands tall
    takes its inner vertices with it (the pier bases)."""
    used = set()
    for f in m.faces:
        if f is not None:
            used.update(f)
    remap, verts = {}, []
    for i, p in enumerate(m.verts):
        if i in used:
            remap[i] = len(verts)
            verts.append(p)
    m.verts = verts
    m.faces = [tuple(remap[i] for i in f) if f is not None else None for f in m.faces]
    m.quads = {}
    return m


def build_tree_collider():
    """Trunk cylinder r 5 (foot to floor), the flat floor, the rim, the
    canopy's outer slope."""
    c = _Mesh()
    n = 24
    circ = lambda rad, y: [c.v((rad * math.cos(2.0 * math.pi * s / n),
                                rad * math.sin(2.0 * math.pi * s / n), y)) for s in range(n)]
    floor = circ(FLOOR_R, FLOOR_Y)
    c.fan(floor, UP, "bark")
    rim = [floor, circ(5.2, FLOOR_Y + 0.55), circ(7.0, FLOOR_Y + 0.55), circ(7.0, FLOOR_Y)]
    loft(c, rim[:3], "bark", want_fn=lambda p: UP)
    loft(c, rim[2:], "bark")
    loft(c, [circ(FLOOR_R, FOOT_Y), floor], "bark")
    canopy = [circ(CANOPY_R, forest_seam.CROWN_RIM[1]), circ(8.5, 36.0), circ(4.5, 36.9)]
    loft(c, canopy, "leaf", want_fn=lambda p: (p[0], p[1], 0.6 * math.hypot(p[0], p[1])))
    c.fan(canopy[-1], UP, "leaf")
    # The roof over the ravine: a shot fired up stops here. One ring on every
    # radius forest_seam.SHEET names, so the collider IS the contract's curve.
    # Three rings were enough while the roof was flat; on a dome that climbs
    # 15.9 m the chord between two of them would sit 1.6 m under the leaves,
    # and a shot would stop in clear air short of what the player can see.
    sheet = [canopy[0]] + [circ(rad, z) for (rad, z) in forest_seam.SHEET[1:]]
    loft(c, sheet, "leaf", want_fn=lambda p: DOWN)
    return c


# =============================================================================
# UNWRAP -- per-face planar projection into a random window of its zone
# =============================================================================

def unwrap(ob, zones, seed=0, water_fn=None):
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + seed * 7919 + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        zone = zones[pi]
        if zone == "water" and water_fn:
            water_fn(me, uvl, poly)
            continue
        u0, v0, u1, v1 = ZONES[zone]
        span_u = (u1 - u0) - 2.0 * UV_PAD
        span_v = (v1 - v0) - 2.0 * UV_PAD
        scale = TPM / ((u1 - u0) * TEX_SIZE)      # metres -> fraction of the zone, each axis its own
        scale_v = TPM / ((v1 - v0) * TEX_SIZE)    # (the lane's zones are wider than tall)
        nrm = poly.normal
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
        fu = -1.0 if r.i(0, 1) else 1.0
        fv = -1.0 if (ax == 2 and r.i(0, 1)) else 1.0
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        mi = min(co[ii] for co in cos)
        mj = min(co[jj] for co in cos)
        w = min((max(co[ii] for co in cos) - mi) * scale, 1.0)
        h = min((max(co[jj] for co in cos) - mj) * scale_v, 1.0)
        ou = r.f() * (1.0 - w)
        ov = r.f() * (1.0 - h)
        for li, co in zip(poly.loop_indices, cos):
            s = min(ou + (co[ii] - mi) * scale, 1.0)
            t = min(ov + (co[jj] - mj) * scale_v, 1.0)
            if fu < 0.0:
                s = 1.0 - s
            if fv < 0.0:
                t = 1.0 - t
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


# =============================================================================
# BUILD / CHECK
# =============================================================================

def build_render_copy(albedo=None, emissive=None):
    """The tree in WORLD coordinates for another model's review renders."""
    m = build_tree_geometry()
    ob = m.object("ReviewTree")
    unwrap(ob, m.zones)
    if albedo is None:
        albedo, emissive = sheet("forest_atlas", paint_atlas)
    mdl.finish(ob, atlas_material("ForestAtlasTree", albedo, emissive), strip_uvs=False)
    return ob


def build():
    m = build_tree_geometry()
    c = build_tree_collider()
    albedo, emissive = sheet("forest_atlas", paint_atlas)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    shift = (0.0, 0.0, -ORIGIN_Y)
    ob = m.object(OBJECT_NAME, shift)
    unwrap(ob, m.zones)
    mdl.finish(ob, atlas_material("ForestAtlas", albedo, emissive), strip_uvs=False)
    coll = c.object(COLLIDER_NAME, shift)
    coll.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d floor_y=%.2f eye_y=%.2f apex_y=%.1f"
          % (len(ob.data.polygons), len(coll.data.polygons), FLOOR_Y, FLOOR_Y + EYE_H, APEX[1]))
    return [ob, coll]


def _ring_z(ring, th):
    """A ring's height at Blender angle th, read between its two nearest vertices:
    what the sheet's surface is at that bearing, whatever the ring's vertex count."""
    n = len(ring)
    a = [(math.atan2(q[1], q[0]) % forest_seam.TWO_PI, q[2]) for q in ring]
    a.sort()
    for k in range(n):
        a0, z0 = a[k]
        a1, z1 = a[(k + 1) % n]
        span = (a1 - a0) % forest_seam.TWO_PI
        off = (th % forest_seam.TWO_PI - a0) % forest_seam.TWO_PI
        if off <= span:
            return z0 + (z1 - z0) * (off / span if span > 1e-12 else 0.0)
    return a[0][1]


def _check():
    import forest_check
    m = build_tree_geometry().compact()
    c = build_tree_collider().compact()
    forest_check.prove(m, "tree")
    forest_check.components_report(m)
    seam = _PROOF["seam"]
    cnt, dev = forest_seam.report(seam, forest_seam.seam_ring())
    print("SEAM n=%d max_dev=%.6f" % (cnt, dev))
    for (tag, rings) in _PROOF["bands"]:
        worst_asp, min_rise, at = 0.0, 1e9, 0.0
        for k in range(len(rings) - 1):
            a, b = rings[k], rings[k + 1]
            ra = sum(math.hypot(q[0], q[1]) for q in a) / len(a)
            rb = sum(math.hypot(q[0], q[1]) for q in b) / len(b)
            za = sum(q[2] for q in a) / len(a)
            zb = sum(q[2] for q in b) / len(b)
            width = min(forest_seam.TWO_PI * ra / len(a), forest_seam.TWO_PI * rb / len(b))
            worst_asp = max(worst_asp, math.hypot(rb - ra, zb - za) / width)
            for deg in range(720):            # the fold test is per bearing, not per ring:
                th = math.radians(deg * 0.5)  # two rings may overlap in z and still not fold
                rise = _ring_z(b, th) - _ring_z(a, th)
                if rise < min_rise:
                    min_rise, at = rise, ra
        print("SHEET %-5s bands=%2d worst_aspect=%.2f min_rise=%+.3f at r=%.1f (fold if <= 0)"
              % (tag, len(rings) - 1, worst_asp, min_rise, at))
    low = min(_PROOF["limbs"], key=lambda q: q[2])
    print("HUNG lowest_y=%.2f at r=%.1f (clear floor %.2f, guard's eye %.2f) clumps=%d tops=%d"
          % (low[2], math.hypot(low[0], low[1]), LEAF_FLOOR, FLOOR_Y + EYE_H, _PROOF["clumps"], len(CROWNS)))
    skin = _PROOF["skin"]
    print("SHEET_SKIN y=%.2f..%.2f verts=%d" % (min(q[2] for q in skin), max(q[2] for q in skin), len(skin)))
    room = sorted((round(p[0], 5), round(p[1], 5), round(p[2], 5)) for p in m.verts
                  if p[2] < ROOM_Z and math.hypot(p[0], p[1]) <= ROOM_R)
    try:
        import pickle
        was = sorted(tuple(p) for p in pickle.load(open("/tmp/tree_room_verts_before.pkl", "rb")))
        print("ROOM_UNCHANGED %s (%d verts under y %.1f inside r %.1f)"
              % ("ok" if was == room else "CHANGED", len(room), ROOM_Z, ROOM_R))
    except IOError:
        print("ROOM_UNCHANGED no baseline (%d verts)" % len(room))
    pre_v, pre_f = _PROOF["pre"]
    try:
        import pickle
        was_v, was_f = pickle.load(open("/tmp/tree_pre_sheet_before.pkl", "rb"))
        same = (was_v == pre_v) and ([(tuple(f), z) for (f, z) in was_f] == pre_f)
        print("PRESHEET_IDENTICAL %s (%d verts, %d tris: trunk, floor, rim, piers, arches,"
              " rails, belly, boss, ribs, canopy disc, roof branches)"
              % ("ok" if same else "CHANGED", len(pre_v), len(pre_f)))
    except IOError:
        print("PRESHEET_IDENTICAL no baseline (%d verts, %d tris)" % (len(pre_v), len(pre_f)))
    welds = {}
    for tag, margin in _WELDS:
        welds.setdefault(tag, []).append(margin)
    print("WELDS " + " ".join("%s=%d(min %.2f)" % (t.replace(" ", "_"), len(v), min(v)) for t, v in sorted(welds.items())))
    for name, mm in (("tree", m), ("coll", c)):
        degen = 0
        for f in mm.faces:
            n = _newell([mm.verts[i] for i in f])
            if math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) < 1e-7:
                degen += 1
        zones = {}
        for z in mm.zones:
            zones[z] = zones.get(z, 0) + 1
        lo = [min(v[k] for v in mm.verts) for k in range(3)]
        hi = [max(v[k] for v in mm.verts) for k in range(3)]
        print("%s tris=%d verts=%d degenerate=%d zones=%s bbox=%s..%s"
              % (name, len(mm.faces), len(mm.verts), degen, zones,
                 ["%.1f" % x for x in lo], ["%.1f" % x for x in hi]))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW)
