extends "res://tools/capture/stages/stage.gd"

## scope_hunt: the guard POV down the scope, hitscan, while seven prisoners run
## the lap of map 1. Shot 2 of the projectile short. Filmed with
## [code]--shot=s3_open_lane --stage=scope_hunt --pov=guard --hud=crosshair --bots=7 --seconds=9.5[/code]
## (cut 1.5 s in, 8.0 s). Ryan: "pov footage of sniper gameplay", under the line
## "and while i liked the idea of hitscan at first, I did need ways to make it
## harder for the sniper than it currently is".
##
## [b]The men are played, not driven.[/b] The first version of this shot put
## seven bodies on a lane at three-degree spacing and walked them round at a
## fixed pace with a glance schedule. Ryan, on the dailies: "the people hes
## shooting at are retarded. they need to look like real players." He is right,
## and the reason is structural -- a driven lane is a conga line wearing a
## costume. Seven bodies abreast at one radius and one speed have no reason to
## be anywhere, so they read as scenery, and a sniper picking off scenery is not
## a sniper.
##
## So nothing here drives a body. [method cast] never calls [method Stage.drive]:
## it hands every prisoner to its own live [RunnerBrain] -- the same brain the
## harness runs and the same one a player meets -- and gets out of the way. They
## sprint the mesh path, break for cover when they read the rifle on them, take
## the jump links, strafe out of the open, and hesitate when they are unsure. The
## tower's head is a hand on a mouse (guard_hand.gd); everything else on the deck
## is playing.
##
## That gives the picture what a lane cannot: a shot that lands near a man makes
## him juke, because [RunnerProfile.tracer_alarm_metres] is a real rule the brain
## already obeys, not an animation this file asked for. Kills one and two change
## the behaviour of the men who see them.
##
## [b]Where the variation lives.[/b] Seven copies of one brain would still move
## alike. Each seat is therefore dealt its own person by
## tools/capture/player_feel.gd -- boldness, patience behind cover, how far it
## will detour for cover, how it reads the tower, how quickly it reacts, how
## much it dares a jump -- seeded from the take seed and the seat index, so a
## take is repeatable and no two men play the same. That layer is capture
## scenery and lives under tools/capture/; [code]scripts/bot/[/code] learns
## nothing about filming, and nothing here teaches a brain about this map.
##
## [b]What the guard can actually see.[/b] The hand cannot be given a timetable
## of bodies when the bodies decide where to be. It gets three beats, and each
## beat carries no body at all until [method tick] finds one: every frame it
## asks [method _clearest] for a live prisoner standing in the open stretch with
## a clear line from the tower eye, and guard_hand cannot fire a beat whose body
## is null. So a beat with nobody in front of it is a guard scanning, not a
## round into a rock. When a man does step out, the squeeze is held
## [constant ACQUIRE_SECONDS] so the hand arrives and settles before it goes,
## and [code]clear[/code] holds the trigger past that until the eye really has
## him. Three squeezes, three bodies, and which three the run decides.
##
## The beat is 2.5 s and the squeeze 1.2 s into it, which is not taste: the
## clear-hold can add up to guard_hand's CLEAR_WAIT of 1.2 s, and 1.2 + 1.2 has
## to fit inside the beat or the beat expires with the trigger never pulled. At
## the first attempt the beat was 2.6 s and the squeeze 1.8 s in, and two of the
## three kills silently never happened.
##
## [b]The band the eye reaches.[/b] probe_ring.gd --los from the tower eye at
## (0, 28.9, 0) reads, at r 48 across this stretch: open 78-89.5, the tower's own
## pier blocking 90-94.5 at r 6.86, open 95-128. --heights reads r 48 flat at
## +0.00 at every bearing across it. Further out the deck itself takes the round:
## r 52 and r 54 are BLOCKED by MapBaseCollision at r ~50.4, the inner wall's
## foot, at every bearing outside the pier's. So the men are started inside
## r 47.6-50.1 -- past that the guard has no shot at all, whatever the brain
## decides -- and started well back of the window at uneven gaps, so they arrive
## in ones and twos across the whole clip and two or three are in shot at once.
## The deck reads as seven people who happen to be running it, not as a row.
##
## Kills land at 2.75, 5.20 and 7.70 clip seconds (1.25, 3.70 and 6.20 into the
## cut), within 0.03 s of that on every seed tried: the beat clock sets when the
## guard shoots, the run sets who he gets.
##
## before_start disarms 40 boost pads and 22 traps: a launched or burned runner
## is not a body the guard shot, and this is the shot that says what the rifle
## does.
##
## Dials (--set=):
##   degs      start bearing of each runner, in order (7 values)
##   rs        start radius of each runner, in order (7 values)
##   start     clip seconds the hand starts moving (the cut's in point)
##   beat      seconds the hand spends per target
##   fire_at   seconds into a beat the trigger goes
##   lead_in   degrees of ring the scope rests ahead of the first target
##   lift      1 to lift the grade for a phone (a POV carries no fill light)
##   clear     the scope's clear centre as a fraction of half the frame height

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
const FEEL := preload("res://tools/capture/player_feel.gd")

