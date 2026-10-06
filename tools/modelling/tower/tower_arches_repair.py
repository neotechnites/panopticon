"""Repair tower_arches.glb in place: boolean slivers, tiny tris and fins merged into neighbours, floating shards dropped.
python3 tools/modelling/tower/tower_arches_repair.py [tol_m]  ->  tower/models/tower_arches_repaired.glb"""

import json
import math
import os
import struct
import sys

import numpy as np

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SRC = os.path.join(REPO, "tower", "models", "tower_arches.glb")
DST = os.path.join(REPO, "tower", "models", "tower_arches_repaired.glb")
SEAM_Y = 0.6       # glTF y: a triangle wholly at or below this is the shaft, frozen byte for byte
TOL = 0.03         # metres: the most any edit may move the surface
TOL_SLIVER = 0.07  # ...where everything it moves is sliver (the artifact itself)
NORMAL_TOL = 5.0   # degrees: a sound facet's normal may turn this much, so its flat shade stays the same
SMALL_TURN = 20.0  # ...and a facet of a hand's breadth (0.01 m^2) may turn this much
SLIVER = 5.0       # degrees
SOFT = 10.0
TINY = 0.005       # m^2
FOLD = 100.0       # degrees between neighbouring facets
FOOT_Y = 2.5       # below this (floor, kerb, pier feet) the guard stands close...
FOOT_TOL = 0.05    # ...so the fans there may move this far
FOOT_TURN = (15.0, 30.0)  # ...and turn this much (large, small facets)
FOOT_SLIVER = 10.0 # ...and a fan blade thinner than this is a sliver there
NEEDLE_ANGLE = 5.0 # degrees: a blade this thin reads as a crack wherever it is
STRIPE_ANGLE = 3.0 # degrees, and...
STRIPE_LEN = 1.0   # ...metres: a blade this thin and long is a stripe of the wrong shade up a pier
STRIPE_TOL = 0.18  # ...closed onto the corner it runs along
STRIPE_TURN = (30.0, 45.0)
CREASE = 40.0      # degrees: facets meeting gentler than this shade as one surface
FLOOR_Y = 1.65     # the guard-room floor, glTF y
FLOOR_UP = 0.97    # a floor facet's normal y
FLOOR_STEP = 1.2   # metres between the points the floor is re-cut through


def read_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack_from("<I", d, 12)[0]
    j = json.loads(d[20:20 + jl])
    b = d[20 + jl + 8:20 + jl + 8 + j["buffers"][0]["byteLength"]]
    return j, b


def accessor(j, b, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
    dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[a["componentType"]]
    arr = np.frombuffer(b, dtype=dt, count=a["count"] * n, offset=bv.get("byteOffset", 0) + a.get("byteOffset", 0))
    return arr.reshape(-1, n) if n > 1 else arr


def tri_normal(p):
    n = np.cross(p[1] - p[0], p[2] - p[0])
    L = np.linalg.norm(n)
    return n / L if L > 1e-15 else n, 0.5 * L


def min_angle(p):
    out = 180.0
    for k in range(3):
        u, w = p[(k + 1) % 3] - p[k], p[(k + 2) % 3] - p[k]
        lu, lw = np.linalg.norm(u), np.linalg.norm(w)
        if lu < 1e-12 or lw < 1e-12:
            return 0.0
        out = min(out, math.degrees(math.acos(max(-1.0, min(1.0, float(u @ w) / (lu * lw))))))
    return out


def pt_tri(q, a, b, c):
    """Distance from q to triangle abc (Ericson)."""
    ab, ac, ap = b - a, c - a, q - a
    d1, d2 = ab @ ap, ac @ ap
    if d1 <= 0 and d2 <= 0:
        return np.linalg.norm(q - a)
    bp = q - b
    d3, d4 = ab @ bp, ac @ bp
    if d3 >= 0 and d4 <= d3:
        return np.linalg.norm(q - b)
    vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0:
        return np.linalg.norm(q - (a + ab * (d1 / (d1 - d3))))
    cp = q - c
    d5, d6 = ab @ cp, ac @ cp
    if d6 >= 0 and d5 <= d6:
        return np.linalg.norm(q - c)
    vb = d5 * d2 - d1 * d6
    if vb <= 0 and d2 >= 0 and d6 <= 0:
        return np.linalg.norm(q - (a + ac * (d2 / (d2 - d6))))
    va = d3 * d6 - d5 * d4
    if va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
        return np.linalg.norm(q - (b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))))
    den = 1.0 / (va + vb + vc)
    return np.linalg.norm(q - (a + ab * (vb * den) + ac * (vc * den)))


