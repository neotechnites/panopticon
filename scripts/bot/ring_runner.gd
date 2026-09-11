class_name RingRunner
extends Node

## The prisoner's brain. Runs one lap along lane waypoints over a baked navmesh
## ([RingNavigation]) and plays the cover game against the tower on the same mesh.

## Emitted once when the runner has swept the whole lap.
signal reached_end(elapsed_seconds: float, path_length: float)

## Emitted on every change of behaviour state.
signal state_changed(previous: State, current: State)

## Direction of travel around the arena, as a sign on the angle about the centre.
const TRAVEL_SIGN: float = 1.0
const SETTLED_SPEED: float = 0.35
const EVALUATE_SEARCH_SECONDS: float = 0.35
const HOLD_DEADZONE: float = 0.6
const RAMP_ARRIVAL_METRES: float = 4.0
## Lane waypoints are laid every this many degrees from start to finish.
const WAYPOINT_STEP_DEGREES: float = 15.0
const WAYPOINT_ARRIVAL_METRES: float = 2.5
const FINISH_OVERSHOOT_DEGREES: float = 4.0
## Metres past the finish gate the last waypoint sits, so the body passes clean through it.
const GATE_THROUGH_METRES: float = 1.5
## The gate waypoint is only passed by getting this close to it: a 4 m gate cannot be cut round.
const GATE_ARRIVAL_METRES: float = 1.0
const FINISH_GATE_GROUP: StringName = &"finish_gate"
const PATH_POINT_METRES: float = 1.0
const PATH_MAX_DRIFT_METRES: float = 3.0
## A waypoint whose path is this many times longer than the straight line is skipped.
const PATH_DETOUR_FACTOR: float = 3.0
const STUCK_WINDOW_SECONDS: float = 2.0
const STUCK_DISTANCE_METRES: float = 1.0
const STUCK_FAILURES_TO_SKIP: int = 2
const CHASE_LOOKAHEAD_METRES: float = 10.0
## A path counts as straight when no point on it leaves the chord by more than this.
const STRAIGHT_PATH_METRES: float = 0.5
## Heading error under which the body holds plain forward; above it, it strafes and throttles.
const ALIGNED_RADIANS: float = 0.05
const MIN_THROTTLE: float = 0.3
const JUMP_LOOK_METRES: float = 6.0
const UNSTICK_LOOK_METRES: float = 3.0

## What the runner is doing.
enum State {
	RUNNING,
	HOLD,
	EVALUATE,
	CROSS,
	RECOVER,
}

## The body this brain drives; its intent_source must be [member input].
@export var controller: PlayerController
@export var input: BotIntentSource
@export var profile: BotProfile
## Difficulty and behaviour; a match overrides it through [member rules].
@export var runner_profile: RunnerProfile
@export var rules: MatchRules

var _centre: Vector3 = Vector3.ZERO
var _has_geometry: bool = false
var _route: RingRoute = null
var _level: int = 0
var _finish_arc: float = 0.0
var _travelled_arc: float = 0.0
var _previous_angle: float = 0.0
var _entry_angle: float = 0.0
var _previous_position: Vector3 = Vector3.ZERO
var _elapsed_seconds: float = 0.0
var _path_length: float = 0.0

var _play: RunnerProfile = null
var _perception: RunnerPerception = RunnerPerception.new()
var _cover: RunnerCoverFinder = RunnerCoverFinder.new()
var _hazards: Array[Dictionary] = []

var _nav: RingNavigation = null
var _agent: NavigationAgent3D = null
var _agent_target: Vector3 = Vector3.ZERO
var _agent_raw_target: Vector3 = Vector3.ZERO
var _has_agent_target: bool = false
## Whether the agent target was snapped to a ready mesh; a target set earlier is re-aimed once it is.
var _agent_target_snapped: bool = false
## The waypoint index whose detour check has been done against a ready mesh.
var _wp_checked: int = -1

## Lane waypoints for the current level, with the arc each sits at; ramp points carry INF.
var _waypoints: PackedVector3Array = PackedVector3Array()
var _waypoint_arcs: PackedFloat32Array = PackedFloat32Array()
var _ramp_from: int = -1
var _gate_wp: int = -1
var _wp: int = 0
var _reported_end: bool = false
## Arc at which this level's lap is done: the finish gate's, or the exit's, from the entry.
var _end_arc: float = 0.0

var _state: State = State.RUNNING
var _chasing: bool = false
var _chase_group: StringName = &""
var _had_threat: bool = false

var _anchor: Vector3 = Vector3.ZERO
var _has_anchor: bool = false
var _anchor_is_cover: bool = false
var _hold_seconds: float = 0.0
var _cross_seconds: float = 0.0
var _cross_budget: float = 0.0
var _cross_wants_slide: bool = false
var _cross_slid: bool = false
var _cross_slide_held: bool = false
var _cross_slide_open: bool = false
var _cross_slide_seconds: float = 0.0
var _jump_cooldown: float = 0.0
var _blocked_seconds: float = 0.0
var _search_countdown: float = 0.0

