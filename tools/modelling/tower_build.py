"""tower -- the watch chamber, carved onto Ryan's hand-modelled TowerRock body.

The body is NOT generated here. It is appended from assets/models/tower.blend
with its HellRock material and packed atlas; this script only adds the wall
band between his floor (z 0.17) and his ceiling (z 5.56) and the collider.

Nothing on the outside of the band is a circle or a level line: every ring
carries the same low-frequency radius/height wander his rock has, the columns
are irregular in width, spacing, lean and waist, their faces are faceted, and
their reveals are splayed. The INNER skin is left a true cylinder at r 7.0 --
it is the collision surface and his floor disc's own edge.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + os.sep + "lib")

import mdl  # noqa: E402

# The model hangs 37 m below its origin, so mdl's ground plane lands above the
# camera at low elevations and renders a black frame. World light replaces it.
mdl.DEFAULTS["ground"] = False
mdl.DEFAULTS["world_grey"] = 0.30
mdl.DEFAULTS["world_strength"] = 0.90

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "tower"
OBJECT_NAME = "TowerRock"
COLLIDER_NAME = "TowerCollision-colonly"
BLEND_PATH = r"C:\dev\panopticon\assets\models\tower.blend"

# ---- the band, all in Ryan's measured metres --------------------------------
FLOOR_Z    = 0.17      # his floor disc
SILL_TOP   = 1.30      # solid parapet: jump apex is 1.11, so he cannot leave
LINTEL_BOT = 4.55
CEIL_Z     = 5.56      # his ceiling underside
CEIL_TOP   = 5.60      # lintel runs 4 cm into it: no coplanar z-fight, no gap
R_IN       = 7.00      # his floor disc's edge, and the collision surface

N_SLOTS    = 9
COL_W      = (0.75, 1.15)   # column width at r 8, metres...
COL_FAT    = (1.45, 1.60)   # ...except two of them
SLOT_W     = (0.84, 1.08)   # slot width as a weight; the ring is closed on it
SLOT_THIN  = 0.68           # ...except one
TAPER      = (0.82, 0.94)   # column half-width at the lintel / at the sill
WAIST      = (0.08, 0.20)   # how much it pinches at mid height
LEAN       = 3.0            # degrees of centre drift over the column's height
SPLAY      = (0.25, 0.55)   # reveal splay: the outer mouth is this much wider
FACETS     = (2, 3)         # planes across one column's outer face
FACET_JAG  = 0.07           # how far a facet break steps in or out
FILLET     = 0.40           # radius of the flare into sill and lintel
FILLET_VAR = 0.14           # +/- per column, so no two corners are the pair
FILLET_SEG = 3
WOBBLE     = 0.06           # per-level jitter on each column edge, metres
R_JAG      = 0.25           # per-vertex outer radius wander, metres
Z_JAG      = 0.12           # sill top / lintel soffit wander, metres
FOOT_OUT   = 0.25           # the band leaves his rim PROUD, never stepped in
R_REF      = 8.00           # radius the widths above are quoted at
SEED       = 20260911

# Measured outer radius by bearing: his rim (band foot) and his cap underside
# (band head). The band's face is interpolated between them so it flows out of
# one and into the other.
RIM = [(2, 7.30), (52, 8.10), (57, 8.60), (62, 8.15), (117, 7.50), (129, 8.30),
       (139, 8.10), (187, 8.60), (192, 9.00), (196, 8.50), (310, 7.70),
       (322, 7.80)]
CAP = [(2, 7.65), (17, 8.10), (23, 8.50), (88, 8.50), (93, 9.00), (117, 7.60),
       (132, 7.20), (162, 7.80), (187, 7.50), (195, 8.30), (227, 8.50),
       (231, 8.85), (260, 7.60), (294, 8.30), (310, 7.60), (327, 8.90),
       (335, 8.30)]

# Low-frequency wander round the bearing: four harmonics, unit total weight, so
# the wall breathes over tens of degrees instead of rippling per vertex.
HARM_R = ((1, 0.83, 0.40), (2, 2.41, 0.30), (3, 5.02, 0.19), (5, 1.27, 0.11))
HARM_S = ((1, 4.11, 0.44), (2, 0.77, 0.28), (3, 3.35, 0.18), (4, 5.60, 0.10))
HARM_L = ((1, 2.06, 0.42), (2, 5.31, 0.29), (3, 1.14, 0.19), (4, 3.88, 0.10))

EYE_H = 1.65           # the guard, for the interior renders
BODY_H = 1.80

# Atlas zones as (u0, v0, u1, v1), matching the packed HellRock atlas.
ZONE_ROCK  = (0.0, 0.5, 0.5, 1.0)
ZONE_SHADE = (0.5, 0.5, 1.0, 1.0)
ZONE_CARVE = (0.5, 0.0, 1.0, 0.5)
UV_SCALE = 0.13
UV_PAD = 1.5 / 128.0

MEASURED = {}


# =============================================================================
# HELPERS
# =============================================================================

class _Rng(object):
    """Deterministic LCG so the band is byte-identical every rebuild."""

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


def _interp(table, theta):
    """Periodic linear interpolation of a (bearing_deg, radius) table."""
    d = math.degrees(theta % (2.0 * math.pi))
    n = len(table)
    for k in range(n):
        a0, r0 = table[k]
        a1, r1 = table[(k + 1) % n]
        span = (a1 - a0) % 360.0
        off = (d - a0) % 360.0
        if off <= span:
            return r0 + (r1 - r0) * (off / span if span else 0.0)
    return table[0][1]


def _noise(harm, theta, phase=0.0):
    return sum(w * math.sin(n * theta + ph + phase) for n, ph, w in harm)


def r_out(theta, z):
    """Wall face radius: his rim at the foot, his cap underside at the head,
    with his rock's own wander on top. Never steps inside his rim."""
    t = max(0.0, min(1.0, (z - FLOOR_Z) / (CEIL_Z - FLOOR_Z)))
    s = t * t * (3.0 - 2.0 * t)
    rim, cap = _interp(RIM, theta), _interp(CAP, theta)
    r = rim * (1.0 - s) + cap * s + FOOT_OUT * (1.0 - s)
    r += R_JAG * (1.0 - 0.55 * s) * _noise(HARM_R, theta, z * 0.55)
    if s < 0.35:
        r = max(r, rim + 0.02)
    return max(r, R_IN + 0.45)


