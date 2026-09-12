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
LAVA_TEX       = 256
LAVA_ALBEDO    = "map_base_lava_albedo"
LAVA_EMISSIVE  = "map_base_lava_emissive"
LAVA_SEED      = 7720133
LAVA_REPEAT    = (12.0, 24.0)         # metres per repeat, drawn per face
LAVA_RINGS     = (1.0, 0.70, 0.42, 0.14)   # radius fractions of the pit foot
LAVA_PATCH     = 16.0                 # metres: faces in one patch share a UV window
LAVA_SWELL     = 0.6                  # +- metres of slow molten swell
LAVA_STEP      = 0.3                  # swell snaps to this: flat crust plates
LAVA_FLAT_R    = 18.0                 # level under the tower's foot

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


def _lava_density(n):
    """Seamless low-frequency crust mask: products of whole-cycle harmonics, so
    it wraps. 1 = plated over, 0 = open molten."""
    out = [0.0] * (n * n)
    for y in range(n):
        b = TWO_PI * y / n
        for x in range(n):
            a = TWO_PI * x / n
            v = (0.55 * math.sin(a + 0.9) * math.sin(b + 2.1)
                 + 0.30 * math.sin(2.0 * a - 1.4) * math.cos(2.0 * b + 0.3)
                 + 0.15 * math.cos(3.0 * b + 2.6) * math.sin(2.0 * a))
            out[y * n + x] = min(1.0, max(0.0, 0.5 + 0.75 * v))
    return out


def _lava_texture():
    """A seamless lava sheet: molten bed, dark crust plates, glowing fissures.
    Plate density rides a low-frequency mask, so the sheet has plated regions
    and open molten regions instead of one even crust everywhere."""
    c = _Canvas(LAVA_TEX)
    r = _Rng(LAVA_SEED)
    n = LAVA_TEX
    dens = _lava_density(n)

    def blot(x, y, w, h, rgb, glow):
        for dy in range(h):
            for dx in range(w):
                c.put((x + dx) % n, (y + dy) % n, rgb, glow)

    hot = [(226, 70, 10), (255, 104, 20), (206, 52, 6), (255, 132, 30)]
    for y in range(n):                                   # molten bed: all emits
        for x in range(n):
            s = r.pick(hot)
            c.put(x, y, s, s)
    crust = [(26, 9, 8), (38, 14, 11), (17, 6, 6), (48, 20, 15)]
    for _ in range(360):                                 # plates: 85 % .. 15 % cover
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        if r.f() > min(1.0, max(0.05, (dens[y * n + x] - 0.30) / 0.35)):
            continue
        w, h = r.i(8, 30), r.i(8, 30)
        sh = r.pick(crust)
        blot(x, y, w, h, sh, (0, 0, 0))
        for _ in range(3):                               # break the square outline
            blot((x + r.i(-4, w - 4)) % n, (y + r.i(-4, h - 4)) % n,
                 r.i(5, 14), r.i(5, 14), sh, (0, 0, 0))
    for _ in range(420):                                 # cooling flecks on the plates
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        if dens[y * n + x] < 0.45:
            continue
        blot(x, y, r.i(2, 5), r.i(2, 5), (60, 22, 14), (24, 4, 1))
    for _ in range(150):                                 # fissures: hot, thin, wandering
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        if dens[y * n + x] < 0.50:
            continue
        for _step in range(50):
            sh = r.pick(hot)
            c.put(x % n, y % n, sh, sh)
            c.put((x + 1) % n, y % n, sh, sh)
            x += r.i(-1, 1)
            y += r.i(-1, 1)
    for _ in range(40):                                  # white-hot pools, open water only
        x, y = r.i(0, n - 1), r.i(0, n - 1)
        if dens[y * n + x] > 0.26:
            continue
        core = r.pick([(255, 214, 96), (255, 178, 60)])
        for _step in range(18):                          # a walked blob, not a square
            blot(x, y, r.i(3, 6), r.i(3, 6), core, (255, 200, 80))
            x += r.i(-3, 3)
            y += r.i(-3, 3)
    images = []
    for name, buf in ((LAVA_ALBEDO, c.alb), (LAVA_EMISSIVE, c.emi)):
        img = bpy.data.images.new(name, LAVA_TEX, LAVA_TEX, alpha=False)
        img.colorspace_settings.name = "sRGB"
        img.pixels.foreach_set(buf)
        img.update()
        images.append(img)
    return images[0], images[1]


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

    def _emit(self, idx, want, zone):
        pts = [self.verts[j] for j in idx]
        n = _newell(pts)
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        if len(idx) == 4:
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


