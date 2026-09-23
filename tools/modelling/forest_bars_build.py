"""forest_bars -- Map 3's start/finish barrier: a stand of living saplings and
young trunks that have grown up across the lane.

Not a gate. There is no frame, no post, no lintel, no rail, no cut end and
nothing that reads as carpentry. Twenty-three stems rise straight out of the
earth, each with a root flare of buttress roots at its foot; each leans, bends
and crosses its neighbours on its own; thin whippy shoots stand between the
thick ones; eleven of the tall stems fork high up and nine side limbs arc out
and tangle. Leaves sit only where a real stand would carry them -- on a few
limb ends and a few short stems -- never as a hedge.

Every cross-section is a 5-, 6-, 7- or 8-gon with a wobbled radius per ring, so
no silhouette edge reads as a sawn plank.

The stand still blocks. `_gaps()` samples 320 heights through the band a body
could ever be in -- z 0.05..3.60, the 1.11 m jump apex plus a 1.8 m capsule
plus 0.7 m of margin -- and proves no clearance there exceeds 0.38 m, the lane
walls included. Above that band nothing can pass, so it is held to thicket
density instead.

10.6 m across (Blender X), 8.5 m tall, 1.2 m through the lane (Blender Y).
ORIGIN IS THE BASE CENTRE: z = 0 is the ground. Blender +X -> Godot +X,
+Z -> Godot +Y, +Y -> Godot -Z, so the scene drops it in where rock_bars.glb
goes and forest.tscn needs no change.

ONE CONTIGUOUS mesh (ForestBars), one surface per material class. What holds it
together is what holds a real stand together: a root plate, buried below
z = -0.04 and never visible, that every ground stem is socketed into. Forks,
limbs, roots and leaf clumps grow out of sockets in what carries them.

Textures: one tiling sheet per class (lib/texel.py, SHEETS below), exactly as
forest_build.py does it, and from forest_build's OWN painters and seeds -- so
`forest_bark`, `forest_leaf` and `forest_root` here are pixel-for-pixel the
sheets the forest's ground and trunks are wearing, at texel.MPT = 0.05 m per
texel. The prefix is therefore "forest", not "forest_bars": these are not this
prop's sheets, they are the forest's, and a bar leaning against a trunk has to
show the same grain at the same size. This replaces the old per-face atlas
window (`ft.unwrap` + `ft.atlas_material`), which gave every face its own
random patch of a 256 px atlas cell stretched to fit -- the reason the stand
read as cut off and smeared close up.

The projection is `mode="box"`, not the forest's "cyl". The forest's ground is
authored in WORLD coordinates and closes round a ring, so its arc length can be
divided into a whole number of repeats. This prop is authored in LOCAL
coordinates with its origin at the base centre and is placed on the lane by the
scene; there is no ring here for "cyl" to close round, and measuring an arc
about the prop's own origin would swirl the bark round a centre that is inside
the stand. A world box projection keeps every texel square on whichever axis a
face points at, which is what a stem wants.

    tools/modelling/model build forest_bars --views front,threequarter
    python3 tools/modelling/forest_bars_build.py --check
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
import texel as tx  # noqa: E402  one tiling sheet per class, world-projected
if bpy is not None:
    import mdl  # noqa: E402

import forest_tree_build as ft  # noqa: E402  the shared library: rng, mesh, atlas, tubes
import forest_build as fb  # noqa: E402  _ptube, the SHEET PAINTERS, and the forest for the in-scene shot

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "forest_bars"
OBJECT_NAME = "ForestBars"
COLLIDER_NAME = "ForestBarsCollision-boxcol"
FACING_YAW = 0.0

HALF_W = 5.3                # 10.6 m across the lane, Blender X
HEIGHT = 8.5
HALF_T = 0.60               # the stand is 1.2 m through the lane
BEARING = 353.0             # where forest.tscn puts the barrier
SEED = 3530417

ROOT_TOP_Z = -0.04          # a ground stem's foot: the root plate's top
WOB = 0.10                  # per-ring radius wobble; the proof subtracts it

# The two bands the stand is proved over. A body can be no higher than its
# jump apex (v^2/2g = 1.11 m) plus its 1.8 m capsule, so 2.91 m is the top of
# anywhere a body could pass; BODY carries 0.7 m of margin over that and is
# the gate. Above it nothing passes, so UPPER is only about looking like wood.
BODY = (0.05, 3.60, 0.38)          # (lo, hi, limit) -- the gate
UPPER = (3.60, 8.20, 0.0)          # measured and printed, never a gate: nothing
                                   # can pass up here, so its widest clearance
                                   # is a canopy number, not a way through
PROOF_LEVELS = 320                 # sample heights per band

PLATE_SIDES = 5             # buried: it never has to be round
PLATE_R = 0.40
PLATE_Z = -0.369            # centre; crown at -0.045, so none of it is above ground
PLATE_PAD = 3.00            # a foot segment is this much longer than its ring
FOOT_MAX = 0.28             # the widest ring the plate can carry
FOOT_FLAT = 0.20            # the foot ring is an oval: narrow along the stand,
                            # full width through it, so the plate can carry a
                            # thick stem without stealing its neighbour's room

FLARE_ON = 0.100            # stems thicker than this get buttress roots
                            # (a whip has no buttress: it is a whip)
FLARE_N = (2, 3)
FOOT_H = 0.52               # a ground stem's second path point is lifted to here,
                            # so its foot segment is tall enough for the buttress
                            # roots to arch out of it in plain sight

CLUMP_WOB = 0.20

WELDS = []                  # (tag, margin): how far inside its patch a socket ring sits
INFO = {}


def plate_y(x):
    """Where a ground stem's foot sits in y: the buried root plate's centre
    line. Deterministic -- the stems are laid out on the same curve."""
    return 0.13 * math.sin(0.62 * x + 0.7) + 0.07 * math.sin(1.9 * x - 2.1)


def point_at(path, t):
    n = len(path) - 1
    x = max(0.0, min(1.0, t)) * n
    k = min(n - 1, int(math.floor(x)))
    f = x - k
    a, b = path[k], path[k + 1]
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f)


def radius_at(radii, t):
    n = len(radii) - 1
    x = max(0.0, min(1.0, t)) * n
    k = min(n - 1, int(math.floor(x)))
    f = x - k
    return radii[k] + (radii[k + 1] - radii[k]) * f


# =============================================================================
# THE STAND -- pure layout: every strand's centre line and radius table
# =============================================================================
# ---- the ground stems: 23 saplings and young trunks out of the earth

NOMINAL_R = []          # per-stem nominal radius, for the proof harness

N = 23
X_LO, X_HI = -5.06, 5.06
GAP_MIN, GAP_MAX = 0.2205, 0.95
# The gate samples the whole body band, measures IN PLAN (so the y wander
# widens a gap as surely as the x spacing does) and takes radii at 0.9 of
# nominal for the tube wobble.  The foot solve works to exactly that metric.
BODY_LO, BODY_HI = 0.05, 3.60
ST_LEVELS = tuple(BODY_LO + (BODY_HI - BODY_LO) * k / 119.0 for k in range(120))
ST_WOBBLE = 0.90                      # the gate's radius factor
WALL = 0.28                        # what a stem beside the lane wall must hold
CROSS_LO = 3.0                     # a crossing only counts between these
CROSS_HI = 7.0                     # heights, and only this close in plan
CROSS_NEAR = 0.25
X_REACH = 5.26                     # no stem axis may swing past this
PT_MAX = 205                       # the whole stand's path-point ceiling
BOW_DEP = 0.62                     # bend the eye reads: departure from the chord
CAPACITY = []                      # [sum lower bounds, sum upper, span]
BEST = []                          # the least bad stand seen, if none is clean
WHY = []                           # why an attempt was thrown away
TARGET = 0.312          # clearance budget the foot solve works to
HARD = 0.330            # what no stem-stem clearance may exceed
EDGE_BEND = 0.105       # bend cap on the two wall stems (they must hug)
Y_REACH = 0.26          # max |dy|, so plate_y + wander stays inside HALF_T


# =============================================================================
# PARTS
# =============================================================================

def stem_radii(rng, nom, ts, taper_p, tip_r):
    """Radii for one stem, base to tip.  ts: list of normalized heights,
    len 9..12, ts[0]=0.0, ts[-1]=1.0, strictly increasing.  Returns a list
    of len(ts) floats."""
    n = len(ts)
    last = n - 1
    out = [0.0] * n
    # foot: the root flare, then the collar just above it
    out[0] = nom * rng.u(2.0, 2.7)
    out[1] = nom * rng.u(1.26, 1.34)
    # power taper measured from ts[1], so the flare pair is not double-counted
    span = 1.0 - ts[1]
    for k in range(2, n):
        out[k] = tip_r + (nom - tip_r) * ((1.0 - ts[k]) / span) ** taper_p

    # one or two swellings: a knot or an old branch scar, fattest at the
    # chosen point and half the excess either side of it
    cand = list(range(2, last - 1))
    for _ in range(rng.i(1, 2)):
        if not cand:
            break
        i = rng.pick(cand)
        cand.remove(i)
        f = rng.u(1.10, 1.22)
        h = 1.0 + (f - 1.0) * 0.5
        out[i] *= f
        for j in (i - 1, i + 1):
            if j >= 2 and j != last:
                out[j] *= h

    # per-point jitter: bark is never a clean lathe curve
    for k in range(2, last):
        out[k] *= rng.u(0.93, 1.07)

    out[last] = tip_r
    for k in range(n):
        if out[k] <= 0.012:
            out[k] = 0.013
    return out


def bend_shape(rng, ts):
    """Lateral offsets added to a stem's straight lean line.
    ts: normalized heights, len 9..12, ts[0]=0.0, ts[-1]=1.0, increasing.
    Returns (dx, dy): two lists of len(ts) metres."""
    two_pi = 2.0 * math.pi
    dy_lim = 0.26                       # leaf clumps must stay off the lane wall

    # --- dx: one full period of a sine, so both ends land on zero and the
    # curve carries exactly two inflections -- the sine's own two zeros.
    phi = rng.u(0.0, two_pi)
    amp = rng.u(0.10, 0.28)
    # Those inflections sit at t1 and t1 + 0.5.  A second difference can only
    # SEE one when it falls inside (ts[1], ts[-2]), so the drawn phase is
    # remapped onto the band of t1 that keeps both visible: same form, same
    # single draw, only the phase offset slides.  The pi branch is preserved,
    # so the S still flips direction with the draw.
    lo, hi = ts[1], ts[-2] - 0.5
    if hi > lo:
        pad = 0.12 * (hi - lo)
        lo, hi = lo + pad, hi - pad
        t1 = lo + (math.fmod(phi, math.pi) / math.pi) * (hi - lo)
    else:
        t1 = 0.25                       # ts too short to show both: centre them
    phi = (math.pi - two_pi * t1) + (math.pi if phi >= math.pi else 0.0)

    raw = [math.sin(phi + two_pi * t) - math.sin(phi) for t in ts]
    peak = 0
    for i in range(1, len(raw)):
        if abs(raw[i]) > abs(raw[peak]):
            peak = i
    scale = amp / abs(raw[peak])
    dx = [max(-amp, min(amp, r * scale)) for r in raw]
    dx[peak] = amp if raw[peak] > 0.0 else -amp    # exact max|dx| == amp
    dx[0] = 0.0
    dx[-1] = 0.0

    # --- dy: a slower wander, under one and a bit periods.
    a = rng.u(1.6 * math.pi, 2.6 * math.pi)
    psi = rng.u(0.0, two_pi)
    best = None
    for k in range(4):
        p = psi + k * math.pi * 0.5                 # quarter turns, no new draws
        g = [math.sin(a * t + p) - math.sin(p) for t in ts]
        g_hi, g_lo = max(g), min(g)
        # 0.5 = the wander sits evenly either side of the lean line, 1.0 = it
        # only ever bulges one way, which reads as a second lean, not a wander.
        ratio = max(g_hi, -g_lo) / (g_hi - g_lo)
        if best is None or ratio < best[0]:
            best = (ratio, g, g_hi, g_lo)
        if ratio <= 0.65:
            break
    ratio, g, g_hi, g_lo = best

    width = rng.u(0.10, 0.40)
    scale = width / (g_hi - g_lo)
    reach = max(g_hi, -g_lo) * scale
    if reach > dy_lim:                              # only if the guard gave up
        scale *= dy_lim / reach
    dy = [max(-dy_lim, min(dy_lim, v * scale)) for v in g]
    dy[0] = 0.0
    return dx, dy


# =============================================================================
# HELPERS
# =============================================================================

def _shuffle(rng, seq):
    for k in range(len(seq) - 1, 0, -1):
        j = rng.i(0, k)
        seq[k], seq[j] = seq[j], seq[k]
    return seq


def _at_z(zs, vals, z):
    """vals sampled at zs (increasing), read off at z."""
    if z <= zs[0]:
        return vals[0]
    if z >= zs[-1]:
        return vals[-1]
    for k in range(len(zs) - 1):
        if z <= zs[k + 1]:
            f = (z - zs[k]) / (zs[k + 1] - zs[k])
            return vals[k] + (vals[k + 1] - vals[k]) * f
    return vals[-1]


def _solve_gaps(LB, UB, W, span):
    """Foot gaps: g_i in [LB_i, UB_i], summing to exactly span, each sitting
    where its own irregular weight puts it inside its own window.  Never
    returns a gap outside its bounds."""
    n = len(LB)
    UB = [max(UB[i], LB[i]) for i in range(n)]
    lo, hi = 0.0, 60.0
    for _ in range(100):
        a = 0.5 * (lo + hi)
        s = sum(LB[i] + min(1.0, a * W[i]) * (UB[i] - LB[i]) for i in range(n))
        if s < span:
            lo = a
        else:
            hi = a
    a = 0.5 * (lo + hi)
    g = [LB[i] + min(1.0, a * W[i]) * (UB[i] - LB[i]) for i in range(n)]
    for _ in range(60):
        err = span - sum(g)
        if err > 1e-12:
            slack = sum(UB[i] - g[i] for i in range(n))
            if slack <= 1e-12:
                break
            f = min(1.0, err / slack)
            for i in range(n):
                g[i] += (UB[i] - g[i]) * f
        elif err < -1e-12:
            room = sum(g[i] - LB[i] for i in range(n))
            if room <= 1e-12:
                break
            f = min(1.0, -err / room)
            for i in range(n):
                g[i] -= (g[i] - LB[i]) * f
        else:
            break
    return g


# =============================================================================
# THE STAND
# =============================================================================

def stems(rng):
    """The 23 ground-rooted strands, left to right."""
    del NOMINAL_R[:]
    del WHY[:]
    del BEST[:]
    for attempt in range(44):
        # Vigour is the stand's thickness.  If the foot solve cannot close
        # every gap, the next attempt grows a slightly stouter stand rather
        # than leaving a hole a body could walk through.
        # the last few attempts stop asking for head-room and simply build
        # the best stand they can, so there is always something to fall back on
        out = _grow(rng, 1.0 + 0.014 * min(attempt, 12),
                    -999.0 if attempt >= 40 else max(0.0, 0.16 - 0.02 * attempt))
        if out is not None:
            return out
    BEST.sort(key=lambda b: b[0])            # nothing clean: the least bad one
    NOMINAL_R.extend(BEST[0][1])
    return BEST[0][2]


def _grow(rng, vigour, demand):
    """One try at a stand.  None if the foot solve could not close it."""
    # ---- who is what -------------------------------------------------------
    # Four young TRUNKS carry the stand, four more stand behind them, eight
    # middling stems fill between, and the thin end is six whips and one
    # shoot.  At twenty metres the eye reads the contrast, not the count.
    spec = ([("fat", "tall")] * 4 + [("thick", "tall")] * 4 +
            [("mid", "tall")] * 4 + [("mid", "midh")] * 2 +
            [("mid", "short")] * 2 + [("shoot", "midh")] * 1 +
            [("whip", "tall")] * 2 + [("whip", "midh")] * 2 +
            [("whip", "short")] * 2)
    _shuffle(rng, spec)
    # The stem at each end of the stand is the one holding the lane wall, and
    # a hole beside the wall is a hole: it has to be a full-height trunk that
    # runs the whole band, not a sapling that stops inside it.
    for slot in (0, N - 1):
        if spec[slot] != ("fat", "tall"):
            for k in range(1, N - 1):
                if spec[k] == ("fat", "tall"):
                    spec[slot], spec[k] = spec[k], spec[slot]
                    break

    SIDES = {"fat": 8, "thick": 8, "mid": 7, "shoot": 6, "whip": 5}
    KIND = {"fat": "trunk", "thick": "trunk", "mid": "trunk",
            "shoot": "shoot", "whip": "shoot"}
    # A stem that is near its tip at the top of the body band still has to
    # hold its piece of the gap there, so the shorter groups are stouter and
    # taper slower than a sapling of that height otherwise would.
    NOM = {("fat", "tall"): (0.200, 0.270),
           ("thick", "tall"): (0.155, 0.195),
           ("mid", "tall"): (0.128, 0.180), ("mid", "midh"): (0.112, 0.150),
           ("mid", "short"): (0.110, 0.148),
           ("shoot", "midh"): (0.090, 0.120),
           ("whip", "tall"): (0.058, 0.080), ("whip", "midh"): (0.052, 0.074),
           ("whip", "short"): (0.047, 0.068)}

    P = []
    for i in range(N):
        grp, hc = spec[i]
        lo, hi = NOM[(grp, hc)]
        nom = min(0.270, rng.u(lo, hi) * vigour)
        if hc == "tall":
            ztop, npt = rng.u(7.64, 8.42), rng.i(8, 9 if grp in ("shoot", "whip") else 10)
            if i in (0, N - 1):
                ztop = rng.u(8.36, 8.42)      # the wall stems run right up
        elif hc == "midh":
            ztop, npt = rng.u(5.06, 6.58), rng.i(8, 9 if grp in ("shoot", "whip") else 10)
        else:
            ztop, npt = rng.u(3.92, 4.94), rng.i(8, 9)

        z0 = ROOT_TOP_Z
        z1 = z0 + rng.u(0.18, 0.30)
        step = (ztop - z1) / float(npt - 2)
        zs = [z0, z1]
        for k in range(2, npt - 1):
            zs.append(z1 + step * (k - 1) + step * 0.30 * rng.sf())
        zs.append(ztop)
        for k in range(1, npt):                       # keep it strictly rising
            if zs[k] <= zs[k - 1] + 0.02:
                zs[k] = zs[k - 1] + 0.02
        ts = [(z - z0) / (zs[-1] - z0) for z in zs]
        # A stem does not lean off the ground at a constant rate: it stands
        # up out of its root plate and does its reaching in the crown.  This
        # cubic is what makes a metre and a half of lean affordable -- a pair
        # thrown across each other has spent under a tenth of its convergence
        # by the top of the body band, and crosses up in the canopy where the
        # gate does not care.  It also bows the stem visibly off its own
        # foot-to-top chord, which is most of the bend the eye reads.
        ls = [0.08 * t + 0.92 * t * t * t for t in ts]

        # a shorter stem tapers slower, or it is a needle by the time the band
        # is done with it and it stops holding its piece of the gap
        tp = rng.u(0.22, 0.38) if hc != "tall" else rng.u(0.34, 0.54)
        radii = stem_radii(rng, nom, ts, tp, rng.u(0.016, 0.030))
        dx, dy = bend_shape(rng, ts)
        P.append({"grp": grp, "hc": hc, "nom": nom, "zs": zs, "ts": ts, "ls": ls,
                  "radii": radii, "dx": dx, "dy": dy, "npt": npt, "lean": 0.0})

    # ---- the wander through the lane ---------------------------------------
    # The gate measures plan distance, so two neighbours that wander apart in y
    # have opened a gap just as surely as if they had leaned apart.  The stand
    # therefore wanders as ONE line, and -- like the bow -- as a wave in
    # ABSOLUTE height, so a short stem and the tall one beside it are always
    # displaced together instead of one snaking out while the other snakes
    # back.  Phase and width drift slowly along the row, so each stem still
    # snakes its own 0.10..0.40 m and its neighbour snakes nearly with it.
    ky = 2.0 * math.pi / rng.u(7.0, 10.0)
    ph0, dph = rng.u(0.0, 2.0 * math.pi), rng.u(0.07, 0.16)
    pw0, dpw = rng.u(0.0, 2.0 * math.pi), rng.u(0.30, 0.55)
    wa, wb = rng.u(0.24, 0.29), rng.u(0.06, 0.10)
    for i in range(N):
        ph = ph0 + dph * i
        z0 = P[i]["zs"][0]
        u = [math.sin(ph + ky * z) - math.sin(ph + ky * z0) for z in P[i]["zs"]]
        hi, lo = max(u), min(u)
        exc = hi - lo if hi > lo else 1.0
        reach = max(hi, -lo) / exc          # 0.5 = even either side, 1 = all one way
        w = wa + wb * math.sin(pw0 + dpw * i)
        if P[i]["grp"] == "whip":
            w *= 1.30                       # a whip is the loosest thing here
        w = min(w, Y_REACH / reach)
        w = max(0.10, min(0.40, w))
        P[i]["dy"] = [v * w / exc for v in u]
        P[i]["dy"][0] = 0.0

    # ---- lean --------------------------------------------------------------
    # A slow wave along the row, not a ramp: neighbours keep similar lean, so a
    # pair's spacing changes slowly with height and one height cannot tear open
    # what another height closes.
    p1, p2 = rng.u(0.0, 2.0 * math.pi), rng.u(0.0, 2.0 * math.pi)
    for i in range(N):
        u = i / float(N - 1)
        L = (0.17 * math.sin(p1 + 2.1 * u) + 0.10 * math.sin(p2 + 4.9 * u)
             + rng.u(-0.04, 0.04))
        if P[i]["hc"] != "tall":
            L *= 0.55           # a short stem spends its lean far sooner
        P[i]["lean"] = L
    # The wall pair leans OUT, into the wall, and the stem next in is not let
    # drift inward off it either.
    P[0]["lean"] = -rng.u(0.05, 0.12)
    P[N - 1]["lean"] = rng.u(0.05, 0.12)
    P[1]["lean"] = min(P[1]["lean"], 0.06)
    P[N - 2]["lean"] = max(P[N - 2]["lean"], -0.06)

    # Both members of a crossing pair must be tall: a short stem spends its
    # lean too early and would have to be planted absurdly wide to still be on
    # its own side of its partner at the top of the band.  A pair thrown hard
    # across is given SHOULDERS -- the stem outside each of them leans the same
    # way, less far -- because a stem thrown over beside an upright one tears
    # that gap open faster than any radius can close it, and the stand would
    # only have to straighten the pair out again.
    cross_pairs = []
    cand = [c for c in range(3, 19)
            if P[c]["hc"] == "tall" and P[c + 1]["hc"] == "tall"]
    _shuffle(rng, cand)
    for c in cand:
        if all(abs(c - d) >= 3 for d in cross_pairs):
            cross_pairs.append(c)
            if len(cross_pairs) == 5:
                break
    cross_pairs.sort()
    for c in cross_pairs:
        P[c - 1]["lean"] = rng.u(0.40, 0.66)
        P[c]["lean"] = rng.u(1.28, 1.86)
        P[c + 1]["lean"] = -rng.u(1.28, 1.86)
        P[c + 2]["lean"] = -rng.u(0.40, 0.66)

    # Everything that is not a wall stem or part of a thrown pair is then
    # relaxed toward its neighbours.  A stem thrown over next to an upright one
    # opens that gap faster than any radius can close it, so the stand carries
    # its lean as a smooth field with four deliberate tears in it, rather than
    # as noise that the foot solve would only have to straighten back out.
    fixed = set([0, N - 1])
    for c in cross_pairs:
        fixed.update((c - 1, c, c + 1, c + 2))
    for _ in range(3):
        L = [p["lean"] for p in P]
        for i in range(1, N - 1):
            if i not in fixed:
                P[i]["lean"] = 0.5 * L[i] + 0.25 * (L[i - 1] + L[i + 1])

    # The bow is combed along the row for the same reason the wander is: two
    # neighbours whose S-bends fight each other are apart at one height and
    # together at another, and the gate takes the worst of every height.  The
    # bow is therefore a wave in ABSOLUTE height, not in each stem's own
    # fraction of itself -- one load bent this whole stand, and it bent every
    # stem in it at the same heights.  Phase and amplitude drift slowly from
    # stem to stem, so neighbours bow very nearly together while stems at
    # opposite ends of the stand do not.  Each stem keeps its own amplitude in
    # 0.10..0.28 m and the two inflections its S was drawn with.
    kz = 2.0 * math.pi / rng.u(7.6, 9.6)
    bp, dbp = rng.u(0.0, 2.0 * math.pi), rng.u(0.10, 0.26)
    pa, dpa = rng.u(0.0, 2.0 * math.pi), rng.u(0.25, 0.50)
    for i in range(N):
        amp = max(abs(v) for v in P[i]["dx"])          # what its own S was given
        amp = 0.75 * (0.30 + 0.11 * math.sin(pa + dpa * i)) + 0.25 * amp
        if P[i]["grp"] == "whip":
            amp *= 1.35
        ph = bp + dbp * i
        raw = [math.sin(ph + kz * z) - math.sin(ph + kz * P[i]["zs"][0])
               for z in P[i]["zs"]]
        m = max(abs(v) for v in raw) or 1.0
        dx = [v * amp / m for v in raw]
        dx[0] = 0.0
        # Amplitude is not what the eye reads -- departure from the stem's own
        # foot-to-tip chord is, and a wave that happens to run nearly straight
        # across one stem's span cancels against its chord however tall it is.
        # So each stem is scaled to the DEPARTURE it needs, which keeps the
        # comb (same phase, same shape) while making the bend visible.
        f = [(z - P[i]["zs"][0]) / (P[i]["zs"][-1] - P[i]["zs"][0])
             for z in P[i]["zs"]]
        dep = max(abs(dx[k] - dx[-1] * f[k]) for k in range(len(dx)))
        if dep > 1e-6:
            sc = min(BOW_DEP / dep, 0.82 / max(abs(v) for v in dx))
            if sc > 1.0:
                dx = [v * sc for v in dx]
        P[i]["dx"] = dx
        P[i]["dx"][0] = 0.0
        P[i]["bow0"] = max(abs(v) for v in dx)
        # the bow no longer dies at the tip, so the lean it adds there counts
        top = P[i]["lean"] + P[i]["dx"][-1]
        if abs(top) > 2.15:
            P[i]["lean"] -= top - (2.15 if top > 0.0 else -2.15)

    for slot in (0, N - 1):                 # the wall stems may barely bow
        a = max(abs(v) for v in P[slot]["dx"])
        if a > EDGE_BEND:
            P[slot]["dx"] = [v * EDGE_BEND / a for v in P[slot]["dx"]]

    # ---- the foot solve ----------------------------------------------------
    # A stem's x at height z is foot + drift(z), and drift never depends on the
    # foot, so the whole stand is one small linear programme in the foot gaps.
    # Only the y baseline, plate_y(foot), feeds back -- so the solve is run
    # three times, each on the feet the last one found.
    def drift(p, z):
        return p["lean"] * _at_z(p["zs"], p["ls"], z) + _at_z(p["zs"], p["dx"], z)

    D = [dict((z, drift(P[i], z)) for z in ST_LEVELS) for i in range(N)]
    RR = [dict((z, _at_z(P[i]["zs"], P[i]["radii"], z) * ST_WOBBLE) for z in ST_LEVELS)
          for i in range(N)]
    DY = [dict((z, _at_z(P[i]["zs"], P[i]["dy"], z)) for z in ST_LEVELS)
          for i in range(N)]
    HERE = [dict((z, P[i]["zs"][0] <= z <= P[i]["zs"][-1]) for z in ST_LEVELS)
            for i in range(N)]
    span = X_HI - X_LO

    # Every stem now runs the whole body band, so no pair ever straddles a
    # stem that has stopped: each gap answers to exactly one constraint.
    def pair_lb(i):
        conv = 0.0
        for z in ST_LEVELS:
            conv = max(conv, D[i][z] - D[i + 1][z])
        lb = max(GAP_MIN, conv + 0.06)
        if i in cross_pairs:
            # a thrown pair must still be on its own side of itself at CROSS_LO,
            # so the two of them cross up in the canopy and not among the legs
            lb = max(lb, drift(P[i], 4.0) - drift(P[i + 1], 4.0) + 0.05)
        return lb

    def pair_ub(i, feet):
        ya, yb = plate_y(feet[i]), plate_y(feet[i + 1])
        u = GAP_MAX
        for z in ST_LEVELS:
            # in plan: hypot(dx, dy) - 0.9(ra+rb) <= TARGET
            c = TARGET + RR[i][z] + RR[i + 1][z]
            dy = (ya + DY[i][z]) - (yb + DY[i + 1][z])
            if abs(dy) >= c - 0.02:
                return None                     # wandered apart on its own
            u = min(u, math.sqrt(c * c - dy * dy) - (D[i + 1][z] - D[i][z]))
        return u

    def bounds(feet):
        LB, UB = [], []
        for i in range(N - 1):
            u = pair_ub(i, feet)
            if u is None:
                return None, None
            LB.append(pair_lb(i))
            UB.append(u)
        return LB, UB

    feet = [X_LO + span * i / float(N - 1) for i in range(N)]
    g = None
    for _ in range(3):
        LB, UB = bounds(feet)
        if LB is None:
            WHY.append('y wander opened a pair on its own')
            return None
        # A pair whose no-swap floor has climbed past its closable ceiling is
        # leaning harder than the stand can carry: ease the two of them until
        # it fits.  Rare, but it must never be left to chance.
        for i in range(N - 1):
            for _ in range(90):
                if LB[i] <= UB[i] - 0.02:
                    break
                for j in (i, i + 1):
                    P[j]["lean"] *= 0.97
                    a = max(abs(v) for v in P[j]["dx"])
                    if a > 0.75 * P[j]["bow0"]:   # relief comes out of lean first
                        f = max(0.75 * P[j]["bow0"] / a, 0.97)
                        P[j]["dx"] = [v * f for v in P[j]["dx"]]
                    D[j] = dict((z, drift(P[j], z)) for z in ST_LEVELS)
                for j in (i - 1, i, i + 1):
                    if 0 <= j < N - 1:
                        u = pair_ub(j, feet)
                        if u is None:
                            return None
                        LB[j], UB[j] = pair_lb(j), u
            if LB[i] > UB[i] - 0.005:
                WHY.append('pair %d floor %.3f over ceiling %.3f' % (i, LB[i], UB[i]))
                if demand > -900.0:
                    return None
                UB[i] = LB[i]
        CAPACITY[:] = [sum(LB), sum(UB), span]
        if sum(UB) - span < demand or sum(LB) > span:
            WHY.append('cap %.3f/%.3f' % (sum(UB) - span, demand))
            if demand > -900.0:
                return None
        W = [0.90 + 0.10 * rng.f() if i in cross_pairs else rng.u(0.02, 1.0)
             for i in range(N - 1)]
        g = _solve_gaps(LB, UB, W, span)
        if abs(sum(g) - span) > 1e-6:
            WHY.append('sum %.4f' % (sum(g) - span))
            if demand > -900.0:
                return None
            f = span / sum(g)
            g = [v * f for v in g]
        feet = [X_LO]
        for v in g:
            feet.append(feet[-1] + v)
        feet[N - 1] = X_HI
        # A metre and a half of lean near the wall would swing the stem clean
        # out of the lane, so once the feet are known each stem's lean is eased
        # back until its whole axis is inside.  The solve then runs again on
        # the drift that survived.
        for i in range(N):
            for _ in range(24):
                r = max(abs(feet[i] + P[i]["lean"] * P[i]["ls"][k] + P[i]["dx"][k])
                        for k in range(P[i]["npt"]))
                if r <= X_REACH:
                    break
                P[i]["lean"] *= 0.88
            D[i] = dict((z, drift(P[i], z)) for z in ST_LEVELS)

    # ---- assemble ----------------------------------------------------------
    shorts = [i for i in range(N) if P[i]["hc"] == "short"]
    _shuffle(rng, shorts)
    leafy = set(shorts[:3])
    out = []
    for i in range(N):
        p = P[i]
        x0, y0 = feet[i], plate_y(feet[i])
        path = [(x0 + p["lean"] * p["ls"][k] + p["dx"][k],
                 y0 + p["dy"][k], p["zs"][k]) for k in range(p["npt"])]
        leaf = i in leafy
        out.append({"kind": KIND[p["grp"]], "path": path, "radii": p["radii"],
                    "sides": SIDES[p["grp"]], "parent": None, "at": 0.0,
                    "tip": "leaf" if leaf else "taper",
                    "tip_r": rng.u(0.30, 0.42) if leaf else 0.0})

    # Easing pairs apart costs lean, so a stand only counts as grown once
    # enough of it is still thrown hard over and enough pairs still cross.
    strong = sum(1 for i in range(N)
                 if abs(out[i]["path"][-1][0] - feet[i]) > 0.58)
    thrown = sum(1 for i in range(N)
                 if 1.2 <= abs(out[i]["path"][-1][0] - feet[i]) <= 2.2)
    seen = _visible_crossings(out)
    pts = sum(len(x["path"]) for x in out)
    # The two wall stems are held against the lane wall and cannot bow.  Of
    # the rest, most must read as visibly bent -- but not all: the lean's own
    # crown curve runs the other way for half the stand, and forcing the S to
    # agree with it everywhere would break the comb that lets the stand be
    # this dense at all.  Ten of the fourteen is what the geometry affords.
    bow = sum(1 for i in range(1, N - 1)
              if out[i]["sides"] >= 7 and _chord_bow(out[i]) >= 0.35)
    cross = 0
    for a in range(N):
        for b in range(a + 1, N):
            if (out[a]["path"][-1][0] - out[b]["path"][-1][0]) * \
               (feet[a] - feet[b]) < 0.0:
                cross += 1
    gap, wall = _worst_gap(out)
    reach = max(abs(q[0]) for s in out for q in s["path"])
    score = (max(0.0, gap - HARD) * 40.0 + max(0.0, wall - WALL) * 40.0 +
             max(0, 8 - strong) + max(0, 4 - cross) +
             max(0, 6 - thrown) + max(0, 5 - len(seen)) +
             max(0, pts - PT_MAX) + max(0, 10 - bow) +
             max(0.0, reach - (HALF_W - 0.015)) * 40.0)
    BEST.append((score, [p["nom"] for p in P], out))
    if score > 0.0:
        WHY.append('strong %d cross %d thrown %d seen %d pts %d bow %d gap %.3f'
                   % (strong, cross, thrown, len(seen), pts, bow, gap))
        return None
    for i in range(N):
        NOMINAL_R.append(P[i]["nom"])
    return out


def _worst_gap(strands):
    """(widest stem-stem clearance, widest wall clearance) over the body band,
    measured exactly the way the gate measures: in plan, radii at 0.9."""
    worst = wall = 0.0
    for z in ST_LEVELS:
        col = []
        for s in strands:
            zs = [q[2] for q in s["path"]]
            if zs[0] <= z <= zs[-1]:
                for k in range(len(zs) - 1):
                    if z <= zs[k + 1]:
                        f = (z - zs[k]) / (zs[k + 1] - zs[k])
                        col.append((s["path"][k][0] + f * (s["path"][k + 1][0]
                                                           - s["path"][k][0]),
                                    s["path"][k][1] + f * (s["path"][k + 1][1]
                                                           - s["path"][k][1]),
                                    (s["radii"][k] + f * (s["radii"][k + 1]
                                                          - s["radii"][k]))
                                    * ST_WOBBLE))
                        break
        if not col:
            continue
        col.sort()
        for a, b in zip(col, col[1:]):
            worst = max(worst, math.hypot(b[0] - a[0], b[1] - a[1]) - a[2] - b[2])
        wall = max(wall, col[0][0] + HALF_W - col[0][2],
                   HALF_W - col[-1][0] - col[-1][2])
    return worst, wall


def _chord_bow(s):
    """How far a stem departs, in x, from the straight line between its foot
    and its tip -- the bend the eye actually reads."""
    p = s["path"]
    z0, z1 = p[0][2], p[-1][2]
    out = 0.0
    for q in p:
        f = (q[2] - z0) / (z1 - z0)
        out = max(out, abs(q[0] - (p[0][0] + (p[-1][0] - p[0][0]) * f)))
    return out


def _visible_crossings(strands):
    """Pairs that genuinely cross to the eye: they swap x order, they do it
    between CROSS_LO and CROSS_HI, and their two axes pass within CROSS_NEAR
    of each other in plan at the height where they swap.  Returns
    [(a, b, z, plan distance), ...]."""
    out = []
    n = len(strands)
    for a in range(n):
        pa = strands[a]["path"]
        for b in range(a + 1, n):
            pb = strands[b]["path"]
            lo = max(pa[0][2], pb[0][2])
            hi = min(pa[-1][2], pb[-1][2])
            if hi - lo < 0.5:
                continue
            def sep(z, pa=pa, pb=pb):
                return _pt(pa, z)[0] - _pt(pb, z)[0]
            if sep(lo) * sep(min(hi, CROSS_HI)) >= 0.0:
                continue                    # never swaps inside the window
            u, v = lo, min(hi, CROSS_HI)
            for _ in range(40):             # bisect to the swap height
                m = 0.5 * (u + v)
                if sep(u) * sep(m) <= 0.0:
                    v = m
                else:
                    u = m
            z = 0.5 * (u + v)
            if not CROSS_LO <= z <= CROSS_HI:
                continue
            qa, qb = _pt(pa, z), _pt(pb, z)
            d = math.hypot(qa[0] - qb[0], qa[1] - qb[1])
            if d <= CROSS_NEAR:
                out.append((a, b, z, d))
    return out


def _pt(path, z):
    """The point on a stem at height z (its path rises monotonically)."""
    if z <= path[0][2]:
        return path[0]
    if z >= path[-1][2]:
        return path[-1]
    for k in range(len(path) - 1):
        if z <= path[k + 1][2]:
            f = (z - path[k][2]) / (path[k + 1][2] - path[k][2])
            return (path[k][0] + (path[k + 1][0] - path[k][0]) * f,
                    path[k][1] + (path[k + 1][1] - path[k][1]) * f, z)
    return path[-1]


# ---- the forks and the side limbs that tangle with neighbours

# =============================================================================
# THE GATE, MIRRORED
# =============================================================================
# Kept as literals rather than imported from thicket_measure, which imports this
# module.  If the gate's bands move, these move with them.

LB_WOBBLE = 1.0 - WOB                 # the tubes get +-10%; the gate measures thin
LB_BODY = (0.05, 3.60)                # the band a body could ever occupy
LB_UPPER = (3.60, 8.20)               # above a body: this only has to read thick
BODY_LIMIT = 0.32
UPPER_LIMIT = 0.55

FOOT_MIN = 3.60                    # no strand in this file puts its FOOT below
                                   # the body band's ceiling, so none of them
                                   # can put a column inside that band at all.
                                   # That is the whole displacement trap closed
                                   # structurally instead of level by level --
                                   # a sampled test just moves the harm to a
                                   # height nobody sampled, as it did twice
                                   # here.  Nothing is lost: the body band is
                                   # the stems' own solve and already measures
                                   # inside its limit without help from a fork.
BODY_FINE = 0.10                   # the veto grid: coarse scoring levels let the
                                   # displacement harm simply move to a height
                                   # nobody sampled, so the body band gets its
                                   # own fine sweep and a hard answer
BODY_STEP = 0.32                   # what the fill scores on.  Coarser than the
UPPER_STEP = 0.14                  # gate's 200 levels a band, fine enough that
                                   # no hole hides between two samples: a
                                   # clearance moves with stem lean, which is
                                   # well under 0.1 m over 0.14 m of rise.
MARGIN = 0.07                      # aim this far under the limit
W_OVER = 1.0                       # cost of being over the aim, to the 4th
W_EVEN = 0.008                     # cost of being uneven at all, to the 4th
DISPLACE = 0.60                    # the last-resort charge, when the fallback
DISPLACE_UP = 0.08                 # sweep has nothing clean left; above the
                                   # body band the same harm is priced, not
                                   # vetoed, so a leader may still buy one bad
                                   # level to close a 1 m canopy hole.
                                   #
                                   # The clearance chain is measured in plan, so
                                   # dropping a strand between two stems does
                                   # not always SPLIT their gap.  Stand a thin
                                   # column just in front of a fat stem and the
                                   # chain now measures from the thin one: the
                                   # link to the next stem is longer by the wood
                                   # displaced, and longer again if the newcomer
                                   # sits off in y.  Seen for real -- a leader
                                   # at x=-2.28 r=0.085 in front of a stem at
                                   # x=-2.28 r=0.142 turned a 0.30 link into
                                   # 0.356 and that was the stand's worst.
                                   #
                                   # The radius rule ("be at least as fat as the
                                   # stem you stand in front of") is the cause;
                                   # the test below is the effect itself, which
                                   # is exact: charge whenever the two links a
                                   # strand leaves behind are not BOTH shorter
                                   # than the one link it replaced.  Scored --
                                   # never hoped for -- but priced, not vetoed,
                                   # so the fill can still buy a bad level when
                                   # a leader closes a 1 m canopy hole with it.
W_BODY = 0.35                      # the body band is the STEMS' solve; a fork
                                   # helps where it can but must not be dragged
                                   # off the canopy chasing a hole down there
W_WALL_BODY = 0.20                 # down in the body band a stem's foot and
                                   # lean decide the two wall clearances and no
                                   # 1.15 m throw closes a 1 m hole, so they are
                                   # scored faintly.  At the canopy it inverts:
W_WALL_UP = 1.00                   # up there the leaders are the ONLY thing
                                   # standing near the wall, and a top thrown
                                   # 1.15 m off a stem at x=4.5 reaches 5.28.
                                   # Scored full, the fill spreads the leaders
                                   # across the whole 10.6 m instead of packing
                                   # them into the middle and leaving a 1.4 m
                                   # hole beside each wall.


def _levels():
    out = []
    for lo, hi, step, lim, w, ww in (
            (LB_BODY[0], LB_BODY[1], BODY_STEP, BODY_LIMIT, W_BODY, W_WALL_BODY),
            (LB_UPPER[0], LB_UPPER[1], UPPER_STEP, UPPER_LIMIT, 1.0, W_WALL_UP)):
        n = int(round((hi - lo) / step))
        for k in range(n + 1):
            out.append((lo + (hi - lo) * k / float(n), lim, w, ww))
    return tuple(out)


LB_LEVELS = _levels()


def _pen(g, lim):
    """What one clearance costs the fill.

    (gap - aim) ** 4 is the target: a level already inside the aim costs
    nothing and stops competing for strands, so the budget flows to the levels
    still open -- always the canopy, where fewest strands reach.  The small
    gap ** 4 term is evenness, and a gradient to follow once the first term has
    gone flat.  Both are RAW sums, never a per-level norm: a norm is concave in
    the level's total, which hands the biggest marginal gain to the level that
    is already fine, and the fill then spends every limb on easy ground.
    """
    if g <= 0.0:
        return 0.0
    e = g - lim + MARGIN
    return (W_OVER * e ** 4 if e > 0.0 else 0.0) + W_EVEN * g ** 4


def _cols(strand, z):
    """Every (x, y, r) where the strand's centre line passes height z, radius
    thinned by the wobble -- exactly thicket_measure.crossings()."""
    path, radii = strand["path"], strand["radii"]
    n = len(path) - 1
    out = []
    for i in range(n):
        a, b = path[i], path[i + 1]
        if abs(b[2] - a[2]) < 1e-9:
            continue
        t = (z - a[2]) / (b[2] - a[2])
        if not 0.0 <= t <= 1.0:
            continue
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t,
                    radius_at(radii, (i + t) / float(n)) * LB_WOBBLE))
    return out


def _wt(k, n, w, ww):
    """Wall clearances are the first and last of a level."""
    return w * ww if (k == 0 or k == n) else w


def _gapline(cols):
    """The clearances across one level, walls included.  len == len(cols) + 1;
    gap k is the one a column inserted at index k would split."""
    n = len(cols)
    if n == 0:
        return [2.0 * HALF_W]
    out = [cols[0][0] + HALF_W - cols[0][2]]
    for k in range(1, n):
        a, b = cols[k - 1], cols[k]
        out.append(math.hypot(b[0] - a[0], b[1] - a[1]) - a[2] - b[2])
    out.append(HALF_W - cols[-1][0] - cols[-1][2])
    return out


def _fork_weights():
    """What the FORK pass scores on.  A leader is the only thing in this file
    that stands above about 8.1 m -- a limb tops out near 8.0 and the stems
    thin out -- so the leaders are weighted towards the canopy and let off the
    body band, which is the stems' own solve.  Weighted flat, they get spent
    evening out ground that the limbs could have covered."""
    out = []
    for z, lim, w, ww in LB_LEVELS:
        if z <= LB_BODY[1]:
            out.append(1.0)        # the displacement charge lives here and
                                   # must not be weighted away; _pen's own
                                   # W_BODY already keeps body GAPS quiet
        else:
            out.append(0.20 + 2.60 * ((z - LB_UPPER[0]) / (LB_UPPER[1] - LB_UPPER[0])) ** 1.5)
    return tuple(out)


W_PASS_LIMB = None                 # flat: a limb serves wherever it can reach


class _Field(object):
    """The stand's occupancy at every scored level, sliced once so a candidate
    strand costs one binary search per level instead of a full re-measure."""

    def __init__(self, strands, wpass=None):
        self.wpass = wpass
        self.bz = []
        self.bcols = []
        n = int(round((LB_BODY[1] - LB_BODY[0]) / BODY_FINE))
        for k in range(n + 1):
            z = LB_BODY[0] + (LB_BODY[1] - LB_BODY[0]) * k / float(n)
            self.bz.append(z)
            self.bcols.append(sorted((c for s in strands for c in _cols(s, z))))
        self.cols, self.gap, self.pre, self.suf, self.cost = [], [], [], [], []
        for z, lim, w, ww in LB_LEVELS:
            cols = sorted((c for s in strands for c in _cols(s, z)))
            g = _gapline(cols)
            pre = [0.0] * (len(g) + 1)
            for k in range(len(g)):
                pre[k + 1] = pre[k] if pre[k] > g[k] else g[k]
            suf = [0.0] * (len(g) + 1)
            for k in range(len(g) - 1, -1, -1):
                suf[k] = suf[k + 1] if suf[k + 1] > g[k] else g[k]
            self.cols.append(cols)
            self.gap.append(g)
            self.pre.append(pre)
            self.suf.append(suf)
            self.cost.append(sum(_wt(k, len(cols), w, ww) * _pen(g[k], lim)
                                 for k in range(len(g))))
        if wpass is not None:
            self.cost = [c * wpass[i] for i, c in enumerate(self.cost)]

    def score(self, strand):
        """(cost, worst clearance) once `strand` is added.  Lower is better."""
        cost = 0.0
        worst = 0.0
        for i in range(len(LB_LEVELS)):
            z, lim, w, ww = LB_LEVELS[i]
            cz = self.cost[i] if self.wpass is None else self.cost[i] / self.wpass[i]
            m = self.pre[i][len(self.gap[i])]
            cc = _cols(strand, z)
            if len(cc) == 1:
                x, y, r = cc[0]
                cols, g = self.cols[i], self.gap[i]
                lo, hi = 0, len(cols)
                while lo < hi:
                    mid = (lo + hi) // 2
                    if cols[mid][0] < x:
                        lo = mid + 1
                    else:
                        hi = mid
                if lo == 0:
                    lft = x + HALF_W - r
                else:
                    a = cols[lo - 1]
                    lft = math.hypot(x - a[0], y - a[1]) - a[2] - r
                if lo == len(cols):
                    rgt = HALF_W - x - r
                else:
                    b = cols[lo]
                    rgt = math.hypot(b[0] - x, b[1] - y) - r - b[2]
                n = len(cols)
                d = (_wt(lo, n + 1, w, ww) * _pen(lft, lim)
                     + _wt(lo + 1, n + 1, w, ww) * _pen(rgt, lim)
                     - _wt(lo, n, w, ww) * _pen(g[lo], lim))
                if z > LB_BODY[1] and 0 < lo < len(cols) \
                        and (lft > g[lo] or rgt > g[lo]):
                    d += DISPLACE_UP
                cz += d if self.wpass is None else d * self.wpass[i]
                m = self.pre[i][lo]
                if self.suf[i][lo + 1] > m:
                    m = self.suf[i][lo + 1]
                if lft > m:
                    m = lft
                if rgt > m:
                    m = rgt
            elif len(cc) > 1:                      # a bowed strand doubling back
                cols = sorted(self.cols[i] + cc)   # -- rare, so just re-measure
                gg = _gapline(cols)
                cz = sum(_wt(k, len(cols), w, ww) * _pen(gg[k], lim)
                         for k in range(len(gg)))
                if self.wpass is not None:
                    cz *= self.wpass[i]
                m = max(gg)
            cost += cz if self.wpass is None else cz * self.wpass[i]
            if m > worst:
                worst = m
        return (cost, worst)

    def harms_body(self, strand):
        """True when this strand would LENGTHEN a clearance link anywhere in the
        body band -- the displacement trap.  Checked on its own fine sweep and
        answered hard: nothing my pass adds is worth widening the one band a
        body can actually walk through, and a strand that cannot help down
        there can always just start above it."""
        if strand["path"][0][2] >= LB_BODY[1]:
            return False
        for i in range(len(self.bz)):
            cc = _cols(strand, self.bz[i])
            if not cc:
                continue
            cols = self.bcols[i]
            for x, y, r in cc:
                lo, hi = 0, len(cols)
                while lo < hi:
                    mid = (lo + hi) // 2
                    if cols[mid][0] < x:
                        lo = mid + 1
                    else:
                        hi = mid
                if not (0 < lo < len(cols)):
                    continue
                a, b = cols[lo - 1], cols[lo]
                old = math.hypot(b[0] - a[0], b[1] - a[1]) - a[2] - b[2]
                if (math.hypot(x - a[0], y - a[1]) - a[2] - r > old
                        or math.hypot(b[0] - x, b[1] - y) - r - b[2] > old):
                    return True
        return False

    def holes(self, n):
        """The n worst clearances as (z, aim_x): where a strand is worth most.
        The fill searches these instead of sweeping every possible throw, which
        is what keeps a full-band score affordable."""
        out = []
        for i in range(len(LB_LEVELS)):
            z, lim, w, ww = LB_LEVELS[i]
            cols, g = self.cols[i], self.gap[i]
            for k in range(len(g)):
                if g[k] <= lim - MARGIN:
                    continue
                lo = -HALF_W if k == 0 else cols[k - 1][0]
                hi = HALF_W if k == len(cols) else cols[k][0]
                out.append((_wt(k, len(cols), w, ww) * g[k], z, 0.5 * (lo + hi)))
        out.sort(reverse=True)
        return [(z, x) for _, z, x in out[:n]]


def _clampx(x):
    return max(-HALF_W + 0.02, min(HALF_W - 0.02, x))


def _clampy(y, lim):
    return max(-lim, min(lim, y))


def _top(strand):
    return strand["path"][-1]


# =============================================================================
# FORKS -- a tall stem's second leader
# =============================================================================

N_FORK = 11
FORK_AT = (0.42, 0.66)
FORK_THROW = (0.45, 1.15)
FORK_TOPS = (8.44, 8.34, 8.22, 8.06, 7.78, 7.46)
FORK_XK = (0.28, 0.40, 0.55, 0.78, 1.15)
                                   # how early the leader leans out.  A small
                                   # exponent opens the V hard just above the
                                   # split and then runs parallel to the stems,
                                   # which is the only shape that holds a
                                   # leader mid-gap at 4 m AND at the canopy; a
                                   # late lean is centred at one height and
                                   # hard against its parent at every other.
FORK_ROOT_K = (0.55, 0.72)
FORK_TIP_R = (0.016, 0.026)
FORK_PER_STEM = 3                  # a stem may throw two leaders.  With one
                                   # each, the midpoints only two stems can
                                   # reach (throw is capped at 1.15 m) get
                                   # stranded and a 0.6 m hole survives the
                                   # whole fill.
TALL_Z = 7.4
Y_LIM = 0.46                       # inside check()'s HALF_T - 0.10
Y_LEAF = 0.26
N_HOLE = 16                        # holes chased per placement
N_AT_F = 4


def _fork_jitter(rng):
    return {
        "bend": rng.u(0.04, 0.13),
        "yamp": rng.u(-0.12, 0.12),    # the gate measures IN PLAN, so a metre
        "yph": rng.u(0.0, 1.0),        # of y wander is a metre of clearance it
        "ydrift": rng.u(-0.06, 0.06),  # hands back.  Wander, but not much.
        "kroot": rng.u(*FORK_ROOT_K),
        "rtip": rng.u(*FORK_TIP_R),
        "npts": rng.i(4, 5),           # 4..5, not 5..6: a leader is a smooth
        "zk": rng.u(0.88, 0.98),       # arc and 4 points carry it.  The tube
                                       # SIDES stay 5 and 6 -- the cross-section
                                       # is the whole reason for this rebuild
                                       # and it does not get cheaper.
        "ztop": rng.u(0.0, 0.055),
        "xk": 0.0,                 # xk and the bend's sign are chosen by the
        "bs": 0.0,                 # search, not by the rng
    }


def _fork(base, p, at, top_x, top_z, j):
    par = base[p]
    p0 = point_at(par["path"], at)
    x0, y0, z0 = p0
    n = j["npts"]
    r0 = j["kroot"] * radius_at(par["radii"], at)
    rt = j["rtip"]
    base_y = j["yamp"] * math.sin(math.pi * j["yph"])
    path, radii = [p0], [r0]
    for k in range(1, n):
        t = k / (n - 1.0)
        z = z0 + (top_z - z0) * (t ** j["zk"])
        x = x0 + (top_x - x0) * (t ** j["xk"]) \
            + j["bs"] * j["bend"] * math.sin(math.pi * t)
        y = y0 + j["yamp"] * math.sin(math.pi * (t * 0.9 + j["yph"])) - base_y
        y += j["ydrift"] * t
        path.append((_clampx(x), _clampy(y, Y_LIM), z))
        radii.append(rt + (r0 - rt) * ((1.0 - t) ** 1.35))
    return {"kind": "fork", "path": path, "radii": radii,
            "sides": 6 if par["sides"] == 8 else 5,
            "parent": p, "at": at, "tip": "taper", "tip_r": 0.0}


def _fallback_fork(base, tall, taken, fld, j, relax=False):
    """Used only when no hole is in reach of any free stem -- a coarse sweep so
    the pass always returns its full count of leaders, whatever stems() did."""
    best = None
    for p in tall:
        if len(taken.get(p, ())) >= FORK_PER_STEM:
            continue
        ptx = _top(base[p])[0]
        for ai in range(N_AT_F):
            at = FORK_AT[0] + (FORK_AT[1] - FORK_AT[0]) * ai / (N_AT_F - 1.0)
            if any(abs(at - h) < 0.09 for h in taken.get(p, ())):
                continue
            z0 = point_at(base[p]["path"], at)[2]
            if z0 < FOOT_MIN and not relax:
                continue
            for side in (-1.0, 1.0):
                for k in range(6):
                    th = FORK_THROW[0] + (FORK_THROW[1] - FORK_THROW[0]) * k / 5.0
                    tx = ptx + side * th
                    if abs(tx) > HALF_W - 0.02:
                        continue
                    for tz0 in FORK_TOPS:
                        tz = tz0 - j["ztop"]
                        if tz < z0 + 1.4:
                            continue
                        j["xk"], j["bs"] = 0.55, 1.0
                        f = _fork(base, p, at, tx, tz, j)
                        sc = fld.score(f)
                        if fld.harms_body(f):
                            sc = (sc[0] + DISPLACE, sc[1])
                        if best is None or sc < best[0]:
                            best = (sc, p, f)
    return best


def _best_fork(base, tall, taken, fld, j):
    """The leader that costs the field least.  For each hole worth closing the
    throw is SOLVED, not scanned: given the split point, the rise and the lean
    exponent, there is exactly one top that puts the leader through (z, aim_x),
    and it either falls inside the 0.45..1.15 m throw or it does not."""
    best = None
    for z_h, aim in fld.holes(N_HOLE):
        for p in tall:
            held = taken.get(p, ())
            if len(held) >= FORK_PER_STEM:
                continue
            ptx = _top(base[p])[0]
            if not (0.20 < abs(aim - ptx) < 1.45):     # out of throw's reach
                continue
            for ai in range(N_AT_F):
                at = FORK_AT[0] + (FORK_AT[1] - FORK_AT[0]) * ai / (N_AT_F - 1.0)
                if any(abs(at - h) < 0.09 for h in held):
                    continue                   # two leaders, but not twinned
                x0, y0, z0 = point_at(base[p]["path"], at)
                if z0 < FOOT_MIN or z_h < z0 + 0.30:
                    continue
                if radius_at(base[p]["radii"], at) * FORK_ROOT_K[0] < j["rtip"] + 0.006:
                    continue
                for tz0 in FORK_TOPS:
                    tz = tz0 - j["ztop"]
                    if tz < z0 + 1.4 or tz < z_h:
                        continue
                    t = ((z_h - z0) / (tz - z0)) ** (1.0 / j["zk"])
                    if not (0.02 < t <= 1.0):
                        continue
                    for xk in FORK_XK:
                        d = t ** xk
                        for bs in (-1.0, 1.0):
                            tx = x0 + (aim - x0 - bs * j["bend"]
                                       * math.sin(math.pi * t)) / d
                            th = tx - ptx
                            if not (FORK_THROW[0] <= abs(th) <= FORK_THROW[1]):
                                continue
                            if abs(tx) > HALF_W - 0.02:
                                continue
                            j["xk"], j["bs"] = xk, bs
                            f = _fork(base, p, at, tx, tz, j)
                            if fld.harms_body(f):
                                continue
                            sc = fld.score(f)
                            if best is None or sc < best[0]:
                                best = (sc, p, f)
    if best is None:
        best = _fallback_fork(base, tall, taken, fld, j)
    if best is None:                       # a stand with no split point above
        best = _fallback_fork(base, tall, taken, fld, j, True)   # 3.6 m at all
    return best


def _held(strands):
    d = {}
    for s in strands:
        d.setdefault(s["parent"], []).append(s["at"])
    return d


def _forks(rng, base):
    tall = [i for i, s in enumerate(base) if _top(s)[2] > TALL_Z]
    jits = [_fork_jitter(rng) for _ in range(N_FORK)]   # rng drawn up front, so
    out = []                                            # the search is exact
    for n in range(N_FORK):
        b = _best_fork(base, tall, _held(out), _Field(base + out, W_PASS_FORK),
                       jits[n])
        out.append(b[2])
    for _ in range(N_SWEEP):
        moved = False
        for n in range(N_FORK):
            rest = out[:n] + out[n + 1:]
            fld = _Field(base + rest, W_PASS_FORK)
            b = _best_fork(base, tall, _held(rest), fld, jits[n])
            if b is not None and b[0] < fld.score(out[n]):
                out[n] = b[2]
                moved = True
        if not moved:
            break
    return out


# =============================================================================
# SIDE LIMBS -- outward, up, and dead just short of the next stem
# =============================================================================

N_LIMB = 9
N_LEAF = 5
LIMB_AT = (0.25, 0.75)
LIMB_CHORD = (0.80, 1.90)
LIMB_ROOT_K = (0.30, 0.46)
LIMB_CLEAR = (0.07, 0.20)          # how far short of the neighbour's skin it dies
LIMB_RISE = (0.45, 1.85)
LIMB_SHAPE = ((0.55, 1.15), (0.55, 1.55), (0.70, 1.30), (0.70, 1.85),
              (0.88, 1.20), (0.88, 1.60))
LEAF_R = (0.26, 0.40)
LIMB_PER_STEM = 2
N_AT_L = 9
N_RISE = 7
N_SWEEP = 9


W_PASS_FORK = _fork_weights()


def _limb_jitter(rng, leaf):
    return {
        "yamp": rng.u(-0.13, 0.13),
        "yph": rng.u(0.0, 1.0),
        "ydrift": rng.u(-0.07, 0.07),
        "kroot": rng.u(*LIMB_ROOT_K),
        "rtip": rng.u(0.020, 0.030) if leaf else rng.u(0.014, 0.022),
        "npts": rng.i(4, 5),
        "clear": rng.u(*LIMB_CLEAR),
        "leaf": leaf,
        "tip_r": rng.u(*LEAF_R) if leaf else 0.0,
        "xk": 0.0,                 # both chosen by the search
        "zk": 0.0,
    }


def _limb(base, p, at, end_x, end_z, j):
    par = base[p]
    p0 = point_at(par["path"], at)
    x0, y0, z0 = p0
    n = j["npts"]
    r0 = j["kroot"] * radius_at(par["radii"], at)
    rt = j["rtip"]
    ylim = Y_LEAF if j["leaf"] else Y_LIM
    base_y = j["yamp"] * math.sin(math.pi * j["yph"])
    path, radii = [p0], [r0]
    for k in range(1, n):
        t = k / (n - 1.0)
        x = x0 + (end_x - x0) * (t ** j["xk"])       # outward first ...
        z = z0 + (end_z - z0) * (t ** j["zk"])       # ... then up
        y = y0 + j["yamp"] * math.sin(math.pi * (t * 0.85 + j["yph"])) - base_y
        y += j["ydrift"] * t
        if t > 0.5:                                  # a clump is drawn back in
            f = (t - 0.5) / 0.5                      # towards the centre plane
            y = y * (1.0 - f) + _clampy(y, ylim) * f
        path.append((_clampx(x), _clampy(y, Y_LIM), z))
        radii.append(rt + (r0 - rt) * ((1.0 - t) ** 1.25))
    x, y, z = path[-1]
    path[-1] = (x, _clampy(y, ylim), z)
    return {"kind": "limb", "path": path, "radii": radii,
            "sides": 6 if par["sides"] == 8 else 5,
            "parent": p, "at": at, "tip": "leaf" if j["leaf"] else "taper",
            "tip_r": j["tip_r"]}


def _neighbours(stand, p, x, z, side, k=3):
    """The nearest few strands on `side` of x still standing at height z, as
    (distance, x, radius).

    Not just the nearest, and not only the ground stems: where stems() leaves a
    3 m void the nearest stem is out of chord range and a single-neighbour rule
    generates no limb at all, exactly where the stand most needs one.  A limb
    that dies just short of a leader reads as tangle the same way.  Ground stems
    still come first -- they are nearer by construction almost everywhere."""
    out = []
    for i, s in enumerate(stand):
        if i == p:
            continue
        for c in _cols(s, z):
            d = (c[0] - x) * side
            if d > 0.12:
                out.append((d, c[0], c[2] / LB_WOBBLE))
    out.sort()
    return out[:k]


def _best_limb(base, stand, load, fld, j, relax=False):
    """A limb's far end is not free: it has to die just short of a neighbouring
    stem, or it reads as a spike rather than as tangle.  So the end is taken
    from the neighbour and the arc's two exponents do the aiming."""
    aims = fld.holes(N_HOLE)
    best = None
    cache = {}
    for p in range(len(base)):
        if load.get(p, 0) >= LIMB_PER_STEM:
            continue
        if aims and not any(abs(point_at(base[p]["path"], 0.5)[0] - a) < 2.2
                            for _, a in aims):
            continue
        for ai in range(N_AT_L):
            at = LIMB_AT[0] + (LIMB_AT[1] - LIMB_AT[0]) * ai / (N_AT_L - 1.0)
            x0, y0, z0 = point_at(base[p]["path"], at)
            if z0 < FOOT_MIN and not relax:
                continue
            if radius_at(base[p]["radii"], at) * LIMB_ROOT_K[0] < j["rtip"] + 0.005:
                continue
            for side in (-1.0, 1.0):
                for ri in range(N_RISE):
                    ez = z0 + LIMB_RISE[0] + (LIMB_RISE[1] - LIMB_RISE[0]) \
                        * ri / (N_RISE - 1.0)
                    if ez > 8.40 or ez > _top(base[p])[2] + 0.30:
                        continue
                    key = (p, side, int(ez * 20.0))
                    nbs = cache.get(key)
                    if nbs is None:
                        nbs = _neighbours(stand, p, x0, ez, side)
                        cache[key] = nbs
                    for nb in nbs:
                        ex = nb[1] - side * (nb[2] + j["clear"])
                        if (ex - x0) * side <= 0.08 or abs(ex) > HALF_W - 0.02:
                            continue
                        for xk, zk in LIMB_SHAPE:
                            j["xk"], j["zk"] = xk, zk
                            lb = _limb(base, p, at, ex, ez, j)
                            a, b = lb["path"][0], lb["path"][-1]
                            ch = math.sqrt((b[0] - a[0]) ** 2
                                           + (b[1] - a[1]) ** 2
                                           + (b[2] - a[2]) ** 2)
                            if not (LIMB_CHORD[0] <= ch <= LIMB_CHORD[1]):
                                continue
                            if fld.harms_body(lb):
                                continue
                            sc = fld.score(lb)
                            if best is None or sc < best[0]:
                                best = (sc, p, lb)
    return best


