class_name PlayerNetLink
extends Node

## Carries one seat's body across the wire: intent up to the authority, and the
## authoritative state back down through [NetReplicator].
##
## One of these sits beside one [PlayerController]. Which direction it pushes
## depends on where it is running, not on who owns the body:
##
## [b]On the authority[/b] (the listen server, or an offline bot run) the body
## simulates. Commands reach it through the owner's [CommandStream] when a client
## owns the seat, or through the local [member local_source] when the host or a bot does. Either way
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
## A client's own body runs each command as the host will decode it, then on a snapshot takes the host's
## exact [PredictedState] at [code]cmd_ack[/code] and replays the rest (Quake 3's playerState).
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

## A client took the authority's first state for this body: until then it neither simulates nor counts as placed.
signal placed()

## The authority took a command packet for this seat; [param seq] is its newest command.
## Authority-only: the seam for telemetry and input logging.
signal intent_received(peer_id: int, seq: int)

## This client numbered [param command] [param seq] and sent it; only a command with an edge in it.
signal command_sent(seq: int, command: MoveIntent)

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

## Unacknowledged commands the prediction buffer holds: as many as the outbox keeps, a second.
const PREDICTION_CAPACITY: int = CommandStream.RING
## Group of a body's child visuals the host's playout draws with its avatar (an armor shell).
const DRAWN_WITH_BODY: StringName = &"drawn_with_body"

## Time constants spent inside [member NetSettings.prediction_smoothing_seconds],
## so a correction is 95% drawn away by the time that setting names.
const _SMOOTHING_CONSTANTS: float = 3.0

## Below this, in metres, a view offset is finished rather than chased.
const _SMOOTHING_EPSILON: float = 0.001



## One unacknowledged command, as it was run, and where it left the body.
class PredictedTick extends RefCounted:
	var seq: int = 0
	var intent: MoveIntent = MoveIntent.new()
	var position: Vector3 = Vector3.ZERO


## This tick's command, as sent; and its sequence, -1 before the world is heard.
var _command: MoveIntent = MoveIntent.new()
var _command_seq: int = -1
var _command_frame: int = -1
## This machine's own view: yaw before [member PlayerController.view_base], and pitch.
var _view: Vector2 = Vector2.ZERO

## True when this machine is a client simulating its own body. Latched with the
## rest of the role in [method refresh_role].
var _predicting: bool = false

## The ring of unacknowledged ticks, oldest first. Allocated once; the entries
## are written over rather than replaced.
var _predicted: Array[PredictedTick] = []
var _predicted_start: int = 0
var _predicted_count: int = 0

## The newest snapshot of this body, waiting for the next physics tick to be reconciled against:
## a snapshot lands on an idle frame and a replay runs physics.
var _pending_state: PlayerState = PlayerState.new()
var _pending_owner: PredictedState = PredictedState.new()
var _pending_ack: int = -1
var _has_pending_state: bool = false

## Prediction error still to be drawn away, in world metres. See
## [member PlayerController.view_offset].
var _view_error: Vector3 = Vector3.ZERO

## The avatar the host draws from its samples instead of at the body, where it sits on it, and
## where the body is drawn.
var _avatar: Node3D = null
var _avatar_rest: Transform3D = Transform3D.IDENTITY
var _drawn_at: Vector3 = Vector3.ZERO
## Body-child visuals drawn with the avatar (Node3D to its transform on the body).
var _drawn_rest: Dictionary = {}

## True if this machine simulates. Latched at [method refresh_role] rather than
## queried per tick, so a session state change cannot flip the role halfway
## through a frame.
var _is_authority: bool = false

## True once the authority's state for this body has landed on this machine; the authority places its own.
var _placed: bool = false

## How many times this body has jumped. An edge has no state to read back off
## the controller, so it is counted off the signal; the count goes out and is
## never cleared, which is what lets a mirror notice a jump whose snapshot was
## dropped. See [member PlayerState.jump_counter].
var _jump_counter: int = 0