def _lava_sea(m, wall, z, r):
    """The floor of the shaft, as a sea of lava. Concentric rings down from the
    wall's own foot vertices (so the seam is shared) to the centre; the rings
    swell on two low harmonics of theta, level again under the tower's foot."""
    n = len(wall.ang)
    nu = wall.nu
    cols = [wall.cols[i * nu + su] for i in range(n) for su in range(nu)]
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
# THE ROCK
# =============================================================================

def _rock(r):
    m = _Mesh()
    ang = [2.0 * math.pi * (i + r.sf() * ANG_JAG) / SIDES for i in range(SIDES)]

    # ---- pit wall: courtyard up to the deck lip. Rings are level (their
    # radius steps, like cleaved rock) so a cell mouth is a rectangle in
    # (theta, z) and cuts cleanly across facet boundaries.
    pit_z = [COURTYARD_Z] + sorted(PIT_RINGS_Z) + [DECK_Z]
    npit = len(pit_z)
    pbias = _held(r, npit, PIT_JAG, one_sided=False)
    for i in range(SIDES):
        pbias[i][npit - 1] = 0.0                # the lip is exactly INNER_R
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

    # ---- the lava sea: what the pit floor is, and what lights it ------------
    _lava_sea(m, pit_wall, COURTYARD_Z, _Rng(LAVA_SEED))

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

    for k in range(nwall - 1):
        m.band(wall[k], wall[k + 1], ang, True, wall_zone(k),
               nu=ANG_SUB, nv=_nv(wall_z[k + 1] - wall_z[k]))

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

    # ---- deck and ceiling: flat annuli sharing the lips' vertices ------------
    deck_nv = _nv(OUTER_R - INNER_R)
    for i in range(SIDES):
        j = (i + 1) % SIDES
        a = ang[i]
        b = ang[i + 1] if i + 1 < SIDES else ang[0] + TWO_PI
        ts = [a + (b - a) * su / ANG_SUB for su in range(ANG_SUB + 1)]
        for t in ts[1:-1]:
            pit_wall.add_xt(len(pit_wall.rows) - 1, t)
            shaft.add_xt(0, t)
        _grid(m, pit[npit - 1][i], pit[npit - 1][j], wall[0][j], wall[0][i], UP, ZONE_DECK,
              ANG_SUB, deck_nv, edge_ab=[pit_wall.W(t, DECK_Z) for t in ts])
        _grid(m, upper[0][i], upper[0][j], wall[nwall - 1][j], wall[nwall - 1][i],
              (0.0, 0.0, -1.0), ZONE_ROCK, ANG_SUB, deck_nv, edge_ab=[shaft.W(t, CEIL_Z) for t in ts])

    # ---- the cells, then the faces they were cut from -------------------------
    for c in _place_cells(_Rng(CELL_SEED), pit_wall, shaft):
        _carve(m, pit_wall if c["z"] < DECK_Z else shaft, c)
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
    return m, ang


# =============================================================================
# COLLISION -- flat deck, clean walls, courtyard floor. Nothing jittered.
# =============================================================================

