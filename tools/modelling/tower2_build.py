"""
PANOPTICON -- tower2: a second look at the tower, built as ONE MASS.

The first tower (tower_build.py) is a column with a drum set on it: plinth,
sill course, piers, lintel, gallery lip, cap. Ryan: "the room on top looks
like it was placed there, and the rail and columns look like they were added
to hold the roof, as opposed to the whole thing looking like it was carved out
of the ground." This file does not touch that model. It is a from-scratch
alternative to look at beside it.

THE IDEA
--------
One hoodoo, foot to crown, one ring profile, one jittered skin. The column
simply keeps going; near the top it swells a little (a hoodoo's harder cap
rock) and rounds off into a broken crown. The guard's room is a CAVITY in that
head: an inner shell, a floor and a ceiling hollowed out of the mass. The
eight openings are holes punched through the wall between cavity and skin --
each an eight-sided ragged polygon of its own width, sill and head, lined with
reveal faces. Everything a mason would call a part is here only as rock that
was NOT removed:

    parapet  = the wall below each hole, left uncut; its inner sill is at
               about 1.0 m so a standing guard shoots down over it and does
               not walk out, and its outer lip is cut lower so the shot clears
    columns  = the rock between two neighbouring holes. Each hole is widest at
               mid-height, so what is left between them is thick at the sill
               and thick at the head and flows into the mass both ways
    roof     = the three metres of rock over the ceiling, ending in the crown

No horizontal course anywhere: every ring is z-jittered, the sill and head of
every opening are different heights, and the room's own floor and ceiling are
the only level surfaces and are not visible from outside.

ORIGIN -- (0, 0, 0) IS THE ROOM'S FLOOR, as for tower.glb
-----------------------------------------------------------
    room floor ........  y =  0.00     (TowerSpawn lands 0.25 m above it)
    top of the crown ..  y = +CROWN_Z  (the "drum top" of the first tower)
    foot of the column   y =  FOOT_Z

Coordinates are Blender space (Z up) and glTF-exported to Godot (Y up).

Run (from the Mac, from the repo root)::

    tools/modelling/model build tower2 --views threequarter,lowangle

`_interior_render` adds tower2_room.png (the guard's room from within) and
tower2_gunport.png (eye at an opening, aimed down) -- mdl's own rig solves
its camera from the bounding box and can only stand outside.

Winding: every face goes through `_Mesh._emit` with the direction its normal
must point, and the winding is flipped if the Newell normal disagrees. The
inner shell faces INWARD; a backwards face is invisible from inside the room
and nothing but that check warns you.

Texturing is the HellRock atlas from tower_build.py, copied verbatim (the
pipeline ships one script per model): 128x128, four zones, nearest filtering,
emissive only in the ember zone.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# Same rig override as tower_build.py: the model hangs 36 m below its origin,
# so mdl's ground plane would sit under the lowangle camera and the frame
# would come back black. No plane; the world does the fill.
mdl.DEFAULTS["ground"] = False
mdl.DEFAULTS["world_grey"] = 0.30
mdl.DEFAULTS["world_strength"] = 0.90

# =============================================================================
# TUNABLES -- everything adjustable lives in this block
# =============================================================================

NAME = "tower2"          # -> assets/models/tower2.glb
OBJECT_NAME = "Tower2Rock"
COLLIDER_NAME = "Tower2Collision-colonly"

FOOT_Z  = -36.5          # metres below the room floor; matches tower.glb
CROWN_Z = 7.6            # apex of the crown above the room floor

# ---- THE ONE PROFILE, foot to crown: (z metres from the room floor, radius)
# One entry per ring, no interpolation. It pinches and swells like the
# approved column, then swells once more into the head and rounds off. The
# three rings marked OPEN carry the openings; their z is the nominal level and
# every opening moves its own sill, waist and head off it.
SILL_Z = 1.05            # nominal inner sill: shoot over it, do not walk out
MID_Z  = 2.3             # the waist of each hole -- its widest point
HEAD_Z = 3.5             # nominal head of each hole
CEIL_Z = 4.6             # the room's ceiling; 3.8 m of rock above it

PROFILE = [
    (FOOT_Z, 10.0),      # foot -- buried in the pit floor
    (-31.0,   9.4),
    (-24.0,  10.3),      # one slight swell
    (-16.5,   7.5),      # THE pinch
    (-10.0,   8.9),      # modest swell
    ( -4.8,   7.9),      # the neck, such as it is: 0.9 m in, over 6 m
    ( -1.2,   8.2),      # the head begins to swell -- the cap rock
    (SILL_Z,  8.7),      # OPEN: sill ring
    (MID_Z,   8.8),      # OPEN: waist ring
    (HEAD_Z,  8.7),      # OPEN: head ring
    (  5.3,   8.4),      # the cap keeps its width: a block, not a ball
    (  6.5,   7.3),      # chamfer
    (  7.2,   4.8),      # crown ring; a broken near-flat fan closes it
]
K_SILL, K_MID, K_HEAD = 7, 8, 9

SIDES = 24               # 8 openings x (two hole sides + one pier side)
N_OPEN = 8

# Skin jitter. Radial jitter is HELD for runs of rings so a facet ends in a
# hard break (cleaved rock), never resampled per ring (a melted candle).
JAG       = 0.130
JAG_RUN   = (2, 4)
ANG_JAG   = 0.36         # even columns, as a fraction of their 30-degree
ANG_JAG_ODD = 0.25       # pitch; odd columns sit between their neighbours
                         # +/- this fraction of the half-gap, so columns never
                         # cross. Held for the whole height: vertical edges
                         # stay vertical
Z_JAG     = 0.85
Z_FOLD    = 0.35         # z jitter never exceeds this fraction of the gap to
                         # the next ring, so no ring folds through another
DRIFT     = 1.60         # axis wander per ring, faded out into the head so
DRIFT_LO  = -12.0        # the room lands on the origin
DRIFT_HI  = 1.5 
PAIR_LO   = -10.0        # below this the 24 columns are paired into 12
PAIR_HI   = -2.0         # coplanar facets (the approved column's chunkiness);
                         # above it every column jitters on its own
SEED      = 7710223

# ---- THE OPENINGS -----------------------------------------------------------
# Angular widths in degrees at each open ring, drawn per opening. Pitch is 45
# degrees, so the pier between two holes is what is left over.
W_SILL  = (20.0, 26.0)   # narrow at the bottom: the pier is thick at its base
W_MID   = (24.0, 31.0)   # widest at the waist
W_HEAD  = (21.0, 28.0)   # narrows again into the roof
CENTRE_JAG  = 4.0        # each opening's bearing off its 45-degree slot
MID_ANG_JAG = 5.0        # the middle column of a hole wanders this much
SILL_DZ  = 0.10          # each jamb's inner sill off SILL_Z
SILL_NOTCH = 0.20        # the sill's middle vertex drops up to this: a V
MID_DZ   = 0.30
HEAD_DZ  = 0.30
HEAD_PEAK = 0.50         # the head's middle vertex rises up to this
SILL_SLOPE = 0.70        # the OUTER lip of the sill sits this far below the
                         # inner one: the shot leaves downhill
HEAD_SPLAY = 0.30        # the outer head is this much higher than the inner
ANG_SPLAY  = 3.0         # the outer hole is this many degrees wider
MID_KINK   = 0.25        # the waist vertex of a jamb kinks in/out (metres)

# ---- THE ROOM ---------------------------------------------------------------
RM_RIN = 6.5             # 13.0 m across; 2.1 m of wall at the sill ring

EYE_H  = 1.65            # the guard, for the interior renders and the
BODY_H = 1.80            # sightline arithmetic in MDL STATS
BODY_R = 0.40

# ---- material / texture (HellRock atlas, as tower_build.py) ------------------
TEX_SIZE      = 128
TEX_ALBEDO    = "tower2_rock_albedo"
TEX_EMISSIVE  = "tower2_rock_emissive"
TEX_SEED      = 6661031
ROCK_ROUGHNESS = 0.95
ROCK_METALLIC  = 0.0
UV_SCALE      = 0.13
UV_PAD        = 1.5 / TEX_SIZE

ZONE_ROCK   = (0.0, 0.5, 0.5, 1.0)   # dark red rock, the body
ZONE_SHADE  = (0.5, 0.5, 1.0, 1.0)   # near-black: recessed facets, the room
ZONE_CARVE  = (0.5, 0.0, 1.0, 0.5)   # dressed stone: the reveals of the holes
ZONE_EMBER  = (0.0, 0.0, 0.5, 0.5)   # split open by brimstone, low down only

SHADE_BIAS  = -0.035
EMBER_BIAS  = -0.090
EMBER_TOP_Z = -14.0      # no clefts above this: the heat is below

FACING_YAW = 0.0         # the column has no front


# =============================================================================
# TEXTURE -- copied from tower_build.py; hand-written texels, no direction
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

    def fan(self, idx, want, zone):
        for k in range(1, len(idx) - 1):
            self._emit([idx[0], idx[k], idx[k + 1]], want, zone)

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


def _radial(ang_a, ang_b, inward=False):
    am = 0.5 * (ang_a + ang_b)
    w = (math.cos(am), math.sin(am), 0.0)
    return (-w[0], -w[1], 0.0) if inward else w


# =============================================================================
# THE ROCK -- one skin, foot to crown, with the room cut out of its head
# =============================================================================

NR = len(PROFILE)
OPEN_RINGS = (K_SILL, K_MID, K_HEAD)
MEASURED = {}            # filled by _rock: the numbers MDL STATS reports
OPEN_BEARING = 0.0       # bearing of opening 0, for the interior renders


def _lerp01(z, lo, hi):
    return max(0.0, min(1.0, (z - lo) / (hi - lo)))


def _rad(deg):
    return math.radians(deg)


def _tangent(a):
    """Direction of increasing bearing at bearing a (unit, horizontal)."""
    return (-math.sin(a), math.cos(a), 0.0)


def _facet_bias(r):
    """Radial jitter per column, HELD for runs of rings: cleaved, not melted."""
    bias = [[0.0] * NR for _ in range(SIDES)]
    for i in range(SIDES):
        k = 0
        while k < NR:
            run = r.i(*JAG_RUN)
            v = r.sf() * JAG
            for kk in range(k, min(k + run, NR)):
                bias[i][kk] = v
            k += run
    return bias


def _drift(r):
    """Axis wander, faded to nothing by DRIFT_HI so the head sits on the origin."""
    out = []
    cx = cy = 0.0
    for k in range(NR):
        cx += r.sf() * DRIFT
        cy += r.sf() * DRIFT
        fade = 1.0 - _lerp01(PROFILE[k][0], DRIFT_LO, DRIFT_HI)
        out.append((cx * fade, cy * fade))
    return out


def _openings(r):
    """Per opening: bearing, and per open ring its width, jamb z's, notch, peak."""
    ops = []
    for k in range(N_OPEN):
        def w(rng):
            return _rad(rng[0] + r.f() * (rng[1] - rng[0]))
        ops.append(dict(
            c=_rad(45.0 * k + r.sf() * CENTRE_JAG),
            w={K_SILL: w(W_SILL), K_MID: w(W_MID), K_HEAD: w(W_HEAD)},
            mid_ang=r.sf() * _rad(MID_ANG_JAG),
            sill=(SILL_Z + r.sf() * SILL_DZ, SILL_Z + r.sf() * SILL_DZ),
            notch=r.f() * SILL_NOTCH,
            mid=(MID_Z + r.sf() * MID_DZ, MID_Z + r.sf() * MID_DZ),
            head=(HEAD_Z + r.sf() * HEAD_DZ, HEAD_Z + r.sf() * HEAD_DZ),
            peak=r.f() * HEAD_PEAK,
            kink=(r.sf() * MID_KINK, r.sf() * MID_KINK)))
    return ops


