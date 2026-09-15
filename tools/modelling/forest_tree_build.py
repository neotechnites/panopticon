"""
PANOPTICON -- forest_tree: Map 3's tower. A great tree grown into a shape.

Origin is the Tower node (world y 25.35), like tower.glb: the model drops in
at identity under scenes/ring/forest.tscn's Tower. Authored in WORLD
coordinates (Blender z = Godot y) and shifted on export.

    water ......... y 0.0     the trunk stands in it, root buttresses out to r 9.5
    trunk ......... y -2..13.5, r 7.4 at the foot to 4.2 at the split
    lattice ....... y 11..25.6: eight branch piers lean out to r 7, fork, and the
                    arms meet the neighbours' in eight pointed arches; two twig
                    rungs per opening; you see the far piers through the openings
    canopy ........ y 24.8..27.0, a scalloped leaf disc r 8..9
    guard floor ... y 27.05 (origin + 1.70, as map 1), flat r 5, a 0.55 m leaf sill
    roof .......... six thin branches off the sill lean in to y 31.5, leaf clumps
                    hung on them: a partial roof, sky between

One material (the forest atlas, painted or textures/forest_atlas_albedo.png),
one mesh, no rig. ForestTreeCollision rides as a `-colonly` node: the guard
floor, the sill, the canopy's slope and the trunk. Nothing else is touched.

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

ORIGIN_Y = 25.35            # the Tower node: the model's origin, world y
WATER_Y = -11.05            # the map's water (map 1's lava sea level)
FLOOR_Y = ORIGIN_Y + 1.70   # the guard's floor, as map 1's room floor
FLOOR_R = 5.0
FLOOR_RINGS = ((3.4, 28), (1.6, 14))   # (r, verts): the flat floor gridded in, halving the count; no sliver fan
SILL = ((5.0, 0.0), (5.2, 0.55), (6.15, 0.5), (6.45, 0.0))   # (r, over the floor), inner to outer; the roof branches root on the top
TOP_RINGS = ((8.0, 0.12),)  # (r, over the floor): the leaf top between the canopy rim and the sill, lumpy
FOOT_Y = -13.0

TRUNK_SIDES = 40            # 5 per pier, 4 per root lobe
TRUNK = [(-13.0, 8.0), (-11.0, 7.4), (-8.5, 6.8), (-5.0, 6.4), (-1.0, 6.2), (3.0, 6.0), (7.0, 5.7),
         (10.5, 5.4), (12.6, 5.15), (14.8, 4.55), (16.8, 3.9), (17.9, 2.4)]   # (y, r): the top domes into the split
TRUNK_CAP_Y = 18.5
TRUNK_FLUTE = 0.035         # per-side radius wander, held up the trunk (more and the pier patches go jagged)
ROOTS = 10                  # buttress lobes of the trunk profile ...
ROOT_LOBE = (0.42, 0.0, 1.4)   # ... (amplitude at the foot, the y they fade out at, the power)
PIER_BAND = 8               # the piers grow out of the two trunk bands TRUNK[8]..TRUNK[10] (a 5x2 patch each)

PIERS = 8
PIER_SIDES = 8              # a 10-gon's edge points straight at the trunk patch's corner: a sliver
PIER_PATH = [(4.55, 14.8), (5.7, 15.75), (6.5, 17.3), (7.1, 18.7), (7.6, 20.2), (8.1, 21.9), (8.3, 23.1),
             (7.5, 24.15)]   # (r, y); the ends snap onto the trunk band and the canopy belly
PIER_R = (1.4, 1.25, 1.1, 1.0, 0.9)
ARM_SEG = 4                 # the pier segment the arches spring from (y ~21)
ARM_R = (0.45, 0.4, 0.34)   # root to apex, mirrored down the other side
ARM_LIFT = 0.55             # the arm leaves the pier at atan(lift) above the patch normal
ARM_OUT = 0.6               # ... from a patch biased this much radially outward (clears the rungs)
APEX = (8.7, 25.7)          # (r, y) where the two halves meet, inside the canopy
ARM_PULL = (15.0, 8.9, 24.9)  # the arm's control point: degrees toward the apex, r, y
RUNG_SEGS = (1, 3, 5)       # pier segments the twig rungs cross from (y ~16.7, 19.5, 22.5)
RUNG_R = 0.22
RUNG_SAG = 0.25

CANOPY = [(24.6, 0.88, 0.2), (25.4, 0.96, 0.6), (26.3, 1.0, 1.0), (27.0, 0.9, 0.7)]   # (y, of R, share of the lobes)
CANOPY_R = 11.0
CANOPY_N = 56               # 7 per pier; the grid is a half step off so a vertex sits at every pier bearing
CANOPY_LOBES = (7, 0.14, 3, 0.05)   # (harmonic, amp) x 2
UNDER = ((9.0, 24.4), (5.9, 23.85))   # (r, y) round belly rings, unlobed: the piers land on the band between
UNDER_CENTRE = ((2.6, 23.6, 28), 23.5)   # (r, y, verts) then the centre's y

ROOF_N = 6
ROOF_SIDES = 7
ROOF_P = ((5.0, 31.0), (3.6, 33.0))   # (r, y) bezier pull and tip; the root is on the sill top
ROOF_R = (0.3, 0.28, 0.23, 0.15)
ROOF_CLUMP = (2.0, 1.1)     # the end clump: radius, its centre this far over the tip
TWIG_T = 0.4                # where along the roof branch the side twig grows
TWIG_R = 0.09
TWIG_CLUMP = (1.3, 0.85)    # the twig's clump: radius, over the twig's end

SEED = 3140271
EYE_H = 1.65

# ---- the forest atlas (shared with forest_build.py) -------------------------
USE_TEXTURE_FILES = True        # textures/forest_atlas_albedo.png replaces the painted sheet
TEX_DIR = "textures"
TEX_SIZE = 256
TEX_SEED = 7710233
TPM = 12.0                      # texels per metre on the atlas
ZONES = {                       # (u0, v0, u1, v1)
    "grass": (0.0, 0.0, 0.5, 0.375),
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


def _paint_grass(c, r, box):
    _fill(c, r, box, [(108, 146, 60), (100, 138, 56), (116, 152, 66), (94, 132, 52)])
    _blotch(c, r, box, [(122, 158, 70), (90, 128, 50), (104, 144, 58)], 40, 4, 12)
    x0, y0, x1, y1 = box
    for _ in range(90):                      # blades
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 4)
        c.rect(x, y, x + 1, y + r.i(2, 4), r.pick([(138, 172, 78), (72, 112, 44)]))
    for _ in range(14):                      # clover / small flowers
        x, y = r.i(x0, x1 - 3), r.i(y0, y1 - 3)
        c.rect(x, y, x + 2, y + 2, r.pick([(150, 184, 90), (86, 124, 50)]))


def _paint_path(c, r, box):
    """The worn line down the middle of the lane: thinner, browner grass."""
    _fill(c, r, box, [(112, 138, 62), (104, 130, 58), (118, 142, 68), (108, 126, 60)])
    _blotch(c, r, box, [(120, 116, 70), (98, 122, 56), (126, 128, 76)], 30, 3, 9)
    x0, y0, x1, y1 = box
    for _ in range(40):
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 3)
        c.rect(x, y, x + 1, y + r.i(2, 3), r.pick([(134, 160, 76), (88, 118, 50)]))
    for _ in range(16):                      # bare earth showing through
        x, y = r.i(x0, x1 - 4), r.i(y0, y1 - 3)
        c.rect(x, y, x + r.i(2, 4), y + 2, r.pick([(124, 104, 66), (110, 92, 58)]))


def _paint_edge(c, r, box):
    _fill(c, r, box, [(80, 118, 48), (72, 110, 44), (88, 126, 52), (64, 100, 40)])
    _blotch(c, r, box, [(60, 92, 40), (96, 134, 56)], 22, 3, 8)
    x0, y0, x1, y1 = box
    for _ in range(40):
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 5)
        c.rect(x, y, x + 1, y + r.i(3, 5), (104, 146, 62))
    for _ in range(10):
        x, y = r.i(x0, x1 - 3), r.i(y0, y1 - 3)
        c.rect(x, y, x + 2, y + 2, (58, 44, 30))


def _paint_leaf(c, r, box):
    _leaves(c, r, box, [(58, 94, 42), (52, 86, 40), (64, 100, 46)],
            [(92, 132, 56), (104, 142, 60), (84, 122, 50), (98, 138, 58)],
            (124, 158, 68), 520, (3, 5))


def _paint_shade(c, r, box):
    _leaves(c, r, box, [(36, 62, 32), (32, 56, 30)],
            [(56, 88, 44), (48, 78, 40), (62, 96, 48)], (78, 112, 54), 110, (3, 5))


def _paint_sun(c, r, box):
    _leaves(c, r, box, [(98, 138, 58), (92, 132, 54)],
            [(132, 168, 72), (150, 184, 84), (118, 156, 66), (140, 176, 78)],
            (172, 200, 104), 110, (3, 5))


def _paint_fern(c, r, box):
    _fill(c, r, box, [(60, 98, 44), (54, 90, 40), (66, 104, 48)])
    x0, y0, x1, y1 = box
    for _ in range(9):                       # fronds: a stem with side ticks
        x, y = r.i(x0 + 4, x1 - 5), r.i(y0 + 2, y1 - 2)
        n = r.i(8, 16)
        dx = r.pick([-1, 1])
        for k in range(n):
            xx, yy = x + (k * dx) // 2, y + k
            if not (x0 <= xx < x1 and y0 <= yy < y1):
                break
            c.put(xx, yy, (96, 142, 60))
            if k % 2 == 0:
                c.put(xx - 1, yy, (112, 156, 68))
                c.put(xx + 1, yy, (112, 156, 68))
    for _ in range(30):
        c.put(r.i(x0, x1 - 1), r.i(y0, y1 - 1), (44, 74, 34))


def _paint_bark(c, r, box, base=((96, 72, 48), (90, 66, 44), (102, 78, 52))):
    _fill(c, r, box, list(base))
    x0, y0, x1, y1 = box
    for _ in range(26):                      # vertical streaks
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 8)
        c.rect(x, y, x + r.i(1, 2), min(y1, y + r.i(6, 18)),
               r.pick([(76, 56, 36), (112, 86, 58), (70, 50, 32)]))
    for _ in range(12):                      # cracks
        x, y = r.i(x0, x1 - 1), r.i(y0, y1 - 6)
        for k in range(r.i(4, 9)):
            c.put(x, y + k, (56, 40, 26))
            x += r.i(-1, 1)
    for _ in range(8):
        x, y = r.i(x0, x1 - 3), r.i(y0, y1 - 3)
        c.rect(x, y, x + 2, y + 2, (82, 112, 60))    # moss


def _paint_earth(c, r, box):
    _fill(c, r, box, [(86, 64, 44), (80, 58, 40), (92, 70, 48), (74, 54, 38)])
    _blotch(c, r, box, [(70, 52, 36), (104, 80, 56), (66, 48, 34)], 30, 3, 9)
    x0, y0, x1, y1 = box
    for _ in range(8):                       # root streaks
        x, y = r.i(x0 + 1, x1 - 2), y0
        for k in range(y1 - y0):
            c.put(x, y + k, (110, 84, 54))
            if k % 3 == 0:
                x += r.i(-1, 1)
            x = max(x0, min(x1 - 1, x))
    for _ in range(14):                      # stones
        x, y = r.i(x0, x1 - 3), r.i(y0, y1 - 3)
        c.rect(x, y, x + 2, y + 2, (118, 108, 94))
    for _ in range(10):
        x, y = r.i(x0, x1 - 3), r.i(y0, y1 - 3)
        c.rect(x, y, x + 2, y + 2, (72, 104, 50))    # moss


def _paint_cell(c, r, box):
    _fill(c, r, box, [(14, 16, 12), (18, 20, 14), (12, 14, 10), (20, 24, 16)])
    _blotch(c, r, box, [(24, 28, 18), (10, 12, 8)], 12, 3, 8)
    x0, y0, x1, y1 = box
    for _ in range(3):                       # something pale, far back
        x, y = r.i(x0 + 4, x1 - 6), r.i(y0 + 4, y1 - 6)
        c.rect(x, y, x + 2, y + 1, (52, 60, 44))


def _paint_root(c, r, box):
    _paint_bark(c, r, box, base=((104, 74, 50), (98, 70, 46), (112, 82, 56)))


PAINTERS = {
    "grass": _paint_grass, "path": _paint_path, "edge": _paint_edge, "leaf": _paint_leaf,
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


def _pier_bearing(k):
    return k * 360.0 / PIERS + 22.5


def _canopy_theta(s, n=None):
    """The canopy family's angular grid, a half step off the pier grid: with
    CANOPY_N = 7 * PIERS a vertex sits exactly at every pier bearing."""
    return 2.0 * math.pi * (s + 0.5) / float(n or CANOPY_N)


def _canopy_R(theta, share=1.0):
    h1, a1, h2, a2 = CANOPY_LOBES
    return CANOPY_R * (1.0 + share * (a1 * math.cos(h1 * theta + 0.4) + a2 * math.cos(h2 * theta + 1.9)))


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


def _weld(m, quads, path, radius, sides, zone, at_start, tag):
    """socket_ring, plus the proof that the ring landed inside its patch: the
    margin (in the patch plane) is kept for the --check report."""
    loop = _loop_of(m, quads)
    ids = socket_ring(m, quads, path, radius, sides, zone, at_start=at_start)
    n = norm(_newell([m.verts[i] for i in quads[0]]))
    c = m.centroid(ids)
    ex = norm(cross(n, UP if abs(n[2]) < 0.9 else (1.0, 0.0, 0.0)))
    ey = cross(n, ex)
    flat = lambda v: (dot(sub(m.verts[v], c), ex), dot(sub(m.verts[v], c), ey))
    poly = [flat(v) for v in loop]
    _WELDS.append((tag, min(_margin(poly, flat(v)) for v in ids)))
    return ids


def _by_azimuth(m, ring, centre):
    """The ring's ids in rising xy azimuth round ``centre``: clump_end lays its
    rings out by azimuth, so a tube's end ring hands over in the same order."""
    return sorted(ring, key=lambda v: math.atan2(m.verts[v][1] - centre[1], m.verts[v][0] - centre[0]) % (2.0 * math.pi))