def _collider(ang):
    c = _Mesh()
    lip = _ring(c, ang, lambda i: INNER_R, lambda i: DECK_Z)
    foot = _ring(c, ang, lambda i: OUTER_R, lambda i: DECK_Z)
    pit_foot = _ring(c, ang, lambda i: INNER_R, lambda i: COURTYARD_Z)
    head = _ring(c, ang, lambda i: OUTER_R, lambda i: CEIL_Z)
    ceil_lip = _ring(c, ang, lambda i: INNER_R, lambda i: CEIL_Z)
    for i in range(SIDES):
        j = (i + 1) % SIDES
        c.quad(lip[i], lip[j], foot[j], foot[i], UP, ZONE_ROCK)        # deck
        c.quad(ceil_lip[i], ceil_lip[j], head[j], head[i],
               (0.0, 0.0, -1.0), ZONE_SHADE)                           # ceiling
    c.band(pit_foot, lip, ang, True, lambda i: ZONE_SHADE)             # pit wall
    c.fan(pit_foot, UP, ZONE_SHADE)                                    # courtyard
    c.band(foot, head, ang, True, lambda i: ZONE_ROCK)                 # outer wall
    return c


# =============================================================================
# UV -- per-face planar projection into a random window of its zone
# =============================================================================

def _lava_uv(me, uvl, poly):
    """The sea is cut into LAVA_PATCH-metre patches; each takes its own window
    of the sheet -- quarter-turn rotation, mirror, offset, 12..24 m per repeat.
    The sheet is toroidal, so every one of those is still seamless, and the sea
    repeats nowhere. Faces in a patch share the window, so the floor does not
    break up face by face."""
    cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
    cx = sum(c[0] for c in cos) / len(cos)
    cy = sum(c[1] for c in cos) / len(cos)
    key = (int(math.floor(cx / LAVA_PATCH)) + 512) * 1021 + int(math.floor(cy / LAVA_PATCH)) + 512
    q = _Rng(LAVA_SEED + key * 7919)
    for _ in range(4):
        q.n()
    k = 1.0 / (LAVA_REPEAT[0] + q.f() * (LAVA_REPEAT[1] - LAVA_REPEAT[0]))
    turns = q.i(0, 3)
    mir = -1.0 if q.i(0, 1) else 1.0
    ou, ov = q.f(), q.f()
    for li, co in zip(poly.loop_indices, cos):
        u, v = mir * co[0] * k, co[1] * k
        for _ in range(turns):
            u, v = -v, u
        uvl.data[li].uv = (ou + u, ov + v)


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
    rock, ang = _rock(_Rng(SEED))
    coll = _collider(ang)

    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    lava_albedo, lava_emissive = _lava_texture()
    mdl.save_texture(lava_albedo)
    mdl.save_texture(lava_emissive)

    ob = rock.object(OBJECT_NAME)
    unwrap(ob, rock.zones)
    mdl.finish(ob, rock_material("HellRock", albedo, emissive), strip_uvs=False)
    ob.data.materials.append(rock_material("LavaSea", lava_albedo, lava_emissive))
    lava_tris = 0
    for pi, poly in enumerate(ob.data.polygons):
        if rock.zones[pi][0] == "lava":
            poly.material_index = 1
            lava_tris += 1

    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d lava_tris=%d deck_uv=%.2f"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), lava_tris, DECK_UV_SCALE))
    print("MDL STATS cells=%d pit=%d pit_top=%.1f uniform_to=%.0f above200=%d top=%.0f"
          % (len(CELLS), sum(1 for c in CELLS if c[0][2] < DECK_Z),
             max(c[0][2] + 0.5 * c[3] for c in CELLS if c[0][2] < DECK_Z), UNIFORM_TOP,
             sum(1 for c in CELLS if c[0][2] > 200.0), max(c[0][2] for c in CELLS)))
    print("MDL STATS deck r=%.1f..%.1f y=%.2f courtyard_y=%.2f ceiling_y=%.2f rim_y=%.1f ground_r=%.0f"
          % (INNER_R, OUTER_R, DECK_Z, COURTYARD_Z, CEIL_Z, RIM_Z, GROUND_RINGS[-1][0]))
    return [ob, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_deck_render)
