class_name WorldSnapshot
extends RefCounted

## Every body's state at one authority tick: one packet, one moment, the whole
## world a client has to draw.
##
## [b]Why one packet and not one per body[/b]
##
## The obvious shape is for each body to send its own state, and it is wrong in
## two ways that only show up later. It multiplies the per-packet overhead by
## the player count -- an RPC's node path and header cost more than the 34
## bytes of state they carry -- and, worse, it lets a client draw a frame
## assembled from bodies sampled at different ticks. A prisoner squeezing past
## the tower would be drawn against a wall that had moved on. One packet per
## tick makes a client's world internally consistent by construction, which is
## the property interpolation needs and the property a hit marker will need
## when hits are replicated.
##
## [b]Fixed storage[/b]
##
## Holds [constant NetTransport.MAX_PLAYERS] [PlayerState] objects for its whole
## life and reports [member count] of them as live. Decoding writes into those
## objects rather than allocating new ones, so the receive path at 30 Hz
## allocates only the [PackedByteArray] the engine hands it.

## The authority's physics tick every state here was sampled on. Shared, which
## is the point: see the class docs.
var tick: int = 0

## How many of [member states] are meaningful this snapshot.
var count: int = 0

## Fixed pool, never resized. Read [member count] entries and ignore the rest.
var states: Array[PlayerState] = []


func _init() -> void:
	states.resize(NetTransport.MAX_PLAYERS)
	for i: int in NetTransport.MAX_PLAYERS:
		states[i] = PlayerState.new()


## Drop every body without dropping the storage.
func clear() -> void:
	tick = 0
	count = 0


## Add one body's state, copied in. Returns false when the snapshot is already
## full, which can only happen if a peer claims more bodies than the session
## can hold -- so the caller drops the packet rather than growing to fit it.
func append(state: PlayerState) -> bool:
	if count >= states.size():
		return false
	states[count].copy_from(state)
	count += 1
	return true


## The next free slot, for a caller that would rather fill it in place than
## build a state and copy it. Advance [member count] yourself with
## [method commit] once it is filled.
func next_slot() -> PlayerState:
	if count >= states.size():
		return null
	return states[count]


## Accept the slot [method next_slot] handed out.
func commit() -> void:
	count = mini(count + 1, states.size())


## The state for [param seat_index], or null when this snapshot does not
## describe that seat.
##
## Linear, over at most eight entries. A dictionary would be faster in theory
## and slower in practice at this size, and it would allocate.
func find_seat(seat_index: int) -> PlayerState:
	for i: int in count:
		if states[i].seat_index == seat_index:
			return states[i]
	return null


func copy_from(other: WorldSnapshot) -> void:
	tick = other.tick
	count = other.count
	for i: int in count:
		states[i].copy_from(other.states[i])
