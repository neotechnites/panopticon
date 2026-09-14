class_name HubLobby
extends Node

## The hub world's lobby: who is standing in it, what the host can start from
## where, and the switch into a match and back.
##
## [b]The hub is a match with the match taken out.[/b] The bodies, the
## replication and the shove are [MatchController] and [NetMatch] in
## [member MatchController.hub_mode]; this node adds only what a lobby has that
## a match does not -- a wedge you stand on, a prompt, the rules panel, and the
## decision to launch. There is no second body path and no second snapshot path.
##
## [b]Host pick, not a vote.[/b] The host walks onto a wedge's dais and presses
## interact; everyone goes. That is the decision Ryan has made so far, and it is
## deliberately the only thing [method start_map] does that a vote would not:
## replacing it means changing who calls [method start_map] and nothing else.
## Who takes the guard seat in a match started from here is likewise not decided
## here -- the seat roles are whatever [MatchRules] already says, exactly as the
## lobby screen sets them today.
##
## [b]The session outlives the scene.[/b] [code]/root/NetSession[/code] is a
## child of the tree root, not of the hub, so hub to match to hub is three
## scenes over one session with one seat table. Offline there is no session at
## all and the same path runs with one body in it.

## The host launched, on every machine. Carries the wedge's map id, which is
## empty for a hub launched with no map chosen. Emitted immediately before the
## scene changes, so a listener sees the decision whether or not it is followed.
signal match_starting(map_id: StringName)

## The line under the crosshair changed. Empty means nothing is offered.
signal prompt_changed(text: String)

## The rules panel opened or closed.
signal overlay_toggled(is_open: bool)

const RULES_PATH: String = "res://resources/rules/default_match_rules.tres"

## Physical key that toggles the rules panel. A scancode rather than an action
## for the reason [constant MatchController.RESTART_KEY] is one: the input map
## is [code]project.godot[/code]'s business, and Tab already means focus-next to
## every [Control] in the game.
const OVERLAY_KEY: Key = KEY_TAB

## True once a match has been started from a hub, so the end of that match comes
## back to the hub instead of the main menu.
##
## Static because the match scene REPLACES the hub scene: by the time the result
## screen asks, there is no hub node left in the tree to ask. Cleared by the
## menu's direct match entry, which is the one way into a match that did not
## come through here.
static var returns_to_hub: bool = false

## The hub's controller, in [member MatchController.hub_mode].
@export var controller: MatchController

## The hub's seat-to-body bridge, in [member NetMatch.hub_mode]. Null in a scene
## with no networking at all.
@export var net_match: NetMatch

## The local player's body, for the trigger test.
@export var player: PlayerController

## The wedge whose dais this trigger stands on. Today the hell wedge; the export
## is what makes a second start point a scene edit rather than a code one.
@export var start_wedge: MapWedge

## The volume the host stands in to be offered the start.
@export var start_trigger: Area3D

## The one line of HUD a hub has beyond the prompt: how many people are here.
@export var players_label: Label

## Where the start prompt is written.
@export var prompt_label: Label

## The rules panel, shown over the hub by Tab. The same screen the menu opens.
@export var setup_screen: MatchSetupScreen

## The seat list drawn above the rules panel. Empty text offline.
@export var seats_label: Label

## The panel's container, hidden and disabled while it is closed.
@export var overlay: Control

## Where the session lives. The shipped answer is the tree root; a test that
## runs two peers in one process gives each a branch of its own.
@export var session_path: NodePath = ^"/root/NetSession"

## The scene a launch goes to.
@export_file("*.tscn") var match_scene_path: String = "res://scenes/match/match.tscn"

## The action that starts the map under your feet.
@export var interact_action: StringName = &"interact"

## Change the running scene on a launch.
##
## True in the game. False for the two-peer test, which stands two hubs in one
## tree: [method SceneTree.change_scene_to_file] replaces the whole tree, so a
## hub that insisted on it could not be tested beside a second one at all.
## [signal match_starting] is the decision and fires either way; the scene
## change is only what follows it.
@export var changes_scene: bool = true

var _store: SettingsStore = null
var _session: NetSession = null
var _lobby: NetLobby = null

## This machine's copy of the rules the host publishes. A duplicate, so editing
## it in the panel does not edit the shipped resource.
var _rules: MatchRules = null

## True for the length of [method start_map], so the seat edits a launch makes
## -- readying everybody, filling the empty seats with bots -- do not each
## rebuild the bodies of a hub that is about to be torn down anyway.
var _starting: bool = false

