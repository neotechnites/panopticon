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
## Intent does not come through here. A client owns exactly one body, so its
## intent is already one packet, and it is addressed to that body's own
## [PlayerNetLink] -- which is also the only node that knows whose packets it
## is allowed to take.
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
## [b]How a client reconciles: it does not[/b]
##
## Stated plainly because it is the honest headline of this whole file. A
## client runs no simulation. It holds the last two snapshots, draws every body
## -- including its own -- at the moment one snapshot interval behind the newer
## of them, and slides between the two. That is INTERPOLATION, and it is all
## there is:
##
## - [b]No prediction.[/b] A client's own body does not move until a snapshot
##   arrives, so local input costs a full round trip of visible delay. This is
##   the single biggest thing missing and the reason this is not shippable feel
##   yet.
## - [b]No reconciliation.[/b] There is no buffer of unacknowledged inputs to
##   replay against a correction, which is why prediction cannot simply be
##   switched on: it needs the authority to say which input it had last seen,
##   and no packet carries that.
## - [b]No lag compensation.[/b] Shots are resolved against where the authority
##   thinks bodies are now, not where the shooter saw them. On a listen server
##   that quietly favours the host, and it is a design question rather than a
##   bug -- see the report.
## - [b]No extrapolation.[/b] A snapshot that never arrives leaves bodies
##   parked at the last one rather than sailing on. Freezing is wrong; sailing
##   on and then snapping back is wrong in a way that looks like a physics bug,
##   so the cheaper wrong was chosen deliberately.
## - [b]No delta compression, no acknowledgement, no interest management.[/b]
##   Every field of every body goes every snapshot to everybody. Cheap at eight
##   players; not a habit to keep.
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

## The two snapshots a client is currently drawing between, and how far along
## it is. Client-only.
var _previous: WorldSnapshot = WorldSnapshot.new()
var _latest: WorldSnapshot = WorldSnapshot.new()
var _have_previous: bool = false
var _have_latest: bool = false
var _playback_seconds: float = 0.0

## Simulated seconds the two buffered snapshots are apart, measured from their
## ticks rather than assumed from settings -- the host's rate is the host's to
## choose and a client that assumed 30 Hz would play a 20 Hz feed too fast.
var _playback_span: float = 0.0

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

var _is_authority: bool = false


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


func find_link(seat_index: int) -> PlayerNetLink:
	for link: PlayerNetLink in _links:
		if link.seat_index == seat_index:
			return link
	return null


func get_link_count() -> int:
	return _links.size()


## The authority's current tick. Stamped on outgoing snapshots and handed to
## [PlayerNetLink] so intent and state carry the same clock.
func get_tick() -> int:
	return _tick


## The authority tick of the newest snapshot a client has applied, or -1.
func get_latest_tick() -> int:
	return _latest.tick if _have_latest else -1


# --- Sending ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _is_authority:
		return
	_tick += 1
	if session == null or not session.is_established() or session.get_peer_count() <= 1:
		# Offline -- single player, or the headless bot harness -- is
		# authoritative with nobody to tell. A lone host has the same shape.
		# The tick still advances: it is the authority's clock, not a counter of
		# packets sent.
		return

	# Every tick, not at the snapshot rate: a hologram is a body the tower is
	# shooting at, and one drawn 33 ms behind is one a client's shot misses.
	_drive_decoys()

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
	rpc(&"_receive_snapshot", NetCodec.pack_snapshot(_outgoing))
	snapshot_sent.emit(_outgoing.tick, _outgoing.count)


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


## Authority to everyone, once, when a runner's hologram appears.
@rpc("authority", "reliable", "call_remote", 0)
func _decoy_spawned(seat_index: int, epoch: int, position: Vector3, yaw: float) -> void:
	if _is_authority or not position.is_finite() or not is_finite(yaw):
		return
	_decoy_epochs[seat_index] = epoch
	_place_decoy(seat_index, position, yaw)


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


func _place_decoy(seat_index: int, position: Vector3, yaw: float) -> void:
	var power: RunnerPower = _power_of(seat_index)
	if power != null:
		power.present_decoy(position, yaw)


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
	if not NetCodec.unpack_snapshot(payload, _incoming):
		return
	if _have_latest and not NetCodec.is_newer_tick(_incoming.tick, _latest.tick):
		# Reordered by UDP and older than one already shown.
		return
	apply_snapshot(_incoming)


## Take a snapshot as though it had arrived over the wire. Public because a
## test and a future replay viewer both drive it directly.
func apply_snapshot(snapshot: WorldSnapshot) -> void:
	if _have_latest:
		_previous.copy_from(_latest)
		_have_previous = true
		var ticks: int = NetCodec.tick_delta(_previous.tick, snapshot.tick)
		# A non-positive gap means a duplicate or a reorder that slipped
		# through; fall back to the nominal interval rather than dividing by it.
		_playback_span = (
			float(ticks) * get_physics_process_delta_time() if ticks > 0
			else session.get_settings().get_snapshot_interval()
		)
	_latest.copy_from(snapshot)
	_have_latest = true
	_playback_seconds = 0.0

	if not _should_interpolate():
		_present(_latest)
	snapshot_received.emit(_latest.tick, _latest.count)


## Play the buffered snapshots back.
##
## Per drawn frame rather than per physics tick: this moves bodies for the
## camera, not for the simulation, and on a client there is no simulation for
## it to be in step with.
func _process(delta: float) -> void:
	if _is_authority or not _should_interpolate() or not _have_previous:
		return
	_playback_seconds += delta
	if _playback_span <= 0.0:
		return
	# Clamped, never extrapolated past 1.0. A snapshot that never arrives parks
	# the bodies where they were last seen; see the class docs for why that
	# wrong was preferred to the other one.
	var weight: float = clampf(_playback_seconds / _playback_span, 0.0, 1.0)
	for link: PlayerNetLink in _links:
		var to: PlayerState = _latest.find_seat(link.seat_index)
		if to == null:
			continue
		var from: PlayerState = _previous.find_seat(link.seat_index)
		if from == null:
			link.apply_state(to)
			continue
		_blend.interpolate_from(from, to, weight)
		link.apply_state(_blend)


## Put a snapshot straight onto the bodies, with no blending.
func _present(snapshot: WorldSnapshot) -> void:
	for i: int in snapshot.count:
		var state: PlayerState = snapshot.states[i]
		var link: PlayerNetLink = find_link(state.seat_index)
		if link != null:
			link.apply_state(state)


func _should_interpolate() -> bool:
	return session != null and session.get_settings().interpolate_remote_bodies


func _clear_playback() -> void:
	_decoy_tracks.clear()
	_decoy_epochs.clear()
	_have_previous = false
	_have_latest = false
	_playback_seconds = 0.0
	_playback_span = 0.0
	_previous.clear()
	_latest.clear()


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
