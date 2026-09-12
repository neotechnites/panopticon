class_name PlayerNetLink
extends Node

## Carries one seat's body across the wire: intent up to the authority, and the
## authoritative state back down through [NetReplicator].
##
## One of these sits beside one [PlayerController]. Which direction it pushes
## depends on where it is running, not on who owns the body:
##
## [b]On the authority[/b] (the listen server, or an offline bot run) the body
## simulates. Intent reaches it through a [RemoteIntentSource] fed by
## [method _receive_intent] when a client owns the seat, or through the local
## [member local_source] when the host or a bot does. Either way
## [PlayerController] polls an [IntentSource] and runs the same physics -- there
## is no networked movement path and no second copy of the acceleration
## routines. The resulting state is sampled by [NetReplicator] after the tick
## and goes out with everyone else's.
##
## [b]On a client[/b] nothing simulates. The controller's physics is switched
## off and every body, this machine's included, is moved by the replicator from
## the snapshots. If this machine owns the seat, the link polls
## [member local_source] each tick and sends the intent to the authority.
##
## [b]A seat, not a peer[/b]
##
## [member seat_index] is what this body is called on the wire, and
## [member owner_peer_id] is the separate question of whose packets may drive
## it. They are separate because a bot's seat has no peer at all: the whole
## project rests on a bot and a remote human being interchangeable in a seat,
## and a body named after the peer driving it could not be replicated when
## nothing is. A zero [member owner_peer_id] means no packet is ever accepted
## for this body -- a bot, an empty seat, or the host's own.
##
## [b]Authority never follows the tower[/b]
##
## This node deliberately never calls [method Node.set_multiplayer_authority].
## Every link on every machine keeps its multiplayer authority at
## [constant NetTransport.AUTHORITY_PEER_ID], including links for bodies a
## client is driving. That separation is the whole point: the tower seat
## changes hands whenever a prisoner scores, and if authority were attached to
## a role rather than to a peer, every score would migrate the simulation
## mid-match.
##
## What is and is not implemented in the replication path is documented in one
## place, on [NetReplicator]. Read that before building on this.

## The authority accepted an intent packet for this seat. Authority-only. The
## seam for telemetry, input logging and a future server-side movement audit.
signal intent_received(peer_id: int, tick: int)

## The session this link belongs to. Supplies the authority test and the local
## peer id; the link never touches a [NetTransport] itself.
@export var session: NetSession

## Where this body's state is sampled from and sent to. The link registers
## itself here at ready and takes itself off again when it leaves the tree.
@export var replicator: NetReplicator

## The body this link replicates.
@export var controller: PlayerController

## Which seat this body is. The name of this body on the wire, and the same
## number on every machine for the life of the session. See [LobbySeat].
@export_range(0, 7, 1) var seat_index: int = 0

## Which peer's packets may drive this body, or 0 for a body no packet may
## drive -- a bot, or this machine's own. Not a role, not a team, not the
## tower.
@export var owner_peer_id: int = 0

## Where this machine's own input comes from when it drives this body: a
## [HumanIntentSource] for a player, a [BotIntentSource] for a bot or the
## harness. Unset for a body owned by somebody else, which is fed from the
## network instead.
##
## [b]This is the interchangeability requirement, in one field.[/b] Whether a
## seat is filled by a bot or by a remote human is the difference between this
## being set and [member owner_peer_id] being set. Nothing else in the match
## can tell.
@export var local_source: IntentSource

## Fed by [method _receive_intent] on the authority when a client owns this
## seat, and switched into the controller in place of [member local_source].
##
## Part of [code]scenes/net/player_net_link.tscn[/code] rather than built here
## when a client first turns up: a node this project needs is a node in a
## scene file, and one made in code is one nobody can see, inspect or retune.
## It costs a handful of bytes on a seat that never has a remote owner.
@export var remote_source: RemoteIntentSource

## Reused per packet so the per-tick path does not allocate.
var _scratch_intent: MoveIntent = MoveIntent.new()

## This machine's own tick count, for stamping outgoing intent. Ordering only:
## it is not synchronised with the authority's and means nothing across
## machines. That is the missing piece reconciliation would need.
var _tick: int = 0

## True if this machine simulates. Latched at [method refresh_role] rather than
## queried per tick, so a session state change cannot flip the role halfway
## through a frame.
var _is_authority: bool = false


func _ready() -> void:
	if session == null or controller == null:
		push_error("PlayerNetLink needs a session and a controller; this body will not replicate.")
		set_physics_process(false)
		return
	if replicator != null:
		replicator.register(self)
	session.connection_state_changed.connect(_on_connection_state_changed)
	refresh_role()


func _exit_tree() -> void:
	if replicator != null:
		replicator.unregister(self)


## Re-read the session and wire the body up accordingly. Called at ready and
## whenever the connection state changes; call it by hand after reassigning
## [member owner_peer_id] or [member local_source], which is exactly what the
## match layer does when a dropped player's seat is handed to a bot.
func refresh_role() -> void:
	if session == null or controller == null:
		return
	_is_authority = session.is_authority()

	if not _is_authority:
		# A client owns no simulation. Leaving the controller's physics running
		# would fight every snapshot that arrives, and the fight would look
		# exactly like a prediction bug in code that has no prediction.
		controller.intent_source = null
		controller.set_physics_process(false)
		return

	controller.set_physics_process(true)
	if _owns_locally():
		controller.intent_source = local_source
	else:
		controller.intent_source = _ensure_remote_source()

	if controller.intent_source != null:
		# PlayerController configures its source once, at its own _ready. A
		# source swapped in afterwards has to be configured here or it has no
		# profile and reports nothing.
		controller.intent_source.configure(controller.profile)


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _is_authority or session == null or controller == null:
		return
	if _owns_locally():
		_send_intent()


