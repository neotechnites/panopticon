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
## [b]On a client[/b] somebody else's body does not simulate: its physics is
## switched off and it is moved by the replicator from the snapshots. THIS
## machine's own body does simulate, off its own input, and is put right against
## the snapshots as they land -- see [b]Prediction[/b] below. Either way the
## intent goes to the authority every tick and the authority's answer wins.
##
## [b]Prediction[/b]
##
## A client's own body runs the same [PlayerController] physics off the same
## [MoveIntent] on the tick the key goes down, so movement costs no round trip.
## Every tick is kept -- the intent, and the body it produced -- until a
## snapshot says the authority has applied it: see
## [member PlayerState.last_intent_tick]. On a snapshot the body is rewound to
## the authority's state at the tick it acknowledges, every intent since is
## replayed on top, and the difference between the old prediction and the new
## one is taken out of [member PlayerController.view_offset] over
## [member NetSettings.prediction_smoothing_seconds] rather than jumped.
##
## Anything the client could not have predicted -- a boost pad, a shove, a kill,
## a respawn -- arrives as a correction larger than
## [member NetSettings.prediction_snap_metres]. Those are not smoothed: the
## buffer is dropped and the body takes the authority's state whole, because
## drawing a launch as a graceful drift would be a lie about where the body is.
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

## The authority disagreed with a prediction of this body. Client-only, at most
## one per snapshot: [param metres] is how far out the prediction was at the
## tick the authority acknowledged, and [param snapped] is whether it was too
## far to replay and the body was moved whole. Telemetry; nothing reacts to it.
signal prediction_corrected(metres: float, snapped: bool)

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

## The match this body is in, and which participant it is. The finisher flags
## and the hit points live on the participant, not on the body. Set by [NetMatch].
@export var match_controller: MatchController

## Fed by [method _receive_intent] on the authority when a client owns this
## seat, and switched into the controller in place of [member local_source].
##
## Part of [code]scenes/net/player_net_link.tscn[/code] rather than built here
## when a client first turns up: a node this project needs is a node in a
## scene file, and one made in code is one nobody can see, inspect or retune.
## It costs a handful of bytes on a seat that never has a remote owner.
@export var remote_source: RemoteIntentSource

## Unacknowledged ticks the prediction buffer holds. 64 at 60 Hz is a second of
## input the authority has not answered for; past that a client is guessing,
## not predicting, and is better off taking the authority's word.
const PREDICTION_CAPACITY: int = 64

## Time constants spent inside [member NetSettings.prediction_smoothing_seconds],
## so a correction is 95% drawn away by the time that setting names.
const _SMOOTHING_CONSTANTS: float = 3.0

## Below this, in metres, a view offset is finished rather than chased.
const _SMOOTHING_EPSILON: float = 0.001


## One unacknowledged tick: the intent that was sent, and the body it produced.
class PredictedTick extends RefCounted:
	var tick: int = 0
	var intent: MoveIntent = MoveIntent.new()
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var motion: PackedFloat32Array = PackedFloat32Array()


## Reused per packet so the per-tick path does not allocate.
var _scratch_intent: MoveIntent = MoveIntent.new()

## True when this machine is a client simulating its own body. Latched with the
## rest of the role in [method refresh_role].
var _predicting: bool = false

## The ring of unacknowledged ticks, oldest first. Allocated once; the entries
## are written over rather than replaced.
var _predicted: Array[PredictedTick] = []
var _predicted_start: int = 0
var _predicted_count: int = 0

## The newest authoritative state for this body, waiting for the next physics
## tick to be reconciled against. Applied there and not on arrival, because a
## snapshot lands on an idle frame and a rewind runs physics.
var _pending_state: PlayerState = PlayerState.new()
var _has_pending_state: bool = false

## Prediction error still to be drawn away, in world metres. See
## [member PlayerController.view_offset].
var _view_error: Vector3 = Vector3.ZERO

## This machine's own tick count, for stamping outgoing intent. Ordering only:
## it is not synchronised with the authority's and means nothing across
## machines. The authority echoes it back in
## [member PlayerState.last_intent_tick], which is what reconciliation rewinds
## to -- so it means something to the machine that sent it, and to no other.
var _tick: int = 0

## True if this machine simulates. Latched at [method refresh_role] rather than
## queried per tick, so a session state change cannot flip the role halfway
## through a frame.
var _is_authority: bool = false

## The body jumped since the last snapshot was sampled. An edge has no state to
## read back off the controller, so it is latched off the signal and cleared
## when it goes out.
var _jumped_since_sample: bool = false

