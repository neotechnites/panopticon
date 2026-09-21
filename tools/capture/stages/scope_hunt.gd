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
## for the lens. All seven run one lane at r 48, three degrees apart, which is
## 2.51 m of ring between bodies: a pack, not a conga line, and the tower's eye
## is 28.9 m up and looking down on it, so nobody is behind anybody. Every one
## has the human layer on and its own seeded glance schedule, so nothing moves
## in lockstep. Four are never shot: the round cannot resolve under the last
## kill.
##
## The lane is S2 The Lava Shelf, 75-130 deg, and it was picked for the picture
## before the ray. The first take ran 52-60 deg because that was the only arc
## --los would pass a round down, but that is the middle of S1 The Spires: nine
## spire columns, and three small dark figures lost in a dark red field. Line of
## sight is a ray; a shot is a picture. S2 is the section docs/MAP1_SECTIONS.md
## builds to be seen from the tower -- inner lane r 44-53 open, a 1.3 m rock
## wall at r 53.5 from 80 to 125, the lava field behind it at r 54.5-60 -- so a
## body on the inner lane stands between the tower and the lava and reads dark
## against orange. The S3 open lane guard_alone used is not available: the crack
## grid now fills 145-200.
##
## Which three drop, and WHERE, is the one thing that is not free. The guard
## shoots outward from the tower's axis, so the tower's own piers and any rise
## in the deck eat rounds. probe_ring.gd --los at r 48, 78-128 deg every 2 deg,
## h 1.0 and h 1.6 (they agree at every sample), then half-degree steps across
## the edges:
##
##   78-89.5 deg     open
##   90-94.5 deg     TowerCollision at r 6.86        the tower's own pier
##   95-128 deg      open
##
## That is 33 degrees clear from 95 to the end of the sweep at 128, and
## --heights reads r 48 dead flat under all of it: +0.00 at every bearing. The two
## r 47 spires S2 keeps for the bots, at 95 and 112, cast no measurable shadow
## one metre further out -- 93-98 and 108-116 at half a degree are open end to
## end. No other radius will do: r 50 is open on the same window but carries
## bumps of +0.89, +0.67 and +1.65 at 84, 106 and 116, and r 52 and r 54 are
## BLOCKED by MapBaseCollision at r ~50.4 at every bearing outside the pier's,
## the rock wall's own foot. So all seven run r 48.
##
## Seven start 3 deg apart from 88 to 106 and the hand takes the middle three,
## runners 2, 3 and 4, back to front -- the rearmost first, then forward with
## the pack -- which spreads the kills along the lane instead of stacking them
## where the scope already sits. At pace 0.22 a body covers 3.2 deg of ring a
## second at r 48 (measured: 94 -> 102.5 deg in 2.68 s), the beats fire at 3.30,
## 5.90 and 8.50 clip seconds, and the headless take drops them at 102.5, 113.9
## and 125.4 degrees: 11 degrees apart, every one inside the open window and
## 8 degrees clear of the pier. Weave 0.25 wanders the radius over 47.7-48.3,
## which is nothing the rifle cares about.
##
## The ground under this lane is not "clear" in probe_ring --clear's sense and
## cannot be: --clear reports only 0-71, 136-143, 202-207 and 272-288 deg free
## of pad and trap footprints inside r 47.5-56.5, because S2's seven lava
## TrapVolumes bound out to r 46.4-61.4 across 72-135 deg and swallow the whole
## band. That is a footprint, not a floor -- the lava itself is at r 54.5-60 --
## and nothing here launches or burns a body anyway: before_start disarms 40
## pads and 22 traps, and a launched or burned runner is not a body the guard
## shot. The first hazard actually sitting on r 48 is S3's crack grid from
## 143.9 deg, and at 9.5 s the leading runner is only at 134 deg.
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
	var degs: PackedStringArray = String(option("degs", "88,91,94,97,100,103,106")).split(",")
	var rs: PackedStringArray = String(option("rs", "48,48,48,48,48,48,48")).split(",")
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
	for raw: String in String(option("targets", "2,3,4")).split(","):
		var k: int = int(raw)
		if k >= 0 and k < _runners.size():
			_targets.append(_runners[k])
			if _first_point == Vector3.ZERO:
				_first_point = LIB.ring_point(float(degs[k]), float(rs[k]), 1.0)
	victim_body(_targets[0] if not _targets.is_empty() else _runners[0])
	say("scope_hunt: %d on the lap at %s deg, r %s, pace %.2f; the hand takes %s" % [
		_runners.size(), ",".join(degs), ",".join(rs), pace, String(option("targets", "2,3,4")),
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
