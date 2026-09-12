class_name BotMatchTelemetry
extends Node

## Watches one match and counts what a balance question is actually made of.
##
## Every number here comes from a [MatchController] SIGNAL or a [Rifle] signal.
## Nothing is read out of the match's internals and nothing is inferred from a
## field name, so this file keeps working across a re-authored match as long as
## the signals keep their meanings. Where the match grows a concept the harness
## cannot see -- a fifth signal, a new phase -- the effect is a missing column,
## not a wrong one.
##
## [b]The clock[/b]
##
## Time is counted in PHYSICS TICKS and divided by the simulated rate at the
## end. Not [method Time.get_ticks_msec], which under time compression measures
## the host machine, and not an accumulated delta, which accumulates float error
## over the tens of thousands of ticks a long match takes. A tick count is exact
## and is the same number on every machine.

## Ticks elapsed since the match started, counted by this node's own physics
## callback. [member Node.process_priority] is lowered by the installer so this
## runs before the match does, and a signal fired later in the same tick is
## attributed to the tick it happened in.
var _ticks: int = 0

var _controller: MatchController = null
var _rifle: Rifle = null

var _tallies: Dictionary[int, BotParticipantTally] = {}
var _order: Array[int] = []

var _participants_total: int = 0
var _race_ran: bool = false
var _rounds_started: int = 0
var _rounds_resolved: int = 0
var _round_wins: int = 0
var _round_losses: int = 0
var _seat_changes: int = 0
var _conversions: int = 0

## Conversions that were a hazard entry on the same tick, not a rifle hit.
var _hazard_deaths: int = 0
var _removed_tick: int = -1
var _hazard_attributed: Dictionary = {}

const STALL_WINDOW_TICKS: int = 180
const STALL_DISTANCE_METRES: float = 1.0

## Per participant index: stall window origin, hold and stall streaks.
var _watch: Dictionary = {}
var _round_tick: int = -1
var _first_shot_pending: bool = false
var _rounds_without_a_shot: int = 0
var _first_shots: Array[float] = []

## Wall microseconds per physics tick, and what the bots charged inside it.
var _last_tick_usec: int = -1
var _tick_max_usec: int = 0
var _tick_sum_usec: int = 0
var _cost_max: Dictionary = {}
var _cost_sum: Dictionary = {}
var _tick_over_16ms: int = 0

## Participants turned into ghosts, by either route: shot by the rifle, or caught
## by another ghost. Zero on every ghostless match, which is what makes it safe
## to leave in the schema unconditionally.
var _ghosts_made: int = 0

## Ghost swaps: a ghost reaching a living prisoner and taking their spot. The one
## number the whole mechanic is about -- a ghost round with no catches in it is a
## round where the speed advantage was not enough.
var _ghost_catches: int = 0

var _shots_fired: int = 0
var _shots_hit_participant: int = 0
var _shots_hit_world: int = 0
var _shots_hit_nothing: int = 0

## Who holds the tower and since when, so the seat's time can be closed out on
## the next change. -1 means nobody, which is the truth during the opening race.
var _seat_index: int = -1
var _seat_since_tick: int = 0

## Who fired the shot currently being resolved.
##
## Separate from [member _seat_index] because of an ordering that cost a shot
## the first time it was measured: [MatchController] connects to
## [signal Rifle.target_hit] before the harness does, so a shot that converts
## the last runner has already run the whole match-winning cascade -- resolve,
## award, freeze, [signal MatchController.match_won] -- by the time this file
## sees the hit, and the seat has been closed out. Attributing shots to the
## seat's LAST KNOWN holder instead of its CURRENT one credits that shot to the
## bot that actually took it. It is only ever wrong if a shot is fired by
## nobody, which cannot happen: there is one rifle and the match hands it to
## the seat.
var _shooter_index: int = -1

var _winner_index: int = -1
var _winner_was_seat: bool = false
var _match_over: bool = false


