class_name RoundTransitionScreen
extends CanvasLayer

## The moment between two rounds, given somewhere to happen.
##
## [b]The problem this exists to solve[/b]
##
## A round ends and the next one begins on the same tick. [MatchController]
## resolves the round, hands the seat over and calls
## [method MatchController.start_round], which writes a new
## [member Node3D.global_position] onto every body in the match -- and the next
## round is live before the player has registered that the last one ended. Ryan
## asked for "a transition screen each round that shows the map or something".
## This is it.
##
## [codeblock]
## round_started
##     |
##     +-- HOLD ...... SceneTree.paused, so nobody runs a metre of the new
##     |               round while the player is reading a card. See _hold().
##     v
##     +-- SHOW ...... round number, map, who holds the tower and on what turn,
##     |               how many prisoners are left -- over a live overhead
##     |               render of the arena itself.
##     v
##     +-- FADE ...... round_card_fade_seconds of it, so the card finishes
##     |               saying something rather than vanishing between frames.
##     v
##     +-- RELEASE ... the tree is unpaused and the round the match already
##                     armed carries on exactly as it was.
## [/codeblock]
##
## [b]It changes no match rule, no outcome and no score.[/b] The round has
## ALREADY been armed by the time this node hears about it -- the seat has
## changed, the bodies are placed, the counters are written -- and every word on
## the card is read back off [MatchController] at the moment it is raised. There
## is no tally here, exactly as [MatchResultScreen] keeps none. What the card
## does is stop the clock for everybody at once, which is the only way a screen
## the player has to read can be fair: without it, three bots would run a second
## and a half of the new round while the human looked at a card.
##
## [b]"Shows the map" is meant literally.[/b] The panel in the middle of the card
## is a [SubViewport] holding one [Camera3D], pointed down at the arena from
## outside the ring. It is a live render of the world the match is being played
## in, not a drawing of one and not a minimap system: no icons are tracked, no
## second representation of the arena exists, and if the map changes the card
## changes with it for free.
##
## [b]Why a SubViewport rather than a camera in the world[/b]
##
## This is the whole reason the card is safe to add. There are already two nodes
## in a match that fight over which [Camera3D] is
## [member Camera3D.current] -- [FxSpectatorView] and [SeatHandoverView] -- and
## that rank has been got wrong on this project before. A camera inside a
## [SubViewport] is current in THAT viewport and nowhere else, so this node never
## touches [member Camera3D.current] on the main viewport, never has to be ranked
## against the dead player's camera, and cannot black-screen a match by losing an
## argument about it. The subviewport inherits the match's [World3D] from the
## root viewport, which is what makes it a render of the real arena.
##
## [b]Three things keep it from becoming a tax on the person testing this game
## hundreds of times a day[/b], and they are the three
## [MatchResultScreen] already uses:
## [codeblock]
##   any key, click or pad button  -> skipped
##   headless                      -> never runs at all
##   round_card_seconds            -> a number in a .tres, not in this file
## [/codeblock]
## The headless case is the one with teeth. [method GameSettings.is_headless]
## gates [method _card_seconds], so [code]tools/harness/[/code] and the whole
## test suite see [signal MatchController.round_started] and carry straight on:
## nothing is shown, the tree is never paused, and no test has to learn about a
## timer. A match with no human in it is the same no-op for the same reason it is
## in [SeatHandoverView] -- there is nobody for a card to be shown to.
##
## [b]Structure lives in the scene.[/b] The layout is authored in
## [code]scenes/ui/round_transition_screen.tscn[/code] and this file binds the
## [code]%[/code]-named nodes and writes text into them, exactly as
## [SettingsScreen] and [MatchResultScreen] do.
## [code]RoundTransitionScreen.new()[/code] would hand back a bare [CanvasLayer]
## with no card in it; instance the scene.
##
## Strictly additive. It subscribes to signals [MatchController] already emits,
## is subscribed to by nothing, and deleting it leaves the match exactly as it
## was.

