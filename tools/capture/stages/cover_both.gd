extends "res://tools/capture/stages/stage.gd"

## cover_both: shots 6 and 7 of the shove short as ONE take, one fixed frame,
## no cut. Filmed with [code]--shot=cover_side --bots=3 --seconds=8[/code]
## (cut from 0.9 s in, 7.4 s: "f06_cover_both").
##
## Ryan, his words: shot 6 "camera low and side-on, fixed, never moves; cover
## on the left third with a player crouched behind it, framed to show a good
## bit more than the head". Shot 7: "same shot, the crouching player gets
## shoved by another out from cover and gets shot". "6 and 7 are one clip."
## "the sniper should not miss the first shot, and once they are pushed, they
## should stop crouching."
##
## The beat: a prisoner crouches in the pocket rock's shadow at 198.5 deg
## (left third, peeking). A second comes in from the left along the deck behind
## him at 2.0 s, crosses the open ground to the right and is dropped there --
## one shot, one kill. At 5.0 s a third comes in large from behind the lens and
## shoves the crouched one out to the right; the crouch key is up that tick, he
## flies, lands standing in the open, and the tower's next round drops him too.
##
## Dials (--set=): victim, runner, runner_to, shover, watch (deg,r); runner_speed,
## runner_wait, shover_speed, shover_wait; impulse (the shove, m/s), up.
##
## Why the numbers: the shipped 16 m/s shove carries a body ten metres, out of
## the right edge of a frame this size; 12 lands him 4 deg down the lane, in
## the open and in frame. The rock shadows the deck from the tower's eye
## between 194.4 and 202.4 deg (probe_ring.gd --los); a body under 194.4 is in
## the open. The shover waits behind the lens on open deck, so it is taken out
## of the rifle's target group for the clip.

const STAGE_AT: float = 0.6

var _victim: PlayerController = null
var _runner: PlayerController = null
var _shover: PlayerController = null
var _victim_driver: Node = null
var _armed: bool = false
var _shoved: bool = false
var _shoved_at: float = 0.0
var _rearmed: bool = false


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.shove_impulse = float(option("impulse", 12.0))
	rules.shove_up_impulse = float(option("up", 5.0))
	# The second shot has to land before the beat is over.
	rules.base_reload_seconds = 0.7


func tune_shooter(profile: ShooterProfile) -> void:
	LIB.dead_eye_shooter(profile)


func before_start() -> void:
	var at: Vector3 = LIB.polar(String(option("watch", "192.5,50.5")), LIB.ring_point(192.5, 50.5))
	LIB.watch(clip.root, LIB.bearing_of(at), LIB.radius_of(at), true)


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 3:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var v: Vector3 = LIB.polar(String(option("victim", "198.5,49.4")), LIB.ring_point(198.5, 49.4))
	var r: Vector3 = LIB.polar(String(option("runner", "201.8,48.2")), LIB.ring_point(201.8, 48.2))
	var r_to: Vector3 = LIB.polar(String(option("runner_to", "186.0,48.2")), LIB.ring_point(186.0, 48.2))
	var s: Vector3 = LIB.polar(String(option("shover", "206.0,50.5")), LIB.ring_point(206.0, 50.5))
	_victim = runners[0].controller
	_runner = runners[1].controller
	_shover = runners[2].controller
	var v_deg: float = LIB.bearing_of(v)
	# The victim: crouched in the rock's shadow, peeking inward at the tower.
	_victim_driver = drive(runners[0], [
		{"do": "place", "at": v + Vector3.UP * 0.1, "face": (-LIB.radial_at(v_deg) * 0.8 - LIB.tangent_at(v_deg) * 0.3).normalized()},
		{"do": "hold", "seconds": 60.0, "crouch": true, "sway": 14.0, "period": 2.6},
	], 0, "ClipVictimDriver")
	# The runner: waits off frame left in the shadow, then crosses the open
	# ground to the right at a run (bearing falling) and is sniped there.
	drive(runners[1], [
		{"do": "place", "at": r + Vector3.UP * 0.1, "face": -LIB.tangent_at(LIB.bearing_of(r))},
		{"do": "hold", "seconds": float(option("runner_wait", 2.0))},
		{"do": "lane", "to": LIB.bearing_of(r_to), "r": LIB.radius_of(r_to), "dir": -1, "speed": float(option("runner_speed", 0.6)), "timeout": 6.0},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipRunnerDriver")
	# The shover: behind the camera on open deck (hidden from the rifle: there
	# is no shadow behind the lens), runs down the lane at the victim, shoves,
	# then backs off to where it stood.
	LIB.hide_from_the_rifle(_shover)
	drive(runners[2], [
		{"do": "place", "at": s + Vector3.UP * 0.1, "face": -LIB.tangent_at(LIB.bearing_of(s))},
		{"do": "hold", "seconds": float(option("shover_wait", 5.0))},
		{"do": "chase", "victim": _victim, "range": 2.3, "timeout": 8.0, "speed": float(option("shover_speed", 0.65))},
		{"do": "hold", "seconds": 0.35},
		{"do": "run", "to": s, "speed": 0.8, "timeout": 3.0},
		{"do": "hold", "seconds": 60.0},
	], 2, "ClipShoverDriver")
	victim_body(_victim)
	stage_body(_victim)
	say("cover_both: %s crouches at %.1f deg r %.1f; %s crosses from %.1f to %.1f; %s shoves from %.1f" % [
		_victim.name, v_deg, LIB.radius_of(v), _runner.name, LIB.bearing_of(r), LIB.bearing_of(r_to), _shover.name, LIB.bearing_of(s),
	])
	return true


func tick(_delta: float) -> void:
	if _victim == null:
		return
	# Every body is in the shadow now: let the tower shoot what it sees.
	if not _armed and elapsed() > STAGE_AT + 0.3 and LIB.set_trigger(seat(), 0.15):
		_armed = true
		say("tower armed")
	# The shoved victim is shot standing, not flying: the tower holds until
	# they are back on the deck and upright.
	if _shoved and not _rearmed and elapsed() > _shoved_at + 0.25 and is_instance_valid(_victim) and _victim.is_on_floor():
		_rearmed = true
		LIB.set_trigger(seat(), 0.15)
		say("victim landed at %.1f deg r %.1f, tower re-armed" % [LIB.bearing_of(_victim.global_position), LIB.radius_of(_victim.global_position)])


func on_shove(_shover_p: MatchParticipant, victim: MatchParticipant) -> void:
	if _shoved or victim.body != _victim:
		return
	_shoved = true
	_shoved_at = elapsed()
	# Crouch key up this tick: they fly, land and stand where they land (their
	# own brain would run them back into the shadow).
	if _victim_driver != null:
		_victim_driver.retarget([{"do": "hold", "seconds": 60.0}])
	LIB.set_trigger(seat(), 1.0)
	say("shove landed on %s" % victim.body.name)
