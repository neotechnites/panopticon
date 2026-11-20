class_name NetReplicator
extends Node

## Per-tick traffic on a scene-outliving node: commands up, one snapshot per standing client down (delta
## against its ack, its owner block, unacked events), drawn at a playout clock; lag compensation (DESIGN 3-7).

## The authority sent a snapshot round. Authority-only, for telemetry.
signal snapshot_sent(tick: int, body_count: int)

## A client decoded a snapshot. Client-only, on arrival.
signal snapshot_received(tick: int, body_count: int)

## A client's newest match record, on arrival when it changed: what its own prediction reads (DESIGN 5).
signal match_arrived(record: PackedByteArray)

## A client's match records, each once and in order, as the playout clock reaches it; [param first] for
## the scene's first.
signal match_due(record: PackedByteArray, tick: int, first: bool)

## A client presents a transient event: on arrival when it is about this machine's own body, else
## when the playout clock reaches [param tick].
signal event_received(type: NetEvents.Type, payload: PackedByteArray, tick: int)

## Decoded worlds kept: the host's baselines and playout, a client's baselines and playback.
const RING: int = 32
## Authority ticks of body positions kept for lag compensation: Source's sv_maxunlag, one second.
const HISTORY_TICKS: int = 64
## How far behind its own tick the host draws other bodies: one sample interval, never extrapolated.
const HOST_PLAYOUT_TICKS: float = 2.0
## Event types presented on arrival: they are about this machine's own predicted body.
const ARRIVAL_EVENTS: Array[NetEvents.Type] = [NetEvents.Type.SHOVE_KICK]


## The host's bookkeeping for one standing client (DESIGN 3.4): what it has acknowledged.
class Recipient:
	extends RefCounted
	## The newest snapshot tick the client decoded, or -1: the baseline of the next one.
	var acked: int = -1
	## Every event up to this sequence has reached the client or been passed over.
	var event_acked: int = -1
	var event_counted: int = -1
	var _sent_ticks: PackedInt64Array = PackedInt64Array()
	var _sent_events: PackedInt64Array = PackedInt64Array()
	var _at: int = 0

	func _init(events_from: int) -> void:
		event_acked = events_from
		event_counted = events_from
		_sent_ticks.resize(RING)
		_sent_ticks.fill(-1)
		_sent_events.resize(RING)

	## A snapshot at [param tick] went out carrying every event up to [param passed].
	func note_sent(tick: int, passed: int) -> void:
		_sent_ticks[_at] = tick
		_sent_events[_at] = passed
		_at = (_at + 1) % RING
		event_counted = maxi(event_counted, passed)

	## The client decoded the snapshot at [param tick].
	func take_ack(tick: int) -> void:
		if tick < 0 or (acked >= 0 and not NetCodec.is_newer_tick(tick, acked)):
			return
		acked = tick
		for i: int in RING:
			if _sent_ticks[i] == tick:
				event_acked = maxi(event_acked, int(_sent_events[i]))
				return


## The session this replicator belongs to.
@export var session: NetSession

var _links: Array[PlayerNetLink] = []
var _is_authority: bool = false

## The authority's tick: simulation ticks, stamped on what is sampled.
var _tick: int = 0
var _send_accumulator: float = 0.0
## The scene epoch this machine's bodies belong to ([method NetLobby.get_epoch]); 0 is none.
var _scene: int = 0

## Decoded (client) or sent (host) worlds, oldest first: baselines, playback and the host's playout.
var _ring: Array[WorldSnapshot] = []
var _ring_start: int = 0
var _ring_count: int = 0

## Host: the world being sampled, each standing client's record, and the event ring.
var _world: WorldSnapshot = WorldSnapshot.new()
var _recipients: Dictionary[int, Recipient] = {}
var events: NetEvents = NetEvents.new()
var _info: NetCodec.SnapshotInfo = NetCodec.SnapshotInfo.new()
var _carry: Array[NetEvents.Entry] = []
## Host: the scene's match record ([method NetCodec.pack_match_state]), set by [NetMatch]; and its props.
var match_source: Callable
var _props: Array[Node] = []
var _prop_ids: PackedInt32Array = PackedInt32Array()

