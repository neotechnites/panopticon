class_name NetReplicator
extends Node

## The per-tick traffic: one world snapshot down from the authority, at a rate
## it chooses, and the playback that turns it back into moving bodies.
##
## [b]One packet, not one per body[/b]
##
## Every [PlayerNetLink] in the session registers here, and this node sends
## [b]one[/b] [WorldSnapshot] describing all of them. A body that sent its own
## state would multiply the RPC header by the player count and, worse, would
## let a client draw a frame stitched together from bodies sampled at
## different ticks. See [WorldSnapshot].
##
## Commands come up through here too: [member outbox] numbers a client's and packs every one the
## host has not run, and on the host each peer's [CommandStream] runs its seat's (DESIGN 3.2, 3.3).
##
## [b]The rate is not the simulation rate[/b]
##
## The authority simulates at 60 Hz and sends at
## [member NetSettings.snapshot_hz], which ships at 30. That number's full
## reasoning is on the field; the short version is that it halves the host's
## upstream, costs 33 ms of staleness on remote bodies, and cannot affect
## whether a shot hits, because shots are resolved on the authority against the
## authority's own 60 Hz bodies.
##
## [b]How a client plays a snapshot back[/b]
##
## Two ways, and which one a body gets is the whole of it. SOMEBODY ELSE'S body
## is INTERPOLATED out of a buffer of recent snapshots by a PLAYOUT CLOCK. THIS
## machine's own body is PREDICTED -- it is never touched here beyond being
## handed the snapshot, because it has already simulated itself and rewinds
## against the correction on its own. See [PlayerNetLink].
##
## [b]The playout clock[/b]
##
## The client keeps its own position in the authority's tick stream and advances
## it with the frame, rather than restarting a slide every time a packet lands.
## That distinction is the whole of jitter tolerance: a reset-on-arrival slide
## draws a body fast when a packet is early and freezes it when a packet is
## late, which is exactly the hitch a jittery line produces, and it produces it
## whether or not any packet was actually lost.
##
## The clock is held [member NetSettings.interpolation_delay_ticks] behind the
## newest snapshot, plus twice the jitter the client has MEASURED on this
## connection, up to
## [member NetSettings.max_interpolation_jitter_ticks]. A LAN pays the floor; a
## tethered phone pays what its own line costs. Drift is taken out by running
## playback a few per cent fast or slow rather than by jumping, so the
## correction is never a frame anybody sees.
##
## Past the newest snapshot the bodies EXTRAPOLATE along their last velocity for
## at most [member NetSettings.max_extrapolation_seconds], then hold. A body
## that keeps running and is corrected reads as a body that kept running; a body
## that freezes and teleports reads as a broken game.
##
## [b]Lag compensation[/b] (Source's): the authority keeps every body's position for
## [constant HISTORY_TICKS] ticks; a shot is traced against the others where they stood on the tick
## its command says the shooter was drawing ([method trace]). The host draws every body but its own
## [constant HOST_PLAYOUT_TICKS] behind out of its own samples, so its shots rewind like a client's.
##
## What is still missing:
##
## - [b]No delta compression and no interest management.[/b] Every field of
##   every body goes every snapshot to everybody, quantised but not differenced.
##   Cheap at eight players; not a habit to keep.
## - [b]Bodies and holograms only.[/b] Weapon fire, hits, the round result and
##   who holds the tower are not replicated by this file.

## The authority sent a snapshot. Authority-only, for telemetry.
signal snapshot_sent(tick: int, body_count: int)

## A client applied a snapshot. Client-only. Fires on receipt, not on each
## interpolated frame.
signal snapshot_received(tick: int, body_count: int)

## How far a hologram must have moved since the last transform went out before
## another one does. A decoy that has run into a wall stops costing bandwidth.
const DECOY_MOVED_METRES: float = 0.001
const DECOY_TURNED_RADIANS: float = 0.001


## One seat's hologram on the authority: which body is being streamed, which
## spawn it is, and what was last sent for it.
class DecoyTrack:
	extends RefCounted

	var decoy: PlayerController = null
	var epoch: int = 0
	var position: Vector3 = Vector3.ZERO
	var yaw: float = 0.0


## The session this replicator belongs to.
@export var session: NetSession

## Bodies to replicate, keyed by [member PlayerNetLink.seat_index]. Registered
## by the links themselves at ready; see [method register].
var _links: Array[PlayerNetLink] = []

## The authority's tick count. Simulation ticks, not snapshots -- what is
## stamped on a snapshot is when it was SAMPLED, so a client can tell a
## snapshot that is one interval old from one that is five.
var _tick: int = 0

## Simulated seconds since the last snapshot was sent. Authority-only.
var _send_accumulator: float = 0.0

