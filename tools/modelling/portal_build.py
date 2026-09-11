"""portal -- the finish line. A ragged rock arch with an emissive swirling disc in it.

Low-poly PS1 hell rock, flat shaded, the tower's atlas with the ember quarter
repainted as the portal swirl (deep red to bright orange, all emissive).
4.5 m wide, 4.0 m tall, 0.8 m deep. ORIGIN IS THE BASE CENTRE: z=0 is the
ground. The disc lies in the Blender XZ plane (Godot local XY) at y=0, so a
runner passes through along Godot local Z. Blender +Z -> Godot +Y, +Y -> -Z.

Contract: one mesh "Portal" (one surface, one UV set), plus "PortalCollision"
-- three boxes (two uprights, a lintel) shipped as a `-colonly` node. The
disc has NO collision.
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

NAME = "portal"
OBJECT_NAME = "Portal"
COLLIDER_NAME = "PortalCollision-colonly"

HALF_W   = 2.25         # 4.5 m wide
HEIGHT   = 4.0
HALF_D   = 0.4          # 0.8 m deep
IN_HALF_W = 1.35        # the opening: 2.7 m wide at the ground
IN_SPRING = 2.6         # where the opening starts to curve in
IN_RISE   = 0.55        # opening apex = IN_SPRING + IN_RISE
OUT_SPRING = 3.0        # outer apex = OUT_SPRING + (HEIGHT - OUT_SPRING)
SIDE_STEPS = 3          # profile points up each straight side (ground point included)
ARCH_STEPS = 7          # profile points over the top, both springings included
JAG_XZ  = 0.13          # metres, in the arch plane; ground points stay on the ground
JAG_Y   = 0.09          # metres, depth: the faces are not planar
SHADE_BIAS = 0.04       # front/back facets pushed back this much go dark
DISC_CENTRE_Z = 1.5

COL_UP_W  = 0.95        # upright box width, from the outer edge in
COL_UP_H  = 2.8
SEED = 7130941
TEX_ALBEDO   = "portal_albedo"
TEX_EMISSIVE = "portal_emissive"
UV_SCALE = 0.30
FACING_YAW = 0.0

# ---- atlas: tower_build.py's painter, same seed, so it is the same rock -----
TEX_SIZE       = 128
TEX_SEED       = 6661031
ROCK_ROUGHNESS = 0.95
ROCK_METALLIC  = 0.0
UV_PAD         = 1.5 / TEX_SIZE

ZONE_ROCK   = (0.0, 0.5, 0.5, 1.0)   # dark red rock, the body
ZONE_SHADE  = (0.5, 0.5, 1.0, 1.0)   # near-black: recessed facets, the inner faces
ZONE_CARVE  = (0.5, 0.0, 1.0, 0.5)   # dressed stone (unused; atlas layout kept)
ZONE_PORTAL = (0.0, 0.0, 0.5, 0.5)   # the ember quarter, repainted as the swirl

SWIRL_ARMS  = 3
SWIRL_TURNS = 2.6       # how many times an arm wraps from the rim to the core
SWIRL_WIDTH = 0.42      # fraction of an arm's band that is bright


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


def _paint_swirl(c, r, box):
    """A spiral of bright orange arms on deep red, white-hot core, dark rim. Emissive."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    cx = x0 + w / 2.0
    cy = y0 + h * (DISC_CENTRE_Z / (IN_SPRING + IN_RISE))
    for y in range(y0, y1):
        for x in range(x0, x1):
            dx, dy = (x + 0.5 - cx) / (w / 2.0), (y + 0.5 - cy) / (h / 2.0)
            rad = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            band = (ang * SWIRL_ARMS / (2.0 * math.pi) + rad * SWIRL_TURNS) % 1.0
            band = min(band, 1.0 - band) * 2.0            # 0 on the arm, 1 between
            if rad < 0.14:
                col = r.pick([(255, 226, 120), (255, 244, 170)])
            elif band < SWIRL_WIDTH * (1.0 - 0.5 * rad):
                col = r.pick([(255, 128, 20), (255, 96, 12), (255, 160, 40)])
            elif band < SWIRL_WIDTH * (1.0 - 0.5 * rad) + 0.22:
                col = r.pick([(190, 40, 8), (210, 52, 10)])
            else:
                col = r.pick([(112, 8, 6), (92, 6, 6), (128, 12, 8)])
            if rad > 0.9:
                col = tuple(int(v * 0.45) for v in col)
            c.put(x, y, col, col)


def build_texture():
    """Paint the atlas and hand back (albedo_image, emissive_image)."""
    c = _Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    _paint_rock(c, r, _rect_of(ZONE_ROCK, TEX_SIZE))
    _paint_shade(c, r, _rect_of(ZONE_SHADE, TEX_SIZE))
    _paint_carve(c, r, _rect_of(ZONE_CARVE, TEX_SIZE))
    _paint_swirl(c, r, _rect_of(ZONE_PORTAL, TEX_SIZE))
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


def _held(r, nsides, nrings, jag, run):
    """Per-side bias held for runs of rings: it steps, like cleaved rock."""
    out = [[0.0] * nrings for _ in range(nsides)]
    for i in range(nsides):
        k = 0
        while k < nrings:
            n = r.i(*run)
            v = r.sf() * jag
            for kk in range(k, min(k + n, nrings)):
                out[i][kk] = v
            k += n
    return out


# =============================================================================
# UV -- per-face planar projection into a random window of its zone, except
# zones listed in ``planar``: those map the whole zone by (axis_i, axis_j) extent
# =============================================================================

