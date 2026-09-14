"""tower_interior -- the inside of the guard tower: door, spiral stair, shaft.

A SEPARATE model from the tower rock. Same origin (guard-room floor = z 0),
so it drops into bentham_ring's Tower node at identity. The rock is READ from
tower_new.blend every build (never modified) to size the shaft: the lining
stays >= ROCK_MIN inside the rock's outer skin at every height. His shaft is
SOLID rock below the room (surveyed, not assumed): the rock is to be hollowed
to this lining later.

    door ..... at the foot (courtyard level), facing game bearing 0 deg (+X)
    stair .... spirals ccw up the shaft wall, landings each ~90 deg of turn
    top ...... a stairwell hole through the guard-room floor at the room's edge

Collision (`-colonly`) is the visible geometry itself (wall facets, floor,
ceiling, parapets, trim, chamber, drips) with one substitution: a smooth
helicoid RAMP under the treads, since the capsule cannot climb a 0.25 m riser.
The door passage is the hollow rock's own cut (tower_hollow_build.py); the
interior draws only a stone reveal round it.

    tools/modelling/model build tower_interior
    blender -b -P tower_interior_build.py -- --measure-only     # rock survey only
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

mdl.DEFAULTS["ground"] = False
mdl.DEFAULTS["world_grey"] = 0.30
mdl.DEFAULTS["world_strength"] = 0.90

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "tower_interior"
OBJECT_NAME = "TowerInterior"
COLLIDER_NAME = "TowerInteriorCollision-colonly"
BLEND_PATH = r"C:\dev\panopticon\assets\models\tower_new.blend"
ROCK_OBJECT = "TowerRock"

ROCK_MIN   = 0.40      # rock left between the lining and the rock's outer skin
FOOT_Z     = -36.40    # model z of the courtyard floor (rock foot is 0.87 lower)
SURVEY_DZ  = 1.0
SURVEY_NB  = 36

# shaft wall
NS         = 20        # facets round; 18 deg each, ~2 m at r 6.5
ANG_OFF    = -9.0      # degrees: facet 0 is centred on the door bearing
BAND_H     = 2.2       # target facet height
DOOR_BAND  = 3.2       # the bottom band is taller: it carries the door
JAG_R      = 0.15      # radial facet jitter, held in runs of rings
JAG_Z      = 0.25      # ring height jitter (free rings only)
JAG_RUN    = (1, 2)
WALL_T     = 0.30      # hidden outer skin this far behind the facets
SHADE_T    = -0.05     # mean recess past which a facet goes dark
EMBER_T    = -0.10     # ...and low down, splits open
EMBER_ABOVE = 9.0      # embers only within this height of the foot
CTRL_Z     = [-36.4, -32.0, -27.0, -22.0, -18.0, -15.0, -12.0, -9.0, -5.0, -1.0]
CTRL_BAND  = 2.6       # each control ring takes the rock's min over +- this

# stair
RISE       = 0.25
GOING      = 0.35      # along the walking line
WALK_OFF   = 0.50      # walking line this far off the parapet face
TREAD_CLEAR = 2.00     # clear width between the wall and the parapet
PARAPET_H  = 0.90
PARAPET_T  = 0.25
SOFFIT_D   = 0.45      # flight thickness under the nosing line
RAMP_DROP  = 0.12      # collider ramp this far under the nosing line
LANDING_EVERY = 90.0   # degrees of turn between landings
LANDING_LEN   = 2.50   # metres along the walking line
STAIR_START_DEG = 27.0 # bearing (Blender, ccw from +x) of the first tread; puts the
                       # stairwell hole on a pier between his windows (267.5 deg)
TOP_TREAD_LEN = 1.20
TOP_LIFT   = 0.03      # top tread sits this far above his floor: no z-fight

# top: stairwell hole and the throat under the room floor
SLAB_T     = 0.80      # shaft ceiling this far under the room floor
HEADROOM   = 2.40      # raked soffit over the last stretch of stair
HOLE_L     = 2.40      # hole length along the wall, at floor level
KERB_H     = 0.15
KERB_T     = 0.28
NC         = 40        # ceiling rim facets

# doorway
DOOR_H     = 2.20
DOOR_W     = 1.40
DOOR_BEARING = 0.0     # Blender deg; +X = game bearing 0 (ring_route: cos,sin in x,z)
TRIM_W     = 0.12      # stone reveal round the door, into the passage
DOOR_FACET = 0         # lining facet the door is cut from; ANG_OFF centres it
SKIN_GROW  = 0.06      # the skin's opening is this much wider than the lining's,
                       # so its cut edge dies inside the reveal
TRIM_D     = 0.60      # reveal depth: must pass the skin at +JAG_R+WALL_T
FLOOR_DROP = 0.03      # shaft floor this far under the courtyard: no z-fight with it
TOP_RAMP_LIFT = 0.17   # ramp ends this much above the nosing line: on his floor, not under it
TOP_LIFT_RUN  = 6.0    # ...gained over this much stair, so the pitch barely changes
SAG = 0.0              # facet chord sag at mid-facet, set from the plan

# windows: (bearing deg, z) wishes; each snaps to a wall facet clear of the stair
WINDOWS    = [(200.0, -29.0), (300.0, -23.0), (60.0, -12.0), (150.0, -5.0)]
SLOT_W     = 0.35
SLOT_H     = 1.50
STAIR_CLEAR = 2.6      # facet centre this far from any stair pass

# landing chamber
CHAMBER_LO, CHAMBER_HI = 0.30, 0.60   # fraction of the climb it may sit at
CHAMBER_H  = 3.40
CHAMBER_REC_MAX = 2.0
SHELF_D    = 2.20      # shelf reach into the shaft past the stair's inner edge
SHELF_T    = 0.45

# drips
N_STALACTITE = 22
N_STALAGMITE = 8
N_CHAMBER_DRIP = 5

SEED = 20260914

# ---- atlas: tower_build.py's painter, same seed, so it is the same rock -----
TEX_SIZE       = 128
TEX_SEED       = 6661031
TEX_ALBEDO     = "tower_interior_rock_albedo"
TEX_EMISSIVE   = "tower_interior_rock_emissive"
ROCK_ROUGHNESS = 0.95
ROCK_METALLIC  = 0.0
UV_SCALE       = 0.13
UV_PAD         = 1.5 / TEX_SIZE

ZONE_ROCK   = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE  = (0.5, 0.5, 1.0, 1.0)
ZONE_CARVE  = (0.5, 0.0, 1.0, 0.5)
ZONE_EMBER  = (0.0, 0.0, 0.5, 0.5)

TAU = 2.0 * math.pi
EYE_H = 1.65


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
        return self.n() >> 12

    def f(self):
        return self.n() / float(0x7FFFFFFF)

    def sf(self):
        return self.f() * 2.0 - 1.0

    def i(self, a, b):
        return a + self.bits() % (b - a + 1)

    def pick(self, seq):
        return seq[self.bits() % len(seq)]


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


def _rect_of(zone, size):
    u0, v0, u1, v1 = zone
    return (int(u0 * size), int(v0 * size), int(u1 * size), int(v1 * size))


def _fill(c, r, box, shades):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            c.put(x, y, r.pick(shades))


def _shatter(c, r, box, shades, count, minsz, maxsz):
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
        node.interpolation = "Closest"
        node.location = (-460, y)
        nt.links.new(node.outputs["Color"], bsdf.inputs[socket])
    bsdf.inputs["Roughness"].default_value = ROCK_ROUGHNESS
    bsdf.inputs["Metallic"].default_value = ROCK_METALLIC
    bsdf.inputs["Emission Strength"].default_value = 1.0
    mat.diffuse_color = (0.13, 0.04, 0.04, 1.0)
    mat.use_backface_culling = True
    return mat


# =============================================================================
# MESH ACCUMULATOR -- every face states which way its normal must point
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
    def __init__(self):
        self.verts = []
        self.faces = []
        self.zones = []
        self.tags = []
        self.tag = "rock"
        self.cache = {}

    def vc(self, p):
        """Vertex shared by position: coincident stations weld, not sliver."""
        key = (round(p[0], 5), round(p[1], 5), round(p[2], 5))
        if key not in self.cache:
            self.cache[key] = self.v(p)
        return self.cache[key]

    def v(self, p):
        self.verts.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.verts) - 1

    def poly(self, idx, want, zone):
        """Polygon with duplicates collapsed; quads split, n-gons fanned."""
        clean = []
        for i in idx:
            if not clean or clean[-1] != i:
                clean.append(i)
        while len(clean) > 1 and clean[0] == clean[-1]:
            clean.pop()
        if len(clean) < 3:
            return
        pts = [self.verts[j] for j in clean]
        n = _newell(pts)
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            clean.reverse()
        for i in range(1, len(clean) - 1):
            self.faces.append((clean[0], clean[i], clean[i + 1]))
            self.zones.append(zone)
            self.tags.append(self.tag)

    def subset(self, keep):
        """A new mesh of the faces whose tag passes keep()."""
        out = _Mesh()
        remap = {}
        for f, zone, tag in zip(self.faces, self.zones, self.tags):
            if not keep(tag):
                continue
            idx = []
            for i in f:
                if i not in remap:
                    remap[i] = out.v(self.verts[i])
                idx.append(remap[i])
            out.faces.append(tuple(idx))
            out.zones.append(zone)
            out.tags.append(tag)
        return out

    def quad(self, a, b, c, d, want, zone):
        self.poly([a, b, c, d], want, zone)

    def tri(self, a, b, c, want, zone):
        self.poly([a, b, c], want, zone)

    def fan(self, ring, centre, want, zone):
        for i in range(len(ring)):
            self.tri(ring[i], ring[(i + 1) % len(ring)], centre, want, zone)

    def sector_prism(self, r0, r1, t0, t1, z0, z1, zone, nseg=None, zone_top=None):
        """Closed curved block: radii r0<r1, angles t0<t1, heights z0<z1."""
        if nseg is None:
            nseg = max(1, int(math.ceil((t1 - t0) * r1 / 0.9)))
        lo_i, lo_o, hi_i, hi_o = [], [], [], []
        for k in range(nseg + 1):
            t = t0 + (t1 - t0) * k / nseg
            c, s = math.cos(t), math.sin(t)
            lo_i.append(self.v((r0 * c, r0 * s, z0)))
            lo_o.append(self.v((r1 * c, r1 * s, z0)))
            hi_i.append(self.v((r0 * c, r0 * s, z1)))
            hi_o.append(self.v((r1 * c, r1 * s, z1)))
        zt = zone_top or zone
        for k in range(nseg):
            t = t0 + (t1 - t0) * (k + 0.5) / nseg
            rad = (math.cos(t), math.sin(t), 0.0)
            nrad = (-rad[0], -rad[1], 0.0)
            self.quad(hi_i[k], hi_o[k], hi_o[k + 1], hi_i[k + 1], (0, 0, 1), zt)
            self.quad(lo_i[k], lo_o[k], lo_o[k + 1], lo_i[k + 1], (0, 0, -1), zone)
            self.quad(lo_i[k], lo_i[k + 1], hi_i[k + 1], hi_i[k], nrad, zone)
            self.quad(lo_o[k], lo_o[k + 1], hi_o[k + 1], hi_o[k], rad, zone)
        tan0 = (-math.sin(t0), math.cos(t0), 0.0)
        tan1 = (-math.sin(t1), math.cos(t1), 0.0)
        self.quad(lo_i[0], lo_o[0], hi_o[0], hi_i[0], (-tan0[0], -tan0[1], 0.0), zone)
        self.quad(lo_i[-1], lo_o[-1], hi_o[-1], hi_i[-1], tan1, zone)

    def cone(self, base, axis_len, radius, sides, zone, tip_off=(0.0, 0.0)):
        """Closed cone from a base disc (in a horizontal plane) to a tip."""
        bx, by, bz = base
        ring = [self.v((bx + radius * math.cos(TAU * i / sides),
                        by + radius * math.sin(TAU * i / sides), bz))
                for i in range(sides)]
        tip = self.v((bx + tip_off[0], by + tip_off[1], bz + axis_len))
        up = 1.0 if axis_len > 0.0 else -1.0
        self.poly(list(ring), (0.0, 0.0, -up), zone)
        for i in range(sides):
            a, b = ring[i], ring[(i + 1) % sides]
            pa, pb = self.verts[a], self.verts[b]
            mx, my = 0.5 * (pa[0] + pb[0]) - bx, 0.5 * (pa[1] + pb[1]) - by
            self.tri(a, b, tip, (mx, my, 0.0), zone)

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


def _held(r, nsides, nrings, jag, run):
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


def _lerp(a, b, t):
    return a + (b - a) * t


def _bilinear(c00, c10, c11, c01, u, v):
    return tuple(_lerp(_lerp(c00[i], c10[i], u), _lerp(c01[i], c11[i], u), v)
                 for i in range(3))


# =============================================================================
# THE ROCK -- appended read-only, welded and hole-filled so rays count cleanly
# =============================================================================

def _append_rock():
    with bpy.data.libraries.load(BLEND_PATH, link=False) as (src, dst):
        names = [n for n in src.objects if n == ROCK_OBJECT]
        if not names:
            raise SystemExit("MDL ERROR: %s has no object %r" % (BLEND_PATH, ROCK_OBJECT))
        dst.objects = names
    ob = dst.objects[0]
    bpy.context.collection.objects.link(ob)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.02)
    for _ in range(3):
        edges = [e for e in bm.edges if e.is_boundary]
        if not edges:
            break
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    for a in list(ob.data.attributes):
        if a.name == "custom_normal":
            ob.data.attributes.remove(a)
    for mat in ob.data.materials:
        if mat:
            mat.use_backface_culling = True
    return ob


def _bvh(ob):
    return BVHTree.FromPolygons([v.co.copy() for v in ob.data.vertices],
                                [list(p.vertices) for p in ob.data.polygons],
                                all_triangles=False, epsilon=0.0)


def _crossings(bvh, origin, direction, length):
    out, run = [], 0.0
    d = Vector(direction).normalized()
    p = Vector(origin)
    for _ in range(64):
        hit = bvh.ray_cast(p, d, length - run)
        if not hit[0]:
            break
        t = run + hit[3]
        if not out or t - out[-1] > 1e-3:
            out.append(t)
        run = t + 1e-4
        p = Vector(origin) + d * run
        if run >= length:
            break
    return out


class Survey(object):
    """The rock, measured: outer radius per ring, hollowness, the room."""

    def __init__(self, rock):
        self.bvh = _bvh(rock)
        zs = [v.co.z for v in rock.data.vertices]
        self.z_min, self.z_max = min(zs), max(zs)
        self.floor = self.down(0.0, 0.0, 3.0)
        self.ceil = self.up(0.0, 0.0, 3.0)
        self.rings = []          # (z, r_out_min, r_out_mean, hollow_frac)
        self.axis_solid = []
        z = math.floor(self.z_min) + 0.5
        while z < (self.floor if self.floor is not None else 0.0):
            outer, hollow = [], 0
            for i in range(SURVEY_NB):
                a = TAU * i / SURVEY_NB
                rs = self.radii(a, z)
                if not rs:
                    continue
                outer.append(rs[0])
                if len(rs) >= 2:
                    hollow += 1
            if outer:
                self.rings.append((z, min(outer), sum(outer) / len(outer),
                                   hollow / float(SURVEY_NB)))
                ts = _crossings(self.bvh, (0.0, 0.0, z), (1.0, 0.0, 0.0), 80.0)
                self.axis_solid.append(len(ts) % 2 == 1)
            z += SURVEY_DZ

    def down(self, x, y, z):
        h = self.bvh.ray_cast(Vector((x, y, z)), Vector((0.0, 0.0, -1.0)), 90.0)
        return h[0].z if h[0] else None

    def up(self, x, y, z):
        h = self.bvh.ray_cast(Vector((x, y, z)), Vector((0.0, 0.0, 1.0)), 90.0)
        return h[0].z if h[0] else None

    def radii(self, a, z, far=80.0):
        """Surface crossings on this bearing, outermost first, this side of the axis."""
        origin = (far * math.cos(a), far * math.sin(a), z)
        ts = _crossings(self.bvh, origin, (-math.cos(a), -math.sin(a), 0.0), far)
        return [far - t for t in ts if far - t > 0.05]

    def r_out(self, a, z):
        rs = self.radii(a, z)
        return rs[0] if rs else 6.0

    def r_out_min(self, z_lo, z_hi):
        vals = [r for (z, r, _m, _h) in self.rings if z_lo <= z <= z_hi]
        return min(vals) if vals else min(r for (_z, r, _m, _h) in self.rings)

    def report(self):
        print("MDL STATS rock z=%.2f..%.2f room_floor=%s ceil=%s"
              % (self.z_min, self.z_max,
                 "%.3f" % self.floor if self.floor is not None else "none",
                 "%.3f" % self.ceil if self.ceil is not None else "none"))
        hollow = sum(1 for r in self.rings if r[3] > 0.5)
        solid = sum(1 for s in self.axis_solid if s)
        print("MDL STATS shaft rings=%d hollow_rings=%d axis_solid_rings=%d -> %s"
              % (len(self.rings), hollow, solid,
                 "SOLID (to be hollowed)" if hollow == 0 else "HOLLOW"))
        for (z, rmin, rmean, hf), s in zip(self.rings, self.axis_solid):
            print("MDL STATS   z=%6.1f outer_r min=%5.2f mean=%5.2f hollow=%3.0f%% axis_solid=%s"
                  % (z, rmin, rmean, 100.0 * hf, s))


# =============================================================================
# THE PLAN -- shaft profile, stair stations, windows, chamber
# =============================================================================

class Plan(object):
    pass


def _profile(sv, z_top):
    """Control rings (z, R): the rock's local minimum outer radius less the margin."""
    ctrl = []
    for z in CTRL_Z + [z_top]:
        r = sv.r_out_min(z - CTRL_BAND, z + CTRL_BAND) - ROCK_MIN - JAG_R
        ctrl.append((z, r))
    ctrl.sort()

    def R_of(z):
        if z <= ctrl[0][0]:
            return ctrl[0][1]
        for (z0, r0), (z1, r1) in zip(ctrl, ctrl[1:]):
            if z <= z1:
                return _lerp(r0, r1, (z - z0) / (z1 - z0))
        return ctrl[-1][1]

    worst = 99.0
    for (z, rmin, _m, _h) in sv.rings:
        worst = min(worst, rmin - (R_of(z) + JAG_R))
    return ctrl, R_of, worst