# ---- trunk ------------------------------------------------------------------

def _trunk(m, r):
    """Lofted rings, fluted; the lower rings' radius modulated by ROOTS lobes
    that grow toward the foot, so the foot is a star of buttress roots."""
    flute = [1.0 + TRUNK_FLUTE * r.sf() for _ in range(TRUNK_SIDES)]
    amp0, fade_y, powr = ROOT_LOBE
    rings = []
    for (y, rad) in TRUNK:
        amp = amp0 * max(0.0, (fade_y - y) / (fade_y - FOOT_Y)) ** powr
        ring = []
        for s in range(TRUNK_SIDES):
            a = 2.0 * math.pi * s / TRUNK_SIDES
            lobe = ((1.0 + math.cos(ROOTS * a)) / 2.0) ** 2        # 0..1, mean 3/8
            rr = rad * flute[s] * (1.0 + amp * (lobe - 0.375)) * (1.0 + 0.02 * r.sf())
            ring.append(m.v((rr * math.cos(a), rr * math.sin(a), y)))
        rings.append(ring)
    split = max(i for i, (y, _) in enumerate(TRUNK) if y < 0.0)
    loft(m, rings[:split + 1], "root")
    loft(m, rings[split:], "bark")
    _cap(m, rings[-1], (0.0, 0.0, TRUNK_CAP_Y), UP, "bark")
    _cap(m, rings[0], (0.0, 0.0, FOOT_Y), DOWN, "root")
    return rings


