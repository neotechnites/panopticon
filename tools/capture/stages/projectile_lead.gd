extends "res://tools/capture/stages/stage.gd"

## projectile_lead: the guard POV down the scope with the projectile lever ON --
## a round seen passing behind a man, then the same hand leading the next one
## and killing him. Shot 5 of the projectile short. Filmed with
## [code]--shot=s3_open_lane --stage=projectile_lead --pov=guard --hud=crosshair --bots=6 --seconds=11.2[/code]
## (cut 1.2 s in, 9.0 s). Ryan: "footage of the new feature being used" and "i
## want it to look like sniping in fortnite where you can actually see the
## bullet as it travels".
##
## The eye is 55 m out and 100 m/s (CAPTURE_SPEED, pinned for the film) is
## 0.56 s in the air: 34 frames at 60 fps of a lit bullet climbing onto the
## crosshair and receding, which is the subject of the shot. Ryan: "if it has to
## move slower than it has to move slower".
##
## [b]The men are played, not driven[/b]
##
## Ryan on the first dailies: "the people hes shooting at are retarded. they
## need to look like real players." The first cut drove them down a lane with a
## weave on it, which is a rail, and it read as one. They now run on their own
## [RunnerBrain], the shipped one, exactly as the bot harness runs them: they
## plan a lap, break for cover when the rifle is on them, jump the gaps, hold
## behind a rock and come out when their patience runs out, and juke when a
## round lands inside their tracer alarm. What this stage does is hand each seat
## a different man to be -- see tools/capture/runner_cast.gd, which is
## capture-only and map-agnostic, and which shot 2 uses for the same reason.
## Nothing here drives a body.
##
## The price of that is nobody can be promised to be anywhere. So the hand is
## not told WHICH man to shoot: each beat is given the whole cast and swings
## onto whoever is in the open and nearest the line it already holds, and holds
## the trigger ("clear") until the eye can see both the man and the ground he is
## being led into. That is also what makes the shot repeatable, because a deck
## of columns hides a runner about half the time.
##
## [b]The lane[/b]
##
## probe_ring.gd --los at h 1.0, every 0.5 deg from 44 to 64, at r 54 and r 56:
## 45.0-49.5 is the pillar, 50-59 is speckled -- open and blocked alternating
## every half degree, plates at r 50-53 standing 1.2 m proud -- 59.5-62.5 is
## clean, and 63 on is the inner wall. Four degrees of sampling reads 50-59 as
## open because 52, 56 and 60 all fall in gaps. They are gaps. The round also
## leaves the muzzle while that probe's ray leaves the eye, and at this
## depression the difference is a plate at 50 m, so the "clear" hold raycasts
## the real thing every frame rather than trusting the table.
##
## [b]The clock[/b], in clip seconds (bodies placed at 0.6, the cut starts at 1.2):
##   1.6   the hand leaves the park and eases onto whoever is in the open
##   4.6+  MISS  the round crosses 1.2 m behind him and carries on
##   7.15+ HIT   led by the round's flight, and he goes down 0.27 s later
##   9.0   the scope comes off the drop onto the next man still coming
## Both firing beats hold past those times until the shot is actually there, so
## the exact frame moves a little with the seed. That is the point of the hold.
##
## Dials (--set=):
##   speed     the projectile lever in m/s (100, CAPTURE_SPEED; 0 is hitscan)
##   first     bearing of the man furthest back (6)
##   step      degrees of ring between them (13)
##   r         radius they are strung along (54)
##   behind    metres of ring the missed round is put behind him (1.2)
##   start     clip seconds the hand leaves the park (1.6)
##   beats     engagements after the first kill (3)
##   beat_more/fire_more   seconds each of those runs, and when its trigger is
##             ready inside it (3.0, 1.2)
##   shots_more/wait_more  rounds each of those may spend on its man, and how
##             long it holds out for a clear one before taking what it has (2, 1.6)
##   beat_a/beat_b/beat_c  seconds the hand spends on each beat (3.8, 3.6, 4.0)
##   fire_a/fire_b         seconds into that beat the trigger is ready (3.0, 1.75)
##   park_deg  bearing the scope rests on before the first beat (52)
##   lift      1 to lift the grade for a phone (a POV carries no fill light)
##   clear     the scope's clear centre as a fraction of half the frame height

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const CAST := preload("res://tools/capture/runner_cast.gd")

## Map 1. Pinned here so a settings file on the filming machine cannot move it.
const MAP_1: StringName = &"bentham_ring"

## The round's speed for THIS capture, m/s. Pinned here and not read from
## MatchRules.SUGGESTED_PROJECTILE_SPEED on purpose: the game's suggestion is a
## balance number and moves, and Ryan picked 100 for the film after seeing both
## -- "remake the shot with 100m/s shot". Over the 48-55 m of this lane that is
## about half a second, thirty frames of bullet to follow. Changing this changes
## the shot, not the game.
const CAPTURE_SPEED: float = 100.0

var _runners: Array = []
var _brains: Array = []
var _hand: Node = null
var _guard: PlayerController = null
var _kills: int = 0


