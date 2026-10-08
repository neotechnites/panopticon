"""
PANOPTICON -- marble: Map 2, the Bentham drawing built in the Temple of
Time's stone.

One closed rotunda, ONE CONTIGUOUS MODEL: the spike floor, the gallery
walkway, the wall of cells and the dome are a single connected mesh in a
single .glb. The tower is the only other model (marble_tower_build.py, its
own contiguous mesh, dropped in by the scene at the guard-room datum, as Map
1 does).

THE SHAPE (pass 3, to Ryan's verdict on pass 2). The rotunda's ground floor
is covered in marble spikes. The running lane is a GALLERY WALKWAY partway up
the wall of cells -- a slab at Map 1's lane height and radii, whose inner
edge is open: step off it and you drop 24 m onto the spikes. The wall is
SEVEN tiers of arched cells, three below the walkway down to the spike
floor and four above it, every cell an open recess with iron bars over the
arch. The lane tier alone stands back at WALL_R: the tiers under and over
it stand in at WALL_IN_R, so the walkway is a corridor cut into the wall.
A pilaster on every pier, a cornice on every tier, a Greek-key frieze
and a great cornice under a solid ribbed dome. No oculus: the light is the
tower's gold lantern, and a cool ambient. Nothing on the lane.

Stone only. Mechanics -- the kill cylinder over the spike floor, portal,
spawns, watch markers -- are scene nodes in maps/marble/marble.tscn.

Authored in WORLD coordinates so the scene instances it at identity:

    spike floor .......  y = FLOOR_Z (-1.0); spikes to 2.0
    tiers .............  bases -1.0 / 7.0 / 15.0 / [23.0] / 31.0 / 39.0 / 47.0 (TIER_H 8.0)
    walkway slab ......  y = SLAB_Z0 (22.0) .. DECK_Z (23.0; the runner's feet, Map 1's ring)
    guard-room floor ..  y = 27.05   (the scene's Tower node at 25.35 + 1.70)
    wall top / frieze .  y = 55.0 .. 56.8
    dome springs ......  y = 57.8, apex 79.0 (scaled to r WALL_IN_R)

Blender +Z -> Godot +Y, Blender +Y -> Godot -Z. A game bearing of b degrees
is Blender angle -b.

HOW IT IS ONE MESH. _Mesh.v() is a welding registry: two parts that put a
vertex at the same world point (to 1e-4) get the same vertex. Every part is
built against the SEAM RINGS below -- exact station angles and radii, so the
floor ends on the ring the wall starts from, the walkway slab closes onto the
third tier's cornice lines and the great cornice's back edge is the dome's
spring line. Bands between rings of different station counts are zippered
(_zipper), never left as T-junctions. Spikes are stitched into the floor's
own cells, bars into their sills, pilasters and cornices share their edges.
_check() proves it: one connected component, every edge on exactly two
faces but the bars' open backs, no duplicate positions.

Parts (each a sibling *_build.py the pipeline ships along):
    marble_lane_build   the spike floor and its spikes, the walkway slab:
                        deck, nosing, inner face, underside, wall margin
    marble_wall_build   the wall: socles, seven tiers of barred cells,
                        pilasters, cornices, frieze, great cornice, the dome

Collision is purpose-built and rides in the .glb as a `-colonly` node: the
floor, the slab (top, inner face, underside), the plain wall face, the dome.
The spikes and bars are NOT colliders: a body that leaves the walkway is dead
by the kill cylinder before it lands.

Texture: one small tile per material, repeated by UV (lib/texel.py, SHEETS
below): marble_brick (two bays by twelve 1 m courses, tinted per class, the
cells and iron darkened), marble_stone, marble_floor, marble_triangle,
marble_column, marble_portal_swirl; marble_tower (the brick's size) on the tower.

    python3 tools/modelling/maps/marble/marble_build.py --check     # geometry + contiguity, no Blender
    tools/modelling/model build marble                  # the pipeline
"""

import math
import os
import sys

try:
    import bpy
except ImportError:                       # --check on the Mac: geometry only
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break
import texel as tx  # noqa: E402  one tiling sheet per class, world-projected
import glb_textures  # noqa: E402
if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["ground"] = False
    mdl.DEFAULTS["world_grey"] = 0.30
    mdl.DEFAULTS["world_strength"] = 0.90
    mdl.DEFAULTS["views"] = []            # closed dome: the outside says nothing


def _png_size(stem):
    """(w, h) of a drawn texture: via the build's spec in Blender, else this checkout's file."""
    if bpy is not None:
        return tx.png_size(stem)
    root = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
    return glb_textures.png_size(os.path.join(root, glb_textures.find(root, stem)))

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "marble"
OBJECT_NAME = "MarbleStone"
COLLIDER_NAME = "MarbleCollision-colonly"
FACING_YAW = 0.0

NSIDE = 64                  # bays round the wall; 5.89 m chords at r 60
INNER_R = 46.7              # walkway inner lip (Map 1's ring): the open edge, the drop
OUTER_R = 57.3              # the lane's outer radius (Map 1's ring); the slab runs on to the wall
DECK_Z = 23.0               # the walkway top: the runner's feet
FLOOR_Z = -1.0              # the rotunda floor, covered in spikes: 24 m under the walkway
WALL_R = 60.0               # the wall face
LIP = 0.10                  # the walkway's chamfered nosing at the open edge
DECK_SUB = 2                # angular subdivision of the deck (2.9 m facets)
DECK_RS = (INNER_R + LIP, 49.4, 52.0, 54.6, OUTER_R)   # paving rings; the margin beyond is plain stone
SLAB_T = 1.0                # the walkway slab's thickness ...
SLAB_Z0 = DECK_Z - SLAB_T   # ... its underside, 22.0: the third tier's cornice soffit

# ---- the wall: seven tiers of cells, Map 1's cell size ----------------------
TIER_H = 8.0
N_BELOW, N_ABOVE = 3, 4     # tiers under the walkway (down to the floor) and over it
N_TIERS = N_BELOW + N_ABOVE
TIER_BASE = tuple(FLOOR_Z + k * TIER_H for k in range(N_TIERS))   # -1 7 15 23 31 39 47; top 55
SLAB_TIER = N_BELOW - 1     # the tier whose cornice is the walkway's lip (the deck closes onto it)
LANE_TIER = N_BELOW         # the tier whose base is the walkway (TIER_BASE[LANE_TIER] == DECK_Z)
SILL_UP = 1.0               # arch sill over the tier base (a socle under every sill)
ARCH_W = 4.0                # cell mouth width
ARCH_JAMB = 3.5             # jamb height, sill to springing; head r 2.0: 5.5 m mouths, Map 1's tallest
HEAD_SEG = 6                # segments in the semicircular head
CELL_D = 3.0                # cell depth into the wall: an open recess to a dark back wall
BAR_N = 5                   # iron bars over every arch ...
BAR_HW = 0.065              # ... 0.13 m square ...
BAR_D = 0.5                 # ... standing on the sill this far into the reveal, tips set in the head
BAND_Z = (7.4, 8.0)         # the tier cornice, over the tier base; its top is the next tier's base
SLAB_BAND_Z = (SLAB_Z0 - TIER_BASE[SLAB_TIER], TIER_H)   # (7.0, 8.0): the slab tier's, one metre thick
BAND_PROUD = 0.45           # ... as proud as the pilasters, which run up into it
FRIEZE_Z = (TIER_BASE[-1] + TIER_H, TIER_BASE[-1] + TIER_H + 1.8)     # 55.0 .. 56.8, Greek key
CORNICE_Z = (FRIEZE_Z[1], FRIEZE_Z[1] + 1.0)                          # 56.8 .. 57.8, the great cornice
CORNICE_PROUD = 0.8
# The corridor: the lane tier stays at WALL_R; the tiers under and over it stand in at WALL_IN_R,
# their cornice fronts on the lip. 50 bays keep one brick drawing a bay at the same texel density.
WALL_IN_R = INNER_R + BAND_PROUD    # 47.15: the inner tiers' wall face
NSIDE_IN = 50
CEIL_Z = TIER_BASE[LANE_TIER + 1]   # 31.0: the corridor's ceiling, the upper tiers' underside