var _in_trigger: bool = false
var _overlay_open: bool = false
var _launched: bool = false
var _prompt: String = ""
var _mouse_before_overlay: Input.MouseMode = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	_store = SettingsStore.instance()
	_rules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
	_session = get_tree().root.get_node_or_null(session_path) as NetSession
	if _session != null and _session.is_established():
		_bind_lobby(_session.lobby)
	if setup_screen != null:
		setup_screen.start_requested.connect(_on_panel_start)
		setup_screen.closed.connect(func() -> void: set_overlay_open(false))
	# Put the panel down without going through _apply_overlay: nothing has been
	# opened yet, so there is no mouse mode to restore and no input to hand back
	# -- and handing it back would switch on a HumanIntentSource a caller (a
	# test, a capture run) had deliberately silenced.
	if overlay != null:
		overlay.visible = false
		overlay.process_mode = Node.PROCESS_MODE_DISABLED
	_refresh()


## Adopt the session's seat table and put it back in a state a launch can come
## out of.
func _bind_lobby(lobby: NetLobby) -> void:
	if lobby == null:
		return
	_lobby = lobby
	_lobby.roster_changed.connect(_on_roster_changed)
	_lobby.match_launching.connect(_on_launching)
	_lobby.phase_changed.connect(func(_phase: NetLobby.Phase) -> void: _refresh())
	if not _session.is_authority():
		return
	match _lobby.get_phase():
		NetLobby.Phase.IDLE:
			# Hosting was started somewhere that did not open a lobby -- the
			# menu's Host online, or an offline host. Open one now.
			_lobby.open(_store.settings.player_name)
		NetLobby.Phase.POST_MATCH:
			# Back from a match. Same session, same people, readiness dropped.
			_lobby.return_to_lobby()


func _process(_delta: float) -> void:
	var body: PlayerController = _local_body()
	var inside: bool = (
		start_trigger != null
		and body != null
		and start_trigger.get_overlapping_bodies().has(body)
	)
	if inside != _in_trigger:
		_in_trigger = inside
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == OVERLAY_KEY:
		set_overlay_open(not _overlay_open)
		_consume_event()
		return
	if _launched or _overlay_open or not InputMap.has_action(interact_action):
		return
	if not event.is_action_pressed(interact_action):
		return
	if _in_trigger and is_host():
		start_map()
		_consume_event()


## Mark the event handled, when there is still a viewport to tell.
##
## A launch takes the hub out of the tree, and the rest of that input frame runs
## on a node that has already left it.
func _consume_event() -> void:
	if not is_inside_tree():
		return
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


# --- State --------------------------------------------------------------------

## True when this machine may start a match: hosting, or alone offline.
func is_host() -> bool:
	return _session == null or not _session.is_established() or _session.is_authority()


## True while the local body is standing on the start wedge's dais.
func is_on_the_dais() -> bool:
	return _in_trigger


## The line the HUD is showing, or empty when nothing is offered.
func get_prompt() -> String:
	return _prompt


func is_overlay_open() -> bool:
	return _overlay_open


## How many people are in the hub. Bots are not: they belong to a match.
func get_player_count() -> int:
	if _lobby == null:
		return 1
	var count: int = 0
	for seat: LobbySeat in _lobby.get_occupied_seats():
		if seat.is_human():
			count += 1
	return maxi(count, 1)


func get_session() -> NetSession:
	return _session


func get_lobby() -> NetLobby:
	return _lobby


# --- Starting -----------------------------------------------------------------

## Start the map on [member start_wedge], for everyone. Host only.
##
## Returns false and changes nothing when this machine is not the host, when the
## wedge holds no map, or when the seat table refuses the launch -- and the
## refusal is [method NetLobby.describe_launch_block]'s to explain, not this
## node's to invent.
func start_map() -> bool:
	if _launched or _starting or not is_host():
		return false
	if start_wedge == null or not start_wedge.is_decided():
		return false
	if not String(start_wedge.map_id).is_empty():
		_store.settings.map_id = start_wedge.map_id
	_store.settings.clamp_all()
	_store.save_to_disk()

	if _lobby == null:
		# Offline: there is no roster to freeze and nobody to tell.
		_begin(start_wedge.map_id)
		return true

	_starting = true
	_store.settings.apply_to_match_rules(_rules)
	_lobby.set_rules(_rules)
	# Standing on the dais IS the host saying go, and in a hub there is no ready
	# button for anybody else to have pressed. The lobby's readiness gate stays
	# where it is -- the hub simply answers it.
	for seat: LobbySeat in _lobby.get_occupied_seats():
		_lobby.set_ready(seat.index, true)
	_lobby.fill_with_bots(_store.settings.prisoner_count + 1)
	if _rules.open_with_race:
		_lobby.clear_roles()
	else:
		var wanted: LobbySeat = _lobby.get_seat(_rules.opening_seat_index)
		_lobby.assign_guard(wanted.index if wanted != null and wanted.is_occupied() else 0)
	var launched: bool = _lobby.launch()
	_starting = false
	if not launched:
		# Refused -- the roster moved while the panel was open, say. The hub is
		# still standing, so put its bodies back in step with the seats.
		_on_roster_changed()
	return launched


