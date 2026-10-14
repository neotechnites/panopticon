extends "res://tools/capture/stages/trailer_finish_marble.gd"

## trailer_finale_marble (v27 g1/g2): the corridor sprint into the portal, then the game's finale: in the tower room
## the finisher runs at the guard, scoped at his window with his back to the room, and shoves him out of the open tower;
## the game's own cinematic follows the throw. --pov=runner is the finisher's eyes, --pov=guard the guard's (his scope,
## then the cinematic every machine cuts to). Ryan v27: "Ending: the guard getting shoved out of the tower, including the
## guard's POV of being flung". Dials: window (126: the guard's window), look (126,47: where his scope rests on the ring),
## wait (0.35 s in the room before he goes), from/pace as trailer_finish_marble.

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

var _hand: Node = null
var _arrived_at: float = -1.0
var _carried: Node3D = null
var _carry_part: PhysicalBone3D = null
var _carry_offset: Transform3D = Transform3D.IDENTITY


## The shipped finale: no rule of trailer_finish's (a finisher rifle, a 1.2 s beat) applies.
func tune_rules(_rules: MatchRules) -> void:
	pass


func before_start() -> void:
	super.before_start()
	controller().kill_beat_started.connect(
		func(guard: MatchParticipant, seconds: float, throw: Vector3) -> void:
			say("finale shove: %s thrown at %v for %.1f s, tower open %s" % [guard.body.name, throw, seconds, controller().is_tower_open()])
			_carry_the_rifle(guard.body)
	)


func tick(_delta: float) -> void:
	if _carried != null and is_instance_valid(_carried):
		_carried.global_transform = _carry_part.global_transform * _carry_offset
		if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 15 == 0:
			say("rifle at %v" % _carried.global_position)
	if OS.has_environment("STAGE_DEBUG") and _runner != null and Engine.get_physics_frames() % 15 == 0:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic if _guard != null else null
		say("at %.1f deg r %.2f y %.2f; scope asked %s full %s" % [LIB.bearing_of(_runner.global_position), LIB.radius_of(_runner.global_position), _runner.global_position.y, optic != null and optic.is_zoom_requested(), optic != null and optic.is_fully_zoomed()])
	# After the cast, as every scope stage does: the tape only writes down a hand raised on bodies it has collected.
	if _guard == null and _runner != null and elapsed() > 0.75:
		_post_the_guard()
	if _runner == null or _armed or _driver == null or int(_driver.get("_index")) < 5:
		return
	if _runner.global_position.distance_to(LIB.ring_point(PORTAL_DEG, PORTAL_R, 0.0)) > ARRIVE_METRES:
		return
	_armed = true
	_arrived_at = elapsed()
	var participant: MatchParticipant = LIB.participant_of(controller(), _runner)
	controller().call("_arm_the_finisher", participant)
	# Through the portal he is in the room behind the guard: a breath, then straight at him.
	_driver.retarget([
		{"do": "hold", "seconds": float(option("wait", 0.35))},
		{"do": "chase", "victim": _guard, "range": float(option("reach", 1.6)), "speed": 1.0, "timeout": 4.0},
		{"do": "hold", "seconds": 60.0},
	])
	say("arrived at %.2f s; finisher armed %s; after the guard (%s)" % [_arrived_at, controller().get_finisher() != null, _guard.name if _guard != null else "none"])


## The guard at his window, scoped on the ring below, his back to the room; he never fires.
func _post_the_guard() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null or shooter.controller == _runner:
		return
	if shooter.profile != null:
		LIB.dead_shooter(shooter.profile)
	_guard = shooter.controller
	LIB.guard_to_window(_guard, float(option("window", 126.0)), 5.6)
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.park = LIB.polar(String(option("look", "126,47")), LIB.ring_point(126.0, 47.0)) + Vector3.UP * 1.0
	_hand.start_at = 1000.0
	say("the guard (%s) at the %.0f window, scoped on the ring" % [_guard.name, float(option("window", 126.0))])


func on_shove(shover: MatchParticipant, victim: MatchParticipant) -> void:
	say("shove %s -> %s" % [shover.body.name, victim.body.name])


## The rifle hangs off the held body, which the kill beat freezes at the window while the ragdoll flies; ride it on the
## ragdoll's nearest part instead, so it goes out with the guard (Ryan: "when the guard gets pushed, the sniper stay").
func _carry_the_rifle(body: PlayerController) -> void:
	var drawn: PrisonerAvatar = PrisonerAvatar.of(body)
	var rag: Object = drawn.get("_ragdoll") if drawn != null else null
	var parts: Array = rag.get("_bones") if rag != null else []
	var gun: Node3D = null
	for child: Node in body.head.get_children():
		if child is Rifle:
			gun = child as Node3D
	if parts.is_empty() or gun == null:
		say("rifle carry: no ragdoll or no rifle on the guard")
		return
	var nearest: float = INF
	for part: PhysicalBone3D in parts:
		var gap: float = part.global_position.distance_to(gun.global_position)
		if gap < nearest:
			nearest = gap
			_carry_part = part
	_carry_offset = _carry_part.global_transform.affine_inverse() * gun.global_transform
	gun.top_level = true
	_carried = gun
	say("rifle carry: the rifle rides the guard's ragdoll (%s, %.2f m off) out of the tower" % [_carry_part.name, nearest])