def _load(strands):
    d = {}
    for s in strands:
        d[s["parent"]] = d.get(s["parent"], 0) + 1
    return d


def _limbs(rng, base, forks):
    jits = [_limb_jitter(rng, n < N_LEAF) for n in range(N_LIMB)]
    out = []
    for n in range(N_LIMB):
        stand = base + forks + out
        fld = _Field(stand)
        b = _best_limb(base, stand, _load(out), fld, jits[n])
        if b is None:
            b = _best_limb(base, stand, _load(out), fld, jits[n], True)
        out.append(b[2])
    for _ in range(N_SWEEP):
        moved = False
        for n in range(N_LIMB):
            rest = out[:n] + out[n + 1:]
            stand = base + forks + rest
            fld = _Field(stand)
            b = _best_limb(base, stand, _load(rest), fld, jits[n])
            if b is not None and b[0] < fld.score(out[n]):
                out[n] = b[2]
                moved = True
        if not moved:
            break
    return out


# =============================================================================
# ENTRY POINT
# =============================================================================

def limbs(rng, base):
    """The 20 forks and side limbs, in that order, parented into `base`."""
    fk = _forks(rng, base)
    lb = _limbs(rng, base, fk)
    return fk + lb


# =============================================================================
# THE MESH -- one root plate, every stem socketed into it, nothing overlapping
# =============================================================================
# ---- TUNABLES ---------------------------------------------------------------