func install(controller: MatchController, rifle: Rifle) -> void:
	_controller = controller
	_rifle = rifle

	controller.match_started.connect(_on_match_started)
	controller.race_started.connect(_on_race_started)
	controller.round_started.connect(_on_round_started)
	controller.seat_changed.connect(_on_seat_changed)
	controller.round_resolved.connect(_on_round_resolved)
	controller.runner_removed.connect(_on_runner_removed)
	controller.runner_ghosted.connect(_on_runner_ghosted)
	controller.ghost_caught.connect(_on_ghost_caught)
	controller.match_won.connect(_on_match_won)

	rifle.fired.connect(_on_fired)
	rifle.target_hit.connect(_on_target_hit)
	rifle.missed.connect(_on_missed)
	_connect_hazards(controller.arena)


func _connect_hazards(node: Node) -> void:
	if node == null:
		return
	if node is TrapVolume:
		(node as Area3D).body_entered.connect(_on_hazard_entered.bind(true))
	elif node is KillVolume:
		(node as Area3D).body_entered.connect(_on_hazard_entered.bind(false))
	elif node is BoostPad:
		(node as Area3D).body_entered.connect(_on_pad_entered)
	for child: Node in node.get_children():
		_connect_hazards(child)


## Runs after the hazard's own handler: a removal on this tick was the hazard's doing.
func _on_hazard_entered(body: Node3D, lava: bool) -> void:
	if _removed_tick != _ticks:
		return
	var participant: MatchParticipant = _controller.resolve_participant(body)
	if participant == null or participant.is_shooter:
		return
	if int(_hazard_attributed.get(participant.index, -1)) == _ticks:
		return
	_hazard_attributed[participant.index] = _ticks
	_hazard_deaths += 1
	var tally: BotParticipantTally = _tallies.get(participant.index, null)
	if tally != null:
		tally.hazard_deaths += 1
		if lava:
			tally.lava_deaths += 1
		else:
			tally.falls += 1


func _on_pad_entered(body: Node3D) -> void:
	var participant: MatchParticipant = _controller.resolve_participant(body)
	var tally: BotParticipantTally = _tallies.get(participant.index, null) if participant != null else null
	if tally != null:
		tally.pad_launches += 1


func _physics_process(_delta: float) -> void:
	_ticks += 1
	var now: int = Time.get_ticks_usec()
	if _last_tick_usec >= 0:
		var spent: int = now - _last_tick_usec
		_tick_max_usec = maxi(_tick_max_usec, spent)
		_tick_sum_usec += spent
		if spent > 16000:
			_tick_over_16ms += 1
		for kind: String in RingNavigation.cost_usec:
			var usec: int = int(RingNavigation.cost_usec[kind])
			_cost_max[kind] = maxi(int(_cost_max.get(kind, 0)), usec)
			_cost_sum[kind] = int(_cost_sum.get(kind, 0)) + usec
	RingNavigation.cost_usec.clear()
	_last_tick_usec = now
	if _controller != null:
		_sample_runners()
		if _trace_every > 0 and _ticks % _trace_every == 0:
			_trace_runners()


## Ticks between trace lines; set by PANOPTICON_TRACE (seconds, 0 is off).
var _trace_every: int = int(60.0 * float(OS.get_environment("PANOPTICON_TRACE")))


