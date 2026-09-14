class_name NetMatch
extends Node

## One body and one link per lobby seat, and the server's match decisions replayed
## on every client. Idle when no established session sits at [constant SESSION_PATH].

## The server started the match, or a client learned that it did.
signal match_bound(authority: bool)

## The session this match was running on ended under a client -- the host quit,
## crashed or timed out. Client-only, and there is no host migration: whoever
## is listening is being told the match is over, not asked to take it over.
signal host_lost()

const SESSION_PATH: NodePath = ^"/root/NetSession"
const LINK_SCENE_PATH: String = "res://scenes/net/player_net_link.tscn"

## How long the server waits for clients to finish loading before starting anyway.
const READY_TIMEOUT_SECONDS: float = 10.0

## Which of the two rifles a shot event belongs to.
const TOWER_RIFLE: int = 0
const FINISHER_RIFLE: int = 1

@export var controller: MatchController
@export var player: PlayerController
@export var runner_scene: PackedScene
@export var runner_container: Node3D

## Bind the hub lobby instead of a match: one body per seated human, the same
## links and the same snapshots, and none of the match events -- there are no
## rounds to replay. See [method MatchController.start_hub].
@export var hub_mode: bool = false

## Where the session lives. The shipped answer is [constant SESSION_PATH]; a
## test that runs two peers in one process gives each its own branch and names
## the session in it, which is the only reason this is not a constant.
@export var session_path: NodePath = SESSION_PATH

var _session: NetSession = null
var _lobby: NetLobby = null
var _links: Array[PlayerNetLink] = []
var _slot_of_seat: Dictionary[int, int] = {}
var _pending_peers: PackedInt32Array = PackedInt32Array()
var _wait_seconds: float = 0.0
var _started: bool = false
var _fire_was_held: bool = false
var _finisher_fire_was_held: bool = false
## Instance ids of the rifles already subscribed to. A bound Callable is a new
## object every time, so [method Signal.is_connected] cannot answer this.
var _watched_rifles: Dictionary[int, bool] = {}


func _ready() -> void:
	_session = get_tree().root.get_node_or_null(session_path) as NetSession
	if _session == null or not _session.is_established() or controller == null:
		set_physics_process(false)
		return
	_lobby = _session.lobby
	if _lobby == null or (not hub_mode and not _is_bindable_phase(_lobby.get_phase())):
		set_physics_process(false)
		return
	_session.session_ended.connect(_on_session_ended)
	controller.auto_start = false
	if hub_mode:
		# No opening role, no event subscriptions and no ready handshake: a hub
		# decides nothing, so there is nothing for a client to wait for.
		set_physics_process(false)
		_build_bodies()
		controller.start_hub()
		_started = true
		match_bound.emit(_session.is_authority())
		return
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


## Phases a match scene may bind in.
##
## [constant NetLobby.Phase.IN_MATCH] as well as
## [constant NetLobby.Phase.LAUNCHING], and the second one is the fix rather
## than an afterthought. The host starts without a client that has not reported
## after [constant READY_TIMEOUT_SECONDS], and starting moves the phase on --
## so a client that was merely slow to load used to arrive in a match scene
## that refused to bind, with no bodies, no links and no way back. It binds
## now, and [method _client_ready] catches it up.
static func _is_bindable_phase(phase: NetLobby.Phase) -> bool:
	return phase == NetLobby.Phase.LAUNCHING or phase == NetLobby.Phase.IN_MATCH


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

## Rebuild the hub's bodies from the seat table as it stands now.
##
## The hub outlives joins and leaves -- that is what a lobby is for -- and a
## body is built per seat at bind time, so a roster that changed needs the set
## rebuilt rather than patched. It is cheap and it is total: every remote body
## and every link goes, the controller drops its roster, and the hub is armed
## again, which stands everybody back on their spawn. Nothing is lost by that
## because a hub holds no state worth keeping.
func rebuild_hub() -> void:
	if not hub_mode or _lobby == null:
		return
	# Out of the tree BEFORE the free, not merely queued: queue_free defers, and
	# a Link0 still holding the name when the new Link0 is added is renamed to
	# Link0@2 -- which is a node path that resolves on nobody else's machine.
	for link: PlayerNetLink in _links:
		remove_child(link)
		link.queue_free()
	_links.clear()
	_slot_of_seat.clear()
	if runner_container != null:
		for child: Node in runner_container.get_children():
			runner_container.remove_child(child)
			child.queue_free()
	controller.release_roster()
	_build_bodies()
	controller.start_hub()


