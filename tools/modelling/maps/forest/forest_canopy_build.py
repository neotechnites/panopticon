"""
PANOPTICON -- forest_canopy: the wood's trees as MAP geometry, rising into the
lane roof and carrying it. One chunk, forest_canopy.glb, at identity.

Ryan: "not a tree trunk going into a green bush at the top; it expands to
create the roof above the running prisoners."

Every tree in forest_trees.LAYOUT (bearing, radius, variant, spin, scale) is
built here at its exact place and scale, against the REAL roof: forest_build's
_Ground is grown in this scene and each limb is aimed at the roof's actual
triangulated underside where it arrives (it sags and lumps), so the wood is
one sculpt with the map and not a prop dropped on it.

    trunk   forest_tree_prop_build's own first eight rings, unchanged -- the
            cover footprint and the collider -- then on up to ~0.58 of the way
            to the roof, tapering
    limbs   four off the trunk's upper bands, sweeping out and curving up to
            end ON the roof; three twigs fork sideways off their bends; the
            trunk's own top carries on as a leader
    pads    every tip ends in a leaf boss hung UNDER the roof: its rim lies on
            the roof surface (read off the mesh, buried PAD_BURY), its underside
            dips down onto the limb. The roof's foliage thickens where a limb
            arrives, so the roof reads as carried by the trees. Nothing crosses
            the ceiling: a pad's rim is the highest thing a tree makes.

Collider: ForestCanopyCollision-colonly, every tree's own prop collider
(forest_tree_prop_build.build_collider) at that tree's transform -- the same
triangles the 113 prop instances gave the bake and the cover finder.

    tools/modelling/model build forest_canopy --views none
    tools/modelling/model build forest_canopy --views lane_up   # one EEVEE frame, lane eye looking up a tree
    python3 tools/modelling/maps/forest/forest_canopy_build.py --check
"""

import math
import os
import shutil
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

import forest_tree_build as ft  # noqa: E402  the forest atlas, the mesh library
from forest_tree_build import (_Mesh, _Rng, UP, DOWN, add, sub, norm, dot, cross,  # noqa: E402
                               lerp, bez, tube, socket_ring, zipper, pol)
import forest_tree_prop_build as ftp  # noqa: E402  the variants: trunk, sockets, collider
import forest_build as fb  # noqa: E402  the ground: the roof the trees end on
import forest_ceiling_build as fc  # noqa: E402
import forest_trees  # noqa: E402  LAYOUT: where every tree stands

if bpy is not None:
    import mdl  # noqa: E402
else:
    mdl = None

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "forest_canopy"
OBJECT_NAME = "ForestCanopy"
COLLIDER_NAME = "ForestCanopyCollision-colonly"
FACING_YAW = 0.0
LANE_Y = forest_trees.LANE_Y        # the props sank 0.05 m into the lane's relief; so do these
TREES = ("tree_a", "tree_b", "tree_c")
LETTER = {"tree_a": "a", "tree_b": "b", "tree_c": "c"}

TRUNK_TOP = 0.58            # the trunk's top, as a share of the local roof height
TRUNK_DRIFT = 0.6           # the extension keeps this much of the last band's lean
TRUNK_TAPER = 0.5           # top radius / ring-7 radius
LIMB_BANDS = (7, 8, 9, 8)   # trunk bands the four main limbs socket into (rings 8..10 are new)
LIMB_OUT = (2.4, 3.6)       # metres out along the bearing to the tip, local
LIMB_JITTER = 18.0          # degrees off an even 90 spread
LIMB_R = {"a": (0.17, 0.09), "b": (0.22, 0.11), "c": (0.19, 0.10)}   # (root, tip) radius
LIMB_SIDES = 6
LIMB_SEGS = 7
LIMB_CTRL = (0.75, 0.30)    # the bezier's control: this far out, this far up the rise
TWIGS = 3                   # off main limbs 0..2, band 3 of the limb
TWIG_OUT = (1.3, 1.9)
TWIG_ANGLE = (55.0, 95.0)   # degrees off the host limb's bearing, either side
TWIG_R = (0.075, 0.05)
TWIG_SIDES = 5
TWIG_SEGS = 4
LEADER_TAPER = 0.6
LEADER_SEGS = 4
LEADER_BEND = 0.35          # metres of sideways bow in the leader
PAD_R = {"main": (1.35, 1.7), "twig": (0.9, 1.15), "top": (1.55, 1.95)}   # rim radius, WORLD metres
PAD_DEPTH = (0.8, 1.1)      # world metres the boss hangs under the roof
PAD_BURY = 0.10             # world metres the rim sits up inside the roof sheet
PAD_SIDES = 8
PAD_WOB = 0.14
PAD_WAIST = (0.55, 0.42)    # the middle ring: this share of the rim radius, this share of the depth up
TIP_R = (fb.INNER_R + 0.3, fb.OUTER_R + 1.6)   # a pad's rim stays on the lane roof: inside the drum's foot, off the wall
WELL_CLEAR = 0.5            # a pad keeps its rim this far outside a sun well's blob
CROWN_MIN_Z = ftp.CROWN_MIN_Z
SEED = 4471021