## Snapshots a client holds to draw between, oldest first. Client-only.
##
## Twelve at 30 Hz is four hundred milliseconds of history, which is more than
## the jitter buffer will ever be allowed to ask for and enough that a burst of
## reordering has something to land in.
const PLAYBACK_CAPACITY: int = 12
var _playback: Array[WorldSnapshot] = []
var _playback_start: int = 0
var _playback_count: int = 0

## How far behind the newest snapshot the playout clock is drawing, in authority
## ticks. Negative means extrapolating past it.
##
## Held relative to the newest tick rather than as an absolute tick so that the
## 32-bit wrap is somebody else's problem: every quantity here is a small
## difference, and differences are what [method NetCodec.tick_delta] makes safe.
var _render_lag: float = 0.0
var _have_clock: bool = false

## The client's own playback clock in seconds, and when a snapshot last arrived
## on it. Simulated seconds, not wall clock: it has to be the same clock the
## frames are drawn against or the jitter it measures is the test runner's.
var _clock_seconds: float = 0.0
var _last_arrival_seconds: float = -1.0

## Measured irregularity of snapshot arrival, in seconds, and the measured gap
## between them in ticks. Both smoothed; both drive the buffer depth.
var _jitter_seconds: float = 0.0
var _interval_ticks: float = 0.0

## Ticks the clock is held behind the newest snapshot. Recomputed per arrival.
var _delay_ticks: float = 2.0

## Authority ticks of body positions kept for lag compensation: Source's sv_maxunlag, one second.
const HISTORY_TICKS: int = 64
## How far behind its own tick the host draws other bodies: one sample interval, never extrapolated.
const HOST_PLAYOUT_TICKS: float = 2.0
## Position of seat s at the tick in slot i is _history[s * HISTORY_TICKS + i].
var _history: PackedVector3Array = PackedVector3Array()
var _history_ticks: PackedInt32Array = PackedInt32Array()
## The body's collision layer on that tick, in the same slot; 0 for a seat with no body in play.
var _history_layers: PackedInt32Array = PackedInt32Array()
## Where the bodies stood, for the ray of a shot traced in the past. Made by the first such shot.
var _rewind_space: RewindSpace = null

## Weight the jitter estimate gives a new sample.
const _JITTER_ALPHA: float = 0.1

## Playback speed change per tick of clock error, and the most of it allowed.
## Twenty per cent closes two ticks of drift in about a sixth of a second, which
## is under what a player can see and over what jitter can open in that time.
const _CLOCK_GAIN: float = 0.1
const _MAX_DILATION: float = 0.2

## Clock error past which the drift is jumped rather than dilated away. A third
## of a second: at that point the connection has changed, not drifted.
const _CLOCK_SNAP_TICKS: float = 20.0

## Reused so the send and receive paths allocate nothing per tick beyond the
## byte array the engine hands over.
var _outgoing: WorldSnapshot = WorldSnapshot.new()
var _incoming: WorldSnapshot = WorldSnapshot.new()
var _blend: PlayerState = PlayerState.new()
var _decoy_in: PlayerState = PlayerState.new()

## Holograms being streamed, keyed by seat. Authority-only.
var _decoy_tracks: Dictionary[int, DecoyTrack] = {}

## The spawn a client believes is live for a seat, keyed by seat. Client-only:
## it is what tells a transform overtaken by its own despawn from a live one.
var _decoy_epochs: Dictionary[int, int] = {}

## Spawn counter, wrapped at [constant NetCodec.DECOY_EPOCH_MODULUS].
var _decoy_epoch: int = 0

## The shield each seat was last told of, by its instance id. Authority-only.
var _shields_told: Dictionary[int, int] = {}

var _is_authority: bool = false

## Client: this machine's commands, numbered and kept until the host has run them.
var outbox: CommandStream.Outbox = CommandStream.Outbox.new()
## Host: each remote peer's commands, by peer id, and the same streams in a list for the tick.
var _streams: Dictionary[int, CommandStream] = {}
var _stream_list: Array[CommandStream] = []
var _last_command_packet: PackedByteArray = PackedByteArray()
## The tick (fractional) of the world this machine last drew other bodies at, or [constant MoveIntent.LIVE_WORLD].
var _drawn_time: float = MoveIntent.LIVE_WORLD

## The scene epoch this machine's bodies belong to ([method NetLobby.get_epoch]): stamped on what
## the authority sends, required of what a client takes and of every intent. 0 is none.
var _scene: int = 0


func _ready() -> void:
	if session == null:
		push_error("NetReplicator has no session; nothing will be replicated.")
		set_physics_process(false)
		set_process(false)
		return
	# After the bodies have moved, so what is sampled is the result of this
	# tick rather than the previous one's.
	process_physics_priority = 100
	session.connection_state_changed.connect(_on_connection_state_changed)
	refresh_role()


