"""tower_arches_clean -- tower_arches.glb with the crown (sill to roof) remodelled as one clean surface.
Shaft triangles and the collider are copied byte for byte; run: blender -b --python this -- [--audit]."""

import json
import math
import os
import struct
import sys

import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import delaunay_2d_cdt

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC = os.path.join(REPO, "tower", "models", "tower_arches.glb")
OUT = os.path.join(REPO, "tower", "models", "tower_arches_clean.glb")

SEAM_Z = 0.6            # shaft triangles wholly at or below this stay exactly as built
TOP_Z = 7.40            # outer wall top, where the roof's shoulder starts
R_W = 7.0               # inner wall face
SILL = 2.352            # opening sill (collider kerb top)
SPRING = 4.57           # springing line of the heads
HEAD_R = 2.43           # head rise: crown at SPRING + HEAD_R = 7.00
CORNER = 0.25           # cove radius where the sill meets a jamb
TAN = math.tan(math.radians(10.0))   # reveal splay per side, widening outward
CEIL = 7.25             # ceiling (collider)
CEIL_WALL = 7.10        # inner wall top: the ceiling cove starts here
CEIL_IN = 6.70          # ...and lands on the ceiling here
FLOOR_COVE = 0.35       # floor-to-wall cove radius
COURSES = ((2.07, 2.35, 0.08), (4.29, 4.57, 0.08))   # sill and springing courses: bottom, top, proud
COURSE_CH = 0.08        # their carved chamfer, top and bottom
KEY = (0.42, 6.74, 7.18, 0.20, 0.10)   # keystone: half width, bottom, top, proud, chamfer
CHISEL = ((1.30, 0.07, 11), (0.55, 0.035, 23))   # wobble octaves: cell metres, amplitude, seed
BLEND = 1.6             # metres over which the shaft's own surface hands over to the crown's
R_REF = 7.7             # unwrap radius for the outer wall's 2D domain
DMIN = 0.20             # lattice points closer than this to a constraint are dropped
UV_M = 12.8             # metres per tile repeat
ROWS = 0.50             # lattice row pitch: coarse, so the stone reads as dressed facets
APEX_Z = 10.17

TAU = 2.0 * math.pi


# ---------------------------------------------------------------- glb in/out

def read_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack_from("<I", d, 12)[0]
    j = json.loads(d[20:20 + jl])
    b = d[20 + jl + 8:]
    return j, b


def accessor(j, b, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
    f = {5126: "f", 5123: "H", 5125: "I"}[a["componentType"]]
    o = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    arr = struct.unpack_from("<%d%s" % (a["count"] * n, f), b, o)
    return [tuple(arr[k * n:(k + 1) * n]) for k in range(a["count"])] if n > 1 else list(arr)


def g2b(p):
    return (p[0], -p[2], p[1])


def b2g(p):
    return (p[0], p[2], -p[1])


# ---------------------------------------------------------------- helpers

def fourier_fit(th, r, order=4):
    th, r = np.array(th), np.array(r)
    cols = [np.ones_like(th)]
    for k in range(1, order + 1):
        cols += [np.cos(k * th), np.sin(k * th)]
    c = np.linalg.lstsq(np.stack(cols, 1), r, rcond=None)[0]

    def f(t):
        v = c[0]
        for k in range(1, order + 1):
            v += c[2 * k - 1] * math.cos(k * t) + c[2 * k] * math.sin(k * t)
        return float(v)
    return f


def _hash(i, j, s):
    h = (i * 374761393 + j * 668265263 + s * 2246822519) & 0xffffffff
    h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
    return ((h ^ (h >> 16)) & 0xffff) / 32767.5 - 1.0


def vnoise(u, v, cell, seed, wrap):
    """Smooth value noise in metres; u wraps every `wrap` metres (the ring)."""
    n = max(1, int(round(wrap / cell)))
    x, y = u / (wrap / n), v / cell
    i, j = math.floor(x), math.floor(y)
    fx, fy = x - i, y - j
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = _hash(i % n, j, seed) + (_hash((i + 1) % n, j, seed) - _hash(i % n, j, seed)) * sx
    b = _hash(i % n, j + 1, seed) + (_hash((i + 1) % n, j + 1, seed) - _hash(i % n, j + 1, seed)) * sx
    return a + (b - a) * sy


def chisel(t, z, r):
    return sum(a * vnoise(t * r, z, c, sd, TAU * r) for c, a, sd in CHISEL)


def plateau(x, lo, hi, ch):
    """1 on [lo+ch, hi-ch], 0 outside [lo, hi], straight chamfers between."""
    return max(0.0, min(1.0, (x - lo) / ch, (hi - x) / ch))


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def seg_dist(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    L = ax * ax + ay * ay
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / L))
    return math.hypot(p[0] - a[0] - t * ax, p[1] - a[1] - t * ay)


