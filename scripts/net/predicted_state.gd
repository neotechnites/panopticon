class_name PredictedState
extends RefCounted

## Everything a client's own body predicts, as one flat f32 struct (Quake 3's playerState_t): the
## host sends its exact values (DESIGN 3.4 OWNER) and reconciliation restores them whole (DESIGN 7).

const POSITION: int = 0
const VELOCITY: int = 3
const YAW: int = 6
const VIEW_BASE: int = 7
const LOCKED: int = 8
const POWER_ACTIVE: int = 9
const POWER_REMAINING: int = 10
const POWER_COOLDOWN: int = 11
const MOTION: int = 12
const WEAPON: int = MOTION + PlayerController.MOTION_STATE_SIZE
const SIZE: int = WEAPON + Rifle.GATE_STATE_SIZE

var values: PackedFloat32Array = PackedFloat32Array()
var _motion: PackedFloat32Array = PackedFloat32Array()
var _gate: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	values.resize(SIZE)
	_motion.resize(PlayerController.MOTION_STATE_SIZE)
	_gate.resize(Rifle.GATE_STATE_SIZE)


func clear() -> void:
	values.fill(0.0)


func copy_from(other: PredictedState) -> void:
	for i: int in SIZE:
		values[i] = other.values[i]


func equals(other: PredictedState) -> bool:
	return values == other.values


func get_position() -> Vector3:
	return Vector3(values[POSITION], values[POSITION + 1], values[POSITION + 2])


## Read [param body]'s predicted state, its power's and the rifle it holds ([param weapon], or null).
func capture(body: PlayerController, weapon: Rifle) -> void:
	_put3(POSITION, body.global_position)
	_put3(VELOCITY, body.velocity)
	values[YAW] = body.rotation.y
	values[VIEW_BASE] = body.view_base
	values[LOCKED] = 1.0 if body.movement_locked else 0.0
	var power: RunnerPower = RunnerPower.of(body)
	values[POWER_ACTIVE] = float(power.get_active()) if power != null else 0.0
	values[POWER_REMAINING] = power.get_predicted_remaining() if power != null else 0.0
	values[POWER_COOLDOWN] = power.get_cooldown_remaining() if power != null else 0.0
	body.capture_motion_state(_motion)
	for i: int in _motion.size():
		values[MOTION + i] = _motion[i]
	if weapon != null:
		weapon.capture_gate(_gate)
	else:
		_gate.fill(0.0)
	for i: int in _gate.size():
		values[WEAPON + i] = _gate[i]


## Put this state on [param body], its power and [param weapon] (when it holds one).
func restore(body: PlayerController, weapon: Rifle) -> void:
	body.global_position = _get3(POSITION)
	body.velocity = _get3(VELOCITY)
	body.rotation.y = values[YAW]
	body.view_base = values[VIEW_BASE]
	for i: int in _motion.size():
		_motion[i] = values[MOTION + i]
	body.restore_motion_state(_motion)
	var power: RunnerPower = RunnerPower.of(body)
	if power != null:
		power.restore_predicted(int(values[POWER_ACTIVE]), values[POWER_REMAINING], values[POWER_COOLDOWN])
	body.movement_locked = values[LOCKED] > 0.5
	if weapon != null:
		for i: int in _gate.size():
			_gate[i] = values[WEAPON + i]
		weapon.restore_gate(_gate)


func _put3(at: int, v: Vector3) -> void:
	values[at] = v.x
	values[at + 1] = v.y
	values[at + 2] = v.z


func _get3(at: int) -> Vector3:
	return Vector3(values[at], values[at + 1], values[at + 2])
