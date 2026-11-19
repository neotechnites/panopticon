class_name PlayerState
extends RefCounted

## One body's record at one host tick, at wire precision (DESIGN 3.4 BODIES): what every machine
## draws of it. Held quantised, so a decoded record equals the host's bit for bit and can be a baseline.
## Timers are end ticks (0 = none), resolved on [member tick]. Reused rather than reallocated.

## Which seat this describes, not which peer: a bot's seat has no peer.
var seat_index: int = 0
## The host tick this was sampled on: the snapshot's.
var tick: int = 0

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
## Body yaw and head pitch, radians.
var yaw: float = 0.0
var pitch: float = 0.0
## [member PlayerController.view_base]: the yaw the match turned this body by (Quake 3's delta_angles).
var view_base: float = 0.0

var on_floor: bool = false
var sliding: bool = false
var crouching: bool = false
var emoting: bool = false
var emote_alt: bool = false
var is_armed: bool = false
var is_finisher: bool = false
## Edges as counters, so a dropped snapshot loses none: jumps, shove swings, and placements (Quake 3's
## EF_TELEPORT_BIT: a body is never interpolated across a change of it).
var jump_counter: int = 0
var shove_counter: int = 0
var placed_counter: int = 0

## Hit points, 0-255.
var health: int = 0

## The power: which [enum MatchRules.RunnerAbility], whether its hologram is out, and its two end ticks.
var ability: int = 0
var decoy_alive: bool = false
var ability_end_tick: int = 0
var cooldown_end_tick: int = 0
## Where the power stands in the world while it has a place: the shield's centre, the hologram's pose.
var has_anchor: bool = false
var anchor_position: Vector3 = Vector3.ZERO
var anchor_yaw: float = 0.0
## The anchor's speed between the two worlds a blend drew it from, m/s; never on the wire.
var anchor_velocity: Vector3 = Vector3.ZERO

## The timed speed boost: multiplier in tenths and its end tick.
var boost_multiplier: float = 1.0
var boost_end_tick: int = 0

## The rifle this body holds: its [enum Rifle.State], scoped, when the state ends, and the charge (0-255).
var weapon_state: int = 0
var weapon_scoped: bool = false
var weapon_end_tick: int = 0
var weapon_charge: int = 0


func clear() -> void:
	seat_index = 0
	tick = 0
	position = Vector3.ZERO
	velocity = Vector3.ZERO
	yaw = 0.0
	pitch = 0.0
	view_base = 0.0
	on_floor = false
	sliding = false
	crouching = false
	emoting = false
	emote_alt = false
	is_armed = false
	is_finisher = false
	jump_counter = 0
	shove_counter = 0
	placed_counter = 0
	health = 0
	ability = 0
	decoy_alive = false
	ability_end_tick = 0
	cooldown_end_tick = 0
	has_anchor = false
	anchor_position = Vector3.ZERO
	anchor_yaw = 0.0
	anchor_velocity = Vector3.ZERO
	boost_multiplier = 1.0
	boost_end_tick = 0
	weapon_state = 0
	weapon_scoped = false
	weapon_end_tick = 0
	weapon_charge = 0


func copy_from(other: PlayerState) -> void:
	seat_index = other.seat_index
	tick = other.tick
	position = other.position
	velocity = other.velocity
	yaw = other.yaw
	pitch = other.pitch
	view_base = other.view_base
	on_floor = other.on_floor
	sliding = other.sliding
	crouching = other.crouching
	emoting = other.emoting
	emote_alt = other.emote_alt
	is_armed = other.is_armed
	is_finisher = other.is_finisher
	jump_counter = other.jump_counter
	shove_counter = other.shove_counter
	placed_counter = other.placed_counter
	health = other.health
	ability = other.ability
	decoy_alive = other.decoy_alive
	ability_end_tick = other.ability_end_tick
	cooldown_end_tick = other.cooldown_end_tick
	has_anchor = other.has_anchor
	anchor_position = other.anchor_position
	anchor_yaw = other.anchor_yaw
	anchor_velocity = other.anchor_velocity
	boost_multiplier = other.boost_multiplier
	boost_end_tick = other.boost_end_tick
	weapon_state = other.weapon_state
	weapon_scoped = other.weapon_scoped
	weapon_end_tick = other.weapon_end_tick
	weapon_charge = other.weapon_charge


## Seconds from [member tick] to [param end_tick], never negative; 0 for none.
func seconds_to(end_tick: int) -> float:
	if end_tick == 0:
		return 0.0
	return maxf(float(NetCodec.tick_delta(tick, end_tick)), 0.0) / float(NetCodec.TICK_RATE)


func ability_remaining() -> float:
	return seconds_to(ability_end_tick)


func cooldown_remaining() -> float:
	return seconds_to(cooldown_end_tick)


func boost_remaining() -> float:
	return seconds_to(boost_end_tick)


## Blend towards [param to] by [param weight] into this record: motion and the anchor slide, angles
## the short way round, every fact from the nearer end; across a placement nothing slides.
func interpolate_from(from: PlayerState, to: PlayerState, weight: float) -> void:
	var t: float = clampf(weight, 0.0, 1.0)
	if from.placed_counter != to.placed_counter:
		t = 1.0
	copy_from(to)
	position = from.position.lerp(to.position, t)
	velocity = from.velocity.lerp(to.velocity, t)
	yaw = lerp_angle(from.yaw, to.yaw, t)
	pitch = lerp_angle(from.pitch, to.pitch, t)
	anchor_velocity = Vector3.ZERO
	if from.has_anchor and to.has_anchor and from.ability == to.ability:
		anchor_position = from.anchor_position.lerp(to.anchor_position, t)
		anchor_yaw = lerp_angle(from.anchor_yaw, to.anchor_yaw, t)
		var ticks: int = NetCodec.tick_delta(from.tick, to.tick)
		if ticks > 0 and from.placed_counter == to.placed_counter:
			anchor_velocity = (to.anchor_position - from.anchor_position) * float(NetCodec.TICK_RATE) / float(ticks)
	if t < 0.5:
		tick = from.tick
		on_floor = from.on_floor


## Whether every field equals [param other]'s: records are held quantised, so this is the wire's equality.
func equals(other: PlayerState) -> bool:
	return NetCodec.body_changes(self, other) == 0 and seat_index == other.seat_index