func bots() -> int:
	return int(option("bots_wanted", 6))


func needs_pov() -> String:
	return "guard"


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = MAP_1
	# The subject of the shot: the round travels, at the suggested lever unless
	# a dial says otherwise.
	rules.guard_projectile_speed = float(option("speed", CAPTURE_SPEED))
	# The rifle comes back in this long, so both beats get a ready rifle.
	rules.base_reload_seconds = 1.0
	# RunnerProfile.resolve gives the round's exported profile priority over the
	# brain's own, so leaving it set would hand all six seats the same man and
	# every dial the cast layer sets below would be ignored.
	CAST.free_the_seats(rules)


func before_start() -> void:
	var root: Node = clip.root
	# Men crossing 60 deg of ring will otherwise find a pad or a lava crack, and
	# a launched runner is not a body the guard missed.
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
	if runners.size() < 2:
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var r: float = float(option("r", 54.0))
	var first: float = float(option("first", 6.0))
	var step: float = float(option("step", 13.0))
	var bodies: Array = []
	var points: Array = []
	var brains: Array = []
	for index: int in runners.size():
		bodies.append(runners[index].controller)
		brains.append(runners[index])
		# Strung along the lap, and off one radius, so the scope never finds
		# them stood in a rank.
		points.append(LIB.ring_point(
			first + step * float(index),
			r + 1.6 * float(index % 3 - 1),
			0.1
		))
	# Each man gets his own way of playing, then is armed again on it.
	CAST.vary(brains, int(clip._options.get("seed", 0)))
	var placed: int = CAST.restart(brains, points)
	_runners = bodies
	_brains = brains
	say("projectile_lead: %d played on the lap from %.0f deg, %.0f deg apart, r %.0f, round %.0f m/s" % [
		placed, first, step, r, float(option("speed", CAPTURE_SPEED)),
	])
	return true


func tick(_delta: float) -> void:
	if _hand != null or _brains.size() < 2:
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
	# No beat names a body: each is given the whole cast and takes whoever is in
	# the open. "clear" holds the trigger until the shot is really there.
	_hand.beats.append({
		"from": _brains, "seconds": float(option("beat_a", 3.8)),
		"fire_at": float(option("fire_a", 3.0)),
		"lead": 0.0, "behind": float(option("behind", 1.2)), "clear": true,
		"watch": true,
	})
	_hand.beats.append({
		"from": _brains, "seconds": float(option("beat_b", 3.6)),
		"fire_at": float(option("fire_b", 1.75)), "clear": true,
		"acquire": float(option("acquire", 0.35)), "watch": true,
	})
	# beats (2): how many more engagements after the miss and the first kill. The
	# short's last section grew to about thirteen seconds of voice, and a scope
	# that has run out of things to do sits on rock. Each of these re-acquires
	# whoever is in the open, leads him and fires -- which lands most of the time
	# and reads as a near miss when it does not, because the hand is still doing
	# what a player does.
	var more: int = maxi(int(option("beats", 3)), 0)
	for index: int in more:
		_hand.beats.append({
			"from": _brains, "seconds": float(option("beat_more", 3.0)),
			"fire_at": float(option("fire_more", 1.2)), "clear": true,
			"acquire": float(option("acquire", 0.35)), "watch": true,
			"shots": int(option("shots_more", 2)),
			"wait": float(option("wait_more", 1.6)),
		})
	# No trigger on the last beat: the scope comes off the drop and onto the man
	# still coming, so the clip ends on a move rather than on a held frame.
	_hand.beats.append({"from": _brains, "seconds": float(option("beat_c", 4.0))})
	_hand.park = LIB.ring_point(float(option("park_deg", 52.0)), float(option("r", 54.0)), 1.0)
	_hand.start_at = float(option("start", 1.6))
	var ready: float = _hand.start_at + float(option("beat_a", 3.8)) + float(option("beat_b", 3.6))
	var more_at: String = ""
	for index: int in more:
		more_at += ", %.2f" % (ready + float(option("fire_more", 1.2)) + float(option("beat_more", 3.0)) * float(index))
	say("tower brain stood down; the hand starts at %.2f s, is ready to miss at %.2f, to lead at %.2f%s, and holds each until the shot is there" % [
		_hand.start_at,
		_hand.start_at + float(option("fire_a", 3.0)),
		_hand.start_at + float(option("beat_a", 3.8)) + float(option("fire_b", 1.75)),
		more_at,
	])


func on_out(participant: MatchParticipant) -> void:
	_kills += 1
	# Out of the hand's pool the moment he is out of the round. The pool is the
	# same Array the beats hold, so this is what stops the scope from tracking a
	# man it has already killed -- which is how an eighteen-second take ends up
	# pointed at rock with nothing happening, and how the last round went into
	# the tower's own pillar.
	for index: int in _brains.size():
		var brain: RunnerBrain = _brains[index] as RunnerBrain
		if brain != null and brain.controller == participant.body:
			_brains.remove_at(index)
			break
	say("kill %d: %s (%d still running)" % [_kills, participant.body.name, _brains.size()])
