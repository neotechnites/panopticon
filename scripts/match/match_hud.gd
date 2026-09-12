class_name MatchHud
extends Control

## The match HUD: edges only, centre clear.
##
## Each role is shown the few things it acts on and nothing else.
##
## [codeblock]
## PRISONER  bottom-left   the TOWER rifle's reload, as a bar
##           bottom-right  your power, and the speed boost while it runs
##           top-centre    round, prisoners left, who holds the tower
## GUARD     under the dot your own reload (or charge)
##           top-centre    round, prisoners left, your turn
## FINISHER  guard layout plus ten health pips
## GHOST     nothing. MatchDeathScreen owns the dead player's screen.
## [/codeblock]
##
## Everything is polled from [MatchController] and [Rifle] each tick, so no
## count here can drift from the match's. Only the three events that must not be
## missed between frames raise the centre line, and it writes one string.

## Which readout is being drawn.
enum Role {
	## No human in this match, or the readout is switched off. Draws nothing.
	NONE,
	## Holding the tower.
	GUARD,
	## A living prisoner on the ring.
	PRISONER,
	## Shot, and chasing. The death screen has this player.
	GHOST,
	## Out, with nothing to play.
	SPECTATOR,
	## A prisoner who has been armed to take the tower by force.
	FINISHER,
}

## How long the centre line holds before it fades out.
const FLASH_SECONDS: float = 2.0

## Pips drawn for a finisher's health, whatever
## [member MatchRules.finisher_health] is.
const PIP_COUNT: int = 10

## The match to report on.
@export var controller: MatchController

## The tower rifle. One object for the life of the match, so this stays correct
## across seat changes.
@export var rifle: Rifle

## The 3 px centre dot.
@export var crosshair: Control

## Top-centre line's root, and the label in it.
@export var status_panel: Control
@export var status_label: Label

## The transient centre line. Never stacked: a new event overwrites the old one.
@export var flash_label: Label

## Bottom-left: the tower rifle's reload, for a prisoner.
@export var tower_panel: Control
@export var tower_fill: Control
@export var tower_value: Label

## Under the crosshair: the guard's or finisher's own reload.
@export var guard_panel: Control
@export var guard_fill: Control
@export var guard_value: Label

## Ten pips under the guard bar, for a finisher.
@export var pips_row: Control

## Bottom-right: the runner's power and its cooldown.
@export var power_panel: Control
@export var power_label: Label
@export var power_fill: Control

## Bottom-right, under the power: the speed boost while one is running.
@export var boost_label: Label

## Top-right: the dev toggles, only while one is on.
@export var dev_label: Label

## Wording and colour. Unset falls back on [MatchReadoutProfile]'s own defaults.
@export var readout: MatchReadoutProfile

## Seconds of centre line left to run.
var _flash_remaining: float = 0.0

## Used when [member readout] is unset, built once and kept.
var _fallback_readout: MatchReadoutProfile = null

var _showing: bool = false


func _ready() -> void:
	_write_flash("")
	_hide_all()
	if controller == null:
		push_error("MatchHud has no MatchController; the match will be unreadable.")
		set_process(false)
		return
	controller.round_resolved.connect(_on_round_resolved)
	controller.race_started.connect(_on_race_started)
	controller.seat_changed.connect(_on_seat_changed)


func _process(delta: float) -> void:
	_tick_flash(delta)
	tick()


## Refresh from the match. Public so a test or a harness may step it without
## waiting on a frame.
func tick() -> void:
	if controller == null:
		return
	var role: Role = get_role()
	_showing = role == Role.GUARD or role == Role.PRISONER or role == Role.FINISHER
	if not _showing:
		_hide_all()
		return

	_show(crosshair, true)
	_show(status_panel, true)
	_write(status_label, _status_text(role), _readout().neutral_color)
	_write_dev()

	var prisoner: bool = role == Role.PRISONER
	_write_bar(tower_panel, tower_fill, tower_value, prisoner, _tower_rifle())
	_write_bar(guard_panel, guard_fill, guard_value, not prisoner, _own_rifle())
	_write_pips(role == Role.FINISHER)
	_write_power(prisoner)


# --- What the player is -------------------------------------------------------

## Which readout the human in this match should be looking at. On a client this
## is the mirror's own participant, so the role follows the seat like the host's.
func get_role() -> Role:
	if controller == null or not _readout().enabled:
		return Role.NONE
	var human: MatchParticipant = controller.get_human_participant()
	if human == null:
		return Role.NONE
	if human.is_shooter:
		return Role.GUARD
	# Checked before is_running: a ghost is made, flags and all, on the tick
	# they are shot.
	if human.is_ghost:
		return Role.GHOST
	if human.is_finisher and human.is_running:
		return Role.FINISHER
	if human.is_running:
		return Role.PRISONER
	return Role.SPECTATOR