def _zj_sill(theta):
    """0 .. +Z_JAG: the stone is never LOWER than the collider's sill."""
    return Z_JAG * 0.5 * (1.0 + _noise(HARM_S, theta))


def _zj_lint(theta):
    """-Z_JAG .. 0: the soffit is never HIGHER than the collider's, so no
    invisible pane ever eats a shot the player watched leave the barrel."""
    return -Z_JAG * 0.5 * (1.0 + _noise(HARM_L, theta))


def _newell(pts):
    nx = ny = nz = 0.0
    for i in range(len(pts)):
        ax, ay, az = pts[i]
        bx, by, bz = pts[(i + 1) % len(pts)]
        nx += (ay - by) * (az + bz)
        ny += (az - bz) * (ax + bx)
        nz += (ax - bx) * (ay + by)
    return (nx, ny, nz)


class _Mesh(object):
    """Vertex/face accumulator that will not let a face end up inside out.

    Every emitter states which way the finished normal MUST point and the
    winding is reversed if Newell disagrees. Godot culls backfaces and the
    guard stands INSIDE this wall, so an inverted inner skin is a hole in the
    world that every render still shows as perfect.
    """

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

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


def _rad(a, inward=False):
    w = (math.cos(a), math.sin(a), 0.0)
    return (-w[0], -w[1], 0.0) if inward else w


def _tan(a, sign):
    return (-math.sin(a) * sign, math.cos(a) * sign, 0.0)


