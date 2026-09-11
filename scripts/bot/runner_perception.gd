class_name RunnerPerception
extends RefCounted

## What a prisoner is allowed to know, and what it costs to know it.
##
## The whole value of a bot match as evidence rests on this file. A runner that
## reads the shooter's aim vector, or the rifle's reload clock, off the node
## graph will beat any shooter at any difficulty and will tell you nothing about
## the game a human plays. So every fact the brain acts on is produced here, and
## every one of them is either public or paid for.
##
## [b]Free, because a panopticon says so[/b]
##
## - [b]That there is a guard this round, and where the tower is.[/b] The tower
##   is a structure in the middle of the ring and the round announces who is in
##   it. Hiding this would model a prison nobody can see the middle of.
##
## [b]Paid for[/b]
##
## - [b]Which way the guard is facing.[/b] Only while this runner has an
##   unobstructed line to the tower AND the tower is inside its own field of
##   view -- the same two gates, in the same order, that
##   [method TowerShooter._visible_targets] applies to a runner. The reading is
##   then blurred by [member RunnerProfile.attention_read_error_degrees], which is
##   the direct counterpart of the shooter's aim error, and a changed reading has
##   to hold for [member RunnerProfile.reaction_seconds] before it is believed.
##   The runner therefore gets a delayed, noisy BOOLEAN -- "I think it is looking
##   at me" -- and never the vector.
## - [b]Whether the rifle is loaded.[/b] Never read from the weapon. The runner
##   hears the report of each shot, exactly as the audio system does, and runs
##   its own clock from there against a believed reload length that
##   [member RunnerProfile.reload_read_accuracy] degrades. It can be, and
##   regularly is, wrong.
## - [b]Whether it was the one being shot at.[/b] A shot draws a tracer that ends
##   where the round ended, so a round that lands near this prisoner is a
##   prisoner that has just been shot at and knows it. That is the one piece of
##   information a shot gives away for free, and taking it is the point.
##
## [b]Cover cuts both ways[/b]
##
## The line-of-sight test that tells the brain it is safe is the same test that
## denies it a reading, because they are the same ray. A prisoner tucked behind a
## box cannot see the guard, its memory of the guard's attention goes stale after
## [member RunnerProfile.threat_memory_seconds], and it then assumes the worst and
## plays the reload alone. That is not a limitation of the model; from behind
## cover, the rhythm of the rifle really is all a prisoner has.

## Group every [TowerShooter] joins on entering the tree, so a runner can find
## the guard without the match having to introduce them.
const SHOOTER_GROUP: StringName = &"tower_shooters"

## Group holding the BODY that is in the tower this round, whoever is driving it.
##
## [b]Why a second way of finding the guard.[/b] [constant SHOOTER_GROUP] finds
## an AI guard, because an AI guard IS a [TowerShooter] node and a running one is
## proof somebody is playing the tower. A human guard has no such node -- see
## [method MatchController._arm_tower_brain], which stands every brain down when
## the seat holder is the human -- so a runner that looked only for shooters
## found nothing, believed the ring had no guard at all, and fell back to the
## baseline lap for the whole round. Every consequence of the cover game went
## with it: no holds, no crossings, and so no slides, which is how the bug was
## noticed.
##
## That was the panopticon's own premise inverted. Which of the two kinds of
## thing is in the tower is exactly what a prisoner cannot see and must not
## branch on, so the match publishes the seat itself and this file reads THAT.
## [MatchController] is the only writer; see [constant MatchController.GUARD_GROUP].
const GUARD_GROUP: StringName = &"tower_guard"

## Seconds between sweeps for a live shooter. The seat changes at most once a
## round, so this is far more often than it needs to be and still costs nothing.
const RESCAN_SECONDS: float = 0.5

## Collision mask used for sight tests when there is no rifle to read one off.
## Everything, which is the safe direction to be wrong in: it can only make the
## runner believe it is hidden less often than it is.
const FALLBACK_SIGHT_MASK: int = 0xFFFFF

var _body: PlayerController = null
var _profile: RunnerProfile = null
var _rules: MatchRules = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## The guard's body, when a live [TowerShooter] is driving one.
var _threat: PlayerController = null

## The rifle whose report this runner is listening for. Held only to connect to
## [signal Rifle.fired]; no state on it is ever read.
var _rifle: Rifle = null

var _rescan_countdown: float = 0.0

## True when the tower is both unobstructed and inside this runner's view.
var _sees_threat: bool = false

## True when nothing solid stands between this runner's chest and the guard's
## eye: the shooter's own shot test, asked from the other end.
var _exposed: bool = true

## This tick's blurred reading of "it is pointed at me", valid only when
## [member _sees_threat].
var _reading: bool = true