## The seats bodies are built for: every occupant in a match, and only the
## people in a hub -- a bot has nothing to do in a lobby and is not spawned.
func _seats_to_build() -> Array[LobbySeat]:
	var seats: Array[LobbySeat] = _lobby.get_occupied_seats()
	if not hub_mode:
		return seats
	var humans: Array[LobbySeat] = []
	for seat: LobbySeat in seats:
		if seat.is_human():
			humans.append(seat)
	return humans


func _build_bodies() -> void:
	var bodies: Array[PlayerController] = []
	var kinds: Array[MatchParticipant.Kind] = []
	var names: PackedStringArray = PackedStringArray()
	var local_seat: int = _lobby.get_local_seat_index()
	var local_slot: int = 0
	var seats: Array[LobbySeat] = _seats_to_build()
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
	link.match_controller = controller
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
	controller.participant_shoved.connect(_on_participant_shoved)
	controller.finisher_armed.connect(_on_finisher_armed)
	controller.kill_beat_started.connect(
		func(guard: MatchParticipant, _seconds: float) -> void: rpc(&"_ev_kill_beat", guard.index)
	)
	controller.ghost_respawned.connect(
		func(participant: MatchParticipant) -> void: rpc(&"_ev_ghost_respawned", participant.index)
	)
	controller.ghost_caught.connect(
		func(ghost: MatchParticipant, caught: MatchParticipant) -> void:
			rpc(&"_ev_ghost_caught", ghost.index, caught.index)
	)
	_lobby.seat_occupancy_changed.connect(_on_seat_occupancy_changed)
	_watch_rifle(controller.rifle, TOWER_RIFLE)


## Send one weapon's shots on, [param which] naming the gun so a client replays
## them on the same one. Idempotent: the finisher's rifle is armed every round.
func _watch_rifle(weapon: Rifle, which: int) -> void:
	if weapon == null or _watched_rifles.has(weapon.get_instance_id()):
		return
	_watched_rifles[weapon.get_instance_id()] = true
	weapon.fired.connect(_on_rifle_fired.bind(weapon, which))
	weapon.target_hit.connect(_on_rifle_hit.bind(which))
	weapon.missed.connect(func(end_point: Vector3) -> void: rpc(&"_ev_rifle_missed", which, end_point))


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


## A remote human in the tower or holding the finisher's rifle fires through its
## intent; the server pulls the trigger.
func _drive_remote_trigger() -> void:
	_fire_was_held = _drive_trigger(
		controller.get_seat_participant(), controller.rifle, _fire_was_held
	)
	_finisher_fire_was_held = _drive_trigger(
		controller.get_finisher(), controller.get_finisher_rifle(), _finisher_fire_was_held
	)


## Pull [param weapon]'s trigger from [param who]'s intent packets. Returns
## whether the trigger is still held.
func _drive_trigger(who: MatchParticipant, weapon: Rifle, was_held: bool) -> bool:
	if who == null or weapon == null or not who.is_human() or who == controller.get_human_participant():
		return false
	var link: PlayerNetLink = _links[who.index] if who.index < _links.size() else null
	var source: RemoteIntentSource = link.get_remote_source() if link != null else null
	if source == null:
		return was_held
	var pressed: bool = source.take_fire()
	var held: bool = source.is_fire_held()
	var charged: bool = weapon.profile != null and weapon.profile.charge_enabled
	if charged:
		if pressed:
			weapon.begin_charge()
		elif was_held and not held:
			weapon.release_charge()
	elif pressed or held:
		weapon.try_fire()
	return held


func _on_round_started() -> void:
	var seat: MatchParticipant = controller.get_seat_participant()
	rpc(&"_ev_round_started", seat.index if seat != null else 0, controller.get_round_number())


func _on_match_won(participant: MatchParticipant) -> void:
	rpc(&"_ev_match_won", participant.index)
	var seat: LobbySeat = _lobby.get_occupied_seats()[participant.index] if participant.index < _lobby.get_occupant_count() else null
	_lobby.conclude_match(seat.index if seat != null else -1)


func _on_rifle_fired(origin: Vector3, end_point: Vector3, weapon: Rifle, which: int) -> void:
	rpc(&"_ev_rifle_fired", which, origin, end_point, weapon.reload_seconds)


func _on_rifle_hit(collider: Node3D, at: Vector3, normal: Vector3, which: int) -> void:
	var participant: MatchParticipant = controller.resolve_participant(collider)
	rpc(&"_ev_rifle_hit", which, participant.index if participant != null else -1, at, normal)