## Re-read the session. Called at ready and on every connection state change.
func refresh_role() -> void:
	if session == null:
		return
	_is_authority = session.is_authority()
	if _is_authority:
		_clear_playback()
	for link: PlayerNetLink in _links:
		link.refresh_role()


## Name the scene epoch whose bodies are registered: the authority once it has placed them, a
## client once it has loaded it. Whatever a client held from another scene is dropped.
func bind_scene(scene: int) -> void:
	if scene == _scene:
		return
	_scene = scene
	# Where the last scene's bodies stood is not where this one's did.
	_history_ticks.fill(-1)
	# A new scene runs no command of the last one's.
	for stream: CommandStream in _stream_list:
		stream.reset()
	outbox.flush()
	# The host's own samples feed its playout too: the last scene's are not this one's.
	_clear_playback()


# --- Registry -----------------------------------------------------------------

## Take responsibility for a body. Called by [PlayerNetLink] at its own ready,
## so the match layer wires one export and never touches this.
##
## Refuses a second link for the same seat: two bodies claiming seat 3 would
## put two entries in every snapshot and leave the receiving end to pick one,
## which it would do differently on different machines.
func register(link: PlayerNetLink) -> bool:
	if link == null or find_link(link.seat_index) != null:
		return false
	_links.append(link)
	_links.sort_custom(func(a: PlayerNetLink, b: PlayerNetLink) -> bool: return a.seat_index < b.seat_index)
	return true


## Stop replicating a body. Safe for one that was never registered, because the
## caller is usually a body being freed and it should not have to check.
func unregister(link: PlayerNetLink) -> void:
	var index: int = _links.find(link)
	if index != -1:
		_links.remove_at(index)
	_draw_live(link)


func find_link(seat_index: int) -> PlayerNetLink:
	for link: PlayerNetLink in _links:
		if link.seat_index == seat_index:
			return link
	return null


func get_link_count() -> int:
	return _links.size()


## Client to authority, every tick: every command of this machine's the host has not run yet.
func send_commands() -> void:
	_last_command_packet = outbox.pack(_scene, get_latest_tick())
	if not _last_command_packet.is_empty():
		rpc_id(NetTransport.AUTHORITY_PEER_ID, &"_receive_intent", _last_command_packet)


## The command packet this machine last sent, or an empty array before the first. For tests.
func get_last_command_packet() -> PackedByteArray:
	return _last_command_packet


## Taken here, not on the body's link: this node outlives every scene, and a scene that has gone has no link.
@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _receive_intent(payload: PackedByteArray) -> void:
	if not _is_authority:
		return
	take_commands(multiplayer.get_remote_sender_id(), payload)


## Take [param payload] from [param sender] as its seat's commands. The sender is the one check
## that stops a peer driving somebody else's body; a packet from another scene is dropped.
func take_commands(sender: int, payload: PackedByteArray) -> void:
	if _scene == 0 or NetCodec.command_epoch(payload) != _scene % NetCodec.EPOCH_MODULUS:
		return
	for link: PlayerNetLink in _links:
		if link.owner_peer_id == sender and sender != 0:
			var newest: int = stream_for(sender).receive(payload, _tick)
			if newest >= 0:
				link.intent_received.emit(sender, newest)
			return


## Host: [param peer_id]'s command stream, made the first time it is asked for.
func stream_for(peer_id: int) -> CommandStream:
	var stream: CommandStream = _streams.get(peer_id, null)
	if stream == null:
		stream = CommandStream.new()
		stream.name = "Commands%d" % peer_id
		add_child(stream)
		_streams[peer_id] = stream
		_stream_list.append(stream)
	var settings: NetSettings = session.get_settings()
	stream.stale_after_ticks = settings.stale_intent_ticks
	stream.cmd_budget = settings.cmd_budget
	return stream


## The bound scene epoch, or 0 when none is.
func get_scene() -> int:
	return _scene


## The authority's current tick. Stamped on outgoing snapshots and handed to
## [PlayerNetLink] so intent and state carry the same clock.
func get_tick() -> int:
	return _tick


## The authority tick of the newest snapshot a client has taken, or -1.
func get_latest_tick() -> int:
	return _newest().tick if _playback_count > 0 else -1


## How far behind the newest snapshot this client is drawing, in authority
## ticks, or -1 before the clock has started. The jitter buffer's depth, for the
## harness and for a debug overlay.
func get_render_lag_ticks() -> float:
	return _render_lag if _have_clock else -1.0


## The delay the jitter buffer has settled on, in authority ticks.
func get_delay_ticks() -> float:
	return _delay_ticks


## Measured irregularity of snapshot arrival on this connection, in seconds.
func get_jitter_seconds() -> float:
	return _jitter_seconds