## What the runner actually believes, after the reaction delay.
var _believes_watched: bool = true

## How long the current reading has disagreed with the belief.
var _disagreement_seconds: float = 0.0

## How long since the tower was last seen. Past the profile's memory the belief
## reverts to "watched".
var _blind_seconds: float = 0.0

## The current angular error on the attention reading, in radians, and its age.
var _read_bias: float = 0.0
var _read_bias_age: float = 0.0

## Seconds the runner believes are left of the guard's reload. Zero means "it can
## shoot me now", which is what a fresh round starts as.
var _reload_remaining: float = 0.0

## Shots heard since [method configure]. Telemetry only; nothing branches on it.
var _shots_heard: int = 0

## Set on the tick a round lands near this runner, cleared on the next tick.
var _was_shot_at: bool = false


## Point this perception at a body and a difficulty. Safe to call again on every
## round; it forgets everything it believed about the last one.
func configure(body: PlayerController, profile: RunnerProfile, rules: MatchRules) -> void:
	_body = body
	_profile = profile
	_rules = rules
	if profile != null:
		_rng = profile.make_rng()

	_forget_threat()
	_rescan_countdown = 0.0
	_sees_threat = false
	_exposed = true
	_reading = true
	_believes_watched = true
	_disagreement_seconds = 0.0
	_blind_seconds = 0.0
	_read_bias = 0.0
	_read_bias_age = 0.0
	_reload_remaining = 0.0
	_shots_heard = 0
	_was_shot_at = false


## One tick of looking and listening. Everything the brain reads is decided here.
func tick(delta: float) -> void:
	_was_shot_at = false
	if _body == null or _profile == null:
		return

	# A body or a weapon can be torn down under us -- a match world being freed
	# between headless runs is the ordinary case -- and a freed Object is not
	# null, it is invalid. Touching one crashes; disconnecting from one crashes
	# too, which is why the reference is dropped rather than unhooked.
	if _threat != null and not is_instance_valid(_threat):
		_threat = null
	if _rifle != null and not is_instance_valid(_rifle):
		_rifle = null

	_reload_remaining = maxf(_reload_remaining - delta, 0.0)
	_rescan_countdown -= delta
	if _rescan_countdown <= 0.0:
		_rescan_countdown = RESCAN_SECONDS
		_find_threat()

	if _threat == null:
		# No guard on the ring: nothing to hide from, nothing to read.
		_sees_threat = false
		_exposed = true
		_believes_watched = false
		return

	_tick_read_bias(delta)
	_exposed = _has_line_of_sight(_cover_test_point(), _threat_eye())
	_sees_threat = _exposed and _threat_within_view()

	if _sees_threat:
		_blind_seconds = 0.0
		_settle_belief(_read_attention(), delta)
		return

	# Out of sight. The last belief stands until it goes stale, and then the
	# assumption in the game's title takes over.
	_blind_seconds += delta
	if _blind_seconds >= _profile.threat_memory_seconds:
		_settle_belief(true, delta)


# --- Readouts -----------------------------------------------------------------

## True when a live [TowerShooter] is driving a body somewhere on this map.
func has_threat() -> bool:
	return _threat != null


## The guard's body, or null. Held for its position; its aim is never read from
## here.
func get_threat_body() -> PlayerController:
	return _threat


## Where the guard's eye is, which is the point every sight test runs to.
func get_threat_eye() -> Vector3:
	return _threat_eye()


## True when a rifle round could reach this runner where it stands: the shooter's
## own line-of-sight test, asked from the target's end. The negation is "I am in
## cover", and it is the one fact in this file that is exact, because it is a
## property of the world rather than of the guard.
func is_exposed() -> bool:
	return _exposed


## True when the tower is currently both visible and inside this runner's view.
func can_see_threat() -> bool:
	return _sees_threat


## Whether the runner BELIEVES it is being watched. Delayed, blurred, and stale
## whenever it is in cover. Never ground truth.
func believes_watched() -> bool:
	return _believes_watched


## This tick's raw, blurred reading, before the reaction delay is charged.
## Exposed so a verification harness can see the difference between what the
## runner read and what it believes; nothing in the brain reads it.
func is_reading_watched() -> bool:
	return _reading


## Seconds the runner believes are left of the guard's reload.
func get_believed_reload_remaining() -> float:
	return _reload_remaining


## True on the tick a shot landed near enough to this prisoner to be about it.
func was_shot_at() -> bool:
	return _was_shot_at


## Shots heard since the round began. Telemetry.
func get_shots_heard() -> int:
	return _shots_heard


# --- Finding the guard --------------------------------------------------------

