class_name HandSender
extends RefCounted

## The host's sending half, for a test that carries its own wire: it samples the host's links into
## a world, keeps the ring, and codes each snapshot against the world the client last acknowledged,
## as [NetReplicator] does (DESIGN 3.4). The client acknowledges through its command packets.

var _ring: Array[WorldSnapshot] = []
var _recipient: NetReplicator.Recipient = NetReplicator.Recipient.new(-1)
var _info: NetCodec.SnapshotInfo = NetCodec.SnapshotInfo.new()
var _no_events: Array[NetEvents.Entry] = []


## [param links]' bodies at [param tick] in [param epoch], coded for the client in [param owner_seat]
## whose commands [param stream] runs.
func send(links: Array[PlayerNetLink], tick: int, epoch: int, owner_seat: int, stream: CommandStream) -> PackedByteArray:
	var world: WorldSnapshot = WorldSnapshot.new()
	NetReplicator.sample_bodies(world, links, tick, epoch)
	_ring.append(world)
	if _ring.size() > NetReplicator.RING:
		_ring.pop_front()
	var base: WorldSnapshot = null
	for kept: WorldSnapshot in _ring:
		if kept.tick == _recipient.acked:
			base = kept
	_info.cmd_ack = stream.get_ack() if stream != null else -1
	var payload: PackedByteArray = NetCodec.pack_snapshot(world, base, owner_seat, _no_events, _info)
	_recipient.note_sent(tick, -1)
	return payload


## The client's command packet arrived: its acknowledgement of a snapshot.
func take_commands(payload: PackedByteArray) -> void:
	_recipient.take_ack(NetCodec.command_snap_ack(payload))
