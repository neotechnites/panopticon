class_name TowerShooter
extends Node

## The tower's brain: the opposite number to [RingRunner].
##
## It stands on the platform, searches the ring, decides whether a runner it can
## see is worth a shot, and calls [method Rifle.try_fire]. It has no movement
## and no weapon of its own: it writes a [MoveIntent] into a [BotIntentSource]
## and the same controller and rifle a human holds do the rest, so nothing it
## does changes how a hit resolves.
##
## It is modelled on a competent human, not a turret: a sampled reaction delay
## per acquisition; an underdamped aim that lags a mover and overshoots; lead
## misjudged more the faster a target crosses; a scan that revisits where
## runners were last seen and the map's chokepoints; commitment through brief
## occlusion; a declined shot at a runner about to reach cover; suspicion of a
## body that appears next to a known one. [member MatchRules.guard_skill]
## scales the reaction, the errors and the scan through [ShooterProfile].
##
## Everything it perceives is inside the live camera frustum and past a line
## of sight ray, so cover works on it the way it works on a player.

signal state_changed(previous: State, current: State)
signal target_acquired(body: PlayerController)
signal target_lost()
signal shot_taken(confidence: float)
signal shot_declined(confidence: float)

enum State {
	SCANNING,
	ACQUIRING,
	ENGAGING,
	RECOVERING,
}

## Map markers the scan prefers when it has nothing remembered: the chokepoints.
const WATCH_GROUP: StringName = &"guard_watch"
## Angular hysteresis before the crosshair swaps to a closer target, radians.
const SWITCH_HYSTERESIS: float = 0.15
## The scan counts a point as reached inside this yaw error, radians.
const SCAN_REACHED: float = 0.09
## A scan point it cannot reach is abandoned after this long.
const SCAN_TIMEOUT_SECONDS: float = 4.0
## How far a remembered runner is projected along its last velocity, seconds.
const MEMORY_PROJECTION_SECONDS: float = 1.5

@export var controller: PlayerController
@export var input: BotIntentSource
@export var rifle: Rifle
@export var optic: WeaponOptic
@export var camera: Camera3D
@export var profile: ShooterProfile
@export var rules: MatchRules
@export var target_group: StringName = &"prisoners"

var _target: PlayerController = null
var _state: State = State.SCANNING
var _clock: float = 0.0
var _sighted_seconds: float = 0.0
var _ready_sighted_seconds: float = 0.0
var _reaction_delay: float = 0.0
var _occluded_seconds: float = 0.0
var _believed_point: Vector3 = Vector3.ZERO
var _believed_velocity: Vector3 = Vector3.ZERO
var _aim_rate: Vector2 = Vector2.ZERO
var _aim_error: Vector2 = Vector2.ZERO
var _aim_error_age: float = 0.0
var _lead_bias: float = 0.0
var _lead_bias_age: float = 0.0
var _confidence: float = 0.0
var _confidence_terms: Vector3 = Vector3.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _fire_attempts: int = 0
var _shots_taken: int = 0
var _found: Array[PlayerController] = []
var _pool: Array[Node] = []
var _half_angles: Vector2 = Vector2.ZERO
var _ray: PhysicsRayQueryParameters3D = _make_ray()
var _ray_exclude: Array[RID] = []

# Memory, keyed by instance id: last seen aim point, velocity and clock time.
var _memory_point: Dictionary = {}
var _memory_velocity: Dictionary = {}
var _memory_seen: Dictionary = {}
var _suspect_until: Dictionary = {}
var _known: Dictionary = {}
var _registered: bool = false

# The scan: chokepoints from the map, the current point of interest, the fallback sweep.
var _watch_points: PackedVector3Array = PackedVector3Array()
var _scan_point: Vector3 = Vector3.ZERO
var _scan_has_point: bool = false
var _scan_dwell: float = 0.0
var _scan_elapsed: float = 0.0
var _scan_index: int = 0
var _scan_sign: float = 1.0
var _scan_swept: float = 0.0


static func _make_ray() -> PhysicsRayQueryParameters3D:
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	ray.collide_with_areas = false
	ray.collide_with_bodies = true
	return ray


