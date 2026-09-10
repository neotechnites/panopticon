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
	controller.match_won.connect(_on_match_won)

	rifle.fired.connect(_on_fired)
	rifle.target_hit.connect(_on_target_hit)
	rifle.missed.connect(_on_missed)


func _physics_process(_delta: float) -> void:
	_ticks += 1


## Ticks the match has been running. The harness's authority on elapsed
## simulated time.
func get_ticks() -> int:
	return _ticks


func is_match_over() -> bool:
	return _match_over


# --- The match ----------------------------------------------------------------

func _on_match_started(participant_count: int) -> void:
	_participants_total = participant_count
	_tallies.clear()
	_order.clear()
	for participant: MatchParticipant in _controller.get_participants():
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
	# The rifle's hit handler has already credited the shot. What is recorded
	# here is the conversion, which under prisoner_lives > 1 is not the same
	# event and must not be counted from the shot.


func _on_match_won(participant: MatchParticipant) -> void:
	_close_seat()
	_match_over = true
	_winner_index = participant.index
	var seat: MatchParticipant = _controller.get_seat_participant()
	_winner_was_seat = seat != null and seat.index == participant.index

	var tally: BotParticipantTally = _tallies.get(participant.index, null)
	if tally != null:
		tally.rounds_won = participant.rounds_won


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
		tally.lane_radius = participant.lane_radius


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
		"participants": participants,
	}


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