def seg_seg(p1, q1, p2, q2):
    d1, d2, r = q1 - p1, q2 - p2, p1 - p2
    a, e, f = d1 @ d1, d2 @ d2, d2 @ r
    c, b = d1 @ r, d1 @ d2
    den = a * e - b * b
    s = min(1.0, max(0.0, (b * f - c * e) / den)) if den > 1e-15 else 0.0
    t = (b * s + f) / e if e > 1e-15 else 0.0
    if t < 0:
        t, s = 0.0, min(1.0, max(0.0, -c / a)) if a > 1e-15 else 0.0
    elif t > 1:
        t, s = 1.0, min(1.0, max(0.0, (b - c) / a)) if a > 1e-15 else 0.0
    return np.linalg.norm((p1 + d1 * s) - (p2 + d2 * t))


class Mesh:
    def __init__(self, P32, F, frozen_y):
        key = np.round(P32.astype(np.float64), 6)
        uq, first, wid = np.unique(key, axis=0, return_index=True, return_inverse=True)
        self.V = P32[first].astype(np.float64)          # welded positions, exact float32 values
        self.V32 = P32[first]
        self.F = [list(f) for f in wid.ravel()[F]]
        self.orig = list(range(len(F)))                 # attribute parent per face
        self.alive = [True] * len(F)
        self.moved = set()                              # welded verts given a new position
        self.frozen = [bool(self.V[f, 1].max() <= frozen_y) for f in self.F]
        self.locked = set(v for f, fr in zip(self.F, self.frozen) if fr for v in f)
        self.vf = [set() for _ in range(len(self.V))]
        for i, f in enumerate(self.F):
            for v in f:
                self.vf[v].add(i)
        self.base = [None] * len(F)                     # parent plane and corners for UV extrapolation
        for i, f in enumerate(self.F):
            self.base[i] = (self.V[f].copy(), tuple(f))

    def pts(self, i):
        return self.V[self.F[i]]

    def edge_faces(self, a, b):
        return [i for i in self.vf[a] & self.vf[b] if self.alive[i]]

    def nbrs(self, v):
        return set(u for i in self.vf[v] for u in self.F[i]) - {v}

    def bad(self, i):
        p = self.pts(i)
        _, ar = tri_normal(p)
        m = min_angle(p)
        c = 0.0
        if m < SLIVER:
            c += 1.0 + (SLIVER - m) / SLIVER
        if m < SOFT:
            c += 0.2 * (SOFT - m) / SOFT
        if ar < TINY:
            c += 0.5 * (1.0 - ar / TINY)
        return c

    def fold(self, a, b):
        fs = self.edge_faces(a, b)
        if len(fs) != 2:
            return 0.0
        if not (self.bad(fs[0]) or self.bad(fs[1])):
            return 0.0                                  # a sharp edge between sound facets is his stone
        n0, _ = tri_normal(self.pts(fs[0]))
        n1, _ = tri_normal(self.pts(fs[1]))
        return 1.0 if float(n0 @ n1) < math.cos(math.radians(FOLD)) else 0.0

    def cost(self, faces):
        c, seen = 0.0, set()
        for i in faces:
            if not self.alive[i]:
                continue
            c += self.bad(i)
            f = self.F[i]
            for k in range(3):
                e = (min(f[k], f[(k + 1) % 3]), max(f[k], f[(k + 1) % 3]))
                if e not in seen:
                    seen.add(e)
                    c += self.fold(*e)
        return c

    # -- operations: each returns an undo record ---------------------------------
    def collapse(self, v, w):
        star = [i for i in self.vf[v] if self.alive[i]]
        rec = ("c", v, w, [(i, list(self.F[i])) for i in star])
        for i in star:
            if w in self.F[i]:
                self.alive[i] = False
                for u in self.F[i]:
                    self.vf[u].discard(i)
            else:
                self.F[i] = [w if u == v else u for u in self.F[i]]
                self.vf[w].add(i)
        self.vf[v] = set()
        return rec

    def flip(self, i, j, a, b):
        fi, fj = self.F[i], self.F[j]
        c = [u for u in fi if u not in (a, b)][0]
        d = [u for u in fj if u not in (a, b)][0]
        # fi holds a->b, fj holds b->a: quad a,d,b,c; split by c-d
        k = fi.index(a)
        if fi[(k + 1) % 3] != b:
            a, b = b, a
        rec = ("f", [(i, list(fi)), (j, list(fj))])
        self.F[i] = [d, b, c]
        self.F[j] = [a, d, c]
        self.vf[a].discard(i)
        self.vf[b].discard(j)
        self.vf[d].add(i)
        self.vf[c].add(j)
        return rec

    def undo(self, rec):
        if rec[0] == "c":
            _, v, w, star = rec
            for i, f in star:
                for u in self.F[i]:
                    self.vf[u].discard(i)
                self.F[i] = f
                self.alive[i] = True
            for i, f in star:
                for u in f:
                    self.vf[u].add(i)
        else:
            for i, f in rec[1]:
                for u in self.F[i]:
                    self.vf[u].discard(i)
            for i, f in rec[1]:
                self.F[i] = f
                for u in f:
                    self.vf[u].add(i)


