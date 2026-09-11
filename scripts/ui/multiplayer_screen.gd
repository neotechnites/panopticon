class_name MultiplayerScreen
extends Control

## Host or join a networked match, then sit in the lobby until the host
## starts it. Owns /root/NetSession; the match scene finds it there.

signal closed()

## The lobby launched; the match scene is about to replace this one.
signal match_launching()

const SESSION_SCENE_PATH: String = "res://scenes/net/net_session.tscn"
const SESSION_NAME: StringName = &"NetSession"
const RULES_PATH: String = "res://resources/rules/default_match_rules.tres"
const MATCH_SCENE_PATH: String = "res://scenes/match/match.tscn"
const CUSTOM_ID: int = -1

@onready var _name_edit: LineEdit = %NameEdit
@onready var _status: Label = %Status
@onready var _connect_panels: Control = %ConnectPanels
@onready var _host_port_spin: SpinBox = %HostPortSpin
@onready var _address_field: TextEdit = %AddressField
@onready var _start_hosting_button: Button = %StartHosting
@onready var _join_address_edit: LineEdit = %JoinAddressEdit
@onready var _join_port_spin: SpinBox = %JoinPortSpin
@onready var _join_button: Button = %Join
@onready var _lobby_panel: Control = %LobbyPanel
@onready var _lobby_title: Label = %LobbyTitle
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _preset_option: OptionButton = %PresetOption
@onready var _prisoner_count_spin: SpinBox = %PrisonerCountSpin
@onready var _rules_summary: Label = %RulesSummary
@onready var _ready_toggle: CheckButton = %ReadyToggle
@onready var _start_match_button: Button = %StartMatch
@onready var _leave_button: Button = %Leave
@onready var _back_button: Button = %Back

var _store: SettingsStore = null
var _session: NetSession = null
var _lobby: NetLobby = null
var _rules: MatchRules = null
var _syncing: bool = false
var _named: bool = false
var _launched: bool = false


func _ready() -> void:
	_store = SettingsStore.instance()
	_rules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
	_configure_controls()
	_name_edit.text_changed.connect(_on_name_changed)
	_host_port_spin.value_changed.connect(func(value: float) -> void: _render_addresses(int(value)))
	_start_hosting_button.pressed.connect(func() -> void: start_hosting())
	_join_address_edit.text_changed.connect(func(text: String) -> void:
		_store.settings.join_address = text)
	_join_port_spin.value_changed.connect(func(value: float) -> void:
		_store.settings.join_port = int(value))
	_join_button.pressed.connect(func() -> void: join_game())
	_preset_option.item_selected.connect(_on_preset_selected)
	_prisoner_count_spin.value_changed.connect(_on_prisoner_count_changed)
	_ready_toggle.toggled.connect(func(pressed: bool) -> void: set_ready(pressed))
	_start_match_button.pressed.connect(func() -> void: start_match())
	_leave_button.pressed.connect(leave)
	_back_button.pressed.connect(close)
	refresh()


# --- Public -------------------------------------------------------------------

## Reload the fields from settings and rescan addresses.
func refresh() -> void:
	var settings: GameSettings = _store.settings
	_syncing = true
	_name_edit.text = settings.player_name
	_join_address_edit.text = settings.join_address
	_join_port_spin.value = float(settings.join_port)
	if _session == null:
		_host_port_spin.value = float(NetSettings.new().port)
	_syncing = false
	_render_addresses(int(_host_port_spin.value))
	_show_lobby(_session != null and _session.is_established())


func focus_start() -> void:
	if _lobby_panel.visible:
		_ready_toggle.grab_focus()
	else:
		_start_hosting_button.grab_focus()


func get_session() -> NetSession:
	return _session


func get_lobby() -> NetLobby:
	return _lobby


func set_player_name(display_name: String) -> void:
	_name_edit.text = display_name
	_on_name_changed(display_name)


func set_host_port(port: int) -> void:
	_host_port_spin.value = float(port)


func set_join_target(address: String, port: int) -> void:
	_join_address_edit.text = address
	_join_port_spin.value = float(port)
	_store.settings.join_address = address
	_store.settings.join_port = port


func start_hosting() -> Error:
	ensure_session()
	var port: int = int(_host_port_spin.value)
	var error: Error = _session.host(port)
	_status.text = "Hosting on port %d" % port if error == OK else "Could not host: %s" % error_string(error)
	return error


func join_game() -> Error:
	ensure_session()
	_store.settings.clamp_all()
	var settings: GameSettings = _store.settings
	var error: Error = _session.join(settings.join_address, settings.join_port)
	_status.text = (
		"Joining %s:%d..." % [settings.join_address, settings.join_port]
		if error == OK else "Could not join: %s" % error_string(error)
	)
	return error


func is_host() -> bool:
	return _session != null and _session.is_established() and _session.is_authority()


## Host only. Total prisoners in the match; the seats humans do not fill get bots.
func set_prisoner_count(count: int) -> void:
	if not is_host():
		return
	_store.settings.prisoner_count = count
	_publish_rules()


