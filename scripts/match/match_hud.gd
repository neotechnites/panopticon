class_name MatchHud
extends Control

## The whole of the first playable's UI: three labels and no art.
##
## Deliberately austere, but not arbitrary. Two of these readouts are the
## difference between a legible round and an unreadable one:
##
## - The reload. The rifle is silent for 2.5 s after every shot and nothing in
##   the 3D scene says so, so without a countdown the player cannot tell a
##   refused trigger from a broken one.
## - The runner count. A removed runner vanishes at 40 m, often behind cover, and
##   the player frequently cannot see whether the shot landed.
##
## Reads state rather than mirroring it: the count and the weapon are polled
## from [MatchController] and [Rifle] each frame, and only the outcome -- which
## happens once and must not be missed between frames -- is taken from a signal.

## The round to report on.
@export var controller: MatchController

## The weapon whose readiness is shown. Normally the tower's.
@export var rifle: Rifle

## Top-left readout: runners left, weapon state, the restart key.
@export var status_label: Label

## Centre readout: "YOU WIN" / "YOU LOSE", empty while the round is live.
@export var outcome_label: Label


func _ready() -> void:
	if outcome_label != null:
		outcome_label.text = ""
	if controller == null:
		push_error("MatchHud has no MatchController; the round will be unreadable.")
		set_process(false)
		return
	controller.round_resolved.connect(_on_round_resolved)
	controller.round_started.connect(_on_round_started)


func _process(_delta: float) -> void:
	if status_label == null or controller == null:
		return
	status_label.text = "Runners: %d / %d    Rifle: %s    [R] restart" % [
		controller.get_runners_remaining(),
		controller.get_runners_total(),
		_weapon_text(),
	]


## READY, or RELOADING with the honest time to the next shot -- which counts the
## firing window as well as the reload, because that is when the trigger will
## actually answer again.
func _weapon_text() -> String:
	if rifle == null:
		return "-"
	if rifle.can_fire():
		return "READY"
	return "RELOADING %.1fs" % rifle.get_time_to_ready()


func _on_round_resolved(outcome: MatchController.Outcome) -> void:
	if outcome_label == null:
		return
	outcome_label.text = "YOU WIN" if outcome == MatchController.Outcome.WIN else "YOU LOSE"


func _on_round_started() -> void:
	if outcome_label != null:
		outcome_label.text = ""