def qem_point(m, v, w):
    """Where v and w meet so the sound facets round them keep their planes (least squares, nearest the midpoint)."""
    A, rhs = np.zeros((3, 3)), np.zeros(3)
    for i in set(m.vf[v]) | set(m.vf[w]):
        if not m.alive[i]:
            continue
        p = m.pts(i)
        ar = sound(p)
        if ar:
            n, _ = tri_normal(p)
            A += ar * np.outer(n, n)
            rhs += ar * n * float(n @ p[0])
    mid = 0.5 * (m.V[v] + m.V[w])
    U, S, Vt = np.linalg.svd(A)
    inv = np.array([1.0 / x if x > S[0] * 1e-3 else 0.0 for x in S]) if S[0] > 0 else np.zeros(3)
    return mid + Vt.T @ (inv * (U.T @ (rhs - A @ mid)))


def try_collapse(m, v, w, x=None, apply=False):
    """Merge v into w (w moved to x when given). Returns (gain, err) or None if not allowed."""
    if v in m.locked or (x is not None and w in m.locked):
        return None
    star = [i for i in m.vf[v] if m.alive[i]]
    wstar = [i for i in m.vf[w] if m.alive[i]]
    if any(m.frozen[i] for i in star) or (x is not None and any(m.frozen[i] for i in wstar)):
        return None
    both = [i for i in star if w in m.F[i]]
    if len(both) != 2:
        return None
    opp = set(u for i in both for u in m.F[i]) - {v, w}
    if m.nbrs(v) & m.nbrs(w) != opp:
        return None
    touched = set(star) | (set(wstar) if x is not None else set())
    old = {i: (m.pts(i).copy(), tri_normal(m.pts(i))) for i in touched}
    region = set(star) | set(wstar)
    before = m.cost(region)
    q, wold = m.V[v].copy(), m.V[w].copy()
    rec = m.collapse(v, w)
    if x is not None:
        m.V[w] = x
    ok, err = True, 0.0
    new = [i for i in touched if m.alive[i]]
    for i in new:
        n, ar = tri_normal(m.pts(i))
        if ar < 1e-9 or (old[i][1][1] > 1e-6 and float(n @ old[i][1][0]) < 0.0):
            ok = False
            break
    if ok:
        err = min(pt_tri(q, *m.pts(i)) for i in new) if new else 0.0
        if x is not None:
            err = max(err, min(pt_tri(wold, *m.pts(i)) for i in new))
        err = max(err, fidelity(m, new, [(old[k][0], old[k][1][0], sound(old[k][0])) for k in touched]))
    after = m.cost(region) if ok else 1e9
    if apply and ok:
        if x is not None:
            m.moved.add(w)
        return (before - after, err)
    m.V[w] = wold
    m.undo(rec)
    return (before - after, err) if ok else None