## Client: the packet being decoded, and the events it carried.
var _incoming: WorldSnapshot = WorldSnapshot.new()
var _decoded_events: Array[NetEvents.Entry] = []
## Client: the newest event sequence (u16) taken, or -1; events waiting for the playout clock.
var _event_seen: int = -1
var _due_events: Array[NetEvents.Entry] = []
## Client: the newest snapshot tick whose props have been applied, or -1; the same for the match record.
var _props_tick: int = -1
var _match_tick: int = -1
var _match_record: PackedByteArray = PackedByteArray()
## Client: packets refused for a baseline this machine no longer holds, and the baseline tick of the
## last one taken (-1: a full update). For telemetry and tests.
var missing_baselines: int = 0
var last_baseline: int = -1

## Client playout clock: how far behind the newest snapshot it draws, in authority ticks.
var _render_lag: float = 0.0
var _have_clock: bool = false
var _clock_seconds: float = 0.0
var _last_arrival_seconds: float = -1.0
var _jitter_seconds: float = 0.0
var _interval_ticks: float = 0.0
var _delay_ticks: float = 2.0
const _JITTER_ALPHA: float = 0.1
## Playback speed change per tick of clock error, and the most of it allowed.
const _CLOCK_GAIN: float = 0.1
const _MAX_DILATION: float = 0.2
## Clock error past which the drift is jumped rather than dilated away: the connection changed.
const _CLOCK_SNAP_TICKS: float = 20.0
var _blend: PlayerState = PlayerState.new()

## Position of seat s at the tick in slot i is _history[s * HISTORY_TICKS + i].
var _history: PackedVector3Array = PackedVector3Array()
var _history_ticks: PackedInt32Array = PackedInt32Array()
## The body's collision layer on that tick, in the same slot; 0 for a seat with no body in play.
var _history_layers: PackedInt32Array = PackedInt32Array()
var _rewind_space: RewindSpace = null

## Client: this machine's commands, numbered and kept until the host has run them.
var outbox: CommandStream.Outbox = CommandStream.Outbox.new()
## Host: each remote peer's commands, by peer id, and the same streams in a list for the tick.
var _streams: Dictionary[int, CommandStream] = {}
var _stream_list: Array[CommandStream] = []
var _last_command_packet: PackedByteArray = PackedByteArray()
var _acked_by_commands: int = -1
var _bare_acked: int = -1
## The tick (fractional) of the world this machine last drew other bodies at, or [constant MoveIntent.LIVE_WORLD].
var _drawn_time: float = MoveIntent.LIVE_WORLD


func _init() -> void:
	_ring.resize(RING)
	for i: int in RING:
		_ring[i] = WorldSnapshot.new()


func _ready() -> void:
	if session == null:
		push_error("NetReplicator has no session; nothing will be replicated.")
		set_physics_process(false)
		set_process(false)
		return
	# After the bodies have moved, so what is sampled is the result of this tick.
	process_physics_priority = 100
	session.connection_state_changed.connect(_on_connection_state_changed)
	refresh_role()


## Re-read the session. Called at ready and on every connection state change.
func refresh_role() -> void:
	if session == null:
		return
	_is_authority = session.is_authority()
	_clear_worlds()
	for link: PlayerNetLink in _links:
		link.refresh_role()


## Name the scene epoch whose bodies are registered: the authority once it has placed them, a
## client once it has loaded it. Both rings, the history and every stream start again (DESIGN N5).
func bind_scene(scene: int) -> void:
	if scene == _scene:
		return
	_scene = scene
	_history_ticks.fill(-1)
	for stream: CommandStream in _stream_list:
		stream.reset()
	outbox.flush()
	_clear_worlds()


## The scene's props ([NetProp]), named by id; a collision is refused and leaves the scene none.
func bind_props(props: Array[Node]) -> void:
	_props.clear()
	_prop_ids.clear()
	var by_id: Dictionary[int, Node] = {}
	for prop: Node in props:
		var id: int = NetProp.id_of(prop)
		if by_id.has(id):
			push_error("NetReplicator: props %s and %s share id %d; this scene's props are not replicated." % [
				by_id[id].get_path(), prop.get_path(), id])
			return
		by_id[id] = prop
	var ids: Array[int] = by_id.keys()
	ids.sort()
	for id: int in ids:
		_prop_ids.append(id)
		_props.append(by_id[id])


# --- Registry -----------------------------------------------------------------

