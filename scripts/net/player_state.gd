class_name PlayerState
extends RefCounted

## One body's authoritative state at one tick: what the listen server decided,
## on its way to every other machine.
##
## The counterpart of [MoveIntent]. Intent travels client to authority; state
## travels authority to everyone. Between them they are the entire wire format
## of the game today, and both are deliberately small enough to read in full.
##
## Reused rather than reallocated per packet -- see [NetCodec].

## Which player this describes. Peer ids, so it survives the tower changing
## hands; see [NetTransport].
var peer_id: int = 0

## The authority's physics tick this was sampled on. Wraps at 2^32, which at 60
## Hz is a little over two years of continuous play.
##
## Nothing consumes it yet beyond dropping out-of-order packets. It is here
## because reconciliation cannot be added later without it, and adding a field
## to the wire format after there are clients in the wild is a different and
## much worse problem.
var tick: int = 0

var position: Vector3 = Vector3.ZERO

## Carried even though the client does not integrate it. Without velocity there
## is nothing to extrapolate from, and extrapolation is the first thing that
## gets built on this.
var velocity: Vector3 = Vector3.ZERO

## Body yaw in radians. The whole body yaws in [PlayerController], so this is
## also the direction the player is facing.
var yaw: float = 0.0

## Head pitch in radians. Cosmetic for a remote body -- it aims nothing on this
## machine, because hit detection is the authority's -- but a body that does
## not look where it shoots reads as broken.
var pitch: float = 0.0

## Whether the authority had this body on the floor. Drives footsteps and
## landing effects on remote machines, which otherwise have to guess from a
## position delta and guess wrong on ramps.
var on_floor: bool = false


func clear() -> void:
	peer_id = 0
	tick = 0
	position = Vector3.ZERO
	velocity = Vector3.ZERO
	yaw = 0.0
	pitch = 0.0
	on_floor = false


func copy_from(other: PlayerState) -> void:
	peer_id = other.peer_id
	tick = other.tick
	position = other.position
	velocity = other.velocity
	yaw = other.yaw
	pitch = other.pitch
	on_floor = other.on_floor
