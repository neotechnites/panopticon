"""
PANOPTICON -- the tower: a watch chamber cut into the top of a hoodoo, a
thousand years ago, in hell. It is HOLLOW, and the shooter stands inside it.

THE BRIEF, IN THE ORDER IT ARRIVED
----------------------------------
Ryan: "imagine like the hoodoos in bryce canyon if they had a room on top, but
again, like its man made, carved out of the rock. and again, low poly. ps1.
dark red like ultrakill or the nightsophere. like a lighthouse, carved from
dark red rock, 1000 years ago."

"it should not have horiztonal anything, becasue it it was man made it wouldnt,
and frankly, it should be so low poly you couldnt even see that definitino if
you could."

"that is legitimently an incredible job on the tower ... the base is nearly
perfect" -- with one change: centre the chamber on the column.

"the watch tower part should be hollow, and the shooter goes inside. literally
like a proper panopticon."

And then, after a rebuild that took that last note as licence to redesign:
"the design of the tower was perfect, go back, and simply make the part that
looks like the watch tower functional. you changed it massivly."

THAT LAST NOTE IS THE MOST IMPORTANT LINE IN THIS FILE
-------------------------------------------------------
THE EXTERIOR IS SIGNED OFF AND IS NOT A DESIGN PROBLEM ANY MORE. Every number
in RING_PROFILE and CH_PROFILE, CH_OPEN_DEPTH, CH_PIER_PROUD, the seeds, and
the RNG draw order in `_column` and `_chamber` reproduce the approved model
exactly. The interior was CARVED OUT of that building; the building was not
redesigned around the interior. If a future change makes the outside look
different, it is wrong, however much better it looks.

Two mistakes are worth stating so they are not made a third time:
  * A rebuild that "improved" the chamber -- eleven splayed embrasures, a 12 m
    interior, thinner walls, a new roof -- was a different building and was
    thrown away. Functionality is added INSIDE the approved envelope.
  * Every jitter array is a walk of a seeded LCG, so its values depend on how
    many rings it walks and in what order the draws happen. JITTER_RINGS
    exists solely to freeze the column's walk at its old length. Do not tidy
    it away, and do not reorder the draws in either builder.

WHAT WAS ADDED, AND NOTHING ELSE WAS
-------------------------------------
  * An inner shell at RM_RIN, wound to face INWARD.
  * A floor and a ceiling.
  * The eight recesses opened right THROUGH the wall. Each was a V-shaped
    notch between two piers; the outer faces either side of it are now cut
    back to their midpoints and the notch's bottom is a genuine void, with
    reveal faces lining the 0.4 m of stone left at the throat. From outside
    the notch still reads as a dark slot in the same place at the same size --
    it was already the darkest thing on the model -- and the ember faces
    flanking it are untouched.

INSIDE-FACING GEOMETRY -- THE THING THAT BREAKS IF YOU ARE CASUAL ABOUT IT
--------------------------------------------------------------------------
Godot's StandardMaterial3D culls back faces, so a shell modelled only from
outside is INVISIBLE from within: the guard would stand in a room made of
nothing and see the world through its walls. Every face in this file is
emitted through `_Mesh._emit`, which is given the direction the finished
normal is REQUIRED to point and reverses the winding if the Newell normal
disagrees. A backwards skin renders perfectly from every camera angle and is a
hole in the world the moment somebody walks into it; nothing else warns you.

ORIGIN -- (0, 0, 0) IS THE ROOM'S FLOOR
---------------------------------------
CHANGED, AND IT HAD TO BE. It used to be the flat top of the drum, back when
the guard stood ON the tower. The guard is now INSIDE it, and TowerSpawn sits
at the Tower node's origin + 0.25 m; leaving the datum on the roof would spawn
them nine metres up in solid stone. So the whole model is shifted so that the
walking surface is again at local Y = 0, which is what every consumer of this
asset already assumes. Nothing about the shape moved -- this is a pure
re-datum, and the renders are identical.

    room floor .......  y =   0.00   (TowerSpawn lands 0.25 m above it)
    top of the drum ..  y = + ROOM_LIFT
    foot of the column  y = - (HEIGHT - ROOM_LIFT)

HEIGHT is still the one tunable that matters: it is the foot-to-drum-top
distance, everything below is a fraction of it, and raising the tower over the
three-level ring stays one number on the Tower node's transform.

Run through the pipeline (from the Mac, from the repo root)::

    tools/modelling/model look  tower --views side,threequarter,lowangle
    tools/modelling/model build tower --views side,threequarter,lowangle

Those three are the shots to compare against the approved renders. Two more
come back with every run, rendered by `_interior_render` rather than by the
standard rig, because mdl solves its camera from the bounding box and can only
ever stand outside the model:

    tower_room.png     the guard's room from within, looking at an opening
    tower_gunport.png  eye at an opening, aimed down at the ring

COORDINATES
-----------
Authored in BLENDER space, then glTF-exported (Blender X,Y,Z -> glTF X,Z,-Y):

    Blender +Z  ->  Godot +Y   (UP -- the column runs along this)
    Blender +X  ->  Godot +X
    Blender +Y  ->  Godot -Z

TEXTURING
---------
One 128x128 atlas quartered into four 64x64 zones, painted texel by texel here
-- no gradients, nearest filtering, PS1 rules -- plus an emissive map that is
black everywhere except the brimstone. The zones are deliberately almost
featureless: at this triangle count and this viewing distance the silhouette
and the colour do all the work, and any pattern with a direction in it would
be reintroducing the horizontal layering the brief threw out.

Zone assignment on the exterior is unchanged from the approved model. Every
NEW surface -- inner shell, floor, ceiling, and the reveals lining the
throats -- takes the near-black zone, so the room stays dark and an opening
still bottoms out in black when a prisoner looks into it.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# ---- RENDER RIG OVERRIDE ----------------------------------------------------
# THE GROUND PLANE HAS TO GO FOR THIS ONE MODEL, and it is worth knowing why
# before turning it back on. mdl drops the plane at the bottom of the bounding
# box and then solves camera distance from that same box. Every other model in
# the repo stands ON its origin, so its box is a couple of metres tall and a
# negative-elevation camera stays above the plane. This one hangs tens of
# metres below its origin, so at `lowangle` (el = -14) the camera solves to a
# point under the floor. The render then "succeeds" and returns a completely
# black frame of the plane's underside -- the exact class of failure
# docs/MODELLING.md warns about with hand-aimed cameras: a picture of nothing
# that looks like a modelling bug. The low angle is the prisoner's view and it
# is the shot that matters most, so the plane goes and the world comes up to
# compensate -- it is now doing the fill the bounce used to do.
mdl.DEFAULTS["ground"] = False
mdl.DEFAULTS["world_grey"] = 0.30
mdl.DEFAULTS["world_strength"] = 0.90

# =============================================================================
# TUNABLES -- everything adjustable lives in this block
# =============================================================================

NAME = "tower"          # -> assets/models/tower.glb
OBJECT_NAME = "TowerRock"
COLLIDER_NAME = "TowerCollision-colonly"

HEIGHT = 46.0          # foot of the column to top of the drum

# ---- THE COLUMN'S SILHOUETTE -- SIGNED OFF, DO NOT RETUNE -------------------
# (height_t, radius_m). ONE ENTRY PER RING -- no interpolation, so this list IS
# the profile and the vertex ring count at once. At this poly count every ring
# costs 24 triangles, so every ring earns a kink in the silhouette.
#
# It pinches and swells rather than tapering, which is the one thing taken from
# the Bryce photograph. A first pass stepped evenly between four pinches of
# equal depth and the tower came out as a turned baluster -- a stack of spools,
# obviously made on a lathe, which is the wrong kind of man-made entirely.
# Cutting it back to ONE real pinch and one slight swell fixed the lathe;
# pinching HARD at 0.700 and standing the drum on that neck built the tower.
RING_PROFILE = [
    (0.000, 10.2),   # foot -- buried in the pit floor once this is placed
    (0.120,  9.6),
    (0.265, 10.4),   # one slight swell
    (0.430,  7.6),   # THE pinch: the slender middle of the column
    (0.560,  8.9),   # modest swell
    (0.700,  6.9),   # THE NECK -- the masons take over from here
]

JITTER_RINGS = 11      # frozen; see the header. NOT the ring count.

SIDES       = 12       # 12 sides x 5 bands x 2 + 20 cap = 140 tris for 46 m
JAG         = 0.120
JAG_RUN     = (2, 4)   # rings a jitter value is HELD for -- it steps, like
                       # cleaved rock, rather than wobbling like a candle
TOP_JAG     = 0.020
ANG_JAG     = 0.42     # chosen ONCE per side and held for the whole height, so
                       # every vertical edge stays vertical
Z_JAG       = 0.90
DRIFT       = 1.30     # a column whose rings are all concentric reads as
DRIFT_FADE  = 0.70     # turned however much its radius varies -- the swells
                       # have to be ONE-SIDED to read as rock

# ---- THE DRUM -- SIGNED OFF, DO NOT RETUNE ---------------------------------
# Sixteen sides; eight openings alternating with eight piers. The plinth flares
# out from inside the neck in a fifth of the height a first pass took, so the
# underside is a flat soffit rather than a bulge -- the bulge was what made the
# first chamber read as a helmet sitting on a head. The drum is NARROW on
# purpose: it has only 13 m of height to work with, so the only way to stop it
# reading as a ball is to take width off it.
CH_SIDES   = 16
CH_PROFILE = [
    (0.690,  4.2),   # buried inside the neck: no gap and no seam
    (0.712,  8.6),   # plinth -- flares out hard over the neck
    (0.728,  8.6),   # plinth band
    (0.775,  8.5),   # SILL COURSE, solid all the way round
    (0.795,  8.5),   # springing of the openings
    (0.912,  8.5),   # head of the openings
    (0.935,  8.6),   # LINTEL COURSE, solid all the way round
    (0.958,  9.4),   # gallery lip, thrown out over the wall
    (0.980,  9.3),
    (1.000,  8.0),   # the flat top of the drum
]
CH_OPEN_RINGS = (4, 5)   # indices into CH_PROFILE: springing .. head
CH_OPEN_DEPTH = 0.120    # opening vertices pull IN by this fraction of radius
CH_PIER_PROUD = 0.028    # pier vertices push OUT, so the step is ~3.1 m. The
                         # two together make the wall a sixteen-point zigzag:
                         # eight outward piers and eight inward notches, and
                         # every face is a ramp between one of each. There is
                         # no flat "window" panel and there never was -- which
                         # is exactly why hollowing it needs the half-face cut
                         # in `_chamber` rather than deleting faces.
CH_JAG     = 0.050       # dressed stone is nearly true. NOT exactly true: at
CH_ZJAG    = 0.70        # zero this is CAD and a thousand years have not
CH_ANG_JAG = 0.35        # happened to it.
CH_SEED    = 4410207

# ---- THE INTERIOR -- the only new geometry ---------------------------------
# Carved out of the drum above. Nothing here may push the outer surface around.
RM_RIN        = 7.00   # interior radius -> a 10.2 m room. It has to clear the
                       # deepest point of the notches (about 5.5 m) so that
                       # opening their throats breaks through, and it leaves
                       # 0.4 m of stone at the throat and 3.6 m at the piers.
RM_FLOOR_DROP = 0.17   # floor sits this far BELOW the openings' sill ring, so
                       # there is a low kerb rather than a lip you walk off
RM_CEIL_LIFT  = 0.75   # ceiling this far above the openings' head ring, well
                       # under the solid lintel course
RM_CUT        = 0.75   # HOW FAR BACK the outer face is cut to open the throat,
                       # as a fraction of each ramp measured from the notch.
                       # KEEP IT SMALL. At 0.50 the breach is the full width of
                       # the notch and the drum reads as an open belfry -- eight
                       # piers with daylight between them -- which is a
                       # different building from the one that was approved. At
                       # 0.24 almost all of the ramp survives, the notch still
                       # reads as the dark slot it always was, and the hole is
                       # a black throat at the bottom of it. It also keeps the
                       # dead-on view through the opening opposite (eight
                       # openings on a sixteen-gon are diametrically paired,
                       # and that cannot be fixed without changing the count,
                       # which is not mine to change) down to a spot rather
                       # than a window.

EYE_H  = 1.65          # the guard, for the interior renders and for the
BODY_H = 1.80          # sightline arithmetic printed in MDL STATS
BODY_R = 0.40

# ---- material / texture -----------------------------------------------------
TEX_SIZE      = 128
TEX_ALBEDO    = "tower_rock_albedo"
TEX_EMISSIVE  = "tower_rock_emissive"
TEX_SEED      = 6661031
ROCK_ROUGHNESS = 0.95
ROCK_METALLIC  = 0.0
UV_SCALE      = 0.13        # texels-per-metre feel. Facets here are 4-6 m
                            # across, so this is chunky on purpose.
UV_PAD        = 1.5 / TEX_SIZE

# Atlas zones as (u0, v0, u1, v1). v = 0 is the BOTTOM row of the image.
ZONE_ROCK   = (0.0, 0.5, 0.5, 1.0)   # dark red rock, the body
ZONE_SHADE  = (0.5, 0.5, 1.0, 1.0)   # near-black: facets that sit recessed
ZONE_CARVE  = (0.5, 0.0, 1.0, 0.5)   # dressed stone, a thousand years worn
ZONE_EMBER  = (0.0, 0.0, 0.5, 0.5)   # split open by brimstone -- the only glow

SHADE_BIAS  = -0.035   # a facet recessed by more than this takes the dark zone
EMBER_BIAS  = -0.095   # ... and by more than THIS, low down, it is a cleft.
                       # Deliberately near the top of JAG's range so only two
                       # or three facets qualify: ember spread over a dozen big
                       # faces stops being a glow and becomes a rust stain.
EMBER_TOP_T = 0.45     # no natural clefts above this: the heat is below

# ---- views ------------------------------------------------------------------
FACING_YAW = 0.0        # the column has no front


# =============================================================================
# TEXTURE -- hand-written texels, no gradients, no filtering, NO DIRECTION
# =============================================================================

class _Rng(object):
    """Tiny deterministic LCG so the model is byte-identical every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def bits(self):
        # An LCG's LOW bits are short-period; taking n() % 4 straight gives a
        # dither that repeats every 4 texels and renders as corduroy.
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
    """sRGB 0-255 -> scene-linear, which is what image.pixels wants."""
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
    """Angular blotches with NO PREFERRED DIRECTION.

    Everything painted here is a squarish patch. Not a line, not a streak, not
    a course -- rule 1 in the header bans directional pattern outright, and a
    long mark of any orientation reads at distance as exactly the layering
    that is not supposed to be here. Blotches also survive the random UV
    window without lining up across facet boundaries, which lines never do.
    """
    x0, y0, x1, y1 = box
    for _ in range(count):
        w = r.i(minsz, maxsz)
        h = max(minsz, min(maxsz, w + r.i(-1, 1)))    # squarish, never a bar
        x, y = r.i(x0, x1 - w - 1), r.i(y0, y1 - h - 1)
        c.rect(x, y, x + w, y + h, r.pick(shades))


