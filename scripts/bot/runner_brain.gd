class_name RunnerBrain
extends Node

## The prisoner's brain: RUN the mesh path to the portal, TAKE_COVER when the
## rifle is on you, CROSS a jump or pad link, RECOVER when stuck or fallen.
## Knows nothing about the map beyond what [RingBake] hands it.

## Emitted once when the runner has swept the whole lap.
signal reached_end(elapsed_seconds: float, path_length: float)
## Emitted on every change of behaviour state.
signal state_changed(previous: State, current: State)

## Direction of travel around the arena, as a sign on the angle about the centre.
const TRAVEL_SIGN: float = 1.0
const GATE_THROUGH_METRES: float = 2.5
const GATE_ARRIVAL_METRES: float = 1.5
const RAMP_ARRIVAL_METRES: float = 4.0
const CORNER_METRES: float = 1.0
const ALIGNED_RADIANS: float = 0.05
const MIN_THROTTLE: float = 0.3
const CORNER_TURN_RADIANS: float = 0.6
const CORNER_BRAKE_SECONDS: float = 0.45
const CORNER_THROTTLE: float = 0.35
const PLAN_PERIOD_TICKS: int = 30
const PLAN_RETRY_TICKS: int = 10
const CHASE_PLAN_PERIOD_TICKS: int = 10
const PATH_DRIFT_METRES: float = 3.0
const JUMP_APPROACH_METRES: float = 3.5
const PAD_APPROACH_METRES: float = 6.0
const JUMP_RUNUP_METRES: float = 2.5
const PAD_RUNUP_METRES: float = 5.0
const TAKEOFF_METRES: float = 0.2
const CHAIN_METRES: float = 1.5
const TAKEOFF_TIMEOUT_SECONDS: float = 2.0
const LAUNCH_WAIT_SECONDS: float = 3.0
const LAUNCH_SPACING_METRES: float = 5.0
const FLIGHT_TIMEOUT_SECONDS: float = 4.0
const FLIGHT_MIN_SECONDS: float = 0.08
const AIRBORNE_SPEED: float = 3.0
## A pad throws a body up faster than any jump; this is how a launch is told from a hop.
const PAD_LAUNCH_SPEED: float = 9.0
const STRAFE_SURPLUS: float = 0.3
const COVER_ARRIVAL_METRES: float = 0.8
const COVER_EXPOSED_SECONDS: float = 0.5
const COVER_RETRY_TICKS: int = 30
const STUCK_WINDOW_SECONDS: float = 2.0
const STUCK_DISTANCE_METRES: float = 1.0
const RECOVER_BURST_SECONDS: float = 1.0
const OFF_MESH_METRES: float = 0.6
const CHASE_SHOVE_SLACK_SECONDS: float = 0.1
## A shoved body flies about this far with no air control; it must come down on safe mesh.
const SHOVE_THROW_METRES: float = 12.0
const SHOVE_CLEARANCE_METRES: float = 2.0
const EDGE_CHECK_TICKS: int = 6

enum State { RUN, TAKE_COVER, CROSS, RECOVER }
enum Cross { LINE_UP, TAKEOFF, FLY }

## The body this brain drives; its intent_source must be [member input].
@export var controller: PlayerController
@export var input: BotIntentSource
@export var profile: BotProfile
## Difficulty and behaviour; a match overrides it through [member rules].
@export var runner_profile: RunnerProfile
@export var rules: MatchRules
## The seat this brain plays; its re-plan tick is phased by it. Set by [MatchController].
var seat_index: int = 0
## Seeds the perception guesses when non-zero; the harness sets it, the game leaves 0.
var perception_seed: int = 0

var _centre: Vector3 = Vector3.ZERO
var _route: RingRoute = null
var _level: int = 0
var _finish_arc: float = 0.0
var _travelled_arc: float = 0.0
var _previous_angle: float = 0.0
var _entry_angle: float = 0.0
var _end_point: Vector3 = Vector3.ZERO
var _previous_position: Vector3 = Vector3.ZERO
var _elapsed_seconds: float = 0.0
var _path_length: float = 0.0
var _reported_end: bool = false
var _through_gate: bool = false

var _play: RunnerProfile = null
var _perception: RunnerPerception = RunnerPerception.new()
var _bake: RingBake = null
var _path: RingPath = RingPath.new()
var _cover_path: RingPath = RingPath.new()
var _taken: PackedVector3Array = PackedVector3Array()
var _cover_tick: int = -COVER_RETRY_TICKS
var _edge_tick: int = -EDGE_CHECK_TICKS
var _near_edge: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _state: State = State.RUN
var _ticks: int = 0
var _plan_tick: int = -PLAN_PERIOD_TICKS
var _plan_failed_tick: int = -PLAN_PERIOD_TICKS
var _goal: Vector3 = Vector3.ZERO
var _has_path: bool = false

