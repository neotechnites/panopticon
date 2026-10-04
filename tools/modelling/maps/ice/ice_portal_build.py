"""
PANOPTICON -- ice_portal: Map 4's finish line, an iceberg arch: two leaning shards,
the taller left one running over the opening past the peak onto the shorter's head.

    envelope ...... 4.5 m wide (X) x 4.0 m tall (Z) x 0.8 m deep (Y), origin base centre
    clear hole .... |x| <= 1.30 from the ground to z 2.8 (portal.glb's hole, to the cm)

One mesh: a faceted sweep round the opening (feet 0.25 m into the lane ice), two
icicle clusters off the gable's soffit rails, the disc fanned off the inner ridge.

    tools/modelling/model build ice_portal --preview
"""

import math
import os
import sys

try:
    import bpy
except ImportError:
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
for _root in (os.path.dirname(HERE), os.path.dirname(os.path.dirname(HERE))):
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break
if bpy is not None:
    import mdl  # noqa: E402

import forest_tree_build as ft  # noqa: E402  the face accumulator and its rng
import texel as tx  # noqa: E402
import portal_disc as pd  # noqa: E402

if bpy is not None:
    mdl.DEFAULTS["ground"] = True         # ft's import turns it off; a portal stands on something

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "ice_portal"
OBJECT_NAME = "IcePortal"
COLLIDER_NAME = "IcePortalCollision-colonly"
SWIRL_MAT = "IcePortalSwirl"
SWIRL_STEM = "ice_portal_swirl_albedo"     # albedo and glow are the same pixels
SWIRL_PAD = 6.0 / 256.0
FACING_YAW = 0.0
SEED = 4410287

HALF_W = 2.25
HEIGHT = 4.0
HALF_D = 0.4
CLEAR_HALF_W = 1.30     # portal.glb's collider hole: |x| <= this ...
CLEAR_Z = 2.8           # ... clear from the ground to here. Load-bearing.
DISC_CENTRE_Z = 1.5
FOOT_Z = -0.25          # the feet run this far into the lane ice

# Stations, left foot round to right foot: (inner ridge x, z, outer x, z, D half
# depth). The left shard runs up over the opening to the peak and past it, ending
# at a fracture step onto the shorter right shard's head. Nothing mirrors.
STATIONS = (
    (-1.36, FOOT_Z, -2.25, FOOT_Z, 0.40),
    (-1.36, 0.00, -2.25, 0.00, 0.40),
    (-1.34, 0.82, -2.08, 0.86, 0.38),
    (-1.33, 1.00, -1.90, 0.96, 0.37),   # ledge A
    (-1.32, 1.85, -1.80, 1.98, 0.35),
    (-1.31, 2.10, -1.64, 2.06, 0.34),   # ledge B
    (-1.30, 2.82, -1.58, 2.98, 0.33),   # the left shard leans over
    (-1.12, 3.06, -1.40, 3.36, 0.32),
    (-0.92, 3.24, -1.12, 3.62, 0.31),
    (-0.70, 3.38, -0.80, 3.86, 0.30),
    (-0.48, 3.46, -0.50, 4.00, 0.29),   # the gable's peak
    (-0.25, 3.43, -0.22, 3.93, 0.28),
    (-0.02, 3.36, 0.08, 3.80, 0.28),
    (0.30, 3.28, 0.46, 3.62, 0.28),     # the left shard's broken end ...
    (0.52, 3.20, 0.62, 3.38, 0.28),     # ... a step down onto the right head
    (0.74, 3.12, 0.92, 3.40, 0.29),
    (0.98, 3.00, 1.24, 3.36, 0.30),
    (1.30, 2.82, 1.62, 3.30, 0.31),     # right shoulder
    (1.31, 2.35, 1.74, 2.26, 0.33),     # ledge C
    (1.32, 2.15, 1.92, 2.18, 0.34),
    (1.33, 1.30, 2.02, 1.18, 0.36),     # ledge D
    (1.34, 1.10, 2.20, 1.10, 0.37),
    (1.35, 0.00, 2.25, 0.00, 0.39),
    (1.35, FOOT_Z, 2.25, FOOT_Z, 0.39),
)
SNOW_BANDS = (2, 4, 18)   # ledges whose up-facing faces hold a snow pocket
SNOW_NZ = 0.55
BLUE_BANDS = (6, 13)     # outer fracture planes, cut raw blue (whole faces)

# Section from the inner ridge (rf 0) to the outer edge (rf 1), df x D. Vertex 0
# is the ridge on y = 0 (the disc's row); 1 and 6 are the soffit rails.
SECT = ((0.0, 0.0), (0.10, 0.92), (0.55, 1.0), (1.0, 0.45),
        (1.0, -0.35), (0.55, -1.0), (0.10, -0.90))
SECT_JIT_R = 0.10       # mid verts only: the outer edge is authored
SECT_JIT_D = 0.18       # inward only: the envelope holds
SECT_SKEW = 0.18        # per-station slide of the outer verts along y: facets

