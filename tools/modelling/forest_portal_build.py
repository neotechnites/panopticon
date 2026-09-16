"""
PANOPTICON -- forest_portal: Map 3's finish line, the forest's answer to map 1's
hell-rock portal.glb.

Two living trunks stand either side of the opening, flare into roots at the
foot, lean in as they climb and braid over the top into a pointed arch.
Thinner branches grow out of the trunks' faces, arch over the crown and out
onto the shoulders, and end in leaf clumps. Inside the opening hangs the
portal's own effect surface: an emissive swirl of sunlit green pulled into a
gold-white core -- portal_build.py's geometry, constants and planar unwrap,
repainted -- so the finish reads the same to a runner and the gameplay does
not move.

    envelope ...... 4.5 m wide (X) x 4.0 m tall (Z) x 0.8 m deep (Y)
    origin ........ the base centre; Blender z = 0 is the ground
    opening ....... 2.7 m wide at the ground, springing z 2.6, apex z 3.15;
                    the runner passes through along Blender Y (Godot local Z)
    clear hole .... |x| <= 1.30 from the ground to z 2.8, nothing solid in it:
                    portal.glb's collider hole, to the centimetre

One mesh (the forest atlas, its "earth" quarter repainted as the swirl), one
surface, one UV set, flat shaded. ForestPortalCollision rides as a `-colonly`
node: the same two jambs and the same arched head, coarsened -- not a box.

The disc does NOT float: the frame's inner face carries a vertex row at y = 0
and the disc is fanned from those exact ids, so the whole model is one
connected component.

    tools/modelling/model build forest_portal --views threequarter,front
    python3 tools/modelling/forest_portal_build.py --check
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
sys.path.insert(0, HERE + os.sep + "lib")
if bpy is not None:
    import mdl  # noqa: E402

import forest_tree_build as ft  # noqa: E402
import forest_build as fb  # noqa: E402

if bpy is not None:
    mdl.DEFAULTS["ground"] = True         # ft's import turns it off; a portal stands on something

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "forest_portal"
OBJECT_NAME = "ForestPortal"
COLLIDER_NAME = "ForestPortalCollision-colonly"
FACING_YAW = 0.0

HALF_W    = 2.25        # 4.5 m wide
HEIGHT    = 4.0
HALF_D    = 0.4         # 0.8 m deep
IN_HALF_W = 1.35        # the opening: 2.7 m wide at the ground
IN_SPRING = 2.6         # where the trunks start to lean over
IN_RISE   = 0.55        # opening apex = IN_SPRING + IN_RISE = 3.15
APEX_Z    = IN_SPRING + IN_RISE
DISC_CENTRE_Z = 1.5

CLEAR_HALF_W = 1.30     # portal.glb's collider hole: |x| <= this ...
CLEAR_Z      = 2.8      # ... clear from the ground to here. Load-bearing.

SIDE_N   = 5            # stations up each straight jamb, the ground one included
ARCH_N   = 6            # stations from a springing to the apex, both included
ARCH_POW = 2.2          # the arch's shape: 1 is an ellipse, higher is a steeper
                        # pointed arch. 2.2 is what keeps the soffit outside
                        # |x| = 1.30 all the way to z = 2.8, so the visual arch
                        # and the collider hole agree instead of the collider
                        # quietly being the only thing that is honest.
SIDE_JIT = 0.085        # stations wander ALONG the profile, never off it: the
ARCH_JIT = 0.030        # outline stays exact, the tessellation goes organic

ROOT_T   = 0.62         # trunk thickness at the foot: a round-ish 0.62 x 0.80 m
SPRING_T = 0.40         # section, so it reads as a trunk and not as a slab. The
CROWN_T  = 0.30         # 4.5 m of envelope is filled by branches and leaves,
                        # which is what Ryan asked the surround to be made of.
ROOT_POW = 1.6          # the root flare is concentrated at the foot
CROWN_POW = 1.3
FOOT_D   = 0.38         # half depth at the foot
SPRING_D = 0.33
CROWN_D  = 0.27
T_WOB    = 0.045        # every wobble SHRINKS: the envelope is never exceeded
D_WOB    = 0.030
RING_WOB = 0.060

# the trunk's cross section: radial factor (x T, out from the inner face) and
# depth factor (x D). Vertices 0, 1 and 7 sit ON the inner face, so the opening
# is exactly IN_HALF_W wide; vertex 0 is the y = 0 row the disc is fanned from.
SECT_R = (0.0, 0.0, 0.28, 0.74, 1.0, 0.74, 0.28, 0.0)
SECT_D = (0.0, 0.5, 1.0, 0.72, 0.0, -0.72, -1.0, -0.5)

BR_SIDES = 4            # branch tube sides (and so the leaf clump's segments)
CLUMP_SQUASH = 0.8
CLUMP_WOB = 0.10

# Branches, written in LEFT-trunk coordinates (rooted at negative x) and
# mirrored in x for the right trunk: six a side, twelve in all.
# (patch bands, segments, control, end, (r0, r1), clump centre, clump r)
# Band k lies between stations k and k+1; sides 2 and 3 face the back, 4 and 5
# the front, 6 the front inner bevel. Each root straddles the pair of faces
# either side of a ridge: a square-ish patch is what bridges without slivers.
# Sides 0, 1 and 7 are the inner face and
# are never used: nothing is allowed to hang into the opening. A quad may be
# claimed once, so every (band, side) below is distinct.
# The first two swing wide, then run past the centre: left and right braid.
BRANCHES = (
    (((4, 4), (4, 5)), 3, (-2.12, -0.24, 3.28), (0.34, -0.10, 3.50),
     (0.093, 0.060), (0.34, -0.04, 3.70), 0.30),
    (((4, 2), (4, 3)), 3, (-2.16, 0.24, 3.38), (0.40, 0.10, 3.58),
     (0.089, 0.058), (0.40, 0.04, 3.76), 0.26),
    (((3, 3), (3, 4)), 3, (-2.15, 0.02, 2.62), (-1.92, 0.00, 2.98),
     (0.099, 0.075), (-1.93, 0.00, 3.16), 0.26),
    (((2, 3), (2, 4)), 3, (-2.12, 0.10, 1.78), (-1.90, 0.06, 2.08),
     (0.093, 0.068), (-1.95, 0.04, 2.26), 0.26),
    (((1, 4), (1, 5)), 3, (-2.06, -0.18, 0.96), (-1.86, -0.10, 1.24),
     (0.083, 0.058), (-1.93, -0.06, 1.41), 0.24),
    (((0, 2), (0, 3)), 3, (-2.02, 0.20, 0.72), (-1.82, 0.12, 0.98),
     (0.078, 0.054), (-1.88, 0.08, 1.14), 0.22),
)
BR_WOB = 0.06
BR_STUB = 0.09          # a branch leaves its face square, then bends

DISC_IN_N = 11          # the effect surface's intermediate ring ...
DISC_IN_F = 0.50        # ... this far from the centre toward the rim

COL_JAMB_N = 3          # collider stations up each straight jamb
SEED = 5140973

# =============================================================================
# TEXTURE -- the forest atlas with portal_build.py's swirl painted over "earth"
# =============================================================================

SWIRL_ARMS  = 3
SWIRL_TURNS = 2.6       # how many times an arm wraps from the rim to the core
SWIRL_WIDTH = 0.42      # fraction of an arm's band that is bright


def _paint_swirl(c, r, box):
    """A spiral of sunlit yellow-green arms on deep leaf shadow, gold-white core, dark rim. Emissive."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    cx = x0 + w / 2.0
    cy = y0 + h * (DISC_CENTRE_Z / (IN_SPRING + IN_RISE))
    for y in range(y0, y1):
        for x in range(x0, x1):
            dx, dy = (x + 0.5 - cx) / (w / 2.0), (y + 0.5 - cy) / (h / 2.0)
            rad = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            band = (ang * SWIRL_ARMS / (2.0 * math.pi) + rad * SWIRL_TURNS) % 1.0
            band = min(band, 1.0 - band) * 2.0            # 0 on the arm, 1 between
            if rad < 0.14:
                col = r.pick([(250, 232, 128), (255, 246, 168)])
            elif band < SWIRL_WIDTH * (1.0 - 0.5 * rad):
                col = r.pick([(170, 180, 96), (144, 158, 84), (158, 172, 90)])
            elif band < SWIRL_WIDTH * (1.0 - 0.5 * rad) + 0.22:
                col = r.pick([(86, 106, 60), (98, 116, 68)])
            else:
                col = r.pick([(44, 58, 36), (38, 50, 31), (50, 64, 40)])
            if rad > 0.9:
                col = tuple(int(v * 0.45) for v in col)
            c.put(x, y, col, col)