var _cover: Vector3 = Vector3.ZERO
var _cover_seconds: float = 0.0
var _cover_exposed: float = 0.0
var _dared: bool = false

var _link: RingBake.Link = null
var _cross: Cross = Cross.LINE_UP
var _cross_seconds: float = 0.0

var _stuck_seconds: float = 0.0
var _stuck_origin: Vector3 = Vector3.ZERO
var _recover_seconds: float = 0.0
var _recover_direction: Vector3 = Vector3.ZERO
var _recover_tries: int = 0

var _chasing: bool = false
var _chase_group: StringName = &""
var _shove_rest: float = 0.0

var _flights: int = 0
var _covers: int = 0


func _ready() -> void:
	if controller == null or input == null or profile == null:
		push_error("RunnerBrain needs a controller, an input and a profile; it will not run.")
	set_physics_process(false)


## Place the body at [param start_point], facing down the track, and start the lap.
func configure(arena_centre: Vector3, start_point: Vector3, end_point: Vector3, route: RingRoute = null) -> void:
	if controller == null or input == null or profile == null:
		return
	var start_angle: float = atan2(start_point.z - arena_centre.z, start_point.x - arena_centre.x)
	controller.global_position = start_point
	controller.velocity = Vector3.ZERO
	controller.rotation = Vector3(0.0, _heading_of(_tangent(start_angle)), 0.0)
	_arm(arena_centre, start_point, end_point, 0.0, start_angle, route, 0)


## Start running from where the body already stands, [param travelled_arc] into the lap.
func resume(
	arena_centre: Vector3, start_point: Vector3, end_point: Vector3, travelled_arc: float,
	route: RingRoute = null, level: int = 0,
) -> void:
	if controller == null or input == null or profile == null:
		return
	input.command.clear()
	var here: Vector3 = controller.global_position
	_arm(arena_centre, start_point, end_point, travelled_arc, atan2(here.z - arena_centre.z, here.x - arena_centre.x), route, level)


func _arm(
	arena_centre: Vector3, start_point: Vector3, end_point: Vector3, travelled_arc: float,
	anchor_angle: float, route: RingRoute, level: int,
) -> void:
	_centre = arena_centre
	_end_point = end_point
	if _route != null and _route.get_parent() == self:
		_route.queue_free()
	_route = route
	if _route == null:
		_route = RingRoute.flat(profile.track_radius, arena_centre, start_point, end_point)
		add_child(_route)
	_level = clampi(level, 0, _route.last_index())
	_finish_arc = _route.lap_arc(_level)
	_chasing = false
	_previous_angle = anchor_angle
	_entry_angle = anchor_angle - TRAVEL_SIGN * travelled_arc
	_previous_position = controller.global_position
	_travelled_arc = travelled_arc
	_elapsed_seconds = 0.0
	_path_length = 0.0
	_reported_end = false
	_through_gate = false

	_play = RunnerProfile.resolve(rules, runner_profile)
	if _play == null:
		_play = RunnerProfile.new()
	_perception.configure(controller, _play, rules, perception_seed)
	_rng = _play.make_rng(perception_seed)
	_bake = RingBake.ensure(RingBake.level_root_of(controller), controller.profile)
	_path.clear()
	_has_path = false
	_ticks = 0
	_plan_tick = -PLAN_PERIOD_TICKS
	_plan_failed_tick = -PLAN_RETRY_TICKS
	_cover_tick = -COVER_RETRY_TICKS
	_edge_tick = -EDGE_CHECK_TICKS
	_near_edge = true
	_link = null
	_flights = 0
	_covers = 0
	_dared = _rng.randf() < _play.boldness
	_state = State.RUN
	_reset_stuck()
	set_physics_process(true)


# --- The chase ----------------------------------------------------------------

## Stop running the ring and hunt the nearest living body ahead in [param target_group].
func begin_chase(target_group: StringName) -> void:
	if controller == null or input == null or profile == null:
		return
	_chase_group = target_group
	_chasing = true
	_shove_rest = 0.0
	_link = null
	_set_state(State.RUN)
	input.command.clear()
	_has_path = false
	_reset_stuck()
	set_physics_process(true)


## Stop chasing and drop the controls.
func end_chase() -> void:
	if not _chasing:
		return
	_chasing = false
	input.command.clear()
	set_physics_process(false)


func is_chasing() -> bool:
	return _chasing


## The body this ghost is closing on, or null.
func get_chase_target() -> Node3D:
	if not _chasing or controller == null:
		return null
	return _nearest_ahead()


