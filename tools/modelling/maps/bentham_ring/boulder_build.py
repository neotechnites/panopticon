"""
PANOPTICON -- boulder: a rock platform standing in lava. 2.0 m across, 1.2 m
tall, a flat-ish top you land on, rough jittered sides. Origin at base centre,
Blender +Z = Godot +Y. Textured with hell_rock_albedo.png, the one hell rock tile.

Contract: one mesh `Boulder` (1 surface), plus `BoulderCollision-colonly`, a
plain 8-sided frustum with a dead-flat top at z=1.2 so the player never snags.
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
NAME = "boulder"
OBJECT_NAME = "Boulder"
COLLIDER_NAME = "BoulderCollision-colonly"

SIDES = 8
HEIGHT = 0.7
RADIUS = 1.3                      # 2.6 m diameter: a platform you can land on
PROFILE = [(0.00, 0.80), (0.40, 1.00), (0.85, 1.02), (1.00, 1.00)]   # (t, r/RADIUS): flat-topped, no taper
R_MAX = 1.36                      # after jitter: 2.0 m across the 8-gon's flats, near enough
ANG_JAG = 0.22                    # per side, held for every ring: vertical edges stay vertical
R_JAG = 0.12                      # per vertex radial jitter, as a fraction of RADIUS
TOP_JAG = 0.0                     # top rim z jitter: flat-ish, not flat
Z_JAG = 0.10                      # mid-ring z jitter per vertex: a boulder, not a barrel
SHADE_T = -0.04                   # a side facet recessed by more than this goes dark
EMBER_T = -0.08                   # ... lowest band only: a cleft with heat in it
SEED = 4410217

COLL_TOP_R = 1.25                 # flat landing disc: nearly the full top
COLL_BASE_R = 1.30

TEX_SIZE = 128
TEX_SEED = 6661031
ROCK_ROUGHNESS = 0.95
UV_SCALE = 0.45                   # facets are ~1 m here, not 5 m
UV_PAD = 1.5 / TEX_SIZE

ZONE_ROCK  = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)
ZONE_EMBER = (0.0, 0.0, 0.5, 0.5)

FACING_YAW = 0.0

# =============================================================================
# RNG -- seeded, so every rebuild lays the same UVs
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


def _rock(r):
    m = _Mesh()
    ang = [(i + 0.5) * 2.0 * math.pi / SIDES + ANG_JAG * r.sf() for i in range(SIDES)]
    rings, jag = [], []
    for k, (t, rf) in enumerate(PROFILE):
        ring, jg = [], []
        for i in range(SIDES):
            j = r.sf() * R_JAG
            if k == 0:
                j = min(j, 0.0)                       # foot never pokes past the base
            rr = min(RADIUS * (rf + j), R_MAX)
            z = HEIGHT * t
            if k == len(PROFILE) - 1:
                z += TOP_JAG * r.sf()
            elif k > 0:
                z += Z_JAG * r.sf()
            ring.append(m.v((rr * math.cos(ang[i]), rr * math.sin(ang[i]), z)))
            jg.append(j)
        rings.append(ring)
        jag.append(jg)
    for k in range(len(PROFILE) - 1):
        lo, hi = rings[k], rings[k + 1]
        for i in range(SIDES):
            q = (i + 1) % SIDES
            am = 0.5 * (ang[i] + ang[q] + (2.0 * math.pi if q == 0 else 0.0))
            want = (math.cos(am), math.sin(am), 0.0)
            recess = 0.5 * (jag[k][i] + jag[k + 1][i]) + 0.5 * (jag[k][q] + jag[k + 1][q])
            zone = ZONE_ROCK
            if recess < EMBER_T and k == 0:
                zone = ZONE_EMBER
            elif recess < SHADE_T:
                zone = ZONE_SHADE
            m.quad(lo[i], lo[q], hi[q], hi[i], want, zone)
    top = rings[-1]
    centre = m.v((0.0, 0.0, HEIGHT))
    for i in range(SIDES):
        m.tri(centre, top[i], top[(i + 1) % SIDES], UP, ZONE_ROCK)
    return m


def _collider():
    c = _Mesh()
    ang = [(i + 0.5) * 2.0 * math.pi / SIDES for i in range(SIDES)]
    foot = [c.v((COLL_BASE_R * math.cos(a), COLL_BASE_R * math.sin(a), 0.0)) for a in ang]
    top = [c.v((COLL_TOP_R * math.cos(a), COLL_TOP_R * math.sin(a), HEIGHT)) for a in ang]
    for i in range(SIDES):
        q = (i + 1) % SIDES
        am = ang[i] + math.pi / SIDES
        c.quad(foot[i], foot[q], top[q], top[i], (math.cos(am), math.sin(am), 0.0), ZONE_ROCK)
    c.fan(top, UP, ZONE_ROCK)
    return c


def build():
    rock = _rock(_Rng(SEED))
    coll = _collider()


    ob = rock.object(OBJECT_NAME)
    unwrap(ob, rock.zones)
    mdl.finish(ob, bpy.data.materials.new("HellRock"), strip_uvs=False)
    tx.retile(ob, tx.hell_atlas_material(ROCK_ROUGHNESS))   # the one hell rock tile

    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons)))
    xs = [v[0] for v in rock.verts]
    zs = [v[2] for v in rock.verts]
    print("MDL STATS dia=%.2f height=%.2f" % (max(xs) - min(xs), max(zs)))
    return [ob, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