## Map 1. Pinned here so a settings file on the filming machine cannot move it.
const MAP_1: StringName = &"bentham_ring"
## Height up the body the eye is tested against: guard_hand's own aim point.
const AIM_HEIGHT: float = 1.0
## The tower's pier eats a round between these bearings at this radius; a target
## found inside it is no target. Measured, not chosen -- see the header.
const PIER_FROM: float = 89.0
const PIER_TO: float = 95.5
## The stretch a kill is allowed to happen in: past the pier, and still on S2's
## lava shelf, where a body reads dark against orange. A man is visible from the
## tower well before this, back down S1's spire field, but that is the dark red
## picture Ryan rejected -- LOS is a ray, a shot is a picture.
const TARGET_FROM: float = 96.0
const TARGET_TO: float = 130.0
## Seconds between finding a man and squeezing, when he is found part-way into a
## beat. A hand that lands and fires on the same frame reads as a machine.
const ACQUIRE_SECONDS: float = 0.6

var _runners: Array[RunnerBrain] = []
var _hand: Node = null
var _guard: PlayerController = null
var _kills: int = 0
var _beat_now: int = -1
var _locked: bool = false
var _spent: Array[PlayerController] = []
var _ray: PhysicsRayQueryParameters3D = null
var _first_point: Vector3 = Vector3.ZERO


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
	# Left null on purpose. RunnerBrain resolves its play profile as
	# RunnerProfile.resolve(rules, runner_profile), so a profile set here would
	# be one personality issued to all seven and would silently beat the per-seat
	# people player_feel.gd deals out.
	rules.ai_runner_profile = null
	# A shot prisoner drops and is out. With ghosts on he gets up as a chaser,
	# and the clip fills with men sprinting BACKWARDS down the lap to catch the
	# living -- which is a different feature's shot. It also gives the hand a
	# body it has already killed to find again.
	rules.ghost_behaviour = MatchRules.GhostBehaviour.NONE


func before_start() -> void:
	var root: Node = clip.root
	# Seven bodies running a lap over ten seconds will otherwise find a pad or a
	# lava crack, and a launched or burned runner is not a body the guard shot.
	say("%d boost pads disarmed" % LIB.disarm_pads(root))
	say("%d traps disarmed" % LIB.disarm_traps(root))
	if int(option("lift", 1)) == 1:
		var world: WorldEnvironment = LIB.find_node(root, "WorldEnvironment") as WorldEnvironment
		if world != null and world.environment != null:
			var env: Environment = world.environment.duplicate() as Environment
			env.tonemap_exposure = 3.8
			env.ambient_light_energy = 3.6
			world.environment = env