## Where the chase is steering: the next corner of the mesh path to the quarry.
func get_chase_aim_point() -> Vector3:
	var quarry: Node3D = get_chase_target()
	if quarry == null:
		return controller.global_position if controller != null else Vector3.ZERO
	if _has_path and _path.cursor < _path.size():
		return _path.points[_path.cursor]
	return quarry.global_position


# --- Readouts -----------------------------------------------------------------

func get_elapsed_seconds() -> float:
	return _elapsed_seconds


func get_path_length() -> float:
	return _path_length


## Fraction of the whole route covered, weighted exactly as [MatchLapTracker] weights it.
func get_progress() -> float:
	if _route == null:
		return 0.0 if _finish_arc <= 0.0 else clampf(_travelled_arc / _finish_arc, 0.0, 1.0)
	return _route.progress(_level, _travelled_arc)


func get_level() -> int:
	return _level


func get_travelled_arc() -> float:
	return _travelled_arc


func get_route() -> RingRoute:
	return _route


func get_state() -> State:
	return _state


func get_state_name() -> String:
	return String(State.keys()[_state])


func get_play_profile() -> RunnerProfile:
	return _play


func get_perception() -> RunnerPerception:
	return _perception


func is_playing_cover() -> bool:
	return _play != null and _play.plays_cover()


## Jump and pad links flown.
func get_flights() -> int:
	return _flights


## Times cover was taken.
func get_covers() -> int:
	return _covers


func get_cover_seconds() -> float:
	return _cover_seconds


## The bake this runner paths on. Null until armed.
func get_navigation() -> RingBake:
	return _bake


# --- The loop -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_ticks += 1
	if _chasing:
		_tick_chase(delta)
		return

	var position: Vector3 = controller.global_position
	_elapsed_seconds += delta
	_path_length += Vector2(position.x - _previous_position.x, position.z - _previous_position.z).length()
	_previous_position = position
	var angle: float = _angle_of(position)
	_travelled_arc += wrapf((angle - _previous_angle) * TRAVEL_SIGN, -PI, PI)
	_previous_angle = angle

	if _route.has_level_above(_level):
		if _route.is_standing_on(_level + 1, position.y):
			_climb()
	elif (_finish_arc - _travelled_arc) * _route.lane_radius(_level) <= profile.arrival_tolerance:
		_finish()

	if is_playing_cover():
		_perception.tick(delta)
	if _bake != null and (_ticks + seat_index) % EDGE_CHECK_TICKS == 0:
		_near_edge = not _shove_lands_safely(position)
	input.shove_enabled = _state != State.CROSS and not _near_edge

	match _state:
		State.RUN:
			_tick_run(delta)
		State.TAKE_COVER:
			_tick_cover(delta)
		State.CROSS:
			_tick_cross(delta)
		State.RECOVER:
			_tick_recover(delta)


## Bank the level and start the next lap from where the body stands.
func _climb() -> void:
	_level = mini(_level + 1, _route.last_index())
	_finish_arc = _route.lap_arc(_level)
	_travelled_arc = 0.0
	_entry_angle = _previous_angle
	_has_path = false


## Report the lap once; the body keeps running through the gate until the match silences it.
func _finish() -> void:
	if _reported_end:
		return
	_reported_end = true
	reached_end.emit(_elapsed_seconds, _path_length)


## Where the run is heading: the ramp to the next level, or the finish, then through it.
func _run_goal() -> Vector3:
	var here: Vector3 = controller.global_position
	if _route.has_level_above(_level):
		if _flat_distance(here, _route.ramp_foot(_centre, _level)) <= RAMP_ARRIVAL_METRES:
			return _route.ramp_top(_centre, _level)
		return _route.ramp_foot(_centre, _level)
	if not _through_gate and _flat_distance(here, _end_point) <= GATE_ARRIVAL_METRES:
		_through_gate = true
	if _through_gate:
		return _end_point + _tangent(_angle_of(_end_point)) * GATE_THROUGH_METRES
	return _end_point


# --- RUN ----------------------------------------------------------------------

func _tick_run(delta: float) -> void:
	if _catch_pad_flight():
		return
	_goal = _run_goal()
	if _reported_end and _flat_distance(controller.global_position, _goal) <= CORNER_METRES:
		# Through the gate and at the end of the road: stand rather than push at whatever is next.
		input.command.move_direction = Vector2.ZERO
		return
	_keep_path(PLAN_PERIOD_TICKS)
	if _link_ahead():
		return
	if is_playing_cover() and _wants_cover() and _find_cover():
		return
	_follow(delta)
	_tick_stuck(delta)