def _paint_rock(c, r, box):
    """The body: dark red going to near-black. Nightosphere, not Bryce.

    Kept very dark and very plain. The arena's key light is already red, so a
    mid-toned rock comes out pink and stops the ember being the brightest
    thing in frame; and at 46 m tall seen from 35-60 m away, anything finer
    than these blotches is a waste of texels.
    """
    _fill(c, r, box, [(74, 27, 25), (58, 20, 19), (90, 35, 30), (46, 16, 16)])
    _shatter(c, r, box, [(96, 40, 33), (48, 16, 16), (110, 48, 38)], 20, 6, 15)
    _shatter(c, r, box, [(32, 11, 12), (118, 56, 43)], 12, 4, 9)
    x0, y0, x1, y1 = box
    for _ in range(6):                                   # heat still in the rock
        x, y = r.i(x0 + 2, x1 - 4), r.i(y0 + 2, y1 - 4)
        c.rect(x, y, x + 2, y + 2, (172, 44, 12), (114, 22, 3))


def _paint_shade(c, r, box):
    """Near-black, for facets that sit recessed.

    This is the model's contrast, and it is a PER-FACET property rather than a
    height one -- which is the whole point. It gives the column depth without
    a single horizontal division, and it matches the Nightosphere frame, which
    is mostly black with very few midtones in it.
    """
    _fill(c, r, box, [(34, 12, 12), (24, 8, 9), (44, 17, 15), (17, 6, 7)])
    _shatter(c, r, box, [(42, 16, 15), (10, 3, 4)], 20, 4, 11)
    x0, y0, x1, y1 = box
    for _ in range(4):
        x, y = r.i(x0 + 2, x1 - 4), r.i(y0 + 2, y1 - 4)
        c.rect(x, y, x + 2, y + 2, (140, 34, 9), (92, 16, 2))