## Take responsibility for a body; refuses a second link for the same seat.
func register(link: PlayerNetLink) -> bool:
	if link == null or find_link(link.seat_index) != null:
		return false
	_links.append(link)
	_links.sort_custom(func(a: PlayerNetLink, b: PlayerNetLink) -> bool: return a.seat_index < b.seat_index)
	return true


## Stop replicating a body. Safe for one never registered.
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


# --- Commands -----------------------------------------------------------------

## Client to authority, every tick: every command of this machine's the host has not run yet.
func send_commands() -> void:
	_last_command_packet = outbox.pack(_scene, get_latest_tick())
	if not _last_command_packet.is_empty():
		_acked_by_commands = Engine.get_physics_frames()
		rpc_id(NetTransport.AUTHORITY_PEER_ID, &"_receive_intent", _last_command_packet)


## A client that sent no commands last tick (no body of its own) acknowledges its newest world alone.
func _send_bare_ack() -> void:
	var newest: int = get_latest_tick()
	if newest < 0 or newest == _bare_acked or _acked_by_commands >= Engine.get_physics_frames() - 1:
		return
	_bare_acked = newest
	rpc_id(NetTransport.AUTHORITY_PEER_ID, &"_receive_intent", NetCodec.pack_ack(_scene, newest))


## The command packet this machine last sent, or an empty array before the first. For tests.
func get_last_command_packet() -> PackedByteArray:
	return _last_command_packet


@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _receive_intent(payload: PackedByteArray) -> void:
	if not _is_authority:
		return
	take_commands(multiplayer.get_remote_sender_id(), payload)


## Take [param payload] from [param sender] as its seat's commands, and its acknowledgement of a
## snapshot. The sender is the one check that stops a peer driving somebody else's body.
func take_commands(sender: int, payload: PackedByteArray) -> void:
	if _scene == 0 or sender == 0 or NetCodec.command_epoch(payload) != _scene % NetCodec.EPOCH_MODULUS:
		return
	var recipient: Recipient = _recipients.get(sender, null)
	if recipient != null:
		recipient.take_ack(NetCodec.command_snap_ack(payload))
	for link: PlayerNetLink in _links:
		if link.owner_peer_id == sender:
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


func get_scene() -> int:
	return _scene


func get_tick() -> int:
	return _tick


## The authority tick of the newest snapshot a client has decoded in this scene, or -1.
func get_latest_tick() -> int:
	return _newest().tick if _ring_count > 0 and not _is_authority else -1


## How far behind the newest snapshot this client is drawing, in ticks, or -1 before the clock starts.
func get_render_lag_ticks() -> float:
	return _render_lag if _have_clock else -1.0


func get_delay_ticks() -> float:
	return _delay_ticks


func get_jitter_seconds() -> float:
	return _jitter_seconds


# --- Sending ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _is_authority:
		_advance_clock(delta)
		if session != null and session.is_established() and _scene != 0:
			_send_bare_ack()
		return
	_tick += 1
	var wall: int = int(Time.get_ticks_usec() * Engine.physics_ticks_per_second / 1000000)
	for stream: CommandStream in _stream_list:
		stream.end_tick(wall)
	if session == null or not session.is_established() or session.get_peer_count() <= 1 or _scene == 0:
		# Offline, or a lone host: authoritative with nobody to tell. The tick still advances.
		return
	_record_history()
	_send_accumulator += delta
	var interval: float = session.get_settings().get_snapshot_interval()
	if _send_accumulator < interval:
		return
	# Subtract rather than zero, so a 30 Hz send on a 60 Hz tick stays on 30 Hz.
	_send_accumulator = fmod(_send_accumulator, interval)
	_send_snapshots()


## Host: record a transient event at this tick for [param target] (DESIGN 6). Returns its sequence.
func send_event(
	type: NetEvents.Type, payload: PackedByteArray, target: NetEvents.Target = NetEvents.Target.ALL, peer: int = 0
) -> int:
	return events.push(type, payload, _tick + 1, target, peer)