def _open_ang(op, k, j, outer):
    """Bearing of column j (0 left jamb, 1 middle, 2 right jamb) at open ring k."""
    w = op["w"][k] + (_rad(ANG_SPLAY) if outer else 0.0)
    return (op["c"] - 0.5 * w, op["c"] + op["mid_ang"], op["c"] + 0.5 * w)[j]


def _open_z(op, k, j, outer):
    """Inner z of column j at open ring k; outer sill drops, outer head rises."""
    if k == K_SILL:
        z = min(op["sill"]) - op["notch"] if j == 1 else op["sill"][j // 2]
        return z - SILL_SLOPE if outer else z
    if k == K_HEAD:
        z = max(op["head"]) + op["peak"] if j == 1 else op["head"][j // 2]
        return z + HEAD_SPLAY if outer else z
    return op["mid"][j // 2]            # K_MID; j == 1 is never asked for


def _zone_of(b, z):
    if b < EMBER_BIAS and z < EMBER_TOP_Z:
        return ZONE_EMBER
    if b < SHADE_BIAS:
        return ZONE_SHADE
    return ZONE_ROCK


def _rock(r):
    global OPEN_BEARING
    bias = _facet_bias(r)
    drift = _drift(r)
    ang = [0.0] * SIDES
    for i in range(0, SIDES, 2):
        ang[i] = 2.0 * math.pi * (i + 2.0 * r.sf() * ANG_JAG) / SIDES
    for i in range(1, SIDES, 2):
        a, b = ang[i - 1], ang[(i + 1) % SIDES]
        half = 0.5 * ((b - a) % (2.0 * math.pi))
        ang[i] = a + half * (1.0 + r.sf() * ANG_JAG_ODD)
    ops = _openings(r)
    OPEN_BEARING = ops[0]["c"]

    def zamp(k):
        if k == 0:
            return Z_JAG                       # foot: only downward, below
        if k == NR - 1:
            return 0.8                         # crown ring: broken rim
        gap = min(PROFILE[k][0] - PROFILE[k - 1][0], PROFILE[k + 1][0] - PROFILE[k][0])
        return min(Z_JAG, Z_FOLD * gap)
    zj = [[(-abs(r.sf()) if k == 0 else r.sf()) * zamp(k) for k in range(NR)]
          for _ in range(SIDES)]

    m = _Mesh()

    # ---- outer skin vertices ----------------------------------------------
    rings = []
    for k, (z0, rp) in enumerate(PROFILE):
        cx, cy = drift[k]
        pts = []
        for i in range(SIDES):
            rr = rp * (1.0 + bias[i][k])
            if k in OPEN_RINGS:
                op, j = ops[i // 3], i % 3
                if k == K_MID and j == 1:
                    pts.append(None)           # inside the hole: no vertex
                    continue
                a = _open_ang(op, k, j, True)
                z = _open_z(op, k, j, True)
                if k == K_MID:
                    rr += op["kink"][j // 2]
            else:
                a = ang[i]
                z = z0 + zj[i][k]
            pts.append([cx + rr * math.cos(a), cy + rr * math.sin(a), z])
        # Pair the columns into 12 coplanar facets low down: each odd column
        # is pulled onto the chord between its neighbours by (1 - blend).
        blend = _lerp01(z0, PAIR_LO, PAIR_HI)
        if blend < 1.0:
            for i in range(1, SIDES, 2):
                p, q = pts[i - 1], pts[(i + 1) % SIDES]
                pts[i] = [0.5 * (p[c] + q[c]) * (1.0 - blend) + pts[i][c] * blend
                          for c in range(3)]
        rings.append([None if p is None else m.v(p) for p in pts])

    # ---- outer skin faces --------------------------------------------------
    for k in range(NR - 1):
        zmid = 0.5 * (PROFILE[k][0] + PROFILE[k + 1][0])
        for i in range(SIDES):
            j = (i + 1) % SIDES
            if k in (K_SILL, K_MID) and i % 3 != 2:
                continue                       # this is the hole
            a, b, c, d = rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]
            want = _radial(ang[i], ang[i] + 2.0 * math.pi / SIDES)
            m.quad(a, b, c, d, want, _zone_of(0.5 * (bias[i][k] + bias[i][k + 1]), zmid))

    # ---- crown and foot ----------------------------------------------------
    apex = m.v((0.0, 0.0, CROWN_Z))
    top = rings[NR - 1]
    for i in range(SIDES):
        m.tri(top[i], top[(i + 1) % SIDES], apex, (0.0, 0.0, 1.0), ZONE_ROCK)
    bot = rings[0]
    for i in range(1, SIDES - 1):
        m.tri(bot[0], bot[i], bot[i + 1], (0.0, 0.0, -1.0), ZONE_SHADE)

    # ---- the cavity: inner shell, floor, ceiling ----------------------------
    # Columns share the openings' inner bearings so every reveal runs straight
    # out from the room to the skin. Level order: floor, sill, mid, head, ceil.
    # Jambs sit at the waist width (the widest) so the inner wall is one
    # plane per column; the sill and head loops narrow only at their outer ends.
    iang = [_open_ang(ops[i // 3], K_MID, i % 3, False) for i in range(SIDES)]
    def ipt(i, z):
        return m.v((RM_RIN * math.cos(iang[i]), RM_RIN * math.sin(iang[i]), z))

    inner = {}                                 # (level, i) -> vertex
    for i in range(SIDES):
        op, j = ops[i // 3], i % 3
        inner[(0, i)] = ipt(i, 0.0)
        inner[(1, i)] = ipt(i, _open_z(op, K_SILL, j, False))
        if j != 1:
            inner[(2, i)] = ipt(i, _open_z(op, K_MID, j, False))
        inner[(3, i)] = ipt(i, _open_z(op, K_HEAD, j, False))
        inner[(4, i)] = ipt(i, CEIL_Z)

    def iwant(i, j):
        return _radial(iang[i], iang[i] + (iang[j] - iang[i]) % (2.0 * math.pi),
                       inward=True)

    for i in range(SIDES):
        j = (i + 1) % SIDES
        pier = i % 3 == 2
        bands = ((0, 1), (1, 2), (2, 3), (3, 4)) if pier else ((0, 1), (3, 4))
        for lo, hi in bands:
            m.quad(inner[(lo, i)], inner[(lo, j)], inner[(hi, j)], inner[(hi, i)],
                   iwant(i, j), ZONE_SHADE)
    floor = [inner[(0, i)] for i in range(SIDES)]
    ceil = [inner[(4, i)] for i in range(SIDES)]
    for i in range(1, SIDES - 1):
        m.tri(floor[0], floor[i], floor[i + 1], (0.0, 0.0, 1.0), ZONE_SHADE)
        m.tri(ceil[0], ceil[i], ceil[i + 1], (0.0, 0.0, -1.0), ZONE_SHADE)

    # ---- the holes: reveals from the inner loop out to the skin --------------
    # Loop order S0 S1 S2 M2 H2 H1 H0 M0, outer and inner alike; each quad's
    # normal must point INTO the hole (sill up, head down, jambs across).
    clear = []
    for k, op in enumerate(ops):
        i0, i1, i2 = 3 * k, 3 * k + 1, 3 * k + 2
        outer = [rings[K_SILL][i0], rings[K_SILL][i1], rings[K_SILL][i2],
                 rings[K_MID][i2], rings[K_HEAD][i2], rings[K_HEAD][i1],
                 rings[K_HEAD][i0], rings[K_MID][i0]]
        inr = [inner[(1, i0)], inner[(1, i1)], inner[(1, i2)],
               inner[(2, i2)], inner[(3, i2)], inner[(3, i1)],
               inner[(3, i0)], inner[(2, i0)]]
        tl, tr = _tangent(iang[i0]), _tangent(iang[i2])
        wants = [(0, 0, 1), (0, 0, 1),
                 (-tr[0], -tr[1], 0.0), (-tr[0], -tr[1], 0.0),
                 (0, 0, -1), (0, 0, -1),
                 tl, tl]
        for e in range(8):
            f = (e + 1) % 8
            m.quad(outer[e], outer[f], inr[f], inr[e], wants[e], ZONE_CARVE)
        clear.append(2.0 * RM_RIN * math.sin(0.5 * op["w"][K_MID]))

    MEASURED.update(
        clear_min=min(clear), clear_max=max(clear),
        sill_in_min=min(min(op["sill"]) - op["notch"] for op in ops),
        sill_in_max=max(max(op["sill"]) for op in ops),
        sill_out_max=max(max(op["sill"]) for op in ops) - SILL_SLOPE,
        head_in_min=min(min(op["head"]) for op in ops),
        pier_min_deg=min(360.0 / N_OPEN - math.degrees(max(op["w"].values())) for op in ops),
        z_min=min(v[2] for v in m.verts), z_max=max(v[2] for v in m.verts))
    return m, _collider(iang, ops)


def _collider(iang, ops):
    """PURPOSE-BUILT COLLISION, shipped in the .glb as a `-colonly` node.

    The jittered rock is never its own collider (a capsule catches on every
    crease). Flat surfaces that agree with what the eye sees: a floor disc on
    the inner bearings, one full-height quad per pier at the inner radius, and
    per opening a kerb from the floor to that opening's LOWEST inner sill and
    no higher, so nothing invisible eats a shot. No ceiling, nothing below the
    room, nothing on the flanks: nothing walks there.
    """
    c = _Mesh()

    def pt(i, z):
        return c.v((RM_RIN * math.cos(iang[i]), RM_RIN * math.sin(iang[i]), z))

    floor = [pt(i, 0.0) for i in range(SIDES)]
    for i in range(1, SIDES - 1):
        c.tri(floor[0], floor[i], floor[i + 1], (0.0, 0.0, 1.0), ZONE_SHADE)

    def wall(i, j, top):
        want = _radial(iang[i], iang[i] + (iang[j] - iang[i]) % (2.0 * math.pi),
                       inward=True)
        c.quad(floor[i], floor[j], pt(j, top), pt(i, top), want, ZONE_SHADE)

    for k, op in enumerate(ops):
        kerb = min(op["sill"]) - op["notch"]
        wall(3 * k, 3 * k + 1, kerb)
        wall(3 * k + 1, 3 * k + 2, kerb)
        wall(3 * k + 2, (3 * k + 3) % SIDES, CEIL_Z)
    return c


# =============================================================================
# UV -- per-face planar projection into a random window of the face's zone
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
# Cameras are aimed with a TRACK_TO constraint on an empty, never a hand-rolled
# rotation_euler (docs/MODELLING.md). The light is the ARENA's: one steep red
# sun like bentham_ring.tscn's KeyLight over a dim red ambient.

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

    # A weak warm lamp for the room shot only: the room is meant to be dark,
    # but a black frame would not show an inside-out shell.
    fl = bpy.data.lights.new("RoomFill", type="POINT")
    fl.energy = 700.0
    fl.color = (1.0, 0.55, 0.40)
    lamp = mdl._link(bpy.data.objects.new("RoomFill", fl))
    lamp.location = (-ux * 1.8, -uy * 1.8, 2.6)
    shot("room", (-ux * 4.3, -uy * 4.3, EYE_H + 0.3),
         (ux * 24.0, uy * 24.0, 1.2), 18.0, (1200, 900))
    bpy.data.objects.remove(lamp, do_unlink=True)

    # The gun port: eye height at the inner face, aimed down at the ring.
    shot("gunport", (ux * (RM_RIN - 0.5), uy * (RM_RIN - 0.5), EYE_H),
         (ux * 34.0, uy * 34.0, -14.0), 26.0, (1200, 900))

    for ob in (cam, target, key):
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    rock, coll = _rock(_Rng(SEED))

    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)

    ob = rock.object(OBJECT_NAME)
    unwrap(ob, rock.zones, seed=0)
    mdl.finish(ob, rock_material("HellRock", albedo, emissive), strip_uvs=False)

    # The collider rides in the same .glb: Godot reads `-colonly` off the node
    # name, makes a StaticBody3D + ConcavePolygonShape3D and drops the mesh.
    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons)))

    # Sightlines from the guard's eye, standing against the inner wall. The
    # limiting ray for shooting down crosses whichever lip is higher relative
    # to its distance: the inner sill or the outer lip.
    stand = RM_RIN - BODY_R
    r_out = PROFILE[K_SILL][1]
    down = min(math.degrees(math.atan2(EYE_H - MEASURED["sill_in_max"], RM_RIN - stand)),
               math.degrees(math.atan2(EYE_H - MEASURED["sill_out_max"], r_out - stand)))
    up = math.degrees(math.atan2(MEASURED["head_in_min"] - EYE_H, RM_RIN - stand))

    print("MDL STATS room_floor_y=0.000 crown_top_y=%.3f foot_y=%.3f height=%.2f"
          % (MEASURED["z_max"], MEASURED["z_min"], MEASURED["z_max"] - MEASURED["z_min"]))
    print("MDL STATS room_dia=%.2f ceiling=%.2f headroom=%.2f wall=%.2f"
          % (2.0 * RM_RIN, CEIL_Z, CEIL_Z - BODY_H, r_out - RM_RIN))
    print("MDL STATS openings=%d clear=%.2f..%.2fm sill_in=%.2f..%.2f head_in>=%.2f pier>=%.1fdeg"
          % (N_OPEN, MEASURED["clear_min"], MEASURED["clear_max"],
             MEASURED["sill_in_min"], MEASURED["sill_in_max"],
             MEASURED["head_in_min"], MEASURED["pier_min_deg"]))
    print("MDL STATS eye=%.2f sightline down=%.1fdeg up=%.1fdeg"
          % (EYE_H, down, up))
    print("MDL STATS uv_layers=%d atlas=%dx%d"
          % (len(ob.data.uv_layers), TEX_SIZE, TEX_SIZE))
    return [ob, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_interior_render)
