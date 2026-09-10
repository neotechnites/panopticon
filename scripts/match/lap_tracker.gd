class_name MatchLapTracker
extends Node

## How far round the ring a body has got, and the tick it reaches the end.
##
## [b]Why this is not [RingRunner][/b]
##
## [RingRunner] already measures arc travelled, and it is the right measurement
## -- see its class docs for why a radius test against the end marker is useless
## on a 25 m wide deck. But it measures it in order to STEER, and it only exists
## on a bot. A match has a human in it, and in the opening race the human is
## running the same lap as the bots for the same prize. Scoring the human off a
## brain that would also drive them is not an option, and scoring the human by
## one rule and the bots by another turns the race into two separate tests that
## happen to run at the same time.
##
## So the scoring is lifted out here, onto a node that measures and never steers,
## and every participant gets one. Human and AI are judged by the same arc, the
## same tolerance and the same tick. A bot still runs on its own [RingRunner] --
## nothing here drives anything -- and that brain's own
## [signal RingRunner.reached_end] remains the brain's business: it is what stops
## the bot walking into the LapDivider. Only this node scores.
##
## [b]Arc, not distance[/b]
##
## Progress is the angle swept about the arena axis, accumulated tick by tick so
## it keeps counting past a wrap instead of jumping. That makes it independent of
## the radius the body chooses to run at, which matters because a lane is a spawn
## position rather than a rail: a human will cut to the inside kerb and must
## still have to cover the whole ring to score.

## Emitted once, on the tick the lap completes. Carries the same telemetry
## [signal RingRunner.reached_end] does, so a listener can be written against
## either.
signal lap_finished(elapsed_seconds: float, path_length: float)

## The body being watched. Assigned by [method begin]; exported so the tracker
## can also be authored into a scene.
@export var body: PlayerController

## Arena axis, at deck height.
var _centre: Vector3 = Vector3.ZERO

## Arc from the start angle to the finish angle in the direction of travel, in
## radians. About 350 degrees: start and finish straddle the LapDivider.
var _finish_arc: float = 0.0

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
	# accumulate the arc of a body being teleported onto its lane.
	set_physics_process(false)


## Start watching [param tracked] run from [param start_point] to
## [param end_point] about [param arena_centre].
##
## Only the ANGLES of the two points are used, exactly as
## [method RingRunner.configure] uses them, so a caller may hand over the ring's
## markers or a staggered start of its own devising. Call it after the body has
## been placed: the first tick differences against where it is now.
func begin(
	tracked: PlayerController,
	arena_centre: Vector3,
	start_point: Vector3,
	end_point: Vector3,
	arrival_tolerance: float,
) -> void:
	body = tracked
	_centre = arena_centre
	_arrival_tolerance = maxf(arrival_tolerance, 0.0)
	_travelled_arc = 0.0
	_elapsed_seconds = 0.0
	_path_length = 0.0
	_finished = false
	if body == null:
		_finish_arc = 0.0
		set_physics_process(false)
		return

	var start_angle: float = _angle_of(start_point)
	var end_angle: float = _angle_of(end_point)
	# wrapf into [0, TAU) picks the long way round whenever the short way is
	# behind us, which for these two markers is exactly the lap.
	_finish_arc = wrapf((end_angle - start_angle) * RingRunner.TRAVEL_SIGN, 0.0, TAU)

	# Anchor on the body where it actually is rather than on start_point: a
	# human placed on the pad settles a few centimetres, and an anchor taken
	# from the marker would book that settle as progress.
	_previous_angle = _angle_of(body.global_position)
	_previous_position = body.global_position
	set_physics_process(true)


## Stop counting and keep the numbers. What the shooter's tracker does, and what
## a converted runner's does.
func stop() -> void:
	set_physics_process(false)


## Take over [param source]'s lap: its arc, its clock and its path length.
##
## For the ghost swap, and only for it. A ghost that catches a living prisoner
## "takes their spot", and the spot includes the distance already run -- so the
## tracker that is about to start counting for the incoming prisoner is seeded
## with what the outgoing one had, instead of starting them at the pad.
##
## Call it AFTER [method begin], which anchors the accumulator on the body where
## it actually is: this writes the totals and leaves that anchor alone, so the
## next tick differences against the right position and the arc it adds is the
## incoming body's own.
##
## See [member GhostProfile.catch_transfers_progress] for what turning this off
## means, and why it is a rule rather than a constant.
func adopt_progress(source: MatchLapTracker) -> void:
	if source == null:
		return
	_travelled_arc = source._travelled_arc
	_elapsed_seconds = source._elapsed_seconds
	_path_length = source._path_length


func is_counting() -> bool:
	return is_physics_processing()


func has_finished() -> bool:
	return _finished


## Fraction of the lap covered, 0.0 at the start and 1.0 at the finish.
func get_progress() -> float:
	if _finish_arc <= 0.0:
		return 0.0
	return clampf(_travelled_arc / _finish_arc, 0.0, 1.0)


## Arc swept so far, in radians. The raw accumulator behind
## [method get_progress], handed over so a ghost swap can carry a lap from one
## body's tracker to another's and to the incoming body's [RingRunner], which
## keeps an accumulator of its own for steering.
func get_travelled_arc() -> float:
	return _travelled_arc


## Radians from the start angle to the finish angle, in the direction of travel:
## the lap this tracker is scoring, as [method begin] worked it out.
##
## Exposed so a test can ask what a runner is actually being judged against
## rather than assuming it. That stopped being obvious the moment the finish
## became per-lane -- under
## [constant MatchRules.LaneEqualisation.STAGGER_FINISH] each lane finishes at
## its own angle, and a tracker armed with the arena's marker instead of the
## lane's finish would score the outer lanes against a line they never reach.
func get_finish_arc() -> float:
	return _finish_arc


func get_elapsed_seconds() -> float:
	return _elapsed_seconds


func get_path_length() -> float:
	return _path_length


func _physics_process(delta: float) -> void:
	if body == null:
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
	_travelled_arc += wrapf((angle - _previous_angle) * RingRunner.TRAVEL_SIGN, -PI, PI)
	_previous_angle = angle

	var remaining_arc: float = _finish_arc - _travelled_arc
	# Tolerance is in metres, so it is converted at the radius the body is
	# ACTUALLY running, not the one it was spawned on. A runner who has cut to
	# the inside gets the same few centimetres of grace as one still out wide.
	var radius: float = maxf(
		Vector2(position.x - _centre.x, position.z - _centre.z).length(),
		1.0,
	)
	if remaining_arc * radius <= _arrival_tolerance:
		_finish()


func _finish() -> void:
	_finished = true
	set_physics_process(false)
	lap_finished.emit(_elapsed_seconds, _path_length)


## Angle of a world point about the arena axis, in radians.
func _angle_of(point: Vector3) -> float:
	return atan2(point.z - _centre.z, point.x - _centre.x)