## The newest snapshot tick whose EDGES have been replayed on this body, or -1
## before the first. Interpolation hands [method apply_state] the same snapshot
## every drawn frame; the events inside it must fire once.
var _event_tick: int = -1
var _was_on_floor: bool = true
var _was_sliding: bool = false

## Downward speed off the last airborne snapshot, for the landing cue.
var _fall_speed: float = 0.0


func _ready() -> void:
	if session == null or controller == null:
		push_error("PlayerNetLink needs a session and a controller; this body will not replicate.")
		set_physics_process(false)
		return
	# After the body has moved, so a recorded tick is the tick's RESULT and a
	# rewind happens between two ticks rather than in the middle of one.
	process_physics_priority = 50
	if replicator != null:
		replicator.register(self)
	session.connection_state_changed.connect(_on_connection_state_changed)
	controller.jumped.connect(func() -> void: _jumped_since_sample = true)
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
	_predicting = (
		not _is_authority
		and _owns_locally()
		and local_source != null
		and session.get_settings().predict_local_body
	)

	controller.net_predicted = _predicting
	if not _is_authority and not _predicting:
		# Somebody else's body on a client owns no simulation. Leaving its
		# physics running would fight every snapshot that arrives.
		controller.intent_source = null
		controller.set_physics_process(false)
		reset_prediction()
		return

	if _predicting:
		# This machine's own body on a client. It runs the real physics off the
		# real input, so it reads its own footing rather than the snapshot's.
		reset_prediction()
		_take_own_footing()

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


func _physics_process(delta: float) -> void:
	_tick += 1
	if _is_authority or session == null or controller == null:
		return
	if not _owns_locally():
		return
	if not _predicting:
		_send_intent()
		return
	if not controller.is_physics_processing():
		# The match has parked this body -- a round break, a kill beat, a ghost
		# settling. There is nothing to predict until it is woken, and the
		# replicator mirrors it in the meantime.
		reset_prediction()
		_send_intent()
		return
	if controller.net_floor >= 0:
		# Mirrored while it was parked. Its own physics answers for it again.
		_take_own_footing()
	# The body has already moved on this tick's intent: record what it did,
	# tell the authority what it was asked to do, then take whatever answer
	# arrived since and put the body right.
	_record_tick()
	_send_intent()
	if _has_pending_state:
		_has_pending_state = false
		_reconcile(delta)
	_decay_view_error(delta)


## This machine's own intent clock -- what an outgoing intent is stamped with,
## and what comes back as [member PlayerState.last_intent_tick]. Ordering only;
## it means nothing on another machine.
func get_intent_tick() -> int:
	return _tick


## True when this body should appear in snapshots. A link whose controller has
## been freed out from under it is not an error -- the match parks and rebuilds
## bodies between rounds -- it simply has nothing to describe.
func is_replicable() -> bool:
	return controller != null and controller.is_inside_tree()


## True when this machine is a client simulating this body ahead of the
## authority. The replicator asks, because a predicted body must not also be
## interpolated.
##
## Gated on the body's own physics, not only on the role: the match parks bodies
## between rounds and through a kill beat, and a parked body is a mirrored one
## until the match wakes it again.
func is_predicting() -> bool:
	return _predicting and controller != null and controller.is_physics_processing()


## Let the body answer for its own footing and pose again, rather than the last
## snapshot that was put on it.
func _take_own_footing() -> void:
	controller.net_floor = -1
	controller.net_slide = -1
	controller.net_crouch = -1


## Forget every unacknowledged tick and finish the view where the body is.
##
## For anything that moves the body from outside the prediction -- a round
## restart, a respawn, a body handed to a bot -- and for the correction too
## large to be anything but one of those.
func reset_prediction() -> void:
	_predicted_start = 0
	_predicted_count = 0
	_has_pending_state = false
	_view_error = Vector3.ZERO
	if controller != null:
		controller.view_offset = Vector3.ZERO


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
	out.cooldown_remaining = power.get_cooldown_remaining() if power != null else 0.0
	out.is_armed = controller.is_armed
	out.sliding = controller.is_sliding()
	out.crouching = controller.is_crouching()
	out.jumped = _jumped_since_sample
	_jumped_since_sample = false
	# What the owner of this seat may rewind to: the last intent of theirs this
	# body has actually simulated, not merely received. Nothing to say for a
	# bot's seat or the host's own, and nobody to say it to.
	out.last_intent_tick = (
		remote_source.applied_tick if remote_source != null and owner_peer_id != 0 else -1
	)
	var participant: MatchParticipant = _participant()
	out.is_finisher = participant.is_finisher if participant != null else false
	out.health = participant.health if participant != null else 0


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
	_apply_presentation(state)
	controller.global_position = state.position
	controller.rotation.y = state.yaw
	controller.velocity = state.velocity
	controller.net_floor = 1 if state.on_floor else 0
	controller.net_slide = 1 if state.sliding else 0
	controller.net_crouch = 1 if state.crouching else 0
	if controller.head != null:
		controller.head.rotation.x = state.pitch
	_present_events(state)


