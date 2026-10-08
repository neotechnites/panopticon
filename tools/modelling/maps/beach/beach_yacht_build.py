"""
PANOPTICON -- beach_yacht: Map 5's anchored flybridge motor yacht (the photo's Prestige 680, generic), the guard's tower.
Origin = the guard's standing point on the flybridge, dropped to the waterline; bow toward +X.

    tools/modelling/model build beach_yacht --preview
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

import forest_tree_build as ft  # noqa: E402  the face accumulator
import texel as tx  # noqa: E402

if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["ground"] = False          # it floats: z 0 is the water

# =============================================================================
# TUNABLES  (Blender local, z up, metres; z 0 = the water surface)
# =============================================================================

NAME = "beach_yacht"
OBJECT_NAME = "BeachYacht"
COLLIDER_NAME = "BeachYachtCollision-colonly"
FACING_YAW = 90.0

# the hull: rows run transom -> stem; t 0 at the transom, 1 on the stem line
TRANSOM_X = -7.60                     # the hull's transom; the bathing platform runs on to -8.8
BOW_X = 12.20
HALF_BEAM = 2.65
STEM = ((-1.5, 7.0), (-0.6, 9.3), (0.0, 10.4), (1.0, 11.4), (2.2, BOW_X))   # (z, x): the raked stem
BEAM = ((0.0, 0.94), (0.3, 1.0), (0.6, 1.0), (0.8, 0.84), (0.92, 0.52), (1.0, 0.0))  # t -> beam fraction
# (name, beam fraction, z at the transom, z at the bow, entry sharpness): keel first, sheer last
ROWS = (
    ("keel", 0.00, -0.90, -1.50, 1.0),
    ("chine", 0.90, -0.45, -0.45, 1.7),
    ("wl", 1.00, 0.08, 0.08, 1.4),
    ("stripe", 1.00, 0.18, 0.18, 1.3),
    ("winlo", 1.00, 0.80, 1.05, 1.1),
    ("winhi", 1.00, 1.15, 1.55, 1.0),
    ("sheer", 0.98, 1.70, 2.20, 0.9),
)
STATIONS = (0.0, 0.08, 0.217, 0.36, 0.508, 0.561, 0.70, 0.80, 0.868, 0.93, 0.97, 1.0)
HULL_WINDOWS = ((0.217, 0.508), (0.561, 0.868))     # t spans of the dark hull-window strips
TEAK_AFT_X = -5.9                                   # deck faces aft of this are teak

PLATFORM = (-8.80, -7.55, 2.30, -0.25, 0.45)        # x0, x1, half y, z0, top: the bathing platform

# the saloon: XZ profile, extruded across y
SALOON_HALF_Y = 2.40
SALOON = ((-6.0, 1.6), (5.0, 1.6), (5.0, 2.45), (2.2, 4.30), (-6.0, 4.30))
SALOON_GLASS = ((-5.6, 2.50), (4.90, 2.50), (2.62, 4.05), (-5.6, 4.05))   # the side window band
GLASS_PROUD = 0.03

# the flybridge
FLOOR_Z = 4.45                      # the guard's floor, exact
RAIL_TUBES = (0.45, 0.90)           # open rail: tube centres above FLOOR_Z, nothing solid round the edge
ROOF = (-6.6, 3.2, 2.50, 4.25)      # x0, x1, half y, underside z (top is FLOOR_Z)
RAIL_PATH = ((3.1, -1.5), (3.1, 1.5), (2.3, 2.42), (-6.5, 2.42), (-6.5, -2.42), (2.3, -2.42))
TUBE = 0.04
STANCHION = 0.05
SCREEN_Z = FLOOR_Z + 0.60           # the low forward windscreen's top
SCREEN_T = 0.03
SILL_Z = FLOOR_Z + 0.65             # the collider's rail wall top: the towers' sill height
POSTS = ((0.9, 1.70), (0.9, -1.70), (2.9, 1.45), (2.9, -1.45))   # the helm only: none aft of x 0.8
POST_W = 0.10
HARDTOP = (0.8, 3.6, 1.80, 7.35, 7.45)    # x0, x1, half y, underside, top
RADOME = (2.2, 0.32, 0.30, 0.25)         # x, radius, drum height, cone height
TOP_LIMIT = 8.5

COL_STATIONS = (0.0, 0.4, 0.75, 0.9, 1.0)
COL_ROWS = ("keel", "chine", "sheer")
COL_WALL_T = 0.10

SHEETS = {
    "hull": tx.Sheet("hull", mode="box", stem="beach_hull", roughness=0.45),
    "glass": tx.Sheet("glass", mode="box", stem="beach_glass", roughness=0.15),
    "teak": tx.Sheet("teak", mode="box", stem="beach_teak"),
    "stripe": tx.Sheet("stripe", mode="box", stem="beach_hull", tint=(0.55, 0.03, 0.04)),
}

UP = (0.0, 0.0, 1.0)
DOWN = (0.0, 0.0, -1.0)

# =============================================================================
# HELPERS
# =============================================================================


def _interp(table, k):
    for (a, va), (b, vb) in zip(table, table[1:]):
        if k <= b:
            f = 0.0 if b == a else (k - a) / (b - a)
            return va + (vb - va) * max(0.0, f)
    return table[-1][1]


def _smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def _face(m, ids, want, zone):
    """A quad, or the triangle left when a pair collapses on the stem."""
    out = []
    for i in ids:
        if i not in out:
            out.append(i)
    if len(out) == 4:
        m.quad(out[0], out[1], out[2], out[3], want, zone)
    elif len(out) == 3:
        m.tri(out[0], out[1], out[2], want, zone)


def _prism(m, loop_a, loop_b, zone, cap_a=None, cap_b=None):
    """Two parallel convex loops (vertex ids) bridged, both ends capped."""
    n = len(loop_a)
    ca, cb = m.centroid(loop_a), m.centroid(loop_b)
    mid = ft.lerp(ca, cb, 0.5)
    for s in range(n):
        q = (s + 1) % n
        ids = (loop_a[s], loop_a[q], loop_b[q], loop_b[s])
        z = zone(s) if callable(zone) else zone
        m.quad(ids[0], ids[1], ids[2], ids[3], ft.sub(m.centroid(ids), mid), z)
    m.fan(loop_a, ft.sub(ca, cb), cap_a or (zone if not callable(zone) else "hull"))
    m.fan(loop_b, ft.sub(cb, ca), cap_b or (zone if not callable(zone) else "hull"))


def _box(m, x0, x1, y0, y1, z0, z1, zone="hull", top=None):
    lo = [m.v((x0, y0, z0)), m.v((x1, y0, z0)), m.v((x1, y1, z0)), m.v((x0, y1, z0))]
    hi = [m.v((x0, y0, z1)), m.v((x1, y0, z1)), m.v((x1, y1, z1)), m.v((x0, y1, z1))]
    _prism(m, lo, hi, zone, cap_a=zone, cap_b=top or zone)


def _seg_box(m, p0, p1, half_t, z0, z1, zone):
    """A wall along one plan segment, half_t either side of it."""
    d = ft.norm((p1[0] - p0[0], p1[1] - p0[1], 0.0))
    nx, ny = -d[1] * half_t, d[0] * half_t
    pts = ((p0[0] + nx, p0[1] + ny), (p1[0] + nx, p1[1] + ny), (p1[0] - nx, p1[1] - ny), (p0[0] - nx, p0[1] - ny))
    lo = [m.v((x, y, z0)) for (x, y) in pts]
    hi = [m.v((x, y, z1)) for (x, y) in pts]
    _prism(m, lo, hi, zone)


def _offset(path, d):
    """A closed convex plan path moved outward by d (mitred corners)."""
    n = len(path)
    cx = sum(p[0] for p in path) / n
    cy = sum(p[1] for p in path) / n
    out = []
    for i in range(n):
        a, b, c = path[i - 1], path[i], path[(i + 1) % n]
        n1 = _out_normal(a, b, cx, cy)
        n2 = _out_normal(b, c, cx, cy)
        bx, by = n1[0] + n2[0], n1[1] + n2[1]
        k = d / max(0.2, (bx * n1[0] + by * n1[1]))
        out.append((b[0] + bx * k, b[1] + by * k))
    return out


def _out_normal(a, b, cx, cy):
    dx, dy = b[0] - a[0], b[1] - a[1]
    ln = math.hypot(dx, dy)
    nx, ny = dy / ln, -dx / ln
    mx, my = (a[0] + b[0]) * 0.5 - cx, (a[1] + b[1]) * 0.5 - cy
    return (nx, ny) if nx * mx + ny * my > 0.0 else (-nx, -ny)


def _inward(p):
    """Unit plan vector from a rail corner toward the rail path's centre."""
    cx = sum(q[0] for q in RAIL_PATH) / len(RAIL_PATH)
    cy = sum(q[1] for q in RAIL_PATH) / len(RAIL_PATH)
    return ft.norm((cx - p[0], cy - p[1], 0.0))


