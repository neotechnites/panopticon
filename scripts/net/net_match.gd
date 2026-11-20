class_name NetMatch
extends Node

## One body and one link per lobby seat, and the server's match decisions replayed
## on every client. Idle when no established session sits at [constant SESSION_PATH].

## The server started the match, or a client learned that it did.
signal match_bound(authority: bool)

const SESSION_PATH: NodePath = ^"/root/NetSession"
const LINK_SCENE_PATH: String = "res://match/net/player_net_link.tscn"

## Which rifle a shot event belongs to: the tower's is the only one.
const TOWER_RIFLE: int = 0

## The match's transitions, by their index on the wire. Reliable and stamped (see [method _event]);
## Phase 5 turns them into the match record's state.
const _EVENTS: Array[StringName] = [
	&"_ev_match_started", &"_ev_race_started", &"_ev_round_started", &"_ev_removed", &"_ev_ghost_fell",
	&"_ev_round_resolved", &"_ev_match_won", &"_ev_ghost_respawned", &"_ev_ghost_caught",
	&"_ev_finisher_armed", &"_ev_kill_beat", &"_ev_brawl_started", &"_ev_brawl_out",
]

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
## Seat index -> slot, and its inverse. The match layer counts participants in
## dense slots; the wire and the lobby name seats. Every crossing goes through
## these two and nowhere else -- deriving a seat from a slot by position in
## get_occupied_seats() is wrong the moment a seat is emptied mid-match.
var _slot_of_seat: Dictionary[int, int] = {}
var _seat_of_slot: PackedInt32Array = PackedInt32Array()
var _started: bool = false
## Instance ids of the rifles already subscribed to. A bound Callable is a new
## object every time, so [method Signal.is_connected] cannot answer this.
var _watched_rifles: Dictionary[int, bool] = {}
var _bound: bool = false
## Over the scene until the world has drawn and frame times settle; null once lifted.
var _cover: LoadingCover = null
## The lobby epoch this scene was loaded for.
var _epoch: int = 0
## Reused by [method get_scene_peers].
var _scene_peers: PackedInt32Array = PackedInt32Array()
## Client: the tick of the match record this mirror converged on, -1 before; and the stamped
## transitions that arrived before it, to be taken or dropped against it.
var _converged_tick: int = -1
var _early: Array[Array] = []
## Client: true only while [method _converge] replays the first record's transitions.
var _converging: bool = false
## Authority: the rules last published from this scene, so a widget that edited none sends none.
var _rules_said: PackedByteArray = PackedByteArray()
## Every prop registered in this scene, as [id, prop], kept while a gate holds it out of the tree.
var _registered: Array[Array] = []
## True once this scene's props are handed to the replicator: a later registration is handed on too.
var _props_bound: bool = false


func _ready() -> void:
	_session = get_tree().root.get_node_or_null(session_path) as NetSession
	if _session == null or not _session.is_established() or controller == null or _session.lobby == null:
		set_physics_process(false)
		return
	_lobby = _session.lobby
	_epoch = _session.flow.epoch_for(hub_mode)
	if _epoch == 0:
		set_physics_process(false)
		return
	_lobby.roster_changed.connect(_on_roster_changed)
	if not _session.is_authority():
		_session.replicator.event_received.connect(_on_event)
		_session.replicator.match_record_received.connect(_on_match_record)
	controller.auto_start = false
	_bound = true
	# Nothing of this scene is drawn until this machine's body has been placed in it.
	_cover = LoadingCover.new()
	add_child(_cover)
	_show_world(false)
	if hub_mode:
		# No opening role, no event subscriptions and no start to wait for: a hub decides nothing.
		set_physics_process(false)
		_build_bodies()
		if _session.is_authority():
			# A shove's flop is drawn off this cue; without it a client never sees a hub shove land.
			controller.participant_shoved.connect(_on_participant_shoved)
		controller.start_hub()
		_started = true
		_bind_props()
		_on_started()
		_session.flow.scene_bound(_epoch, get_parent())
		return
	# The controller installs the chosen map on the scene's ready, after this node's.
	if controller.is_armed():
		_bind_match()
	else:
		controller.armed.connect(_bind_match, CONNECT_ONE_SHOT)


