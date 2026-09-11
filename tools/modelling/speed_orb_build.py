"""speed_orb -- the race power-up: a fist-sized ember/soul orb, floating.

A faceted icosahedron (20 tris) so the geometry itself reads as a cracked
shell; the atlas paints each facet as a bright emissive ember core scarred by
dark, non-emissive crack lines. Origin at the centre -- it is a pickup a
script spins and bobs about its own middle, not a floor object.

Contract: one mesh "SpeedOrb" (one surface, one UV set). NO collision -- the
pickup script (scripts/match/speed_powerup.gd) owns its own trigger volume.
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
NAME = "speed_orb"
OBJECT_NAME = "SpeedOrb"

RADIUS = 0.05              # 10 cm diameter: fist-sized

TEX_SIZE = 64
TEX_SEED = 5551212
UV_SCALE = 12.0             # face edges (~0.055 m) fill most of the atlas
UV_PAD = 1.5 / TEX_SIZE
CRACK_COUNT = 12
CRACK_STEPS = (28, 46)

ROUGHNESS = 0.65
METALLIC = 0.0

CORE_SHADES = [(255, 150, 30), (255, 120, 24), (255, 96, 14), (230, 70, 6)]
CORE_HOT = [(255, 210, 120), (255, 170, 70)]
SHELL_DARK = [(28, 10, 9), (18, 6, 6), (36, 13, 11)]
MOTE = (255, 255, 210)

FACING_YAW = 0.0

# =============================================================================
# GEOMETRY -- a regular icosahedron; the "want" normal is each face's own
# centroid direction, since the shape is convex and centred on the origin.
# =============================================================================

_PHI = (1.0 + 5.0 ** 0.5) / 2.0

_RAW_VERTS = [
    (-1.0, _PHI, 0.0), (1.0, _PHI, 0.0), (-1.0, -_PHI, 0.0), (1.0, -_PHI, 0.0),
    (0.0, -1.0, _PHI), (0.0, 1.0, _PHI), (0.0, -1.0, -_PHI), (0.0, 1.0, -_PHI),
    (_PHI, 0.0, -1.0), (_PHI, 0.0, 1.0), (-_PHI, 0.0, -1.0), (-_PHI, 0.0, 1.0),
]

FACES = [
    (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
    (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
    (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
    (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
]


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
    """Faces carry an atlas zone; winding is fixed against a wanted normal."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.zones = []

    def v(self, p):
        self.verts.append(tuple(p))
        return len(self.verts) - 1

    def tri(self, a, b, c, want, zone):
        idx = [a, b, c]
        pts = [self.verts[j] for j in idx]
        n = _newell(pts)
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        self.faces.append(tuple(idx))
        self.zones.append(zone)

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


def _build_shell():
    m = _Mesh()
    verts = [tuple(c * RADIUS / math.sqrt(1.0 + _PHI * _PHI) for c in v) for v in _RAW_VERTS]
    idx = [m.v(v) for v in verts]
    zone = (0.0, 0.0, 1.0, 1.0)
    for a, b, c in FACES:
        centroid = tuple((verts[a][i] + verts[b][i] + verts[c][i]) / 3.0 for i in range(3))
        m.tri(idx[a], idx[b], idx[c], centroid, zone)
    return m


# =============================================================================
# TEXTURE -- a bright emissive ember core scarred by dark, unlit crack lines.
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

    def i(self, a, b):
        return a + int(self.f() * (b - a + 1))

    def pick(self, seq):
        return seq[self.i(0, len(seq) - 1)]


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


def _fill(c, r, box, shades, glow=None):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            k = r.i(0, len(shades) - 1)
            c.put(x, y, shades[k], glow[k] if glow else None)


def _shatter(c, r, box, shades, count, minsz, maxsz, glow=None):
    x0, y0, x1, y1 = box
    for _ in range(count):
        w = r.i(minsz, maxsz)
        h = max(minsz, min(maxsz, w + r.i(-1, 1)))
        x, y = r.i(x0, x1 - w - 1), r.i(y0, y1 - h - 1)
        k = r.i(0, len(shades) - 1)
        c.rect(x, y, x + w, y + h, shades[k], glow[k] if glow else None)


def _walk_crack(c, r, x0, y0, steps):
    """A dark, non-emissive fissure -- the shell showing through the glow."""
    x, y = x0, y0
    for _ in range(steps):
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if dx == 0 and dy == 0 or r.f() < 0.5:
                    c.put(x + dx, y + dy, r.pick(SHELL_DARK), (0, 0, 0))
        x += r.i(-1, 1)
        y += r.i(-1, 1)
        if not (0 <= x < c.w and 0 <= y < c.h):
            break


def _make_images(c):
    images = []
    for name, buf in (("speed_orb_albedo", c.alb), ("speed_orb_emissive", c.emi)):
        img = bpy.data.images.new(name, TEX_SIZE, TEX_SIZE, alpha=False)
        img.colorspace_settings.name = "sRGB"
        img.pixels.foreach_set(buf)
        img.update()
        images.append(img)
    return images[0], images[1]


def build_texture():
    c = _Canvas(TEX_SIZE)
    r = _Rng(TEX_SEED)
    box = (0, 0, TEX_SIZE, TEX_SIZE)
    _fill(c, r, box, CORE_SHADES, CORE_SHADES)
    _shatter(c, r, box, CORE_HOT, 16, 3, 8, CORE_HOT)
    for _ in range(CRACK_COUNT):
        _walk_crack(c, r, r.i(0, TEX_SIZE - 1), r.i(0, TEX_SIZE - 1), r.i(*CRACK_STEPS))
    for _ in range(4):
        x, y = r.i(0, TEX_SIZE - 2), r.i(0, TEX_SIZE - 2)
        c.rect(x, y, x + 2, y + 2, MOTE, MOTE)
    return _make_images(c)


def ember_material(name, albedo, emissive):
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
    bsdf.inputs["Metallic"].default_value = METALLIC
    bsdf.inputs["Emission Strength"].default_value = 1.0  # no KHR extension, no Godot warning
    mat.diffuse_color = (0.6, 0.25, 0.05, 1.0)
    return mat


def unwrap(ob, zones):
    """Per-face planar projection into a random window of the shared zone --
    tower_build.py's scheme, trimmed to the one zone this orb needs."""
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + 7919 + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        u0, v0, u1, v1 = zones[pi]
        span_u = (u1 - u0) - 2.0 * UV_PAD
        span_v = (v1 - v0) - 2.0 * UV_PAD
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
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
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


def build():
    shell = _build_shell()
    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)

    ob = shell.object(OBJECT_NAME)
    unwrap(ob, shell.zones)
    mdl.finish(ob, ember_material("SpeedOrb", albedo, emissive), strip_uvs=False)

    print("MDL STATS visual_tris=%d" % len(ob.data.polygons))
    print("MDL STATS diameter=%.3f" % (2.0 * RADIUS))
    return [ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