def poly_dist(p, poly, closed):
    n = len(poly)
    m = n if closed else n - 1
    return min(seg_dist(p, poly[i], poly[(i + 1) % n]) for i in range(m))


def inside(p, poly):
    x, y = p
    c = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


class Pool:
    """Keyed vertex pool: one 3D position per key, so seams weld by construction."""

    def __init__(self):
        self.co, self.key, self.keyof = [], {}, []

    def add(self, key, co):
        if key not in self.key:
            self.key[key] = len(self.co)
            self.co.append(tuple(co))
            self.keyof.append(key)
        return self.key[key]


# ---------------------------------------------------------------- build

def build():
    j, binary = read_glb(SRC)
    prim = j["meshes"][1]["primitives"][0]
    A = prim["attributes"]
    gpos = accessor(j, binary, A["POSITION"])
    gnrm = accessor(j, binary, A["NORMAL"])
    guv = accessor(j, binary, A["TEXCOORD_0"])
    gcol = accessor(j, binary, A["COLOR_0"])
    gidx = accessor(j, binary, prim["indices"])
    cpos = [g2b(p) for p in accessor(j, binary, j["meshes"][0]["primitives"][0]["attributes"]["POSITION"])]
    cidx = accessor(j, binary, j["meshes"][0]["primitives"][0]["indices"])
    bpos = [g2b(p) for p in gpos]
    tris = [tuple(gidx[k:k + 3]) for k in range(0, len(gidx), 3)]

    # ---- the shaft that stays, and its top edge loop
    keep = [t for t in tris if all(bpos[i][2] <= SEAM_Z for i in t)]
    wid = {}
    wkey = lambda i: tuple(round(c, 6) for c in bpos[i])
    for i in range(len(bpos)):
        wid.setdefault(wkey(i), i)
    edges = {}
    for t in keep:
        w = [wid[wkey(i)] for i in t]
        for k in range(3):
            edges.setdefault((w[k], w[(k + 1) % 3]), 0)
            edges[(w[k], w[(k + 1) % 3])] += 1
    bnd = [e for e in edges if (e[1], e[0]) not in edges]
    nxt = {a: b for a, b in bnd}
    assert len(nxt) == len(bnd), "seam is not a simple loop"
    loop = [bnd[0][0]]
    while True:
        n = nxt[loop[-1]]
        if n == loop[0]:
            break
        loop.append(n)
    assert len(loop) == len(bnd)
    ang = lambda i: math.atan2(bpos[i][1], bpos[i][0])
    rin = max(math.hypot(p[0], p[1]) for p in cpos)
    sill_v = sorted(set(round(math.degrees(math.atan2(p[1], p[0])) % 360, 4)
                        for p in cpos if abs(p[2] - SILL) < 0.02 and math.hypot(p[0], p[1]) > 1))
    grid32 = [a for a in sill_v if abs((a / 11.25) - round(a / 11.25)) < 1e-3]
    jambs = sorted(set(sill_v) - set(grid32))
    a0, a1 = jambs[0], jambs[1]               # an opening's end and the next one's start
    if a1 - a0 > 22.5:
        a0, a1 = jambs[1], jambs[2]
    half_in = 0.5 * (45.0 - (a1 - a0))
    bear0_deg = (a0 - half_in) % 45.0
    BEAR = [math.radians(bear0_deg + 45.0 * k) for k in range(8)]
    PIER0 = math.radians(bear0_deg + 22.5)
    HW_IN = rin * math.sin(math.radians(half_in))
    print("TOWER bays at %.3f+45k deg, half_in %.3f deg, hw_in %.4f, r_in %.4f" % (bear0_deg, half_in, HW_IN, rin))

    def hw(y):
        return HW_IN + (y - rin) * TAN

    start = min(range(len(loop)), key=lambda k: abs(((ang(loop[k]) - PIER0 - 0.02) + math.pi) % TAU - math.pi))
    loop = loop[start:] + loop[:start]
    if ((ang(loop[1]) - ang(loop[0]) + math.pi) % TAU - math.pi) < 0:
        loop = [loop[0]] + loop[1:][::-1]
    th_s0 = ang(loop[0])
    seam = []
    for i in loop:
        t = ang(i)
        t = th_s0 + (t - th_s0) % TAU
        seam.append((i, t, bpos[i][2], math.hypot(bpos[i][0], bpos[i][1])))
    for k in range(1, len(seam)):
        assert seam[k][1] > seam[k - 1][1], "seam not monotonic in bearing"

    # ---- sample the shipped mesh for the silhouette
    bvh = BVHTree.FromPolygons([Vector(p) for p in bpos], tris)

    def r_at(t, z):
        d = Vector((math.cos(t), math.sin(t), 0.0))
        h = bvh.ray_cast(d * 30.0 + Vector((0, 0, z)), -d, 40.0)
        return None if h[0] is None else (h[0] - Vector((0, 0, z))).dot(d)

    def in_bay(t, margin):
        return any(abs(((t - b) + math.pi) % TAU - math.pi) < margin for b in BEAR)

    st, sr = [], []
    for c in range(128):
        t = c * TAU / 128
        for z in (1.0, 1.5):
            r = r_at(t, z)
            if r:
                st.append(t)
                sr.append(r)
        if not in_bay(t, math.radians(20.5)):
            for z in (3.0, 4.0, 5.0, 6.0):
                r = r_at(t, z)
                if r:
                    st.append(t)
                    sr.append(r)
    R_base = fourier_fit(st, sr, 8)
    dome_z = [7.8, 8.1, 8.4, 8.7, 9.0, 9.3, 9.6]
    dome_f = []
    for z in dome_z:
        tt, rr = [], []
        for c in range(128):
            t = c * TAU / 128
            r = r_at(t, z)
            if r:
                tt.append(t)
                rr.append(r)
        dome_f.append(fourier_fit(tt, rr, 6))

    seam_t = [s[1] for s in seam] + [seam[0][1] + TAU]
    seam_z = [s[2] for s in seam] + [seam[0][2]]
    seam_r = [s[3] for s in seam] + [seam[0][3]]

    def seam_at(t):
        t = th_s0 + (t - th_s0) % TAU
        k = max(0, min(len(seam_t) - 2, next(i for i in range(len(seam_t) - 1) if t <= seam_t[i + 1])))
        f = (t - seam_t[k]) / (seam_t[k + 1] - seam_t[k])
        return seam_z[k] + f * (seam_z[k + 1] - seam_z[k]), seam_r[k] + f * (seam_r[k + 1] - seam_r[k])

    def bands(t, z):
        v = sum(p * plateau(z, lo, hi, COURSE_CH) for lo, hi, p in COURSES)
        kw, k0, k1, kp, kc = KEY
        for b in BEAR:
            x = abs(((t - b) + math.pi) % TAU - math.pi) * R_REF
            v += kp * plateau(x, -kw, kw, kc) * plateau(z, k0, k1, kc)
        return v

    def crown(t, z):
        return R_base(t) + bands(t, z) + chisel(t, z, R_REF)

    def R_out(t, z):
        """His shaft's own surface at the seam, handing over to the carved crown across BLEND."""
        c = crown(t, z)
        zs, _rs = seam_at(t)
        w = smoothstep((z - zs) / BLEND)
        if w >= 1.0:
            return c
        ro = r_at(t, z)
        return c if ro is None else ro + (c - ro) * w

    def R_in(t, z):
        w = plateau(z, 2.0, CEIL_WALL, 0.35)
        return R_W + w * (0.03 + 0.5 * chisel(t, z + 40.0, R_W))

    pool = Pool()
    faces = []          # (i, j, k, region)

    def P(t, r, z):
        return (r * math.cos(t), r * math.sin(t), z)

    # ---- opening outlines: one closed section per bay, on either face
    def section():
        """Chunky voussoirs; jamb rows land on the springing course, head points on the keystone's edges."""
        out = []
        n_s, n_c, n_h = 5, 2, 12
        zc = SILL + CORNER
        lo, hi, _p = COURSES[1]
        jz = [3.2, 3.75, lo, 0.5 * (lo + hi)]
        ja = [(z - zc) / (SPRING - zc) for z in jz]
        kx = [KEY[0]]
        heads = sorted(set([math.pi * i / n_h for i in range(n_h + 1)]
                           + [math.acos(sg * x / (HW_IN + 0.9 * TAN)) for x in kx for sg in (1, -1)]))
        for i in range(n_s + 1):
            out.append(("sill", i / n_s))
        for i in range(1, n_c + 1):
            out.append(("corner", 0.5 * math.pi * i / n_c))
        for a in ja:
            out.append(("jamb", a))
        for a in heads:
            out.append(("head", a))
        for a in reversed(ja):
            out.append(("jambL", a))
        for i in range(n_c, 0, -1):
            out.append(("cornerL", 0.5 * math.pi * i / n_c))
        for i in range(n_s, 0, -1):
            out.append(("sillL", i / n_s))
        return out
    SEC = section()

    def sec_xz(kind, a, y):
        h = hw(y)
        zc = SILL + CORNER
        if kind.startswith("sill"):
            x, z = a * (h - CORNER), SILL
        elif kind.startswith("corner"):
            x, z = h - CORNER + CORNER * math.sin(a), zc - CORNER * math.cos(a)
        elif kind.startswith("jamb"):
            x, z = h, zc + a * (SPRING - zc)
        else:
            x, z = h * math.cos(a), SPRING + HEAD_R * math.sin(a)
        if kind.endswith("L"):
            x = -x
        return x + WOB[0], z + WOB[1]

    def on_face(b, kind, a, surf):
        y = R_W
        for _ in range(8):
            x, z = sec_xz(kind, a, y)
            t = b + math.atan2(x, y)
            r = surf(t, z)
            y = math.sqrt(max(r * r - x * x, 1.0))
        x, z = sec_xz(kind, a, y)
        er, et = (math.cos(b), math.sin(b)), (-math.sin(b), math.cos(b))
        return (er[0] * y + et[0] * x, er[1] * y + et[1] * x, z), y

    outlines_in, outlines_out = [], []
    WOB = [0.0, 0.0]
    for k, b in enumerate(BEAR):
        oi, oo = [], []
        for s, (kind, a) in enumerate(SEC):
            if kind == "sillL" and a == 0.0:
                continue
            flat_ = kind.startswith("sill")
            WOB[0] = 0.0 if flat_ else 0.03 * _hash(k, s, 5)
            WOB[1] = 0.03 * _hash(k, s, 7) if kind == "head" else 0.0
            pi_, yi = on_face(b, kind, a, R_in)
            po, yo = on_face(b, kind, a, R_out)
            oi.append(pool.add(("oin", k, s), pi_))
            oo.append(pool.add(("oout", k, s), po))
        outlines_in.append(oi)
        outlines_out.append(oo)
        # reveals: inner outline to outer outline, facing the opening
        n = len(oi)
        for s in range(n):
            q = (oi[s], oi[(s + 1) % n], oo[(s + 1) % n], oo[s])
            faces.append((q, "reveal", b))

    # ---- 2D CDT patch helper
    def cdt_patch(bpts, outer, chains, holes, lattice, region, to3d, flip):
        """bpts: {key2d: (u, v, pool_key, co)}; outer and holes are closed key loops, chains open."""
        keys = list(bpts.keys())
        kid = {k: i for i, k in enumerate(keys)}
        uv = [bpts[k][:2] for k in keys]
        cons = []
        for lp in [outer] + holes:
            for i in range(len(lp)):
                cons.append((kid[lp[i]], kid[lp[(i + 1) % len(lp)]]))
        for ch in chains:
            for i in range(len(ch) - 1):
                cons.append((kid[ch[i]], kid[ch[i + 1]]))
        segs = [(uv[a], uv[b]) for a, b in cons]
        domain = [uv[kid[k]] for k in outer]
        hole2 = [[uv[kid[k]] for k in h] for h in holes]
        extra = []
        for p in lattice:
            if not inside(p[:2], domain) or any(inside(p[:2], h) for h in hole2):
                continue
            dmin = p[2] if len(p) > 2 else DMIN
            p = p[:2]
            if min(seg_dist(p, a, b) for a, b in segs) < dmin:
                continue
            if any(abs(p[0] - q[0]) < 0.05 and abs(p[1] - q[1]) < 0.05 for q in extra):
                continue
            extra.append(p)
        allp = uv + extra
        res = delaunay_2d_cdt([Vector(p) for p in allp], cons, [], 0, 1e-9, True)
        ov, of, orig = res[0], res[2], res[3]
        assert len(ov) == len(allp), "CDT added or merged vertices (%d vs %d)" % (len(ov), len(allp))
        idx = []
        for o in orig:
            src = o[0]
            if src < len(keys):
                _u, _v, pk, co = bpts[keys[src]]
                idx.append(pool.add(pk, co))
            else:
                p = allp[src]
                idx.append(pool.add((region, round(p[0], 6), round(p[1], 6)), to3d(p)))
        n = 0
        for f in of:
            c = (sum(ov[i][0] for i in f) / 3.0, sum(ov[i][1] for i in f) / 3.0)
            if not inside(c, domain) or any(inside(c, h) for h in hole2):
                continue
            tri = [idx[i] for i in f]
            if len(set(tri)) < 3:
                raise RuntimeError("degenerate CDT triangle in %s" % region)
            faces.append((tuple(reversed(tri)) if flip else tuple(tri), region, None))
            n += 1
        print("TOWER %s: %d tris, %d lattice points" % (region, n, len(extra)))
        return n

    # ---- outer wall: seam to TOP_Z, eight holes; unwrapped at a cut up the pier nearest the seam start
    N_TOP = 64
    top_t = [PIER0 + TAU * i / N_TOP for i in range(N_TOP)]
    th0 = seam[0][1]
    t_cut = th0 + ((PIER0 - th0 + math.pi) % TAU - math.pi)

    def unwrap(t, base):
        return base + (t - base) % TAU

    rows = [round(float(z), 3) for z in np.arange(-1.6, TOP_Z - 0.1, ROWS)]
    band_rows = [z for lo, hi, _ in COURSES for z in (lo, lo + COURSE_CH, hi - COURSE_CH, hi)]
    rows = sorted([z for z in rows if all(abs(z - q) > 0.16 for q in band_rows)] + band_rows)

    bp = {}
    outer = []
    for (vi, t, z, r) in seam:
        bp[("seam", vi)] = (t * R_REF, z, ("seam", vi), bpos[vi])
        outer.append(("seam", vi))
    vi0, _, z_s0, _ = seam[0]
    bp[("seamR",)] = ((th0 + TAU) * R_REF, z_s0, ("seam", vi0), bpos[vi0])
    outer.append(("seamR",))
    cut = []
    for z in rows:
        if z_s0 + 0.3 < z < TOP_Z - 0.2:
            f = smoothstep((z - z_s0) / max(0.3, 1.6 - z_s0))
            t = th0 + (t_cut - th0) * f
            cut.append((t, z))
    for ri, (t, z) in enumerate(cut):
        bp[("cutR", ri)] = ((t + TAU) * R_REF, z, ("ocut", ri), P(t, R_out(t, z), z))
        outer.append(("cutR", ri))
    for i in range(N_TOP, -1, -1):
        t = top_t[i % N_TOP]
        u = (t_cut + (t - t_cut) % TAU) if i < N_TOP else t_cut + TAU
        if i == 0:
            u = t_cut
        bp[("top", i)] = (u * R_REF, TOP_Z, ("otop", i % N_TOP), P(t, crown(t, TOP_Z), TOP_Z))
        outer.append(("top", i))
    for ri in range(len(cut) - 1, -1, -1):
        t, z = cut[ri]
        bp[("cutL", ri)] = (t * R_REF, z, ("ocut", ri), P(t, R_out(t, z), z))
        outer.append(("cutL", ri))
    holes = []
    for k in range(8):
        h = []
        for s, vi in enumerate(outlines_out[k]):
            co = pool.co[vi]
            u = unwrap(math.atan2(co[1], co[0]), t_cut) * R_REF
            bp[("oh", k, s)] = (u, co[2], pool.keyof[vi], co)
            h.append(("oh", k, s))
        holes.append(h)
    lat = []
    for z in rows:
        for c in range(120):
            lat.append(((PIER0 + TAU * c / 120) * R_REF, z))
    kw, k0, k1, kp, kc = KEY
    for b in BEAR:
        for x in (-kw, -kw + kc, -0.12, 0.12, kw - kc, kw):
            for z in (k1 - kc, k1):
                lat.append((unwrap(b, th0) * R_REF + x, z, 0.06))

    def out3d(p):
        t = p[0] / R_REF
        return P(t, R_out(t, p[1]), p[1])
    cdt_patch(bp, outer, [], holes, lat, "owall", out3d, False)

    # ---- floor: the collider's own fan planes, and a cove up to the inner wall
    hub = min((p for p in cpos if p[2] < 2.0), key=lambda p: math.hypot(p[0], p[1]))
    ring = {}
    for p in cpos:
        if p[2] < 2.0 and math.hypot(p[0], p[1]) > 1.0:
            ring[round(math.atan2(p[1], p[0]) % TAU, 6)] = p
    spoke_t = sorted(ring)
    ring = [ring[t] for t in spoke_t]

    def floor_z(x, y):
        t = math.atan2(y, x) % TAU
        k = len(spoke_t) - 1
        for i in range(len(spoke_t)):
            if spoke_t[i] <= t + 1e-12:
                k = i
        a, b, c = Vector(hub), Vector(ring[k]), Vector(ring[(k + 1) % len(ring)])
        n = (b - a).cross(c - a)
        return a.z - (n.x * (x - a.x) + n.y * (y - a.y)) / n.z

    bot_t = sorted([(PIER0 + TAU * i / 64) % TAU for i in range(64)] + spoke_t)
    i0 = min(range(len(bot_t)), key=lambda i: abs(((bot_t[i] - PIER0) + math.pi) % TAU - math.pi))
    bot_t = bot_t[i0:] + bot_t[:i0]
    r_c0 = R_W - FLOOR_COVE
    cove_rows = []
    for ci, a in enumerate((0.0, math.pi / 6, math.pi / 3, math.pi / 2)):
        row = []
        for i, t in enumerate(bot_t):
            zf = floor_z(r_c0 * math.cos(t), r_c0 * math.sin(t))
            r = r_c0 + FLOOR_COVE * math.sin(a)
            z = zf + FLOOR_COVE - FLOOR_COVE * math.cos(a)
            row.append(pool.add(("fcove", ci, i), P(t, r, z)))
        cove_rows.append(row)
    _rings(faces, cove_rows, "fcove", flip=True)
    fb = {}
    fring = []
    for i in range(len(bot_t)):
        co = pool.co[cove_rows[0][i]]
        fb[("fr", i)] = (co[0], co[1], ("fcove", 0, i), co)
        fring.append(("fr", i))
    fb[("hub",)] = (hub[0], hub[1], ("hub",), hub)
    chains = []
    for s, t in enumerate(spoke_t):
        ch = [("hub",)]
        n = 6
        for m in range(2, n):
            r = r_c0 * m / n
            x, y = r * math.cos(t), r * math.sin(t)
            fb[("sp", s, m)] = (x, y, ("spoke", s, m), (x, y, floor_z(x, y)))
            ch.append(("sp", s, m))
        ch.append(("fr", bot_t.index(t)))
        chains.append(ch)
    flat = []
    for gi, gy in enumerate(np.arange(-7.0, 7.01, 0.78)):
        for gx in np.arange(-7.0, 7.01, 0.9):
            flat.append((float(gx) + (0.45 if gi % 2 else 0.0), float(gy)))
    cdt_patch(fb, fring, chains, [], flat, "floor", lambda p: (p[0], p[1], floor_z(p[0], p[1])), False)

    # ---- inner wall: floor cove top to ceiling cove, eight holes, cut up the pier at PIER0
    N_IT = 128
    itop_t = [PIER0 + TAU * i / N_IT for i in range(N_IT)]
    ib = {}
    iouter = []
    for i, t in enumerate(bot_t):
        co = pool.co[cove_rows[3][i]]
        u = (PIER0 + (t - PIER0) % TAU) if i else PIER0
        ib[("b", i)] = (u * R_W, co[2], ("fcove", 3, i), co)
        iouter.append(("b", i))
    co0 = pool.co[cove_rows[3][0]]
    ib[("bR",)] = ((PIER0 + TAU) * R_W, co0[2], ("fcove", 3, 0), co0)
    iouter.append(("bR",))
    icut = [float(z) for z in np.arange(co0[2] + ROWS, CEIL_WALL - 0.15, ROWS)]
    for ri, z in enumerate(icut):
        ib[("cR", ri)] = ((PIER0 + TAU) * R_W, z, ("icut", ri), P(PIER0, R_W, z))
        iouter.append(("cR", ri))
    for i in range(N_IT, -1, -1):
        t = itop_t[i % N_IT]
        u = (PIER0 + TAU) if i == N_IT else t
        ib[("t", i)] = (u * R_W, CEIL_WALL, ("itop", i % N_IT), P(t, R_W, CEIL_WALL))
        iouter.append(("t", i))
    for ri in range(len(icut) - 1, -1, -1):
        z = icut[ri]
        ib[("cL", ri)] = (PIER0 * R_W, z, ("icut", ri), P(PIER0, R_W, z))
        iouter.append(("cL", ri))
    iholes = []
    for k in range(8):
        h = []
        for s, vi in enumerate(outlines_in[k]):
            co = pool.co[vi]
            u = unwrap(math.atan2(co[1], co[0]), PIER0) * R_W
            ib[("ih", k, s)] = (u, co[2], pool.keyof[vi], co)
            h.append(("ih", k, s))
        iholes.append(h)
    ilat = []
    irows = [float(z) for z in np.arange(co0[2] + ROWS, CEIL_WALL - 0.1, ROWS)]
    for z in irows:
        for c in range(96):
            ilat.append(((PIER0 + TAU * c / 96) * R_W, z))
    cdt_patch(ib, iouter, [], iholes, ilat, "iwall", lambda p: P(p[0] / R_W, R_in(p[0] / R_W, p[1]), p[1]), True)

    # ---- ceiling cove and ceiling disk
    c_rows = []
    for ci, a in enumerate((0.0, math.pi / 6, math.pi / 3, math.pi / 2)):
        row = []
        for i, t in enumerate(itop_t):
            r = CEIL_IN + (R_W - CEIL_IN) * math.cos(a)
            z = CEIL_WALL + (CEIL - CEIL_WALL) * math.sin(a)
            key = ("itop", i) if ci == 0 else ("ccove", ci, i)
            row.append(pool.add(key, P(t, r, z)))
        c_rows.append(row)
    _rings(faces, c_rows, "ccove", flip=True)
    cb = {}
    cring = []
    for i in range(N_IT):
        co = pool.co[c_rows[3][i]]
        cb[("c", i)] = (co[0], co[1], ("ccove", 3, i), co)
        cring.append(("c", i))
    clat = []
    for gi, gy in enumerate(np.arange(-7.0, 7.01, 0.78)):
        for gx in np.arange(-7.0, 7.01, 0.9):
            clat.append((float(gx) + (0.45 if gi % 2 else 0.0), float(gy)))
    cdt_patch(cb, cring, [], [], clat, "ceiling", lambda p: (p[0], p[1], CEIL), True)

    # ---- roof: his own roof rings, carved, up to his apex
    knots = [(7.8, dome_f[0]), (8.1, dome_f[1]), (8.4, dome_f[2]), (8.7, dome_f[3]),
             (9.0, dome_f[4]), (9.3, dome_f[5]), (9.6, dome_f[6])]
    apex_co = max(bpos, key=lambda p: p[2])
    d_rows = [TOP_Z, 7.6] + [z for z, _ in knots] + [9.85]
    rows3 = []
    prev = None
    for ri, z in enumerate(d_rows):
        if z == 7.6:
            rad = lambda t: 0.5 * (crown(t, TOP_Z) + dome_f[0](t))
        elif z == 9.85:
            rad = None
        else:
            rad = next((f for zz, f in knots if zz == z), None)
        if rad is None and ri:
            pts = [(apex_co[0] + 0.45 * (pool.co[v][0] - apex_co[0]), apex_co[1] + 0.45 * (pool.co[v][1] - apex_co[1]))
                   for v in prev]
            mean_r = sum(math.hypot(x - apex_co[0], y - apex_co[1]) for x, y in pts) / len(pts)
        else:
            mean_r = sum((rad(t) if ri else 7.6) for t in top_t) / N_TOP
        n = 64 if mean_r > 4.2 else 32 if mean_r > 1.8 else 16 if mean_r > 0.8 else 8
        step = N_TOP // n
        row = []
        for i in range(0, N_TOP, step):
            t = top_t[i]
            if ri == 0:
                row.append(pool.add(("otop", i), P(t, crown(t, TOP_Z), TOP_Z)))
            elif rad is None:
                src = pool.co[prev[i // (N_TOP // len(prev))]]
                jz = 0.03 * _hash(ri, i, 3)
                row.append(pool.add(("dome", ri, i), (apex_co[0] + 0.45 * (src[0] - apex_co[0]),
                                                     apex_co[1] + 0.45 * (src[1] - apex_co[1]), z + jz)))
            else:
                r = rad(t) + chisel(t, z * 1.7 + 20.0, R_REF) * 0.9
                row.append(pool.add(("dome", ri, i), P(t, r, z + 0.04 * _hash(ri, i, 9))))
        rows3.append(row)
        prev = row
    _rings(faces, rows3, "dome", flip=False)
    last = rows3[-1]
    apex = pool.add(("apex",), tuple(apex_co))
    for i in range(len(last)):
        faces.append(((last[i], last[(i + 1) % len(last)], apex), "dome", None))

    return j, binary, gpos, gnrm, guv, gcol, tris, keep, pool, faces, BEAR, hw


def _rings(faces, rows, region, flip):
    """Stitch consecutive closed rings (counts may halve) with quads and zip triangles."""
    for a, b in zip(rows[:-1], rows[1:]):
        na, nb = len(a), len(b)
        if na == nb:
            for i in range(na):
                q = (a[i], a[(i + 1) % na], b[(i + 1) % nb], b[i])
                faces.append((tuple(reversed(q)) if flip else q, region, None))
        else:
            r = na // nb
            assert na == nb * r
            for i in range(nb):
                fan = [a[(i * r + m) % na] for m in range(r + 1)]
                # lower edge pieces to b[i] and b[i+1]: split at the middle
                mid = r // 2
                for m in range(r):
                    top = b[i] if m < mid else b[(i + 1) % nb]
                    t = (fan[m], fan[m + 1], top)
                    faces.append((tuple(reversed(t)) if flip else t, region, None))
                t = (fan[mid], b[(i + 1) % nb], b[i])
                faces.append((tuple(reversed(t)) if flip else t, region, None))


# ---------------------------------------------------------------- finish: uv, normals, glb

def uv_for(cos, n):
    c = [sum(p[i] for p in cos) / 3.0 for i in range(3)]
    ac = math.atan2(c[1], c[0])
    rx, ry = math.cos(ac), math.sin(ac)
    nr = n[0] * rx + n[1] * ry
    nt = -n[0] * ry + n[1] * rx
    out = []
    for p in cos:
        if abs(n[2]) >= max(abs(nr), abs(nt)):
            u, v = p[0] / UV_M, 1.0 + p[1] / UV_M
        elif abs(nr) >= abs(nt):
            th = math.atan2(p[1], p[0])
            th = ac + (th - ac + math.pi) % TAU - math.pi
            u = (2.0 - 4.0 * th / TAU) if nr > 0 else (1.5 - 3.0 * th / TAU)
            v = 1.0 + p[2] / UV_M
        else:
            u, v = math.hypot(p[0], p[1]) / UV_M, 1.0 + p[2] / UV_M
        out.append((u, 1.0 - v))           # glTF's v runs down
    return out


def tri_list(faces, pool):
    out = []
    for f, region, b in faces:
        if len(f) == 4:
            a, b_, c, d = f
            # split along the shorter diagonal
            if math.dist(pool.co[a], pool.co[c]) <= math.dist(pool.co[b_], pool.co[d]):
                out += [((a, b_, c), region, b), ((a, c, d), region, b)]
            else:
                out += [((a, b_, d), region, b), ((b_, c, d), region, b)]
        else:
            out.append((tuple(f), region, b))
    return out


def orient(tris, pool, BEAR, hw):
    fixed = []
    for (a, b, c), region, bear in tris:
        A, B, C = (Vector(pool.co[i]) for i in (a, b, c))
        n = (B - A).cross(C - A)
        m = (A + B + C) / 3.0
        if region == "reveal":
            er = Vector((math.cos(bear), math.sin(bear), 0.0))
            et = Vector((-math.sin(bear), math.cos(bear), 0.0))
            y = m.dot(er)
            z = max(SILL + 0.6, min(SPRING, m.z))
            want = er * y + Vector((0, 0, z)) - m
        else:
            want = None
        if want is not None and n.dot(want) < 0:
            fixed.append(((a, c, b), region))
        else:
            fixed.append(((a, b, c), region))
    return fixed


def write(j, binary, gpos, gnrm, guv, gcol, tris, keep, pool, newtris):
    rock = {}
    cnt = {}
    for t in keep:
        for i in t:
            cnt[gcol[i]] = cnt.get(gcol[i], 0) + 1
    col = max(cnt, key=cnt.get)
    verts, index, vid = [], [], {}

    def emit(key):
        if key not in vid:
            vid[key] = len(verts)
            verts.append(key)
        index.append(vid[key])
    for t in keep:
        for i in t:
            emit((gpos[i], gnrm[i], guv[i], gcol[i]))
    f32 = lambda x: struct.unpack("<f", struct.pack("<f", x))[0]
    for (a, b, c), region in newtris:
        cos = [pool.co[i] for i in (a, b, c)]
        A, B, C = (Vector(p) for p in cos)
        n = (B - A).cross(C - A).normalized()
        uvs = uv_for(cos, n)
        ng = tuple(f32(x) for x in b2g(n))
        for p, uv in zip(cos, uvs):
            emit((tuple(f32(x) for x in b2g(p)), ng, tuple(f32(x) for x in uv), col))
    assert len(verts) < 65536
    # rebuild the BIN: collider views copied raw, the rock's written fresh
    jj = json.loads(json.dumps(j))
    out = bytearray()
    views = []

    def add_view(raw, target=None):
        while len(out) % 4:
            out.append(0)
        v = {"buffer": 0, "byteOffset": len(out), "byteLength": len(raw)}
        if target:
            v["target"] = target
        out.extend(raw)
        views.append(v)
        return len(views) - 1
    cprim = jj["meshes"][0]["primitives"][0]
    for ai in list(cprim["attributes"].values()) + [cprim["indices"]]:
        a = jj["accessors"][ai]
        bv = j["bufferViews"][a["bufferView"]]
        raw = binary[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        a["bufferView"] = add_view(raw, bv.get("target"))
    prim = jj["meshes"][1]["primitives"][0]
    A = prim["attributes"]
    P_ = [v[0] for v in verts]
    for name, data, fmt in (("POSITION", P_, "fff"), ("NORMAL", [v[1] for v in verts], "fff"),
                            ("TEXCOORD_0", [v[2] for v in verts], "ff"), ("COLOR_0", [v[3] for v in verts], "fff")):
        raw = b"".join(struct.pack("<" + fmt, *d) for d in data)
        a = jj["accessors"][A[name]]
        a["bufferView"] = add_view(raw, 34962)
        a["count"] = len(data)
        if name == "POSITION":
            a["min"] = [min(p[i] for p in P_) for i in range(3)]
            a["max"] = [max(p[i] for p in P_) for i in range(3)]
    raw = struct.pack("<%dH" % len(index), *index)
    a = jj["accessors"][prim["indices"]]
    a["bufferView"] = add_view(raw, 34963)
    a["count"] = len(index)
    while len(out) % 4:
        out.append(0)
    jj["bufferViews"] = views
    jj["buffers"] = [{"byteLength": len(out)}]
    js = json.dumps(jj, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(OUT, "wb") as fh:
        fh.write(struct.pack("<III", 0x46546C67, 2, total))
        fh.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        fh.write(struct.pack("<II", len(out), 0x004E4942) + bytes(out))
    print("TOWER wrote %s tris=%d verts=%d (kept %d shaft tris)" % (OUT, len(index) // 3, len(verts), len(keep)))


def main():
    j, binary, gpos, gnrm, guv, gcol, tris, keep, pool, faces, BEAR, hw = build()
    newtris = orient(tri_list(faces, pool), pool, BEAR, hw)
    write(j, binary, gpos, gnrm, guv, gcol, tris, keep, pool, newtris)


if __name__ == "__main__":
    main()
