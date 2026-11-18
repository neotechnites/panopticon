class_name NetEvents
extends RefCounted

## The host's last [constant CAPACITY] transient events (DESIGN 6): each rides every snapshot to its targets
## until acknowledged or [constant TTL_TICKS] old (Quake 3's reliable server commands, with a TTL).

enum Type { NONE, SHOT, HIT, MISS, SHOVE_LANDED, SHOVE_KICK, CAT_BLAST }
enum Target { ALL, ONE, ALL_BUT }

const CAPACITY: int = 256
## A cosmetic older than this is wrong to show, so it is skipped rather than sent late.
const TTL_TICKS: int = 30


class Entry:
	extends RefCounted
	## Monotonic on the host; the wire carries its low 16 bits.
	var seq: int = -1
	var tick: int = 0
	var type: Type = Type.NONE
	var target: Target = Target.ALL
	var peer: int = 0
	var payload: PackedByteArray = PackedByteArray()

	func copy_from(other: Entry) -> void:
		seq = other.seq
		tick = other.tick
		type = other.type
		target = other.target
		peer = other.peer
		payload = other.payload

	func is_for(peer_id: int) -> bool:
		match target:
			Target.ONE:
				return peer == peer_id
			Target.ALL_BUT:
				return peer != peer_id
		return true


var _ring: Array[Entry] = []
var _next: int = 0
## Events skipped as too old, ever: what [code]test_net_cost[/code] reports.
var expired_total: int = 0


func _init() -> void:
	_ring.resize(CAPACITY)
	for i: int in CAPACITY:
		_ring[i] = Entry.new()


## Record one event at host tick [param tick]. Returns its sequence.
func push(type: Type, payload: PackedByteArray, tick: int, target: Target = Target.ALL, peer: int = 0) -> int:
	var entry: Entry = _ring[_next % CAPACITY]
	entry.seq = _next
	entry.tick = tick
	entry.type = type
	entry.target = target
	entry.peer = peer
	entry.payload = payload
	_next += 1
	return entry.seq


## The newest sequence recorded, or -1 before the first.
func newest() -> int:
	return _next - 1


## [param peer_id]'s events after [param after], young at [param now], oldest first into [param out] until
## [param room] bytes are spent; returns the newest sequence passed. Expiries past [param counted] count.
func collect(peer_id: int, after: int, now: int, room: int, out: Array[Entry], counted: int) -> int:
	out.clear()
	var passed: int = after
	var seq: int = maxi(after + 1, _next - CAPACITY)
	while seq < _next:
		var entry: Entry = _ring[seq % CAPACITY]
		if entry.is_for(peer_id):
			if NetCodec.tick_delta(entry.tick, now) > TTL_TICKS:
				expired_total += int(seq > counted)
			else:
				var size: int = NetCodec.EVENT_HEADER_SIZE + entry.payload.size()
				if size > room:
					break
				room -= size
				out.append(entry)
		passed = seq
		seq += 1
	return passed
