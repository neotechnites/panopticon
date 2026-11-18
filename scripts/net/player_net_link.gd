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
## A client's own body runs the same [PlayerController] physics off the same
## [MoveIntent] on the tick the key goes down, so movement costs no round trip.
## Every command is kept -- as run, and the body it produced -- until a
## snapshot says the authority has run it: see
## [member PlayerState.cmd_ack]. On a snapshot the body is rewound to
## the authority's state at the command it acknowledges, every command since is
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

## How far a predicted boost timer may sit from the authority's before it is replaced: the wire's tenth.
const _BOOST_TOLERANCE_SECONDS: float = 0.11


## One unacknowledged command: as the body ran it, and the body it produced.
class PredictedTick extends RefCounted:
	var seq: int = 0
	var intent: MoveIntent = MoveIntent.new()
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var motion: PackedFloat32Array = PackedFloat32Array()
	## Whether the body ended this tick held by its armor lock.
	var locked: bool = false


## Reused per tick so the send path does not allocate.
var _scratch_intent: MoveIntent = MoveIntent.new()
## The authority's [member PlayerController.view_base] for this body, off its snapshots.
var _view_base: float = 0.0
## A client's own view (yaw less [member _view_base], pitch) when it is not predicting.
var _view: Vector2 = Vector2.ZERO

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
## The power this client last predicted, and the command it changed on: the
## authority's word on it waits until that command is acknowledged.
var _predicted_power: int = 0
var _power_seq: int = -1

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
	if not _is_authority and not _predicting:
		# Somebody else's body on a client owns no simulation. Leaving its
		# physics running would fight every snapshot that arrives. Our own unplaced body keeps its source.
		if not _owns_locally():
			controller.intent_source = null
		controller.set_physics_process(false)
		reset_prediction()
		_view = controller.get_view_angles()
		return

	if _predicting:
		# This machine's own body on a client. It runs the real physics off the
		# real input, so it reads its own footing rather than the snapshot's.
		reset_prediction()
		# The view sent carries on unbroken: a facing this machine gave the body is the base's, not the player's.
		_view_base = wrapf(controller.rotation.y - _view.x, -PI, PI)
		_take_own_footing()

	# The body runs its commands here; whether they move it is the match's (held).
	controller.set_physics_process(true)
	if _owns_locally():
		controller.intent_source = local_source
	elif replicator != null:
		controller.intent_source = replicator.stream_for(owner_peer_id)

	if controller.intent_source != null:
		# PlayerController configures its source once, at its own _ready. A
		# source swapped in afterwards has to be configured here or it has no
		# profile and reports nothing.
		controller.intent_source.configure(controller.profile)


func _physics_process(delta: float) -> void:
	if _is_authority or session == null or controller == null or not _owns_locally():
		return
	if local_source == null or not session.is_established():
		return
	if is_predicting() and controller.net_floor >= 0:
		# Mirrored while it was held. Its own physics answers for it again.
		_take_own_footing()
	var seq: int = _send_commands(delta)
	if seq >= 0 and is_predicting():
		# The body has already run this command: keep what it did, then take whatever answer
		# arrived since and put the body right.
		_record(seq)
		_note_predicted_power(seq)
	else:
		# Unplaced, or held by the match: nothing to predict, and the replicator mirrors it.
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
## Not while the match holds it: a held body is a mirrored one until the match lets it go.
func is_predicting() -> bool:
	return _predicting and controller != null and not controller.held


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


