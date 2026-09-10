class_name PlayerNetLink
extends Node

## Carries one player's body across the wire: intent up to the authority,
## authoritative state back down.
##
## One of these sits beside one [PlayerController]. Which direction it pushes
## depends on where it is running, not on who owns the body:
##
## [b]On the authority[/b] (the listen server, or an offline bot run) the body
## simulates. Intent reaches it through a [RemoteIntentSource] fed by
## [method _receive_intent] when the owner is a client, or through the local
## [member local_source] when the owner is the host. Either way
## [PlayerController] polls an [IntentSource] and runs the same physics -- there
## is no networked movement path and no second copy of the acceleration
## routines. After the tick, the resulting [PlayerState] is broadcast to
## everyone.
##
## [b]On a client[/b] nothing simulates. The controller's physics is switched
## off and every body, the local player's included, is snapped to the snapshots
## as they arrive. If the owner is local, the link polls [member local_source]
## each tick and sends the intent to the authority.
##
## [b]Authority never follows the tower[/b]
##
## This node deliberately never calls [method Node.set_multiplayer_authority].
## Every [PlayerNetLink] on every machine keeps its multiplayer authority at
## [constant NetTransport.AUTHORITY_PEER_ID], including the links for bodies a
## client is driving. Ownership of [i]input[/i] is [member owner_peer_id],
## checked by hand against the RPC sender. That separation is the whole point:
## the tower seat changes hands whenever a prisoner scores, and if authority
## were attached to a role rather than to a peer, every score would migrate the
## simulation mid-match.
##
## [b]What this is honestly not[/b]
##
## This is the authoritative path, correct and complete, and nothing more:
##
## - [b]No prediction.[/b] A client's own body does not move until a snapshot
##   arrives, so local input costs a full round trip of visible delay. This is
##   the single biggest thing missing and the reason this is not shippable
##   feel yet.
## - [b]No reconciliation.[/b] There is no input buffer to replay, which is why
##   prediction cannot simply be switched on: it needs the acked-tick plumbing
##   the wire format already reserves space for.
## - [b]No interpolation.[/b] Remote bodies teleport to each snapshot at the
##   authority's tick rate rather than being played back from a buffer, so
##   movement is stepped and every dropped packet is a visible hitch.
## - [b]No lag compensation.[/b] Shots are resolved against where the authority
##   thinks bodies are now, not where the shooter saw them. On a listen server
##   that quietly favours the host.
## - [b]No delta compression and no acks.[/b] Every field goes every tick.
##   Cheap at eight players; not a habit to keep.
## - [b]No spawn replication.[/b] There is no [MultiplayerSpawner] here, so
##   RPCs resolve by node path and the match layer must build identically named
##   nodes on every peer. Bodies joining and leaving mid-match are not handled.
## - [b]Nothing but movement.[/b] Weapon fire, hits, the round result and who
##   holds the tower are not replicated by this file.
## - [b]No clock sync.[/b] Ticks are each machine's own count, used for
##   ordering only, and mean nothing across machines.

## The authority accepted an intent packet from [member owner_peer_id].
## Authority-only. The seam for telemetry, input logging and a future
## server-side movement audit.
signal intent_received(peer_id: int, tick: int)

## A client applied an authoritative snapshot. Client-only.
signal state_received(state: PlayerState)

## The session this link belongs to. Supplies the authority test and the peer
## roster; the link never touches a [NetTransport] itself.
@export var session: NetSession

## The body this link replicates.
@export var controller: PlayerController

## Which peer's input drives this body. Not a role, not a team, not the tower --
## a peer id, stable for the session.
@export var owner_peer_id: int = NetTransport.AUTHORITY_PEER_ID

## Where this machine's own input comes from when it owns this body: a
## [HumanIntentSource] for a player, a [BotIntentSource] for the harness. Unset
## for a body owned by somebody else, which is fed from the network instead.
@export var local_source: IntentSource

## Largest per-tick look delta the authority will accept from a client, in
## radians.
##
## A client's packet is hostile input. The codec rejects a malformed one and
## rejects NaN, but a well-formed packet claiming a thousand radians of yaw in
## one tick is exactly what an aimbot sends, and it is clamped here rather than
## in [NetCodec] because the sane range is a gameplay question and the codec
## has no business knowing about gameplay. PI is a half turn in one tick, well
## beyond any real flick and still short of a rotation that could be used to
## alias the yaw.
##
## Note the limit of this: it bounds one tick. Sustained impossible movement --
## the rest of a movement audit -- is not implemented.
@export var max_look_delta_radians: float = PI

## Fed by [method _receive_intent] on the authority when a client owns this
## body. Created on demand, and only there.
var _remote_source: RemoteIntentSource = null

## This machine's physics tick count. Ordering only; see the class docs.
var _tick: int = 0