## Re-plan when due, when there is no path, or when the body has strayed from it.
func _keep_path(period: int) -> void:
	if _bake == null or not _bake.is_ready():
		_has_path = false
		return
	var due: bool = _ticks - _plan_tick >= period and (_ticks + seat_index) % period == 0
	if _has_path and not due and not _strayed():
		return
	if not _has_path and _ticks - _plan_failed_tick < PLAN_RETRY_TICKS:
		return
	_plan_tick = _ticks
	_has_path = _bake.plan(controller.global_position, _bake.snap(_goal), _layers(), _path)
	_path.cursor = 0
	if _has_path:
		_advance_cursor()
	else:
		_plan_failed_tick = _ticks


## The links this runner will take: every pad, and jumps up to its confidence.
func _layers() -> int:
	var layers: int = RingBake.LAYER_WALK | RingBake.LAYER_PAD | RingBake.LAYER_EASY_JUMP
	if _play == null or _play.jump_confidence >= 0.5:
		layers |= RingBake.LAYER_HARD_JUMP
	return layers


func _strayed() -> bool:
	if _path.cursor >= _path.size():
		return true
	return _flat_distance(controller.global_position, _path.points[_path.cursor]) > PATH_DRIFT_METRES + CORNER_METRES * 4.0


## Move the cursor past every corner already reached or passed, stopping at a link start.
func _advance_cursor() -> void:
	var here: Vector3 = controller.global_position
	while _path.cursor < _path.size() - 1:
		var index: int = _path.cursor
		if _path.links[index] >= 0:
			return
		var corner: Vector3 = _path.points[index]
		var next: Vector3 = _path.points[index + 1]
		var reached: bool = _flat_distance(here, corner) <= CORNER_METRES
		var passed: bool = Vector2(here.x - corner.x, here.z - corner.z).dot(Vector2(next.x - corner.x, next.z - corner.z)) > 0.0 \
			and _flat_distance(here, corner) <= CORNER_METRES * 3.0
		if not reached and not passed:
			return
		_path.cursor += 1


## Steer at the next corner; without a path, at the mesh a few metres on round the lap.
func _follow(delta: float) -> void:
	var here: Vector3 = controller.global_position
	var target: Vector3 = here + _tangent(_angle_of(here)) * 5.0
	if _has_path:
		_advance_cursor()
		target = _path.points[_path.cursor]
	elif _bake != null and _bake.is_ready():
		target = _bake.snap(target)
	var error: float = _face(target, delta)
	var throttle: float = clampf(1.0 - absf(error) / (PI * 0.5), MIN_THROTTLE, 1.0)
	if _has_path and _path.cursor + 1 < _path.size():
		# Slow for a sharp corner the body could not turn at speed.
		var corner: Vector3 = _path.points[_path.cursor]
		var beyond: Vector3 = _path.points[_path.cursor + 1]
		var turn: float = Vector2(corner.x - here.x, corner.z - here.z).angle_to(Vector2(beyond.x - corner.x, beyond.z - corner.z))
		if absf(turn) > CORNER_TURN_RADIANS and _flat_distance(here, corner) < controller.get_horizontal_speed() * CORNER_BRAKE_SECONDS:
			throttle = minf(throttle, CORNER_THROTTLE)
	if absf(error) < ALIGNED_RADIANS:
		input.command.move_direction = Vector2(0.0, throttle)
		return
	_drive_towards(target, 0.0)
	input.command.move_direction *= throttle


## Begin a crossing when the path's next link start is within its approach distance.
func _link_ahead() -> bool:
	if not _has_path:
		return false
	var index: int = _path.next_link_from(_path.cursor)
	if index < 0:
		return false
	var link: RingBake.Link = _bake.get_link(_path.links[index])
	var approach: float = PAD_APPROACH_METRES if link.kind == RingBake.LinkKind.PAD else JUMP_APPROACH_METRES
	approach *= maxf(controller.get_horizontal_speed() / _wish_speed() * _speed_scale(), 1.0)
	var here: Vector3 = controller.global_position
	if _flat_distance(here, link.start) > approach:
		return false
	if _flat_distance(here, _path.points[_path.cursor]) + _path.metres_between(_path.cursor, index) > approach + CORNER_METRES:
		return false
	_begin_cross(link, Cross.LINE_UP)
	return true


## A pad the path never meant to use fired anyway: fly its link.
func _catch_pad_flight() -> bool:
	if controller.is_on_floor() or controller.velocity.y < AIRBORNE_SPEED or _bake == null:
		return false
	var link: RingBake.Link = _bake.pad_link_near(controller.global_position)
	if link == null:
		return false
	_begin_cross(link, Cross.FLY)
	return true


# --- TAKE_COVER ---------------------------------------------------------------