ROOT_SIDES = 5              # NEVER 4: a 4-gon root reads as a sawn edge
ROOT_SEGS = 2               # bezier segments: out, then down
ROOT_R = (0.80, 0.30)       # multiples of nominal_r: at the weld .. at the tip
ROOT_REACH = (0.34, 0.62)   # tip distance from the trunk axis, in xy
ROOT_DEPTH = (-0.06, -0.02) # tip z: just under the soil, clear of the root plate's
                            # crown at -0.04, so the whole arch of the root is seen
ROOT_SWAY = 0.16            # how far off dead-radial a root may wander
ROOT_PULL = 0.55            # where along the reach the control point sits
ROOT_LIFT = -0.30           # control point ABOVE the chord: the root arches out
                            # of the trunk and comes down, as a buttress root does
ROOT_WOB = 0.08
ROOT_CLEAR = 2.2            # tip radii of bark the tip must clear, whatever the reach says


def _sides_for(n, count):
    """The base side of each of ``count`` roots, spread as evenly as n allows.
    A root claims that side AND its neighbour -- a root as thick as a buttress
    root is wider than one face of the trunk it leaves -- so no two bases may
    be adjacent."""
    count = max(0, min(count, n // 2))
    out, used = [], set()
    for k in range(max(count, 1)):
        want = int(round(k * n / float(max(count, 1)))) % n
        for d in range(n):
            s = (want + d) % n
            if not (s in used or (s + 1) % n in used or (s - 1) % n in used):
                used.add(s)
                used.add((s + 1) % n)
                out.append(s)
                break
    return out


def flare(m, rng, rings, nominal_r, count):
    """`count` buttress roots at a trunk's foot: short tapered tubes welded out
    of separate band quads of segment 0 of the tube `rings`, each arcing
    outward and DOWN to z in [-0.14, -0.03] (underground) where it is capped.
    Returns the list of (tip point, tip radius)."""
    n = len(rings[0])
    axis = ft._seg_axis(m, rings, 0)                       # the trunk's own line at the foot
    rad_w = nominal_r * ROOT_R[0]
    rad_t = nominal_r * ROOT_R[1]
    tips = []

    for s in _sides_for(n, count):
        patch = ft._patch_mid(m, rings[0], rings[1], ft._grid_sides(s, n, 2))
        foot = ft._patch_centre(m, patch)

        out = ft.sub(foot, axis)
        out = ft.norm((out[0], out[1], 0.0))               # straight off the bark, in plan
        wx = ft.dot(ft.sub(foot, axis), out)               # how far out the bark already is

        aim = ft.add(out, ft.cross(ft.UP, out), rng.u(-ROOT_SWAY, ROOT_SWAY))
        aim = ft.norm((aim[0], aim[1], 0.0))               # a root is never dead radial

        reach = max(rng.u(*ROOT_REACH), wx + rad_t * ROOT_CLEAR)
        drop = foot[2] - rng.u(*ROOT_DEPTH)                # how far under the foot the tip sits
        level = (axis[0], axis[1], foot[2])                # the trunk axis at the weld's height

        tip = ft.add(ft.add(level, aim, reach), ft.DOWN, drop)
        tip = (max(-5.10, min(5.10, tip[0])), max(-0.40, min(0.40, tip[1])), tip[2])
        pull = ft.add(ft.add(level, aim, wx + (reach - wx) * ROOT_PULL),
                      ft.DOWN, drop * ROOT_LIFT)           # above the chord: out flat, then down
        path = ft.bez(foot, pull, tip, ROOT_SEGS)

        root = fb._ptube(m, path, (rad_w, rad_t), ROOT_SIDES, "root",
                         start=(patch, "root"), caps=(True, False),
                         wob=ROOT_WOB, rng=rng)
        m.fan(root[-1], ft.norm(ft.sub(path[-1], path[-2])), "root")   # capped underground
        tips.append((m.centroid(root[-1]), rad_t))

    return tips


def _lift_foot(path):
    """Raise a ground stem's second path point to FOOT_H without moving the rest
    of the stem: the foot segment becomes tall enough to carry a visible root
    flare, and the point keeps the x and y the stem's own line has at that
    height, so nothing about its lean or bend changes."""
    z = ROOT_TOP_Z + FOOT_H
    if len(path) < 3 or path[2][2] <= z:
        return path
    for i in range(1, len(path) - 1):
        a, b = path[i], path[i + 1]
        if a[2] <= z <= b[2] and b[2] - a[2] > 1e-9:
            t = (z - a[2]) / (b[2] - a[2])
            p = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, z)
            return [path[0], p] + list(path[2:])
    return path


def _fit(m, patch, path, radius, sides, flat, tag):
    """Record how far inside ``patch`` the ring _ptube is about to weld there
    sits, in the patch's own plane, at the best of the 24 phases _best_ring
    will choose from. Positive is inside. Call it BEFORE the patch is claimed:
    it only measures, and it is the proof that nothing is welded into thin
    air."""
    t, ex, ez = ft.frames(path)[0]
    pn, _sx, _sy, ids = fb._patch_frame(m, patch)
    plane = (m.centroid(ids), pn)
    c = plane[0]
    px = ft.norm(ft.cross(pn, ft.UP if abs(pn[2]) < 0.9 else (1.0, 0.0, 0.0)))
    py = ft.cross(pn, px)
    flat2 = lambda q: (ft.dot(ft.sub(q, c), px), ft.dot(ft.sub(q, c), py))
    poly = [flat2(m.verts[v]) for v in ft._loop_of(m, patch)]
    best = -9.0
    for k in range(24):
        ring = ft.project_ring(fb._ring_at(path[0], ex, ez, radius, sides, flat,
                                           2.0 * math.pi * k / 24.0), t, plane)
        best = max(best, min(ft._margin(poly, flat2(q)) for q in ring))
    WELDS.append((tag, best))


def _plate(m, r, feet, foot_r):
    """The root plate: a buried log along X carrying one segment of its own per
    stem, sized to that stem's foot ring, with filler segments between. Its top
    never reaches z = -0.04, so nothing of it is ever seen; it is what makes
    the stand one mesh, as a root plate makes a stand one plant. Returns
    (rings, the plate segment index of each stem)."""
    xs, seg_of = [], []
    cut = -HALF_W
    for k, x in enumerate(feet):
        w = foot_r[k] * FOOT_FLAT * PLATE_PAD
        lo, hi = x - w, x + w
        if lo <= cut + 0.01:                       # never let two feet share a boundary
            lo = cut + 0.01
        if not xs:
            xs.append(-HALF_W)
        xs.append(lo)
        seg_of.append(len(xs) - 1)
        xs.append(hi)
        cut = hi
    xs.append(HALF_W)
    path = [(x, plate_y(x), PLATE_Z) for x in xs]
    # No wobble: a wobbled ring makes the band quads non-planar, their two
    # triangles can then wind against each other, and m.claim() loses an edge
    # of the socket boundary -- which tears a hole in the mesh. Nothing of the
    # plate is ever seen, so it has nothing to gain from being lumpy.
    return fb._ptube(m, path, (PLATE_R,), PLATE_SIDES, "root", wob=0.0), seg_of


def _foot_radii(feet, radii0):
    """Each stem's foot ring, shrunk until the plate can carry it and until it
    and its neighbour's leave the plate a segment each."""
    out = [min(r0, FOOT_MAX) for r0 in radii0]
    for k in range(len(feet) - 1):
        span = 0.90 * (feet[k + 1] - feet[k]) / (FOOT_FLAT * PLATE_PAD)
        if out[k] + out[k + 1] > span:
            s = span / (out[k] + out[k + 1])
            out[k] *= s
            out[k + 1] *= s
    return out


def _child_patch(m, rings, taken, at, aim, radius):
    """Where a fork or a limb leaves its parent: free band quads of the tube
    ``rings`` at parameter ``at``, on the side facing ``aim``. One quad when
    the limb's ring fits across it, three when it does not -- a limb welded
    into a face narrower than itself would be bridged over its own neighbours.
    Returns the patch, or None when nothing within reach is free."""
    nseg = len(rings) - 1
    seg = min(nseg - 1, max(0, int(math.floor(at * nseg))))
    n = len(rings[0])
    for d in (0, 1, -1, 2, -2):                    # walk to a segment with free sides
        s = seg + d
        if not 0 <= s < nseg:
            continue
        axis = ft._seg_axis(m, rings, s)
        c0 = m.centroid(rings[s])
        d0 = ft.sub(m.verts[rings[s][0]], c0)
        host = max(0.02, math.sqrt(ft.dot(d0, d0)))
        want = 1 if 2.2 * radius <= 2.0 * host * math.sin(math.pi / n) else 3
        order = sorted(range(n), reverse=True, key=lambda k: ft.dot(
            ft.norm(ft.sub(m.centroid(ft._band_quad(rings[s], rings[s + 1], k)), axis)), aim))
        for side in order:
            sides = ft._grid_sides(side, n, want)
            if any((s, q) in taken for q in sides):
                continue
            taken.update((s, q) for q in sides)
            return ft._patch_mid(m, rings[s], rings[s + 1], sides)
    return None


def _leaves(m, r, rings, path, radius):
    """A leaf clump grown straight off a twig's last ring, in the TWIG's own
    frame: four rings up a squashed ball and a fan over the top. ft.clump_end
    lays its rings out round world Z, which twists -- and tears -- on a limb
    that points sideways; this one closes on the ring it grows from whichever
    way the twig points."""
    d = ft.norm(ft.sub(path[-1], path[-2]))
    up = ft.UP if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)
    ex = ft.norm(ft.cross(up, d))
    ez = ft.cross(d, ex)
    tip = path[-1]
    c = ft.add(tip, d, radius * 0.55)
    c = (c[0], max(-0.30, min(0.30, c[1])), c[2])
    angs = [math.atan2(ft.dot(ft.sub(m.verts[v], tip), ez),
                       ft.dot(ft.sub(m.verts[v], tip), ex)) for v in rings[-1]]
    band = [rings[-1]]
    for lat in (-38.0, 2.0, 38.0, 66.0):
        cl, sl = math.cos(math.radians(lat)), math.sin(math.radians(lat))
        ring = []
        for a in angs:
            rr = radius * (1.0 + CLUMP_WOB * r.sf())
            p = ft.add(ft.add(ft.add(c, ex, rr * cl * math.cos(a)), ez, rr * cl * math.sin(a)),
                       d, rr * sl * 0.8)
            ring.append(m.v(p))
        band.append(ring)
    ft.loft(m, band, "leaf", want_fn=lambda p: ft.sub(p, c))
    top = m.v(ft.add(c, d, radius * 0.8 * (1.0 + CLUMP_WOB * r.sf())))
    n = len(band[-1])
    for s in range(n):
        q = (s + 1) % n
        tri = (top, band[-1][s], band[-1][q])
        m.tri(tri[0], tri[1], tri[2], ft.sub(m.centroid(tri), c), "leaf")


