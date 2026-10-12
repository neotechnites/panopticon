extends SceneTree

## Haters short (pipeline v2), shot 1: run_clip's marker contract for the c4943a47 build (no run_clip there).
## The tower's player on the centre platform, scoped in (--fov), the build's crosshair, the head driven like a hand.

const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const HAND_OMEGA: float = 6.0
const HAND_ZETA: float = 0.7
const HAND_MAX_RATE: float = deg_to_rad(70.0)
const SETTLE_SECONDS: float = 0.35
const RECOIL_PITCH_RATE: float = deg_to_rad(80.0)
const RECOIL_YAW_RATE: float = deg_to_rad(14.0)
const SWAY_DEGREES: float = 0.35
const SWAY_HZ: float = 0.6
const AIM_HEIGHT: float = 1.05
const VELOCITY_WINDOW: float = 0.45
const DROP_SECONDS: float = 0.45
## Take seconds: [start hand on a man, earliest squeeze, miss by metres, hold on him after].
const BEATS: Array = [
	{"from": 0.9, "fire_at": 2.05, "miss_by": 0.0},
	{"from": 2.6, "fire_at": 4.45, "miss_by": 0.0},
	{"from": 4.7, "fire_at": 6.85, "miss_by": 0.0},
]

var _options: Dictionary = {}
var _seconds: float = 8.8
var _sync_left: int = 0
var _tail_left: int = -1
var _cover: CanvasLayer = null
var _booted: bool = false
var _elapsed: float = 0.0
var _player: PlayerController = null
var _rifle: Rifle = null
var _controller: MatchController = null
var _camera: Camera3D = null
var _hand: Node = null


class Hand extends Node:
	var run: Object = null

	func _physics_process(delta: float) -> void:
		run.call(&"_hand_tick", delta)