## True when a body shoved from [param here] the way this one faces would land on safe mesh.
func _shove_lands_safely(here: Vector3) -> bool:
	if not _bake.is_ready() or _bake.pad_link_near(here, PAD_APPROACH_METRES) != null:
		return false
	var forward: Vector3 = -controller.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return false
	forward = forward.normalized()
	var step: float = SHOVE_THROW_METRES / 4.0
	for index: int in range(1, 5):
		var point: Vector3 = here + forward * (step * float(index))
		var height: float = _bake.height_at(point)
		if is_nan(height) or _bake.is_lethal(Vector3(point.x, height, point.z), SHOVE_CLEARANCE_METRES):
			return false
		if _bake.boundary_distance(Vector3(point.x, height, point.z), SHOVE_CLEARANCE_METRES) < SHOVE_CLEARANCE_METRES:
			return false
	return true


## Shot at, or watched in the open by a runner that did not dare to keep going.
func _wants_cover() -> bool:
	if not _perception.has_threat():
		return false
	if _perception.was_shot_at():
		return true
	return _perception.is_exposed() and _perception.believes_watched() and not _dared


## Head for the nearest cover point ahead within reach; false when there is none.
func _find_cover() -> bool:
	if _bake == null or not _bake.is_ready() or _ticks - _cover_tick < COVER_RETRY_TICKS:
		return false
	_cover_tick = _ticks
	var here: Vector3 = controller.global_position
	var forward: Vector3 = _tangent(_angle_of(here))
	if _has_path and _path.cursor < _path.size():
		var corner: Vector3 = _path.points[_path.cursor]
		var ahead: Vector3 = Vector3(corner.x - here.x, 0.0, corner.z - here.z)
		if ahead.length() > 0.5:
			forward = ahead.normalized()
	_taken.clear()
	for node: Node in BotIntentSource._rivals(controller):
		var rival: Node3D = node as Node3D
		if rival != null and rival != controller and is_instance_valid(rival):
			_taken.append(rival.global_position)
	var index: int = _bake.nearest_cover_ahead(here, forward, _play.cover_reach_metres, _taken)
	if index < 0:
		return false
	_cover = _bake.cover_point(index)
	if not _bake.plan(here, _cover, _layers(), _cover_path) or _cover_path.next_link_from(0) >= 0:
		return false
	_goal = _cover
	_path.points = _cover_path.points
	_path.links = _cover_path.links
	_path.cursor = 0
	_has_path = true
	_plan_tick = _ticks
	_cover_seconds = 0.0
	_cover_exposed = 0.0
	_covers += 1
	_set_state(State.TAKE_COVER)
	return true


func _tick_cover(delta: float) -> void:
	var here: Vector3 = controller.global_position
	if _flat_distance(here, _cover) > COVER_ARRIVAL_METRES:
		_goal = _cover
		_keep_path(PLAN_PERIOD_TICKS)
		_follow(delta)
		_tick_stuck(delta)
		_cover_seconds += delta
		if _cover_seconds > _play.cover_patience_seconds * 2.0:
			_leave_cover()
		return
	input.command.move_direction = Vector2.ZERO
	_face(_perception.get_threat_eye(), delta)
	_cover_seconds += delta
	_cover_exposed = _cover_exposed + delta if _perception.is_exposed() else 0.0
	if _cover_exposed >= COVER_EXPOSED_SECONDS or not _perception.has_threat():
		_leave_cover()
		return
	if _cover_seconds < _play.hold_min_seconds:
		return
	var window: bool = _perception.get_believed_reload_remaining() > 0.0 or not _perception.believes_watched()
	if window or _cover_seconds >= _play.cover_patience_seconds:
		_leave_cover()


func _leave_cover() -> void:
	_dared = _rng.randf() < _play.boldness
	_has_path = false
	_set_state(State.RUN)


# --- CROSS --------------------------------------------------------------------

func _begin_cross(link: RingBake.Link, phase: Cross) -> void:
	_link = link
	_cross = phase
	_cross_seconds = 0.0
	if phase == Cross.FLY:
		_flights += 1
	_set_state(State.CROSS)


func _tick_cross(delta: float) -> void:
	_cross_seconds += delta
	# A pad fired under the body, whatever it was doing: fly that pad's link.
	if controller.velocity.y > PAD_LAUNCH_SPEED and not controller.is_on_floor():
		var fired: RingBake.Link = _bake.pad_link_near(controller.global_position)
		if fired != null and (fired != _link or _cross != Cross.FLY):
			_begin_cross(fired, Cross.FLY)
	match _cross:
		Cross.LINE_UP:
			_tick_line_up(delta)
		Cross.TAKEOFF:
			_tick_takeoff(delta)
		Cross.FLY:
			_tick_fly(delta)


