"""beach_lib -- the beach's sculpt helpers (the ice map's, minus its roof): mesh accumulator, noise,
ring stitching, the --check report. Pure Python: runs without Blender."""

import math

TWO_PI = 2.0 * math.pi
UP = (0.0, 0.0, 1.0)
DOWN = (0.0, 0.0, -1.0)


def pol(bearing_deg, radius, z):
    """Game bearing (as the scene's markers) -> Blender xyz."""
    a = math.radians(-bearing_deg)
    return (radius * math.cos(a), radius * math.sin(a), z)


def bearing_of(p):
    return (-math.degrees(math.atan2(p[1], p[0]))) % 360.0


def rad_of(p):
    return math.hypot(p[0], p[1])


def lerp(a, b, t):
    return a + (b - a) * t


def lerp3(p, q, t):
    return tuple(p[k] + (q[k] - p[k]) * t for k in range(len(p)))


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def smooth(t):
    t = clamp(t)
    return t * t * (3.0 - 2.0 * t)


def ramp(x, a, b):
    """0 at a, 1 at b, smooth between (a may exceed b)."""
    if a == b:
        return 1.0 if x >= b else 0.0
    return smooth((x - a) / (b - a))


def angdiff(a, b):
    """Signed a - b in degrees, wrapped to -180..180."""
    return (a - b + 180.0) % 360.0 - 180.0


def interp(table, x):
    """Piecewise-linear lookup in a sorted [(x, y)] table, clamped at both ends."""
    if x <= table[0][0]:
        return table[0][1]
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return table[-1][1]


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def scale(a, f):
    return (a[0] * f, a[1] * f, a[2] * f)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def newell(pts):
    n = [0.0, 0.0, 0.0]
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return n


def unit(v):
    ln = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) or 1.0
    return (v[0] / ln, v[1] / ln, v[2] / ln)


# =============================================================================
# NOISE -- integer hashes, so every build on every box lands on the same floats
# =============================================================================

