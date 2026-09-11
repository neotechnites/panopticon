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

# ---- prison cells: stone screens cut into the pit faces ---------------------
# A cell is 4..7 vertical SLOTS cut through the wall surface; the stone left
# between them is the bars, one surface with the sill and lintel. Behind the
# screen is a plain glowing box. Positions come from seeded dart throwing on
# the wall in (arc, height), not from the facet grid; a cell is cut into
# whichever facets it overlaps (T-junctions land on straight facet edges).
CELL_SEED   = 4420917
CELL_H      = (2.0, 5.0)      # mouth height, metres
SLOT_W      = (0.35, 0.50)
BAR_W       = (0.20, 0.30)
ARCH_DROP   = 0.32            # outer slots this fraction shorter: a pointed arch
CELL_DEPTH  = (2.0, 3.0)
REVEAL      = 0.25            # carved slot side depth on near cells
NEAR_Z      = 60.0            # below: slot reveals; above: plain cuts
N_PIT       = 105             # cells deck -> courtyard
N_SHAFT     = 78              # cells ceiling -> rim
SHAFT_FALL  = 95.0            # e-folding height of the shaft density
CELL_ZTOP   = RIM_Z - 20.0
GAP_MIN, GAP_MAX = 0.4, 3.6   # spacing field: tight clusters .. empty stretches
PIT_SUB, PIT_CAP     = 2, 7.0
SHAFT_SUB, SHAFT_CAP = 1, 25.0
SHAFT_NEAR_Z = 105.0

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


def _grid(m, a, b, c, d, want, zone, nu, nv):
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
            m.quad(ids[iv][iu], ids[iv][iu + 1], ids[iv + 1][iu + 1], ids[iv + 1][iu],
                   want, zone)


# =============================================================================
# PIT FACES -- a (theta, z) grid of bilinear facets; cells are cut into it
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


TWO_PI = 2.0 * math.pi
DOWN = (0.0, 0.0, -1.0)


class _Wall(object):
    """One pit face between ascending rings. W(theta, z) is a point on the
    coarse bilinear side-quads, so anything cut into a facet lies on it."""

    def __init__(self, m, ang, ring_z, rings, nu, cap, zone_fn):
        self.m, self.ang, self.ring_z, self.rings = m, ang, ring_z, rings
        self.zone_fn = zone_fn
        n = len(ang)
        self.a0 = ang[0]
        self.cols = []
        for i in range(n):
            a = ang[i]
            b = ang[i + 1] if i + 1 < n else ang[0] + TWO_PI
            self.cols += [a + (b - a) * su / nu for su in range(nu)]
        self.cols.append(ang[0] + TWO_PI)
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
        self.holes = {}

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
            c1 = min(len(self.cols) - 2, _bisect_left(self.cols, pb) - 1)
            r0 = max(0, _bisect(self.rows, za) - 1)
            r1 = min(len(self.rows) - 2, _bisect_left(self.rows, zb) - 1)
            for ci in range(c0, c1 + 1):
                for ri in range(r0, r1 + 1):
                    self.holes.setdefault((ci, ri), []).append(
                        (max(pa, self.cols[ci]), min(pb, self.cols[ci + 1]),
                         max(za, self.rows[ri]), min(zb, self.rows[ri + 1])))

    def emit(self):
        nu = (len(self.cols) - 1) // len(self.ang)
        for ci in range(len(self.cols) - 1):
            am = 0.5 * (self.cols[ci] + self.cols[ci + 1])
            want = (-math.cos(am), -math.sin(am), 0.0)
            side = ci // nu
            for ri in range(len(self.rows) - 1):
                k = max(0, min(len(self.ring_z) - 2, _bisect(self.ring_z, self.rows[ri]) - 1))
                zone = self.zone_fn(k, side)
                t0, t1, z0, z1 = self.cols[ci], self.cols[ci + 1], self.rows[ri], self.rows[ri + 1]
                holes = self.holes.get((ci, ri))
                if not holes:
                    self.rect(t0, t1, z0, z1, want, zone)
                    continue
                ts = sorted(set([t0, t1] + [h[0] for h in holes] + [h[1] for h in holes]))
                zs = sorted(set([z0, z1] + [h[2] for h in holes] + [h[3] for h in holes]))
                for j in range(len(zs) - 1):
                    zm = 0.5 * (zs[j] + zs[j + 1])
                    run = None
                    for i in range(len(ts) - 1):
                        tm = 0.5 * (ts[i] + ts[i + 1])
                        if any(h[0] <= tm <= h[1] and h[2] <= zm <= h[3] for h in holes):
                            if run:
                                self.rect(run[0], run[1], zs[j], zs[j + 1], want, zone)
                            run = None
                        else:
                            run = (run[0] if run else ts[i], ts[i + 1])
                    if run:
                        self.rect(run[0], run[1], zs[j], zs[j + 1], want, zone)

    def rect(self, ta, tb, za, zb, want, zone):
        self.m.quad(self.W(ta, za), self.W(tb, za), self.W(tb, zb), self.W(ta, zb), want, zone)


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