## Emitted when the card appears, carrying the round it is announcing.
signal transition_shown(round_number: int)

## Emitted when the card goes away, by the clock, by a skip, or by a fresh match.
signal transition_dismissed()

## The match to watch. Without one this node does nothing at all.
@export var controller: MatchController

## The scene's pause menu, when it has one.
##
## Used for exactly one thing, and it is the objection [MatchResultScreen]'s own
## header raises against pausing: a tree this node paused must not be unpaused
## out from under a menu the player opened over the top of it. See [method _hold].
@export var pause_menu: PauseMenu

## How long the card is held and how it fades. The SAME resource [MatchHud] and
## [MatchResultScreen] read, because the handover banner, this card and the win
## beat are one pacing decision. Unset falls back on the defaults written in
## [MatchAnnouncementProfile] itself.
@export var announcements: MatchAnnouncementProfile

## Stop the world while the card is up.
##
## [b]This is the fairness switch, not a convenience.[/b] The round is live
## behind the card: leave this off and every bot runs the length of the card
## while the human reads it, which is a handicap the rules never wrote. On, the
## tree is paused for its length and the round resumes for everybody on the same
## tick, so the card costs no one a metre.
##
## Never pauses headless, and never pauses when the card is not shown.
@export var hold_match: bool = true

## Go inert when there is no display server.
##
## The one switch the bot harness and the test suite depend on, and it is
## exported for the reason [member SeatHandoverView.headless_inert] is: the
## SHIPPED node must switch itself off in a headless run, and a test that wants
## to prove the card behaves must be able to build one that does not. Nothing
## turns this off in a played game.
@export var headless_inert: bool = true

# --- The shot of the arena ----------------------------------------------------

## Draw the live overhead render at all. Off leaves the card's text on a plain
## backdrop, which is the cheap fallback if the arena ever reads as black from
## outside it.
@export var show_map: bool = true

## Degrees above the horizon the map camera sits.
##
## Not straight down. The arena is lit by ONE red light above the tower and a
## plan view of it is mostly unlit concrete; from an angle the lit tower is in
## frame and gives the shot something to be about. It is also the shot the
## handover flight was praised for -- looking down on the ring from above.
@export_range(5.0, 80.0, 1.0) var map_pitch_degrees: float = 38.0

## Degrees around the arena axis the map camera sits at. Which side of the ring
## the card looks from; pure taste, and free to change.
@export_range(-180.0, 180.0, 1.0) var map_yaw_degrees: float = 0.0

## How far out the camera sits, in multiples of [member MatchRules.track_radius].
##
## Derived from the track rather than typed in metres so a map with a bigger ring
## frames itself.
@export_range(0.5, 6.0, 0.05) var map_distance_multiplier: float = 1.75

## Metres above the arena centre the camera aims at. A little up, so the tower is
## in the middle of the frame rather than the deck under it.
@export_range(0.0, 40.0, 0.5) var map_focus_height_metres: float = 10.0

## The map camera's field of view. Its own, not the player's: this camera is
## never current in the main viewport and the display-FOV setting has nothing to
## do with it.
@export_range(20.0, 110.0, 1.0) var map_fov_degrees: float = 55.0

## The authored card. Bound in [method _bind] rather than with [code]@onready[/code].
##
## [b]Not a style choice.[/b] [code]@onready[/code] assigns in
## [method Node._ready], and [MatchController] arms round one from its own
## [method Node._ready] -- which runs first, because it is an earlier child of
## the match. A card raised at that moment would find every one of these null.
var _root: Control = null
var _round_label: Label = null
var _map_label: Label = null
var _map_view: SubViewportContainer = null
var _map_viewport: SubViewport = null
var _map_camera: Camera3D = null
var _tower_label: Label = null
var _prisoners_label: Label = null
var _hint_label: Label = null

## Whether [method _bind] has found the authored nodes.
var _bound: bool = false

var _is_showing: bool = false

## Seconds of card left to run.
var _remaining: float = 0.0