# --- Sending ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _is_authority:
		_advance_clock(delta)
		return
	_tick += 1
	var wall: int = int(Time.get_ticks_usec() * Engine.physics_ticks_per_second / 1000000)
	for stream: CommandStream in _stream_list:
		stream.end_tick(wall)
	if session == null or not session.is_established() or session.get_peer_count() <= 1 or _scene == 0:
		# Offline -- single player, or the headless bot harness -- is
		# authoritative with nobody to tell. A lone host has the same shape.
		# The tick still advances: it is the authority's clock, not a counter of
		# packets sent.
		return
	_record_history()

	# Every tick, not at the snapshot rate: a hologram is a body the tower is
	# shooting at, and one drawn 33 ms behind is one a client's shot misses.
	_drive_decoys()
	_drive_shields()

	_send_accumulator += delta
	var interval: float = session.get_settings().get_snapshot_interval()
	if _send_accumulator < interval:
		return
	# Subtract rather than zero, so a 30 Hz send on a 60 Hz tick stays on 30 Hz
	# instead of drifting to 20 the first time a frame runs long.
	_send_accumulator = fmod(_send_accumulator, interval)
	_send_snapshot()


func _send_snapshot() -> void:
	_outgoing.clear()
	_outgoing.tick = _tick
	_outgoing.scene = _scene
	for link: PlayerNetLink in _links:
		if not link.is_replicable():
			continue
		var slot: PlayerState = _outgoing.next_slot()
		if slot == null:
			# More bodies than the session can hold. The lobby caps seats at
			# MAX_PLAYERS so this is unreachable through the game; it is here
			# because a truncated snapshot must not be sent silently.
			push_error("NetReplicator has more bodies than a snapshot can carry; the extra ones are not being sent.")
			break
		link.sample_state(slot)
		slot.tick = _tick
		_outgoing.commit()

	if _outgoing.count == 0:
		return
	# The host's own playout is fed from what it sends: what it draws is what everybody is told.
	_buffer_snapshot(_outgoing)
	rpc(&"_receive_snapshot", NetCodec.pack_snapshot(_outgoing))
	snapshot_sent.emit(_outgoing.tick, _outgoing.count)


# --- Lag compensation ---------------------------------------------------------

## Keep where every body is on this tick, after it has moved.
func _record_history() -> void:
	if _history.is_empty():
		_history.resize(NetTransport.MAX_PLAYERS * HISTORY_TICKS)
		_history_ticks.resize(HISTORY_TICKS)
		_history_ticks.fill(-1)
		_history_layers.resize(_history.size())
	var slot: int = _tick % HISTORY_TICKS
	_history_ticks[slot] = _tick
	for seat: int in NetTransport.MAX_PLAYERS:
		_history_layers[seat * HISTORY_TICKS + slot] = 0
	for link: PlayerNetLink in _links:
		if link.is_replicable() and link.seat_index < NetTransport.MAX_PLAYERS:
			var at: int = link.seat_index * HISTORY_TICKS + slot
			_history[at] = link.controller.global_position
			_history_layers[at] = link.controller.collision_layer


## The tick (fractional) of the world this machine last drew other bodies at, stamped on its
## commands as their view time; [constant MoveIntent.LIVE_WORLD] before it has drawn one, or with nobody to draw.
func get_view_time() -> float:
	return _drawn_time


## Authority: ticks back to the world a command's [param view_time] names, within the history
## kept; 0 for the live world.
func rewind_ticks(view_time: float) -> int:
	if not is_finite(view_time):
		return 0
	return clampi(roundi(float(_tick) - view_time), 0, HISTORY_TICKS - 1)


## [param query]'s ray in [param space], with every body it does not exclude standing where it
## stood [param back] ticks ago; the live ray when that tick is not in the history kept.
func trace(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, back: int) -> Dictionary:
	var then: int = _tick - back
	var slot: int = posmod(then, HISTORY_TICKS)
	if not _is_authority or back <= 0 or then < 0 or _history.is_empty() or _history_ticks[slot] != then:
		return space.intersect_ray(query)
	var live_exclude: Array[RID] = query.exclude
	var exclude: Array[RID] = live_exclude.duplicate()
	if _rewind_space == null:
		_rewind_space = RewindSpace.new()
	_rewind_space.clear()
	for link: PlayerNetLink in _links:
		if not link.is_replicable() or link.seat_index >= NetTransport.MAX_PLAYERS:
			continue
		var body: PlayerController = link.controller
		if live_exclude.has(body.get_rid()):
			continue
		exclude.append(body.get_rid())
		var at: int = link.seat_index * HISTORY_TICKS + slot
		# A body that could not be hit on that tick was not there for the shooter to aim at.
		if (_history_layers[at] & query.collision_mask) != 0:
			_rewind_space.place(link.seat_index, body, _history[at])
	var hit: Dictionary = _rewind_space.intersect_ray(query)
	query.exclude = exclude
	var world_hit: Dictionary = space.intersect_ray(query)
	query.exclude = live_exclude
	if hit.is_empty():
		return world_hit
	if world_hit.is_empty():
		return hit
	var near: float = query.from.distance_squared_to(hit["position"])
	return hit if near <= query.from.distance_squared_to(world_hit["position"]) else world_hit


