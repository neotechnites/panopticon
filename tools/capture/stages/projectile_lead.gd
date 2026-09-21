extends "res://tools/capture/stages/stage.gd"

## projectile_lead: the guard POV down the scope with the projectile lever ON --
## a round that misses behind a runner, then the same hand leading the next one
## and killing him. Shot 5 of the projectile short. Filmed with
## [code]--shot=s3_open_lane --stage=projectile_lead --pov=guard --hud=crosshair --bots=4 --seconds=10.2[/code]
## (cut 1.2 s in, 9.0 s). Ryan: "footage of the new feature being used" and "i
## want it to look like sniping in fortnite where you can actually see the
## bullet as it travels", under the line "So, i went ahead and implemented that,
## tell me in the comments what you think, is this a good addition?".
##
## Shot 2 said what hitscan looks like in this lane; this is the same lane, the
## same hand and the same runners with guard_projectile_speed at 200 m/s, so the
## only thing that changed on screen between the two shots is that the round now
## takes time to arrive. The eye is 55 m out and 200 m/s is 0.27 s in the air:
## 16 frames at 60 fps of a lit bullet with a 2.5 m tail, which is the subject.
##
## The miss is a fixed 1.2 m of ring behind him ("behind" on the beat), not a
## scaled-down lead. That is measurement, not taste: a runner's gait is
## stop-start, and his speed at the squeeze reads anywhere from 3.1 to 6.3 m/s,
## so a lead scaled to 0 leaves the round anywhere from 0.8 to 1.7 m behind him
## -- which is a hit about half the time. A fixed 1.2 m is always a miss, always
## reads as one, and is small enough that both the man and the mark stay inside
## the one arc the round can cross. The second beat takes the full lead and kills. That is the
## Fortnite read Ryan asked for: why you missed, and what fixes it.
##
## THE LANE. probe_ring.gd --los at h 1.0, every 0.5 deg from 44 to 64, at r 54
## and r 56 (both agree), says 45.0-49.5 is the pillar, 50-59 is speckled --
## open and blocked alternating every half degree, MapBaseCollision at r 50-53 --
## 59.5-62.5 is clean, and 63 on is the inner wall. Four degrees of sampling
## (what shot 2 used) reads 50-59 as open because 52, 56 and 60 all happen to
## fall in gaps. They are gaps.
##
## That probe is a point test, and a point test is not what governs this shot. A
## raycast from the tower eye to each runner's chest, every 0.1 s for the whole
## take, says a man on this deck is VISIBLE ABOUT HALF THE TIME, flickering in
## and out of 0.2-0.5 s windows as he crosses the columns, everywhere on the
## arc. So the first cut of this shot fired its killing round at a man the scope
## could not see: he was behind a column at the squeeze, the round was led into
## the open bearing ahead of him, and he ran out into it just in time to be hit.
## Correct in the log, unreadable on camera.
##
## Both squeezes are therefore timed to a moment when the TRACKED MAN IS VISIBLE
## and the led mark is in an open half-degree. A hitscan shot only needs the
## first; a round that travels needs both, and on this deck the two are rarely
## true together for long. A: visible at 54.9 deg, mark 53.7. B: visible at 53.5
## deg, mark 55.3. If either beat is re-timed, re-measure BOTH -- do not assume
## an arc the probe calls open will still have a man standing in the clear.
##
## The round also leaves the muzzle while the probe's ray leaves the eye, and at
## this depression that difference is a plate at 50 m. An earlier cut aimed the
## miss at 56.9 deg, which the probe calls blocked; the round hit that plate five
## metres short of the man instead of crossing him.
##
## No runner carries flinch_on. The flinch is honest and it is also the one
## thing that couples the second shot to the first: a one-frame difference in
## when the first round lands moves the flinch, and three seconds later the
## second man is up to 8 degrees from where the clock says he is -- which is the
## difference between a kill and a round in the rock. Without it the take repeats.
##
## The clock, in clip seconds (bodies placed at 0.6 s, the cut starts at 1.2):
##   1.6  the hand leaves the park and eases down the line onto A
##   4.6  MISS   A at 54.9 deg, the round crosses 1.2 m behind him and flies on
##   7.15 HIT    B at 53.5 deg, led 1.8 deg, down at 7.43
##   9.0  the scope comes off the drop onto C, who is still coming up the ring
## A starts at 35.82 deg, B at 16.11, C at 8.0, all at r 54, pace 0.55. A's start
## is a poor dial -- his glance schedule makes the bearing he reaches by the
## squeeze move about 1.8 deg for every degree of start -- so it was searched,
## not solved. A is
## never killed -- he is missed and runs on -- and C is never shot, so the round
## cannot resolve under the one kill and no body has to be parked to hold it open.
##
## Dials (--set=):
##   speed     the projectile lever in m/s (200; 0 would be hitscan)
##   degs      start bearing of A, B and C (35.82,16.11,8.0)
##   r         radius of all three (54)
##   pace      run speed multiplier (0.55)
##   arc       degrees of ring each lane runs (55)
##   behind    metres of ring the missed round is put behind A (1.2)
##   start     clip seconds the hand leaves the park (1.6)
##   beat_a/beat_b/beat_c  seconds the hand spends on each man (3.8, 3.6, 4.0)
##   fire_a/fire_b         seconds into that beat the trigger goes (3.0, 1.75)
##   lead_in   degrees of ring the scope rests ahead of A (-13)
##   lift      1 to lift the grade for a phone (a POV carries no fill light)
##   clear     the scope's clear centre as a fraction of half the frame height

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