## Sample the world once, keep it, and send each standing client its own coding of it.
func _send_snapshots() -> void:
	_sample_world()
	if _world.present == 0:
		return
	var kept: WorldSnapshot = _push_world(_world)
	var lobby: NetLobby = session.lobby
	for peer: int in session.get_peer_ids():
		if peer == NetTransport.AUTHORITY_PEER_ID:
			continue
		if lobby == null or not lobby.is_standing_in(peer, _scene):
			_recipients.erase(peer)
			continue
		var recipient: Recipient = _recipients.get(peer, null)
		if recipient == null:
			# A client newly standing has no baseline: its first snapshot is the whole world.
			recipient = Recipient.new(events.newest())
			_recipients[peer] = recipient
		_send_to(peer, recipient, kept)
	snapshot_sent.emit(kept.tick, kept.get_count())


func _send_to(peer: int, recipient: Recipient, world: WorldSnapshot) -> void:
	var base: WorldSnapshot = _find_world(recipient.acked)
	var stream: CommandStream = _streams.get(peer, null)
	_info.cmd_ack = stream.get_ack() if stream != null else -1
	_info.cmd_buffer = roundi(stream.get_cmd_buffer()) if stream != null else 0
	var passed: int = events.collect(
		peer, recipient.event_acked, world.tick, NetCodec.MAX_SNAPSHOT_BYTES, _carry, recipient.event_counted
	)
	var payload: PackedByteArray = NetCodec.pack_snapshot(world, base, _seat_of_peer(peer), _carry, _info)
	if _info.event_count < _carry.size():
		passed = _carry[_info.event_count].seq - 1
	recipient.note_sent(world.tick, passed)
	rpc_id(peer, &"_receive_snapshot", payload)


## The world at this tick, at wire precision: every body, each remote owner's predicted state,
## the match record and the props.
func _sample_world() -> void:
	sample_bodies(_world, _links, _tick, _scene)
	if match_source.is_valid():
		_world.match_record = match_source.call()
	for i: int in _props.size():
		if is_instance_valid(_props[i]):
			_world.set_prop(_prop_ids[i], _props[i].call(&"net_record"))


## [param links]' bodies into a cleared [param world] at [param tick] in [param epoch], quantised, with
## each remote owner's exact predicted state. The host's sampling, shared with hand-carried test wires.
static func sample_bodies(world: WorldSnapshot, links: Array[PlayerNetLink], tick: int, epoch: int) -> void:
	world.clear()
	world.tick = tick
	world.epoch = epoch
	for link: PlayerNetLink in links:
		if not link.is_replicable() or link.seat_index >= NetTransport.MAX_PLAYERS:
			continue
		var state: PlayerState = world.slot(link.seat_index)
		link.sample_state(state, tick)
		NetCodec.quantise_state(state, tick)
		if link.owner_peer_id != 0 and not link.is_owned_here():
			link.sample_predicted(world.owners[link.seat_index])
		world.owner_valid |= 1 << link.seat_index


## The seat whose body [param peer] drives, or -1.
func _seat_of_peer(peer: int) -> int:
	for link: PlayerNetLink in _links:
		if link.owner_peer_id == peer:
			return link.seat_index
	return -1


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
## commands as their view time; [constant MoveIntent.LIVE_WORLD] before it has drawn one.
func get_view_time() -> float:
	return _drawn_time


## Authority: ticks back to the world a command's [param view_time] names, within the history kept.
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


# --- Receiving ----------------------------------------------------------------

## Authority to one client, [member NetSettings.snapshot_hz] times a second. The receiver drops
## what is stale itself, so a transport need only be unreliable (DESIGN 3.1).
@rpc("authority", "unreliable_ordered", "call_remote", 2)
func _receive_snapshot(payload: PackedByteArray) -> void:
	if _is_authority:
		return
	receive_snapshot(payload)


## Decode one snapshot packet against the baseline it names and take it. Public for tests that
## carry packets themselves. Returns whether it was taken.
func receive_snapshot(payload: PackedByteArray) -> bool:
	if _scene == 0 or NetCodec.snapshot_epoch(payload) != _scene % NetCodec.EPOCH_MODULUS:
		return false
	var tick: int = NetCodec.snapshot_tick(payload)
	if _ring_count > 0 and not NetCodec.is_newer_tick(tick, _newest().tick):
		return false
	var baseline: int = NetCodec.snapshot_baseline(payload)
	var base: WorldSnapshot = null
	if baseline >= 0:
		base = _find_world(baseline)
		if base == null:
			missing_baselines += 1
			return false
	if not NetCodec.unpack_snapshot(payload, base, _incoming, _info, _decoded_events):
		return false
	_incoming.epoch = _scene
	last_baseline = baseline
	var first: bool = _ring_count == 0
	var previous_match: PackedByteArray = _newest().match_record if not first else PackedByteArray()
	_push_world(_incoming)
	_take(first, previous_match)
	return true