def tier_ring(tier):
    """(face radius, bays) of a tier's wall."""
    return (WALL_R, NSIDE) if tier == LANE_TIER else (WALL_IN_R, NSIDE_IN)


# ---- the dome -------------------------------------------------------------
DOME_Z0 = CORNICE_Z[1]      # 57.8
DOME_K = WALL_IN_R / WALL_R # the dome scaled whole to the inner tiers' radius
DOME_RISE = 27.0 * DOME_K
DOME_RINGS = 8
DOME_CAP_R = 4.2 * DOME_K   # flat medallion at the crown

# ---- the spike floor ------------------------------------------------------
SPIKE_SEED = 7702141
SPIKE_R0, SPIKE_R1 = 10.3, 45.5   # spikes from the tower's foot to under the walkway's lip
SPIKE_PITCH = 2.6           # floor cell pitch, radial and along a ring
SPIKE_H = (1.4, 2.8)        # spike height, short .. tall
SMALL_EVERY = 3             # a small spike at the foot of every third one
SMALL_H = 0.45              # ... this fraction of its height
BASE_K = (0.08, 0.14)       # base half-width = BASE_K[0] + BASE_K[1] * H: sharp
GUARD_EYE_Z = 28.7          # tower floor 27.05 + 1.65
LANE_R = 52.0

# ---- the bars between finish and start ---------------------------------------
# Nothing stands on the lane. The bars that stop a runner walking back from
# the start line to the portal are a scene node (RockBars, as on Map 1), at
# this bearing, and the lane's stations are even.
BARS_B = 353.0

# ---- texture ------------------------------------------------------------------
TEX_SEED = 9021131          # the window unwrap's random stream
ROUGHNESS = 1.0
METALLIC = 0.0
UV_SCALE = 0.066            # window unwrap: cell units a metre (a cell is a 64 px window)
UV_PAD = 1.5 / 64.0         # ... kept this far inside its window, as a fraction of it
CELL_PX = 64.0

# The windowed zones (props, the hub): each zone's window in its own tile, the 64 px
# cell it had on the old atlas -- (u0, v0, u1, v1) of the file TILE_OF names.
ZONES = {z: (0.0, 0.0, 1.0, 1.0) for z in ("marble", "marble2", "shade", "plinth", "floor", "portal",
                                           "spike", "field", "stone", "coffer", "frieze", "iron")}
ZONES["column"] = ZONES["band"] = ZONES["collar"] = (0.0, 0.0, 1.0, 1.0)   # the whole 64 px column tile
ZONES["cellin"] = (0.0, 0.0, 0.25, 0.25)                                     # 64 px of the brick
FIT = {"floor": "uv", "frieze": "uv", "coffer": "uv", "portal": "uv",   # the whole face onto the whole cell
       "band": "v", "collar": "v", "column": "u", "iron": "u"}   # ... on one axis only
ANCHORED = ("stone", "plinth", "band", "collar")        # courses stay level: no v offset, no flips
WALL_PROJECT = ("collar",)                              # unwrapped along-the-face/up whatever the tilt: the
                                                        # collar leans 45 deg, _project's floor/wall threshold
EYE_H = 1.65
TWO_PI = 2.0 * math.pi
EPS = 1e-9
UP = (0.0, 0.0, 1.0)
DOWN = (0.0, 0.0, -1.0)


# =============================================================================
# TEXTURE -- the drawn files in maps/marble/textures/, referenced, never written
# =============================================================================

class _Rng(object):
    """Deterministic LCG; the model is byte-identical every rebuild."""

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


# ---- the tiles (lib/texel.py) ----------------------------------------------
# One small tile per material, repeated by UV: brick (two bays by twelve 1 m courses),
# plain stone, the floor, the triangle row, the column, the portal swirl.
BAY_M = TWO_PI * WALL_R / NSIDE          # 5.89 m
BRICK_W, BRICK_H = _png_size("marble_brick_albedo")   # 256 x 256: two bays across
WALL_PX = BRICK_W // 2                   # 128 texels a bay: 0.046 m a texel
WALL_MPT = BAY_M / WALL_PX
COURSES = 12                             # 12.0 m up before the tile repeats
WALL_H = BRICK_H
COURSE_MPT = COURSES / float(BRICK_H)    # metres a texel up: the courses on the world 1 m grid
STONE_PX = _png_size("marble_stone_albedo")[0]
STONE_M = STONE_PX * WALL_MPT            # the plain stone's repeat
COL_W, COL_H = _png_size("marble_column_albedo")


def tile(name, stem, mode, w, h, mpt=tx.MPT, **kw):
    """Class `name` wearing maps/marble/textures/<stem>_albedo.png, w x h texels."""
    return tx.Sheet(name, mode=mode, width=w, size=h, mpt=mpt, roughness=ROUGHNESS, stem=stem, **kw)


def stone(name, mode="cyl", mpt=WALL_MPT, **kw):
    """Class `name` wearing the plain stone."""
    return tile(name, "marble_stone", mode, STONE_PX, STONE_PX, mpt, **kw)


def band_sheet():
    """The column tile turned 90 deg: the flutes run along the band, the band's height fits across them."""
    return brick("band", mode="box")      # TRIAL: the brick at its wall density


def column_sheet():
    return brick("column", mode="box")    # TRIAL: the brick at its wall density


# Linear multipliers over the brick: each class's old mean colour.
TINT_SHADE = (0.85, 0.85, 0.85)
TINT_PLINTH_WALL = (0.8106, 0.8086, 0.8369)
TINT_PLINTH = (0.8285, 0.8293, 0.8617)
TINT_MARBLE2 = (0.7939, 0.7923, 0.8147)
TOWER_STEM = "marble_tower"           # the tower's own tile: his brick pixels at the chapel's grey
TINT_BARS = None
TINT_CELL = (0.0280, 0.0329, 0.0643)     # the brick massively darkened: the old cell interiors' mean
TINT_IRON = (0.0366, 0.0499, 0.2038)     # the plain stone darkened: the old iron's mean