## One diagnostic line per live runner: where it is, what it is doing, what it sees.
func _trace_runners() -> void:
	for participant: MatchParticipant in _controller.get_participants():
		var brain: RingRunner = participant.brain
		if brain == null or participant.body == null or not participant.is_running:
			continue
		if not participant.body.is_physics_processing():
			continue
		var position: Vector3 = participant.body.global_position
		var perception: RunnerPerception = brain.get_perception()
		var cover: RunnerCoverFinder = brain.get("_cover")
		var anchor: Vector3 = brain.get("_anchor")
		print(
			"TRACE t=%.1f p%d %-8s bear=%6.1f pos=(%.1f,%.1f,%.1f) spd=%.2f wp=%d arc=%.1f"
			% [
				float(_ticks) / 60.0, participant.index, brain.get_state_name(),
				rad_to_deg(atan2(position.z, position.x)),
				position.x, position.y, position.z,
				participant.body.get_horizontal_speed(),
				int(brain.get("_wp")), rad_to_deg(brain.get_travelled_arc()),
			]
			+ (" threat=%d exposed=%d watched=%d shots=%d reload=%.2f hold=%.1f conf=%.2f/%.2f open=%.1f"
			% [
				int(perception.has_threat()), int(perception.is_exposed()),
				int(perception.believes_watched()), perception.get_shots_heard(),
				perception.get_believed_reload_remaining(),
				float(brain.get("_hold_seconds")), brain.get_last_break_confidence(),
				brain.get_last_break_threshold(), brain.get_last_exposed_metres(),
			])
			+ (" tgt=%d cov=%d/%d anchor=(%.1f,%.1f,%.1f) x=%d"
			% [
				int(brain.get("_has_target")), int(cover.has_result()), int(cover.is_complete()),
				anchor.x, anchor.y, anchor.z, brain.get_crossings(),
			])
		)


## Stall and hold streaks, sampled from each live runner's body and brain.
func _sample_runners() -> void:
	for participant: MatchParticipant in _controller.get_participants():
		var tally: BotParticipantTally = _tallies.get(participant.index, null)
		var brain: RingRunner = participant.brain
		if tally == null or brain == null or participant.body == null:
			continue
		var w: Dictionary = _watch.get(participant.index, {})
		if not participant.is_running or not participant.body.is_physics_processing():
			_watch[participant.index] = {}
			continue
		var state: RingRunner.State = brain.get_state()
		var holding: bool = state == RingRunner.State.HOLD or state == RingRunner.State.EVALUATE
		var perception: RunnerPerception = brain.get_perception()
		var in_cover: bool = perception != null and perception.has_threat() and not perception.is_exposed()
		var hold_ticks: int = int(w.get("hold", 0)) + 1 if holding else 0
		tally.max_hold_seconds = maxf(tally.max_hold_seconds, float(hold_ticks) / 60.0)
		var position: Vector3 = participant.body.global_position
		var stall_run: int = int(w.get("stall_run", 0))
		if holding or in_cover or not w.has("origin"):
			w = {"hold": hold_ticks, "origin": position, "since": _ticks, "stall_run": 0 if holding or in_cover else stall_run}
			_watch[participant.index] = w
			continue
		if _ticks - int(w["since"]) >= STALL_WINDOW_TICKS:
			var origin: Vector3 = w["origin"]
			var moved: float = Vector2(position.x - origin.x, position.z - origin.z).length()
			if moved < STALL_DISTANCE_METRES:
				tally.stalls += 1
				stall_run += STALL_WINDOW_TICKS
				tally.max_stall_seconds = maxf(tally.max_stall_seconds, float(stall_run) / 60.0)
			else:
				stall_run = 0
			w["origin"] = position
			w["since"] = _ticks
			w["stall_run"] = stall_run
		w["hold"] = hold_ticks
		_watch[participant.index] = w


## Ticks the match has been running. The harness's authority on elapsed
## simulated time.
func get_ticks() -> int:
	return _ticks


func is_match_over() -> bool:
	return _match_over


# --- The match ----------------------------------------------------------------

func _on_match_started(participant_count: int) -> void:
	_participants_total = participant_count
	for participant: MatchParticipant in _controller.get_participants():
		if _tallies.has(participant.index):
			continue
		var tally: BotParticipantTally = BotParticipantTally.new()
		tally.index = participant.index
		tally.display_name = participant.display_name
		tally.kind = "HUMAN" if participant.is_human() else "AI"
		_tallies[participant.index] = tally
		_order.append(participant.index)


func _on_race_started() -> void:
	_race_ran = true
	_close_seat()
	# Nobody holds the rifle during the race, and the match stows it rather than
	# leaving it in anyone's hands. A shot in this window would be a bug worth
	# seeing as an uncredited shot rather than one quietly filed under the last
	# person to hold the seat.
	_shooter_index = -1