def _ring_wall(m, path, half_t, z0, z1, zone):
    """A closed band wall round a convex plan path: outer, inner, top and bottom faces."""
    outer, inner = _offset(path, half_t), _offset(path, -half_t)
    n = len(path)
    rows = [[m.v((x, y, z)) for (x, y) in pl] for (pl, z) in ((outer, z0), (outer, z1), (inner, z1), (inner, z0))]
    cx = sum(p[0] for p in path) / n
    cy = sum(p[1] for p in path) / n
    for r in range(4):
        a, b = rows[r], rows[(r + 1) % 4]
        for s in range(n):
            q = (s + 1) % n
            ids = (a[s], a[q], b[q], b[s])
            c = m.centroid(ids)
            if r == 0:
                want = (c[0] - cx, c[1] - cy, 0.0)
            elif r == 1:
                want = UP
            elif r == 2:
                want = (cx - c[0], cy - c[1], 0.0)
            else:
                want = DOWN
            m.quad(ids[0], ids[1], ids[2], ids[3], want, zone)


# =============================================================================
# THE HULL
# =============================================================================

def _stem_x(z):
    return _interp(STEM, z)


def _hull_point(row, t):
    _n, yf, z_aft, z_bow, sharp = row
    z = z_aft + (z_bow - z_aft) * _smooth(t)
    x = TRANSOM_X + (_stem_x(z) - TRANSOM_X) * t
    y = HALF_BEAM * yf * (_interp(BEAM, t) ** sharp)
    return x, y, z


