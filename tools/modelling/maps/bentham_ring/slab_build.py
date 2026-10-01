"""slab -- a low thick rock block. Thick cover; the rest-pocket element.

Low-poly PS1 hell rock, flat shaded, the hell rock tile. ORIGIN IS THE BASE
CENTRE: y=0 is the ground it sits on. 3.0 wide (x) x 1.6 tall x 1.0 deep,
rough top. Blender +Z -> Godot +Y, +X -> +X, +Y -> -Z.

Contract: one mesh "Slab" (one surface, one UV set), plus "SlabCollision" --
a plain box shipped as a `-colonly` node, NOT the jittered rock.
"""

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import mdl  # noqa: E402
import texel as tx  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "slab"
OBJECT_NAME = "Slab"
COLLIDER_NAME = "SlabCollision-colonly"

WIDTH, HEIGHT, DEPTH = 3.0, 1.6, 1.0
PERIM = [               # plan outline, CCW: corners plus edge points
    (-1.5, -0.5), (-0.5, -0.5), (0.5, -0.5), (1.5, -0.5), (1.5, 0.0),
    (1.5, 0.5), (0.5, 0.5), (-0.5, 0.5), (-1.5, 0.5), (-1.5, 0.0),
]
MID_T     = 0.55        # height fraction of the middle ring
JAG       = 0.07        # in/out per column and ring, fraction of the point's radius
JAG_RUN   = (1, 2)
XY_JAG    = 0.10        # per column, held for the whole height
MID_BULGE = 0.04        # the middle ring stands proud
TOP_PULL  = -0.05       # the top ring is weathered back
TOP_ZJAG  = (-0.16, 0.06)   # top ring z range about HEIGHT
MID_ZJAG  = 0.10
CROWN     = 0.12        # the top's centre vertex above HEIGHT: a rough top

SHADE_BIAS = -0.04
EMBER_BIAS = -0.09

COL_H = 1.55            # collider box top; the top's average height

SEED = 8221407
UV_SCALE = 0.30
FACING_YAW = 0.0

# ---- UVs laid on the old 128 atlas; tx.retile moves them onto hell_rock ------
TEX_SIZE       = 128
TEX_SEED       = 6661031
ROCK_ROUGHNESS = 0.95
UV_PAD         = 1.5 / TEX_SIZE

ZONE_ROCK   = (0.0, 0.5, 0.5, 1.0)   # dark red rock, the body
ZONE_SHADE  = (0.5, 0.5, 1.0, 1.0)   # near-black: facets that sit recessed
ZONE_EMBER  = (0.0, 0.0, 0.5, 0.5)   # split open by brimstone -- the only glow


# =============================================================================
# RNG -- seeded, so every rebuild lays the same UVs
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


def _zone_of(bias, low_band):
    """Recessed facets go dark; deeply recessed ones low down split open."""
    if bias < EMBER_BIAS and low_band:
        return ZONE_EMBER
    if bias < SHADE_BIAS:
        return ZONE_SHADE
    return ZONE_ROCK


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


def _drop_faces(ob, idx):
    """Delete faces no camera reaches, after unwrap so every kept face keeps its texels."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in idx], context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def _finish(rock, coll):
    """Texture, unwrap, material and the `-colonly` collider; returns [visual, collider]."""
    ob = rock.object(OBJECT_NAME)
    unwrap(ob, rock.zones)
    _drop_faces(ob, rock.buried)
    mdl.finish(ob, bpy.data.materials.new("HellRock"), strip_uvs=False)
    tx.retile(ob, tx.hell_atlas_material(ROCK_ROUGHNESS))   # the one hell rock tile
    coll_ob = coll.object(COLLIDER_NAME)     # Godot: StaticBody3D + ConcavePolygonShape3D
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons)))
    return [ob, coll_ob]


# =============================================================================
# THE ROCK
# =============================================================================

def _slab(r):
    m = _Mesh()
    n = len(PERIM)
    zs = [0.0, HEIGHT * MID_T, HEIGHT]
    bias = _held(r, n, 3, JAG, JAG_RUN)
    for i in range(n):
        bias[i][1] += MID_BULGE
        bias[i][2] += TOP_PULL
    shift = [(r.sf() * XY_JAG, r.sf() * XY_JAG) for _ in range(n)]
    rings = []
    for k in range(3):
        ring = []
        for i in range(n):
            px, py = PERIM[i]
            s = 1.0 + bias[i][k]
            if k == 0:
                zj = 0.0
            elif k == 1:
                zj = r.sf() * MID_ZJAG
            else:
                zj = TOP_ZJAG[0] + r.f() * (TOP_ZJAG[1] - TOP_ZJAG[0])
            ring.append(m.v((px * s + shift[i][0], py * s + shift[i][1], zs[k] + zj)))
        rings.append(ring)
    crown = m.v((r.sf() * 0.3, r.sf() * 0.1, HEIGHT + CROWN))

    for k in range(2):
        for i in range(n):
            j = (i + 1) % n
            ox = PERIM[i][0] + PERIM[j][0]
            oy = PERIM[i][1] + PERIM[j][1]
            b = 0.25 * (bias[i][k] + bias[j][k] + bias[i][k + 1] + bias[j][k + 1])
            m.quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i],
                   (ox, oy, 0.0), _zone_of(b, k == 0))
    m.fan(rings[2], (0.0, 0.0, 1.0), ZONE_ROCK, centre=crown)
    f0 = len(m.faces)
    m.fan(rings[0], (0.0, 0.0, -1.0), ZONE_SHADE)
    m.buried = list(range(f0, len(m.faces)))   # the base sits on the ground: dropped after unwrap
    return m


def _collider():
    """One box. 12 tris."""
    c = _Mesh()
    c.box((-WIDTH / 2.0, -DEPTH / 2.0, 0.0), (WIDTH / 2.0, DEPTH / 2.0, COL_H), ZONE_ROCK)
    return c


def build():
    objects = _finish(_slab(_Rng(SEED)), _collider())
    print("MDL STATS size=%.1fx%.1fx%.1f collider_top=%.2f" % (WIDTH, HEIGHT, DEPTH, COL_H))
    return objects


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