def _stations(p, z_floor):
    """Walk the stair: a nose and a back station per tread, landings on the way."""
    n_steps = int(round((z_floor - FOOT_Z) / RISE))
    rise = (z_floor - FOOT_Z) / n_steps
    st = []                   # dicts: s, th, zt, going, kind
    th = math.radians(STAIR_START_DEG)
    s, z, turn = 0.0, FOOT_Z + rise, 0.0
    landings = []
    for i in range(n_steps):
        top = i == n_steps - 1
        rc = p.rc_of(z)
        if turn >= math.radians(LANDING_EVERY) and not top and i > 2 \
                and (n_steps - i) > 6:
            dth = LANDING_LEN / rc
            st.append(dict(s=s, th=th, zt=z, going=LANDING_LEN, kind="landing"))
            landings.append(len(st) - 1)
            s, th, turn = s + LANDING_LEN, th + dth, 0.0
        going = TOP_TREAD_LEN if top else GOING
        dth = going / rc
        st.append(dict(s=s, th=th, zt=z + (TOP_LIFT if top else 0.0),
                       going=going, kind="top" if top else "tread"))
        s, th, turn = s + going, th + dth, turn + dth
        z += rise
    p.n_steps, p.rise, p.st, p.landings = n_steps, rise, st, landings
    p.s_top = st[-1]["s"]
    p.s_end = st[-1]["s"] + st[-1]["going"]
    p.th_end = st[-1]["th"] + st[-1]["going"] / (p.rc_of(z_floor))
    p.climb = z_floor - FOOT_Z
    p.turns = (p.th_end - math.radians(STAIR_START_DEG)) / TAU

    # nose line and bearing as piecewise-linear functions of s
    rc0 = p.rc_of(FOOT_Z)
    knots = [(-GOING, FOOT_Z, math.radians(STAIR_START_DEG) - GOING / rc0)]
    for d in st:
        knots.append((d["s"], d["zt"], d["th"]))
        if d["kind"] in ("landing", "top"):
            rc = p.rc_of(d["zt"])
            knots.append((d["s"] + d["going"], d["zt"], d["th"] + d["going"] / rc))
    p.knots = knots

    def at(s):
        if s <= knots[0][0]:
            return knots[0][1], knots[0][2]
        for (s0, z0, t0), (s1, z1, t1) in zip(knots, knots[1:]):
            if s <= s1:
                f = (s - s0) / (s1 - s0) if s1 > s0 else 0.0
                return _lerp(z0, z1, f), _lerp(t0, t1, f)
        return knots[-1][1], knots[-1][2]
    p.nose = lambda s: at(s)[0]
    p.theta = lambda s: at(s)[1]

    def s_of_nose(zt):
        """Lowest s at which the nose line reaches zt."""
        for (s0, z0, _t0), (s1, z1, _t1) in zip(knots, knots[1:]):
            if z0 <= zt <= z1 and z1 > z0:
                return _lerp(s0, s1, (zt - z0) / (z1 - z0))
        return knots[-1][0]
    p.s_of_nose = s_of_nose

    def passes(bearing):
        """Nose heights at which the walking line crosses this bearing."""
        out = []
        b = bearing % TAU
        for (s0, z0, t0), (s1, z1, t1) in zip(knots, knots[1:]):
            if t1 <= t0:
                continue
            k0 = math.floor((t0 - b) / TAU)
            for k in (k0, k0 + 1):
                tb = b + k * TAU
                if t0 <= tb < t1:
                    out.append(_lerp(z0, z1, (tb - t0) / (t1 - t0)))
        return out
    p.passes = passes