MAX_TRIS = 150000


# =============================================================================
# THE ROOF -- the real underside, off the built ground
# =============================================================================

def _tri_z(tri, x, y):
    """z of the triangle's plane at (x, y) if (x, y) is inside it in plan, else None."""
    (ax, ay, az), (bx, by, bz), (cx, cy, cz) = tri
    d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(d) < 1e-12:
        return None
    u = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / d
    v = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / d
    w = 1.0 - u - v
    if u < -1e-6 or v < -1e-6 or w < -1e-6:
        return None
    return u * az + v * bz + w * cz


class _Roof(object):
    """The lane roof as forest.glb ships it: gallery quads by (band, column)."""

    def __init__(self):
        g = fb._Ground()
        g.build()
        self.g = g
        self.nc = len(g.gal[0])
        self.tris = {}
        for k in range(len(g.gal) - 1):
            for i in range(self.nc):
                fis = g.m.quads.get(frozenset(fc.gal_quad_ids(g, k, i)))
                if fis:
                    self.tris[(k, i)] = [tuple(g.m.verts[j] for j in g.m.faces[fi]) for fi in fis]
        self.wells = [(sh["centre"], sh["radius"]) for sh in g.shafts]

    def z(self, x, y):
        """The underside's height over (x, y), read off its own triangles."""
        bearing = (-math.degrees(math.atan2(y, x))) % 360.0
        i0 = int(bearing / (360.0 / self.nc))
        rad = math.hypot(x, y)
        for k in range(len(fc.GALLERY_R) - 1):
            if not (fc.GALLERY_R[k + 1] - 0.8 <= rad <= fc.GALLERY_R[k] + 0.8):
                continue
            for di in (0, -1, 1, -2, 2):
                for tri in self.tris.get((k, (i0 + di) % self.nc), ()):
                    z = _tri_z(tri, x, y)
                    if z is not None:
                        return z
        return fc.gallery_z(self.g, x, y)

    def well_clear(self, x, y, margin):
        return all(math.hypot(x - c[0], y - c[1]) >= r * 1.7 + margin for (c, r) in self.wells)


# =============================================================================
# PLACEMENT -- forest_trees.place, in Blender's frame
# =============================================================================

class _Place(object):
    """Local Blender xyz of a prop -> world: rotate by yaw+spin, scale, stand at the foot."""

    def __init__(self, bearing, radius, spin, scale):
        phi = math.radians(-bearing + spin)
        self.c, self.s = math.cos(phi), math.sin(phi)
        self.k = scale
        self.foot = pol(bearing, radius, LANE_Y)

    def __call__(self, p):
        x = self.foot[0] + self.k * (self.c * p[0] - self.s * p[1])
        y = self.foot[1] + self.k * (self.s * p[0] + self.c * p[1])
        return (x, y, LANE_Y + self.k * p[2])

    def xy(self, x, y):
        return self((x, y, 0.0))[:2]


# =============================================================================
# ONE TREE, in its own local frame
# =============================================================================

def _trunk_spec(spec, top_z):
    """The variant's trunk, its first eight rings untouched, carried on up to top_z."""
    path = [tuple(p) for p in spec["path"]]
    radii = list(spec["radii"])
    p6, p7 = path[-2], path[-1]
    dz = p7[2] - p6[2]
    drift = ((p7[0] - p6[0]) / dz * TRUNK_DRIFT, (p7[1] - p6[1]) / dz * TRUNK_DRIFT)
    n = 3
    for k in range(1, n + 1):
        t = k / float(n)
        z = p7[2] + (top_z - p7[2]) * t
        path.append((p7[0] + drift[0] * (z - p7[2]), p7[1] + drift[1] * (z - p7[2]), z))
        radii.append(radii[7] * (1.0 - (1.0 - TRUNK_TAPER) * t))
    out = dict(spec)
    out["path"], out["radii"] = path, radii
    return out