## What [member _remaining] started at, so the fade keeps its shape.
var _total: float = 0.0

## Seconds the card has been up, which is what the skip lockout is measured
## against. Counted separately from the remainder so that editing the profile
## mid-card cannot make a card retroactively skippable.
var _elapsed: float = 0.0

## Whether the tree is paused because THIS node paused it. Never inferred from
## [member SceneTree.paused], which [PauseMenu] also writes.
var _holding: bool = false

## Used when [member announcements] is unset, built once and kept.
var _fallback_announcements: MatchAnnouncementProfile = null

## Degrees added to [member map_yaw_degrees] by the slow orbit while the card is
## up. Reset to 0.0 every time a card is raised, so each card starts from the
## authored framing and only drifts from there -- it never inherits spin left
## over from a previous card.
var _map_rotation_degrees: float = 0.0


## Subscribed here as well as in [method _ready], and that is not belt and
## braces.
##
## A match whose rules skip the opening race arms round one from inside
## [method MatchController.start_match], which [MatchController] calls from its
## own [method Node._ready] -- and Godot runs every [method Node._enter_tree] in
## a scene before any [method Node._ready] in it. Connecting only in
## [method Node._ready] would therefore miss the first round of every raceless
## match, which is exactly the configuration the Match tab's race skip selects.
## [MatchAudio] subscribes in [method Node._enter_tree] for the same reason.
func _enter_tree() -> void:
	_bind()
	_subscribe()


func _ready() -> void:
	# The card pauses the tree itself, and PauseMenu can be opened over the top
	# of it. A card that stopped counting behind a menu the player just closed
	# would leave the match paused with nothing on screen to explain it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind()
	# Guarded rather than unconditional, and that guard is the other half of the
	# note on [method _enter_tree]. A match that skips the opening race arms
	# round one from inside [method MatchController.start_match], called from
	# MatchController's own [method Node._ready] -- which runs BEFORE this one,
	# because it is an earlier child of the match. A card can therefore already
	# be up by the time this line is reached, and hiding it here would take down
	# the first card of every raceless match.
	if not _is_showing:
		_apply_visibility(false)
		_render_the_map(false)
		set_process(false)
		set_process_input(false)

	if controller == null:
		push_error("RoundTransitionScreen has no MatchController; rounds will turn over in silence.")
		return
	_subscribe()


## Never leave a scene paused because a card was still up when it was torn down.
func _exit_tree() -> void:
	hide_transition()


# --- Public API ---------------------------------------------------------------

## True when this node will never show anything: no display server, and
## [member headless_inert] left on.
func is_inert() -> bool:
	return headless_inert and GameSettings.is_headless()


## True while the card is on screen.
func is_showing() -> bool:
	return _is_showing


## Seconds of card left to run, or 0.0 when none is up.
func get_remaining_seconds() -> float:
	return maxf(_remaining, 0.0) if _is_showing else 0.0


## How long the card that is up was raised for, or 0.0 when none is.
func get_total_seconds() -> float:
	return _total if _is_showing else 0.0


## True while this node is the reason [member SceneTree.paused] is set.
func is_holding_the_match() -> bool:
	return _holding


## Raise the card for the round the match has just armed.
##
## Public and idempotent-ish: a caller that wants the card without waiting for
## the signal may ask for it, and a second call restarts the clock rather than
## stacking two cards.
func begin_transition() -> void:
	if controller == null:
		return
	# A match with no human in it -- the bot harness, a sweep -- runs the
	# identical round-start path and never gets past this line. The same guard
	# SeatHandoverView opens with, for the same reason: there is nobody to show
	# anything to.
	if controller.get_human_participant() == null:
		return
	var seconds: float = _card_seconds()
	if seconds <= 0.0:
		return
	_start(seconds)


## True while a card is up AND past its skip lockout, so a key would be answered.
## What the hint label is shown from, and the readout a test asserts the lockout
## against.
func is_skippable() -> bool:
	return _is_showing and _elapsed >= _skip_lockout_seconds()