class Rng(object):
    """Deterministic LCG."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def f(self):
        return (self.n() >> 8) / float(0x7FFFFF)

    def u(self, a, b):
        return a + (b - a) * self.f()

    def i(self, a, b):
        return a + (self.n() >> 12) % (b - a + 1)


def h2(i, j, seed):
    """Hash of an integer lattice point -> 0..1."""
    n = (i * 374761393 + j * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFFFF) / float(0x1000000)


def vnoise(x, y, seed, px=0):
    """Smooth value noise, -1..1; px > 0 wraps x every px lattice cells."""
    i, j = math.floor(x), math.floor(y)
    fx, fy = x - i, y - j
    fx, fy = fx * fx * (3.0 - 2.0 * fx), fy * fy * (3.0 - 2.0 * fy)
    i0, i1 = (i % px, (i + 1) % px) if px else (i, i + 1)
    a, b = h2(i0, j, seed), h2(i1, j, seed)
    c, d = h2(i0, j + 1, seed), h2(i1, j + 1, seed)
    return 2.0 * (a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy) - 1.0


def fbm(x, y, seed, octaves=3, px=0):
    s, amp, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        s += amp * vnoise(x * (1 << o), y * (1 << o), seed + 17 * o, px * (1 << o) if px else 0)
        tot += amp
        amp *= 0.5
    return s / tot


def ring_noise(bearing_deg, seed, waves=((2, 1.0), (5, 0.6), (11, 0.35))):
    """Periodic 1-D noise round the ring, -1..1: whole harmonics with hashed phases."""
    a = math.radians(bearing_deg)
    s = sum(amp * math.sin(k * a + TWO_PI * h2(k, 7, seed)) for k, amp in waves)
    return s / sum(amp for _k, amp in waves)


def worley(x, y, seed, px=0, jitter=0.85):
    """Nearest two feature points on a jittered lattice: (d1, d2, (i, j) of the nearest, its hash)."""
    ci, cj = math.floor(x), math.floor(y)
    best = (9e9, None)
    second = 9e9
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            i, j = ci + di, cj + dj
            wi = i % px if px else i
            fx = i + 0.5 + jitter * (h2(wi, j, seed) - 0.5)
            fy = j + 0.5 + jitter * (h2(wi, j, seed + 911) - 0.5)
            d = math.hypot(fx - x, fy - y)
            if d < best[0]:
                second = best[0]
                best = (d, (wi, j))
            elif d < second:
                second = d
    return best[0], second, best[1], h2(best[1][0], best[1][1], seed + 5003)


# =============================================================================
# MESH
# =============================================================================

class Mesh(object):
    """Triangle accumulator: every face states where its normal must point, its material zone
    and its export chunk; vertices carry an RGBA (COLOR_0)."""

    def __init__(self):
        self.verts = []
        self.cols = []
        self.faces = []
        self.zones = []
        self.chunks = []

    def v(self, p, col=(1.0, 1.0, 1.0, 1.0)):
        self.verts.append((float(p[0]), float(p[1]), float(p[2])))
        self.cols.append(tuple(col) if len(col) == 4 else (col[0], col[1], col[2], 1.0))
        return len(self.verts) - 1

    def tri(self, a, b, c, want, zone, chunk):
        if a == b or b == c or a == c:
            return
        pts = [self.verts[a], self.verts[b], self.verts[c]]
        n = newell(pts)
        cen = tuple((pts[0][k] + pts[1][k] + pts[2][k]) / 3.0 for k in range(3))
        w = want(cen) if callable(want) else want
        if n[0] * w[0] + n[1] * w[1] + n[2] * w[2] < 0.0:
            b, c = c, b
            n = (-n[0], -n[1], -n[2])
        if callable(zone):
            zone = zone(unit(n), cen, (a, b, c))
        self.faces.append((a, b, c))
        self.zones.append(zone)
        self.chunks.append(chunk)

    def tri_as(self, a, b, c, zone, chunk):
        """A triangle wound exactly as given."""
        if a == b or b == c or a == c:
            return
        pts = [self.verts[a], self.verts[b], self.verts[c]]
        if callable(zone):
            cen = tuple((pts[0][k] + pts[1][k] + pts[2][k]) / 3.0 for k in range(3))
            zone = zone(unit(newell(pts)), cen, (a, b, c))
        self.faces.append((a, b, c))
        self.zones.append(zone)
        self.chunks.append(chunk)

    def quad(self, a, b, c, d, want, zone, chunk):
        """Split along the shorter diagonal."""
        va, vb, vc, vd = (self.verts[i] for i in (a, b, c, d))
        if math.dist(va, vc) <= math.dist(vb, vd):
            self.tri(a, b, c, want, zone, chunk)
            self.tri(a, c, d, want, zone, chunk)
        else:
            self.tri(a, b, d, want, zone, chunk)
            self.tri(b, c, d, want, zone, chunk)

    def grid(self, rows, want, zone, chunk, closed=True, skip=None):
        """Quads between consecutive rows of equal length, every one wound the way the first
        faces want (a ledge or an overhang cannot flip itself); skip(r, i) omits one."""
        n = len(rows[0])
        flip = None
        for r, (lo, hi) in enumerate(zip(rows, rows[1:])):
            for i in range(n if closed else n - 1):
                j = (i + 1) % n
                if skip is not None and skip(r, i):
                    continue
                q = (lo[i], lo[j], hi[j], hi[i])
                if flip is None:
                    pts = [self.verts[v] for v in q]
                    nrm = newell(pts)
                    cen = tuple(sum(p[k] for p in pts) / 4.0 for k in range(3))
                    w = want(cen) if callable(want) else want
                    flip = nrm[0] * w[0] + nrm[1] * w[1] + nrm[2] * w[2] < 0.0
                if flip:
                    q = (q[3], q[2], q[1], q[0])
                va, vb, vc, vd = (self.verts[v] for v in q)
                if math.dist(va, vc) <= math.dist(vb, vd):
                    self.tri_as(q[0], q[1], q[2], zone, chunk)
                    self.tri_as(q[0], q[2], q[3], zone, chunk)
                else:
                    self.tri_as(q[0], q[1], q[3], zone, chunk)
                    self.tri_as(q[1], q[2], q[3], zone, chunk)

    def stitch(self, ring_a, ring_b, want, zone, chunk):
        """Zipper two closed rings of different counts by bearing."""
        a = sorted(ring_a, key=lambda v: bearing_of(self.verts[v]))
        b = sorted(ring_b, key=lambda v: bearing_of(self.verts[v]))
        ba = [bearing_of(self.verts[v]) for v in a]
        bb = [bearing_of(self.verts[v]) for v in b]
        i = j = 0
        na, nb = len(a), len(b)
        while i < na or j < nb:
            nxt_a = ba[i + 1] if i + 1 < na else ba[0] + 360.0
            nxt_b = bb[j + 1] if j + 1 < nb else bb[0] + 360.0
            if j >= nb or (i < na and nxt_a <= nxt_b):
                self.tri(a[i % na], a[(i + 1) % na], b[j % nb], want, zone, chunk)
                i += 1
            else:
                self.tri(a[i % na], b[(j + 1) % nb], b[j % nb], want, zone, chunk)
                j += 1

    def zipper(self, a, ta, b, tb, want, zone, chunk):
        """Triangles between two open polylines, each advanced by its own parameter (ta, tb rising)."""
        i = j = 0
        while i < len(a) - 1 or j < len(b) - 1:
            if j >= len(b) - 1 or (i < len(a) - 1 and ta[i + 1] <= tb[j + 1]):
                self.tri(a[i], a[i + 1], b[j], want, zone, chunk)
                i += 1
            else:
                self.tri(a[i], b[j + 1], b[j], want, zone, chunk)
                j += 1

    def spike(self, fi, tip, zone, inset=0.55, col=(1.0, 1.0, 1.0, 1.0)):
        """Grow a spike out of face fi: the face keeps a rim, an inset triangle is drawn out to tip."""
        a, b, c = self.faces[fi]
        chunk, host = self.chunks[fi], self.zones[fi]
        pa, pb, pc = self.verts[a], self.verts[b], self.verts[c]
        cen = tuple((pa[k] + pb[k] + pc[k]) / 3.0 for k in range(3))
        ia, ib, ic = (self.v(lerp3(p, cen, inset), self.cols[v]) for p, v in ((pa, a), (pb, b), (pc, c)))
        t = self.v(tip, col)
        self.faces[fi] = (a, b, ib)
        for tri, z in (((a, ib, ia), host), ((b, c, ic), host), ((b, ic, ib), host), ((c, a, ia), host),
                       ((c, ia, ic), host), ((ia, ib, t), zone), ((ib, ic, t), zone), ((ic, ia, t), zone)):
            self.faces.append(tri)
            self.zones.append(z)
            self.chunks.append(chunk)

    def used(self):
        """(verts, cols, faces) with unreferenced vertices dropped."""
        remap, verts, cols, faces = {}, [], [], []
        for f in self.faces:
            g = []
            for vi in f:
                if vi not in remap:
                    remap[vi] = len(verts)
                    verts.append(self.verts[vi])
                    cols.append(self.cols[vi])
                g.append(remap[vi])
            faces.append(tuple(g))
        return verts, cols, faces


# =============================================================================
# PROOF -- pure Python, for --check
# =============================================================================

def report(m, name):
    """Components after welding, duplicate positions, degenerate faces, open edges."""
    verts, _cols, faces = m.used()
    key = {}
    weld = [key.setdefault((round(x, 5), round(y, 5), round(z, 5)), i) for i, (x, y, z) in enumerate(verts)]
    parent = list(range(len(verts)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    degen, edges = 0, {}
    for f in faces:
        w = [weld[i] for i in f]
        n = newell([verts[i] for i in f])
        if math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) < 1e-8:
            degen += 1
        for k in range(3):
            parent[find(w[k])] = find(w[(k + 1) % 3])
            e = (min(w[k], w[(k + 1) % 3]), max(w[k], w[(k + 1) % 3]))
            edges[e] = edges.get(e, 0) + 1
    comps = len({find(weld[i]) for f in faces for i in f})
    dup = len(verts) - len(key)
    opn = sum(1 for c in edges.values() if c == 1)
    multi = sum(1 for c in edges.values() if c > 2)
    zones = {}
    for z in m.zones:
        zones[z] = zones.get(z, 0) + 1
    print("%s tris=%d verts=%d components=%d duplicate_positions=%d degenerate=%d open_edges=%d nonmanifold=%d zones=%s"
          % (name, len(faces), len(verts), comps, dup, degen, opn, multi, zones))
    return comps, dup, degen