def _fit_tip(place, roof, tip_xy, pad_r):
    """Pull a tip's plan position onto the lane roof: rim inside TIP_R, clear of the wells."""
    wx, wy = place.xy(*tip_xy)
    rad = math.hypot(wx, wy)
    lo, hi = TIP_R[0] + pad_r, TIP_R[1] - pad_r
    if rad < lo or rad > hi:
        want = max(lo, min(hi, rad))
        wx, wy = wx * want / rad, wy * want / rad
    return (wx, wy)


def _flip_if_off(place, roof, root_xy, d, out, pad_r):
    """A limb that would leave the roof (into the drum or the wall) is mirrored
    across the lane's tangent before its socket is chosen; a limb over a sun
    well is turned off it."""
    def world_ok(dd):
        wx, wy = place.xy(root_xy[0] + dd[0] * out, root_xy[1] + dd[1] * out)
        rad = math.hypot(wx, wy)
        return TIP_R[0] + pad_r <= rad <= TIP_R[1] - pad_r
    if not world_ok(d):
        fx, fy = place.foot[0], place.foot[1]
        rr = math.hypot(fx, fy)
        radial = (fx / rr, fy / rr)
        wd = (place.c * d[0] - place.s * d[1], place.s * d[0] + place.c * d[1])   # world direction
        k = wd[0] * radial[0] + wd[1] * radial[1]
        wd = (wd[0] - 2.0 * k * radial[0], wd[1] - 2.0 * k * radial[1])          # radial part flipped
        d = (place.c * wd[0] + place.s * wd[1], -place.s * wd[0] + place.c * wd[1], 0.0)
    for _ in range(6):
        wx, wy = place.xy(root_xy[0] + d[0] * out, root_xy[1] + d[1] * out)
        if roof.well_clear(wx, wy, pad_r + WELL_CLEAR):
            break
        a = math.radians(35.0)
        d = (d[0] * math.cos(a) - d[1] * math.sin(a), d[0] * math.sin(a) + d[1] * math.cos(a), 0.0)
    return d


def _roof_pad(m, rng, end_ring, tip, pad_r_w, depth_w, place, roof):
    """The leaf boss under the roof: waist ring, rim ring ON the roof, capped inside it."""
    k = place.k
    R, depth = pad_r_w / k, depth_w / k
    cx, cy, cz = tip
    waist, rim = [], []
    for s in range(PAD_SIDES):
        a = 2.0 * math.pi * s / PAD_SIDES + rng.f() * 0.3
        rw = R * PAD_WAIST[0] * (1.0 + PAD_WOB * rng.sf())
        waist.append(m.v((cx + rw * math.cos(a), cy + rw * math.sin(a),
                          cz + depth * PAD_WAIST[1] * (1.0 + 0.12 * rng.sf()))))
    for s in range(PAD_SIDES):
        a = 2.0 * math.pi * s / PAD_SIDES + rng.f() * 0.3
        rr = R * (1.0 + PAD_WOB * rng.sf())
        lx, ly = cx + rr * math.cos(a), cy + rr * math.sin(a)
        wx, wy = place.xy(lx, ly)
        z = (roof.z(wx, wy) + PAD_BURY - LANE_Y) / k
        rim.append(m.v((lx, ly, z)))
    zipper(m, waist, end_ring, DOWN, "leaf", centre=(cx, cy, cz))
    above = (cx, cy, cz + depth + 0.5)
    for s in range(PAD_SIDES):
        q = (s + 1) % PAD_SIDES
        idx = (waist[s], waist[q], rim[q], rim[s])
        m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), above), "leaf")
    m.fan(rim, UP, "leaf")
    return rim