def _strand(m, r, s, start, zone="bark", flat=1.0):
    """One strand as a tube. ``start`` is (patch, zone). A tapered free end is
    capped at its own 0.02 m tip, which is no cut end anyone can see; a leaf
    end hands its last ring to a clump."""
    leaf = s["tip"] == "leaf"
    rings = fb._ptube(m, s["path"], s["radii"], s["sides"], zone, flat=flat,
                      start=start, caps=(start is None, not leaf), wob=WOB, rng=r)
    if leaf:
        _leaves(m, r, rings, s["path"], s["tip_r"])
    return rings


def build_geometry():
    """The stand as one mesh, plus the strand list the collider and the gap
    proof are built from."""
    m = ft._Mesh()
    r = ft._Rng(SEED)
    del WELDS[:]
    base = stems(r)
    kids = limbs(r, base)
    strands = base + kids

    feet = [s["path"][0][0] for s in base]
    foot_r = _foot_radii(feet, [s["radii"][0] for s in base])
    plate, seg_of = _plate(m, r, feet, foot_r)

    rings = [None] * len(strands)
    taken = {}
    for k, s in enumerate(base):
        seg = seg_of[k]
        patch = ft._patch_mid(m, plate[seg], plate[seg + 1],
                              ft._facing(m, plate, seg, ft.UP, 3))
        s["radii"] = [foot_r[k]] + list(s["radii"][1:])
        s["path"] = _lift_foot(s["path"])
        flat = [FOOT_FLAT] + [1.0] * (len(s["path"]) - 1)
        _fit(m, patch, s["path"], foot_r[k], s["sides"], FOOT_FLAT, "stem foot")
        rings[k] = _strand(m, r, s, (patch, "root"), flat=flat)
        taken[k] = set()
        nom = s["radii"][2] if len(s["radii"]) > 2 else s["radii"][-1]
        if nom >= FLARE_ON:
            cnt = r.i(*FLARE_N)
            flare(m, r, rings[k], nom, cnt)
            nn = len(rings[k][0])
            for side in _sides_for(nn, cnt):
                taken[k].update(((0, side), (0, (side + 1) % nn)))
    for k, s in enumerate(kids, start=len(base)):
        p = s["parent"]
        aim = ft.norm(ft.sub(s["path"][1], s["path"][0]))
        patch = _child_patch(m, rings[p], taken[p], s["at"], aim, s["radii"][0])
        if patch is None:
            raise ValueError("strand %d found no free side on parent %d" % (k, p))
        s["path"] = [ft._patch_centre(m, patch)] + list(s["path"][1:])
        _fit(m, patch, s["path"], s["radii"][0], s["sides"], 1.0, s["kind"] + " root")
        rings[k] = _strand(m, r, s, (patch, "bark"))
        taken[k] = set()

    INFO["strands"] = strands
    return ft.orient(ft._prune(m)), _collider(strands), strands   # socket bridges wound as their neighbours