## What a decoded snapshot means on arrival: acknowledgements, the own body's correction, the
## match record, and the events.
func _take(first: bool, previous_match: PackedByteArray) -> void:
	var newest: WorldSnapshot = _newest()
	outbox.acknowledge(_info.cmd_ack)
	_measure_arrival(first)
	_deliver_predictions(newest, _info.cmd_ack)
	if first or newest.match_record != previous_match:
		match_arrived.emit(newest.match_record)
	_take_events()
	if not _should_interpolate():
		_draw_at_newest()
		_apply_match(float(newest.tick))
	snapshot_received.emit(newest.tick, newest.get_count())


## Hand this machine's own body its record, exact predicted state and acknowledgement.
func _deliver_predictions(snapshot: WorldSnapshot, cmd_ack: int) -> void:
	for link: PlayerNetLink in _links:
		if not link.is_predicting():
			continue
		var state: PlayerState = snapshot.find_seat(link.seat_index)
		if state != null:
			link.receive_authoritative(state, snapshot.find_owner(link.seat_index), cmd_ack)


## Each event once, in order: about this machine's own body now, the rest at the playout clock.
func _take_events() -> void:
	for i: int in _info.event_count:
		var entry: NetEvents.Entry = _decoded_events[i]
		if _event_seen >= 0 and not _newer_u16(entry.seq, _event_seen):
			continue
		_event_seen = entry.seq
		if ARRIVAL_EVENTS.has(entry.type) or not _should_interpolate() or _predicted_here(NetCodec.event_subject(entry)):
			# About the body this machine predicts: drawn where that body is now.
			event_received.emit(entry.type, entry.payload, entry.tick)
			continue
		var held: NetEvents.Entry = NetEvents.Entry.new()
		held.copy_from(entry)
		_due_events.append(held)


## True when [param seat] is the body this machine predicts.
func _predicted_here(seat: int) -> bool:
	var link: PlayerNetLink = find_link(seat) if seat >= 0 else null
	return link != null and link.is_predicting()


static func _newer_u16(candidate: int, reference: int) -> bool:
	var difference: int = (candidate - reference + 0x10000) % 0x10000
	return difference != 0 and difference < 0x8000


## Re-measure how irregularly snapshots arrive, and set the playout buffer's depth from it.
func _measure_arrival(first: bool) -> void:
	if not first and _ring_count >= 2:
		var advanced: int = NetCodec.tick_delta(_slot(_ring_count - 2).tick, _newest().tick)
		if advanced > 0:
			_render_lag += float(advanced)
			_interval_ticks = float(advanced) if _interval_ticks <= 0.0 else lerpf(_interval_ticks, float(advanced), _JITTER_ALPHA)
	var settings: NetSettings = session.get_settings()
	if _last_arrival_seconds >= 0.0 and _interval_ticks > 0.0:
		var expected: float = _interval_ticks * _tick_seconds()
		var observed: float = _clock_seconds - _last_arrival_seconds
		_jitter_seconds = lerpf(_jitter_seconds, absf(observed - expected), _JITTER_ALPHA)
	_last_arrival_seconds = _clock_seconds
	var jitter_ticks: float = clampf(
		_jitter_seconds * 2.0 / _tick_seconds(), 0.0, float(settings.max_interpolation_jitter_ticks)
	)
	# Below a whole snapshot interval there is no second snapshot to interpolate towards.
	_delay_ticks = maxf(float(settings.interpolation_delay_ticks), maxf(_interval_ticks, 1.0)) + jitter_ticks
	if not _have_clock:
		_render_lag = _delay_ticks
		_have_clock = true


## Move the playout clock on by one authority tick, give or take the dilation taking drift out of it.
func _advance_clock(delta: float) -> void:
	_clock_seconds += delta
	if not _have_clock or _ring_count == 0 or not _should_interpolate():
		return
	var error: float = _render_lag - _delay_ticks
	if absf(error) > _CLOCK_SNAP_TICKS:
		_render_lag = _delay_ticks
	else:
		_render_lag -= 1.0 + clampf(error * _CLOCK_GAIN, -_MAX_DILATION, _MAX_DILATION)
	# Never behind both the oldest snapshot held and the target: a buffer still filling holds its first.
	var oldest_lag: float = float(NetCodec.tick_delta(_slot(0).tick, _newest().tick))
	_render_lag = clampf(_render_lag, -_extrapolation_ticks(), maxf(oldest_lag, _delay_ticks))


