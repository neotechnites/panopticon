class_name MatchDeathScreen
extends CanvasLayer

## The legible half of being dead: what happened, and when it ends.
##
## The author, on the three second hold: [i]"when someone gets shot, they jsut
## stop animating and sit there for 3 secdson, let give them a reload screen, or
## make them a free camera or something."[/i] [FxSpectatorView] is the camera
## half. This is the reload screen, and the two are deliberately separate nodes:
## a camera cannot say HOW LONG, and a countdown cannot give you anything to look
## at.
##
## [b]Why a countdown at all[/b]
##
## Three seconds of held camera with no text is indistinguishable from three
## seconds of a game that has hung, and a player who cannot tell those apart
## stops trusting the game rather than the tower. The number is the difference
## between a wait and a freeze -- and a player who can see 1.2 on the screen is
## already deciding what to do when they land.
##
## [b]And why the elimination case has no number[/b]
##
## A racer who falls during the opening race is out for the rest of it -- the
## author's ruling, and it stands. That has no deadline anybody can compute: it
## ends when somebody still running crosses the line. Showing a countdown that
## was really a guess would be worse than showing none, so that state gets a
## sentence instead, and the sentence says what it is waiting FOR.
##
## Polls [method MatchController.get_spectating_state] every frame for the same
## reason [FxSpectatorView] does: an edge-driven screen is wrong for a player who
## died before it was ready and wrong after a restart.
##
## Built in code, like every other menu in this project, and strictly additive:
## it subscribes to nothing and deleting it leaves the match as it was.

## The match to report on.
@export var controller: MatchController

## Draw order. Above the HUD (1) and the feedback rig (2) -- a death screen that
## a hitmarker drew over would be absurd -- and far below [PauseMenu] at 128, so
## a player can still pause while dead.
@export var draw_layer: int = 3

## Go inert with no display server.
@export var headless_inert: bool = true

const HEADLESS_DISPLAY: String = "headless"

## Colour of the band the text sits on. Dark and translucent: the whole point is
## that the player can still see the world behind it.
const BAND_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)

## Height of that band as a fraction of the screen.
const BAND_HEIGHT_RATIO: float = 0.26

const TITLE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.96)
const COUNTDOWN_COLOR: Color = Color(1.0, 0.86, 0.4, 1.0)
const HINT_COLOR: Color = Color(0.78, 0.78, 0.78, 0.85)

const TITLE_SIZE: int = 44
const COUNTDOWN_SIZE: int = 64
const HINT_SIZE: int = 16

var _inert: bool = false
var _root: Control
var _band: ColorRect
var _title: Label
var _countdown: Label
var _hint: Label

## What was on screen last frame, so the labels are only rewritten when they
## change rather than sixty times a second.
var _shown_state: MatchController.Spectating = MatchController.Spectating.NONE
var _shown_tenths: int = -1


func _ready() -> void:
	layer = draw_layer
	if headless_inert and DisplayServer.get_name() == HEADLESS_DISPLAY:
		_inert = true
		set_process(false)
		return
	if controller == null:
		push_error("MatchDeathScreen has no MatchController; a dead player will be told nothing.")
		_inert = true
		set_process(false)
		return
	_build()
	_root.visible = false


func _process(_delta: float) -> void:
	tick()


## Refresh the screen from the match. Public so a harness may step it.
func tick() -> void:
	if _inert or controller == null or _root == null:
		return

	var participant: MatchParticipant = controller.get_human_participant()
	var state: MatchController.Spectating = controller.get_spectating_state(participant)
	if state == MatchController.Spectating.NONE:
		if _root.visible:
			_root.visible = false
			_shown_state = state
			_shown_tenths = -1
		return

	_root.visible = true
	if state != _shown_state:
		_shown_state = state
		_shown_tenths = -1
		_title.text = _title_for(state)
		_hint.text = _hint_for(state)
		_countdown.visible = state == MatchController.Spectating.RESPAWNING

	if state != MatchController.Spectating.RESPAWNING:
		return

	# Rounded UP and to a tenth: a countdown that shows 0.0 for a sixth of a
	# second reads as having stalled at the very moment the player is waiting
	# hardest, and one that shows three decimals reads as a debug print.
	var remaining: float = controller.get_respawn_hold_remaining(participant)
	var tenths: int = maxi(int(ceilf(remaining * 10.0)), 0)
	if tenths != _shown_tenths:
		_shown_tenths = tenths
		_countdown.text = "%.1f" % (float(tenths) * 0.1)


# --- Public API ---------------------------------------------------------------

## True while the screen is up. The seam a test asserts against.
func is_showing() -> bool:
	return _root != null and _root.visible


## What the screen is showing right now.
func get_shown_state() -> MatchController.Spectating:
	return _shown_state if is_showing() else MatchController.Spectating.NONE


## The countdown as it currently reads, or an empty string when there is none.
func get_countdown_text() -> String:
	if _countdown == null or not _countdown.visible or not is_showing():
		return ""
	return _countdown.text


func is_inert() -> bool:
	return _inert


# --- Wording ------------------------------------------------------------------

## The headline. It names the ROLE the player has lost, because that is what
## actually changed: a shot prisoner is not out of the match, they are a ghost,
## and a screen that said DEAD would be lying about the mechanic.
func _title_for(state: MatchController.Spectating) -> String:
	if state == MatchController.Spectating.RESPAWNING:
		return "DOWN"
	if controller.get_phase() == MatchController.Phase.RACE:
		return "OUT OF THE RACE"
	return "CONVERTED"


func _hint_for(state: MatchController.Spectating) -> String:
	if state == MatchController.Spectating.RESPAWNING:
		return "returning to the start line   ---   look around with the mouse"
	if controller.get_phase() == MatchController.Phase.RACE:
		return "you are out for the rest of the race   ---   you run the first round   ---   look around with the mouse"
	return "waiting for the round to end   ---   look around with the mouse"


# --- Construction -------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_band = ColorRect.new()
	_band.name = "Band"
	_band.color = BAND_COLOR
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.set_anchors_preset(Control.PRESET_CENTER)
	_band.anchor_left = 0.0
	_band.anchor_right = 1.0
	_band.anchor_top = 0.5 - BAND_HEIGHT_RATIO * 0.5
	_band.anchor_bottom = 0.5 + BAND_HEIGHT_RATIO * 0.5
	_band.offset_left = 0.0
	_band.offset_right = 0.0
	_band.offset_top = 0.0
	_band.offset_bottom = 0.0
	_root.add_child(_band)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.add_child(column)

	_title = _make_label("Title", TITLE_SIZE, TITLE_COLOR)
	column.add_child(_title)
	_countdown = _make_label("Countdown", COUNTDOWN_SIZE, COUNTDOWN_COLOR)
	column.add_child(_countdown)
	_hint = _make_label("Hint", HINT_SIZE, HINT_COLOR)
	column.add_child(_hint)


func _make_label(node_name: String, font_size: int, colour: Color) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	# An outline, because this text is drawn over the live world and the world
	# behind it is a grey ring under a grey sky.
	label.add_theme_constant_override(&"outline_size", 6)
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	return label