# =============================================================================
# COLLIDER -- one box: the stand's footprint (HALF_W x HALF_T) by its height
# (Ryan: "the collision object looks really complicated? is it? it can just be a big rectangle.")
# =============================================================================

def _box(c, lo, hi, zone="bark"):
    """An axis-aligned box, 12 tris."""
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    p = [c.v(q) for q in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                          (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
    c.quad(p[0], p[1], p[2], p[3], ft.DOWN, zone)
    c.quad(p[4], p[5], p[6], p[7], ft.UP, zone)
    c.quad(p[0], p[1], p[5], p[4], (0.0, -1.0, 0.0), zone)
    c.quad(p[2], p[3], p[7], p[6], (0.0, 1.0, 0.0), zone)
    c.quad(p[1], p[2], p[6], p[5], (1.0, 0.0, 0.0), zone)
    c.quad(p[3], p[0], p[4], p[7], (-1.0, 0.0, 0.0), zone)


def _collider(strands):
    """One box over the whole stand: the lane's full width, the stand's
    thickness, ground to its top. The strands are what the gap proof reads;
    the collider no longer follows them."""
    c = ft._Mesh()
    _box(c, (-HALF_W, -HALF_T, 0.0), (HALF_W, HALF_T, HEIGHT), "bark")
    return c


# =============================================================================
# THE GAP PROOF -- nothing a body gets through, at any height it could be at
# =============================================================================

def _crossings(s, z):
    """Every (x, y, radius) where strand ``s`` crosses height z. A strand that
    bends back over itself is counted at each crossing. The radius is the
    smallest the wobble can make it, so a gap is never understated."""
    path, radii = s["path"], s["radii"]
    n = len(path) - 1
    out = []
    for i in range(n):
        a, b = path[i], path[i + 1]
        if abs(b[2] - a[2]) < 1e-9:
            continue
        t = (z - a[2]) / (b[2] - a[2])
        if not 0.0 <= t <= 1.0:
            continue
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t,
                    radius_at(radii, (i + t) / float(n)) * (1.0 - WOB)))
    return out