var _target: Vector3 = Vector3.ZERO
var _target_is_cover: bool = false
var _target_path: PackedVector3Array = PackedVector3Array()
var _has_target: bool = false
var _exposed_metres: float = 0.0
var _last_confidence: float = 0.0
var _last_threshold: float = 0.0

var _stuck_seconds: float = 0.0
var _stuck_origin: Vector3 = Vector3.ZERO
var _stuck_failures: int = 0

var _crossings: int = 0
var _crossings_to_cover: int = 0
var _crossings_believed_safe: int = 0
var _seconds_in_cover: float = 0.0
var _seconds_exposed: float = 0.0
var _slides_attempted: int = 0
var _jumps: int = 0


func _ready() -> void:
	if controller == null or input == null or profile == null:
		push_error("RingRunner needs a controller, an input and a profile; it will not run.")
	set_physics_process(false)


## Place the body at [param start_point], facing down the track, and start the lap.
func configure(
	arena_centre: Vector3,
	start_point: Vector3,
	end_point: Vector3,
	route: RingRoute = null,
) -> void:
	if controller == null or input == null or profile == null:
		return
	var start_angle: float = _angle_of_about(arena_centre, start_point)
	controller.global_position = start_point
	controller.velocity = Vector3.ZERO
	controller.rotation = Vector3(0.0, _heading_of(_track_tangent(start_angle)), 0.0)
	_arm(arena_centre, start_point, end_point, 0.0, start_angle, route, 0)


## Start running from where the body already stands, [param travelled_arc] into the lap.
func resume(
	arena_centre: Vector3,
	start_point: Vector3,
	end_point: Vector3,
	travelled_arc: float,
	route: RingRoute = null,
	level: int = 0,
) -> void:
	if controller == null or input == null or profile == null:
		return
	input.command.clear()
	_arm(
		arena_centre,
		start_point,
		end_point,
		travelled_arc,
		_angle_of_about(arena_centre, controller.global_position),
		route,
		level,
	)


func _arm(
	arena_centre: Vector3,
	start_point: Vector3,
	end_point: Vector3,
	travelled_arc: float,
	anchor_angle: float,
	route: RingRoute,
	level: int,
) -> void:
	_centre = arena_centre
	_has_geometry = true

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

	_play = RunnerProfile.resolve(rules, runner_profile)
	_perception.configure(controller, _play, rules)
	_hazards = RunnerCoverFinder.collect_hazards(controller.get_tree().root)

	_nav = RingNavigation.ensure(
		RingNavigation.level_root_of(controller), _bake_bounds(), _route, _centre
	)
	_ensure_agent()
	_has_agent_target = false
	_build_waypoints()

	_state = State.RUNNING
	_had_threat = false
	_has_anchor = false
	_anchor_is_cover = false
	_anchor = Vector3.ZERO
	_hold_seconds = 0.0
	_cross_seconds = 0.0
	_cross_budget = 0.0
	_cross_wants_slide = false
	_cross_slid = false
	_cross_slide_held = false
	_cross_slide_open = false
	_cross_slide_seconds = 0.0
	_search_countdown = 0.0
	_target = Vector3.ZERO
	_target_is_cover = false
	_target_path = PackedVector3Array()
	_has_target = false
	_exposed_metres = 0.0
	_last_confidence = 0.0
	_last_threshold = 0.0
	_crossings = 0
	_crossings_to_cover = 0
	_crossings_believed_safe = 0
	_seconds_in_cover = 0.0
	_seconds_exposed = 0.0
	_slides_attempted = 0
	_jumps = 0
	_jump_cooldown = 0.0
	_blocked_seconds = 0.0
	_reported_end = false
	_reset_stuck()

	set_physics_process(true)


## World-space box around every deck of the route, so the bake skips the pit and the tower.
func _bake_bounds() -> AABB:
	if _route == null:
		return AABB()
	var low: float = INF
	var high: float = -INF
	var reach: float = 0.0
	for level: RingLevel in _route.get_levels():
		low = minf(low, level.deck_height)
		high = maxf(high, level.deck_height)
		reach = maxf(reach, maxf(level.outer_radius, level.lane_radius))
	reach += 6.0
	return AABB(
		Vector3(_centre.x - reach, low - 3.0, _centre.z - reach),
		Vector3(2.0 * reach, high - low + 9.0, 2.0 * reach),
	)


func _ensure_agent() -> void:
	if _agent != null:
		return
	_agent = NavigationAgent3D.new()
	_agent.name = "NavAgent"
	_agent.avoidance_enabled = false
	_agent.radius = RingNavigation.AGENT_RADIUS
	_agent.height = RingNavigation.AGENT_HEIGHT
	_agent.path_desired_distance = PATH_POINT_METRES
	_agent.target_desired_distance = PATH_POINT_METRES
	_agent.path_max_distance = PATH_MAX_DRIFT_METRES
	controller.add_child(_agent)