## Host only. Apply a named preset from [MatchPresets].
func select_preset(id: StringName) -> void:
	if not is_host():
		return
	var preset: MatchPresets.Preset = MatchPresets.by_id(id)
	if preset == null:
		return
	preset.apply_to(_store.settings)
	_publish_rules()


func get_rules() -> MatchRules:
	return _rules


func set_ready(ready: bool) -> void:
	if _lobby == null or _lobby.get_local_seat() == null:
		return
	_lobby.set_ready(_lobby.get_local_seat_index(), ready)


func can_start() -> bool:
	return (
		is_host()
		and _lobby.get_phase() == NetLobby.Phase.GATHERING
		and _lobby.get_occupant_count() >= 1
		and _lobby.is_everyone_ready()
	)


## Host only. Fill the ring with bots, set the opening roles and launch.
func start_match() -> bool:
	if not can_start():
		_status.text = _lobby.describe_launch_block() if _lobby != null else "Not hosting."
		return false
	var settings: GameSettings = _store.settings
	_lobby.fill_with_bots(settings.prisoner_count + 1)
	if _rules.open_with_race:
		_lobby.clear_roles()
	else:
		var wanted: LobbySeat = _lobby.get_seat(_rules.opening_seat_index)
		_lobby.assign_guard(wanted.index if wanted != null and wanted.is_occupied() else 0)
	if not _lobby.launch():
		_status.text = _lobby.describe_launch_block()
		return false
	return true


## Drop the session and return to the host/join panels.
func leave() -> void:
	if _session != null:
		_session.leave()
	_named = false
	_status.text = ""
	_show_lobby(false)


func close() -> void:
	leave()
	_store.settings.clamp_all()
	_store.save_to_disk()
	AudioDirector.post_event(AudioEvents.UI_BACK)
	closed.emit()


## Find or create /root/NetSession.
func ensure_session() -> NetSession:
	if _session != null:
		return _session
	var root: Window = get_tree().root
	var found: NetSession = root.get_node_or_null(NodePath(SESSION_NAME)) as NetSession
	if found == null:
		found = (load(SESSION_SCENE_PATH) as PackedScene).instantiate() as NetSession
		found.name = SESSION_NAME
		root.add_child(found)
	_bind_session(found)
	return _session


## Every non-loopback IPv4 this machine has, Tailscale (100.64/10) marked.
static func local_addresses() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for address: String in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127."):
			continue
		var parts: PackedStringArray = address.split(".")
		if parts.size() != 4:
			continue
		var second: int = int(parts[1])
		var tailscale: bool = parts[0] == "100" and second >= 64 and second <= 127
		if tailscale:
			lines.insert(0, "%s   (Tailscale)" % address)
		else:
			lines.append(address)
	return lines


# --- Session ------------------------------------------------------------------

func _bind_session(session: NetSession) -> void:
	_session = session
	_lobby = session.lobby
	session.session_established.connect(_on_established)
	session.session_ended.connect(_on_session_ended)
	_lobby.roster_changed.connect(_render_roster)
	_lobby.rules_changed.connect(_on_rules_changed)
	_lobby.match_launching.connect(_on_launching)
	_lobby.join_refused.connect(func(_peer: int, why: String) -> void: _status.text = why)


func _on_established() -> void:
	_named = false
	if _session.is_authority():
		_lobby.open(_store.settings.player_name)
		_publish_rules()
		_lobby_title.text = "LOBBY  ·  hosting on port %d" % int(_host_port_spin.value)
	else:
		_lobby_title.text = "LOBBY  ·  %s" % _store.settings.join_address
		_status.text = "Connected. Waiting for the host."
	_show_lobby(true)
	_render_roster()
	_render_rules()


func _on_session_ended(failed: bool) -> void:
	_status.text = "Connection failed." if failed else "Left the lobby."
	_named = false
	_show_lobby(false)


func _on_launching() -> void:
	if _launched:
		return
	_launched = true
	_store.save_to_disk()
	match_launching.emit()
	var error: Error = get_tree().change_scene_to_file(MATCH_SCENE_PATH)
	if error != OK:
		push_error("MultiplayerScreen could not load %s: %s" % [MATCH_SCENE_PATH, error_string(error)])


func _publish_rules() -> void:
	if not is_host():
		return
	_store.settings.clamp_all()
	_store.settings.apply_to_match_rules(_rules)
	_lobby.set_rules(_rules)
	_render_rules()


func _on_rules_changed() -> void:
	if is_host():
		return
	NetCodec.copy_rules(_lobby.get_rules(), _rules)
	_render_rules()


# --- Controls -----------------------------------------------------------------

