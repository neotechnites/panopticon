"""
PANOPTICON -- map 1, section S3: "The Minefield".

The deck here is paved in demon boost pads and a single pad-free corridor is
cut through the field. Walk the corridor and you cross; step off it and the
floor throws you 14.7 m into somebody else's line of sight. The corridor
WEAVES, r 50.7 to 53.6, so the route threads between the pads instead of
running a lane down the middle -- and the pads follow it, because the deck is
only 10.6 m wide and what fits either side changes as the route swings.

Low rock crests sit on the TOWER side of the corridor, wherever the weave
carries it far enough out for one to fit inward. No two match: each is drawn
with its own height, footprint, orientation and radius, and each has a broad
near-flat top. That plateau is not decoration. The mesh samples this module's
height field on the section's own grid, about 0.40 m either way, so a crest
that comes to a point between two nodes is simply never built -- it ships as a
1.4 m cone casting a shadow one metre deep, which the cover bake never sees.
A plateau holds full height across several grid steps in both axes. The scoop
of dead ground behind each crest is what finishes the job of hiding a runner.

Three dips break the corridor. Each is a shallow saucer, rounded, with a pad
on its floor and rims exactly 6.0 m apart. The pad cannot be walked around:
at its bearing the deck is shut wall to wall, by a crest on the tower side and
a pinch pad centred in what is left outward, so every gap beside the pad is
narrower than a body. Its trigger box is 1.0 m tall with its bottom on the
saucer floor, so the only way past is a running jump -- feet clear the box,
the pad never fires, and the runner lands on the far rim. A dip is a skill
check placed on the only safe route, and a guard who knows the map knows
exactly where the runner must leave the ground.

Geometry only. No scene, no mesh, no Blender, no bpy. This module is the
single source of truth for the section: the scene builder reads `layout()`
and places nodes; the mesh builder reads `layout()["height"]` and sculpts.

FRAME. Game bearing b (deg) -> plan point (gx, gz) = (r cos b, r sin b), and
that plan point is Godot (gx, y, gz). The deck top is y = DECK_Z; the pit lip
is r = INNER_R and the outer wall foot is r = OUTER_R. `height` returns metres
of rock ABOVE DECK_Z, and is exactly 0.0 outside the section so S3 welds to
plain deck with nothing to reconcile.

A pad's facing is the unit vector (cos yaw, sin yaw) -- the same bearing ->
direction map the positions use -- so a pad whose yaw is its own bearing + 90
launches tangentially toward increasing bearing. No pad's yaw is written down:
each is SOLVED, forward first, falling back to backward where the deck leaves
no forward flight that still lands on it.

Run `python3 s3_minefield.py` for the self-proof. It prints every number it
asserts, and it prints the one place this section falls short of its brief --
the pad count -- rather than hiding it.
"""

import math
from collections import deque

# The section's whole public surface. Everything else is either a TUNABLE the
# style rule asks to be named, or a private helper.
__all__ = ["S3_B0", "S3_B1", "S3_EXT", "S3_SEED", "layout"]

# =============================================================================
# TUNABLES
# =============================================================================

# ---- frame: fixed by the map base, never re-derived here ---------------------
DECK_Z = 23.0               # world y of the deck surface (runner's feet)
INNER_R = 46.7              # pit lip: deck inner edge
OUTER_R = 57.3              # outer wall foot: deck outer edge
# The guard eye, on the ring axis. 28.90 is the value traced out of the running
# game: the Tower/TowerSpawn marker (tower origin 25.35 + local 1.95 = 27.30)
# plus EYE_HEIGHT_METRES 1.60, which bake.get_eye() prints as (0.0, 28.9, 0.0).
# The 27.0 that older build scripts use is a deck-level approximation, and it
# flatters every cover claim by 1.9 m of eye height. A HIGHER eye makes a crest
# harder to hide behind, not easier, so proving the crests at 28.90 proves them
# at 27.0 too -- the self-proof asserts both.
GUARD_EYE_Y = 28.90
GUARD_EYE_Y_OLD = 27.00     # the old approximation, still asserted as the easier case
BAKE_CHEST = 0.90           # the cover bake's chest probe, metres over the deck
BAKE_HEAD = 1.50            # and its head probe: BOTH must be blocked to count
BAKE_GRID = 1.50            # the bake samples cover on this grid, so a shadow
                            # narrower than one cell is a shadow it never sees
# Two full bake cells. The bake samples cover on a BAKE_GRID grid, so a crest
# whose shadow is narrower is one it keeps failing to see -- measured: twelve
# crests yielded about seven cover points, and none at all across a third of
# the section. It costs crest LENGTH, roughly 4.9 m at the bake's 1.5 m head
# probe, and that length is affordable because crests live INWARD of the
# corridor: a line of them along the run costs the inner pad lane, never the
# route.
PATCH_MIN = 3.00            # least shadow WIDTH this section will publish as cover
PATCH_DEPTH_MIN = 2.00      # least shadow DEPTH: more than one bake cell, straight
                            # out from the crest

# ---- the section's extent ---------------------------------------------------
S3_B0, S3_B1 = 145.0, 200.0     # the field proper, game bearings
S3_EXT = (143.0, 202.0)         # bearings S3 re-lays: an ease-in at each end
S3_SEED = 30313                 # this section's own seed; editing S3 diffs S3

EASE_B = 1.5                # bearing ease: rock falls to 0 within this of an ext edge
EASE_R = 0.7                # radial ease: rock falls to 0 within this of either rim

COL_COUNT = 132             # bearing columns the mesh re-lays across S3_EXT
STATION_COUNT = 26          # radial stations from INNER_R to OUTER_R
SPREAD_JITTER = 0.09        # +/- fraction on each column/station step, so bands read as rock

# ---- movement, fixed: do not re-derive --------------------------------------
RUN_SPEED = 11.0            # m/s on the flat
JUMP_V = 7.0                # m/s up off the floor
GRAVITY = 22.0              # m/s^2
BODY_R = 0.40               # capsule radius
# THE BINDING WIDTH IS NOT THE BODY'S. Godot's RingBake bakes the navmesh with
# AGENT_RADIUS 0.50 and CELL_SIZE 0.25, so the walkable surface is eroded half a
# metre all round every obstacle and then quantised to a quarter-metre grid. A
# 1.76 m corridor a 0.40 m body walks happily becomes 0.76 m of navmesh and then
# nothing: measured, only 28% of this section's floor baked, path queries failed
# right across it, and run_bot_match returned 10 matches all UNRESOLVED with the
# guard taking zero shots. A corridor a human can walk is not automatically a
# corridor a bot can path, so the route is proved with a disc this size instead:
# 0.50 agent + 0.25 cell + 0.25 cell + 0.30 margin.
NAV_DISC_R = 1.30           # the route must let a disc THIS big roll end to end
STAND_H = 1.80              # standing capsule height (feet at the body origin)
CROUCH_H = 1.20             # crouched capsule height
JUMP_FLAT = 7.00            # flat jump distance at RUN_SPEED

# ---- the pad, fixed: do not re-derive ---------------------------------------
PAD_LAUNCH = 18.0           # m/s launch speed
PAD_ANGLE = 45.0            # launch pitch, degrees
PAD_RANGE = 14.70           # flat flight distance (exactly 324/22 = 14.727, called 14.70)
PAD_APEX = 3.68             # flight apex above the take-off
PAD_BOX_ACROSS = 1.25       # trigger box half extent across the facing (2.5 m wide)
PAD_BOX_ALONG = 1.25        # trigger box half extent along the facing (2.5 m deep)
PAD_BOX_TALL = 1.0          # trigger box height, bottom face on the floor
PAD_BACKSET = 1.25          # take-off point is the centre moved this far BACKWARD
PAD_DISC_R = 1.25           # the pad itself is a 2.5 m disc; THIS is what must sit on
                            # the deck. The trigger box is a gameplay volume and may
                            # overhang the wall foot, where no body can stand anyway --
                            # and a yaw-free rule is what lets the last pads rotate

# ---- the field --------------------------------------------------------------
FIELD_AMP = 0.12            # undulation peak, metres: the field breathes, it is not a plate
FIELD_F1 = 0.62             # undulation frequency on gx (rad/m, ~10.1 m wavelength)
FIELD_F2 = 0.47             # undulation frequency on gz (rad/m, ~13.4 m wavelength)
FLAT_BLEND = 0.40           # undulation fades out over this distance around any flat patch

# ---- the corridor ----------------------------------------------------------
# The route WEAVES across the deck: two sines, one slow sweep and one slower
# drift, so it threads between the pads instead of running a lane down the
# middle. Amplitudes are capped by walkability -- at r 52 one degree is 0.91 m,
# so a radial slope over ~0.38 m/deg would tilt the path past 22 deg off
# tangential and read as a zigzag rather than a path.
CORR_R_MID = 52.20          # corridor centreline mean radius
CORR_A1, CORR_P1, CORR_PH1 = 0.90, 42.0, 1.2     # the sweep: amp, period deg, phase
CORR_A2, CORR_P2, CORR_PH2 = 0.40, 110.0, 2.0    # the drift: amp, period deg, phase
# Half the pad keep-out. The deck has 8.10 m of legal pad-centre radius, and
# every metre of keep-out costs two metres of that, so this is as tight as the
# route can be and still walk: a crest's face to the outer pads' faces leaves
# 2.60 m clear, against an 0.80 m body.
CORR_HALF = NAV_DISC_R      # pads and crests keep this far off the centreline, so
                            # the clear corridor is 2 x NAV_DISC_R wide everywhere
CORR_STEP = 0.45            # bearing step of the published corridor polyline
CORR_B0 = 145.50            # corridor starts at or before 146.0
CORR_B1 = 199.50            # corridor ends at or after 199.0

# ---- cover -----------------------------------------------------------------
# No two crests match. Each is drawn per piece: a long RIDGE along the run or a
# broader squat MASS, with its own height, footprint, plan orientation and
# radius -- the radius follows the weaving corridor, so a crest always sits on
# the TOWER side of the route WHERE THE ROUTE IS. Each has a broad near-flat
# top at least COVER_FLAT_MIN across, so it is an outcrop with a shoulder to
# shelter behind, not a cone that comes to a point.
COVER_TOP_MIN, COVER_TOP_MAX = 1.90, 2.10        # summit height above DECK_Z
COVER_RIDGE_LEN = (4.5, 5.5)     # long ridge: full length along the run, metres
COVER_RIDGE_WID = (2.3, 3.0)     # long ridge: full width across the run
COVER_MASS_LEN = (4.5, 5.2)      # squat mass: full length along the run
COVER_MASS_WID = (2.4, 3.4)      # squat mass: full width across the run
# THE flat top is the whole point, and 1.60 is not a taste call. The mesh
# samples `height` on this section's own cols x stations grid, about 0.40 m
# either way, so a peak between two nodes is simply never built: a cone that
# peaks at 2.05 in the field gets a 1.4 m top in the mesh, which casts a
# shadow one metre deep that the 1.50 m cover bake never samples. A plateau
# 1.60 m across holds its full height across four grid steps in BOTH axes.
COVER_FLAT_MIN = 1.60            # the flat top is never narrower than this, metres
COVER_FLANK_DEG = 48.0           # every flank is solved to beat this, degrees
COVER_FLAT_MARGIN = 0.02         # slack past the binding bound, so both hold strictly
COVER_FLAT_MAX = 0.75            # flat_frac ceiling: past this there is no flank left
COVER_MIN_HALF_ALONG = 2.10      # shorter than this and a crest cannot cast a shadow
                                 # PATCH_MIN wide, so it is not cover at all
COVER_MIN_HALF_ACROSS = 1.15     # thinner than this and its flat top cannot be
                                 # COVER_FLAT_MIN across at any legal flat_frac
COVER_SEAL_HALF_MAX = 2.80       # widest a dip's sealing crest may be, half extent
COVER_SEAL_HALF_MIN = 1.00       # and the narrowest. Below COVER_MIN_HALF_ACROSS on
                                 # purpose: a seal's first job is to shut the strip to
                                 # the pit lip, and at 1.00 its flat top is still
                                 # 2 x 0.75 x 1.00 = 1.50 m across, wider than three
                                 # cells of the mesh grid, so its top still samples
DIP_SEAL_GAP = 0.20              # the sealing crest reaches PAST the walkable inner
                                 # edge to the pit-lip margin: stopping short of it by
                                 # even 0.7 m leaves a lane a body slips along
COVER_SHRINK = 0.98              # factor on half_along while a drawn spec is trimmed
COVER_SHRINK_TRIES = 64          # safety bound on that trim
COVER_GAP_MIN = 2.50              # least bearing-gap-equivalent between crests, metres
COVER_GAP_MAX = 4.40              # most, so spacing is irregular, not a rhythm
COVER_MIN_CORR_R = 50.60         # a crest needs this much corridor radius to fit inward
# A crest's inner face stops at the radial ease zone, never inside it: inside,
# the surface is multiplied down to 0.0 to weld onto plain deck, and a crest
# reaching in there has its toe dragged into a shallow ramp.
COVER_EDGE_PAD = EASE_R          # a crest's inner face keeps this clear of the pit lip
COVER_TARGET = 7                 # spread crests to aim for, on top of the three dip
                                 # ones -- 9 total, the brief's minimum. Every crest
                                 # past that costs a pad, and the pad count is the
                                 # larger shortfall, so the crest count sits at the
                                 # floor of its range rather than the ceiling.