def build_atlas():
    """The forest atlas, with the sun swirl replacing the earth zone.

    Returns (albedo_image, emissive_image).
    """
    c = ft._Canvas(ft.TEX_SIZE)
    r = ft._Rng(ft.TEX_SEED)
    for zone, fn in sorted(ft.PAINTERS.items()):
        fn(c, r, ft._rect_of(ft.ZONES[zone], ft.TEX_SIZE))
    _paint_swirl(c, r, ft._rect_of(ft.ZONES["earth"], ft.TEX_SIZE))
    return ft._images(c, ft.TEX_SIZE, ("forest_portal_albedo", "forest_portal_emissive"))


# =============================================================================
# UNWRAP -- forest_tree_build.unwrap, plus portal_build's whole-zone planar
# branch: zones named in ``planar`` map by (axis_i, axis_j) extent instead of
# a random window, so the swirl lands on the disc once, centred.
# =============================================================================

def unwrap(ob, zones, planar=None, seed=0):
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    r = ft._Rng(ft.TEX_SEED + seed * 7919 + len(me.polygons))
    planar = planar or {}
    for pi, poly in enumerate(me.polygons):
        zone = zones[pi]
        u0, v0, u1, v1 = ft.ZONES[zone]
        span_u = (u1 - u0) - 2.0 * ft.UV_PAD
        span_v = (v1 - v0) - 2.0 * ft.UV_PAD
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        if zone in planar:
            ii, jj, lo_i, lo_j, hi_i, hi_j = planar[zone]
            for li, co in zip(poly.loop_indices, cos):
                s = min(max((co[ii] - lo_i) / (hi_i - lo_i), 0.0), 1.0)
                t = min(max((co[jj] - lo_j) / (hi_j - lo_j), 0.0), 1.0)
                uvl.data[li].uv = (u0 + ft.UV_PAD + s * span_u, v0 + ft.UV_PAD + t * span_v)
            continue
        scale = ft.TPM / ((u1 - u0) * ft.TEX_SIZE)      # metres -> fraction of the zone, each axis its own
        scale_v = ft.TPM / ((v1 - v0) * ft.TEX_SIZE)    # (the lane's zones are wider than tall)
        nrm = poly.normal
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
        fu = -1.0 if r.i(0, 1) else 1.0
        fv = -1.0 if (ax == 2 and r.i(0, 1)) else 1.0
        mi = min(co[ii] for co in cos)
        mj = min(co[jj] for co in cos)
        w = min((max(co[ii] for co in cos) - mi) * scale, 1.0)
        h = min((max(co[jj] for co in cos) - mj) * scale_v, 1.0)
        ou = r.f() * (1.0 - w)
        ov = r.f() * (1.0 - h)
        for li, co in zip(poly.loop_indices, cos):
            s = min(ou + (co[ii] - mi) * scale, 1.0)
            t = min(ov + (co[jj] - mj) * scale_v, 1.0)
            if fu < 0.0:
                s = 1.0 - s
            if fv < 0.0:
                t = 1.0 - t
            uvl.data[li].uv = (u0 + ft.UV_PAD + s * span_u, v0 + ft.UV_PAD + t * span_v)