func _ready() -> void:
	# Joined before the configuration check and never left: this is how a
	# RingRunner finds out there is a guard on the ring at all.
	add_to_group(RunnerPerception.SHOOTER_GROUP)
	if controller == null or input == null or rifle == null or profile == null:
		push_error("TowerShooter needs a controller, an input, a rifle and a profile; it will not play.")
		set_physics_process(false)
		return
	_rng = profile.make_rng()
	_resample_aim_error()
	set_physics_process(false)


## Place the body on its stand facing [param initial_yaw] and start playing.
func configure(spawn_point: Vector3, initial_yaw: float = 0.0) -> void:
	if controller == null or input == null or rifle == null or profile == null:
		return
	controller.global_position = spawn_point
	controller.velocity = Vector3.ZERO
	controller.rotation = Vector3(0.0, initial_yaw, 0.0)
	_target = null
	_state = State.SCANNING
	_clock = 0.0
	_sighted_seconds = 0.0
	_ready_sighted_seconds = 0.0
	_reaction_delay = 0.0
	_occluded_seconds = 0.0
	_aim_rate = Vector2.ZERO
	_confidence = 0.0
	_fire_attempts = 0
	_shots_taken = 0
	_memory_point.clear()
	_memory_velocity.clear()
	_memory_seen.clear()
	_suspect_until.clear()
	_known.clear()
	_registered = false
	_scan_has_point = false
	_scan_index = 0
	_scan_sign = 1.0
	_scan_swept = 0.0
	_resample_aim_error()
	_resample_lead_bias()
	_read_watch_points()
	if optic != null:
		optic.reset_zoom()
	set_physics_process(true)


func _read_watch_points() -> void:
	_watch_points.clear()
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(WATCH_GROUP):
		var marker: Node3D = node as Node3D
		if marker != null:
			_watch_points.append(marker.global_position)


# --- Readouts -----------------------------------------------------------------

func get_state() -> State:
	return _state


func get_state_name() -> String:
	return String(State.keys()[_state])


func get_target() -> PlayerController:
	return _target


func get_fire_attempts() -> int:
	return _fire_attempts


func get_shots_taken() -> int:
	return _shots_taken


## Seconds the current target has been continuously visible.
func get_sighted_seconds() -> float:
	return _sighted_seconds


## Of those, the seconds the rifle was ready: the guard's own latency to a shot.
func get_ready_sighted_seconds() -> float:
	return _ready_sighted_seconds


## The reaction delay sampled for the current acquisition, seconds.
func get_reaction_delay() -> float:
	return _reaction_delay


func get_skill() -> float:
	return rules.guard_skill if rules != null else 0.5


func is_suspect(body: PlayerController) -> bool:
	if body == null:
		return false
	return float(_suspect_until.get(body.get_instance_id(), -1.0)) > _clock


func get_aim_rate() -> Vector2:
	return _aim_rate


func get_lead_bias() -> float:
	return _lead_bias


## A fresh reaction sample from the profile's distribution at [param skill].
func sample_reaction_seconds(skill: float) -> float:
	var median: float = profile.get_reaction_median_seconds(skill)
	var sample: float = median * exp(_rng.randfn(0.0, profile.reaction_spread))
	return maxf(sample, profile.reaction_floor_seconds)


