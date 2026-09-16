"""forest_bars -- Map 3's start/finish gate: the forest's answer to map 1's
hell-rock screen.

The map's own branches grown into a gate. A fallen log lies across the lane as
the sill; two thick living end posts rise out of it to the head; a lintel log
lies across their tops; nineteen BRANCHES are socketed into the sill's top
quads and the lintel's underside quads; two lashing rails tie them at mid
height, welded into the posts; four leaf sprays break out of the posts where
the frame is still living wood. forest_build's `_fence()` idiom, scaled into a
gate and given real wood.

A bar is a branch, not a bar: it leaves the sill thick and reaches the lintel
thin, losing most of its girth in its first third; it bows through the gate's
thickness and wanders across it, with one or two kinks where it changed its
mind; it swells at its knots; short stubs stick out of it where side branches
were cut off; some of them fork near the top, the second limb lashed to the
front of the lintel. The lintel's lane boundaries drift across the gate, so no
two bars stand at the same angle and the screen is a fan, not a comb. Every
number of every bar comes off the one seed, so no two are alike and the model
is byte-identical every rebuild.

10.6 m across (Blender X), 8.5 m tall, 0.8 m thick (Blender Y). ORIGIN IS THE
BASE CENTRE: z = 0 is the ground. Blender +X -> Godot +X, +Z -> Godot +Y,
+Y -> Godot -Z, so the scene drops it in where rock_bars.glb goes.

ONE CONTIGUOUS mesh (ForestBars), one surface (the forest atlas): the posts
grow out of the sill's top, the bars tie the sill to the lintel, the rails and
the sprays grow out of the posts. Nothing merely overlaps its host.
ForestBarsCollision rides as a `-colonly` node: the sill, the lintel, the two
posts, one box per bar spanning that bar's widest reach, and the two rails.

    tools/modelling/model build forest_bars
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
if bpy is not None:
    import mdl  # noqa: E402

import forest_tree_build as ft  # noqa: E402  the shared library: rng, mesh, atlas, tubes
import forest_build as fb  # noqa: E402  _ptube, _fence's idiom, the forest for the in-scene shot

# =============================================================================
# TUNABLES
# =============================================================================

NAME = "forest_bars"
OBJECT_NAME = "ForestBars"
COLLIDER_NAME = "ForestBarsCollision-colonly"
FACING_YAW = 0.0

HALF_W = 5.3                # 10.6 m across the lane, Blender X
HEIGHT = 8.5
MAX_GAP = 0.38              # nothing may be passable wider than this, anywhere
BEARING = 353.0             # where marble.tscn puts the bars: between finish 345 and start 5

SEED = 3530417

# ---- the sill: a fallen log lying across the lane, its ends the model's ends
SILL_SIDES = 6
SILL_R = (0.370, 0.360, 0.342)   # thick at the lip end, tapering to the wall end
SILL_WOB = 0.05

# ---- the bars: one lane each, the sill and lintel cut into one segment per bar
NBARS = 20
BAR_HALF = 4.02             # the outermost bar centres
BAR_WOB = 0.15
BAR_SIDES = 4
BAR_PTS = 7                 # path points per branch: six segments to bend over
BAR_R = (0.130, 0.102)      # foot radius .. head radius, before the per-bar scatter
BAR_SCATTER = (0.84, 1.08)  # every branch its own girth
BAR_TAPER = 1.75            # >1: the branch loses its thickness low down, as wood does
BAR_BOW = (-0.28, -0.14)    # the bow through the gate's thickness, all one way
BAR_WANDER = (0.020, 0.040) # the branch's own wander, X and Y, on top of the bow
BAR_KINKS = (1, 2)          # sharp changes of direction per branch
BAR_KINK = (0.024, 0.052)  # ... and how far each one throws it
KNOTS = (1, 3)              # radius swellings per branch: where a limb once left
KNOT_SWELL = (0.16, 0.34)
LEAN = 0.13                 # the lintel lane boundaries' drift: the fan, not the comb

# ---- the knots' stubs: cut side branches sticking out of a bar
STUBS = (0, 2)              # per branch
STUB_LEN = (0.13, 0.24)
STUB_R = (0.40, 0.52)       # multiple of the bar's radius where it leaves
STUB_SIDES = 3              # a nub, three-sided: four bridges into the bar's quad worse
STUB_SEGS = 2               # bezier segments: the one kink on the way out
HALF_T = 0.40               # the gate is 0.8 m thick: nothing may reach past this

# ---- the forks: a second limb near the top, welded to the lintel's front face
FORK_EVERY = 4              # every FORK_EVERY-th branch forks
FORK_SEG = 4                # the segment the fork leaves at (of BAR_PTS - 1)
FORK_R = 0.46               # multiple of the bar's radius there
FORK_SIDES = 3              # three: four bridges into the host's quad worse, and costs more
FORK_SEGS = 3               # bezier segments up and over to the lintel
FORK_T = 0.42               # the control point sits toward the root: it leaves, then arrives
FORK_LEAN = 0.18            # how far off the chord, along the host's own outward normal
FORK_RISE = 0.12            # ... and along the host tube, so it goes up and over
FORK_WANDER = 0.04          # hand-grown, never twice the same

# ---- the end posts: living wood, a blade wide across the lane and thin through it
POST_SIDES = 6
# The post's own height table: SHORT segments where a rail or a spray is welded
# on, so the socket patch is the size of the ring that lands in it and the
# bridging makes no slivers. POST_R is the half thickness in Y at each point.
POST_T = (0.0, 0.09, 0.15, 0.36, 0.42, 0.62, 0.68, 0.87, 0.93, 1.0)
POST_R = (0.255, 0.272, 0.278, 0.282, 0.278, 0.272, 0.266, 0.254, 0.246, 0.238)
POST_FLAT = 1.75            # half width in X = R * FLAT: a blade, wide toward the lintel
POST_WOB = 0.05
POST_TOP = 8.06             # capped just inside the lintel, which rests on it
POST_WANDER = 0.025

# ---- the lintel: a second log across the posts' tops, its top at HEIGHT
LIN_SIDES = 6
LIN_R = (0.330, 0.345, 0.318)
LIN_WOB = 0.05

# ---- the lashing rails: thin, welded into the posts, crossing behind the bars
RAIL_SEGS = (3, 5)          # the post's short segments the rails are welded into
RAIL_R = 0.14
RAIL_SIDES = 5
RAIL_WOB = 0.08
RAIL_SAG = 0.06

# ---- the leaf sprays: (post sign, post segment, branch reach in X, rise, clump radius)
SPRAYS = ((-1, 7, 0.66, 0.70, 0.32), (1, 7, 0.62, 0.66, 0.30),
          (-1, 1, 0.64, 0.74, 0.31), (1, 1, 0.60, 0.70, 0.29))
SPRAY_CLUMP_WOB = 0.18      # a clump reaches rad * (1 + wob): 0.32 is all 0.8 m of thickness allows
SPRAY_SIDES = 4
SPRAY_R = (0.085, 0.055)
SPRAY_SEGS = 2

WELDS = []                  # (tag, margin) -- how far inside its patch each socket ring sits
INFO = {}                   # what the renders need

# ---- derived: the lane layout -----------------------------------------------
BAR_PITCH = 2.0 * BAR_HALF / (NBARS - 1)
BAR_EDGE = BAR_HALF + 0.5 * BAR_PITCH        # the bar zone's outer boundary on the sill
POST_X = 0.5 * (HALF_W + BAR_EDGE)           # the post axis: centred on its two sill segments
SILL_Z = math.cos(math.radians(30.0)) * max(SILL_R) * (1.0 + SILL_WOB)
LIN_Z = HEIGHT - math.cos(math.radians(30.0)) * max(LIN_R) * (1.0 + LIN_WOB)


# =============================================================================
# WELD DIAGNOSTIC -- the proof that every socket ring landed inside its patch
# =============================================================================

def _fit(m, patch, path, radius, sides, flat, tag, at_start=True):
    """Record how far inside ``patch`` the ring _ptube is about to weld there
    sits, measured in the patch's own plane (positive = inside). Call this
    BEFORE the patch is claimed; it only measures."""
    fr = ft.frames(path)
    t, ex, ez = fr[0] if at_start else fr[-1]
    p = path[0] if at_start else path[-1]
    pts = fb._ring_at(p, ex, ez, radius, sides, flat, 0.0)
    pn, _sx, _sy, ids = fb._patch_frame(m, patch)
    plane = (m.centroid(ids), pn)
    ring = ft.project_ring(pts, t, plane)
    loop = ft._loop_of(m, patch)
    c = plane[0]
    px = ft.norm(ft.cross(pn, ft.UP if abs(pn[2]) < 0.9 else (1.0, 0.0, 0.0)))
    py = ft.cross(pn, px)
    flat2 = lambda q: (ft.dot(ft.sub(q, c), px), ft.dot(ft.sub(q, c), py))
    poly = [flat2(m.verts[v]) for v in loop]
    WELDS.append((tag, min(ft._margin(poly, flat2(q)) for q in ring)))


def _band(m, rings, segs, sides):
    """The patch of ``sides`` adjacent tube faces across ``segs`` consecutive
    segments: a rectangle of quads whose boundary is one loop."""
    out = []
    for seg in segs:
        out += [ft._band_quad(rings[seg], rings[seg + 1], s) for s in sides]
    return out


# =============================================================================
# THE GATE
# =============================================================================

def stub(m, r, rings, seg, side, length, rad, fit=None):
    """A cut side-branch knot: a short tapered tube welded out of the band
    quad (rings[seg], rings[seg+1], side) of an existing bark tube, angled
    away from the tube axis with an upward tilt and one kink, capped at its
    free end. Returns the tip point."""
    patch = ft._patch_mid(m, rings[seg], rings[seg + 1], [side])
    root = ft._patch_centre(m, patch)
    out = ft.norm(ft.sub(root, ft._seg_axis(m, rings, seg)))          # straight off the bark
    rise = ft.norm(ft.add(ft.UP, out, -ft.dot(ft.UP, out)))           # up, squared to `out`
    tilt = r.u(0.24, 0.40)                                            # how hard it lifts
    kink = r.u(0.46, 0.60)                                            # where the one kink sits
    aim = ft.norm(ft.add(out, rise, tilt))
    tip = ft.add(root, aim, length)
    pull = ft.add(ft.add(root, out, length * kink),                   # control below the chord:
                  rise, length * tilt * kink * 0.35)                  # leaves flat, then kinks up
    path = ft.bez(root, pull, tip, STUB_SEGS)                         # one kink on the way out
    if fit is not None:
        fit(patch, path, rad, STUB_SIDES, 1.0, "stub root", True)     # measure before the patch is claimed
    knot = fb._ptube(m, path, (rad, rad * 0.45), STUB_SIDES, "bark",
                     start=(patch, "bark"), caps=(True, False), wob=0.12, rng=r)
    m.fan(knot[-1], ft.norm(ft.sub(path[-1], path[-2])), "bark")      # the saw cut at the free end
    return m.centroid(knot[-1])


def fork(m, r, rings, seg, side, target_patch, rad, fit=None):
    """The second limb of a forked branch: a tapered tube out of the band
    quad (rings[seg], rings[seg+1], side) of an existing bark tube, curving
    up and over to weld into ``target_patch`` (a list of already-registered
    quads elsewhere in m). Returns the limb's rings."""
    patch = ft._patch_mid(m, rings[seg], rings[seg + 1], [side])
    root = ft._patch_centre(m, patch)
    tip = ft._patch_centre(m, target_patch)

    # The host's own frame at that band: outward off the tube, and along it.
    away = ft.norm(ft.sub(root, ft._seg_axis(m, rings, seg)))
    along = ft.norm(ft.sub(m.centroid(rings[seg + 1]), m.centroid(rings[seg])))

    chord = ft.sub(tip, root)
    span = math.sqrt(ft.dot(chord, chord))
    ch = ft.norm(chord)

    # Only the part of ``away`` that leaves the chord bends the curve; the rest
    # would just lengthen a strut. If the fork points straight out of its host,
    # the host's own axis supplies the bend instead.
    lean = ft.add(away, ch, -ft.dot(away, ch))
    if ft.dot(lean, lean) < 1e-6:
        lean = ft.add(along, ch, -ft.dot(along, ch))
    lean = ft.norm(lean)

    pull = ft.lerp(root, tip, FORK_T)
    pull = ft.add(pull, lean, span * FORK_LEAN)
    pull = ft.add(pull, along, span * FORK_RISE)
    pull = ft.add(pull, (r.sf(), r.sf(), r.sf()), span * FORK_WANDER)

    path = ft.bez(root, pull, tip, FORK_SEGS)

    if fit is not None:                      # measure BEFORE either patch is claimed
        fit(patch, path, rad, FORK_SIDES, 1.0, "fork root", True)
        fit(target_patch, path, rad * 0.7, FORK_SIDES, 1.0, "fork head", False)

    return fb._ptube(m, path, (rad, rad * 0.7), FORK_SIDES, "bark",
                     start=(patch, "bark"), end=(target_patch, "bark"),
                     wob=0.1, rng=r)


