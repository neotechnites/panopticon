class_name BotProfile
extends Resource

## Every tunable number a [RingRunner] uses.
##
## Same doctrine as [MovementProfile]: nothing about how the bot behaves may be
## hard-coded in the brain, because the project answers design questions by
## sweeping variants of a resource in headless matches. A constant buried in
## [RingRunner] is a constant that can never be swept, and "how fast does a
## runner cross the open ground at r=51" is exactly the kind of question this
## game needs to be able to ask a hundred times with different numbers.
##
## Units are metres, seconds and radians unless a field name says otherwise.

# --- The track -----------------------------------------------------------------

## Distance from the arena centre that the runner steers back to and tries to
## hold for the whole lap.
##
## Every prisoner runs this same circle -- a match writes
## [member MatchRules.track_radius] here on every placement -- so this is not
## "which of them is this one", it is where the track is.
##
## The deck is an annulus from r=35 to r=60 and cover sits in three radial bands
## centred on r=41, r=47.5 and r=54. Each piece is 6 m tangential by 1.5 m
## radial, so its corners sweep roughly +/-0.9 m about its band: the occupied
## bands are ~[40.4, 41.9], ~[46.8, 48.3] and ~[53.3, 54.8]. This runner does not
## use cover and does not path around it, so a track radius inside one of those
## bands walks a 0.4 m capsule straight into a box and stops there for the rest
## of the round.
##
## The default sits in the clear channel between the inner and middle cover
## bands. The other honest choices are ~38.5 (inboard of everything, outboard of
## the 0.5 m kerb at r=36) and ~51.0 (between middle and outer).
@export_range(36.0, 60.0, 0.1) var track_radius: float = 44.5

# --- Steering ------------------------------------------------------------------

## Proportional gain on the heading error, in radians per second of yaw rate per
## radian of error.
##
## The runner is a plain P controller with no damping term, so this is the whole
## of its steering intelligence. Too low and it drifts outward on the curve
## because it can never turn as fast as the track does; too high and it hunts
## about the track, which shows up as a longer measured path for the same lap.
## At the default a 0.1 rad error is corrected in about a sixth of a second,
## which is well inside the 4 m lookahead.
@export_range(0.1, 30.0, 0.1) var steering_gain: float = 6.0

## Ceiling on the yaw rate the bot will ask for, in radians per second.
##
## Exists so that a large error -- being spun by a collision, or a deliberately
## bad spawn heading -- produces a turn a human hand could plausibly make rather
## than an instant snap. It is also what keeps [member steering_gain] safe to
## raise during a sweep.
@export_range(0.1, 20.0, 0.1) var max_yaw_rate: float = 4.0

## How far along the track, in metres of arc, the runner aims ahead of itself.
##
## Aiming at the point it is standing on would leave nothing to steer towards;
## aiming too far ahead cuts the corner and pulls the runner inboard of the
## track, straight into the cover band this radius was chosen to avoid. Roughly
## half a second of travel is the usual sweet spot for a pure-pursuit steerer,
## and 4 m is half a second at walk speed.
@export_range(0.5, 30.0, 0.1) var lookahead_distance: float = 4.0

# --- Finishing -----------------------------------------------------------------

## How much arc, in metres, may still be outstanding and still count as having
## reached the end.
##
## Deliberately generous. The finish is judged on arc travelled rather than on
## distance to the [code]PrisonerEnd[/code] marker, because that marker sits at
## r=47.5 and a runner holding r=44.5 passes it 3 m away -- a distance test
## would fire late or not at all, and a runner that missed it would keep going
## into the 4 m LapDivider wall at 0 degrees and grind there forever. See
## [RingRunner].
@export_range(0.1, 10.0, 0.1) var arrival_tolerance: float = 1.5

