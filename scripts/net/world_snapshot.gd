class_name WorldSnapshot
extends RefCounted

## The whole lasting world at one host tick (DESIGN 3.4): bodies, predicted states, match record and
## props, by seat in fixed storage; one moment for a consistent frame, one baseline for a delta.

## The host tick every record here was sampled on.
var tick: int = 0
## The lobby epoch these bodies belong to ([method NetLobby.get_epoch]); 0 is none.
var epoch: int = 0
## Which seats have a body this tick, one bit each.
var present: int = 0
var states: Array[PlayerState] = []
## Each seat's exact predicted state; only a remote owner's seat is sampled, and a client keeps its own.
var owners: Array[PredictedState] = []
## Which seats' [member owners] hold a state that was sent, one bit each.
var owner_valid: int = 0
## The match's record ([method NetCodec.pack_match_state]), empty when there is no match.
var match_record: PackedByteArray = PackedByteArray()
## Each scene prop's record by id, ids ascending.
var prop_ids: PackedInt32Array = PackedInt32Array()
var prop_records: Array[PackedByteArray] = []


func _init() -> void:
	states.resize(NetTransport.MAX_PLAYERS)
	owners.resize(NetTransport.MAX_PLAYERS)
	for i: int in NetTransport.MAX_PLAYERS:
		states[i] = PlayerState.new()
		states[i].seat_index = i
		owners[i] = PredictedState.new()


## Drop every body, record and prop without dropping the storage.
func clear() -> void:
	tick = 0
	epoch = 0
	present = 0
	owner_valid = 0
	for i: int in NetTransport.MAX_PLAYERS:
		states[i].clear()
		states[i].seat_index = i
		owners[i].clear()
	match_record = PackedByteArray()
	prop_ids.clear()
	prop_records.clear()


## How many seats have a body.
func get_count() -> int:
	var count: int = 0
	for i: int in NetTransport.MAX_PLAYERS:
		count += (present >> i) & 1
	return count


func has_seat(seat_index: int) -> bool:
	return seat_index >= 0 and seat_index < NetTransport.MAX_PLAYERS and (present & (1 << seat_index)) != 0


## The record for [param seat_index], or null when this snapshot has no body there.
func find_seat(seat_index: int) -> PlayerState:
	return states[seat_index] if has_seat(seat_index) else null


## [param seat_index]'s record, marked present, for the caller to fill; null outside the seats.
func slot(seat_index: int) -> PlayerState:
	if seat_index < 0 or seat_index >= NetTransport.MAX_PLAYERS:
		return null
	present |= 1 << seat_index
	states[seat_index].seat_index = seat_index
	states[seat_index].tick = tick
	return states[seat_index]


## [param seat_index]'s predicted state, or null when none was sent.
func find_owner(seat_index: int) -> PredictedState:
	return owners[seat_index] if has_seat(seat_index) and (owner_valid & (1 << seat_index)) != 0 else null


## [param id]'s prop record, or an empty array.
func find_prop(id: int) -> PackedByteArray:
	var at: int = prop_ids.bsearch(id)
	return prop_records[at] if at < prop_ids.size() and prop_ids[at] == id else PackedByteArray()


## Set [param id]'s record, keeping ids ascending.
func set_prop(id: int, record: PackedByteArray) -> void:
	var at: int = prop_ids.bsearch(id)
	if at < prop_ids.size() and prop_ids[at] == id:
		prop_records[at] = record
		return
	prop_ids.insert(at, id)
	prop_records.insert(at, record)


func copy_from(other: WorldSnapshot) -> void:
	tick = other.tick
	epoch = other.epoch
	present = other.present
	owner_valid = other.owner_valid
	for i: int in NetTransport.MAX_PLAYERS:
		states[i].copy_from(other.states[i])
		owners[i].copy_from(other.owners[i])
	match_record = other.match_record
	prop_ids = other.prop_ids.duplicate()
	prop_records = other.prop_records.duplicate()
