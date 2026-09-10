class_name RingLevel
extends Node3D

## One deck of a [RingRoute]: where it is, how wide it is, and the arc a
## prisoner owes on it.
##
## [b]Data, authored on the map.[/b] Nothing here is computed and nothing here
## steers. The arena scene says what its levels are and
## [code]tools/modelling/gen_bentham_ring.py[/code] emits these values from the
## same table it cuts the geometry from, so the deck a runner is standing on and
## the deck they are being scored against cannot drift apart. A second map with
## one flat lap authors one of these -- or none at all, and
## [method MatchController] builds it from [member MatchRules.track_radius].
##
## [b]Angles are degrees here and radians everywhere else.[/b] Degrees because
## this is the face a human authors against and a scene file full of 6.0039
## radians is unreadable; [RingRoute] converts once, at the boundary, and no
## caller ever sees a degree.

## World Y of the walking surface. The route's level ordering is this value
## ascending, and it is what [method RingRoute.level_for_height] resolves a body
## against.
@export var deck_height: float = 0.0

## Inner edge of the deck annulus, in metres from the arena axis.
##
## It is not decoration: the levels of a route are required to be disjoint bands
## with each level's inner radius at or outboard of the one below's outer radius,
## because that is the property that makes a central tower able to see every
## level. See [RingRoute].
@export var inner_radius: float = 35.0

## Outer edge of the deck annulus.
@export var outer_radius: float = 60.0

## The circle the runner brain steers, and the radius a metre of progress on
## this level is worth. Traps, pits and cover are all placed clear of
## [code]lane_radius[/code] plus or minus the clear channel; see the Traps node
## of the arena for why an avoidance-free bot makes that a hard requirement.
@export var lane_radius: float = 44.5

## Where a lap of this level starts, in degrees about the arena axis. On the
## first level it is the start line; on every other it is where the ramp from
## below lands.
@export var entry_angle_degrees: float = 4.8

## Where a lap of this level ends. On the last level it is the finish -- the end
## of the whole route. On every other it is the foot of the ramp up.
@export var exit_angle_degrees: float = 348.8

## Radius of the foot of the ramp that leaves this level, at
## [member exit_angle_degrees]. Zero on the last level, which has no ramp.
@export var ramp_foot_radius: float = 0.0

## Radius at which that ramp lands on the level above, at the level above's
## [member entry_angle_degrees]. Zero on the last level.
@export var ramp_landing_radius: float = 0.0


## True when this level names a ramp up off it.
func has_ramp() -> bool:
	return ramp_foot_radius > 0.0 and ramp_landing_radius > 0.0


## Everything wrong with this level, in words, or an empty array. Mirrors
## [method MatchRules.validate] and [method MapDefinition.validate]: the tests
## and the harness ask, nothing asserts.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if inner_radius <= 0.0:
		problems.append("%s has inner_radius %.1f; there is no deck." % [name, inner_radius])
	if outer_radius <= inner_radius:
		problems.append(
			"%s spans r%.1f to r%.1f, which is inside out." % [name, inner_radius, outer_radius]
		)
	if lane_radius < inner_radius or lane_radius > outer_radius:
		problems.append(
			"%s puts its lane at r%.1f, off its own deck (r%.1f-r%.1f)."
			% [name, lane_radius, inner_radius, outer_radius]
		)
	if is_equal_approx(entry_angle_degrees, exit_angle_degrees):
		problems.append("%s starts and finishes at the same angle; the lap is empty." % name)
	return problems