def _paint_carve(c, r, box):
    """Dressed stone, a thousand years after the last chisel.

    Greyer and flatter than the living rock, because worked stone loses its
    colour, and lighter, because that is the only way the chamber separates
    from the column at distance. Heavily pitted and sooted so it does not read
    as freshly quarried. NO tool courses: an earlier pass had horizontal ones
    and they were the exact thing Ryan threw out.
    """
    _fill(c, r, box, [(84, 58, 53), (72, 48, 44), (96, 69, 63), (64, 42, 39)])
    _shatter(c, r, box, [(66, 43, 40), (102, 74, 68), (56, 35, 33)], 14, 5, 14)
    _shatter(c, r, box, [(74, 38, 27), (46, 27, 25)], 10, 4, 10)
    x0, y0, x1, y1 = box
    for _ in range(10):                                  # spall pits
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        c.rect(x, y, x + 2, y + 2, (52, 32, 30))
    for _ in range(3):                                   # a coal in a joint
        x, y = r.i(x0 + 2, x1 - 4), r.i(y0 + 2, y1 - 4)
        c.rect(x, y, x + 2, y + 2, (152, 48, 14), (88, 18, 2))


def _paint_ember(c, r, box):
    """Rock split wide open by brimstone -- and the light inside the openings.

    Random-walked cracks with a dull halo and a hot core, so the glow has a
    shape rather than being a flat orange field: at 35-60 m the halo is what
    survives and the core is what gives it depth. The walk is free to wander
    in any direction, which is what keeps it from becoming a stripe.
    """
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
    for _ in range(30):                               # cold slag between cracks
        c.put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), (7, 3, 4))
    for _ in range(10):                               # loose embers
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        c.rect(x, y, x + 2, y + 2, (236, 92, 18), (194, 54, 5))