## The half of a state that is drawn rather than simulated: the power, the
## rifle and the participant's own facts. A predicted body takes this and moves
## itself; a mirrored one takes this and the transform with it.
func _apply_presentation(state: PlayerState) -> void:
	var power: RunnerPower = RunnerPower.of(controller)
	if power != null:
		power.present(
			state.ability as MatchRules.RunnerAbility,
			state.ability_remaining,
			state.cooldown_remaining,
		)
	controller.is_armed = state.is_armed
	var participant: MatchParticipant = _participant()
	if participant != null:
		participant.is_finisher = state.is_finisher
		participant.health = state.health


## Turn one snapshot's transitions back into the body's own signals, so that
## [MovementAudioListener] and [PrisonerAvatar] hear a mirrored body move.
##
## Once per snapshot, not once per drawn frame: interpolation replays the same
## state until the next one lands.
func _present_events(state: PlayerState) -> void:
	if _event_tick >= 0 and not NetCodec.is_newer_tick(state.tick, _event_tick):
		return
	var first: bool = _event_tick < 0
	_event_tick = state.tick
	if first:
		_was_on_floor = state.on_floor
		_was_sliding = state.sliding
		return
	if state.jumped:
		controller.jumped.emit()
	if state.on_floor and not _was_on_floor:
		controller.landed.emit(_fall_speed)
	elif not state.on_floor:
		_fall_speed = absf(state.velocity.y)
	if state.sliding and not _was_sliding:
		controller.slide_started.emit(controller.get_horizontal_speed())
	elif _was_sliding and not state.sliding:
		controller.slide_ended.emit()
	_was_on_floor = state.on_floor
	_was_sliding = state.sliding


## This body's participant, or null before the match has built them.
func _participant() -> MatchParticipant:
	if match_controller == null or controller == null:
		return null
	return match_controller.resolve_participant(controller)


# --- Sending ------------------------------------------------------------------

func _send_intent() -> void:
	if local_source == null or not session.is_established():
		return
	# A predicting body has already polled the source on this tick, through the
	# controller. Polling it again here would eat the edges twice and send an
	# input the body never acted on.
	if _predicting:
		_scratch_intent.copy_from(controller.get_intent())
	else:
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


# --- Prediction ---------------------------------------------------------------

## Take the authority's state for this body. Called by [NetReplicator] on a
## client in place of [method apply_state] while this link is predicting.
##
## Held rather than applied: a snapshot lands on an idle frame and putting the
## body right runs physics, so it waits for the next physics tick.
func receive_authoritative(state: PlayerState) -> void:
	_pending_state.copy_from(state)
	_has_pending_state = true


## Keep this tick: the intent the body was driven by, and where it ended up.
func _record_tick() -> void:
	if _predicted.is_empty():
		_predicted.resize(PREDICTION_CAPACITY)
		for i: int in PREDICTION_CAPACITY:
			_predicted[i] = PredictedTick.new()
	if _predicted_count >= PREDICTION_CAPACITY:
		# Nothing has been acknowledged for a second. The oldest goes, not the
		# newest: it is the one the authority has most likely passed already.
		_predicted_start = (_predicted_start + 1) % PREDICTION_CAPACITY
		_predicted_count -= 1
	var entry: PredictedTick = _slot(_predicted_count)
	_predicted_count += 1
	entry.tick = _tick
	entry.intent.copy_from(controller.get_intent())
	_write_result(entry)


## Where the body is now, into [param entry].
func _write_result(entry: PredictedTick) -> void:
	entry.position = controller.global_position
	entry.velocity = controller.velocity
	entry.yaw = controller.rotation.y
	controller.capture_motion_state(entry.motion)