func _configure_controls() -> void:
	_host_port_spin.min_value = float(GameSettings.MIN_NET_PORT)
	_host_port_spin.max_value = float(GameSettings.MAX_NET_PORT)
	_join_port_spin.min_value = float(GameSettings.MIN_NET_PORT)
	_join_port_spin.max_value = float(GameSettings.MAX_NET_PORT)
	_prisoner_count_spin.min_value = float(GameSettings.MIN_PRISONER_COUNT)
	_prisoner_count_spin.max_value = float(GameSettings.MAX_PRISONER_COUNT)
	_name_edit.max_length = GameSettings.MAX_PLAYER_NAME_LENGTH
	_preset_option.clear()
	var presets: Array[MatchPresets.Preset] = MatchPresets.all()
	for index: int in presets.size():
		_preset_option.add_item(presets[index].title, index)
	_preset_option.add_item("Custom", CUSTOM_ID)
	_preset_option.set_item_disabled(_preset_option.item_count - 1, true)


func _on_name_changed(text: String) -> void:
	if _syncing:
		return
	_store.settings.player_name = text
	if _lobby != null and _lobby.get_local_seat() != null:
		_lobby.set_display_name(_lobby.get_local_seat_index(), text)


func _on_preset_selected(index: int) -> void:
	if _syncing:
		return
	var id: int = _preset_option.get_item_id(index)
	var presets: Array[MatchPresets.Preset] = MatchPresets.all()
	if id < 0 or id >= presets.size():
		return
	select_preset(presets[id].id)


func _on_prisoner_count_changed(value: float) -> void:
	if _syncing:
		return
	set_prisoner_count(int(roundf(value)))


# --- Rendering ----------------------------------------------------------------

func _show_lobby(in_lobby: bool) -> void:
	_connect_panels.visible = not in_lobby
	_lobby_panel.visible = in_lobby
	if in_lobby:
		var host: bool = is_host()
		_start_match_button.visible = host
		_prisoner_count_spin.editable = host
		_preset_option.disabled = not host


func _render_addresses(port: int) -> void:
	var lines: PackedStringArray = local_addresses()
	if lines.is_empty():
		_address_field.text = "No network address found."
		return
	for i: int in lines.size():
		lines[i] = "%s  port %d" % [lines[i], port]
	_address_field.text = "\n".join(lines)


func _render_roster() -> void:
	if _lobby == null:
		return
	var local: LobbySeat = _lobby.get_local_seat()
	if local != null and not _named and not is_host():
		_named = true
		_lobby.set_display_name(local.index, _store.settings.player_name)
	for child: Node in _player_list.get_children():
		child.queue_free()
	for seat: LobbySeat in _lobby.get_occupied_seats():
		var row: Label = Label.new()
		var shown: String = seat.display_name if not seat.display_name.is_empty() else "Player %d" % (seat.index + 1)
		if seat.is_bot():
			shown += " (bot)"
		if local != null and seat.index == local.index:
			shown += " (you)"
		row.text = "Seat %d   %s   %s   %s" % [
			seat.index + 1, shown, _role_name(seat.role), "READY" if seat.is_ready else "not ready",
		]
		_player_list.add_child(row)
	if local != null:
		_ready_toggle.set_pressed_no_signal(local.is_ready)
	_ready_toggle.disabled = local == null or _lobby.get_phase() != NetLobby.Phase.GATHERING
	_start_match_button.disabled = not can_start()
	_start_match_button.tooltip_text = _lobby.describe_launch_block() if is_host() else ""


func _render_rules() -> void:
	var probe: GameSettings = _settings_of(_rules)
	var found: MatchPresets.Preset = MatchPresets.describing(probe)
	var presets: Array[MatchPresets.Preset] = MatchPresets.all()
	_syncing = true
	_prisoner_count_spin.value = float(_rules.prisoner_count)
	_preset_option.selected = _index_of(_preset_option, presets.find(found) if found != null else CUSTOM_ID)
	_syncing = false
	_rules_summary.text = "%s  ·  %d prisoners  ·  ghosts %s  ·  %s  ·  %s to win" % [
		found.title if found != null else "Custom rules",
		_rules.prisoner_count,
		"on" if _rules.has_ghosts() else "off",
		"race for the tower" if _rules.open_with_race else "seat %d opens in the tower" % (_rules.opening_seat_index + 1),
		"one round" if _rules.rounds_to_win_match == 1 else "%d rounds" % _rules.rounds_to_win_match,
	]


static func _settings_of(rules: MatchRules) -> GameSettings:
	var probe: GameSettings = GameSettings.new()
	probe.prisoner_count = rules.prisoner_count
	probe.prisoner_lives = rules.prisoner_lives
	probe.ghosts_enabled = rules.has_ghosts()
	probe.skip_opening_race = not rules.open_with_race
	probe.tower_seat_index = rules.opening_seat_index
	probe.shooter_win_condition = rules.shooter_win_condition
	probe.runner_win_condition = rules.runner_win_condition
	probe.rounds_to_win_match = rules.rounds_to_win_match
	return probe


static func _role_name(role: LobbySeat.Role) -> String:
	match role:
		LobbySeat.Role.GUARD:
			return "tower"
		LobbySeat.Role.PRISONER:
			return "prisoner"
	return "race"


static func _index_of(option: OptionButton, id: int) -> int:
	for index: int in option.item_count:
		if option.get_item_id(index) == id:
			return index
	return 0
