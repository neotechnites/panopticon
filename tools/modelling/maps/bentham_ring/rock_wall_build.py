"""rock_wall -- an 8 m wall segment. Walls, the Split divider; 0.43 y-scale is crouch cover.

Low-poly PS1 hell rock, flat shaded, the hell rock tile. ORIGIN IS THE BASE
CENTRE: y=0 is the ground it sits on. 8.0 long (x) x 3.0 tall x 1.2 thick,
ragged top, cleaved faces. Blender +Z -> Godot +Y, +X -> +X, +Y -> -Z.

BUTTS END TO END: the two end faces at x = +-4.0 are flat, vertical and
identical (y +-0.6, z 0..3.0, ridge at y 0), with no jitter on any end vertex,
so a copy translated 8.0 m meets this one with no gap and no step.

Contract: one mesh "RockWall" (one surface, one UV set), plus
"RockWallCollision" -- a plain box shipped as a `-colonly` node, NOT the
jittered rock.
"""

import math
import os
import sys

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

NAME = "rock_wall"
OBJECT_NAME = "RockWall"
COLLIDER_NAME = "RockWallCollision-colonly"

LENGTH, HEIGHT, THICK = 8.0, 3.0, 1.2
SEGS      = 8           # columns at every metre; columns 0 and SEGS are the exact ends
MID_T     = 0.5
X_JAG     = 0.22        # interior column x shift, metres, held per column
Y_JAG     = 0.14        # face in/out, metres, held in runs along the wall
JAG_RUN   = (1, 3)
MID_BULGE = 0.05        # the middle row stands proud
MID_ZJAG  = 0.12
TOP_DROP  = (0.0, 0.40)     # front/back top verts sit this far below HEIGHT
RIDGE_RISE = (-0.05, 0.30)  # the ridge over HEIGHT
RIDGE_YJAG = 0.25

SHADE_BIAS = -0.06      # metres of recess
EMBER_BIAS = -0.11

SEED = 5510337
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


def _finish(rock, coll):
    """Texture, unwrap, material and the `-colonly` collider; returns [visual, collider]."""
    ob = rock.object(OBJECT_NAME)
    unwrap(ob, rock.zones)
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

def _wall(r):
    m = _Mesh()
    ncol = SEGS + 1
    hx, hy = LENGTH / 2.0, THICK / 2.0
    zmid = HEIGHT * MID_T
    end = lambda k: k in (0, SEGS)                      # noqa: E731

    xs = [-hx + LENGTH * k / SEGS + (0.0 if end(k) else r.sf() * X_JAG) for k in range(ncol)]
    # off[face][row][col]: +ve = proud. Rows: bottom, mid, top. Ends are exact.
    off = []
    for face in range(2):
        rows = _held(r, 3, ncol, Y_JAG, JAG_RUN)
        for k in range(ncol):
            rows[1][k] += MID_BULGE
            if end(k):
                rows[0][k] = rows[1][k] = rows[2][k] = 0.0
        off.append(rows)

    col = []
    for k in range(ncol):
        zm = zmid + (0.0 if end(k) else r.sf() * MID_ZJAG)
        zt = [HEIGHT - (0.0 if end(k) else TOP_DROP[0] + r.f() * (TOP_DROP[1] - TOP_DROP[0]))
              for _ in range(2)]
        ry = 0.0 if end(k) else r.sf() * RIDGE_YJAG
        rz = HEIGHT + (0.0 if end(k) else RIDGE_RISE[0] + r.f() * (RIDGE_RISE[1] - RIDGE_RISE[0]))
        f = off[0]
        b = off[1]
        col.append(dict(
            fb=m.v((xs[k], -hy - f[0][k], 0.0)),
            fm=m.v((xs[k], -hy - f[1][k], zm)),
            ft=m.v((xs[k], -hy - f[2][k], zt[0])),
            rg=m.v((xs[k], ry, rz)),
            bt=m.v((xs[k], hy + b[2][k], zt[1])),
            bm=m.v((xs[k], hy + b[1][k], zm)),
            bb=m.v((xs[k], hy + b[0][k], 0.0)),
        ))

    for k in range(SEGS):
        a, c = col[k], col[k + 1]
        f, b = off[0], off[1]
        fl = 0.25 * (f[0][k] + f[0][k + 1] + f[1][k] + f[1][k + 1])
        fu = 0.25 * (f[1][k] + f[1][k + 1] + f[2][k] + f[2][k + 1])
        bl = 0.25 * (b[0][k] + b[0][k + 1] + b[1][k] + b[1][k + 1])
        bu = 0.25 * (b[1][k] + b[1][k + 1] + b[2][k] + b[2][k + 1])
        m.quad(a["fb"], c["fb"], c["fm"], a["fm"], (0, -1, 0), _zone_of(fl, True))
        m.quad(a["fm"], c["fm"], c["ft"], a["ft"], (0, -1, 0), _zone_of(fu, False))
        m.quad(a["ft"], c["ft"], c["rg"], a["rg"], (0, 0, 1), ZONE_ROCK)
        m.quad(a["rg"], c["rg"], c["bt"], a["bt"], (0, 0, 1), ZONE_ROCK)
        m.quad(a["bt"], c["bt"], c["bm"], a["bm"], (0, 1, 0), _zone_of(bu, False))
        m.quad(a["bm"], c["bm"], c["bb"], a["bb"], (0, 1, 0), _zone_of(bl, True))
    for k, want in ((0, (-1, 0, 0)), (SEGS, (1, 0, 0))):
        e = col[k]
        # Fan from the proud mid vertex: from fb, fb-fm-ft is a 2-degree sliver. The base sits on the ground.
        m.fan([e["fm"], e["ft"], e["rg"], e["bt"], e["bm"], e["bb"], e["fb"]], want, ZONE_ROCK)
    return m


def _collider():
    """One box, the wall's nominal envelope. 12 tris."""
    c = _Mesh()
    c.box((-LENGTH / 2.0, -THICK / 2.0, 0.0), (LENGTH / 2.0, THICK / 2.0, HEIGHT), ZONE_ROCK)
    return c


def build():
    objects = _finish(_wall(_Rng(SEED)), _collider())
    print("MDL STATS length=%.1f height=%.1f thick=%.1f ends_x=+-%.1f"
          % (LENGTH, HEIGHT, THICK, LENGTH / 2.0))
    return objects


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