def _hull_rings(m, stations, rows):
    """[ring ids]: keel, starboard up to sheer, port back down; the stem ring shares both sides."""
    rings = []
    for t in stations:
        stbd = []
        for row in rows:
            x, y, z = _hull_point(row, t)
            stbd.append(m.v((x, y, z)))
        port = []
        for k, row in enumerate(rows[1:], 1):
            x, y, z = _hull_point(row, t)
            port.append(stbd[k] if (t >= 1.0 or y == 0.0) else m.v((x, -y, z)))
        rings.append(stbd + port[::-1])
    return rings


def _hull_zone(k, s, nrows, t0, t1, x_mid):
    names = [r[0] for r in ROWS]
    seg = s if s < nrows - 1 else 2 * nrows - 2 - s
    if s == nrows - 1:
        return "teak" if x_mid < TEAK_AFT_X else "hull"
    lower = names[seg]
    if lower == "wl":
        return "stripe"
    if lower == "winlo" and any(a <= t0 and t1 <= b for (a, b) in HULL_WINDOWS):
        return "glass"
    return "hull"


def _hull(m):
    rings = _hull_rings(m, STATIONS, ROWS)
    nr = len(ROWS)
    n = len(rings[0])
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for s in range(n):
            q = (s + 1) % n
            ids = (a[s], a[q], b[q], b[s])
            c = m.centroid(ids)
            if s == nr - 1:
                want = UP
            else:                                  # outboard, forward at the bow: never vertical at the stem
                want = (max(0.0, c[0] - 6.0) * 0.3, math.copysign(1.0, c[1]), (c[2] - 0.4) * 0.4)
            _face(m, ids, want, _hull_zone(k, s, nr, STATIONS[k], STATIONS[k + 1], c[0]))
    m.fan(rings[0], (-1.0, 0.0, 0.0), "hull")         # the transom
    x0, x1, hy, z0, z1 = PLATFORM
    _box(m, x0, x1, -hy, hy, z0, z1, "hull", top="teak")


# =============================================================================
# SUPERSTRUCTURE
# =============================================================================

def _saloon(m):
    s = [m.v((x, SALOON_HALF_Y, z)) for (x, z) in SALOON]
    p = [m.v((x, -SALOON_HALF_Y, z)) for (x, z) in SALOON]
    _prism(m, s, p, lambda i: "glass" if i == 2 else "hull")     # face 2 is the raked windscreen
    for sgn in (1.0, -1.0):
        y0 = sgn * (SALOON_HALF_Y - 0.01)
        y1 = sgn * (SALOON_HALF_Y + GLASS_PROUD)
        a = [m.v((x, y0, z)) for (x, z) in SALOON_GLASS]
        b = [m.v((x, y1, z)) for (x, z) in SALOON_GLASS]
        _prism(m, a, b, "glass")
    x0, x1, hy, z0 = ROOF
    _box(m, x0, x1, -hy, hy, z0, FLOOR_Z, "hull", top="teak")