def _pt(a, r, z):
    return (r * math.cos(a), r * math.sin(a), z)


# =============================================================================
# THE BAND
# =============================================================================

def _levels():
    """Z levels up a column: fillet, shaft, fillet. Shared by every column."""
    zs = [SILL_TOP + FILLET * k / FILLET_SEG for k in range(FILLET_SEG + 1)]
    shaft = LINTEL_BOT - FILLET - (SILL_TOP + FILLET)
    zs += [SILL_TOP + FILLET + shaft * k / 3.0 for k in (1, 2)]
    zs += [LINTEL_BOT - FILLET * k / FILLET_SEG for k in range(FILLET_SEG, -1, -1)]
    return zs


ZS = _levels()
SPAN_Z = LINTEL_BOT - SILL_TOP


def _zlev(k, a):
    """Height of level k at bearing a, carrying the sill's and soffit's wander."""
    z = ZS[k]
    u = (z - SILL_TOP) / SPAN_Z
    return z + _zj_sill(a) * (1.0 - u) + _zj_lint(a) * u


def _flare(z, f):
    """Extra half-width from the 3-segment fillets. No right angle anywhere."""
    out = 0.0
    for d in (z - SILL_TOP, LINTEL_BOT - z):
        if d < f:
            out = max(out, f - math.sqrt(max(0.0, f ** 2 - (f - d) ** 2)))
    return out


def _layout(r):
    """Nine irregular bays: two fat columns, one narrow slot, shuffled round."""
    circ = 2.0 * math.pi * R_REF
    cols = [COL_W[0] + (COL_W[1] - COL_W[0]) * r.f() for _ in range(N_SLOTS)]
    fat = set()
    while len(fat) < 2:
        fat.add(r.i(0, N_SLOTS - 1))
    for i in fat:
        cols[i] = COL_FAT[0] + (COL_FAT[1] - COL_FAT[0]) * r.f()
    w = [SLOT_W[0] + (SLOT_W[1] - SLOT_W[0]) * r.f() for _ in range(N_SLOTS)]
    thin = r.i(0, N_SLOTS - 1)
    w[thin] = SLOT_THIN
    share = (circ - sum(cols)) / sum(w)
    slots = [wi * share for wi in w]

    order = list(range(N_SLOTS))
    for i in range(N_SLOTS - 1, 0, -1):
        j = r.i(0, i)
        order[i], order[j] = order[j], order[i]

    bays, a = [], 0.0
    for i in order:
        nf = r.i(*FACETS)
        bays.append({
            "ac": a + 0.5 * (cols[i] + slots[i]) / R_REF,
            "half": 0.5 * cols[i] / R_REF,
            "taper": TAPER[0] + (TAPER[1] - TAPER[0]) * r.f(),
            "waist": WAIST[0] + (WAIST[1] - WAIST[0]) * r.f(),
            "lean": math.radians(LEAN) * r.sf(),
            "fil": FILLET + FILLET_VAR * r.sf(),
            "dr": 0.09 * r.sf(),
            "splay": [SPLAY[0] + (SPLAY[1] - SPLAY[0]) * r.f() for _ in range(2)],
            "nf": nf,
            "fo": [0.0] + [FACET_JAG * r.sf() for _ in range(nf - 1)] + [0.0],
            "wob": [[WOBBLE * r.sf() for _ in ZS] for _ in range(2)],
            "col_m": cols[i],
            "slot_m": slots[i],
        })
        a += (cols[i] + slots[i]) / R_REF
    return bays


