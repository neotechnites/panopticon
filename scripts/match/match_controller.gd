class_name MatchController
extends Node

## The match: many rounds, many seat changes, exactly one winner.
##
## Every rule of the match is ENFORCED here and nowhere else, and DECIDED in
## [MatchRules]. The rifle reports what it struck and stays ignorant of what that
## means; [RingRunner] reports that it finished its lap and stays ignorant of
## what that costs; [MatchLapTracker] reports arc and rules on nothing; the
## player's body knows nothing about any of it. This node is the only place that
## turns those reports into a seat change, a round, or a match.
##
## [b]The shape of a match[/b]
##
## [codeblock]
## start_match()
##   |
##   +-- RACE ............ no shooter at all. Every participant runs the ring.
##   |     |               The first to reach the end takes the tower.
##   |     v
##   +-> ROUND ........... one participant in the tower, the rest running.
##         |               No clock.
##         |
##         +-- a runner reaches the end
##         |     -> round resolves LOSS
##         |     -> that runner TAKES THE SEAT (turn count +1, reload recomputed)
##         |     -> the outgoing shooter becomes a runner
##         |     -> the round RESTARTS from the beginning; no progress carries
##         |
##         +-- the shooter converts every runner
##               -> round resolves WIN
##               -> the shooter has won a round FROM THE TOWER
##               -> MATCH_OVER
## [/codeblock]
##
## Reaching the end never wins the match. It wins the tower. The tower is the
## prize, and holding it through a round is the win -- which is why the outcome
## of a round is still named from the shooter's point of view: [constant
## Outcome.WIN] is the shooter converting everyone, [constant Outcome.LOSS] is
## somebody arriving and taking the seat off them.
##
## [b]The seat is a role, not a body[/b]
##
## There is no "the shooter node". There are [MatchParticipant]s, one per player
## for the whole match, and exactly one of them holds the seat at a time. Taking
## the seat means: your body is put on the tower, the rifle is reparented to your
## head, your lap tracker stops, your lap-running brain (if you are AI) is
## switched off, your TOWER brain (if you are AI) is switched on, and your turn
## count goes up. It works identically for the human and for a bot, which is the
## requirement -- when a bot takes the tower the human is put on a lane and runs
## like everybody else.
##
## [b]Two brains, one of them running[/b]
##
## An AI participant owns a [RingRunner] and a [TowerShooter] and is driven by
## exactly one of them, decided by where the match has just put its body:
##
## [codeblock]
## on a lane  -> RingRunner runs,   TowerShooter down
## in the tower -> TowerShooter runs, RingRunner down
## converted, or during the race -> neither
## human, anywhere -> neither; the keyboard drives it
## [/codeblock]
##
## The swap happens in [method _arm_tower_brain], from [method _wake_bodies], on
## the tick the placed bodies come back to life -- which is the only tick on
## which it is safe. See both. What a bot in the tower DOES with the rifle is
## still not this node's business: it is [TowerShooter]'s, and this node only
## points it at the rifle, the eye and the group of legitimate targets that the
## seat change has just changed underneath it.
##
## [b]The terminator[/b]
##
## Each turn in the tower shortens the holder's reload by
## [member MatchRules.reload_reduction_per_turn], down to
## [method MatchRules.get_reload_floor_seconds]. A shooter too weak to close out
## a round loses the seat, wins it back, and comes back faster; eventually fast
## enough. That is the only reason a match is guaranteed to end, and it is why
## [member MatchRules.turn_count_resets_on_seat_loss] defaults to false -- see
## that field for the two readings of "consecutive" and why this one is shipped.
##
## [b]Not implemented, deliberately[/b]
##
## Ghosts ([member MatchRules.ghost_behaviour]), lives beyond
## [member MatchRules.prisoner_lives], and every shooter win condition except
## [constant MatchRules.ShooterWinCondition.TOTAL_CONVERSION]. Those are deferred
## design questions and inventing answers to them here would make the answers
## permanent by accident.

## Where a match is, exhaustively.
enum Phase {
	## Built but not started. [method start_match] leaves it.
	IDLE,
	## The opening race. No shooter, no rifle in anyone's hands, everybody
	## running. Ends the moment somebody reaches the end.
	RACE,
	## One shooter, the rest running. The state a match spends its life in.
	ROUND,
	## Somebody won a round from the tower. Nothing moves and nothing resolves.
	MATCH_OVER,
}

## What a round has come to, from the shooter's point of view. Exhaustive.
enum Outcome {
	## Live. The only state in which a hit or a finished lap means anything.
	IN_PROGRESS,
	## The shooter converted every runner. Under the shipped rules this also
	## wins the match.
	WIN,
	## A runner reached the end. The shooter loses the SEAT, not the match.
	LOSS,
}

## Emitted once, when a match is armed and before the race or the first round
## starts. Carries how many players are in it.
signal match_started(participant_count: int)

## Emitted when the opening race is armed: no shooter, everyone on the ring.
signal race_started()

## Emitted when a round is armed, after the shooter is on the tower and the
## runners are on their lanes. A seat change emits it again, because a seat
## change restarts the round.
signal round_started()

## Emitted whenever the tower changes hands, including the grant that ends the
## opening race and the first round of a match that skipped it.
##
## [param turns_in_tower] is the new holder's own count INCLUDING this turn, so
## it is 1 on their first turn. It is what the reload is computed from.
signal seat_changed(participant: MatchParticipant, turns_in_tower: int)

## Emitted once per round, on the tick it resolves. A [constant Outcome.LOSS] is
## followed immediately by [signal seat_changed] and [signal round_started].
signal round_resolved(outcome: Outcome)

## Emitted once per match, when a participant wins a round from the tower. The
## match stops here: nothing resolves afterwards.
signal match_won(participant: MatchParticipant)

## Emitted when a runner is converted, carrying how many are still running.
signal runner_removed(remaining: int)

## Every design parameter of the match: how many players, on which lanes, at what
## pace, with what reload escalation, and what counts as a win.
##
## Leave it unset and the match runs on a default-constructed [MatchRules] (see
## [method get_rules]). A sweep assigns a variant here and changes nothing else.
@export var rules: MatchRules

## The arena instance. Its origin is the ring axis and the markers are found
## under it by the three paths below.
@export var arena: Node3D

## The human's body. One participant is built around it, and it is put on the
## tower or on a lane exactly like any other participant's.
##
## May be null: a match with no human is every participant AI, which is what a
## headless sweep runs.
@export var player: PlayerController