def iron_sheet():
    return stone("iron", mode="box", tint=TINT_IRON)


def brick(name, mpt_u=WALL_MPT, mpt_v=COURSE_MPT, tint=None, stem="marble_brick", **kw):
    """Class `name` wearing the brick (or a tile its size, `stem`) at mpt_u across and mpt_v up."""
    return tx.Sheet(name, mpt=mpt_v, mpt_u=mpt_u, size=BRICK_H, width=BRICK_W,
                    roughness=ROUGHNESS, stem=stem, tint=tint, **kw)


def ashlar_sheet(name, across, tint=None, **kw):
    """Class `name` wearing the brick, one bay spanning `across` metres."""
    return brick(name, across / WALL_PX, COURSE_MPT, tint, **kw)


def shade_sheet(name, **kw):
    """Class `name` wearing the brick in the shade's palette."""
    return brick(name, tint=TINT_SHADE, **kw)


def _wall_ref(c):
    """The ring a face's bricks are measured on: the lane tier's and the ceiling at WALL_R, else WALL_IN_R."""
    return WALL_R if math.hypot(c[0], c[1]) > 0.5 * (WALL_IN_R + WALL_R) or abs(c[2] - CEIL_Z) < 1e-6 else WALL_IN_R


_WALL = dict(ref_r=_wall_ref, phase=(0.0, FLOOR_Z))
SHEETS = {
    "marble": brick("marble", **_WALL),
    "shade": brick("shade", tint=TINT_SHADE, **_WALL),
    "plinth": brick("plinth", mpt_v=COURSE_MPT / 2.0, tint=TINT_PLINTH_WALL, **_WALL),   # 0.5 m courses
    "cellin": brick("cellin", tint=TINT_CELL, **_WALL),
    "field": tx.Sheet("field", mpt=COURSE_MPT, mpt_u=WALL_MPT, size=BRICK_H, width=BRICK_W,
                      roughness=ROUGHNESS, stem="marble_pit", mode="box"),   # the pit floor: its own tile, brick density
    "spike": stone("spike", mode="box", mpt=tx.MPT),
    "floor": tile("floor", "marble_floor", "fit", 64, 64, mpt=2.7 / 64.0),
    "frieze": stone("frieze", ref_r=WALL_IN_R),   # unruled; the Greek key was tile("frieze", <its file>, "fit", 256, 64)
    "column": column_sheet(),
    "band": band_sheet(),
    "iron": iron_sheet(),
    "dome": tile("dome", "marble_triangle", "custom", 128, 20),          # the triangle row round the dome's foot
    "vault": stone("vault", mode="custom"),                              # ... and plain stone above it
}
_CLASS = {"marble2": "marble", "collar": "band"}


# ---- the props: windowed zones on their own tiles, the brick world-boxed -----
# A prop's cell drew 16 px courses at UV_SCALE: 3.97 m. Its bricks keep that.
PROP_COURSE_M = 16.0 / (UV_SCALE * CELL_PX * (1.0 - 2.0 * UV_PAD))
PROP_MPT = PROP_COURSE_M / (WALL_H / float(COURSES))
PROP_BRICKS = {"marble": None, "marble2": TINT_MARBLE2, "shade": TINT_SHADE, "plinth": TINT_PLINTH}
TILE_OF = {                              # zone: (material key, stem, tint, glows)
    "floor": ("floor", "marble_floor", None, False),
    "portal": ("glow", "marble_portal_swirl", None, True),
    "column": ("column", "marble_column", None, False),
    "band": ("column", "marble_column", None, False),
    "collar": ("column", "marble_column", None, False),
    "cellin": ("cellin", "marble_brick", TINT_CELL, False),
    "iron": ("iron", "marble_stone", TINT_IRON, False),
}
TURNED = ("band", "collar")              # the column's window turned: flutes along the band


def prop_finish(ob, zones, name, atlas_index=None):
    """A window-unwrapped model's materials, after unwrap(): brick zones re-projected onto the
    brick (world box, PROP_MPT, tinted), every other zone on its own tile (TILE_OF, else the
    plain stone), its window already in it. zones[pi] None leaves that face alone; atlas_index
    is the slot the model already has for the untinted brick (the hub)."""
    me = ob.data
    uvl = me.uv_layers["UVMap"]
    sheets = {z: brick(z, PROP_MPT, PROP_MPT, t, mode="box") for z, t in PROP_BRICKS.items()}
    for z in ("column", "band", "collar"):   # TRIAL: the column zones wear the brick at wall density
        sheets[z] = brick(z, mode="box")
    faces, kind = {}, {}
    for pi, poly in enumerate(me.polygons):
        z = zones[pi]
        if z is None:
            continue
        loops = list(poly.loop_indices)
        if z in sheets:
            cos = [tuple(me.vertices[me.loops[li].vertex_index].co) for li in loops]
            for li, uv in zip(loops, tx.box_uv(cos, tuple(poly.normal), sheets[z])):
                uvl.data[li].uv = uv
            cls = z
        else:
            spec = TILE_OF.get(z, ("stone", "marble_stone", None, False))
            if z in TURNED:
                u0, v0, u1, v1 = ZONES[z]
                for li in loops:
                    u, v = uvl.data[li].uv
                    uvl.data[li].uv = (u0 + (v - v0) / (v1 - v0) * (u1 - u0), v0 + (u - u0) / (u1 - u0) * (v1 - v0))
            cls = "~" + spec[0]
            kind[cls] = spec
        faces.setdefault(cls, []).append(pi)
    if atlas_index is None:
        me.materials.clear()
    for cls in sorted(faces):
        if cls == "marble" and atlas_index is not None:
            idx = atlas_index
        else:
            if cls in kind:
                key, stem, tint, glows = kind[cls]
                img = tx.image(stem + "_albedo")
                if glows:
                    mat = stone_material(name + "Glow", img, img)
                else:
                    mat = tx.material("%s_%s" % (name, key), img, None, ROUGHNESS, METALLIC, False, tint)
            else:
                alb = tx.images("marble", sheets[cls])[0]
                mat = tx.material("%s_%s" % (name, cls), alb, None, ROUGHNESS, METALLIC, False, sheets[cls].tint)
            mat.diffuse_color = (0.78, 0.76, 0.72, 1.0)
            idx = len(me.materials)
            me.materials.append(mat)
        for pi in faces[cls]:
            me.polygons[pi].material_index = idx
    if atlas_index is None:
        me.shade_flat()
    return sorted(faces)