## End the card now if it is allowed to be ended. What a key press calls.
func skip() -> void:
	if not is_skippable():
		return
	hide_transition()


## Take the card down and give the match back, whatever is running. Safe at any
## time and safe twice.
func hide_transition() -> void:
	if not _is_showing:
		return
	_is_showing = false
	_remaining = 0.0
	_total = 0.0
	_elapsed = 0.0
	set_process(false)
	set_process_input(false)
	_apply_visibility(false)
	_render_the_map(false)
	# Last, and after the card is off screen: the match must never resume on a
	# frame that is still drawing the card over it.
	_hold(false)
	transition_dismissed.emit()


## Rebuild every line from the controller. Safe to call at any time.
func refresh() -> void:
	if controller == null:
		return
	if _round_label != null:
		_round_label.text = "ROUND %d" % controller.get_round_number()
	if _map_label != null:
		_map_label.text = _map_title()
	if _tower_label != null:
		_tower_label.text = _tower_text()
	if _prisoners_label != null:
		_prisoners_label.text = "PRISONERS  %d" % controller.get_runners_remaining()


# --- What it says -------------------------------------------------------------

## The map's own title, off [MapCatalog], or an empty line when the rules name a
## map the catalog does not have. Never a guess and never the scene path.
func _map_title() -> String:
	var definition: MapDefinition = MapCatalog.by_id(controller.get_rules().map_id)
	if definition == null or definition.title.is_empty():
		return ""
	return definition.title.to_upper()


## Who holds the tower and on which of their turns -- which is the number that
## matters, because the reload shortens with every turn a player takes.
func _tower_text() -> String:
	var seat: MatchParticipant = controller.get_seat_participant()
	if seat == null:
		return "TOWER  UNCLAIMED"
	return "TOWER  %s  ·  TURN %d" % [seat.display_name.to_upper(), seat.turns_in_tower]


# --- The card -----------------------------------------------------------------

## How long the card should run for, or 0.0 for no card at all.
##
## Headless is 0.0 unconditionally and that is the load-bearing line in this
## file: the bot harness and the test suite must cross a round boundary on the
## frame the match crosses it, with no timer to advance, no tree to unpause and
## nothing to wait for.
func _card_seconds() -> float:
	if is_inert():
		return 0.0
	return _announcements().get_round_card_seconds()


func _start(seconds: float) -> void:
	_bind()
	if _root == null:
		return
	refresh()
	_frame_the_map()
	_render_the_map(true)
	if _hint_label != null:
		# Offered only once the card can actually be skipped, so the prompt is
		# never a lie.
		_hint_label.visible = _skip_lockout_seconds() <= 0.0

	_total = seconds
	_remaining = seconds
	_elapsed = 0.0
	_map_rotation_degrees = 0.0
	_root.modulate.a = 1.0
	_is_showing = true
	_apply_visibility(true)
	set_process(true)
	# Input is only listened for while there is a card to skip, so this node
	# costs a live match nothing at all.
	set_process_input(true)
	_hold(true)
	transition_shown.emit(controller.get_round_number())


func _process(delta: float) -> void:
	tick(delta)


## Advance the card by [param delta] seconds, taking it down when it runs out.
##
## Public for the same reason [method SeatHandoverView.tick] and
## [method MatchHud.tick] are: a test or a harness must be able to step this at a
## delta it chooses rather than waiting on a frame -- and this node runs on the
## render tick while the suite drives the physics one.
func tick(delta: float) -> void:
	if not _is_showing:
		set_process(false)
		return
	_elapsed += delta
	_remaining -= delta
	if _hint_label != null and not _hint_label.visible and is_skippable():
		_hint_label.visible = true
	if _remaining <= 0.0:
		hide_transition()
		return
	_orbit_the_map(delta)
	if _root == null:
		return
	var fade: float = MatchAnnouncementProfile.fade_within(
		_announcements().round_card_fade_seconds, _total
	)
	if fade > 0.0 and _remaining < fade:
		_root.modulate.a = clampf(_remaining / fade, 0.0, 1.0)