## The tower's rifle. Reparented to whoever holds the seat, and stowed on this
## node while the opening race runs -- during the race the rifle is nobody's.
@export var rifle: Rifle

## Where AI bodies are parented. They live for the whole match; a converted
## runner is parked, not freed, because the round restarts the moment the seat
## changes and they are back on the ring in the same frame.
@export var runner_container: Node3D

## The body scene AI participants are built from.
@export var runner_scene: PackedScene

@export var start_marker_path: NodePath = ^"StartEnd/PrisonerStart"
@export var end_marker_path: NodePath = ^"StartEnd/PrisonerEnd"
@export var spawn_marker_path: NodePath = ^"Tower/TowerSpawn"

## Arm the match from [method Node._ready]. Off for a harness that wants to place
## things itself before the clock starts.
@export var auto_start: bool = true

## Physical key that restarts the whole match. Read as a physical scancode rather
## than through the input map because the map is [code]project.godot[/code]'s
## business and this scene does not get to add actions to it.
const RESTART_KEY: Key = KEY_R

## Long enough to run any reload out in a single [method Rifle.tick]. Used to
## force the weapon back to READY on a seat change without reaching into its
## state machine: tick() is the weapon's own public harness seam, and one
## enormous step lands on READY from FIRING or RELOADING alike.
const FORCE_READY_SECONDS: float = 3600.0

## Where a converted runner's body is put: straight down, well under the pit
## floor, with its collision switched off and its mesh hidden.
##
## [member MatchRules.ghost_behaviour] is [constant
## MatchRules.GhostBehaviour.NONE], which means a converted prisoner is gone from
## the world -- and this is gone from the world. It is a park rather than a
## [method Node.queue_free] only because the PARTICIPANT outlives the round: they
## are back on the ring the instant somebody takes the seat. Nothing here is a
## ghost; a parked body does not move, cannot be hit and renders nothing.
const PEN_DEPTH_METRES: float = -100.0

## Horizontal spacing between parked bodies, so two of them are not stacked in
## the same cubic metre even though neither can collide.
const PEN_SPACING_METRES: float = 4.0

## The [ShooterProfile] an AI in the tower plays on when [MatchRules] names
## none. The same resource [code]scenes/bot/tower_shooter.tscn[/code] ships
## with, so a bot that takes the seat here plays exactly the shooter that scene
## was tuned as rather than a second, quietly different default.
const DEFAULT_SHOOTER_PROFILE_PATH: String = "res://scenes/bot/default_shooter_profile.tres"

## Physics frames a freshly placed body spends inert before it is woken.
##
## Two rather than one because a seat change can be raised from inside a physics
## frame (a lap tracker finishing) or from an idle one (a harness, a restart key),
## and two frames is correct from either. See [method _place_body_at].
const SETTLE_PHYSICS_FRAMES: int = 2

## Scene-tree group holding exactly the bodies that are RUNNING right now.
##
## The match's answer to "who is a legitimate target". Membership is maintained
## by placement: joined when a participant is put on a lane, left when they take
## the tower or are converted. It is a group rather than a list because the thing
## that needs it is an AI in the tower, which must be able to find its targets
## without a reference to this node -- the same way a human finds them, by
## looking at the ring.
##
## [b]It is not a list of AI.[/b] The human is in it whenever the human is
## running, which is the whole point: a bot holding the seat shoots at the human
## on exactly the terms a human holding the seat shoots at bots.
const RUNNER_GROUP: StringName = &"prisoners"

## Physics frames left before the bodies placed by the last arming are woken.
var _settle_frames: int = 0

var _phase: Phase = Phase.IDLE
var _outcome: Outcome = Outcome.IN_PROGRESS

## Everyone in the match, in a fixed order. Index 0 is the human when there is
## one. The order is the lane assignment and the race's tiebreaker, which is what
## keeps both deterministic rather than a draw.
var _participants: Array[MatchParticipant] = []

## Who holds the tower. Null during the opening race, and only then.
var _seat: MatchParticipant = null

## Who won the match, once somebody has.
var _winner: MatchParticipant = null

## Body instance id -> participant. The rifle hands back the [CollisionObject3D]
## a ray struck; the match thinks in participants. Built at match start from the
## bodies themselves, so it survives any restructuring of the body scene.
var _participant_by_body_id: Dictionary[int, MatchParticipant] = {}

## Rounds armed so far this match. The race is not one.
var _round_number: int = 0

## How many runners the current round or race was armed with.
var _round_runner_count: int = 0

## How many times this controller has resolved a round. A regression in the
## once-only guard shows up here as a number greater than the rounds played.
var _resolve_count: int = 0

## Runners the rifle has converted in the current round.
var _removed_count: int = 0

## Keeps the unimplemented-win-condition complaint to one line per round instead
## of one per frame.
var _warned_unimplemented_rules: bool = false

## Backing store for the rules used when [member rules] is unset. Built on
## demand, never shared, so a caller that retunes it cannot reach into another
## controller's match.
var _fallback_rules: MatchRules

# Arena geometry, cached at match start. The arena does not move.
var _centre: Vector3 = Vector3.ZERO
var _start_point: Vector3 = Vector3.ZERO
var _end_point: Vector3 = Vector3.ZERO
var _tower_point: Vector3 = Vector3.ZERO
var _geometry_ready: bool = false


## The rule set actually in force, never null.
func get_rules() -> MatchRules:
	if rules != null:
		return rules
	if _fallback_rules == null:
		_fallback_rules = MatchRules.new()
	return _fallback_rules


func _ready() -> void:
	if arena == null or rifle == null or runner_scene == null or runner_container == null:
		push_error("MatchController is missing an arena, a rifle, a runner scene or a container; no match will run.")
		return
	rifle.target_hit.connect(_on_target_hit)
	if auto_start:
		start_match()


## Wakes the bodies the last arming placed, once the physics server has caught
## up with where they were put. Does nothing on every other frame.
func _physics_process(_delta: float) -> void:
	if _settle_frames <= 0:
		return
	_settle_frames -= 1
	if _settle_frames == 0:
		_wake_bodies()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == RESTART_KEY:
		start_match()
		get_viewport().set_input_as_handled()


# --- The match ----------------------------------------------------------------

