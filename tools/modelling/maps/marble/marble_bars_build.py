"""
PANOPTICON -- marble_bars: the start/finish gate of Map 2, the marble answer
to Map 1's hell-rock rock_bars. Ryan: "now create bars and portals that match
the actual maps."

An IRON PORTCULLIS IN A MARBLE FRAME, built out of the rotunda's own
architecture and nothing else: a socle under it, fluted pilaster jambs on the
rotunda's mb.PILASTER_W, a semicircular arched head of mb.HEAD_SEG segments on
the cells' own arch profile, a cornice across the top (soffit, front in three,
top in three, exactly as marble_wall_build._cornice orders them). Hanging in
the mouth, N_BAR vertical bars of the cells' own iron -- 0.13 m square,
2 * mb.BAR_HW -- with N_XBAR horizontal cross-bars through them.

IT SPANS THE WALKWAY WALL TO LIP. Ryan, 2026-09-23: "the gate doesnt block
anyone from going past it to the portal." It did not: on rock_bars' inherited
10.6 m (HALF_W 5.3) centred on the lane at r 52.0 it reached r 46.7..57.3,
while marble's walkway runs r 46.7..59.55 -- headless measurement of the scene,
2.2495 m of open floor between the gate's outer end and the cell wall, and a
body walked round it. The gate is now 12.85 m wide (x -6.425 .. 6.425) and the
scene stands its centre at r 53.125, so it reaches the inner lip (46.7) and the
wall (59.55) with nothing to walk round. Everything else is rock_bars' still:
8.5 m tall (z 0 .. 8.5), 0.5 m deep (y -0.25 .. 0.25). ORIGIN IS THE BASE
CENTRE: z = 0 is the ground. Blender +Z -> Godot +Y, +X -> +X, +Y -> -Z, so the
screen spans Godot local X across the lane and its thickness is local Z along
the lane. As rock_bars guarantees, NO GAP ANYWHERE IS WIDER THAN 0.38 m: the
widest is the bar pitch, 0.342.

THE EXTRA 2.25 m GOES INTO THE FLANKING ASHLAR FIELD, nowhere else. The mouth
stays 6.0 m under its r 3.0 head, the jambs stay mb.PILASTER_W wide at the two
ends, the twelve bars keep their 0.342 pitch: only the screen between a jamb's
inner line (XP) and the mouth grows, 1.3 m a side to 2.425 m a side. The
collider's own field boxes grow with it, so the new stone is solid, not scenery.

The frame's profile is three depths, and only three: PROUD_HD (the socle, the
pilasters and the cornice, at the full 0.25) and FIELD_HD (the screen between
the pilasters, 0.13), with the reveal of the mouth cut through the screen. The
rotunda's pilasters stand mb.PILASTER_PROUD (0.45) off a 3 m wall; a 0.5 m gate
can only afford PROUD (0.12), so the proportion is kept and the number is the
gate's own -- the one place this model interprets rather than imports.

ONE CONTIGUOUS MESH, and it closes. mb._Mesh welds coincident vertices, so
every part is authored against the same named constants and meets on them.
The two places a bar becomes stone are cut, marble_wall_build._sill style, by
_holed(): the bars' square feet are holes in the SILL (the socle's top inside
the mouth) and the cross-bars' ends are holes in the JAMB REVEALS, each hole's
four edges lying on exactly one stone face and one iron face. The bars' heads
are cut out of the HEAD SOFFIT the same way, on the soffit's own polyline --
the soffit and the bar tops share it, so the arch closes on the iron with no
lens of daylight. Where a long edge meets many short ones the long face is
emitted as one polygon carrying the short edges as collinear points (the
ledge, the cornice soffit, the jamb margins), never as a T-junction. The
underside is capped: nothing is left open.

MarbleBarsCollision rides in the .glb as a `-colonly` node, one box per real
solid -- socle, two pilasters, two jamb margins, spandrel, cornice, a box per
vertical bar, a box per cross-bar -- not one fat box over everything. The two
jamb-margin boxes are the ones that carry the widening: they run ARCH_HW .. XP
a side, so the new ashlar field is solid from the socle to the cornice soffit
and the only opening left anywhere across the walkway is the barred mouth.

It now carries a box for EVERY real solid, which the widening's test found it
did not: see _collider(). The sweep of it measures 0.342 m, the drawn mesh's
own widest gap, at every height.

tests/test_marble_gate.gd is the proof in the scene: it drives a 0.4 x 1.8 m
capsule at the gate at 11 m/s from radial offsets spanning the whole walkway,
sweeps the collider for an opening wider than 0.38 m, and checks the top.

Texture: ONE TILING SHEET PER MATERIAL CLASS (lib/texel.py, SHEETS below) at
the rotunda's own density -- no atlas, no per-face random window, which is what
left this gate a flat cold wash beside the wall it stands in. The gate is a
FLAT SLAB, not a ring, so the stone is projected "box" -- world x/y/z by the
face normal's largest axis, in the gate's own frame -- and its courses are
therefore level lines at the gate's own heights: a joint on the ledge (0.85,
the socle is exactly one course) and on the sill (1.0), then on up the world 1 m
grid the rotunda's wall courses stand on. The iron is on the PORTCULLIS' OWN
MODULE (see _sheet_iron), so every upright wears the cells' lit rim.
USE_TEXTURE_FILES swaps a painted class for textures/marble_bars_<class>_albedo.png
when one is there.

    python3 tools/modelling/maps/marble/marble_bars_build.py --check
    tools/modelling/model build marble_bars

The column-0 `import x_build as y` lines are what tools/modelling/model ships
to the PC: keep them at column 0.
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
_HOME = os.path.dirname(os.path.abspath(__file__))
for _root in (os.path.dirname(_HOME), os.path.dirname(os.path.dirname(_HOME))):  # the repo's tools/modelling
    if os.path.isfile(os.path.join(_root, "model")) and os.path.isfile(os.path.join(_root, "lib", "mdl.py")):
        sys.path[1:1] = [d for d, _, _ in os.walk(_root) if "__pycache__" not in d]
        break

import marble_build as mb  # noqa: E402
import texel as tx  # noqa: E402  one tiling sheet per class, world-projected
# marble_build imports its two part modules at its foot; they ride along to the
# PC only when a column-0 `import x_build as y` names them in THIS script.
import marble_lane_build as _ml  # noqa: E402, F401
import marble_wall_build as _mw  # noqa: E402, F401

if bpy is not None:
    import mdl  # noqa: E402
    mdl.DEFAULTS["views"] = ["threequarter", "front"]
    mdl.DEFAULTS["ground"] = True

# =============================================================================
# TUNABLES  (metres; z 0 is the ground the gate stands on)
# =============================================================================

NAME = "marble_bars"
OBJECT_NAME = "MarbleBars"
COLLIDER_NAME = "MarbleBarsCollision-colonly"
FACING_YAW = 0.0

BEARING = 353.0             # the scene's bearing for the gate: mb.BARS_B, the gap between
                            # finish (345) and start (5). The in-scene render stands it here.

LIP_R = 46.7                # the walkway's inner lip, and the gate's inner end
WALL_R = 59.55              # the walkway's outer edge at the cell wall, and the gate's outer end
HALF_W = 0.5 * (WALL_R - LIP_R)   # 6.425: 12.85 m across the lane, WALL to LIP, so there is
                            # no floor to walk round. Was rock_bars' 5.3, which left 2.25 m open
                            # outboard once the scene centred it on the lane at r 52.0.
CENTRE_R = 0.5 * (WALL_R + LIP_R) # 53.125: where the scene must stand the gate's origin
HEIGHT = 8.5                # rock_bars' height, unchanged
PROUD_HD = 0.25             # half depth of socle, pilasters and cornice: 0.5 m of stone, rock_bars' depth
PROUD = 0.12                # the pilaster stands this far proud of the screen. The rotunda's
                            # mb.PILASTER_PROUD is 0.45 off a 3 m wall; a 0.5 m gate affords 0.12
FIELD_HD = PROUD_HD - PROUD # 0.13: half depth of the screen between the pilasters

PW = mb.PILASTER_W          # 1.0: the pilaster jambs, the rotunda's own pier width
XP = HALF_W - PW            # 5.425: the pilasters' inner line, where the screen sets back.
                            # The jambs keep PW; the widening lands in the field inboard of it.

SOCLE_Z = 0.85              # the socle's top: the ledge where the frame sets back to FIELD_HD
SILL_Z = mb.SILL_UP         # 1.0: the sill the bars stand on (the rotunda's sill over a tier base)
JAMB_H = 3.20               # sill to springing. The cells' mb.ARCH_JAMB is 3.5 on an 8 m tier;
                            # 8.5 m less a 1.0 socle and a 0.8 cornice leaves the gate 3.2
SPRING_Z = SILL_Z + JAMB_H  # 4.20: the springing line
ARCH_HW = 3.0               # the mouth is 6.0 m wide under a SEMICIRCULAR head of radius 3.0 ...
CROWN_Z = SPRING_Z + ARCH_HW    # 7.20: ... crowning here
CORN_Z = 7.70               # the cornice's soffit: 0.5 m of spandrel over the crown, 0.8 of cornice over it
HEAD_SEG = mb.HEAD_SEG      # 6 segments in the head, the rotunda's own

BAR_HW = mb.BAR_HW          # 0.065: 0.13 m square iron, the cell bars' section, imported not retuned
N_BAR = 12                  # vertical bars. 12 is the fewest that keeps every gap under rock_bars'
                            # 0.38 m: the pitch is (6.0 - 12*0.13)/13 = 0.342
N_XBAR = 3                  # horizontal cross-bars through them ...
XBAR_TOPS = (2.0, 3.0, 4.0) # ... their top edges, a metre apart, the last 0.2 under the springing
                            # so the cross-bar's end lands in the FLAT part of the jamb reveal

SEED = 5                    # the atlas unwrap's seed for this model

UP, DOWN = mb.UP, mb.DOWN
FRONT, BACK = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0)
XPOS, XNEG = (1.0, 0.0, 0.0), (-1.0, 0.0, 0.0)


# =============================================================================
# THE PORTCULLIS' STATIONS
# =============================================================================

BAR_PITCH = (2.0 * ARCH_HW - N_BAR * 2.0 * BAR_HW) / (N_BAR + 1)   # 0.3415: the widest gap in the gate


def bar_x(k):
    """Centre of vertical bar k, k = 0 at the left jamb."""
    return -ARCH_HW + (k + 1) * BAR_PITCH + (2 * k + 1) * BAR_HW


def bar_span(k):
    return bar_x(k) - BAR_HW, bar_x(k) + BAR_HW


XBAR_Z = tuple((t - 2.0 * BAR_HW, t) for t in XBAR_TOPS)   # (bottom, top) of each cross-bar
BAR_ZS = [SILL_Z] + [z for band in XBAR_Z for z in band]   # the vertical bars' face splits, sill to 4.0


def head_z(x):
    """The head's underside at x: the semicircle about (0, SPRING_Z)."""
    return SPRING_Z + math.sqrt(max(0.0, ARCH_HW * ARCH_HW - x * x))