def unwrap(ob, zones, planar=None, seed=0):
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + seed * 7919 + len(me.polygons))
    planar = planar or {}
    for pi, poly in enumerate(me.polygons):
        zone = zones[pi]
        u0, v0, u1, v1 = zone
        span_u = (u1 - u0) - 2.0 * UV_PAD
        span_v = (v1 - v0) - 2.0 * UV_PAD
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        if zone in planar:
            ii, jj, lo_i, lo_j, hi_i, hi_j = planar[zone]
            for li, co in zip(poly.loop_indices, cos):
                s = min(max((co[ii] - lo_i) / (hi_i - lo_i), 0.0), 1.0)
                t = min(max((co[jj] - lo_j) / (hi_j - lo_j), 0.0), 1.0)
                uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)
            continue
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


# =============================================================================
# THE ARCH
# =============================================================================

def _profile(half_w, spring, apex):
    """(x, z) points ground-left, up, over the top, down to ground-right."""
    pts = []
    for k in range(SIDE_STEPS):
        pts.append((-half_w, spring * k / float(SIDE_STEPS)))
    for k in range(ARCH_STEPS):
        a = math.pi * (1.0 - k / float(ARCH_STEPS - 1))
        pts.append((half_w * math.cos(a), spring + (apex - spring) * math.sin(a)))
    for k in range(SIDE_STEPS - 1, -1, -1):
        pts.append((half_w, spring * k / float(SIDE_STEPS)))
    return pts


def _jag(r, pts, keep_ground):
    out = []
    for (x, z) in pts:
        if keep_ground and z == 0.0:
            out.append((x + r.sf() * JAG_XZ * 0.5, 0.0))
        else:
            out.append((x + r.sf() * JAG_XZ, z + r.sf() * JAG_XZ))
    return out


def _portal(r):
    m = _Mesh()
    inner = _jag(r, _profile(IN_HALF_W, IN_SPRING, IN_SPRING + IN_RISE), True)
    outer = _jag(r, _profile(HALF_W, OUT_SPRING, HEIGHT), True)
    n = len(inner)
    # four vertex rows: inner/outer x front/back, depth jittered
    def row(pts, y):
        return [m.v((x, y + r.sf() * JAG_Y, z)) for (x, z) in pts]
    dy = [r.sf() * JAG_Y for _ in range(n)]
    i_f = [m.v((x, -HALF_D + dy[k], z)) for k, (x, z) in enumerate(inner)]
    i_b = [m.v((x, HALF_D + dy[k], z)) for k, (x, z) in enumerate(inner)]
    o_f = row(outer, -HALF_D)
    o_b = row(outer, HALF_D)
    for k in range(n - 1):
        f_zone = ZONE_SHADE if 0.5 * (dy[k] + dy[k + 1]) > SHADE_BIAS else ZONE_ROCK
        b_zone = ZONE_SHADE if 0.5 * (dy[k] + dy[k + 1]) < -SHADE_BIAS else ZONE_ROCK
        m.quad(i_f[k], i_f[k + 1], o_f[k + 1], o_f[k], (0, -1, 0), f_zone)
        m.quad(i_b[k], i_b[k + 1], o_b[k + 1], o_b[k], (0, 1, 0), b_zone)
        ox = 0.5 * (outer[k][0] + outer[k + 1][0])
        oz = 0.5 * (outer[k][1] + outer[k + 1][1]) - DISC_CENTRE_Z
        m.quad(o_f[k], o_f[k + 1], o_b[k + 1], o_b[k], (ox, 0.0, oz), ZONE_ROCK)
        m.quad(i_f[k], i_f[k + 1], i_b[k + 1], i_b[k], (-ox, 0.0, -oz),
               ZONE_SHADE if k % 3 else ZONE_ROCK)
    # the disc: the opening's own outline at y=0, fanned from the centre, both sides
    rim = [m.v((x, 0.0, z)) for (x, z) in inner]
    centre = m.v((0.0, 0.0, DISC_CENTRE_Z))
    m.fan(rim, (0.0, -1.0, 0.0), ZONE_PORTAL, centre=centre)
    m.fan(rim, (0.0, 1.0, 0.0), ZONE_PORTAL, centre=centre)
    return m


def _collider():
    """Two uprights and a lintel: 36 tris. The disc is not here."""
    c = _Mesh()
    c.box((-HALF_W, -HALF_D, 0.0), (-HALF_W + COL_UP_W, HALF_D, COL_UP_H), ZONE_ROCK)
    c.box((HALF_W - COL_UP_W, -HALF_D, 0.0), (HALF_W, HALF_D, COL_UP_H), ZONE_ROCK)
    c.box((-HALF_W, -HALF_D, COL_UP_H), (HALF_W, HALF_D, HEIGHT), ZONE_ROCK)
    return c


def build():
    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    rock = _portal(_Rng(SEED))
    ob = rock.object(OBJECT_NAME)
    unwrap(ob, rock.zones,
           planar={ZONE_PORTAL: (0, 2, -IN_HALF_W, 0.0, IN_HALF_W, IN_SPRING + IN_RISE)})
    mdl.finish(ob, rock_material("HellRock", albedo, emissive), strip_uvs=False)
    coll_ob = _collider().object(COLLIDER_NAME)   # Godot: StaticBody3D + ConcavePolygonShape3D
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d width=%.2f height=%.2f depth=%.2f"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), 2 * HALF_W, HEIGHT, 2 * HALF_D))
    return [ob, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