## Tear down whatever match is running and arm a fresh one.
##
## Turn counts, rounds won and the winner all go back to zero: the terminator is
## defined over a player's history within ONE match, so carrying a count across
## restarts would hand the next match a shooter who is already fast.
func start_match() -> void:
	if arena == null or rifle == null:
		push_error("MatchController cannot start a match without an arena and a rifle.")
		return

	var active: MatchRules = get_rules()
	# Once per match, not once per round: a round now restarts on every seat
	# change and a per-round complaint would be a wall of identical warnings.
	for problem: String in active.validate():
		push_warning("MatchRules: %s" % problem)

	_cache_geometry()
	# Before the roster is rebuilt, while the old participants are still here to
	# be read. See the method: difficulty is drawn when a brain is BUILT.
	_release_tower_brains()
	_build_participants()
	if _participants.is_empty():
		push_error("MatchController has no participants; there is nobody to play a match.")
		return

	for participant: MatchParticipant in _participants:
		participant.turns_in_tower = 0
		participant.rounds_won = 0
		participant.is_shooter = false
		participant.is_running = false
	_seat = null
	_winner = null
	_round_number = 0
	_resolve_count = 0
	_removed_count = 0
	_outcome = Outcome.IN_PROGRESS
	_warned_unimplemented_rules = false

	match_started.emit(_participants.size())

	if active.open_with_race and _participants.size() > 1:
		start_race()
	else:
		# No race: the first participant opens the match in the tower on turn
		# one, which is what a single-round harness wants and what the game did
		# before the race existed.
		take_seat(_participants[0])
		start_round()


## Alias for [method start_match], for callers that read better this way.
func restart() -> void:
	start_match()


## Arm the opening race: no shooter, every participant on the ring.
##
## The rifle is stowed on this node rather than left in anyone's hands, because
## "no shooter" has to be true of the world and not merely of a variable.
func start_race() -> void:
	_phase = Phase.RACE
	_outcome = Outcome.IN_PROGRESS
	_removed_count = 0
	_seat = null
	_stow_rifle()
	# "No shooter" has to be true of the BRAINS as well as of the rifle, and
	# true immediately rather than two frames from now, or the racer who held
	# the tower last shoots the field while everybody runs.
	_silence_all_tower_brains()

	_settle_frames = SETTLE_PHYSICS_FRAMES
	var racers: Array[MatchParticipant] = _participants.duplicate()
	_place_runners(racers, true)
	race_started.emit()


## Arm a round with the current seat holder in the tower.
##
## A restart is a real restart: every runner is put back on the start pad with a
## fresh lap tracker, converted runners come back, and the rifle is forced ready.
## Runner progress never carries across a seat change -- that is the design, and
## this is where it is enforced.
##
## With no seat granted yet (a match whose race is still running, or a harness
## that skipped [method start_match]), the first participant takes the tower, so
## a caller who just wants a round gets one.
func start_round() -> void:
	if _participants.is_empty():
		push_error("MatchController cannot arm a round with no participants.")
		return
	if _seat == null:
		take_seat(_participants[0])

	_phase = Phase.ROUND
	_round_number += 1
	_outcome = Outcome.IN_PROGRESS
	_removed_count = 0
	_warned_unimplemented_rules = false

	# Every body about to be placed goes inert until the physics server has
	# caught up. See [method _hold_body]: without it, a seat change drags both
	# the incoming and the outgoing shooter out of the arena. The tower brains
	# go down with them and the seat holder's is brought back up by
	# [method _arm_tower_brain] on the tick they are woken -- a brain aiming
	# from a stand the physics server has not caught up with yet is aiming from
	# the wrong place.
	_silence_all_tower_brains()
	_settle_frames = SETTLE_PHYSICS_FRAMES
	var runners: Array[MatchParticipant] = []
	for participant: MatchParticipant in _participants:
		if participant != _seat:
			runners.append(participant)
	_place_runners(runners, false)
	_place_in_tower(_seat)

	round_started.emit()


## Give the tower to [param participant], counting the turn and retuning the
## reload for it.
##
## Public because the seat is the match's central act and a harness must be able
## to drive it directly. It does NOT arm a round; call [method start_round]
## after, which is what the arrival path does.
func take_seat(participant: MatchParticipant) -> void:
	if participant == null:
		return
	var previous: MatchParticipant = _seat
	if previous != null and previous != participant:
		previous.is_shooter = false
		if get_rules().turn_count_resets_on_seat_loss:
			# The other reading of "consecutive": losing the seat wipes the
			# count and the terminator with it. Off by default; see the rule.
			previous.turns_in_tower = 0

	_seat = participant
	participant.is_shooter = true
	participant.is_running = false
	participant.turns_in_tower += 1

	_attach_rifle(participant)
	_apply_turn_reload(participant)
	seat_changed.emit(participant, participant.turns_in_tower)


# --- Readable state -----------------------------------------------------------

func get_phase() -> Phase:
	return _phase


func get_phase_name() -> String:
	return String(Phase.keys()[_phase])


func get_outcome() -> Outcome:
	return _outcome


func get_outcome_name() -> String:
	return String(Outcome.keys()[_outcome])


func is_resolved() -> bool:
	return _outcome != Outcome.IN_PROGRESS


func is_match_over() -> bool:
	return _phase == Phase.MATCH_OVER


## Everyone in the match, in match order. A copy: callers may iterate freely.
func get_participants() -> Array[MatchParticipant]:
	return _participants.duplicate()


## Who holds the tower, or null during the opening race.
func get_seat_participant() -> MatchParticipant:
	return _seat


## The seat holder's own turn count, including the turn they are on. 0 when
## nobody holds the seat.
func get_seat_turns() -> int:
	return _seat.turns_in_tower if _seat != null else 0


## Who won the match, or null while it is still being played.
func get_match_winner() -> MatchParticipant:
	return _winner


## The reload the tower is running on right now, in seconds.
func get_current_reload_seconds() -> float:
	return rifle.reload_seconds if rifle != null else 0.0


## Rounds armed this match. The opening race is not a round, so this is 0 while
## it runs.
func get_round_number() -> int:
	return _round_number


func get_runners_remaining() -> int:
	var remaining: int = 0
	for participant: MatchParticipant in _participants:
		if participant.is_running:
			remaining += 1
	return remaining


## How many runners the current round or race was armed with. A round has
## [member MatchRules.prisoner_count] of them; the race has every participant.
func get_runners_total() -> int:
	return _round_runner_count


## How many rounds this controller has ever resolved.
func get_resolve_count() -> int:
	return _resolve_count


