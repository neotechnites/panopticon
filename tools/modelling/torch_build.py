"""torch -- a wall sconce. Dark iron-rock bracket 0.5 m tall, a 0.4 m flame on top.

Low-poly PS1 hell, flat shaded, the tower's atlas with the ember quarter
repainted as flame (strongly emissive orange-yellow). ORIGIN IS THE CENTRE OF
THE BRACKET'S BACK FACE: y=0 is the wall, the torch projects to -Y, which is
Godot local +Z, out into the room. Blender +Z -> Godot +Y, +X -> +X, +Y -> -Z.

Contract: one mesh "Torch" (one surface, one UV set). NO collision.
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

NAME = "torch"
OBJECT_NAME = "Torch"

PLATE_HW   = 0.09       # wall plate half width; 0.5 m tall, 0.05 m proud of the wall
PLATE_HH   = 0.25
PLATE_D    = 0.05
ARM_FROM   = (0.0, -0.05, -0.12)   # the arm rises from the plate to the cup
ARM_TO     = (0.0, -0.24, 0.12)
ARM_R      = (0.045, 0.035)
CUP_R      = (0.05, 0.10)          # bottom, top
CUP_Z      = (0.12, 0.25)
FLAME_SIDES = 5
FLAME_RINGS = [         # (z, radius); the tip closes it
    (0.24, 0.07),
    (0.34, 0.11),
    (0.46, 0.07),
    (0.56, 0.035),
]
FLAME_TIP   = 0.65
FLAME_JAG   = 0.28      # radial, fraction of ring radius
FLAME_ANG_JAG = 0.35
FLAME_LEAN  = 0.05      # per ring, metres: a flame is never plumb

SEED = 7130931
TEX_ALBEDO   = "torch_albedo"
TEX_EMISSIVE = "torch_emissive"
UV_SCALE = 0.9          # facets are ~0.1 m: the atlas texels must still read
FACING_YAW = 0.0

# ---- atlas: tower_build.py's painter, same seed, so it is the same rock -----
TEX_SIZE       = 128
TEX_SEED       = 6661031
ROCK_ROUGHNESS = 0.95
ROCK_METALLIC  = 0.0
UV_PAD         = 1.5 / TEX_SIZE

ZONE_ROCK   = (0.0, 0.5, 0.5, 1.0)   # dark red rock
ZONE_SHADE  = (0.5, 0.5, 1.0, 1.0)   # near-black: the bracket
ZONE_CARVE  = (0.5, 0.0, 1.0, 0.5)   # dressed stone (unused; atlas layout kept)
ZONE_FLAME  = (0.0, 0.0, 0.5, 0.5)   # the ember quarter, repainted as fire


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


def _lerp3(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _paint_flame(c, r, box):
    """Bottom white-yellow, orange in the middle, red tongues at the top. All glows."""
    x0, y0, x1, y1 = box
    h = y1 - y0
    for y in range(y0, y1):
        t = (y - y0) / float(h - 1)
        if t < 0.5:
            base = _lerp3((255, 232, 130), (255, 140, 22), t / 0.5)
        else:
            base = _lerp3((255, 140, 22), (214, 44, 10), (t - 0.5) / 0.5)
        for x in range(x0, x1):
            k = r.i(-14, 14)
            col = tuple(max(0, min(255, v + k)) for v in base)
            c.put(x, y, col, col)
    for _ in range(18):                                   # rising streaks
        x, y = r.i(x0, x1 - 1), r.i(y0, y0 + h // 2)
        hot = r.pick([(255, 236, 150), (255, 200, 80)])
        for _step in range(r.i(6, 18)):
            c.put(x, y, hot, hot)
            y += 1
            x += r.i(-1, 1)
            if not (x0 <= x < x1 and y < y1):
                break
    for _ in range(12):                                   # dark licks near the tips
        x, y = r.i(x0, x1 - 2), r.i(y0 + 2 * h // 3, y1 - 3)
        c.rect(x, y, x + 2, y + 3, (120, 20, 6), (80, 10, 2))


def build_texture():
    """Paint the atlas and hand back (albedo_image, emissive_image)."""
    c = _Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    _paint_rock(c, r, _rect_of(ZONE_ROCK, TEX_SIZE))
    _paint_shade(c, r, _rect_of(ZONE_SHADE, TEX_SIZE))
    _paint_carve(c, r, _rect_of(ZONE_CARVE, TEX_SIZE))
    _paint_flame(c, r, _rect_of(ZONE_FLAME, TEX_SIZE))
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
# THE SCONCE
# =============================================================================

def _ring(m, cx, cy, z, rad, angs):
    return [m.v((cx + rad * math.cos(a), cy + rad * math.sin(a), z)) for a in angs]


def _band(m, lo, hi, angs, zone, cx=0.0, cy=0.0):
    """Quads between two rings, normals outward from (cx, cy)."""
    n = len(lo)
    for i in range(n):
        j = (i + 1) % n
        mid = 0.5 * (angs[i] + angs[j] + (2.0 * math.pi if j == 0 else 0.0))
        m.quad(lo[i], lo[j], hi[j], hi[i], (math.cos(mid), math.sin(mid), 0.0), zone)


def _torch(r):
    m = _Mesh()
    # wall plate: five faces, the back is the wall
    x0, x1 = -PLATE_HW, PLATE_HW
    z0, z1 = -PLATE_HH, PLATE_HH
    y0, y1 = -PLATE_D, 0.0
    p = [m.v(c) for c in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                          (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
    m.quad(p[0], p[1], p[2], p[3], (0, 0, -1), ZONE_SHADE)
    m.quad(p[4], p[5], p[6], p[7], (0, 0, 1), ZONE_SHADE)
    m.quad(p[0], p[1], p[5], p[4], (0, -1, 0), ZONE_SHADE)
    m.quad(p[1], p[2], p[6], p[5], (1, 0, 0), ZONE_SHADE)
    m.quad(p[3], p[0], p[4], p[7], (-1, 0, 0), ZONE_SHADE)
    # arm: a tapered 4-sided bar, plate to cup
    angs4 = [math.pi / 4.0 + i * math.pi / 2.0 for i in range(4)]
    lo = _ring(m, ARM_FROM[0], ARM_FROM[1], ARM_FROM[2], ARM_R[0], angs4)
    hi = _ring(m, ARM_TO[0], ARM_TO[1], ARM_TO[2], ARM_R[1], angs4)
    _band(m, lo, hi, angs4, ZONE_SHADE)
    # cup: a 5-sided frustum, open at the top (the flame sits in it)
    angs5 = [2.0 * math.pi * (i + 0.5) / 5.0 for i in range(5)]
    cb = _ring(m, ARM_TO[0], ARM_TO[1], CUP_Z[0], CUP_R[0], angs5)
    ct = _ring(m, ARM_TO[0], ARM_TO[1], CUP_Z[1], CUP_R[1], angs5)
    _band(m, cb, ct, angs5, ZONE_SHADE)
    m.fan(cb, (0.0, 0.0, -1.0), ZONE_SHADE)
    # flame: ragged 5-sided tongues, leaning, tip closed
    angs = [2.0 * math.pi * (i + r.sf() * FLAME_ANG_JAG) / FLAME_SIDES for i in range(FLAME_SIDES)]
    rings = []
    cx, cy = ARM_TO[0], ARM_TO[1]
    for k, (z, rad) in enumerate(FLAME_RINGS):
        if k > 0:
            cx += r.sf() * FLAME_LEAN
            cy += r.sf() * FLAME_LEAN
        ring = []
        for a in angs:
            rr = rad * (1.0 + (r.sf() * FLAME_JAG if k > 0 else 0.0))
            ring.append(m.v((cx + rr * math.cos(a), cy + rr * math.sin(a), z)))
        rings.append(ring)
    tip = m.v((cx + r.sf() * FLAME_LEAN, cy + r.sf() * FLAME_LEAN, FLAME_TIP))
    for k in range(len(rings) - 1):
        _band(m, rings[k], rings[k + 1], angs, ZONE_FLAME)
    for i in range(FLAME_SIDES):
        j = (i + 1) % FLAME_SIDES
        mid = 0.5 * (angs[i] + angs[j] + (2.0 * math.pi if j == 0 else 0.0))
        m.tri(rings[-1][i], rings[-1][j], tip, (math.cos(mid), math.sin(mid), 0.3), ZONE_FLAME)
    m.fan(rings[0], (0.0, 0.0, -1.0), ZONE_FLAME)
    return m


def build():
    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    rock = _torch(_Rng(SEED))
    ob = rock.object(OBJECT_NAME)
    fx = 0.16
    unwrap(ob, rock.zones,
           planar={ZONE_FLAME: (0, 2, -fx, FLAME_RINGS[0][0], fx, FLAME_TIP)})
    mdl.finish(ob, rock_material("HellRock", albedo, emissive), strip_uvs=False)
    print("MDL STATS visual_tris=%d collision_tris=0 bracket=%.2f flame=%.2f"
          % (len(ob.data.polygons), 2.0 * PLATE_HH, FLAME_TIP - FLAME_RINGS[0][0]))
    return [ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