# Plan orientation: a smooth pure function of the crest's own bearing, so the
# ridge axis varies piece to piece and the proof can re-derive it from the
# published bearing alone.
COVER_YAW_AMP = 7.0             # degrees off tangential, peak
COVER_YAW_F = 0.37               # radians of jitter phase per degree of bearing
COVER_YAW_PH = 1.9               # jitter phase offset
HIDE_GAP_MIN, HIDE_GAP_MAX = 0.35, 0.95   # hide spot inset from the corridor's inner edge
HIDE_DEPTH = 0.30           # the scoop of dead ground behind a crest, metres down
HIDE_RAD_MIN, HIDE_RAD_MAX = 1.20, 1.65   # radius of that scoop, varied per crest
# Clusters: a main mass with one or two smaller lumps at its foot, always on the
# TOWER side so they never crowd the route. Derived from the crest's published
# numbers, so they are rock the walkability proof can see and account for.
LUMP_MAX = 2                # at most this many lumps per crest
LUMP_TOP = (0.60, 1.25)     # lump summit height above DECK_Z
LUMP_HALF = (0.55, 1.05)    # lump half extent, both axes
LUMP_OUT = (0.85, 1.70)     # how far past the crest's inner face a lump sits

# ---- the dips ---------------------------------------------------------------
# A dip's real requirements -- a crest that fits inward, a pad with a legal
# forward flight, a buttress that fits outward -- are each tested directly in
# _dip_viable. This band is only a coarse sanity rail around the weave; the
# direct tests are what decide, so it is deliberately generous.
DIP_BAND = (49.50, 54.50)   # corridor radius a dip can live at
DIP_SEP = 9.0              # least bearing separation between two dips, degrees
DIP_SEARCH = (148.0, 193.0)  # dips are looked for in this bearing range
DIP_DEPTHS = (0.52, 0.55, 0.58)             # saucer floor below the rim (must sit 0.50..0.60)
DIP_ALONG = 6.00                            # rim0 -> rim1, metres
DIP_SLOPE = 1.20                            # rim to floor over this distance
DIP_HALF_ACROSS = 2.45                      # saucer half width: floor flat over the pad
DIP_PAD_NEAR = 2.00                         # pad near edge, metres from rim0
DIP_YAW_SWEEP = 6                           # a dip pad may turn this far off the chord
                                            # to find a legal flight. At 9 deg its box
                                            # edges shift 0.015 m along the corridor, so
                                            # the 2.00 / 4.50 m edges still hold
# The feet must clear the pad's trigger box, so this IS the box height -- tie
# them together rather than writing 1.00 twice and letting them drift apart.
DIP_JUMP_CLEAR = PAD_BOX_TALL               # feet must stay this far over the floor

# ---- the pad field ----------------------------------------------------------
# THE PAD COUNT IS DECK-LIMITED, and this is where S3 falls short of its brief.
# Three things bound it, all measured: pads must aim FORWARD (a backward one
# loops a bot), and no forward flight lands on the field past b~185, so the last
# stretch carries none; a landing must have navmesh under it, clear of every
# crest and dip, or the bake carves it out as a dead pad; and a bearing column
# of a 10.6 m deck holds the corridor keep-out plus at most two 2.5 m pad lanes,
# one of which a crest takes at its own bearing. Moving it needs a human call on
# the pad count, the cover count, the corridor width, or crest breadth. The
# self-proof prints this as a DEVIATION rather than hiding it.
PAD_MIN_ACHIEVED = 6       # regression floor at the measured frontier
PAD_BRIEF_MIN = 34          # what the brief asks for, for the record
PAD_MAX = 42                # hard cap on pads (schema allows 34..42)
PAD_LATTICE_DB = 0.20       # candidate bearing step, degrees: fine, the packer picks
PAD_LATTICE_DR = 0.15       # candidate radius step: the legal radius windows either
                            # side of the corridor are only ~0.10 m wide
PAD_LATTICE_R0 = 47.95      # innermost candidate radius: the pad disc's own limit
PAD_LATTICE_R1 = 56.05      # outermost candidate radius: likewise
PAD_GAP = 0.05              # least gap between two pad boxes. Neighbours along a row
                            # sit at slightly different bearings, so their boxes are a
                            # few degrees out of square and the true gap is tighter
PAD_GAP_COVER = 0.25        # field pad box to crest. A patch's blend reaches 0.40 m,
                            # so at this gap it bites 0.15 m into the crest's toe and
                            # STEEPENS it -- the toe slope there is 1.95*g/0.40 along
                            # and 2.93*g/0.40 across, both over tan(46 deg) at g=0.25
PAD_GAP_DIP = 0.12          # dip pad to its crest: it must sit in the pinch, and a
                            # 0.20 m gap still leaves the crest's across toe over 46 deg
DIP_YAW_MARGIN = 0.12       # the dip pad's yaw is not settled when its crest is
                            # placed; over DIP_YAW_SWEEP its box reaches up to this
                            # much further toward the crest, so hold it back
DIP_COVER_SLACK = 0.04      # the dip chord runs ~0.3 deg off the crest's tangent axis,
                            # which shaves the corner-to-face gap; pay for it up front
PAD_ARC_SKIP = 2.50         # arc clearance is checked past here: the pad's own flat patch
PAD_ARC_CLEAR = 0.50        # the arc must clear the rock by this much, take-off to apex
PAD_LAND_R0 = 48.20         # legal landing radius, inner
PAD_LAND_R1 = 56.20         # legal landing radius, outer
PAD_LAND_B0 = 146.0         # legal landing bearing, low
PAD_LAND_B1 = 199.0         # legal landing bearing, high
# A landing is only a landing if the navmesh has floor under it. The cover bake
# carves every crest footprint and every steep dip flank OUT of the walkable
# surface, so a pad whose flight ends on rock or off the edge is not a launcher
# -- it is an obstacle the bake reports as a dead pad. Zero is the only
# acceptable number, so the solver owns this rather than the bake.
# 0.90 is the bake's own rule, not a padding: it wants a landing 0.45 m inside
# the walkable boundary, and a crest footprint IS a boundary, so 0.45 plus the
# 0.40 body radius is what a landing needs to clear one.
PAD_LAND_CLEAR = 0.90       # clear of crest and dip footprints, in plan
PAD_LAND_EDGE = 0.90        # clear of the walkable edges. Smaller on purpose: GRID_R0
                            # and GRID_R1 already sit 0.5 m inside the real deck
YAW_SWEEP = 60              # how far off tangential a yaw may be searched, degrees
YAW_STEP = 3                # yaw search step, degrees

# ---- the walkability proof --------------------------------------------------
GRID_STEP = 0.10            # plan grid for the body sweep
GRID_R0 = 47.20             # the proof walks this annulus
GRID_R1 = 56.80
GRID_B0 = 145.0
GRID_B1 = 200.0
COVER_FLANK_MIN = 46.0      # crest flanks must be steeper than this, degrees
SIGHT_MARGIN_MIN = 0.15     # a crest must out-top the eye-to-head line by this much
JUMP_MARGIN_MIN = 0.15      # least slack on the dip jump
HEIGHT_FLOOR = -0.70        # rock never sinks below this

_TAN_FLANK_MIN = math.tan(math.radians(COVER_FLANK_MIN))
_ARC_K = GRAVITY / (2.0 * PAD_LAUNCH * PAD_LAUNCH *
                    math.cos(math.radians(PAD_ANGLE)) ** 2)   # arc: y = x - _ARC_K x^2
_ARC_APEX_X = math.tan(math.radians(PAD_ANGLE)) / (2.0 * _ARC_K)

# ---- EVERY PAD AIMS FORWARD. Not a preference -- a measured regression.
# A backward-aiming pad loops a bot: it walks forward, the pad throws it 13.45 m
# back down the ring, it walks forward, it hits the same pad, forever. Measured
# in the running game: with six backward pads in the scene
# test_a_runner_completes_a_lap failed ("expected 1, got 0") and every harness
# match collapsed to one round; deleting exactly those six turned it green.
# Bots are map-agnostic by design, so the fix belongs in the map. A pad exists
# only where a legal FORWARD flight exists; past the bearing where those run out
# the section carries no pads, which reads as the way out. Never hardcoded.
FWD_MIN = 6                # regression floor on the forward pad count


# =============================================================================
# DETERMINISM -- the _Rng LCG, so the section is byte-identical every rebuild
# =============================================================================

class _Rng(object):
    """Deterministic LCG; the section is byte-identical every rebuild."""

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

    def pick(self, seq):
        return seq[self.bits() % len(seq)]


# =============================================================================
# PLAN GEOMETRY HELPERS
# =============================================================================

def _plan(b_deg, r):
    """Game bearing + radius -> plan point (gx, gz)."""
    a = math.radians(b_deg)
    return (r * math.cos(a), r * math.sin(a))


def _bearing(gx, gz):
    """Plan point -> game bearing in degrees, 0..360."""
    b = math.degrees(math.atan2(gz, gx))
    return b + 360.0 if b < 0.0 else b


def _dir(yaw_deg):
    """A facing bearing -> its plan unit vector, the same map the positions use."""
    a = math.radians(yaw_deg)
    return (math.cos(a), math.sin(a))


def _smooth(t):
    """Smoothstep, clamped: 0 at t<=0, 1 at t>=1, zero slope at both ends."""
    if t <= 0.0:
        return 0.0
    if t >= 1.0:
        return 1.0
    return t * t * (3.0 - 2.0 * t)


def _spread(a, b, n, rng):
    """n+1 ascending values a..b; every step jittered so bands read as rock."""
    w = [1.0 + rng.sf() * SPREAD_JITTER for _ in range(n)]
    tot = sum(w)
    out = [a]
    acc = 0.0
    for x in w[:-1]:
        acc += x
        out.append(a + (b - a) * acc / tot)
    out.append(b)
    return out


def _crest_profile(t, top, flat_frac):
    """Crest height at L-inf normalised distance t: a flat top out to
    flat_frac, then a straight flank falling to 0.0 at t = 1.0."""
    if t <= flat_frac:
        return top
    if t >= 1.0:
        return 0.0
    return top * (1.0 - t) / (1.0 - flat_frac)


def _uniform(rng, span):
    """One draw from a (lo, hi) pair using the caller's LCG."""
    return span[0] + (span[1] - span[0]) * rng.f()


def _flat_frac(top, half_along, half_across):
    """Smallest flat_frac keeping the top wide enough and both flanks steep."""
    width_bound = 0.5 * COVER_FLAT_MIN / half_across
    slope_bound = 1.0 - top / (math.tan(math.radians(COVER_FLANK_DEG))
                               * max(half_along, half_across))
    return max(width_bound, slope_bound) + COVER_FLAT_MARGIN


def _crest_spec(rng, ridge):
    """One crest's shape. `ridge` True for a long ridge running along the run,
    False for a broader squat mass. Returns
    (top, half_along, half_across, flat_frac)."""
    top = _uniform(rng, (COVER_TOP_MIN, COVER_TOP_MAX))
    if ridge:
        full_len = _uniform(rng, COVER_RIDGE_LEN)
        full_wid = _uniform(rng, COVER_RIDGE_WID)
    else:
        full_len = _uniform(rng, COVER_MASS_LEN)
        full_wid = _uniform(rng, COVER_MASS_WID)
    half_across = 0.5 * full_wid
    # the ridge axis is never the short one, so u stays the along-run axis
    half_along = max(0.5 * full_len, half_across)
    frac = _flat_frac(top, half_along, half_across)
    tries = 0
    while frac > COVER_FLAT_MAX and half_along > half_across and tries < COVER_SHRINK_TRIES:
        half_along = max(half_along * COVER_SHRINK, half_across)
        frac = _flat_frac(top, half_along, half_across)
        tries += 1
    return (top, half_along, half_across, min(frac, COVER_FLAT_MAX))


def _cover_yaw(b_deg):
    """A crest's ridge bearing: tangential plus a smooth jitter that is a pure
    function of its own bearing, so no two neighbours line up and the proof can
    re-derive the axis from the published bearing alone."""
    return (b_deg + 90.0
            + COVER_YAW_AMP * math.sin(b_deg * COVER_YAW_F + COVER_YAW_PH))


def _cover_lumps(cover):
    """The smaller lumps at one crest's foot, always on the TOWER side, derived
    from that crest's published numbers so they are rock everything can see.
    Returns a list of (cx, cz, ux, uz, half, half, top, flat_frac)."""
    rng = _Rng((int(round(cover["b"] * 1000.0)) * 2654435761) ^ S3_SEED)
    yaw = _cover_yaw(cover["b"])
    ux, uz = _dir(yaw)
    ax, az = -uz, ux
    cx, cz = _plan(cover["b"], cover["r"])
    out = []
    for k in range(rng.i(0, LUMP_MAX)):
        top = _uniform(rng, LUMP_TOP)
        half = _uniform(rng, LUMP_HALF)
        # inward along the crest's across axis, and slid along its ridge
        inward = cover["half_across"] + _uniform(rng, LUMP_OUT)
        slide = rng.sf() * cover["half_along"]
        sign = 1.0 if (ax * cx + az * cz) < 0.0 else -1.0
        lx = cx + ax * sign * inward + ux * slide
        lz = cz + az * sign * inward + uz * slide
        if math.hypot(lx, lz) - half * 1.5 < INNER_R + COVER_EDGE_PAD:
            continue
        frac = _flat_frac(top, half, half)
        if frac > COVER_FLAT_MAX:
            continue
        out.append((lx, lz, ux, uz, half, half, top, frac))
        del k
    return out