# =============================================================================
# THE PROFILE -- one curve, ground-left up the jamb, over the arch, down again
# =============================================================================

def _jamb(sg, z, r, wob=True):
    """A station on a straight jamb: (P, outward unit, thickness, half depth)."""
    t = z / IN_SPRING
    T = SPRING_T + (ROOT_T - SPRING_T) * (1.0 - t) ** ROOT_POW
    D = FOOT_D + (SPRING_D - FOOT_D) * t
    if wob:
        T -= r.u(0.0, T_WOB)
        D -= r.u(0.0, D_WOB)
    return ((sg * IN_HALF_W, 0.0, z), (sg, 0.0, 0.0), T, D)


def _arch(sg, s, r, wob=True):
    """A station on the arch, s = 0 at the springing, 1 at the apex."""
    phi = 0.5 * math.pi * (s ** ARCH_POW)
    T = SPRING_T + (CROWN_T - SPRING_T) * (s ** CROWN_POW)
    D = SPRING_D + (CROWN_D - SPRING_D) * s
    if wob:
        T -= r.u(0.0, T_WOB)
        D -= r.u(0.0, D_WOB)
    return ((sg * IN_HALF_W * math.cos(phi), 0.0, IN_SPRING + IN_RISE * s),
            (sg * math.cos(phi), 0.0, math.sin(phi)), T, D)