# ---- canopy -----------------------------------------------------------------

def _canopy(m, r):
    """The scalloped leaf disc: lobed rims, a round belly underneath (the piers
    land on its outer band), the leaf top in to the sill, the flat floor.
    Returns (belly rings, sill rings)."""
    n = CANOPY_N
    rings = []
    for (y, frac, share) in CANOPY:
        ring = []
        for s in range(n):
            th = _canopy_theta(s)
            rr = _canopy_R(th, share) * frac * (1.0 + 0.03 * r.sf())
            ring.append(m.v((rr * math.cos(th), rr * math.sin(th), y + 0.18 * r.sf())))
        rings.append(ring)
    loft(m, rings[:2], "shade")
    loft(m, rings[1:], "leaf")
    # underside: round belly rings (no lobes, no jitter: the piers' landing), then in to the centre
    belly = [rings[0]] + [_circle(m, rad, y, n) for (rad, y) in UNDER]
    loft(m, belly, "shade", want_fn=lambda c: DOWN)
    (rad, y, nc), yc = UNDER_CENTRE
    inner = _circle(m, rad, y, nc, r, jy=0.12)
    zipper(m, belly[-1], inner, DOWN, "shade")
    _cap(m, inner, (0.0, 0.0, yc), DOWN, "shade")
    # top: the outer leaf ring in over the lumpy top to the sill, over the sill, the flat floor
    top = [rings[-1]]
    for (rad, over) in TOP_RINGS:
        top.append(_circle(m, rad, FLOOR_Y + over, n, r, jr=0.04, jy=0.12))
    sill = [_circle(m, rad, FLOOR_Y + over, n) for (rad, over) in reversed(SILL)]
    loft(m, top + sill[:1], "sun", want_fn=lambda c: UP)
    loft(m, sill, "leaf", want_fn=lambda c: UP)
    prev = sill[-1]
    for (rad, nf) in FLOOR_RINGS:
        ring = _circle(m, rad, FLOOR_Y, nf)
        zipper(m, prev, ring, UP, "sun")
        prev = ring
    _cap(m, prev, (0.0, 0.0, FLOOR_Y), UP, "sun")
    return belly[1:], list(reversed(sill))