def _rings(p, z_floor):
    """Wall ring heights: fixed ones, the gaps filled to ~BAND_H."""
    fixed = [FOOT_Z, FOOT_Z + DOOR_BAND, p.z_c, p.z_top]
    if p.chamber:
        zl = p.chamber["z"]
        fixed += [zl - 0.06, zl - 0.03, zl + CHAMBER_H, zl + CHAMBER_H + 0.05]
    fixed = sorted(set(round(z, 4) for z in fixed))
    rings, free = [], []
    for z0, z1 in zip(fixed, fixed[1:]):
        rings.append(z0)
        free.append(False)
        # the door band stays one cell: a ring through it would cut the arch short
        n = 1 if abs(z0 - FOOT_Z) < 1e-6 else int(math.ceil((z1 - z0) / BAND_H))
        for k in range(1, n):
            rings.append(_lerp(z0, z1, k / float(n)))
            free.append(True)
    rings.append(fixed[-1])
    free.append(False)
    p.Z, p.Zfree = rings, free


def _cell_of(p, bearing, z):
    j = int(round((math.degrees(bearing % TAU) - ANG_OFF) / (360.0 / NS) - 0.5)) % NS
    best, bk = None, 0
    for k in range(len(p.Z) - 1):
        zc = 0.5 * (p.Z[k] + p.Z[k + 1])
        if best is None or abs(zc - z) < best:
            best, bk = abs(zc - z), k
    return j, bk


def _cell_centre(p, j, k):
    a = math.radians(ANG_OFF + (j + 0.5) * 360.0 / NS)
    return a, 0.5 * (p.Z[k] + p.Z[k + 1])


def _plan_windows(p, sv):
    p.windows = []
    used = set()
    for bdeg, z in WINDOWS:
        j, k = _cell_of(p, math.radians(bdeg), z)
        pick = None
        for dk in (0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6):
            kk = k + dk
            if kk < 1 or kk >= len(p.Z) - 1 or (j, kk) in used:
                continue
            a, zc = _cell_centre(p, j, kk)
            if zc > p.z_c - 1.5:
                continue
            if p.Z[kk + 1] - p.Z[kk] < SLOT_H + 0.3:
                continue
            if p.chamber and p.chamber["j0"] <= j <= p.chamber["j1"] \
                    and p.chamber["z"] - 1.0 <= zc <= p.chamber["z"] + CHAMBER_H + 1.0:
                continue
            if all(abs(zc - zp) >= STAIR_CLEAR for zp in p.passes(a)):
                pick = kk
                break
        if pick is None:
            print("MDL WARN window at %.0f deg z=%.1f found no clear facet" % (bdeg, z))
            continue
        used.add((j, pick))
        a, zc = _cell_centre(p, j, pick)
        p.windows.append(dict(j=j, k=pick, bearing=a, z=zc,
                              r_end=sv.r_out(a, zc) + 0.15))