## Lane points every [constant WAYPOINT_STEP_DEGREES] to the finish, then the ramp if there is one.
func _build_waypoints() -> void:
	_waypoints = PackedVector3Array()
	_waypoint_arcs = PackedFloat32Array()
	_ramp_from = -1
	_gate_wp = -1
	_end_arc = _finish_arc
	var step: float = deg_to_rad(WAYPOINT_STEP_DEGREES)
	var arc: float = step
	while arc < _finish_arc - step * 0.5:
		_waypoints.append(_point_on_track(_entry_angle + TRAVEL_SIGN * arc))
		_waypoint_arcs.append(arc)
		arc += step
	if _route.has_level_above(_level):
		_waypoints.append(_point_on_track(_entry_angle + TRAVEL_SIGN * _finish_arc))
		_waypoint_arcs.append(_finish_arc)
		_ramp_from = _waypoints.size()
		_waypoints.append(_route.ramp_foot(_centre, _level))
		_waypoint_arcs.append(INF)
		_waypoints.append(_route.ramp_top(_centre, _level))
		_waypoint_arcs.append(INF)
	else:
		var last_arc: float = _finish_arc + deg_to_rad(FINISH_OVERSHOOT_DEGREES)
		var radius: float = _lane_radius()
		var gate: Node3D = _finish_gate()
		if gate != null:
			var gate_arc: float = wrapf(
				(_angle_of(gate.global_position) - _entry_angle) * TRAVEL_SIGN, 0.0, TAU
			)
			if gate_arc >= _finish_arc - step and gate_arc <= _finish_arc + PI * 0.5:
				radius = maxf(_radius_of(gate.global_position), 1.0)
				_gate_wp = _waypoints.size()
				_waypoints.append(_point_on_level(_entry_angle + TRAVEL_SIGN * gate_arc, radius))
				_waypoint_arcs.append(gate_arc)
				last_arc = gate_arc + GATE_THROUGH_METRES / radius
		_waypoints.append(_point_on_level(_entry_angle + TRAVEL_SIGN * last_arc, radius))
		_waypoint_arcs.append(last_arc)
		_end_arc = last_arc
	_wp = 0
	_wp_checked = -1
	_advance_waypoints()


## The Area3D the lap tracker scores on, or null when the map has none.
func _finish_gate() -> Node3D:
	var gates: Array[Node] = controller.get_tree().get_nodes_in_group(FINISH_GATE_GROUP)
	return gates[0] as Node3D if not gates.is_empty() else null


# --- The chase ----------------------------------------------------------------

## Stop running the ring and hunt the nearest living body ahead in [param target_group].
func begin_chase(target_group: StringName) -> void:
	if controller == null or input == null or profile == null:
		return
	_chase_group = target_group
	_chasing = true
	_state = State.RUNNING
	input.command.clear()
	_has_agent_target = false
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


## Where the chase is steering: a point down the ring ahead, or the quarry itself once close.
func get_chase_aim_point() -> Vector3:
	var quarry: Node3D = get_chase_target()
	if quarry == null:
		return controller.global_position if controller != null else Vector3.ZERO
	return _chase_aim_point(quarry.global_position)


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


func get_crossings() -> int:
	return _crossings


func get_crossings_to_cover() -> int:
	return _crossings_to_cover


func get_crossings_believed_safe() -> int:
	return _crossings_believed_safe


func get_seconds_in_cover() -> float:
	return _seconds_in_cover


func get_seconds_exposed() -> float:
	return _seconds_exposed


func get_slides_attempted() -> int:
	return _slides_attempted


func get_jumps() -> int:
	return _jumps


func get_last_break_confidence() -> float:
	return _last_confidence


func get_last_break_threshold() -> float:
	return _last_threshold


func get_last_exposed_metres() -> float:
	return _exposed_metres


## The navmesh this runner paths on. Null until armed.
func get_navigation() -> RingNavigation:
	return _nav