def sound(p):
    """A sound facet's area (0 for a sliver or tiny one, whose shade is the artifact)."""
    ar = tri_normal(p)[1]
    return ar if min_angle(p) >= SLIVER and ar >= TINY else 0.0


def turn_limit(area):
    """Small facets may turn further than large ones: at 0.01 m^2 or less, SMALL_TURN; from 0.05 m^2, NORMAL_TOL."""
    t = min(1.0, max(0.0, (area - 0.01) / 0.04))
    return SMALL_TURN + t * (NORMAL_TOL - SMALL_TURN)


DEV = [0.0]


def fidelity(m, new, olds):
    """Largest gap from the new facets to the old surface; inf if a sound old facet's shade would turn."""
    err = 0.0
    for i in new:
        p = m.pts(i)
        n, ar = tri_normal(p)
        for s in (p[0], p[1], p[2], (p[0] + p[1]) / 2, (p[1] + p[2]) / 2, (p[2] + p[0]) / 2):
            err = max(err, min(pt_tri(s, *o[0]) for o in olds))
        if ar < 1e-4:
            continue
        for s in (p.mean(0), (4 * p[0] + p[1] + p[2]) / 6, (p[0] + 4 * p[1] + p[2]) / 6, (p[0] + p[1] + 4 * p[2]) / 6):
            ds = [pt_tri(s, *o[0]) for o in olds]
            d0 = min(ds)
            err = max(err, d0)
            near = [o for o, d in zip(olds, ds) if d <= d0 + 1e-3]
            if not all(o[2] for o in near):
                continue                                # over a sliver: its shade is the artifact
            dev = min(math.degrees(math.acos(max(-1.0, min(1.0, float(n @ o[1]))))) - turn_limit(o[2]) for o in near)
            DEV[0] = max(DEV[0], dev)
            if dev > 0.0:
                return float("inf")
    return err


def try_flip(m, a, b):
    fs = m.edge_faces(a, b)
    if len(fs) != 2 or any(m.frozen[i] for i in fs):
        return None
    i, j = fs
    c = [u for u in m.F[i] if u not in (a, b)][0]
    d = [u for u in m.F[j] if u not in (a, b)][0]
    if c == d or m.edge_faces(c, d) or (c in m.nbrs(d)):
        return None
    oi, oj = m.orig[i], m.orig[j]
    if COLOR[oi] != COLOR[oj] or not uv_agree(m, i, j, a, b):
        return None
    err = seg_seg(m.V[a], m.V[b], m.V[c], m.V[d])
    olds = [(m.pts(k).copy(), tri_normal(m.pts(k))[0], sound(m.pts(k))) for k in (i, j)]
    region = {i, j} | set(k for u in (a, b, c, d) for k in m.vf[u] if m.alive[k])
    before = m.cost(region)
    rec = m.flip(i, j, a, b)
    ok = all(tri_normal(m.pts(k))[1] > 1e-9 for k in (i, j))
    if ok:
        err = max(err, fidelity(m, (i, j), olds))
    after = m.cost(region) if ok else 1e9
    m.undo(rec)
    return (before - after, err) if ok else None


def uv_at(m, i, q):
    """UV of point q on face i, from its parent facet's own projection (exact at the parent's corners)."""
    o = m.orig[i]
    bp, bv = m.base[o]
    for k in range(3):
        if np.array_equal(m.V[bv[k]], q):
            return UV[CORNER[o][k]].astype(np.float64)
    n = np.cross(bp[1] - bp[0], bp[2] - bp[0])
    a0 = n @ n
    if a0 < 1e-20:
        return UV[CORNER[o][0]].astype(np.float64)
    w = [np.cross(bp[(k + 1) % 3] - q, bp[(k + 2) % 3] - q) @ n / a0 for k in range(3)]
    return sum(w[k] * UV[CORNER[o][k]].astype(np.float64) for k in range(3))


def uv_agree(m, i, j, a, b):
    return all(np.abs(uv_at(m, i, m.V[v]) - uv_at(m, j, m.V[v])).max() < 1e-3 for v in (a, b))


