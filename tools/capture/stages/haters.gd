extends "res://tools/capture/stages/stage.gd"

## haters: shots 2-4 of the haters short as ONE staged take on the green forest,
## filmed twice from the same seed: [code]--pov=guard --hud=crosshair[/code]
## (the sniper down the scope) and [code]--pov=runner[/code] (the shover's eyes).
## Ryan: "Sniper POV sniping at 3 runners" / "the EXACT SAME INSTANCE from one
## runner's POV: being shot at (tracers past him), then shoving another runner
## off the lane into the pit" / "the shover turns back and gets sniped".
##
## [code]--stage=haters --shot=s3_open_lane --map=forest --bots=4 --seconds=8.6 --seed=20261012[/code]
##
## The beat, clip seconds: three runners on the lane's last leg to the portal
## (bearing rising, 320 -> 340 deg; the portal at 345). The tower brain is
## stood down; the hand (guard_hand.gd) drops the leader at ~1.9 s, puts a round
## behind the shover (~3.2 s) and one ahead of him (~4.4 s); at chase_at (4.5)
## the shover shoves the victim, a step inside him, into the ravine (the tower
## and the drop are on his right); the scope follows the fall; the shover looks
## down, turns back to the lane and runs, and the hand drops him (~7.4 s).
##
## Why the numbers (probe_ring --floor --scene=res://maps/forest/forest_green.tscn):
## the deck is r 45.5-56; something stands on r 48.5-51 at 304 deg, r 48.5-49.5
## at 312, r 50.5-53.5 at 318, r 47.5-48.5 at 320, r 52-53.5 at 326, r 52-54.5
## at 336; lip boulders at r 47.4 span 330.3-333.4 and 338.3-341.3 deg. So the
## victim runs r 49.25 from 321.5, the shover r 51.5 from 320, the leader r 50.5
## from 328, and the shove lands at ~335 deg, between the two boulders. The
## eye at y 28.9 sees r 50-54 at 310-340 deg except r 52 at 325 (canopy).
##
## Dials (--set=): pace (0.3), chase_at (4.5), hand_start (0.9), impulse (18), up (6),
## guard_deg (315), guard_r (4.4).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const SPARE_DEG: float = 120.0
const SHOVER_AT := Vector2(281.0, 51.0)
const VICTIM_AT := Vector2(284.0, 48.75)
const LEAD_AT := Vector2(278.0, 52.5)

var _shover: PlayerController = null
var _victim: PlayerController = null
var _lead: PlayerController = null
var _hand: Node = null
var _guard: PlayerController = null
var _first_point: Vector3 = Vector3.ZERO


func bots() -> int:
	return 4


func tune_rules(rules: MatchRules) -> void:
	rules.base_reload_seconds = 1.0
	rules.guard_projectile_speed = 0.0
	rules.shove_impulse = float(option("impulse", 18.0))
	rules.shove_up_impulse = float(option("up", 6.0))