## Rewind to the authority's state, replay what it has not seen, and hand the
## difference to the view.
##
## The POSITION rewound to is the authority's. The AIM rewound to is this
## machine's own, recorded at the same tick: yaw is the player's own integration
## of the look deltas the authority is integrating too, so taking it off a
## snapshot would drag the mouse a round trip into the past thirty times a
## second. It must still be rewound to something, though -- the replay turns by
## every unacknowledged look delta again, and a replay that starts from the yaw
## it has already reached turns the player twice for every correction.
func _reconcile(delta: float) -> void:
	_apply_presentation(_pending_state)
	var acked: int = _pending_state.last_intent_tick
	if acked < 0:
		# The authority has run none of this client's input yet. There is
		# nothing to rewind to and nothing to replay.
		_snap_to(_pending_state)
		prediction_corrected.emit(0.0, true)
		return

	var first: int = _first_unacknowledged(acked)
	if first == 0:
		# Every tick held is newer than the acknowledgement: this is the wake of
		# a snap, and the authority is still answering for input from before it.
		# Nothing here maps onto anything kept, so it is left alone -- the body
		# is already where the snap put it -- and reconciliation resumes on its
		# own once the acknowledgements catch the buffer up, a round trip later.
		return
	var index: int = first - 1
	var predicted: PredictedTick = _slot(index)
	if predicted.tick != acked:
		# A tick was acknowledged that this buffer straddles but does not hold.
		_snap_to(_pending_state)
		prediction_corrected.emit(0.0, true)
		return

	var missed: float = _pending_state.position.distance_to(predicted.position)
	prediction_corrected.emit(missed, missed > session.get_settings().prediction_snap_metres)
	if missed > session.get_settings().prediction_snap_metres:
		_snap_to(_pending_state)
		return

	var before: Vector3 = controller.global_position
	controller.global_position = _pending_state.position
	controller.velocity = _pending_state.velocity
	controller.rotation.y = predicted.yaw
	controller.restore_motion_state(predicted.motion)
	# The replayed ticks are this body's own past. Their signals were heard when
	# they happened; heard again they would fire the last hundred milliseconds
	# of footsteps, jumps and landings a second time.
	controller.set_block_signals(true)
	for i: int in range(index + 1, _predicted_count):
		var entry: PredictedTick = _slot(i)
		controller.simulate_tick(entry.intent, delta)
		_write_result(entry)
	controller.set_block_signals(false)

	_drop_through(index)
	_add_view_error(before - controller.global_position)


## The first tick held that the authority has not acknowledged, as an index into
## the buffer. Equal to the count when it has acknowledged them all.
func _first_unacknowledged(acked: int) -> int:
	for i: int in _predicted_count:
		if NetCodec.is_newer_tick(_slot(i).tick, acked):
			return i
	return _predicted_count


## Take the authority's state whole, for a correction no replay can explain: a
## launch, a shove, a kill, a respawn, or a buffer that has run out of history.
func _snap_to(state: PlayerState) -> void:
	# The turning done since the authority sampled this is still the player's.
	# The yaw comes back from the authority -- a body the match has re-placed is
	# facing where the match put it -- and the unacknowledged look deltas are
	# turned onto it again, so being shoved never also takes the mouse.
	var turned: float = _unacknowledged_yaw(state.last_intent_tick)
	reset_prediction()
	controller.global_position = state.position
	controller.velocity = state.velocity
	controller.rotation.y = state.yaw - turned


## Yaw the player has asked for since [param acked_tick], in radians of
## [method Node3D.rotate_y] input.
func _unacknowledged_yaw(acked_tick: int) -> float:
	var turned: float = 0.0
	for i: int in range(_first_unacknowledged(acked_tick), _predicted_count):
		turned += _slot(i).intent.look_delta.x
	return turned


## Add to the error the view still owes, capped so a snap-sized mistake that
## slipped past the threshold cannot detach the camera from the body.
func _add_view_error(error: Vector3) -> void:
	if not error.is_finite():
		return
	_view_error += error
	var limit: float = session.get_settings().prediction_snap_metres
	if _view_error.length() > limit:
		_view_error = _view_error.normalized() * limit
	controller.view_offset = _view_error


func _decay_view_error(delta: float) -> void:
	if _view_error == Vector3.ZERO:
		return
	var seconds: float = session.get_settings().prediction_smoothing_seconds
	if seconds <= 0.0 or _view_error.length() < _SMOOTHING_EPSILON:
		_view_error = Vector3.ZERO
	else:
		_view_error *= exp(-delta * _SMOOTHING_CONSTANTS / seconds)
	controller.view_offset = _view_error


## The unacknowledged tick at [param index], oldest first.
func _slot(index: int) -> PredictedTick:
	return _predicted[(_predicted_start + index) % PREDICTION_CAPACITY]


## Forget everything up to and including [param index].
func _drop_through(index: int) -> void:
	var dropped: int = index + 1
	_predicted_start = (_predicted_start + dropped) % PREDICTION_CAPACITY
	_predicted_count -= dropped


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
