class_name MatchLapTracker
extends Node

## How far along the route a body has got, and the tick it reaches the end.
##
## [b]Why this is not [RingRunner][/b]
##
## [RingRunner] already measures arc travelled, and it is the right measurement
## -- see its class docs for why a radius test against the end marker is useless
## on a 25 m wide deck. But it measures it in order to STEER, and it only exists
## on a bot. A match has a human in it, and in the opening race the human is
## running the same route as the bots for the same prize. Scoring the human off a
## brain that would also drive them is not an option, and scoring the human by
## one rule and the bots by another turns the race into two separate tests that
## happen to run at the same time.
##
## So the scoring is lifted out here, onto a node that measures and never steers,
## and every participant gets one. Human and AI are judged by the same route, the
## same tolerance and the same tick. A bot still runs on its own [RingRunner] --
## nothing here drives anything -- and that brain's own
## [signal RingRunner.reached_end] remains the brain's business. Only this node
## scores.
##
## [b]Arc and level, not distance[/b]
##
## Progress within a level is the angle swept about the arena axis, accumulated
## tick by tick so it keeps counting past a wrap instead of jumping. That makes
## it independent of the radius the body chooses to run at, which matters because
## a deck is where the bodies are put down rather than a rail: a human will cut
## to the inside kerb and must still have to cover the whole ring to score.
##
## Arc alone stopped being an answer when the arena grew a second deck at the
## same angles five and a half metres up. What is scored now is the [RingRoute]:
## the metres banked for every level already finished, plus this level's arc
## taken at this level's lane radius. See [RingRoute] for why that measurement
## and not another, and for why a level is banked on the arc AND the height
## rather than on either alone.

## Emitted once, on the tick the route is completed. Carries the same telemetry
## [signal RingRunner.reached_end] does, so a listener can be written against
## either.
signal lap_finished(elapsed_seconds: float, path_length: float)

## Emitted on the tick a level is banked and the next one begins. Telemetry
## only: nothing in the match is required to listen, and the round does not
## change shape when a prisoner climbs.
signal level_reached(level: int)

## The body being watched. Assigned by [method begin]; exported so the tracker
## can also be authored into a scene.
@export var body: PlayerController

## Arena axis, at level one's deck height.
var _centre: Vector3 = Vector3.ZERO

## The route being run. Never null once [method begin] has been called with one;
## a caller with a flat map hands over [method RingRoute.flat].
var _route: RingRoute = null

## Which level of the route the body is being scored on. Only ever goes up, and
## only when both of [method RingRoute]'s tests pass.
var _level: int = 0

## Arc swept on THIS level so far, in radians.
var _travelled_arc: float = 0.0

var _previous_angle: float = 0.0
var _previous_position: Vector3 = Vector3.ZERO
var _elapsed_seconds: float = 0.0
var _path_length: float = 0.0

## Metres of arc from the finish that count as having arrived.
var _arrival_tolerance: float = 1.5

var _finished: bool = false


func _ready() -> void:
	# Dormant until begin(). A tracker that started counting on _ready would
	# accumulate the arc of a body being teleported onto the start line.
	set_physics_process(false)


## Start watching [param tracked] run [param route] from [param start_point]
## about [param arena_centre].
##
## Only the ANGLE of [param start_point] is used, exactly as
## [method RingRunner.configure] uses it, so a caller may hand over the ring's
## marker or a staggered start of its own devising. Call it after the body has
## been placed: the first tick differences against where it is now.
func begin(
	tracked: PlayerController,
	arena_centre: Vector3,
	route: RingRoute,
	arrival_tolerance: float,
) -> void:
	body = tracked
	_centre = arena_centre
	_route = route
	_arrival_tolerance = maxf(arrival_tolerance, 0.0)
	_level = 0
	_travelled_arc = 0.0
	_elapsed_seconds = 0.0
	_path_length = 0.0
	_finished = false
	if body == null or _route == null or _route.level_count() <= 0:
		set_physics_process(false)
		return

	# Anchor on the body where it actually is rather than on the marker: a
	# human placed on the pad settles a few centimetres, and an anchor taken
	# from the marker would book that settle as progress.
	_previous_angle = _angle_of(body.global_position)
	_previous_position = body.global_position
	set_physics_process(true)


## Stop counting and keep the numbers. What the shooter's tracker does, and what
## a converted runner's does.
func stop() -> void:
	set_physics_process(false)