def _dip_frac(u, v, half_along, half_across, slope):
    """Saucer depth fraction at plan offset (u, v) from the dip centre: 0.0 at
    the rim, 1.0 on the flat floor, soft-cornered and smooth in between. The
    corners are rounded by MULTIPLYING the two ramps rather than min()ing
    them, which is what removes the chiselled square edge."""
    f_a = (half_along - abs(u)) / slope
    if f_a <= 0.0:
        return 0.0
    if f_a > 1.0:
        f_a = 1.0
    f_c = (half_across - abs(v)) / slope
    if f_c <= 0.0:
        return 0.0
    if f_c > 1.0:
        f_c = 1.0
    x = f_a * f_c
    return x * x * (3.0 - 2.0 * x)


def _disc_box_overlap(px, pz, rad, cx, cz, yaw_deg, half_across, half_along):
    """True when the disc (centre px,pz, radius rad) overlaps the rectangle
    centred (cx,cz) whose 'along' axis is the unit vector
    (cos(yaw_deg), sin(yaw_deg)) and whose 'across' axis is
    (-sin(yaw_deg), cos(yaw_deg)), with half extents half_along and
    half_across on those axes."""
    yaw = yaw_deg * 0.017453292519943295
    ca = math.cos(yaw)
    sa = math.sin(yaw)
    dx = px - cx
    dz = pz - cz
    da = dx * ca + dz * sa
    dc = -dx * sa + dz * ca
    if da > half_along:
        da -= half_along
    elif da < -half_along:
        da += half_along
    else:
        da = 0.0
    if dc > half_across:
        dc -= half_across
    elif dc < -half_across:
        dc += half_across
    else:
        dc = 0.0
    return da * da + dc * dc <= rad * rad


def _box_reach(ux, uz, half_along, half_across, mx, mz):
    """How far an oriented box reaches from its centre along the unit
    direction (mx, mz). A rotated box reaches further than its half width, and
    forgetting that is how a crest corner ends up inside a pad."""
    return (half_along * abs(ux * mx + uz * mz) +
            half_across * abs(-uz * mx + ux * mz))


def _obb_gap(box_a, box_b):
    """Separating-axis gap between two oriented boxes: > 0 means a clear gap,
    <= 0 means they touch or overlap. Each box is
    (cx, cz, ux, uz, half_along, half_across)."""
    best = None
    for first, second in ((box_a, box_b), (box_b, box_a)):
        cx, cz, ux, uz, hl, hc = first
        ox, oz, oux, ouz, ohl, ohc = second
        for nx, nz, ext in ((ux, uz, hl), (-uz, ux, hc)):
            dc = abs((ox - cx) * nx + (oz - cz) * nz)
            proj = abs(oux * nx + ouz * nz) * ohl + abs(-ouz * nx + oux * nz) * ohc
            gap = dc - ext - proj
            if best is None or gap > best:
                best = gap
    return best


def _sight_margin(crest_r, crest_top, hide_r, hide_h, head_h, eye_y=GUARD_EYE_Y):
    """Metres by which the crest top out-tops the straight eye-to-head line at
    the crest's radius. Positive means the crest blocks the eye; negative means
    the head is visible over it. The eye is on the ring axis, so the whole
    sight line lies in the head's own bearing plane and this is exact in 2D."""
    head_y = DECK_Z + hide_h + head_h
    line_y = eye_y + (crest_r / hide_r) * (head_y - eye_y)
    return (DECK_Z + crest_top) - line_y


def _bfs_reach(free, n_a, n_b, starts, jumps):
    """Flood fill a n_a x n_b occupancy grid. `free` is a bytearray of length
    n_a * n_b, index i * n_b + j, 1 == walkable. `starts` is an iterable of
    (i, j). `jumps` is a list of (i0, j0, i1, j1) extra bidirectional edges
    that bridge blocked ground, usable only when BOTH endpoints are free.
    Returns a bytearray `seen` of the same shape, 1 where reached."""
    seen = bytearray(n_a * n_b) if n_a > 0 and n_b > 0 else bytearray()
    if n_a <= 0 or n_b <= 0:
        return seen
    jump_map = {}
    for edge in (jumps or ()):
        i0, j0, i1, j1 = edge
        if not (0 <= i0 < n_a and 0 <= j0 < n_b):
            continue
        if not (0 <= i1 < n_a and 0 <= j1 < n_b):
            continue
        jump_map.setdefault((i0, j0), []).append((i1, j1))
        jump_map.setdefault((i1, j1), []).append((i0, j0))
    queue = deque()
    for start in starts:
        i, j = start
        if not (0 <= i < n_a and 0 <= j < n_b):
            continue
        idx = i * n_b + j
        if not free[idx] or seen[idx]:
            continue
        seen[idx] = 1
        queue.append((i, j))
    while queue:
        i, j = queue.popleft()
        for n_i, n_j in ((i - 1, j), (i + 1, j), (i, j - 1), (i, j + 1)):
            if 0 <= n_i < n_a and 0 <= n_j < n_b:
                k = n_i * n_b + n_j
                if free[k] and not seen[k]:
                    seen[k] = 1
                    queue.append((n_i, n_j))
        linked = jump_map.get((i, j))
        if linked:
            for n_i, n_j in linked:
                k = n_i * n_b + n_j
                if free[k] and not seen[k]:
                    seen[k] = 1
                    queue.append((n_i, n_j))
    return seen


# =============================================================================
# THE CORRIDOR -- the pad-free walking route, and the frame every feature hangs on
# =============================================================================

def _corr_r(b_deg):
    """Corridor centreline radius: a sweep plus a slower drift, so the route
    weaves across the deck rather than running a lane down the middle."""
    t = b_deg - S3_B0
    return (CORR_R_MID
            + CORR_A1 * math.sin(2.0 * math.pi * t / CORR_P1 + CORR_PH1)
            + CORR_A2 * math.sin(2.0 * math.pi * t / CORR_P2 + CORR_PH2))


def _corr_point(b_deg):
    """Corridor centreline plan point at a bearing."""
    return _plan(b_deg, _corr_r(b_deg))


def _corr_frame(b_deg):
    """Corridor forward unit vector and its inward normal at a bearing."""
    d = 0.02
    ax, az = _corr_point(b_deg - d)
    bx, bz = _corr_point(b_deg + d)
    fx, fz = bx - ax, bz - az
    mag = math.hypot(fx, fz)
    fx, fz = fx / mag, fz / mag
    px, pz = _corr_point(b_deg)
    nx, nz = -fz, fx                        # one of the two normals
    if nx * px + nz * pz > 0.0:             # make it point toward the tower
        nx, nz = -nx, -nz
    return (fx, fz, nx, nz)


def _corr_advance(b0, want):
    """The bearing whose corridor point is exactly `want` metres (straight line)
    from the corridor point at b0, going forward. Bisected, so the dip rims are
    exactly DIP_ALONG apart and the jump maths needs no arc-length fudge."""
    ax, az = _corr_point(b0)
    lo, hi = b0, b0 + 1.0
    while True:
        hx, hz = _corr_point(hi)
        if math.hypot(hx - ax, hz - az) >= want:
            break
        hi += 1.0
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        mx, mz = _corr_point(mid)
        if math.hypot(mx - ax, mz - az) < want:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)




# =============================================================================
# THE SURFACE -- one callable that IS the section
# =============================================================================
# Feature records are plain tuples, so the hot loop does no attribute lookups.
# Field 0 is the kind:
#   0 cover crest  (0, cx, cz, ux, uz, half_along, half_across, top, flat_frac)
#   1 dip saucer   (1, cx, cz, ux, uz, half_along, half_across, depth)
#   2 hide hollow  (2, hx, hz, radius, depth)
#   3 flat patch   (3, cx, cz, ux, uz, half_along, half_across, level)
#
# Every feature carries a weight w: 1.0 inside its plan footprint, falling to
# 0.0 over FLAT_BLEND outside it. The undulation is damped by (1 - max w), so
# no ripple rides a crest flank and spoils its angle. A flat patch PINS the
# surface to its own level -- exactly, whatever the pad's yaw -- and blends
# that level into the surroundings over the same FLAT_BLEND.
#
# Positives and negatives never stack: the tallest crest wins, else the
# deepest hollow wins. So the surface is bounded by construction at COVER_TOP_MAX
# above and -max(DIP_DEPTHS) below, whatever is laid where.

_K_COVER, _K_DIP, _K_HOLLOW, _K_FLAT = 0, 1, 2, 3


def _bucket(feats):
    """Index features by whole degree of bearing, so `height` tests a handful,
    not the whole field. Every feature is filed under every degree its plan
    footprint plus the blend can touch."""
    out = {}
    for f in feats:
        if f[0] == _K_HOLLOW:
            cx, cz, reach = f[1], f[2], f[3]
        else:
            cx, cz = f[1], f[2]
            reach = math.hypot(f[5], f[6])
        reach += FLAT_BLEND
        r = math.hypot(cx, cz)
        span = math.degrees(math.asin(min(1.0, reach / r))) + 1.0
        b = _bearing(cx, cz)
        for k in range(int(math.floor(b - span)), int(math.ceil(b + span)) + 1):
            out.setdefault(k, []).append(f)
    return dict((k, tuple(v)) for k, v in out.items())


def _make_height(feats, wave_p1, wave_p2):
    """Build the section's surface callable. Pure, deterministic, no globals."""
    buckets = _bucket(feats)
    ext0, ext1 = S3_EXT
    amp = FIELD_AMP
    inv_blend = 1.0 / FLAT_BLEND

    def height(gx, gz):
        r = math.hypot(gx, gz)
        if r < INNER_R or r > OUTER_R:
            return 0.0
        b = math.degrees(math.atan2(gz, gx))
        if b < 0.0:
            b += 360.0
        if b < ext0 or b > ext1:
            return 0.0
        pos = 0.0
        neg = 0.0
        shape_w = 0.0
        flat_w = 0.0
        flat_level = 0.0
        for f in buckets.get(int(b), ()):
            kind = f[0]
            if kind == _K_HOLLOW:
                d = math.hypot(gx - f[1], gz - f[2])
                q = 1.0 - d / f[3]
                if q > 0.0:
                    h = -f[4] * _smooth(q)
                    if h < neg:
                        neg = h
                    w = 1.0
                else:
                    w = 1.0 + q * f[3] * inv_blend
                if w > shape_w:
                    shape_w = w
                continue
            dx = gx - f[1]
            dz = gz - f[2]
            ux, uz = f[3], f[4]
            u = abs(dx * ux + dz * uz)
            v = abs(-dx * uz + dz * ux)
            hl, hc = f[5], f[6]
            du = u - hl
            dv = v - hc
            if du < 0.0:
                du = 0.0
            if dv < 0.0:
                dv = 0.0
            if du > FLAT_BLEND or dv > FLAT_BLEND:
                continue
            w = 1.0 - math.hypot(du, dv) * inv_blend
            if w <= 0.0:
                continue
            if w > shape_w:
                shape_w = w
            if kind == _K_COVER:
                ta, tc = u / hl, v / hc
                h = _crest_profile(ta if ta > tc else tc, f[7], f[8])
                if h > pos:
                    pos = h
            elif kind == _K_DIP:
                q = _dip_frac(u, v, hl, hc, DIP_SLOPE)
                if q > 0.0:
                    h = -f[7] * q
                    if h < neg:
                        neg = h
            elif w > flat_w:
                flat_w = w
                flat_level = f[7]
        if pos > 0.0:
            core = pos
        elif neg < 0.0:
            core = neg
        else:
            core = amp * (1.0 - shape_w) * (0.5 * math.sin(gx * FIELD_F1 + wave_p1) +
                                            0.5 * math.sin(gz * FIELD_F2 + wave_p2))
        if flat_w > 0.0:
            core = core * (1.0 - flat_w) + flat_level * flat_w
        if core == 0.0:
            return 0.0
        eb = min(b - ext0, ext1 - b) / EASE_B
        er = min(r - INNER_R, OUTER_R - r) / EASE_R
        return core * _smooth(eb) * _smooth(er)

    return height


# =============================================================================
# THE PAD SOLVER
# =============================================================================
# A pad throws the body PAD_RANGE from a take-off PAD_BACKSET behind the pad
# centre. The yaw is not chosen, it is solved: sweep candidate yaws, forward
# group first (increasing bearing, which is where the runner is going), then
# the backward group, and keep the first that lands on the field AND whose arc
# clears the rock. Past roughly b=185 the forward group is empty -- the far
# corner of the legal annulus is nearer than the flight is long -- so those
# pads fall through to backward on their own, with no bearing special case.

_YAW_DELTAS = tuple([0] + [s * d for d in range(YAW_STEP, YAW_SWEEP + 1, YAW_STEP)
                           for s in (1, -1)])