def _widest(strands, z):
    """(clearance, what it is between, how many strands stand there) at height
    z. A clearance is the distance between two strand axes IN PLAN less both
    radii -- a real opening, lean and bow included. The stand's two ends are
    measured to the lane walls at +-HALF_W: a hole beside the wall is a hole."""
    cols = sorted([c for s in strands for c in _crossings(s, z)], key=lambda c: c[0])
    if not cols:
        return 2.0 * HALF_W, "empty", 0
    pairs = ([((-HALF_W, cols[0][1], 0.0), cols[0], "wall")] +
             [(cols[k], cols[k + 1], "stem-stem") for k in range(len(cols) - 1)] +
             [(cols[-1], (HALF_W, cols[-1][1], 0.0), "wall")])
    g, kind = max(((math.hypot(b[0] - a[0], b[1] - a[1]) - a[2] - b[2], k)
                   for a, b, k in pairs), key=lambda q: q[0])
    return g, kind, len(cols)


def _gaps(band, strands, levels=PROOF_LEVELS):
    """The widest clearance anywhere in ``band``: (gap, z, kind, strands)."""
    lo, hi = band[0], band[1]
    worst = (0.0, lo, "", 0)
    for i in range(levels + 1):
        z = lo + (hi - lo) * i / float(levels)
        g, kind, n = _widest(strands, z)
        if g > worst[0]:
            worst = (g, z, kind, n)
    return worst