## True when this body should appear in snapshots. A link whose controller has
## been freed out from under it is not an error -- the match parks and rebuilds
## bodies between rounds -- it simply has nothing to describe.
func is_replicable() -> bool:
	return controller != null and controller.is_inside_tree()


## The network-fed source for this body. Present whether or not it is in use;
## [method PlayerController.intent_source] is what says which source is live.
func get_remote_source() -> RemoteIntentSource:
	return remote_source


## Read this body's current state into [param out]. Called by [NetReplicator]
## on the authority, after the physics tick.
func sample_state(out: PlayerState) -> void:
	out.seat_index = seat_index
	out.position = controller.global_position
	out.velocity = controller.velocity
	out.yaw = controller.rotation.y
	out.pitch = controller.head.rotation.x if controller.head != null else 0.0
	out.on_floor = controller.is_on_floor()
	var power: RunnerPower = RunnerPower.of(controller)
	out.ability = int(power.get_active()) if power != null else 0
	out.ability_remaining = power.get_remaining() if power != null else 0.0


## Put an authoritative state onto the body. Called by [NetReplicator] on a
## client, once per drawn frame while interpolating and once per snapshot when
## not.
##
## Transform, velocity and floor state. A client never integrates the velocity
## -- its physics is off -- but [PrisonerAvatar] reads speed and footing to pick
## a clip, and a body reporting neither is drawn standing still or dead forever.
##
## The runner power comes down the same way and is DRAWN, not run: the effect
## belongs to the authority, and this machine's own body is mirrored like any
## other, so a client sees its own shield here or nowhere.
func apply_state(state: PlayerState) -> void:
	if controller == null:
		return
	var power: RunnerPower = RunnerPower.of(controller)
	if power != null:
		power.present(state.ability as MatchRules.RunnerAbility, state.ability_remaining)
	controller.global_position = state.position
	controller.rotation.y = state.yaw
	controller.velocity = state.velocity
	controller.net_floor = 1 if state.on_floor else 0
	if controller.head != null:
		controller.head.rotation.x = state.pitch


# --- Sending ------------------------------------------------------------------

func _send_intent() -> void:
	if local_source == null or not session.is_established():
		return
	_scratch_intent.copy_from(local_source.poll(get_physics_process_delta_time()))
	_scratch_intent.normalise()
	rpc_id(session.get_authority_peer_id(), &"_receive_intent", NetCodec.pack_intent(_tick, _scratch_intent))


# --- Receiving ----------------------------------------------------------------

## Client to authority, every tick.
##
## Every tick, and not at the snapshot rate: an input that is not sent is an
## input the player made and the game ignored, which is a different and much
## worse thing than a position drawn 33 ms late. Unreliable and ordered,
## because a late input is worth less than the next one and retransmitting it
## would add delay to buy back a tick nobody wants any more.
@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _receive_intent(payload: PackedByteArray) -> void:
	if not _is_authority:
		# Only the authority consumes intent. Reaching here on a client means
		# a peer is impersonating the server, and the right response is to
		# ignore it rather than to move a body.
		return
	if owner_peer_id == 0:
		# Nothing remote drives this seat. A bot's body and the host's own can
		# never be moved by a packet, however well formed.
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != owner_peer_id:
		# The one check that stops a peer driving somebody else's body.
		return

	var tick: int = NetCodec.unpack_intent(payload, _scratch_intent)
	if tick < 0:
		return
	var limit: float = session.get_settings().max_look_delta_radians
	_scratch_intent.look_delta = _scratch_intent.look_delta.clampf(-limit, limit)

	var source: RemoteIntentSource = _ensure_remote_source()
	if not source.accept(tick, _scratch_intent):
		# Reordered by UDP and older than one already applied.
		return
	intent_received.emit(sender_id, tick)


# --- Internals ----------------------------------------------------------------

## True when this machine's own input drives this body.
##
## Zero means nobody remote does, which on the authority means this machine
## does -- that is a bot's seat, and the host's own seat when offline.
func _owns_locally() -> bool:
	if owner_peer_id == 0:
		return true
	return owner_peer_id == session.get_local_peer_id()


## The network-fed source, configured from the session's settings the first
## time it is asked for. Null only when the scene was assembled without one.
func _ensure_remote_source() -> RemoteIntentSource:
	if remote_source != null:
		remote_source.stale_after_ticks = session.get_settings().stale_intent_ticks
	return remote_source


func _on_connection_state_changed(_state: NetTransport.ConnectionState) -> void:
	refresh_role()


## One line, for logs and the harness.
func describe() -> String:
	return "PlayerNetLink(seat %d, owner peer %d, %s, %s)" % [
		seat_index,
		owner_peer_id,
		"authority" if _is_authority else "client",
		"local input" if _owns_locally() else "remote input",
	]