def _plan_chamber(p, sv):
    """The landing between 30 and 60 % of the climb with the most rock behind it."""
    best = None
    for li in p.landings:
        d = p.st[li]
        f = (d["zt"] - FOOT_Z) / p.climb
        if not (CHAMBER_LO <= f <= CHAMBER_HI):
            continue
        rc = p.rc_of(d["zt"])
        t0, t1 = d["th"], d["th"] + d["going"] / rc
        j0 = int(math.floor((math.degrees(t0 % TAU) - ANG_OFF) / (360.0 / NS)))
        j1 = int(math.floor((math.degrees(t1 % TAU) - ANG_OFF) / (360.0 / NS)))
        if j1 < j0:
            j1 += NS
        j0 -= 1
        j1 += 1
        rec = CHAMBER_REC_MAX
        for j in range(j0, j1 + 2):
            a = math.radians(ANG_OFF + j * 360.0 / NS)
            for z in (d["zt"], d["zt"] + CHAMBER_H * 0.5, d["zt"] + CHAMBER_H):
                rec = min(rec, sv.r_out(a, z) - ROCK_MIN - JAG_R - p.R_of(z))
        if rec < 0.5:
            continue
        if best is None or rec > best["rec"]:
            best = dict(li=li, z=d["zt"], t0=t0, t1=t1, j0=j0, j1=j1, rec=rec)
    p.chamber = best


def make_plan(sv):
    p = Plan()
    z_floor_axis = sv.floor
    p.ctrl, p.R_of, p.worst = _profile(sv, z_floor_axis)
    # the wall leans in where the shaft narrows going up; a tread's inner edge
    # keeps its width under the wall a body's height above it, or the capsule wedges
    p.R_in = lambda z: min(p.R_of(z + h) for h in (0.0, 0.5, 1.0, 1.5, 2.0))
    # the facets jitter JAG_R in and sag SAG at mid-chord: the clear width is
    # measured to the nearest the wall can actually be
    global SAG
    SAG = max(c[1] for c in p.ctrl) * (1.0 - math.cos(math.pi / NS))
    p.R_clear = lambda z: p.R_in(z) - JAG_R - SAG
    # walking line 0.5 m off the parapet, as a spiral's going is measured: the
    # parapet edge then runs at ~39 deg, under the capsule's 46 deg floor limit
    p.rc_of = lambda z: p.R_clear(z) - TREAD_CLEAR + WALK_OFF
    p.r_i_of = lambda z: p.R_clear(z) - TREAD_CLEAR - PARAPET_T   # tread's inner edge
    # the hole sits at the room's edge: measure his floor there once the
    # stair's arrival bearing is known (a first pass at the axis height)
    _stations(p, z_floor_axis)
    th = p.st[-1]["th"]
    rr = p.rc_of(z_floor_axis)
    zf = sv.down(rr * math.cos(th), rr * math.sin(th), z_floor_axis + 3.0)
    p.z_floor = zf if zf is not None else z_floor_axis
    p.z_c = p.z_floor - SLAB_T
    p.z_top = p.z_floor - 0.02
    p.R_top = p.R_of(p.z_floor)
    _stations(p, p.z_floor)
    p.chamber = None
    _plan_chamber(p, sv)
    _rings(p, p.z_floor)
    _plan_windows(p, sv)
    # the stairwell hole and the throat under the floor
    # the hole opens where the raked soffit meets the floor: HEADROOM over the
    # nose, or the capsule's head is in the room floor before the hole
    p.s_throat = p.s_of_nose(p.z_c - HEADROOM)
    p.s_h0 = min(p.s_top - (HOLE_L - TOP_TREAD_LEN), p.s_of_nose(p.z_floor - 0.05 - HEADROOM))
    p.r_cd = p.r_i_of(p.z_floor) - 0.03
    p.th_h0 = p.theta(p.s_h0)
    return p


# =============================================================================
# GEOMETRY
# =============================================================================

def _radial(t):
    return (math.cos(t), math.sin(t), 0.0)


def _wall(m, p, r, sv):
    """The faceted lining, its hidden outer skin, door and window cells."""
    nz = len(p.Z)
    rjit = _held(r, NS, nz, JAG_R, JAG_RUN)
    zjit = [[(r.sf() * JAG_Z if p.Zfree[k] else 0.0) for k in range(nz)]
            for _ in range(NS)]
    rec = [[0.0] * nz for _ in range(NS)]
    if p.chamber:
        c = p.chamber
        for j in range(c["j0"], c["j1"] + 2):
            for k in range(nz):
                if c["z"] - 0.031 <= p.Z[k] <= c["z"] + CHAMBER_H + 0.001:
                    rec[j % NS][k] = c["rec"]
    vin, pin = {}, {}
    for j in range(NS):
        a = math.radians(ANG_OFF + j * 360.0 / NS)
        for k in range(nz):
            z = p.Z[k] + zjit[j][k]
            rr = p.R_of(p.Z[k]) + rjit[j][k] + rec[j][k]
            pin[(j, k)] = (rr * math.cos(a), rr * math.sin(a), z)
            vin[(j, k)] = m.v(pin[(j, k)])
    special = {(DOOR_FACET, 0): "door"}
    for w in p.windows:
        special[(w["j"], w["k"])] = w

    def zone_of(j, k):
        bias = 0.25 * (rjit[j][k] + rjit[(j + 1) % NS][k]
                       + rjit[j][k + 1] + rjit[(j + 1) % NS][k + 1])
        zc = 0.5 * (p.Z[k] + p.Z[k + 1])
        if bias < EMBER_T and zc < FOOT_Z + EMBER_ABOVE:
            return ZONE_EMBER
        if bias < SHADE_T:
            return ZONE_SHADE
        return ZONE_ROCK

    for j in range(NS):
        j1 = (j + 1) % NS
        a_mid = math.radians(ANG_OFF + (j + 0.5) * 360.0 / NS)
        want = (-math.cos(a_mid), -math.sin(a_mid), 0.0)
        for k in range(nz - 1):
            key = (j, k)
            zone = zone_of(j, k)
            c00, c10 = pin[(j, k)], pin[(j1, k)]
            c11, c01 = pin[(j1, k + 1)], pin[(j, k + 1)]
            if key not in special:
                m.quad(vin[(j, k)], vin[(j1, k)], vin[(j1, k + 1)], vin[(j, k + 1)],
                       want, zone)
                continue
            P = lambda u, v: _bilinear(c00, c10, c11, c01, u, v)   # noqa: E731
            corners = dict(v00=vin[(j, k)], v10=vin[(j1, k)],
                           v11=vin[(j1, k + 1)], v01=vin[(j, k + 1)])
            cw = (p.R_of(p.Z[k]) * TAU / NS)
            ch = p.Z[k + 1] - p.Z[k]
            if special[key] == "door":
                outline = _arched_hole(m, P, corners, want, zone, cw, ch,
                                       DOOR_W, DOOR_H, 0.0)
                p.door_outline_in = outline
            else:
                w = special[key]
                u0, u1 = 0.5 - 0.5 * SLOT_W / cw, 0.5 + 0.5 * SLOT_W / cw
                v0 = 0.5 - 0.5 * SLOT_H / ch
                v1 = v0 + SLOT_H / ch
                _slot_hole(m, P, corners, want, zone, u0, u1, v0, v1, w)

    # hidden outer skin and the caps that close the shell
    m.tag = "skin"
    vout, pout = {}, {}
    for j in range(NS):
        a = math.radians(ANG_OFF + j * 360.0 / NS)
        for k in (0, 1, nz - 1):
            rr = p.R_of(p.Z[k]) + JAG_R + WALL_T + (rec[j][k])
            pout[(j, k)] = (rr * math.cos(a), rr * math.sin(a), p.Z[k])
            vout[(j, k)] = m.v(pout[(j, k)])
    for j in range(NS):
        j1 = (j + 1) % NS
        a_mid = math.radians(ANG_OFF + (j + 0.5) * 360.0 / NS)
        if j == DOOR_FACET:
            # The rock is cut away at the door, so the skin is seen there: it
            # carries the same opening, grown to stay inside the reveal.
            c00, c10 = pout[(j, 0)], pout[(j1, 0)]
            c11, c01 = pout[(j1, 1)], pout[(j, 1)]
            _arched_hole(
                m, lambda u, v: _bilinear(c00, c10, c11, c01, u, v),
                dict(v00=vout[(j, 0)], v10=vout[(j1, 0)],
                     v11=vout[(j1, 1)], v01=vout[(j, 1)]),
                _radial(a_mid), ZONE_SHADE,
                (p.R_of(p.Z[0]) + JAG_R + WALL_T) * TAU / NS, p.Z[1] - p.Z[0],
                DOOR_W + 2.0 * SKIN_GROW, DOOR_H + SKIN_GROW, 0.0)
            m.quad(vout[(j, 1)], vout[(j1, 1)], vout[(j1, nz - 1)],
                   vout[(j, nz - 1)], _radial(a_mid), ZONE_SHADE)
        else:
            m.quad(vout[(j, 0)], vout[(j1, 0)], vout[(j1, nz - 1)],
                   vout[(j, nz - 1)], _radial(a_mid), ZONE_SHADE)
        m.quad(vin[(j, 0)], vin[(j1, 0)], vout[(j1, 0)], vout[(j, 0)],
               (0, 0, -1), ZONE_SHADE)
        m.quad(vin[(j, nz - 1)], vin[(j1, nz - 1)], vout[(j1, nz - 1)],
               vout[(j, nz - 1)], (0, 0, 1), ZONE_SHADE)
    m.tag = "rock"
    p.rjit, p.zjit, p.rec, p.pin = rjit, zjit, rec, pin