## Bodies and the opening on a map that stands; the host starts once everyone stands in it.
func _bind_match() -> void:
	_build_bodies()
	_apply_opening()
	_bind_props()
	if _session.is_authority():
		_subscribe_server()
		_session.replicator.match_source = func() -> PackedByteArray: return NetCodec.pack_match(controller, _started)
	else:
		_lobby.rules_changed.connect(_on_rules_changed)
	_on_roster_changed()
	_session.flow.scene_bound(_epoch, get_parent())


## The NetMatch of the scene [param node] stands in: the nearest ancestor with one as a child, or null.
static func of_scene(node: Node) -> NetMatch:
	var at: Node = node.get_parent()
	while at != null:
		for child: Node in at.get_children():
			if child is NetMatch:
				return child as NetMatch
		at = at.get_parent()
	return null


## Take [param prop] as this scene's, named by its path from the scene root (DESIGN 2 prop ids).
func register_prop(prop: Node) -> void:
	_registered.append([NetProp.id_of(get_parent().get_path_to(prop)), prop])
	if _props_bound:
		_bind_props()


## Hand the replicator the scene's props by id. A prop on its way out is no longer the scene's, and
## two that share an id leave the scene none.
func _bind_props() -> void:
	_props_bound = true
	var kept: Array[Array] = []
	var by_id: Dictionary[int, Node] = {}
	var clash: String = ""
	for entry: Array in _registered:
		var prop: Node = entry[1]
		if not is_instance_valid(prop) or _is_leaving(prop):
			continue
		kept.append(entry)
		if by_id.has(entry[0]) and clash.is_empty():
			clash = "%s and %s" % [by_id[entry[0]].name, prop.name]
		by_id[entry[0]] = prop
	_registered = kept
	if not clash.is_empty():
		push_error("NetMatch: props %s share an id; this scene's props are not replicated." % clash)
		by_id.clear()
	_session.replicator.bind_props(by_id)


## True when [param node] or a node above it is queued to be freed.
static func _is_leaving(node: Node) -> bool:
	while node != null:
		if node.is_queued_for_deletion():
			return true
		node = node.get_parent()
	return false


func _exit_tree() -> void:
	if not _bound:
		return
	# A scene on its way out answers for nothing.
	_lobby.roster_changed.disconnect(_on_roster_changed)
	if _session.replicator.event_received.is_connected(_on_event):
		_session.replicator.event_received.disconnect(_on_event)
		_session.replicator.match_record_received.disconnect(_on_match_record)
	_session.replicator.match_source = Callable()
	_props_bound = false
	_session.replicator.bind_props({})
	if _lobby.rules_changed.is_connected(_on_rules_changed):
		_lobby.rules_changed.disconnect(_on_rules_changed)
	_session.replicator.bind_scene(0)
	_show_world(true)


## The roster moved: the replicator speaks for this scene only while the lobby names it, bodies follow
## their seats, and the host starts once everyone stands.
func _on_roster_changed() -> void:
	_bind_replicator()
	_reconcile_hub()
	_reconcile_seats()
	_start_if_ready()


## Stamp and accept this scene's epoch while the lobby names it: a client's at once, the host's once it
## has placed bodies.
func _bind_replicator() -> void:
	var speaks: bool = _is_current() and (_started or not _session.is_authority())
	_session.replicator.bind_scene(_epoch if speaks else 0)


## True while the lobby names this scene: its epoch is the one this scene was loaded for.
func _is_current() -> bool:
	return _lobby.get_epoch() == _epoch


## The bodies are placed: what the host sends from now on is this scene's, and its world is drawn.
func _on_started() -> void:
	_bind_replicator()
	if _session.is_authority():
		_show_world(true)
	match_bound.emit(_session.is_authority())


## Draw the 3D world or not. A client's world comes on with its own body's first placement.
func _show_world(shown: bool) -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.disable_3d = not shown
	if shown and is_instance_valid(_cover):
		_cover.release()


func _on_local_placed() -> void:
	_show_world(true)


func is_active() -> bool:
	return _lobby != null


func is_authority() -> bool:
	return _session != null and _session.is_authority()


func has_started() -> bool:
	return _started


## True while a transition is replayed from the match record this client converges on, not sent to it.
func is_converging() -> bool:
	return _converging