## Any key, any click, any pad button -- the same net [MatchResultScreen] casts,
## and for the same reason: the card has to answer a key nobody bound.
##
## [b]An event somebody else has already handled is not a skip.[/b] [PauseMenu]
## is the last child of the match and takes [code]ui_cancel[/code] before this
## node is offered it, so without this test the Escape that opened a menu over
## the card would also dismiss the card underneath it.
func _input(event: InputEvent) -> void:
	if not is_skippable():
		return
	var viewport: Viewport = get_viewport()
	if viewport == null or viewport.is_input_handled():
		return
	if not _is_skip(event):
		return
	viewport.set_input_as_handled()
	skip()


func _is_skip(event: InputEvent) -> bool:
	var key: InputEventKey = event as InputEventKey
	if key != null:
		return key.pressed and not key.echo
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		return button.pressed
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if pad != null:
		return pad.pressed
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		return touch.pressed
	return false


func _skip_lockout_seconds() -> float:
	return maxf(_announcements().round_card_skip_lockout_seconds, 0.0)


# --- Holding the match --------------------------------------------------------

## Stop the world for the length of the card, and start it again afterwards.
##
## [b]Only ever unpauses a pause it set itself[/b] -- [member _holding] -- and
## not even then if [PauseMenu] is open. The pause menu can be opened over the
## card, and it restores [member SceneTree.paused] itself when it closes;
## unpausing here would drop a player out of the menu they are reading and hand
## PauseMenu a tree it thinks it paused and no longer has. That is precisely the
## objection [MatchResultScreen]'s own header raises against pausing, answered
## rather than ignored.
func _hold(on: bool) -> void:
	if on:
		if _holding or not hold_match or is_inert():
			return
		var tree_in: SceneTree = get_tree()
		if tree_in == null:
			return
		_holding = true
		tree_in.paused = true
		return

	if not _holding:
		return
	_holding = false
	var tree_out: SceneTree = get_tree()
	if tree_out == null:
		return
	if pause_menu != null and is_instance_valid(pause_menu) and pause_menu.is_open():
		return
	tree_out.paused = false


# --- The map panel ------------------------------------------------------------

## Point the map camera at the arena the match is actually being played in.
##
## Everything here is derived: the centre is the arena node's own position and
## the distance is a multiple of the arena's own size, so a bigger ring frames
## itself and nothing about this arena is written down twice.
##
## [b]The size is the OUTERMOST level's outer edge[/b], not
## [member MatchRules.track_radius]. That number is the bottom deck's racing
## line, and framing a three-level amphitheatre on it puts the camera inside the
## bowl looking at a wall. The route says how big the arena actually is; a flat
## map's route says the same thing the track radius used to.
func _frame_the_map() -> void:
	if _map_camera == null or controller == null:
		return
	var arena: Node3D = controller.arena
	if arena == null or not is_instance_valid(arena):
		return
	var centre: Vector3 = arena.global_position
	var radius: float = maxf(controller.get_rules().track_radius, 1.0)
	var route: RingRoute = controller.get_route()
	var yaw: float = deg_to_rad(map_yaw_degrees + _map_rotation_degrees)
	_map_camera.fov = map_fov_degrees
	if route != null and route.level_count() > 0:
		# A hole in the ground with a roofed gallery: from outside there is only
		# rock. Stand inside the void above the deck and look across the ring.
		var top: RingLevel = route.level_at(route.last_index())
		var deck_y: float = centre.y + route.deck_height(route.last_index())
		var across: Vector3 = Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, yaw)
		var inner: float = top.inner_radius if top != null else radius
		var lane: float = route.lane_radius(route.last_index())
		_map_camera.global_position = centre - across * inner * 0.5 + Vector3.UP * (deck_y + 10.0)
		_map_camera.look_at(centre + across * lane + Vector3.UP * deck_y, Vector3.UP)
		return
	var pitch: float = deg_to_rad(clampf(map_pitch_degrees, 5.0, 80.0))
	var away: Vector3 = Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw)
	_map_camera.global_position = centre + away * radius * maxf(map_distance_multiplier, 0.1)
	_map_camera.look_at(centre + Vector3.UP * map_focus_height_metres, Vector3.UP)