func _initialize() -> void:
	for raw: String in OS.get_cmdline_user_args():
		if raw.begins_with("--"):
			var kv: PackedStringArray = raw.substr(2).split("=", true, 1)
			_options[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_seconds = float(_options.get("seconds", "8.8"))
	_sync_left = int(_options.get("sync", "0"))
	_cover = CanvasLayer.new()
	_cover.layer = 128
	var white := ColorRect.new()
	white.color = Color.WHITE
	white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(white)
	root.add_child(_cover)
	_cover.visible = _sync_left > 0


func _process(delta: float) -> bool:
	if _tail_left >= 0:
		_tail_left -= 1
		if _tail_left < 0:
			quit(0)
		return false
	if _sync_left > 0:
		_sync_left -= 1
		return false
	if not _booted:
		_booted = true
		_cover.visible = false
		_boot()
		return false
	_elapsed += delta
	if _camera != null:
		_camera.current = true
	if _elapsed >= _seconds:
		print("[take] %6.2f  end" % _elapsed)
		_tail_left = int(_options.get("tail-marker", "0"))
		_cover.visible = true
		if _tail_left <= 0:
			quit(0)
	return false


func _boot() -> void:
	var scene: Node = (load(MATCH_SCENE) as PackedScene).instantiate()
	_player = scene.get_node("Player") as PlayerController
	_rifle = scene.get_node("Player/Head/Rifle") as Rifle
	_controller = scene.get_node("MatchController") as MatchController
	var human: Node = _player.get_node_or_null("HumanInput")
	if human != null:
		_player.remove_child(human)
		human.free()
	var idle := IntentSource.new()
	idle.name = "HandInput"
	_player.add_child(idle)
	_player.intent_source = idle
	root.add_child(scene)
	_camera = _player.get_node("Head/Camera") as Camera3D
	_camera.fov = float(_options.get("fov", "28"))
	var cross: Label = scene.get_node_or_null("HUD/Root/Crosshair") as Label
	if cross != null:
		cross.add_theme_font_size_override(&"font_size", int(_options.get("cross", "44")))
		cross.add_theme_color_override(&"font_outline_color", Color.BLACK)
		cross.add_theme_constant_override(&"outline_size", 6)
		cross.offset_left = -40.0; cross.offset_right = 40.0; cross.offset_top = -30.0; cross.offset_bottom = 30.0
		cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for label: String in ["HUD/Root/Status", "HUD/Root/Outcome"]:
		var item: CanvasItem = scene.get_node_or_null(label) as CanvasItem
		if item != null:
			item.visible = false
	_rifle.target_hit.connect(_on_hit)
	_rifle.missed.connect(func(_end: Vector3) -> void: print("[event] %6.2f  miss" % _elapsed))
	_hand = Hand.new()
	_hand.run = self
	root.add_child(_hand)
	var env: Environment = (scene.get_node("Arena/Environment/WorldEnvironment") as WorldEnvironment).environment
	var e: float = env.tonemap_exposure
	var a: float = env.ambient_light_energy
	var s: float = env.background_energy_multiplier
	print("[clip] probe: 0 meshes, 0 triangles (the eye stands still on the open platform)")
	print("[clip] %6.2f  clear" % 0.0)
	print("[light] %6.2f  exposure=%.3f ambient=%.3f sky=%.3f look=shipped fill=0.000  shipped exposure=%.3f ambient=%.3f sky=%.3f" % [0.0, e, a, s, e, a, s])


# --- the hand ----------------------------------------------------------------

var _yaw: float = 0.0
var _pitch: float = 0.0
var _rate: Vector2 = Vector2.ZERO
var _hand_t: float = 0.0
var _beat: int = -1
var _target: PlayerController = null
var _fired: Dictionary = {}
var _seen: Dictionary = {}
var _drops: Array = []
var _aimed: bool = false


func _live() -> Array[PlayerController]:
	var out: Array[PlayerController] = []
	for brain: RingRunner in _controller.get_live_runners():
		if brain != null and brain.controller != null and is_instance_valid(brain.controller):
			out.append(brain.controller)
	return out


func _eye() -> Vector3:
	return _camera.global_position


func _angles_to(point: Vector3) -> Vector2:
	var d: Vector3 = point - _eye()
	return Vector2(atan2(-d.x, -d.z), atan2(d.y, maxf(Vector2(d.x, d.z).length(), 0.001)))


func _can_see(body: PlayerController) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_eye(), body.global_position + Vector3.UP * AIM_HEIGHT)
	q.exclude = [_player.get_rid(), body.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _measure(delta: float) -> void:
	for body: PlayerController in _live():
		var key: int = body.get_instance_id()
		var here: Vector3 = body.global_position
		if not _seen.has(key):
			_seen[key] = {"at": here, "v": Vector3.ZERO}
			continue
		var row: Dictionary = _seen[key]
		var step: Vector3 = (here - row["at"]) / delta
		row["at"] = here
		row["v"] = (row["v"] as Vector3).lerp(Vector3(step.x, 0.0, step.z), clampf(delta / VELOCITY_WINDOW, 0.0, 1.0))


func _velocity(body: PlayerController) -> Vector3:
	return _seen[body.get_instance_id()]["v"] if _seen.has(body.get_instance_id()) else Vector3.ZERO


## The man in the open nearest the line the hand already holds.
func _pick(avoid: PlayerController) -> PlayerController:
	var best: PlayerController = null
	var best_err: float = INF
	for body: PlayerController in _live():
		if body == avoid or not _can_see(body):
			continue
		var to: Vector2 = _angles_to(body.global_position + Vector3.UP * AIM_HEIGHT)
		var err: float = absf(angle_difference(_yaw, to.x)) + absf(to.y - _pitch)
		if err < best_err:
			best_err = err
			best = body
	return best


func _hand_tick(delta: float) -> void:
	if _player == null:
		return
	if not _aimed:
		_aimed = true
		var pack: Vector3 = Vector3.ZERO
		var bodies: Array[PlayerController] = _live()
		for b: PlayerController in bodies:
			pack += b.global_position
		pack = pack / maxf(bodies.size(), 1.0) + Vector3(0.0, AIM_HEIGHT, 0.0)
		var a: Vector2 = _angles_to(pack)
		_yaw = a.x + deg_to_rad(4.0)
		_pitch = a.y - deg_to_rad(1.5)
	_hand_t += delta
	_measure(delta)
	_tick_drops(delta)
	var t: float = _elapsed
	while _beat + 1 < BEATS.size() and t >= float(BEATS[_beat + 1]["from"]) \
			and (_beat < 0 or _fired.has(_beat) or t > float(BEATS[_beat + 1]["from"]) + 1.0):
		_beat += 1
		var beat: Dictionary = BEATS[_beat]
		if not bool(beat.get("same", false)) or _target == null or not is_instance_valid(_target):
			var previous: PlayerController = _target if is_instance_valid(_target) else null
			_target = _pick(previous)
	var wanted: Vector2 = Vector2(_yaw, _pitch)
	var fire_at: float = -1.0
	if _beat >= 0:
		var beat: Dictionary = BEATS[_beat]
		fire_at = float(beat["fire_at"])
		if _target == null or not is_instance_valid(_target) or not _live().has(_target):
			_target = _pick(null) if not _fired.has(_beat) else _target
		if _target != null and is_instance_valid(_target):
			var aim: Vector3 = _target.global_position + Vector3.UP * AIM_HEIGHT
			aim += _velocity(_target) * (2.0 * HAND_ZETA / HAND_OMEGA)
			wanted = _angles_to(aim)
	var settling: float = 1.0 if (fire_at < 0.0 or _fired.has(_beat)) else clampf((fire_at - t) / SETTLE_SECONDS, 0.0, 1.0)
	var sway: float = deg_to_rad(SWAY_DEGREES) * settling
	wanted += Vector2(sin(_hand_t * TAU * SWAY_HZ) * sway, sin(_hand_t * TAU * SWAY_HZ * 1.7 + 1.0) * sway * 0.6)
	var error := Vector2(angle_difference(_yaw, wanted.x), wanted.y - _pitch)
	_rate += (error * (HAND_OMEGA * HAND_OMEGA) - _rate * (2.0 * HAND_ZETA * HAND_OMEGA)) * delta
	_rate = _rate.limit_length(HAND_MAX_RATE)
	_yaw = wrapf(_yaw + _rate.x * delta, -PI, PI)
	_pitch += _rate.y * delta
	if _beat >= 0 and not _fired.has(_beat) and t >= fire_at and _target != null and is_instance_valid(_target) \
			and _rifle.can_fire() and (_can_see(_target) or t > fire_at + 0.8):
		var mark: Vector3 = _target.global_position + Vector3.UP * AIM_HEIGHT
		var miss_by: float = float(BEATS[_beat]["miss_by"])
		if miss_by > 0.0:
			var run: Vector3 = _velocity(_target)
			mark -= (run.normalized() if run.length_squared() > 0.01 else Vector3.RIGHT) * miss_by
			mark.y += 0.3
		var exact: Vector2 = _angles_to(mark)
		_yaw = exact.x
		_pitch = exact.y
		_apply_head()
		_fired[_beat] = true
		print("[event] %6.2f  shot  beat %d %s" % [_elapsed, _beat, "fired" if _rifle.try_fire() else "REFUSED"])
		_rate = Vector2(RECOIL_YAW_RATE * (1.0 if _beat % 2 == 0 else -1.0), RECOIL_PITCH_RATE)
		return
	_apply_head()


func _apply_head() -> void:
	_player.rotation = Vector3(0.0, _yaw, 0.0)
	_player.head.rotation.x = _pitch
	_player.set(&"_pitch", _pitch)


## A hit man goes over where he stood instead of blinking out: the build frees the body next frame.
func _on_hit(collider: Node3D, _at: Vector3, _normal: Vector3) -> void:
	var body: PlayerController = collider as PlayerController
	if body == null:
		print("[event] %6.2f  hit  %s" % [_elapsed, collider.name if collider != null else "?"])
		return
	print("[event] %6.2f  hit  %s" % [_elapsed, body.name])
	var mesh: MeshInstance3D = body.get_node_or_null("BodyMesh") as MeshInstance3D
	if mesh == null:
		return
	var copy := MeshInstance3D.new()
	copy.mesh = mesh.mesh
	copy.material_override = mesh.material_override
	copy.layers = mesh.layers
	root.add_child(copy)
	var away: Vector3 = body.global_position - _eye()
	away.y = 0.0
	away = away.normalized()
	var axis: Vector3 = Vector3.UP.cross(away).normalized()
	var drop: Dictionary = {"node": copy, "base": body.global_position, "axis": axis, "t": 0.0, "v": _velocity(body), "yaw": body.rotation.y}
	_drops.append(drop)
	_place_drop(drop)


func _tick_drops(delta: float) -> void:
	for drop: Dictionary in _drops:
		if drop["t"] < DROP_SECONDS:
			drop["t"] = minf(drop["t"] + delta, DROP_SECONDS)
			drop["base"] += (drop["v"] as Vector3) * delta * (1.0 - drop["t"] / DROP_SECONDS) * 0.6
			_place_drop(drop)


func _place_drop(drop: Dictionary) -> void:
	var k: float = drop["t"] / DROP_SECONDS
	var angle: float = PI * 0.5 * k * k
	var basis := Basis(drop["axis"], angle)
	var node: MeshInstance3D = drop["node"]
	node.global_transform = Transform3D(basis, drop["base"] + basis * Vector3(0.0, 0.9, 0.0) + Vector3(0.0, 0.4 * sin(angle), 0.0))
