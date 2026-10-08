"""
PANOPTICON -- beach_portal: Map 4's finish line, a natural sea arch of weathered beach rock:
two leaning jambs on broad splayed feet, a rough lintel sagging over the opening.

    envelope ...... 4.5 m wide (X) x 4.0 m tall (Z) x 0.8 m deep (Y), origin base centre
    clear hole .... |x| <= 1.30 from the ground to z 2.8 (portal.glb's hole, to the cm)

One mesh: a faceted sweep round the opening (feet 0.25 m into the sand), the disc
fanned off the inner ridge.

    tools/modelling/model build beach_portal --preview
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

NAME = "beach_portal"
OBJECT_NAME = "BeachPortal"
COLLIDER_NAME = "BeachPortalCollision-colonly"
SWIRL_MAT = "BeachPortalSwirl"
SWIRL_STEM = "beach_portal_swirl_albedo"   # albedo and glow are the same pixels
SWIRL_PAD = 6.0 / 256.0
FACING_YAW = 0.0
SEED = 5530719

HALF_W = 2.25
HEIGHT = 4.0
HALF_D = 0.4
CLEAR_HALF_W = 1.30     # portal.glb's collider hole: |x| <= this ...
CLEAR_Z = 2.8           # ... clear from the ground to here. Load-bearing.
DISC_CENTRE_Z = 1.5
FOOT_Z = -0.25          # the feet run this far into the sand

# Stations, left foot round to right foot: (inner ridge x, z, outer x, z, D half
# depth). Feet splay wide, the jambs lean in, the lintel sags off-centre. Nothing mirrors.
STATIONS = (
    (-1.34, FOOT_Z, -2.25, FOOT_Z, 0.40),
    (-1.34, 0.00, -2.25, 0.00, 0.40),
    (-1.33, 0.42, -2.10, 0.50, 0.39),   # the splay closes
    (-1.32, 1.10, -1.86, 1.22, 0.37),
    (-1.31, 1.85, -1.72, 1.96, 0.35),   # the waist
    (-1.30, 2.45, -1.70, 2.62, 0.34),
    (-1.30, 2.82, -1.80, 3.22, 0.34),   # the left jamb leans over
    (-1.10, 3.06, -1.86, 3.64, 0.33),   # a shoulder overhangs the jamb
    (-0.78, 3.18, -1.30, 3.94, 0.32),
    (-0.36, 3.24, -0.52, 4.00, 0.31),   # the lintel's high crown
    (0.08, 3.14, 0.12, 3.84, 0.30),     # a sag, worn thin
    (0.52, 3.20, 0.66, 3.92, 0.31),
    (0.94, 3.10, 1.28, 3.78, 0.32),
    (1.18, 2.96, 1.80, 3.46, 0.33),
    (1.30, 2.82, 1.76, 3.04, 0.34),     # right shoulder
    (1.31, 2.20, 1.66, 2.34, 0.35),
    (1.32, 1.50, 1.78, 1.56, 0.36),
    (1.33, 0.80, 1.96, 0.74, 0.38),
    (1.34, 0.30, 2.16, 0.26, 0.39),     # the splay opens
    (1.35, 0.00, 2.25, 0.00, 0.40),
    (1.35, FOOT_Z, 2.25, FOOT_Z, 0.40),
)
WET_BANDS = (0, 1, 18, 19)   # the feet: damp, darker rock where the sand meets it

# Section from the inner ridge (rf 0) to the outer edge (rf 1), df x D. Vertex 0
# is the ridge on y = 0 (the disc's row); 1 and 6 are the soffit rails.
SECT = ((0.0, 0.0), (0.10, 0.92), (0.55, 1.0), (1.0, 0.45),
        (1.0, -0.35), (0.55, -1.0), (0.10, -0.90))
SECT_JIT_R = 0.10       # mid verts only: the outer edge is authored
SECT_JIT_D = 0.22       # inward only: the envelope holds
SECT_SKEW = 0.22        # per-station slide of the outer verts along y: facets

COL_SIDES = 4            # the collider's prism section

ROCK = "beach_rock"     # one drawing; deep and wet are it tinted darker
SHEETS = {
    "rock": tx.Sheet("rock", mode="box", stem=ROCK, cull=False),
    "deep": tx.Sheet("deep", mode="box", stem=ROCK, tint=(0.70, 0.68, 0.66), cull=False),
    "wet": tx.Sheet("wet", mode="box", stem=ROCK, tint=(0.58, 0.56, 0.54), cull=False),
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
        m.fan(self.rings[0], ft.DOWN, "wet")       # the feet, under the sand
        m.fan(self.rings[-1], ft.DOWN, "wet")

    def _zone(self, k, s, q):
        """Whole faces: the feet wet, the inner reveal deep, the rest rock."""
        if k in WET_BANDS:
            return "wet"
        if s == 0 or q == 0:
            return "deep"
        return "rock"

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
        self.disc()
        return self.m


def build_geometry():
    p = _Portal()
    m = p.build().compact()
    m.rim_xz = p.rim_xz
    return m


def build_collider():
    """The same jambs and lintel, coarsened to a four-sided prism ring on STATIONS."""
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
            c.quad(idx[0], idx[1], idx[2], idx[3], ft.sub(c.centroid(idx), ax), "rock")
    c.fan(rings[0], ft.DOWN, "rock")
    c.fan(rings[-1], ft.DOWN, "rock")
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

    def earth(me, uvl, poly):
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            s_ = min(max((co.x - lo_x) / (hi_x - lo_x), 0.0), 1.0)
            t_ = min(max((co.z - lo_z) / (hi_z - lo_z), 0.0), 1.0)
            uvl.data[li].uv = (SWIRL_PAD + s_ * span, SWIRL_PAD + t_ * span)
    return {"earth": earth}


def build():
    m = build_geometry()
    c = build_collider()
    ob = m.object(OBJECT_NAME)
    zones = list(m.zones)
    tx.unwrap(ob, zones, SHEETS, seed=1, custom=_uv_custom(m.rim_xz))
    mats = tx.materials("BeachPortal", SHEETS, names={k: "BeachPortal_" + k for k in SHEETS})
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