def _sill(m, r):
    """The fallen log across the lane: end to end, capped, lying on the ground.
    Its path breaks at every bar lane boundary and at the two post patches, so
    every bar and every post has its own quad to grow out of. Its two end
    segments are the posts' patches; the rest are the bar lanes."""
    xs = [-HALF_W] + [-BAR_EDGE + BAR_PITCH * j for j in range(NBARS + 1)] + [HALF_W]
    path = [(x, 0.0, SILL_Z) for x in xs]
    return fb._ptube(m, path, SILL_R, SILL_SIDES, "bark", wob=SILL_WOB, rng=r)


def _lean(k):
    """How far bar ``k``'s lane boundary drifts on the LINTEL relative to the
    sill. A half-wave across the gate plus a settled wobble: the heads fan out
    while neighbours stay within a boundary-step of each other, so the gap the
    fan opens is bounded and the proof can hold it under MAX_GAP."""
    u = k / float(NBARS)
    return LEAN * math.sin(math.pi * (u - 0.5)) + LEAN * 0.22 * math.sin(2.4 * math.pi * u + 1.1)


def _lintel(m, r):
    """The head rail: a second log across the posts' tops, its top at HEIGHT.
    One segment per bar, so every bar has its own underside quad -- and the
    boundaries between those segments drift (``_lean``), so a bar's head does
    not stand over its foot and no two bars are parallel."""
    xs = [-HALF_W] + [-BAR_EDGE + BAR_PITCH * j + _lean(j) for j in range(NBARS + 1)] + [HALF_W]
    path = [(x, 0.0, LIN_Z) for x in xs]
    return fb._ptube(m, path, LIN_R, LIN_SIDES, "bark", wob=LIN_WOB, rng=r)


