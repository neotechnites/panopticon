class_name AirControlSwitcher
extends Node

## Puts a list of [AirControlPreset]s under one key, so a tuning question is
## settled by feeling two answers ten seconds apart instead of by editing a
## resource, restarting, and trying to remember what the last one felt like.
##
## [b]Dev only.[/b] Nothing in a match instances this. It lives beside
## [MovementReadout] in [code]scenes/dev/movement_playground.tscn[/code] and,
## like the readout, draws no conclusions -- it swaps a resource and prints the
## name of what is now selected.
##
## [b]The intent seam is not touched.[/b] This node reads a key, but it is not
## an [IntentSource] and it never writes a [MoveIntent]: it calls
## [method PlayerController.set_profile] and nothing else. The body it points at
## goes on asking whatever [IntentSource] it already has for its intent, so a
## bot-driven body switches presets by the identical code path with no input
## layer involved at all -- call [method select] or [method cycle] directly. A
## headless sweep does exactly that.
##
## [b]The comparison is only fair if the swap is invisible.[/b] Selecting a
## preset changes tunables and nothing else: position, velocity, the slide in
## progress and the jump timers all survive it, so a preset can be changed in
## mid-flight and the very next tick is the new tuning applied to the old
## momentum. That is the whole point -- a swap that reset the body would make
## every comparison a comparison of first strides.

## Emitted whenever the selection changes, carrying the preset now in force.
## The readout hangs off this rather than polling.
signal preset_selected(preset: AirControlPreset)

## The body to retune. Required.
@export var body: PlayerController

## The presets to cycle through, in the order the key walks them. Authored in
## the scene, so the set on offer is a thing you can see in the inspector rather
## than a list built in code.
@export var presets: Array[AirControlPreset] = []

## Shows the selected preset's [member AirControlPreset.display_name], its
## position in the list, and the key that advances it.
@export var name_label: Label

## Shows the selected preset's [member AirControlPreset.feel] and its four
## numbers. Optional: without it the name alone still identifies the preset.
@export var feel_label: Label

## Action this node advances the selection on. Registered against
## [member fallback_keycode] at ready if the project has not defined it, the
## same courtesy [PlayerActions] extends to the movement keys, so the playground
## is runnable without editing project settings first.
@export var cycle_action: StringName = &"air_control_cycle"

## Physical keycode used when [member cycle_action] has to be registered here.
## Physical, so it stays under the same finger on AZERTY.
@export var fallback_keycode: Key = KEY_F

## Profiles built from [member presets], one per preset, built once at ready.
##
## Built once rather than per switch because [method AirControlPreset.build]
## duplicates the base profile, and a fresh duplicate on every keypress would
## hand [PlayerController] a different object each time -- harmless today, and
## exactly the kind of churn that makes an identity comparison in a later test
## fail for no visible reason.
var _profiles: Array[MovementProfile] = []

var _index: int = 0


func _ready() -> void:
	if body == null:
		push_error("AirControlSwitcher has no PlayerController; there is nothing to retune.")
		set_process_unhandled_input(false)
		return
	if presets.is_empty():
		push_error("AirControlSwitcher has no presets; there is nothing to switch between.")
		set_process_unhandled_input(false)
		return

	for preset: AirControlPreset in presets:
		_profiles.append(preset.build())

	_ensure_action()
	# Index 0 deliberately, and index 0 is deliberately the shipped tuning: a
	# scene that opened on anything else would be showing a game nobody plays.
	select(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(cycle_action):
		cycle(1)


## Advance the selection by [param step], wrapping in both directions.
func cycle(step: int) -> void:
	if presets.is_empty():
		return
	select(posmod(_index + step, presets.size()))


## Put preset [param index] in force. Out-of-range indices are ignored rather
## than clamped: a caller asking for a preset that is not there has a bug, and
## silently handing them a neighbour hides it.
func select(index: int) -> void:
	if index < 0 or index >= presets.size():
		push_error("AirControlSwitcher has no preset %d; %d are loaded." % [index, presets.size()])
		return
	var profile: MovementProfile = _profiles[index]
	if profile == null:
		return
	_index = index
	body.set_profile(profile)
	_refresh_labels()
	preset_selected.emit(presets[index])


## The preset currently in force.
func get_selected() -> AirControlPreset:
	if _index < 0 or _index >= presets.size():
		return null
	return presets[_index]


func _refresh_labels() -> void:
	var preset: AirControlPreset = presets[_index]
	if name_label != null:
		name_label.text = "%d/%d  %s        [%s] to cycle" % [
			_index + 1, presets.size(), preset.display_name,
			OS.get_keycode_string(fallback_keycode),
		]
	if feel_label != null:
		feel_label.text = "%s\n\n%s" % [preset.feel, preset.describe_numbers()]


func _ensure_action() -> void:
	if InputMap.has_action(cycle_action):
		return
	InputMap.add_action(cycle_action, PlayerActions.DEADZONE)
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = fallback_keycode
	InputMap.action_add_event(cycle_action, event)