## Runners the rifle has converted in the current round.
func get_runners_removed() -> int:
	return _removed_count


## The participants still running, as a copy.
func get_live_participants() -> Array[MatchParticipant]:
	var live: Array[MatchParticipant] = []
	for participant: MatchParticipant in _participants:
		if participant.is_running:
			live.append(participant)
	return live


## The AI brains still running, as a copy.
##
## A convenience for callers that think in [RingRunner]s. It cannot see the
## human, who has no brain and never will; [method get_live_participants] is the
## complete list.
func get_live_runners() -> Array[RingRunner]:
	var live: Array[RingRunner] = []
	for participant: MatchParticipant in _participants:
		if participant.is_running and participant.brain != null:
			live.append(participant.brain)
	return live


## Rifle hits [param participant] has left, or 0 if they are not running.
func get_lives_left(participant: MatchParticipant) -> int:
	if participant == null or not participant.is_running:
		return 0
	return participant.lives


## Which participant, if any, a physics collider belongs to.
##
## Walks up from the collider through its ancestors and asks the match-start map
## at each step, so a body with its hitbox on a child node, or reparented under a
## squad node, resolves without a change here. Returns null for the deck, the
## cover, the tower or anything else in the world.
func resolve_participant(collider: Node3D) -> MatchParticipant:
	var node: Node = collider
	while node != null:
		var id: int = node.get_instance_id()
		if _participant_by_body_id.has(id):
			return _participant_by_body_id[id]
		node = node.get_parent()
	return null


## The AI brain a collider belongs to, or null. The human's body resolves to null
## here because the human has no brain; use [method resolve_participant].
func resolve_runner(collider: Node3D) -> RingRunner:
	var participant: MatchParticipant = resolve_participant(collider)
	return participant.brain if participant != null else null


# --- Conversion ---------------------------------------------------------------

## Take a runner out of the round. Returns true if they were in it.
##
## Refuses once the round is resolved, which is half of the once-only guarantee:
## a shot fired in the same frame as an arrival cannot turn a lost seat into a
## won round.
func convert_participant(participant: MatchParticipant) -> bool:
	if participant == null or is_resolved() or _phase != Phase.ROUND:
		return false
	if not participant.is_running:
		return false

	participant.is_running = false
	participant.lives = 0
	_park_body(participant)
	_removed_count += 1

	runner_removed.emit(get_runners_remaining())
	_check_shooter_win()
	return true


## [method convert_participant], for callers holding a [RingRunner].
func remove_runner(runner: RingRunner) -> bool:
	return convert_participant(_participant_of_brain(runner))


## Land one rifle hit on [param participant], spending a life. Returns true if
## that hit converted them.
##
## The one place [member MatchRules.prisoner_lives] is spent. At the default of 1
## this is one hit, one conversion, and above 1 the runner keeps going with no
## hit reaction and no recovery, because neither is designed.
func apply_hit(participant: MatchParticipant) -> bool:
	if participant == null or is_resolved() or not participant.is_running:
		return false
	participant.lives -= 1
	if participant.lives > 0:
		return false
	return convert_participant(participant)


# --- Participants -------------------------------------------------------------

## Build the roster, once per match, reusing bodies where the size has not
## changed.
##
## A match has [method MatchRules.get_participant_count] players: one in the
## tower and [member MatchRules.prisoner_count] on the ring. The human, when
## there is one, takes the first slot; AI bodies fill the rest.
func _build_participants() -> void:
	var wanted: int = get_rules().get_participant_count()
	if _participants.size() == wanted:
		return

	for participant: MatchParticipant in _participants:
		# The human's body belongs to the scene and is only borrowed.
		if not participant.is_human() and participant.body != null:
			participant.body.queue_free()
	_participants.clear()
	_participant_by_body_id.clear()

	if player != null:
		_participants.append(_make_human_participant())

	var pool: PackedFloat32Array = get_rules().get_lane_radii_for(wanted)
	while _participants.size() < wanted:
		var slot: int = _participants.size()
		var ai: MatchParticipant = _make_ai_participant(slot, pool[slot])
		if ai == null:
			break
		_participants.append(ai)

	for index: int in _participants.size():
		var participant: MatchParticipant = _participants[index]
		participant.index = index
		if participant.body != null:
			_participant_by_body_id[participant.body.get_instance_id()] = participant


func _make_human_participant() -> MatchParticipant:
	var participant: MatchParticipant = MatchParticipant.new()
	participant.kind = MatchParticipant.Kind.HUMAN
	participant.display_name = "You"
	participant.body = player
	participant.home_collision_layer = player.collision_layer
	participant.home_collision_mask = player.collision_mask
	participant.tracker = _attach_tracker(player)
	participant.tracker.lap_finished.connect(_on_participant_arrived.bind(participant))
	return participant


## Instance one AI body, place it, and wire a brain and a tracker to it.
##
## [param spawn_radius] is only where the body is put down before it enters the
## tree; the lane it actually runs is assigned per round. Placing it at all is
## the point: a body added to the tree is registered by the physics server at the
## position it holds AT THAT MOMENT, and a body added at the scene default sits
## at the origin -- which is the tower spawn. Three capsules materialising inside
## the shooter threw them across the arena once already.
func _make_ai_participant(slot: int, spawn_radius: float) -> MatchParticipant:
	var body: PlayerController = runner_scene.instantiate() as PlayerController
	if body == null:
		push_error("MatchController's runner scene does not have a PlayerController at its root.")
		return null

	body.name = "Runner_%d" % slot
	body.position = runner_container.to_local(_point_on_lane(spawn_radius, _angle_of(_start_point)))
	runner_container.add_child(body)

	var brain: RingRunner = _find_brain(body)
	if brain == null:
		push_error("MatchController's runner scene has no RingRunner brain; the runner will not run.")
		body.queue_free()
		return null

	# Duplicate the profile: the scene's is a shared resource, and writing a lane
	# radius into it would retune every runner ever spawned from it, including
	# the ones already running.
	var profile: BotProfile = brain.profile.duplicate() as BotProfile
	brain.profile = profile

	var participant: MatchParticipant = MatchParticipant.new()
	participant.kind = MatchParticipant.Kind.AI
	participant.display_name = "Runner %d" % slot
	participant.body = body
	participant.brain = brain
	participant.home_collision_layer = body.collision_layer
	participant.home_collision_mask = body.collision_mask
	participant.tracker = _attach_tracker(body)
	participant.tracker.lap_finished.connect(_on_participant_arrived.bind(participant))
	return participant