func _on_round_started() -> void:
	_rounds_started += 1
	if _first_shot_pending:
		_rounds_without_a_shot += 1
	_round_tick = _ticks
	_first_shot_pending = true


## The tower changed hands. Close the outgoing holder's time and open the new
## one's, then take the counts the match keeps rather than keeping a second
## copy of them here: the turn count is the match's own, and a harness that
## recomputed it would eventually disagree with the reload it explains.
func _on_seat_changed(participant: MatchParticipant, turns_in_tower: int) -> void:
	var previous_index: int = _seat_index
	_close_seat()
	_seat_changes += 1

	# Which seat changes were EARNED by a lap, and which were not. Three ways
	# the tower changes hands and only one of them is a lap:
	#
	# - the opening grant of a match with no race: nobody has run anything yet;
	# - a shooter who won a round and stays on for another (rounds_to_win_match
	#   above one), which the match expresses as a fresh seat grant to the same
	#   participant;
	# - anybody else taking the seat, which under every shipped rule means they
	#   reached the end, in the race or in a round.
	var opening_grant: bool = not _race_ran and _rounds_started == 0
	var retained: bool = previous_index == participant.index
	var earned: bool = not opening_grant and not retained

	_seat_index = participant.index
	_shooter_index = participant.index
	_seat_since_tick = _ticks

	var tally: BotParticipantTally = _tallies.get(participant.index, null)
	if tally == null:
		return
	tally.turns_in_tower = turns_in_tower
	tally.seat_takes += 1
	if earned:
		tally.laps_finished += 1


func _on_round_resolved(outcome: MatchController.Outcome) -> void:
	_rounds_resolved += 1
	if outcome == MatchController.Outcome.WIN:
		_round_wins += 1
	elif outcome == MatchController.Outcome.LOSS:
		_round_losses += 1


func _on_runner_removed(_remaining: int) -> void:
	_conversions += 1
	_removed_tick = _ticks
	# The rifle's hit handler has already credited the shot. What is recorded
	# here is the conversion, which under prisoner_lives > 1 is not the same
	# event and must not be counted from the shot.


func _on_runner_ghosted(_participant: MatchParticipant) -> void:
	_ghosts_made += 1


## A ghost took a living prisoner's spot. Counted, and deliberately NOT counted
## as a conversion: a catch conserves the number of living prisoners and only the
## rifle lowers it, so folding the two together would make a ghost match look
## like a shooter who never missed.
func _on_ghost_caught(_ghost: MatchParticipant, _caught: MatchParticipant) -> void:
	_ghost_catches += 1


func _on_match_won(participant: MatchParticipant) -> void:
	_close_seat()
	_match_over = true
	_winner_index = participant.index
	var seat: MatchParticipant = _controller.get_seat_participant()
	_winner_was_seat = seat != null and seat.index == participant.index

	var tally: BotParticipantTally = _tallies.get(participant.index, null)
	if tally != null:
		tally.rounds_won = participant.rounds_won
	for other: MatchParticipant in _controller.get_participants():
		var entry: BotParticipantTally = _tallies.get(other.index, null)
		if entry != null and other.tracker != null:
			entry.final_progress = other.tracker.get_progress()


func _close_seat() -> void:
	if _seat_index < 0:
		return
	var tally: BotParticipantTally = _tallies.get(_seat_index, null)
	if tally != null:
		tally.ticks_in_tower += _ticks - _seat_since_tick
	_seat_index = -1


# --- The rifle ----------------------------------------------------------------

func _on_fired(_origin: Vector3, _end_point: Vector3) -> void:
	_shots_fired += 1
	var tally: BotParticipantTally = _tallies.get(_shooter_index, null)
	if tally != null:
		tally.shots_fired += 1
		if _first_shot_pending and _round_tick >= 0:
			var seconds: float = float(_ticks - _round_tick) / 60.0
			tally.first_shot_seconds.append(seconds)
			_first_shots.append(seconds)
	_first_shot_pending = false


