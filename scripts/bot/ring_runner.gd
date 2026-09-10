class_name RingRunner
extends Node

## The dumbest possible prisoner: walks one counter-clockwise lap of the ring at
## a fixed radius and stops.
##
## [b]Why it is this dumb[/b]
##
## It is a baseline, not an opponent. Every later bot -- one that uses cover, one
## that reacts to being shot at, one that varies its pace -- has to be measured
## against something, and the only honest something is a runner that does
## nothing at all. If this one starts making decisions, the baseline moves and
## no comparison means anything. So: no cover, no threat awareness, no
## pathfinding, no navmesh. Steer at the next point on a circle and walk.
##
## [b]Why it drives a PlayerController[/b]
##
## This node never drives motion itself: it never calls [code]move_and_slide[/code]
## and owns no movement numbers. It writes [member CharacterBody3D.velocity] only in
## [method configure], to clear inherited motion when placing the body at spawn. It writes a
## [MoveIntent] into a [BotIntentSource] and the same [PlayerController] that
## carries a human carries it -- same Quake acceleration, same friction, same
## floor snap, same everything. A bot with its own movement code would be
## measuring a system no player ever touches, which would make every bot match
## this project ever runs worthless as evidence. This is the hard rule of the
## file.
##
## [b]Why the finish is judged on arc, not on distance to the marker[/b]
##
## [code]PrisonerEnd[/code] is a single point at r=47.5. Runners are spread
## across the 25 m deck so they do not overlap, and one holding r=38.5 sweeps
## past that marker 9 m away. A radius test against the marker would simply
## never fire for it; the runner would walk on into the 4 m LapDivider wall at
## 0 degrees and grind against it until the harness timed out. Arc travelled is
## the only finish condition that means the same thing in every lane.

## Emitted once, on the tick the lap is complete. Carries the runner's own
## telemetry because it is already integrating both for the steering and it
## costs nothing to hand them over.
##
## What finishing [i]means[/i] -- a score, a door opening, a round ending -- is
## deliberately not decided here. This node reports; something else rules.
signal reached_end(elapsed_seconds: float, path_length: float)

## Direction of travel around the arena, as a sign on the angle
## [code]atan2(z - centre.z, x - centre.x)[/code].
##
## This is arena canon rather than a tunable, which is why it is a constant and
## not a [BotProfile] field: the ring is run counter-clockwise, from
## PrisonerStart at +5 degrees round to PrisonerEnd at -5 degrees, and the cover
## pieces are numbered 42, 68, 96 ... 330 degrees in that order. It cannot be
## derived from the two markers, because they are only 10 degrees apart and the
## short way between them is the way the LapDivider blocks.
const TRAVEL_SIGN: float = 1.0

## The body this brain drives. Its [member PlayerController.intent_source] must
## be [member input], or the intent written here goes nowhere.
@export var controller: PlayerController

## The seam through which intent reaches [member controller].
@export var input: BotIntentSource

## Tunables. Without one the runner refuses to run rather than inventing a lane.
@export var profile: BotProfile

## The round's design parameters, when a match supplies them.
##
## Only the pace is read: [member MatchRules.bot_speed_mode] overrides
## [member BotProfile.speed_mode]. That is the seam -- "walk or sprint" is a rule
## of the round and every prisoner in a match obeys the same one, whereas gain,
## yaw ceiling, lookahead and arrival tolerance are tuning of this one brain and
## stay in [member profile].
##
## Null is normal and means "no match opinion": the profile's own speed mode is
## used, which is what a runner dropped into a test scene sees.
## [MatchController] assigns this at spawn.
@export var rules: MatchRules

## Arena centre, at deck height. Set by [method configure].
var _centre: Vector3 = Vector3.ZERO

## Arc from the start angle to the end angle in the travel direction, in
## radians. About 350 degrees, not 360: start and end straddle the LapDivider.
var _finish_arc: float = 0.0

## Arc covered so far, in radians, accumulated tick by tick so that it keeps
## counting past a full turn instead of wrapping back to zero.
var _travelled_arc: float = 0.0

## Last tick's wrapped angle, the term the accumulator differences against.
var _previous_angle: float = 0.0

## Last tick's position, for the path-length integral.
var _previous_position: Vector3 = Vector3.ZERO

var _elapsed_seconds: float = 0.0
var _path_length: float = 0.0


func _ready() -> void:
	# Fail loudly and stand still. A half-configured bot that wanders is far
	# harder to diagnose than one that never moves.
	if controller == null or input == null or profile == null:
		push_error("RingRunner needs a controller, an input and a profile; it will not run.")
		set_physics_process(false)
		return

	# Nothing to do until configure() has placed the body on its lane.
	set_physics_process(false)