# =============================================================================
# SHEETS -- the forest's own sheets, box-projected (lib/texel.py)
# =============================================================================
# The stand's polygons carry exactly three zones: bark (stems, forks, limbs),
# root (the buttress flares and the buried plate) and leaf (the few clumps).
# Each takes forest_build's painter AND its seed, so the painted image is the
# one forest.glb wears -- no second palette to drift, no copy-pasted painter.
# Only the projection differs: "box", because a prop authored about its own
# base centre has no ring for "cyl" to close round (see the module docstring).
CLASSES = ("bark", "leaf", "root")


def _sheet(cls):
    src = fb.SHEETS[cls]
    return tx.Sheet(cls, src.paint, mpt=src.mpt, size=src.size, mode="box",
                    roughness=src.roughness, metallic=src.metallic,
                    cull=src.cull, seed=src.seed, emissive=src.emissive)


SHEETS = {cls: _sheet(cls) for cls in CLASSES}
TEX_ARGS = dict(use_files=ft.USE_TEXTURE_FILES, tex_dir=os.path.join(HERE, ft.TEX_DIR))


# =============================================================================
# BUILD
# =============================================================================

def build():
    m, c, strands = build_geometry()
    albedo, emissive = ft.sheet("forest_atlas", ft.paint_atlas)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    INFO["albedo"], INFO["emissive"] = albedo, emissive   # the in-scene shot's tree copy

    ob = m.object(OBJECT_NAME)
    classes = list(m.zones)
    unknown = sorted(set(classes) - set(SHEETS))
    if unknown:
        raise ValueError("forest_bars: no Sheet for zone(s) %s" % ", ".join(unknown))
    tx.unwrap(ob, classes, SHEETS, seed=1)
    order = tx.finish(ob, classes, tx.materials("forest", SHEETS, **TEX_ARGS))
    tx.report(SHEETS)
    print("MDL STATS surfaces=%d order=%s" % (len(ob.data.materials), ",".join(order)))

    coll = c.object(COLLIDER_NAME)
    coll.hide_render = True
    print("MDL STATS visual_tris=%d collision_tris=%d" % (len(ob.data.polygons), len(coll.data.polygons)))
    print("MDL STATS width=%.2f height=%.2f strands=%d" % (2.0 * HALF_W, HEIGHT, len(strands)))
    gap, gz, kind, n = _gaps(BODY, strands)
    print("MDL STATS body %.2f..%.2f widest_gap=%.3f (%s at z=%.2f, %d strands) limit=%.2f %s"
          % (BODY[0], BODY[1], gap, kind, gz, n, BODY[2], "OK" if gap <= BODY[2] else "OVER"))
    gap, gz, kind, n = _gaps(UPPER, strands)
    print("MDL STATS canopy %.2f..%.2f widest=%.3f (%s at z=%.2f, %d strands) -- not a gate"
          % (UPPER[0], UPPER[1], gap, kind, gz, n))
    return [ob, coll]