# =============================================================================
# CELLS -- placement, then the cut, the reveals and the glowing box
# =============================================================================

def _gap_field(s, z):
    """Spacing between cells, metres: low in clumps, high in the empty stretches."""
    n = 0.5 + 0.25 * (math.sin(s * 0.043 + 1.1) + math.sin(z * 0.061 - 0.7)) \
        + 0.25 * math.sin(s * 0.017 - z * 0.029 + 2.0)
    return GAP_MIN + (GAP_MAX - GAP_MIN) * min(1.0, max(0.0, n))


def _place_cells(r):
    """Seeded dart throwing in (arc, z) on the pit faces; returns cell dicts."""
    circ = TWO_PI * INNER_R
    cells = []

    def throw(z_of):
        h = CELL_H[0] + (CELL_H[1] - CELL_H[0]) * r.f() ** 0.9
        n = max(4, min(7, int(round(2.2 + 0.9 * h + r.sf() * 0.6))))
        slots = [SLOT_W[0] + r.f() * (SLOT_W[1] - SLOT_W[0]) for _ in range(n)]
        bars = [BAR_W[0] + r.f() * (BAR_W[1] - BAR_W[0]) for _ in range(n - 1)]
        w = sum(slots) + sum(bars)
        s = r.f() * circ
        z = z_of(h)
        depth = CELL_DEPTH[0] + r.f() * (CELL_DEPTH[1] - CELL_DEPTH[0])
        if z is None:
            return False
        gap = _gap_field(s, z)
        for c in cells:
            ds = abs(s - c["s"])
            ds = min(ds, circ - ds)
            if ds < 0.5 * (w + c["w"]) + gap and abs(z - c["z"]) < 0.5 * (h + c["h"]) + gap:
                return False
        cells.append({"s": s, "z": z, "w": w, "h": h, "slots": slots, "bars": bars,
                      "depth": depth})
        return True

    def pit_z(h):
        lo, hi = COURTYARD_Z + 1.5 + 0.5 * h, DECK_Z - 0.8 - 0.5 * h
        return lo + r.f() * (hi - lo)

    def shaft_z(h):
        z = CEIL_Z + 0.8 + 0.5 * h - SHAFT_FALL * math.log(1.0 - r.f() * 0.999)
        return z if z + 0.5 * h < CELL_ZTOP else None

    for want, z_of in ((N_PIT, pit_z), (N_SHAFT, shaft_z)):
        got = tries = 0
        while got < want and tries < 6000:
            tries += 1
            got += throw(z_of)
    return cells


def _slots(wall, c):
    """[(ta, tb, ztop)] and the sill z for a cell, in wall (theta, z)."""
    n = len(c["slots"])
    z0 = c["z"] - 0.5 * c["h"]
    t = wall._norm((c["s"] - 0.5 * c["w"]) / INNER_R)
    out = []
    for k in range(n):
        x = (k - 0.5 * (n - 1)) / max(0.5 * (n - 1), 1e-9)
        top = z0 + c["h"] * (1.0 - ARCH_DROP * x * x)
        out.append((t, t + c["slots"][k] / INNER_R, top))
        t += c["slots"][k] / INNER_R
        if k < n - 1:
            t += c["bars"][k] / INNER_R
    return out, z0