def _jamb(bay, side, k):
    """(inner, outer) bearing of one jamb at level k. The reveal is splayed:
    the outer mouth is wider than the inner, so no reveal is square to the
    wall. side -1 = left, +1 = right."""
    z = ZS[k]
    u = (z - SILL_TOP) / SPAN_Z
    shaft = bay["half"] * (1.0 + (bay["taper"] - 1.0) * u)
    shaft *= 1.0 - bay["waist"] * math.sin(math.pi * u)
    fl = _flare(z, bay["fil"])
    wob = bay["wob"][(side + 1) // 2][k] * (1.0 - fl / bay["fil"])
    hw = shaft + (fl + wob) / R_REF
    mid = bay["ac"] + bay["lean"] * (u - 0.5)
    return (mid + side * hw, mid + side * (hw - shaft * bay["splay"][(side + 1) // 2]))


def _band(bays, r):
    m = _Mesh()

    # ---- the columns --------------------------------------------------------
    for bay in bays:
        rows = []
        for k in range(len(ZS)):
            aiL, aoL = _jamb(bay, -1, k)
            aiR, aoR = _jamb(bay, 1, k)
            inner = [m.v(_pt(a, R_IN, _zlev(k, a))) for a in (aiL, aiR)]
            # The facet break and the column's own radial offset fade OUT at
            # the fillets, so the foot and head of every column sit exactly on
            # the course's face: no step, no hairline shadow, no ledge.
            g = 1.0 - _flare(ZS[k], bay["fil"]) / bay["fil"]
            outer = []
            for j in range(bay["nf"] + 1):
                a = aoL + (aoR - aoL) * j / float(bay["nf"])
                ro = r_out(a, ZS[k]) + (bay["dr"] + bay["fo"][j]) * g
                outer.append(m.v(_pt(a, ro, _zlev(k, a))))
            rows.append((inner, outer, aiL, aiR, aoL, aoR))
        for k in range(len(ZS) - 1):
            i0, o0, aiL0, aiR0, aoL0, aoR0 = rows[k]
            i1, o1, aiL1, aiR1, aoL1, aoR1 = rows[k + 1]
            mid = 0.5 * (aiL0 + aiR0)
            m.quad(i0[0], i0[1], i1[1], i1[0], _rad(mid, inward=True), ZONE_SHADE)
            for j in range(bay["nf"]):
                fa = 0.5 * (aoL0 + aoR0)
                m.quad(o0[j], o0[j + 1], o1[j + 1], o1[j], _rad(fa), ZONE_ROCK)
            m.quad(i0[0], o0[0], o1[0], i1[0], _tan(aiL0, -1), ZONE_CARVE)
            m.quad(i0[1], o0[-1], o1[-1], i1[1], _tan(aiR0, 1), ZONE_CARVE)

    # ---- angle rings: one off the column feet, one off the column heads ------
    def ring(k):
        """[(inner bearing, outer bearing)] round the circle, column edges
        first so the shelves land exactly on the column footprints."""
        out = []
        for i, bay in enumerate(bays):
            aiL, aoL = _jamb(bay, -1, k)
            aiR, aoR = _jamb(bay, 1, k)
            out.append((aiL, aoL))
            out.append((aiR, aoR))
            nxt = _jamb(bays[(i + 1) % N_SLOTS], -1, k)[0]
            span = (nxt - aiR) % (2.0 * math.pi)
            for s in (1, 2):
                a = aiR + span * s / 3.0
                out.append((a, a))
        return out

    def course(angs, z0, zk, sign, zone_top):
        """One solid course: inner skin, outer skin, and its exposed shelf."""
        n = len(angs)
        lo, hi = [], []
        for ai, ao in angs:
            zt = _zlev(zk, ai)
            lo.append((m.v(_pt(ai, R_IN, z0)), m.v(_pt(ao, r_out(ao, z0), z0))))
            hi.append((m.v(_pt(ai, R_IN, zt)),
                       m.v(_pt(ao, r_out(ao, ZS[zk]), _zlev(zk, ao)))))
        for p in range(n):
            q = (p + 1) % n
            mid = angs[p][0] + 0.5 * ((angs[q][0] - angs[p][0]) % (2.0 * math.pi))
            m.quad(lo[p][0], lo[q][0], hi[q][0], hi[p][0],
                   _rad(mid, inward=True), ZONE_SHADE)
            m.quad(lo[p][1], lo[q][1], hi[q][1], hi[p][1], _rad(mid), ZONE_ROCK)
            if p % 4 == 0:
                continue                      # under a column: nothing exposed
            m.quad(hi[p][0], hi[q][0], hi[q][1], hi[p][1],
                   (0.0, 0.0, float(sign)), zone_top)

    foot = ring(0)
    course(foot, FLOOR_Z, 0, 1, ZONE_CARVE)
    course(ring(len(ZS) - 1), CEIL_TOP, len(ZS) - 1, -1, ZONE_SHADE)
    MEASURED["foot_angles"] = [a for a, _ in foot]
    return m


def _ceiling(m, r):
    """Only built when his cap has no floor over the room. Faces DOWN."""
    n = 16
    hub = m.v((0.0, 0.0, CEIL_Z + 0.09))
    rim = [m.v(_pt(2.0 * math.pi * i / n, R_IN, CEIL_Z + r.f() * 0.04))
           for i in range(n)]
    for i in range(n):
        m.tri(hub, rim[i], rim[(i + 1) % n], (0.0, 0.0, -1.0), ZONE_SHADE)


# =============================================================================
# COLLIDER
# =============================================================================

def _collider(bays, angs):
    """Flat surfaces that agree with what the eye sees and have none of the
    noise: floor disc, the sill all round, one quad per column, lintel soffit.
    NOTHING over the slots, so a shot and a sightline both leave cleanly."""
    c = _Mesh()
    n = len(angs)
    floor = [c.v(_pt(a, R_IN, FLOOR_Z)) for a in angs]
    for i in range(1, n - 1):
        c.tri(floor[0], floor[i], floor[i + 1], (0.0, 0.0, 1.0), ZONE_SHADE)
    sill = [c.v(_pt(a, R_IN, SILL_TOP)) for a in angs]
    for p in range(n):
        q = (p + 1) % n
        mid = angs[p] + 0.5 * ((angs[q] - angs[p]) % (2.0 * math.pi))
        c.quad(floor[p], floor[q], sill[q], sill[p], _rad(mid, inward=True),
               ZONE_SHADE)
    for bay in bays:
        a0, a1 = _jamb(bay, -1, 0)[0], _jamb(bay, 1, 0)[0]
        lo = [c.v(_pt(a, R_IN, SILL_TOP)) for a in (a0, a1)]
        hi = [c.v(_pt(a, R_IN, CEIL_Z)) for a in (a0, a1)]
        c.quad(lo[0], lo[1], hi[1], hi[0], _rad(0.5 * (a0 + a1), inward=True),
               ZONE_SHADE)
    last = len(ZS) - 1
    for i, bay in enumerate(bays):
        a0 = _jamb(bay, 1, last)[0]
        a1 = _jamb(bays[(i + 1) % N_SLOTS], -1, last)[0]
        span = (a1 - a0) % (2.0 * math.pi)
        pts = [(c.v(_pt(a, R_IN, LINTEL_BOT)),
                c.v(_pt(a, r_out(a, LINTEL_BOT), LINTEL_BOT)))
               for a in (a0, a0 + span)]
        c.quad(pts[0][0], pts[1][0], pts[1][1], pts[0][1], (0.0, 0.0, -1.0),
               ZONE_SHADE)
    return c


# =============================================================================
# UV -- per-face planar projection into that face's zone of the packed atlas
# =============================================================================

def unwrap(ob, zones, name):
    me = ob.data
    uvl = me.uv_layers.new(name=name)
    r = _Rng(SEED + len(me.polygons))
    for pi, poly in enumerate(me.polygons):
        u0, v0, u1, v1 = zones[pi]
        span_u, span_v = (u1 - u0) - 2.0 * UV_PAD, (v1 - v0) - 2.0 * UV_PAD
        nrm = poly.normal
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        ii, jj = ((1, 2), (0, 2), (0, 1))[ax]
        fu = -1.0 if r.i(0, 1) else 1.0
        fv = -1.0 if r.i(0, 1) else 1.0
        cos = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        mi, mj = min(c[ii] for c in cos), min(c[jj] for c in cos)
        w = min((max(c[ii] for c in cos) - mi) * UV_SCALE, 1.0)
        h = min((max(c[jj] for c in cos) - mj) * UV_SCALE, 1.0)
        ou, ov = r.f() * (1.0 - w), r.f() * (1.0 - h)
        for li, co in zip(poly.loop_indices, cos):
            s = min(ou + (co[ii] - mi) * UV_SCALE, 1.0)
            t = min(ov + (co[jj] - mj) * UV_SCALE, 1.0)
            if fu < 0.0:
                s = 1.0 - s
            if fv < 0.0:
                t = 1.0 - t
            uvl.data[li].uv = (u0 + UV_PAD + s * span_u, v0 + UV_PAD + t * span_v)


# =============================================================================
# HIS BODY
# =============================================================================

def _append_rock():
    with bpy.data.libraries.load(BLEND_PATH, link=False) as (src, dst):
        names = [n for n in src.objects if n == OBJECT_NAME]
        if not names:
            raise SystemExit("MDL ERROR: %s has no object %r (has %s)"
                             % (BLEND_PATH, OBJECT_NAME, list(src.objects)))
        dst.objects = names
    ob = dst.objects[0]
    bpy.context.collection.objects.link(ob)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mat = ob.data.materials[0] if ob.data.materials else None
    if mat is None:
        raise SystemExit("MDL ERROR: %s carries no material" % OBJECT_NAME)
    imgs = []
    if mat.use_nodes:
        for nd in mat.node_tree.nodes:
            if nd.type == "TEX_IMAGE" and nd.image:
                if not nd.image.packed_file:
                    nd.image.pack()
                imgs.append("%s %dx%d" % (nd.image.name, nd.image.size[0],
                                          nd.image.size[1]))
    uvname = ob.data.uv_layers[0].name if ob.data.uv_layers else "UVMap"
    ob.data.calc_loop_triangles()
    zs = [v.co.z for v in ob.data.vertices]
    hub = min([math.hypot(v.co.x, v.co.y) for v in ob.data.vertices if v.co.z > 5.0]
              or [999.0])
    print("MDL BODY %s verts=%d tris=%d z=%.2f..%.2f mat=%s uv=%s tex=[%s]"
          % (ob.name, len(ob.data.vertices), len(ob.data.loop_triangles),
             min(zs), max(zs), mat.name, uvname, ", ".join(imgs)))
    print("MDL BODY min_radius_above_z5=%.2f -> %s"
          % (hub, "CEILING PRESENT" if hub < 2.0 else "OPEN: adding a ceiling disc"))
    return ob, mat, uvname, hub < 2.0


# =============================================================================
# EXTRA RENDERS -- the facade at deck height, and the room from inside
# =============================================================================

OPEN_BEARING = 0.0


def _extra_renders(spec, objects):
    scene = bpy.context.scene
    if spec.get("engine", "eevee").lower() == "cycles":
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = int(spec.get("samples", 24))
        scene.cycles.use_denoising = True
    else:
        scene.render.engine = "BLENDER_EEVEE"
        mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 64)))
        mdl._try(scene.eevee, "use_shadows", True)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")

    world = bpy.data.worlds.new("Hell")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.32, 0.09, 0.07, 1.0)
    bg.inputs[1].default_value = 0.55
    ld = bpy.data.lights.new("KeyRed", type="SUN")
    ld.energy = 3.6
    ld.color = (1.0, 0.36, 0.28)
    key = mdl._link(bpy.data.objects.new("KeyRed", ld))
    key.rotation_euler = (math.radians(-62.0), 0.0, math.radians(35.0))

    target = mdl._link(bpy.data.objects.new("InTarget", None))
    cam = mdl._link(bpy.data.objects.new("InCam", bpy.data.cameras.new("InCam")))
    scene.camera = cam
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"

    ux, uy = math.cos(OPEN_BEARING), math.sin(OPEN_BEARING)
    out_dir = spec.get("out_dir", ".")

    def shot(nm, loc, tgt, lens, res):
        cam.data.lens = lens
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, nm))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    shot("facade", (ux * 25.0, uy * 25.0, 3.4), (0.0, 0.0, 2.9), 42.0, (1300, 950))

    fl = bpy.data.lights.new("RoomFill", type="POINT")
    fl.energy = 900.0
    fl.color = (1.0, 0.55, 0.40)
    lamp = mdl._link(bpy.data.objects.new("RoomFill", fl))
    lamp.location = (-ux * 1.8, -uy * 1.8, 2.6)
    shot("room", (-ux * 4.6, -uy * 4.6, EYE_H + 0.3), (ux * 24.0, uy * 24.0, 1.4),
         18.0, (1100, 820))
    bpy.data.objects.remove(lamp, do_unlink=True)

    shot("gunport", (ux * (R_IN - 0.5), uy * (R_IN - 0.5), EYE_H),
         (ux * 34.0, uy * 34.0, -14.0), 26.0, (1100, 820))

    for ob in (cam, target, key):
        bpy.data.objects.remove(ob, do_unlink=True)