def _post(m, r, sign, sill):
    """A living end post out of the sill's top: the log's end segment, three
    faces of it around, rising to POST_TOP where the lintel lands on it."""
    seg = 0 if sign < 0 else len(sill) - 2
    sides = ft._facing(m, sill, seg, ft.UP, 3)
    patch = ft._patch_mid(m, sill[seg], sill[seg + 1], sides)
    base = ft._patch_centre(m, patch)
    n = len(POST_T) - 1
    path = [(sign * POST_X + (0.0 if i in (0, n) else r.u(-POST_WANDER, POST_WANDER)),
             0.0 if i in (0, n) else r.u(-POST_WANDER, POST_WANDER),
             base[2] + (POST_TOP - base[2]) * POST_T[i]) for i in range(n + 1)]
    _fit(m, patch, path, POST_R[0], POST_SIDES, POST_FLAT, "post foot")
    return fb._ptube(m, path, POST_R, POST_SIDES, "bark", start=(patch, "bark"),
                     flat=POST_FLAT, wob=POST_WOB, rng=r)


def _branch(r, foot, top):
    """One bar's shape: the path from its sill quad to its lintel quad and the
    radius table along it. Irregular taper (thick foot, thin head, most of the
    girth lost in the first third), a bow through the gate's thickness, its own
    wander across it, one or two kinks, and a swelling at each knot. Every
    offset is scaled by sin(pi*u), so both welded ends stay exactly where the
    socket put them. Returns (path, radii)."""
    n = BAR_PTS - 1
    bow = r.u(*BAR_BOW)
    ax, ay = r.u(*BAR_WANDER), r.u(*BAR_WANDER) * 0.7
    fx, fy = r.u(1.1, 2.7), r.u(0.9, 2.1)
    px, py = r.u(0.0, 2.0 * math.pi), r.u(0.0, 2.0 * math.pi)
    kinks = {}
    for _ in range(r.i(*BAR_KINKS)):
        a, d = r.u(0.0, 2.0 * math.pi), r.u(*BAR_KINK)
        kinks[r.i(1, n - 1)] = (d * math.cos(a), d * math.sin(a) * 0.7)
    r0 = BAR_R[0] * r.u(*BAR_SCATTER)
    r1 = BAR_R[1] * r.u(*BAR_SCATTER)
    knots = set(r.i(1, n - 1) for _ in range(r.i(*KNOTS)))
    path, radii = [], []
    for i in range(n + 1):
        u = i / float(n)
        s = math.sin(math.pi * u)                    # 0 at both sockets
        kx, ky = kinks.get(i, (0.0, 0.0))
        p = ft.lerp(foot, top, u)
        path.append((p[0] + (ax * math.sin(fx * math.pi * u + px) + kx) * s,
                     p[1] + (bow + ay * math.sin(fy * math.pi * u + py) + ky) * s,
                     p[2]))
        rad = (r0 + (r1 - r0) * (u ** (1.0 / BAR_TAPER))) * (1.0 + r.u(-0.05, 0.05))
        radii.append(rad * (1.0 + r.u(*KNOT_SWELL)) if i in knots else rad)
    return path, radii, sorted(knots)