## Place seven people on the lap and let go. No driver is handed out: every body
## keeps the brain the match gave it, and the only thing done to it is where it
## starts and who it is.
func cast(runners: Array[RunnerBrain]) -> bool:
	# Started well back down the lap, not inside the window, because a live brain
	# SPRINTS: a man covers about 13 degrees of ring a second at this radius, so
	# the 96-130 stretch he can be shot in is only about two and a half seconds
	# of his run. Seven men parked inside it would all be through it by the
	# second beat. Spread back like this they arrive in ones and twos across the
	# whole clip, which is also what a lap looks like from the tower: a stream,
	# not a firing line. Gaps are uneven on purpose.
	var degs: PackedStringArray = String(option("degs", "34,42,49,57,64,72,80")).split(",")
	var rs: PackedStringArray = String(option("rs", "49.4,47.8,50.1,48.3,49.7,47.6,48.9")).split(",")
	if runners.size() < degs.size() or degs.size() != rs.size():
		return false
	for brain: RunnerBrain in runners:
		if brain.controller == null:
			return false
	var take_seed: int = int(option("seed", 20260930))
	for index: int in degs.size():
		var brain: RunnerBrain = runners[index]
		var deg: float = float(degs[index])
		var r: float = float(rs[index])
		# Start standing on the deck facing the way the lap runs, not facing the
		# tower: a man who begins by turning round reads as a spawn.
		brain.controller.global_position = LIB.ring_point(deg, r, 0.1)
		brain.controller.rotation = Vector3(0.0, atan2(
			-LIB.tangent_at(deg).x, -LIB.tangent_at(deg).z
		), 0.0)
		var person: String = FEEL.apply(brain, index, degs.size(), take_seed)
		# player_feel deals out a person; this pins the lane, because the lane is
		# this map's geometry and not a personality. BotProfile.track_radius is
		# 52 by default and MatchRules can push it further out, and the deck's
		# own inner wall takes the round at r ~50.4: probe_ring --los reads every
		# bearing from 96 to 128 open at r 48, 49 and 50 and BLOCKED at r 51 and
		# 52. A runner steered to 52 is a runner the guard cannot shoot at all,
		# so each man keeps the radius he was started on.
		if brain.profile != null:
			brain.profile.track_radius = r
		say("seat %d at %.0f deg r %.1f -- %s" % [index, deg, r, person])
		_runners.append(brain)
	# The scope rests near the middle of the pack, so the first ease-on is a
	# short one wherever the run has put the first man.
	var middle: int = degs.size() / 2
	_first_point = LIB.ring_point(float(degs[middle]), float(rs[middle]), 1.0)
	say("scope_hunt: %d live brains on the lap, spread %s deg; nothing is driven" % [
		_runners.size(), ",".join(degs),
	])
	return true


## A beat does not get a timetable, it gets whoever walks into the window. Until
## one does the beat carries no body at all, and guard_hand cannot fire a beat
## with no body -- so the guard scans instead of shooting a rock on the clock.
func tick(_delta: float) -> void:
	if _hand == null:
		_raise_the_hand()
		return
	var beat: float = float(option("beat", 2.5))
	var into: float = elapsed() - _hand.start_at
	if into < 0.0:
		return
	var k: int = clampi(int(into / beat), 0, _hand.beats.size() - 1)
	if k != _beat_now:
		_beat_now = k
		_locked = false
	if _locked:
		return
	var mark: PlayerController = _clearest()
	if mark == null:
		# No man, no shot. Cleared every frame so a body that steps out of the
		# open before the squeeze does not take the round with him.
		_hand.beats[k]["body"] = null
		return
	var within: float = into - float(k) * beat
	# Found late in the beat, the squeeze waits ACQUIRE_SECONDS: a hand that
	# lands on a man and fires the same frame reads as a machine. Capped so the
	# squeeze plus guard_hand's own clear-wait still fits inside the beat --
	# past that the beat expires with the trigger never pulled, which is what
	# swallowed two of the three kills the first time this ran.
	_hand.beats[k]["fire_at"] = minf(
		maxf(float(option("fire_at", 1.2)), within + ACQUIRE_SECONDS),
		beat - GUARD_HAND.CLEAR_WAIT - 0.05
	)
	_hand.beats[k]["body"] = mark
	_locked = true
	_spent.append(mark)
	if k == 0:
		victim_body(mark)
	say("beat %d takes %s at %.0f deg r %.1f, squeeze at +%.2f" % [
		k, mark.name, LIB.bearing_of(mark.global_position),
		LIB.radius_of(mark.global_position), float(_hand.beats[k]["fire_at"]),
	])