def _carve(m, wall, c):
    """Cut the slots, then build the reveals and the glowing box behind."""
    slots, z0 = _slots(wall, c)
    for ta, tb, zt in slots:
        wall.hole(ta, tb, z0, zt)
    ta, tb = slots[0][0], slots[-1][1]
    zt = max(sl[2] for sl in slots)
    tc = 0.5 * (ta + tb)
    out = (math.cos(tc), math.sin(tc), 0.0)
    pc = wall.P(tc, 0.5 * (z0 + zt))
    d = c["depth"]

    def back(t, z):
        p = wall.P(t, z)
        return m.v(_v3(p, out, d + _dot(_sub(pc, p), out)))

    tl, zl = wall.tbreaks(ta, tb), wall.zbreaks(z0, zt)
    for i in range(len(tl) - 1):
        m.quad(wall.W(tl[i], z0), wall.W(tl[i + 1], z0), back(tl[i + 1], z0), back(tl[i], z0),
               UP, ZONE_GLOW)
        m.quad(wall.W(tl[i], zt), wall.W(tl[i + 1], zt), back(tl[i + 1], zt), back(tl[i], zt),
               DOWN, ZONE_GLOW)
    for t, sgn in ((ta, 1.0), (tb, -1.0)):
        side = (-math.sin(t) * sgn, math.cos(t) * sgn, 0.0)
        for j in range(len(zl) - 1):
            m.quad(wall.W(t, zl[j]), wall.W(t, zl[j + 1]), back(t, zl[j + 1]), back(t, zl[j]),
                   side, ZONE_GLOW)
    bk = [[back(t, z) for t in tl] for z in zl]
    for j in range(len(zl) - 1):
        for i in range(len(tl) - 1):
            m.quad(bk[j][i], bk[j][i + 1], bk[j + 1][i + 1], bk[j + 1][i],
                   (-out[0], -out[1], 0.0), ZONE_GLOW)

    if c["z"] < NEAR_Z:
        for sa, sb, st in slots:
            zl = wall.zbreaks(z0, st)
            for t, sgn in ((sa, 1.0), (sb, -1.0)):
                side = (-math.sin(t) * sgn, math.cos(t) * sgn, 0.0)
                for j in range(len(zl) - 1):
                    p0, p1 = wall.P(t, zl[j]), wall.P(t, zl[j + 1])
                    m.quad(wall.W(t, zl[j]), wall.W(t, zl[j + 1]),
                           m.v(_v3(p1, out, REVEAL)), m.v(_v3(p0, out, REVEAL)), side, ZONE_SHADE)
    CELLS.append((pc, out, c["w"], c["h"]))


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

    # ---- pit wall: courtyard up to the deck lip. Rings are level (their
    # radius steps, like cleaved rock) so a cell's slots are rectangles in
    # (theta, z) and cut cleanly across facet boundaries.
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

    # ---- courtyard floor: the tower's foot lands on it ----------------------
    # Nobody ever stands on it (the KillVolume converts anything that falls
    # this far); coarse FAR_CAP bands, no angular split.
    _disc(m, pit[0], (0.0, 0.0, COURTYARD_Z), COURTYARD_LEVELS, 1, UP, ZONE_SHADE)

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
    deck_nv = _nv(OUTER_R - INNER_R)
    lip = pit[npit - 1]
    for i in range(SIDES):
        j = (i + 1) % SIDES
        _grid(m, lip[i], lip[j], wall[0][j], wall[0][i], UP, ZONE_ROCK, ANG_SUB, deck_nv)

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

    near_z = [z for z in up_z if z <= SHAFT_NEAR_Z]
    far_z = [z for z in up_z if z >= SHAFT_NEAR_Z]
    kn = len(near_z)
    shaft_near = _Wall(m, ang, near_z, upper[:kn], SHAFT_SUB, SHAFT_CAP, upper_zone)
    shaft_far = _Wall(m, ang, far_z, upper[kn - 1:], 1, FAR_CAP,
                      lambda k, i: upper_zone(k + kn - 1, i))

    # ---- the cells ------------------------------------------------------------
    for c in _place_cells(_Rng(CELL_SEED)):
        z = c["z"]
        if z < DECK_Z:
            _carve(m, pit_wall, c)
        elif z < SHAFT_NEAR_Z:
            _carve(m, shaft_near, c)
        else:
            _carve(m, shaft_far, c)
    pit_wall.emit()
    shaft_near.emit()
    shaft_far.emit()

    # ---- the ceiling: flat, faces DOWN, flush with the lip -----------------
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
        cm, out, w, h = max([c for c in CELLS if c[0][2] < DECK_Z] or CELLS,
                            key=lambda c: c[3])
        eye = _v3(_v3(cm, out, -2.2 * h), UP, 0.35 * h)
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
    print("MDL STATS cells=%d pit=%d above200=%d top=%.0f"
          % (len(CELLS), sum(1 for c in CELLS if c[0][2] < DECK_Z),
             sum(1 for c in CELLS if c[0][2] > 200.0), max(c[0][2] for c in CELLS)))
    print("MDL STATS deck r=%.1f..%.1f y=%.2f courtyard_y=%.2f ceiling_y=%.2f rim_y=%.1f ground_r=%.0f"
          % (INNER_R, OUTER_R, DECK_Z, COURTYARD_Z, CEIL_Z, RIM_Z, GROUND_RINGS[-1][0]))
    return [ob, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_deck_render)
