extends "res://tools/capture/stages/lavaparkour.gd"

## hell_going: short 12 "how its going" in hell, ONE take filmed twice off one tape: three hop the S5 lava platforms
## (lavaparkour's line, the POV last); the hand at the 306 deg window drops the lead and then the man ahead of the POV, both in the air.
## [code]--stage=hell_going --shot=lava_parkour --pov=guard|runner --bots=3 --seed=20261017[/code]
## Probe (eye 306:5.6:5.9): every flight's midpoint at h 2.0 open 300.9-335.5; the r 50.2 tops are under the near rim from it.
## Mac smoke (seed 20261017, line 3): lead in the air on hop 5 3.35-4.05 (apex 319 deg), mid on hop 4 3.75-4.4 (apex 313), POV
## lands on 309.5 at 4.18. Dials (--set=): window (306), scope_fov (26), hand_at (1.0), drop_lead (3.6), drop_mid (4.05), reload (0.4), track (3.0).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

const LEAD: int = 0
const MID: int = 1
const POV: int = 2

var _hand: Node = null


func bots() -> int:
	return 3


## Both POVs play the same line: the bodies never depend on whose eyes the take is filmed down.
func option(key: String, fallback: Variant) -> Variant:
	if key == "pov":
		return "runner"
	if key == "line":
		return 3
	return super(key, fallback)


func tune_rules(rules: MatchRules) -> void:
	rules.base_reload_seconds = float(option("reload", 0.4))
	rules.guard_projectile_speed = 0.0
	rules.bots_shove_rivals = false
	# A shot man plays his death and lies where he fell, never a ghost.
	rules.ghost_behaviour = MatchRules.GhostBehaviour.CATCH_AND_SWAP


func tick(delta: float) -> void:
	super(delta)
	if OS.has_environment("STAGE_DEBUG") and _line.size() == 3 and Engine.get_physics_frames() % 6 == 0:
		var line: String = ""
		for body: PlayerController in _line:
			line += " %s %.1f/%.2f h %.2f" % [body.name, LIB.bearing_of(body.global_position), LIB.radius_of(body.global_position), body.global_position.y - LIB.DECK_Y]
		say("at" + line)
	if _line.size() < 3 or _hand != null:
		return
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	var guard: PlayerController = shooter.controller
	LIB.guard_to_window(guard, float(option("window", 306.0)), 5.6)
	LIB.open_the_scope(guard, 0.74)
	var optic: WeaponOptic = guard.get_node_or_null(^"Optic") as WeaponOptic
	var fov: float = float(option("scope_fov", 26.0))
	if fov > 0.0 and optic != null and optic.profile != null and optic.base_fov > 0.0:
		optic.profile.zoom_factor = clampf(fov / optic.base_fov, 0.05, 1.0)
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(guard, controller(), elapsed())
	_hand.start_at = float(option("hand_at", 1.0))
	var drop_lead: float = float(option("drop_lead", 3.6))
	var drop_mid: float = float(option("drop_mid", 4.05))
	# The lead to his squeeze and a beat on him; the swing onto the mid man; then the hand rides the POV on.
	var lead_watch: float = minf(0.5, (drop_mid - drop_lead) * 0.35)
	_hand.beats.append({"body": _line[LEAD], "seconds": drop_lead + lead_watch - _hand.start_at, "fire_at": drop_lead - _hand.start_at, "watch": true})
	_hand.beats.append({"body": _line[MID], "seconds": drop_mid + 0.35 - (drop_lead + lead_watch), "fire_at": drop_mid - (drop_lead + lead_watch), "watch": true, "omega": 9.0})
	_hand.beats.append({"body": _line[POV], "seconds": float(option("track", 3.0))})
	_hand.park = LIB.ring_point(312.0, 53.0, 1.0)
	say("hell_going: hand on %s at the %.0f deg window from %.2f s" % [guard.name, float(option("window", 306.0)), _hand.start_at])


func on_hit(collider: Node3D) -> void:
	# The smoke's framing check: the shot man's chest inside the lens at the hit.
	var lens_now: Camera3D = clip.root.get_viewport().get_camera_3d()
	for body: PlayerController in _line:
		if body == collider and lens_now != null and lens_now.is_position_in_frustum(body.global_position + Vector3.UP):
			print("[event] %6.2f  in_frame  %s" % [elapsed(), body.name])


func on_out(participant: MatchParticipant) -> void:
	say("out: %s at %.1f deg r %.2f h %.2f" % [participant.body.name, LIB.bearing_of(participant.body.global_position), LIB.radius_of(participant.body.global_position), participant.body.global_position.y - LIB.DECK_Y])