def _canopy_limb(m, rng, spec, host, band, patch, bearing, out, radii, sides, segs,
                 pad_kind, place, roof, flip):
    """One limb: socket in the host, sweep out and up, end in a pad on the roof."""
    d = ftp._dir_of(bearing)
    pad_r_w = rng.u(*PAD_R[pad_kind])
    if flip:
        c = m.centroid(host[band] + host[band + 1])
        d = _flip_if_off(place, roof, (c[0], c[1]), d, out, pad_r_w)
        bearing = -math.degrees(math.atan2(d[1], d[0]))
    quads, root, plane_n = ftp._patch(m, host, band, patch[0], patch[1], bearing)
    wx, wy = _fit_tip(place, roof, (root[0] + d[0] * out, root[1] + d[1] * out), pad_r_w)
    depth_w = rng.u(*PAD_DEPTH)
    z_tip = (roof.z(wx, wy) - depth_w - LANE_Y) / place.k
    # back to local plan
    lx = place.c * (wx - place.foot[0]) + place.s * (wy - place.foot[1])
    ly = -place.s * (wx - place.foot[0]) + place.c * (wy - place.foot[1])
    tip = (lx / place.k, ly / place.k, z_tip)
    collar = add(root, plane_n, ftp.STUB * radii[0])
    reach = sub(tip, collar)
    ctrl = (collar[0] + reach[0] * LIMB_CTRL[0], collar[1] + reach[1] * LIMB_CTRL[0],
            collar[2] + reach[2] * LIMB_CTRL[1])
    path = [root, collar] + bez(collar, ctrl, tip, segs)[1:]
    flat = ftp._collar(m, quads, bearing, root, radii[0])
    ring0 = socket_ring(m, quads, path, radii[0], sides, "bark", flat=flat, at_start=True)
    rings = tube(m, path, tuple(radii), sides, "bark", caps=(False, False),
                 wob=spec["wob"], rng=rng, first_ring=ring0)
    _roof_pad(m, rng, rings[-1], path[-1], pad_r_w, depth_w, place, roof)
    return rings, bearing


def _leader(m, rng, spec, trunk, place, roof):
    """The trunk's top carries on, bowing a little, into the biggest pad."""
    top_ring, top_c = trunk["top_ring"], trunk["top_centre"]
    n = len(top_ring)
    ang = [math.atan2(m.verts[v][1] - top_c[1], m.verts[v][0] - top_c[0]) for v in top_ring]
    pad_r_w = rng.u(*PAD_R["top"])
    a = rng.f() * 2.0 * math.pi
    wx, wy = _fit_tip(place, roof, (top_c[0] + 0.5 * math.cos(a), top_c[1] + 0.5 * math.sin(a)), pad_r_w)
    depth_w = rng.u(*PAD_DEPTH)
    z_tip = (roof.z(wx, wy) - depth_w - LANE_Y) / place.k
    lx = place.c * (wx - place.foot[0]) + place.s * (wy - place.foot[1])
    ly = -place.s * (wx - place.foot[0]) + place.c * (wy - place.foot[1])
    tip = (lx / place.k, ly / place.k, z_tip)
    b = a + math.pi / 2.0
    mid = lerp(top_c, tip, 0.5)
    ctrl = (mid[0] + LEADER_BEND * math.cos(b), mid[1] + LEADER_BEND * math.sin(b), mid[2])
    path = bez(top_c, ctrl, tip, LEADER_SEGS)
    r0, r1 = trunk["top_r"], trunk["top_r"] * LEADER_TAPER
    rings = [list(top_ring)]
    for i in range(1, len(path)):
        t = i / float(len(path) - 1)
        r = r0 + (r1 - r0) * t
        cx, cy, cz = path[i]
        rings.append([m.v((cx + r * (1.0 + spec["wob"] * rng.sf()) * math.cos(ang[s]),
                           cy + r * (1.0 + spec["wob"] * rng.sf()) * math.sin(ang[s]), cz))
                      for s in range(n)])
    for i in range(len(rings) - 1):
        axis = lerp(path[i], path[i + 1], 0.5)
        for s in range(n):
            q = (s + 1) % n
            idx = (rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s])
            m.quad(idx[0], idx[1], idx[2], idx[3], sub(m.centroid(idx), axis), "bark")
    _roof_pad(m, rng, rings[-1], path[-1], pad_r_w, depth_w, place, roof)
    return rings


