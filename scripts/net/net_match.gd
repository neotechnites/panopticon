class_name NetMatch
extends Node

## One body and one link per lobby seat, and the server's match decisions replayed
## on every client. Idle when no established session sits at [constant SESSION_PATH].

## The server started the match, or a client learned that it did.
signal match_bound(authority: bool)

## Authority: [param peer_id]'s copy of this scene now stands; what it missed can be sent.
signal peer_bound(peer_id: int)

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
## Reused by [method get_scene_peers], which a carried cat asks every tick.
var _scene_peers: PackedInt32Array = PackedInt32Array()
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
	_lobby.peer_standing.connect(_on_peer_standing)
	_lobby.roster_changed.connect(_on_roster_changed)
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
	if _session.is_authority():
		_subscribe_server()
	else:
		_lobby.rules_changed.connect(_on_rules_changed)
	_on_roster_changed()
	_session.flow.scene_bound(_epoch, get_parent())


func _exit_tree() -> void:
	if not _bound:
		return
	# A scene on its way out answers for nothing: a late binder is the next scene's to greet.
	_lobby.peer_standing.disconnect(_on_peer_standing)
	_lobby.roster_changed.disconnect(_on_roster_changed)
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
			link.controller.global_transform = places[link.seat_index]


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
	weapon.missed.connect(func(end_point: Vector3) -> void: _event(&"_ev_rifle_missed", [which, end_point]))


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


func _on_rifle_fired(origin: Vector3, end_point: Vector3, weapon: Rifle, which: int) -> void:
	var gravity: float = weapon.profile.projectile_gravity if weapon.profile != null else -1.0
	_event(&"_ev_rifle_fired", [which, origin, end_point, weapon.reload_seconds, weapon.get_last_launch_speed(), gravity])


func _on_rifle_hit(collider: Node3D, at: Vector3, normal: Vector3, which: int) -> void:
	var participant: MatchParticipant = controller.resolve_participant(collider)
	_event(&"_ev_rifle_hit", [which, participant.index if participant != null else -1, at, normal])


## One reliable one-shot to every peer standing in this scene. A peer still loading has no node to
## receive it; it gets what it missed from [method _catch_up] when it stands.
func _event(method: StringName, args: Array = []) -> void:
	for peer: int in _session.get_peer_ids():
		if peer != NetTransport.AUTHORITY_PEER_ID and _lobby.is_standing_in(peer, _epoch):
			callv(&"rpc_id", [peer, method] + args)


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


## Authority: [param peer_id] stands in this scene. Once it has started, what was said before it could
## hear is said again.
func _on_peer_standing(peer_id: int) -> void:
	if not _started or peer_id == NetTransport.AUTHORITY_PEER_ID or not _lobby.is_standing_in(peer_id, _epoch):
		return
	if not hub_mode:
		_catch_up(peer_id)
	_announce_bound(peer_id)


## [param peer_id]'s scene stands: it is told what was said once before it could hear.
func _announce_bound(peer_id: int) -> void:
	_session.replicator.send_placed_to(peer_id)
	peer_bound.emit(peer_id)


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
	rpc_id(peer, &"_ev_shoved", forward.normalized())


## The victim's cue, to everyone: the launch rides the snapshot, the sound does not.
func _on_shove_landed(victim: MatchParticipant) -> void:
	if victim != null and victim.body != null:
		_event(&"_ev_shove_landed", [_seat_index_of(victim.index), victim.body.global_position])


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


## Send one peer that bound after the start the whole match state (Quake's gamestate); the
## events after it ride the same ordered channel. Bodies need nothing: snapshots are absolute.
func _catch_up(peer_id: int) -> void:
	if peer_id <= 0 or peer_id == NetTransport.AUTHORITY_PEER_ID:
		return
	rpc_id(peer_id, &"_ev_gamestate", NetCodec.pack_gamestate(controller))


@rpc("authority", "reliable", "call_remote", 0)
func _ev_match_started() -> void:
	if not _replays():
		return
	controller.net_start_match()
	_reconcile_seats()
	if not _started:
		_started = true
		match_bound.emit(false)