## Map 1. Pinned here so a settings file on the filming machine cannot move it.
const MAP_1: StringName = &"bentham_ring"

var _runners: Array = []
var _hand: Node = null
var _first_point: Vector3 = Vector3.ZERO
var _guard: PlayerController = null
var _kills: int = 0


func bots() -> int:
	return 4


func needs_pov() -> String:
	return "guard"


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = MAP_1
	# The subject of the shot: the round travels. 200 m/s is the lever the
	# bullet_test capture used, and MatchRules.SUGGESTED_PROJECTILE_SPEED.
	rules.guard_projectile_speed = float(option("speed", 200.0))
	# The rifle comes back in this long, so both beats get a ready rifle.
	rules.base_reload_seconds = 1.0


func before_start() -> void:
	var root: Node = clip.root
	# Three bodies crossing 55 deg of ring will otherwise find a pad or a lava
	# crack, and a launched runner is not a body the guard missed.
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
	var degs: PackedStringArray = String(option("degs", "35.82,16.11,8.0")).split(",")
	if runners.size() < degs.size():
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var r: float = float(option("r", 54.0))
	var pace: float = float(option("pace", 0.55))
	var arc: float = float(option("arc", 55.0))
	# Every runner gets the lane shape scope_hunt proved on camera -- the human
	# layer on, his own glance schedule, weave 0.25. Taking the human layer off
	# the two the hand shoots at (to steady their speed for the lead) looked like
	# the obvious fix and is not: without it the lane stalls the body outright,
	# frozen at one bearing for the rest of the take. The lead is steadied in the
	# hand instead, by measuring the body's speed over VELOCITY_WINDOW.
	for index: int in degs.size():
		var deg: float = float(degs[index])
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(deg, r, 0.1)},
			{"do": "human", "on": true},
			{
				"do": "lane", "to": deg + arc, "r": r,
				"speed": pace, "weave": 0.25, "period": 1.2, "timeout": 30.0,
				"glances": _glances(index),
			},
			{"do": "hold", "seconds": 60.0},
		], index)
		_runners.append(runners[index].controller)
	# Anyone past the three is parked at 280 deg, in the 272-288 clear stretch,
	# a hundred metres of ring from every window the scope visits.
	for index: int in range(degs.size(), runners.size()):
		drive(runners[index], [
			{"do": "place", "at": LIB.ring_point(280.0 + 3.0 * float(index), 52.0, 0.1)},
			{"do": "hold", "seconds": 60.0},
		], index, "ClipSpare%d" % index)
	_first_point = LIB.ring_point(float(degs[0]), r, 1.0)
	# B is the one who dies.
	victim_body(_runners[1] if _runners.size() > 1 else _runners[0])
	say("projectile_lead: %d crossing at %s deg, r %.0f, pace %.2f, round %.0f m/s" % [
		_runners.size(), ",".join(degs), r, pace, float(option("speed", 200.0)),
	])
	return true


## A runner looking around as he runs. Every body gets a different schedule, and
## the driver's own seed_with jitters it further, so three heads never turn together.
func _glances(index: int) -> Array:
	var phase: float = 0.35 + 0.31 * float(index)
	return [
		{"t": phase, "right": -38.0 - 6.0 * float(index % 3), "pitch": -3.0},
		{"t": phase + 1.4, "right": 24.0 + 5.0 * float(index % 2), "pitch": 2.0},
		{"t": phase + 3.1, "right": -52.0, "pitch": -5.0},
		{"t": phase + 4.9, "right": 18.0, "pitch": 0.0},
	]


func tick(_delta: float) -> void:
	if _hand != null or _runners.size() < 3:
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
	_hand.beats.append({
		"body": _runners[0], "seconds": float(option("beat_a", 3.8)),
		"fire_at": float(option("fire_a", 3.0)),
		"lead": 0.0, "behind": float(option("behind", 1.2)),
	})
	_hand.beats.append({
		"body": _runners[1], "seconds": float(option("beat_b", 3.6)),
		"fire_at": float(option("fire_b", 1.75)),
	})
	# No trigger on the last beat: the scope comes off the drop and onto the man
	# still coming, so the clip ends on a move rather than on a held frame.
	_hand.beats.append({"body": _runners[2], "seconds": float(option("beat_c", 4.0))})
	_hand.park = LIB.ring_point(
		LIB.bearing_of(_first_point) - float(option("lead_in", -13.0)),
		LIB.radius_of(_first_point),
		1.0
	)
	_hand.start_at = float(option("start", 1.6))
	say("tower brain stood down; the hand starts at %.2f s, misses at %.2f, leads and hits at %.2f" % [
		_hand.start_at,
		_hand.start_at + float(option("fire_a", 3.0)),
		_hand.start_at + float(option("beat_a", 3.8)) + float(option("fire_b", 1.75)),
	])


func on_out(participant: MatchParticipant) -> void:
	_kills += 1
	say("kill %d: %s" % [_kills, participant.body.name])
