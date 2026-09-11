"""
PANOPTICON -- the map base: a hole in the ground of hell, cut from the same
dark red rock as the tower. ONE ring gallery round a central void; below the
deck's inner edge the pit drops to the courtyard floor the tower stands on;
the gallery is a CUTOUT: rock ceiling CEIL_H over the deck, open only toward
the void; above it the pit wall carries on to a ragged rim and hell's ground.

Rock only. No cover, traps, pits, pads, ramps or tower -- those are scene work.

Authored in WORLD coordinates so the scene instances it at identity:

    courtyard floor ..  y = COURTYARD_Z  (tower foot lands on it)
    deck surface .....  y = DECK_Z       (runner's feet; guard's eye level)
    gallery ceiling ..  y = CEIL_Z
    rim ..............  y = RIM_Z

Blender +Z -> Godot +Y, Blender +Y -> Godot -Z.

Collision is purpose-built and rides in the .glb as a `-colonly` node, as the
tower's does: flat deck, clean pit wall, courtyard disc, outer wall and flat
ceiling. The jittered rock mesh is NEVER its own collider.

Texture: the tower's atlas, same painter, same seed -- byte-identical, so
this reads as the rock the tower was cut from.

    tools/modelling/model look  map_base --cam 35,30,40
    tools/modelling/model build map_base --cam 35,30,40

Two hand-placed shots come back with every run: map_base_runner.png (eye on
the deck) and map_base_guard.png (from the void's centre at deck height).
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

# ---- prison cells: arched recesses with thin carved columns across the mouth
# Cells live on the vertical pit faces only (deck -> courtyard, and the shaft
# above the gallery ceiling). One cell at most per wall facet, so the facet's
# own four corners frame it and no T-junctions are made.
CELL_SEED   = 4420917
CELL_H      = (2.5, 4.5)      # mouth height, metres
CELL_ASPECT = (0.60, 0.85)    # width / height
CELL_W      = (2.0, 3.5)
CELL_DEPTH  = (2.0, 3.0)
CELL_TAPER  = 0.65            # back wall scale vs the mouth
CELL_MX     = 0.6             # rock left between the mouth and the facet edge
CELL_MY     = 0.6
LIP_OUT     = 0.45            # the drip shelf under the mouth
LIP_DROP    = 0.10
LIP_UNDER   = 0.45
BAR_PITCH   = 0.55            # nominal column spacing -> 4..7 columns
BAR_R       = (0.09, 0.14)    # 0.18..0.28 m thick
BAR_LEAN    = 0.06
BAR_FLARE   = 1.25            # top ring / bottom ring radius
BAR_SINK    = 0.6             # column axis this many radii behind the mouth plane
NEAR_Z      = 60.0            # below: 7-point arch, 5-sided columns; above: 5 / 4
CELL_RHO_PIT   = 0.0095       # cells per m^2, deck -> courtyard
CELL_RHO_SHAFT = 0.0075       # ... at the ceiling, decaying up the shaft
CELL_FALL      = 40.0         # e-folding height of that decay
PIT_SUB, PIT_CAP     = 2, 7.0     # pit wall facets ~4.6 x 5-7 m: a cell fits one
SHAFT_SUB, SHAFT_CAP = 2, 8.0     # same for the shaft below SHAFT_NEAR_Z
SHAFT_NEAR_Z = 105.0

CELLS = []                    # (centre, normal, up, width, height) for the renders

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

    def band(self, lo, hi, ang, inward, zone_fn, nu=1, nv=1, cell_fn=None):
        """Quads between two rings; zone_fn(i) picks the atlas zone per side.

        nu/nv grid each side's quad (bilinear on its own four corners, no new
        jitter) so no facet outgrows the atlas texel budget. cell_fn, if given,
        may claim a facet and carve a cell into it instead of the plain quad.
        """
        n = len(lo)
        for i in range(n):
            j = (i + 1) % n
            am = 0.5 * (ang[i] + ang[i] + 2.0 * math.pi / n)
            w = (math.cos(am), math.sin(am), 0.0)
            want = (-w[0], -w[1], 0.0) if inward else w
            _grid(self, lo[i], lo[j], hi[j], hi[i], want, zone_fn(i), nu, nv, cell_fn)

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


def _grid(m, a, b, c, d, want, zone, nu, nv, cell_fn=None):
    """Subdivide the coarse quad a-b-c-d into nu x nv sub-quads by bilinear
    interpolation of its four existing corners. No new jitter, no reshaping:
    same corners, more triangles, so each one fits the atlas texel budget.
    """
    pa, pb, pc, pd = m.verts[a], m.verts[b], m.verts[c], m.verts[d]

    def pt(u, v):
        return tuple((1 - u) * (1 - v) * pa[k] + u * (1 - v) * pb[k]
                      + u * v * pc[k] + (1 - u) * v * pd[k] for k in range(3))

    corners = {(0, 0): a, (nu, 0): b, (nu, nv): c, (0, nv): d}
    ids = [[corners[(iu, iv)] if (iu, iv) in corners
            else m.v(pt(iu / float(nu), iv / float(nv)))
            for iu in range(nu + 1)] for iv in range(nv + 1)]
    for iv in range(nv):
        for iu in range(nu):
            q = (ids[iv][iu], ids[iv][iu + 1], ids[iv + 1][iu + 1], ids[iv + 1][iu])
            if cell_fn is not None and cell_fn(m, q, want, zone):
                continue
            m.quad(q[0], q[1], q[2], q[3], want, zone)


# =============================================================================
# CELLS -- an arched recess carved into one wall facet, a drip lip under the
# mouth, thin smooth columns sill to arch. Interior faces are ZONE_GLOW. No
# collision: nothing here touches _collider.
# =============================================================================

def _v3(p, q, s=1.0):
    return (p[0] + q[0] * s, p[1] + q[1] * s, p[2] + q[2] * s)


def _sub(p, q):
    return (p[0] - q[0], p[1] - q[1], p[2] - q[2])


def _dot(p, q):
    return p[0] * q[0] + p[1] * q[1] + p[2] * q[2]


def _cross(p, q):
    return (p[1] * q[2] - p[2] * q[1], p[2] * q[0] - p[0] * q[2], p[0] * q[1] - p[1] * q[0])


def _norm(p):
    l = math.sqrt(_dot(p, p)) or 1.0
    return (p[0] / l, p[1] / l, p[2] / l)


def _zipper(m, outer, inner, want, zone):
    """Triangulate the ring between two loops, each a list of (angle, id)
    sorted by angle about a common centre: len(outer)+len(inner) tris."""
    no, ni = len(outer), len(inner)
    i = j = 0
    for _ in range(no + ni):
        oa = outer[(i + 1) % no][0] + 2.0 * math.pi * ((i + 1) // no)
        ia = inner[(j + 1) % ni][0] + 2.0 * math.pi * ((j + 1) // ni)
        if i < no and (j >= ni or oa <= ia):
            m.tri(outer[i % no][1], outer[(i + 1) % no][1], inner[j % ni][1], want, zone)
            i += 1
        else:
            m.tri(inner[j % ni][1], inner[(j + 1) % ni][1], outer[i % no][1], want, zone)
            j += 1


def _sorted_loop(pts, centre):
    """[(angle, id)] about centre, ascending, for a list of ((x, y), id)."""
    out = [(math.atan2(p[1] - centre[1], p[0] - centre[0]), i) for p, i in pts]
    out.sort()
    return out


def _cell_density(z):
    if z < DECK_Z:
        return CELL_RHO_PIT
    return CELL_RHO_SHAFT * math.exp(-(z - CEIL_Z) / CELL_FALL)


def _cell(m, r, q, want, zone):
    """Roll for a cell on facet q=(bl, br, tr, tl); carve it and return True."""
    a, b, c, d = q
    if m.verts[d][2] < m.verts[a][2]:          # band emitted top ring first
        a, b, c, d = d, c, b, a
    pa, pb, pc, pd = m.verts[a], m.verts[b], m.verts[c], m.verts[d]
    W = math.sqrt(_dot(_sub(pb, pa), _sub(pb, pa)))
    H = math.sqrt(_dot(_sub(pd, pa), _sub(pd, pa)))
    zmid = 0.25 * (pa[2] + pb[2] + pc[2] + pd[2])
    if r.f() >= _cell_density(zmid) * W * H:
        return False
    if W < 2.0 * CELL_MX + CELL_W[0] or H < 2.0 * CELL_MY + CELL_H[0]:
        return False

    def pt(u, v):
        return tuple((1 - u) * (1 - v) * pa[k] + u * (1 - v) * pb[k]
                      + u * v * pc[k] + (1 - u) * v * pd[k] for k in range(3))

    U = _norm(_sub(pb, pa))
    V = _norm(_sub(pd, pa))
    N = _norm(_cross(U, V))
    if _dot(N, want) < 0.0:
        N = (-N[0], -N[1], -N[2])

    h = min(CELL_H[0] + r.f() * (CELL_H[1] - CELL_H[0]), H - 2.0 * CELL_MY)
    w = h * (CELL_ASPECT[0] + r.f() * (CELL_ASPECT[1] - CELL_ASPECT[0]))
    w = min(max(w, CELL_W[0]), CELL_W[1], W - 2.0 * CELL_MX)
    depth = CELL_DEPTH[0] + r.f() * (CELL_DEPTH[1] - CELL_DEPTH[0])
    x0 = CELL_MX + r.f() * (W - 2.0 * CELL_MX - w)          # metres along U
    y0 = CELL_MY + r.f() * (H - 2.0 * CELL_MY - h)          # metres along V
    near = zmid < NEAR_Z
    sides = 5 if near else 4
    if near:
        arch = [(0.0, 0.0), (w, 0.0), (w, 0.55 * h), (0.78 * w, 0.88 * h), (0.5 * w, h),
                (0.22 * w, 0.88 * h), (0.0, 0.55 * h)]
    else:
        arch = [(0.0, 0.0), (w, 0.0), (w, 0.6 * h), (0.5 * w, h), (0.0, 0.6 * h)]

    def mouth(x, y):
        return pt((x0 + x) / W, (y0 + y) / H)

    P = [m.v(mouth(x, y)) for x, y in arch]
    centre = (x0 + 0.5 * w, y0 + 0.5 * h)
    outer = _sorted_loop([((0.0, 0.0), a), ((W, 0.0), b), ((W, H), c), ((0.0, H), d)], centre)
    inner = _sorted_loop([((x0 + x, y0 + y), i) for (x, y), i in zip(arch, P)], centre)
    _zipper(m, outer, inner, want, zone)

    # ---- the recess: side walls to a smaller back wall, all glowing --------
    cm = mouth(0.5 * w, 0.5 * h)
    cb = _v3(cm, N, -depth)
    B = [m.v(_v3(cb, _sub(m.verts[p], cm), CELL_TAPER)) for p in P]
    n = len(P)
    for k in range(n):
        j = (k + 1) % n
        mid = tuple(0.5 * (m.verts[P[k]][t] + m.verts[P[j]][t]) for t in range(3))
        m.quad(P[k], P[j], B[j], B[k], _sub(cm, mid), ZONE_GLOW)
    m.fan(B, N, ZONE_GLOW)

    # ---- the drip lip under the sill ----------------------------------------
    bl, br = m.verts[P[0]], m.verts[P[1]]
    fl = m.v(_v3(_v3(bl, N, LIP_OUT), V, -LIP_DROP))
    fr = m.v(_v3(_v3(br, N, LIP_OUT), V, -LIP_DROP))
    wl = m.v(_v3(bl, V, -LIP_UNDER))
    wr = m.v(_v3(br, V, -LIP_UNDER))
    m.quad(P[0], P[1], fr, fl, V, ZONE_ROCK)
    m.quad(fl, fr, wr, wl, _v3(N, V, -1.0), ZONE_ROCK)
    m.tri(P[0], fl, wl, (-U[0], -U[1], -U[2]), ZONE_ROCK)
    m.tri(P[1], fr, wr, U, ZONE_ROCK)

    # ---- the columns: sill to arch, uneven, a slight lean, flared at the top -
    nb = max(4, min(7, int(round(w / BAR_PITCH))))
    pitch = w / (nb + 1)
    for k in range(nb):
        rb = BAR_R[0] + r.f() * (BAR_R[1] - BAR_R[0])
        x = (k + 1) * pitch + r.sf() * 0.22 * pitch
        x = min(max(x, rb + 0.05), w - rb - 0.05)
        xt = min(max(x + r.sf() * BAR_LEAN, rb + 0.05), w - rb - 0.05)
        yt = h
        for s in range(1, n):                       # the arch, sill edge skipped
            (xa, ya), (xb, yb) = arch[s], arch[(s + 1) % n]
            if min(xa, xb) <= xt <= max(xa, xb) and xa != xb:
                yt = ya + (yb - ya) * (xt - xa) / (xb - xa)
                break
        bot = _v3(mouth(x, 0.0), N, -BAR_SINK * rb)
        top = _v3(mouth(xt, yt), N, -BAR_SINK * rb)
        A = _norm(_sub(top, bot))
        bot = _v3(bot, A, -0.05)
        top = _v3(top, A, 0.05)
        e1 = _norm(_v3(N, A, -_dot(N, A)))
        e2 = _cross(A, e1)
        t0 = r.f() * 2.0 * math.pi
        rings = []
        for cen, rad in ((bot, rb * 0.95), (top, rb * BAR_FLARE)):
            ring = []
            for i in range(sides):
                t = t0 + 2.0 * math.pi * i / sides
                ring.append(m.v(_v3(_v3(cen, e1, rad * math.cos(t)), e2, rad * math.sin(t))))
            rings.append(ring)
        for i in range(sides):
            j = (i + 1) % sides
            t = t0 + 2.0 * math.pi * (i + 0.5) / sides
            out = _v3(_v3((0.0, 0.0, 0.0), e1, math.cos(t)), e2, math.sin(t))
            m.quad(rings[0][i], rings[0][j], rings[1][j], rings[1][i], out, ZONE_ROCK)

    CELLS.append((cm, N, V, w, h))
    return True


def _disc(m, rim, center_pt, levels, ang_sub, want, zone):
    """A flat-ish disc from a jagged rim ring down to a true centre point, in
    concentric bands of constant radial step -- not one giant pie slice fan.
    The rim's own jag survives, scaled toward the centre; nothing reshaped.
    """
    n = len(rim)
    rings = [rim]
    for s in range(1, levels):
        frac = 1.0 - s / float(levels)
        rings.append([m.v(tuple(center_pt[k] + (m.verts[rim[i]][k] - center_pt[k]) * frac
                                 for k in range(3)))
                      for i in range(n)])
    for s in range(levels - 1):
        for i in range(n):
            j = (i + 1) % n
            _grid(m, rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i],
                  want, zone, ang_sub, 1)
    cid = m.v(center_pt)
    last = rings[-1]
    for i in range(n):
        j = (i + 1) % n
        m.tri(cid, last[i], last[j], want, zone)


COURTYARD_LEVELS = _nv(INNER_R, cap=FAR_CAP)


# =============================================================================
# THE ROCK
# =============================================================================

def _rock(r):
    m = _Mesh()
    ang = [2.0 * math.pi * (i + r.sf() * ANG_JAG) / SIDES for i in range(SIDES)]

    # ---- pit wall: deck lip down to the courtyard --------------------------
    pit_z = [DECK_Z] + PIT_RINGS_Z + [COURTYARD_Z]
    npit = len(pit_z)
    pbias = _held(r, npit, PIT_JAG, one_sided=False)
    for i in range(SIDES):
        pbias[i][0] = 0.0                       # the lip is exactly INNER_R
    pzj = [[0.0 if k in (0, npit - 1) else r.sf() * Z_JAG for k in range(npit)]
           for _ in range(SIDES)]
    pit = [_ring(m, ang,
                 lambda i, k=k: INNER_R * (1.0 + pbias[i][k]),
                 lambda i, k=k: pit_z[k] + pzj[i][k])
           for k in range(npit)]

    def pit_zone(k):
        def zone(i):
            b = 0.5 * (pbias[i][k] + pbias[i][k + 1])   # +ve = back under the deck
            if b > EMBER_T * PIT_JAG and k >= npit - 1 - EMBER_BANDS:
                return ZONE_EMBER
            if b > SHADE_T * PIT_JAG:
                return ZONE_SHADE
            return ZONE_ROCK
        return zone

    cr = _Rng(CELL_SEED)
    cell_fn = lambda mm, q, want, zone: _cell(mm, cr, q, want, zone)   # noqa: E731
    for k in range(npit - 1):
        m.band(pit[k], pit[k + 1], ang, True, pit_zone(k),
               nu=PIT_SUB, nv=_nv(pit_z[k] - pit_z[k + 1], cap=PIT_CAP), cell_fn=cell_fn)

    # ---- courtyard floor: the tower's foot lands on it ----------------------
    # Nobody ever stands on it (the KillVolume converts anything that falls
    # this far); coarse FAR_CAP bands, no angular split.
    _disc(m, pit[npit - 1], (0.0, 0.0, COURTYARD_Z), COURTYARD_LEVELS, 1, UP, ZONE_SHADE)

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

    # ---- the deck: one flat dressed-stone annulus, lip to wall foot --------
    # Gridded to the same <=3 m facet cap as the walls, so the atlas sits at
    # the tower's texel density instead of stretched over one huge face.
    # Same ROCK zone as the walls and the tower.
    deck_nv = _nv(OUTER_R - INNER_R)
    for i in range(SIDES):
        j = (i + 1) % SIDES
        _grid(m, pit[0][i], pit[0][j], wall[0][j], wall[0][i], UP, ZONE_ROCK,
              ANG_SUB, deck_nv)

    # ---- upper pit wall: ceiling lip up to the rim, 300 m nobody stands near -
    up_z = [CEIL_Z] + UPPER_RINGS_Z + [RIM_Z]
    nup = len(up_z)
    ubias = _held(r, nup, PIT_JAG, one_sided=True)
    for i in range(SIDES):
        ubias[i][0] = 0.0                       # the lip is exactly INNER_R
    uzj = [[0.0 if k == 0 else (r.sf() * RIM_JAG if k == nup - 1 else r.sf() * Z_JAG)
            for k in range(nup)] for _ in range(SIDES)]
    upper = [_ring(m, ang,
                   lambda i, k=k: INNER_R * (1.0 + ubias[i][k]),
                   lambda i, k=k: up_z[k] + uzj[i][k])
             for k in range(nup)]

    def upper_zone(k):
        def zone(i):
            b = 0.5 * (ubias[i][k] + ubias[i][k + 1])
            return ZONE_SHADE if b > SHADE_T * PIT_JAG else ZONE_ROCK
        return zone

    for k in range(nup - 1):
        if up_z[k] < SHAFT_NEAR_Z:
            m.band(upper[k], upper[k + 1], ang, True, upper_zone(k),
                   nu=SHAFT_SUB, nv=_nv(up_z[k + 1] - up_z[k], cap=SHAFT_CAP), cell_fn=cell_fn)
        else:
            m.band(upper[k], upper[k + 1], ang, True, upper_zone(k),
                   nu=1, nv=_nv(up_z[k + 1] - up_z[k], cap=FAR_CAP), cell_fn=cell_fn)

    # ---- the ceiling: flat, faces DOWN, flush with the lip -----------------
    # Same ROCK zone and grid as the deck it mirrors -- exterior rock seen
    # from below, not the dark interior zone.
    for i in range(SIDES):
        j = (i + 1) % SIDES
        _grid(m, upper[0][i], upper[0][j], wall[nwall - 1][j], wall[nwall - 1][i],
              (0.0, 0.0, -1.0), ZONE_ROCK, ANG_SUB, deck_nv)

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

def unwrap(ob, zones, seed=0):
    """Identical to tower_build.py's unwrap: fixed UV_SCALE texel density, no
    per-face scale reduction. Every face here is now <=3 m, so nothing needs
    the density dropped to fit -- that drop was the washed-out-grey bug.
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
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


