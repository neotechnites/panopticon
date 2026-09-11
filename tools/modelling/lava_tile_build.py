"""
PANOPTICON -- lava_tile: a 4 x 4 m, 0.3 m thick slab of lava. Emissive
orange-red top with a dark crust pattern, dark rock sides. Tiles are laid in
grids: every edge vertex sits exactly at x,y = +-2.0 and z = 0.3, the sides are
flat and vertical, and the lava zone is drawn wrap-around so the pattern
continues across a neighbour. Origin at base centre, Blender +Z = Godot +Y.

NO collision node: the scene puts a TrapVolume kill trigger over it.
Contract: one mesh `LavaTile`, 1 surface.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================
NAME = "lava_tile"
OBJECT_NAME = "LavaTile"

HALF = 2.0                        # 4 x 4 m
THICK = 0.3
GRID = 3                          # top is GRID x GRID quads; interior verts sag a little
SAG = (-0.06, 0.02)               # interior vertex z offset range: molten, not planar
SEED = 7720133

TEX_SIZE = 128
TEX_ALBEDO = "lava_tile_albedo"
TEX_EMISSIVE = "lava_tile_emissive"
TEX_SEED = 6661031
ROCK_ROUGHNESS = 0.95
ROCK_METALLIC = 0.0
UV_SCALE = 0.45
UV_PAD = 1.5 / TEX_SIZE

ZONE_ROCK  = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)
ZONE_CARVE = (0.5, 0.0, 1.0, 0.5)   # unused here; kept so the atlas layout matches the tower
ZONE_LAVA  = (0.0, 0.0, 0.5, 0.5)   # the ember quarter, repainted as a lava surface

FACING_YAW = 0.0

# =============================================================================
# TEXTURE -- the tower's hell-rock atlas painter (tower_build.py), same palette
# =============================================================================

class _Rng(object):
    """Tiny deterministic LCG so the model is byte-identical every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0xFFFFFFFF

    def n(self):
        self.s = (1664525 * self.s + 1013904223) & 0xFFFFFFFF
        return self.s

    def f(self):
        return self.n() / 4294967296.0

    def sf(self):
        return 2.0 * self.f() - 1.0

    def i(self, a, b):
        return a + int(self.f() * (b - a + 1))

    def pick(self, seq):
        return seq[self.i(0, len(seq) - 1)]


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


def _fill(c, r, box, shades, glow=None):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            k = r.i(0, len(shades) - 1)
            c.put(x, y, shades[k], glow[k] if glow else None)


def _shatter(c, r, box, shades, count, minsz, maxsz, glow=None):
    """Squarish blotches with no preferred direction (no courses, no streaks)."""
    x0, y0, x1, y1 = box
    for _ in range(count):
        w = r.i(minsz, maxsz)
        h = max(minsz, min(maxsz, w + r.i(-1, 1)))
        x, y = r.i(x0, x1 - w - 1), r.i(y0, y1 - h - 1)
        c.rect(x, y, x + w, y + h, r.pick(shades), glow)


def _paint_rock(c, r, box):
    """The body: dark red going to near-black, a few coals still in it."""
    _fill(c, r, box, [(74, 27, 25), (58, 20, 19), (90, 35, 30), (46, 16, 16)])
    _shatter(c, r, box, [(96, 40, 33), (48, 16, 16), (110, 48, 38)], 20, 6, 15)
    _shatter(c, r, box, [(32, 11, 12), (118, 56, 43)], 12, 4, 9)
    x0, y0, x1, y1 = box
    for _ in range(6):
        x, y = r.i(x0 + 2, x1 - 4), r.i(y0 + 2, y1 - 4)
        c.rect(x, y, x + 2, y + 2, (172, 44, 12), (114, 22, 3))


def _paint_shade(c, r, box):
    """Near-black, for facets that sit recessed."""
    _fill(c, r, box, [(34, 12, 12), (24, 8, 9), (44, 17, 15), (17, 6, 7)])
    _shatter(c, r, box, [(42, 16, 15), (10, 3, 4)], 20, 4, 11)
    x0, y0, x1, y1 = box
    for _ in range(4):
        x, y = r.i(x0 + 2, x1 - 4), r.i(y0 + 2, y1 - 4)
        c.rect(x, y, x + 2, y + 2, (140, 34, 9), (92, 16, 2))


def _paint_carve(c, r, box):
    """Dressed stone, worn: greyer and flatter than the living rock."""
    _fill(c, r, box, [(84, 58, 53), (72, 48, 44), (96, 69, 63), (64, 42, 39)])
    _shatter(c, r, box, [(66, 43, 40), (102, 74, 68), (56, 35, 33)], 14, 5, 14)
    _shatter(c, r, box, [(74, 38, 27), (46, 27, 25)], 10, 4, 10)
    x0, y0, x1, y1 = box
    for _ in range(10):
        x, y = r.i(x0, x1 - 2), r.i(y0, y1 - 2)
        c.rect(x, y, x + 2, y + 2, (52, 32, 30))


def _paint_ember(c, r, box):
    """Rock split open by brimstone: random-walked cracks, dull halo, hot core."""
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


def _make_images(c):
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
    bsdf.inputs["Emission Strength"].default_value = 1.0   # 1.0: no KHR_materials_emissive_strength, no Godot warning
    mat.diffuse_color = (0.13, 0.04, 0.04, 1.0)
    return mat


