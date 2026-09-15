extends Node

## B-roll only: walks one prisoner along the S2 boulder chain, jumping the gaps.
##
## The navmesh gives the chain no lake links (only S5 declares a `LavaSurface`),
## so no runner ever takes it and the shot has nothing in it. This drives one
## body over it by hand for the camera: the brain is switched off, the body's own
## physics still run, and every gap is crossed with [method PlayerController.launch]
## on an exact ballistic solution. Nothing here is reachable from a match.

## The chain's centre line, and the landings on it: bearing, top y, half length.
const CHAIN_RADIUS: float = 54.7
const LANDING_DEGREES: Array[float] = [82.6, 91.5, 99.8, 108.6, 117.1, 126.0]
const LANDING_TOP_Y: Array[float] = [23.05, 23.35, 22.95, 23.30, 23.15, 22.90]
const LANDING_HALF_METRES: Array[float] = [1.72, 1.65, 1.72, 1.68, 1.65, 1.72]
## Where the run starts and finishes, on the deck either side of the river.
const ENTRY_DEGREES: float = 76.5
const EXIT_DEGREES: float = 130.0
const BANK_Y: float = 23.0

const DRIVER := preload("res://tools/capture/stage_driver.gd")

const GATHER_SPEED: float = 2.6      ## crossing a landing, before the leap
const LEAP_SPEED: float = 8.0        ## horizontal speed carried over a gap
const EDGE_ARRIVAL_METRES: float = 0.35

var _body: PlayerController = null
var _brain: Node = null
var _next: int = 0
var _airborne: bool = false
var _started: bool = false


## Take [param body] off its brain and put it on the chain's near bank.
func install(body: PlayerController, brain: Node) -> void:
	_body = body
	_brain = brain
	if _brain != null:
		_brain.process_mode = Node.PROCESS_MODE_DISABLED
	_body.intent_source = null
	_body.global_position = _ring_point(ENTRY_DEGREES, BANK_Y + 0.1)
	_body.velocity = Vector3.ZERO
	_face(_tangent_at(ENTRY_DEGREES))
	_started = true


func _physics_process(_delta: float) -> void:
	if not _started or _body == null:
		return
	var intent := MoveIntent.new()
	_body.set_intent(intent)

	if not _body.is_on_floor():
		# Only a leap counts as airborne: the drop from the placement height does not.
		return
	if _airborne:
		# Landed: the next landing becomes the one after the one just reached.
		_airborne = false
		_next = mini(_next + 1, LANDING_DEGREES.size())

	if _next >= LANDING_DEGREES.size():
		_walk_to(_ring_point(EXIT_DEGREES, BANK_Y))
		return

	var here: Vector3 = _body.global_position
	var launch_from: Vector3 = _leading_edge()
	if _flat_distance(here, launch_from) <= EDGE_ARRIVAL_METRES:
		_leap_to(_landing_point(_next))
	else:
		_walk_to(launch_from)


# --- Driving the body ---------------------------------------------------------

## Hold [constant GATHER_SPEED] straight at [param target], facing the way it goes.
func _walk_to(target: Vector3) -> void:
	var flat: Vector3 = Vector3(target.x - _body.global_position.x, 0.0, target.z - _body.global_position.z)
	if flat.length() < 0.001:
		return
	var direction: Vector3 = flat.normalized()
	_body.velocity = Vector3(
		direction.x * GATHER_SPEED, _body.velocity.y, direction.z * GATHER_SPEED
	)
	_face(direction)


## Throw the body at [param target] so it arrives there, not near there.
func _leap_to(target: Vector3) -> void:
	var velocity: Vector3 = DRIVER.launch_velocity(_body, target, LEAP_SPEED)
	if velocity == Vector3.ZERO:
		return
	_face(Vector3(velocity.x, 0.0, velocity.z).normalized())
	_body.launch(velocity, DRIVER.flight_seconds(_body, target, LEAP_SPEED) * 0.9)
	_airborne = true


func _face(direction: Vector3) -> void:
	_body.rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)


# --- The chain ----------------------------------------------------------------

## The point on landing [param index] a body stands on.
func _landing_point(index: int) -> Vector3:
	return _ring_point(LANDING_DEGREES[index], LANDING_TOP_Y[index] + 0.05)


## The far edge of whatever is under the body now: where the next leap starts.
func _leading_edge() -> Vector3:
	if _next == 0:
		return _ring_point(ENTRY_DEGREES + 0.8, BANK_Y + 0.05)
	var index: int = _next - 1
	var span: float = rad_to_deg(LANDING_HALF_METRES[index] / CHAIN_RADIUS)
	return _ring_point(LANDING_DEGREES[index] + span, LANDING_TOP_Y[index] + 0.05)


func _tangent_at(degrees: float) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(-sin(angle), 0.0, cos(angle))


func _ring_point(degrees: float, height: float) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(cos(angle) * CHAIN_RADIUS, height, sin(angle) * CHAIN_RADIUS)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