# --- The loop -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	_tick_aim_error(delta)
	_tick_lead_bias(delta)
	# The tower does not walk; written every tick so the ground phase runs.
	input.command.move_direction = Vector2.ZERO
	var target: PlayerController = _choose_target(_visible_targets())
	if target == null:
		_forget_target()
		_scan(delta)
		_drive_optic(0.0, Vector2.ZERO)
		_set_state(State.RECOVERING if not rifle.can_fire() else State.SCANNING)
		return
	if target != _target:
		_acquire(target)
	_scan_has_point = false
	var visible_now: bool = _found.has(target)
	if visible_now:
		_sighted_seconds += delta
		if rifle.can_fire():
			_ready_sighted_seconds += delta
		_occluded_seconds = 0.0
		_believed_point = _aim_point(target)
		_read_velocity(target.velocity, delta)
	else:
		_occluded_seconds += delta
		_believed_point += _believed_velocity * delta
	var aim_error: Vector2 = _track(delta)
	var distance: float = _eye_position().distance_to(_believed_point)
	_drive_optic(distance, aim_error)
	if not rifle.can_fire():
		_set_state(State.RECOVERING)
		return
	if not visible_now or _sighted_seconds < _reaction_delay:
		_set_state(State.ACQUIRING)
		return
	_set_state(State.ENGAGING)
	_confidence = _compute_confidence(target, aim_error, distance)
	if _confidence < profile.shot_confidence_threshold:
		shot_declined.emit(_confidence)
		return
	if not _has_line_of_sight(target):
		return
	# Reload discipline: a runner a step from cover is not worth the reload.
	if _confidence < profile.sure_shot_confidence and _about_to_be_covered(target):
		shot_declined.emit(_confidence)
		return
	_fire_attempts += 1
	if rifle.try_fire():
		_shots_taken += 1
		_ready_sighted_seconds = 0.0
		shot_taken.emit(_confidence)
		_set_state(State.RECOVERING)


## The velocity read lags a change: a turn is led where the target was going.
func _read_velocity(actual: Vector3, delta: float) -> void:
	var read: float = profile.get_velocity_read_seconds(get_skill())
	if read <= 0.0:
		_believed_velocity = actual
		return
	_believed_velocity = _believed_velocity.lerp(actual, clampf(delta / read, 0.0, 1.0))


func _acquire(target: PlayerController) -> void:
	_target = target
	_sighted_seconds = 0.0
	_ready_sighted_seconds = 0.0
	_occluded_seconds = 0.0
	_reaction_delay = sample_reaction_seconds(get_skill())
	_believed_point = _aim_point(target)
	_believed_velocity = target.velocity
	_resample_aim_error()
	_resample_lead_bias()
	target_acquired.emit(target)


# --- Perception ---------------------------------------------------------------

func _visible_targets() -> Array[PlayerController]:
	var found: Array[PlayerController] = _found
	found.clear()
	var pool: Array[Node] = _pool
	pool.clear()
	pool.append_array(get_tree().get_nodes_in_group(target_group))
	pool.append_array(get_tree().get_nodes_in_group(RunnerPower.DECOY_GROUP))
	_half_angles = _view_half_angles()
	_note_appearances(pool)
	for node: Node in pool:
		var body: PlayerController = node as PlayerController
		if body == null or body == controller:
			continue
		if not _is_within_view(body):
			continue
		if not _has_line_of_sight(body):
			continue
		if not _is_discernible(body):
			continue
		found.append(body)
		var id: int = body.get_instance_id()
		_memory_point[id] = _aim_point(body)
		_memory_velocity[id] = body.velocity
		_memory_seen[id] = _clock
	return found


## A body seen for the first time within a few metres of a known one is a
## likely hologram; the first tick registers everyone without suspicion.
func _note_appearances(pool: Array[Node]) -> void:
	for node: Node in pool:
		var body: PlayerController = node as PlayerController
		if body == null or body == controller:
			continue
		var id: int = body.get_instance_id()
		if _known.has(id):
			continue
		_known[id] = true
		if not _registered:
			continue
		if _appeared_beside_a_known_body(body, pool):
			_suspect_until[id] = _clock + profile.decoy_suspicion_seconds
	_registered = true


func _appeared_beside_a_known_body(body: PlayerController, pool: Array[Node]) -> bool:
	var reach: float = profile.decoy_suspicion_metres
	for node: Node in pool:
		var other: PlayerController = node as PlayerController
		if other == null or other == body or other == controller:
			continue
		if other.global_position.distance_to(body.global_position) <= reach:
			return true
	return false


func _is_discernible(body: PlayerController) -> bool:
	var ability: RunnerPower = RunnerPower.of(body)
	if ability == null or not ability.is_camouflaged():
		return true
	return _eye_position().distance_to(_aim_point(body)) <= RunnerPower.CAMO_VISIBLE_RANGE