## Take over [param source]'s run: its level, its arc, its clock and its path
## length.
##
## For the ghost swap, and only for it. A ghost that catches a living prisoner
## "takes their spot", and the spot includes the distance already run -- so the
## tracker that is about to start counting for the incoming prisoner is seeded
## with what the outgoing one had, instead of starting them at the pad.
##
## The LEVEL is part of the spot and is carried too. Carrying the arc without it
## would put a prisoner caught on the top deck back to the bottom lap with a
## top-deck arc against it, which is neither where they are nor what they owe.
##
## Call it AFTER [method begin], which anchors the accumulator on the body where
## it actually is: this writes the totals and leaves that anchor alone, so the
## next tick differences against the right position and the arc it adds is the
## incoming body's own.
func adopt_progress(source: MatchLapTracker) -> void:
	if source == null:
		return
	_level = source._level
	_travelled_arc = source._travelled_arc
	_elapsed_seconds = source._elapsed_seconds
	_path_length = source._path_length


func is_counting() -> bool:
	return is_physics_processing()


func has_finished() -> bool:
	return _finished


## The route being scored. Null until [method begin].
func get_route() -> RingRoute:
	return _route


## Which level the body is on, 0 for the first.
func get_level() -> int:
	return _level


## Fraction of the WHOLE ROUTE covered, 0.0 at the start and 1.0 at the finish.
func get_progress() -> float:
	if _route == null:
		return 0.0
	return _route.progress(_level, _travelled_arc)


## Arc swept on the current level so far, in radians. The raw accumulator behind
## [method get_progress], handed over so a ghost swap can carry a run from one
## body's tracker to another's and to the incoming body's [RingRunner], which
## keeps an accumulator of its own for steering.
func get_travelled_arc() -> float:
	return _travelled_arc


## Radians from the current level's entry to its exit: the lap this tracker is
## scoring right now, as the route defines it.
##
## Exposed so a test can ask what a runner is actually being judged against
## rather than recomputing the arc from the markers and asserting against its
## own arithmetic.
func get_finish_arc() -> float:
	return 0.0 if _route == null else _route.lap_arc(_level)


## Metres of the route still to run, across every level left. What the HUD
## counts down, and the one number that means the same thing on every deck.
func get_metres_remaining() -> float:
	return 0.0 if _route == null else _route.metres_remaining(_level, _travelled_arc)


func get_elapsed_seconds() -> float:
	return _elapsed_seconds


func get_path_length() -> float:
	return _path_length


func _physics_process(delta: float) -> void:
	if body == null or _route == null:
		set_physics_process(false)
		return

	var position: Vector3 = body.global_position
	_elapsed_seconds += delta
	_path_length += Vector2(
		position.x - _previous_position.x,
		position.z - _previous_position.z,
	).length()
	_previous_position = position

	# Difference of wrapped angles, re-wrapped to the shortest step, so the
	# accumulator cannot mistake a step across the +/-PI seam for a lap.
	var angle: float = _angle_of(position)
	_travelled_arc += wrapf((angle - _previous_angle) * RingRoute.TRAVEL_SIGN, -PI, PI)
	_previous_angle = angle

	var lap_arc: float = _route.lap_arc(_level)
	var remaining_arc: float = lap_arc - _travelled_arc
	# Tolerance is in metres, so it is converted at the radius the body is
	# ACTUALLY running, not the one it was spawned on. A runner who has cut to
	# the inside gets the same few centimetres of grace as one still out wide.
	var radius: float = maxf(
		Vector2(position.x - _centre.x, position.z - _centre.z).length(),
		1.0,
	)
	var swept: bool = remaining_arc * radius <= _arrival_tolerance

	if _route.has_level_above(_level):
		# Both tests, and in this order because the arc is the cheap one. See
		# RingRoute: the arc alone would bank a level nobody ran, and the height
		# alone would bank two.
		if swept and _route.is_standing_on(_level + 1, position.y):
			_bank_a_level(angle)
		return

	if swept:
		_finish()


## Close the current level and open the next one.
##
## The arc accumulator is reset rather than carried, and the anchor is re-taken
## from where the body actually is -- which, having just come off a ramp, is the
## next level's entry angle. Carrying the overshoot a climb accumulates would
## credit the ramp's own arc twice, once as the tail of the lap below and once
## as the head of the lap above.
func _bank_a_level(angle: float) -> void:
	_level += 1
	_travelled_arc = 0.0
	_previous_angle = angle
	level_reached.emit(_level)


func _finish() -> void:
	_finished = true
	set_physics_process(false)
	lap_finished.emit(_elapsed_seconds, _path_length)


## Angle of a world point about the arena axis, in radians.
func _angle_of(point: Vector3) -> float:
	return atan2(point.z - _centre.z, point.x - _centre.x)