# =============================================================================
# GEOMETRY -- face accumulator; winding is checked against a wanted normal
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
    """Faces carry an atlas zone; a ("full", zone, half_extent) zone maps planar over the whole zone."""

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

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


UP = (0.0, 0.0, 1.0)
DOWN = (0.0, 0.0, -1.0)


def unwrap(ob, zones, seed=0):
    """Per-face planar projection into a random window of its zone (tower_build.py)."""
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + seed * 7919 + len(me.polygons))
    half = 0.5 / TEX_SIZE
    for pi, poly in enumerate(me.polygons):
        zone = zones[pi]
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        if zone[0] == "full":                    # top-down over the whole zone, texel-centre inset
            _, (u0, v0, u1, v1), ext = zone
            for li, co in zip(poly.loop_indices, cos):
                s = min(max((co[0] + ext) / (2.0 * ext), 0.0), 1.0)
                t = min(max((co[1] + ext) / (2.0 * ext), 0.0), 1.0)
                uvl.data[li].uv = (u0 + half + s * (u1 - u0 - 2.0 * half),
                                   v0 + half + t * (v1 - v0 - 2.0 * half))
            continue
        u0, v0, u1, v1 = zone
        span_u = (u1 - u0) - 2.0 * UV_PAD
        span_v = (v1 - v0) - 2.0 * UV_PAD
        nrm = poly.normal
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
        fu = -1.0 if r.i(0, 1) else 1.0
        fv = -1.0 if r.i(0, 1) else 1.0
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


def _paint_lava(c, r, box):
    """Molten field with a dark crust network. Wraps: crust walks go modulo the zone."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    hot = [(236, 78, 12), (255, 108, 22), (222, 60, 8), (255, 138, 34)]
    _fill(c, r, box, hot, glow=hot)
    for _ in range(14):                                   # crust plates
        pw, ph = r.i(5, 12), r.i(5, 12)
        px, py = r.i(0, w - 1), r.i(0, h - 1)
        for dy in range(ph):
            for dx in range(pw):
                shade = r.pick([(26, 9, 8), (36, 13, 10), (18, 6, 6)])
                c.put(x0 + (px + dx) % w, y0 + (py + dy) % h, shade, (0, 0, 0))
    for _ in range(20):                                   # crust veins between plates
        x, y = r.i(0, w - 1), r.i(0, h - 1)
        for _step in range(28):
            for dx in (0, 1):
                for dy in (0, 1):
                    c.put(x0 + (x + dx) % w, y0 + (y + dy) % h, (30, 11, 9), (0, 0, 0))
            x += r.i(-1, 1)
            y += r.i(-1, 1)
    for _ in range(26):                                   # white-hot cores
        x, y = r.i(0, w - 1), r.i(0, h - 1)
        core = r.pick([(255, 214, 96), (255, 178, 60)])
        c.rect(x0 + x, y0 + y, x0 + x + 2, y0 + y + 2, core, core)


def build_texture():
    c = _Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    _paint_rock(c, r, _rect_of(ZONE_ROCK, TEX_SIZE))
    _paint_shade(c, r, _rect_of(ZONE_SHADE, TEX_SIZE))
    _paint_carve(c, r, _rect_of(ZONE_CARVE, TEX_SIZE))
    _paint_lava(c, r, _rect_of(ZONE_LAVA, TEX_SIZE))
    return _make_images(c)


def _slab(r):
    m = _Mesh()
    n = GRID + 1
    top = []
    for j in range(n):
        row = []
        for i in range(n):
            x = -HALF + 2.0 * HALF * i / GRID
            y = -HALF + 2.0 * HALF * j / GRID
            z = THICK
            if 0 < i < GRID and 0 < j < GRID:
                z += SAG[0] + (SAG[1] - SAG[0]) * r.f()
            row.append(m.v((x, y, z)))
        top.append(row)
    lava = ("full", ZONE_LAVA, HALF)
    for j in range(GRID):
        for i in range(GRID):
            m.quad(top[j][i], top[j][i + 1], top[j + 1][i + 1], top[j + 1][i], UP, lava)
    foot = {}
    for (i, j) in ((0, 0), (GRID, 0), (GRID, GRID), (0, GRID)):
        x, y, _ = m.verts[top[j][i]]
        foot[(i, j)] = m.v((x, y, 0.0))
    rim = [(0, 0), (GRID, 0), (GRID, GRID), (0, GRID)]
    for k in range(4):
        a, b = rim[k], rim[(k + 1) % 4]
        ta, tb = top[a[1]][a[0]], top[b[1]][b[0]]
        ax, ay, _ = m.verts[ta]
        bx, by, _ = m.verts[tb]
        m.quad(foot[a], foot[b], tb, ta, (0.5 * (ax + bx), 0.5 * (ay + by), 0.0), ZONE_SHADE)
    return m


def build():
    slab = _slab(_Rng(SEED))

    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)

    ob = slab.object(OBJECT_NAME)
    unwrap(ob, slab.zones)
    mdl.finish(ob, rock_material("LavaTile", albedo, emissive), strip_uvs=False)
    print("MDL STATS visual_tris=%d collision_tris=0" % len(ob.data.polygons))
    xs = [v[0] for v in slab.verts]
    zs = [v[2] for v in slab.verts]
    print("MDL STATS size=%.2f thick=%.2f" % (max(xs) - min(xs), max(zs)))
    return [ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