## The lobby epoch this scene was loaded for, or 0 when it is bound to none.
func get_epoch() -> int:
	return _epoch


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

## The hub's bodies follow the seats one by one (DESIGN 4.5): a seat that gained a person is built, one
## that lost theirs is freed, and nobody else is touched. Only while the lobby names this hub.
func _reconcile_hub() -> void:
	if not hub_mode or not _started or not _is_current():
		return
	var seats: Array[LobbySeat] = _seats_to_build()
	var wanted: Dictionary[int, int] = {}
	for seat: LobbySeat in seats:
		wanted[seat.index] = seat.peer_id
	var changed: bool = false
	for link: PlayerNetLink in _links.duplicate():
		if wanted.get(link.seat_index, -1) != link.owner_peer_id and link.controller != player:
			_unseat(link)
			changed = true
	for slot: int in seats.size():
		if _link_for_seat(seats[slot].index) == null:
			_seat(seats[slot], slot)
			changed = true
	if changed:
		_index_slots()


## Build [param seat]'s body and link and seat it in the standing hub at [param slot].
func _seat(seat: LobbySeat, slot: int) -> void:
	var body: PlayerController = runner_scene.instantiate() as PlayerController
	body.name = "Seat%d" % seat.index
	runner_container.add_child(body)
	_add_link(seat, body, false)
	controller.hub_seat(body, seat_name(seat), slot)


## Take [param link]'s body out of the hub and free both. Out of the tree before the free: a queued
## Link0 still holding the name would rename the next Link0, a path nobody else's machine has.
func _unseat(link: PlayerNetLink) -> void:
	var body: PlayerController = link.controller
	controller.hub_unseat(body)
	_links.erase(link)
	remove_child(link)
	link.queue_free()
	if body != null:
		body.get_parent().remove_child(body)
		body.queue_free()


## Seat to slot and back from the controller's roster, after a seat was built or freed.
func _index_slots() -> void:
	_slot_of_seat.clear()
	var participants: Array[MatchParticipant] = controller.get_participants_ref()
	_seat_of_slot.resize(participants.size())
	for slot: int in participants.size():
		var link: PlayerNetLink = PlayerNetLink.of(participants[slot].body)
		_seat_of_slot[slot] = link.seat_index if link != null else -1
		if link != null:
			_slot_of_seat[link.seat_index] = slot


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
	_seat_of_slot.resize(seats.size())
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
		names.append(seat_name(seat))
		_slot_of_seat[seat.index] = slot
		_seat_of_slot[slot] = seat.index
		_add_link(seat, body, seat.index == local_seat)
	controller.configure_net(bodies, kinds, names, local_slot, not _session.is_authority())


## The name a seat's player goes by in a match, on every screen.
static func seat_name(seat: LobbySeat) -> String:
	return seat.display_name if not seat.display_name.is_empty() else "Player %d" % (seat.index + 1)


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
	if is_local and not _session.is_authority():
		link.placed.connect(_on_local_placed)
	add_child(link)
	_links.append(link)


## The seat a participant slot was built from, or -1 for a slot this match has
## no body for.
func _seat_index_of(slot: int) -> int:
	if slot < 0 or slot >= _seat_of_slot.size():
		return -1
	return _seat_of_slot[slot]