## The newest snapshot tick whose EDGES have been replayed on this body, or -1
## before the first. Interpolation hands [method apply_state] the same snapshot
## every drawn frame; the events inside it must fire once.
var _event_tick: int = -1
var _was_on_floor: bool = true
var _was_sliding: bool = false

## The jump count last replayed on a mirrored body. See
## [member PlayerState.jump_counter].
var _seen_jumps: int = 0

## Shove swings this body has made; sampled into the snapshot as the jump counter is.
var _shove_counter: int = 0
var _seen_shoves: int = 0

## Links by the instance id of the body they carry: a link sits under [NetMatch], not its body.
static var _by_body: Dictionary[int, PlayerNetLink] = {}


## The link carrying [param body], or null when nothing replicates it.
static func of(body: Node) -> PlayerNetLink:
	if body == null:
		return null
	var link: PlayerNetLink = _by_body.get(body.get_instance_id(), null)
	return link if is_instance_valid(link) and link.controller == body else null

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
	_avatar = controller.get_node_or_null(^"Avatar") as Node3D
	if replicator != null:
		replicator.register(self)
	session.connection_state_changed.connect(_on_connection_state_changed)
	controller.jumped.connect(func() -> void: _jump_counter += 1)
	controller.shoved.connect(func() -> void: _shove_counter += 1)
	_by_body[controller.get_instance_id()] = self
	refresh_role()


func _exit_tree() -> void:
	# A scene change leaves this link detached but alive, and the engine still routes RPCs to it;
	# out of the tree it has no multiplayer to answer them with, so it simulates nothing.
	_is_authority = false
	if local_source != null and local_source.shape == Callable(self, &"_shape_command"):
		local_source.shape = Callable()
	if controller != null and _by_body.get(controller.get_instance_id(), null) == self:
		_by_body.erase(controller.get_instance_id())
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
		and _placed
		and _owns_locally()
		and local_source != null
		and session.get_settings().predict_local_body
	)
	controller.net_predicted = _predicting
	if _owns_locally() and local_source != null and replicator != null:
		# This machine's commands carry the time it draws the others at: what its shots rewind to.
		local_source.view_clock = replicator.get_view_time
		# A client's are the host's to run: its body runs each exactly as the host will.
		local_source.shape = _shape_command if not _is_authority else Callable()
	if not _is_authority and not _predicting:
		# Somebody else's body on a client owns no simulation: the snapshots move it.
		if not _owns_locally():
			controller.intent_source = null
		controller.set_physics_process(false)
		reset_prediction()
		return
	if _predicting:
		# This machine's own body on a client runs exactly the commands it sends.
		reset_prediction()
		_take_own_footing()
	if _owns_locally():
		controller.intent_source = local_source
	elif replicator != null:
		controller.intent_source = replicator.stream_for(owner_peer_id)
	# The body runs its commands here; whether they move it is the match's (held).
	controller.set_physics_process(true)
	if controller.intent_source != null:
		# A source swapped in after the body's ready has to be configured here.
		controller.intent_source.configure(controller.profile)


func _physics_process(delta: float) -> void:
	if _is_authority or session == null or controller == null or not _owns_locally():
		return
	if local_source == null or not session.is_established():
		return
	if is_predicting() and controller.net_floor >= 0:
		# Mirrored while it was held. Its own physics answers for it again.
		_take_own_footing()
	if _command_frame != Engine.get_physics_frames():
		# The body did not run this tick (unplaced, or mirrored): its command is still sent.
		local_source.next_command(delta)
	if _command_seq >= 0:
		replicator.send_commands()
	if _command_seq >= 0 and is_predicting():
		_record(_command_seq)
	else:
		reset_prediction()
	if _has_pending_state:
		_has_pending_state = false
		if is_predicting():
			_reconcile(delta)
	_decay_view_error(delta)


## True when this body should appear in snapshots. A link whose controller has
## been freed out from under it is not an error -- the match parks and rebuilds
## bodies between rounds -- it simply has nothing to describe.
func is_replicable() -> bool:
	return controller != null and controller.is_inside_tree()