ICICLE_BANDS = (7, 8, 9, 10, 14, 15, 16)   # two clusters under the gable
ICICLE_L = (0.20, 0.70)  # drawn length; clipped so no tip enters the clear hole
ICICLE_FLOOR = 2.83      # no tip inside |x| < CLEAR_HALF_W drops below this
COL_SIDES = 4            # the collider's prism section

SHEETS = {
    "blue": tx.Sheet("blue", mode="box", stem="ice_blue", roughness=0.4, cull=False),
    "deep": tx.Sheet("deep", mode="box", stem="ice_deep", roughness=0.4, cull=False),
    "icicle": tx.Sheet("icicle", mode="custom", stem="ice_icicle", roughness=0.4, cull=False),
    "snow": tx.Sheet("snow", mode="box", stem="ice_snow", cull=False),
}

# =============================================================================
# THE PROFILE
# =============================================================================


def _stations():
    """[(P inner ridge, O outer edge, D)], both on y = 0."""
    return [((xi, 0.0, zi), (xo, 0.0, zo), D) for (xi, zi, xo, zo, D) in STATIONS]


def _inside(p):
    """Pulled back inside the envelope: x, y and the top."""
    return (max(-HALF_W, min(HALF_W, p[0])), max(-HALF_D, min(HALF_D, p[1])), min(HEIGHT, p[2]))


def _axis(stn):
    P, O, _D = stn
    return ft.lerp(P, O, 0.5)


# =============================================================================
# THE PORTAL
# =============================================================================

class _Portal(object):
    def __init__(self):
        self.m = ft._Mesh()
        self.r = ft._Rng(SEED)
        self.st = _stations()
        self.rings = []

    def frame(self):
        m, r = self.m, self.r
        for (P, O, D) in self.st:
            skew = r.u(-SECT_SKEW, SECT_SKEW)
            ids = []
            for i, (rf, df) in enumerate(SECT):
                if i:
                    df *= 1.0 - r.u(0.0, SECT_JIT_D)
                    if rf < 1.0:
                        rf += r.u(-SECT_JIT_R, SECT_JIT_R) * rf
                    else:
                        df = max(-1.0, min(1.0, df + skew))
                p = ft.lerp(P, O, rf)
                ids.append(m.v(_inside((p[0], df * D, p[2]))))
            self.rings.append(ids)
        ns = len(SECT)
        for k in range(len(self.st) - 1):
            a, b = self.rings[k], self.rings[k + 1]
            ax = ft.lerp(_axis(self.st[k]), _axis(self.st[k + 1]), 0.5)
            for s in range(ns):
                q = (s + 1) % ns
                idx = (a[s], a[q], b[q], b[s])
                m.quad(idx[0], idx[1], idx[2], idx[3], ft.sub(m.centroid(idx), ax),
                       self._zone(k, s, q))
        m.fan(self.rings[0], ft.DOWN, "blue")      # the feet, under the lane ice
        m.fan(self.rings[-1], ft.DOWN, "blue")

    def _zone(self, k, s, q):
        """Whole faces: the inner reveal blue, named fracture bands blue, ledge tops snow."""
        if s == 0 or q == 0:
            return "deep"
        if k in BLUE_BANDS:
            return "deep"
        if k not in SNOW_BANDS:
            return "blue"

        def z(pts):
            n = ft._newell(pts)
            ln = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) or 1.0
            return "snow" if n[2] / ln > SNOW_NZ else "blue"
        return z

    def fringe(self):
        """Spikes off the soffit rails (section verts 1 and 6), in two clusters."""
        m, r = self.m, self.r
        for side, want in ((1, (0.0, 1.0, 0.0)), (6, (0.0, -1.0, 0.0))):
            for k in ICICLE_BANDS:
                a, b = self.rings[k][side], self.rings[k + 1][side]
                pa, pb = m.verts[a], m.verts[b]
                mid = ft.lerp(pa, pb, r.u(0.35, 0.65))
                tip_z = mid[2] - r.u(*ICICLE_L)
                if min(abs(pa[0]), abs(pb[0]), abs(mid[0])) < CLEAR_HALF_W + 0.02:
                    tip_z = max(tip_z, ICICLE_FLOOR)
                m.tri(a, b, m.v((mid[0], mid[1] * 0.97, tip_z)), want, "icicle")

    def disc(self):
        """portal_disc's sheet at y = 0, its rim corners the frame's own ridge row."""
        m = self.m
        corners = [ring[0] for k, ring in enumerate(self.rings) if self.st[k][0][2] >= 0.0]
        pts = pd.rim([(m.verts[i][0], m.verts[i][2]) for i in corners])
        self.rim_xz = [(x, z) for (x, z, _k) in pts]
        ids = [corners[k] if k is not None else m.v((x, 0.0, z)) for (x, z, k) in pts]
        pd.sheet(m, ids, self.rim_xz, DISC_CENTRE_Z, "earth")

    def build(self):
        self.frame()
        self.fringe()
        self.disc()
        return self.m


