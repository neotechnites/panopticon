"""block -- a squarish carved rock platform. 2.4 x 2.4 m footprint, 0.7 m
tall, dead-flat top, slightly irregular vertical sides with a small chamfer,
corners jittered a few cm off square. ORIGIN IS THE BASE CENTRE. Blender
+Z -> Godot +Y. Textured with hell_rock_albedo.png, the one hell rock tile.

Contract: one mesh "Block" (one surface, one UV set), plus "BlockCollision" --
a plain flat box the full top size, shipped as a `-colonly` node.
"""

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

NAME = "block"
OBJECT_NAME = "Block"
COLLIDER_NAME = "BlockCollision-colonly"

SIZE = 2.4               # footprint, x and y
HEIGHT = 0.7
CHAMFER_H = 0.06          # height of the bevel band below the top
CHAMFER_IN = 0.06         # inward inset of the chamfer ring, metres
CORNER_JAG = 0.035        # per-corner xy jitter: a few cm, corners not square

SEED = 3320119
UV_SCALE = 0.35
FACING_YAW = 0.0

# ---- UVs laid on the old 128 atlas; tx.retile moves them onto hell_rock ------
TEX_SIZE = 128
TEX_SEED = 6661031
ROCK_ROUGHNESS = 0.95
UV_PAD = 1.5 / TEX_SIZE

ZONE_ROCK = (0.0, 0.5, 0.5, 1.0)     # dark red rock, the body
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)    # near-black: facets that sit recessed
ZONE_CARVE = (0.5, 0.0, 1.0, 0.5)    # dressed stone, worn: the chamfer


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
        return self.n() >> 12

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
    coll_ob = coll.object(COLLIDER_NAME)     # Godot: StaticBody3D + CollisionShape3D
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons)))
    return [ob, coll_ob]


# =============================================================================
# THE ROCK -- a carved block: vertical walls, a small chamfer, a dead-flat top
# =============================================================================

def _block(r):
    m = _Mesh()
    h = SIZE / 2.0
    corners = [(-h, -h), (h, -h), (h, h), (-h, h)]
    jitter = [(r.sf() * CORNER_JAG, r.sf() * CORNER_JAG) for _ in range(4)]

    # base and wall-top share the same per-corner jitter: the wall stays a
    # flat, vertical facet even though the block is off-square.
    base = [m.v((cx + jx, cy + jy, 0.0)) for (cx, cy), (jx, jy) in zip(corners, jitter)]
    wall_top = [m.v((cx + jx, cy + jy, HEIGHT - CHAMFER_H))
                for (cx, cy), (jx, jy) in zip(corners, jitter)]

    # chamfer ring: inset toward the block's own corner direction, dead-flat z.
    chamfer = []
    for (cx, cy), (jx, jy) in zip(corners, jitter):
        sx = cx - (CHAMFER_IN if cx > 0 else -CHAMFER_IN)
        sy = cy - (CHAMFER_IN if cy > 0 else -CHAMFER_IN)
        chamfer.append(m.v((sx + jx * 0.5, sy + jy * 0.5, HEIGHT)))

    for i in range(4):
        j = (i + 1) % 4
        ox, oy = corners[i][0] + corners[j][0], corners[i][1] + corners[j][1]
        m.quad(base[i], base[j], wall_top[j], wall_top[i], (ox, oy, 0.0), ZONE_ROCK)
        m.quad(wall_top[i], wall_top[j], chamfer[j], chamfer[i], (ox, oy, 0.4), ZONE_CARVE)

    m.fan(chamfer, (0.0, 0.0, 1.0), ZONE_ROCK)      # dead-flat top, 2 tris
    f0 = len(m.faces)
    m.fan(base, (0.0, 0.0, -1.0), ZONE_SHADE)
    m.buried = list(range(f0, len(m.faces)))   # the base sits on the ground: dropped after unwrap
    return m


def _collider():
    """One flat box, the full top size. 12 tris."""
    c = _Mesh()
    h = SIZE / 2.0
    c.box((-h, -h, 0.0), (h, h, HEIGHT), ZONE_ROCK)
    return c


def build():
    objects = _finish(_block(_Rng(SEED)), _collider())
    print("MDL STATS size=%.1fx%.1fx%.1f chamfer_h=%.2f chamfer_in=%.2f"
          % (SIZE, SIZE, HEIGHT, CHAMFER_H, CHAMFER_IN))
    return objects


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
