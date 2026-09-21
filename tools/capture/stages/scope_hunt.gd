extends "res://tools/capture/stages/stage.gd"

## scope_hunt: the guard POV down the scope, hitscan, while seven prisoners run
## the lap of map 1. Shot 2 of the projectile short. Filmed with
## [code]--shot=s3_open_lane --stage=scope_hunt --pov=guard --hud=crosshair --bots=7 --seconds=9.5[/code]
## (cut 1.5 s in, 8.0 s). Ryan: "pov footage of sniper gameplay", under the line
## "and while i liked the idea of hitscan at first, I did need ways to make it
## harder for the sniper than it currently is".
##
## The point of the shot is that hitscan is instant and easy: the crosshair
## arrives on a running body and the body drops on the same frame, three times,
## spaced across eight seconds so there is no doubt it is the rule and not a
## lucky frame. So the tower's own brain is stood down the moment it holds the
## rifle and the head becomes a hand on a mouse (guard_hand.gd): drift, an
## eased arc onto a runner that overshoots and settles, a tracking beat that
## leads him, the squeeze, the recoil, then off to the next.
##
## Seven runners, not three: Ryan asked for the lap, so the deck is busy and
## the three that drop are picked out of a moving pack rather than queued up
## for the lens. They run two lanes at two radii so seven bodies fit the clear
## stretch without a conga line, every one of them with the human layer on and
## its own seeded glance schedule, so nothing moves in lockstep. Four are never
## shot: the round cannot resolve under the last kill.
##
## Which three drop, and WHERE, is the one thing that is not free, and it cost
## two takes to learn why. The guard shoots outward from the tower's axis, so
## two things stand between him and the ring: the tower's own pillars, and the
## deck itself where the inner ring rises. probe_ring.gd --los at r 54, every
## 4 deg, h 1.0 and h 1.6 (they agree everywhere) reads:
##
##   4 deg        TowerCollision at r 6.85       a pillar
##   5-13 deg     MapBaseCollision at r ~46      the inner wall, +4.6 m
##   16 deg       open
##   20-40 deg    MapBaseCollision at r 46 -> 40 the inner ring, rising
##   44-47 deg    open
##   48 deg       TowerCollision at r 6.85       the second pillar
##   49-60 deg    open
##   63-70 deg    MapBaseCollision at r ~18      the inner wall again, +3.0 m
##
## So there is exactly one window wide enough to kill three men in eight
## seconds without a pillar or a deck lip eating a round: 52-60 degrees. The
## first take put a target at 12 deg and the round hit MapBaseCollision at
## r 46.9, y 24.48 -- the wall, not the man. Every beat is therefore timed so
## that the body is between 52 and 60 degrees at the squeeze: at pace 0.22 a
## runner covers 2.42 deg of ring a second, the beats fire at 3.3, 5.9 and
## 8.5 clip seconds, so the three targets start at 46.5, 43.2 and 39.9 and are
## shot at 53, 56 and 59 degrees. The pack is taken front to back while it
## streams forward, so the scope falls back through the line rather than
## chasing its own start bearing. Four spares at 26, 30, 34 and 50 fill the
## frame and keep the round alive under the last kill.
##
## All seven run one radius, r 54: probe_ring --heights finds a 2.74 m object
## standing on the deck at r 52, 48 deg, straight through a second lane. The
## line is broken up by weave and by the human layer instead.
##
## Where they run is measured, not chosen. probe_ring.gd --clear at bc9684c
## reports exactly four pad- and trap-free stretches of the ring inside the
## walkable band r 47.5-56.5: 0-71, 136-143, 202-207 and 272-288 degrees. Only
## the first is long enough for seven bodies and eight seconds, and --heights
## reads it flat at r 52 and r 54 (r 48 is +4.6 m of wall, r 58 has no floor at
## all). So the lap runs 12-36 deg out to the fifties, two radii two metres
## apart, well inside the stretch at both ends. The S3 open lane guard_alone
## used is not available here: the crack grid now fills 145-200.
##
## Dials (--set=):
##   degs      start bearing of each runner, in order (7 values)
##   rs        radius of each runner, in order (7 values)
##   arc       degrees of ring each runner's lane runs (every runner is shot
##             running; a lane that ends early leaves a body standing in frame)
##   pace      run speed multiplier
##   targets   which runner indices the hand drops, in order
##   start     clip seconds the hand starts moving (the cut's in point)
##   beat      seconds the hand spends per target
##   fire_at   seconds into a beat the trigger goes
##   lead_in   degrees of ring the scope rests ahead of the first target
##   lift      1 to lift the grade for a phone (a POV carries no fill light)
##   clear     the scope's clear centre as a fraction of half the frame height

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