func _attach_tracker(body: PlayerController) -> MatchLapTracker:
	var existing: MatchLapTracker = _find_tracker(body)
	if existing != null:
		return existing
	var tracker: MatchLapTracker = MatchLapTracker.new()
	tracker.name = "LapTracker"
	body.add_child(tracker)
	return tracker


func _find_tracker(body: Node) -> MatchLapTracker:
	for child: Node in body.get_children():
		var tracker: MatchLapTracker = child as MatchLapTracker
		if tracker != null:
			return tracker
	return null


## The brain, found by type rather than by path.
func _find_brain(body: Node) -> RingRunner:
	for child: Node in body.get_children():
		var brain: RingRunner = child as RingRunner
		if brain != null:
			return brain
	return null


func _participant_of_brain(brain: RingRunner) -> MatchParticipant:
	if brain == null:
		return null
	for participant: MatchParticipant in _participants:
		if participant.brain == brain:
			return participant
	return null


# --- Placement ----------------------------------------------------------------

func _cache_geometry() -> void:
	var start_marker: Marker3D = arena.get_node_or_null(start_marker_path) as Marker3D
	var end_marker: Marker3D = arena.get_node_or_null(end_marker_path) as Marker3D
	var spawn_marker: Marker3D = arena.get_node_or_null(spawn_marker_path) as Marker3D
	if start_marker == null or end_marker == null or spawn_marker == null:
		push_error("MatchController cannot find the PrisonerStart/PrisonerEnd/TowerSpawn markers.")
		_geometry_ready = false
		return
	_centre = arena.global_position
	_start_point = start_marker.global_position
	_end_point = end_marker.global_position
	_tower_point = spawn_marker.global_position
	_geometry_ready = true


## Put every participant in [param runners] on a lane and start them running.
##
## Lanes are handed out in match order, which is deterministic: the opening race
## decides the tower, and a race decided by a draw would be exactly the thing the
## design forbids. A lane is a spawn position, not a rail -- only the baseline
## [RingRunner] holds a radius, and scoring is by arc, so a human is free to cut
## to the inside kerb and still owes the whole ring.
func _place_runners(runners: Array[MatchParticipant], is_race: bool) -> void:
	_round_runner_count = runners.size()
	if not _geometry_ready:
		return

	var active: MatchRules = get_rules()
	var radii: PackedFloat32Array = active.get_lane_radii_for(runners.size())
	var equalise: bool = is_race and active.equalise_race_lane_distance
	var shortest: float = _shortest_radius(radii)
	var end_angle: float = _angle_of(_end_point)
	var full_arc: float = wrapf(
		(end_angle - _angle_of(_start_point)) * RingRunner.TRAVEL_SIGN, 0.0, TAU
	)

	for index: int in runners.size():
		var participant: MatchParticipant = runners[index]
		var radius: float = radii[index]
		var start_angle: float = _angle_of(_start_point)
		if equalise and radius > 0.0:
			# Every racer is left the same number of METRES of their own lane,
			# so the outer lanes start further round. See
			# MatchRules.equalise_race_lane_distance for why this is off by
			# default.
			start_angle = end_angle - RingRunner.TRAVEL_SIGN * (full_arc * shortest / radius)
		_place_on_lane(participant, radius, start_angle)


func _place_on_lane(participant: MatchParticipant, radius: float, start_angle: float) -> void:
	var active: MatchRules = get_rules()
	var start_point: Vector3 = _point_on_lane(radius, start_angle)

	participant.lane_radius = radius
	participant.is_shooter = false
	participant.is_running = true
	participant.lives = maxi(active.prisoner_lives, 1)

	var body: PlayerController = participant.body
	_hold_body(participant)
	# A body on a lane runs; it does not play the tower. The outgoing shooter
	# arrives here on every seat change with its tower brain still loaded.
	_silence_tower_brain(participant)
	if participant.brain != null:
		# The brain reads pace from the rules and geometry from its profile. The
		# split is the seam: "walk or sprint" is a rule of the round, "how hard
		# does it steer" is tuning of the brain. configure() places the body.
		participant.brain.profile.lane_radius = radius
		participant.brain.rules = active
		participant.brain.configure(_centre, start_point, _end_point)
	else:
		body.global_position = start_point
		body.velocity = Vector3.ZERO
		# Face down the lane. A human teleported to the start line facing the
		# outer wall would spend their first second turning round, and that
		# second is part of the race.
		body.rotation = Vector3(0.0, _heading_of(_lane_tangent(start_angle)), 0.0)

	body.add_to_group(RUNNER_GROUP)
	participant.tracker.begin(body, _centre, start_point, _end_point, active.lap_arrival_tolerance)


func _place_in_tower(participant: MatchParticipant) -> void:
	if participant == null:
		return
	participant.is_shooter = true
	participant.is_running = false
	participant.lane_radius = 0.0

	var body: PlayerController = participant.body
	_hold_body(participant)
	body.global_position = _tower_point
	body.velocity = Vector3.ZERO
	# Out of the target group, which is the whole of "the tower cannot be shot":
	# an AI shooter's candidate list IS this group, so a seat holder left in it
	# would be a legitimate target for the next occupant -- and, but for
	# [TowerShooter]'s own self-check, for itself.
	body.remove_from_group(RUNNER_GROUP)
	participant.tracker.stop()
	# The lap brain goes down here; the tower brain comes up in
	# [method _arm_tower_brain] once the body has been woken.
	_silence_brain(participant)


## Make a body inert for the placement: visible, but solid to nothing and moving
## under its own power not at all. [method _wake_bodies] undoes it.
##
## [b]This is the spawn-ejection trap in its second and nastier form, and it cost
## an afternoon.[/b] The known form is a body ADDED to the tree at the origin:
## the physics server registers it where it was at that moment. The form that
## bites a MATCH is a body MOVED while another body stands on the point it is
## moving away from -- which is every seat change, because the incoming shooter
## is put exactly where the outgoing one is standing.
##
## Setting [member Node3D.global_position] on a [CharacterBody3D] is not a
## teleport as far as the physics server is concerned. The body is kinematic, so
## the server treats the change as MOTION from the transform it last flushed to
## the new one, and a kinematic body that moves CARRIES whatever is standing at
## the start of that motion. Measured, with the tower at the origin: the outgoing
## shooter is sent to its lane, picks up the incoming shooter who has just been
## put on the tower, and deposits it 38 m away on top of itself; both then slide
## off the deck and out to the wall at r=59, gaining height the whole way, while
## the node graph insists the shooter is standing on the tower. Ordering the two
## placements the other way round does not help: only the last transform written
## in a frame is ever flushed, so the server sees the same swap either way.
##
## What does help is placing the body with nothing to collide with, and turning
## its collision back on once the server has flushed the new transform -- which
## is [constant SETTLE_PHYSICS_FRAMES] frames later. The position is correct
## IMMEDIATELY, so the HUD, a test and this file all read the truth; only the
## physics is deferred, and only by two frames.
func _hold_body(participant: MatchParticipant) -> void:
	var body: PlayerController = participant.body
	body.visible = true
	body.velocity = Vector3.ZERO
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_physics_process(false)


