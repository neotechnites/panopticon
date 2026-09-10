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

## How hard the runner is trying. This is a mode rather than a speed in m/s
## because the actual speeds live in [MovementProfile] -- the bot must not get
## its own private top speed, or bot telemetry would stop describing the game
## humans play.
enum SpeedMode {
	WALK, ## Sprint released. 8 m/s on the tuned profile.
	SPRINT, ## Sprint held. 11 m/s on the tuned profile.
}

# --- The lane ------------------------------------------------------------------

## Distance from the arena centre that the runner tries to hold for the whole
## lap.
##
## The deck is an annulus from r=35 to r=60 and cover sits in three radial lanes
## centred on r=41, r=47.5 and r=54. Each piece is 6 m tangential by 1.5 m
## radial, so its corners sweep a band of roughly +/-0.9 m about its lane: the
## occupied bands are ~[40.4, 41.9], ~[46.8, 48.3] and ~[53.3, 54.8]. This
## runner does not use cover and does not path around it, so a lane radius
## inside one of those bands walks a 0.4 m capsule straight into a wall and
## stops there for the rest of the round.
##
## The default sits in the clear channel between the inner and middle cover
## lanes. The other honest choices are ~38.5 (inboard of everything, outboard of
## the 0.5 m kerb at r=36) and ~51.0 (between middle and outer). Three runners
## at 38.5 / 44.5 / 51.0 are 6.5 m apart, which is far wider than the 0.8 m
## capsule, so they never touch.
@export_range(36.0, 60.0, 0.1) var lane_radius: float = 44.5

## Walk or sprint. The only speed knob, on purpose: everything else about pace
## is [MovementProfile]'s business.
@export var speed_mode: SpeedMode = SpeedMode.WALK

# --- Steering ------------------------------------------------------------------

## Proportional gain on the heading error, in radians per second of yaw rate per
## radian of error.
##
## The runner is a plain P controller with no damping term, so this is the whole
## of its steering intelligence. Too low and it drifts outward on the curve
## because it can never turn as fast as the lane does; too high and it hunts
## about the lane, which shows up as a longer measured path for the same lap.
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

## How far along the lane, in metres of arc, the runner aims ahead of itself.
##
## Aiming at the point it is standing on would leave nothing to steer towards;
## aiming too far ahead cuts the corner and pulls the runner inboard of its own
## lane, straight into the cover band this profile was chosen to avoid. Roughly
## half a second of travel is the usual sweet spot for a pure-pursuit steerer,
## and 4 m is half a second at walk speed.
@export_range(0.5, 30.0, 0.1) var lookahead_distance: float = 4.0

# --- Finishing -----------------------------------------------------------------

## How much arc, in metres, may still be outstanding and still count as having
## reached the end.
##
## Deliberately generous. The finish is judged on arc travelled rather than on
## distance to the [code]PrisonerEnd[/code] marker, because that marker sits at
## r=47.5 and a runner holding r=38.5 passes it 9 m away -- a distance test
## would never fire, and the runner would keep going into the 4 m LapDivider
## wall at 0 degrees and grind there forever. See [RingRunner].
@export_range(0.1, 10.0, 0.1) var arrival_tolerance: float = 1.5


## True when the runner should hold sprint. Keeps the enum comparison in one
## place so callers never grow their own idea of what SPRINT means.
func wants_sprint() -> bool:
	return speed_mode == SpeedMode.SPRINT