def _lintel_front(m, lin, lseg):
    """The lintel segment's lower-FRONT face: the quad beside the one the bar's
    head took, the one leaning out of the gate. A fork's second limb lands here,
    which is why a fork costs no extra lintel geometry."""
    down = ft._facing(m, lin, lseg, ft.DOWN, 1)[0]
    cand = [(down + 1) % LIN_SIDES, (down - 1) % LIN_SIDES]
    best = min(cand, key=lambda t: m.centroid(ft._band_quad(lin[lseg], lin[lseg + 1], t))[1])
    return [ft._band_quad(lin[lseg], lin[lseg + 1], best)]


def _stub_len(m, rings, seg, side, want):
    """``want``, shortened if a stub that long would poke out of the gate's own
    0.8 m thickness: a knot is a nub on the branch, never a spike in the lane."""
    root = ft._patch_centre(m, ft._patch_mid(m, rings[seg], rings[seg + 1], [side]))
    out = ft.norm(ft.sub(root, ft._seg_axis(m, rings, seg)))
    if abs(out[1]) < 1e-6:
        return want
    return max(0.07, min(want, (HALF_T - abs(root[1])) / abs(out[1])))


def _bars(m, r, sill, lin):
    """One branch per lane: socketed into the sill's top quad and the lintel's
    underside quad, shaped by _branch, knotted with cut stubs, and every
    FORK_EVERY-th one forked near the top into the lintel's front face.
    Returns (path, radii, extra) per bar -- ``extra`` is every point the
    collider must still cover (the fork limb)."""
    out = []
    fit = lambda patch, pth, rad, sd, fl, tag, at_start: _fit(m, patch, pth, rad, sd, fl, tag, at_start)
    for k in range(NBARS):
        sseg = lseg = 1 + k
        sq = [ft._band_quad(sill[sseg], sill[sseg + 1], ft._facing(m, sill, sseg, ft.UP, 1)[0])]
        lq = [ft._band_quad(lin[lseg], lin[lseg + 1], ft._facing(m, lin, lseg, ft.DOWN, 1)[0])]
        path, radii, knots = _branch(r, m.centroid(sq[0]), m.centroid(lq[0]))
        _fit(m, sq, path, radii[0], BAR_SIDES, 1.0, "bar foot")
        _fit(m, lq, path, radii[-1], BAR_SIDES, 1.0, "bar head", at_start=False)
        rings = fb._ptube(m, path, radii, BAR_SIDES, "bark", start=(sq, "bark"), end=(lq, "bark"),
                          wob=BAR_WOB, rng=r)
        extra, taken = [], set()            # (seg, side): a band quad is claimed once
        if k % FORK_EVERY == 2:
            side = ft._facing(m, rings, FORK_SEG, (1.0 if k % 2 else -1.0, -0.2, 0.0), 1)[0]
            rad = ft._at(radii, (FORK_SEG + 0.5) / float(BAR_PTS - 1)) * FORK_R
            limb = fork(m, r, rings, FORK_SEG, side, _lintel_front(m, lin, lseg), rad, fit=fit)
            extra = [m.centroid(ring) for ring in limb]
            taken.add((FORK_SEG, side))
        for _ in range(r.i(*STUBS)):            # a stub leaves at a knot, where one did
            i = r.pick(knots) if knots else r.i(1, BAR_PTS - 2)
            seg = min(BAR_PTS - 2, max(0, i - 1))
            s0 = r.i(0, BAR_SIDES - 1)          # walk from a drawn side to the first free one
            side = next((s for s in ((s0 + d) % BAR_SIDES for d in range(BAR_SIDES))
                         if (seg, s) not in taken), None)
            if side is None:
                continue
            taken.add((seg, side))
            rad = ft._at(radii, (seg + 0.5) / float(BAR_PTS - 1)) * r.u(*STUB_R)
            stub(m, r, rings, seg, side, _stub_len(m, rings, seg, side, r.u(*STUB_LEN)), rad, fit=fit)
        out.append((path, radii, extra))
    return out