# --- The loop -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _chasing:
		_tick_chase(delta)
		return

	var position: Vector3 = controller.global_position
	_elapsed_seconds += delta
	_path_length += Vector2(
		position.x - _previous_position.x,
		position.z - _previous_position.z,
	).length()
	_previous_position = position

	var angle: float = _angle_of(position)
	_travelled_arc += wrapf((angle - _previous_angle) * TRAVEL_SIGN, -PI, PI)
	_previous_angle = angle

	var remaining_arc: float = _finish_arc - _travelled_arc
	var swept: bool = (_end_arc - _travelled_arc) * _lane_radius() <= profile.arrival_tolerance

	if _route.has_level_above(_level):
		if _route.is_standing_on(_level + 1, position.y):
			_climb_to_the_next_level()
			return
	elif swept:
		_finish()
		return

	_advance_waypoints()
	var climbing: bool = _ramp_from >= 0 and _wp >= _ramp_from

	if climbing or not is_playing_cover():
		_run_route(delta)
		_tick_stuck(delta)
		if is_playing_cover():
			_maybe_jump(delta)
		return

	_perception.tick(delta)
	if not _perception.has_threat():
		if _had_threat:
			_had_threat = false
			_has_anchor = false
			_set_state(State.RUNNING)
		_run_route(delta)
		_tick_stuck(delta)
		_maybe_jump(delta)
		return

	if not _had_threat:
		_had_threat = true
		_has_anchor = false
		_set_state(State.RECOVER)

	if _perception.is_exposed():
		_seconds_exposed += delta
	else:
		_seconds_in_cover += delta

	match _state:
		State.RECOVER:
			_tick_recover(remaining_arc, delta)
		State.HOLD:
			_tick_hold(remaining_arc, delta)
		State.EVALUATE:
			_tick_evaluate(remaining_arc, delta)
		State.CROSS:
			_tick_cross(delta)
		_:
			_set_state(State.RECOVER)
			_tick_recover(remaining_arc, delta)

	_maybe_jump(delta)


## Path to the living prisoner the least route ahead, never turning round.
func _tick_chase(delta: float) -> void:
	var quarry: Node3D = _nearest_ahead()
	if quarry == null:
		input.command.move_direction = Vector2.ZERO
		return
	_aim_agent(_chase_aim_point(quarry.global_position))
	_follow_path(delta)
	_tick_stuck(delta)


## A point on the ring a lookahead ahead of the ghost, converging on the quarry's radius.
func _chase_aim_point(quarry: Vector3) -> Vector3:
	if not _has_geometry:
		return quarry

	var here: Vector3 = controller.global_position
	var my_level: int = _route_level_of(here)
	if _route != null and _route_level_of(quarry) > my_level:
		if _flat_distance(here, _route.ramp_foot(_centre, my_level)) <= RAMP_ARRIVAL_METRES:
			return _route.ramp_top(_centre, my_level)
		quarry = _route.ramp_foot(_centre, my_level)

	var here_angle: float = _angle_of(here)
	var here_radius: float = maxf(_radius_of(here), 0.001)
	var gap_arc: float = wrapf((_angle_of(quarry) - here_angle) * TRAVEL_SIGN, 0.0, TAU)
	var lookahead: float = maxf(profile.lookahead_distance, CHASE_LOOKAHEAD_METRES)
	var step_arc: float = minf(lookahead / here_radius, gap_arc)

	var fraction: float = 1.0 if gap_arc <= 0.0 else step_arc / gap_arc
	var radius: float = lerpf(here_radius, _radius_of(quarry), fraction)
	var angle: float = here_angle + TRAVEL_SIGN * step_arc
	return Vector3(_centre.x + cos(angle) * radius, here.y, _centre.z + sin(angle) * radius)


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
		var cost: float = _flat_distance(here, body.global_position)
		if _has_geometry and _route != null:
			cost = _route_metres_of(body.global_position) - here_metres
			if cost < 0.0:
				cost += route_length
		if best == null or cost < best_cost:
			best = body
			best_cost = cost
	return best


func _route_metres_of(point: Vector3) -> float:
	if _route == null:
		return 0.0
	var level: int = _route_level_of(point)
	var swept: float = wrapf(
		(_angle_of(point) - _route.entry_angle(level)) * TRAVEL_SIGN, 0.0, TAU
	)
	return _route.metres_travelled(level, swept)


func _route_level_of(point: Vector3) -> int:
	return 0 if _route == null else _route.level_for_height(point.y)


# --- The route ----------------------------------------------------------------

## Path to the current waypoint and hold forward.
func _run_route(delta: float) -> void:
	_aim_agent(_current_waypoint())
	_follow_path(delta)


func _current_waypoint() -> Vector3:
	if _waypoints.is_empty():
		return controller.global_position
	return _waypoints[clampi(_wp, 0, _waypoints.size() - 1)]


func _waypoint_is_ramp(index: int) -> bool:
	return _ramp_from >= 0 and index >= _ramp_from


## Move past every waypoint already reached, and any the mesh cannot reach sensibly.
func _advance_waypoints() -> void:
	var here: Vector3 = controller.global_position
	var last: int = _waypoints.size() - 1
	while _wp < last:
		var point: Vector3 = _waypoints[_wp]
		var reached: bool = false
		if _waypoint_is_ramp(_wp):
			reached = _flat_distance(here, point) <= RAMP_ARRIVAL_METRES
		elif _wp == _gate_wp:
			reached = _flat_distance(here, point) <= GATE_ARRIVAL_METRES
		else:
			var arrival_arc: float = WAYPOINT_ARRIVAL_METRES / _lane_radius()
			reached = _travelled_arc >= _waypoint_arcs[_wp] - arrival_arc \
				or _flat_distance(here, point) <= WAYPOINT_ARRIVAL_METRES
		if not reached:
			break
		_wp += 1
		_stuck_failures = 0
	if _nav_ready() and _wp != _wp_checked:
		while _wp < last and _waypoint_is_a_detour(here, _waypoints[_wp]):
			_wp += 1
		_wp_checked = _wp