def _arc_ok(terrain, tx, tz, ux, uz, base_y, need):
    """True when the ballistic arc clears the rock by `need` from PAD_ARC_SKIP
    (the far edge of the pad's own flat patch) to the apex. Returns the worst
    clearance found, or None when it never gets there."""
    worst = None
    x = PAD_ARC_SKIP
    while x <= _ARC_APEX_X + 1e-9:
        y = base_y + x - _ARC_K * x * x
        clr = y - (DECK_Z + terrain(tx + ux * x, tz + uz * x))
        if worst is None or clr < worst:
            worst = clr
        if clr < need:
            return None
        x += 0.35
    return worst


def _land(cx, cz, yaw):
    """Take-off point, flight direction and landing point of a pad."""
    ux, uz = _dir(yaw)
    tx, tz = cx - ux * PAD_BACKSET, cz - uz * PAD_BACKSET
    return (tx, tz, ux, uz, tx + ux * PAD_RANGE, tz + uz * PAD_RANGE)


def _pad_box(cx, cz, yaw):
    """A pad's trigger-box footprint as an oriented box record."""
    ux, uz = _dir(yaw)
    return (cx, cz, ux, uz, PAD_BOX_ALONG, PAD_BOX_ACROSS)


def _solve_pad(cx, cz, terrain, yaw_groups, taken, covers, corr_pts,
               free_corridor, need_back_dr, cover_gap, dips=()):
    """Find a legal yaw for a pad at (cx, cz). `yaw_groups` is tried in order.
    Returns (yaw, land, worst_clearance, forward) or None."""
    r = math.hypot(cx, cz)
    if r < INNER_R + PAD_DISC_R or r > OUTER_R - PAD_DISC_R:
        return None
    for group in yaw_groups:
        for yaw in group:
            tx, tz, ux, uz, lx, lz = _land(cx, cz, yaw)
            land_r = math.hypot(lx, lz)
            if land_r < PAD_LAND_R0 or land_r > PAD_LAND_R1:
                continue
            land_b = _bearing(lx, lz)
            if land_b < PAD_LAND_B0 or land_b > PAD_LAND_B1:
                continue
            if land_b <= _bearing(cx, cz):
                continue      # never backward: it loops a bot round the ring
            forward = True
            if not _land_clear(lx, lz, covers, dips):
                continue      # nothing to land on: the bake would carve it out
            box = _pad_box(cx, cz, yaw)
            bad = False
            for cov in covers:
                if _obb_gap(box, cov) < cover_gap:
                    bad = True
                    break
            if bad:
                continue
            for other in taken:
                if _obb_gap(box, other) < PAD_GAP:
                    bad = True
                    break
            if bad:
                continue
            if free_corridor:
                pb = _bearing(cx, cz)
                for sb, sx, sz in corr_pts:
                    if abs(sb - pb) > 4.0:
                        continue
                    if _disc_box_overlap(sx, sz, CORR_HALF, cx, cz, yaw,
                                         PAD_BOX_ACROSS, PAD_BOX_ALONG):
                        bad = True
                        break
            if bad:
                continue
            base_y = DECK_Z + terrain(cx, cz)
            worst = _arc_ok(terrain, tx, tz, ux, uz, base_y, PAD_ARC_CLEAR + 0.15)
            if worst is None:
                continue
            return (yaw, (lx, lz), worst, forward)
    return None


def _plan_gap(px, pz, box):
    """Plan distance from a point to an oriented box footprint, 0.0 inside."""
    cx, cz, ux, uz, hl, hc = box
    dx, dz = px - cx, pz - cz
    du = abs(dx * ux + dz * uz) - hl
    dv = abs(-dx * uz + dz * ux) - hc
    return math.hypot(max(du, 0.0), max(dv, 0.0))


def _land_clear(lx, lz, rock, dips):
    """True when a landing has walkable floor around it: inside the walkable
    annulus by PAD_LAND_EDGE, and PAD_LAND_CLEAR from every crest and dip."""
    lr = math.hypot(lx, lz)
    if lr < GRID_R0 + PAD_LAND_EDGE or lr > GRID_R1 - PAD_LAND_EDGE:
        return False
    for box in rock:
        if _plan_gap(lx, lz, box) < PAD_LAND_CLEAR:
            return False
    for box in dips:
        if _plan_gap(lx, lz, box) < PAD_LAND_CLEAR:
            return False
    return True


def _yaw_groups(b_deg, deltas=_YAW_DELTAS):
    """Candidate yaws, forward only -- the backward group does not exist."""
    return ([b_deg + 90.0 + d for d in deltas],)


# =============================================================================
# BUILD
# =============================================================================
# Every published record carries only what the scene and the mesh need, and
# only what the self-proof can re-derive from the public interface alone: a
# crest's ridge axis is the tangent at its own bearing, a hide spot shares its
# crest's bearing, a dip's axis is rim0 -> rim1. Nothing private leaks out, so
# the proof cannot cheat by reading the builder's working notes.

def _fit_crest(spec, ux, uz, mx, mz, outer_face):
    """Draw a crest and SOLVE its size so it fits between `outer_face` (the
    radius its outward side may reach) and the pit lip, measuring the ROTATED
    reach along the radial. Solved in one step rather than shrunk in a loop, so
    the shape it lands on is exactly the one _min_crest_fits bounds and the two
    can never disagree. Returns (r, top, half_along, half_across, flat_frac) or
    None when nothing fits at this bearing. The spec is passed in rather than
    drawn here so a caller can fit the same piece twice without moving the
    seed."""
    top, hl, hc, _frac = spec
    a = abs(ux * mx + uz * mz)
    b = abs(-uz * mx + ux * mz)
    reach_max = 0.5 * (outer_face - INNER_R - COVER_EDGE_PAD)
    if COVER_MIN_HALF_ALONG * a + COVER_MIN_HALF_ACROSS * b > reach_max:
        return None
    if hl * a + hc * b > reach_max:
        # Trim the WIDTH first and keep the LENGTH. Length is what casts the
        # shadow the cover bake has to be able to sample, so a crest that must
        # give something up gives up girth, not reach along the run.
        hc = max(COVER_MIN_HALF_ACROSS, (reach_max - hl * a) / b)
        if hl * a + hc * b > reach_max:
            hl = COVER_MIN_HALF_ALONG if a < 1e-9 else (reach_max - hc * b) / a
    if hl < COVER_MIN_HALF_ALONG or hc < COVER_MIN_HALF_ACROSS:
        return None
    cr = outer_face - (hl * a + hc * b)
    return (cr, top, hl, hc, min(_flat_frac(top, hl, hc), COVER_FLAT_MAX))


def _dip_geom(bd):
    """A dip's straight-chord geometry at a bearing: rims exactly DIP_ALONG
    apart, the saucer centre, the chord axis and where its pad sits."""
    r0x, r0z = _corr_point(bd)
    r1x, r1z = _corr_point(_corr_advance(bd, DIP_ALONG))
    ux, uz = (r1x - r0x) / DIP_ALONG, (r1z - r0z) / DIP_ALONG
    pad_s = DIP_PAD_NEAR + PAD_BOX_ALONG
    return {"bd": bd, "rim0": (r0x, r0z), "rim1": (r1x, r1z),
            "mid": (r0x + ux * 0.5 * DIP_ALONG, r0z + uz * 0.5 * DIP_ALONG),
            "u": (ux, uz), "pc": (r0x + ux * pad_s, r0z + uz * pad_s),
            "yaw": _bearing(ux, uz)}


def _dip_yaw_groups(d):
    """A dip pad's candidate yaws: along the chord, then reversed, each with a
    small sweep. Anything wider would move its trigger box's near and far
    edges off the 2.00 / 4.50 m the jump proof is written against."""
    sweep = [0] + [sg * k for k in range(YAW_STEP, DIP_YAW_SWEEP + 1, YAW_STEP)
                   for sg in (1, -1)]
    return ([d["yaw"] + k for k in sweep], [d["yaw"] + 180.0 + k for k in sweep])


def _flight_exists(cx, cz, yaw_groups):
    """True when some candidate yaw puts the pad's disc on the deck and its
    landing inside the legal annulus segment. Pure geometry -- no terrain, so
    it can be asked before the crests that shape the terrain are placed."""
    if math.hypot(cx, cz) < INNER_R + PAD_DISC_R:
        return False
    if math.hypot(cx, cz) > OUTER_R - PAD_DISC_R:
        return False
    for group in yaw_groups:
        for yaw in group:
            _tx, _tz, _ux, _uz, lx, lz = _land(cx, cz, yaw)
            lr = math.hypot(lx, lz)
            if lr < PAD_LAND_R0 or lr > PAD_LAND_R1:
                continue
            lb = _bearing(lx, lz)
            if lb <= _bearing(cx, cz):
                continue
            if PAD_LAND_B0 <= lb <= PAD_LAND_B1:
                return True
    return False


def _min_crest_fits(b_deg, outer_face):
    """True when even the SMALLEST crest _fit_crest may return still clears the
    pit lip at this bearing. _fit_crest only ever shrinks, so this is exactly
    the condition under which it succeeds -- and it costs no rng draw, so it
    can be asked speculatively without moving the seed."""
    ux, uz = _dir(_cover_yaw(b_deg))
    mx, mz = math.cos(math.radians(b_deg)), math.sin(math.radians(b_deg))
    reach = _box_reach(ux, uz, COVER_MIN_HALF_ALONG, COVER_MIN_HALF_ACROSS, mx, mz)
    return outer_face - 2.0 * reach >= INNER_R + COVER_EDGE_PAD


BUTTRESS_TOP = 1.55         # the outer shoulder's height above DECK_Z
BUTTRESS_ALONG = 1.70       # half its length along the run: it must out-span the pad
BUTTRESS_REACH = 0.40       # how far past the walkable outer edge it runs
BUTTRESS_FLANK = 52.0       # flanks solved to beat this, degrees


def _dip_buttress(pad_c, pad_yaw):
    """The rock shoulder that shuts a dip's OUTER side.

    It used to be a pad, and that was the thing that broke: a pad there sits at
    r ~55, and under forward-only NO flight from r ~55 lands legally -- it
    overshoots the annulus unless it aims hard inward, and then it lands on a
    crest. That one requirement collapsed the viable dip bearings to 3.1 deg,
    i.e. two dips, against a brief that asks for three. Rock needs no flight.
    Derived entirely from the dip pad's published position and yaw, so the
    walkability proof re-derives the identical shoulder.
    """
    pb = _bearing(*pad_c)
    _fx, _fz, nx, nz = _corr_frame(pb)
    bx, bz = _corr_point(pb)
    pux, puz = _dir(pad_yaw)
    out = -((pad_c[0] - bx) * nx + (pad_c[1] - bz) * nz)
    face = out + _box_reach(pux, puz, PAD_BOX_ALONG, PAD_BOX_ACROSS, nx, nz)
    wall = (GRID_R1 - math.hypot(bx, bz)) + BUTTRESS_REACH
    half = 0.5 * (wall - (face + PAD_GAP))
    if half <= 0.0:
        return None
    off = face + PAD_GAP + half
    cx, cz = bx - nx * off, bz - nz * off
    ux, uz = -nz, nx                     # along the run, square to the normal
    frac = max(1.0 - BUTTRESS_TOP / (math.tan(math.radians(BUTTRESS_FLANK))
                                     * max(BUTTRESS_ALONG, half)), 0.0) + 0.02
    if frac > COVER_FLAT_MAX:
        return None
    return (cx, cz, ux, uz, BUTTRESS_ALONG, half, BUTTRESS_TOP, frac)


def _dip_viable(bd):
    """True when a bearing can carry a WHOLE dip: the saucer inside DIP_BAND,
    a crest inward of its pad, a legal flight off that pad, and a pinch pad
    outward of it with a legal flight of its own. Checked before anything is
    committed, so a bearing that only half works is passed over instead of
    failing the build."""
    span = int(DIP_ALONG / 0.45) + 2
    if not all(DIP_BAND[0] <= _corr_r(bd + k * 0.5) <= DIP_BAND[1]
               for k in range(span)):
        return False
    d = _dip_geom(bd)
    cx, cz = d["pc"]
    pb = _bearing(cx, cz)
    pr = math.hypot(cx, cz)
    mx, mz = math.cos(math.radians(pb)), math.sin(math.radians(pb))
    pux, puz = _dir(d["yaw"])
    pad_reach = _box_reach(pux, puz, PAD_BOX_ALONG, PAD_BOX_ACROSS, mx, mz)
    # the same seal condition _build uses, so viability and building agree
    lip = max(INNER_R + COVER_EDGE_PAD, GRID_R0 + DIP_SEAL_GAP)
    half = 0.5 * ((pr - pad_reach - PAD_GAP_DIP - DIP_YAW_MARGIN
                   - DIP_COVER_SLACK) - lip)
    if half < COVER_SEAL_HALF_MIN or half > COVER_SEAL_HALF_MAX:
        return False
    if not _flight_exists(cx, cz, _dip_yaw_groups(d)):
        return False
    return _dip_buttress((cx, cz), d["yaw"]) is not None


class _Retry(Exception):
    """Raised when a chosen set of dip bearings cannot carry a whole section.
    _dip_viable cannot see the crests -- they are not placed yet -- so a bearing
    that passes every test it CAN run may still lose its pad's landing to a
    crest later. The build catches this and tries the next candidate set."""


def _dip_candidates():
    """Every bearing that can carry a dip on its own merits."""
    out = []
    b = DIP_SEARCH[0]
    while b <= DIP_SEARCH[1]:
        if _dip_viable(b):
            out.append(b)
        b += 0.25
    return out