def _rails(m, r, posts):
    """Two lashing rails across the gate, each welded into a patch on the inner
    face of both posts: they tie the bars at mid height."""
    out = []
    for seg in RAIL_SEGS:
        ends = []
        for sign, prings in posts:
            sides = ft._facing(m, prings, seg, (-sign, 0.0, 0.0), 3)
            ends.append((ft._patch_mid(m, prings[seg], prings[seg + 1], sides), sign))
        left = ends[0] if ends[0][1] < 0 else ends[1]
        right = ends[1] if ends[1][1] > 0 else ends[0]
        a = ft._patch_centre(m, left[0])
        b = ft._patch_centre(m, right[0])
        path = [a] + [ft.add(ft.lerp(a, b, t), (0.0, r.u(-0.02, 0.02), -RAIL_SAG * math.sin(math.pi * t)))
                      for t in (0.25, 0.5, 0.75)] + [b]
        _fit(m, left[0], path, RAIL_R, RAIL_SIDES, 1.0, "rail end")
        _fit(m, right[0], path, RAIL_R, RAIL_SIDES, 1.0, "rail end", at_start=False)
        fb._ptube(m, path, (RAIL_R, RAIL_R * 0.95, RAIL_R), RAIL_SIDES, "bark",
                  start=(left[0], "bark"), end=(right[0], "bark"), wob=RAIL_WOB, rng=r)
        out.append((a, b))
    return out