def head_xs():
    """The head's x stations, -ARCH_HW .. ARCH_HW ascending: the HEAD_SEG
    segment ends AND every bar's two sides, so the soffit's polyline and the
    bars' heads are cut out of one another and the arch closes on the iron."""
    xs = [ARCH_HW * math.cos(math.pi * k / HEAD_SEG) for k in range(HEAD_SEG + 1)]
    for k in range(N_BAR):
        xs += list(bar_span(k))
    xs.sort()
    out = []
    for x in xs:
        if not out or x - out[-1] > 1e-6:
            out.append(x)
    return out


HEAD_XS = head_xs()


def widest_gap():
    """The widest opening anywhere in the gate. Below the springing it is the
    bar pitch; above it the arch closes IN on the bars (a bar's head is cut on
    the soffit's own polyline, so stone and iron meet with no daylight), and
    the first bar right of the arch's edge is never more than a pitch away."""
    worst = BAR_PITCH
    spans = [bar_span(k) for k in range(N_BAR)]
    steps = 400
    for i in range(steps + 1):
        z = SPRING_Z + (CROWN_Z - SPRING_Z) * i / steps
        xa = -math.sqrt(max(0.0, ARCH_HW ** 2 - (z - SPRING_Z) ** 2))
        for (xl, xr) in spans:
            if xr > xa:
                worst = max(worst, max(0.0, xl - xa))
                break
    return worst