def _arch_pts(w, h):
    """(x, z) round the door opening, floor-left up over the head to floor-right."""
    hw = w * 0.5
    spring = h - hw * 0.72
    pts = [(-hw, 0.0), (-hw, spring)]
    for i in range(1, 6):
        a = math.pi * (1.0 - i / 6.0)
        pts.append((hw * math.cos(a), spring + (h - spring) * math.sin(a)))
    pts += [(hw, spring), (hw, 0.0)]
    return pts


def _arched_hole(m, P, c, want, zone, cw, ch, w, h, v_base):
    """A cell/rect with an arched opening cut from its bottom edge.

    Returns the opening's outline vertex indices, floor-left round to floor-right.
    """
    pts = _arch_pts(w, h)
    uv = [(0.5 + x / cw, v_base + z / ch) for (x, z) in pts]
    idx = [m.v(P(u, v)) for (u, v) in uv]
    bl, br = c["v00"], c["v10"]
    if v_base > 0.0:
        bl, br = m.v(P(0.0, v_base)), m.v(P(1.0, v_base))
        m.quad(c["v00"], c["v10"], br, bl, want, zone)
    u0, u1 = uv[0][0], uv[-1][0]
    top_l, top_r = m.v(P(u0, 1.0)), m.v(P(u1, 1.0))
    m.quad(bl, idx[0], top_l, c["v01"], want, zone)
    m.quad(idx[-1], br, c["v11"], top_r, want, zone)
    top_c = m.v(P(0.5, 1.0))
    ring = [top_r] + list(reversed(idx[1:-1])) + [top_l]
    for i in range(len(ring) - 1):
        m.tri(top_c, ring[i], ring[i + 1], want, zone)
    return idx


def _slot_hole(m, P, c, want, zone, u0, u1, v0, v1, w):
    us, vs = (0.0, u0, u1, 1.0), (0.0, v0, v1, 1.0)
    g = {}
    for a, u in enumerate(us):
        for b, v in enumerate(vs):
            if (a, b) == (0, 0):
                g[(a, b)] = c["v00"]
            elif (a, b) == (3, 0):
                g[(a, b)] = c["v10"]
            elif (a, b) == (3, 3):
                g[(a, b)] = c["v11"]
            elif (a, b) == (0, 3):
                g[(a, b)] = c["v01"]
            else:
                g[(a, b)] = m.v(P(u, v))
    for a in range(3):
        for b in range(3):
            if (a, b) == (1, 1):
                continue
            m.quad(g[(a, b)], g[(a + 1, b)], g[(a + 1, b + 1)], g[(a, b + 1)], want, zone)
    inner = [g[(1, 1)], g[(2, 1)], g[(2, 2)], g[(1, 2)]]
    d = _radial(w["bearing"])
    outer = []
    for i in inner:
        q = m.verts[i]
        along = q[0] * d[0] + q[1] * d[1]
        L = w["r_end"] - along
        outer.append(m.v((q[0] + d[0] * L, q[1] + d[1] * L, q[2])))
    cz = 0.5 * (m.verts[inner[0]][2] + m.verts[inner[2]][2])
    tang = (-d[1], d[0], 0.0)
    wants = [(0, 0, 1), (-tang[0], -tang[1], 0.0), (0, 0, -1), tang]
    for i in range(4):
        a, b = inner[i], inner[(i + 1) % 4]
        m.quad(a, b, outer[(i + 1) % 4], outer[i], wants[i], ZONE_SHADE)
    w["cz"] = cz


def _door(m, p, sv):
    """Where the rock's face is on the door's bearing, and a stone reveal lining
    the first TRIM_D of the passage, flush with the rock's cut."""
    a = math.radians(DOOR_BEARING)
    d = _radial(a)
    x_rock = 0.0
    for y in (-1.4, -0.7, 0.0, 0.7, 1.4):
        for z in (FOOT_Z + 0.2, FOOT_Z + 1.2, FOOT_Z + 2.2, FOOT_Z + 3.0):
            hit = sv.bvh.ray_cast(Vector((80.0 * d[0] - y * d[1], 80.0 * d[1] + y * d[0], z)),
                                  Vector((-d[0], -d[1], 0.0)), 80.0)
            if hit[0]:
                x_rock = max(x_rock, hit[0].x * d[0] + hit[0].y * d[1])
    p.door = dict(x_rock=x_rock, R=p.R_of(FOOT_Z + 1.1))

    tang = (-d[1], d[0], 0.0)
    ring = [m.verts[i] for i in p.door_outline_in]
    n = len(ring)
    # the outline pushed TRIM_W outward in its own plane (the floor ends only sideways)
    outer = []
    for k, (x, y, z) in enumerate(ring):
        across = x * tang[0] + y * tang[1]
        along = x * d[0] + y * d[1]
        if k == 0 or k == n - 1:
            oa, oz = across + (-TRIM_W if k == 0 else TRIM_W), z
        else:
            cx, cz = 0.0, FOOT_Z + DOOR_H - 0.5 * DOOR_W
            L = math.hypot(across - cx, z - cz) or 1.0
            oa, oz = across + (across - cx) / L * TRIM_W, z + (z - cz) / L * TRIM_W
        outer.append((along * d[0] + oa * tang[0], along * d[1] + oa * tang[1], oz))
    m.tag = "trim"
    vi = [m.v(q) for q in ring]
    vo = [m.v(q) for q in outer]
    vi2 = [m.v((q[0] + d[0] * TRIM_D, q[1] + d[1] * TRIM_D, q[2])) for q in ring]
    vo2 = [m.v((q[0] + d[0] * TRIM_D, q[1] + d[1] * TRIM_D, q[2])) for q in outer]
    axis = (p.door["R"] * d[0], p.door["R"] * d[1], FOOT_Z + 1.0)
    for k in range(n - 1):
        mid = ring[k]
        want = (axis[0] - mid[0], axis[1] - mid[1], axis[2] - mid[2])
        m.quad(vi[k], vi[k + 1], vi2[k + 1], vi2[k], want, ZONE_CARVE)       # the reveal
        m.quad(vo[k], vo[k + 1], vo2[k + 1], vo2[k],
               (-want[0], -want[1], -want[2]), ZONE_ROCK)                     # buried back
        m.quad(vi2[k], vi2[k + 1], vo2[k + 1], vo2[k], d, ZONE_ROCK)         # the trim's edge
    m.tag = "rock"