## True when the mesh path to [param point] is missing or far longer than the straight line.
func _waypoint_is_a_detour(here: Vector3, point: Vector3) -> bool:
	var path: PackedVector3Array = _nav.find_path(here, _nav.snap(point))
	if path.is_empty():
		return true
	return RingNavigation.path_length(path) > PATH_DETOUR_FACTOR * _flat_distance(here, point) + 10.0


func _skip_ahead() -> void:
	if _state == State.CROSS:
		_release_slide()
		_has_anchor = false
		_set_state(State.RECOVER)
		return
	if _wp < _waypoints.size() - 1:
		_wp += 1
	_aim_agent(_current_waypoint(), true)


## Bank the level and start the next lap from where the body stands.
func _climb_to_the_next_level() -> void:
	_level = mini(_level + 1, _route.last_index())
	_finish_arc = _route.lap_arc(_level)
	_travelled_arc = 0.0
	_previous_angle = _angle_of(controller.global_position)
	_entry_angle = _previous_angle
	_has_anchor = false
	_has_target = false
	_anchor_is_cover = false
	_build_waypoints()
	_set_state(State.RUNNING)


# --- Navigation ---------------------------------------------------------------

func _nav_ready() -> bool:
	return _nav != null and _nav.is_ready()


## Point the agent at [param target], snapped to the mesh. Re-queries only when it changes.
func _aim_agent(target: Vector3, force: bool = false) -> void:
	var ready: bool = _nav_ready()
	if not force and _has_agent_target and _agent_target_snapped == ready \
		and _flat_distance(target, _agent_raw_target) < PATH_POINT_METRES:
		return
	_agent_raw_target = target
	_agent_target = _nav.snap(target) if ready else target
	_agent_target_snapped = ready
	_has_agent_target = true
	if _agent != null:
		_agent.target_position = _agent_target


func _agent_live() -> bool:
	return _agent != null and _agent.is_inside_tree() and _nav_ready()


## The next point to steer at: the path's next corner, or the target itself without a mesh.
func _next_path_point() -> Vector3:
	if not _has_agent_target:
		return controller.global_position
	if not _agent_live():
		return _agent_target
	if _agent.is_navigation_finished():
		return _agent_target
	return _agent.get_next_path_position()


## Turn to the next path point and move at it, slowing as the turn gets sharper.
func _follow_path(delta: float) -> void:
	var next: Vector3 = _next_path_point()
	var error: float = _face(next, delta)
	if absf(error) < ALIGNED_RADIANS:
		input.command.move_direction = Vector2(0.0, 1.0)
		return
	_drive_towards(next, 0.0)
	input.command.move_direction *= clampf(1.0 - absf(error) / (PI * 0.5), MIN_THROTTLE, 1.0)


## The mesh path from [param from] to [param to], or the straight line when there is no mesh.
func _plan_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if _nav_ready():
		return _nav.find_path(from, to)
	if RunnerCoverFinder.segment_crosses_hazard(_hazards, from, to):
		return PackedVector3Array()
	return PackedVector3Array([from, to])


## True when what is left of the agent's path is one straight chord that crosses no hazard.
func _path_is_straight_and_clear() -> bool:
	if not _has_agent_target:
		return false
	var here: Vector3 = controller.global_position
	var goal: Vector3 = _agent_target
	if _agent_live():
		var path: PackedVector3Array = _agent.get_current_navigation_path()
		var line: Vector2 = Vector2(goal.x - here.x, goal.z - here.z)
		var span: float = line.length_squared()
		for index: int in range(_agent.get_current_navigation_path_index(), path.size()):
			var v: Vector2 = Vector2(path[index].x - here.x, path[index].z - here.z)
			var t: float = 0.0 if span <= 0.0001 else clampf(v.dot(line) / span, 0.0, 1.0)
			if (v - line * t).length() > STRAIGHT_PATH_METRES:
				return false
	return not RunnerCoverFinder.segment_crosses_hazard(_hazards, here, goal)


## True when [param metres] straight ahead of the body is floor with no hazard on it.
func _ahead_is_clear(metres: float) -> bool:
	var here: Vector3 = controller.global_position
	var forward: Vector3 = -controller.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return false
	var end: Vector3 = here + forward.normalized() * metres
	if RunnerCoverFinder.segment_crosses_hazard(_hazards, here, end):
		return false
	if _nav_ready():
		return _flat_distance(_nav.snap(end), end) <= PATH_POINT_METRES
	var world: World3D = controller.get_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	return RunnerCoverFinder.path_is_walkable(world.direct_space_state, _play, here, end)