## Everyone's half of a launch: remember where the match came from, say so, and
## leave. Runs on the host and on every client, off the lobby's own signal.
func _begin(map_id: StringName) -> void:
	if _launched:
		return
	_launched = true
	HubLobby.returns_to_hub = true
	match_starting.emit(map_id)
	if not changes_scene:
		return
	# Deferred: change_scene_to_file takes the hub out of the tree the moment it
	# is called, and this runs inside the hub's own input frame.
	_change_scene.call_deferred()


func _change_scene() -> void:
	if not is_inside_tree():
		return
	var error: Error = get_tree().change_scene_to_file(match_scene_path)
	if error != OK:
		push_error("HubLobby could not load %s: %s" % [match_scene_path, error_string(error)])


func _on_launching() -> void:
	_begin(_lobby.get_rules().map_id if _lobby.get_rules() != null else &"")


func _on_panel_start() -> void:
	set_overlay_open(false)
	start_map()


## A peer joined or left. The hub's bodies are built per seat, so the set is
## rebuilt rather than patched; see [method NetMatch.rebuild_hub].
func _on_roster_changed() -> void:
	if net_match != null and not _launched and not _starting:
		net_match.rebuild_hub()
	_refresh()


# --- The panel ----------------------------------------------------------------

## Show or hide the rules panel. Closed, it holds nothing: the body reads the
## mouse and the keyboard exactly as it does with no panel in the scene.
func set_overlay_open(open: bool) -> void:
	if open == _overlay_open:
		return
	_apply_overlay(open)


func _apply_overlay(open: bool) -> void:
	_overlay_open = open
	if overlay != null:
		overlay.visible = open
		overlay.process_mode = (
			Node.PROCESS_MODE_INHERIT if open else Node.PROCESS_MODE_DISABLED
		)
	if open:
		_mouse_before_overlay = Input.mouse_mode
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if setup_screen != null:
			setup_screen.refresh()
			setup_screen.focus_start()
	elif DisplayServer.get_name() != "headless":
		Input.mouse_mode = _mouse_before_overlay
	_set_body_input(not open)
	_refresh()
	overlay_toggled.emit(open)


## Mute or unmute the local body's own input while the panel is over it. The
## body itself is untouched -- it keeps its physics, and a shove already in the
## air still lands.
func _set_body_input(active: bool) -> void:
	var body: PlayerController = _local_body()
	if body == null:
		return
	for node: Node in body.get_children():
		var human: HumanIntentSource = node as HumanIntentSource
		if human != null:
			human.set_active(active)


# --- Rendering ----------------------------------------------------------------

func _refresh() -> void:
	if players_label != null:
		var count: int = get_player_count()
		players_label.text = "%d player" % count if count == 1 else "%d players" % count
	var wanted: String = _prompt_text()
	if wanted != _prompt:
		_prompt = wanted
		prompt_changed.emit(_prompt)
	if prompt_label != null:
		prompt_label.text = _prompt
		prompt_label.visible = not _prompt.is_empty()
	if seats_label != null:
		seats_label.text = _seat_lines()


func _prompt_text() -> String:
	if _overlay_open or not _in_trigger or start_wedge == null:
		return ""
	if not start_wedge.is_decided():
		return "Nothing stands here yet"
	if not is_host():
		return "Waiting for host"
	return "Start %s: %s" % [start_wedge.title, _interact_key_name()]


## What the interact action is actually bound to, so the prompt is not a lie
## after a rebind. Falls back to the shipped key when the action is missing.
func _interact_key_name() -> String:
	if not InputMap.has_action(interact_action):
		return "E"
	for event: InputEvent in InputMap.action_get_events(interact_action):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			return OS.get_keycode_string(
				key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			)
	return "E"


func _seat_lines() -> String:
	if _lobby == null:
		return ""
	var lines: PackedStringArray = PackedStringArray()
	var local: LobbySeat = _lobby.get_local_seat()
	for seat: LobbySeat in _lobby.get_occupied_seats():
		if not seat.is_human():
			continue
		var shown: String = (
			seat.display_name if not seat.display_name.is_empty()
			else "Player %d" % (seat.index + 1)
		)
		if local != null and seat.index == local.index:
			shown += "  (you)"
		if seat.peer_id == NetTransport.AUTHORITY_PEER_ID:
			shown += "  (host)"
		lines.append("Seat %d   %s" % [seat.index + 1, shown])
	return "\n".join(lines)


func _local_body() -> PlayerController:
	if player != null:
		return player
	if controller == null:
		return null
	var human: MatchParticipant = controller.get_human_participant()
	return human.body if human != null else null