## Stand the tower's own brain down, open the scope and put a hand on the mouse.
func _raise_the_hand() -> void:
	if _runners.is_empty():
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
	var beat: float = float(option("beat", 2.5))
	var fire_at: float = float(option("fire_at", 1.2))
	# Three beats, each starting on the first live body it can see. The bodies
	# here are only placeholders so the hand has something to rest on; tick()
	# replaces each one as its beat comes up.
	for index: int in 3:
		_hand.beats.append({
			"body": _runners[mini(index + 2, _runners.size() - 1)].controller,
			"seconds": beat,
			"fire_at": fire_at,
			# Hold the trigger until the eye really has the man. With live
			# brains a scheduled squeeze is a squeeze into whatever rock he
			# stepped behind.
			"clear": true,
		})
	_hand.park = LIB.ring_point(
		LIB.bearing_of(_first_point) - float(option("lead_in", -13.0)),
		LIB.radius_of(_first_point),
		1.0
	)
	_hand.start_at = float(option("start", 1.5))
	say("tower brain stood down; the hand starts at %.2f s, beats %.2f s, fires at +%.2f" % [
		_hand.start_at, beat, fire_at,
	])


## The live prisoner the tower can best shoot right now: on the deck, outside the
## pier's shadow, with an unobstructed line from the eye to his chest, and not
## one this clip has already taken. Nearest the middle of the open window wins,
## so the hand is not thrown to the edge of its reach for a marginal body.
func _clearest() -> PlayerController:
	if _guard == null:
		return null
	var best: PlayerController = null
	var best_score: float = -1.0
	for brain: RunnerBrain in _runners:
		var body: PlayerController = brain.controller
		if body == null or not is_instance_valid(body) or body in _spent:
			continue
		if not LIB.on_deck(body):
			continue
		var bearing: float = LIB.bearing_of(body.global_position)
		if bearing < TARGET_FROM or bearing > TARGET_TO:
			continue
		if bearing >= PIER_FROM and bearing <= PIER_TO:
			continue
		if not _eye_reaches(body):
			continue
		# Middle of the open stretch beyond the pier, where the scope has room
		# on both sides to ease on and recoil off.
		var score: float = 60.0 - absf(bearing - 112.0)
		if score > best_score:
			best_score = score
			best = body
	return best


## True when nothing stands between the tower eye and [param body]'s chest. One
## query object, reused; this runs three times in a clip, at the top of a beat.
func _eye_reaches(body: PlayerController) -> bool:
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.collide_with_areas = false
	var camera: Node3D = _guard.get_node_or_null(^"Head/Camera") as Node3D
	var eye: Vector3 = camera.global_position if camera != null else _guard.global_position + Vector3.UP * 1.65
	_ray.exclude = [_guard.get_rid(), body.get_rid()]
	_ray.from = eye
	_ray.to = body.global_position + Vector3.UP * AIM_HEIGHT
	return _guard.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


func on_out(participant: MatchParticipant) -> void:
	_kills += 1
	say("kill %d: %s at %.1f deg" % [
		_kills, participant.body.name, LIB.bearing_of(participant.body.global_position),
	])