def build_tree(m, rng, spec, place, roof):
    """One tree in its local frame: trunk, four limbs, three twigs, the leader, eight pads."""
    first_v = len(m.verts)
    h_local = (roof.z(place.foot[0], place.foot[1]) - LANE_Y) / place.k
    trunk = ftp.build_trunk(m, rng, _trunk_spec(spec, TRUNK_TOP * h_local))
    base = rng.f() * 360.0
    limbs, bearings = [], []
    letter = spec["letter"]
    for i, band in enumerate(LIMB_BANDS):
        bearing = base + 90.0 * i + rng.sf() * LIMB_JITTER
        rings, bearing = _canopy_limb(m, rng, spec, trunk["rings"], band, (1, 3), bearing,
                                      rng.u(*LIMB_OUT), LIMB_R[letter], LIMB_SIDES, LIMB_SEGS,
                                      "main", place, roof, flip=True)
        limbs.append(rings)
        bearings.append(bearing)
    for i in range(TWIGS):
        side = 1.0 if rng.f() < 0.5 else -1.0
        bearing = bearings[i] + side * rng.u(*TWIG_ANGLE)
        _canopy_limb(m, rng, spec, limbs[i], 3, (1, 2), bearing, rng.u(*TWIG_OUT), TWIG_R,
                     TWIG_SIDES, TWIG_SEGS, "twig", place, roof, flip=False)
    _leader(m, rng, spec, trunk, place, roof)
    made = m.verts[first_v:]
    crown = [p for p in made[len(trunk["rings"]) * len(trunk["rings"][0]) + 1:]]
    lowest = min(p[2] for p in crown)
    assert lowest >= CROWN_MIN_Z - 1e-9, "crown reaches z=%.2f under CROWN_MIN_Z" % lowest
    return first_v, trunk


# =============================================================================
# THE CHUNK -- every tree, placed; one collider
# =============================================================================

def _append(dst, src, place):
    """src's faces into dst, its vertices through place."""
    base = len(dst.verts)
    for p in src.verts:
        dst.v(place(p))
    for f, z in zip(src.faces, src.zones):
        if f is None:
            continue
        dst.faces.append(tuple(i + base for i in f))
        dst.zones.append(z)


def tree_rows():
    return [r for r in forest_trees.LAYOUT if r[1] in TREES]


def build_geometry():
    """(canopy mesh, collider mesh, stats)."""
    roof = _Roof()
    m, c = _Mesh(), _Mesh()
    stats = {"trees": 0, "per_kind": {}}
    for idx, (section, kind, bearing, radius, aim, spin, scale) in enumerate(tree_rows()):
        assert aim == "radial", aim
        spec = ftp.spec_of(LETTER[kind])
        place = _Place(bearing, radius, spin, scale[0])
        local = _Mesh()
        rng = _Rng(SEED + spec["seed"] + 7919 * idx)
        build_tree(local, rng, spec, place, roof)
        local.compact()
        _append(m, local, place)
        _append(c, ftp.build_collider(spec).compact(), place)
        stats["trees"] += 1
        stats["per_kind"][kind] = stats["per_kind"].get(kind, 0) + 1
    return m, c, stats


def build():
    m, c, stats = build_geometry()
    albedo, emissive = ft.sheet("forest_atlas", ft.paint_atlas)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    ob = m.object(OBJECT_NAME)
    ft.unwrap(ob, m.zones)
    mdl.finish(ob, ft.atlas_material("ForestAtlas", albedo, emissive), strip_uvs=False)
    coll = c.object(COLLIDER_NAME)
    coll.hide_render = True
    zs = [v[2] for v in m.verts]
    print("MDL STATS trees=%d %s visual_tris=%d collision_tris=%d top_y=%.2f roof_y=%.1f"
          % (stats["trees"], stats["per_kind"], len(ob.data.polygons), len(coll.data.polygons),
             max(zs), fc.GALLERY_Z))
    return [ob, coll]


# =============================================================================
# THE FRAME -- a prisoner's eye on the lane, up a tree into the roof
# =============================================================================

LANE_UP_BEARING = 200.0     # the lane tree nearest this bearing is the one looked up
LANE_UP_STAND = 4.5         # metres along the lane from its foot
LANE_UP_LENS = 20.0
LANE_UP_RES = (1300, 1500)
PC_OUT = r"C:\Users\ddd\Desktop\panopticon-renders\forest-canopy-sculpt"


