"""portal -- the finish line. A ragged rock arch with an emissive swirling disc in it.

Low-poly PS1 hell rock, flat shaded, the hell rock tile; the disc wears
hell_props_albedo.png, the swirl, as albedo and emission.
4.5 m wide, 4.0 m tall, 0.8 m deep. ORIGIN IS THE BASE CENTRE: z=0 is the
ground. The disc lies in the Blender XZ plane (Godot local XY) at y=0, so a
runner passes through along Godot local Z. Blender +Z -> Godot +Y, +Y -> -Z.

Contract: one mesh "Portal" (UVMap, plus "Wave": the lava wave's share), plus "PortalCollision"
-- three boxes (two uprights, a lintel) shipped as a `-colonly` node. The
disc has NO collision.
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
DISC_RINGS = 6          # the disc: rings in from the rim, so the wave has vertices to travel over
DISC_SEGS = 24          # rim vertices: the arch's corners plus points along its edges

COL_UP_W  = 0.95        # upright box width, from the outer edge in
COL_UP_H  = 2.8
SEED = 7130941
UV_SCALE = 0.30
FACING_YAW = 0.0

# ---- UVs laid on the old 128 atlas; tx.retile moves them onto hell_rock ------
TEX_SIZE       = 128
TEX_SEED       = 6661031
ROCK_ROUGHNESS = 0.95
ROCK_METALLIC  = 0.0
UV_PAD         = 1.5 / TEX_SIZE

ZONE_ROCK   = (0.0, 0.5, 0.5, 1.0)   # dark red rock, the body
ZONE_SHADE  = (0.5, 0.5, 1.0, 1.0)   # near-black: recessed facets, the inner faces
ZONE_PORTAL = (0.0, 0.0, 0.5, 0.5)   # the old ember quarter: retile sends it onto hell_props


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


PORTAL_ALPHA = 0.55
WAVE_RAMP = 0.5         # metres in from the rim the wave reaches full height; the rim is pinned


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
    bsdf.inputs["Alpha"].default_value = PORTAL_ALPHA   # see-through swirl: glTF BLEND
    mat.blend_method = "BLEND"
    mat.show_transparent_back = False                   # no depth write: no mote sorting flicker
    mat.use_backface_culling = False                    # drawn from both sides
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

def unwrap(ob, zones, planar=None, seed=0, count=None):
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + seed * 7919 + (len(me.polygons) if count is None else count))
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
    # the disc: one sheet at y=0 (drawn double-sided), rings shrinking to a centre;
    # the old front fan's count still seeds the rock UVs, so they stay as they were
    m.uv_faces = len(m.faces) + n
    m.rim = _rim(inner)
    rings = [[m.v((x, 0.0, z)) for (x, z) in m.rim]]
    for k in range(1, DISC_RINGS):
        f = 1.0 - k / float(DISC_RINGS)
        rings.append([m.v((x * f, 0.0, DISC_CENTRE_Z + (z - DISC_CENTRE_Z) * f)) for (x, z) in m.rim])
    for a, b in zip(rings, rings[1:]):
        for j in range(DISC_SEGS):
            jj = (j + 1) % DISC_SEGS
            m.quad(a[j], a[jj], b[jj], b[j], (0.0, -1.0, 0.0), ZONE_PORTAL)
    m.fan(rings[-1], (0.0, -1.0, 0.0), ZONE_PORTAL, centre=m.v((0.0, 0.0, DISC_CENTRE_Z)))
    return m


def _rim(outline):
    """The opening's outline as DISC_SEGS points: every corner kept, the longest edges split."""
    cuts = [1] * len(outline)
    seg = lambda i: math.dist(outline[i], outline[(i + 1) % len(outline)]) / cuts[i]
    for _ in range(DISC_SEGS - len(outline)):
        cuts[max(range(len(outline)), key=seg)] += 1
    pts = []
    for i, (ax, az) in enumerate(outline):
        bx, bz = outline[(i + 1) % len(outline)]
        pts += [(ax + (bx - ax) * c / cuts[i], az + (bz - az) * c / cuts[i]) for c in range(cuts[i])]
    return pts


def _wave_uv(ob, ring):
    """UV2.x: the lava wave's share, 0 on the disc's rim (and all rock), rising WAVE_RAMP in."""
    me = ob.data
    glow = {i for i, mt in enumerate(me.materials) if mt.name.split(".")[0] == "PortalGlow"}
    disc = {v for p in me.polygons if p.material_index in glow for v in p.vertices}

    def seg(px, pz, a, b):
        ex, ez = b[0] - a[0], b[1] - a[1]
        t = max(0.0, min(1.0, ((px - a[0]) * ex + (pz - a[1]) * ez) / max(ex * ex + ez * ez, 1e-12)))
        return math.hypot(px - a[0] - t * ex, pz - a[1] - t * ez)

    w = {}
    for v in disc:
        co = me.vertices[v].co
        d = min(seg(co.x, co.z, ring[k], ring[(k + 1) % len(ring)]) for k in range(len(ring)))
        w[v] = min(1.0, d / WAVE_RAMP)
    layer = me.uv_layers.new(name="Wave")
    layer.data.foreach_set("uv", [c for lp in me.loops for c in (w.get(lp.vertex_index, 0.0), 0.0)])
    me.uv_layers[0].active = True
    me.uv_layers[0].active_render = True
    print("MDL STATS wave disc_verts=%d peak=%.2f" % (len(disc), max(w.values())))


def _collider():
    """Two uprights and a lintel: 36 tris. The disc is not here."""
    c = _Mesh()
    c.box((-HALF_W, -HALF_D, 0.0), (-HALF_W + COL_UP_W, HALF_D, COL_UP_H), ZONE_ROCK)
    c.box((HALF_W - COL_UP_W, -HALF_D, 0.0), (HALF_W, HALF_D, COL_UP_H), ZONE_ROCK)
    c.box((-HALF_W, -HALF_D, COL_UP_H), (HALF_W, HALF_D, HEIGHT), ZONE_ROCK)
    return c


def build():
    glow = tx.props_image()   # hell_props: the swirl, its own file
    rock = _portal(_Rng(SEED))
    ob = rock.object(OBJECT_NAME)
    unwrap(ob, rock.zones, count=rock.uv_faces,
           planar={ZONE_PORTAL: (0, 2, -IN_HALF_W, 0.0, IN_HALF_W, IN_SPRING + IN_RISE)})
    mdl.finish(ob, bpy.data.materials.new("HellRock"), strip_uvs=False)
    tx.retile(ob, tx.hell_atlas_material(ROCK_ROUGHNESS),
              glow=(ZONE_PORTAL, rock_material("PortalGlow", glow, glow)))   # it glows its own albedo
    _wave_uv(ob, rock.rim)
    coll_ob = _collider().object(COLLIDER_NAME)   # Godot: StaticBody3D + ConcavePolygonShape3D
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d width=%.2f height=%.2f depth=%.2f"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), 2 * HALF_W, HEIGHT, 2 * HALF_D))
    return [ob, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