def _sprays(m, r, posts):
    """A short branch out of a post's inner face, ending in a leaf clump: the
    frame is living wood and it is still in leaf."""
    byside = dict((sign, prings) for sign, prings in posts)
    for sign, seg, reach, rise, rad in SPRAYS:
        prings = byside[sign]
        sides = ft._facing(m, prings, seg, (-sign, 0.0, 0.0), 3)
        patch = ft._patch_mid(m, prings[seg], prings[seg + 1], sides)
        root = ft._patch_centre(m, patch)
        inward = (-sign, 0.0, 0.0)
        pull = ft.add(ft.add(root, inward, reach * 0.62), ft.UP, rise * 0.28)
        tip = ft.add(ft.add(root, inward, reach), ft.UP, rise)
        path = ft.bez(root, pull, tip, SPRAY_SEGS)
        _fit(m, patch, path, SPRAY_R[0], SPRAY_SIDES, 1.0, "spray root")
        rings = fb._ptube(m, path, SPRAY_R, SPRAY_SIDES, "bark", start=(patch, "bark"),
                          caps=(True, False), wob=0.1, rng=r)
        centre = (tip[0], 0.0, tip[2] + rad * 0.55)     # on the gate's centre plane: |y| <= 0.4
        ft.clump_end(m, ft._by_azimuth(m, rings[-1], centre), centre, rad, "leaf", r,
                     wob=SPRAY_CLUMP_WOB)


