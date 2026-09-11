"""rock_bars -- a grate of thin carved rock columns filling a gallery cross-section.

Low-poly PS1 hell rock, flat shaded, the tower's atlas. 10.6 m wide, 8.5 m
tall: a rock sill, a rock lintel, and 17 smooth tapered columns 0.24-0.30 m
thick, unevenly spaced and never quite plumb, no gap wider than 0.38 m -- you
see straight through it, a body cannot. Same style as map_base's cell bars.
ORIGIN IS THE BASE CENTRE: z=0 is the ground. Bars span Blender X (Godot X),
thickness along Blender Y (Godot Z). Blender +Z -> Godot +Y, +X -> +X, +Y -> -Z.

Contract: one mesh "RockBars" (one surface, one UV set), plus "RockBarsCollision"
-- one box per bar plus the sill and lintel, shipped as a `-colonly` node.
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

NAME = "rock_bars"
OBJECT_NAME = "RockBars"
COLLIDER_NAME = "RockBarsCollision-colonly"

HALF_W   = 5.3          # 10.6 m wide
HEIGHT   = 8.5
BARS     = 17
BAR_R    = (0.12, 0.15) # column radius: 0.24-0.30 m thick
MAX_GAP  = 0.38         # a body cannot pass, at any height
SIDES    = 5            # smooth carved column: no jag, no knobs
SILL_H   = 0.45
LINTEL_H = 0.5
BEAM_HD  = 0.25         # sill/lintel half depth: proud of the bars
OVERLAP  = 0.08         # bars run this far into the sill and lintel
MID_Z    = (0.42, 0.60) # the waist ring sits in this band of the bar's height
FLARE    = (1.12, 0.92, 1.22)   # radius factors: foot, waist, head -- a slight lip
POS_JAG  = 0.03         # metres, column spacing jitter
LEAN     = 0.035        # metres, head offset: a column is never plumb
WAIST_KINK = 0.03       # metres, waist offset

SEED = 7130951
TEX_ALBEDO   = "rock_bars_albedo"
TEX_EMISSIVE = "rock_bars_emissive"
UV_SCALE = 0.30
FACING_YAW = 0.0

# ---- atlas: tower_build.py's painter, same seed, so it is the same rock -----
TEX_SIZE       = 128
TEX_SEED       = 6661031
ROCK_ROUGHNESS = 0.95
ROCK_METALLIC  = 0.0
UV_PAD         = 1.5 / TEX_SIZE

ZONE_ROCK   = (0.0, 0.5, 0.5, 1.0)   # dark red rock, the body
ZONE_SHADE  = (0.5, 0.5, 1.0, 1.0)   # near-black: facets that sit recessed
ZONE_CARVE  = (0.5, 0.0, 1.0, 0.5)   # dressed stone
ZONE_EMBER  = (0.0, 0.0, 0.5, 0.5)   # split open by brimstone -- the only glow


# =============================================================================
# TEXTURE -- copied from tower_build.py; do not retune here
# =============================================================================

class _Rng(object):
    """Seeded LCG so the model is byte-identical every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def bits(self):
        return self.n() >> 12          # low bits are short-period

    def f(self):
        return self.n() / float(0x7FFFFFFF)

    def sf(self):
        return self.f() * 2.0 - 1.0

    def i(self, a, b):
        return a + self.bits() % (b - a + 1)

    def pick(self, seq):
        return seq[self.bits() % len(seq)]