## The link driving a participant slot's body, or null.
func _link_of_slot(slot: int) -> PlayerNetLink:
	return _link_for_seat(_seat_index_of(slot))


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
	controller.match_started.connect(func(_count: int) -> void: _event(&"_ev_match_started"))
	controller.race_started.connect(func() -> void: _event(&"_ev_race_started"))
	controller.brawl_started.connect(func() -> void: _event(&"_ev_brawl_started"))
	controller.brawler_out.connect(
		func(participant: MatchParticipant, throw: Vector3) -> void:
			_event(&"_ev_brawl_out", [participant.index, throw])
	)
	controller.round_started.connect(_on_round_started)
	controller.participant_converted.connect(
		func(participant: MatchParticipant) -> void:
			_event(&"_ev_removed", [participant.index, int(participant.death_cause), _is_held(participant)])
	)
	controller.ghost_fell.connect(
		func(participant: MatchParticipant) -> void:
			_event(&"_ev_ghost_fell", [participant.index, int(participant.death_cause)])
	)
	controller.round_resolved.connect(
		func(outcome: MatchController.Outcome) -> void: _event(&"_ev_round_resolved", [int(outcome)])
	)
	controller.match_won.connect(_on_match_won)
	controller.participant_shoved.connect(_on_participant_shoved)
	controller.finisher_armed.connect(_on_finisher_armed)
	controller.kill_beat_started.connect(
		func(guard: MatchParticipant, _seconds: float, throw: Vector3) -> void:
			_event(&"_ev_kill_beat", [guard.index, throw])
	)
	controller.ghost_respawned.connect(
		func(participant: MatchParticipant) -> void: _event(&"_ev_ghost_respawned", [participant.index])
	)
	controller.ghost_caught.connect(
		func(ghost: MatchParticipant, caught: MatchParticipant) -> void:
			_event(&"_ev_ghost_caught", [ghost.index, caught.index, _is_held(caught)])
	)
	controller.rules_edited.connect(_publish_rules)
	_watch_rifle(controller.rifle, TOWER_RIFLE)


## The rules are replicated state: the host's edit goes out on the lobby's line, where a peer
## still loading finds it too.
func _publish_rules() -> void:
	var packed: PackedByteArray = NetCodec.pack_rules(controller.get_rules())
	if packed != _rules_said:
		_rules_said = packed
		_lobby.set_rules(controller.get_rules())


## A mirror runs by the host's rules as they stand now, not as they stood at the launch.
func _on_rules_changed() -> void:
	NetCodec.copy_rules(_lobby.get_rules(), controller.get_rules())
	controller.refresh_rules()


## Whether the server still holds a body it has just made a ghost. With no respawn delay it is
## back up inside its own making, and that respawn was announced before the making was.
func _is_held(participant: MatchParticipant) -> bool:
	return participant.respawn_hold_remaining > 0.0


## Send one weapon's shots on, [param which] naming the gun so a client replays
## them on the same one. Idempotent.
func _watch_rifle(weapon: Rifle, which: int) -> void:
	if weapon == null or _watched_rifles.has(weapon.get_instance_id()):
		return
	_watched_rifles[weapon.get_instance_id()] = true
	weapon.lag_back = _session.replicator.rewind_ticks
	weapon.lag_trace = _session.replicator.trace
	weapon.fired.connect(_on_rifle_fired.bind(weapon, which))
	weapon.target_hit.connect(_on_rifle_hit.bind(which))
	weapon.missed.connect(
		func(end_point: Vector3) -> void:
			_session.replicator.send_event(NetEvents.Type.MISS, NetCodec.pack_point(which, end_point))
	)


## Authority: start once this machine and every human stand in the scene, or the launch wait after
## the bump is spent; [member NetSettings.drop_unlaunched_peers] says whether the late are let go then.
func _start_if_ready() -> void:
	if _started or hub_mode or _links.is_empty() or not _session.is_authority() or not _is_current():
		return
	if _lobby.get_local_seat().standing_epoch != _epoch:
		return
	var late: PackedInt32Array = _lobby.get_unstanding_peers()
	var waited: bool = _session.get_epoch_age_ms() >= int(_session.get_settings().launch_timeout_seconds * 1000.0)
	if not late.is_empty() and not waited:
		return
	_started = true
	controller.start_match()
	_reconcile_seats()
	_on_started()
	if late.is_empty():
		return
	push_warning("NetMatch: %d client(s) not standing at the launch wait; starting without them." % late.size())
	if _session.get_settings().drop_unlaunched_peers:
		for peer: int in late:
			_session.kick_peer(peer)


func _physics_process(_delta: float) -> void:
	if not is_authority() or _started:
		return
	# Acknowledgements start it through the roster; this is only the launch wait running out.
	if _session.get_epoch_age_ms() >= int(_session.get_settings().launch_timeout_seconds * 1000.0):
		_start_if_ready()


func _on_round_started() -> void:
	var seat: MatchParticipant = controller.get_seat_participant()
	_event(&"_ev_round_started", [
		seat.index if seat != null else 0, controller.get_round_number(), seat.rounds_won if seat != null else 0,
	])