## Give every placed body its collision and its motion back. Converted runners
## are left parked: they are out of the round and must stay unhittable.
func _wake_bodies() -> void:
	for participant: MatchParticipant in _participants:
		if not (participant.is_shooter or participant.is_running):
			continue
		var body: PlayerController = participant.body
		body.collision_layer = participant.home_collision_layer
		body.collision_mask = participant.home_collision_mask
		body.set_physics_process(true)
	_arm_tower_brain()


## Put a converted runner's body out of the world: hidden, uncollidable, stopped
## and buried. See [constant PEN_DEPTH_METRES].
func _park_body(participant: MatchParticipant) -> void:
	var body: PlayerController = participant.body
	participant.tracker.stop()
	_silence_brain(participant)
	_silence_tower_brain(participant)
	body.velocity = Vector3.ZERO
	body.set_physics_process(false)
	body.remove_from_group(RUNNER_GROUP)
	body.visible = false
	body.collision_layer = 0
	body.collision_mask = 0
	body.global_position = _pen_point(participant.index)


## Where body number [param index] is put when it is out of the world. Distinct
## per participant, so two parked or vacated bodies never share a point.
func _pen_point(index: int) -> Vector3:
	return _centre + Vector3(
		float(index) * PEN_SPACING_METRES, PEN_DEPTH_METRES, 0.0
	)


## Stop a participant's lap-running brain and drop the controls it was holding.
## A shooter does not run laps, and neither does a converted runner.
func _silence_brain(participant: MatchParticipant) -> void:
	if participant.brain == null:
		return
	participant.brain.set_physics_process(false)
	if participant.brain.input != null:
		participant.brain.input.command.clear()


# --- The tower's brain --------------------------------------------------------

## Put the right brain behind every body, now that the placement has settled.
##
## This is the seat change as the BODIES experience it. [method take_seat] moves
## the rifle and counts the turn; this decides who is actually driving.
##
## [b]Why it runs from [method _wake_bodies] and not from [method take_seat][/b]
##
## Two reasons, both measured rather than assumed. A placed body is inert for
## [constant SETTLE_PHYSICS_FRAMES] frames -- see [method _hold_body] -- so a
## brain started any earlier would be writing intent at a controller whose
## physics is switched off, and aiming from a stand the physics server has not
## flushed yet. And this is deliberately the LAST word on the subject: anything
## else that has attached a [TowerShooter] to one of these bodies is stood down
## here and, if it is on the seat holder, adopted rather than duplicated. Two
## shooters on one body do not take turns -- they both write a look rate into
## the same [MoveIntent] every tick, from two different aim errors, and the head
## shakes between them.
func _arm_tower_brain() -> void:
	_silence_all_tower_brains()
	if _phase != Phase.ROUND or _seat == null or _seat.is_human():
		# The opening race has no shooter, and a human in the tower is driven by
		# the human. Either way every brain stays down: an AI that fought the
		# player for their own look axis would be the worst bug in the game.
		return

	var shooter: TowerShooter = _tower_brain_of(_seat)
	if shooter == null:
		return

	var body: PlayerController = _seat.body
	# Re-pointed on EVERY seat change, because every one of these moved. There
	# is one rifle and [method _attach_rifle] has just reparented it onto this
	# body's head and repointed its aim source at this body's eye; the camera
	# whose frustum decides what the bot can see and the optic that narrows it
	# are this body's too. A brain left pointing at the previous holder's head
	# would search the ring from a node standing on a lane.
	shooter.rifle = rifle
	shooter.rules = get_rules()
	shooter.target_group = RUNNER_GROUP
	shooter.camera = body.get_node_or_null(^"Head/Camera") as Camera3D
	shooter.optic = body.get_node_or_null(^"Optic") as WeaponOptic
	# The profile is deliberately NOT reassigned here. [TowerShooter] draws its
	# aim RNG from the profile in _ready, so writing one now would retune the
	# shooter without re-drawing its seed -- a difficulty that is half the new
	# setting and half the old one, which is the worst of the three states. A
	# rule set that has genuinely changed is picked up by
	# [method _release_tower_brains] at the next [method start_match]. Leaving
	# it alone also means a brain somebody else built and tuned -- the headless
	# harness seeds its own -- is driven rather than quietly overridden.
	# Where the body ALREADY is, never where it ought to be. configure() writes
	# global_position, and on a woken body that is motion, not a teleport -- see
	# [method _hold_body] for what that costs. Passing the current position
	# makes the write a no-op the physics server has nothing to do with.
	shooter.configure(body.global_position, body.rotation.y)


## Stop a participant's tower brain and drop the controls it was holding.
##
## The mirror of [method _silence_brain]. Idempotent, and silent when the brain
## was not running: clearing a [MoveIntent] that a live [RingRunner] wrote this
## tick would cost that runner a tick of movement for no reason.
func _silence_tower_brain(participant: MatchParticipant) -> void:
	var shooter: TowerShooter = _find_tower_brain(participant)
	if shooter == null or not shooter.is_physics_processing():
		return
	shooter.set_physics_process(false)
	if shooter.input != null:
		shooter.input.command.clear()


func _silence_all_tower_brains() -> void:
	for participant: MatchParticipant in _participants:
		_silence_tower_brain(participant)


## The tower brain already on [param participant]'s body, or null.
##
## Found by TYPE, exactly as [method _find_brain] finds the lap-running one, and
## then cached on the participant. Searching rather than trusting the cache the
## first time is what lets a brain this node did not build be ADOPTED instead of
## duplicated -- the headless harness has historically attached its own, and a
## body driven by two shooters is the failure described in
## [method _arm_tower_brain].
func _find_tower_brain(participant: MatchParticipant) -> TowerShooter:
	if participant == null:
		return null
	if participant.tower_brain != null and is_instance_valid(participant.tower_brain):
		return participant.tower_brain
	if participant.body == null:
		return null
	for child: Node in participant.body.get_children():
		var shooter: TowerShooter = child as TowerShooter
		if shooter != null:
			participant.tower_brain = shooter
			return shooter
	return null