# ---- the split: piers out of the trunk, up into the canopy -----------------

def _pier(m, r, k, trunk, belly):
    """Pier k: its base ring is a socket in the trunk's split bands (5 sides
    of 40 by 2 bands, centred on the bearing: two bands so the patch's sides
    have a vertex halfway and no corner fans across the ring), its top ring
    a socket in the canopy belly (4 quads of 56, centred on the vertex at the
    bearing)."""
    b = _pier_bearing(k)
    path = [pol(b, rad, y) for (rad, y) in PIER_PATH]
    per = TRUNK_SIDES // PIERS
    s0 = int(round(-b / 360.0 * TRUNK_SIDES - per / 2.0)) % TRUNK_SIDES
    sides = [(s0 + d) % TRUNK_SIDES for d in range(per)]
    base = _patch(m, trunk[PIER_BAND], trunk[PIER_BAND + 1], sides) + _patch(m, trunk[PIER_BAND + 1], trunk[PIER_BAND + 2], sides)
    out = norm(sub(_patch_centre(m, base), (0.0, 0.0, TRUNK[PIER_BAND + 1][0])))   # the band's mean normal, roughly
    base = sorted(base, key=lambda q: -dot(norm(_newell([m.verts[i] for i in q])), out))
    path[0] = _patch_centre(m, base)
    v = int(round(-b / 360.0 * CANOPY_N - 0.5)) % CANOPY_N
    land = _patch(m, belly[0], belly[1], [(v + d) % CANOPY_N for d in (-2, -1, 0, 1)])
    path[-1] = _patch_centre(m, land)
    first = _weld(m, base, path, PIER_R[0], PIER_SIDES, "bark", True, "pier base")
    last = _weld(m, land, path, PIER_R[-1], PIER_SIDES, "shade", False, "pier top")
    return tube(m, path, PIER_R, PIER_SIDES, "bark", caps=(False, False), wob=0.06, rng=r,
                first_ring=first, last_ring=last)