def _s2l(rgb):
    """sRGB 0-255 -> scene-linear."""
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
    bsdf.inputs["Emission Strength"].default_value = 1.0   # exactly 1.0: no KHR ext
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
    """Vertex/face accumulator; every face states which way its normal must point."""

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
        if len(idx) == 4:              # split: the corners are not coplanar
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

    def fan(self, ring, want, zone, centre=None):
        """Triangulate a ring: from a centre vertex, or from ring[0] if none."""
        if centre is None:
            for i in range(1, len(ring) - 1):
                self.tri(ring[0], ring[i], ring[i + 1], want, zone)
        else:
            for i in range(len(ring)):
                self.tri(ring[i], ring[(i + 1) % len(ring)], centre, want, zone)

    def box(self, lo, hi, zone):
        """Axis-aligned box, 12 tris. The collider shape."""
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        p = [self.v(c) for c in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                                 (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
        self.quad(p[0], p[1], p[2], p[3], (0, 0, -1), zone)
        self.quad(p[4], p[5], p[6], p[7], (0, 0, 1), zone)
        self.quad(p[0], p[1], p[5], p[4], (0, -1, 0), zone)
        self.quad(p[2], p[3], p[7], p[6], (0, 1, 0), zone)
        self.quad(p[1], p[2], p[6], p[5], (1, 0, 0), zone)
        self.quad(p[3], p[0], p[4], p[7], (-1, 0, 0), zone)

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


# =============================================================================
# UV -- per-face planar projection into a random window of its zone
# =============================================================================

def unwrap(ob, zones, seed=0):
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
# THE GRATE
# =============================================================================

def _beam(m, z0, z1, top, bottom):
    """Sill or lintel: a box the full width; ``top``/``bottom`` say which caps to draw."""
    x0, x1, y0, y1 = -HALF_W, HALF_W, -BEAM_HD, BEAM_HD
    p = [m.v(c) for c in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                          (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
    if bottom:
        m.quad(p[0], p[1], p[2], p[3], (0, 0, -1), ZONE_SHADE)
    if top:
        m.quad(p[4], p[5], p[6], p[7], (0, 0, 1), ZONE_ROCK)
    m.quad(p[0], p[1], p[5], p[4], (0, -1, 0), ZONE_ROCK)
    m.quad(p[2], p[3], p[7], p[6], (0, 1, 0), ZONE_ROCK)
    m.quad(p[1], p[2], p[6], p[5], (1, 0, 0), ZONE_SHADE)
    m.quad(p[3], p[0], p[4], p[7], (-1, 0, 0), ZONE_SHADE)


def _columns(r):
    """Per column: rings [(z, x, radius) foot, waist, head], gaps <= MAX_GAP."""
    z0, z1 = SILL_H - OVERLAP, HEIGHT - LINTEL_H + OVERLAP
    rad = [BAR_R[0] + r.f() * (BAR_R[1] - BAR_R[0]) for _ in range(BARS)]
    gap = (2.0 * HALF_W - 2.0 * sum(rad)) / (BARS + 1)
    cols = []
    x = -HALF_W + gap
    for k in range(BARS):
        cx = x + rad[k] + r.sf() * POS_JAG
        zm = z0 + (z1 - z0) * (MID_Z[0] + r.f() * (MID_Z[1] - MID_Z[0]))
        cols.append([[z0, cx, rad[k] * FLARE[0]],
                     [zm, cx + r.sf() * WAIST_KINK, rad[k] * FLARE[1]],
                     [z1, cx + r.sf() * LEAN, rad[k] * FLARE[2]]])
        x += 2.0 * rad[k] + gap

    def at(col, z):
        (za, xa, ra), (zb, xb, rb), (zc, xc, rc) = col
        if z <= zb:
            t = (z - za) / (zb - za)
            return xa + (xb - xa) * t, ra + (rb - ra) * t
        t = (z - zb) / (zc - zb)
        return xb + (xc - xb) * t, rb + (rc - rb) * t

    walls = [[[z0, -HALF_W, 0.0], [0.5 * (z0 + z1), -HALF_W, 0.0], [z1, -HALF_W, 0.0]]] + cols \
        + [[[z0, HALF_W, 0.0], [0.5 * (z0 + z1), HALF_W, 0.0], [z1, HALF_W, 0.0]]]
    levels = [z0 + (z1 - z0) * i / 8.0 for i in range(9)]
    for _ in range(40):                       # pull neighbours together where too wide
        worst = 0.0
        for k in range(len(walls) - 1):
            for z in levels:
                xa, ra = at(walls[k], z)
                xb, rb = at(walls[k + 1], z)
                e = (xb - rb) - (xa + ra) - MAX_GAP
                if e > worst:
                    worst = e
                if e > 0.0:
                    for col, s in ((walls[k], 0.5), (walls[k + 1], -0.5)):
                        if col[0][2] == 0.0:
                            continue          # the wall does not move
                        ring = min(col, key=lambda rg: abs(rg[0] - z))
                        ring[1] += s * e * 1.05
        if worst <= 1e-4:
            break
    return cols, worst + MAX_GAP


def _column(m, r, col):
    """A smooth SIDES-gon column through three rings: SIDES * 4 tris."""
    t0 = r.f() * 2.0 * math.pi
    rings = []
    for z, cx, rad in col:
        rings.append([m.v((cx + rad * math.cos(t0 + 2.0 * math.pi * i / SIDES),
                           rad * math.sin(t0 + 2.0 * math.pi * i / SIDES), z))
                      for i in range(SIDES)])
    for k in range(len(rings) - 1):
        for i in range(SIDES):
            j = (i + 1) % SIDES
            t = t0 + 2.0 * math.pi * (i + 0.5) / SIDES
            m.quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i],
                   (math.cos(t), math.sin(t), 0.0), ZONE_ROCK)


def _grate(r):
    m = _Mesh()
    _beam(m, 0.0, SILL_H, top=True, bottom=False)
    _beam(m, HEIGHT - LINTEL_H, HEIGHT, top=False, bottom=True)
    cols, widest = _columns(r)
    for col in cols:
        _column(m, r, col)
    return m, cols, widest


def _collider(cols):
    """One box per column (its full lean), plus the sill and the lintel."""
    c = _Mesh()
    c.box((-HALF_W, -BEAM_HD, 0.0), (HALF_W, BEAM_HD, SILL_H), ZONE_ROCK)
    c.box((-HALF_W, -BEAM_HD, HEIGHT - LINTEL_H), (HALF_W, BEAM_HD, HEIGHT), ZONE_ROCK)
    for col in cols:
        x0 = min(x - rad for _, x, rad in col)
        x1 = max(x + rad for _, x, rad in col)
        rm = max(rad for _, _, rad in col)
        c.box((x0, -rm, SILL_H), (x1, rm, HEIGHT - LINTEL_H), ZONE_ROCK)
    return c


def _finish(rock, coll):
    """Texture, unwrap, material and the `-colonly` collider; returns [visual, collider]."""
    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    ob = rock.object(OBJECT_NAME)
    unwrap(ob, rock.zones)
    mdl.finish(ob, rock_material("HellRock", albedo, emissive), strip_uvs=False)
    coll_ob = coll.object(COLLIDER_NAME)     # Godot: StaticBody3D + ConcavePolygonShape3D
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons)))
    return [ob, coll_ob]


def build():
    rock, cols, widest = _grate(_Rng(SEED))
    objects = _finish(rock, _collider(cols))
    print("MDL STATS width=%.2f height=%.2f bars=%d widest_gap=%.3f"
          % (2.0 * HALF_W, HEIGHT, BARS, widest))
    return objects


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