def _stations(r, side_n=SIDE_N, arch_n=ARCH_N, wob=True):
    """Ground-left, up the left jamb, over the arch, down to ground-right."""
    out = []
    for k in range(side_n):
        z = IN_SPRING * k / float(side_n)
        if k and wob:
            z += r.u(-SIDE_JIT, SIDE_JIT)
        out.append(_jamb(-1.0, z, r, wob and k > 0))
    for k in range(arch_n + 1):
        s = k / float(arch_n)
        if wob and 0 < k < arch_n:
            s = min(0.97, max(0.03, s + r.u(-ARCH_JIT, ARCH_JIT)))
        out.append(_arch(-1.0, s, r, wob))
    for k in range(arch_n - 1, -1, -1):
        s = k / float(arch_n)
        if wob and 0 < k < arch_n:
            s = min(0.97, max(0.03, s + r.u(-ARCH_JIT, ARCH_JIT)))
        out.append(_arch(1.0, s, r, wob))
    for k in range(side_n - 1, -1, -1):
        z = IN_SPRING * k / float(side_n)
        if k and wob:
            z += r.u(-SIDE_JIT, SIDE_JIT)
        out.append(_jamb(1.0, z, r, wob and k > 0))
    return out


def _axis(stn):
    """The middle of the trunk at a station: what every face's normal points away from."""
    P, u, T, _D = stn
    return (P[0] + u[0] * 0.5 * T, 0.0, P[2] + u[2] * 0.5 * T)


# =============================================================================
# THE PORTAL
# =============================================================================

class _Portal(object):
    def __init__(self, r):
        self.m = ft._Mesh()
        self.r = r
        self.st = _stations(r)
        self.rings = []
        self.bands = []

    # ---- the frame: one tube round the opening -----------------------------
    def frame(self):
        m, r = self.m, self.r
        for stn in self.st:
            P, u, T, D = stn
            ids = []
            for i in range(8):
                rf, df = SECT_R[i], SECT_D[i]
                if rf:
                    rf *= 1.0 - r.u(0.0, RING_WOB)       # inward only: the envelope holds
                if df:
                    df *= 1.0 - r.u(0.0, RING_WOB)
                ids.append(m.v((P[0] + u[0] * rf * T, df * D, P[2] + u[2] * rf * T)))
            self.rings.append(ids)
        for k in range(len(self.st) - 1):
            a, b = self.rings[k], self.rings[k + 1]
            ax = ft.lerp(_axis(self.st[k]), _axis(self.st[k + 1]), 0.5)
            row = []
            for s in range(8):
                q = (s + 1) % 8
                idx = (a[s], a[q], b[q], b[s])
                m.quad(idx[0], idx[1], idx[2], idx[3], ft.sub(m.centroid(idx), ax), "bark")
                row.append(idx)
            self.bands.append(row)
        m.fan(self.rings[0], ft.DOWN, "bark")            # the two feet, flat on the ground
        m.fan(self.rings[-1], ft.DOWN, "bark")

    # ---- the effect surface ------------------------------------------------
    def _zip_xz(self, outer, inner, c, want):
        """Angle-matched zipper in the disc's own plane (xz): ft.zipper sorts in
        xy, and every vertex here is at y = 0."""
        m = self.m

        def ang(vid):
            p = m.verts[vid]
            return math.atan2(p[2] - c[2], p[0] - c[0])

        O, I = sorted(outer, key=ang), sorted(inner, key=ang)
        aO, aI = [ang(v) for v in O], [ang(v) for v in I]
        i = j = 0
        no, ni = len(O), len(I)
        while i < no or j < ni:
            next_o = aO[i + 1] if i + 1 < no else aO[0] + 2.0 * math.pi
            next_i = aI[j + 1] if j + 1 < ni else aI[0] + 2.0 * math.pi
            oi, ii = O[i % no], I[j % ni]
            if (i < no and next_o <= next_i) or j >= ni:
                m.tri(oi, O[(i + 1) % no], ii, want, "earth")
                i += 1
            else:
                m.tri(oi, I[(j + 1) % ni], ii, want, "earth")
                j += 1

    def disc(self):
        """The opening's own outline at y = 0, filled from a centre at
        (0, 0, 1.5), both sides -- off the frame's OWN vertex row, so nothing
        floats. An intermediate ring carries the fill: a bare fan from the
        centre makes 1..3 degree slivers where the arch's stations crowd."""
        m = self.m
        rim = [ring[0] for ring in self.rings]           # section vertex 0: on the inner face, y = 0
        n = len(rim)
        c = (0.0, 0.0, DISC_CENTRE_Z)
        centre = m.v(c)
        inner = []
        for i in range(DISC_IN_N):
            p = m.verts[rim[int(round(i * n / float(DISC_IN_N))) % n]]
            inner.append(m.v((c[0] + (p[0] - c[0]) * DISC_IN_F, 0.0,
                              c[2] + (p[2] - c[2]) * DISC_IN_F)))
        for want in ((0.0, -1.0, 0.0), (0.0, 1.0, 0.0)):
            self._zip_xz(rim, inner, c, want)
            for i in range(DISC_IN_N):
                m.tri(inner[i], inner[(i + 1) % DISC_IN_N], centre, want, "earth")
        return centre

    # ---- what grows out of it ----------------------------------------------
    def branches(self):
        m, r = self.m, self.r
        nb = len(self.bands)
        for mul in (1.0, -1.0):                          # left trunk, then its mirror
            for (cells, segs, ctrl, end, radii, cc, crad) in BRANCHES:
                patch = []
                for (k, s) in cells:
                    kk = k if mul > 0.0 else (nb - 1 - k)
                    patch.append(self.bands[kk][s])
                # leave the trunk square to the face, as forest_tree's arms do
                # (ARM_STUB), THEN bend: a ring projected onto its patch along a
                # shallow tube is an ellipse, and an ellipse in a narrow quad is
                # what makes sliver bridging.
                n, _ex, _ey, ids = fb._patch_frame(m, patch)
                p0 = m.centroid(ids)
                path = [p0] + ft.bez(ft.add(p0, n, BR_STUB),
                                     (mul * ctrl[0], ctrl[1], ctrl[2]),
                                     (mul * end[0], end[1], end[2]), segs)
                rings = fb._ptube(m, path, radii, BR_SIDES, "bark",
                                  start=(patch, "bark"), caps=(True, False),
                                  wob=BR_WOB, rng=r)
                ft.clump_end(m, rings[-1], (mul * cc[0], cc[1], cc[2]), crad, "leaf", r,
                             squash=CLUMP_SQUASH, wob=CLUMP_WOB)

    def build(self):
        self.frame()
        self.disc()
        self.branches()
        return self.m