def build_geometry():
    p = _Portal()
    m = p.build().compact()
    m.rim_xz = p.rim_xz
    return m


def build_collider():
    """The same jambs and head, coarsened to a four-sided prism ring on STATIONS."""
    c = ft._Mesh()
    st = _stations()
    rings = []
    for (P, O, D) in st:
        rings.append([c.v((P[0], -D, P[2])), c.v((P[0], D, P[2])),
                      c.v((O[0], D, O[2])), c.v((O[0], -D, O[2]))])
    for k in range(len(st) - 1):
        a, b = rings[k], rings[k + 1]
        ax = ft.lerp(_axis(st[k]), _axis(st[k + 1]), 0.5)
        for s in range(COL_SIDES):
            q = (s + 1) % COL_SIDES
            idx = (a[s], a[q], b[q], b[s])
            c.quad(idx[0], idx[1], idx[2], idx[3], ft.sub(c.centroid(idx), ax), "blue")
    c.fan(rings[0], ft.DOWN, "blue")
    c.fan(rings[-1], ft.DOWN, "blue")
    return c


def _clear_hole(mm, skip_zone=None):
    """Smallest |x| any solid edge reaches between the ground and CLEAR_Z."""
    edges = set()
    for fi, f in enumerate(mm.faces):
        if f is None or (skip_zone and mm.zones[fi] == skip_zone):
            continue
        for k in range(3):
            a, b = f[k], f[(k + 1) % 3]
            edges.add((min(a, b), max(a, b)))
    best = 1e9
    for i in range(int(CLEAR_Z / 0.02) + 1):
        z = 0.02 * i
        for (a, b) in edges:
            pa, pb = mm.verts[a], mm.verts[b]
            if (pa[2] - z) * (pb[2] - z) > 0.0:
                continue
            t = 0.0 if abs(pb[2] - pa[2]) < 1e-12 else (z - pa[2]) / (pb[2] - pa[2])
            best = min(best, abs(pa[0] + (pb[0] - pa[0]) * t))
    return best


# =============================================================================
# UV + MATERIALS
# =============================================================================

def _uv_custom(rim_xz):
    xs = [x for x, _z in rim_xz]
    zs = [z for _x, z in rim_xz]
    lo_x, hi_x, lo_z, hi_z = min(xs), max(xs), min(zs), max(zs)
    span = 1.0 - 2.0 * SWIRL_PAD
    period = SHEETS["icicle"].metres_u

    def icicle(me, uvl, poly):
        vs = [me.vertices[me.loops[li].vertex_index] for li in poly.loop_indices]
        tip = min(vs, key=lambda v: v.co.z)
        rail_z = max(v.co.z for v in vs)
        drop = max(rail_z - tip.co.z, 1e-3) / ICICLE_L[1]
        for li, v in zip(poly.loop_indices, vs):
            vv = 1.0 if v.index != tip.index else 1.0 - 0.5 * min(drop, 1.0)
            uvl.data[li].uv = (v.co.x / period, vv)

    def earth(me, uvl, poly):
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            s_ = min(max((co.x - lo_x) / (hi_x - lo_x), 0.0), 1.0)
            t_ = min(max((co.z - lo_z) / (hi_z - lo_z), 0.0), 1.0)
            uvl.data[li].uv = (SWIRL_PAD + s_ * span, SWIRL_PAD + t_ * span)
    return {"icicle": icicle, "earth": earth}


def build():
    m = build_geometry()
    c = build_collider()
    ob = m.object(OBJECT_NAME)
    zones = list(m.zones)
    tx.unwrap(ob, zones, SHEETS, seed=1, custom=_uv_custom(m.rim_xz))
    mats = tx.materials("IcePortal", SHEETS, names={k: "IcePortal_" + k for k in SHEETS})
    swirl = tx.image(SWIRL_STEM)
    mats["earth"] = tx.material(SWIRL_MAT, swirl, swirl, 0.9, 0.0, False)
    pd.see_through(mats["earth"])
    tx.finish(ob, zones, mats)
    pd.wave_uv(ob, SWIRL_MAT, m.rim_xz)
    coll = c.object(COLLIDER_NAME)
    coll.hide_render = True
    size = [max(v[k] for v in m.verts) - min(v[k] for v in m.verts) for k in range(3)]
    lo = [min(v[k] for v in m.verts) for k in range(3)]
    hi = [max(v[k] for v in m.verts) for k in range(3)]
    print("MDL STATS visual_tris=%d collision_tris=%d size=%.2fx%.2fx%.2f lo=%s hi=%s "
          "clear_visual=%.3f clear_collider=%.3f (need >= %.2f to z %.2f)"
          % (len(ob.data.polygons), len(coll.data.polygons), size[0], size[2], size[1],
             ["%.2f" % v for v in lo], ["%.2f" % v for v in hi],
             _clear_hole(m, "earth"), _clear_hole(c.compact()), CLEAR_HALF_W, CLEAR_Z))
    return [ob, coll]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