def repair(m, tol, zone=None):
    applied = {"flip": 0, "collapse": 0, "placed": 0}
    for _ in range(60):
        work = []
        for i in range(len(m.F)):
            if not m.alive[i] or m.frozen[i]:
                continue
            b = m.bad(i)
            if b > 0 and (zone is None or zone(m.pts(i))):
                work.append((-b, i))
        work.sort()
        changed = 0
        for _, i in work:
            if not m.alive[i]:
                continue
            f = m.F[i]
            if m.bad(i) <= 0:
                continue
            best = None

            def offer(r, *op):
                nonlocal best
                lim = tol if DEV[0] > -1e9 else TOL_SLIVER     # nothing sound under it: only slivers move
                if r and r[1] <= lim:
                    best = max(best or (-1e9,), (r[0] - (1e-3 if op[0] == "q" else 0.0), -r[1]) + op)
            for k in range(3):
                a, c = f[k], f[(k + 1) % 3]
                DEV[0] = -2e9
                offer(try_flip(m, a, c), "f", a, c, None)
                for v, w in ((a, c), (c, a)):
                    DEV[0] = -2e9
                    offer(try_collapse(m, v, w), "c", v, w, None)
                x = qem_point(m, a, c)
                for v, w in ((a, c), (c, a)):
                    DEV[0] = -2e9
                    offer(try_collapse(m, v, w, x), "q", v, w, x)
            if best and best[0] > 1e-6:
                if best[2] == "f":
                    fs = m.edge_faces(best[3], best[4])
                    m.flip(fs[0], fs[1], best[3], best[4])
                    applied["flip"] += 1
                elif best[2] == "c":
                    m.collapse(best[3], best[4])
                    applied["collapse"] += 1
                else:
                    try_collapse(m, best[3], best[4], best[5], apply=True)
                    applied["placed"] += 1
                changed += 1
        print("pass: %d edits" % changed)
        if not changed:
            break
    return applied


def manifold_at(m, verts):
    """Every edge round these verts has exactly two faces running opposite ways, and each vert one fan."""
    for v in verts:
        fs = [i for i in m.vf[v] if m.alive[i]]
        if not fs:
            continue
        out = {}
        for i in fs:
            f = m.F[i]
            k = f.index(v)
            out.setdefault(f[(k + 1) % 3], []).append(f[(k + 2) % 3])
        if any(len(x) != 1 for x in out.values()):
            return False
        start = next(iter(out))
        cur, n = start, 0
        while True:
            cur = out.get(cur, [None])[0]
            n += 1
            if cur is None or cur not in out:
                return False
            if cur == start:
                break
        if n != len(out):
            return False
        for u in out:
            d = sum(1 for i in m.vf[v] & m.vf[u] if m.alive[i])
            if d != 2:
                return False
    return True


def fins(m, limit=170.0, tol=0.10):
    """Faces folded flat back onto a neighbour (a zero-thickness flap: its back shows through) are merged away."""
    done = 0
    for _ in range(10):
        found = False
        for i in range(len(m.F)):
            if not m.alive[i] or m.frozen[i]:
                continue
            f = m.F[i]
            for k in range(3):
                a, b = f[k], f[(k + 1) % 3]
                fs = m.edge_faces(a, b)
                if len(fs) != 2:
                    continue
                n0, n1 = tri_normal(m.pts(fs[0]))[0], tri_normal(m.pts(fs[1]))[0]
                if float(n0 @ n1) > math.cos(math.radians(limit)):
                    continue
                vs = sorted(set(m.F[fs[0]]) | set(m.F[fs[1]]))
                best = None
                for v in vs:
                    for w in vs:
                        if v == w or v in m.locked or w not in m.nbrs(v):
                            continue
                        r = cancel_collapse(m, v, w, tol)
                        if r is not None and (best is None or r < best[0]):
                            best = (r, v, w)
                if best:
                    cancel_collapse(m, best[1], best[2], tol, apply=True)
                    done += 1
                    found = True
                    break
        if not found:
            break
    return done