# =============================================================================
# EXTRA RENDERS -- from the deck, which mdl's rig cannot reach
# =============================================================================

def _deck_render(spec, objects):
    """Arena light (bentham_ring's red sun), hand-placed cameras via TRACK_TO."""
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
    if CELLS:
        cm, n, v, w, h = max([c for c in CELLS if c[0][2] < DECK_Z] or CELLS,
                             key=lambda c: c[4])
        eye = _v3(_v3(cm, n, 2.2 * h), v, 0.35 * h)
        shot("cell", eye, cm, 35.0, (1000, 800))

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

    ob = rock.object(OBJECT_NAME)
    unwrap(ob, rock.zones)
    mdl.finish(ob, rock_material("HellRock", albedo, emissive), strip_uvs=False)

    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons)))
    print("MDL STATS cells=%d near=%d pit=%d"
          % (len(CELLS), sum(1 for c in CELLS if c[0][2] < NEAR_Z),
             sum(1 for c in CELLS if c[0][2] < DECK_Z)))
    print("MDL STATS deck r=%.1f..%.1f y=%.2f courtyard_y=%.2f ceiling_y=%.2f rim_y=%.1f ground_r=%.0f"
          % (INNER_R, OUTER_R, DECK_Z, COURTYARD_Z, CEIL_Z, RIM_Z, GROUND_RINGS[-1][0]))
    return [ob, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_deck_render)
