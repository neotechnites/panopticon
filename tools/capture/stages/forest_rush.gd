extends "res://tools/capture/stages/haters_forest_shove.gd"

## forest_rush: short 11 "how its going" in the forest, ONE take filmed twice off one tape: three on the pit lane
## (haters_forest_shove's run, the POV shoves the pit-side man over the lip); the hand at the 84 deg window drops the lead
## running ahead of them before the shove, then the shover after it. Probe (eye 84:4.4:5.9, forest): r 48.5-50.5 open 78-86
## and 90-92 deg, trunks at 76, 88, 94 (r 50.5), 100. Dials (--set=): haters_forest_shove's, and guard_deg (84), guard_r (4.4),
## scope_fov (24), hand_at (0.8), drop_lead (2.4), drop_pov (3.75), reload (0.45).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

var _lead: PlayerController = null
var _hand: Node = null


func tune_rules(rules: MatchRules) -> void:
	super(rules)
	rules.base_reload_seconds = float(option("reload", 0.45))
	rules.guard_projectile_speed = 0.0
	rules.bots_shove_rivals = false
	# A shot man plays his death and lies where he fell, never a ghost.
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func cast(runners: Array[RunnerBrain]) -> bool:
	if not super(runners):
		return false
	_lead = runners[2].controller
	return true


func tick(delta: float) -> void:
	super(delta)
	if OS.has_environment("STAGE_DEBUG") and _lead != null and Engine.get_physics_frames() % 6 == 0:
		say("lead %.1f deg r %.2f" % [LIB.bearing_of(_lead.global_position), LIB.radius_of(_lead.global_position)])
	if _lead == null or _hand != null:
		return
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	var guard: PlayerController = shooter.controller
	LIB.guard_to_window(guard, float(option("guard_deg", 84.0)), float(option("guard_r", 4.4)))
	LIB.open_the_scope(guard, 0.74)
	var optic: WeaponOptic = guard.get_node_or_null(^"Optic") as WeaponOptic
	var fov: float = float(option("scope_fov", 24.0))
	if fov > 0.0 and optic != null and optic.profile != null and optic.base_fov > 0.0:
		optic.profile.zoom_factor = clampf(fov / optic.base_fov, 0.05, 1.0)
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(guard, controller(), elapsed())
	_hand.start_at = float(option("hand_at", 0.8))
	var drop_lead: float = float(option("drop_lead", 2.4))
	var drop_pov: float = float(option("drop_pov", 3.75))
	# The lead to his squeeze and a beat on him; the swing back onto the pair at the lip; the shover after his shove.
	var lead_end: float = drop_lead + 0.3
	_hand.beats.append({"body": _lead, "seconds": lead_end - _hand.start_at, "fire_at": drop_lead - _hand.start_at, "watch": true, "clear": true})
	_hand.beats.append({"body": _pov, "seconds": drop_pov + 0.6 - lead_end, "fire_at": drop_pov - lead_end, "watch": true, "omega": 8.0})
	_hand.park = LIB.ring_point(80.0, 50.0, 1.0)
	say("forest_rush: hand on %s at the %.0f deg window from %.2f s" % [guard.name, float(option("guard_deg", 84.0)), _hand.start_at])


func on_hit(collider: Node3D) -> void:
	# The smoke's framing check: the shot man's chest inside the lens at the hit.
	var lens_now: Camera3D = clip.root.get_viewport().get_camera_3d()
	for body: PlayerController in [_pov, _victim, _lead]:
		if body == collider and lens_now != null and lens_now.is_position_in_frustum(body.global_position + Vector3.UP):
			print("[event] %6.2f  in_frame  %s" % [elapsed(), body.name])


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.2f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position)])