def build_texture():
    """Paint the atlas and hand back (albedo_image, emissive_image)."""
    c = _Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    _paint_rock(c, r, _rect_of(ZONE_ROCK, TEX_SIZE))
    _paint_shade(c, r, _rect_of(ZONE_SHADE, TEX_SIZE))
    _paint_carve(c, r, _rect_of(ZONE_CARVE, TEX_SIZE))
    _paint_ember(c, r, _rect_of(ZONE_EMBER, TEX_SIZE))

    images = []
    for name, buf in ((TEX_ALBEDO, c.alb), (TEX_EMISSIVE, c.emi)):
        img = bpy.data.images.new(name, TEX_SIZE, TEX_SIZE, alpha=False)
        img.colorspace_settings.name = "sRGB"
        img.pixels.foreach_set(buf)
        img.update()
        images.append(img)
    return images[0], images[1]


def save_texture(img, out_dir):
    path = os.path.join(out_dir, img.name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    img.filepath = path
    img.pack()                      # so the .glb carries it too
    print("MDL TEXTURE %s (%dx%d)" % (path, TEX_SIZE, TEX_SIZE))
    return path


def rock_material(name, albedo, emissive):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    for img, socket, y in ((albedo, "Base Color", 260), (emissive, "Emission Color", -220)):
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.interpolation = "Closest"          # hard texels; this is the look
        node.location = (-460, y)
        nt.links.new(node.outputs["Color"], bsdf.inputs[socket])
    bsdf.inputs["Roughness"].default_value = ROCK_ROUGHNESS
    bsdf.inputs["Metallic"].default_value = ROCK_METALLIC
    # Exactly 1.0 keeps glTF from writing KHR_materials_emissive_strength,
    # which Godot's importer would warn about -- and the verify bar is zero
    # warnings, not "no errors".
    bsdf.inputs["Emission Strength"].default_value = 1.0
    mat.diffuse_color = (0.13, 0.04, 0.04, 1.0)
    return mat





# =============================================================================
# GEOMETRY HELPERS -- winding is checked, never assumed
# =============================================================================

RINGS = len(RING_PROFILE)
CH_RINGS = len(CH_PROFILE)

# The re-datum: enough lift to put the room's floor on y = 0. Derived, never
# typed in, so the floor follows CH_PROFILE if the drum ever legitimately moves.
ROOM_FLOOR_RAW = -HEIGHT * (1.0 - CH_PROFILE[CH_OPEN_RINGS[0]][0]) - RM_FLOOR_DROP
ROOM_LIFT = -ROOM_FLOOR_RAW
ROOM_CEIL = -HEIGHT * (1.0 - CH_PROFILE[CH_OPEN_RINGS[1]][0]) + RM_CEIL_LIFT + ROOM_LIFT


def height_of(t):
    """Blender Z of a profile fraction, re-datumed onto the room's floor."""
    return -HEIGHT * (1.0 - t) + ROOM_LIFT


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
    """Vertex/face accumulator that will not let a face end up inside out.

    Every emitter states the direction the finished normal MUST point --
    outward, inward, up, down -- and the winding is reversed if the Newell
    normal disagrees. That check is the whole reason this class exists: the
    drum now has an inner skin and an outer skin, they are wound opposite
    ways, and getting one of them backwards produces a model that looks
    perfect in every render and is a hole in the world the moment somebody
    stands inside it. Backface culling does not warn you.
    """

    def __init__(self):
        self.verts = []
        self.faces = []
        self.zones = []

    def v(self, p):
        self.verts.append(tuple(p))
        return len(self.verts) - 1

    def lerp(self, a, b, u):
        pa, pb = self.verts[a], self.verts[b]
        return self.v(tuple(pa[k] + (pb[k] - pa[k]) * u for k in range(3)))

    def _emit(self, idx, want, zone):
        pts = [self.verts[j] for j in idx]
        n = _newell(pts)
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        if len(idx) == 4:
            # Split rather than leaving a quad: the corners are not coplanar
            # (independent Z jitter), and an n-gon would shade from an averaged
            # normal that smooths away exactly the faceting this model is made
            # of.
            self.faces.append((idx[0], idx[1], idx[2]))
            self.faces.append((idx[0], idx[2], idx[3]))
            self.zones.append(zone)
            self.zones.append(zone)
        else:
            self.faces.append(tuple(idx))
            self.zones.append(zone)

    def quad(self, a, b, c, d, want, zone):
        self._emit([a, b, c, d], want, zone)

    def tri(self, a, b, c, want, zone):
        self._emit([a, b, c], want, zone)

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


def _radial(ang_a, ang_b, inward=False):
    am = 0.5 * (ang_a + ang_b)
    w = (math.cos(am), math.sin(am), 0.0)
    return (-w[0], -w[1], 0.0) if inward else w


BAR_H     = 1.25   # solid parapet: stone from the floor up to the waist
BAR_TOP   = 1.25   # above the room floor -- clears the guard's 1.11 m jump


def _bar(m, ang0, span, z0, z1, depth, zone_outer, zone_inner, r=None):
    """The parapet across one opening: the wall itself continuing up, from
    RM_RIN (flush with the room wall) out to the notch's own outer face
    (flush with the opening's sill), not a bar in front of either.

    zone_outer is the throat-facing skin, zone_inner everything else. With
    an `_Rng` passed as `r`, the top edge gets the drum's own CH_JAG/CH_ZJAG
    jitter so it is not a CAD line; omitted (the collider) it stays a flat
    box of the same footprint.
    """
    a0, a1 = ang0, ang0 + span
    out = _radial(a0, a1)
    left = (RM_RIN * math.cos(a0), RM_RIN * math.sin(a0))
    right = (RM_RIN * math.cos(a1), RM_RIN * math.sin(a1))

    def pt(p, d, z):
        return (p[0] + out[0] * d, p[1] + out[1] * d, z)

    def top_z():
        return z1 + r.sf() * CH_ZJAG if r else z1

    def top_depth():
        return depth * (1.0 + r.sf() * CH_JAG) if r else depth

    li0, lo0 = m.v(pt(left, 0.0, z0)), m.v(pt(left, depth, z0))
    ri0, ro0 = m.v(pt(right, 0.0, z0)), m.v(pt(right, depth, z0))
    li1, ri1 = m.v(pt(left, 0.0, top_z())), m.v(pt(right, 0.0, top_z()))
    lo1 = m.v(pt(left, top_depth(), top_z()))
    ro1 = m.v(pt(right, top_depth(), top_z()))

    m.quad(li0, ri0, ri1, li1, (-out[0], -out[1], 0.0), zone_inner)  # room-facing
    m.quad(lo0, lo1, ro1, ro0, (out[0], out[1], 0.0), zone_outer)    # throat-facing
    m.quad(li1, ri1, ro1, lo1, (0.0, 0.0, 1.0), zone_inner)          # top
    m.quad(li0, lo0, ro0, ri0, (0.0, 0.0, -1.0), zone_inner)         # bottom

    tx, ty = right[0] - left[0], right[1] - left[1]
    tl = math.hypot(tx, ty)
    tx, ty = tx / tl, ty / tl
    m.quad(li0, li1, lo1, lo0, (-tx, -ty, 0.0), zone_inner)          # left end
    m.quad(ri0, ro0, ro1, ri1, (tx, ty, 0.0), zone_inner)            # right end


# =============================================================================
# THE COLUMN -- frozen
# =============================================================================

def _facet_bias(r):
    """Random radius jitter, HELD for runs of rings.

    Held, not resampled per ring: a value that changes every ring gives a
    wobbling melted candle, while holding it and then stepping gives a facet
    that ends in a hard break, which is what cleaved rock does.
    """
    bias = [[0.0] * JITTER_RINGS for _ in range(SIDES)]
    for i in range(SIDES):
        k = 0
        while k < JITTER_RINGS:
            run = r.i(*JAG_RUN)
            v = r.sf() * JAG
            for kk in range(k, min(k + run, JITTER_RINGS)):
                bias[i][kk] = v
            k += run
        bias[i][JITTER_RINGS - 1] = max(-TOP_JAG, min(TOP_JAG,
                                                      bias[i][JITTER_RINGS - 1]))
    return bias


def _drift(r):
    """Lateral wander of the column axis, then RE-CENTRED ON ITS OWN NECK.

    A perfectly straight axis reads as a turned column and no hoodoo stands
    plumb, so the axis takes a random walk. But the drum is built on the origin
    -- it has to be, because TowerSpawn and everything else measure from there
    -- and a column whose neck had wandered metres off it put the chamber
    visibly off-axis. Ryan: "centre the chamber on the column."

    Subtracting the NECK's drift from every ring is a RIGID TRANSLATION of the
    whole column: the approved silhouette is unchanged to the last decimal, the
    neck lands exactly under the drum, and the only thing that moves is the
    foot, which is buried in the pit floor.
    """
    out = []
    cx = cy = 0.0
    for k in range(JITTER_RINGS):
        t = RING_PROFILE[k][0] if k < RINGS else 1.0
        cx += r.sf() * DRIFT
        cy += r.sf() * DRIFT
        fade = 1.0 if t <= DRIFT_FADE else 1.0 - (t - DRIFT_FADE) / (1.0 - DRIFT_FADE)
        out.append((cx * fade, cy * fade))
    ox, oy = out[RINGS - 1]
    return [(x - ox, y - oy) for (x, y) in out]


def _column(r):
    """The eroded hoodoo, foot to neck. 12 sides, 6 rings, 140 triangles.

    THE ORDER OF THE THREE RNG DRAWS BELOW IS FROZEN. Reordering them
    reshuffles the LCG walk and rerolls the approved silhouette just as surely
    as changing the ring count would.
    """
    bias = _facet_bias(r)
    drift = _drift(r)
    ang = [2.0 * math.pi * (i + r.sf() * ANG_JAG) / SIDES for i in range(SIDES)]
    # The FOOT gets Z jitter but only downward: a level bottom rim is the one
    # horizontal line the model would otherwise have and it reads as a plinth,
    # while a foot that jittered upward would lift rock clear of the pit floor
    # it is meant to be continuous with. Ragged, always at or below the foot.
    zjit = [[0.0 if k == JITTER_RINGS - 1 else
             (-abs(r.sf()) * Z_JAG if k == 0 else r.sf() * Z_JAG)
             for k in range(JITTER_RINGS)] for _ in range(SIDES)]

    m = _Mesh()
    rings = []
    for k, (t, rp) in enumerate(RING_PROFILE):
        cx, cy = drift[k]
        z = height_of(t)
        rings.append([m.v((cx + rp * (1.0 + bias[i][k]) * math.cos(ang[i]),
                           cy + rp * (1.0 + bias[i][k]) * math.sin(ang[i]),
                           z + zjit[i][k])) for i in range(SIDES)])

    for k in range(RINGS - 1):
        t = 0.5 * (RING_PROFILE[k][0] + RING_PROFILE[k + 1][0])
        for i in range(SIDES):
            j = (i + 1) % SIDES
            b = 0.5 * (bias[i][k] + bias[i][k + 1])
            if b < EMBER_BIAS and t < EMBER_TOP_T:
                zone = ZONE_EMBER          # a natural cleft, low down
            elif b < SHADE_BIAS:
                zone = ZONE_SHADE          # recessed facet: the contrast
            else:
                zone = ZONE_ROCK
            m.quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i],
                   _radial(ang[i], ang[i] + 2.0 * math.pi / SIDES), zone)

    # Caps. The top one is the neck's sheared face, which shows as a narrow
    # rock shelf around the foot of the drum, so it takes the dressed-stone
    # zone; the bottom is buried in the pit floor.
    top, bot = rings[RINGS - 1], rings[0]
    for i in range(1, SIDES - 1):
        m.tri(top[0], top[i], top[i + 1], (0.0, 0.0, 1.0), ZONE_CARVE)
        m.tri(bot[0], bot[i], bot[i + 1], (0.0, 0.0, -1.0), ZONE_SHADE)
    return m