# --- Stuck detection ----------------------------------------------------------

func _reset_stuck() -> void:
	_stuck_seconds = 0.0
	_stuck_failures = 0
	if controller != null:
		_stuck_origin = controller.global_position


## Under 1 m in 2 s: re-path first, skip the waypoint (or give up the crossing) second.
func _tick_stuck(delta: float) -> void:
	_stuck_seconds += delta
	if _stuck_seconds < STUCK_WINDOW_SECONDS:
		return
	var here: Vector3 = controller.global_position
	var moved: float = _flat_distance(here, _stuck_origin)
	_stuck_seconds = 0.0
	_stuck_origin = here
	if moved >= STUCK_DISTANCE_METRES:
		_stuck_failures = 0
		return
	_stuck_failures += 1
	if _stuck_failures >= STUCK_FAILURES_TO_SKIP:
		_stuck_failures = 0
		_skip_ahead()
	elif _has_agent_target:
		_aim_agent(_agent_target, true)


# --- The cover game -----------------------------------------------------------

func _tick_recover(remaining_arc: float, delta: float) -> void:
	_watch_and_hold(delta)
	if _perception.is_exposed():
		_plan_and_cross(remaining_arc, delta)
		return
	if controller.get_horizontal_speed() > SETTLED_SPEED:
		return
	_hold_seconds = 0.0
	_search_countdown = 0.0
	_set_state(State.HOLD)


func _tick_hold(remaining_arc: float, delta: float) -> void:
	_watch_and_hold(delta)
	_hold_seconds += delta
	if _perception.is_exposed():
		_plan_and_cross(remaining_arc, delta)
		return
	if _hold_seconds >= _play.min_hold_seconds:
		_set_state(State.EVALUATE)


## Behind cover, poised: the crossing decision, made fresh every tick.
func _tick_evaluate(remaining_arc: float, delta: float) -> void:
	_watch_and_hold(delta)
	_hold_seconds += delta
	if _perception.is_exposed():
		_plan_and_cross(remaining_arc, delta)
		return

	_search_countdown -= delta
	if _search_countdown <= 0.0 or not _has_target:
		_search_countdown = EVALUATE_SEARCH_SECONDS
		_choose_target(remaining_arc)
	if not _has_target:
		return

	_last_confidence = _crossing_confidence()
	_last_threshold = _break_threshold()
	if _last_confidence >= _last_threshold:
		_begin_cross(_target, _target_is_cover, _target_path)


## Committed: follow the path to the anchor.
func _tick_cross(delta: float) -> void:
	_cross_seconds += delta
	_aim_agent(_anchor)
	_follow_path(delta)
	_maybe_slide()
	_tick_slide_release(delta)

	var arrived: bool = _flat_distance(controller.global_position, _anchor) \
		<= _play.cover_arrival_tolerance
	var settled: bool = arrived and (not _anchor_is_cover or not _perception.is_exposed())
	if settled or _cross_seconds >= _cross_budget:
		_release_slide()
		_set_state(State.RECOVER)
		return
	_tick_stuck(delta)


## Press and hold slide once per crossing, only on a straight, hazard-free chord at speed.
func _maybe_slide() -> void:
	if not _cross_wants_slide or _cross_slid or controller.is_sliding():
		return
	if controller.profile == null:
		return
	if controller.get_horizontal_speed() < controller.profile.slide_min_entry_speed:
		return
	if input.command.move_direction.y < controller.profile.slide_min_forward_intent:
		return
	if not _path_is_straight_and_clear():
		return
	input.hold_slide(true)
	_cross_slid = true
	_cross_slide_held = true
	_cross_slide_open = false
	_cross_slide_seconds = 0.0
	_slides_attempted += 1


## Let go of slide the tick the slide ends, or once a press that never opened one is spent.
func _tick_slide_release(delta: float) -> void:
	if not _cross_slide_held or controller.profile == null:
		return
	_cross_slide_seconds += delta
	if controller.is_sliding():
		_cross_slide_open = true
		return
	if _cross_slide_open or _cross_slide_seconds >= controller.profile.slide_buffer_time:
		_release_slide()


func _release_slide() -> void:
	if _cross_slide_held:
		input.hold_slide(false)
		_cross_slide_held = false


# --- Jumping ------------------------------------------------------------------