## Sweep for whoever is playing the tower: a [TowerShooter] that is actually
## driving a body, or -- when the guard is a human, who has no such brain -- the
## body the match has put in [constant GUARD_GROUP].
##
## The AI sweep runs first and is unchanged: by GROUP and by whether it is
## processing, never by asking the match. A brain that has been stood down still
## exists on the body that used to hold the seat --
## [method MatchController._silence_tower_brain] switches it off rather than
## deleting it -- and a runner that treated a silenced brain as a guard would
## hide from nobody for a whole round. The seat sweep is the fallback rather
## than the primary for the same reason in reverse: a live [TowerShooter] is
## proof that somebody is driving, and a scene with no [MatchController] in it --
## a test fixture, the headless harness -- publishes no seat but does stand up a
## shooter.
##
## What comes out is the same two references either way, so nothing downstream
## of here can tell a human guard from an AI one. That is the point: a prisoner
## reads a body in the tower and the report of a rifle, and both kinds of guard
## have exactly those.
func _find_threat() -> void:
	if _body == null or not _body.is_inside_tree():
		return

	var found: PlayerController = null
	var found_rifle: Rifle = null
	for node: Node in _body.get_tree().get_nodes_in_group(SHOOTER_GROUP):
		var shooter: TowerShooter = node as TowerShooter
		if shooter == null or not shooter.is_physics_processing():
			continue
		if shooter.controller == null or shooter.controller == _body:
			continue
		found = shooter.controller
		found_rifle = shooter.rifle
		break

	if found == null:
		for node: Node in _body.get_tree().get_nodes_in_group(GUARD_GROUP):
			var guard: PlayerController = node as PlayerController
			if guard == null or guard == _body:
				continue
			found = guard
			found_rifle = _rifle_carried_by(guard)
			break

	if found == _threat and found_rifle == _rifle:
		return

	_forget_threat()
	_threat = found
	_listen_to(found_rifle)


## The rifle in [param guard]'s hands, or null.
##
## Found on the body rather than taken from the match, because the rifle really
## is on the body: [method MatchController._attach_rifle] reparents the one rifle
## onto the holder's head on every seat change. Searching for it is what keeps
## this file free of any reference to the match, which is what lets a runner in a
## bare test scene work at all.
##
## The reference is used for exactly one thing -- connecting to
## [signal Rifle.fired], the sound of the shot. No state on it is read; see
## [method _on_shot_heard].
func _rifle_carried_by(guard: PlayerController) -> Rifle:
	var head: Node3D = guard.head if guard.head != null else guard
	for child: Node in head.get_children():
		var weapon: Rifle = child as Rifle
		if weapon != null:
			return weapon
	return null


func _forget_threat() -> void:
	_listen_to(null)
	_threat = null


## Start listening for the report of [param rifle], and stop listening to the
## last one. The seat moves one rifle between bodies, so this changes rarely, but
## a runner still listening to a weapon nobody is holding would run its reload
## clock off silence.
func _listen_to(rifle: Rifle) -> void:
	if rifle == _rifle:
		return
	if _rifle != null and is_instance_valid(_rifle) and _rifle.fired.is_connected(_on_shot_heard):
		_rifle.fired.disconnect(_on_shot_heard)
	_rifle = rifle
	if _rifle != null:
		_rifle.fired.connect(_on_shot_heard)


## A shot went off somewhere on the ring.
##
## [b]This is a sound, not a subscription to the weapon.[/b] The only things
## taken from it are the ones a prisoner standing on the deck would have: that a
## shot happened, which starts the reload clock, and where the round ended, which
## is the tracer. [param _origin] is deliberately unused -- knowing exactly where
## the muzzle was would hand the runner the guard's position to the centimetre,
## and it already knows where the tower is.
func _on_shot_heard(_origin: Vector3, end_point: Vector3) -> void:
	_shots_heard += 1
	_reload_remaining = _believed_reload_window()
	if _body == null or _profile == null:
		return
	if end_point.distance_to(_cover_test_point()) <= _profile.tracer_alarm_metres:
		# That one was about me. No reaction time is charged for it: being shot
		# at is not a thing you have to notice.
		_was_shot_at = true
		_believes_watched = true
		_disagreement_seconds = 0.0
		_blind_seconds = 0.0


## How long the runner thinks it now has, in seconds.
##
## The length of the reload is public -- every prisoner on the ring has been
## listening to it all match -- so the truth comes from the round's rules. What
## is private is how well this prisoner counts it, and that is
## [member RunnerProfile.reload_read_accuracy]: a normal error whose spread grows
## as the accuracy falls, re-drawn on every shot, so a poor reader is sometimes
## early and gets shot and sometimes late and wastes the window.
func _believed_reload_window() -> float:
	var truth: float = _profile.assumed_reload_seconds
	if _rules != null and _rules.base_reload_seconds > 0.0:
		truth = _rules.base_reload_seconds

	var spread: float = (1.0 - _profile.reload_read_accuracy) * 0.5
	var scale: float = 1.0
	if spread > 0.0:
		scale = clampf(1.0 + _rng.randfn(0.0, spread), 0.05, 2.0)
	return maxf(truth * scale - _profile.reload_safety_margin, 0.0)