## True when this machine is a client simulating this body ahead of the
## authority. The replicator asks, because a predicted body must not also be
## interpolated.
##
## A held one too: the hold rides its owner block, and a held body runs its commands and moves nothing.
func is_predicting() -> bool:
	return _predicting and controller != null


## True when this machine's own player drives this body: not a bot's seat, and not another peer's.
func is_owned_here() -> bool:
	return owner_peer_id != 0 and session != null and owner_peer_id == session.get_local_peer_id()


## Host: draw this body's avatar and the visuals in [constant DRAWN_WITH_BODY] at [param at]
## instead of at the body ([param playout]), or give them back. The collider never moves for it.
func draw_avatar_at(at: Transform3D, playout: bool = true) -> void:
	if _avatar == null:
		return
	if not playout:
		if _avatar.top_level:
			_avatar.top_level = false
			_avatar.transform = _avatar_rest
		for node: Variant in _drawn_rest.keys():
			if is_instance_valid(node):
				(node as Node3D).top_level = false
				(node as Node3D).transform = _drawn_rest[node]
		_drawn_rest.clear()
		return
	if not _avatar.top_level:
		_avatar_rest = _avatar.transform
		_avatar.top_level = true
	_avatar.global_transform = at * _avatar_rest
	_drawn_at = at.origin
	for node: Variant in _drawn_rest.keys():
		if not is_instance_valid(node):
			_drawn_rest.erase(node)
	for child: Node in controller.get_children():
		var visual: Node3D = child as Node3D
		if visual == null or not visual.is_in_group(DRAWN_WITH_BODY):
			continue
		if not _drawn_rest.has(visual):
			_drawn_rest[visual] = visual.transform
			visual.top_level = true
		visual.global_transform = at * (_drawn_rest[visual] as Transform3D)


## How far from the body this machine draws it: the host's playout lag, zero elsewhere.
func drawn_offset() -> Vector3:
	return drawn_position() - controller.global_position


## Where this machine draws the body: on the host, where its playout has it; elsewhere, the body.
func drawn_position() -> Vector3:
	return _drawn_at if _avatar != null and _avatar.top_level else controller.global_position


## Let the body answer for its own footing and pose again, rather than the last
## snapshot that was put on it.
func _take_own_footing() -> void:
	controller.net_floor = -1
	controller.net_slide = -1
	controller.net_crouch = -1
	controller.net_emote = -1


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


## Read this body's record at host tick [param tick] into [param out]. Called by [NetReplicator]
## on the authority, after the physics tick; the codec snaps it to wire precision.
func sample_state(out: PlayerState, tick: int) -> void:
	out.seat_index = seat_index
	out.position = controller.global_position
	out.velocity = controller.velocity
	out.yaw = controller.rotation.y
	out.pitch = controller.head.rotation.x if controller.head != null else 0.0
	out.view_base = controller.view_base
	out.on_floor = controller.is_on_floor()
	out.sliding = controller.is_sliding()
	out.crouching = controller.is_crouching()
	out.emoting = controller.is_emoting()
	out.emote_alt = controller.is_emote_alt()
	out.is_armed = controller.is_armed
	out.jump_counter = _jump_counter
	out.shove_counter = _shove_counter
	out.placed_counter = controller.placed_counter
	if controller.power != null:
		controller.power.state.sample(out, tick)
	out.boost_multiplier = controller.get_speed_boost_multiplier()
	out.boost_end_tick = NetCodec.end_tick(tick, controller.get_speed_boost_remaining())
	var weapon: Rifle = _weapon()
	if weapon != null:
		out.weapon_state = int(weapon.get_state())
		out.weapon_scoped = weapon.optic != null and weapon.optic.is_zoom_requested()
		out.weapon_end_tick = NetCodec.end_tick(tick, weapon.get_time_to_ready())
		out.weapon_charge = roundi(weapon.get_charge() * 255.0)
	var participant: MatchParticipant = _participant()
	out.is_finisher = participant.is_finisher if participant != null else false
	out.health = participant.health if participant != null else 0


## This body's exact predicted state, for the owner block its client restores. Authority-only.
func sample_predicted(out: PredictedState) -> void:
	out.capture(controller, _weapon())


