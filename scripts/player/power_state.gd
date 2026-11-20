class_name PowerState
extends RefCounted

## A runner power's whole state (DESIGN 9): stepped by commands on the deciding machine and the owner's
## prediction, taken from the snapshot everywhere else, and the only thing its visuals are drawn from.

## Floats [method capture] writes: the owner's predicted part, without the host entity's pose.
const PREDICTED_SIZE: int = 8
## Activations wrap here: a record names which activation it describes (a prediction key).
const SERIAL_MODULUS: int = 4

## The [enum MatchRules.RunnerAbility] of the running or the last activation; kept while it cools.
var which: int = 0
var active: bool = false
## Its host entity is out in the world: a hologram running, a cat thrown.
var out: bool = false
## The cat's fuse is lit.
var cooking: bool = false
var serial: int = 0
## Ticks (commands) left of the power (the fuse, for the cat) and of the cooldown after it: whole
## numbers, so the host's count and the owner's replay of it are the same number.
var remaining_ticks: int = 0
var cooldown_ticks: int = 0
## Where the activation put it: the shield's centre, the hologram's spawn. Predicted.
var place_position: Vector3 = Vector3.ZERO
var place_yaw: float = 0.0
## The host entity's pose while [member out]; never predicted.
var pose_position: Vector3 = Vector3.ZERO
var pose_yaw: float = 0.0
var pose_velocity: Vector3 = Vector3.ZERO


func clear() -> void:
	which = 0
	active = false
	out = false
	cooking = false
	serial = 0
	remaining_ticks = 0
	cooldown_ticks = 0
	place_position = Vector3.ZERO
	place_yaw = 0.0
	pose_position = Vector3.ZERO
	pose_yaw = 0.0
	pose_velocity = Vector3.ZERO


func copy_from(other: PowerState) -> void:
	which = other.which
	active = other.active
	out = other.out
	cooking = other.cooking
	serial = other.serial
	remaining_ticks = other.remaining_ticks
	cooldown_ticks = other.cooldown_ticks
	place_position = other.place_position
	place_yaw = other.place_yaw
	pose_position = other.pose_position
	pose_yaw = other.pose_yaw
	pose_velocity = other.pose_velocity


## The power running now, or NONE.
func running() -> int:
	return which if active else 0


## True while [member remaining_ticks] counts down: every running power but an unlit fuse.
func is_timed() -> bool:
	return active and (RunnerPower.DEFS[which][&"clock"] != RunnerPower.Clock.FUSE or cooking)


func get_remaining() -> float:
	return float(remaining_ticks) / float(NetCodec.TICK_RATE)


func get_cooldown() -> float:
	return float(cooldown_ticks) / float(NetCodec.TICK_RATE)


## Where the world sees it: the entity's pose while out, else the placed anchor while running.
func anchor_position() -> Vector3:
	return pose_position if out else (place_position if active else Vector3.ZERO)


func anchor_yaw() -> float:
	return pose_yaw if out else (place_yaw if active else 0.0)


## The predicted part into [param values] from [param at], exact (the OWNER block).
func capture(values: PackedFloat32Array, at: int) -> void:
	values[at] = float(which)
	values[at + 1] = float(int(active) | (int(out) << 1) | (int(cooking) << 2) | (serial << 3))
	values[at + 2] = float(remaining_ticks)
	values[at + 3] = float(cooldown_ticks)
	values[at + 4] = place_position.x
	values[at + 5] = place_position.y
	values[at + 6] = place_position.z
	values[at + 7] = place_yaw


## Take the predicted part back from [param values] at [param at]; the pose is left as it is.
func restore(values: PackedFloat32Array, at: int) -> void:
	which = int(values[at])
	var flags: int = int(values[at + 1])
	active = (flags & 1) != 0
	out = (flags & 2) != 0
	cooking = (flags & 4) != 0
	serial = (flags >> 3) % SERIAL_MODULUS
	remaining_ticks = int(values[at + 2])
	cooldown_ticks = int(values[at + 3])
	place_position = Vector3(values[at + 4], values[at + 5], values[at + 6])
	place_yaw = values[at + 7]


## This state as [param record] says it stood: a body this machine draws and does not simulate.
func take_record(record: PlayerState) -> void:
	which = record.ability
	active = record.power_active
	out = record.power_out
	cooking = record.power_cooking
	serial = record.power_serial
	cooldown_ticks = record.ticks_to(record.cooldown_end_tick)
	if is_timed():
		remaining_ticks = record.ticks_to(record.ability_end_tick)
	else:
		remaining_ticks = RunnerPower.ticks_of(RunnerPower.duration_of(which, null)) if active else 0
	if out:
		pose_position = record.anchor_position
		pose_yaw = record.anchor_yaw
		pose_velocity = record.anchor_velocity
	else:
		place_position = record.anchor_position
		place_yaw = record.anchor_yaw
		pose_velocity = Vector3.ZERO


## Write this state into [param record] at host tick [param tick], before quantisation.
func sample(record: PlayerState, tick: int) -> void:
	record.ability = which
	record.power_active = active
	record.power_out = out
	record.power_cooking = cooking
	record.power_serial = serial
	record.ability_end_tick = NetCodec.end_tick(tick, get_remaining()) if is_timed() else 0
	record.cooldown_end_tick = NetCodec.end_tick(tick, get_cooldown())
	record.anchor_position = anchor_position()
	record.anchor_yaw = anchor_yaw()