# --- Holograms ----------------------------------------------------------------

## Send every live decoy's spawn, motion and death.
##
## A stream of its own rather than a field of the snapshot, because a decoy is
## not a seat: it comes and goes inside a round, there is at most one per
## runner, and the snapshot body is a fixed-size record shared with a machine
## that may never see a hologram at all.
##
## Polled here rather than pushed from [RunnerPower], which spawns them: the
## authority is the only machine that may say a decoy exists, and polling the
## seats it already walks costs nothing next to the snapshot it is about to
## build.
func _drive_decoys() -> void:
	for link: PlayerNetLink in _links:
		if not link.is_replicable():
			continue
		var power: RunnerPower = RunnerPower.of(link.controller)
		var decoy: PlayerController = power.get_decoy() if power != null else null
		var track: DecoyTrack = _decoy_tracks.get(link.seat_index)
		if decoy == null:
			if track != null:
				_decoy_tracks.erase(link.seat_index)
				rpc(&"_decoy_ended", link.seat_index, track.epoch)
			continue
		if track == null or track.decoy != decoy:
			_decoy_epoch = (_decoy_epoch + 1) % NetCodec.DECOY_EPOCH_MODULUS
			track = DecoyTrack.new()
			track.decoy = decoy
			track.epoch = _decoy_epoch
			track.position = decoy.global_position
			track.yaw = decoy.rotation.y
			_decoy_tracks[link.seat_index] = track
			# Reliable: a spawn nobody hears is a hologram half the lobby is
			# shooting at and half cannot see.
			rpc(&"_decoy_spawned", link.seat_index, track.epoch, track.position, track.yaw)
			continue
		var position: Vector3 = decoy.global_position
		var yaw: float = decoy.rotation.y
		if (
			position.distance_squared_to(track.position) < DECOY_MOVED_METRES * DECOY_MOVED_METRES
			and absf(angle_difference(track.yaw, yaw)) < DECOY_TURNED_RADIANS
		):
			continue
		track.position = position
		track.yaw = yaw
		rpc(&"_decoy_moved", NetCodec.pack_decoy_move(link.seat_index, track.epoch, position, yaw))


## Tell [param peer_id], whose scene has just stood up, of every hologram and shield already out:
## each is said once, and a peer with no bodies yet had nowhere to put it.
func send_placed_to(peer_id: int) -> void:
	if not _is_authority:
		return
	for seat_index: int in _decoy_tracks:
		var track: DecoyTrack = _decoy_tracks[seat_index]
		if is_instance_valid(track.decoy):
			rpc_id(peer_id, &"_decoy_spawned", seat_index, track.epoch, track.position, track.yaw)
	for seat_index: int in _shields_told:
		var power: RunnerPower = _power_of(seat_index)
		var shield: Node3D = power.get_shield() if power != null else null
		if shield != null:
			rpc_id(peer_id, &"_shield_raised", seat_index, shield.global_position)


## Say once where each new bubble shield stands. A mirror raises its own off the snapshot, where
## its drawn body had got to; this is where the authority stops shots.
func _drive_shields() -> void:
	for link: PlayerNetLink in _links:
		if not link.is_replicable():
			continue
		var power: RunnerPower = RunnerPower.of(link.controller)
		var shield: Node3D = power.get_shield() if power != null else null
		var told: int = _shields_told.get(link.seat_index, 0)
		if shield == null:
			if told != 0:
				_shields_told.erase(link.seat_index)
		elif told != shield.get_instance_id():
			_shields_told[link.seat_index] = shield.get_instance_id()
			rpc(&"_shield_raised", link.seat_index, shield.global_position)


## Authority to everyone, once, when a runner's shield goes up.
@rpc("authority", "reliable", "call_remote", 0)
func _shield_raised(seat_index: int, position: Vector3) -> void:
	if _is_authority or not position.is_finite():
		return
	var power: RunnerPower = _power_of(seat_index)
	if power != null:
		power.place_shield(position)


## Authority to everyone, once, when a runner's hologram appears.
@rpc("authority", "reliable", "call_remote", 0)
func _decoy_spawned(seat_index: int, epoch: int, position: Vector3, yaw: float) -> void:
	if _is_authority or not position.is_finite() or not is_finite(yaw):
		return
	_decoy_epochs[seat_index] = epoch
	_place_decoy(seat_index, position, yaw, true)


