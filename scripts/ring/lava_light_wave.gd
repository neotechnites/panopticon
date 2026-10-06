@tool
class_name LavaLightWave
extends Node3D

## Swells the lava's real lights (children and [member also_wave]) with lava_wave.gdshaderinc's own swell
## at each light, plus a slow per-light phase; it runs in the editor too, resting the lights for a save.

## The shader's wave speed in rad/s ([code]speed[/code] in lava_wave.gdshaderinc).
const SPEED: float = 0.55
## The shader's flat-lava levels: river and cracks, the S5 shelf, the sea.
const RIVER_Y: float = 22.7
const SHELF_Y: float = 28.8
const SEA_Y: float = -11.05
## The shader wraps TIME at this many seconds (rendering/limits/time/time_rollover_secs).
const TIME_ROLLOVER: float = 3600.0

## Energy swing either way, as a fraction of the light's own energy.
@export_range(0.0, 0.3, 0.01) var energy_swing: float = 0.12
## Metres a light over flat lava rides up and down with the swell.
@export_range(0.0, 1.0, 0.05) var bob_metres: float = 0.35
## Lights elsewhere in the scene that swell too (the shadowed pit fires).
@export var also_wave: Array[NodePath] = []

var _lights: Array[Light3D] = []
var _rest: PackedVector3Array = PackedVector3Array()
var _base_energy: PackedFloat32Array = PackedFloat32Array()
var _base_y: PackedFloat32Array = PackedFloat32Array()
var _phase: PackedFloat32Array = PackedFloat32Array()
var _flat: PackedFloat32Array = PackedFloat32Array()
var _bob: PackedFloat32Array = PackedFloat32Array()
## The energy each light was last given, so an inspector edit in the editor becomes its new rest.
var _set_energy: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_collect(self)
	for path: NodePath in also_wave:
		var light: Light3D = get_node_or_null(path) as Light3D
		if light != null:
			_add(light, false)


func _collect(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Light3D:
			_add(child as Light3D, true)
		_collect(child)


func _add(light: Light3D, bobs: bool) -> void:
	var at: Vector3 = light.global_position
	_lights.append(light)
	_rest.append(at)
	_base_energy.append(light.light_energy)
	_base_y.append(light.position.y)
	# Deterministic from position, so neighbours never pulse together.
	_phase.append(fposmod(at.x * 12.9898 + at.z * 78.233, TAU))
	_flat.append(maxf(maxf(_flat_w(at.y, RIVER_Y), _flat_w(at.y, SHELF_Y)), _flat_w(at.y, SEA_Y)))
	_bob.append(bob_metres if bobs else 0.0)
	_set_energy.append(light.light_energy)


## The shader's flat_w, widened for a light hung up to 3 m over the level: 1 there, 0 on a fall.
static func _flat_w(y: float, level: float) -> float:
	return 1.0 - smoothstep(3.0, 4.0, absf(y - level))


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_rest_lights()
		set_process(false)
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		set_process(true)


## Every light back at its rest energy and height, as the scene stores it.
func _rest_lights() -> void:
	for i: int in _lights.size():
		_lights[i].light_energy = _base_energy[i]
		_set_energy[i] = _base_energy[i]
		if _bob[i] > 0.0:
			_lights[i].position.y = _base_y[i]


func _process(_delta: float) -> void:
	var now: float = fmod(Time.get_ticks_msec() * 0.001, TIME_ROLLOVER)
	var t: float = now * SPEED
	for i: int in _lights.size():
		var light: Light3D = _lights[i]
		if not is_equal_approx(light.light_energy, _set_energy[i]):
			_base_energy[i] = light.light_energy   # moved by hand in the editor
		var at: Vector3 = _rest[i]
		var r: float = Vector2(at.x, at.z).length()
		# lava_wave.gdshaderinc: the flat swell, and the falls' rings running down the face.
		var sr: float = 0.6 * sin(0.4 * r + t) + 0.4 * sin(0.2 * at.x + 0.27 * at.z + 0.7 * t)
		var sf: float = 0.75 * sin(0.45 * at.y + 1.3 * t) + 0.25 * sin(0.3 * (at.x - at.z) + 0.6 * t)
		var fl: float = _flat[i]
		var swell: float = fl * sr + (1.0 - fl) * sf
		var own: float = sin(0.9 * t + _phase[i])
		light.light_energy = _base_energy[i] * (1.0 + energy_swing * (0.75 * swell + 0.25 * own))
		_set_energy[i] = light.light_energy
		if _bob[i] > 0.0:
			light.position.y = _base_y[i] + _bob[i] * fl * sr