## Nearest to the crosshair wins, suspects only when nothing else is there, the
## current target kept unless another is clearly closer, and a target just lost
## behind cover held for [member ShooterProfile.commitment_seconds].
func _choose_target(candidates: Array[PlayerController]) -> PlayerController:
	var best: PlayerController = null
	var best_offset: float = INF
	var best_suspect: bool = true
	var current_offset: float = INF
	var current_suspect: bool = false
	for body: PlayerController in candidates:
		var offset: float = _crosshair_offset(body)
		var suspect: bool = is_suspect(body)
		if body == _target:
			current_offset = offset
			current_suspect = suspect
		if suspect and not best_suspect:
			continue
		if (not suspect and best_suspect) or offset < best_offset:
			best = body
			best_offset = offset
			best_suspect = suspect
	if _target != null and current_offset < INF:
		if current_suspect == best_suspect and current_offset <= best_offset + SWITCH_HYSTERESIS:
			return _target
		return best
	if best == null and _target != null and _occluded_seconds < profile.commitment_seconds:
		if is_instance_valid(_target) and _target.is_inside_tree() and _still_a_target(_target):
			return _target
	return best


func _still_a_target(body: PlayerController) -> bool:
	return body.is_in_group(target_group) or body.is_in_group(RunnerPower.DECOY_GROUP)


func _crosshair_offset(body: PlayerController) -> float:
	var local: Vector3 = _eye().to_local(_aim_point(body))
	return Vector2(local.x, local.y).length()


func _is_within_view(body: PlayerController) -> bool:
	var local: Vector3 = _eye().to_local(_aim_point(body))
	if local.z >= 0.0:
		return false
	var half: Vector2 = _half_angles
	var horizontal: float = absf(atan2(local.x, -local.z))
	var vertical: float = absf(atan2(local.y, Vector2(local.x, local.z).length()))
	return horizontal <= half.x and vertical <= half.y


func _view_half_angles() -> Vector2:
	var fov: float = camera.fov if camera != null else profile.fallback_fov_degrees
	var vertical: float = deg_to_rad(fov) * 0.5
	var horizontal: float = atan(tan(vertical) * profile.view_aspect)
	if rules != null and rules.guard_fov_degrees < 360.0:
		horizontal = minf(horizontal, deg_to_rad(rules.guard_fov_degrees) * 0.5)
	return Vector2(horizontal, vertical) * profile.fov_margin


func _has_line_of_sight(body: PlayerController) -> bool:
	return _line_clear_to(body, _aim_point(body))


func _about_to_be_covered(body: PlayerController) -> bool:
	if profile.cover_lookahead_seconds <= 0.0:
		return false
	var ahead: Vector3 = _aim_point(body) + body.velocity * profile.cover_lookahead_seconds
	return not _line_clear_to(body, ahead)