## Converge a freshly bound match on the server's state through the same transitions the events run.
@rpc("authority", "reliable", "call_remote", 0)
func _ev_gamestate(state: PackedInt32Array) -> void:
	if not _replays():
		return
	_ev_match_started()
	if not NetCodec.is_gamestate(state, controller.get_participants().size()):
		return
	var phase: MatchController.Phase = state[0] as MatchController.Phase
	if phase == MatchController.Phase.RACE:
		controller.net_start_race()
	elif phase == MatchController.Phase.BRAWL:
		controller.net_start_brawl()
	elif state[2] >= 0:
		controller.net_start_round(state[2], state[1])
	if state[3] >= 0:
		controller.net_arm_finisher(state[3])
	var participants: Array[MatchParticipant] = controller.get_participants()
	for i: int in participants.size():
		var flags: int = state[NetCodec.GAMESTATE_HEADER + i * NetCodec.GAMESTATE_PARTICIPANT]
		if flags & (NetCodec.GAMESTATE_RUNNING | NetCodec.GAMESTATE_SHOOTER) == 0 and participants[i].is_running:
			_ev_removed(i, int(MatchParticipant.DeathCause.SHOT), true)
		if flags & NetCodec.GAMESTATE_GHOST != 0 and flags & NetCodec.GAMESTATE_HELD == 0:
			# Its respawn landed before this machine was listening.
			controller.net_ghost_respawn(i)
	for i: int in participants.size():
		var at: int = NetCodec.GAMESTATE_HEADER + i * NetCodec.GAMESTATE_PARTICIPANT
		participants[i].rounds_won = state[at + 1]
		participants[i].turns_in_tower = state[at + 2]
	if state[4] != int(MatchController.Outcome.IN_PROGRESS):
		controller.net_resolve(state[4] as MatchController.Outcome)
	if phase == MatchController.Phase.MATCH_OVER and state[5] >= 0:
		controller.net_win(state[5])


@rpc("authority", "reliable", "call_remote", 0)
func _ev_race_started() -> void:
	if not _replays():
		return
	controller.net_start_race()


@rpc("authority", "reliable", "call_remote", 0)
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


@rpc("authority", "reliable", "call_remote", 0)
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


@rpc("authority", "reliable", "call_remote", 0)
func _ev_ghost_fell(index: int, cause: int) -> void:
	if not _replays():
		return
	controller.net_ghost_fall(index, _cause_of(cause))


## A death cause off the wire, or SHOT for a number this build has no cause for.
func _cause_of(cause: int) -> MatchParticipant.DeathCause:
	if cause < 0 or cause >= MatchParticipant.DeathCause.size():
		return MatchParticipant.DeathCause.SHOT
	return cause as MatchParticipant.DeathCause


@rpc("authority", "reliable", "call_remote", 0)
func _ev_round_resolved(outcome: int) -> void:
	if not _replays():
		return
	controller.net_resolve(outcome as MatchController.Outcome)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_match_won(index: int, rounds_won: int) -> void:
	if not _replays():
		return
	_take_rounds_won(index, rounds_won)
	controller.net_win(index)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_ghost_respawned(index: int) -> void:
	if not _replays():
		return
	controller.net_ghost_respawn(index)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_ghost_caught(ghost_index: int, caught_index: int, held: bool) -> void:
	if not _replays():
		return
	controller.net_ghost_caught(ghost_index, caught_index)
	_made_ghost(caught_index, held)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_rifle_fired(
	which: int, origin: Vector3, end_point: Vector3, reload: float, speed: float, gravity: float
) -> void:
	if not _replays():
		return
	var weapon: Rifle = _weapon_of(which)
	if weapon != null:
		weapon.show_remote_shot(origin, end_point, reload, speed, gravity)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_rifle_hit(which: int, index: int, at: Vector3, normal: Vector3) -> void:
	if not _replays():
		return
	var weapon: Rifle = _weapon_of(which)
	if weapon == null:
		return
	var participants: Array[MatchParticipant] = controller.get_participants()
	var participant: MatchParticipant = participants[index] if index >= 0 and index < participants.size() else null
	var body: Node3D = participant.body if participant != null else null
	weapon.show_remote_hit(body, at, normal)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_rifle_missed(which: int, end_point: Vector3) -> void:
	if not _replays():
		return
	var weapon: Rifle = _weapon_of(which)
	if weapon != null:
		weapon.show_remote_miss(end_point)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_finisher_armed(index: int) -> void:
	if not _replays():
		return
	controller.net_arm_finisher(index)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_kill_beat(guard_index: int, throw: Vector3) -> void:
	if not _replays() or not throw.is_finite():
		return
	controller.net_kill_beat(guard_index, throw)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_brawl_started() -> void:
	if _replays():
		controller.net_start_brawl()


@rpc("authority", "reliable", "call_remote", 0)
func _ev_brawl_out(index: int, throw: Vector3) -> void:
	if _replays() and throw.is_finite():
		controller.net_brawl_out(index, throw)


@rpc("authority", "reliable", "call_remote", 0)
func _ev_shove_landed(seat_index: int, at: Vector3) -> void:
	if not _replays() or not at.is_finite():
		return
	controller.net_shove_landed(_slot_of_seat.get(seat_index, -1), at)


## Which gun an event names, or null for one this build has not got. Callers have
## already refused the authority; see [method _replays].
func _weapon_of(which: int) -> Rifle:
	return controller.rifle if which == TOWER_RIFLE else null


@rpc("authority", "reliable", "call_remote", 0)
func _ev_shoved(forward: Vector3) -> void:
	if not _replays() or not forward.is_finite():
		return
	controller.net_shove_felt(forward)