def stone_material(name, albedo, emissive):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    for img, socket, y in ((albedo, "Base Color", 260), (emissive, "Emission Color", -220)):
        if img is None:
            bsdf.inputs[socket].default_value = (0.0, 0.0, 0.0, 1.0)
            continue
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.interpolation = "Closest"
        node.location = (-460, y)
        nt.links.new(node.outputs["Color"], bsdf.inputs[socket])
    bsdf.inputs["Roughness"].default_value = ROUGHNESS
    bsdf.inputs["Metallic"].default_value = METALLIC
    bsdf.inputs["Emission Strength"].default_value = 1.0   # exactly 1.0: no KHR warning
    mat.diffuse_color = (0.78, 0.76, 0.72, 1.0)
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
    """Face accumulator: every face states the direction its normal must point."""

    WELD = 1.0e-4

    def __init__(self):
        self.verts = []
        self.faces = []
        self.zones = []
        self.groups = []                          # per triangle: the emitted face it came from
        self.face_uv = {}                         # triangle index -> {vertex: (u, v)} when the face states its own
        self._index = {}

    def v(self, p):
        """The vertex at p -- the existing one if a part already put one there."""
        key = (round(p[0] / self.WELD), round(p[1] / self.WELD), round(p[2] / self.WELD))
        i = self._index.get(key)
        if i is None:
            i = len(self.verts)
            self.verts.append((float(p[0]), float(p[1]), float(p[2])))
            self._index[key] = i
        return i

    def _emit(self, idx, want, zone, uv=None):
        pts = [self.verts[j] for j in idx]
        n = _newell(pts)
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0.0:
            idx = list(reversed(idx))
        gid = len(self.groups)                    # the atlas window is per emitted face, not per triangle
        if uv is not None:                        # stated per vertex: the same for every triangle of the face
            for k in range(2 if len(idx) == 4 else 1):
                self.face_uv[len(self.faces) + k] = uv
        if len(idx) == 4:
            self.faces.append((idx[0], idx[1], idx[2]))
            self.faces.append((idx[0], idx[2], idx[3]))
            self.zones.append(zone)
            self.zones.append(zone)
            self.groups += [gid, gid]
        else:
            self.faces.append(tuple(idx))
            self.zones.append(zone)
            self.groups.append(gid)

    def quad(self, a, b, c, d, want, zone, uv=None):
        self._emit([a, b, c, d], want, zone, uv)

    def tri(self, a, b, c, want, zone):
        self._emit([a, b, c], want, zone)

    def fan(self, ring, want, zone):
        gid = len(self.groups)
        for i in range(1, len(ring) - 1):
            self.tri(ring[0], ring[i], ring[i + 1], want, zone)
            self.groups[-1] = gid                 # the whole fan is one face for the atlas

    def poly(self, ring, want, zone):
        """A convex polygon as a fan from its first vertex."""
        self.fan(ring, want, zone)

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


def pol(bearing_deg, rad, z):
    """Game bearing -> Blender xy (a game bearing of b is Blender angle -b)."""
    a = math.radians(-bearing_deg)
    return (rad * math.cos(a), rad * math.sin(a), z)


def _add(p, q, s=1.0):
    return (p[0] + q[0] * s, p[1] + q[1] * s, p[2] + q[2] * s)


def _unit(p):
    n = math.sqrt(p[0] ** 2 + p[1] ** 2 + p[2] ** 2) or 1.0
    return (p[0] / n, p[1] / n, p[2] / n)


ANG = [TWO_PI * i / NSIDE for i in range(NSIDE)]

# =============================================================================
# SEAM CONTRACT -- the rings the parts meet on. Angles are Blender radians,
# sorted ascending in [0, 2pi). Both sides of a seam call the same function,
# so the floats agree and _Mesh.v welds them.
# =============================================================================

PILASTER_W = 1.0            # the pier between two cells, proud of the wall face
PILASTER_PROUD = 0.45


def ring_pts(angles, rad, z):
    """World points of a ring."""
    return [(rad * math.cos(a), rad * math.sin(a), z) for a in angles]


def lane_angles():
    """The lane system's stations, 128 even. Used by the deck, both podium
    walls, the trough's inner rings and the inner bed's outer band."""
    return [TWO_PI * i / (NSIDE * DECK_SUB) for i in range(NSIDE * DECK_SUB)]


def wall_stations(rad=WALL_R, n=NSIDE):
    """The wall's stations, 192 round: every bay corner and the pilaster edge
    PILASTER_W/2 along the chord on each side of it -- as (angle, x, y), sorted
    by angle. They are CHORD points (_Bay.at), not points on the r 60 circle:
    the wall part reaches them with the same _Bay arithmetic, so they weld.
    The trough's outer ring, every cornice's back edge and the dome's spring
    ring are made of these."""
    out = []
    for i in range(n):
        bay = _Bay(i, rad, n)
        for u in (0.0, PILASTER_W / 2.0, bay.L - PILASTER_W / 2.0):
            x, y, _z = bay.at(u, 0.0)
            out.append((math.atan2(y, x) % TWO_PI, x, y))
    return sorted(out)


def station_pts(stations, z):
    return [(x, y, z) for (_a, x, y) in stations]


def station_angles(stations):
    return [a for (a, _x, _y) in stations]


TOWER_BASE_R = 8.0          # the tower's bottom step: the floor runs in under it
TOWER_FOOT_Z = FLOOR_Z


def corner_pt(i, z, proud, rad=WALL_R, n=NSIDE):
    """The pilaster/cornice corner: the radial point r rad - proud on bay
    corner i's own bearing, so both bays meeting there use one vertex."""
    a = TWO_PI * (i % n) / n
    r = rad - proud
    return (r * math.cos(a), r * math.sin(a), z)


def slab_stations(rad=WALL_R, n=NSIDE):
    """The 192 stations of a tier cornice's FRONT line, proud BAND_PROUD of
    the wall: per bay the radial corner point (corner_pt) and the two
    pilaster-edge points (_Bay.at(u, z, -BAND_PROUD)) -- as (angle, x, y),
    sorted by angle. The wall part's cornice fronts are made of exactly these
    points, so the walkway slab welds to the slab tier's cornice lines."""
    out = []
    for i in range(n):
        bay = _Bay(i, rad, n)
        x, y, _z = corner_pt(i, 0.0, BAND_PROUD, rad, n)
        out.append((math.atan2(y, x) % TWO_PI, x, y))
        for u in (PILASTER_W / 2.0, bay.L - PILASTER_W / 2.0):
            x, y, _z = bay.at(u, 0.0, -BAND_PROUD)
            out.append((math.atan2(y, x) % TWO_PI, x, y))
    return sorted(out)


def seam_wall_foot():
    """(stations, y): the inner tiers' foot ring at y FLOOR_Z -- the floor ends here, the wall starts."""
    return wall_stations(WALL_IN_R, NSIDE_IN), FLOOR_Z


def seam_slab():
    """(stations, y): the slab tier's cornice front top line, the lip: the deck closes onto it."""
    return slab_stations(WALL_IN_R, NSIDE_IN), DECK_Z


def seam_lane_foot():
    """(stations, y): the lane tier's foot at WALL_R, y DECK_Z: the deck's margin closes onto it."""
    return wall_stations(), DECK_Z


def seam_dome_spring():
    """(stations, y): the great cornice's back edge at y DOME_Z0 -- the dome's spring ring."""
    return wall_stations(WALL_IN_R, NSIDE_IN), DOME_Z0