def _flight(m, p):
    """The stair as one closed swept solid: treads, risers, parapet, soffit."""
    st = p.st
    loops = []
    prev_key = None

    def hp_at(s):
        h = PARAPET_H * min(1.0, s / 1.0)
        if s >= p.s_h0 - GOING:
            return 0.0
        if p.chamber:
            c = st[p.chamber["li"]]
            if c["s"] - 1e-6 <= s <= c["s"] + c["going"] + 1e-6:
                return 0.0
        return h

    def loop(s, th, zt):
        R = p.R_top if s >= p.s_h0 - GOING else p.R_of(zt)
        r_o = R + JAG_R + 0.06
        r_i = p.r_i_of(p.z_floor if s >= p.s_h0 - GOING else zt)
        hp = hp_at(s)
        r_p = r_i + PARAPET_T if hp > 0.0 else r_i
        nose = p.nose(s)
        cop = nose + hp if hp > 0.0 else zt
        sof = nose - SOFFIT_D
        c, sn = math.cos(th), math.sin(th)
        pts = [(r_o, zt), (r_p, zt), (r_p, cop), (r_i, cop), (r_i, sof), (r_o, sof)]
        return [m.vc((rr * c, rr * sn, z)) for (rr, z) in pts], th

    def connect(A, B, thA, thB, riser):
        tm = 0.5 * (thA + thB)
        rad = _radial(tm)
        nrad = (-rad[0], -rad[1], 0.0)
        tang = (-rad[1], rad[0], 0.0)
        ntang = (rad[1], -rad[0], 0.0)
        wants = [ntang if riser else (0, 0, 1), rad, (0, 0, 1), nrad, (0, 0, -1), rad]
        if riser:
            end = ntang if m.verts[B[2]][2] < m.verts[A[2]][2] else tang
            wants[1] = wants[2] = wants[3] = end
        zones = [ZONE_CARVE, ZONE_ROCK, ZONE_ROCK, ZONE_ROCK, ZONE_SHADE, ZONE_SHADE]
        tags = ["tread", "parapet_face", "flight", "flight", "flight", "flight"]
        for e in range(6):
            f = (e + 1) % 6
            m.tag = tags[e]
            m.quad(A[e], A[f], B[f], B[e], wants[e], zones[e])
        m.tag = "rock"

    prev = None
    for d in st:
        for (s, th, zt) in ((d["s"], d["th"], d["zt"]),
                            (d["s"] + d["going"],
                             d["th"] + d["going"] / (p.rc_of(d["zt"])),
                             d["zt"])):
            key = (round(s, 5), round(zt, 5))
            if prev is not None and key == prev[0]:
                continue
            L, _ = loop(s, th, zt)
            if prev is None:
                m.tag = "tread"      # the first riser: the ramp, not a wall
                m.poly(list(reversed(L)), (math.sin(th), -math.cos(th), 0.0), ZONE_ROCK)
                m.tag = "rock"
            else:
                riser = abs(s - prev[1]) < 1e-6
                connect(prev[2], L, prev[3], th, riser)
            prev = (key, s, L, th)
    m.tag = "tread"
    m.poly(prev[2], (-math.sin(prev[3]), math.cos(prev[3]), 0.0), ZONE_ROCK)
    m.tag = "rock"


def _ceiling(m, p):
    """Flat shaft ceiling under the room floor, the raked throat, the well, the kerb."""
    z_c = p.z_c
    r_cd = p.r_cd
    r_out = p.R_top + JAG_R + WALL_T
    th_a = p.theta(p.s_throat) % TAU
    th_e = p.th_end % TAU
    span = (th_e - th_a) % TAU

    def in_throat(t):
        return (t - th_a) % TAU < span

    # stations through the throat: s from s_throat to s_end
    ss = [p.s_throat, p.s_h0]
    for k in p.knots:
        if p.s_throat < k[0] < p.s_end:
            ss.append(k[0])
    ss.append(p.s_end)
    ss = sorted(set(ss))
    # extra stations so the raked soffit is smooth over long knots
    fine = []
    for s0, s1 in zip(ss, ss[1:]):
        n = max(1, int(math.ceil((s1 - s0) / 0.7)))
        for i in range(n):
            fine.append(_lerp(s0, s1, i / float(n)))
    fine.append(ss[-1])
    th_st = [p.theta(s) % TAU for s in fine]

    def h_of(s):
        return min(p.nose(s) + HEADROOM, p.z_floor - 0.05)

    rim = [(TAU * i / NC, None) for i in range(NC) if not in_throat(TAU * i / NC)]
    rim += [(t, s) for t, s in zip(th_st, fine)]
    rim.sort(key=lambda x: x[0])

    for target in (m,):
        centre = target.v((0.0, 0.0, z_c))
        inner = [target.v((r_cd * math.cos(t), r_cd * math.sin(t), z_c)) for t, _ in rim]
        outer = [target.v((r_out * math.cos(t), r_out * math.sin(t), z_c)) for t, _ in rim]
        n = len(rim)
        for i in range(n):
            j = (i + 1) % n
            target.tri(inner[i], inner[j], centre, (0, 0, -1),
                       ZONE_SHADE if i % 3 else ZONE_ROCK)
            ti, si = rim[i]
            tj, sj = rim[j]
            if si is not None and sj is not None and sj > si:
                # raked / flat soffit over the stair, or open where the hole is
                hi_, hj_ = h_of(si), h_of(sj)
                a_i = target.v((r_cd * math.cos(ti), r_cd * math.sin(ti), hi_))
                b_i = target.v((r_out * math.cos(ti), r_out * math.sin(ti), hi_))
                a_j = target.v((r_cd * math.cos(tj), r_cd * math.sin(tj), hj_))
                b_j = target.v((r_out * math.cos(tj), r_out * math.sin(tj), hj_))
                if sj <= p.s_h0 + 1e-6:
                    target.quad(a_i, b_i, b_j, a_j, (0, 0, -1), ZONE_SHADE)
                # the throat's inner wall, and the well's above it
                top_i = target.v((r_cd * math.cos(ti), r_cd * math.sin(ti),
                                  p.z_floor + 0.02 if si >= p.s_h0 - 1e-6 else hi_))
                top_j = target.v((r_cd * math.cos(tj), r_cd * math.sin(tj),
                                  p.z_floor + 0.02 if sj >= p.s_h0 - 1e-6 else hj_))
                tm = 0.5 * (ti + tj) if abs(tj - ti) < math.pi else 0.5 * (ti + tj + TAU)
                target.quad(inner[i], inner[j], top_j, top_i, _radial(tm), ZONE_ROCK)
                if sj >= p.s_end - 1e-6:
                    # the well's far end, down to the ceiling
                    e_o = target.v((r_out * math.cos(tj), r_out * math.sin(tj), p.z_floor + 0.02))
                    target.quad(inner[j], outer[j], e_o, top_j,
                                (math.sin(tj), -math.cos(tj), 0.0), ZONE_ROCK)
            else:
                target.quad(inner[i], outer[i], outer[j], inner[j], (0, 0, -1),
                            ZONE_ROCK if i % 2 else ZONE_SHADE)

    # the kerb along the hole's inner side: "the lipped hole"
    t0 = p.th_h0 - 0.30 / r_cd
    t1 = p.th_end + 0.30 / r_cd
    m.sector_prism(r_cd - KERB_T, r_cd, t0, t1, p.z_floor - 0.05, p.z_floor + KERB_H,
                   ZONE_ROCK, zone_top=ZONE_CARVE)
    p.hole = dict(t0=p.th_h0 % TAU, t1=p.th_end % TAU, r0=r_cd, r1=p.R_top,
                  z=p.z_floor, th_a=th_a)


def _floor(m, p, r):
    R = p.R_of(FOOT_Z) + JAG_R + WALL_T
    z0 = FOOT_Z - FLOOR_DROP
    centre = m.v((0.0, 0.0, z0))
    mid = [m.v((3.0 * math.cos(TAU * i / NS), 3.0 * math.sin(TAU * i / NS),
                z0 - 0.06 * r.f())) for i in range(NS)]
    rim = [m.v((R * math.cos(TAU * i / NS), R * math.sin(TAU * i / NS), z0))
           for i in range(NS)]
    for i in range(NS):
        j = (i + 1) % NS
        m.tri(mid[i], mid[j], centre, (0, 0, 1), ZONE_SHADE if i % 2 else ZONE_ROCK)
        m.quad(mid[i], rim[i], rim[j], mid[j], (0, 0, 1), ZONE_ROCK if i % 3 else ZONE_SHADE)


def _chamber(m, p):
    c = p.chamber
    if not c:
        return
    d = p.st[c["li"]]
    R = p.R_of(d["zt"])
    r_i = p.r_i_of(d["zt"])
    z = d["zt"]
    t0, t1 = c["t0"], c["t1"]
    # the shelf out into the shaft, and its parapet
    m.sector_prism(r_i - SHELF_D, r_i - 0.02, t0, t1, z - SHELF_T, z,
                   ZONE_ROCK, zone_top=ZONE_CARVE)
    m.sector_prism(r_i - SHELF_D, r_i - SHELF_D + PARAPET_T, t0, t1,
                   z, z + PARAPET_H, ZONE_ROCK)
    for t in (t0, t1):
        ta, tb = (t, t + PARAPET_T / r_i) if t == t0 else (t - PARAPET_T / r_i, t)
        m.sector_prism(r_i - SHELF_D, r_i, ta, tb, z, z + PARAPET_H, ZONE_ROCK)
    a0 = math.radians(ANG_OFF + c["j0"] * 360.0 / NS)
    a1 = math.radians(ANG_OFF + (c["j1"] + 1) * 360.0 / NS)
    if a1 < a0:
        a1 += TAU
    p.chamber.update(dict(R=R, Rb=R + c["rec"], a0=a0, a1=a1))