def build_geometry():
    p = _Portal(ft._Rng(SEED))
    return ft._prune(p.build().compact())


def build_collider():
    """The same two jambs and the same arched head, coarsened: a four-sided
    prism ring on the ideal profile. Its inner face is the visual's inner face
    to the millimetre, so the hole the runner goes through is the hole they see.
    """
    c = ft._Mesh()
    r = ft._Rng(SEED)                                   # unused: the collider takes no wobble
    st = _stations(r, side_n=COL_JAMB_N, arch_n=ARCH_N, wob=False)
    rings = []
    for (P, u, T, D) in st:
        rings.append([c.v((P[0], -D, P[2])), c.v((P[0], D, P[2])),
                      c.v((P[0] + u[0] * T, D, P[2] + u[2] * T)),
                      c.v((P[0] + u[0] * T, -D, P[2] + u[2] * T))])
    for k in range(len(st) - 1):
        a, b = rings[k], rings[k + 1]
        ax = ft.lerp(_axis(st[k]), _axis(st[k + 1]), 0.5)
        for s in range(4):
            q = (s + 1) % 4
            idx = (a[s], a[q], b[q], b[s])
            c.quad(idx[0], idx[1], idx[2], idx[3], ft.sub(c.centroid(idx), ax), "bark")
    c.fan(rings[0], ft.DOWN, "bark")
    c.fan(rings[-1], ft.DOWN, "bark")
    return c


# =============================================================================
# REVIEW RENDERS -- the `post=` hook: a scale shot with a human proxy, then the
# fixture standing on the lane in the real forest. Runs after the .glb export,
# so everything made here is rendered but never exported; everything made here
# is hidden again at the end, so mdl's own threequarter/front views afterwards
# show the bare fixture. EEVEE only.
# =============================================================================