def _zipper(m, outer, outer_ang, inner, inner_ang, want, zone):
    """Triangles between two closed rings of different station counts, each
    given as vertex ids with their angles (ascending). Advances whichever
    side's next angle is smaller, so no edge is left with a vertex in its
    middle. `want` may be a vector or a function of the face's centroid."""
    no, ni = len(outer), len(inner)
    # start both at their smallest angle; angles are in [0, 2pi)
    io = ii = 0
    steps = 0
    # the outer ring is the reference; iterate until both wrapped
    a_o = list(outer_ang) + [outer_ang[0] + TWO_PI]
    a_i = list(inner_ang) + [inner_ang[0] + TWO_PI]
    # align: rotate inner so its first angle is the first >= outer[0]
    while io < no or ii < ni:
        next_o = a_o[io + 1] if io < no else 1e9
        next_i = a_i[ii + 1] if ii < ni else 1e9
        o0, i0 = outer[io % no], inner[ii % ni]
        if next_o < next_i - 1e-9:                # ties advance the inner ring: fatter triangles
            o1 = outer[(io + 1) % no]
            tri = (o0, o1, i0)
            io += 1
        else:
            i1 = inner[(ii + 1) % ni]
            tri = (o0, i1, i0)
            ii += 1
        w = want(m.verts[tri[0]], m.verts[tri[1]], m.verts[tri[2]]) if callable(want) else want
        m.tri(tri[0], tri[1], tri[2], w, zone)
        steps += 1
        if steps > no + ni + 2:
            raise RuntimeError("zipper ran away")


def _ring(m, rad, z, n=NSIDE, ang=None):
    ang = ang or ANG
    return [m.v((rad * math.cos(a), rad * math.sin(a), z)) for a in ang[:n]]


def _rad_of(i):
    """Outward unit vector at ring vertex i (Blender xy)."""
    return (math.cos(ANG[i]), math.sin(ANG[i]), 0.0)


def _mid_rad(i):
    a = ANG[i] + math.pi / NSIDE
    return (math.cos(a), math.sin(a), 0.0)


def _band(m, lo, hi, inward, zone):
    """Quads between two rings (same count)."""
    n = len(lo)
    for i in range(n):
        j = (i + 1) % n
        w = _mid_rad(i) if n == NSIDE else _unit(_add(m.verts[lo[i]], m.verts[lo[j]]))
        want = (-w[0], -w[1], 0.0) if inward else w
        m.quad(lo[i], lo[j], hi[j], hi[i], want, zone)


class _Bay(object):
    """One flat facet of the wall: corner P0 at ANG[i], P1 at ANG[i+1], r WALL_R.
    Local (u, z, d): u along the chord, z up, d into the wall."""

    def __init__(self, i, rad=WALL_R, n=NSIDE):
        a0, a1 = TWO_PI * i / n, TWO_PI * ((i + 1) % n) / n
        self.rad, self.n = rad, n
        self.p0 = (rad * math.cos(a0), rad * math.sin(a0))
        self.p1 = (rad * math.cos(a1), rad * math.sin(a1))
        dx, dy = self.p1[0] - self.p0[0], self.p1[1] - self.p0[1]
        self.L = math.hypot(dx, dy)
        self.u = (dx / self.L, dy / self.L)
        am = a0 + math.pi / n                            # never the wrap-around mean
        self.n_in = (-math.cos(am), -math.sin(am), 0.0)     # toward the axis
        self.n_out = (math.cos(am), math.sin(am), 0.0)

    def at(self, u, z, d=0.0):
        return (self.p0[0] + self.u[0] * u + self.n_out[0] * d,
                self.p0[1] + self.u[1] * u + self.n_out[1] * d, z)

    def dir(self, du, dz):
        """A local (u, z) direction as a world vector."""
        return (self.u[0] * du, self.u[1] * du, dz)


# =============================================================================
# THE ARCH -- an outline and its frame, by rays from the springing centre
# =============================================================================

def _ray_box(cx, cz, th, u0, u1, z0, z1):
    """Where the ray from (cx, cz) at angle th leaves the box."""
    dx, dz = math.cos(th), math.sin(th)
    t = 1e9
    if abs(dx) > EPS:
        t = min(t, ((u1 if dx > 0 else u0) - cx) / dx)
    if abs(dz) > EPS:
        t = min(t, ((z1 if dz > 0 else z0) - cz) / dz)
    return (cx + dx * t, cz + dz * t)


def _arch_thetas(c, hw, s, sp, u0, u1, z0, z1):
    """Angles round the springing centre: the head's segments, the rays to the
    rectangle's corners, the sill corners and the sill's middle. Sorted."""
    ths = [math.pi * k / HEAD_SEG for k in range(HEAD_SEG + 1)]
    for (x, z) in ((u1, z1), (u0, z1), (u0, z0), (u1, z0), (c - hw, s), (c + hw, s), (c, s)):
        ths.append(math.atan2(z - sp, x - c) % TWO_PI)
    ths.sort()
    out = []
    for t in ths:
        if not out or t - out[-1] > 1e-6:
            out.append(t)
    if out and TWO_PI - out[-1] < 1e-6:
        out.pop()
    return out


def _arch_inner(c, hw, s, sp, th):
    """The arch outline at angle th: the head for 0..pi, else the jamb/sill box."""
    if th <= math.pi + 1e-9:
        return (c + hw * math.cos(th), sp + hw * math.sin(th))
    return _ray_box(c, sp, th, c - hw, c + hw, s, sp)


def _arch_frame(m, bay, u0, u1, z0, z1, c, hw, s, sp, depth, zone_of,
                inner_pts=None, want_in=None, back=True, back_zone="cellin", reveal_zone="shade"):
    """The bay face [u0,u1]x[z0,z1] with an arched mouth cut in it, the reveal
    running `depth` into the wall, and a back wall. Returns the inner loop.

    zone_of(zmid): the frame's zone by height. want_in: the face normal (the
    bay's inward normal by default)."""
    want = want_in or bay.n_in
    ths = _arch_thetas(c, hw, s, sp, u0, u1, z0, z1)
    inner2 = [_arch_inner(c, hw, s, sp, t) for t in ths]
    outer2 = [_ray_box(c, sp, t, u0, u1, z0, z1) for t in ths]
    vin = [m.v(bay.at(u, z)) for (u, z) in inner2]
    vout = [m.v(bay.at(u, z)) for (u, z) in outer2]
    n = len(ths)
    for k in range(n):
        j = (k + 1) % n
        zm = 0.25 * (inner2[k][1] + inner2[j][1] + outer2[k][1] + outer2[j][1])
        m.quad(vin[k], vin[j], vout[j], vout[k], want, zone_of(zm))
    if depth <= 0.0:
        return vin
    vdeep = [m.v(bay.at(u, z, depth)) for (u, z) in inner2]
    for k in range(n):
        j = (k + 1) % n
        mu = 0.5 * (inner2[k][0] + inner2[j][0])
        mz = 0.5 * (inner2[k][1] + inner2[j][1])
        w = bay.dir(c - mu, sp - mz)                       # toward the springing centre
        if abs(w[0]) + abs(w[1]) + abs(w[2]) < EPS:
            w = UP
        m.quad(vin[k], vin[j], vdeep[j], vdeep[k], w, reveal_zone)
    if back:
        # fan from the sill's middle: every other outline point is in view of
        # it, and the jamb's three collinear points never make a sliver
        k0 = min(range(n), key=lambda k: abs(ths[k] - 1.5 * math.pi))
        m.poly(vdeep[k0:] + vdeep[:k0], want, back_zone)
    return vin