def _dip_sets(cands):
    """Candidate triples, DIP_SEP apart, greedy from each start in turn."""
    sets = []
    for start in range(len(cands)):
        picks = []
        for b in cands[start:]:
            if all(abs(b - q) >= DIP_SEP for q in picks):
                picks.append(b)
        if len(picks) >= 3 and tuple(picks[:3]) not in sets:
            sets.append(tuple(picks[:3]))
    if not sets:
        raise AssertionError("the weave leaves no room for three dips")
    return sets


def _shuffle(seq, rng):
    """Deterministic Fisher-Yates, so the pad pack is a scatter and not a row."""
    out = list(seq)
    for i in range(len(out) - 1, 0, -1):
        j = rng.i(0, i)
        out[i], out[j] = out[j], out[i]
    return out


def _build_try(dip_bearings):
    """Lay the section out for one choice of dip bearings. Deterministic in
    S3_SEED: the rng starts here, so the section finally returned does not
    depend on how many attempts came before it."""
    rng = _Rng(S3_SEED)
    wave_p1 = rng.f() * 2.0 * math.pi
    wave_p2 = rng.f() * 2.0 * math.pi

    corr_pts = []
    bb = S3_EXT[0] - 1.0
    while bb <= S3_EXT[1] + 1.0:
        px, pz = _corr_point(bb)
        corr_pts.append((bb, px, pz))
        bb += 0.20

    # ---- the dips: rims exactly DIP_ALONG apart, pad on the saucer floor ----
    dip_work = []
    for idx, bd in enumerate(dip_bearings):
        d = _dip_geom(bd)
        d["depth"] = DIP_DEPTHS[idx]
        dip_work.append(d)

    # ---- cover -------------------------------------------------------------
    # Three crests come with the dips, pinned to their pads. The rest are laid
    # along the corridor wherever it runs far enough out for a crest to fit
    # inward of it, at irregular gaps, each its own shape.
    specs = []
    for d in dip_work:
        pb = _bearing(*d["pc"])
        pr = math.hypot(*d["pc"])
        mx, mz = math.cos(math.radians(pb)), math.sin(math.radians(pb))
        cux, cuz = _dir(_cover_yaw(pb))
        pux, puz = _dir(d["yaw"])
        pad_reach = _box_reach(pux, puz, PAD_BOX_ALONG, PAD_BOX_ACROSS, mx, mz)
        # the SAME gap the check below demands -- building in a smaller one and
        # then testing for a larger one leaves the seal permanently short
        want = PAD_GAP_DIP + DIP_YAW_MARGIN
        face = pr - pad_reach - want - DIP_COVER_SLACK
        # A dip's crest is not just cover, it is the SEAL on the tower side. The
        # whole strip from the pad to the pit lip has to be shut or a runner
        # walks round the inside of the saucer -- measured, the BFS did exactly
        # that. So this crest's width is not drawn, it is solved to span from
        # the pad gap down to the lip.
        lip = max(INNER_R + COVER_EDGE_PAD, GRID_R0 + DIP_SEAL_GAP)
        spec = _crest_spec(rng, True)

        def _seal(outer, along, sp=spec):
            half = 0.5 * (outer - lip)
            if half < COVER_SEAL_HALF_MIN or half > COVER_SEAL_HALF_MAX:
                return None
            hl = max(along, half, COVER_MIN_HALF_ALONG)
            return (outer - half, sp[0], hl, half,
                    min(_flat_frac(sp[0], hl, half), COVER_FLAT_MAX))

        along0 = max(spec[1], COVER_MIN_HALF_ALONG)
        got = _seal(face, along0)
        if got is None:
            raise _Retry("dip at b=%.1f cannot be sealed on the tower side" % pb)
        # Positioning by radial reach is not enough once a crest is a long ridge
        # at a yaw of its own: measure the real box-to-box gap to the pad and
        # pull the crest back by whatever it is short.
        # What reaches the pad is the ridge's END, not its side: it is long and
        # sits at a yaw of its own, so trim the LENGTH first and only pull the
        # whole piece inward once it is already as short as a crest may be.
        pad_box = _pad_box(d["pc"][0], d["pc"][1], d["yaw"])
        outer, along = face, along0
        for _ in range(24):
            gx, gz = _plan(pb, got[0])
            gap = _obb_gap(pad_box, (gx, gz, cux, cuz, got[2], got[3]))
            if gap >= want:
                break
            if along > COVER_MIN_HALF_ALONG + 1e-9:
                along = max(COVER_MIN_HALF_ALONG, along - (want - gap))
            else:
                outer -= (want - gap)
            got = _seal(outer, along)
            if got is None:
                raise _Retry("no crest clears the dip pad at b=%.1f" % pb)
        specs.append((pb,) + got)

    # A crest competes with the inner pad lane for the same band of deck, so it
    # is placed where it costs least: the bearings where the weave carries the
    # route furthest out and there is room for both. Best spots first.
    placed_b = [sp[0] for sp in specs]
    slots = []
    b = S3_B0 + 1.0
    while b <= S3_B1 - 1.0:
        if _corr_r(b) >= COVER_MIN_CORR_R:
            slots.append(b)
        b += 0.25
    slots.sort(key=lambda q: -_corr_r(q))
    for b in slots:
        if len(specs) >= COVER_TARGET + len(dip_work):
            break
        rc = _corr_r(b)
        gap_m = _uniform(rng, (COVER_GAP_MIN, COVER_GAP_MAX))
        if any(abs(b - q) * math.pi * rc / 180.0 < gap_m for q in placed_b):
            continue
        mx, mz = math.cos(math.radians(b)), math.sin(math.radians(b))
        cux, cuz = _dir(_cover_yaw(b))
        spec = _crest_spec(rng, rng.f() < 0.55)
        got = _fit_crest(spec, cux, cuz, mx, mz, rc - CORR_HALF)
        if got is None:
            continue
        # A crest is positioned by its RADIAL reach but what must clear the
        # route is its face along the corridor NORMAL, and the weave tilts the
        # two apart. Pull it back by the difference, or a long ridge at a
        # tilted stretch lays its corner across the centreline.
        _fx, _fz, nx, nz = _corr_frame(b)
        extra = (_box_reach(cux, cuz, got[2], got[3], nx, nz) -
                 _box_reach(cux, cuz, got[2], got[3], mx, mz))
        if extra > 0.0:
            got = _fit_crest(spec, cux, cuz, mx, mz, rc - CORR_HALF - extra)
            if got is None:
                continue
        specs.append((b,) + got)
        placed_b.append(b)
    specs.sort()

    covers = []
    cover_boxes = []
    hollows = []
    for cb, cr, top, hl, hc, frac in specs:
        ux, uz = _dir(_cover_yaw(cb))
        cx, cz = _plan(cb, cr)
        hide_r = _corr_r(cb) - CORR_HALF + _uniform(rng, (HIDE_GAP_MIN, HIDE_GAP_MAX))
        hx, hz = _plan(cb, hide_r)
        covers.append({"b": cb, "r": cr, "top": top, "half_along": hl,
                       "half_across": hc, "hide_r": hide_r})
        cover_boxes.append((cx, cz, ux, uz, hl, hc))
        hollows.append((_K_HOLLOW, hx, hz,
                        _uniform(rng, (HIDE_RAD_MIN, HIDE_RAD_MAX)), HIDE_DEPTH))

    # ---- the terrain the arcs are solved against: rock only, no pads -------
    shape_feats = list(hollows)
    lump_boxes = []
    for c, box, spec in zip(covers, cover_boxes, specs):
        shape_feats.append((_K_COVER,) + box + (c["top"], spec[5]))
        for lx, lz, lux, luz, lh, _lh2, ltop, lfrac in _cover_lumps(c):
            shape_feats.append((_K_COVER, lx, lz, lux, luz, lh, lh, ltop, lfrac))
            lump_boxes.append((lx, lz, lux, luz, lh, lh))
    for d in dip_work:
        shape_feats.append((_K_DIP, d["mid"][0], d["mid"][1], d["u"][0], d["u"][1],
                            0.5 * DIP_ALONG, DIP_HALF_ACROSS, d["depth"]))
    terrain = _make_height(shape_feats, wave_p1, wave_p2)
    rock_boxes = cover_boxes + lump_boxes
    dip_boxes = [(d["mid"][0], d["mid"][1], d["u"][0], d["u"][1],
                  0.5 * DIP_ALONG, DIP_HALF_ACROSS) for d in dip_work]

    # ---- pads: the three dip pads, their outer pinch pads, then the field ---
    work = []
    taken = []
    for d in dip_work:
        cx, cz = d["pc"]
        got = _solve_pad(cx, cz, terrain, _dip_yaw_groups(d), taken, rock_boxes,
                         corr_pts, False, False, PAD_GAP_DIP, dip_boxes)
        if got is None:
            raise _Retry("dip pad at b=%.1f has no legal yaw" % d["bd"])
        yaw, land, _worst, _fwd = got
        d["pad_c"] = (cx, cz)
        d["pad_yaw"] = yaw
        work.append((_bearing(cx, cz), math.hypot(cx, cz), yaw, land, (cx, cz),
                     -d["depth"]))
        taken.append(_pad_box(cx, cz, yaw))

    # Each dip's OUTER side is shut with rock, not with a pad -- see
    # _dip_buttress for why a pad there cannot exist under forward-only.
    for d in dip_work:
        bt = _dip_buttress(d["pc"], d["pad_yaw"])
        if bt is None:
            raise _Retry("no buttress fits outward of the dip at b=%.1f" % d["bd"])
        shape_feats.append((_K_COVER,) + bt)
        rock_boxes.append(bt[:6])
    terrain = _make_height(shape_feats, wave_p1, wave_p2)

    # The field is a MINEFIELD, not two rows: candidates over the whole deck
    # width are shuffled once and packed in that order, so the pads land in a
    # scatter across the section instead of queueing up along two radii.
    back = 0          # only FIELD pads are capped: the six above are structural
    field = []
    pb = S3_B0 + 0.5
    while pb <= S3_B1 - 0.5:
        radii = []
        pr = PAD_LATTICE_R0
        while pr <= PAD_LATTICE_R1 + 1e-9:
            radii.append(pr)
            pr += PAD_LATTICE_DR
        # Bearings are walked in order, so the pack stays tight along the run;
        # radii are shuffled inside each column, and because the route weaves,
        # the pads follow it instead of forming two tidy concentric arcs.
        for pr in _shuffle(radii, rng):
            cx, cz = _plan(pb, pr)
            got = _solve_pad(cx, cz, terrain, _yaw_groups(pb), taken, rock_boxes,
                             corr_pts, True, True, PAD_GAP_COVER, dip_boxes)
            if got is None:
                continue
            yaw, land, _worst, fwd = got
            if not fwd:
                if back >= BACK_MAX:
                    continue
                back += 1
            field.append((pb, pr, yaw, land, (cx, cz), 0.0))
            taken.append(_pad_box(cx, cz, yaw))
        pb += PAD_LATTICE_DB

    allow = PAD_MAX - len(work)
    if len(field) > allow:
        n = len(field)
        field = [field[int(i * n / allow)] for i in range(allow)]
    work.extend(field)

    work.sort(key=lambda w: w[0])
    pads = [{"b": w[0], "r": w[1], "yaw": w[2], "land": w[3]} for w in work]

    dips = []
    for d in dip_work:
        idx = next(i for i, w in enumerate(work) if w[4] == d["pad_c"])
        dips.append({"b": d["bd"], "r": _corr_r(d["bd"]), "depth": d["depth"],
                     "along": DIP_ALONG, "pad": idx,
                     "rim0": d["rim0"], "rim1": d["rim1"]})

    # ---- the surface: rock plus every pad's flat patch ---------------------
    feats = list(shape_feats)
    for w in work:
        ux, uz = _dir(w[2])
        feats.append((_K_FLAT, w[4][0], w[4][1], ux, uz,
                      PAD_BOX_ALONG, PAD_BOX_ACROSS, w[5]))

    corridor = []
    cb = CORR_B0
    while cb <= CORR_B1 + 1e-9:
        corridor.append((cb, _corr_r(cb)))
        cb += CORR_STEP

    return {
        "ext": S3_EXT,
        "cols": _spread(S3_EXT[0], S3_EXT[1], COL_COUNT, rng),
        "stations": _spread(INNER_R, OUTER_R, STATION_COUNT, rng),
        "height": _make_height(feats, wave_p1, wave_p2),
        "field_amp": FIELD_AMP,
        "covers": covers,
        "pads": pads,
        "dips": dips,
        "corridor": corridor,
    }


def _build():
    """Lay the section out, walking the candidate dip sets until one carries a
    whole section: a crest landing where a dip pad must land costs a retry
    rather than the build."""
    why = None
    for picks in _dip_sets(_dip_candidates()):
        try:
            return _build_try(picks)
        except _Retry as exc:
            why = "%s (dips %s)" % (exc, [round(q, 1) for q in picks])
    raise AssertionError("no dip set carries a whole section; last: %s" % why)


_LAYOUT = None


def layout():
    """Deterministic and cached: the identical dict on every call."""
    global _LAYOUT
    if _LAYOUT is None:
        _LAYOUT = _build()
    return _LAYOUT