## Advance the slow orbit and re-frame the camera against it.
##
## [b]Why this runs off [method tick] rather than a [Tween] or [AnimationPlayer]
## [/b]: [method tick] is already the one clock this node keeps that survives
## the tree being paused -- [member process_mode] is
## [constant Node.PROCESS_MODE_ALWAYS] precisely so the card's own fade and
## skip lockout keep advancing while [SceneTree.paused] is true, and the orbit
## rides the same clock rather than inventing a second one. Zero speed is a
## no-op: [member map_yaw_degrees] alone decides the shot, exactly as before
## this existed.
func _orbit_the_map(delta: float) -> void:
	var degrees_per_second: float = _announcements().round_card_rotation_degrees_per_second
	if degrees_per_second == 0.0:
		return
	_map_rotation_degrees += degrees_per_second * delta
	_frame_the_map()


## Switch the overhead render on for the length of the card and off again.
##
## Off is [constant SubViewport.UPDATE_DISABLED] rather than merely hidden: a
## second viewport rendering the arena every frame of a live match, behind an
## invisible card, is a frame cost for nothing.
func _render_the_map(on: bool) -> void:
	var wanted: bool = on and show_map and not is_inert()
	if _map_view != null:
		_map_view.visible = wanted
	if _map_viewport == null:
		return
	_map_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if wanted else SubViewport.UPDATE_DISABLED
	)


# --- Wiring -------------------------------------------------------------------

## Find the authored card. Safe to call before [method Node._ready], safe twice,
## and a no-op for a bare [code]RoundTransitionScreen.new()[/code] -- which has
## no card in it and is not how this node is meant to be built.
func _bind() -> void:
	if _bound:
		return
	if get_node_or_null(^"%Root") == null:
		return
	_bound = true
	_root = get_node_or_null(^"%Root") as Control
	_round_label = get_node_or_null(^"%Round") as Label
	_map_label = get_node_or_null(^"%MapName") as Label
	_map_view = get_node_or_null(^"%MapView") as SubViewportContainer
	_map_viewport = get_node_or_null(^"%MapViewport") as SubViewport
	_map_camera = get_node_or_null(^"%MapCamera") as Camera3D
	_tower_label = get_node_or_null(^"%Tower") as Label
	_prisoners_label = get_node_or_null(^"%Prisoners") as Label
	_hint_label = get_node_or_null(^"%Hint") as Label


func _subscribe() -> void:
	if controller == null:
		return
	if not controller.round_started.is_connected(_on_round_started):
		controller.round_started.connect(_on_round_started)
	if not controller.match_started.is_connected(_on_match_started):
		controller.match_started.connect(_on_match_started)
	if not controller.match_won.is_connected(_on_match_won):
		controller.match_won.connect(_on_match_won)


func _on_round_started() -> void:
	begin_transition()


## A fresh match. Whatever was on screen is about to be wrong, and the round card
## for round one arrives immediately after this on a match that skips the race.
func _on_match_started(_participant_count: int) -> void:
	hide_transition()


## The win beat on [MatchResultScreen] takes the screen from here. Two
## announcements over each other read as one unreadable one -- the same ruling
## [MatchHud] makes about its handover banner.
func _on_match_won(_participant: MatchParticipant) -> void:
	hide_transition()


## The tuning, whether or not the scene supplied any.
func _announcements() -> MatchAnnouncementProfile:
	if announcements != null:
		return announcements
	if _fallback_announcements == null:
		_fallback_announcements = MatchAnnouncementProfile.new()
	return _fallback_announcements


func _apply_visibility(visible_now: bool) -> void:
	if _root != null:
		_root.visible = visible_now