def cancel_collapse(m, v, w, tol, apply=False):
    """Collapse v into w, deleting faces left back to back; returns the surface gap or None."""
    star = [i for i in m.vf[v] if m.alive[i]]
    if any(m.frozen[i] for i in star):
        return None
    old = [m.pts(i).copy() for i in star]
    q = m.V[v].copy()
    rec = m.collapse(v, w)
    gone = []
    bykey = {}
    for i in [k for k in m.vf[w] if m.alive[k]]:
        bykey.setdefault(frozenset(m.F[i]), []).append(i)
    for key, fs in bykey.items():
        if len(fs) == 2:
            for i in fs:
                m.alive[i] = False
                for u in m.F[i]:
                    m.vf[u].discard(i)
                gone.append(i)
    region = set(u for i in star for u in m.F[i]) | {w}
    ok = manifold_at(m, region)
    new = [i for i in star if m.alive[i]]
    err = None
    if ok and new:
        err = min(pt_tri(q, *m.pts(i)) for i in new)
        for i in new:
            p = m.pts(i)
            if tri_normal(p)[1] < 1e-9:
                err = None
                break
            for s in (p.mean(0), (p[0] + p[1]) / 2, (p[1] + p[2]) / 2, (p[2] + p[0]) / 2):
                err = max(err, min(pt_tri(s, *o) for o in old))
        if err is not None and err > tol:
            err = None
    if apply and err is not None:
        return err
    for i in gone:
        m.alive[i] = True
        for u in m.F[i]:
            m.vf[u].add(i)
    m.undo(rec)
    return err


def _in2(q, p):
    """Barycentrics of q in triangle p, in the floor's plan (x, z)."""
    (ax, az), (bx, bz), (cx, cz) = p[0][[0, 2]], p[1][[0, 2]], p[2][[0, 2]]
    det = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
    if abs(det) < 1e-12:
        return None
    l0 = ((bz - cz) * (q[0] - cx) + (cx - bx) * (q[2] - cz)) / det
    l1 = ((cz - az) * (q[0] - cx) + (ax - cx) * (q[2] - cz)) / det
    return np.array([l0, l1, 1.0 - l0 - l1])


def _ccw2(a, b, c):
    return (b[0] - a[0]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[0] - a[0])


def _incircle(a, b, c, d):
    """> 0 when d lies inside the circumcircle of a, b, c (plan view, either winding)."""
    m = np.array([[a[0] - d[0], a[2] - d[2], (a[0] - d[0]) ** 2 + (a[2] - d[2]) ** 2],
                  [b[0] - d[0], b[2] - d[2], (b[0] - d[0]) ** 2 + (b[2] - d[2]) ** 2],
                  [c[0] - d[0], c[2] - d[2], (c[0] - d[0]) ** 2 + (c[2] - d[2]) ** 2]])
    return np.linalg.det(m) * (1.0 if _ccw2(a, b, c) > 0 else -1.0)


def refloor(m, spacing=FLOOR_STEP):
    """The guard-room floor's long fan re-cut: points laid on his floor a stride apart, Delaunay in plan."""
    region = set()
    for i in range(len(m.F)):
        if m.alive[i] and not m.frozen[i]:
            n, _ = tri_normal(m.pts(i))
            if n[1] > FLOOR_UP and abs(m.pts(i)[:, 1].mean() - FLOOR_Y) < 0.35:
                region.add(i)
    bverts = set()
    for i in region:
        f = m.F[i]
        for k in range(3):
            a, b = f[k], f[(k + 1) % 3]
            if not all(j in region for j in m.edge_faces(a, b)):
                bverts.update((a, b))
    bpts = m.V[sorted(bverts)]
    lo, hi = m.V[[u for i in region for u in m.F[i]]].min(0), m.V[[u for i in region for u in m.F[i]]].max(0)
    pts, row = [], 0
    z = lo[2]
    while z <= hi[2]:
        x = lo[0] + (spacing * 0.5 if row % 2 else 0.0)
        while x <= hi[0]:
            pts.append((x, z))
            x += spacing
        z += spacing * math.sqrt(3) / 2
        row += 1
    added = 0
    for x, z in pts:
        q = np.array([x, 0.0, z])
        if np.min(np.hypot(bpts[:, 0] - x, bpts[:, 2] - z)) < spacing * 0.6:
            continue
        host = None
        for i in region:
            if m.alive[i]:
                l = _in2(q, m.pts(i))
                if l is not None and l.min() > 0.02:
                    host = (i, l)
                    break
        if host is None:
            continue
        i, l = host
        q = l @ m.pts(i)                                # on his floor
        if not all(_edge_clear(m, region, q, spacing * 0.45)):
            continue
        region |= _split(m, i, q)
        added += 1
    flips = _delaunay(m, region)
    return added, flips