def _apex(k):
    """Where the arch between piers k and k+1 peaks: APEX, pulled in where a
    lobe valley would let the arm poke out of the canopy."""
    b = _pier_bearing(k) + 180.0 / PIERS
    th = math.radians(-b)
    y = APEX[1]
    lo = hi = None
    for i in range(len(CANOPY) - 1):
        (y0, f0, s0), (y1, f1, s1) = CANOPY[i], CANOPY[i + 1]
        if y0 <= y <= y1:
            t = (y - y0) / (y1 - y0)
            lo = _canopy_R(th, s0) * f0
            hi = _canopy_R(th, s1) * f1
            surface = lo + (hi - lo) * t
    rad = min(APEX[0], surface * 0.97 - ARM_R[-1] - 0.3)
    return pol(b, rad, y)


def _arch(m, r, k, piers):
    """One pointed arch: from a socket (2 sides of the pier's 8) in pier k's
    outer side, up through the apex (a bezier corner) and down into a socket
    in pier k+1's side."""
    apex = _apex(k)
    radii = ARM_R + tuple(reversed(ARM_R[:-1]))
    halves = []
    for (kk, sgn) in ((k, 1.0), ((k + 1) % PIERS, -1.0)):
        rings = piers[kk]
        b = _pier_bearing(kk)
        axis = _seg_axis(m, rings, ARM_SEG)
        side = norm(sub((apex[0], apex[1], axis[2]), axis))
        face = norm(add(side, radial(b), ARM_OUT))
        patch = _patch(m, rings[ARM_SEG], rings[ARM_SEG + 1], _facing(m, rings, ARM_SEG, face, 2))
        root = _patch_centre(m, patch)
        out = norm(_newell([m.verts[i] for i in patch[0]]))    # the plane the ring is projected onto: leave square to it
        if dot(out, sub(root, axis)) < 0.0:
            out = (-out[0], -out[1], -out[2])
        q = add(root, norm(add(out, UP, ARM_LIFT)), 1.0)
        pull = pol(b + sgn * ARM_PULL[0], ARM_PULL[1], ARM_PULL[2])
        halves.append((patch, [root, q] + bez(q, pull, apex, 4)[1:]))
    (pa, ha), (pb, hb) = halves
    path = ha + list(reversed(hb))[1:]
    first = _weld(m, pa, path, ARM_R[0], 6, "bark", True, "arm root")
    last = _weld(m, pb, path, ARM_R[0], 6, "bark", False, "arm root")
    tube(m, path, radii, 6, "bark", caps=(False, False), wob=0.05, rng=r, first_ring=first, last_ring=last)