## Place the runner on its lane and start it.
##
## [param arena_centre] is the ring's axis at deck height; [param start_point]
## and [param end_point] are the world positions of the PrisonerStart and
## PrisonerEnd markers. Only their angles about the centre are used -- the
## radius comes from [member BotProfile.lane_radius], which is what lets several
## runners share one pair of markers without overlapping.
##
## Call it after the runner is in the scene tree: it writes
## [member Node3D.global_position].
func configure(arena_centre: Vector3, start_point: Vector3, end_point: Vector3) -> void:
	if controller == null or input == null or profile == null:
		return

	_centre = arena_centre
	var start_angle: float = _angle_of(start_point)
	var end_angle: float = _angle_of(end_point)

	# wrapf into [0, TAU) picks the long way round whenever the short way is
	# behind us, which for these two markers is exactly the lap.
	_finish_arc = wrapf((end_angle - start_angle) * TRAVEL_SIGN, 0.0, TAU)

	controller.global_position = _point_on_lane(start_angle)
	controller.velocity = Vector3.ZERO
	# Face straight down the lane. A runner spawned facing the wall would spend
	# its first second turning around, and that second would land in the lap
	# time as if it were running.
	controller.rotation = Vector3(0.0, _heading_of(_lane_tangent(start_angle)), 0.0)

	_previous_angle = start_angle
	_previous_position = controller.global_position
	_travelled_arc = 0.0
	_elapsed_seconds = 0.0
	_path_length = 0.0
	set_physics_process(true)


## Seconds since [method configure], frozen once the lap ends.
func get_elapsed_seconds() -> float:
	return _elapsed_seconds


## Metres actually walked, measured in the horizontal plane. Compare it against
## the lane circumference to see how much the steering cost.
func get_path_length() -> float:
	return _path_length


## Fraction of the lap covered, 0.0 at the start pad and 1.0 at the end pad.
func get_progress() -> float:
	if _finish_arc <= 0.0:
		return 0.0
	return clampf(_travelled_arc / _finish_arc, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	var position: Vector3 = controller.global_position

	_elapsed_seconds += delta
	# Horizontal only: a step down onto the deck is not progress round the ring.
	_path_length += Vector2(
		position.x - _previous_position.x,
		position.z - _previous_position.z,
	).length()
	_previous_position = position

	# Difference of wrapped angles, re-wrapped to the shortest step. At 11 m/s
	# and r>=36 a physics tick turns at most ~0.005 rad, so this can never
	# mistake a step forward for a step back.
	var angle: float = _angle_of(position)
	_travelled_arc += wrapf((angle - _previous_angle) * TRAVEL_SIGN, -PI, PI)
	_previous_angle = angle

	var remaining_arc: float = _finish_arc - _travelled_arc
	if remaining_arc * profile.lane_radius <= profile.arrival_tolerance:
		_finish()
		return

	_steer(remaining_arc, delta)


# --- Steering ------------------------------------------------------------------

## Pure pursuit of a point further along the same circle.
##
## The body's wish direction is local-space and the controller yaws the whole
## body, so there is only one way for a bot to go somewhere: turn until it is
## pointing there, and hold forward. That is also how a human plays -- mouse to
## aim, W to move -- which is the point.
func _steer(remaining_arc: float, delta: float) -> void:
	# Never aim past the finish, or the last few metres are run at an angle.
	var lookahead_arc: float = minf(
		profile.lookahead_distance / profile.lane_radius,
		remaining_arc,
	)
	var target: Vector3 = _point_on_lane(_previous_angle + TRAVEL_SIGN * lookahead_arc)
	var to_target: Vector3 = target - controller.global_position

	# Signed heading error in the horizontal plane: positive means the target is
	# off to the runner's right.
	var forward: Vector3 = -controller.global_transform.basis.z
	var error: float = Vector2(forward.x, forward.z).angle_to(
		Vector2(to_target.x, to_target.z)
	)

	# aim() takes RADIANS PER SECOND and does the per-tick scaling itself.
	# Writing MoveIntent.look_delta here instead would need the value
	# pre-multiplied by delta, and getting that wrong does not raise an error --
	# the yaw aliases past a whole turn every tick and the movement quietly
	# loses speed, which reads as a physics bug and has cost this project time
	# once already. Positive yaw_rate turns right, and positive error means the
	# target is to the right, so the sign passes straight through.
	input.aim(
		clampf(error * profile.steering_gain, -profile.max_yaw_rate, profile.max_yaw_rate),
		0.0,
		delta,
	)

	# Full forward, every tick, unconditionally. Throttling on heading error
	# would be a second control loop and would make lap time a function of
	# steering quality rather than of speed and distance, which is the one thing
	# this baseline exists to report cleanly.
	input.command.move_direction = Vector2(0.0, 1.0)
	input.command.sprint_held = wants_sprint()


## Whether to hold sprint this tick: the match's rule when there is one, the
## profile's mode otherwise. One place, so no caller grows its own idea of it.
func wants_sprint() -> bool:
	if rules != null:
		return rules.wants_sprint()
	return profile.wants_sprint()


func _finish() -> void:
	set_physics_process(false)
	# Release the controls rather than freeze the body: friction brings it to a
	# stop over a metre or so, exactly as letting go of the keys would, and it
	# leaves the LapDivider 4 m ahead untouched.
	input.command.clear()
	reached_end.emit(_elapsed_seconds, _path_length)


# --- Ring geometry -------------------------------------------------------------

## Angle of a world point about the arena axis, in radians.
func _angle_of(point: Vector3) -> float:
	return atan2(point.z - _centre.z, point.x - _centre.x)


## The point on this runner's lane at the given angle, at deck height.
func _point_on_lane(angle: float) -> Vector3:
	return _centre + Vector3(cos(angle), 0.0, sin(angle)) * profile.lane_radius


## Unit tangent to the lane at the given angle, pointing the way the lap runs.
func _lane_tangent(angle: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, cos(angle)) * TRAVEL_SIGN


## Body yaw, in radians, that points the controller's forward axis along
## [param direction]. Forward is -Z, hence the double negation.
func _heading_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