## True while the HUD is drawing a role's readout. The seam a test asserts on.
func is_readout_showing() -> bool:
	return _showing


## The top-centre line, or an empty string when it is not on screen.
func get_status_text() -> String:
	return _shown(status_panel, status_label)


## The reload readout the role is being shown: the tower's for a prisoner, your
## own in the tower. Empty when there is none.
func get_primary_text() -> String:
	if get_role() == Role.PRISONER:
		return _shown(tower_panel, tower_value)
	return _shown(guard_panel, guard_value)


## The runner's power, as it reads bottom-right.
func get_context_text() -> String:
	return _shown(power_panel, power_label)


## The transient centre line, or an empty string.
func get_flash_text() -> String:
	return _shown(flash_label, flash_label)


## The dev toggles, or an empty string when none are on.
func get_dev_text() -> String:
	return _shown(dev_label, dev_label)


## A label's text, but only while the block it lives in is on screen. Every
## label in this HUD is authored with placeholder text for the editor.
func _shown(panel: Control, label: Label) -> String:
	if panel == null or label == null or not panel.visible:
		return ""
	return label.text


# --- The lines ----------------------------------------------------------------

## Round, prisoners left, and the one thing about the tower this role needs:
## who is in it for a prisoner, which turn this is for the guard.
func _status_text(role: Role) -> String:
	var tuning: MatchReadoutProfile = _readout()
	var parts: PackedStringArray = PackedStringArray([_round_text()])
	if role == Role.PRISONER:
		parts.append("%s %d/%d" % [
			tuning.prisoners_word,
			controller.get_runners_remaining(),
			controller.get_runners_total(),
		])
		var seat: MatchParticipant = controller.get_seat_participant()
		parts.append("TOWER: %s" % (seat.display_name if seat != null else "--"))
	else:
		parts.append("%s %d" % [tuning.prisoners_word, controller.get_runners_remaining()])
		var human: MatchParticipant = controller.get_human_participant()
		parts.append("%s %d" % [tuning.turn_word, human.turns_in_tower if human != null else 0])
	return tuning.separator.join(parts)


func _round_text() -> String:
	if controller.get_phase() == MatchController.Phase.RACE:
		return "RACE"
	return "ROUND %d" % controller.get_round_number()


## The rifle whose reload the tower is running, or null while nobody holds it.
func _tower_rifle() -> Rifle:
	return null if controller.get_seat_participant() == null else rifle


## The rifle in this player's hands: the tower's, or the finisher's.
func _own_rifle() -> Rifle:
	if get_role() == Role.FINISHER:
		return controller.get_finisher_rifle()
	return rifle


## One reload bar: READY when loaded, the seconds to the next shot while it is
## not, and the charge on a weapon whose profile has one.
func _write_bar(panel: Control, fill: Control, value: Label, wanted: bool, gun: Rifle) -> void:
	_show(panel, wanted and gun != null)
	if not wanted or gun == null:
		return
	var tuning: MatchReadoutProfile = _readout()
	if gun.can_fire():
		var charged: bool = gun.profile != null and gun.profile.charge_enabled
		_set_fill(fill, gun.get_charge() if charged else 1.0)
		_write(value, tuning.ready_text, tuning.ready_color)
		return
	var total: float = maxf(controller.get_current_reload_seconds(), 0.01)
	var left: float = gun.get_time_to_ready()
	_set_fill(fill, clampf(1.0 - left / total, 0.0, 1.0))
	_write(value, String.num(left, tuning.reload_decimals), tuning.reloading_color)


## A finisher's health, as ten pips whatever the rule's own number is.
func _write_pips(wanted: bool) -> void:
	_show(pips_row, wanted)
	if not wanted or pips_row == null:
		return
	var human: MatchParticipant = controller.get_human_participant()
	var maximum: float = maxf(float(controller.get_rules().finisher_health), 1.0)
	var lit: int = clampi(
		int(ceilf(float(human.health if human != null else 0) / maximum * float(PIP_COUNT))),
		0,
		PIP_COUNT,
	)
	var tuning: MatchReadoutProfile = _readout()
	for index: int in pips_row.get_child_count():
		var pip: Control = pips_row.get_child(index) as Control
		if pip != null:
			pip.modulate = tuning.ready_color if index < lit else tuning.dim_color * Color(1, 1, 1, 0.25)


## The runner's power, its cycle, and the speed boost while one runs.
func _write_power(wanted: bool) -> void:
	var text: String = _ability_text() if wanted else ""
	_show(power_panel, text != "")
	if text != "":
		_write(power_label, text, _readout().neutral_color)
		_set_fill(power_fill, _ability_fill())
	var boost: String = _speed_boost_text() if wanted else ""
	_show(boost_label, boost != "")
	if boost != "":
		_write(boost_label, boost, _readout().ready_color)


