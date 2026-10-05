extends "res://tools/capture/stages/stage.gd"

## trailer_marble_column (v11 10a/10b): two prisoners side by side behind a wall of three columns, hidden from the 216
## window; one shoves the other along the ring out into the open and the guard drops him. Two POVs.
## Columns are this shot's own (spawn_columns), never the map's: three at r 47.5, shafts touching (1.04 m, 1.2545 deg).
## v11: the 216 section, 90 deg on from 5b's columns at 126 (lamps and fills repeat every 90: the v8 frame, turned).
## Shadow: the 3.12 m shaft wall hides ~1.6 m each side of the window at r 48.6; victim 0.45 m along the ring (+), shover 0.4 m
## back (-), 0.2 m further out; the swing runs 5 deg inboard of the ring and lands him past the wall in the open.
## Dials: victim (216.531,48.55), pov (215.53,48.75), shove (clip s, 2.7), impulse (8.5), up (4.0), lead (0.7: he stops dead on landing), kick (0.3), edge (217.1).
## v8 (Ryan): "he needs to get shot WHILE he's being shoved out": no recovery; the squeeze the first frame he is in the open.

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const COLUMN_SCENE: String = "res://maps/marble/models/marble_column.glb"
const COLUMN_DEGREES: Array[float] = [214.7455, 216.0, 217.2545]
const COLUMN_R: float = 47.5
## The window the guard stands at: centred between the tower room's columns at 115 and 137.5.
const WINDOW: float = 216.0

var _victim: PlayerController = null
var _pov: PlayerController = null
var _victim_driver: Node = null
var _hand: Node = null
var _guard: PlayerController = null
var _shoved: bool = false
var _shoved_at: float = 0.0
var _exposed: bool = false


## Marble columns at [param degrees] on the inner edge for one shot only; the map scene is untouched.
static func spawn_columns(map: Node, degrees: Array[float]) -> void:
	var packed: PackedScene = load(COLUMN_SCENE) as PackedScene
	if map == null or packed == null:
		printerr("[stage] no marble map or no column; nothing spawned")
		return
	for deg: float in degrees:
		var column: Node3D = packed.instantiate() as Node3D
		column.name = "ClipColumn%d" % int(deg * 10.0)
		map.add_child(column)
		column.global_position = LIB.ring_point(deg, COLUMN_R, 0.0)
		column.rotation = Vector3(0.0, -deg_to_rad(deg), 0.0)


func bots() -> int:
	return 2


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"marble"
	rules.shove_impulse = float(option("impulse", 8.5))
	rules.shove_up_impulse = float(option("up", 4.0))
	rules.guard_projectile_speed = 0.0
	rules.base_reload_seconds = 1.0
	# The shipped rule: a shot man plays his death and lies where he fell, not parked out of the world.
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
	spawn_columns(controller().arena if controller().arena != null else clip.root, COLUMN_DEGREES)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var v: Vector3 = LIB.polar(String(option("victim", "216.531,48.55")), LIB.ring_point(216.531, 48.55))
	var p: Vector3 = LIB.polar(String(option("pov", "215.53,48.75")), LIB.ring_point(215.53, 48.75))
	var v_deg: float = LIB.bearing_of(v)
	var p_deg: float = LIB.bearing_of(p)
	_victim = runners[0].controller
	_pov = runners[1].controller
	var tower: Vector3 = LIB.ring_point(WINDOW, 5.6, 6.0)
	# The victim: in the column's shadow, half turned to peek round it at the tower; a slow sway.
	var v_face: Vector3 = (-LIB.radial_at(v_deg) * 0.75 + LIB.tangent_at(v_deg) * 0.45).normalized()
	_victim_driver = drive(runners[0], [
		{"do": "place", "at": v + Vector3.UP * 0.1, "face": v_face},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 200.0, "gain": 8.0},
		{"do": "hold", "seconds": 0.9, "sway": 6.0, "period": 2.9, "look_at": tower},
		{"do": "glance", "right": -24.0, "pitch": -3.0, "seconds": 0.5},
		{"do": "hold", "seconds": 0.5, "look_down": 2.0},
		{"do": "glance", "right": 30.0, "pitch": 4.0, "seconds": 0.45},
		{"do": "hold", "seconds": 60.0, "sway": 4.0, "period": 2.3},
	], 0, "ClipColumnVictim")
	# The rider: tucked in behind him, eyes on the column and the edge of it, a look at him,
	# then square up and shove him along the ring out of its shadow into the gap.
	var p_face: Vector3 = (LIB.tangent_at(p_deg) * 0.34 - LIB.radial_at(p_deg) * 0.94).normalized()
	var at_him: Vector3 = LIB.toward(p, v)
	var turn: float = _right_of(p_face, at_him)
	LIB.hide_from_the_rifle(_pov)
	# The swing goes along the ring, 5 deg inboard to keep him in the cone; the edge is r 46.7, he lands ~r 48.
	var swing: Vector3 = (LIB.tangent_at(v_deg) * cos(deg_to_rad(5.0)) - LIB.radial_at(v_deg) * sin(deg_to_rad(5.0))).normalized()
	var square: float = _right_of(p_face, swing)
	drive(runners[1], [
		{"do": "place", "at": p + Vector3.UP * 0.1, "face": p_face},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": 0.35},
		{"do": "glance", "right": -9.0, "pitch": 6.0, "seconds": 0.45},
		{"do": "hold", "seconds": 0.3},
		{"do": "glance", "right": turn * 0.6 + 9.0, "pitch": -7.0, "seconds": 0.4},
		# v26 (Ryan): "a random cut for nor eason before the player gets shoved": the square-up was a 45 deg flick in six
		# frames. His head comes round onto him over half a second, eased, and the shove lands as it arrives.
		{"do": "until", "t": float(option("shove", 2.7)) - float(option("square_lead", 0.85))},
		{"do": "glance", "right": square - turn * 0.6, "pitch": -1.0, "seconds": 0.5, "smooth": true},
		{"do": "shove", "face": swing},
		{"do": "hold", "seconds": 0.25},
		{"do": "glance", "right": 18.0, "pitch": -2.0, "seconds": 0.4},
		{"do": "hold", "seconds": 0.5},
		{"do": "glance", "right": -40.0, "pitch": 7.0, "seconds": 0.5},
		{"do": "hold", "seconds": 60.0, "fidget": true},
	], 1, "ClipColumnShover")
	for index: int in range(2, runners.size()):
		drive(runners[index], [{"do": "place", "at": LIB.ring_point(250.0, 52.0, 0.1)}, {"do": "hold", "seconds": 60.0}], index)
		LIB.hide_from_the_rifle(runners[index].controller)
	victim_body(_victim)
	stage_body(_pov)
	say("trailer_marble_column: %s behind the %.1f column, %s behind him" % [_victim.name, v_deg, _pov.name])
	return true