## The brain that plays the tower for [param participant], built on first use.
##
## Built rather than instanced from [code]scenes/bot/tower_shooter.tscn[/code],
## because that scene is a whole BODY. The participant already has a body, a
## head, a camera and an optic -- the same ones it runs the ring with, which is
## the entire point of a seat that is a role -- so the only thing missing is the
## brain, and the brain is a bare [Node] with five references.
##
## Null for the human, who is driven from the keyboard, and null for any body
## whose intent does not come from a [BotIntentSource]: a [MoveIntent] written
## somewhere the controller never polls produces a shooter that looks wired and
## never turns.
func _tower_brain_of(participant: MatchParticipant) -> TowerShooter:
	if participant == null or participant.is_human() or participant.body == null:
		return null
	var existing: TowerShooter = _find_tower_brain(participant)
	if existing != null:
		return existing

	var body: PlayerController = participant.body
	var input: BotIntentSource = body.intent_source as BotIntentSource
	if input == null:
		push_error(
			"MatchController cannot give %s the tower: its intent_source is not a BotIntentSource."
			% participant.display_name
		)
		return null

	var profile: ShooterProfile = _shooter_profile_for(participant)
	if profile == null:
		return null

	var shooter: TowerShooter = TowerShooter.new()
	shooter.name = "TowerBrain"
	shooter.controller = body
	shooter.input = input
	shooter.rifle = rifle
	shooter.optic = body.get_node_or_null(^"Optic") as WeaponOptic
	shooter.camera = body.get_node_or_null(^"Head/Camera") as Camera3D
	shooter.rules = get_rules()
	# The match's own answer to "who is a legitimate target", so the bot's
	# candidate list is exactly the live runners and the match does not have to
	# maintain a second list that could disagree with the first.
	shooter.target_group = RUNNER_GROUP
	# Every reference is set BEFORE the node enters the tree, for two reasons:
	# TowerShooter._ready refuses to play and disables itself if any of the four
	# required ones is missing, and it seeds its aim RNG from the profile there.
	# A profile assigned afterwards retunes the shooter but cannot re-draw its
	# seed.
	shooter.profile = profile
	body.add_child(shooter)
	participant.tower_brain = shooter
	return shooter


## A private [ShooterProfile] for [param participant], chosen by the rules.
##
## This is where match DIFFICULTY is decided, and it is decided from
## [MatchRules] so that a headless sweep can vary it per match and per
## participant without touching a scene. See
## [member MatchRules.ai_shooter_profiles].
##
## The chosen resource is duplicated, never used directly:
## [member MatchRules.ai_shooter_aim_seed] is written into the COPY, and a sweep
## that wrote it into the .tres would hand every later match in the same process
## a shooter an earlier one had quietly retuned.
func _shooter_profile_for(participant: MatchParticipant) -> ShooterProfile:
	var active: MatchRules = get_rules()
	var chosen: ShooterProfile = active.get_ai_shooter_profile_for(participant.index)
	if chosen == null:
		chosen = load(DEFAULT_SHOOTER_PROFILE_PATH) as ShooterProfile
	if chosen == null:
		push_error(
			"MatchController cannot load %s and the rules name no ShooterProfile; %s will stand in the tower doing nothing."
			% [DEFAULT_SHOOTER_PROFILE_PATH, participant.display_name]
		)
		return null

	var copy: ShooterProfile = chosen.duplicate() as ShooterProfile
	var seed_value: int = active.get_ai_shooter_seed_for(participant.index)
	if seed_value != 0:
		copy.aim_random_seed = seed_value
	return copy


## Throw away the tower brains a previous match built, so the next one is played
## on the rules in force NOW.
##
## Difficulty is drawn once, when a brain is built: see the comment in
## [method _arm_tower_brain] for why a live brain cannot simply be handed a new
## [ShooterProfile]. Rebuilding is therefore the only way a swept [MatchRules]
## reaches a controller that has already played a match, and it costs one [Node]
## per AI participant per match.
##
## Removed from the tree as well as freed, so that a brain queued for deletion
## cannot still be found by [method _find_tower_brain] on the same frame.
func _release_tower_brains() -> void:
	for participant: MatchParticipant in _participants:
		var shooter: TowerShooter = _find_tower_brain(participant)
		participant.tower_brain = null
		if shooter == null:
			continue
		shooter.set_physics_process(false)
		var parent: Node = shooter.get_parent()
		if parent != null:
			parent.remove_child(shooter)
		shooter.queue_free()


# --- The rifle ----------------------------------------------------------------

## Move the rifle onto [param participant]'s head and point it at their eye.
##
## This is what "the seat is a role" means in practice: there is one rifle, and
## it belongs to whoever is in the tower. The human's trigger is switched off
## whenever the holder is not the human, so a bot in the tower cannot be fired by
## somebody else's mouse.
func _attach_rifle(participant: MatchParticipant) -> void:
	if rifle == null:
		return
	var body: PlayerController = participant.body
	var head: Node3D = body.head if body.head != null else body
	if rifle.get_parent() != head:
		var parent: Node = rifle.get_parent()
		if parent != null:
			parent.remove_child(rifle)
		head.add_child(rifle)
	rifle.transform = Transform3D.IDENTITY

	# The shot line is the eye's, so a bot aims the same rifle through the same
	# field with no camera of its own -- a head pivot is enough.
	var camera: Camera3D = head.get_node_or_null(^"Camera") as Camera3D
	rifle.aim_source = camera if camera != null else head
	rifle.shooter_body = body
	rifle.rules = get_rules()
	_set_human_trigger(participant.is_human())


## Take the rifle out of everyone's hands. The opening race has no shooter, and
## that has to be true of the world, not just of a variable.
func _stow_rifle() -> void:
	if rifle == null:
		return
	if rifle.get_parent() != self:
		var parent: Node = rifle.get_parent()
		if parent != null:
			parent.remove_child(rifle)
		add_child(rifle)
	rifle.aim_source = null
	rifle.shooter_body = null
	_set_human_trigger(false)