def _edge_clear(m, region, q, d):
    for i in region:
        if m.alive[i]:
            for v in m.F[i]:
                yield math.hypot(m.V[v][0] - q[0], m.V[v][2] - q[2]) >= d


def _split(m, i, q):
    v = len(m.V)
    m.V = np.vstack([m.V, q])
    m.vf.append(set())
    m.moved.add(v)
    a, b, c = m.F[i]
    new = []
    for tri in ((a, b, v), (b, c, v), (c, a, v)):
        if not new:
            for u in m.F[i]:
                m.vf[u].discard(i)
            m.F[i] = list(tri)
            k = i
        else:
            k = len(m.F)
            m.F.append(list(tri))
            m.orig.append(m.orig[i])
            m.alive.append(True)
            m.frozen.append(False)
        for u in tri:
            m.vf[u].add(k)
        new.append(k)
    return set(new)


def _delaunay(m, region):
    flips = 0
    for _ in range(200):
        changed = 0
        for i in list(region):
            if not m.alive[i]:
                continue
            f = m.F[i]
            for k in range(3):
                a, b = f[k], f[(k + 1) % 3]
                fs = m.edge_faces(a, b)
                if len(fs) != 2 or not all(j in region for j in fs):
                    continue
                j = fs[0] if fs[1] == i else fs[1]
                c = [u for u in m.F[i] if u not in (a, b)][0]
                d = [u for u in m.F[j] if u not in (a, b)][0]
                if c in m.nbrs(d):
                    continue
                A, B, C, D = m.V[a], m.V[b], m.V[c], m.V[d]
                if _ccw2(C, D, A) * _ccw2(C, D, B) >= 0:     # quad not convex in plan
                    continue
                if _incircle(A, B, C, D) > 1e-9:
                    m.flip(i, j, a, b)
                    changed += 1
                    break
        flips += changed
        if not changed:
            break
    return flips


def components(m):
    par = list(range(len(m.V)))

    def find(x):
        while par[x] != x:
            par[x] = par[par[x]]
            x = par[x]
        return x
    for i, f in enumerate(m.F):
        if m.alive[i]:
            for u in f[1:]:
                par[find(u)] = find(f[0])
    groups = {}
    for i, f in enumerate(m.F):
        if m.alive[i]:
            groups.setdefault(find(f[0]), []).append(i)
    return sorted(groups.values(), key=len, reverse=True)


