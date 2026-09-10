class_name MatchHud
extends Control

## The whole of the match's UI: four labels and no art.
##
## Deliberately austere, but not arbitrary. Every readout here is the difference
## between a legible match and an unreadable one:
##
## - The reload. The tower is silent for seconds after every shot and nothing in
##   the 3D scene says so, so without a countdown the player cannot tell a
##   refused trigger from a broken one. It also SHORTENS as a player takes more
##   turns in the tower, and a terminator nobody can see is indistinguishable
##   from a bug.
## - The runner count. A converted runner vanishes at 40 m, often behind cover,
##   and the player frequently cannot see whether the shot landed.
## - Who holds the tower, and on what turn. The seat is a role that passes
##   between players, including to AI, and the human out on the track needs to
##   know both that they are running and who they are running from.
##
## Reads state rather than mirroring it: everything countable is polled from
## [MatchController] and [Rifle] each frame, and only the events that happen once
## and must not be missed between frames -- a resolution, a match win -- are
## taken from signals.

## The match to report on.
@export var controller: MatchController

## The weapon whose readiness is shown. It changes hands, but it is one object
## for the life of the match, so this reference stays correct across seat
## changes.
@export var rifle: Rifle

## Top-left readout: runners left, weapon state, the restart key.
@export var status_label: Label

## Under the status: the phase, who holds the tower, and every participant's turn
## count.
@export var match_label: Label

## Centre readout: the round's result and, at the end, the match winner.
@export var outcome_label: Label


func _ready() -> void:
	if outcome_label != null:
		outcome_label.text = ""
	if controller == null:
		push_error("MatchHud has no MatchController; the match will be unreadable.")
		set_process(false)
		return
	controller.round_resolved.connect(_on_round_resolved)
	controller.race_started.connect(_on_race_started)
	controller.seat_changed.connect(_on_seat_changed)
	controller.match_won.connect(_on_match_won)


func _process(_delta: float) -> void:
	if controller == null:
		return
	if status_label != null:
		status_label.text = "Runners: %d / %d    Rifle: %s    Reload: %.2fs    [R] restart match" % [
			controller.get_runners_remaining(),
			controller.get_runners_total(),
			_weapon_text(),
			controller.get_current_reload_seconds(),
		]
	if match_label != null:
		match_label.text = _match_text()


## READY, or RELOADING with the honest time to the next shot -- which counts the
## firing window as well as the reload, because that is when the trigger will
## actually answer again.
func _weapon_text() -> String:
	if rifle == null:
		return "-"
	if rifle.can_fire():
		return "READY"
	return "RELOADING %.1fs" % rifle.get_time_to_ready()


## The match, in three lines: what is happening, who has the tower, and what
## every player's turn count is.
func _match_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s    round %d" % [controller.get_phase_name(), controller.get_round_number()])

	var seat: MatchParticipant = controller.get_seat_participant()
	if seat == null:
		lines.append("Tower: NOBODY -- race for it")
	else:
		lines.append("Tower: %s    turn %d" % [seat.display_name, seat.turns_in_tower])

	for participant: MatchParticipant in controller.get_participants():
		lines.append("  %s: %s, turns %d" % [
			participant.display_name,
			participant.get_role_name(),
			participant.turns_in_tower,
		])
	return "\n".join(lines)


## The centre label carries the last thing that HAPPENED, and is never cleared.
##
## A seat change fires round_resolved, seat_changed and round_started within one
## tick, so a label cleared on round_started would blank the result on the frame
## it appeared. Each handler simply overwrites, and the order of emission means
## the last word belongs to the most informative event.
func _on_round_resolved(outcome: MatchController.Outcome) -> void:
	if outcome_label == null:
		return
	if outcome == MatchController.Outcome.WIN:
		var seat: MatchParticipant = controller.get_seat_participant()
		# Emitted before the seat can change hands, so this is still the shooter
		# who did it.
		outcome_label.text = "%s HELD THE TOWER" % (seat.display_name if seat != null else "nobody")
	else:
		outcome_label.text = "A RUNNER REACHED THE END"


func _on_race_started() -> void:
	if outcome_label != null:
		outcome_label.text = "RACE FOR THE TOWER"


func _on_seat_changed(participant: MatchParticipant, turns_in_tower: int) -> void:
	if outcome_label != null:
		# "TOWER TAKEN BY" rather than "X takes the tower": the human's name is
		# "You", and the second phrasing reads as broken English for half the
		# participants in every match.
		outcome_label.text = "TOWER TAKEN BY %s (turn %d)" % [
			participant.display_name, turns_in_tower,
		]


func _on_match_won(participant: MatchParticipant) -> void:
	if outcome_label != null:
		outcome_label.text = "MATCH WON BY %s" % participant.display_name
