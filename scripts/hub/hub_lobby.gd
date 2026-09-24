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
## [b]Host pick, or a vote.[/b] Under [constant MatchRules.MapPickMode.HOST] the
## host walks onto any decided wedge's dais and presses interact; everyone goes
## to that wedge's map. Under
## [constant MatchRules.MapPickMode.VOTE] the same press opens a vote instead:
## for [member MatchRules.vote_seconds] every body standing on a decided wedge's
## dais is a vote for it, the host counts them, and the fullest dais starts --
## ties by a seeded draw -- through the same launch path. Who takes the guard
## seat is not decided here either way: the seat roles are whatever [MatchRules]
## already says.
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

## The vote opened, moved, closed or was cancelled on this machine.
signal vote_changed()

## The vote ended with a winner. [param tied] when the seed had to break it.
signal vote_closed(winner: MapWedge, rng_seed: int, tied: bool)

const RULES_PATH: String = "res://match/rules/default_match_rules.tres"

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

## The parent of every [MapWedge]: each one's dais is a start point, and a vote
## counts them all.
@export var wedges_root: Node3D

## The small vote readout: the timer and one line per decided wedge.
@export var vote_label: Label

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
@export_file("*.tscn") var match_scene_path: String = "res://match/match.tscn"

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

## The wedge whose dais the local body is standing on, or null out on the ring.
var _wedge_here: MapWedge = null
var _overlay_open: bool = false
var _launched: bool = false
var _prompt: String = ""
var _mouse_before_overlay: Input.MouseMode = Input.MOUSE_MODE_CAPTURED

var _wedges: Array[MapWedge] = []
var _wedge_triggers: Array[Area3D] = []
var _vote_open: bool = false
var _vote_seconds_left: float = 0.0
var _vote_shown_seconds: int = -1
var _vote_seed: int = 0
var _vote_counts: PackedInt32Array = PackedInt32Array()
var _vote_winner: MapWedge = null
var _vote_tied: bool = false


func _ready() -> void:
	_store = SettingsStore.instance()
	_rules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
	_session = get_tree().root.get_node_or_null(session_path) as NetSession
	if wedges_root != null:
		for child: Node in wedges_root.get_children():
			var wedge: MapWedge = child as MapWedge
			if wedge != null:
				_wedges.append(wedge)
				_wedge_triggers.append(wedge.get_trigger())
	_vote_counts.resize(_wedges.size())
	if vote_label != null:
		vote_label.visible = false
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
	# So a client knows how the map gets picked before the host presses anything.
	_publish_rules()


func _process(_delta: float) -> void:
	var here: MapWedge = _wedge_under(_local_body())
	if here != _wedge_here:
		_wedge_here = here
		_refresh()


## The wedge whose dais trigger holds [param body], or null.
func _wedge_under(body: PlayerController) -> MapWedge:
	if body == null:
		return null
	for i: int in _wedges.size():
		var trigger: Area3D = _wedge_triggers[i]
		if trigger != null and trigger.overlaps_body(body):
			return _wedges[i]
	return null


func _physics_process(delta: float) -> void:
	if not _vote_open:
		return
	_vote_seconds_left = maxf(_vote_seconds_left - delta, 0.0)
	if not is_host():
		if ceili(_vote_seconds_left) != _vote_shown_seconds:
			_refresh_vote_view()
		return
	if _count_votes():
		_publish_vote()
	elif ceili(_vote_seconds_left) != _vote_shown_seconds:
		_refresh_vote_view()
	if _vote_seconds_left <= 0.0:
		_close_vote()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == OVERLAY_KEY:
		set_overlay_open(not _overlay_open)
		_consume_event()
		return
	if _launched or _overlay_open or not InputMap.has_action(interact_action):
		return
	if not event.is_action_pressed(interact_action) or not is_host():
		return
	if _vote_open:
		cancel_vote()
		_consume_event()
	elif _wedge_here != null:
		if _pick_mode() == MatchRules.MapPickMode.VOTE:
			open_vote()
		else:
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


## True while the local body is standing on a wedge's dais.
func is_on_the_dais() -> bool:
	return _wedge_here != null


## The wedge whose dais the local body is standing on, or null.
func get_wedge_here() -> MapWedge:
	return _wedge_here


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


## How the map gets picked on this machine: the host's own setting, or the
## rules the host published.
func _pick_mode() -> MatchRules.MapPickMode:
	if is_host():
		return _store.settings.map_pick_mode as MatchRules.MapPickMode
	var rules: MatchRules = _lobby.get_rules() if _lobby != null else null
	return rules.map_pick_mode if rules != null else MatchRules.MapPickMode.HOST


# --- The vote -----------------------------------------------------------------

func is_vote_open() -> bool:
	return _vote_open


func get_vote_seconds_left() -> float:
	return _vote_seconds_left