def _flybridge(m):
    for h in RAIL_TUBES:
        _ring_wall(m, RAIL_PATH, TUBE * 0.5, FLOOR_Z + h - TUBE * 0.5, FLOOR_Z + h + TUBE * 0.5, "hull")
    top = FLOOR_Z + RAIL_TUBES[-1] + TUBE * 0.5
    n = len(RAIL_PATH)
    for i in range(n):
        a, b = RAIL_PATH[i], RAIL_PATH[(i + 1) % n]
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        k = max(1, int(round(ln / 1.6)))
        for j in range(k):
            px, py = ft.lerp((a[0], a[1], 0.0), (b[0], b[1], 0.0), j / float(k))[:2]
            h = STANCHION * 0.5
            _box(m, px - h, px + h, py - h, py + h, FLOOR_Z - 0.02, top - 0.01)
    for i in (5, 0, 1):                           # the forward three runs: the low windscreen
        a, b = RAIL_PATH[i], RAIL_PATH[(i + 1) % n]
        _seg_box(m, ft.add(a + (0.0,), _inward(a), 0.06)[:2], ft.add(b + (0.0,), _inward(b), 0.06)[:2],
                 SCREEN_T * 0.5, FLOOR_Z - 0.02, SCREEN_Z, "glass")
    h = POST_W * 0.5
    x0, x1, hy, zu, zt = HARDTOP
    for (px, py) in POSTS:
        _box(m, px - h, px + h, py - h, py + h, FLOOR_Z - 0.02, zu + 0.02)
    _box(m, x0, x1, -hy, hy, zu, zt)
    rx, rr, dh, ch = RADOME
    seg = 8
    lo = [m.v((rx + rr * math.cos(2 * math.pi * i / seg), rr * math.sin(2 * math.pi * i / seg), zt - 0.01))
          for i in range(seg)]
    hi = [m.v((rx + rr * math.cos(2 * math.pi * i / seg), rr * math.sin(2 * math.pi * i / seg), zt + dh))
          for i in range(seg)]
    tip = m.v((rx, 0.0, zt + dh + ch))
    for s in range(seg):
        q = (s + 1) % seg
        ids = (lo[s], lo[q], hi[q], hi[s])
        c = m.centroid(ids)
        m.quad(ids[0], ids[1], ids[2], ids[3], (c[0] - rx, c[1], 0.0), "hull")
        m.tri(hi[s], hi[q], tip, (c[0] - rx, c[1], 0.6), "hull")
    m.fan(lo, DOWN, "hull")


def build_geometry():
    m = ft._Mesh()
    _hull(m)
    _saloon(m)
    _flybridge(m)
    return m.compact()


def build_collider():
    """Hull prism, saloon block, flybridge floor slab, and a rail ring wall to the rail top."""
    c = ft._Mesh()
    rows = tuple(r for r in ROWS if r[0] in COL_ROWS)
    rings = _hull_rings(c, COL_STATIONS, rows)
    n = len(rings[0])
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for s in range(n):
            q = (s + 1) % n
            ids = (a[s], a[q], b[q], b[s])
            cc = c.centroid(ids)
            _face(c, ids, UP if s == len(rows) - 1 else (0.0, cc[1], cc[2] - 0.4), "hull")
    c.fan(rings[0], (-1.0, 0.0, 0.0), "hull")
    s = [c.v((x, SALOON_HALF_Y, z)) for (x, z) in SALOON]
    p = [c.v((x, -SALOON_HALF_Y, z)) for (x, z) in SALOON]
    _prism(c, s, p, "hull")
    x0, x1, hy, z0 = ROOF
    _box(c, x0, x1, -hy, hy, z0, FLOOR_Z)
    _ring_wall(c, RAIL_PATH, COL_WALL_T * 0.5, FLOOR_Z, SILL_Z, "hull")
    return c.compact()


# =============================================================================
# UV + MATERIALS
# =============================================================================

def build():
    m = build_geometry()
    c = build_collider()
    ob = m.object(OBJECT_NAME)
    zones = list(m.zones)
    tx.unwrap(ob, zones, SHEETS, seed=1)
    mats = tx.materials("beach", SHEETS, names={k: "BeachYacht_" + k for k in SHEETS})
    tx.finish(ob, zones, mats)
    coll = c.object(COLLIDER_NAME)
    coll.hide_render = True
    lo = [min(v[k] for v in m.verts) for k in range(3)]
    hi = [max(v[k] for v in m.verts) for k in range(3)]
    print("MDL STATS visual_tris=%d collision_tris=%d lo=%s hi=%s floor_z=%.3f sill_z=%.3f (top <= %.1f)"
          % (len(ob.data.polygons), len(coll.data.polygons), ["%.2f" % v for v in lo],
             ["%.2f" % v for v in hi], FLOOR_Z, SILL_Z, TOP_LIMIT))
    return [ob, coll]


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