## Get behind the take-off on the link's own axis, then walk it straight in.
func _tick_line_up(delta: float) -> void:
	var here: Vector3 = controller.global_position
	var along: float = Vector3(here.x - _link.start.x, 0.0, here.z - _link.start.z).dot(_link.direction)
	var runup: float = PAD_RUNUP_METRES if _link.kind == RingBake.LinkKind.PAD else JUMP_RUNUP_METRES
	var staged: Vector3 = _link.start - _link.direction * runup
	if _flat_distance(_bake.snap(staged), staged) > OFF_MESH_METRES:
		staged = _link.start
	var past_staging: bool = Vector3(here.x - staged.x, 0.0, here.z - staged.z).dot(_link.direction) > -0.3
	if along > -runup * 0.5 or past_staging or _flat_distance(here, staged) < CORNER_METRES * 1.5:
		_cross = Cross.TAKEOFF
		_cross_seconds = 0.0
		_tick_takeoff(delta)
		return
	_face(staged, delta)
	_drive_towards(staged, 0.0)
	if _link.kind == RingBake.LinkKind.JUMP:
		input.command.move_direction *= clampf(_link.speed / _wish_speed(), MIN_THROTTLE, 1.0)
	_tick_stuck(delta)
	if _cross_seconds > TAKEOFF_TIMEOUT_SECONDS * 2.0:
		_abort_cross()


## Run straight through the take-off at the link's speed; a jump presses on the edge.
## Waits its turn: not while shoved, not while a rival is on the plate or the landing.
func _tick_takeoff(delta: float) -> void:
	var here: Vector3 = controller.global_position
	var along: float = Vector3(here.x - _link.start.x, 0.0, here.z - _link.start.z).dot(_link.direction)
	var aim: Vector3 = _link.start + _link.direction * 4.0
	_face(aim, delta)
	if along < -TAKEOFF_METRES and _cross_seconds < LAUNCH_WAIT_SECONDS \
		and (controller.get_air_lock_remaining() > 0.0 or not _clear_to_launch()):
		input.command.move_direction = Vector2.ZERO
		return
	_drive_towards(aim, 0.0)
	if _link.kind == RingBake.LinkKind.PAD:
		if not controller.is_on_floor() and controller.velocity.y > AIRBORNE_SPEED:
			_cross = Cross.FLY
			_cross_seconds = 0.0
			_flights += 1
		elif _cross_seconds > TAKEOFF_TIMEOUT_SECONDS + LAUNCH_WAIT_SECONDS:
			_abort_cross()
		return
	var wish: float = clampf(_link.speed / _wish_speed(), MIN_THROTTLE, 1.0)
	input.command.move_direction *= wish
	if along >= -TAKEOFF_METRES and controller.is_on_floor():
		input.command.jump_pressed = true
		_cross = Cross.FLY
		_cross_seconds = 0.0
		_flights += 1
	elif _cross_seconds > TAKEOFF_TIMEOUT_SECONDS + LAUNCH_WAIT_SECONDS:
		_abort_cross()


## In the air: hold the wish that puts the body down on the link's end.
func _tick_fly(delta: float) -> void:
	var here: Vector3 = controller.global_position
	var end: Vector3 = _link.end
	_face(end, delta)
	if controller.is_on_floor() and _cross_seconds > FLIGHT_MIN_SECONDS:
		_land()
		return
	if _cross_seconds > FLIGHT_TIMEOUT_SECONDS:
		_abort_cross()
		return
	var g: float = controller.profile.get_effective_gravity() if controller.profile != null else 22.0
	var vy: float = controller.velocity.y
	var under: float = vy * vy - 2.0 * g * (end.y - here.y)
	var remaining: float = (vy + sqrt(under)) / g if under > 0.0 else maxf(vy / g, 0.0)
	var current: Vector3 = Vector3(controller.velocity.x, 0.0, controller.velocity.z)
	if remaining < FLIGHT_MIN_SECONDS:
		# Touching down: hold the line rather than brake on a vanishing clock.
		_drive_towards(here + current * 5.0, 0.0)
		return
	var desired: Vector3 = Vector3(end.x - here.x, 0.0, end.z - here.z) / remaining
	var error: Vector3 = desired - current
	var wish_speed: float = _wish_speed()
	if desired.length() > wish_speed + STRAFE_SURPLUS and desired.length() > current.length() + STRAFE_SURPLUS and current.length() > 1.0:
		# More speed than holding forward gives: strafe, on the side that also turns toward the landing.
		var side: Vector3 = Vector3(-current.z, 0.0, current.x).normalized()
		if side.dot(desired) < 0.0:
			side = -side
		_drive_towards(here + side * 5.0, 0.0)
		return
	if error.length() < 0.05:
		input.command.move_direction = Vector2.ZERO
		return
	var direction: Vector3 = error.normalized()
	var air_accel: float = controller.profile.air_acceleration if controller.profile != null else 12.0
	var stick: float = maxf(error.length() / maxf(air_accel * wish_speed * delta, 0.001), desired.dot(direction) / wish_speed)
	_drive_towards(here + direction * 5.0, 0.0)
	input.command.move_direction *= clampf(stick, 0.05, 1.0)


