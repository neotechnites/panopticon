"""rock_bars -- a cave wall with slots cut through it, across the lane.

Ryan: "have an agent remodel the gate for the hell map, so that its less like
carved bars and more like a cave wall with slots through it."

So the ROCK is the subject and the gaps are cut into it. There is no sill, no
lintel and no row of uprights: one mass of the map's own hell rock spans the
lane from the lip to the outer wall, its two faces swelling and thinning on their own (a
half-thickness of 0.13 .. 0.58 m, heaviest at the haunch where it meets the
floor and under the brow at the crest), its top edge broken rather than sawn,
and nine tall slots are cut clean through it. No two slots are alike: each has
its own width, its own lean, its own kink, its own taper and its own head and
foot, and the rock left between them runs from 0.5 m to 1.7 m across, so the
screen has no rhythm to read off. Every row of the wall's lattice carries its
own x and z wobble, which is what makes a slot's edge ragged instead of milled.

THE GUARANTEE IS UNCHANGED. No opening is wider than 0.48 m at any height, so
a body (0.8 m across) cannot pass and a rifle round and a sight line can.
THE FIT (Ryan: "it just sticks right out the side and off the cliff"): built at
world scale, its inner end stops on the cliff lip, never over the drop, and its
outer end grows out of the lane's outer wall in a flare and runs on buried in
it; it fillets into the floor and the ceiling. Origin the base centre, z=0 the
ground. forest_bars and marble_bars keep the old 10.6 m envelope; they are not this.

TEXTURE: map 1's own rock sheets through lib/texel.py, not an atlas (Ryan: "the
texturing on the gate is bad, you seemed to fix it for the maps generally").
Same painters, same seeds, same tx.MPT = 0.05 m per texel as map_base's walls,
world-projected in the model's own frame ("box"), so marks run across face
edges instead of each face carrying its own cut-off window. The RockBars node
is unscaled, so the texels are 0.05 m in the world, as map 1's walls are.

The screen spans Blender X (Godot X), thickness along Blender Y (Godot Z).
Blender +Z -> Godot +Y, +X -> +X, +Y -> -Z.

Contract: one mesh "RockBars" (two sheets: rock and shade), plus
"RockBarsCollision" -- one box per rock column plus a sill and a lintel,
shipped as a `-colonly` node.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import mdl  # noqa: E402
import texel as tx  # noqa: E402

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "rock_bars"
OBJECT_NAME = "RockBars"
COLLIDER_NAME = "RockBarsCollision-colonly"

# Ryan: "the model you made just sticks right out the side and off the cliff."
# Built at world scale now (the node is unscaled), spanning r 46.58 .. 58.50 on bearing 350.
HALF_W = 5.96           # inner end on the cliff lip (map_base's is r 46.49 .. 46.57 here) ...
X_WALL = 4.55           # ... the lane's outer rock wall face (r 57.09); past it the rock is buried
HEIGHT = 8.5
FOOT = -0.25            # the foot is sunk under the deck, so no seam line where it meets it

# The wall's lattice. One row list for the whole wall; every line wobbles its
# own z at every row, so no band edge is straight.
ROWS = [0.0, 0.62, 1.35, 2.10, 2.85, 3.60, 4.35, 5.10, 5.85, 6.60, 7.45, 8.50]
Z_JITTER = 0.24         # a row's height wobble, line by line
X_JITTER = 0.065        # a solid line's sideways wobble, row by row
# The gallery is a CUTOUT with a rock ceiling CEIL_H 8.5 m over the deck
# (map_base_build.CEIL_H), which is exactly this wall's height: so the TOP row
# is dead flat at 8.5 and buried in that ceiling, and the broken-rock read
# comes from the row under it instead. A knocked-out crest here would be a
# 0.5 m letterbox of daylight over the gate.
TOP_JITTER = 0.28       # how far the last band under the ceiling breaks up

SLOTS = 8
# World metres: the old slots x the old node's 1.30 X scale, so they read as they did.
SLOT_W = (0.30, 0.48)   # a slot's base width at its widest
SLOT_MAX = 0.48         # hard ceiling on any opening, at any height
SLOT_MIN = 0.09         # how far a slot may pinch before it is called shut
SLOT_LEAN = 0.22        # drift of a slot's centre from foot to head
SLOT_KINK = 0.13        # its own wander across the lane on the way up
SLOT_JITTER = 0.065     # per-row raggedness of the cut edge
SLOT_TAPER = 0.22       # how much of its width a tapering slot sheds
ROCK_MIN = 0.65         # the least rock that may be left between two slots: below
                        # this a column stops being a mass and starts being a bar
ROCK_SKEW = 3.0         # how hard the spare width piles onto a few columns, so the
                        # wall carries two or three real masses and not nine equals
ROCK_SPLIT = 1.50       # a rock column this wide or wider gets two lattice lines

# Slot heads and feet as row indices: nine different pairs, dealt by the seed.
SLOT_SPANS = [(1, 10), (1, 9), (2, 10), (1, 8), (3, 10), (1, 10), (2, 7), (1, 9), (4, 10)]

# The wall's own mass: half-thickness at a point, per face.
T_BASE = 0.185
T_MIN, T_MAX = 0.115, 0.62
HAUNCH, HAUNCH_Z = 0.28, 2.30      # it thickens into the floor
BROW, BROW_Z, BROW_H = 0.34, 6.30, 2.20   # and fillets into the ceiling
FLARE, FLARE_L = 0.80, 2.60        # it grows out of the outer wall: extra half-thickness, reach
FLARE_STEP = 0.45                  # lattice spacing through the flare, so it curves, not facets
PROW_MIN, PROW_L = 0.55, 0.70      # at the lip it rounds off to this of its thickness, over this
END_RAG = 0.15                     # the lip end is broken back by up to this, never out past it
PHASE_FRONT, PHASE_BACK = 0.0, 2.70       # the two faces are not each other

SHADE_T = 0.150         # a face thinner than this reads as recessed: the shade sheet
COLL_HD_MIN = 0.16      # a collider box is as deep as the rock it stands for, and
                        # never shallower than this

SEED = 7130951

# ---- texture: map 1's rock sheets, lib/texel.py, no atlas -------------------
TEX_PREFIX = "map_base"          # so Ryan's map 1 rock PNGs, if he drops them
TEX_DIR = "textures"             # in, dress the gate and the map together
USE_TEXTURE_FILES = True
ROCK_ROUGHNESS = 0.95


# =============================================================================
# THE ROCK SHEETS -- map_base_build.py's painters, same seeds, same density
# =============================================================================

_K = (tx.TILE * tx.MPT / 8.0) ** 2      # sheet area / the old atlas cell's: 2.56
_S = 0.125 / tx.MPT                     # old texel / new texel: 2.5


def _n(count):
    return int(round(count * _K))


def _sz(texels):
    return max(1, int(round(texels * _S)))


def _specks(c, r, count, size, rgb, glow):
    for _ in range(_n(count)):
        x, y = r.i(0, c.w - 1), r.i(0, c.h - 1)
        c.rect(x, y, x + size, y + size, rgb, glow)


def _sheet_rock(c, r, s):
    tx.fill(c, r, c.box, [(74, 27, 25), (58, 20, 19), (90, 35, 30), (46, 16, 16)])
    tx.shatter(c, r, c.box, [(96, 40, 33), (48, 16, 16), (110, 48, 38)], _n(20), _sz(6), _sz(15))
    tx.shatter(c, r, c.box, [(32, 11, 12), (118, 56, 43)], _n(12), _sz(4), _sz(9))
    _specks(c, r, 6, _sz(2), (172, 44, 12), (114, 22, 3))


def _sheet_shade(c, r, s):
    tx.fill(c, r, c.box, [(34, 12, 12), (24, 8, 9), (44, 17, 15), (17, 6, 7)])
    tx.shatter(c, r, c.box, [(42, 16, 15), (10, 3, 4)], _n(20), _sz(4), _sz(11))
    _specks(c, r, 4, _sz(2), (140, 34, 9), (92, 16, 2))


# Two sheets and no more. map_base has a third, `ember`, for rock split open by
# brimstone, and five glowing reveal faces did look good in here -- but the Ring
# measures materials=16 on main against test_map_draw_budgets' ceiling of 18, so
# a third material for ten triangles would spend the map's last slot on a detail
# the rock sheet's own emissive specks already carry.
SHEETS = {
    "rock": tx.Sheet("rock", _sheet_rock, mode="box", roughness=ROCK_ROUGHNESS, seed=1),
    "shade": tx.Sheet("shade", _sheet_shade, mode="box", roughness=ROCK_ROUGHNESS, seed=2),
}
MAT_NAMES = {"rock": "HellRock", "shade": "HellShade"}


# =============================================================================
# GEOMETRY HELPERS -- winding is checked, never assumed
# =============================================================================

class _Rng(object):
    """Seeded LCG so the model is byte-identical every rebuild."""

    def __init__(self, seed):
        self.s = seed & 0x7FFFFFFF

    def n(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def bits(self):
        return self.n() >> 12          # low bits are short-period

    def f(self):
        return self.n() / float(0x7FFFFFFF)

    def sf(self):
        return self.f() * 2.0 - 1.0

    def u(self, a, b):
        return a + (b - a) * self.f()

    def i(self, a, b):
        return a + self.bits() % (b - a + 1)

    def pick(self, seq):
        return seq[self.bits() % len(seq)]


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
    """Vertex/face accumulator; every face states which way its normal must point."""

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
        if len(idx) == 4:              # split: the corners are not coplanar
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

    def box(self, lo, hi, zone):
        """Axis-aligned box, 12 tris. The collider shape."""
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        p = [self.v(c) for c in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                                 (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
        self.quad(p[0], p[1], p[2], p[3], (0, 0, -1), zone)
        self.quad(p[4], p[5], p[6], p[7], (0, 0, 1), zone)
        self.quad(p[0], p[1], p[5], p[4], (0, -1, 0), zone)
        self.quad(p[2], p[3], p[7], p[6], (0, 1, 0), zone)
        self.quad(p[1], p[2], p[6], p[5], (1, 0, 0), zone)
        self.quad(p[3], p[0], p[4], p[7], (-1, 0, 0), zone)

    def object(self, name):
        return mdl.mesh(name, self.verts, self.faces)


# =============================================================================
# THE WALL
# =============================================================================

def _thickness(x, z, phase):
    """Half-thickness of the wall at a point on one of its faces. Four drifting
    waves for the rock's own swell, a haunch into the floor and a brow at the
    crest; the two faces run on different phases so neither is the other's
    mirror."""
    v = T_BASE
    v += 0.104 * math.sin(0.62 * x + phase) * math.cos(0.47 * z + 1.7 * phase)
    v += 0.080 * math.sin(1.21 * x - 0.83 * z + 2.4 + phase)
    v += 0.056 * math.cos(0.95 * z + 0.70 * x - 1.1 + 2.0 * phase)
    v += 0.036 * math.sin(2.35 * x + 1.90 * z + 3.0 * phase)
    v += HAUNCH * max(0.0, 1.0 - z / HAUNCH_Z) ** 2
    v += BROW * max(0.0, (z - BROW_Z) / BROW_H) ** 2
    v = min(T_MAX, max(T_MIN, v))
    s = min(1.0, max(0.0, 1.0 - (X_WALL - x) / FLARE_L))
    e = min(1.0, max(0.0, (x + HALF_W) / PROW_L))
    return (v + FLARE * s * s) * (PROW_MIN + (1.0 - PROW_MIN) * math.sqrt(e))


def _taper(kind, u):
    if kind == "up":
        return 1.0 - SLOT_TAPER * u
    if kind == "down":
        return 1.0 - SLOT_TAPER * (1.0 - u)
    if kind == "waist":
        return 1.0 - SLOT_TAPER * math.sin(math.pi * u)
    if kind == "belly":
        return 1.0 - SLOT_TAPER + SLOT_TAPER * math.sin(math.pi * u)
    return 1.0


def _plan(r):
    """Slot widths and spans, and the rock columns between them, normalised so
    the lattice fills the lane from the lip to the outer wall; the last column
    runs on into the wall. Returns the slots and the lane count of each column."""
    spans = list(SLOT_SPANS)
    for k in range(len(spans) - 1, 0, -1):          # deal them, seed's choice
        j = r.i(0, k)
        spans[k], spans[j] = spans[j], spans[k]
    slots = []
    for k in range(SLOTS):
        b, t = spans[k]
        slots.append({
            "w": r.u(SLOT_W[0], SLOT_W[1]),
            "b": b, "t": t,
            "lean": r.sf() * SLOT_LEAN,
            "kink": r.sf() * SLOT_KINK,
            "freq": r.u(0.7, 2.1),
            "phase": r.f() * 2.0 * math.pi,
            "kind": r.pick(["none", "up", "down", "waist", "belly", "up", "belly"]),
        })
    w = [r.f() ** ROCK_SKEW for _ in range(SLOTS + 1)]
    free = X_WALL + HALF_W - sum(s["w"] for s in slots)
    spare = free - (SLOTS + 1) * ROCK_MIN
    if spare <= 0.0:
        raise ValueError("no room for %d slots and %d columns of %.2f m"
                         % (SLOTS, SLOTS + 1, ROCK_MIN))
    cols = [ROCK_MIN + spare * x / sum(w) for x in w]
    lanes = [2 if c >= ROCK_SPLIT else 1 for c in cols]
    lanes[0] = 2                                    # a line for the prow to round over
    lanes[-1] = max(lanes[-1], int(math.ceil((cols[-1] + HALF_W - X_WALL) / FLARE_STEP)))
    x = -HALF_W
    for g in range(SLOTS + 1):
        x += cols[g]
        if g < SLOTS:
            slots[g]["x0"] = x
            x += slots[g]["w"]
            slots[g]["x1"] = x
    return slots, cols, lanes


def _lattice(r, slots, cols, lanes):
    """X[i][j] and Z[i][j] for every lattice line and row, plus which lane each
    slot owns. Built row by row: the slots claim their own edges first, then
    each rock column shares out what is left between them, so the row is
    monotone by construction and no slot can be widened by a neighbour."""
    nz = len(ROWS)
    nx = 1 + SLOTS + sum(lanes)
    X = [[0.0] * nz for _ in range(nx)]
    cell_of = []
    for j in range(nz):
        edges = []
        for k, s in enumerate(slots):
            zb, zt = ROWS[s["b"]], ROWS[s["t"]]
            u = min(1.0, max(0.0, (ROWS[j] - zb) / (zt - zb)))
            c = 0.5 * (s["x0"] + s["x1"])
            c += s["lean"] * (u - 0.5)
            c += s["kink"] * math.sin(math.pi * s["freq"] * u + s["phase"])
            c += r.sf() * SLOT_JITTER
            w = s["w"] * _taper(s["kind"], u) * (1.0 + r.sf() * 0.20)
            w = min(SLOT_MAX, max(SLOT_MIN, w))
            edges.append((c - 0.5 * w, c + 0.5 * w))
        i = 0
        X[i][j] = -HALF_W
        for g in range(SLOTS + 1):
            a = -HALF_W if g == 0 else edges[g - 1][1]
            b = HALF_W if g == SLOTS else edges[g][0]
            step = (b - a) / lanes[g]
            for p in range(1, lanes[g]):
                i += 1
                X[i][j] = a + step * p + r.sf() * min(X_JITTER, 0.30 * step)
            if g < SLOTS:
                i += 1
                X[i][j] = edges[g][0]
                if j == 0:
                    cell_of.append(i)
                i += 1
                X[i][j] = edges[g][1]
        i += 1
        X[i][j] = HALF_W
    Z = [[0.0] * nz for _ in range(nx)]
    for i in range(nx):
        for j in range(nz):
            if j == 0:
                Z[i][j] = FOOT                       # under the floor: no daylight, no seam
            elif j == nz - 1:
                Z[i][j] = HEIGHT                     # the ceiling: none over it either
            else:
                Z[i][j] = ROWS[j] + r.sf() * (TOP_JITTER if j == nz - 2 else Z_JITTER)
    for j in range(1, nz - 1):                     # the lip end, broken back off the drop
        X[0][j] = -HALF_W + END_RAG * r.f()
    return X, Z, cell_of


def _wall(r):
    """One mass of rock with the slots cut clean through it."""
    slots, cols, lanes = _plan(r)
    X, Z, cell_of = _lattice(r, slots, cols, lanes)
    nx, nz = len(X), len(ROWS)

    TH = {}
    for side in (-1, 1):
        ph = PHASE_FRONT if side < 0 else PHASE_BACK
        for i in range(nx):
            for j in range(nz):
                TH[(side, i, j)] = _thickness(X[i][j], Z[i][j], ph)
    m = _Mesh()
    idx = {}
    for side in (-1, 1):
        for i in range(nx):
            for j in range(nz):
                idx[(side, i, j)] = m.v((X[i][j], side * TH[(side, i, j)], Z[i][j]))

    hole = {}
    for k, s in enumerate(slots):
        for j in range(s["b"], s["t"]):
            hole[(cell_of[k], j)] = k

    def th(i, j):
        return TH[(-1, i, j)]

    for i in range(nx - 1):                     # the two faces
        for j in range(nz - 1):
            if (i, j) in hole:
                continue
            mean = 0.25 * (th(i, j) + th(i + 1, j) + th(i, j + 1) + th(i + 1, j + 1))
            zone = "shade" if mean < SHADE_T else "rock"
            for side, want in ((-1, (0, -1, 0)), (1, (0, 1, 0))):
                m.quad(idx[(side, i, j)], idx[(side, i + 1, j)],
                       idx[(side, i + 1, j + 1)], idx[(side, i, j + 1)], want, zone)

    reveals = []                                # the cut sides of every slot
    for k, s in enumerate(slots):
        i, b, t = cell_of[k], s["b"], s["t"]
        for j in range(b, t):
            reveals.append((i, j, 1))           # left edge, facing into the slot
            reveals.append((i + 1, j, -1))
        for row, want in ((b, (0, 0, 1)), (t, (0, 0, -1))):
            m.quad(idx[(-1, i, row)], idx[(-1, i + 1, row)],
                   idx[(1, i + 1, row)], idx[(1, i, row)], want, "shade")
    for i, j, sgn in reveals:
        m.quad(idx[(-1, i, j)], idx[(-1, i, j + 1)], idx[(1, i, j + 1)], idx[(1, i, j)],
               (sgn, 0, 0), "shade")

    # Foot (under the deck), crest (in the ceiling) and the far end (in the outer wall) are
    # never seen: only the lip column keeps its caps, where the rock meets the drop.
    m.quad(idx[(-1, 0, 0)], idx[(-1, 1, 0)], idx[(1, 1, 0)], idx[(1, 0, 0)], (0, 0, -1), "shade")
    m.quad(idx[(-1, 0, nz - 1)], idx[(-1, 1, nz - 1)], idx[(1, 1, nz - 1)], idx[(1, 0, nz - 1)],
           (0, 0, 1), "rock")
    for j in range(nz - 1):
        m.quad(idx[(-1, 0, j)], idx[(-1, 0, j + 1)], idx[(1, 0, j + 1)], idx[(1, 0, j)],
               (-1, 0, 0), "rock")
    return m, slots, X, Z, cell_of, lanes, TH


def _collider(slots, X, Z, cell_of, TH):
    """One box per rock column, floor to ceiling, plus a sill under the lowest
    slot foot and a lintel over the highest slot head. The slot lanes are left
    OPEN, which is what lets a round and a sight line through what a body
    cannot pass.

    EACH BOX IS AS DEEP AS THE ROCK IT STANDS FOR, not as deep as the wall's
    deepest point. The wall swells and thins; one blanket half-depth would put
    a metre of invisible stone across the lane where the rock is a third of
    that, which is a footprint the lane can feel and the eye cannot check."""
    c = _Mesh()
    nx = len(X)
    ends = []
    for g in range(len(slots) + 1):
        lo = 0 if g == 0 else cell_of[g - 1] + 1
        hi = cell_of[g] if g < len(slots) else nx - 1
        a = -HALF_W if g == 0 else max(X[cell_of[g - 1] + 1])
        b = HALF_W if g == len(slots) else min(X[cell_of[g]])
        ends.append((a, b, lo, hi))

    def depth(lo, hi, j0=0, j1=None):
        j1 = len(ROWS) - 1 if j1 is None else j1
        return max(COLL_HD_MIN,
                   max(TH[(side, i, j)] for side in (-1, 1)
                       for i in range(lo, hi + 1) for j in range(j0, j1 + 1)))

    for a, b, lo, hi in ends[:-1]:
        d = depth(lo, hi)
        c.box((a, -d, 0.0), (b, d, HEIGHT), "rock")
    a, _, lo, hi = ends[-1]                         # the flare: a box per lane, so it follows
    for i in range(lo, hi):
        x0 = a if i == lo else min(X[i])
        x1 = HALF_W if i == hi - 1 else max(X[i + 1])
        d = depth(i, i + 1)
        c.box((x0, -d, 0.0), (x1, d, HEIGHT), "rock")
    nbox = len(ends) - 1 + hi - lo
    s0, s1 = cell_of[0], cell_of[-1] + 1           # the sill and lintel span the slots only
    foot = min(min(Z[cell_of[k]][s["b"]], Z[cell_of[k] + 1][s["b"]])
               for k, s in enumerate(slots))
    head = max(max(Z[cell_of[k]][s["t"]], Z[cell_of[k] + 1][s["t"]])
               for k, s in enumerate(slots))
    d = depth(s0, s1, 0, 1)
    c.box((min(X[s0]), -d, 0.0), (max(X[s1]), d, foot), "rock")
    d = depth(s0, s1, len(ROWS) - 2, len(ROWS) - 1)
    c.box((min(X[s0]), -d, head), (max(X[s1]), d, HEIGHT), "rock")
    return c, nbox + 2, foot, head


def _measure(slots, X, cell_of):
    """The widest opening the lattice makes, at any row of any slot."""
    worst = 0.0
    for k in range(len(slots)):
        i = cell_of[k]
        for j in range(len(ROWS)):
            worst = max(worst, X[i + 1][j] - X[i][j])
    return worst


# =============================================================================
# BUILD
# =============================================================================

def _finish(wall, coll):
    ob = wall.object(OBJECT_NAME)
    classes = list(wall.zones)
    tx.unwrap(ob, classes, SHEETS, seed=1)
    mats = tx.materials(TEX_PREFIX, SHEETS, use_files=USE_TEXTURE_FILES,
                        tex_dir=os.path.join(os.path.dirname(os.path.abspath(__file__)), TEX_DIR),
                        names=MAT_NAMES)
    for mat in mats.values():
        mat.diffuse_color = (0.13, 0.04, 0.04, 1.0)
    order = tx.finish(ob, classes, mats)
    tx.report(SHEETS)
    coll_ob = coll.object(COLLIDER_NAME)     # Godot: StaticBody3D + ConcavePolygonShape3D
    coll_ob.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d surfaces=%d order=%s"
          % (len(ob.data.polygons), len(coll_ob.data.polygons), len(ob.data.materials),
             ",".join(order)))
    return [ob, coll_ob]


def build():
    r = _Rng(SEED)
    wall, slots, X, Z, cell_of, lanes, TH = _wall(r)
    coll, nbox, foot, head = _collider(slots, X, Z, cell_of, TH)
    cols = [(-HALF_W if g == 0 else max(X[cell_of[g - 1] + 1]))
            for g in range(len(slots) + 1)]
    cols = [(HALF_W if g == len(slots) else min(X[cell_of[g]]))
            - (-HALF_W if g == 0 else max(X[cell_of[g - 1] + 1]))
            for g in range(len(slots) + 1)]
    objects = _finish(wall, coll)
    widest = _measure(slots, X, cell_of)
    lo = min(min(col) for col in X)
    hi = max(max(col) for col in X)
    top = max(max(col) for col in Z)
    print("MDL STATS width=%.2f height=%.2f slots=%d widest_gap=%.3f lanes=%d boxes=%d"
          % (hi - lo, top, SLOTS, widest, len(X) - 1, nbox))
    slot_th = max(TH[(-1, cell_of[k], (s["b"] + s["t"]) // 2)]
                  + TH[(1, cell_of[k], (s["b"] + s["t"]) // 2)]
                  for k, s in enumerate(slots))
    print("MDL STATS columns=%s" % ",".join("%.2f" % c for c in cols))
    cd = sorted(set(round(2.0 * abs(v[1]), 2) for v in coll.verts))
    print("MDL STATS sill_to=%.2f lintel_from=%.2f depth=%.2f slot_depth=%.2f "
          "coll_depth=%s mpt=%.4f"
          % (foot, head, 2.0 * max(TH.values()), slot_th,
             ",".join("%.2f" % d for d in cd), tx.MPT))
    for k, s in enumerate(slots):
        print("MDL STATS slot%d x=%.2f w=%.3f z=%.2f..%.2f kind=%s"
              % (k, 0.5 * (s["x0"] + s["x1"]), s["w"], ROWS[s["b"]], ROWS[s["t"]], s["kind"]))
    return objects


if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=0.0)