## The rifle this body holds, or null.
func _weapon() -> Rifle:
	if match_controller == null or match_controller.rifle == null:
		return null
	return match_controller.rifle if match_controller.rifle.shooter_body == controller else null


## A drawn record onto a mirrored body, once per frame: transform, velocity, footing and poses its
## avatar picks clips off (no physics runs for it); the power drawn, never run.
func apply_state(state: PlayerState) -> void:
	if controller == null:
		return
	_apply_presentation(state)
	controller.global_position = state.position
	controller.rotation.y = state.yaw
	controller.velocity = state.velocity
	controller.view_base = state.view_base
	controller.net_floor = 1 if state.on_floor else 0
	controller.net_slide = 1 if state.sliding else 0
	controller.net_crouch = 1 if state.crouching else 0
	controller.net_emote = (2 if state.emote_alt else 1) if state.emoting else 0
	controller.set_speed_boost(state.boost_multiplier, state.boost_remaining())
	if controller.head != null:
		controller.head.rotation.x = state.pitch
	_present_events(state)
	if not _placed:
		_placed = true
		refresh_role()
		placed.emit()


## What the host's record says of this predicting body that it does not predict itself: the entity its
## power put in the world. Called at the playout clock, as for any remote entity.
func apply_anchor(state: PlayerState) -> void:
	if controller != null and controller.power != null:
		controller.power.take_entity_record(state)


## The half of a record that is drawn rather than simulated: the power, the rifle and the
## participant's own facts. A predicting body restores its power from the owner block instead.
func _apply_presentation(state: PlayerState, predicted: bool = false) -> void:
	if controller.power != null and not predicted:
		controller.power.take_record(state)
	controller.is_armed = state.is_armed
	var weapon: Rifle = _weapon()
	if weapon != null and not predicted:
		weapon.present_record(state.weapon_state as Rifle.State, state.seconds_to(state.weapon_end_tick), float(state.weapon_charge) / 255.0)
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
		_seen_jumps = state.jump_counter
		_seen_shoves = state.shove_counter
		return
	# Once per jump the counter has advanced by, not once per snapshot that
	# mentions one: a dropped snapshot is a jump this body still made.
	var jumps: int = posmod(state.jump_counter - _seen_jumps, NetCodec.JUMP_COUNTER_MODULUS)
	_seen_jumps = state.jump_counter
	for _i: int in jumps:
		controller.jumped.emit()
	_present_swings(state.shove_counter)
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


## A predicting body heard its own jumps, landings, slides and swings as it made them (its swing
## gate draws them): the mirror's memory moves past them, so none is replayed when it is held.
func _pass_own_events(state: PlayerState) -> void:
	_event_tick = state.tick
	_was_on_floor = state.on_floor
	_was_sliding = state.sliding
	_seen_jumps = state.jump_counter
	_seen_shoves = state.shove_counter


## Draw the swings the authority's counter has advanced by on a mirrored body.
func _present_swings(counter: int) -> void:
	var swings: int = posmod(counter - _seen_shoves, NetCodec.SHOVE_COUNTER_MODULUS)
	_seen_shoves = counter
	for _i: int in swings:
		controller.shoved.emit()


## This body's participant, or null before the match has built them.
func _participant() -> MatchParticipant:
	if match_controller == null or controller == null:
		return null
	return match_controller.resolve_participant(controller)


# --- Sending ------------------------------------------------------------------

## The device's [param command] as sent: view absolute, quantised as the host decodes it, numbered
## (none before this scene's world is heard, as Quake 3 sends no usercmd before its first snapshot).
func _shape_command(command: MoveIntent) -> MoveIntent:
	_view = command.view_angles if command.view_absolute else controller.turned_view(_view, command.look_delta)
	_command.copy_from(command)
	_command.view_angles = _view
	NetCodec.quantise_command(_command)
	_command_frame = Engine.get_physics_frames()
	if replicator.get_latest_tick() < 0:
		# The host's stream will start at a later command and take its edges against nothing.
		local_source.rebase_edges()
		_command_seq = -1
	else:
		_command_seq = replicator.outbox.push(_command)
		replicator.collide_props_at(replicator.tick_of_command(_command_seq))
		if _command.pressed | _command.released != 0:
			command_sent.emit(_command_seq, _command)
	return _command


