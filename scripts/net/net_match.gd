class_name NetMatch
extends Node

## One body and one link per lobby seat, and the host's match record converged on by every client.
## Idle when no established session sits at [constant SESSION_PATH].

## The server started the match, or a client learned that it did.
signal match_bound(authority: bool)

## Every NetMatch in the tree: how a scene prop finds the one on its own machine.
const GROUP: StringName = &"net_match"

const SESSION_PATH: NodePath = ^"/root/NetSession"
const LINK_SCENE_PATH: String = "res://match/net/player_net_link.tscn"

## Which rifle a shot event belongs to: the tower's is the only one.
const TOWER_RIFLE: int = 0

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
## Host: the match's lasting state, sampled for each snapshot. Client: the newest record on arrival,
## and the mirror converging on the records as they fall due.
var _state: MatchState = MatchState.new()
var _arrived: MatchState = MatchState.new()
var _mirror: MatchMirror = null
## Authority: the rules last published from this scene, so a widget that edited none sends none.
var _rules_said: PackedByteArray = PackedByteArray()


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
	add_to_group(GROUP)
	_lobby.roster_changed.connect(_on_roster_changed)
	if not _session.is_authority():
		_session.replicator.event_received.connect(_on_event)
		_session.replicator.match_arrived.connect(_on_match_arrived)
		_session.replicator.match_due.connect(_on_match_due)
		_mirror = MatchMirror.new(controller)
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
		_session.replicator.bind_props(_scene_props())
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
	_session.replicator.bind_props(_scene_props())
	if _session.is_authority():
		_subscribe_server()
		_session.replicator.match_source = _sample_match
	else:
		_lobby.rules_changed.connect(_on_rules_changed)
	_on_roster_changed()
	_session.flow.scene_bound(_epoch, get_parent())


## The scene's props: what the snapshot carries besides bodies (DESIGN 3.4 PROPS).
func _scene_props() -> Array[Node]:
	var props: Array[Node] = []
	var root: Node = get_parent()
	for prop: Node in get_tree().get_nodes_in_group(NetProp.GROUP):
		if root.is_ancestor_of(prop):
			props.append(prop)
	return props


func _exit_tree() -> void:
	if not _bound:
		return
	# A scene on its way out answers for nothing.
	_lobby.roster_changed.disconnect(_on_roster_changed)
	if _session.replicator.event_received.is_connected(_on_event):
		_session.replicator.event_received.disconnect(_on_event)
		_session.replicator.match_arrived.disconnect(_on_match_arrived)
		_session.replicator.match_due.disconnect(_on_match_due)
	_session.replicator.match_source = Callable()
	_session.replicator.bind_props([])
	if _lobby.rules_changed.is_connected(_on_rules_changed):
		_lobby.rules_changed.disconnect(_on_rules_changed)
	_session.replicator.bind_scene(0)
	_show_world(true)


## The roster moved: the replicator speaks for this scene only while the lobby names it, bodies follow
## their seats, and the host starts once everyone stands.
func _on_roster_changed() -> void:
	_bind_replicator()
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


## True while a transition is replayed from the first match record this client converges on, not sent to it.
func is_converging() -> bool:
	return _mirror != null and _mirror.is_converging()


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