func _on_match_won(participant: MatchParticipant) -> void:
	_event(&"_ev_match_won", [participant.index, participant.rounds_won])
	_lobby.conclude_match(_seat_index_of(participant.index))


## A shot, to everyone but a client that fired it: that one drew its own when it predicted it.
func _on_rifle_fired(origin: Vector3, end_point: Vector3, weapon: Rifle, which: int) -> void:
	var gravity: float = weapon.profile.projectile_gravity if weapon.profile != null else -1.0
	var shooter: PlayerNetLink = PlayerNetLink.of(weapon.shooter_body)
	var peer: int = shooter.owner_peer_id if shooter != null and not shooter.is_owned_here() else 0
	_session.replicator.send_event(
		NetEvents.Type.SHOT,
		NetCodec.pack_shot(which, origin, end_point, weapon.reload_seconds, weapon.get_last_launch_speed(), gravity),
		NetEvents.Target.ALL_BUT if peer != 0 else NetEvents.Target.ALL, peer,
	)


func _on_rifle_hit(collider: Node3D, at: Vector3, normal: Vector3, which: int) -> void:
	var participant: MatchParticipant = controller.resolve_participant(collider)
	var seat: int = _seat_index_of(participant.index) if participant != null else -1
	_session.replicator.send_event(NetEvents.Type.HIT, NetCodec.pack_hit(which, seat, at, normal))


## One match transition, reliable, stamped with the first tick whose world includes it: a mirror takes
## only those its first world does not (Quake 3's gamestate and serverCommandSequence).
func _event(method: StringName, args: Array = []) -> void:
	var stamp: int = (_session.replicator.get_tick() + 1) % NetCodec.TICK_MODULUS
	var index: int = _EVENTS.find(method)
	if index < 0:
		push_error("NetMatch: %s is not a match transition." % method)
		return
	for peer: int in _session.get_peer_ids():
		if peer != NetTransport.AUTHORITY_PEER_ID and _lobby.is_standing_in(peer, _epoch):
			rpc_id(peer, &"_ev", stamp, index, args)


@rpc("authority", "reliable", "call_remote", 0)
func _ev(stamp: int, index: int, args: Array) -> void:
	if not _replays() or index < 0 or index >= _EVENTS.size():
		return
	if _converged_tick < 0:
		_early.append([stamp, index, args])
	elif NetCodec.is_newer_tick(stamp, _converged_tick):
		callv(_EVENTS[index], args)


## A client's match record: the scene's first one is converged on, and every transition stamped
## after it is then taken in order. Later records are Phase 5's.
func _on_match_record(record: PackedByteArray, tick: int, first: bool) -> void:
	if not first or hub_mode:
		return
	if not record.is_empty():
		_converging = true
		_converge(record)
		_converging = false
	_converged_tick = tick
	for early: Array in _early:
		if NetCodec.is_newer_tick(int(early[0]), tick):
			callv(_EVENTS[int(early[1])], early[2])
	_early.clear()


## A presented event of the snapshot's ring: shots, hits, misses, shoves and hub cat blasts.
func _on_event(type: NetEvents.Type, payload: PackedByteArray, _tick: int) -> void:
	match type:
		NetEvents.Type.SHOT:
			var weapon: Rifle = _weapon_of(payload[0])
			if weapon != null:
				weapon.show_remote_shot(
					NetCodec.event_point(payload, 1), NetCodec.event_point(payload, 13),
					payload.decode_float(25), payload.decode_float(29), payload.decode_float(33),
				)
		NetEvents.Type.HIT:
			var weapon: Rifle = _weapon_of(payload[0])
			var link: PlayerNetLink = _link_for_seat(payload[1])
			if weapon != null:
				weapon.show_remote_hit(
					link.controller if link != null else null, NetCodec.event_point(payload, 2),
					NetCodec.event_unit(payload, 14),
				)
		NetEvents.Type.MISS:
			var weapon: Rifle = _weapon_of(payload[0])
			if weapon != null:
				weapon.show_remote_miss(NetCodec.event_point(payload, 1))
		NetEvents.Type.SHOVE_LANDED:
			controller.net_shove_landed(_slot_of_seat.get(payload[0], -1), NetCodec.event_point(payload, 1))
		NetEvents.Type.SHOVE_KICK:
			controller.net_shove_felt(NetCodec.event_unit(payload, 0))
		NetEvents.Type.CAT_BLAST:
			CatView.play_blast(get_parent(), NetCodec.event_point(payload, 1))