# =============================================================================
# THE DRUM -- approved exterior, hollowed
# =============================================================================

def _chamber(r):
    n = CH_RINGS
    k0, k1 = CH_OPEN_RINGS
    # FROZEN DRAW ORDER, exactly as the approved model. Three arrays, in this
    # sequence, sized by these loops.
    ang = [2.0 * math.pi * (i + r.sf() * CH_ANG_JAG) / CH_SIDES
           for i in range(CH_SIDES)]
    jit = [[r.sf() * CH_JAG for _ in range(n)] for _ in range(CH_SIDES)]
    zj = [[0.0 if k in (0, n - 1) else r.sf() * CH_ZJAG for k in range(n)]
          for _ in range(CH_SIDES)]

    # Alternate vertices are openings. Only the rings between sill and lintel
    # are touched, so those two courses stay true circles.
    def offset(i, k):
        if not (k0 <= k <= k1):
            return 0.0
        return CH_OPEN_DEPTH if i % 2 == 0 else -CH_PIER_PROUD

    m = _Mesh()
    rings = []
    for k, (t, rp) in enumerate(CH_PROFILE):
        z = height_of(t)
        row = []
        for i in range(CH_SIDES):
            rr = rp * (1.0 + jit[i][k] - offset(i, k))
            row.append(m.v((rr * math.cos(ang[i]), rr * math.sin(ang[i]),
                            z + zj[i][k])))
        rings.append(row)

    step = 2.0 * math.pi / CH_SIDES

    # ---- outer skin --------------------------------------------------------
    # Identical to the approved model everywhere except the one band that holds
    # the openings, where each ramp face is cut back to its midpoint so the
    # bottom of every notch becomes a void. The half that survives is the half
    # against the pier, which is the half you actually see; the half removed
    # was the deepest, darkest part of the notch and now reads as the hole it
    # always looked like.
    cut = {}
    for k in range(n - 1):
        band_is_open = (k0 <= k and k + 1 <= k1)
        for i in range(CH_SIDES):
            j = (i + 1) % CH_SIDES
            zone = ZONE_EMBER if (i % 2 == 0 and band_is_open) else ZONE_CARVE
            want = _radial(ang[i], ang[i] + step)
            if not band_is_open:
                m.quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i],
                       want, zone)
                continue
            # Exactly one end of this face is a notch vertex and the other is
            # a pier. Cut RM_CUT of the way ALONG THE FACE FROM THE NOTCH --
            # which is RM_CUT for an even face and 1 - RM_CUT for an odd one,
            # because the notch is at the far end there. Getting that
            # asymmetry wrong is silent and expensive: keeping RM_CUT from the
            # wrong end leaves RM_CUT + (1 - RM_CUT) of face removed either
            # side of every notch, so the breach is exactly one side wide
            # WHATEVER RM_CUT is set to, and turning the dial changes nothing
            # in the render. That is what happened on the first hollowing.
            u = RM_CUT if i % 2 == 0 else 1.0 - RM_CUT
            lo = m.lerp(rings[k][i], rings[k][j], u)
            hi = m.lerp(rings[k + 1][i], rings[k + 1][j], u)
            cut[i] = (lo, hi)
            if i % 2 == 0:               # vertex i is the notch, j is the pier
                m.quad(lo, rings[k][j], rings[k + 1][j], hi, want, zone)
            else:                        # vertex i is the pier, j is the notch
                m.quad(rings[k][i], lo, hi, rings[k + 1][i], want, zone)

    # ---- caps --------------------------------------------------------------
    top, bot = rings[n - 1], rings[0]
    for i in range(1, CH_SIDES - 1):
        m.tri(top[0], top[i], top[i + 1], (0.0, 0.0, 1.0), ZONE_CARVE)
        m.tri(bot[0], bot[i], bot[i + 1], (0.0, 0.0, -1.0), ZONE_SHADE)

    # ---- inner shell -------------------------------------------------------
    # ITS VERTICES SIT ON THE CUT BEARINGS, not on a regular polygon. That is
    # what keeps the throat honest at any RM_CUT: the reveal then runs straight
    # out along a radius instead of splaying one way or the other, and the
    # opening is the same width inside as out. An earlier version used a plain
    # sixteen-gon at the midpoint angles, which was exactly right at RM_CUT =
    # 0.50 and wrong everywhere else -- widen the piers' gaps past that and the
    # throat starts CONVERGING inward, which quietly narrows the guard's field
    # of fire while looking fine from outside.
    iang = []
    for i in range(0, CH_SIDES, 2):
        for vid in (cut[(i - 1) % CH_SIDES][0], cut[i][0]):
            x, y, _z = m.verts[vid]
            iang.append(math.atan2(y, x))
    # Index 2k is the left edge of notch 2k and 2k+1 its right edge, so the
    # span between an even index and the next is a HOLE and the span between an
    # odd index and the next is a PIER.
    nin = len(iang)
    levels = [0.0, height_of(CH_PROFILE[k0][0]), height_of(CH_PROFILE[k1][0]),
              ROOM_CEIL]
    inner = [[m.v((RM_RIN * math.cos(a), RM_RIN * math.sin(a), z))
              for a in iang] for z in levels]

    for b in range(1, 3):          # floor is at sill level: no band below it
        for p in range(nin):
            if b == 1 and p % 2 == 0:
                continue                 # this span IS the opening
            q = (p + 1) % nin
            m.quad(inner[b][p], inner[b][q], inner[b + 1][q], inner[b + 1][p],
                   _radial(iang[p], iang[p] + (iang[q] - iang[p]) % (2.0 * math.pi),
                           inward=True), ZONE_SHADE)

    for i in range(1, nin - 1):
        m.tri(inner[1][0], inner[1][i], inner[1][i + 1], (0.0, 0.0, 1.0),
              ZONE_SHADE)               # floor: the guard stands here
        m.tri(inner[3][0], inner[3][i], inner[3][i + 1], (0.0, 0.0, -1.0),
              ZONE_SHADE)               # ceiling

    # ---- the throats -------------------------------------------------------
    # The stone left between the inner shell's hole and the outer notch. Five
    # sided top and bottom -- the outer rim is a V through the notch vertex,
    # the inner rim a straight chord -- so each is fanned into three triangles,
    # and the two jambs are quads.
    for k, i in enumerate(range(0, CH_SIDES, 2)):
        cl_lo, cl_hi = cut[(i - 1) % CH_SIDES]     # cut point on the left ramp
        cr_lo, cr_hi = cut[i]                      # ...and on the right ramp
        p_lo, p_hi = rings[k0][i], rings[k1][i]    # the notch vertex itself
        il_lo, ir_lo = inner[1][2 * k], inner[1][2 * k + 1]
        il_hi, ir_hi = inner[2][2 * k], inner[2][2 * k + 1]
        for (il, ir, cl, cr, pv, want) in (
                (il_lo, ir_lo, cl_lo, cr_lo, p_lo, (0.0, 0.0, 1.0)),
                (il_hi, ir_hi, cl_hi, cr_hi, p_hi, (0.0, 0.0, -1.0))):
            m.tri(il, ir, cr, want, ZONE_SHADE)
            m.tri(il, cr, pv, want, ZONE_SHADE)
            m.tri(il, pv, cl, want, ZONE_SHADE)
        a_l, a_r = iang[2 * k], iang[2 * k + 1]
        m.quad(il_lo, il_hi, cl_hi, cl_lo,
               (-math.sin(a_l), math.cos(a_l), 0.0), ZONE_SHADE)
        m.quad(ir_lo, ir_hi, cr_hi, cr_lo,
               (math.sin(a_r), -math.cos(a_r), 0.0), ZONE_SHADE)

    # ---- waist bars ----------------------------------------------------
    # The wall itself, carried up across each opening's clear width to the
    # waist, not a bar hung in front of it: same depth as the throat, from
    # RM_RIN out to the notch's outer face. Stone, not a wall put up.
    floor_z = levels[1]
    throat = CH_PROFILE[k0][1] * (1.0 - CH_OPEN_DEPTH) - RM_RIN
    for p in range(0, nin, 2):
        span = (iang[p + 1] - iang[p]) % (2.0 * math.pi)
        _bar(m, iang[p], span, floor_z, floor_z + BAR_TOP, throat,
             ZONE_CARVE, ZONE_SHADE, r)

    hole = (iang[1] - iang[0]) % (2.0 * math.pi)
    pier = (iang[2] - iang[1]) % (2.0 * math.pi)
    MEASURED.update(hole_deg=math.degrees(hole), pier_deg=math.degrees(pier),
                    clear_m=2.0 * RM_RIN * math.sin(0.5 * hole))
    return m, _collider(iang, levels[1], throat)