## The finisher's rifle exists only once one has been armed, so it is subscribed
## to here rather than at [method _subscribe_server].
func _on_finisher_armed(weapon: Rifle) -> void:
	var who: MatchParticipant = controller.get_finisher()
	_watch_rifle(weapon, FINISHER_RIFLE)
	rpc(&"_ev_finisher_armed", who.index if who != null else -1)


## The victim's launch rides the snapshot; the shover's own kick and clip do not,
## so they are sent to the peer that pushed.
func _on_participant_shoved(shover: MatchParticipant, victim: MatchParticipant) -> void:
	_on_shove_landed(victim)
	var seats: Array[LobbySeat] = _lobby.get_occupied_seats()
	if shover == null or shover.body == null or shover.index >= seats.size():
		return
	var peer: int = seats[shover.index].peer_id
	if peer <= 0 or peer == NetTransport.AUTHORITY_PEER_ID:
		return
	var forward: Vector3 = -shover.body.global_transform.basis.z
	forward.y = 0.0
	rpc_id(peer, &"_ev_shoved", forward.normalized())


## The victim's cue, to everyone: the launch rides the snapshot, the sound does not.
func _on_shove_landed(victim: MatchParticipant) -> void:
	if victim != null and victim.body != null:
		rpc(&"_ev_shove_landed", victim.body.global_position)


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
	var sender_id: int = multiplayer.get_remote_sender_id()
	var index: int = _pending_peers.find(sender_id)
	if index != -1:
		_pending_peers.remove_at(index)
	if _started:
		_catch_up(sender_id)
		return
	if _pending_peers.is_empty():
		_start_now()


## Tell one peer what it missed by binding late.
##
## The match events are one-shots on a reliable channel, which delivers them to
## whoever is listening AT THE TIME -- and a client still loading is not. Two
## messages cover it: the match is running, and this is the round it is on. The
## bodies themselves need nothing, because a snapshot is absolute and the next
## one puts every one of them right.
func _catch_up(peer_id: int) -> void:
	if peer_id <= 0 or peer_id == NetTransport.AUTHORITY_PEER_ID:
		return
	rpc_id(peer_id, &"_ev_match_started")
	var seat: MatchParticipant = controller.get_seat_participant()
	if seat == null:
		# Nobody in the tower yet: the opening race is still running.
		rpc_id(peer_id, &"_ev_race_started")
		return
	rpc_id(peer_id, &"_ev_round_started", seat.index, controller.get_round_number())


## The host went away. There is no migration -- see [ENetTransport] -- so this
## says so and stops, rather than letting a mirror run a match nobody is
## deciding.
func _on_session_ended(_failed: bool) -> void:
	if is_authority():
		return
	set_physics_process(false)
	host_lost.emit()


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
func _ev_rifle_fired(which: int, origin: Vector3, end_point: Vector3, reload: float) -> void:
	var weapon: Rifle = _weapon_of(which)
	if weapon != null:
		weapon.show_remote_shot(origin, end_point, reload)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_rifle_hit(which: int, index: int, at: Vector3, normal: Vector3) -> void:
	var weapon: Rifle = _weapon_of(which)
	if weapon == null:
		return
	var participants: Array[MatchParticipant] = controller.get_participants()
	var participant: MatchParticipant = participants[index] if index >= 0 and index < participants.size() else null
	var body: Node3D = participant.body if participant != null else null
	weapon.show_remote_hit(body, at, normal)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_rifle_missed(which: int, end_point: Vector3) -> void:
	var weapon: Rifle = _weapon_of(which)
	if weapon != null:
		weapon.show_remote_miss(end_point)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_finisher_armed(index: int) -> void:
	if not is_authority():
		controller.net_arm_finisher(index)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_kill_beat(guard_index: int) -> void:
	if not is_authority():
		controller.net_kill_beat(guard_index)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_shove_landed(at: Vector3) -> void:
	if not is_authority() and at.is_finite():
		controller.net_shove_landed(at)


## Which gun an event names, on a client. Null on the authority, which replays
## nothing, and before a finisher has been armed.
func _weapon_of(which: int) -> Rifle:
	if is_authority():
		return null
	return controller.get_finisher_rifle() if which == FINISHER_RIFLE else controller.rifle


@rpc("authority", "reliable", "call_remote", 0)
func _ev_shoved(forward: Vector3) -> void:
	if not is_authority() and forward.is_finite():
		controller.net_shove_felt(forward)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_seat_to_bot(slot: int) -> void:
	if not is_authority():
		controller.net_seat_to_bot(slot)