func get_vote_seed() -> int:
	return _vote_seed


## Bodies on [param wedge]'s dais as of the last count, or 0 off a vote.
func get_vote_count(wedge: MapWedge) -> int:
	var index: int = _wedges.find(wedge)
	return _vote_counts[index] if index >= 0 else 0


## The wedge the last vote picked, or null while none has.
func get_vote_winner() -> MapWedge:
	return _vote_winner


func was_vote_tied() -> bool:
	return _vote_tied


## Open the vote, for everyone. Host only, and only under
## [constant MatchRules.MapPickMode.VOTE]. [param rng_seed] 0 draws one.
func open_vote(rng_seed: int = 0) -> bool:
	if _launched or _starting or _vote_open or not is_host():
		return false
	if _pick_mode() != MatchRules.MapPickMode.VOTE or _decided_count() == 0:
		return false
	if _lobby != null and _lobby.get_phase() != NetLobby.Phase.GATHERING:
		return false
	_publish_rules()
	_vote_seed = rng_seed if rng_seed != 0 else maxi(randi(), 1)
	_vote_seconds_left = _rules.vote_seconds
	_vote_shown_seconds = -1
	_vote_counts.fill(0)
	_vote_winner = null
	_vote_tied = false
	_vote_open = true
	_count_votes()
	_publish_vote()
	_refresh()
	return true


## Drop the vote without a launch. Host only.
func cancel_vote() -> bool:
	if not _vote_open or not is_host():
		return false
	_vote_open = false
	_vote_winner = null
	_publish_vote()
	_refresh()
	return true


## The wedge [param counts] elects: the fullest decided one, ties drawn with
## [param rng_seed]. -1 when no wedge is decided.
func resolve_winner(counts: PackedInt32Array, rng_seed: int) -> int:
	var best: int = -1
	for i: int in _wedges.size():
		if _wedges[i].is_decided() and i < counts.size():
			best = maxi(best, counts[i])
	var tied: PackedInt32Array = PackedInt32Array()
	for i: int in _wedges.size():
		if _wedges[i].is_decided() and i < counts.size() and counts[i] == best:
			tied.append(i)
	if tied.is_empty():
		return -1
	if tied.size() == 1:
		return tied[0]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed
	return tied[rng.randi_range(0, tied.size() - 1)]


func _decided_count() -> int:
	var count: int = 0
	for wedge: MapWedge in _wedges:
		if wedge.is_decided():
			count += 1
	return count


## True when more than one decided wedge holds the top count.
func _is_tied(counts: PackedInt32Array) -> bool:
	var best: int = -1
	var holders: int = 0
	for i: int in _wedges.size():
		if not _wedges[i].is_decided() or i >= counts.size():
			continue
		if counts[i] > best:
			best = counts[i]
			holders = 1
		elif counts[i] == best:
			holders += 1
	return holders > 1


## Recount the bodies on every decided dais. True when a count moved.
func _count_votes() -> bool:
	var changed: bool = false
	if controller == null:
		return false
	var participants: Array[MatchParticipant] = controller.get_participants_ref()
	for i: int in _wedges.size():
		var count: int = 0
		var trigger: Area3D = _wedge_triggers[i]
		if trigger != null and _wedges[i].is_decided():
			for participant: MatchParticipant in participants:
				if participant.body != null and trigger.overlaps_body(participant.body):
					count += 1
		if count != _vote_counts[i]:
			_vote_counts[i] = count
			changed = true
	return changed


func _close_vote() -> void:
	var winner: int = resolve_winner(_vote_counts, _vote_seed)
	_vote_open = false
	_vote_winner = _wedges[winner] if winner >= 0 else null
	_vote_tied = winner >= 0 and _is_tied(_vote_counts)
	_publish_vote()
	if _vote_winner == null:
		_refresh()
		return
	vote_closed.emit(_vote_winner, _vote_seed, _vote_tied)
	if not _start_on(_vote_winner):
		_refresh()


## The host's copy of the vote, to this machine and to every client.
func _publish_vote() -> void:
	_refresh_vote_view()
	vote_changed.emit()
	if _lobby != null and _session.is_established() and _session.get_peer_count() > 1:
		rpc(
			&"_vote_state", _vote_open, _vote_seconds_left, _vote_seed,
			_wedges.find(_vote_winner), _vote_counts,
		)


## Authority to everyone: where the vote stands.
@rpc("authority", "reliable", "call_remote", 0)
func _vote_state(
	open: bool, seconds: float, rng_seed: int, winner: int, counts: PackedInt32Array
) -> void:
	if is_host() or not is_finite(seconds) or counts.size() != _wedges.size():
		return
	_vote_open = open
	_vote_seconds_left = maxf(seconds, 0.0)
	_vote_seed = rng_seed
	_vote_counts = counts
	_vote_winner = _wedges[winner] if winner >= 0 and winner < _wedges.size() else null
	_vote_tied = _vote_winner != null and _is_tied(counts)
	_refresh_vote_view()
	vote_changed.emit()
	_refresh()