MEASURED = {}          # filled by _chamber: the numbers MDL STATS reports


def _collider(iang, sill_z, depth):
    """PURPOSE-BUILT COLLISION, shipped inside the .glb as a `-colonly` node.

    THE ROCK MUST NOT BE ITS OWN COLLIDER. Every surface on this model is
    deliberately jittered -- non-planar quads, ragged rings, a V-notched wall,
    a five-sided reveal round every throat -- and a trimesh taken from that is
    a field of invisible lips and creases for a capsule to catch on. Shipped
    that way it read in game as the guard snagging on nothing and sticking in
    the openings. What follows is FORTY-SIX TRIANGLES of flat surfaces that
    agree with what the eye sees and have none of the noise:

      * a flat floor disc on the same cut bearings as the inner shell, so its
        rim lands exactly on the wall with no sliver of gap to drop into;
      * ONE FULL-HEIGHT QUAD PER PIER at the inner wall's own radius, so the
        guard slides along the stone they can actually see;
      * ONE KERB QUAD PER OPENING, floor to the model's own sill height and no
        higher. Everything above it is empty, so a shot and a sightline both
        leave cleanly -- an invisible pane any taller would eat the bullet the
        player just watched leave the barrel, which is the bug this is meant
        to prevent, not cause.
      * ONE WAIST-BAR BOX PER OPENING, matching the visible one in `_chamber`,
        so the guard cannot walk or jump (1.11 m) through the gap the kerb
        leaves open above it.

    NO COLLISION BELOW THE ROOM AND NONE ON THE COLUMN, deliberately. Nothing
    ever walks there: bentham_ring.tscn's KillVolume roof is at y = -3 and
    converts anything that falls past it, so the courtyard floor and the
    tower's flanks are unreachable. A shell there would only be more surface
    for a falling body to catch on.

    NO CEILING either -- the tuned MovementProfile jumps 1.11 m and the ceiling
    is over six metres up.
    """
    c = _Mesh()
    n = len(iang)
    floor = [c.v((RM_RIN * math.cos(a), RM_RIN * math.sin(a), sill_z)) for a in iang]
    for i in range(1, n - 1):
        c.tri(floor[0], floor[i], floor[i + 1], (0.0, 0.0, 1.0), ZONE_SHADE)
    for p in range(n):
        q = (p + 1) % n
        if p % 2 == 0:
            continue                 # opening: floor runs straight out, no kerb
        top = ROOM_CEIL
        a, b = iang[p], iang[q]
        hp = c.v((RM_RIN * math.cos(a), RM_RIN * math.sin(a), top))
        hq = c.v((RM_RIN * math.cos(b), RM_RIN * math.sin(b), top))
        c.quad(floor[p], floor[q], hq, hp,
               _radial(a, a + (b - a) % (2.0 * math.pi), inward=True), ZONE_SHADE)
    for p in range(0, n, 2):
        span = (iang[p + 1] - iang[p]) % (2.0 * math.pi)
        _bar(c, iang[p], span, sill_z, sill_z + BAR_TOP, depth,
             ZONE_SHADE, ZONE_SHADE)
    return c