def post(spec, objects):
    """--views lane_up: the map grown in this scene as the backdrop, one EEVEE frame."""
    if "lane_up" not in (spec.get("views") or []):
        spec["views"] = []              # the named views frame 120 m of forest as a rifle
        return
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 64)))
    mdl._try(scene.eevee, "use_shadows", True)
    mdl._try(scene.eevee, "use_raytracing", True)
    mdl._try(scene.eevee, "shadow_ray_count", 2)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")
    mdl._try(scene.view_settings, "exposure", fb.REVIEW_EXPOSURE)

    ground = fb.build()
    for ob in ground:
        if ob.name == fb.RAYS_SOLID_NAME:
            ob.hide_render = True
    tower = ft.build_render_copy(fb.INFO["albedo"], fb.INFO["emissive"])

    world = bpy.data.worlds.new("ForestSky")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (fb.REVIEW_SKY[0], fb.REVIEW_SKY[1], fb.REVIEW_SKY[2], 1.0)
    bg.inputs[1].default_value = fb.REVIEW_WORLD * fb.REVIEW_WORLD_VARIANT["light"]
    sb, se = fb.SUN
    aim = mdl._link(bpy.data.objects.new("ReviewAim", None))
    aim.location = (0.0, 0.0, 20.0)
    lights = []
    for (nm, energy, colour, shadow, b, e) in (("ReviewSun", fb.REVIEW_SUN, (1.0, 0.96, 0.84), True, sb, se),
                                               ("ReviewFill", fb.REVIEW_FILL, (0.9, 1.0, 0.9), False, sb + 180.0, 40.0)):
        ld = bpy.data.lights.new(nm, type="SUN")
        ld.energy, ld.color = energy, colour
        mdl._try(ld, "use_shadow", shadow)
        ob = mdl._link(bpy.data.objects.new(nm, ld))
        ob.location = add(aim.location, (math.cos(math.radians(e)) * math.cos(math.radians(-b)),
                                         math.cos(math.radians(e)) * math.sin(math.radians(-b)),
                                         math.sin(math.radians(e))), 120.0)
        con = ob.constraints.new(type="TRACK_TO")
        con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"
        lights.append(ob)

    lane = [r for r in tree_rows() if r[0] == "Lane" and r[1] != "tree_c"]
    row = min(lane, key=lambda r: abs(r[2] - LANE_UP_BEARING))
    foot = pol(row[2], row[3], LANE_Y)
    t = ft.tangent(row[2])
    target = mdl._link(bpy.data.objects.new("ForestTarget", None))
    target.location = (foot[0], foot[1], fb.DECK_Z + 12.0)
    cam = mdl._link(bpy.data.objects.new("ForestCam", bpy.data.cameras.new("ForestCam")))
    cam.location = add(foot, t, LANE_UP_STAND)
    cam.location = (cam.location[0], cam.location[1], fb.DECK_Z + fb.EYE_H)
    cam.data.lens = LANE_UP_LENS
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
    scene.render.resolution_x, scene.render.resolution_y = LANE_UP_RES
    bpy.context.view_layer.update()
    out_dir = spec.get("out_dir", ".")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "%s_lane_up.png" % NAME)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("MDL RENDER %s (lane eye at bearing %.1f, up %s)" % (os.path.basename(path), row[2], row[1]))
    if os.path.isdir(os.path.dirname(PC_OUT)):
        os.makedirs(PC_OUT, exist_ok=True)
        shutil.copyfile(path, os.path.join(PC_OUT, "lane_up.png"))
        print("MDL RENDER copied to %s" % os.path.join(PC_OUT, "lane_up.png"))
    for ob in [cam, target, aim, tower] + lights + list(ground):
        bpy.data.objects.remove(ob, do_unlink=True)
    spec["views"] = []


# =============================================================================
# CHECK -- the geometry, on the Mac, no Blender
# =============================================================================

def _check():
    import forest_check
    m, c, stats = build_geometry()
    m.compact()
    c.compact()
    vis = forest_check.prove(m, NAME)
    col = forest_check.prove(c, NAME + "_collider")
    zs = [v[2] for v in m.verts]
    print("SIZE trees=%d %s top_y=%.2f roof_y=%.1f" % (stats["trees"], stats["per_kind"], max(zs), fc.GALLERY_Z))
    ok = True
    for label, cond, why in (
            ("components", vis["components"] == stats["trees"], "one shell per tree"),
            ("duplicates", vis["duplicate_positions"] == 0, "no split seam"),
            ("degenerate", vis["degenerate"] == 0, "no degenerate faces"),
            ("open_edges", vis["open_edges"] == 0, "closed volumes"),
            ("tris", vis["tris"] <= MAX_TRIS, "<= %d tris" % MAX_TRIS),
            ("coll_components", col["components"] == stats["trees"], "one collider shell per tree"),
            ("under_roof", max(zs) <= fc.GALLERY_Z + fc.GALLERY_LUMP + PAD_BURY + 0.5, "nothing through the ceiling"),
    ):
        if not cond:
            ok = False
            print("FAIL %s: %s" % (label, why))
    print("CHECK %s" % ("OK" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(_check())
    mdl.main(NAME, build, facing_yaw=FACING_YAW, post=post)