def _drips(m, p, r):
    r_cd = p.r_cd
    th_a, th_e = p.hole["th_a"], p.hole["t1"]
    span = (th_e - th_a) % TAU
    n = 0
    tries = 0
    while n < N_STALACTITE and tries < 400:
        tries += 1
        rr = 0.6 + r.f() * (r_cd - 1.4)
        t = r.f() * TAU
        if (t - th_a + 0.4) % TAU < span + 0.8 and rr > r_cd - 2.6:
            continue
        L = 0.6 + r.f() * 2.0
        rad = 0.12 + r.f() * 0.26
        m.cone((rr * math.cos(t), rr * math.sin(t), p.z_c + 0.05), -L, rad, 5,
               ZONE_SHADE if r.i(0, 2) else ZONE_ROCK, (r.sf() * 0.1, r.sf() * 0.1))
        n += 1
    n = 0
    tries = 0
    R0 = p.R_of(FOOT_Z)
    while n < N_STALAGMITE and tries < 400:
        tries += 1
        rr = 1.5 + r.f() * (R0 - 3.6)
        t = r.f() * TAU
        if abs(((t - math.radians(DOOR_BEARING)) + math.pi) % TAU - math.pi) < math.radians(28.0):
            continue
        H = 0.5 + r.f() * 1.3
        rad = 0.2 + r.f() * 0.3
        m.cone((rr * math.cos(t), rr * math.sin(t), FOOT_Z - 0.05), H, rad, 5,
               ZONE_ROCK if r.i(0, 1) else ZONE_SHADE, (r.sf() * 0.08, r.sf() * 0.08))
        n += 1
    if p.chamber:
        c = p.chamber
        for _ in range(N_CHAMBER_DRIP):
            rr = c["R"] + 0.3 + r.f() * max(0.2, c["rec"] - 0.6)
            t = _lerp(c["a0"], c["a1"], 0.15 + 0.7 * r.f())
            L = 0.4 + r.f() * 1.2
            m.cone((rr * math.cos(t), rr * math.sin(t), c["z"] + CHAMBER_H + 0.05), -L,
                   0.1 + r.f() * 0.18, 5, ZONE_SHADE, (r.sf() * 0.06, r.sf() * 0.06))


def _collider(m, p):
    """Every drawn face but the hidden skin, the treads and the parapet's tread
    face; under the treads a smooth ramp with the parapet face carried down to it."""
    coll = m.subset(lambda tag: tag not in ("skin", "tread", "parapet_face"))
    prev = None
    ss = sorted(set([k[0] for k in p.knots]))
    fine = []
    for s0, s1 in zip(ss, ss[1:]):
        n = max(1, int(math.ceil((s1 - s0) / 0.45)))
        for i in range(n):
            fine.append(_lerp(s0, s1, i / float(n)))
    fine.append(ss[-1])
    for s in fine:
        nose, th = p.nose(s), p.theta(s)
        top = s >= p.s_h0 - GOING
        R = p.R_top if top else p.R_of(nose)
        r_o = R + JAG_R + 0.06
        r_i = p.r_i_of(p.z_floor if top else nose)
        hp = 0.0 if top else PARAPET_H * min(1.0, s / 1.0)
        if p.chamber:
            c = p.st[p.chamber["li"]]
            if c["s"] - 1e-6 <= s <= c["s"] + c["going"] + 1e-6:
                hp = 0.0
        r_p = r_i + PARAPET_T if hp > 0.0 else r_i
        lift = TOP_RAMP_LIFT * min(1.0, max(0.0, (s - (p.s_top - TOP_LIFT_RUN)) / TOP_LIFT_RUN))
        z = max(FOOT_Z - FLOOR_DROP, nose - RAMP_DROP + lift)
        cop = nose + hp if hp > 0.0 else z
        cs, sn = math.cos(th), math.sin(th)
        L = [coll.v((r_o * cs, r_o * sn, z)), coll.v((r_p * cs, r_p * sn, z)),
             coll.v((r_p * cs, r_p * sn, cop))]
        if prev is not None:
            tm = 0.5 * (prev[1] + th)
            rad = _radial(tm)
            coll.quad(prev[0][0], prev[0][1], L[1], L[0], (0, 0, 1), ZONE_ROCK)
            coll.quad(prev[0][1], prev[0][2], L[2], L[1], rad, ZONE_ROCK)
        prev = (L, th)
    return coll


def _measure_stair(m, p):
    """Clear tread width to the drawn wall, headroom over the ramp, worst slope."""
    bvh = BVHTree.FromPolygons([Vector(v) for v in m.verts], [list(f) for f in m.faces],
                               all_triangles=True, epsilon=0.0)
    clear, head, slope, where = 99.0, 99.0, 0.0, ""
    s = 0.0
    while s < p.s_end:
        nose, th = p.nose(s), p.theta(s)
        r_i = p.r_i_of(nose)
        r_p = r_i + PARAPET_T
        rc = p.rc_of(nose)
        for h in (0.3, 1.0, 1.7):
            org = Vector(((r_p + 0.05) * math.cos(th), (r_p + 0.05) * math.sin(th), nose + h))
            hit = bvh.ray_cast(org, Vector((math.cos(th), math.sin(th), 0.0)), 6.0)
            if hit[0]:
                clear = min(clear, (hit[0] - org).length + 0.05)
        # headroom over the clear width; outside it the leaning wall is the ceiling
        for rr in (r_p + 0.3, rc, p.R_clear(nose) - 0.3):
            org = Vector((rr * math.cos(th), rr * math.sin(th), nose + 0.3))
            hit = bvh.ray_cast(org, Vector((0.0, 0.0, 1.0)), 60.0)
            if hit[0] and hit[0].z - nose < head:
                head = hit[0].z - nose
                where = "s=%.1f bearing=%.0fdeg z=%.1f r=%.2f" % (s, math.degrees(th) % 360.0, nose, rr)
        slope = max(slope, math.degrees(math.atan2(RISE, GOING * r_p / rc)))
        s += 0.25
    rcs = [p.rc_of(z) for z in (FOOT_Z, p.z_floor)] + [p.rc_of(c[0]) for c in p.ctrl]
    return (clear, min(rcs), max(rcs), slope), (head, where)


# =============================================================================
# UV -- per-face planar projection into a random window of its zone
# =============================================================================

def unwrap(ob, zones):
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + len(me.polygons))
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
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


# =============================================================================
# RENDERS -- hand-placed: door, stairs, shaft, top, cut
# =============================================================================

PLAN = {}


