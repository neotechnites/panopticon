class_name NetMatch
extends Node

## One body and one link per lobby seat, and the server's match decisions replayed
## on every client. Idle when no established session sits at [constant SESSION_PATH].

## The server started the match, or a client learned that it did.
signal match_bound(authority: bool)

const SESSION_PATH: NodePath = ^"/root/NetSession"
const LINK_SCENE_PATH: String = "res://scenes/net/player_net_link.tscn"

## How long the server waits for clients to finish loading before starting anyway.
const READY_TIMEOUT_SECONDS: float = 10.0

@export var controller: MatchController
@export var player: PlayerController
@export var runner_scene: PackedScene
@export var runner_container: Node3D

var _session: NetSession = null
var _lobby: NetLobby = null
var _links: Array[PlayerNetLink] = []
var _slot_of_seat: Dictionary[int, int] = {}
var _pending_peers: PackedInt32Array = PackedInt32Array()
var _wait_seconds: float = 0.0
var _started: bool = false
var _fire_was_held: bool = false


func _ready() -> void:
	_session = get_tree().root.get_node_or_null(SESSION_PATH) as NetSession
	if _session == null or not _session.is_established() or controller == null:
		set_physics_process(false)
		return
	_lobby = _session.lobby
	if _lobby == null or _lobby.get_phase() != NetLobby.Phase.LAUNCHING:
		set_physics_process(false)
		return
	controller.auto_start = false
	_build_bodies()
	_apply_opening()
	if _session.is_authority():
		_subscribe_server()
		for seat: LobbySeat in _lobby.get_occupied_seats():
			if seat.is_human() and seat.peer_id != NetTransport.AUTHORITY_PEER_ID:
				_pending_peers.append(seat.peer_id)
		if _pending_peers.is_empty():
			_start_now()
	else:
		rpc_id(NetTransport.AUTHORITY_PEER_ID, &"_client_ready")


func is_active() -> bool:
	return _lobby != null


func is_authority() -> bool:
	return _session != null and _session.is_authority()


func has_started() -> bool:
	return _started


func get_local_link() -> PlayerNetLink:
	var seat: LobbySeat = _lobby.get_local_seat() if _lobby != null else null
	return _link_for_seat(seat.index) if seat != null else null


## Drive this machine's own body from [param source] instead of its scene input.
func set_local_source(source: IntentSource) -> void:
	var link: PlayerNetLink = get_local_link()
	if link == null:
		return
	link.local_source = source
	link.refresh_role()


func get_session() -> NetSession:
	return _session


# --- Bodies -------------------------------------------------------------------

func _build_bodies() -> void:
	var bodies: Array[PlayerController] = []
	var kinds: Array[MatchParticipant.Kind] = []
	var names: PackedStringArray = PackedStringArray()
	var local_seat: int = _lobby.get_local_seat_index()
	var local_slot: int = 0
	var seats: Array[LobbySeat] = _lobby.get_occupied_seats()
	for slot: int in seats.size():
		var seat: LobbySeat = seats[slot]
		var body: PlayerController
		if seat.index == local_seat and player != null:
			body = player
			local_slot = slot
		else:
			body = runner_scene.instantiate() as PlayerController
			body.name = "Seat%d" % seat.index
			runner_container.add_child(body)
		bodies.append(body)
		kinds.append(MatchParticipant.Kind.AI if seat.is_bot() else MatchParticipant.Kind.HUMAN)
		names.append(seat.display_name if not seat.display_name.is_empty() else "Player %d" % (seat.index + 1))
		_slot_of_seat[seat.index] = slot
		_add_link(seat, body, seat.index == local_seat)
	controller.configure_net(bodies, kinds, names, local_slot, not _session.is_authority())


func _add_link(seat: LobbySeat, body: PlayerController, is_local: bool) -> void:
	var link: PlayerNetLink = (load(LINK_SCENE_PATH) as PackedScene).instantiate() as PlayerNetLink
	link.name = "Link%d" % seat.index
	link.session = _session
	link.replicator = _session.replicator
	link.controller = body
	link.seat_index = seat.index
	link.owner_peer_id = seat.peer_id
	if is_local or (seat.is_bot() and _session.is_authority()):
		link.local_source = body.intent_source
	add_child(link)
	_links.append(link)


func _link_for_seat(seat_index: int) -> PlayerNetLink:
	for link: PlayerNetLink in _links:
		if link.seat_index == seat_index:
			return link
	return null


## The lobby's opening role, if it named one, is the rules' opening seat.
func _apply_opening() -> void:
	var rules: MatchRules = controller.get_rules()
	var guard: LobbySeat = _lobby.get_guard_seat()
	if guard == null or not _slot_of_seat.has(guard.index):
		rules.open_with_race = true
		return
	rules.open_with_race = false
	rules.opening_seat_index = _slot_of_seat[guard.index]


# --- Server -------------------------------------------------------------------