# --- Prediction ---------------------------------------------------------------

## The host's record, exact predicted state ([param owner]) and newest command run ([param cmd_ack]),
## held for the next physics tick: a snapshot lands on an idle frame and a replay runs physics.
func receive_authoritative(state: PlayerState, owner: PredictedState, cmd_ack: int) -> void:
	if owner == null:
		return
	_pending_state.copy_from(state)
	_pending_owner.copy_from(owner)
	_pending_ack = cmd_ack
	_has_pending_state = true


## Keep command [param seq] as the body ran it, and where it left the body.
func _record(seq: int) -> void:
	if _predicted.is_empty():
		_predicted.resize(PREDICTION_CAPACITY)
		for i: int in PREDICTION_CAPACITY:
			_predicted[i] = PredictedTick.new()
	if _predicted_count >= PREDICTION_CAPACITY:
		# Nothing acknowledged for a second: the oldest goes, the one the host has most likely passed.
		_predicted_start = (_predicted_start + 1) % PREDICTION_CAPACITY
		_predicted_count -= 1
	var entry: PredictedTick = _slot(_predicted_count)
	_predicted_count += 1
	entry.seq = seq
	entry.intent.copy_from(_command)
	entry.position = controller.global_position


## Restore the host's exact state at its acknowledgement and replay every command after it (DESIGN
## 7); the difference from what was predicted is drawn away, or jumped when it is too large.
func _reconcile(delta: float) -> void:
	_apply_presentation(_pending_state, true)
	_pass_own_events(_pending_state)
	var acked: int = _pending_ack
	var first: int = _first_unacknowledged(acked) if acked >= 0 else 0
	var missed: float = 0.0
	var compared: bool = first > 0 and _slot(first - 1).seq == acked
	if compared:
		missed = _pending_owner.get_position().distance_to(_slot(first - 1).position)
	var snapped: bool = missed > session.get_settings().prediction_snap_metres
	if compared:
		prediction_corrected.emit(missed, snapped)
	var before: Vector3 = controller.global_position
	var weapon: Rifle = _weapon()
	_pending_owner.restore(controller, weapon)
	# What the replay moves says nothing: its reload and power cues were heard the first time.
	var quiet: Array[Object] = [weapon, controller.power]
	var was_blocked: Array[bool] = []
	for node: Object in quiet:
		was_blocked.append(node != null and node.is_blocking_signals())
		if node != null:
			node.set_block_signals(true)
	for i: int in range(first, _predicted_count):
		replicator.collide_props_at(replicator.tick_of_command(_slot(i).seq))
		controller.simulate_tick(_slot(i).intent, delta)
		_slot(i).position = controller.global_position
	replicator.collide_props_at(-1)
	for j: int in quiet.size():
		if quiet[j] != null:
			quiet[j].set_block_signals(was_blocked[j])
	if first > 0:
		_drop_through(first - 1)
	if snapped:
		# Something no prediction could know -- a launch, a shove, a respawn: the view goes with the body.
		_view_error = Vector3.ZERO
		controller.view_offset = Vector3.ZERO
		return
	_add_view_error(before - controller.global_position)


## The first tick held that the authority has not acknowledged, as an index into
## the buffer. Equal to the count when it has acknowledged them all.
func _first_unacknowledged(acked: int) -> int:
	for i: int in _predicted_count:
		if NetCodec.is_newer_tick(_slot(i).seq, acked):
			return i
	return _predicted_count


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

## The scene epoch this body's packets are stamped with and checked against.
func _epoch() -> int:
	return replicator.get_scene() if replicator != null else 0


## True when this machine's own input drives this body.
##
## Zero means nobody remote does, which on the authority means this machine
## does -- that is a bot's seat, and the host's own seat when offline.
func _owns_locally() -> bool:
	if owner_peer_id == 0:
		return true
	return owner_peer_id == session.get_local_peer_id()


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