def write(j, b, m, at, F, path):
    P, N = [], []
    T, C = [], []
    idx, seen = [], {}

    def corner(p, n, t, c):
        k = (p.tobytes(), n.tobytes(), t.tobytes(), c.tobytes())
        if k not in seen:
            seen[k] = len(P)
            P.append(p), N.append(n), T.append(t), C.append(c)
        return seen[k]
    fn = {i: tri_normal(m.V[f])[0] for i, f in enumerate(m.F) if m.alive[i]}

    def smooth(i, v):
        """Angle-weighted normal over the facets at v that meet facet i gentler than CREASE: one stone, carved edges kept."""
        if v in m.locked:
            return fn[i]
        acc = np.zeros(3)
        for j in m.vf[v]:
            if m.alive[j] and float(fn[i] @ fn[j]) >= math.cos(math.radians(CREASE)):
                f = m.F[j]
                k = f.index(v)
                e1, e2 = m.V[f[(k + 1) % 3]] - m.V[v], m.V[f[(k + 2) % 3]] - m.V[v]
                ang = math.acos(max(-1.0, min(1.0, float(e1 @ e2) / max(np.linalg.norm(e1) * np.linalg.norm(e2), 1e-15))))
                acc += ang * fn[j]
        L = np.linalg.norm(acc)
        return acc / L if L > 1e-12 else fn[i]
    for i, f in enumerate(m.F):
        if not m.alive[i]:
            continue
        o = m.orig[i]
        if m.frozen[i]:
            for k in range(3):
                ci = F[o][k]
                idx.append(corner(at["POSITION"][ci], at["NORMAL"][ci], at["TEXCOORD_0"][ci], at["COLOR_0"][ci]))
            continue
        for v in f:
            p32 = m.V[v].astype(np.float32) if v in m.moved else m.V32[v]
            idx.append(corner(p32, smooth(i, v).astype(np.float32), uv_at(m, i, m.V[v]).astype(np.float32),
                              at["COLOR_0"][F[o][0]]))
    P, N, T, C = (np.array(x, dtype=np.float32) for x in (P, N, T, C))
    I = np.array(idx, dtype=np.uint16 if len(P) < 65536 else np.uint32)
    prim = j["meshes"][1]["primitives"][0]
    rock_acc = [prim["attributes"][k] for k in ("POSITION", "NORMAL", "TEXCOORD_0", "COLOR_0")] + [prim["indices"]]
    data = dict(zip(rock_acc, (P, N, T, C, I)))
    out = bytearray()
    for vi, bv in enumerate(j["bufferViews"]):
        ai = [k for k, a in enumerate(j["accessors"]) if a["bufferView"] == vi]
        blob = data[ai[0]].tobytes() if ai and ai[0] in data else b[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        while len(out) % 4:
            out += b"\0"
        bv["byteOffset"] = len(out)
        bv["byteLength"] = len(blob)
        out += blob
    while len(out) % 4:
        out += b"\0"
    for k, arr in data.items():
        a = j["accessors"][k]
        a["count"] = int(len(arr))
        if k == prim["indices"]:
            a["componentType"] = 5123 if arr.dtype == np.uint16 else 5125
        if "min" in a:
            a["min"] = [float(x) for x in arr.min(0)]
            a["max"] = [float(x) for x in arr.max(0)]
    j["buffers"][0]["byteLength"] = len(out)
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<III", 0x46546C67, 2, total))
        fh.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        fh.write(struct.pack("<II", len(out), 0x004E4942) + bytes(out))


def main():
    global UV, COLOR, CORNER
    tol = float(sys.argv[1]) if len(sys.argv) > 1 and __name__ == "__main__" else TOL
    j, b = read_glb(SRC)
    prim = j["meshes"][1]["primitives"][0]
    at = {k: accessor(j, b, v) for k, v in prim["attributes"].items()}
    F = accessor(j, b, prim["indices"]).astype(np.int64).reshape(-1, 3)
    UV, CORNER = at["TEXCOORD_0"], F
    COLOR = [at["COLOR_0"][f[0]].tobytes() for f in F]
    m = Mesh(at["POSITION"], F, SEAM_Y)
    comps = components(m)
    shards = [i for c in comps[1:] for i in c]
    for i in shards:
        m.alive[i] = False
        for u in m.F[i]:
            m.vf[u].discard(i)
    print("floating shards removed: %d components, %d tris" % (len(comps) - 1, len(shards)))
    print("fins merged: %d" % fins(m))
    print("edits:", repair(m, tol))
    print("fins merged after: %d" % fins(m))
    print("floor re-cut: %d points, %d flips" % refloor(m))
    global NORMAL_TOL, SMALL_TURN, SLIVER, SOFT
    NORMAL_TOL, SMALL_TURN = FOOT_TURN
    SLIVER, SOFT = FOOT_SLIVER, 2.0 * FOOT_SLIVER       # the kerb and pier feet: long fans, seen close
    print("feet:", repair(m, FOOT_TOL, lambda p: p[:, 1].mean() < FOOT_Y))
    SLIVER, SOFT = NEEDLE_ANGLE, NEEDLE_ANGLE           # last: needles anywhere above the shaft, the cracks seen close
    print("needles:", repair(m, FOOT_TOL))
    NORMAL_TOL, SMALL_TURN = STRIPE_TURN                # long blades up a pier corner: sky-lit stripes
    SLIVER, SOFT = STRIPE_ANGLE, STRIPE_ANGLE
    print("stripes:", repair(m, STRIPE_TOL, lambda p: max(np.linalg.norm(p[k] - p[k - 1]) for k in range(3)) > STRIPE_LEN))
    print("fins merged last: %d" % fins(m))
    if not os.environ.get("REPAIR_DRY"):
        write(j, b, m, at, F, DST)
        print("wrote", DST)
    return m


if __name__ == "__main__":
    main()