def _rungs(m, r, k, piers):
    """Twig rungs across the opening on pier k's clockwise side: both ends
    are sockets in the piers' facing quads (one side of the pier's 8)."""
    ra, rc = piers[k], piers[(k + 1) % PIERS]
    for seg in RUNG_SEGS:
        aa, cc = _seg_axis(m, ra, seg), _seg_axis(m, rc, seg)
        d = norm((cc[0] - aa[0], cc[1] - aa[1], 0.0))
        pa = _patch(m, ra[seg], ra[seg + 1], _facing(m, ra, seg, d, 1))
        pc = _patch(m, rc[seg], rc[seg + 1], _facing(m, rc, seg, (-d[0], -d[1], 0.0), 1))
        a, c = _patch_centre(m, pa), _patch_centre(m, pc)
        mid = lerp(a, c, 0.5)
        path = bez(a, (mid[0], mid[1], mid[2] - RUNG_SAG), c, 3)
        first = _weld(m, pa, path, RUNG_R, 4, "bark", True, "rung")
        last = _weld(m, pc, path, RUNG_R, 4, "bark", False, "rung")
        tube(m, path, (RUNG_R, RUNG_R * 0.9), 4, "bark", caps=(False, False), wob=0.1, rng=r,
             first_ring=first, last_ring=last)


# ---- roof -------------------------------------------------------------------

def _clump(m, ring, centre, radius, zone, r):
    clump_end(m, _by_azimuth(m, ring, centre), centre, radius, zone, r)