# =============================================================================
# UV
# =============================================================================

def unwrap(ob, zones, seed=0):
    """Per-face planar projection into a random window of that face's zone.

    Every face is projected on its own dominant axis and dropped somewhere in
    its 64x64 zone, with a random mirror in each direction. No shared UV space
    between faces means no seam to reason about and no unwrap to maintain, and
    the random window plus mirror is what stops big facets all showing the same
    few texels. The zones carry no directional pattern, so no orientation of
    the window can betray one.
    """
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + seed * 7919 + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        u0, v0, u1, v1 = zones[pi]
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
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u,
                               v0 + UV_PAD + t * span_v)


# =============================================================================
# EXTRA RENDERS -- from inside, which mdl's rig cannot reach
# =============================================================================
# mdl solves its camera distance from the bounding box and aims at the box
# centre, so it can only ever stand outside the model looking in. The guard's
# whole experience of this asset is the other side of that wall. Cameras are
# aimed with a TRACK_TO constraint on an empty and never with a hand-computed
# rotation_euler, because docs/MODELLING.md records what hand-aimed cameras
# cost the last person who tried.
#
# The light rig is the ARENA's, not the studio's: one steep red sun matching
# bentham_ring.tscn's KeyLight (-75 deg about X, colour 1.0/0.36/0.28) over a
# dim red ambient. Judging an interior under a neutral three-point setup would
# say nothing about the game.