# --- Drawing ------------------------------------------------------------------

func _process(delta: float) -> void:
	play_back(delta)


## One frame of playback. Public because the cost test times it directly.
func play_back(_delta: float) -> void:
	if _is_authority:
		draw_host_at(float(_tick) - HOST_PLAYOUT_TICKS + Engine.get_physics_interpolation_fraction())
		return
	if not _have_clock or _ring_count == 0 or not _should_interpolate():
		return
	var lag: float = maxf(_render_lag - Engine.get_physics_interpolation_fraction(), -_extrapolation_ticks())
	_drawn_time = float(_newest().tick) - lag
	_draw(lag)
	# Events first: a death's DEATH is in hand when the record that shows it is converged.
	_present_due(_drawn_time)
	_apply_match(_drawn_time)


## Host: draw every body but its own at tick [param time], from the worlds it sent. Render-only:
## the avatar moves, the collider stays where physics has it.
func draw_host_at(time: float) -> void:
	var live: bool = _ring_count < 2 or session == null or session.get_peer_count() <= 1 or _scene == 0
	_drawn_time = MoveIntent.LIVE_WORLD if live else time
	var to_index: int = 0
	while not live and to_index < _ring_count - 1 and float(_slot(to_index).tick) < _drawn_time:
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
		if from_state.placed_counter != to_state.placed_counter:
			weight = 1.0
		var yaw: float = lerp_angle(from_state.yaw, to_state.yaw, weight)
		link.draw_avatar_at(Transform3D(Basis(Vector3.UP, yaw), from_state.position.lerp(to_state.position, weight)))


func _draw_live(link: PlayerNetLink) -> void:
	link.draw_avatar_at(Transform3D.IDENTITY, false)


## How far past the newest snapshot a body may be carried, in authority ticks.
func _extrapolation_ticks() -> float:
	return session.get_settings().max_extrapolation_seconds / _tick_seconds()


func _tick_seconds() -> float:
	return maxf(get_physics_process_delta_time(), 0.0001)


## Put every mirrored body where the playout clock says it is, [param lag] ticks behind the newest.
func _draw(lag: float) -> void:
	var newest: WorldSnapshot = _newest()
	if lag <= 0.0 or _ring_count == 1:
		_draw_extrapolated(newest, maxf(-lag, 0.0) * _tick_seconds())
		return
	# The newest snapshot at or behind the clock, and the one before it.
	var to_index: int = _ring_count - 1
	for i: int in _ring_count:
		if float(NetCodec.tick_delta(_slot(i).tick, newest.tick)) <= lag:
			to_index = i
			break
	var to_snapshot: WorldSnapshot = _slot(to_index)
	_apply_props(to_snapshot)
	if to_index == 0:
		_draw_extrapolated(to_snapshot, 0.0)
		return
	var from_snapshot: WorldSnapshot = _slot(to_index - 1)
	var lag_from: float = float(NetCodec.tick_delta(from_snapshot.tick, newest.tick))
	var lag_to: float = float(NetCodec.tick_delta(to_snapshot.tick, newest.tick))
	var span: float = lag_from - lag_to
	var weight: float = 1.0 if span <= 0.0 else clampf((lag_from - lag) / span, 0.0, 1.0)
	for link: PlayerNetLink in _links:
		var to_state: PlayerState = to_snapshot.find_seat(link.seat_index)
		if to_state == null:
			continue
		var from_state: PlayerState = from_snapshot.find_seat(link.seat_index)
		if from_state == null:
			_blend.copy_from(to_state)
		else:
			_blend.interpolate_from(from_state, to_state, weight)
		if link.is_predicting():
			# This machine's own body moves itself; what its power put in the world is the host's.
			link.apply_anchor(_blend)
		else:
			link.apply_state(_blend)


