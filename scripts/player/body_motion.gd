extends RefCounted

## What one body is doing this frame, sampled once by its avatar for every procedural layer on the skeleton.
## Model space throughout: +Z the way the toes point, +X the body's left, +Y up.

## Seconds the slow velocity trails the real one by; the gap between them is the surge.
const SURGE_SECONDS: float = 0.28

## False while the body is dead; every layer fades out.
var live: bool = true
## True while the ragdoll owns the skeleton; every layer stops at once.
var limp: bool = false
var grounded: bool = true
var sliding: bool = false
## A rifle is in the hands, so the hold owns the pitch.
var holding: bool = false
## Horizontal speed, m/s, and that as a share of the profile's ground speed.
var speed: float = 0.0
var pace: float = 0.0
## Velocity gained over the last beat, as a share of ground speed: where the body is being pushed.
var surge: Vector3 = Vector3.ZERO
## The velocity, and its change since last frame, in world space.
var velocity: Vector3 = Vector3.ZERO
var step: Vector3 = Vector3.ZERO
## World to model, rotation only.
var to_model: Basis = Basis.IDENTITY

var _slow: Vector3 = Vector3.ZERO


## Read [param body] once; [param model_basis] is the avatar's world basis.
func sample(body: PlayerController, model_basis: Basis, reference_speed: float, delta: float) -> void:
	var now: Vector3 = body.velocity
	step = now - velocity
	velocity = now
	grounded = body.is_grounded()
	sliding = body.is_sliding()
	speed = Vector2(now.x, now.z).length()
	pace = speed / maxf(reference_speed, 0.01)
	to_model = model_basis.orthonormalized().inverse()
	var flat: Vector3 = Vector3(now.x, 0.0, now.z)
	_slow = _slow.lerp(flat, 1.0 - exp(-delta / SURGE_SECONDS))
	surge = to_model * (flat - _slow) / maxf(reference_speed, 0.01)
