class_name PlayerState
extends RefCounted

## One body's authoritative state at one tick: what the listen server decided,
## on its way to every other machine.
##
## The counterpart of [MoveIntent]. Intent travels client to authority; state
## travels authority to everyone, batched into a [WorldSnapshot]. Between them
## they are the entire wire format of the game today, and both are deliberately
## small enough to read in full.
##
## Reused rather than reallocated per packet -- see [NetCodec].

## Which SEAT this describes, not which peer.
##
## This was a peer id once and it was wrong. Bots fill seats -- that is how this
## game gets tested at all -- and a bot has no peer to be named by, so a body
## keyed on a peer id is a body that cannot be replicated when a bot is driving
## it. See [LobbySeat].
var seat_index: int = 0

## The authority's physics tick this was sampled on. Wraps at 2^32, which at 60
## Hz is a little over two years of continuous play.
##
## Consumed for two things: discarding a snapshot that UDP delivered out of
## order, and dating the two snapshots [PlayerNetLink] interpolates between.
## The third use -- telling a client which of its own inputs the authority had
## seen when it produced this -- is what reconciliation needs and is not
## implemented.
var tick: int = 0

var position: Vector3 = Vector3.ZERO

## Carried even though the client does not integrate it. Without velocity there
## is nothing to extrapolate from, and extrapolation is what covers a snapshot
## that never arrives.
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
	seat_index = 0
	tick = 0
	position = Vector3.ZERO
	velocity = Vector3.ZERO
	yaw = 0.0
	pitch = 0.0
	on_floor = false


func copy_from(other: PlayerState) -> void:
	seat_index = other.seat_index
	tick = other.tick
	position = other.position
	velocity = other.velocity
	yaw = other.yaw
	pitch = other.pitch
	on_floor = other.on_floor


## Blend towards [param other] by [param weight], writing into this state.
##
## Position and velocity lerp; the two angles take the short way round, because
## a body crossing north with a plain lerp between 3.1 and -3.1 radians spins
## the long way and reads as a body doing a pirouette every lap.
##
## [member on_floor] and [member tick] are taken from whichever end the weight
## is nearer: they are facts about a moment, and half a fact is not one.
func interpolate_from(from: PlayerState, to: PlayerState, weight: float) -> void:
	var t: float = clampf(weight, 0.0, 1.0)
	seat_index = to.seat_index
	position = from.position.lerp(to.position, t)
	velocity = from.velocity.lerp(to.velocity, t)
	yaw = lerp_angle(from.yaw, to.yaw, t)
	pitch = lerp_angle(from.pitch, to.pitch, t)
	if t < 0.5:
		tick = from.tick
		on_floor = from.on_floor
	else:
		tick = to.tick
		on_floor = to.on_floor