## A shot struck SOMETHING. Whether that something was a player is the match's
## question to answer, and [method MatchController.resolve_participant] is the
## public way to ask it -- the alternative, comparing the collider against a
## roster this file kept, would silently stop working the day a body grows a
## separate hitbox node.
func _on_target_hit(collider: Node3D, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	var struck: MatchParticipant = _controller.resolve_participant(collider)
	if struck == null:
		_shots_hit_world += 1
		return

	_shots_hit_participant += 1
	var shooter: BotParticipantTally = _tallies.get(_shooter_index, null)
	if shooter != null:
		shooter.shots_hit += 1
	var victim: BotParticipantTally = _tallies.get(struck.index, null)
	if victim != null:
		victim.times_converted += 1


func _on_missed(_end_point: Vector3) -> void:
	_shots_hit_nothing += 1


# --- The report ---------------------------------------------------------------

## Fold the final state of the roster in and close the open seat. Called once,
## by [BotMatchRunner], on the tick the match stops -- including a match stopped
## by the tick ceiling, which is why this is not done from
## [method _on_match_won].
func finalise() -> void:
	_close_seat()
	if _controller == null:
		return
	for participant: MatchParticipant in _controller.get_participants():
		var tally: BotParticipantTally = _tallies.get(participant.index, null)
		if tally == null:
			continue
		tally.turns_in_tower = participant.turns_in_tower
		tally.rounds_won = participant.rounds_won
		tally.running_at_end = participant.is_running and not _match_over
		if participant.tracker != null:
			tally.final_progress = participant.tracker.get_progress()
	if _first_shot_pending and _rounds_started > 0:
		_rounds_without_a_shot += 1


func get_hit_rate() -> float:
	if _shots_fired <= 0:
		return 0.0
	return float(_shots_hit_participant) / float(_shots_fired)


## Everything measured, as plain data. [param sim_hz] is the simulated physics
## rate the ticks were counted at.
func to_dictionary(sim_hz: int) -> Dictionary:
	var participants: Array = []
	for index: int in _order:
		var tally: BotParticipantTally = _tallies.get(index, null)
		if tally != null:
			participants.append(tally.to_dictionary(sim_hz))

	return {
		"participants_total": _participants_total,
		"rounds": {
			"race_ran": _race_ran,
			"started": _rounds_started,
			"resolved": _rounds_resolved,
			"shooter_wins": _round_wins,
			"shooter_losses": _round_losses,
		},
		"seat": {
			"changes": _seat_changes,
			"changes_in_rounds": _laps_total(),
		},
		"shots": {
			"fired": _shots_fired,
			"hit_participant": _shots_hit_participant,
			"hit_world": _shots_hit_world,
			"hit_nothing": _shots_hit_nothing,
			"hit_rate": get_hit_rate(),
		},
		"conversions": _conversions,
		"hazard_deaths": _hazard_deaths,
		"tick_ms": _tick_dictionary(),
		"first_shot_seconds": _first_shots,
		"rounds_without_a_shot": _rounds_without_a_shot,
		"ghosts": {
			"made": _ghosts_made,
			"catches": _ghost_catches,
		},
		"participants": participants,
	}


func _tick_dictionary() -> Dictionary:
	var ticks: float = float(maxi(_ticks - 1, 1))
	var out: Dictionary = {
		"max": float(_tick_max_usec) / 1000.0,
		"avg": float(_tick_sum_usec) / ticks / 1000.0,
		"over_16ms": _tick_over_16ms,
	}
	for kind: String in _cost_max:
		out["%s_max" % kind] = float(_cost_max[kind]) / 1000.0
		out["%s_avg" % kind] = float(_cost_sum[kind]) / ticks / 1000.0
	return out


## Seat changes that somebody actually ran a lap for. The number a balance
## question about the tower is usually asking after.
func _laps_total() -> int:
	var total: int = 0
	for tally: BotParticipantTally in _tallies.values():
		total += tally.laps_finished
	return total


func get_winner_index() -> int:
	return _winner_index


func winner_held_the_tower() -> bool:
	return _winner_was_seat