func _line_clear_to(body: PlayerController, point: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = controller.get_world_3d().direct_space_state
	if space == null:
		return false
	_ray.from = _eye_position()
	_ray.to = point
	_ray.collision_mask = rifle.profile.hit_mask if rifle.profile != null else 0xFFFFF
	if _ray_exclude.is_empty() or _ray_exclude[0] != controller.get_rid():
		_ray_exclude.clear()
		_ray_exclude.append(controller.get_rid())
		_ray.exclude = _ray_exclude
	var hit: Dictionary = space.intersect_ray(_ray)
	if hit.is_empty():
		return true
	return (hit.get("collider", null) as Node3D) == body


func _aim_point(body: PlayerController) -> Vector3:
	return body.global_position + Vector3.UP * profile.target_aim_height


func _eye() -> Node3D:
	if rifle.aim_source != null:
		return rifle.aim_source
	if camera != null:
		return camera
	if controller.head != null:
		return controller.head
	return controller


func _eye_position() -> Vector3:
	return _eye().global_position


# --- Looking ------------------------------------------------------------------

## Nothing in view: rest on the freshest sighting projected along its velocity,
## then a chokepoint, alternating; sweep when there is neither.
func _scan(delta: float) -> void:
	var skill: float = get_skill()
	var yaw_cap: float = profile.get_scan_yaw_rate(skill)
	if _scan_has_point:
		_scan_elapsed += delta
		var error: Vector2 = _angles_to(_scan_point)
		if absf(error.x) <= SCAN_REACHED:
			_scan_dwell -= delta
		if _scan_dwell <= 0.0 or _scan_elapsed >= SCAN_TIMEOUT_SECONDS:
			_scan_has_point = false
		else:
			_steer(error, delta, yaw_cap, profile.max_pitch_rate)
			return
	if _pick_scan_point():
		_steer(_angles_to(_scan_point), delta, yaw_cap, profile.max_pitch_rate)
		return
	var rate: float = yaw_cap * _scan_sign
	_scan_swept += yaw_cap * delta
	if _scan_swept >= profile.get_scan_sweep_radians():
		_scan_swept = 0.0
		_scan_sign = -_scan_sign
	var pitch_error: float = profile.get_scan_pitch_radians() - _current_pitch()
	_aim_rate = Vector2(rate, _clamp_pitch_rate(pitch_error * profile.tracking_omega))
	input.aim(_aim_rate.x, _aim_rate.y, delta)


func _pick_scan_point() -> bool:
	_scan_index += 1
	var want_memory: bool = _scan_index % 2 == 1 or _watch_points.is_empty()
	if want_memory and _recall_freshest():
		return _begin_scan_point()
	if _watch_points.is_empty():
		return false
	_scan_point = _watch_points[(_scan_index / 2) % _watch_points.size()]
	return _begin_scan_point()


func _begin_scan_point() -> bool:
	_scan_has_point = true
	_scan_dwell = profile.scan_dwell_seconds * ShooterProfile.skill_scale(get_skill(), profile.skill_scan_span)
	_scan_elapsed = 0.0
	return true


func _recall_freshest() -> bool:
	var freshest: float = -INF
	var found: bool = false
	for id: Variant in _memory_seen:
		var seen: float = float(_memory_seen[id])
		if _clock - seen > profile.memory_seconds or seen <= freshest:
			continue
		var body: PlayerController = instance_from_id(int(id)) as PlayerController
		if body == null or not _still_a_target(body):
			continue
		freshest = seen
		found = true
		var age: float = minf(_clock - seen, MEMORY_PROJECTION_SECONDS)
		_scan_point = (_memory_point[id] as Vector3) + (_memory_velocity[id] as Vector3) * age
	return found


## Steer at the believed point plus lead, misjudged in proportion to how fast
## the target crosses; returns the believed aim error for the shot decision.
func _track(delta: float) -> Vector2:
	var to_target: Vector3 = _believed_point - _eye_position()
	var range_to_target: float = maxf(to_target.length(), 0.0001)
	var direction: Vector3 = to_target / range_to_target
	var crossing: Vector3 = _believed_velocity - direction * _believed_velocity.dot(direction)
	var crossing_speed: float = crossing.length()
	var angular_speed: float = crossing_speed / range_to_target
	var omega: float = profile.get_tracking_omega(get_skill())
	var ideal_lead: float = 2.0 * profile.tracking_damping / omega
	var steer_point: Vector3 = _believed_point + crossing * ideal_lead
	if crossing_speed > 0.0001:
		var misjudged: float = profile.get_lead_error_radians(angular_speed, get_skill()) * _lead_bias
		steer_point += crossing / crossing_speed * (misjudged * range_to_target)
	_steer(_angles_to(steer_point), delta, profile.max_yaw_rate, profile.max_pitch_rate)
	return _angles_to(_believed_point)


## The hand on the mouse: a second-order response to the aim error.
func _steer(error: Vector2, delta: float, yaw_cap: float, pitch_cap: float) -> void:
	var omega: float = profile.get_tracking_omega(get_skill())
	var accel: Vector2 = error * (omega * omega) - _aim_rate * (2.0 * profile.tracking_damping * omega)
	_aim_rate += accel * delta
	_aim_rate.x = clampf(_aim_rate.x, -yaw_cap, yaw_cap)
	_aim_rate.y = clampf(_aim_rate.y, -pitch_cap, pitch_cap)
	input.aim(_aim_rate.x, _aim_rate.y, delta)


func _angles_to(point: Vector3) -> Vector2:
	var to_target: Vector3 = point - _eye_position()
	var flat: float = Vector2(to_target.x, to_target.z).length()
	var forward: Vector3 = -controller.global_transform.basis.z
	var yaw: float = Vector2(forward.x, forward.z).angle_to(
		Vector2(to_target.x, to_target.z)
	) + _aim_error.x
	var pitch: float = atan2(to_target.y, flat) + _aim_error.y - _current_pitch()
	return Vector2(yaw, pitch)


func _clamp_pitch_rate(rate: float) -> float:
	return clampf(rate, -profile.max_pitch_rate, profile.max_pitch_rate)


func _current_pitch() -> float:
	if controller.head == null:
		return 0.0
	return controller.head.rotation.x


# --- Errors -------------------------------------------------------------------

func _tick_aim_error(delta: float) -> void:
	_aim_error_age += delta
	if _aim_error_age >= profile.aim_error_resample_seconds:
		_resample_aim_error()


func _resample_aim_error() -> void:
	_aim_error_age = 0.0
	var limit: float = profile.get_aim_error_radians_at(get_skill())
	if limit <= 0.0:
		_aim_error = Vector2.ZERO
		return
	var angle: float = _rng.randf_range(-PI, PI)
	var radius: float = limit * sqrt(_rng.randf())
	_aim_error = Vector2(cos(angle), sin(angle)) * radius


func _tick_lead_bias(delta: float) -> void:
	_lead_bias_age += delta
	if _lead_bias_age >= profile.lead_error_resample_seconds:
		_resample_lead_bias()


func _resample_lead_bias() -> void:
	_lead_bias_age = 0.0
	_lead_bias = clampf(_rng.randfn(0.0, 1.0), -2.0, 2.0)


# --- The shot decision --------------------------------------------------------

func get_shot_confidence() -> float:
	return _confidence


func get_confidence_terms() -> Vector3:
	return _confidence_terms


func _compute_confidence(body: PlayerController, aim_error: Vector2, distance: float) -> float:
	var aim_term: float = clampf(
		1.0 - aim_error.length() / maxf(profile.get_aim_tolerance_radians(), 0.0001),
		0.0,
		1.0,
	)
	var to_target: Vector3 = _aim_point(body) - _eye_position()
	var range_to_target: float = maxf(to_target.length(), 0.0001)
	var direction: Vector3 = to_target / range_to_target
	var crossing: Vector3 = body.velocity - direction * body.velocity.dot(direction)
	var angular_speed: float = crossing.length() / range_to_target
	var motion_term: float = 1.0 / (
		1.0 + angular_speed / maxf(profile.max_comfortable_track_rate, 0.0001)
	)
	var range_term: float = 1.0
	if distance > profile.confident_range:
		var span: float = maxf(profile.max_engagement_range - profile.confident_range, 0.0001)
		range_term = clampf((profile.max_engagement_range - distance) / span, 0.0, 1.0)
	_confidence_terms = Vector3(aim_term, motion_term, range_term)
	return aim_term * motion_term * range_term


# --- Optic --------------------------------------------------------------------

func _drive_optic(distance: float, aim_error: Vector2) -> void:
	if optic == null or not profile.wants_optic():
		return
	if _target == null or distance < profile.optic_min_distance:
		optic.zoom_out()
		return
	var half: Vector2 = _zoomed_half_angles() * profile.optic_centre_fraction
	optic.set_zoomed(absf(aim_error.x) <= half.x and absf(aim_error.y) <= half.y)


func _zoomed_half_angles() -> Vector2:
	var fov: float = optic.get_zoomed_fov()
	if fov <= 0.0:
		fov = profile.fallback_fov_degrees
	var vertical: float = deg_to_rad(fov) * 0.5
	return Vector2(atan(tan(vertical) * profile.view_aspect), vertical) * profile.fov_margin


# --- State --------------------------------------------------------------------

func _forget_target() -> void:
	if _target == null:
		return
	_target = null
	_sighted_seconds = 0.0
	_ready_sighted_seconds = 0.0
	_occluded_seconds = 0.0
	_confidence = 0.0
	_confidence_terms = Vector3.ZERO
	target_lost.emit()


func _set_state(next: State) -> void:
	if next == _state:
		return
	var previous: State = _state
	_state = next
	state_changed.emit(previous, _state)