## Authority to everyone, every tick the hologram moved.
##
## Unreliable and ordered, for the reason a snapshot is: a transform that
## arrives late has been overtaken by a newer one. It rides a channel of its
## own so a burst of them cannot delay the snapshot, which is why a stale one
## can outlive the reliable despawn that followed it -- hence the epoch.
@rpc("authority", "unreliable_ordered", "call_remote", 3)
func _decoy_moved(payload: PackedByteArray) -> void:
	if _is_authority:
		return
	var epoch: int = NetCodec.unpack_decoy_move(payload, _decoy_in)
	if epoch < 0 or int(_decoy_epochs.get(_decoy_in.seat_index, -1)) != epoch:
		return
	_place_decoy(_decoy_in.seat_index, _decoy_in.position, _decoy_in.yaw)


## Authority to everyone, when the hologram expires or is shot away.
@rpc("authority", "reliable", "call_remote", 0)
func _decoy_ended(seat_index: int, epoch: int) -> void:
	if _is_authority or int(_decoy_epochs.get(seat_index, -1)) != epoch:
		return
	_decoy_epochs.erase(seat_index)
	var power: RunnerPower = _power_of(seat_index)
	if power != null:
		power.clear_decoy()


func _place_decoy(seat_index: int, position: Vector3, yaw: float, spawn: bool = false) -> void:
	var power: RunnerPower = _power_of(seat_index)
	if power != null:
		power.present_decoy(position, yaw, spawn)


## The ability node of the body in [param seat_index], or null.
func _power_of(seat_index: int) -> RunnerPower:
	var link: PlayerNetLink = find_link(seat_index)
	if link == null or not link.is_replicable():
		return null
	return RunnerPower.of(link.controller)


# --- Receiving ----------------------------------------------------------------

## Authority to everyone, [member NetSettings.snapshot_hz] times a second.
##
## Unreliable and ordered: a snapshot that arrives late has already been
## overtaken by a newer one, so retransmitting it would spend latency to
## deliver a worse answer. Restricted to the node's multiplayer authority,
## which is [constant NetTransport.AUTHORITY_PEER_ID] for the life of the
## session however often the tower changes hands.
@rpc("authority", "unreliable_ordered", "call_remote", 2)
func _receive_snapshot(payload: PackedByteArray) -> void:
	if _is_authority:
		# The authority does not take snapshots. Reaching here means a peer is
		# impersonating the server, and the right response is to ignore it
		# rather than to move every body in the world.
		return
	if _scene == 0 or not NetCodec.unpack_snapshot(payload, _incoming) or _incoming.scene != _scene:
		return
	if _playback_count > 0 and not NetCodec.is_newer_tick(_incoming.tick, _newest().tick):
		# Reordered by UDP and older than one already buffered.
		return
	apply_snapshot(_incoming)


## Take a snapshot as though it had arrived over the wire. Public because a
## test and a future replay viewer both drive it directly.
func apply_snapshot(snapshot: WorldSnapshot) -> void:
	_acknowledge(snapshot)
	_buffer_snapshot(snapshot)
	_update_delay()
	if not _have_clock:
		_render_lag = _delay_ticks
		_have_clock = true

	_deliver_predictions(_newest())
	if not _should_interpolate():
		# Interpolation off: the snapshot goes straight onto the bodies, which is
		# the zero-seconds case of the same routine playback uses.
		_draw_extrapolated(_newest(), 0.0)
	snapshot_received.emit(_newest().tick, _newest().count)


## Hand the outbox the host's word on this machine's own seat: the commands it has run.
func _acknowledge(snapshot: WorldSnapshot) -> void:
	for link: PlayerNetLink in _links:
		if link.is_owned_here():
			var state: PlayerState = snapshot.find_seat(link.seat_index)
			if state != null:
				outbox.acknowledge(state.cmd_ack)
			return


## Keep [param snapshot], dropping the oldest when the buffer is full. The
## arriving tick is newer than everything held -- [method _receive_snapshot] has
## already refused anything else -- so it goes on the end.
func _buffer_snapshot(snapshot: WorldSnapshot) -> void:
	if _playback.is_empty():
		_playback.resize(PLAYBACK_CAPACITY)
		for i: int in PLAYBACK_CAPACITY:
			_playback[i] = WorldSnapshot.new()
	var previous_newest: int = _newest().tick if _playback_count > 0 else -1
	if _playback_count >= PLAYBACK_CAPACITY:
		_playback_start = (_playback_start + 1) % PLAYBACK_CAPACITY
		_playback_count -= 1
	_slot(_playback_count).copy_from(snapshot)
	_playback_count += 1
	if previous_newest >= 0:
		# The newest tick moved on, so everything behind it is that much further
		# behind -- the playout clock included.
		var advanced: int = NetCodec.tick_delta(previous_newest, snapshot.tick)
		if advanced > 0 and not _is_authority:
			_render_lag += float(advanced)
			_interval_ticks = (
				float(advanced) if _interval_ticks <= 0.0
				else lerpf(_interval_ticks, float(advanced), _JITTER_ALPHA)
			)