## The power's name and where it is in its cycle.
func _ability_text() -> String:
	var human: MatchParticipant = controller.get_human_participant()
	var rules: MatchRules = controller.get_rules()
	if human == null or rules.runner_ability == MatchRules.RunnerAbility.NONE:
		return ""
	var ability: RunnerPower = RunnerPower.of(human.body)
	if ability == null:
		return ""
	var title: String = MatchRules.runner_ability_title(rules.runner_ability).to_upper()
	if ability.is_active():
		return "%s — %.1fs" % [title, ability.get_remaining()]
	if ability.get_cooldown_remaining() > 0.0:
		return "%s — READY IN %.0fs" % [title, ability.get_cooldown_remaining()]
	return "%s — READY" % title


## How full the power bar is: the run while it is active, the wait while it is
## cooling, full when it is ready.
func _ability_fill() -> float:
	var human: MatchParticipant = controller.get_human_participant()
	var rules: MatchRules = controller.get_rules()
	var ability: RunnerPower = RunnerPower.of(human.body) if human != null else null
	if ability == null:
		return 0.0
	if ability.is_active():
		return clampf(ability.get_remaining() / maxf(rules.ability_duration_seconds, 0.01), 0.0, 1.0)
	var cooling: float = ability.get_cooldown_remaining()
	if cooling <= 0.0:
		return 1.0
	return clampf(1.0 - cooling / maxf(rules.ability_cooldown_seconds, 0.01), 0.0, 1.0)


## The boost on the human's own body, or an empty string.
func _speed_boost_text() -> String:
	var human: MatchParticipant = controller.get_human_participant()
	if human == null or human.body == null:
		return ""
	var remaining: float = human.body.get_speed_boost_remaining()
	if remaining <= 0.0:
		return ""
	return "SPEED x%d · %.1fs" % [int(human.body.get_speed_boost_multiplier()), remaining]


## Dev toggles on the human's body: T turbo, Y invincible. Empty when off.
func _dev_text() -> String:
	var human: MatchParticipant = controller.get_human_participant()
	if human == null or human.body == null:
		return ""
	var intent: MoveIntent = human.body.get_intent()
	var flags: PackedStringArray = PackedStringArray()
	if intent.godmode:
		flags.append("INVINCIBLE")
	if intent.turbo_held:
		flags.append("TURBO")
	return " · ".join(flags)


func _write_dev() -> void:
	var text: String = _dev_text()
	_show(dev_label, text != "")
	if text != "":
		_write(dev_label, text, _readout().reloading_color)


# --- The centre line ----------------------------------------------------------

func _on_round_resolved(outcome: MatchController.Outcome) -> void:
	var human: MatchParticipant = controller.get_human_participant()
	if human == null:
		return
	var tower_held: bool = outcome == MatchController.Outcome.WIN
	_flash("ROUND WON" if tower_held == human.is_shooter else "ROUND LOST")


func _on_race_started() -> void:
	_flash("")


func _on_seat_changed(participant: MatchParticipant, _turns_in_tower: int) -> void:
	# "TOWER TAKEN BY" rather than "X takes the tower": the human's name is
	# "You", and the second reads as broken English for half of every match.
	_flash("TOWER TAKEN BY %s" % participant.display_name.to_upper())


## Raise the centre line, replacing whatever was there. Never stacked.
func _flash(text: String) -> void:
	_flash_remaining = 0.0 if text == "" else FLASH_SECONDS
	_write_flash(text)


func _tick_flash(delta: float) -> void:
	if _flash_remaining <= 0.0 or flash_label == null:
		return
	_flash_remaining -= delta
	if _flash_remaining <= 0.0:
		_write_flash("")
		return
	flash_label.modulate.a = clampf(_flash_remaining / FLASH_SECONDS, 0.0, 1.0)


func _write_flash(text: String) -> void:
	if flash_label == null:
		return
	flash_label.text = text
	flash_label.modulate = Color(1.0, 1.0, 1.0, 1.0 if text != "" else 0.0)
	flash_label.visible = text != ""


# --- Drawing ------------------------------------------------------------------

func _hide_all() -> void:
	for node: Control in [
		crosshair, status_panel, tower_panel, guard_panel, pips_row, power_panel,
		boost_label, dev_label,
	]:
		_show(node, false)


func _show(node: Control, visible_now: bool) -> void:
	if node != null:
		node.visible = visible_now


func _write(label: Label, text: String, colour: Color) -> void:
	if label == null:
		return
	label.text = text
	label.modulate = colour


## Drive a bar by its right anchor, so it fills its track at any resolution.
func _set_fill(fill: Control, fraction: float) -> void:
	if fill != null:
		fill.anchor_right = clampf(fraction, 0.0, 1.0)


## The readout tuning, whether or not the scene supplied any.
func _readout() -> MatchReadoutProfile:
	if readout != null:
		return readout
	if _fallback_readout == null:
		_fallback_readout = MatchReadoutProfile.new()
	return _fallback_readout