## Reused per packet so the per-tick path does not allocate.
var _scratch_intent: MoveIntent = MoveIntent.new()
var _scratch_state: PlayerState = PlayerState.new()

## True if this machine simulates. Latched at [method refresh_role] rather than
## queried per tick, so a session state change cannot flip the role halfway
## through a frame.
var _is_authority: bool = false


func _ready() -> void:
	if session == null or controller == null:
		push_error("PlayerNetLink needs a session and a controller; this body will not replicate.")
		set_physics_process(false)
		return
	# Run after the controller's own physics, so the state sampled and sent is
	# the result of this tick's movement rather than the previous one's.
	process_physics_priority = 100
	session.connection_state_changed.connect(_on_connection_state_changed)
	refresh_role()


## Re-read the session and wire the body up accordingly. Called at ready and
## whenever the connection state changes; call it by hand after reassigning
## [member owner_peer_id].
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
	if session == null or controller == null:
		return

	if _is_authority:
		_broadcast_state()
		return

	if _owns_locally():
		_send_intent()


## The network-fed source for this body, or null when the owner is local or
## this machine is not the authority.
func get_remote_source() -> RemoteIntentSource:
	return _remote_source


## Apply an authoritative snapshot to the body. Public because a replay or a
## test drives it directly.
##
## A hard snap, on purpose. Interpolation would hide how coarse this path
## currently is, and the first thing built on top of this must be prediction
## for the local body, not a smoothing filter that makes the delay pretty.
func apply_state(state: PlayerState) -> void:
	if controller == null:
		return
	controller.global_position = state.position
	controller.velocity = state.velocity
	controller.rotation.y = state.yaw
	if controller.head != null:
		controller.head.rotation.x = state.pitch


# --- Sending ------------------------------------------------------------------

func _send_intent() -> void:
	if local_source == null or not session.is_established():
		return
	_scratch_intent.copy_from(local_source.poll(_get_physics_delta()))
	_scratch_intent.normalise()
	var payload: PackedByteArray = NetCodec.pack_intent(_tick, _scratch_intent)
	rpc_id(session.get_authority_peer_id(), &"_receive_intent", payload)


func _broadcast_state() -> void:
	# Offline -- single player, or the headless bot harness -- is authoritative
	# with nobody to tell. A lone host has the same shape.
	if not session.is_established() or session.get_peer_count() <= 1:
		return
	_sample_state(_scratch_state)
	rpc(&"_receive_state", NetCodec.pack_state(_scratch_state))


func _sample_state(out: PlayerState) -> void:
	out.peer_id = owner_peer_id
	out.tick = _tick
	out.position = controller.global_position
	out.velocity = controller.velocity
	out.yaw = controller.rotation.y
	out.pitch = controller.head.rotation.x if controller.head != null else 0.0
	out.on_floor = controller.is_on_floor()


# --- Receiving ----------------------------------------------------------------

## Client to authority, every tick. Unreliable and ordered: a late input is
## worth less than the next one, so retransmitting it would add delay to buy
## back a tick nobody wants any more.
@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _receive_intent(payload: PackedByteArray) -> void:
	if not _is_authority:
		# Only the authority consumes intent. Reaching here on a client means
		# a peer is impersonating the server, and the right response is to
		# ignore it rather than to move a body.
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != owner_peer_id:
		# The one check that stops a peer driving somebody else's body.
		return

	var tick: int = NetCodec.unpack_intent(payload, _scratch_intent)
	if tick < 0:
		return
	_scratch_intent.look_delta = _scratch_intent.look_delta.clampf(
		-max_look_delta_radians, max_look_delta_radians
	)

	var source: RemoteIntentSource = _ensure_remote_source()
	if not source.accept(tick, _scratch_intent):
		# Reordered by UDP and older than one already applied.
		return
	intent_received.emit(sender_id, tick)


## Authority to everyone, every tick. Restricted to the node's multiplayer
## authority, which is [constant NetTransport.AUTHORITY_PEER_ID] and stays
## there for the life of the session however often the tower changes hands.
@rpc("authority", "unreliable_ordered", "call_remote", 2)
func _receive_state(payload: PackedByteArray) -> void:
	if _is_authority:
		return
	if not NetCodec.unpack_state(payload, _scratch_state):
		return
	apply_state(_scratch_state)
	state_received.emit(_scratch_state)


# --- Internals ----------------------------------------------------------------

func _owns_locally() -> bool:
	var local_id: int = session.get_local_peer_id()
	if local_id == 0:
		# Offline: there is one machine and it owns everything on it.
		return true
	return local_id == owner_peer_id


func _ensure_remote_source() -> RemoteIntentSource:
	if _remote_source == null:
		_remote_source = RemoteIntentSource.new()
		_remote_source.name = "RemoteIntent"
		add_child(_remote_source)
	return _remote_source


func _get_physics_delta() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


func _on_connection_state_changed(_state: NetTransport.ConnectionState) -> void:
	refresh_role()