## Press jump (never hold) to unstick from a wall, or mid-crossing for speed or exposure.
## Never when the ground ahead crosses a hazard or leaves the mesh.
func _maybe_jump(delta: float) -> void:
	_jump_cooldown = maxf(_jump_cooldown - delta, 0.0)

	if _play == null or not _play.jump_enabled or controller.profile == null:
		_blocked_seconds = 0.0
		return
	if not controller.is_on_floor() or controller.is_sliding() or _cross_slide_held:
		_blocked_seconds = 0.0
		return

	var asking_to_move: bool = input.command.move_direction.length_squared() > 0.25
	var speed: float = controller.get_horizontal_speed()

	if asking_to_move and controller.is_on_wall() and speed < _play.jump_blocked_speed:
		_blocked_seconds += delta
		if _blocked_seconds >= _play.jump_blocked_seconds and _jump_cooldown <= 0.0 \
			and _ahead_is_clear(UNSTICK_LOOK_METRES):
			_blocked_seconds = 0.0
			_press_jump()
		return
	_blocked_seconds = 0.0

	if _jump_cooldown > 0.0:
		return
	if _state != State.CROSS or not _has_anchor or not asking_to_move:
		return
	if _cross_wants_slide and not _cross_slid:
		return
	if _flat_distance(controller.global_position, _anchor) <= _play.jump_min_remaining_metres:
		return

	var surplus: bool = speed > controller.profile.ground_speed
	var worth_breaking: bool = _exposed_metres > _play.free_crossing_metres
	if not surplus and not worth_breaking:
		return
	if not _path_is_straight_and_clear() or not _ahead_is_clear(JUMP_LOOK_METRES):
		return
	_press_jump()


func _press_jump() -> void:
	input.command.jump_pressed = true
	_jump_cooldown = _play.jump_cooldown_seconds
	_jumps += 1


# --- Deciding -----------------------------------------------------------------

## How good this crossing looks, 0 to 1: reload window, guard attention, open ground.
func _crossing_confidence() -> float:
	if _exposed_metres <= 0.0:
		return 1.0

	var speed: float = maxf(_crossing_speed(), 0.001)
	var open_seconds: float = _exposed_metres / speed
	var window: float = clampf(
		_perception.get_believed_reload_remaining() / open_seconds, 0.0, 1.0
	)

	var attention: float = 1.0
	if _perception.believes_watched():
		attention = _play.watched_confidence_penalty

	var exposure: float = 1.0
	if _exposed_metres > _play.free_crossing_metres:
		var span: float = maxf(
			_play.max_crossing_metres - _play.free_crossing_metres, 0.0001
		)
		exposure = clampf((_play.max_crossing_metres - _exposed_metres) / span, 0.0, 1.0)

	return exposure * (window + (1.0 - window) * attention)


## The confidence a crossing has to beat, falling to zero as patience runs out.
func _break_threshold() -> float:
	var span: float = maxf(_play.max_hold_seconds - _play.min_hold_seconds, 0.0001)
	var patience: float = clampf(
		(_hold_seconds - _play.min_hold_seconds) / span, 0.0, 1.0
	)
	return _play.break_confidence_threshold * (1.0 - patience)


## Commit to [param target] along [param path]; the anchor is the path's on-mesh end.
func _begin_cross(target: Vector3, is_cover: bool, path: PackedVector3Array) -> void:
	_has_target = false
	_anchor = path[path.size() - 1] if not path.is_empty() else target
	_has_anchor = true
	_anchor_is_cover = is_cover
	_cross_seconds = 0.0
	_aim_agent(_anchor, true)

	_cross_wants_slide = _exposed_metres >= _play.slide_min_exposed_metres
	_cross_slid = false
	_cross_slide_held = false
	_cross_slide_open = false
	_cross_slide_seconds = 0.0

	var distance: float = maxf(
		RingNavigation.path_length(path), _flat_distance(controller.global_position, _anchor)
	)
	_cross_budget = (distance / maxf(_crossing_speed(), 0.001)) \
		* _play.cross_timeout_multiple + 1.0

	_crossings += 1
	if is_cover:
		_crossings_to_cover += 1
	if _perception.get_believed_reload_remaining() > 0.0:
		_crossings_believed_safe += 1
	_set_state(State.CROSS)


## Re-plan from here and go without asking the confidence: standing in the open is never an option.
func _plan_and_cross(remaining_arc: float, delta: float) -> void:
	_choose_target(remaining_arc)
	if not _has_target:
		if not _has_anchor:
			_run_route(delta)
		return
	_last_confidence = 0.0
	_last_threshold = 0.0
	_begin_cross(_target, _target_is_cover, _target_path)


## Search for cover, keep it only if the mesh reaches it, else fall back to the route ahead.
func _choose_target(remaining_arc: float) -> void:
	_search_cover(remaining_arc)
	var here: Vector3 = controller.global_position
	_has_target = false
	_target_path = PackedVector3Array()

	if _cover.has_result():
		var path: PackedVector3Array = _plan_path(here, _cover.get_position())
		if not path.is_empty():
			_target = _cover.get_position()
			_target_is_cover = true
			_target_path = path
			_has_target = true

	if not _has_target:
		var arc: float = minf(_play.get_cover_search_arc_radians(), maxf(remaining_arc, 0.0))
		var ahead: Vector3 = _point_on_track(_previous_angle + TRAVEL_SIGN * arc)
		for candidate: Vector3 in [ahead, _current_waypoint()]:
			var snapped: Vector3 = _nav.snap(candidate) if _nav_ready() else candidate
			var path: PackedVector3Array = _plan_path(here, snapped)
			if path.is_empty():
				continue
			_target = snapped
			_target_is_cover = false
			_target_path = path
			_has_target = true
			break

	if _has_target:
		_exposed_metres = _measure_exposure(_target_path)