## Landed: step the path past the link, and chain straight into the next one if it starts here.
func _land() -> void:
	var landed: RingBake.Link = _link
	_link = null
	if _has_path:
		for index: int in range(_path.cursor, _path.size() - 1):
			var link_index: int = _path.links[index]
			if link_index >= 0 and _bake.get_link(link_index) == landed:
				_path.cursor = mini(index + 1, _path.size() - 1)
				break
		var next: int = _path.next_link_from(_path.cursor)
		if next >= 0:
			var link: RingBake.Link = _bake.get_link(_path.links[next])
			if _flat_distance(controller.global_position, link.start) <= CHAIN_METRES + JUMP_RUNUP_METRES:
				_begin_cross(link, Cross.LINE_UP)
				return
	_has_path = false
	_set_state(State.RUN)


func _abort_cross() -> void:
	_link = null
	_has_path = false
	_begin_recover()


func _speed_scale() -> float:
	return maxf(controller.speed_scale * controller.run_speed_scale, 0.1)


## False while another body is on the link ahead: on the plate, in the air, or on the landing.
func _clear_to_launch() -> bool:
	var start: Vector3 = _link.start
	var reach: float = _flat_distance(start, _link.end) + LAUNCH_SPACING_METRES
	for node: Node in BotIntentSource._rivals(controller):
		var rival: PlayerController = node as PlayerController
		if rival == null or rival == controller or not is_instance_valid(rival):
			continue
		var offset: Vector3 = rival.global_position - start
		offset.y = 0.0
		var ahead: float = offset.dot(_link.direction)
		var aside: float = (offset - _link.direction * ahead).length()
		if aside >= LAUNCH_SPACING_METRES * 0.5 or ahead <= -LAUNCH_SPACING_METRES * 0.5:
			continue
		if ahead < LAUNCH_SPACING_METRES * 0.5 or (not rival.is_on_floor() and ahead < reach):
			return false
	return true


## The speed a full stick asks for, with the match's multipliers on it.
func _wish_speed() -> float:
	var base: float = controller.profile.ground_speed if controller.profile != null else 11.0
	return maxf(base * controller.speed_scale * controller.run_speed_scale, 0.1)


# --- RECOVER ------------------------------------------------------------------

func _begin_recover() -> void:
	_recover_seconds = 0.0
	var blocked: Vector3 = -controller.get_wall_normal() if controller.is_on_wall() else -controller.global_transform.basis.z
	blocked.y = 0.0
	blocked = blocked.normalized() if blocked.length_squared() > 0.0001 else Vector3.FORWARD
	var side: Vector3 = Vector3(-blocked.z, 0.0, blocked.x)
	_recover_direction = side if _recover_tries % 2 == 0 else -side
	if _recover_tries % 4 == 3:
		_recover_direction = -blocked
	_recover_tries += 1
	_has_path = false
	_set_state(State.RECOVER)


## Off the mesh: walk back onto it. Wedged: burst sideways, then re-path.
func _tick_recover(delta: float) -> void:
	_recover_seconds += delta
	var here: Vector3 = controller.global_position
	if _bake == null or not _bake.is_ready():
		_set_state(State.RUN)
		return
	var on_mesh: Vector3 = _bake.snap(here)
	if _flat_distance(here, on_mesh) > OFF_MESH_METRES or absf(on_mesh.y - here.y) > 1.5:
		_face(on_mesh, delta)
		_drive_towards(on_mesh, 0.0)
		if controller.is_on_floor() and controller.is_on_wall() and _recover_seconds > 0.5:
			input.command.jump_pressed = true
			_recover_seconds = 0.0
		return
	if _recover_seconds < RECOVER_BURST_SECONDS and controller.is_on_wall() \
		and not _bake.is_lethal(here + _recover_direction * 2.0, 1.0):
		_drive_towards(here + _recover_direction * 5.0, 0.0)
		if controller.is_on_floor():
			input.command.jump_pressed = true
		return
	_reset_stuck()
	_set_state(State.RUN)


func _reset_stuck() -> void:
	_stuck_seconds = 0.0
	if controller != null:
		_stuck_origin = controller.global_position


## Asking to move and not moving for two seconds is stuck.
func _tick_stuck(delta: float) -> void:
	if input.command.move_direction == Vector2.ZERO or not controller.is_on_floor():
		_reset_stuck()
		return
	_stuck_seconds += delta
	if _stuck_seconds < STUCK_WINDOW_SECONDS:
		return
	var moved: float = _flat_distance(controller.global_position, _stuck_origin)
	_reset_stuck()
	if moved < STUCK_DISTANCE_METRES:
		_link = null
		_begin_recover()
	else:
		_recover_tries = 0