# =============================================================================
# TEXTURE  (lib/texel.py: one tiling sheet per class, world box projection)
# =============================================================================
# The gate wears the rotunda's stone at the rotunda's density: mb.WALL_MPT
# (0.046019 m) a texel on a sheet mb.WALL_H (261) texels tall = 12 courses of
# 1.0 m. It is a FLAT SLAB standing across the lane, not a ring, so the stone
# projects "box" -- world x/y/z by the normal's largest axis -- in the gate's
# OWN frame, which is the frame its joints have to line up with: v = z on every
# face of the screen, so a course line is level right across the gate and
# carries on through the jamb reveals at the same height.
#
# Up (v): V0 puts a joint exactly on the SILL (1.0), the line the iron stands
# on, and the courses then run up from it a course at a time. The gate's z 0 IS
# the walkway deck (world y 23), 24 courses over the rotunda's own FLOOR_Z
# (-1.0), so those lines are the wall's own course lines to within the quarter
# texel the 261/12 rounding costs. The socle is phased on its own top instead:
# V0_PLINTH puts its single joint on the ledge at 0.85, so the socle reads as
# one course of stone from the ground to the ledge, which is what a socle is.
#
# Across (u): STONE_PX texels = 2.991 m, blocks of 1.50 m half-bonded, the
# rotunda's own block. Phase U0 = 0 stands the sheet's continuous vertical
# joint on the gate's centre line (behind the iron), on the mouth's two jambs
# (+-2.991, 9 mm -- a fifth of a texel -- off the +-3.0 arris) and behind the
# pilasters (+-5.98), so every one of them falls on an edge or on nothing.
#
# The iron is the cells' iron, on the portcullis' own module: see _sheet_iron.

USE_TEXTURE_FILES = True
TEX_DIR = mb.TEX_DIR
MPT = mb.WALL_MPT                       # 0.046019 m a texel: the rotunda's wall density
SHEET_H = mb.WALL_H                     # 261 texels = 12 courses of 1.0 m
COURSES = 12
COURSE_PX = int(round(SHEET_H / float(COURSES)))   # 22 texels
COURSE_M = COURSE_PX * MPT              # 1.0124 m: the course, to the nearest texel
STONE_PX = int(round(3.0 / MPT))        # 65 texels = 2.991 m across: 1.50 m blocks
U0 = 0.0                                # u = 0 on the gate's centre line
V0 = SILL_Z - COURSE_M                  # a joint exactly on the sill, then a course at a time
V0_PLINTH = SOCLE_Z - COURSE_M          # ... and the socle's one joint on the ledge

IRON_MOD = BAR_PITCH + 2.0 * BAR_HW     # 0.4715 m: the uprights' centre-to-centre pitch
IRON_PX = 58                            # texels across one module -> the bar is 16 of them
IRON_MPT = IRON_MOD / IRON_PX           # 0.008130 m a texel
BAR_PX = int(round(2.0 * BAR_HW / IRON_MPT))       # 16
IRON_U0 = bar_x(0) - BAR_HW             # u = 0 on EVERY upright's left edge


# ---- the painters: the palette docs/maps/marble.md records, unchanged -------