func _set_human_trigger(active: bool) -> void:
	var trigger: WeaponInput = _find_trigger(rifle)
	if trigger != null:
		trigger.set_active(active)


func _find_trigger(node: Node) -> WeaponInput:
	for child: Node in node.get_children():
		var trigger: WeaponInput = child as WeaponInput
		if trigger != null:
			return trigger
	return null


## Retune the rifle for the holder's turn count and force it ready.
##
## The escalation is the match's terminator. It is applied on the seat change
## rather than at round start so that a holder who wins a round and starts
## another gets the turn they have earned, and so the HUD's reload readout is
## correct the instant the tower changes hands.
func _apply_turn_reload(participant: MatchParticipant) -> void:
	if rifle == null:
		return
	var active: MatchRules = get_rules()
	rifle.rules = active
	var weapon_base: float = rifle.profile.base_reload_seconds if rifle.profile != null else 0.0
	var weapon_floor: float = rifle.profile.min_reload_seconds if rifle.profile != null else 0.0
	rifle.reload_seconds = active.get_reload_seconds_for_turn(
		participant.get_turn_index(), weapon_base, weapon_floor
	)
	rifle.tick(FORCE_READY_SECONDS)


# --- Resolution ---------------------------------------------------------------

func _on_target_hit(collider: Node3D, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	if _phase != Phase.ROUND or is_resolved():
		return
	var participant: MatchParticipant = resolve_participant(collider)
	if participant == null:
		# The shot hit the world. A miss costs the same reload either way, which
		# is the rifle's business and not this node's.
		return
	apply_hit(participant)


## Somebody reached the end. What that is worth depends entirely on the phase:
## in the race it is the tower, in a round it is the tower AND the round, and it
## is never the match.
func _on_participant_arrived(
	_elapsed_seconds: float, _path_length: float, participant: MatchParticipant
) -> void:
	if participant == null or not participant.is_running:
		return

	match _phase:
		Phase.RACE:
			# First past the post takes the seat and the race is over. Later
			# arrivals in the same frame find the phase already changed.
			take_seat(participant)
			start_round()
		Phase.ROUND:
			if is_resolved():
				return
			match get_rules().runner_win_condition:
				MatchRules.RunnerWinCondition.FIRST_ARRIVAL:
					_score_and_restart(participant)
				MatchRules.RunnerWinCondition.ALL_ARRIVALS:
					# Every runner still in the round has to make it. The one
					# who completes the set takes the seat.
					if _all_running_have_finished():
						_score_and_restart(participant)
		_:
			return


## A runner scored: the round is over, the seat changes hands, and the round
## starts again from the beginning. The outgoing shooter is put on a lane by
## [method start_round] like everybody else.
func _score_and_restart(scorer: MatchParticipant) -> void:
	_resolve(Outcome.LOSS)
	take_seat(scorer)
	start_round()


func _all_running_have_finished() -> bool:
	for participant: MatchParticipant in _participants:
		if participant.is_running and not participant.tracker.has_finished():
			return false
	return true


## Resolve a WIN if [member MatchRules.shooter_win_condition] has been met.
##
## Only total conversion is implemented; the other conditions deliberately never
## fire and complain once per round rather than falling back on total conversion,
## because a sweep that quietly measured a different rule than the one it
## selected is the worst outcome available here.
func _check_shooter_win() -> void:
	if is_resolved():
		return
	var active: MatchRules = get_rules()
	match active.shooter_win_condition:
		MatchRules.ShooterWinCondition.TOTAL_CONVERSION:
			if get_runners_remaining() == 0:
				_resolve(Outcome.WIN)
				_award_round_to_shooter()
		_:
			if not _warned_unimplemented_rules:
				_warned_unimplemented_rules = true
				push_warning(
					"MatchController: shooter_win_condition %s is not implemented; this round cannot be won."
					% String(MatchRules.ShooterWinCondition.keys()[active.shooter_win_condition])
				)


## The shooter held the tower through a round. That, and only that, wins a match.
func _award_round_to_shooter() -> void:
	if _seat == null:
		return
	_seat.rounds_won += 1
	if _seat.rounds_won >= maxi(get_rules().rounds_to_win_match, 1):
		_win_match(_seat)
		return
	# More rounds to defend: the same player keeps the seat and begins another
	# turn in the tower, which is a turn like any other and earns its reduction.
	take_seat(_seat)
	start_round()


func _win_match(participant: MatchParticipant) -> void:
	_phase = Phase.MATCH_OVER
	_winner = participant
	_freeze_everyone()
	_set_human_trigger(false)
	match_won.emit(participant)


func _resolve(outcome: Outcome) -> void:
	if is_resolved():
		return
	_outcome = outcome
	_resolve_count += 1
	_freeze_runners()
	round_resolved.emit(_outcome)


## Stop the survivors dead the moment the round is decided.
##
## Not cosmetic: without it, the runners still on the ring after a seat change go
## on to finish their own laps a second later and score a seat change of their
## own. The guard in [method _resolve] would swallow those, but a frozen ring is
## the honest picture of a round that is over.
func _freeze_runners() -> void:
	for participant: MatchParticipant in _participants:
		if participant.is_running:
			_silence_brain(participant)
			participant.tracker.stop()
			participant.body.velocity = Vector3.ZERO


## Stop everything, including the tower. Only a won match does this.
func _freeze_everyone() -> void:
	# Cancel any pending wake, or the settle tick would put the bodies back on
	# their feet a frame after the match ended.
	_settle_frames = 0
	for participant: MatchParticipant in _participants:
		_silence_brain(participant)
		_silence_tower_brain(participant)
		participant.tracker.stop()
		participant.body.velocity = Vector3.ZERO
		participant.body.set_physics_process(false)


# --- Ring geometry ------------------------------------------------------------

func _angle_of(point: Vector3) -> float:
	return atan2(point.z - _centre.z, point.x - _centre.x)


func _point_on_lane(radius: float, angle: float) -> Vector3:
	return _centre + Vector3(cos(angle), 0.0, sin(angle)) * radius


func _lane_tangent(angle: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, cos(angle)) * RingRunner.TRAVEL_SIGN


## Body yaw, in radians, that points the controller's forward axis along
## [param direction]. Forward is -Z, hence the double negation.
func _heading_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func _shortest_radius(radii: PackedFloat32Array) -> float:
	var shortest: float = 0.0
	for index: int in radii.size():
		if index == 0 or radii[index] < shortest:
			shortest = radii[index]
	return shortest