## Draw [param snapshot] carried [param seconds] forward along each body's own velocity.
func _draw_extrapolated(snapshot: WorldSnapshot, seconds: float) -> void:
	_apply_props(snapshot)
	var before: WorldSnapshot = null
	for i: int in range(1, _ring_count):
		if _slot(i) == snapshot:
			before = _slot(i - 1)
	for link: PlayerNetLink in _links:
		var state: PlayerState = snapshot.find_seat(link.seat_index)
		if state == null:
			continue
		var earlier: PlayerState = before.find_seat(link.seat_index) if before != null else null
		if earlier != null:
			# At this world, with the anchor's speed into it from the one before.
			_blend.interpolate_from(earlier, state, 1.0)
		else:
			_blend.copy_from(state)
		_blend.position += state.velocity * maxf(seconds, 0.0)
		if link.is_predicting():
			link.apply_anchor(_blend)
		else:
			link.apply_state(_blend)


## With interpolation off, everything remote is taken as it arrives.
func _draw_at_newest() -> void:
	_draw_extrapolated(_newest(), 0.0)


## Present the events the playout clock has reached, oldest first.
func _present_due(time: float) -> void:
	while not _due_events.is_empty() and float(_due_events[0].tick) <= time:
		var entry: NetEvents.Entry = _due_events.pop_front()
		event_received.emit(entry.type, entry.payload, entry.tick)


## Each match record the playout clock has reached at [param time], once and oldest first, when it changed.
func _apply_match(time: float) -> void:
	for i: int in _ring_count:
		var world: WorldSnapshot = _slot(i)
		if float(world.tick) > time:
			return
		if _match_tick >= 0 and not NetCodec.is_newer_tick(world.tick, _match_tick):
			continue
		var first: bool = _match_tick < 0
		_match_tick = world.tick
		if first or world.match_record != _match_record:
			_match_record = world.match_record
			match_due.emit(_match_record, world.tick, first)


## Each prop whose record [param snapshot] changes, once, when the playout clock reaches it.
func _apply_props(snapshot: WorldSnapshot) -> void:
	if _props_tick >= 0 and not NetCodec.is_newer_tick(snapshot.tick, _props_tick):
		return
	var before: WorldSnapshot = _find_world(_props_tick) if _props_tick >= 0 else null
	_props_tick = snapshot.tick
	for i: int in _prop_ids.size():
		var record: PackedByteArray = snapshot.find_prop(_prop_ids[i])
		if record.is_empty() or not is_instance_valid(_props[i]):
			continue
		if before != null and before.find_prop(_prop_ids[i]) == record:
			continue
		_props[i].call(&"net_apply", record)


# --- Rings --------------------------------------------------------------------

## Keep a copy of [param world] on the end of the ring, dropping the oldest. Returns the copy.
func _push_world(world: WorldSnapshot) -> WorldSnapshot:
	if _ring_count >= RING:
		_ring_start = (_ring_start + 1) % RING
		_ring_count -= 1
	var kept: WorldSnapshot = _slot(_ring_count)
	kept.copy_from(world)
	_ring_count += 1
	return kept


## The world kept for [param tick], or null.
func _find_world(tick: int) -> WorldSnapshot:
	if tick < 0:
		return null
	for i: int in _ring_count:
		if _slot(i).tick == tick:
			return _slot(i)
	return null


func _slot(index: int) -> WorldSnapshot:
	return _ring[(_ring_start + index) % RING]


## The newest world kept. Never called with an empty ring.
func _newest() -> WorldSnapshot:
	return _slot(maxi(_ring_count - 1, 0))


func _should_interpolate() -> bool:
	return session != null and session.get_settings().interpolate_remote_bodies


func _clear_worlds() -> void:
	_ring_start = 0
	_ring_count = 0
	_recipients.clear()
	_due_events.clear()
	_event_seen = -1
	_props_tick = -1
	_match_tick = -1
	_match_record = PackedByteArray()
	_have_clock = false
	_render_lag = 0.0
	_last_arrival_seconds = -1.0
	_jitter_seconds = 0.0
	_interval_ticks = 0.0
	_drawn_time = MoveIntent.LIVE_WORLD


func _on_connection_state_changed(_state: NetTransport.ConnectionState) -> void:
	refresh_role()


## One line, for logs and the harness.
func describe() -> String:
	return "NetReplicator(%s, %d bodies, tick %d, %d Hz)" % [
		"authority" if _is_authority else "client",
		_links.size(),
		_tick,
		session.get_settings().snapshot_hz if session != null else 0,
	]