# --- Reading the guard --------------------------------------------------------

## The blurred reading of "the guard is pointed at me".
##
## [b]The one place the guard's facing is touched, and the reason it is safe.[/b]
## The true angle between where the guard is looking and the line to this runner
## is computed, then [member _read_bias] -- a random offset of up to
## [member RunnerProfile.attention_read_error_degrees] -- is added before it is
## compared with the cone. What leaves this function is a single bit that is
## wrong a knowable fraction of the time, in both directions. Nothing else in the
## codebase may read [member _threat]'s basis.
func _read_attention() -> bool:
	var to_me: Vector3 = _cover_test_point() - _threat_eye()
	var facing: Vector3 = -_threat.global_transform.basis.z
	var flat_to_me: Vector2 = Vector2(to_me.x, to_me.z)
	var flat_facing: Vector2 = Vector2(facing.x, facing.z)
	if flat_to_me.length_squared() <= 0.0 or flat_facing.length_squared() <= 0.0:
		return true
	var offset: float = absf(flat_facing.angle_to(flat_to_me) + _read_bias)
	return offset <= _profile.get_attention_cone_radians()


## Move the belief towards [param reading], but only after it has held for the
## reaction time. Charged in both directions: a guard who sweeps past and back
## inside the reaction window is never registered as having looked away.
func _settle_belief(reading: bool, delta: float) -> void:
	_reading = reading
	if reading == _believes_watched:
		_disagreement_seconds = 0.0
		return
	_disagreement_seconds += delta
	if _disagreement_seconds >= _profile.reaction_seconds:
		_believes_watched = reading
		_disagreement_seconds = 0.0


func _tick_read_bias(delta: float) -> void:
	_read_bias_age += delta
	if _read_bias_age < _profile.attention_resample_seconds:
		return
	_read_bias_age = 0.0
	var limit: float = _profile.get_attention_read_error_radians()
	_read_bias = _rng.randf_range(-limit, limit) if limit > 0.0 else 0.0


## True when the tower sits inside this runner's own field of view.
##
## The same construction as [method TowerShooter._is_within_view], read off the
## runner's head so that turning away really does cost it sight of the guard --
## which is what makes committing to a crossing a decision with a price.
func _threat_within_view() -> bool:
	var eye: Node3D = _eye_node()
	var local: Vector3 = eye.to_local(_threat_eye())
	# -Z is forward for every Node3D in Godot.
	if local.z >= 0.0:
		return false
	var half: Vector2 = _profile.get_view_half_angles()
	var horizontal: float = absf(atan2(local.x, -local.z))
	var vertical: float = absf(atan2(local.y, Vector2(local.x, local.z).length()))
	return horizontal <= half.x and vertical <= half.y


# --- Geometry -----------------------------------------------------------------

## Whether a clear line runs between two points, on the mask the rifle shoots on.
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	if space == null:
		return false

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = _sight_mask()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [_body.get_rid(), _threat.get_rid()] if _threat != null else [_body.get_rid()]
	return space.intersect_ray(query).is_empty()


## Whether a clear line runs from an arbitrary point on the deck to the guard.
## Public because [RunnerCoverFinder] asks exactly this question of every
## candidate it probes, and asking it twice in two files is how the two answers
## come to disagree.
func has_clear_line(from: Vector3, to: Vector3) -> bool:
	if _body == null:
		return false
	return _has_line_of_sight(from, to)


## The mask a shot travels on, so "in cover" means the same thing to the runner
## as it does to the rifle.
func _sight_mask() -> int:
	if _rifle != null and _rifle.profile != null:
		return _rifle.profile.hit_mask
	return FALLBACK_SIGHT_MASK


## The point on this runner a shot would be aimed at, and therefore the point
## every cover test runs from.
func _cover_test_point() -> Vector3:
	return _body.global_position + Vector3.UP * _profile.cover_test_height


func _threat_eye() -> Vector3:
	if _threat == null:
		return Vector3.ZERO
	if _threat.head != null:
		return _threat.head.global_position
	return _threat.global_position + Vector3.UP * _profile.eye_height


## What the runner looks out of: the head if the body has one, so that pitch is
## included, and the body otherwise.
func _eye_node() -> Node3D:
	if _body.head != null:
		return _body.head
	return _body