## The host's settings onto the rules every machine plays by.
func _publish_rules() -> void:
	_store.settings.apply_to_match_rules(_rules)
	if _lobby != null:
		_lobby.set_rules(_rules)


# --- Starting -----------------------------------------------------------------

## Start the map on the wedge under the local body, for everyone. Host only.
##
## Returns false and changes nothing when this machine is not the host, when
## the body is not on a dais or the wedge holds no map, or when the seat table
## refuses the launch -- and the refusal is
## [method NetLobby.describe_launch_block]'s to explain, not this node's to
## invent.
func start_map() -> bool:
	return _start_on(_wedge_here)


func _start_on(wedge: MapWedge) -> bool:
	if _launched or _starting or _vote_open or not is_host():
		return false
	if wedge == null or not wedge.is_decided():
		return false
	if not String(wedge.map_id).is_empty():
		_store.settings.map_id = wedge.map_id
	_store.settings.clamp_all()
	_store.save_to_disk()

	if _lobby == null:
		# Offline: there is no roster to freeze and nobody to tell.
		_begin(wedge.map_id)
		return true

	_starting = true
	_publish_rules()
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


## The panel's Start: the wedge under the body, else the wedge holding the map
## the panel picked.
func _on_panel_start() -> void:
	set_overlay_open(false)
	_start_on(_wedge_here if _wedge_here != null else _wedge_for_map(_store.settings.map_id))


## The wedge holding [param map_id], or null when no wedge has it.
func _wedge_for_map(map_id: StringName) -> MapWedge:
	for wedge: MapWedge in _wedges:
		if wedge.is_decided() and wedge.map_id == map_id:
			return wedge
	return null


## A peer joined or left. The hub's bodies are built per seat, so the set is
## rebuilt rather than patched; see [method NetMatch.rebuild_hub].
func _on_roster_changed() -> void:
	if net_match != null and not _launched and not _starting:
		net_match.rebuild_hub()
	if _vote_open and is_host():
		# A joiner missed the opening; the bodies were just rebuilt anyway.
		_publish_vote()
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
		players_label.text = tr("HUB_PLAYERS_ONE" if count == 1 else "HUB_PLAYERS_MANY").format({"count": count})
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
	if _overlay_open:
		return ""
	if _vote_open:
		return tr("HUB_CANCEL_VOTE_PROMPT").format({"key": _interact_key_name()}) if is_host() else ""
	if _wedge_here == null:
		return ""
	if not _wedge_here.is_decided():
		return tr("HUB_NOTHING_HERE")
	if not is_host():
		return tr("HUB_WAITING_FOR_HOST")
	if _pick_mode() == MatchRules.MapPickMode.VOTE:
		return tr("HUB_OPEN_VOTE_PROMPT").format({"key": _interact_key_name()})
	return tr("HUB_START_PROMPT").format({"map": tr(_wedge_here.title), "key": _interact_key_name()})


## The signs and the readout, from the counts as they stand.
func _refresh_vote_view() -> void:
	_vote_shown_seconds = ceili(_vote_seconds_left)
	for i: int in _wedges.size():
		_wedges[i].set_vote_count(_vote_counts[i] if _vote_open else -1)
	if vote_label == null:
		return
	if _vote_open:
		var lines: PackedStringArray = PackedStringArray([
			tr("HUB_VOTE_TIMER").format({"seconds": _vote_shown_seconds})
		])
		for i: int in _wedges.size():
			if _wedges[i].is_decided():
				lines.append(tr("HUB_VOTE_ROW").format({
					"map": tr(_wedges[i].title), "count": _vote_counts[i]
				}))
		vote_label.text = "\n".join(lines)
		vote_label.visible = true
	elif _vote_winner != null:
		vote_label.text = tr("HUB_VOTE_WINS_TIE" if _vote_tied else "HUB_VOTE_WINS").format({
			"map": tr(_vote_winner.title), "seed": _vote_seed
		})
		vote_label.visible = true
	else:
		vote_label.visible = false


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
			else tr("HUB_SEAT_PLAYER").format({"number": seat.index + 1})
		)
		if local != null and seat.index == local.index:
			shown = tr("HUB_SEAT_NAME_YOU").format({"name": shown})
		if seat.peer_id == NetTransport.AUTHORITY_PEER_ID:
			shown = tr("HUB_SEAT_NAME_HOST").format({"name": shown})
		lines.append(tr("HUB_SEAT_ROW").format({"number": seat.index + 1, "name": shown}))
	return "\n".join(lines)


func _local_body() -> PlayerController:
	if player != null:
		return player
	if controller == null:
		return null
	var human: MatchParticipant = controller.get_human_participant()
	return human.body if human != null else null