def _ashlar(c, r, shades, joint, verticals=True, courses=COURSES):
    """Coursed blocks: a joint line on every course, a vertical joint on the
    sheet's own edge every course and the courses half-bonded between, so a
    joint runs across a face edge instead of stopping at it."""
    tx.fill(c, r, c.box, shades)
    rows = [int(round(k * c.h / float(courses))) for k in range(courses)]
    for k, y0 in enumerate(rows):
        y1 = rows[k + 1] if k + 1 < len(rows) else c.h
        c.rect(0, y0, c.w, y0 + 1, joint)
        if not verticals:
            continue
        for x in ([0, c.w // 2] if k % 2 == 0 else [0, c.w // 4, (3 * c.w) // 4]):
            c.rect(x, y0 + 1, x + 1, y1, joint)
    tx.shatter(c, r, c.box, [shades[0], shades[-1]], 16, 4, 9)


def _sheet_marble(c, r, s):
    """The screen's ashlar field: #9a9676 in #6c6950 mortar."""
    _ashlar(c, r, [(154, 150, 118), (150, 146, 114), (158, 154, 122), (146, 142, 110)],
            (108, 105, 80))


def _sheet_marble2(c, r, s):
    """The spandrel over the head: the second sheet, #928e70 in #66634a."""
    _ashlar(c, r, [(146, 142, 112), (142, 138, 108), (150, 146, 116), (138, 134, 104)],
            (102, 99, 74))


def _sheet_shade(c, r, s):
    """Grey-olive #6b6b55 in #505042: ledge, reveals, soffits, sill, the
    cornice's top. Courses only -- an underside shows no vertical joint."""
    _ashlar(c, r, [(107, 107, 85), (103, 103, 81), (111, 111, 89), (99, 99, 78)],
            (80, 80, 66), verticals=False)


def _sheet_plinth(c, r, s):
    """The socle: #928e70 in #6c6950, one course tall (V0_PLINTH)."""
    _ashlar(c, r, [(146, 142, 112), (142, 138, 108), (150, 146, 116), (144, 140, 110)],
            (108, 105, 80))


def _sheet_iron(c, r, s):
    """The cell bars' iron -- near-black #181a1f with the lit rim #686e7a --
    drawn on the PORTCULLIS' OWN MODULE. The uprights' centres are exactly
    IRON_MOD apart, so with u = 0 on bar 0's left edge EVERY upright's face
    falls on texels 0 .. BAR_PX of the sheet and every cross-bar segment --
    which spans a gap between two uprights -- falls on the rest. So each
    upright wears the rim down its left arris and the shadow down its right,
    exactly as a cell bar does, and the cross-bars wear the base iron."""
    tx.fill(c, r, c.box, [(24, 26, 31), (20, 22, 27), (28, 30, 35), (22, 24, 29)])
    c.rect(0, 0, 2, c.h, (104, 110, 122))              # the lit rim
    c.rect(2, 0, 3, c.h, (80, 85, 96))                 # ... stepping down to the base
    c.rect(BAR_PX - 2, 0, BAR_PX, c.h, (58, 62, 72))   # the shadow edge
    tx.blades(c, r, c.box, 40, [(16, 18, 23), (34, 36, 42)])


def _stone(name, paint, seed, v0=V0):
    return tx.Sheet(name, paint, mpt=MPT, size=SHEET_H, width=STONE_PX, mode="box",
                    phase=(U0, v0), roughness=mb.ROUGHNESS, seed=seed)


SHEETS = {
    "marble": _stone("marble", _sheet_marble, 1),                              # the screen's field
    "marble2": _stone("marble2", _sheet_marble2, 2),                           # the spandrel
    "shade": _stone("shade", _sheet_shade, 3),                                 # ledge, reveals, soffits, sill
    "plinth": _stone("plinth", _sheet_plinth, 4, V0_PLINTH),                   # the socle
    "band": tx.Sheet("band", mb._sheet_band, mode="fit_v", width=256, size=64,
                     roughness=mb.ROUGHNESS, seed=5),                          # the cornice's mouldings
    "column": tx.Sheet("column", mb._sheet_column, mode="fit_u", width=64, size=256,
                       roughness=mb.ROUGHNESS, seed=6),                        # the fluted pilasters
    "iron": tx.Sheet("iron", _sheet_iron, mpt=IRON_MPT, width=IRON_PX, size=256,
                     mode="box", phase=(IRON_U0, 0.0),
                     roughness=mb.ROUGHNESS, seed=7),                          # the portcullis
}


# =============================================================================
# GEOMETRY HELPERS
# =============================================================================

def _quad(m, pts, want, zone):
    m.quad(m.v(pts[0]), m.v(pts[1]), m.v(pts[2]), m.v(pts[3]), want, zone)


def _poly(m, pts, want, zone):
    m.poly([m.v(p) for p in pts], want, zone)


def _box(m, lo, hi, zone):
    """An axis-aligned box: the collider's one solid."""
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    p = [m.v(c) for c in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                          (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
    m.quad(p[0], p[1], p[2], p[3], DOWN, zone)
    m.quad(p[4], p[5], p[6], p[7], UP, zone)
    m.quad(p[0], p[1], p[5], p[4], BACK, zone)
    m.quad(p[2], p[3], p[7], p[6], FRONT, zone)
    m.quad(p[1], p[2], p[6], p[5], XPOS, zone)
    m.quad(p[3], p[0], p[4], p[7], XNEG, zone)


def _holed(m, P, lo, hi, s0, s1, sa, sb, holes, want, zone):
    """The face [lo, hi] x [s0, s1] in (t, s) under P(t, s), with the windows
    [t0, t1] x [sa, sb] -- holes ascending and disjoint, lo < t0, t1 < hi and
    s0 < sa < sb < s1 -- left open: a fan from the (lo, s0) corner over the sa
    chain ((hi, s0), then every window's sa corners high t to low), the same
    from (lo, s1) over the windows' sb corners, one gap quad between
    consecutive windows and one at each end.  Each window's four edges is then
    on exactly one of these faces, so the plug meets no T-junction."""
    n = len(holes)
    lo0, hi0 = m.v(P(lo, s0)), m.v(P(hi, s0))
    lo1, hi1 = m.v(P(lo, s1)), m.v(P(hi, s1))
    a = [(m.v(P(t0, sa)), m.v(P(t1, sa))) for (t0, t1) in holes]      # (low t, high t)
    b = [(m.v(P(t0, sb)), m.v(P(t1, sb))) for (t0, t1) in holes]
    chain = [hi0]
    for k in reversed(range(n)):
        chain += [a[k][1], a[k][0]]
    m.fan([lo0] + chain, want, zone)
    chain = [hi1]
    for k in reversed(range(n)):
        chain += [b[k][1], b[k][0]]
    m.fan([lo1] + chain, want, zone)
    m.quad(lo0, a[0][0], b[0][0], lo1, want, zone)
    for k in range(n - 1):
        m.quad(a[k][1], a[k + 1][0], b[k + 1][0], b[k][1], want, zone)
    m.quad(a[n - 1][1], hi0, hi1, b[n - 1][1], want, zone)


# =============================================================================
# THE MARBLE FRAME
# =============================================================================

def _socle(m):
    """The socle: a closed foot 0 .. SOCLE_Z at the full depth, the ledge on
    top of it where the screen sets back, and the gate's two end faces."""
    xs = (-HALF_W, -XP, XP, HALF_W)
    for i in range(3):                                            # the underside, capped
        _quad(m, [(xs[i], -PROUD_HD, 0.0), (xs[i + 1], -PROUD_HD, 0.0),
                  (xs[i + 1], PROUD_HD, 0.0), (xs[i], PROUD_HD, 0.0)], DOWN, "plinth")
    for (hd, want) in ((PROUD_HD, FRONT), (-PROUD_HD, BACK)):
        for i in range(3):                                        # the socle's two faces, split on the pilaster lines
            _quad(m, [(xs[i], hd, 0.0), (xs[i + 1], hd, 0.0),
                      (xs[i + 1], hd, SOCLE_Z), (xs[i], hd, SOCLE_Z)], want, "plinth")
        # the ledge: ONE polygon, its inner edge carrying the screen's own
        # stations (+-XP, +-ARCH_HW) as collinear points -- no T-junction
        f = math.copysign(FIELD_HD, hd)
        _poly(m, [(-XP, hd, SOCLE_Z), (XP, hd, SOCLE_Z), (XP, f, SOCLE_Z),
                  (ARCH_HW, f, SOCLE_Z), (-ARCH_HW, f, SOCLE_Z), (-XP, f, SOCLE_Z)], UP, "shade")
    zs = (0.0, SOCLE_Z, CORN_Z, HEIGHT)
    for (x, want) in ((HALF_W, XPOS), (-HALF_W, XNEG)):           # the gate's ends
        for (i, zone) in enumerate(("plinth", "marble", "band")):
            _quad(m, [(x, -PROUD_HD, zs[i]), (x, PROUD_HD, zs[i]),
                      (x, PROUD_HD, zs[i + 1]), (x, -PROUD_HD, zs[i + 1])], want, zone)


def _pilasters(m):
    """The two jambs: a fluted front at the full depth, a return into the
    screen on each side, SOCLE_Z to the cornice's soffit."""
    for (hd, want) in ((PROUD_HD, FRONT), (-PROUD_HD, BACK)):
        for (x0, x1) in ((XP, HALF_W), (-HALF_W, -XP)):
            _quad(m, [(x0, hd, SOCLE_Z), (x1, hd, SOCLE_Z),
                      (x1, hd, CORN_Z), (x0, hd, CORN_Z)], want, "column")
        f = math.copysign(FIELD_HD, hd)
        for (x, w) in ((XP, XNEG), (-XP, XPOS)):                  # the returns
            _quad(m, [(x, f, SOCLE_Z), (x, hd, SOCLE_Z),
                      (x, hd, CORN_Z), (x, f, CORN_Z)], w, "marble")


def _screen(m):
    """The screen between the pilasters, with the arched mouth cut in it: two
    jamb margins (one polygon each, carrying the mouth's sill, springing and
    crown lines as collinear points), the band under the sill, and the
    spandrel over the head, a quad per head station."""
    for (hd, want) in ((FIELD_HD, FRONT), (-FIELD_HD, BACK)):
        _poly(m, [(-XP, hd, SOCLE_Z), (-ARCH_HW, hd, SOCLE_Z), (-ARCH_HW, hd, SILL_Z),
                  (-ARCH_HW, hd, SPRING_Z), (-ARCH_HW, hd, CORN_Z), (-XP, hd, CORN_Z)], want, "marble")
        _poly(m, [(XP, hd, SOCLE_Z), (XP, hd, CORN_Z), (ARCH_HW, hd, CORN_Z),
                  (ARCH_HW, hd, SPRING_Z), (ARCH_HW, hd, SILL_Z), (ARCH_HW, hd, SOCLE_Z)], want, "marble")
        _quad(m, [(-ARCH_HW, hd, SOCLE_Z), (ARCH_HW, hd, SOCLE_Z),
                  (ARCH_HW, hd, SILL_Z), (-ARCH_HW, hd, SILL_Z)], want, "marble")
        for i in range(len(HEAD_XS) - 1):                         # the spandrel over the head
            xa, xb = HEAD_XS[i], HEAD_XS[i + 1]
            _quad(m, [(xa, hd, head_z(xa)), (xb, hd, head_z(xb)),
                      (xb, hd, CORN_Z), (xa, hd, CORN_Z)], want, "marble2")


def _cornice(m):
    """The cornice across the top, marble_wall_build._cornice's own order: the
    soffit (one polygon a side, carrying every head station on its inner
    edge), the front in three, the top in three."""
    xs = (-HALF_W, -XP, XP, HALF_W)
    chain = [XP] + list(reversed(HEAD_XS)) + [-XP]
    for (hd, want) in ((PROUD_HD, FRONT), (-PROUD_HD, BACK)):
        f = math.copysign(FIELD_HD, hd)
        _poly(m, [(-XP, hd, CORN_Z), (XP, hd, CORN_Z)] + [(x, f, CORN_Z) for x in chain],
              DOWN, "shade")                                      # the soffit
        for i in range(3):
            _quad(m, [(xs[i], hd, CORN_Z), (xs[i + 1], hd, CORN_Z),
                      (xs[i + 1], hd, HEIGHT), (xs[i], hd, HEIGHT)], want, "band")
    for i in range(3):                                            # the top, in three
        _quad(m, [(xs[i], -PROUD_HD, HEIGHT), (xs[i + 1], -PROUD_HD, HEIGHT),
                  (xs[i + 1], PROUD_HD, HEIGHT), (xs[i], PROUD_HD, HEIGHT)], UP, "shade")


def _reveals(m):
    """The mouth's two straight jamb reveals, sill to springing, with the
    cross-bars' ends cut out of them, and the head's soffit, a strip of three
    along the head's polyline with the bars' heads cut out of it. Every hole's
    four edges are one stone face and one iron face."""
    for (x, want) in ((-ARCH_HW, XPOS), (ARCH_HW, XNEG)):
        _holed(m, lambda z, y, _x=x: (_x, y, z), SILL_Z, SPRING_Z,
               -FIELD_HD, FIELD_HD, -BAR_HW, BAR_HW, list(XBAR_Z), want, "shade")
    ys = (-FIELD_HD, -BAR_HW, BAR_HW, FIELD_HD)
    spans = [bar_span(k) for k in range(N_BAR)]
    last = len(HEAD_XS) - 2
    for i in range(len(HEAD_XS) - 1):
        xa, xb = HEAD_XS[i], HEAD_XS[i + 1]
        za, zb = head_z(xa), head_z(xb)
        xm = 0.5 * (xa + xb)
        want = (-xm, 0.0, SPRING_Z - 0.5 * (za + zb))             # toward the springing centre
        # the two springing segments are ONE polygon each: the edge they share
        # with the jamb reveal's head is a single edge (that is what _holed
        # leaves), and the bars' own +-BAR_HW lines ride the far edge as
        # collinear points, so the strip splits with no T-junction
        if i == 0 or i == last:
            near = (xa, za) if i == 0 else (xb, zb)
            far = (xb, zb) if i == 0 else (xa, za)
            _poly(m, [(near[0], -FIELD_HD, near[1]), (near[0], FIELD_HD, near[1]),
                      (far[0], FIELD_HD, far[1]), (far[0], BAR_HW, far[1]),
                      (far[0], -BAR_HW, far[1]), (far[0], -FIELD_HD, far[1])], want, "shade")
            continue
        mouth = any(xl - 1e-7 <= xm <= xr + 1e-7 for (xl, xr) in spans)
        for j in range(3):
            if j == 1 and mouth:                                  # the bar's head: the hole it closes
                continue
            _quad(m, [(xa, ys[j], za), (xb, ys[j], zb),
                      (xb, ys[j + 1], zb), (xa, ys[j + 1], za)], want, "shade")


def _sill(m):
    """The sill inside the mouth -- the socle's top -- with the vertical bars'
    square feet cut out of it, marble_wall_build._sill's own decomposition."""
    _holed(m, lambda x, y: (x, y, SILL_Z), -ARCH_HW, ARCH_HW,
           -FIELD_HD, FIELD_HD, -BAR_HW, BAR_HW,
           [bar_span(k) for k in range(N_BAR)], UP, "shade")


# =============================================================================
# THE IRON
# =============================================================================

def _uprights(m):
    """N_BAR square bars, sill to head. Their long faces are split at every
    cross-bar's two edges; over a cross-bar the side (radial) faces are left
    out, where the cross-bar's end closes them -- marble_tower_build._posts'
    own bargain with _rails. The head is one polygon on the soffit's polyline."""
    bands = set(XBAR_Z)
    for k in range(N_BAR):
        xl, xr = bar_span(k)
        for i in range(len(BAR_ZS) - 1):
            za, zb = BAR_ZS[i], BAR_ZS[i + 1]
            for (y, want) in ((BAR_HW, FRONT), (-BAR_HW, BACK)):
                _quad(m, [(xl, y, za), (xr, y, za), (xr, y, zb), (xl, y, zb)], want, "iron")
            if (za, zb) in bands:
                continue
            for (x, want) in ((xr, XPOS), (xl, XNEG)):
                _quad(m, [(x, -BAR_HW, za), (x, BAR_HW, za),
                          (x, BAR_HW, zb), (x, -BAR_HW, zb)], want, "iron")
        z0 = BAR_ZS[-1]
        sts = [s for s in HEAD_XS if xl - 1e-7 <= s <= xr + 1e-7]
        for (y, want) in ((BAR_HW, FRONT), (-BAR_HW, BACK)):
            _poly(m, [(xl, y, z0), (xr, y, z0)] + [(s, y, head_z(s)) for s in reversed(sts)],
                  want, "iron")
        for (x, want) in ((xr, XPOS), (xl, XNEG)):
            _quad(m, [(x, -BAR_HW, z0), (x, BAR_HW, z0),
                      (x, BAR_HW, head_z(x)), (x, -BAR_HW, head_z(x))], want, "iron")


def _crossbars(m):
    """The horizontal bars, of the same section, in segments: one between the
    reveal and the first upright, one between every pair of uprights, one to
    the far reveal. Each segment's two ends ARE the holes left in the upright's
    side face and in the reveal, so the iron and the stone share those edges."""
    edges = [-ARCH_HW]
    for k in range(N_BAR):
        edges += list(bar_span(k))
    edges.append(ARCH_HW)
    spans = [(edges[2 * i], edges[2 * i + 1]) for i in range(len(edges) // 2)]
    for (z0, z1) in XBAR_Z:
        for (xa, xb) in spans:
            for (y, want) in ((BAR_HW, FRONT), (-BAR_HW, BACK)):
                _quad(m, [(xa, y, z0), (xb, y, z0), (xb, y, z1), (xa, y, z1)], want, "iron")
            _quad(m, [(xa, -BAR_HW, z1), (xb, -BAR_HW, z1),
                      (xb, BAR_HW, z1), (xa, BAR_HW, z1)], UP, "iron")
            _quad(m, [(xa, -BAR_HW, z0), (xb, -BAR_HW, z0),
                      (xb, BAR_HW, z0), (xa, BAR_HW, z0)], DOWN, "iron")


# =============================================================================
# THE TWO MESHES
# =============================================================================

def _gate():
    m = mb._Mesh()
    _socle(m)
    _pilasters(m)
    _screen(m)
    _cornice(m)
    n1 = len(m.faces)
    _reveals(m)
    _sill(m)
    n2 = len(m.faces)
    _uprights(m)
    _crossbars(m)
    return m, {"frame": n1, "mouth": n2 - n1, "iron": len(m.faces) - n2}


def _collider():
    """One box per real solid, not one fat box over everything -- and a box for
    EVERY real solid, which is the fix of 2026-09-23. Two pieces of drawn stone
    had no box: the band between the socle's top (0.85) and the sill the bars
    stand on (1.00), and the spandrel's curved haunches, which a single flat
    CROWN_Z .. CORN_Z slab left open from the arch's underside up to 7.20. A
    radial sweep of the old collider found 5.995 m of open lane at z 0.87 and
    2.72 m at z 7.11, against a drawn mesh with no gap over 0.342 anywhere. Both
    were out of a body's reach, and neither is any business of a barrier's to
    leave lying about: tests/test_marble_gate.gd asserts the collider's own
    widest opening across the walkway, at every height, not the reachable ones.

    The spandrel is now a stair of boxes on the head's OWN stations, HEAD_XS --
    the same polyline the drawn soffit is built on. Each column's floor is the
    LOWER of its two ends, so the collider's arch is inscribed in the drawn one:
    a barrier may be solid where the stone is not, never open where it is."""
    c = mb._Mesh()
    _box(c, (-HALF_W, -PROUD_HD, 0.0), (HALF_W, PROUD_HD, SOCLE_Z), "plinth")
    _box(c, (-HALF_W, -PROUD_HD, CORN_Z), (HALF_W, PROUD_HD, HEIGHT), "band")
    for (x0, x1) in ((XP, HALF_W), (-HALF_W, -XP)):
        _box(c, (x0, -PROUD_HD, SOCLE_Z), (x1, PROUD_HD, CORN_Z), "column")
    for (x0, x1) in ((ARCH_HW, XP), (-XP, -ARCH_HW)):
        _box(c, (x0, -FIELD_HD, SOCLE_Z), (x1, FIELD_HD, CORN_Z), "marble")
    _box(c, (-ARCH_HW, -FIELD_HD, SOCLE_Z), (ARCH_HW, FIELD_HD, SILL_Z), "marble")
    for i in range(len(HEAD_XS) - 1):
        xa, xb = HEAD_XS[i], HEAD_XS[i + 1]
        _box(c, (xa, -FIELD_HD, min(head_z(xa), head_z(xb))), (xb, FIELD_HD, CORN_Z), "marble2")
    for k in range(N_BAR):
        xl, xr = bar_span(k)
        # The drawn bar's head is a polygon ON the soffit's polyline, so the box
        # tops at the HIGHER of its two ends: the low end would leave a sliver of
        # daylight between the bar's shoulder and the spandrel above it, and at
        # the haunch that sliver merges with the pitch beside it into a 0.411 m
        # opening. Over-topping only pushes iron into stone.
        _box(c, (xl, -BAR_HW, SILL_Z), (xr, BAR_HW, max(head_z(xl), head_z(xr))), "iron")
    for (z0, z1) in XBAR_Z:
        _box(c, (-ARCH_HW, -BAR_HW, z0), (ARCH_HW, BAR_HW, z1), "iron")
    return c


# =============================================================================
# RENDERS
# =============================================================================

def _render(spec, objects):
    """Two extra shots on top of the pipeline's own views (mdl.main calls this
    hook, then renders `views` itself, so everything made here is removed and
    the prop's transform is put back before we return).

    1. `<NAME>_scale` -- eye level, a 0.6 x 0.3 x 1.8 m box standing beside the
       prop, so the fixture can be read against a body. Render-only, never
       exported (mdl.main has already written the .glb by the time we run).
    2. `<NAME>_lane` -- the in-scene shot: the rotunda imported at identity, the
       prop stood on the marble lane at its real scene transform, lit the way
       marble_build._render lights the arena, shot from a runner's eye 22 deg
       round the lane. If the rotunda .glb is not on this machine the shot is
       skipped with a note; a missing companion never fails a build.
    """
    ROTUNDA_GLB = r"C:\Users\ddd\panopticon-modelling\jobs\marble\out\marble.glb"
    PROXY_W, PROXY_D, PROXY_H = 0.6, 0.3, 1.8   # metres: shoulders, chest, a standing runner
    LANE_R = CENTRE_R           # 53.125: the gate's centre, wall to lip, the scene transform's own number
    LANE_Z = 23.0               # the walkway top the prop stands on (mb.DECK_Z)
    CAM_OFF = 22.0              # degrees round the lane between the runner and the prop

    scene = bpy.context.scene
    out_dir = spec.get("out_dir", ".")
    # EEVEE only: the engine is pinned here, never taken from spec.
    scene.render.engine = "BLENDER_EEVEE"
    mdl._try(scene.eevee, "taa_render_samples", 64)
    mdl._try(scene.eevee, "use_shadows", True)
    mdl._try(scene.eevee, "use_raytracing", True)
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    mdl._try(scene.view_settings, "view_transform", "Standard")
    mdl._try(scene.view_settings, "exposure", 0.0)

    keep = [(ob, tuple(ob.location), tuple(ob.rotation_euler)) for ob in objects]
    made = []

    def _world(rgb, strength):
        w = bpy.data.worlds.new("BarsReview")
        scene.world = w
        w.use_nodes = True
        bg = w.node_tree.nodes["Background"]
        bg.inputs[0].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
        bg.inputs[1].default_value = strength
        return w

    target = mdl._link(bpy.data.objects.new("ShotTarget", None))
    cam = mdl._link(bpy.data.objects.new("ShotCam", bpy.data.cameras.new("ShotCam")))
    con = cam.constraints.new(type="TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    scene.camera = cam
    made += [target, cam]

    def shot(name, loc, tgt, lens, res):
        cam.data.lens = lens
        cam.data.clip_end = 600.0
        cam.location = loc
        target.location = tgt
        scene.render.resolution_x, scene.render.resolution_y = res
        bpy.context.view_layer.update()
        path = os.path.join(out_dir, "%s_%s.png" % (NAME, name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("MDL RENDER %s (hand-placed camera)" % os.path.basename(path))

    # -- 1. the scale shot -------------------------------------------------------
    _world((0.40, 0.42, 0.45), 0.7)
    sd = bpy.data.lights.new("ScaleSun", type="SUN")
    sd.energy = 2.2
    sun = mdl._link(bpy.data.objects.new("ScaleSun", sd))
    sun.rotation_euler = (math.radians(52.0), 0.0, math.radians(35.0))
    fd = bpy.data.lights.new("ScaleFill", type="POINT")
    fd.energy, fd.use_shadow = 6000.0, False
    fill = mdl._link(bpy.data.objects.new("ScaleFill", fd))
    fill.location = (HALF_W + 3.0, -9.0, HEIGHT * 0.8)
    made += [sun, fill]

    gx = max(HALF_W * 3.0, 20.0)                       # a floor, so the proxy has feet
    ground = mdl.mesh("ScaleGround",
                      [(-gx, -gx, -0.01), (gx, -gx, -0.01), (gx, gx, -0.01), (-gx, gx, -0.01)],
                      [(0, 1, 2, 3)])
    ground.data.materials.append(mdl.flat_material("ScaleGroundGrey", (0.30, 0.30, 0.32, 1.0)))
    made.append(ground)

    px = HALF_W + 0.55                                 # beside the prop, clear of its widest face
    py = -(PROXY_D * 0.5 + 0.60)                       # a stride in front of the face, not inside it
    verts, faces = [], []
    for dz in (0.0, PROXY_H):
        for (dx, dy) in ((-PROXY_W / 2.0, -PROXY_D / 2.0), (PROXY_W / 2.0, -PROXY_D / 2.0),
                         (PROXY_W / 2.0, PROXY_D / 2.0), (-PROXY_W / 2.0, PROXY_D / 2.0)):
            verts.append((px + dx, py + dy, dz))
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    proxy = mdl.mesh("PlayerProxy", verts, faces)      # 0.6 x 0.3 x 1.8 m, render-only
    proxy.data.materials.append(mdl.flat_material("ProxyGreen", (0.10, 0.90, 0.20, 1.0)))
    made.append(proxy)

    dist = max(HALF_W * 2.4, HEIGHT * 1.9, 14.0)       # far enough back to hold both in frame
    shot("scale", (HALF_W * 0.45, -dist, mb.EYE_H), (HALF_W * 0.25, 0.0, HEIGHT * 0.45),
         28.0, (1300, 950))

    for ob in (ground, proxy, sun, fill):
        bpy.data.objects.remove(ob, do_unlink=True)
        made.remove(ob)

    # -- 2. the lane shot --------------------------------------------------------
    if not os.path.isfile(ROTUNDA_GLB):
        print("MDL note: no %s; skipping the %s_lane shot" % (ROTUNDA_GLB, NAME))
    else:
        rotunda = []
        try:
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=ROTUNDA_GLB)
            rotunda = list(set(bpy.data.objects) - before)
        except Exception as exc:                        # a bad companion never fails a build
            print("MDL note: could not import %s (%s); skipping the %s_lane shot"
                  % (ROTUNDA_GLB, exc, NAME))
            for ob in rotunda:
                bpy.data.objects.remove(ob, do_unlink=True)
            rotunda = []
        if rotunda:
            made += rotunda
            for ob in rotunda:
                if ob.parent is None:                   # the rotunda sits at the world origin
                    ob.location = (0.0, 0.0, 0.0)
                if "colonly" in ob.name:
                    ob.hide_render = True
            for ob in objects:                          # the prop, on the lane, facing the axis
                ob.location = mb.pol(BEARING, LANE_R, LANE_Z)
                ob.rotation_euler = (0.0, 0.0, math.radians(-BEARING))

            _world((0.40, 0.41, 0.44), 0.35)
            ld = bpy.data.lights.new("Lantern", type="POINT")
            ld.energy = mb.REVIEW_LANTERN_W
            ld.color = mb.LANTERN_RGB
            ld.shadow_soft_size = mb.LANTERN_SOFT
            lantern = mdl._link(bpy.data.objects.new("Lantern", ld))
            lantern.location = (0.0, 0.0, mb.TOWER_Y + mb.LANTERN_H)
            made.append(lantern)
            for k in range(12):                         # unshadowed fills round the ring
                rd = bpy.data.lights.new("ReviewFill%d" % k, type="POINT")
                rd.energy = mb.REVIEW_FILL_W
                rd.color = (0.90, 0.91, 0.94)
                rd.use_shadow = False
                f = mdl._link(bpy.data.objects.new("ReviewFill%d" % k, rd))
                f.location = mb.pol(k * 30.0 + 15.0, 50.0, 38.0)
                made.append(f)

            bpy.context.view_layer.update()
            shot("lane",
                 mb.pol(BEARING + CAM_OFF, LANE_R, mb.DECK_Z + mb.EYE_H),
                 mb.pol(BEARING, LANE_R, LANE_Z + HEIGHT * 0.42),
                 35.0, (1400, 850))

    # -- put the scene back the way mdl.main's own render() expects it ------------
    for ob in made:
        bpy.data.objects.remove(ob, do_unlink=True)
    for ob, loc, rot in keep:
        ob.location = loc
        ob.rotation_euler = rot
    bpy.context.view_layer.update()


# =============================================================================
# BUILD
# =============================================================================

def build():
    gate, counts = _gate()
    coll = _collider()
    ob = gate.object(OBJECT_NAME)
    tx.unwrap(ob, gate.zones, SHEETS, seed=SEED, groups=gate.groups)
    mats = tx.materials(NAME, SHEETS, use_files=USE_TEXTURE_FILES,
                        tex_dir=os.path.join(HERE, TEX_DIR))
    for mat in mats.values():
        mat.diffuse_color = (0.78, 0.76, 0.72, 1.0)
    order = tx.finish(ob, gate.zones, mats)
    tx.report(SHEETS)
    print("MDL STATS surfaces=%d order=%s" % (len(ob.data.materials), ",".join(order)))
    coll_ob = coll.object(COLLIDER_NAME)
    coll_ob.hide_render = True
    a = mb.audit(gate, "bars")
    print("MDL STATS visual_tris=%d collision_tris=%d frame=%d mouth=%d iron=%d"
          % (len(ob.data.polygons), len(coll_ob.data.polygons),
             counts["frame"], counts["mouth"], counts["iron"]))
    print("MDL STATS contiguity components=%d boundary=%d doubled=%d over=%d degenerate=%d dup_pos=%d"
          % (a["components"], a["boundary_edges"], a["doubled_edges"], a["over_edges"],
             a["degenerate"], a["duplicate_positions"]))
    print("MDL STATS width=%.2f height=%.2f depth=%.2f mouth=%.2fx%.2f bars=%d cross=%d "
          "bar=%.3f widest_gap=%.3f sill_z=%.2f spring_z=%.2f crown_z=%.2f cornice_z=%.2f"
          % (2.0 * HALF_W, HEIGHT, 2.0 * PROUD_HD, 2.0 * ARCH_HW, CROWN_Z - SILL_Z, N_BAR, N_XBAR,
             2.0 * BAR_HW, widest_gap(), SILL_Z, SPRING_Z, CROWN_Z, CORN_Z))
    return [ob, coll_ob]


def _check():
    """--check: build without Blender; prove one closed contiguous mesh."""
    gate, counts = _gate()
    coll = _collider()
    a = mb.audit(gate, "bars")
    mb.audit(coll, "coll")
    xs = [v[0] for v in gate.verts]
    ys = [v[1] for v in gate.verts]
    zs = [v[2] for v in gate.verts]
    gap = widest_gap()
    print("counts=%s x=%.2f..%.2f y=%.2f..%.2f z=%.2f..%.2f loops=%s"
          % (counts, min(xs), max(xs), min(ys), max(ys), min(zs), max(zs),
             mb.boundary_loops(gate)[:3]))
    print("mouth %.2f x %.2f under a semicircular head r %.2f crowning at %.2f; "
          "%d bars of %.3f at a %.3f pitch, %d cross-bars; widest gap %.3f"
          % (2.0 * ARCH_HW, CROWN_Z - SILL_Z, ARCH_HW, CROWN_Z, N_BAR,
             2.0 * BAR_HW, BAR_PITCH, N_XBAR, gap))
    fits = (abs(min(xs) + HALF_W) < 1e-9 and abs(max(xs) - HALF_W) < 1e-9
            and abs(min(zs)) < 1e-9 and abs(max(zs) - HEIGHT) < 1e-9
            and min(ys) >= -PROUD_HD - 1e-9 and max(ys) <= PROUD_HD + 1e-9)
    ok = a["components"] == 1 and a["boundary_edges"] == 0 and a["doubled_edges"] == 0 \
        and a["over_edges"] == 0 and a["degenerate"] == 0 and a["duplicate_positions"] == 0 \
        and fits and gap < 0.38
    print("envelope %s  widest_gap %.3f < 0.38 %s" % ("OK" if fits else "WRONG",
                                                      gap, "OK" if gap < 0.38 else "WRONG"))
    print("CONTIGUOUS %s" % ("YES" if ok else "NO"))
    return ok


if __name__ == "__main__":
    if bpy is None or "--check" in sys.argv:
        sys.exit(0 if _check() else 1)
    else:
        mdl.main(NAME, build, facing_yaw=FACING_YAW, post=_render)