## Read this body's current state into [param out]. Called by [NetReplicator]
## on the authority, after the physics tick.
func sample_state(out: PlayerState) -> void:
	out.seat_index = seat_index
	out.position = controller.global_position
	out.velocity = controller.velocity
	out.yaw = controller.rotation.y
	out.pitch = controller.head.rotation.x if controller.head != null else 0.0
	out.view_base = controller.view_base
	out.on_floor = controller.is_on_floor()
	var power: RunnerPower = RunnerPower.of(controller)
	out.ability = int(power.get_active()) if power != null else 0
	out.ability_remaining = power.get_remaining() if power != null else 0.0
	out.cooldown_remaining = power.get_cooldown_remaining() if power != null else 0.0
	out.is_armed = controller.is_armed
	out.sliding = controller.is_sliding()
	out.crouching = controller.is_crouching()
	out.emoting = controller.is_emoting()
	out.emote_alt = controller.is_emote_alt()
	out.jump_counter = _jump_counter
	out.shove_counter = _shove_counter
	out.boost_remaining = controller.get_speed_boost_remaining()
	out.boost_multiplier = controller.get_speed_boost_multiplier()
	# What the owner of this seat may rewind to: the last command of theirs this body has run,
	# not merely received. Nothing to say for a bot's seat or the host's own.
	out.cmd_ack = (
		replicator.stream_for(owner_peer_id).get_ack()
		if replicator != null and owner_peer_id != 0 and not _owns_locally() else -1
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
	_view_base = state.view_base
	controller.net_floor = 1 if state.on_floor else 0
	controller.net_slide = 1 if state.sliding else 0
	controller.net_crouch = 1 if state.crouching else 0
	controller.net_emote = (2 if state.emote_alt else 1) if state.emoting else 0
	controller.set_speed_boost(state.boost_multiplier, state.boost_remaining)
	if controller.head != null:
		controller.head.rotation.x = state.pitch
	_present_events(state)
	if not _placed:
		_placed = true
		refresh_role()
		placed.emit()


## The half of a state that is drawn rather than simulated: the power, the
## rifle and the participant's own facts. A predicted body takes this and moves
## itself; a mirrored one takes this and the transform with it.
func _apply_presentation(state: PlayerState, predicted: bool = false) -> void:
	var power: RunnerPower = RunnerPower.of(controller)
	if power != null and not predicted:
		power.present(
			state.ability as MatchRules.RunnerAbility,
			state.ability_remaining,
			state.cooldown_remaining,
		)
	elif power != null and not _power_unacknowledged(state.cmd_ack):
		power.reconcile(
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

## Number this tick's command and send every one the host has not run. A predicting body has
## already run it; an unplaced one has not, so its device is read here. Returns the sequence, or
## -1 before this scene's world has been heard: a command is input to the host's world (Quake 3
## sends none before its first snapshot), so one made before the host runs the scene is not sent.
func _send_commands(delta: float) -> int:
	var command: MoveIntent
	if controller.is_physics_processing():
		command = controller.get_intent()
		var view: Vector2 = controller.get_view_angles()
		_view = Vector2(wrapf(view.x - _view_base, -PI, PI), view.y)
	else:
		command = local_source.next_command(delta)
		_view = controller.turned_view(_view, command.look_delta)
	_scratch_intent.copy_from(command)
	# The view goes as absolute angles, Quake's usercmd: a lost packet costs no aim.
	_scratch_intent.view_angles = _view
	_scratch_intent.view_absolute = true
	_scratch_intent.look_delta = Vector2.ZERO
	if replicator.get_latest_tick() < 0:
		# The host's stream will start at a later command and take its edges against nothing.
		local_source.rebase_edges()
		return -1
	var seq: int = replicator.outbox.push(_scratch_intent)
	if _scratch_intent.pressed | _scratch_intent.released != 0:
		command_sent.emit(seq, _scratch_intent)
	replicator.send_commands()
	return seq


# --- Prediction ---------------------------------------------------------------

## Take the authority's state for this body. Called by [NetReplicator] on a
## client in place of [method apply_state] while this link is predicting.
##
## Held rather than applied: a snapshot lands on an idle frame and putting the
## body right runs physics, so it waits for the next physics tick.
func receive_authoritative(state: PlayerState) -> void:
	_pending_state.copy_from(state)
	_has_pending_state = true


## Mark the command this client's own power started or stopped on, if it did.
func _note_predicted_power(seq: int) -> void:
	var power: RunnerPower = RunnerPower.of(controller)
	var active: int = int(power.get_active()) if power != null else 0
	if active != _predicted_power:
		_predicted_power = active
		_power_seq = seq


## True while the authority has not yet run the command that changed this power.
func _power_unacknowledged(acked: int) -> bool:
	return _power_seq >= 0 and (acked < 0 or NetCodec.is_newer_tick(_power_seq, acked))


## Keep command [param seq]: as the body ran it, and where it ended up.
func _record(seq: int) -> void:
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
	entry.seq = seq
	entry.intent.copy_from(controller.get_intent())
	_write_result(entry)


## Where the body is now, into [param entry].
func _write_result(entry: PredictedTick) -> void:
	entry.position = controller.global_position
	entry.velocity = controller.velocity
	entry.yaw = controller.rotation.y
	controller.capture_motion_state(entry.motion)
	entry.locked = controller.movement_locked


## Rewind to the authority's state, replay what it has not seen, and hand the
## difference to the view.
##
## The POSITION rewound to is the authority's; the AIM is this machine's own,
## the view it sends, turned by whatever facing the match has set since.
func _reconcile(delta: float) -> void:
	_apply_presentation(_pending_state, true)
	_pass_own_events(_pending_state)
	var rebase: float = angle_difference(_view_base, _pending_state.view_base)
	if rebase != 0.0:
		_view_base = _pending_state.view_base
		controller.rotation.y = wrapf(controller.rotation.y + rebase, -PI, PI)
		# Every yaw held was turned in the old base; one acknowledged later must not undo the turn.
		for i: int in _predicted_count:
			var held: PredictedTick = _slot(i)
			held.yaw = wrapf(held.yaw + rebase, -PI, PI)
	var acked: int = _pending_state.cmd_ack
	if acked < 0:
		# The authority has run none of this client's input yet. There is
		# nothing to rewind to and nothing to replay.
		_snap_to(_pending_state)
		prediction_corrected.emit(0.0, true)
		return

	var first: int = _first_unacknowledged(acked)
	if first == 0:
		# Every tick held is newer than the acknowledgement: the wake of a
		# buffer that was thrown away -- a respawn, or one of the two hard snaps
		# above -- while the authority is still answering for input from before
		# it. Nothing here maps onto anything kept, so it is left alone and
		# reconciliation resumes once the acknowledgements catch the buffer up.
		return
	var index: int = first - 1
	var predicted: PredictedTick = _slot(index)
	if predicted.seq != acked:
		# A tick was acknowledged that this buffer straddles but does not hold.
		_snap_to(_pending_state)
		prediction_corrected.emit(0.0, true)
		return

	var missed: float = _pending_state.position.distance_to(predicted.position)
	var snapped: bool = missed > session.get_settings().prediction_snap_metres
	prediction_corrected.emit(missed, snapped)

	var before: Vector3 = controller.global_position
	controller.global_position = _pending_state.position
	controller.velocity = _pending_state.velocity
	controller.rotation.y = predicted.yaw
	controller.restore_motion_state(predicted.motion)
	# What no input of this machine's decides is the authority's as of that tick: whether the
	# emote is up and the boost it handed out. The replay below carries both forward.
	controller.set_emote_state(_pending_state.emoting, _pending_state.emote_alt)
	controller.set_speed_boost(
		_pending_state.boost_multiplier, _pending_state.boost_remaining, _BOOST_TOLERANCE_SECONDS
	)
	# An armor lock that began or ended inside the window is replayed tick by tick as it was
	# predicted; one the authority has answered for holds, or not, across the whole window.
	var locked_now: bool = controller.movement_locked
	var replay_lock: bool = _power_unacknowledged(acked)
	if replay_lock:
		controller.movement_locked = predicted.locked
	# The replayed ticks are this body's own past. Their signals were heard when
	# they happened; heard again they would fire the last hundred milliseconds
	# of footsteps, jumps and landings a second time.
	controller.set_block_signals(true)
	for i: int in range(index + 1, _predicted_count):
		var entry: PredictedTick = _slot(i)
		controller.simulate_tick(entry.intent, delta)
		if replay_lock:
			if entry.locked and not controller.movement_locked:
				controller.velocity = Vector3.ZERO
			controller.movement_locked = entry.locked
		_write_result(entry)
	controller.movement_locked = locked_now
	controller.set_block_signals(false)

	_drop_through(index)
	if snapped:
		# An event the client could not have predicted -- a launch, a shove, a
		# kill, a respawn. The BODY still replays: the player's last round trip
		# of running and turning is theirs and throwing it away is a worse lie
		# than any pop. What a snap changes is the VIEW, which goes with the
		# body at once instead of drifting onto it, because drawing a launch as
		# a graceful slide is a lie about where the body is.
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


## Take the authority's state whole, for a correction no replay can be based on:
## a body the authority has run no input for yet, or an acknowledgement this
## buffer straddles but does not hold. A correction that is merely LARGE is not
## one of these -- see [method _reconcile].
func _snap_to(state: PlayerState) -> void:
	# The view stays the player's own, already turned by any facing the match set.
	reset_prediction()
	controller.global_position = state.position
	controller.velocity = state.velocity


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