## Map 1. Pinned here so a settings file on the filming machine cannot move it.
const MAP_1: StringName = &"bentham_ring"

var _runners: Array = []
var _targets: Array = []
var _hand: Node = null
var _first_point: Vector3 = Vector3.ZERO
var _guard: PlayerController = null
var _kills: int = 0


func bots() -> int:
	return 7


func needs_pov() -> String:
	return "guard"


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = MAP_1
	# Hitscan: the projectile lever off, whatever the filming machine has saved.
	# This is the shot that says what hitscan looks like, so it is not a default
	# to be inherited -- it is the subject.
	rules.guard_projectile_speed = 0.0
	# The rifle comes back in this long, so every beat gets a ready rifle.
	rules.base_reload_seconds = 1.0


func before_start() -> void:
	var root: Node = clip.root
	# Seven bodies running a lap over eight seconds will otherwise find a pad or
	# a lava crack, and a launched or burned runner is not a body the guard shot.
	say("%d boost pads disarmed" % LIB.disarm_pads(root))
	say("%d traps disarmed" % LIB.disarm_traps(root))
	if int(option("lift", 1)) == 1:
		var world: WorldEnvironment = LIB.find_node(root, "WorldEnvironment") as WorldEnvironment
		if world != null and world.environment != null:
			var env: Environment = world.environment.duplicate() as Environment
			env.tonemap_exposure = 3.8
			env.ambient_light_energy = 3.6
			world.environment = env


func cast(runners: Array[RunnerBrain]) -> bool:
	var degs: PackedStringArray = String(option("degs", "26,30,34,39.9,43.2,46.5,50")).split(",")
	var rs: PackedStringArray = String(option("rs", "54,54,54,54,54,54,54")).split(",")
	if runners.size() < degs.size() or degs.size() != rs.size():
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var pace: float = float(option("pace", 0.22))
	var arc: float = float(option("arc", 55.0))
	for index: int in degs.size():
		var deg: float = float(degs[index])
		var r: float = float(rs[index])
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(deg, r, 0.1)},
			{"do": "human", "on": true},
			{
				"do": "lane", "to": deg + arc, "r": r,
				"speed": pace, "weave": 0.25, "period": 1.2, "timeout": 30.0,
				"glances": _glances(index), "flinch_on": "hit",
			},
			{"do": "hold", "seconds": 60.0},
		], index)
		_runners.append(runners[index].controller)
	for raw: String in String(option("targets", "5,4,3")).split(","):
		var k: int = int(raw)
		if k >= 0 and k < _runners.size():
			_targets.append(_runners[k])
			if _first_point == Vector3.ZERO:
				_first_point = LIB.ring_point(float(degs[k]), float(rs[k]), 1.0)
	victim_body(_targets[0] if not _targets.is_empty() else _runners[0])
	say("scope_hunt: %d on the lap at %s deg, r %s, pace %.2f; the hand takes %s" % [
		_runners.size(), ",".join(degs), ",".join(rs), pace, String(option("targets", "5,4,3")),
	])
	return true


## A runner looking around as he runs. Every body gets a different schedule, and
## the driver's own seed_with jitters it further, so seven heads never turn together.
func _glances(index: int) -> Array:
	var phase: float = 0.35 + 0.31 * float(index)
	return [
		{"t": phase, "right": -38.0 - 6.0 * float(index % 3), "pitch": -3.0},
		{"t": phase + 1.4, "right": 24.0 + 5.0 * float(index % 2), "pitch": 2.0},
		{"t": phase + 3.1, "right": -52.0, "pitch": -5.0},
		{"t": phase + 4.9, "right": 18.0, "pitch": 0.0},
	]


func tick(_delta: float) -> void:
	if _hand != null or _targets.is_empty():
		return
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	var beat: float = float(option("beat", 2.6))
	var fire_at: float = float(option("fire_at", 1.8))
	for body: PlayerController in _targets:
		_hand.beats.append({"body": body, "seconds": beat, "fire_at": fire_at})
	_hand.park = LIB.ring_point(
		LIB.bearing_of(_first_point) - float(option("lead_in", -13.0)),
		LIB.radius_of(_first_point),
		1.0
	)
	_hand.start_at = float(option("start", 1.5))
	say("tower brain stood down; the hand starts at %.2f s, beats %.2f s, fires at +%.2f" % [
		_hand.start_at, beat, fire_at,
	])


func on_out(participant: MatchParticipant) -> void:
	_kills += 1
	say("kill %d: %s" % [_kills, participant.body.name])