## The other machines whose copy of this scene stands; who a prop in it may send to.
func get_scene_peers() -> PackedInt32Array:
	_scene_peers.clear()
	if not _bound or not _session.is_authority():
		return _scene_peers
	for peer: int in _session.get_peer_ids():
		if peer != NetTransport.AUTHORITY_PEER_ID and _lobby.is_standing_in(peer, _epoch):
			_scene_peers.append(peer)
	return _scene_peers


## The finisher is in the tower; every peer is told who, for the role.
func _on_finisher_armed(_weapon: Rifle) -> void:
	var who: MatchParticipant = controller.get_finisher()
	_event(&"_ev_finisher_armed", [who.index if who != null else -1])


## The victim's launch rides the snapshot; the shover's own kick and clip do not,
## so they are sent to the peer that pushed.
func _on_participant_shoved(shover: MatchParticipant, victim: MatchParticipant) -> void:
	_on_shove_landed(victim)
	if shover == null or shover.body == null:
		return
	var seat: LobbySeat = _lobby.get_seat(_seat_index_of(shover.index))
	if seat == null:
		return
	var peer: int = seat.peer_id
	if peer <= 0 or peer == NetTransport.AUTHORITY_PEER_ID:
		return
	var forward: Vector3 = -shover.body.global_transform.basis.z
	forward.y = 0.0
	_session.replicator.send_event(NetEvents.Type.SHOVE_KICK, NetCodec.pack_kick(forward), NetEvents.Target.ONE, peer)


## The victim's cue, to everyone: the launch rides the snapshot, the sound does not.
func _on_shove_landed(victim: MatchParticipant) -> void:
	if victim != null and victim.body != null:
		_session.replicator.send_event(
			NetEvents.Type.SHOVE_LANDED, NetCodec.pack_point(_seat_index_of(victim.index), victim.body.global_position)
		)


## Every body follows its seat as the roster has it: a seat whose human left is a bot's, its link
## driven by the bot on the host and its participant briefed. Idempotent; mirrors read the same roster.
func _reconcile_seats() -> void:
	for seat_index: int in _slot_of_seat:
		var seat: LobbySeat = _lobby.get_seat(seat_index)
		if seat == null or not seat.is_bot():
			continue
		var link: PlayerNetLink = _link_for_seat(seat_index)
		if _session.is_authority() and link != null and link.owner_peer_id != 0:
			link.owner_peer_id = 0
			link.local_source = link.controller.get_node_or_null(^"BotInput") as IntentSource
			link.refresh_role()
		controller.net_seat_to_bot(_slot_of_seat[seat_index])


# --- Wire ---------------------------------------------------------------------

## True when this machine replays the server's decisions rather than making
## them. Every [code]_ev_[/code] handler below opens with it, in one spelling, so
## the guard is read once rather than re-derived per message.
func _replays() -> bool:
	return not is_authority()


func _ev_match_started() -> void:
	if not _replays():
		return
	controller.net_start_match()
	_reconcile_seats()
	if not _started:
		_started = true
		match_bound.emit(false)


## Converge a freshly bound match on the host's record through the same transitions the events run.
func _converge(record: PackedByteArray) -> void:
	_ev_match_started()
	if not NetCodec.is_match_record(record, controller.get_participants().size()):
		return
	var phase: MatchController.Phase = record[0] as MatchController.Phase
	var seat: int = NetCodec.match_slot(record, 2)
	if phase == MatchController.Phase.RACE:
		controller.net_start_race()
	elif phase == MatchController.Phase.BRAWL:
		controller.net_start_brawl()
	elif seat >= 0:
		controller.net_start_round(seat, record[1])
	if NetCodec.match_slot(record, 3) >= 0:
		controller.net_arm_finisher(NetCodec.match_slot(record, 3))
	var participants: Array[MatchParticipant] = controller.get_participants()
	for i: int in participants.size():
		var flags: int = record[NetCodec.MATCH_HEADER_SIZE + i * NetCodec.MATCH_PARTICIPANT_SIZE]
		if flags & (NetCodec.MATCH_RUNNING | NetCodec.MATCH_SHOOTER) == 0 and participants[i].is_running:
			_ev_removed(i, int(MatchParticipant.DeathCause.SHOT), true)
		if flags & NetCodec.MATCH_GHOST != 0 and flags & NetCodec.MATCH_HELD == 0:
			# Its respawn landed before this machine was listening.
			controller.net_ghost_respawn(i)
	for i: int in participants.size():
		var at: int = NetCodec.MATCH_HEADER_SIZE + i * NetCodec.MATCH_PARTICIPANT_SIZE
		participants[i].rounds_won = record[at + 1]
		participants[i].turns_in_tower = record[at + 2]
	if record[4] != int(MatchController.Outcome.IN_PROGRESS):
		controller.net_resolve(record[4] as MatchController.Outcome)
	if phase == MatchController.Phase.MATCH_OVER and NetCodec.match_slot(record, 5) >= 0:
		controller.net_win(NetCodec.match_slot(record, 5))