func _subscribe_server() -> void:
	controller.match_started.connect(func(_count: int) -> void: rpc(&"_ev_match_started"))
	controller.race_started.connect(func() -> void: rpc(&"_ev_race_started"))
	controller.round_started.connect(_on_round_started)
	controller.participant_converted.connect(
		func(participant: MatchParticipant) -> void: rpc(&"_ev_removed", participant.index)
	)
	controller.round_resolved.connect(
		func(outcome: MatchController.Outcome) -> void: rpc(&"_ev_round_resolved", int(outcome))
	)
	controller.match_won.connect(_on_match_won)
	controller.ghost_respawned.connect(
		func(participant: MatchParticipant) -> void: rpc(&"_ev_ghost_respawned", participant.index)
	)
	controller.ghost_caught.connect(
		func(ghost: MatchParticipant, caught: MatchParticipant) -> void:
			rpc(&"_ev_ghost_caught", ghost.index, caught.index)
	)
	_lobby.seat_occupancy_changed.connect(_on_seat_occupancy_changed)


func _start_now() -> void:
	if _started:
		return
	_started = true
	controller.start_match()
	_lobby.begin_match()
	match_bound.emit(true)


func _physics_process(delta: float) -> void:
	if not is_authority():
		return
	if not _started:
		_wait_seconds += delta
		if _wait_seconds >= READY_TIMEOUT_SECONDS:
			push_warning("NetMatch: %d client(s) never reported ready; starting without them." % _pending_peers.size())
			_start_now()
		return
	_drive_remote_trigger()


## A remote human in the tower fires through its intent; the server pulls the trigger.
func _drive_remote_trigger() -> void:
	var seat: MatchParticipant = controller.get_seat_participant()
	var rifle: Rifle = controller.rifle
	if seat == null or rifle == null or not seat.is_human() or seat == controller.get_human_participant():
		_fire_was_held = false
		return
	var link: PlayerNetLink = _links[seat.index] if seat.index < _links.size() else null
	var source: RemoteIntentSource = link.get_remote_source() if link != null else null
	if source == null:
		return
	var pressed: bool = source.take_fire()
	var held: bool = source.is_fire_held()
	var charged: bool = rifle.profile != null and rifle.profile.charge_enabled
	if charged:
		if pressed:
			rifle.begin_charge()
		elif _fire_was_held and not held:
			rifle.release_charge()
	elif pressed or held:
		rifle.try_fire()
	_fire_was_held = held


func _on_round_started() -> void:
	var seat: MatchParticipant = controller.get_seat_participant()
	rpc(&"_ev_round_started", seat.index if seat != null else 0, controller.get_round_number())


func _on_match_won(participant: MatchParticipant) -> void:
	rpc(&"_ev_match_won", participant.index)
	var seat: LobbySeat = _lobby.get_occupied_seats()[participant.index] if participant.index < _lobby.get_occupant_count() else null
	_lobby.conclude_match(seat.index if seat != null else -1)


func _on_seat_occupancy_changed(seat_index: int, occupancy: LobbySeat.Occupancy) -> void:
	if not _started or occupancy != LobbySeat.Occupancy.BOT or not _slot_of_seat.has(seat_index):
		return
	var slot: int = _slot_of_seat[seat_index]
	var link: PlayerNetLink = _link_for_seat(seat_index)
	if link != null:
		link.owner_peer_id = 0
		link.local_source = link.controller.get_node_or_null(^"BotInput") as IntentSource
		link.refresh_role()
	controller.net_seat_to_bot(slot)
	# Deferred: this runs inside the leaving peer's disconnect signal.
	rpc.call_deferred(&"_ev_seat_to_bot", slot)


# --- Wire ---------------------------------------------------------------------

@rpc("any_peer", "reliable", "call_remote", 0)
func _client_ready() -> void:
	if not is_authority():
		return
	var index: int = _pending_peers.find(multiplayer.get_remote_sender_id())
	if index != -1:
		_pending_peers.remove_at(index)
	if _pending_peers.is_empty():
		_start_now()


@rpc("authority", "reliable", "call_remote", 0)
func _ev_match_started() -> void:
	if is_authority():
		return
	controller.net_start_match()
	if not _started:
		_started = true
		match_bound.emit(false)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_race_started() -> void:
	if not is_authority():
		controller.net_start_race()


@rpc("authority", "reliable", "call_remote", 0)
func _ev_round_started(seat_index: int, round_number: int) -> void:
	if not is_authority():
		controller.net_start_round(seat_index, round_number)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_removed(index: int) -> void:
	if is_authority():
		return
	if controller.get_phase() == MatchController.Phase.RACE:
		controller.net_race_out(index)
	else:
		controller.net_convert(index)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_round_resolved(outcome: int) -> void:
	if not is_authority():
		controller.net_resolve(outcome as MatchController.Outcome)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_match_won(index: int) -> void:
	if not is_authority():
		controller.net_win(index)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_ghost_respawned(index: int) -> void:
	if not is_authority():
		controller.net_ghost_respawn(index)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_ghost_caught(ghost_index: int, caught_index: int) -> void:
	if not is_authority():
		controller.net_ghost_caught(ghost_index, caught_index)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_seat_to_bot(slot: int) -> void:
	if not is_authority():
		controller.net_seat_to_bot(slot)