# =============================================================================
# AUDIT -- what "one contiguous mesh" means, as numbers
# =============================================================================

def audit(m, label="mesh"):
    """Components, edge classes, degenerate faces, duplicate positions.

    An edge is MANIFOLD when exactly two faces use it in opposite directions,
    BOUNDARY when one face does, DOUBLED when two faces run it the same way
    (a flipped or duplicated face), OVER when three or more faces meet on it.
    Returns the dict it prints."""
    parent = list(range(len(m.verts)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    directed = {}
    degenerate = 0
    for f in m.faces:
        for k in range(3):
            e = (f[k], f[(k + 1) % 3])
            directed[e] = directed.get(e, 0) + 1
            union(e[0], e[1])
        n = _newell([m.verts[i] for i in f])
        if math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) < 1e-7:
            degenerate += 1
    used = set(i for f in m.faces for i in f)
    comps = len(set(find(i) for i in used))
    manifold = boundary = doubled = over = 0
    seen = set()
    for (a, b), n in directed.items():
        key = (min(a, b), max(a, b))
        if key in seen:
            continue
        seen.add(key)
        back = directed.get((b, a), 0)
        total = n + back
        if total == 2 and n == 1 and back == 1:
            manifold += 1
        elif total == 1:
            boundary += 1
        elif total >= 3:
            over += 1
        else:
            doubled += 1
    dup = 0
    keys = set()
    for v in m.verts:
        key = (round(v[0], 4), round(v[1], 4), round(v[2], 4))
        if key in keys:
            dup += 1
        keys.add(key)
    out = {"tris": len(m.faces), "verts": len(m.verts), "components": comps,
           "manifold_edges": manifold, "boundary_edges": boundary, "doubled_edges": doubled,
           "over_edges": over, "degenerate": degenerate, "duplicate_positions": dup,
           "unused_verts": len(m.verts) - len(used)}
    print("%s tris=%d verts=%d components=%d manifold=%d boundary=%d doubled=%d over=%d degenerate=%d dup_pos=%d unused=%d"
          % (label, out["tris"], out["verts"], comps, manifold, boundary, doubled, over, degenerate, dup, out["unused_verts"]))
    return out


def boundary_loops(m):
    """The boundary edges grouped into closed loops: (edge count, mean radius, mean z) each."""
    directed = {}
    for f in m.faces:
        for k in range(3):
            directed[(f[k], f[(k + 1) % 3])] = 1
    nxt = {}
    for (a, b) in directed:
        if (b, a) not in directed:
            nxt[a] = b
    loops = []
    seen = set()
    for a in list(nxt):
        if a in seen:
            continue
        loop, cur = [], a
        while cur in nxt and cur not in seen:
            seen.add(cur)
            loop.append(cur)
            cur = nxt[cur]
        pts = [m.verts[i] for i in loop]
        loops.append((len(loop), sum(math.hypot(q[0], q[1]) for q in pts) / len(pts),
                      sum(q[2] for q in pts) / len(pts)))
    return sorted(loops, key=lambda t: -t[0])


# =============================================================================
# UV -- per-face planar projection into a random window of its zone
# =============================================================================

def _project(cos_list, nrm, wall=False):
    """Planar 2-D coordinates for a set of points: radial/tangential for floors
    and soffits, along-the-face/up for walls (wall=True: for this face whatever
    its tilt)."""
    if abs(nrm[2]) > 0.7 and not wall:
        ac = math.atan2(sum(c[1] for c in cos_list), sum(c[0] for c in cos_list))
        rc = sum(math.hypot(c[0], c[1]) for c in cos_list) / len(cos_list)
        pts = []
        for co in cos_list:
            th = math.atan2(co[1], co[0])
            th = ac + (th - ac + math.pi) % TWO_PI - math.pi
            pts.append((math.hypot(co[0], co[1]), (th - ac) * rc))
        return pts
    ex = (-nrm[1], nrm[0])
    ln = math.hypot(ex[0], ex[1]) or 1.0
    ex = (ex[0] / ln, ex[1] / ln)
    return [(co[0] * ex[0] + co[1] * ex[1], co[2]) for co in cos_list]


def _group_uv(me, uvl, polys, zone, r, fit, anchored, wall=False):
    """One atlas window for a whole emitted face (both triangles of a quad,
    every triangle of a fan), so no seam runs down a quad's diagonal."""
    u0, v0, u1, v1 = zone
    pad_u, pad_v = UV_PAD * (u1 - u0), UV_PAD * (v1 - v0)
    span_u = (u1 - u0) - 2.0 * pad_u
    span_v = (v1 - v0) - 2.0 * pad_v
    nrm = me.polygons[polys[0]].normal
    loops = [li for pi in polys for li in me.polygons[pi].loop_indices]
    cos_list = [me.vertices[me.loops[li].vertex_index].co for li in loops]
    pts = _project(cos_list, nrm, wall)
    mi = min(p[0] for p in pts)
    mj = min(p[1] for p in pts)
    w = max(p[0] for p in pts) - mi
    h = max(p[1] for p in pts) - mj
    k = min(UV_SCALE, 1.0 / max(w, h, EPS))
    sx = sy = k
    ou, ov = r.f() * (1.0 - w * k), r.f() * (1.0 - h * k)
    fu = -1.0 if r.i(0, 1) else 1.0
    fv = -1.0 if r.i(0, 1) else 1.0
    if fit in ("uv", "u"):
        sx, ou, fu = 1.0 / max(w, EPS), 0.0, 1.0
    if fit in ("uv", "v"):
        sy, ov, fv = 1.0 / max(h, EPS), 0.0, 1.0
    if anchored:
        ov, fu, fv = 0.0, 1.0, 1.0
    for li, p in zip(loops, pts):
        s = min(ou + (p[0] - mi) * sx, 1.0)
        t = min(ov + (p[1] - mj) * sy, 1.0)
        if fu < 0.0:
            s = 1.0 - s
        if fv < 0.0:
            t = 1.0 - t
        uvl.data[li].uv = (u0 + pad_u + s * span_u, v0 + pad_v + t * span_v)


def unwrap(ob, zones, groups, seed=0, face_uv=None):
    """Every emitted face gets a random window of its zone's cell -- unless it
    stated its own (u, v) per vertex (face_uv: the dome's panels), which is
    written into the cell as given: 0..1 across the cell, inside UV_PAD."""
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = _Rng(TEX_SEED + seed * 7919 + len(me.polygons))
    face_uv = face_uv or {}
    by_group = {}
    for pi in range(len(me.polygons)):
        if pi in face_uv:
            u0, v0, u1, v1 = ZONES[zones[pi]]
            su, sv = (u1 - u0) * (1.0 - 2.0 * UV_PAD), (v1 - v0) * (1.0 - 2.0 * UV_PAD)
            for li in me.polygons[pi].loop_indices:
                u, v = face_uv[pi][me.loops[li].vertex_index]
                uvl.data[li].uv = (u0 + UV_PAD * (u1 - u0) + u * su, v0 + UV_PAD * (v1 - v0) + v * sv)
            continue
        by_group.setdefault(groups[pi], []).append(pi)
    for gid in sorted(by_group):
        polys = by_group[gid]
        z = zones[polys[0]]
        _group_uv(me, uvl, polys, ZONES[z], r, FIT.get(z, ""), z in ANCHORED, z in WALL_PROJECT)


# =============================================================================
# RENDERS -- the arena is closed, so every shot is lit from inside
# =============================================================================

TOWER_GLB = r"C:\Users\ddd\panopticon-modelling\jobs\marble_tower\out\marble_tower.glb"
if not os.path.isfile(TOWER_GLB):     # on the Mac: the shipped tower, so the guard's view has its arches
    TOWER_GLB = os.path.join(HERE, "..", "..", "..", "..", "maps", "marble", "models", "marble_tower.glb")
TOWER_Y = 25.35             # the scene's Tower node: the model's origin, world y
LANTERN_H = 5.6             # the arena light: this far over the tower datum -- under the arcade's arches, so
                            # the light leaves the room (scene: marble_tower_light_profile.tres, same number)
LANTERN_RGB = (1.0, 0.90, 0.66)   # gold: the Temple of Time's light pools (scene profile carries the same)
LANTERN_SOFT = 2.4          # the lamp is 2.4 m WIDE, not a point: the scene's size_metres, and the reason
                            # the room no longer has a hot spot in the middle of it (Ryan, pass 6)
REVIEW_LANTERN_W = 8500.0   # review renders only: the lantern's soft light, watts -- a sixth of pass 5's
                            # 70000, which blew the tower's own room white ...
REVIEW_FILL_W = 7000.0      # ... twelve unshadowed fills round the ring, standing in for the scene's nearly
                            # flat falloff (attenuation 0.3), which Blender's inverse square cannot do ...
REVIEW_PIT_W = 4500.0       # ... six over the spike floor ...
REVIEW_DOME_W = 60000.0     # ... and one under the dome, which lights its ribs


def _company():
    """The tower at its datum, for the renders only."""
    made = []
    if not os.path.isfile(TOWER_GLB):
        print("MDL note: no %s; rendering without the tower" % TOWER_GLB)
        return made
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=TOWER_GLB)
    for ob in set(bpy.data.objects) - before:
        if ob.parent is None:
            ob.location = (0.0, 0.0, TOWER_Y)
        if "colonly" in ob.name:
            ob.hide_render = True
        made.append(ob)
    bpy.context.view_layer.update()
    print("MDL note: marble_tower.glb placed at z=%.2f for the renders" % TOWER_Y)
    return made