## A lane run through [param legs] ([to_deg, r] pairs): one lane step each, so
## the body arcs from radius to radius round the trunks at full speed.
func _legs(legs: Array, pace: float, weave: float, extra: Dictionary = {}) -> Array:
	var out: Array = []
	for leg: Array in legs:
		var step: Dictionary = {"do": "lane", "to": float(leg[0]), "r": float(leg[1]), "speed": pace,
			"weave": weave, "period": 1.3, "timeout": 30.0}
		step.merge(extra)
		out.append(step)
	return out


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 4:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var pace: float = float(option("pace", 1.0))
	# Driver clocks start at cast (0.6 s): a clip second is a driver second + 0.6.
	_shover = runners[0].controller
	_victim = runners[1].controller
	_lead = runners[2].controller

	# The shover (the POV): outside the victim, weaving the trunks; eyes flick to
	# the tree on his right at each crack. Same steps on both cameras.
	var shover_steps: Array = [
		{"do": "place", "at": LIB.ring_point(SHOVER_AT.x, SHOVER_AT.y, 0.1)},
		{"do": "human", "on": true},
	]
	var glances: Array = [
		{"t": 0.0, "right": 0.0, "pitch": -1.0},
		{"t": 0.8, "right": 10.0, "pitch": -2.0},
		{"t": 1.5, "right": 2.0, "pitch": -1.0},
		{"t": 1.85, "right": 40.0, "pitch": 3.0},    # the leader drops: a look at the tree
		{"t": 2.3, "right": 6.0, "pitch": -1.0},
		{"t": 3.05, "right": 55.0, "pitch": 4.0},    # the crack behind him
		{"t": 3.5, "right": 8.0, "pitch": 0.0},
	]
	var legs: Array = _legs([[287.0, 53.0], [295.0, 51.5], [301.0, 51.5], [306.0, 53.0], [316.0, 52.0], [322.0, 50.8], [334.0, 50.8]],
		pace, 0.04)
	for leg: Dictionary in legs:
		leg["glances"] = glances
	shover_steps.append_array(legs)
	shover_steps.append_array([
		{"do": "chase", "victim": _victim, "range": 2.6, "timeout": 1.5, "speed": 1.0},
		{"do": "glance", "right": 15.0, "pitch": 22.0, "seconds": 0.3},    # watch him go over
		{"do": "hold", "seconds": 0.35},
		{"do": "glance", "right": 75.0, "pitch": -22.0, "seconds": 0.45},   # turns back down the lane
		{"do": "lane", "to": 300.0, "r": 50.5, "dir": -1.0, "speed": pace, "weave": 0.04, "period": 1.2, "timeout": 30.0},
		{"do": "hold", "seconds": 60.0},
	])
	drive(runners[0], shover_steps, 0, "ClipShoverDriver")

	var victim_steps: Array = [
		{"do": "place", "at": LIB.ring_point(VICTIM_AT.x, VICTIM_AT.y, 0.1)},
		{"do": "human", "on": true},
	]
	victim_steps.append_array(_legs([[290.0, 48.75], [300.0, 51.5], [306.0, 52.75], [316.0, 51.5],
		[322.0, 50.5], [345.0, 48.75]], pace * 0.9, 0.04))
	victim_steps.append({"do": "hold", "seconds": 60.0})
	drive(runners[1], victim_steps, 1, "ClipVictimDriver")

	var lead_steps: Array = [
		{"do": "place", "at": LIB.ring_point(LEAD_AT.x, LEAD_AT.y, 0.1)},
		{"do": "human", "on": true},
	]
	lead_steps.append_array(_legs([[345.0, LEAD_AT.y]], pace, 0.06))
	lead_steps.append({"do": "hold", "seconds": 60.0})
	drive(runners[2], lead_steps, 2, "ClipLeadDriver")

	# A spare parked behind the tree, so the round never resolves under a kill.
	for index: int in range(3, runners.size()):
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(SPARE_DEG + 3.0 * float(index), 52.0, 0.1)},
			{"do": "hold", "seconds": 60.0},
		], index, "ClipSpare%d" % index)

	_first_point = LIB.ring_point(LEAD_AT.x, LEAD_AT.y, 1.0)
	stage_body(_shover)
	victim_body(_victim)
	say("haters: %s shoves, %s is the victim, %s leads; pace %.2f" % [_shover.name, _victim.name, _lead.name, pace])
	return true


func tick(_delta: float) -> void:
	if _shover == null:
		return
	if OS.has_environment("HATERS_TRACE") and int(elapsed() * 4.0) != int((elapsed() - _delta) * 4.0):
		for b: PlayerController in [_shover, _victim, _lead]:
			var p: Vector3 = b.global_position
			say("trace %s %.1f deg r %.1f y %.1f" % [b.name, LIB.bearing_of(p), LIB.radius_of(p), p.y])
	if _hand != null:
		return
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	# From the spawn at the tree's axis the pier at 337.5 deg fills the scope; a
	# player steps up to the window (piers at 292.5/337.5): 315 deg, r 4.4 of the r 5 floor,
	# which keeps the pier 15 deg clear of the last target at 342.
	var stand: Vector3 = LIB.ring_point(float(option("guard_deg", 315.0)), float(option("guard_r", 4.4)), 0.0)
	_guard.global_position = Vector3(stand.x, _guard.global_position.y, stand.z)
	_guard.velocity = Vector3.ZERO
	LIB.open_the_scope(_guard, 0.74)
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.beats = [
		{"body": _lead, "seconds": 2.0, "fire_at": 1.6, "watch": true},
		{"body": _shover, "seconds": 1.1, "fire_at": 1.0, "miss_by": 2.0},
		{"body": _shover, "seconds": 1.0, "fire_at": 0.8, "miss_by": 2.6},
		# The lip he goes over, not the body: the twig rail cuts the eye off 13 deg down.
		{"at": LIB.ring_point(336.0, 46.5, 0.5), "seconds": 1.0},
		{"body": _shover, "seconds": 4.0, "fire_at": 0.6, "watch": true},
	]
	_hand.park = LIB.ring_point(LEAD_AT.x + 10.0, LEAD_AT.y, 1.0)
	_hand.start_at = float(option("hand_start", 0.8))
	say("tower brain stood down; the hand starts at %.1f s" % _hand.start_at)


func on_shove(shover: MatchParticipant, victim: MatchParticipant) -> void:
	if victim.body == null:
		return
	say("shove: %s -> %s at %.1f deg r %.1f" % [shover.body.name if shover.body else "?", victim.body.name,
		LIB.bearing_of(victim.body.global_position), LIB.radius_of(victim.body.global_position)])


func on_out(participant: MatchParticipant) -> void:
	say("out: %s" % (participant.body.name if participant.body else "?"))