def build_geometry():
    """The gate as one mesh, and the per-bar record the collider and the gap
    proof are built from."""
    m = ft._Mesh()
    r = ft._Rng(SEED)
    sill = _sill(m, r)
    posts = [(sign, _post(m, r, sign, sill)) for sign in (-1, 1)]
    lin = _lintel(m, r)
    bars = _bars(m, r, sill, lin)
    rails = _rails(m, r, posts)
    _sprays(m, r, posts)
    INFO["bars"] = bars
    INFO["rails"] = rails
    return ft._prune(m), _collider(bars, rails), bars


# =============================================================================
# COLLIDER -- the visual's own shape: sill, lintel, posts, one box per bar
# =============================================================================

def _box(c, lo, hi, zone="bark"):
    """An axis-aligned box, 12 tris: the collider's one shape (ft._Mesh has none)."""
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


def _post_rx(t):
    return ft._at(POST_R, t) * POST_FLAT * (1.0 + POST_WOB)


def _post_ry(t):
    return ft._at(POST_R, t) * (1.0 + POST_WOB)


def _bar_at(path, radii, z):
    """(x, y, radius) of a bar at height z, straight-line between path points;
    the radius is the smallest the wobble can make it, so the gap it leaves is
    never understated."""
    for i in range(len(path) - 1):
        a, b = path[i], path[i + 1]
        if (a[2] - z) * (b[2] - z) <= 0.0 and abs(b[2] - a[2]) > 1e-9:
            t = (z - a[2]) / (b[2] - a[2])
            u = (i + t) / float(len(path) - 1)
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t,
                    ft._at(radii, u) * (1.0 - BAR_WOB))
    p = path[0] if z < path[0][2] else path[-1]
    return (p[0], p[1], ft._at(radii, 0.0) * (1.0 - BAR_WOB))


def _collider(bars, rails):
    c = ft._Mesh()
    sill_top = SILL_Z + math.cos(math.radians(30.0)) * min(SILL_R)
    lin_bot = LIN_Z - math.cos(math.radians(30.0)) * min(LIN_R)
    sw = max(SILL_R) * (1.0 + SILL_WOB)
    lw = max(LIN_R) * (1.0 + LIN_WOB)
    _box(c, (-HALF_W, -sw, 0.0), (HALF_W, sw, sill_top), "bark")
    _box(c, (-HALF_W, -lw, lin_bot), (HALF_W, lw, HEIGHT), "bark")
    for sign in (-1, 1):
        rx = max(_post_rx(t) for t in POST_T)
        ry = max(_post_ry(t) for t in POST_T)
        _box(c, (sign * POST_X - rx, -ry, sill_top), (sign * POST_X + rx, ry, POST_TOP), "bark")
    for path, radii, extra in bars:
        rr = max(radii) * (1.0 + BAR_WOB)
        xs = [p[0] for p in path] + [p[0] for p in extra]
        ys = [p[1] for p in path] + [p[1] for p in extra]
        _box(c, (min(xs) - rr, max(-HALF_T, min(ys) - rr), sill_top),
             (max(xs) + rr, min(HALF_T, max(ys) + rr), lin_bot), "bark")
    for a, b in rails:
        z = 0.5 * (a[2] + b[2])
        _box(c, (a[0], -RAIL_R, z - RAIL_R - RAIL_SAG), (b[0], RAIL_R, z + RAIL_R), "bark")
    return c