## Re-measure how irregularly snapshots are arriving, and set the buffer depth
## from it.
##
## Jitter is the difference between when a snapshot was DUE, from the tick gap
## it carries, and when it turned up on this machine's own playback clock. Twice
## the smoothed value is held on top of the floor, which covers the ordinary
## spread of a domestic line without holding a LAN back.
func _update_delay() -> void:
	var settings: NetSettings = session.get_settings()
	if _last_arrival_seconds >= 0.0 and _interval_ticks > 0.0:
		var expected: float = _interval_ticks * _tick_seconds()
		var observed: float = _clock_seconds - _last_arrival_seconds
		_jitter_seconds = lerpf(_jitter_seconds, absf(observed - expected), _JITTER_ALPHA)
	_last_arrival_seconds = _clock_seconds
	var jitter_ticks: float = clampf(
		_jitter_seconds * 2.0 / _tick_seconds(), 0.0, float(settings.max_interpolation_jitter_ticks)
	)
	# The floor is a whole snapshot interval whatever the setting says: below
	# one there is no second snapshot to interpolate towards.
	var floor_ticks: float = maxf(
		float(settings.interpolation_delay_ticks), maxf(_interval_ticks, 1.0)
	)
	_delay_ticks = floor_ticks + jitter_ticks


## Move the playout clock on by one authority tick, give or take the dilation
## that is taking drift out of it. Client-only.
##
## On the PHYSICS tick and not the drawn frame. The clock counts the authority's
## ticks, the authority advances them on its own physics, and tying the two
## together is what makes the buffer depth mean the same thing at 30 frames a
## second as at 240.
func _advance_clock(delta: float) -> void:
	_clock_seconds += delta
	if not _have_clock or _playback_count == 0 or not _should_interpolate():
		return
	var error: float = _render_lag - _delay_ticks
	if absf(error) > _CLOCK_SNAP_TICKS:
		# The connection changed rather than drifted -- a hitch on the host, a
		# route that moved. Dilating a third of a second away would take four
		# seconds of visibly wrong-speed bodies.
		_render_lag = _delay_ticks
	else:
		# Run a shade fast when the buffer is deeper than it should be and a
		# shade slow when it is shallower. A few per cent of playback speed is
		# not visible on a running body; a jump is.
		_render_lag -= 1.0 + clampf(error * _CLOCK_GAIN, -_MAX_DILATION, _MAX_DILATION)
	var oldest_lag: float = float(NetCodec.tick_delta(_slot(0).tick, _newest().tick))
	_render_lag = clampf(_render_lag, -_extrapolation_ticks(), oldest_lag)


## Draw where the playout clock stands.
##
## Per drawn frame rather than per physics tick: this moves bodies for the
## camera, not for the simulation. The sub-tick fraction is what keeps a body
## smooth on a machine drawing faster than it simulates.
func _process(delta: float) -> void:
	play_back(delta)


## One frame of playback. Public because the cost test times it directly.
func play_back(_delta: float) -> void:
	if _is_authority:
		draw_host_at(float(_tick) - HOST_PLAYOUT_TICKS + Engine.get_physics_interpolation_fraction())
		return
	if not _have_clock or _playback_count == 0 or not _should_interpolate():
		return
	var lag: float = maxf(_render_lag - Engine.get_physics_interpolation_fraction(), -_extrapolation_ticks())
	_drawn_time = float(_newest().tick) - lag
	_draw(lag)


## Host: draw every body but its own at tick [param time], [constant HOST_PLAYOUT_TICKS] behind its
## own, from the samples it sent. Render-only: the avatar moves, the collider stays where physics has it.
func draw_host_at(time: float) -> void:
	var live: bool = _playback_count < 2 or session == null or session.get_peer_count() <= 1 or _scene == 0
	_drawn_time = MoveIntent.LIVE_WORLD if live else time
	var to_index: int = 0
	while to_index < _playback_count - 1 and float(_slot(to_index).tick) < _drawn_time:
		to_index += 1
	var to_snapshot: WorldSnapshot = _slot(to_index) if not live else null
	var from_snapshot: WorldSnapshot = _slot(maxi(to_index - 1, 0)) if not live else null
	for link: PlayerNetLink in _links:
		if live or link.is_owned_here() or not link.is_replicable():
			_draw_live(link)
			continue
		var to_state: PlayerState = to_snapshot.find_seat(link.seat_index)
		var from_state: PlayerState = from_snapshot.find_seat(link.seat_index)
		if to_state == null or from_state == null:
			_draw_live(link)
			continue
		var span: float = float(to_snapshot.tick - from_snapshot.tick)
		var weight: float = 1.0 if span <= 0.0 else clampf((_drawn_time - float(from_snapshot.tick)) / span, 0.0, 1.0)
		var yaw: float = lerp_angle(from_state.yaw, to_state.yaw, weight)
		link.draw_avatar_at(
			Transform3D(Basis(Vector3.UP, yaw), from_state.position.lerp(to_state.position, weight))
		)