# =============================================================================
# SELF-PROOF SUPPORT
# =============================================================================
# The proof works from the PUBLIC interface only -- layout()'s dict and the
# plan helpers. It re-derives a crest's ridge axis, a dip's axis and every
# pad's box from published numbers, so it cannot agree with the builder by
# reading the builder's own working notes.

_PF_HASH_CELL = 3.0        # plan hash cell for the body sweep, metres
_PF_NB = [0]               # grid row stride, set once the grid is built


def _pf_digest(lay):
    """A stable text digest of everything layout() publishes -- every float via
    float.hex(), every collection in its published order, plus `height` on a
    fixed grid. Two builds that agree here produce the same mesh bytes."""
    out = ["ext %s %s" % (lay["ext"][0].hex(), lay["ext"][1].hex()),
           "amp %s" % lay["field_amp"].hex()]
    out.append("cols " + " ".join(v.hex() for v in lay["cols"]))
    out.append("stations " + " ".join(v.hex() for v in lay["stations"]))
    for c in lay["covers"]:
        out.append("cover " + " ".join("%s=%s" % (k, c[k].hex())
                                       for k in sorted(c)))
    for q in lay["pads"]:
        out.append("pad b=%s r=%s yaw=%s land=%s,%s"
                   % (q["b"].hex(), q["r"].hex(), q["yaw"].hex(),
                      q["land"][0].hex(), q["land"][1].hex()))
    for d in lay["dips"]:
        out.append("dip b=%s r=%s depth=%s along=%s pad=%d r0=%s,%s r1=%s,%s"
                   % (d["b"].hex(), d["r"].hex(), d["depth"].hex(),
                      d["along"].hex(), d["pad"], d["rim0"][0].hex(),
                      d["rim0"][1].hex(), d["rim1"][0].hex(), d["rim1"][1].hex()))
    out.append("corridor " + " ".join("%s,%s" % (b.hex(), r.hex())
                                      for b, r in lay["corridor"]))
    height = lay["height"]
    grid = []
    for i in range(200):
        b = S3_EXT[0] + (S3_EXT[1] - S3_EXT[0]) * (i % 25) / 24.0
        r = INNER_R + (OUTER_R - INNER_R) * (i // 25) / 7.0
        grid.append(height(*_plan(b, r)).hex())
    out.append("height " + " ".join(grid))
    return "\n".join(out)


def _pf_rock(lay):
    """Only the ROCK: crests, their lumps, and each dip's outer buttress. Pads
    are NOT here -- Godot's bake treats a pad as a link, not an obstacle, so
    the navmesh's own connectivity depends on rock alone. This is the set the
    nav disc must roll through without any jump."""
    obs = []
    for c in lay["covers"]:
        cx, cz = _plan(c["b"], c["r"])
        obs.append((cx, cz, _cover_yaw(c["b"]), c["half_across"], c["half_along"]))
        for lx, lz, _ux, _uz, lh, _lh2, _lt, _lf in _cover_lumps(c):
            obs.append((lx, lz, _cover_yaw(c["b"]), lh, lh))
    for d in lay["dips"]:
        q = lay["pads"][d["pad"]]
        bt = _dip_buttress(_plan(q["b"], q["r"]), q["yaw"])
        if bt is not None:
            obs.append((bt[0], bt[1], math.degrees(math.atan2(bt[3], bt[2])),
                        bt[5], bt[4]))
    return obs


def _pf_obstacles(lay, drop=()):
    """Every solid thing a walking body can be stopped by, as boxes:
    (cx, cz, yaw, half_across, half_along). Pad trigger boxes, plus the crest
    footprints -- a crest's flanks are over 46 deg, so it is a wall, not a
    ramp, and leaving it out would flatter the corridor."""
    obs = []
    for i, p in enumerate(lay["pads"]):
        if i in drop:
            continue
        cx, cz = _plan(p["b"], p["r"])
        obs.append((cx, cz, p["yaw"], PAD_BOX_ACROSS, PAD_BOX_ALONG))
    for c in lay["covers"]:
        cx, cz = _plan(c["b"], c["r"])
        obs.append((cx, cz, _cover_yaw(c["b"]), c["half_across"], c["half_along"]))
        for lx, lz, _ux, _uz, lh, _lh2, _lt, _lf in _cover_lumps(c):
            obs.append((lx, lz, _cover_yaw(c["b"]), lh, lh))
    # Each dip's outer shoulder is rock too, and it is what shuts that side.
    for d in lay["dips"]:
        q = lay["pads"][d["pad"]]
        bt = _dip_buttress(_plan(q["b"], q["r"]), q["yaw"])
        if bt is not None:
            obs.append((bt[0], bt[1], math.degrees(math.atan2(bt[3], bt[2])),
                        bt[5], bt[4]))
    return obs


def _pf_hash(obs, rad):
    """Bucket boxes by plan cell so a point test looks at a handful, not all."""
    out = {}
    for o in obs:
        reach = math.hypot(o[3], o[4]) + rad
        for i in range(int(math.floor((o[0] - reach) / _PF_HASH_CELL)),
                       int(math.floor((o[0] + reach) / _PF_HASH_CELL)) + 1):
            for j in range(int(math.floor((o[1] - reach) / _PF_HASH_CELL)),
                           int(math.floor((o[1] + reach) / _PF_HASH_CELL)) + 1):
                out.setdefault((i, j), []).append(o)
    return out


def _pf_clear(px, pz, rad, hsh):
    """True when a disc of radius rad at (px, pz) hits nothing in the hash."""
    key = (int(math.floor(px / _PF_HASH_CELL)), int(math.floor(pz / _PF_HASH_CELL)))
    for o in hsh.get(key, ()):
        if _disc_box_overlap(px, pz, rad, o[0], o[1], o[2], o[3], o[4]):
            return False
    return True


def _pf_bbox():
    """Tight plan bounding box of the swept annulus, so the grid is 0.1 M cells
    and not 1.4 M."""
    xs, zs = [], []
    b = GRID_B0
    while b <= GRID_B1 + 1e-9:
        for r in (GRID_R0, GRID_R1):
            px, pz = _plan(b, r)
            xs.append(px)
            zs.append(pz)
        b += 0.10
    return (min(xs) - 0.2, min(zs) - 0.2, max(xs) + 0.2, max(zs) + 0.2)


def _pf_grid(hsh):
    """The body-sweep grid: GRID_STEP cells over the annulus, 1 where an
    0.40 m capsule fits. Returns (free, n_a, n_b, x0, z0, bear); `bear` holds
    each cell's bearing, so a bearing window costs a copy, not a rebuild."""
    x0, z0, x1, z1 = _pf_bbox()
    n_a = int((x1 - x0) / GRID_STEP) + 1
    n_b = int((z1 - z0) / GRID_STEP) + 1
    free = bytearray(n_a * n_b)
    bear = [0.0] * (n_a * n_b)
    for i in range(n_a):
        px = x0 + i * GRID_STEP
        base = i * n_b
        for j in range(n_b):
            pz = z0 + j * GRID_STEP
            r = math.hypot(px, pz)
            if r < GRID_R0 or r > GRID_R1:
                continue
            b = _bearing(px, pz)
            if b < GRID_B0 or b > GRID_B1:
                continue
            bear[base + j] = b
            if _pf_clear(px, pz, BODY_R, hsh):
                free[base + j] = 1
    return (free, n_a, n_b, x0, z0, bear)


def _pf_window(free, bear, b_lo, b_hi):
    """A copy of `free` with everything outside a bearing window blocked."""
    out = bytearray(free)
    for k in range(len(out)):
        if out[k] and not (b_lo <= bear[k] <= b_hi):
            out[k] = 0
    return out


def _pf_cell(px, pz, n_b, x0, z0):
    """Plan point -> grid index pair."""
    return (int(round((px - x0) / GRID_STEP)), int(round((pz - z0) / GRID_STEP)))


def _pf_edges(free, bear, b_lo, b_hi):
    """Free cells at the low-bearing and high-bearing ends of a window."""
    lo, hi = [], []
    n_b = _PF_NB[0]
    for k in range(len(free)):
        if not free[k]:
            continue
        b = bear[k]
        if b <= b_lo:
            lo.append((k // n_b, k % n_b))
        elif b >= b_hi:
            hi.append((k // n_b, k % n_b))
    return (lo, hi)


def _pf_jumps(lay, n_b, x0, z0):
    """One jump edge per across-offset per dip: rim0 -> rim1, the only way
    over a dip pad. Its legality is proof item 4, not an assumption here."""
    out = []
    for d in lay["dips"]:
        r0, r1 = d["rim0"], d["rim1"]
        ux, uz = (r1[0] - r0[0]) / d["along"], (r1[1] - r0[1]) / d["along"]
        ax, az = -uz, ux
        for v in (-0.6, -0.3, 0.0, 0.3, 0.6):
            c0 = _pf_cell(r0[0] + ax * v, r0[1] + az * v, n_b, x0, z0)
            c1 = _pf_cell(r1[0] + ax * v, r1[1] + az * v, n_b, x0, z0)
            out.append((c0[0], c0[1], c1[0], c1[1]))
    return out


def _pf_span(b_deg, r_mid, hsh):
    """Clear width of the corridor at a bearing, measured PERPENDICULAR to the
    route -- the weave tilts the path up to ~15 deg off tangential, and a radial
    measurement would flatter the width by 1/cos of that. Returns
    (inward, outward) or None when the centreline itself is blocked."""
    px, pz = _plan(b_deg, r_mid)
    if not _pf_clear(px, pz, BODY_R, hsh):
        return None
    _fx, _fz, nx, nz = _corr_frame(b_deg)
    out = []
    for sign in (1.0, -1.0):
        d = 0.0
        while d < 12.0:
            d += 0.02
            qx, qz = px + nx * sign * d, pz + nz * sign * d
            r = math.hypot(qx, qz)
            if r < GRID_R0 or r > GRID_R1 or not _pf_clear(qx, qz, BODY_R, hsh):
                break
        out.append(d - 0.02)
    return (out[0], out[1])


def _pf_snap(b_deg, r, cols, stations):
    """The nearest node of the section's own cols x stations grid. The mesh is
    built on that grid, so this is the surface the game actually has."""
    cb = min(cols, key=lambda q: abs(q - b_deg))
    cr = min(stations, key=lambda q: abs(q - r))
    return (cb, cr)


def _pf_sampled(b_deg, r, cols, stations, height):
    """Rock height as the MESH has it: the field read at the nearest grid node."""
    cb, cr = _pf_snap(b_deg, r, cols, stations)
    return height(*_plan(cb, cr))


def _pf_blocked(cover, b_off_m, d_out, cols, stations, height):
    """True when a body standing d_out metres outward of a crest's face, and
    b_off_m metres along the run from its centre, is hidden from the measured
    eye at BOTH bake probe heights -- judged on the SAMPLED surface, which is
    what the cover bake will raycast."""
    b2 = cover["b"] + math.degrees(b_off_m / cover["r"])
    crest_top = _pf_sampled(b2, cover["r"], cols, stations, height)
    r_probe = cover["r"] + cover["half_across"] + d_out
    if r_probe > OUTER_R - 0.2:
        return False
    ground = _pf_sampled(b2, r_probe, cols, stations, height)
    for head in (BAKE_CHEST, BAKE_HEAD):
        if _sight_margin(cover["r"], crest_top, r_probe, ground, head) <= 0.0:
            return False
    return True


def _pf_patch(cover, cols, stations, height):
    """The crest's usable shadow: how deep it runs radially straight out from
    the crest, and how wide it runs along the run one metre out. Both on the
    sampled surface. This is the number that decides whether the cover bake,
    which samples on a BAKE_GRID grid, can see this crest at all."""
    depth = 0.0
    d = 0.2
    while d <= 8.0 and _pf_blocked(cover, 0.0, d, cols, stations, height):
        depth = d
        d += 0.2
    width = 0.0
    for sign in (1.0, -1.0):
        w = 0.1
        while w <= 6.0 and _pf_blocked(cover, sign * w, 1.0, cols, stations, height):
            width += 0.1
            w += 0.1
    return (width, depth)


# =============================================================================
# SELF-PROOF
# =============================================================================

if __name__ == "__main__":
    import sys
    import time

    LAY = layout()
    assert layout() is LAY, "layout() is not cached"
    H = LAY["height"]

    print("=" * 78)
    print("S3 THE MINEFIELD -- self proof")
    print("=" * 78)

    # ---- 1. schema ---------------------------------------------------------
    print("\n[1] SCHEMA")
    assert set(LAY) == {"ext", "cols", "stations", "height", "field_amp",
                        "covers", "pads", "dips", "corridor"}, sorted(LAY)
    print("  keys                 %s" % " ".join(sorted(LAY)))
    assert LAY["ext"] == (143.0, 202.0)
    print("  ext                  %s" % (LAY["ext"],))
    assert LAY["field_amp"] == 0.12
    print("  field_amp            %.2f" % LAY["field_amp"])

    cols = LAY["cols"]
    steps = [cols[i + 1] - cols[i] for i in range(len(cols) - 1)]
    print("  cols                 n=%d  %.3f .. %.3f  step %.4f..%.4f"
          % (len(cols), cols[0], cols[-1], min(steps), max(steps)))
    assert cols[0] == 143.0 and cols[-1] == 202.0
    assert min(steps) >= 0.30 and max(steps) <= 0.50

    sta = LAY["stations"]
    ssteps = [sta[i + 1] - sta[i] for i in range(len(sta) - 1)]
    print("  stations             n=%d  %.3f .. %.3f  step %.4f..%.4f"
          % (len(sta), sta[0], sta[-1], min(ssteps), max(ssteps)))
    assert sta[0] == 46.7 and sta[-1] == 57.3
    assert min(ssteps) >= 0.25 and max(ssteps) <= 0.50

    covers = LAY["covers"]
    assert 9 <= len(covers) <= 12, len(covers)
    for c in covers:
        assert set(c) == {"b", "r", "top", "half_along", "half_across", "hide_r"}
        assert 1.90 <= c["top"] <= 2.10
        assert c["hide_r"] > c["r"]
    print("  covers               n=%d" % len(covers))
    # The MESH samples `height` on this section's own grid, so the analytic peak
    # is not what the game gets. Assert the SAMPLED top, which is the number a
    # raycast onto the shipped collider returns.
    samp = [_pf_sampled(c["b"], c["r"], cols, sta, H) for c in covers]
    print("  crest top SAMPLED    %.3f .. %.3f m at the nearest cols x stations node"
          % (min(samp), max(samp)))
    for k, v in enumerate(samp):
        assert 1.90 <= v <= 2.10, (k, v)

    pads = LAY["pads"]
    for p in pads:
        assert set(p) == {"b", "r", "yaw", "land"}
    print("  pads                 n=%d  area %.1f%% of the field"
          % (len(pads), len(pads) * 6.25 / 529.2 * 100.0))
    assert PAD_MIN_ACHIEVED <= len(pads) <= PAD_MAX, len(pads)
    if len(pads) < PAD_BRIEF_MIN:
        last = max(q["b"] for q in pads)
        print("  *** DEVIATION         the brief asks %d..%d pads; this deck yields %d"
              % (PAD_BRIEF_MIN, PAD_MAX, len(pads)))
        print("      forward only      every pad must aim forward or it loops a bot")
        print("                        round the ring -- measured: six backward pads")
        print("                        failed test_a_runner_completes_a_lap, deleting")
        print("                        them turned it green. No forward flight lands")
        print("                        on the field past b=%.0f, so the last %.0f deg"
              % (last, S3_B1 - last))
        print("                        of the section carries no pads at all.")
        print("      live landings     a landing needs navmesh under it: %.2f m clear"
              % PAD_LAND_CLEAR)
        print("                        of every crest and dip, or the bake carves it")
        print("                        out and the pad is dead, not a launcher.")
        print("      deck width        10.6 m holds the corridor keep-out (2 x %.2f)"
              % (CORR_HALF + PAD_BOX_ACROSS))
        print("                        plus at most two 2.5 m pad lanes, and a crest")
        print("                        long enough for the cover bake to see its")
        print("                        shadow takes one lane at its own bearing.")
        print("      frontier          pads + 2 x covers ~= %d on this deck. A human"
              % (len(pads) + 2 * len(covers)))
        print("                        picks which number moves: pad count, crest")
        print("                        count, corridor width, or crest length.")

    dips = LAY["dips"]
    assert len(dips) == 3
    for d in dips:
        assert set(d) == {"b", "r", "depth", "along", "pad", "rim0", "rim1"}
        assert 0.50 <= d["depth"] <= 0.60
        assert d["along"] == 6.0
        assert 0 <= d["pad"] < len(pads)
        gap = math.hypot(d["rim1"][0] - d["rim0"][0], d["rim1"][1] - d["rim0"][1])
        assert abs(gap - 6.0) < 1e-6, gap
    print("  dips                 n=3  depths %s  rim gap %.6f"
          % ([d["depth"] for d in dips], gap))

    cor = LAY["corridor"]
    csteps = [cor[i + 1][0] - cor[i][0] for i in range(len(cor) - 1)]
    assert cor[0][0] <= 146.0 and cor[-1][0] >= 199.0
    assert max(csteps) <= 0.50
    print("  corridor             n=%d  b %.2f..%.2f  r %.2f..%.2f  step<=%.3f"
          % (len(cor), cor[0][0], cor[-1][0], min(c[1] for c in cor),
             max(c[1] for c in cor), max(csteps)))

    t0 = time.time()
    for _ in range(4000):
        H(-50.0, 12.0)
    print("  height cost          %.2f us/call" % ((time.time() - t0) / 4000 * 1e6))

    # ---- pad flatness over the whole footprint -----------------------------
    worst_flat = 0.0
    for p in pads:
        cx, cz = _plan(p["b"], p["r"])
        ux, uz = _dir(p["yaw"])
        ax, az = -uz, ux
        lvl = H(cx, cz)
        for iu in range(-5, 6):
            for iv in range(-5, 6):
                u, v = iu * 0.25, iv * 0.25
                dev = abs(H(cx + ux * u + ax * v, cz + uz * u + az * v) - lvl)
                worst_flat = max(worst_flat, dev)
    print("  pad patch flatness   worst deviation %.5f m over a 2.5x2.5 footprint"
          % worst_flat)
    assert worst_flat <= 0.02, worst_flat

    # ---- 2. walkability ----------------------------------------------------
    print("\n[2] WALKABILITY  (0.40 m body, 0.10 m grid, r %.1f..%.1f, b %.0f..%.0f)"
          % (GRID_R0, GRID_R1, GRID_B0, GRID_B1))
    obs = _pf_obstacles(LAY)
    hsh = _pf_hash(obs, BODY_R)
    free, n_a, n_b, x0, z0, bear = _pf_grid(hsh)
    _PF_NB[0] = n_b
    print("  grid                 %d x %d cells, %d free"
          % (n_a, n_b, sum(free)))
    jumps = _pf_jumps(LAY, n_b, x0, z0)
    lo, hi = _pf_edges(free, bear, 146.0, 199.0)
    seen = _bfs_reach(free, n_a, n_b, lo, jumps)
    reached = [c for c in hi if seen[c[0] * n_b + c[1]]]
    print("  route b<=146 -> b>=199   %s  (%d of %d far-edge cells reached)"
          % ("EXISTS" if reached else "NONE", len(reached), len(hi)))
    assert reached, "no walk-and-jump route through S3"

    dip_b = [(d["b"], _bearing(*d["rim1"])) for d in dips]
    narrow = None
    for cb, cr in cor:
        if cb < 146.0 or cb > 199.0:
            continue
        if any(lo_b - 1.0 <= cb <= hi_b + 1.0 for lo_b, hi_b in dip_b):
            continue
        sp = _pf_span(cb, cr, hsh)
        assert sp is not None, "corridor centreline blocked at b=%.2f" % cb
        w = sp[0] + sp[1] + 2.0 * BODY_R
        if narrow is None or w < narrow[0]:
            narrow = (w, cb)
    print("  narrowest clear width    %.2f m at b=%.2f  (dips excluded)"
          % (narrow[0], narrow[1]))
    assert narrow[0] >= 2.0 * BODY_R + GRID_STEP

    # THE CHECK THAT MATTERS TO A BOT. Re-run the same sweep with a disc the
    # size the navmesh bake actually leaves room for, not the size of the body.
    # Everything except a dip's 6.00 m gap -- which the jump bridges -- must let
    # it roll. This is the gate that catches a corridor the bake erodes away.
    nav_hsh = _pf_hash(obs, NAV_DISC_R)
    nav_free, _na, _nb, _nx0, _nz0, nav_bear = _pf_grid(nav_hsh)
    nav_lo, nav_hi = _pf_edges(nav_free, nav_bear, 146.0, 199.0)
    nav_seen = _bfs_reach(nav_free, n_a, n_b, nav_lo, jumps)
    nav_reached = [c for c in nav_hi if nav_seen[c[0] * n_b + c[1]]]
    print("  NAV DISC r=%.2f        route b<=146 -> b>=199   %s  (%d of %d far cells)"
          % (NAV_DISC_R, "ROLLS" if nav_reached else "BLOCKED",
             len(nav_reached), len(nav_hi)))
    nav_narrow = None
    for cb, cr in cor:
        if cb < 146.0 or cb > 199.0:
            continue
        if any(lo_b - 1.0 <= cb <= hi_b + 1.0 for lo_b, hi_b in dip_b):
            continue
        sp = _pf_span(cb, cr, nav_hsh)
        assert sp is not None, "the nav disc cannot even stand at b=%.2f" % cb
        w = sp[0] + sp[1] + 2.0 * NAV_DISC_R
        if nav_narrow is None or w < nav_narrow[0]:
            nav_narrow = (w, cb)
    print("                        narrowest %.2f m at b=%.2f, needs %.2f"
          % (nav_narrow[0], nav_narrow[1], 2.0 * NAV_DISC_R))
    assert nav_reached, "the navmesh disc cannot roll through S3"
    assert nav_narrow[0] >= 2.0 * NAV_DISC_R - 1e-9, nav_narrow

    # And the same disc on ROCK ALONE, with NO jump edges. Godot bakes a pad as
    # a link, not an obstacle, so this is what decides whether the navmesh is
    # one connected surface through the section -- the thing
    # test_the_bake_links_the_whole_lap_into_one_path asks.
    rock_hsh = _pf_hash(_pf_rock(LAY), NAV_DISC_R)
    rock_free, _ra, _rb, _rx0, _rz0, rock_bear = _pf_grid(rock_hsh)
    rock_lo, rock_hi = _pf_edges(rock_free, rock_bear, 146.0, 199.0)
    rock_seen = _bfs_reach(rock_free, n_a, n_b, rock_lo, [])
    rock_reached = [c for c in rock_hi if rock_seen[c[0] * n_b + c[1]]]
    print("  NAV ON ROCK ALONE     no jumps, no pads: %s  (%d of %d far cells)"
          % ("CONNECTED" if rock_reached else "SEVERED",
             len(rock_reached), len(rock_hi)))
    assert rock_reached, "rock alone severs the navmesh through S3"

    # ---- 3. the pad must be jumped -----------------------------------------
    print("\n[3] EACH DIP PAD CANNOT BE WALKED AROUND")
    for k, d in enumerate(dips):
        # clamped to the swept grid: the last dip's far rim sits close to the
        # section's end, and a window running off the grid would have no goal
        # cells and read as "impassable" for the wrong reason
        b_lo = max(GRID_B0 + 0.5, d["b"] - 3.0)
        b_hi = min(GRID_B1 - 0.5, _bearing(*d["rim1"]) + 3.0)
        win = _pf_window(free, bear, b_lo, b_hi)
        wlo, whi = _pf_edges(win, bear, b_lo + 0.4, b_hi - 0.4)
        got = _bfs_reach(win, n_a, n_b, wlo, [])
        with_pad = any(got[c[0] * n_b + c[1]] for c in whi)

        obs2 = _pf_obstacles(LAY, drop=(d["pad"],))
        hsh2 = _pf_hash(obs2, BODY_R)
        free2, _a2, _b2, _x2, _z2, bear2 = _pf_grid(hsh2)
        win2 = _pf_window(free2, bear2, b_lo, b_hi)
        wlo2, whi2 = _pf_edges(win2, bear2, b_lo + 0.4, b_hi - 0.4)
        got2 = _bfs_reach(win2, n_a, n_b, wlo2, [])
        without = any(got2[c[0] * n_b + c[1]] for c in whi2)

        # measured AT the pad, where the crest and the pinch pad are, not at rim0
        dp = pads[d["pad"]]
        sp = _pf_span(dp["b"], dp["r"], hsh2)
        pinch = sp[0] + sp[1] + 2.0 * BODY_R if sp else float("nan")
        # The 3.30 m pinch in the brief is a proxy for "the pad cannot be walked
        # around". Measure the thing itself: with the pad in, the widest clear
        # gap left beside it, against the 0.80 m body. The BFS above is the
        # direct proof; this is the margin by which it holds.
        side = _pf_span(dp["b"], dp["r"], hsh)
        widest = 0.0 if side is None else max(side) + BODY_R
        print("  dip %d b=%6.2f  walk route with pad: %-5s   pad deleted: %-5s"
              "   pinch %.2f m  widest side gap %.2f m (body %.2f)"
              % (k, d["b"], with_pad, without, pinch, widest, 2.0 * BODY_R))
        assert not with_pad, "dip %d can be walked around" % k
        assert without, "dip %d is impassable even without its pad" % k
        assert widest < 2.0 * BODY_R, (k, widest)
        if pinch > 3.30:
            print("      note              pinch is over the brief's 3.30 m, but the"
                  " widest")
            print("                        gap beside the pad is %.2f m against an"
                  " %.2f m body," % (widest, 2.0 * BODY_R))
            print("                        and the BFS above proves the route is shut.")

    # ---- 4. the jump -------------------------------------------------------
    print("\n[4] THE JUMP  (run %.1f m/s, jump %.1f m/s, g %.1f)"
          % (RUN_SPEED, JUMP_V, GRAVITY))
    x_lo = DIP_PAD_NEAR - BODY_R
    x_hi = DIP_PAD_NEAR + 2.0 * PAD_BOX_ALONG + BODY_R
    for k, d in enumerate(dips):
        worst = None
        x = x_lo
        while x <= x_hi + 1e-9:
            t = x / RUN_SPEED
            feet = d["depth"] + JUMP_V * t - 0.5 * GRAVITY * t * t
            if worst is None or feet < worst[0]:
                worst = (feet, x)
            x += 0.02
        margin = worst[0] - DIP_JUMP_CLEAR
        print("  dip %d depth %.2f  feet over floor %.3f m at x=%.2f  margin %.3f m"
              % (k, d["depth"], worst[0], worst[1], margin))
        assert margin >= JUMP_MARGIN_MIN, margin
    print("  box span checked     x %.2f .. %.2f m from rim0" % (x_lo, x_hi))
    print("  flat jump needed     %.2f m to rim1, available %.2f m"
          % (DIP_ALONG, JUMP_FLAT))
    assert DIP_ALONG <= JUMP_FLAT

    # ---- 5. every pad's flight ---------------------------------------------
    print("\n[5] PAD FLIGHTS  (range %.2f m, apex %.2f m)" % (PAD_RANGE, PAD_APEX))
    # Structural pads: the three in the dips, plus the pinch pad that shares
    # each dip pad's bearing. Their radii are fixed by the pinch, so the
    # anti-loop radial rule is a field-pad rule and cannot bind them.
    dip_pads = set(d["pad"] for d in dips)
    struct = set(dip_pads)
    for i in dip_pads:
        for j, q in enumerate(pads):
            # the pinch pad is the one sitting just OUTWARD of a dip pad at
            # essentially its bearing; offsetting along the corridor normal
            # rather than the radial shifts it by up to ~0.7 deg
            if j != i and abs(q["b"] - pads[i]["b"]) < 1.20 and q["r"] > pads[i]["r"]:
                struct.add(j)
    worst_arc = None
    worst_full = None
    n_fwd = n_back = n_back_field = 0
    for i, p in enumerate(pads):
        cx, cz = _plan(p["b"], p["r"])
        tx, tz, ux, uz, lx, lz = _land(cx, cz, p["yaw"])
        assert abs(lx - p["land"][0]) < 1e-9 and abs(lz - p["land"][1]) < 1e-9
        lr, lb = math.hypot(lx, lz), _bearing(lx, lz)
        assert PAD_LAND_R0 <= lr <= PAD_LAND_R1, (i, lr)
        assert PAD_LAND_B0 <= lb <= PAD_LAND_B1, (i, lb)
        fwd = lb > p["b"]
        base_y = DECK_Z + H(cx, cz)
        clr = None
        x = PAD_ARC_SKIP
        while x <= _ARC_APEX_X + 1e-9:
            g = (base_y + x - _ARC_K * x * x) - (DECK_Z + H(tx + ux * x, tz + uz * x))
            if clr is None or g < clr:
                clr = g
            x += 0.05
        assert clr >= PAD_ARC_CLEAR, (i, clr)
        if worst_arc is None or clr < worst_arc[0]:
            worst_arc = (clr, i)
        full = None
        x = PAD_ARC_SKIP
        while x <= PAD_RANGE - PAD_ARC_SKIP + 1e-9:
            g = (base_y + x - _ARC_K * x * x) - (DECK_Z + H(tx + ux * x, tz + uz * x))
            if full is None or g < full:
                full = g
            x += 0.05
        if worst_full is None or full < worst_full[0]:
            worst_full = (full, i)
        if fwd:
            n_fwd += 1
        else:
            n_back += 1
            if i not in struct:
                n_back_field += 1
                assert abs(lr - p["r"]) >= BACK_MIN_DR, (i, lr)
        tag = "DIP" if i in dip_pads else ("fwd" if fwd else "BACK")
        print("  %2d %-4s b=%7.2f r=%5.2f yaw=%7.2f -> land r=%5.2f b=%7.2f "
              "dr=%+5.2f arc clr %.2f" % (i, tag, p["b"], p["r"], p["yaw"] % 360.0,
                                          lr, lb, lr - p["r"], clr))
    print("  forward %d / backward %d -- a backward pad loops a bot round the"
          " ring, so zero is the only number" % (n_fwd, n_back))
    assert n_back == 0, n_back
    print("  last pad             b=%.2f; past there no FORWARD flight lands on the"
          " field, so no pad is laid" % max(q["b"] for q in pads))
    print("  worst arc clearance  %.3f m (pad %d) over take-off..apex, required %.2f"
          % (worst_arc[0], worst_arc[1], PAD_ARC_CLEAR))
    print("  same over the WHOLE flight, descent included: %.3f m (pad %d) -- reported,"
          % (worst_full[0], worst_full[1]))
    print("                       not asserted: the rule is 'before its descent'")
    assert n_fwd >= FWD_MIN, n_fwd

    # ---- 6. cover ----------------------------------------------------------
    print("\n[6] COVER  (eye (0, %.2f, 0), traced from the running game; crest"
          % GUARD_EYE_Y)
    print("    flanks must beat %.0f deg; shadow judged on the SAMPLED surface)"
          % COVER_FLANK_MIN)
    tops, lens, wids, rads, patw, patd = [], [], [], [], [], []
    for k, c in enumerate(covers):
        cx, cz = _plan(c["b"], c["r"])
        ux, uz = _dir(_cover_yaw(c["b"]))
        ax, az = -uz, ux
        # The flank is measured, not assumed -- but measured as a SECANT over
        # the descent, from 85% of the summit down to 15%. Segment-by-segment
        # sampling reads two false shallows on every ray: the step that
        # straddles the plateau edge holds part of a flat, and the step at the
        # footprint edge holds part of a neighbour's shoulder. Neither is a
        # flank. The secant spans the real drop and cannot see either.
        angles = []
        for dx, dz, reach in ((ux, uz, c["half_along"]), (-ux, -uz, c["half_along"]),
                              (ax, az, c["half_across"]), (-ax, -az, c["half_across"])):
            summit = H(cx, cz)
            hi = lo = None
            prev = summit
            s = 0.0
            while s < reach - 1e-9:
                s += 0.02
                cur = H(cx + dx * s, cz + dz * s)
                if cur > prev + 1e-9:
                    break                      # climbing a neighbour
                if hi is not None and prev - cur < 0.002:
                    break                      # the descent stalled: this crest's
                    # flank has ended and the flat beyond it belongs to whatever
                    # it is resting against, not to this piece
                if hi is None and cur <= 0.85 * summit:
                    hi = (s, cur)
                if hi is not None and cur >= 0.15 * summit:
                    lo = (s, cur)
                prev = cur
            # A ray whose height never gets down near the ground inside the
            # footprint has its flank BURIED against a neighbouring crest.
            # There is no exposed flank on that side to measure, and no
            # launched body could stand there either -- the neighbour's rock is
            # in the way. Such a ray is skipped, not read as a shallow ramp.
            if (hi is not None and lo is not None and lo[0] > hi[0] + 1e-9
                    and lo[1] <= 0.30 * summit):
                angles.append(math.degrees(math.atan2(hi[1] - lo[1], lo[0] - hi[0])))
        assert angles, ("every flank of crest %d is buried" % k)
        hide_h = H(*_plan(c["b"], c["hide_r"]))
        m_st = _sight_margin(c["r"], c["top"], c["hide_r"], hide_h, STAND_H)
        m_cr = _sight_margin(c["r"], c["top"], c["hide_r"], hide_h, CROUCH_H)
        m_old = _sight_margin(c["r"], c["top"], c["hide_r"], hide_h, STAND_H,
                              GUARD_EYE_Y_OLD)
        wide, deep = _pf_patch(c, cols, sta, H)
        print("  %2d b=%6.2f r=%5.2f %4.1fx%4.1f m  flank %.1f..%.1f  block st %+.3f"
              " cr %+.3f  shadow %.1f x %.1f m"
              % (k, c["b"], c["r"], 2 * c["half_along"], 2 * c["half_across"],
                 min(angles), max(angles), m_st, m_cr, wide, deep))
        assert min(angles) > COVER_FLANK_MIN, (k, min(angles))
        assert m_st >= SIGHT_MARGIN_MIN, (k, m_st)
        assert m_cr >= SIGHT_MARGIN_MIN, (k, m_cr)
        assert m_old >= m_st, (k, m_old, m_st)   # the old 27.0 eye is the easier case
        assert c["hide_r"] > c["r"], k
        tops.append(c["top"])
        lens.append(2 * c["half_along"])
        wids.append(2 * c["half_across"])
        rads.append(c["r"])
        patw.append(wide)
        patd.append(deep)
    gaps = [(covers[i + 1]["b"] - covers[i]["b"]) * math.pi * covers[i]["r"] / 180.0
            for i in range(len(covers) - 1)]
    print("  VARIATION            top %.2f..%.2f   length %.2f..%.2f   width %.2f..%.2f"
          % (min(tops), max(tops), min(lens), max(lens), min(wids), max(wids)))
    print("                       radius %.2f..%.2f   gap along the run %.2f..%.2f m"
          % (min(rads), max(rads), min(gaps), max(gaps)))
    print("  SHADOW               width %.1f..%.1f m, depth %.1f..%.1f m; bake grid %.2f m"
          % (min(patw), max(patw), min(patd), max(patd), BAKE_GRID))
    assert max(tops) - min(tops) > 0.05 and max(lens) - min(lens) > 0.8
    assert max(rads) - min(rads) > 1.0, "crests all sit at one radius"
    # WIDTH is the gate -- it is the axis the bake's grid has to straddle to
    # sample a crest's shadow at all. Depth is reported with its own, lower
    # floor: it is measured straight out from the crest, where a shadow is
    # naturally deep, and it has never been the number that fails.
    for k in range(len(covers)):
        assert patw[k] >= PATCH_MIN, (k, patw[k])
        assert patd[k] >= PATCH_DEPTH_MIN, (k, patd[k])

    # ---- 7. the surface welds ----------------------------------------------
    print("\n[7] SURFACE")
    for b in (142.9, 143.0 - 1e-9, 202.0 + 1e-9, 202.1, 120.0, 250.0):
        for r in (48.0, 52.0, 56.0):
            assert H(*_plan(b, r)) == 0.0, (b, r)
    for r in (46.699, 46.0, 57.301, 58.0, 30.0, 80.0):
        for b in (150.0, 172.0, 195.0):
            assert H(*_plan(b, r)) == 0.0, (b, r)
    print("  zero outside ext and outside r 46.7..57.3   exact 0.0 at 27 probes")
    # ON the edge, _plan's round trip can land a few float-eps INSIDE it, so the
    # smoothstep returns ~1e-19 rather than a hard zero. The brief asks for exact
    # 0.0 OUTSIDE, which is proven above; on the edge we show the magnitude.
    edge_v = [abs(H(*_plan(143.0, 52.0))), abs(H(*_plan(202.0, 52.0))),
              abs(H(*_plan(160.0, 46.7))), abs(H(*_plan(160.0, 57.3)))]
    print("  ON  ext and ON  r 46.7 / 57.3               |h| <= %.2e" % max(edge_v))
    assert max(edge_v) < 1e-12, edge_v

    lo_h = hi_h = 0.0
    b = 142.5
    while b <= 202.5:
        r = 46.5
        while r <= 57.5:
            v = H(*_plan(b, r))
            lo_h = min(lo_h, v)
            hi_h = max(hi_h, v)
            r += 0.05
        b += 0.05
    print("  extremes             %.4f .. %.4f m  (floor %.2f, crest top %.2f)"
          % (lo_h, hi_h, HEIGHT_FLOOR, COVER_TOP_MAX))
    assert lo_h >= HEIGHT_FLOOR, lo_h
    assert hi_h <= COVER_TOP_MAX + 1e-9, hi_h

    edge = max(abs(H(*_plan(143.0 + 1.5, r))) for r in (48.0, 52.0, 56.0))
    print("  ease-in at 1.5 deg   %.4f m  (rock is back by then)" % edge)

    # ---- 8. determinism ----------------------------------------------------
    # The repo compares .glb bytes between machines, so layout() must be
    # bit-identical every run. CPython randomises string hashing per process,
    # which is exactly the sort of thing that flips one quad's diagonal, so the
    # digest is taken again under two different PYTHONHASHSEEDs.
    print("\n[8] DETERMINISM")
    import hashlib
    import os
    import subprocess

    dig = _pf_digest(LAY)
    assert _pf_digest(layout()) == dig, "layout() differs between calls"
    here = hashlib.sha256(dig.encode()).hexdigest()[:32]
    print("  digest               %s" % here)
    print("  same object twice    layout() is layout(): %s" % (layout() is LAY))

    code = ("import s3_minefield as m, hashlib;"
            "print(hashlib.sha256(m._pf_digest(m.layout()).encode()).hexdigest()[:32])")
    for seed in ("0", "1"):
        env = dict(os.environ)
        env["PYTHONHASHSEED"] = seed
        got = subprocess.run([sys.executable, "-c", code], capture_output=True,
                             text=True, env=env,
                             cwd=os.path.dirname(os.path.abspath(__file__)))
        out = got.stdout.strip()
        print("  PYTHONHASHSEED=%s      %s  %s"
              % (seed, out, "match" if out == here else "MISMATCH"))
        assert out == here, (seed, out, here)
    print("  floats compared via float.hex(); cols, stations, every cover/pad/dip")
    print("  field, the corridor, and height on a fixed 200-point grid")

    print("\n" + "=" * 78)
    print("ALL CHECKS PASSED")
    print("=" * 78)