# =============================================================================
# THE GAP PROOF -- nothing a 0.38 m sphere gets through, at any height
# =============================================================================

def _gaps(bars, levels=140):
    """(widest gap between bars or bar and post, widest slot at the lane's
    edge, the height the widest gap is at). A gap between two bars is the
    distance between their axes less both radii -- a true clearance in plan,
    bow included. A bar-to-post gap is measured to the post's inner face."""
    sill_top = SILL_Z + math.cos(math.radians(30.0)) * min(SILL_R)
    lin_bot = LIN_Z - math.cos(math.radians(30.0)) * min(LIN_R)
    worst = (0.0, 0.0, "")
    edge = 0.0
    for i in range(levels + 1):
        z = sill_top + (lin_bot - sill_top) * i / float(levels)
        t = max(0.0, min(1.0, (z - sill_top) / (POST_TOP - sill_top)))
        rx = _post_rx(t)
        cols = sorted([_bar_at(p, rr, z) for p, rr, _x in bars], key=lambda c: c[0])
        cols = [(-POST_X + rx, 0.0, 0.0)] + cols + [(POST_X - rx, 0.0, 0.0)]
        for k in range(len(cols) - 1):
            a, b = cols[k], cols[k + 1]
            g = math.hypot(b[0] - a[0], b[1] - a[1]) - a[2] - b[2]
            if g > worst[0]:
                worst = (g, z, "post-bar" if k in (0, len(cols) - 2) else "bar-bar")
        if z < POST_TOP:
            edge = max(edge, HALF_W - (POST_X + rx))
    return worst, edge


# =============================================================================
# BUILD
# =============================================================================

def build():
    m, c, bars = build_geometry()
    albedo, emissive = ft.sheet("forest_atlas", ft.paint_atlas)
    mdl.save_texture(albedo)
    mdl.save_texture(emissive)
    INFO["albedo"], INFO["emissive"] = albedo, emissive

    ob = m.object(OBJECT_NAME)
    ft.unwrap(ob, m.zones)
    mdl.finish(ob, ft.atlas_material("ForestAtlas", albedo, emissive), strip_uvs=False)

    coll = c.object(COLLIDER_NAME)
    coll.hide_render = True
    (gap, gz, kind), edge = _gaps(bars)
    print("MDL STATS visual_tris=%d collision_tris=%d" % (len(ob.data.polygons), len(coll.data.polygons)))
    print("MDL STATS width=%.2f height=%.2f bars=%d widest_gap=%.3f (%s at z=%.2f) edge_slot=%.3f limit=%.2f"
          % (2.0 * HALF_W, HEIGHT, NBARS, gap, kind, gz, edge, MAX_GAP))
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
    ft.unwrap(ground, m.zones)
    mdl.finish(ground, ft.atlas_material("ForestAtlasScene", INFO["albedo"], INFO["emissive"]),
               strip_uvs=False)
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
    m, c, bars = build_geometry()
    m.compact()
    c.compact()
    forest_check.prove(m, NAME)
    forest_check.components_report(m)
    tags = {}
    for tag, margin in WELDS:
        tags.setdefault(tag, []).append(margin)
    print("WELDS " + " ".join("%s=%d(min %.3f)" % (t.replace(" ", "_"), len(v), min(v))
                              for t, v in sorted(tags.items())))
    (gap, gz, kind), edge = _gaps(bars)
    print("GAPS bars=%d pitch=%.3f widest=%.3f (%s at z=%.2f) edge_slot=%.3f limit=%.2f %s"
          % (NBARS, BAR_PITCH, gap, kind, gz, edge, MAX_GAP,
             "OK" if max(gap, edge) <= MAX_GAP else "OVER"))
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