## Degrees to the body's right that turn [param from] onto [param to] (a positive turn is right).
static func _right_of(from: Vector3, to: Vector3) -> float:
	var yaw_from: float = atan2(-from.x, -from.z)
	var yaw_to: float = atan2(-to.x, -to.z)
	return -rad_to_deg(wrapf(yaw_to - yaw_from, -PI, PI))


func tick(_delta: float) -> void:
	if _victim == null:
		return
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 15 == 0 and is_instance_valid(_victim):
		say("victim %.1f deg r %.2f y %.2f; pov %.1f r %.2f" % [LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position), _victim.global_position.y, LIB.bearing_of(_pov.global_position), LIB.radius_of(_pov.global_position)])
	if _hand == null:
		_raise_the_hand()
		return
	_hand.hold_scope = elapsed() >= float(option("zoom", 1.0))
	if not _hand.hold_scope:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(false)
	# Exposed: his shoulder clears the wall's edge (edge, deg); the round is already led into the open.
	if _shoved and not _exposed and is_instance_valid(_victim) and LIB.bearing_of(_victim.global_position) >= float(option("edge", 217.1)):
		_exposed = true
		_hand.beats[0]["fire_at"] = elapsed() - _hand.start_at
		say("victim exposed %.2f s after the shove at %.1f deg r %.2f; squeeze now" % [elapsed() - _shoved_at, LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position)])


## The guard at the 216 window, a hand resting on the column he hides behind.
func _raise_the_hand() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", WINDOW)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.beats.append({"body": _victim, "seconds": 100.0, "fire_at": -1.0, "watch": true, "lead": float(option("lead", 0.7)), "now": true, "kick": float(option("kick", 0.3))})
	_hand.park = LIB.ring_point(218.6, 48.6, 1.3)
	_hand.start_at = elapsed() + 0.3
	if OS.has_environment("STAGE_DEBUG") and controller().rifle != null:
		controller().rifle.target_hit.connect(func(c: Node3D, at: Vector3, _n: Vector3) -> void:
			say("round struck %s at %.1f deg r %.2f y %.2f" % [c.name if c != null else "?", LIB.bearing_of(at), LIB.radius_of(at), at.y]))
		controller().rifle.projectile_launched.connect(func(o: Vector3, d: Vector3, sp: float) -> void:
			say("launched from r %.2f y %.2f dir %v speed %.0f" % [LIB.radius_of(o), o.y, d, sp]))


func on_shove(_shover: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved or victim.body != _victim:
		return
	_shoved = true
	_shoved_at = elapsed()
	if _victim_driver != null:
		# Still stumbling from the push when the round arrives: no input, no recovery.
		_victim_driver.retarget([{"do": "hold", "seconds": 60.0}])
	say("shove landed on %s" % victim.body.name)


func on_hit(collider: Node3D) -> void:
	say("round hit %s" % (collider.name if collider != null else "nothing"))


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.2f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])


func lens(_delta: float) -> bool:
	return false
