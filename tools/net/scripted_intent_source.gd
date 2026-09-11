class_name ScriptedIntentSource
extends IntentSource

## A canned human for headless net runs: walks forward, sweeps aim, fires.

## Walk in bursts: this many seconds on, then this many off.
@export var walk_seconds: float = 3.0
@export var rest_seconds: float = 2.0
## Yaw sweep per second while walking, radians.
@export var yaw_rate: float = 0.15
## First trigger pull, seconds after start; 0 or less never fires.
@export var fire_at: float = 4.0
## Pull again this often after the first; 0 never repeats.
@export var fire_every: float = 0.0

var _elapsed: float = 0.0
var _next_fire: float = -1.0


func _ready() -> void:
	_next_fire = fire_at


func poll(delta: float) -> MoveIntent:
	_elapsed += delta
	_intent.clear()
	if _elapsed < 1.0:
		return _intent
	var cycle: float = fmod(_elapsed - 1.0, walk_seconds + rest_seconds)
	if cycle < walk_seconds:
		_intent.move_direction = Vector2(0.0, 1.0)
		_intent.look_delta = Vector2(yaw_rate * delta, 0.0)
	if _next_fire > 0.0 and _elapsed >= _next_fire:
		_intent.fire_pressed = true
		_next_fire = _elapsed + fire_every if fire_every > 0.0 else -1.0
	return _intent