# =============================================================================
# BUILD
# =============================================================================

def build():
    global OPEN_BEARING
    rock, mat, uvname, has_ceiling = _append_rock()

    r = _Rng(SEED)
    bays = _layout(r)
    m = _band(bays, r)
    if not has_ceiling:
        _ceiling(m, r)
    a0 = _jamb(bays[0], 1, 0)[0]
    OPEN_BEARING = a0 + 0.5 * ((_jamb(bays[1], -1, 0)[0] - a0) % (2.0 * math.pi))

    band = m.object("band")
    unwrap(band, m.zones, uvname)
    ob = mdl.join([rock, band], OBJECT_NAME)
    mdl.finish(ob, mat, flat=True, strip_uvs=False)

    coll_ob = _collider(bays, MEASURED["foot_angles"]).object(COLLIDER_NAME)
    coll_ob.hide_render = True

    cw = [b["col_m"] for b in bays]
    sw = [b["slot_m"] for b in bays]
    ob.data.calc_loop_triangles()
    coll_ob.data.calc_loop_triangles()
    print("MDL STATS visual_tris=%d collision_tris=%d"
          % (len(ob.data.loop_triangles), len(coll_ob.data.loop_triangles)))
    print("MDL STATS slots=%d slot_arc_r8=%.2f..%.2f column_w=%.2f..%.2f ratio=1:%.1f..1:%.1f"
          % (N_SLOTS, min(sw), max(sw), min(cw), max(cw),
             min(s / c for s, c in zip(sw, cw)), max(s / c for s, c in zip(sw, cw))))
    print("MDL STATS sill=%.2f..%.2f slot=%.2f..%.2f lintel=%.2f..%.2f headroom=%.2f"
          % (FLOOR_Z, SILL_TOP, SILL_TOP, LINTEL_BOT, LINTEL_BOT, CEIL_Z,
             CEIL_Z - BODY_H))
    rs = [r_out(math.radians(d), 3.0) for d in range(0, 360, 3)]
    print("MDL STATS outer_r=%.2f..%.2f jag_r=%.2f jag_z=%.2f lean=%.1fdeg facets=%d-%d"
          % (min(rs), max(rs), R_JAG, Z_JAG, LEAN, FACETS[0], FACETS[1]))
    stand = R_IN - 0.40
    down = math.degrees(math.atan2(EYE_H - SILL_TOP, _interp(RIM, 0.0) - stand))
    print("MDL STATS sill_above_floor=%.2f eye=%.2f sightline_down=%.1fdeg uv_layers=%d"
          % (SILL_TOP - FLOOR_Z, EYE_H, down, len(ob.data.uv_layers)))
    return [ob, coll_ob]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=0.0, post=_extra_renders)