def _extra_renders(spec, objects):
    p, rock = PLAN["plan"], PLAN["rock"]
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 48)))
    mdl._try(scene.eevee, "use_shadows", True)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")
    world = bpy.data.worlds.new("Hell")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.34, 0.11, 0.08, 1.0)
    bg.inputs[1].default_value = 0.55

    target = mdl._link(bpy.data.objects.new("InTarget", None))
    cam = mdl._link(bpy.data.objects.new("InCam", bpy.data.cameras.new("InCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    cam.data.clip_end = 400.0

    lamps = []
    for z in (FOOT_Z + 3.0, FOOT_Z + 12.0, FOOT_Z + 21.0, FOOT_Z + 30.0, p.z_c - 2.0):
        ld = bpy.data.lights.new("Fill", type="POINT")
        ld.energy = 5200.0
        ld.color = (1.0, 0.55, 0.40)
        ld.shadow_soft_size = 0.8
        lo = mdl._link(bpy.data.objects.new("Fill", ld))
        lo.location = (0.0, 0.0, z)
        lamps.append(lo)
    ld = bpy.data.lights.new("DoorFill", type="POINT")
    ld.energy = 900.0
    ld.color = (1.0, 0.6, 0.45)
    lo = mdl._link(bpy.data.objects.new("DoorFill", ld))
    lo.location = (p.door["x_rock"] + 2.5, 1.5, FOOT_Z + 2.4)
    lamps.append(lo)
    ld = bpy.data.lights.new("WellFill", type="POINT")
    ld.energy = 1200.0
    ld.color = (1.0, 0.6, 0.45)
    lo = mdl._link(bpy.data.objects.new("WellFill", ld))
    tw = p.theta(p.s_top - 1.5)
    rw = p.R_top - 2.6
    lo.location = (rw * math.cos(tw), rw * math.sin(tw), p.z_floor + 1.6)
    lamps.append(lo)
    if p.chamber:
        c = p.chamber
        ld = bpy.data.lights.new("ChamberFill", type="POINT")
        ld.energy = 900.0
        ld.color = (1.0, 0.6, 0.45)
        lo = mdl._link(bpy.data.objects.new("ChamberFill", ld))
        tc = 0.5 * (c["t0"] + c["t1"])
        rc = c["R"] - 2.0
        lo.location = (rc * math.cos(tc), rc * math.sin(tc), c["z"] + 2.2)
        lamps.append(lo)

    out = spec.get("out_dir", ".")

    def shot(tag, loc, aim, lens, res):
        cam.data.lens = lens
        cam.location = loc
        target.location = aim
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(out, "%s_%s.png" % (NAME, tag))
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s_%s.png (hand-placed)" % (NAME, tag))

    def on_stair(s, up=EYE_H):
        th = p.theta(s)
        rc = p.rc_of(p.nose(s))
        return (rc * math.cos(th), rc * math.sin(th), p.nose(s) + up)

    rock.hide_render = True
    d = _radial(math.radians(DOOR_BEARING))
    shot("door", (d[0] * (p.door["x_rock"] + 3.2), d[1] * (p.door["x_rock"] + 3.2) + 0.5,
                  FOOT_Z + EYE_H),
         (d[0] * (p.door["R"] - 2.5), d[1] * (p.door["R"] - 2.5), FOOT_Z + 1.3),
         24.0, (1000, 760))
    rock.hide_render = False
    s_mid = p.s_end * 0.18
    shot("stairs", on_stair(s_mid), on_stair(s_mid + 7.0, 1.2), 20.0, (1000, 760))
    shot("shaft", (0.8, 0.6, FOOT_Z + EYE_H), (0.0, 0.0, p.z_c), 16.0, (900, 1100))
    shot("top", on_stair(p.s_top - 5.0), on_stair(p.s_end - 0.4, 0.9), 20.0, (1000, 760))
    if p.chamber:
        c = p.chamber
        tc = 0.5 * (c["t0"] + c["t1"])
        rc = p.rc_of(c["z"])
        shot("chamber", (rc * math.cos(c["t0"] - 0.35), rc * math.sin(c["t0"] - 0.35),
                         c["z"] + EYE_H),
             ((c["Rb"] - 0.3) * math.cos(tc), (c["Rb"] - 0.3) * math.sin(tc), c["z"] + 1.2),
             20.0, (1000, 760))
        rf = c["R"] - 3.2
        shot("chamber_far", (-rf * math.cos(tc) * 0.6, -rf * math.sin(tc) * 0.6, c["z"] + 4.0),
             (c["R"] * math.cos(tc), c["R"] * math.sin(tc), c["z"] + 1.0), 24.0, (1000, 760))

    # the cut: both meshes bisected on the door's plane, the near half dropped
    keep = []
    for src in objects[:1] + [rock]:
        dup = src.copy()
        dup.data = src.data.copy()
        mdl._link(dup)
        bm = bmesh.new()
        bm.from_mesh(dup.data)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                               dist=1e-4, plane_co=(0.0, 0.0, 0.0),
                               plane_no=(0.0, -1.0, 0.0), clear_outer=True,
                               clear_inner=False)
        bm.to_mesh(dup.data)
        bm.free()
        for mat in dup.data.materials:
            if mat:
                mat.use_backface_culling = False
        src.hide_render = True
        keep.append(dup)
    for lo in lamps:
        lo.location = (lo.location.x, lo.location.y + 2.5, lo.location.z)
        lo.data.energy *= 1.6
    zc = 0.5 * (FOOT_Z + p.z_floor)
    shot("cut", (0.0, -62.0, zc + 2.0), (0.0, 0.0, zc), 40.0, (820, 1400))
    for dup in keep:
        bpy.data.objects.remove(dup, do_unlink=True)
    for src in objects[:1]:
        src.hide_render = False
        for mat in src.data.materials:
            if mat:
                mat.use_backface_culling = True
    bpy.data.objects.remove(rock, do_unlink=True)
    for ob in [cam, target] + lamps:
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    rock = _append_rock()
    sv = Survey(rock)
    sv.report()
    p = make_plan(sv)
    r = _Rng(SEED)

    m = _Mesh()
    _wall(m, p, r, sv)
    _door(m, p, sv)
    _flight(m, p)
    _ceiling(m, p)
    _floor(m, p, r)
    _chamber(m, p)
    _drips(m, p, r)
    coll = _collider(m, p)
    clear, head = _measure_stair(m, p)

    albedo, emissive = build_texture()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    ob = m.object(OBJECT_NAME)
    unwrap(ob, m.zones)
    mdl.finish(ob, rock_material("HellRock", albedo, emissive), strip_uvs=False)
    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    PLAN["plan"], PLAN["rock"] = p, rock

    bm = bmesh.new()
    bm.from_mesh(ob.data)
    n_open = len([e for e in bm.edges if e.is_boundary])
    bm.free()

    print("MDL STATS visual_tris=%d collision_tris=%d open_edges=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), n_open))
    print("MDL STATS profile worst_margin=%.2f (need >= %.2f) ctrl=%s"
          % (p.worst, ROCK_MIN, " ".join("%.1f:%.2f" % c for c in p.ctrl)))
    print("MDL STATS room_floor_axis=%.3f floor_at_hole=%.3f shaft_ceiling=%.3f R_top=%.2f"
          % (sv.floor, p.z_floor, p.z_c, p.R_top))
    print("MDL STATS stair steps=%d rise=%.4f climb=%.2f turns=%.2f landings=%d "
          "start=%.0fdeg arrive=%.0fdeg" % (p.n_steps, p.rise, p.climb, p.turns,
                                            len(p.landings), STAIR_START_DEG,
                                            math.degrees(p.th_end % TAU)))
    h = p.hole
    corners = []
    for t in (h["t0"], h["t1"]):
        for rr in (h["r0"], h["r1"]):
            corners.append("(%.2f, %.2f, %.2f)" % (rr * math.cos(t), h["z"], -rr * math.sin(t)))
    print("MDL STATS hole bearing=%.1f..%.1fdeg (blender ccw from +x; godot angle = -this) "
          "r=%.2f..%.2f z=%.2f throat_from=%.1fdeg godot_corners=%s"
          % (math.degrees(h["t0"]), math.degrees(h["t1"]), h["r0"], h["r1"], h["z"],
             math.degrees(h["th_a"]), " ".join(corners)))
    print("MDL STATS door bearing=%.0fdeg lining_R=%.2f rock_face=%.2f passage=%.1fm "
          "opening=%.2fx%.2f" % (DOOR_BEARING, p.door["R"], p.door["x_rock"],
                                 p.door["x_rock"] - p.door["R"], DOOR_W, DOOR_H))
    print("MDL STATS tread clear_width min=%.2f (want %.2f) headroom min=%.2f (want %.2f) "
          "at %s; walking_r=%.2f..%.2f inner_slope max=%.1fdeg"
          % (clear[0], TREAD_CLEAR, head[0], HEADROOM, head[1], clear[1], clear[2], clear[3]))
    for w in p.windows:
        print("MDL STATS window bearing=%.0fdeg z=%.1f reach=%.2f" %
              (math.degrees(w["bearing"]), w["z"], w["r_end"]))
    if p.chamber:
        c = p.chamber
        print("MDL STATS chamber z=%.2f bearing=%.0f..%.0fdeg recess=%.2f (%.0f%% of climb)"
              % (c["z"], math.degrees(c["t0"] % TAU), math.degrees(c["t1"] % TAU),
                 c["rec"], 100.0 * (c["z"] - FOOT_Z) / p.climb))
    else:
        print("MDL WARN no landing had rock enough for the chamber")
    return [ob, coll_ob]


if __name__ == "__main__":
    if "--measure-only" in sys.argv:
        mdl.reset()
        Survey(_append_rock()).report()
        print("MDL SURVEY DONE")
    elif "--dry" in sys.argv:
        mdl.reset()
        mdl.report(NAME, [o for o in build() if o.type == "MESH"])
        print("MDL DRY DONE")
    else:
        mdl.main(NAME, build, facing_yaw=0.0, post=_extra_renders)