func _ev_race_started() -> void:
	if not _replays():
		return
	controller.net_start_race()


func _ev_round_started(seat_index: int, round_number: int, rounds_won: int) -> void:
	if not _replays():
		return
	_take_rounds_won(seat_index, rounds_won)
	controller.net_start_round(seat_index, round_number)


## The rounds [param index] has held the tower through, as the server counts them: only it
## awards one, so the count rides the event that follows the award.
func _take_rounds_won(index: int, rounds_won: int) -> void:
	var participants: Array[MatchParticipant] = controller.get_participants()
	if index >= 0 and index < participants.size():
		participants[index].rounds_won = maxi(rounds_won, 0)


func _ev_removed(index: int, cause: int, held: bool) -> void:
	if not _replays():
		return
	match controller.get_phase():
		MatchController.Phase.RACE:
			controller.net_race_out(index)
		MatchController.Phase.BRAWL:
			# Only a late peer's catch-up comes this way: it was out before this machine could see the throw.
			controller.net_brawl_out(index, Vector3.ZERO)
		_:
			controller.net_convert(index, _cause_of(cause))
			_made_ghost(index, held)


## A mirror has just made [param index] a ghost: one the server no longer holds has already
## respawned there, and must not wait here for a respawn that will not be said again.
func _made_ghost(index: int, held: bool) -> void:
	if not held:
		controller.net_ghost_respawn(index)


func _ev_ghost_fell(index: int, cause: int) -> void:
	if not _replays():
		return
	controller.net_ghost_fall(index, _cause_of(cause))


## A death cause off the wire, or SHOT for a number this build has no cause for.
func _cause_of(cause: int) -> MatchParticipant.DeathCause:
	if cause < 0 or cause >= MatchParticipant.DeathCause.size():
		return MatchParticipant.DeathCause.SHOT
	return cause as MatchParticipant.DeathCause


func _ev_round_resolved(outcome: int) -> void:
	if not _replays():
		return
	controller.net_resolve(outcome as MatchController.Outcome)


func _ev_match_won(index: int, rounds_won: int) -> void:
	if not _replays():
		return
	_take_rounds_won(index, rounds_won)
	controller.net_win(index)


func _ev_ghost_respawned(index: int) -> void:
	if not _replays():
		return
	controller.net_ghost_respawn(index)


func _ev_ghost_caught(ghost_index: int, caught_index: int, held: bool) -> void:
	if not _replays():
		return
	controller.net_ghost_caught(ghost_index, caught_index)
	_made_ghost(caught_index, held)


func _ev_finisher_armed(index: int) -> void:
	if not _replays():
		return
	controller.net_arm_finisher(index)


func _ev_kill_beat(guard_index: int, throw: Vector3) -> void:
	if not _replays() or not throw.is_finite():
		return
	controller.net_kill_beat(guard_index, throw)


func _ev_brawl_started() -> void:
	if _replays():
		controller.net_start_brawl()


func _ev_brawl_out(index: int, throw: Vector3) -> void:
	if _replays() and throw.is_finite():
		controller.net_brawl_out(index, throw)


## Which gun an event names, or null for one this build has not got. Callers have
## already refused the authority; see [method _replays].
func _weapon_of(which: int) -> Rifle:
	return controller.rifle if which == TOWER_RIFLE else null