func _draw_live(link: PlayerNetLink) -> void:
	link.draw_avatar_at(Transform3D.IDENTITY, false)


## How far past the newest snapshot a body may be carried, in authority ticks.
func _extrapolation_ticks() -> float:
	return session.get_settings().max_extrapolation_seconds / _tick_seconds()


## Seconds in one authority tick, as this machine simulates them.
func _tick_seconds() -> float:
	return maxf(get_physics_process_delta_time(), 0.0001)


## Put every mirrored body where the playout clock says it is, [param lag] ticks
## behind the newest snapshot.
func _draw(lag: float) -> void:
	var newest: WorldSnapshot = _newest()
	if lag <= 0.0 or _playback_count == 1:
		_draw_extrapolated(newest, maxf(-lag, 0.0) * _tick_seconds())
		return

	# The newest snapshot at or behind the clock, and the one before it. The
	# buffer is in tick order, so lag falls as the index rises.
	var to_index: int = _playback_count - 1
	for i: int in _playback_count:
		if float(NetCodec.tick_delta(_slot(i).tick, newest.tick)) <= lag:
			to_index = i
			break
	var to_snapshot: WorldSnapshot = _slot(to_index)
	if to_index == 0:
		# Older than anything held: the clock has been clamped to the back of
		# the buffer and there is nothing behind it to slide from.
		_draw_extrapolated(to_snapshot, 0.0)
		return

	var from_snapshot: WorldSnapshot = _slot(to_index - 1)
	var lag_from: float = float(NetCodec.tick_delta(from_snapshot.tick, newest.tick))
	var lag_to: float = float(NetCodec.tick_delta(to_snapshot.tick, newest.tick))
	var span: float = lag_from - lag_to
	var weight: float = 1.0 if span <= 0.0 else clampf((lag_from - lag) / span, 0.0, 1.0)
	for link: PlayerNetLink in _links:
		if link.is_predicting():
			# This machine's own body moves itself. Sliding it between two
			# snapshots as well would be two things driving one body.
			continue
		var to_state: PlayerState = to_snapshot.find_seat(link.seat_index)
		if to_state == null:
			continue
		var from_state: PlayerState = from_snapshot.find_seat(link.seat_index)
		if from_state == null:
			link.apply_state(to_state)
			continue
		_blend.interpolate_from(from_state, to_state, weight)
		link.apply_state(_blend)


## Draw [param snapshot] carried [param seconds] forward along each body's own
## velocity. Zero seconds is the snapshot itself.
func _draw_extrapolated(snapshot: WorldSnapshot, seconds: float) -> void:
	for link: PlayerNetLink in _links:
		if link.is_predicting():
			continue
		var state: PlayerState = snapshot.find_seat(link.seat_index)
		if state == null:
			continue
		if seconds <= 0.0:
			link.apply_state(state)
			continue
		_blend.copy_from(state)
		_blend.position += state.velocity * seconds
		link.apply_state(_blend)


## Hand the snapshot to the bodies this machine predicts. They take it as a
## correction to rewind against, not as a position to be moved to.
func _deliver_predictions(snapshot: WorldSnapshot) -> void:
	for link: PlayerNetLink in _links:
		if not link.is_predicting():
			continue
		var state: PlayerState = snapshot.find_seat(link.seat_index)
		if state != null:
			link.receive_authoritative(state)


## The buffered snapshot at [param index], oldest first.
func _slot(index: int) -> WorldSnapshot:
	return _playback[(_playback_start + index) % PLAYBACK_CAPACITY]


## The newest snapshot held. Never called with an empty buffer.
func _newest() -> WorldSnapshot:
	return _slot(_playback_count - 1)


func _should_interpolate() -> bool:
	return session != null and session.get_settings().interpolate_remote_bodies


func _clear_playback() -> void:
	_decoy_tracks.clear()
	_decoy_epochs.clear()
	_shields_told.clear()
	_playback_start = 0
	_playback_count = 0
	_have_clock = false
	_render_lag = 0.0
	_last_arrival_seconds = -1.0
	_jitter_seconds = 0.0
	_interval_ticks = 0.0


func _on_connection_state_changed(_state: NetTransport.ConnectionState) -> void:
	_clear_playback()
	refresh_role()


## One line, for logs and the harness.
func describe() -> String:
	return "NetReplicator(%s, %d bodies, tick %d, %d Hz)" % [
		"authority" if _is_authority else "client",
		_links.size(),
		_tick,
		session.get_settings().snapshot_hz if session != null else 0,
	]