## Rebuild the hub's bodies when the seat-to-peer map changed; a seat still held keeps its place.
## Interim until Phase 6's per-seat reconcile.
func rebuild_hub() -> void:
	if not hub_mode or _lobby == null:
		return
	var wanted: Dictionary[int, int] = {}
	for seat: LobbySeat in _seats_to_build():
		wanted[seat.index] = seat.peer_id
	var built: Dictionary[int, int] = {}
	for link: PlayerNetLink in _links:
		built[link.seat_index] = link.owner_peer_id
	if wanted == built:
		# A ready mark or a machine standing changes the roster, not who is in the hub.
		return
	var places: Dictionary[int, Transform3D] = {}
	var holders: Dictionary[int, int] = {}
	for link: PlayerNetLink in _links:
		if link.controller != null and link.controller.is_inside_tree():
			places[link.seat_index] = link.controller.global_transform
			holders[link.seat_index] = link.owner_peer_id
	# Out of the tree BEFORE the free, not merely queued: queue_free defers, and
	# a Link0 still holding the name when the new Link0 is added is renamed to
	# Link0@2 -- which is a node path that resolves on nobody else's machine.
	for link: PlayerNetLink in _links:
		remove_child(link)
		link.queue_free()
	_links.clear()
	_slot_of_seat.clear()
	_seat_of_slot.clear()
	if runner_container != null:
		for child: Node in runner_container.get_children():
			runner_container.remove_child(child)
			child.queue_free()
	controller.release_roster()
	_build_bodies()
	controller.start_hub()
	for link: PlayerNetLink in _links:
		if holders.get(link.seat_index, -1) == link.owner_peer_id:
			var place: Transform3D = places[link.seat_index]
			link.controller.place(place.origin, place.basis.get_euler().y)


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
	controller.brawler_out.connect(
		func(participant: MatchParticipant, throw: Vector3) -> void:
			if throw != Vector3.ZERO:
				_session.replicator.send_event(
					NetEvents.Type.BRAWL_THROW, NetCodec.pack_throw(_seat_index_of(participant.index), throw)
				)
	)
	controller.participant_shot_dead.connect(
		func(participant: MatchParticipant, at: Vector3, direction: Vector3) -> void:
			_session.replicator.send_event(
				NetEvents.Type.DEATH, NetCodec.pack_death(_seat_index_of(participant.index), at, direction)
			)
	)
	controller.match_won.connect(_on_match_won)
	controller.participant_shoved.connect(_on_participant_shoved)
	controller.rules_edited.connect(_publish_rules)
	_watch_rifle(controller.rifle, TOWER_RIFLE)


## Host: the match record of this tick, for the snapshot's MATCH section.
func _sample_match() -> PackedByteArray:
	controller.capture_state(_state, _session.replicator.get_tick(), _started)
	return NetCodec.pack_match_state(_state)


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


func _on_match_won(participant: MatchParticipant) -> void:
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


## Client: the newest record, on arrival. Only its collision is taken now, because this machine's own
## body collides with it; the rest waits for the playout clock (DESIGN 5).
func _on_match_arrived(record: PackedByteArray) -> void:
	if not hub_mode and NetCodec.unpack_match_state(record, 0, _arrived):
		controller.apply_structure(_arrived.phase as MatchController.Phase)


## Client: a record the playout clock has reached, converged on in order.
func _on_match_due(record: PackedByteArray, tick: int, first: bool) -> void:
	if hub_mode or not NetCodec.unpack_match_state(record, tick, _state):
		return
	if _mirror.converge(_state, first):
		_reconcile_seats()
		if not _started:
			_started = true
			match_bound.emit(false)


## A presented event of the snapshot's ring: shots, hits, misses, shoves, cat blasts, and the initial
## conditions of the deaths and throws the match record will show.
func _on_event(type: NetEvents.Type, payload: PackedByteArray, tick: int) -> void:
	match type:
		NetEvents.Type.DEATH:
			_mirror.note_death(
				_slot_of_seat.get(payload[0], -1), tick, NetCodec.event_point(payload, 1), NetCodec.event_unit(payload, 13)
			)
		NetEvents.Type.BRAWL_THROW:
			_mirror.note_throw(_slot_of_seat.get(payload[0], -1), tick, NetCodec.event_throw(payload, 1))
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


## The NetMatch on [param node]'s machine, or null: off a session there is none bound.
static func of(node: Node) -> NetMatch:
	if node == null or not node.is_inside_tree():
		return null
	for found: Node in node.get_tree().get_nodes_in_group(GROUP):
		if found.multiplayer == node.multiplayer:
			return found as NetMatch
	return null


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

## Which gun an event names, or null for one this build has not got.
func _weapon_of(which: int) -> Rifle:
	return controller.rifle if which == TOWER_RIFLE else null