## Metres of [param path] on which a shot from the tower could reach a chest.
func _measure_exposure(path: PackedVector3Array) -> float:
	var length: float = RingNavigation.path_length(path)
	if length <= 0.0 or path.size() < 2:
		return 0.0
	var eye: Vector3 = _perception.get_threat_eye()
	var lift: Vector3 = Vector3.UP * _play.cover_test_height
	var samples: int = maxi(_play.path_samples, 2)
	var open: int = 0
	for index: int in samples:
		var along: float = length * (float(index) + 0.5) / float(samples)
		if _perception.has_clear_line(_point_along(path, along) + lift, eye):
			open += 1
	return length * float(open) / float(samples)


func _point_along(path: PackedVector3Array, metres: float) -> Vector3:
	var left: float = metres
	for index: int in range(1, path.size()):
		var a: Vector3 = path[index - 1]
		var b: Vector3 = path[index]
		var segment: float = Vector2(b.x - a.x, b.z - a.z).length()
		if left <= segment or index == path.size() - 1:
			return a.lerp(b, 0.0 if segment <= 0.0 else clampf(left / segment, 0.0, 1.0))
		left -= segment
	return path[path.size() - 1]


func _search_cover(remaining_arc: float) -> void:
	var space: PhysicsDirectSpaceState3D = controller.get_world_3d().direct_space_state
	if space == null:
		return
	_cover.search(
		_perception,
		_play,
		space,
		controller.global_position,
		_centre,
		TRAVEL_SIGN,
		_lane_radius(),
		remaining_arc,
		_hazards,
	)


# --- Driving the body ---------------------------------------------------------

## Face the tower and hold station on the anchor.
func _watch_and_hold(delta: float) -> void:
	_face(_perception.get_threat_eye(), delta)
	if _has_anchor:
		_drive_towards(_anchor, _play.cover_arrival_tolerance * HOLD_DEADZONE)
	else:
		input.command.move_direction = Vector2.ZERO


## Turn towards [param point] at this tick's allowed rate; returns the signed heading error.
## [method BotIntentSource.aim] takes radians per second.
func _face(point: Vector3, delta: float) -> float:
	var to_target: Vector3 = point - controller.global_position
	var forward: Vector3 = -controller.global_transform.basis.z
	var error: float = Vector2(forward.x, forward.z).angle_to(
		Vector2(to_target.x, to_target.z)
	)
	input.aim(
		clampf(error * profile.steering_gain, -profile.max_yaw_rate, profile.max_yaw_rate),
		0.0,
		delta,
	)
	return error


## Walk towards [param point] whatever the body faces; move_direction is body-local.
func _drive_towards(point: Vector3, deadzone: float) -> void:
	var to_target: Vector3 = point - controller.global_position
	var flat: Vector2 = Vector2(to_target.x, to_target.z)
	if flat.length() <= deadzone:
		input.command.move_direction = Vector2.ZERO
		return
	var basis: Basis = controller.global_transform.basis
	var right: Vector2 = Vector2(basis.x.x, basis.x.z)
	var forward: Vector2 = Vector2(-basis.z.x, -basis.z.z)
	input.command.move_direction = Vector2(flat.dot(right), flat.dot(forward)).normalized()


func _crossing_speed() -> float:
	if controller.profile == null:
		return 1.0
	return controller.profile.ground_speed


## Report the lap once. With a gate on the map, keep running back through it until the
## match silences this brain, so a body that slipped past the gate box still gets scored.
func _finish() -> void:
	if not _reported_end:
		_reported_end = true
		reached_end.emit(_elapsed_seconds, _path_length)
	if _gate_wp >= 0:
		_wp = _gate_wp
		_wp_checked = _wp
		_aim_agent(_current_waypoint(), true)
		return
	set_physics_process(false)
	input.command.clear()


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


func _angle_of_about(centre: Vector3, point: Vector3) -> float:
	return atan2(point.z - centre.z, point.x - centre.x)


func _lane_radius() -> float:
	return 44.5 if _route == null else _route.lane_radius(_level)


func _point_on_track(angle: float) -> Vector3:
	return _point_on_level(angle, _lane_radius())


func _point_on_level(angle: float, radius: float) -> Vector3:
	var height: float = _centre.y if _route == null else _route.deck_height(_level)
	return Vector3(_centre.x + cos(angle) * radius, height, _centre.z + sin(angle) * radius)


func _track_tangent(angle: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, cos(angle)) * TRAVEL_SIGN


func _heading_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func _radius_of(point: Vector3) -> float:
	return Vector2(point.x - _centre.x, point.z - _centre.z).length()


func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()