def _roof(m, r, sill):
    """ROOF_N thin branches out of sockets in the sill top, leaning in, each
    ending in a leaf clump; one side twig each, ending in a smaller clump."""
    inner, outer = sill[1], sill[2]        # the sill top band
    n = CANOPY_N
    for k in range(ROOF_N):
        b = k * 360.0 / ROOF_N + 30.0 + r.u(-6.0, 6.0)
        v = int(round(-b / 360.0 * n - 0.5)) % n
        b = -math.degrees(_canopy_theta(v))     # snapped to the sill vertex
        patch = _patch(m, inner, outer, [(v - 1) % n, v])
        root = _patch_centre(m, patch)
        pull = pol(b, ROOF_P[0][0], ROOF_P[0][1])
        tip = pol(b + r.u(-10.0, 10.0), ROOF_P[1][0], ROOF_P[1][1])
        path = bez(root, pull, tip, 6)
        first = _weld(m, patch, path, ROOF_R[0], ROOF_SIDES, "leaf", True, "roof branch")
        rings = tube(m, path, ROOF_R, ROOF_SIDES, "bark", caps=(False, False), wob=0.06, rng=r, first_ring=first)
        _clump(m, rings[-1], add(tip, UP, ROOF_CLUMP[1]), ROOF_CLUMP[0], "sun", r)
        # the side twig: out of the branch's outer side, bending up, widened to six for its clump
        seg = int(round(TWIG_T * 6))
        axis = _seg_axis(m, rings, seg)
        want = norm(add(radial(b), tangent(b), r.pick((-0.7, 0.7))))
        tp = _patch(m, rings[seg], rings[seg + 1], _facing(m, rings, seg, want, 2))
        troot = _patch_centre(m, tp)
        out = norm(sub(troot, axis))
        tpath = [troot, add(troot, out, 0.35), add(add(troot, out, 0.55), UP, 0.45), add(add(troot, out, 0.6), UP, 0.95)]
        tfirst = _weld(m, tp, tpath, TWIG_R, 4, "bark", True, "twig")
        trings = tube(m, tpath, (TWIG_R, TWIG_R * 0.8, TWIG_R * 0.6), 4, "bark", caps=(False, False), first_ring=tfirst)
        end = tpath[-1]
        six = [m.v((end[0] + 0.3 * math.cos(_canopy_theta(s, 6)), end[1] + 0.3 * math.sin(_canopy_theta(s, 6)), end[2] + 0.12))
               for s in range(6)]
        zipper(m, six, _by_azimuth(m, trings[-1], end), UP, "sun", centre=end)
        _clump(m, six, add(end, UP, TWIG_CLUMP[1]), TWIG_CLUMP[0], "sun", r)


def build_tree_geometry():
    del _WELDS[:]
    m = _Mesh()
    r = _Rng(SEED)
    trunk = _trunk(m, r)
    belly, sill = _canopy(m, r)
    piers = [_pier(m, r, k, trunk, belly) for k in range(PIERS)]
    for k in range(PIERS):
        _arch(m, r, k, piers)
        _rungs(m, r, k, piers)
    _roof(m, r, sill)
    return _prune(m)


def _prune(m):
    """Drop the vertices no face references: a socket patch two quads tall
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
    c = _Mesh()
    n = 24
    circ = lambda rad, y: [c.v((rad * math.cos(2.0 * math.pi * s / n),
                                rad * math.sin(2.0 * math.pi * s / n), y)) for s in range(n)]
    floor = circ(FLOOR_R, FLOOR_Y)
    c.fan(floor, UP, "sun")
    prev = floor
    for (rad, over) in SILL[1:]:
        ring = circ(rad, FLOOR_Y + over)
        loft(c, [prev, ring], "leaf", want_fn=lambda p: UP)
        prev = ring
    for (rad, y) in ((CANOPY_R * 0.9, 25.4), (UNDER[0][0], 24.4)):
        ring = circ(rad, y)
        loft(c, [prev, ring], "leaf", want_fn=lambda p: (p[0], p[1], 0.6))
        prev = ring
    trunk = [circ(5.0, FOOT_Y), circ(5.0, 14.5)]
    loft(c, trunk, "bark")
    c.fan(trunk[1], UP, "bark")
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
        px = (u1 - u0) * TEX_SIZE
        scale = TPM / px                     # metres -> fraction of the zone
        nrm = poly.normal
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
        fu = -1.0 if r.i(0, 1) else 1.0
        fv = -1.0 if (ax == 2 and r.i(0, 1)) else 1.0
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        mi = min(co[ii] for co in cos)
        mj = min(co[jj] for co in cos)
        w = min((max(co[ii] for co in cos) - mi) * scale, 1.0)
        h = min((max(co[jj] for co in cos) - mj) * scale, 1.0)
        ou = r.f() * (1.0 - w)
        ov = r.f() * (1.0 - h)
        for li, co in zip(poly.loop_indices, cos):
            s = min(ou + (co[ii] - mi) * scale, 1.0)
            t = min(ov + (co[jj] - mj) * scale, 1.0)
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


def _check():
    import forest_check
    m = build_tree_geometry().compact()
    c = build_tree_collider().compact()
    forest_check.prove(m, "tree")
    forest_check.components_report(m)
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