OPEN_BEARING = 0.0      # filled in by build(): the bearing of one opening


def _interior_render(spec, objects):
    scene = bpy.context.scene
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
    bg.inputs[1].default_value = 0.45
    ld = bpy.data.lights.new("KeyRed", type="SUN")
    ld.energy = 3.4
    ld.color = (1.0, 0.36, 0.28)
    key = mdl._link(bpy.data.objects.new("KeyRed", ld))
    key.rotation_euler = (math.radians(-75.0), 0.0, 0.0)

    target = mdl._link(bpy.data.objects.new("InTarget", None))
    cam = mdl._link(bpy.data.objects.new("InCam", bpy.data.cameras.new("InCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"

    ux, uy = math.cos(OPEN_BEARING), math.sin(OPEN_BEARING)
    out_dir = spec.get("out_dir", ".")

    def shot(name, loc, tgt, lens, res):
        cam.data.lens = lens
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()      # the constraint has not solved yet
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    # A weak warm lamp for the room shot ONLY. The room is meant to be dark,
    # but a black rectangle would not show whether the inner shell, floor,
    # ceiling and throats were built inside-out, which is what this frame is
    # for.
    fl = bpy.data.lights.new("RoomFill", type="POINT")
    fl.energy = 700.0
    fl.color = (1.0, 0.55, 0.40)
    lamp = mdl._link(bpy.data.objects.new("RoomFill", fl))
    lamp.location = (-ux * 1.8, -uy * 1.8, 2.6)
    shot("room", (-ux * 4.3, -uy * 4.3, EYE_H + 0.3),
         (ux * 24.0, uy * 24.0, 1.2), 18.0, (1200, 900))
    bpy.data.objects.remove(lamp, do_unlink=True)

    # The gun port: eye height at the inner face, aimed down at a prisoner on
    # the ring. If this frame is looking at stone, the approved sill is too
    # high to shoot past and that is a decision for Ryan, not a thing to fix
    # here by resizing his openings.
    shot("gunport", (ux * (RM_RIN - 0.5), uy * (RM_RIN - 0.5), EYE_H),
         (ux * 34.0, uy * 34.0, -14.0), 26.0, (1200, 900))

    for ob in (cam, target, key):
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    global OPEN_BEARING
    col = _column(_Rng(TEX_SEED))
    cham, coll = _chamber(_Rng(CH_SEED))
    OPEN_BEARING = 0.0                   # chamber vertex 0 is an opening

    albedo, emissive = build_texture()
    out_dir = mdl._spec_from_argv().get("out_dir", ".")
    save_texture(albedo, out_dir)
    save_texture(emissive, out_dir)

    parts = []
    for k, (mesh, name) in enumerate(((col, "column"), (cham, "chamber"))):
        ob = mesh.object(name)
        unwrap(ob, mesh.zones, seed=k)
        parts.append(ob)

    ob = mdl.join(parts, OBJECT_NAME)
    mdl.finish(ob, rock_material("TowerRock", albedo, emissive), strip_uvs=False)

    # The collider rides in the same .glb. Godot's glTF importer reads the
    # suffix off the NODE NAME: `-colonly` turns the mesh into a StaticBody3D
    # with a ConcavePolygonShape3D and throws the mesh itself away, so it costs
    # nothing to draw, keeps `surfaces` at 1 for the contract, and -- the whole
    # point -- travels with the model instead of being rebuilt by hand in every
    # scene that uses it. hide_render keeps it out of the renders; the glTF
    # exporter still writes it, because it filters on selection rather than on
    # renderability.
    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons)))

    # Sightlines, computed rather than eyeballed, all in room-floor coordinates.
    # The limiting ray for shooting down leaves the eye and crosses the OUTER
    # lip of the sill -- the sill course ring, which is the last solid stone
    # outboard of the opening.
    k0, k1 = CH_OPEN_RINGS
    sill_z = height_of(CH_PROFILE[k0 - 1][0])
    sill_r = CH_PROFILE[k0 - 1][1]
    head_z = height_of(CH_PROFILE[k1 + 1][0])
    head_r = CH_PROFILE[k1 + 1][1]
    stand = RM_RIN - BODY_R
    down = math.degrees(math.atan2(EYE_H - sill_z, sill_r - stand))
    up = math.degrees(math.atan2(head_z - EYE_H, head_r - stand))
    open_h = height_of(CH_PROFILE[k1][0]) - height_of(CH_PROFILE[k0][0])
    open_w = MEASURED["clear_m"]

    print("MDL STATS height=%.2f room_floor_y=0.000 drum_top_y=%.3f foot_y=%.3f"
          % (HEIGHT, ROOM_LIFT, ROOM_LIFT - HEIGHT))
    print("MDL STATS room_dia=%.2f ceiling=%.2f headroom=%.2f body_fits=%s"
          % (2.0 * RM_RIN, ROOM_CEIL, ROOM_CEIL - BODY_H, ROOM_CEIL > BODY_H))
    print("MDL STATS openings=%d clear=%.2fm_wide x %.2fm_tall throat=%.2f"
          % (CH_SIDES // 2, open_w, open_h,
             CH_PROFILE[k0][1] * (1.0 - CH_OPEN_DEPTH) - RM_RIN))
    print("MDL STATS opening=%.1fdeg pier=%.1fdeg (ratio %.2f : 1)"
          % (MEASURED["hole_deg"], MEASURED["pier_deg"],
             MEASURED["hole_deg"] / MEASURED["pier_deg"]))
    print("MDL STATS sill_above_floor=%.2f eye=%.2f sightline down=%.1fdeg up=%.1fdeg"
          % (height_of(CH_PROFILE[k0][0]), EYE_H, down, up))
    print("MDL STATS uv_layers=%d atlas=%dx%d"
          % (len(ob.data.uv_layers), TEX_SIZE, TEX_SIZE))
    return [ob, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=0.0, post=_interior_render)