def _in_scene_render(spec, objects):
    """Render-only rig: a 1.8 m proxy beside the fixture, then the fixture on
    the lane inside the real forest. Runs after the .glb export, so nothing
    made here is ever exported -- and everything made here is deleted again,
    because mdl.render() runs AFTER this and must see a clean scene."""
    if bpy is None:
        return

    visual, collider = objects[0], objects[1]
    collider.hide_render = True

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    mdl._try(scene.eevee, "taa_render_samples", int(spec.get("samples", 64)))
    mdl._try(scene.eevee, "use_shadows", True)
    mdl._try(scene.eevee, "use_raytracing", True)
    mdl._try(scene.eevee, "shadow_ray_count", 2)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")

    out_dir = spec.get("out_dir", ".")
    os.makedirs(out_dir, exist_ok=True)
    made = []                       # every object this hook creates; all deleted below

    def keep(ob):
        made.append(ob)
        return ob

    def sun_lamp(name, bearing, elevation, energy, shadow, aim, tint):
        ld = bpy.data.lights.new(name, type="SUN")
        ld.energy, ld.color = energy, tint
        mdl._try(ld, "use_shadow", shadow)
        mdl._try(ld, "angle", math.radians(1.5))
        lamp = keep(mdl._link(bpy.data.objects.new(name, ld)))
        a = math.radians(-bearing)
        e = math.radians(elevation)
        lamp.location = (aim.location[0] + math.cos(e) * math.cos(a) * 120.0,
                         aim.location[1] + math.cos(e) * math.sin(a) * 120.0,
                         aim.location[2] + math.sin(e) * 120.0)
        con = lamp.constraints.new(type="TRACK_TO")
        con.target, con.track_axis, con.up_axis = aim, "TRACK_NEGATIVE_Z", "UP_Y"
        return lamp

    def rig(prefix):
        """A camera aimed the only legal way: a TRACK_TO on an empty."""
        target = keep(mdl._link(bpy.data.objects.new(prefix + "Target", None)))
        cam = keep(mdl._link(bpy.data.objects.new(prefix + "Cam",
                                                  bpy.data.cameras.new(prefix + "Cam"))))
        con = cam.constraints.new(type="TRACK_TO")
        con.target, con.track_axis, con.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"
        return cam, target

    def shot(stem, cam, target, loc, tgt, lens, res):
        scene.camera = cam
        cam.data.type = "PERSP"
        cam.data.lens = lens
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = int(res[0]), int(res[1])
        bpy.context.view_layer.update()          # the constraint has not solved yet
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, stem))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    # ------------------------------------------------------------------ scale
    # The fixture sits at the origin here: bound_box is world space.
    xs = [v[0] for v in visual.bound_box]
    zs = [v[2] for v in visual.bound_box]
    half_x, top_z = max(abs(min(xs)), abs(max(xs))), max(zs)
    px = half_x + 0.95                       # the proxy stands clear of the fixture

    mdl._try(scene.view_settings, "exposure", 0.0)
    world = bpy.data.worlds.new("ScaleSky")
    scene.world = world
    world.use_nodes = True
    wbg = world.node_tree.nodes["Background"]
    wbg.inputs[0].default_value = (0.42, 0.46, 0.44, 1.0)
    wbg.inputs[1].default_value = 0.85

    bpy.ops.mesh.primitive_plane_add(size=60.0, location=(0.0, 0.0, -0.004))
    plane = keep(bpy.context.active_object)
    plane.name = "ScaleGround"
    mdl.finish(plane, mdl.flat_material("ScaleGround", (0.26, 0.27, 0.24, 1.0)))

    proxy = keep(mdl.box("ScaleProxy", (px - 0.3, -0.15, 0.0), (px + 0.3, 0.15, 1.8)))
    mdl.finish(proxy, mdl.flat_material("ProxyGreen", (0.1, 0.9, 0.2, 1.0)))

    aim = keep(mdl._link(bpy.data.objects.new("ScaleAim", None)))
    aim.location = (px * 0.5, 0.0, 1.0)
    sun_lamp("ScaleKey", 300.0, 46.0, 4.2, True, aim, (1.0, 0.96, 0.86))
    sun_lamp("ScaleFill", 120.0, 34.0, 1.5, False, aim, (0.9, 0.96, 1.0))

    cam, target = rig("Scale")
    cx = px * 0.5
    framed = max(top_z, 1.8) * 0.5 + 0.25
    shot("scale", cam, target,
         (2.0, -17.5, 1.65), (0.6, 0.0, max(framed, 3.8)), 35.0, (1200, 900))

    for ob in list(made):                    # nothing from the scale shot may reach the forest
        bpy.data.objects.remove(ob, do_unlink=True)
    made = []

    # --------------------------------------------------------------- in-scene
    m, _coll, _rays = fb.build_geometry()
    ground = keep(m.object(fb.OBJECT_NAME))
    gclasses = list(m.zones)                 # the ground wears what forest.glb wears, so the
    tx.unwrap(ground, gclasses, fb.SHEETS, seed=1)   # shot answers "does the bark match?"
    tx.finish(ground, gclasses, tx.materials(
        fb.NAME, fb.SHEETS, names={c: "ForestScene_" + c for c in fb.SHEETS}, **TEX_ARGS))
    keep(ft.build_render_copy(INFO["albedo"], INFO["emissive"]))

    # The fixture on the lane: local +X onto radial(BEARING), local +Y onto tangent.
    for ob in (visual, collider):
        ob.rotation_euler = (0.0, 0.0, math.radians(-BEARING))
        ob.location = ft.pol(BEARING, 52.0, fb.DECK_Z)

    mdl._try(scene.view_settings, "exposure", fb.REVIEW_EXPOSURE)
    world = bpy.data.worlds.new("ForestSceneSky")
    scene.world = world
    world.use_nodes = True
    wbg = world.node_tree.nodes["Background"]
    wbg.inputs[0].default_value = (fb.REVIEW_SKY[0], fb.REVIEW_SKY[1], fb.REVIEW_SKY[2], 1.0)
    wbg.inputs[1].default_value = fb.REVIEW_WORLD

    sb, se = fb.SUN
    aim = keep(mdl._link(bpy.data.objects.new("ForestAim", None)))
    aim.location = (0.0, 0.0, 20.0)
    sun_lamp("ForestSun", sb, se, fb.REVIEW_SUN, True, aim, (1.0, 0.96, 0.84))
    sun_lamp("ForestFill", sb + 180.0, 40.0, fb.REVIEW_FILL, False, aim, (0.9, 1.0, 0.9))

    # One camera, on the lane, ~10 m round on the START side (bearing 4 against
    # the fixture's 353), looking back down the lane toward the finish: the gate
    # stands in the near middle of the frame with the lane running away past it.
    cam, target = rig("Forest")
    eye = fb.DECK_Z + fb.EYE_H
    shot("inscene", cam, target,
         ft.pol(BEARING + 13.2, 52.0, eye),          # 12.0 m round the lane, on the start side
         ft.pol(350.5, 51.0, fb.DECK_Z + 3.8), 24.0, (1400, 900))

    # ------------------------------------------------------------------ clean
    for ob in made:
        bpy.data.objects.remove(ob, do_unlink=True)
    for ob in (visual, collider):
        ob.location = (0.0, 0.0, 0.0)
        ob.rotation_euler = (0.0, 0.0, 0.0)
    mdl._try(scene.view_settings, "exposure", 0.0)
    scene.camera = None
    bpy.context.view_layer.update()


def _check():
    import forest_check
    m, c, strands = build_geometry()
    m.compact()
    c.compact()
    forest_check.prove(m, NAME)
    forest_check.components_report(m)
    kinds = {}
    for s in strands:
        kinds[s["kind"]] = kinds.get(s["kind"], 0) + 1
    print("STAND %s leaves=%d" % (kinds, sum(1 for s in strands if s["tip"] == "leaf")))
    tags = {}
    for tag, margin in WELDS:
        tags.setdefault(tag, []).append(margin)
    print("WELDS " + " ".join("%s=%d(min %.4f)" % (t.replace(" ", "_"), len(v), min(v))
                              for t, v in sorted(tags.items())))
    gap, gz, kind, n = _gaps(BODY, strands)
    print("GAPS BODY %.2f..%.2f widest=%.3f (%s at z=%.2f, %d strands) limit=%.2f %s"
          % (BODY[0], BODY[1], gap, kind, gz, n, BODY[2], "OK" if gap <= BODY[2] else "OVER"))
    gap, gz, kind, n = _gaps(UPPER, strands)
    print("GAPS CANOPY %.2f..%.2f widest=%.3f (%s at z=%.2f, %d strands) -- not a gate"
          % (UPPER[0], UPPER[1], gap, kind, gz, n))
    for z in (0.3, 1.0, 1.8, 2.6, 3.4, 4.2, 5.0, 5.8, 6.6, 7.4, 8.0, 8.2):
        g, kind, n = _widest(strands, z)
        print("  z=%4.2f strands=%2d widest=%.3f (%s)" % (z, n, g, kind))
    for name, mm in ((NAME, m), ("coll", c)):
        zones = {}
        for z in mm.zones:
            zones[z] = zones.get(z, 0) + 1
        lo = [min(v[k] for v in mm.verts) for k in range(3)]
        hi = [max(v[k] for v in mm.verts) for k in range(3)]
        print("%s tris=%d verts=%d zones=%s bbox=%s..%s"
              % (name, len(mm.faces), len(mm.verts), zones,
                 ["%.3f" % x for x in lo], ["%.3f" % x for x in hi]))


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        _check()
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_in_scene_render)