def _render(spec, objects):
    scene = bpy.context.scene
    if spec.get("engine", "eevee").lower() == "cycles":
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = int(spec.get("samples", 64))
        scene.cycles.use_denoising = True
    else:
        scene.render.engine = "BLENDER_EEVEE"
        mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 64)))
        mdl._try(scene.eevee, "use_shadows", True)
        mdl._try(scene.eevee, "use_raytracing", True)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")
    mdl._try(scene.view_settings, "exposure", 0.0)

    made = _company()
    world = bpy.data.worlds.new("Rotunda")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.40, 0.41, 0.44, 1.0)
    bg.inputs[1].default_value = 0.35

    # the arena's light: one pale-gold lamp under the arcade, shadowed and WIDE,
    # so the arches throw soft beams as the drawing has them ...
    ld = bpy.data.lights.new("Lantern", type="POINT")
    ld.energy = REVIEW_LANTERN_W
    ld.color = LANTERN_RGB
    ld.shadow_soft_size = LANTERN_SOFT
    lantern = mdl._link(bpy.data.objects.new("Lantern", ld))
    lantern.location = (0.0, 0.0, TOWER_Y + LANTERN_H)
    made.append(lantern)
    # ... and review-only fill: unshadowed points round the ring under the
    # third tier, so the stone reads off-white and the shadows grey.
    for k in range(12):
        fd = bpy.data.lights.new("ReviewFill%d" % k, type="POINT")
        fd.energy = REVIEW_FILL_W
        fd.color = (0.90, 0.91, 0.94)
        fd.use_shadow = False
        f = mdl._link(bpy.data.objects.new("ReviewFill%d" % k, fd))
        f.location = pol(k * 30.0 + 15.0, 50.0, 38.0)
        made.append(f)
    for k in range(6):                       # ... and over the spike floor, under the walkway
        fd = bpy.data.lights.new("ReviewPit%d" % k, type="POINT")
        fd.energy = REVIEW_PIT_W
        fd.color = (0.90, 0.91, 0.94)
        fd.use_shadow = False
        f = mdl._link(bpy.data.objects.new("ReviewPit%d" % k, fd))
        f.location = pol(k * 60.0, 30.0, 12.0)
        made.append(f)
    hd = bpy.data.lights.new("ReviewDome", type="POINT")
    hd.energy = REVIEW_DOME_W
    hd.color = (0.86, 0.88, 0.92)
    hd.use_shadow = False
    h = mdl._link(bpy.data.objects.new("ReviewDome", hd))
    h.location = (0.0, 0.0, 66.0)
    made.append(h)

    target = mdl._link(bpy.data.objects.new("ShotTarget", None))
    cam = mdl._link(bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    made += [target, cam]
    out_dir = spec.get("out_dir", ".")

    only = os.environ.get("MARBLE_SHOTS", "")     # the fast loop: MARBLE_SHOTS=a,b renders only those

    def shot(name, loc, tgt, lens, res):
        if only and name not in only.split(","):
            return
        cam.data.lens = lens
        cam.data.clip_end = 600.0
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    eye = DECK_Z + EYE_H
    shot("tex_cell_1m", pol(2.8125, WALL_R - 1.0, eye), pol(2.8125, WALL_R + 0.5, DECK_Z + SILL_UP + 2.5), 18.0, (1200, 675))
    shot("tex_pilaster_1m", pol(5.625, WALL_R - 1.45, eye), pol(5.625, WALL_R - 0.4, DECK_Z + 2.0), 18.0, (1200, 675))
    shot("tex_floor_1m", pol(45.0, INNER_R + 1.0, eye), pol(45.0, INNER_R - 0.1, DECK_Z - 0.2), 18.0, (1200, 675))
    shot("runner", pol(30.0, LANE_R, eye), pol(58.0, LANE_R, DECK_Z + 1.0), 24.0, (1400, 800))
    # the guard on the dais at the axis, looking out THROUGH an arch (the openings
    # are centred on 36.25 + 22.5k) at the lane: a column at 6.3 m filled the old frame
    shot("guard", pol(36.25, 0.4, GUARD_EYE_Z), pol(36.25, LANE_R, DECK_Z), 26.0, (1400, 800))
    shot("wide", pol(200.0, 25.0, 74.0), pol(20.0, 30.0, 16.0), 18.0, (1500, 1000))
    shot("across", pol(120.0, 55.0, eye), (0.0, 0.0, TOWER_Y + 4.0), 28.0, (1400, 800))
    # from the walkway's open edge: down over the lip at the spike floor, across at the tower
    shot("edge", pol(95.0, INNER_R + 0.9, eye), pol(95.0, INNER_R - 29.1, eye - 21.0), 18.0, (1000, 1300))
    # low over the spike floor, the tower's shaft behind
    shot("floor", pol(80.0, 40.0, FLOOR_Z + 4.0), pol(60.0, 12.0, FLOOR_Z + 6.0), 24.0, (1400, 800))
    shot("tiers", pol(150.0, 48.0, eye), pol(150.0, WALL_R, 30.0), 14.0, (1000, 1300))
    # the dome from over the walkway, the drawing's own angle on it: the collar
    # off the great cornice, the pleats, the ring, the ribs closing on the crown
    shot("dome", pol(200.0, 54.0, 49.0), (0.0, 0.0, 71.0), 24.0, (1400, 900))
    # the ceiling as the game shows it (Ryan: "the ceiling of the marble room ...
    # garbled"): from the runner's eye on the lane; from the guard's eye on the
    # balcony (from the seat the arch heads cap the sightline at 17 deg -- the
    # fourth tier, never the dome); and close under the collar where the flutes
    # stand on the ring
    shot("dome_from_lane", pol(30.0, LANE_R, eye), (0.0, 0.0, 78.0), 14.0, (1400, 900))
    shot("dome_from_guard", pol(120.0, 7.6, TOWER_Y + 1.70 + EYE_H), pol(120.0, 40.0, 75.0), 16.0, (1400, 900))
    shot("dome_detail", pol(200.0, 50.0, eye), pol(200.0, 57.0, 62.0), 20.0, (1400, 900))
    # inside a cell of the tier over the walkway, 2.3 m back from the mouth,
    # looking out through the bars at the tower
    bay = _Bay(int(round(NSIDE * (360.0 - 120.0) / 360.0)) % NSIDE)
    cm = bay.at(bay.L / 2.0, TIER_BASE[LANE_TIER + 1] + SILL_UP + EYE_H, CELL_D - 0.7)
    shot("cell", cm, (0.0, 0.0, TOWER_Y + 3.0), 18.0, (1200, 800))
    # the runner's eye on the lane, at a lane-tier cell's bars about 12 m off
    shot("bars", pol(30.0, LANE_R, eye), pol(41.5, WALL_R, TIER_BASE[LANE_TIER] + SILL_UP + 2.5), 35.0, (1400, 800))
    # close on that cell from the margin of the lane, the bars foot to head in one
    # frame: the proof they are one width their full length (Ryan, pass 8)
    shot("cell_close", pol(41.5, WALL_R - 5.5, eye), pol(41.5, WALL_R, TIER_BASE[LANE_TIER] + SILL_UP + 2.75), 22.0, (1000, 1300))
    # the guard's room at eye level under the arena's own lamp: the proof that
    # the middle of the tower is no longer a hot spot (Ryan, pass 6)
    shot("tower_light", pol(200.0, 5.2, GUARD_EYE_Z), pol(20.0, 6.0, TOWER_Y + 2.9), 16.0, (1400, 900))
    # standing on the tower's balcony, the railing in hand, looking across the ring at the lane
    shot("balcony", pol(120.0, 7.1, TOWER_Y + 1.70 + EYE_H), pol(120.0, INNER_R, DECK_Z), 16.0, (1400, 800))

    for ob in made:
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def _parts():
    return ml, mw


def _stone():
    """The whole rotunda in one welded mesh, and each part's numbers."""
    ml, mw = _parts()
    m = _Mesh()
    info = {}
    n0 = len(m.faces)
    info["lane"] = ml.build(m) or {}
    info["lane"]["tris"] = len(m.faces) - n0
    n0 = len(m.faces)
    info["wall"] = mw.build(m) or {}
    info["wall"]["tris"] = len(m.faces) - n0
    return m, info


def _collider():
    ml, mw = _parts()
    c = _Mesh()
    ml.collider(c)
    mw.collider(c)
    return c


def build():
    stone, info = _stone()
    coll = _collider()
    a = audit(stone, "stone")
    ob = stone.object(OBJECT_NAME)
    classes = [_CLASS.get(z, z) for z in stone.zones]
    tx.unwrap(ob, classes, SHEETS, seed=1, face_uv=stone.face_uv, groups=stone.groups)
    mats = tx.materials(NAME, SHEETS)
    for mat in mats.values():
        mat.diffuse_color = (0.78, 0.76, 0.72, 1.0)
    order = tx.finish(ob, classes, mats)
    tx.report(SHEETS)
    print("MDL STATS surfaces=%d order=%s" % (len(ob.data.materials), ",".join(order)))
    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True

    print("MDL STATS visual_tris=%d collision_tris=%d lane_tris=%d wall_tris=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), info["lane"]["tris"], info["wall"]["tris"]))
    print("MDL STATS contiguity components=%d manifold=%d boundary=%d doubled=%d over=%d degenerate=%d dup_pos=%d"
          % (a["components"], a["manifold_edges"], a["boundary_edges"], a["doubled_edges"],
             a["over_edges"], a["degenerate"], a["duplicate_positions"]))
    if a["components"] != 1 or a["boundary_edges"] != _bar_open(info) or a["doubled_edges"] or a["over_edges"] \
            or a["degenerate"] or a["duplicate_positions"]:
        raise RuntimeError("marble: the stone is not one closed contiguous mesh")
    for part in ("lane", "wall"):
        print("MDL STATS %s %s" % (part, " ".join("%s=%s" % kv for kv in sorted(info[part].items()))))
    print("MDL STATS lane r=%.1f..%.1f y=%.2f floor_y=%.2f tiers=%d wall_r=%.1f dome=%.1f..%.1f"
          % (INNER_R, OUTER_R, DECK_Z, FLOOR_Z, N_TIERS, WALL_R, DOME_Z0, DOME_Z0 + DOME_RISE))
    return [ob, coll_ob]


def _bar_open(info):
    """The only free edges: every bar's open back and cap, which no camera can face."""
    return mw.BAR_OPEN * info["wall"]["bars"]


def _check():
    """--check: build without Blender and prove the mesh is one contiguous model."""
    stone, info = _stone()
    coll = _collider()
    a = audit(stone, "stone")
    audit(coll, "coll")
    for part in ("lane", "wall"):
        print("%s %s" % (part, " ".join("%s=%s" % kv for kv in sorted(info[part].items()))))
    loops = boundary_loops(stone)
    print("boundary loops: %d  largest: %s" % (len(loops), loops[:4]))
    ok = a["components"] == 1 and a["doubled_edges"] == 0 and a["over_edges"] == 0 \
        and a["degenerate"] == 0 and a["duplicate_positions"] == 0 and a["boundary_edges"] == _bar_open(info)
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


# The parts, imported last so their own `import marble_build` finds this module
# complete. Column-0 `import x_build as y`: tools/modelling/model ships the
# siblings it sees written exactly like that.
import marble_lane_build as ml  # noqa: E402
import marble_wall_build as mw  # noqa: E402


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_render)