def _in_scene_render(spec, objects):
    if bpy is None:
        return
    scene = bpy.context.scene
    out_dir = spec.get("out_dir", ".")
    os.makedirs(out_dir, exist_ok=True)

    fixture = None
    for ob in objects:
        if ob.name == OBJECT_NAME:
            fixture = ob
        elif ob.name == COLLIDER_NAME:
            ob.hide_render = True          # the collider is never in a render
    if fixture is None:
        return
    # the fixture is still at its authored origin here: bound_box is world space
    bb = [tuple(co) for co in fixture.bound_box]
    lo = [min(co[k] for co in bb) for k in range(3)]
    hi = [max(co[k] for co in bb) for k in range(3)]

    # ---- the rig: EEVEE, fb's review world, fb's sun and fill --------------
    scene.render.engine = "BLENDER_EEVEE"
    mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 64)))
    mdl._try(scene.eevee, "use_shadows", True)
    mdl._try(scene.eevee, "use_raytracing", True)
    mdl._try(scene.eevee, "shadow_ray_count", 2)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")
    mdl._try(scene.view_settings, "exposure", fb.REVIEW_EXPOSURE)

    world = bpy.data.worlds.new("ForestPortalSky")
    scene.world = world
    world.use_nodes = True
    wnt = world.node_tree
    bg = wnt.nodes["Background"]
    bg.inputs[0].default_value = (fb.REVIEW_SKY[0], fb.REVIEW_SKY[1], fb.REVIEW_SKY[2], 1.0)
    bg.inputs[1].default_value = fb.REVIEW_WORLD
    # as fb._forest_render: what the camera sees past the geometry is pale sky
    # at REVIEW_SEEN, not the white slab the world's fill would paint.
    seen = wnt.nodes.new("ShaderNodeBackground")
    seen.inputs[0].default_value = (fb.REVIEW_SEEN[0], fb.REVIEW_SEEN[1], fb.REVIEW_SEEN[2], 1.0)
    seen.inputs[1].default_value = 1.0
    lpath = wnt.nodes.new("ShaderNodeLightPath")
    mixw = wnt.nodes.new("ShaderNodeMixShader")
    wout = wnt.nodes["World Output"]
    wnt.links.new(lpath.outputs["Is Camera Ray"], mixw.inputs["Fac"])
    wnt.links.new(bg.outputs["Background"], mixw.inputs[1])
    wnt.links.new(seen.outputs["Background"], mixw.inputs[2])
    wnt.links.new(mixw.outputs["Shader"], wout.inputs["Surface"])

    sb, se = fb.SUN
    sd = bpy.data.lights.new("ReviewSun", type="SUN")
    sd.energy, sd.color = fb.REVIEW_SUN, (1.0, 0.96, 0.84)
    mdl._try(sd, "use_shadow", True)
    mdl._try(sd, "angle", math.radians(1.5))
    sun = mdl._link(bpy.data.objects.new("ReviewSun", sd))
    aim = mdl._link(bpy.data.objects.new("ReviewAim", None))
    aim.location = (0.0, 0.0, 20.0)
    sun.location = ft.add(aim.location,
                          (math.cos(math.radians(se)) * math.cos(math.radians(-sb)),
                           math.cos(math.radians(se)) * math.sin(math.radians(-sb)),
                           math.sin(math.radians(se))), 120.0)
    con = sun.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"
    fd = bpy.data.lights.new("ReviewFill", type="SUN")
    fd.energy, fd.color = fb.REVIEW_FILL, (0.9, 1.0, 0.9)
    mdl._try(fd, "use_shadow", False)
    fill = mdl._link(bpy.data.objects.new("ReviewFill", fd))
    fill.location = ft.add(aim.location,
                           (math.cos(math.radians(40.0)) * math.cos(math.radians(-(sb + 180.0))),
                            math.cos(math.radians(40.0)) * math.sin(math.radians(-(sb + 180.0))),
                            math.sin(math.radians(40.0))), 120.0)
    con = fill.constraints.new(type="TRACK_TO")
    con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"

    target = mdl._link(bpy.data.objects.new("PortalTarget", None))
    cam = mdl._link(bpy.data.objects.new("PortalCam", bpy.data.cameras.new("PortalCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")      # never rotation_euler on a camera
    con.target, con.track_axis, con.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"

    def shot(name, loc, tgt, lens, res):
        cam.data.lens = lens
        cam.data.clip_end = 600.0
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()             # constraints have not solved yet
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    made = []           # everything built here: hidden before mdl's own views

    # ---- the scale shot: a 1.8 m human proxy beside the fixture ------------
    px = hi[0] + 0.65                               # 0.35 m clear of the fixture's end
    proxy = mdl.box("ScaleProxy", (px - 0.30, -0.15, 0.0), (px + 0.30, 0.15, 1.80))
    mdl.finish(proxy, mdl.flat_material("ProxyGreen", (0.1, 0.9, 0.2, 1.0)))
    made.append(proxy)
    # a slab of ground so the proxy and the fixture read as standing on something
    pad = mdl.box("ScaleGround", (-11.0, -11.0, -0.06), (11.0, 11.0, 0.0))
    mdl.finish(pad, mdl.flat_material("ScaleGroundGrey", (0.24, 0.26, 0.22, 1.0)))
    made.append(pad)

    cx = 0.5 * (lo[0] + px + 0.30)
    top = max(hi[2], 1.80)
    half_w = 0.5 * (px + 0.30 - lo[0]) + 0.45
    half_h = 0.5 * top + 0.40
    # 35 mm on a 36 mm sensor: tan(hfov/2) = 18/35; the frame is 4:3, so the
    # vertical half angle is 3/4 of that. Stand off past the fixture's depth.
    dist = 1.12 * max(half_w / (18.0 / 35.0), half_h / (13.5 / 35.0)) + max(hi[1] - lo[1], 0.4)
    dist = max(dist, 4.0)
    yaw = math.radians(20.0)                        # a little off square: the depth reads
    shot("scale",
         (cx - dist * math.sin(yaw), -dist * math.cos(yaw), fb.EYE_H),
         (cx, 0.0, 0.5 * top),
         35.0, (1200, 900))

    # ---- the fixture on the lane, in the real forest -----------------------
    for ob in made:                                 # the proxy is not in the in-scene shot
        ob.hide_render = True

    albedo, emissive = ft.sheet("forest_atlas", ft.paint_atlas)   # the forest's own atlas
    gm, _coll, _rays = fb.build_geometry()
    ground = gm.object(fb.OBJECT_NAME)              # fb.build()'s recipe, minus the export
    ft.unwrap(ground, gm.zones)
    mdl.finish(ground, ft.atlas_material("ForestAtlasGround", albedo, emissive), strip_uvs=False)
    made.append(ground)
    made.append(ft.build_render_copy(albedo, emissive))

    b = 345.0                                       # the fixture's bearing on the lane
    fixture.rotation_euler = (0.0, 0.0, math.radians(-b))
    fixture.location = ft.pol(b, 52.0, fb.DECK_Z)
    eye = fb.DECK_Z + fb.EYE_H                      # 1.65 m over the deck
    aim_z = fb.DECK_Z + max(1.0, min(0.55 * hi[2], 3.0))
    shot("inscene",
         ft.pol(355.0, 52.0, eye),                  # 9.1 m down the lane from the fixture
         ft.pol(b, 52.0, aim_z),
         28.0, (1400, 900))
    # ... and again from the far side. fb's stick fence stands across the whole
    # lane at FENCE_B = 350, five degrees before the finish, so every shot from
    # 8..12 m BEFORE the portal is a shot through the fence: this one looks back
    # up the lane at it instead, where the branches are not behind bars.
    shot("inscene_clear",
         ft.pol(336.0, 52.0, eye),                  # 8.2 m past the finish, looking back
         ft.pol(b, 52.0, aim_z),
         28.0, (1400, 900))
    # the effect surface close up, and the same surface from the guard's eye on
    # the tree platform: it has to read from the tower as well as from the lane.
    surf_z = fb.DECK_Z + DISC_CENTRE_Z
    shot("surface",
         ft.pol(b + 3.6, 52.0, surf_z),             # 3.3 m in front of the mouth
         ft.pol(b, 52.0, surf_z),
         35.0, (1000, 1000))
    shot("tower",
         ft.pol(b, 9.5, ft.FLOOR_Y + ft.EYE_H),     # guard's eye height, clear of the piers
         ft.pol(b, 52.0, surf_z),
         35.0, (1400, 900))

    # ---- leave the scene as mdl's own views expect to find it --------------
    for ob in made:
        ob.hide_render = True
    for ob in (cam, target, sun, aim, fill):
        bpy.data.objects.remove(ob, do_unlink=True)
    fixture.location = (0.0, 0.0, 0.0)
    fixture.rotation_euler = (0.0, 0.0, 0.0)
    mdl._try(scene.view_settings, "exposure", 0.0)  # the review exposure is ours, not mdl's
    bpy.context.view_layer.update()


# =============================================================================
# BUILD / CHECK
# =============================================================================

def build():
    m = build_geometry()
    c = build_collider()
    albedo, emissive = build_atlas()
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    ob = m.object(OBJECT_NAME)
    unwrap(ob, m.zones,
           planar={"earth": (0, 2, -IN_HALF_W, 0.0, IN_HALF_W, APEX_Z)})
    # cull=False, as portal.glb's HellRock: the exporter keeps only one of two
    # coincident disc triangles (13 of 26 in portal.glb, 45 of 90 here), so it is
    # the material's two-sidedness that makes the effect surface read from behind.
    mdl.finish(ob, ft.atlas_material("ForestPortalAtlas", albedo, emissive, cull=False),
               strip_uvs=False)
    coll = c.object(COLLIDER_NAME)     # Godot: StaticBody3D + ConcavePolygonShape3D
    coll.hide_render = True
    size = [max(v[k] for v in m.verts) - min(v[k] for v in m.verts) for k in range(3)]
    print("MDL STATS visual_tris=%d collision_tris=%d measured=%.2fx%.2fx%.2f "
          "envelope=%.2fx%.2fx%.2f opening=%.2fx%.2f clear=%.2fx%.2f"
          % (len(ob.data.polygons), len(coll.data.polygons), size[0], size[2], size[1],
             2 * HALF_W, HEIGHT, 2 * HALF_D, 2 * IN_HALF_W, APEX_Z,
             2 * CLEAR_HALF_W, CLEAR_Z))
    return [ob, coll]


def _clear_hole(mm, skip_zone=None):
    """The smallest |x| any solid surface reaches, sampled in z from the ground
    to CLEAR_Z -- edges included, so a coarse chord cannot cheat the hole."""
    worst = (1e9, 0.0)
    keep = [f for fi, f in enumerate(mm.faces)
            if f is not None and (skip_zone is None or mm.zones[fi] != skip_zone)]
    edges = set()
    for f in keep:
        for k in range(3):
            a, b = f[k], f[(k + 1) % 3]
            edges.add((a, b) if a < b else (b, a))
    steps = int(CLEAR_Z / 0.02) + 1
    for i in range(steps):
        z = CLEAR_Z * i / float(steps - 1)
        best = 1e9
        for (a, b) in edges:
            pa, pb = mm.verts[a], mm.verts[b]
            z0, z1 = pa[2], pb[2]
            if (z0 - z) * (z1 - z) > 0.0:
                continue
            t = 0.0 if abs(z1 - z0) < 1e-12 else (z - z0) / (z1 - z0)
            best = min(best, abs(pa[0] + (pb[0] - pa[0]) * t))
        if best < worst[0]:
            worst = (best, z)
    return worst


def _check():
    import forest_check
    m = build_geometry()
    c = build_collider().compact()
    forest_check.prove(m, "forest_portal")
    forest_check.components_report(m)
    for name, mm in (("portal", m), ("coll", c)):
        degen = 0
        for f in mm.faces:
            n = ft._newell([mm.verts[i] for i in f])
            if math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) < 1e-7:
                degen += 1
        zones = {}
        for z in mm.zones:
            zones[z] = zones.get(z, 0) + 1
        lo = [min(v[k] for v in mm.verts) for k in range(3)]
        hi = [max(v[k] for v in mm.verts) for k in range(3)]
        print("%s tris=%d verts=%d degenerate=%d zones=%s bbox=%s..%s size=%s"
              % (name, len(mm.faces), len(mm.verts), degen, zones,
                 ["%.2f" % x for x in lo], ["%.2f" % x for x in hi],
                 ["%.2f" % (hi[k] - lo[k]) for k in range(3)]))
    vx, vz = _clear_hole(m, skip_zone="earth")
    cx, cz = _clear_hole(c)
    print("CLEAR needed=|x|>=%.2f to z=%.2f  visual_min=%.4f (at z=%.2f)  collider_min=%.4f (at z=%.2f)  %s"
          % (CLEAR_HALF_W, CLEAR_Z, vx, vz, cx, cz,
             "OK" if min(vx, cx) >= CLEAR_HALF_W else "FAIL"))
    print("OPENING ground_width=%.2f m  apex=%.2f m  clear_gate=%.2f x %.2f m"
          % (2 * IN_HALF_W, APEX_Z, 2 * CLEAR_HALF_W, CLEAR_Z))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_in_scene_render)
