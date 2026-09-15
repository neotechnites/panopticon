extends "res://tools/capture/stages/stage.gd"

## guard_alone: the guard POV, down the scope, dropping three runners one after
## another (f03_guard_alone). Filmed with
## [code]--pov=guard --hud=crosshair --stage=guard_alone --shot=s3_open_lane --bots=4 --seconds=8[/code]
## (cut 1.8 s in, 5.2 s). Ryan: "it felt like everybody was playing a
## different race" -- "guard pov"; then "keep the crosshair on the guard POV
## shot"; "the sniper should hit some shots"; "it snaps between people too
## quick, they should be closer together, and it should look like a normal
## person aiming"; "one just spawns in right in frame".
##
## So: three runners jog the open S3 deck in a line about 10 m apart, all
## placed and already running before the cut begins (nothing spawns in the
## cut). The tower's brain is stood down the moment it holds the rifle and the
## head is a hand on a mouse (guard_hand.gd): the scope eases off the 180 deg
## pillar onto the leader, tracks him for a beat, drops him at 1.25 s of the
## beat; eases ~8 deg back down the line onto the second, drops him; the last
## the same. Three shots, three hits, every take. A fourth bot is parked at 58
## deg on deck, out of frame, so the round never resolves under the third kill.
## The scope's clear centre is opened to 0.74 of half the frame height so it
## fills the width of the tall frame; the grade is lifted (exposure 3.8,
## ambient 3.6) because a POV carries no fill light and the scope is dark rock.
##
## Dials (--set=): degs (162,151,140), r (54), pace (0.5), beat (1.7), fire_at
## (1.25), start (1.8, when the hand starts moving), lead_in (-13, degrees of
## ring the scope rests ahead of the first runner), lift (1).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const SPARE_DEG: float = 58.0

var _bodies: Array = []
var _hand: Node = null
var _guard: PlayerController = null


func bots() -> int:
	return 4


func needs_pov() -> String:
	return "guard"


func tune_rules(rules: MatchRules) -> void:
	# The rifle comes back in this long, so every rest gets a ready rifle.
	rules.base_reload_seconds = 1.0


func before_start() -> void:
	if int(option("lift", 1)) == 1:
		var world: WorldEnvironment = LIB.find_node(clip.root, "WorldEnvironment") as WorldEnvironment
		if world != null and world.environment != null:
			var env: Environment = world.environment.duplicate() as Environment
			env.tonemap_exposure = 3.8
			env.ambient_light_energy = 3.6
			world.environment = env


func cast(runners: Array[RunnerBrain]) -> bool:
	var degs: PackedStringArray = String(option("degs", "162,151,140")).split(",")
	if runners.size() < degs.size():
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var r: float = float(option("r", 54.0))
	var pace: float = float(option("pace", 0.5))
	for index: int in degs.size():
		var deg: float = float(degs[index])
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(deg, r, 0.1)},
			{"do": "lane", "to": deg + 30.0, "r": r, "speed": pace, "weave": 0.2, "period": 1.2, "timeout": 20.0},
			{"do": "hold", "seconds": 60.0},
		], index)
		_bodies.append(runners[index].controller)
	# Everyone else parked on deck in the S1/S2 pocket, out of every window the
	# scope visits; one prisoner is always left standing.
	for index: int in range(degs.size(), runners.size()):
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(SPARE_DEG + 2.0 * float(index), 50.0, 0.1)},
			{"do": "hold", "seconds": 60.0},
		], index, "ClipSpare%d" % index)
	victim_body(_bodies[0])
	say("guard_alone: %d runners at %s deg r %.0f, pace %.2f" % [_bodies.size(), ",".join(degs), r, pace])
	return true


func tick(_delta: float) -> void:
	if _hand != null or _bodies.is_empty():
		return
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.open_the_scope(_guard, 0.74)
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	var beat: float = float(option("beat", 1.7))
	var fire_at: float = float(option("fire_at", 1.25))
	for body: PlayerController in _bodies:
		_hand.beats.append({"body": body, "seconds": beat, "fire_at": fire_at})
	var first: Vector3 = _bodies[0].global_position
	_hand.park = LIB.ring_point(LIB.bearing_of(first) - float(option("lead_in", -13.0)), LIB.radius_of(first), 1.0)
	_hand.start_at = float(option("start", 1.8))
	say("tower brain stood down; the hand starts at %.1f s" % float(option("start", 1.8)))