# --- The chase ----------------------------------------------------------------

## Path to the living prisoner the least route ahead, never turning round.
func _tick_chase(delta: float) -> void:
	if _state == State.CROSS:
		_tick_cross(delta)
		return
	if _state == State.RECOVER:
		_tick_recover(delta)
		return
	if _catch_pad_flight():
		return
	var quarry: Node3D = _nearest_ahead()
	if quarry == null:
		input.command.move_direction = Vector2.ZERO
		return
	_goal = quarry.global_position
	_keep_path(CHASE_PLAN_PERIOD_TICKS)
	if _link_ahead():
		return
	_follow(delta)
	_maybe_shove(quarry, delta)
	_tick_stuck(delta)


## Tap shove once the quarry is in the match's reach and in front of this ghost.
func _maybe_shove(quarry: Node3D, delta: float) -> void:
	_shove_rest = maxf(_shove_rest - delta, 0.0)
	if rules == null or _shove_rest > 0.0:
		return
	var offset: Vector3 = quarry.global_position - controller.global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > rules.shove_range_metres or distance < 1e-3:
		return
	var forward: Vector3 = -controller.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 1e-6:
		return
	if forward.normalized().dot(offset / distance) < MatchController.SHOVE_FACING_DOT:
		return
	input.command.shove_pressed = true
	_shove_rest = rules.shove_cooldown_seconds + CHASE_SHOVE_SLACK_SECONDS


## The living prisoner the least route AHEAD of this ghost, or null.
func _nearest_ahead() -> Node3D:
	if _chase_group == StringName(""):
		return null
	var here: Vector3 = controller.global_position
	var here_metres: float = _route_metres_of(here)
	var route_length: float = 0.0 if _route == null else _route.total_metres()
	var best: Node3D = null
	var best_cost: float = 0.0
	for node: Node in controller.get_tree().get_nodes_in_group(_chase_group):
		var body: Node3D = node as Node3D
		if body == null or body == controller:
			continue
		var cost: float = _route_metres_of(body.global_position) - here_metres
		if cost < 0.0:
			cost += route_length
		if best == null or cost < best_cost:
			best = body
			best_cost = cost
	return best


func _route_metres_of(point: Vector3) -> float:
	if _route == null:
		return 0.0
	var level: int = _route.level_for_height(point.y)
	var swept: float = wrapf((_angle_of(point) - _route.entry_angle(level)) * TRAVEL_SIGN, 0.0, TAU)
	return _route.metres_travelled(level, swept)


# --- Driving the body ---------------------------------------------------------

## Turn towards [param point] at this tick's allowed rate; returns the signed heading error.
func _face(point: Vector3, delta: float) -> float:
	var to_target: Vector3 = point - controller.global_position
	var forward: Vector3 = -controller.global_transform.basis.z
	var error: float = Vector2(forward.x, forward.z).angle_to(Vector2(to_target.x, to_target.z))
	input.aim(clampf(error * profile.steering_gain, -profile.max_yaw_rate, profile.max_yaw_rate), 0.0, delta)
	return error


## Walk towards [param point] whatever the body faces; move_direction is body-local.
func _drive_towards(point: Vector3, deadzone: float) -> void:
	var to_target: Vector3 = point - controller.global_position
	var flat: Vector2 = Vector2(to_target.x, to_target.z)
	if flat.length() <= deadzone:
		input.command.move_direction = Vector2.ZERO
		return
	flat = _along_the_wall(flat)
	var basis: Basis = controller.global_transform.basis
	var right: Vector2 = Vector2(basis.x.x, basis.x.z)
	var forward: Vector2 = Vector2(-basis.z.x, -basis.z.z)
	input.command.move_direction = Vector2(flat.dot(right), flat.dot(forward)).normalized()


## [param wish] with the part of it that pushes into a wall taken out.
func _along_the_wall(wish: Vector2) -> Vector2:
	if not controller.is_on_wall():
		return wish
	var normal: Vector3 = controller.get_wall_normal()
	var flat: Vector2 = Vector2(normal.x, normal.z)
	if flat.length() < 0.001:
		return wish
	flat = flat.normalized()
	var into: float = wish.dot(flat)
	if into >= 0.0:
		return wish
	var along: Vector2 = wish - flat * into
	return wish if along.length() < 0.001 else along


func _set_state(next: State) -> void:
	if next == _state:
		return
	var previous: State = _state
	_state = next
	_reset_stuck()
	state_changed.emit(previous, _state)


# --- Ring geometry -------------------------------------------------------------

func _angle_of(point: Vector3) -> float:
	return atan2(point.z - _centre.z, point.x - _centre.x)


func _tangent(angle: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, cos(angle)) * TRAVEL_SIGN


func _heading_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()
