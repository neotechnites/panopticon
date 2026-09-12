class_name BotIntentSource
extends IntentSource

## Lets AI drive a [PlayerController] through exactly the same struct a human
## does. Write into [member command] from wherever the bot thinks, then let the
## controller poll as usual.
##
## Polling consumes the one-tick fields ([member MoveIntent.jump_pressed],
## [member MoveIntent.slide_pressed] and the look delta) so a bot that writes
## once cannot accidentally hold an edge down for every subsequent tick;
## sustained fields (move direction, held buttons) persist until changed,
## matching how a device behaves.

## The bot's standing orders. Safe to mutate at any time.
var command: MoveIntent = MoveIntent.new()

## Take a free shove when a rival walks into reach. Off makes this source do
## nothing a caller did not ask for.
@export var shove_enabled: bool = true

## What "into reach" means: metres ahead, and how square in front.
const SHOVE_RANGE_METRES: float = 2.0
const SHOVE_FACING_DOT: float = 0.7

## Seconds a bot leaves between shoves. Its own patience, not the match's
## cooldown -- the authority enforces that one.
const SHOVE_REST_SECONDS: float = 2.0

var _shove_rest: float = 0.0


## Aim by angular rate, in radians per second: positive [param yaw_rate] turns
## right, positive [param pitch_rate] looks up, and [param delta] is the tick
## length.
##
## Prefer this to assigning [member MoveIntent.look_delta] directly. That field
## is a per-tick delta already in radians, so a bot that reaches for the
## sensitivity conversion a mouse needs will feed the controller a value
## hundreds of times too large. Nothing errors: the yaw simply aliases past a
## full turn each tick, and the strafe silently produces speed loss instead of
## gain, which reads as a physics bug rather than as a caller bug.
func aim(yaw_rate: float, pitch_rate: float, delta: float) -> void:
	command.look_delta = Vector2(yaw_rate * delta, -pitch_rate * delta)


## Ask for a slide and keep holding it, exactly as a hand on the key would.
##
## Prefer this to writing [member MoveIntent.slide_pressed] alone: the press is
## an edge that [method poll] consumes, so a bot that sets only the edge opens a
## slide and then ends it on the very next tick, because
## [member MovementProfile.slide_requires_hold] reads the held flag and finds it
## false. That failure looks like a slide that will not stay open.
func hold_slide(held: bool) -> void:
	if held and not command.slide_held:
		command.slide_pressed = true
	command.slide_held = held


func poll(delta: float) -> MoveIntent:
	command.normalise()
	if shove_enabled:
		_look_for_a_shove(delta)
	_intent.copy_from(command)
	command.jump_pressed = false
	command.slide_pressed = false
	command.shove_pressed = false
	command.look_delta = Vector2.ZERO
	return _intent


## Tap shove when a living prisoner is already in front of a running bot. No
## pathing and no target choice: it takes what the lap has put there.
func _look_for_a_shove(delta: float) -> void:
	_shove_rest = maxf(_shove_rest - delta, 0.0)
	if _shove_rest > 0.0 or command.move_direction.y <= 0.0:
		return
	var body: PlayerController = get_parent() as PlayerController
	if body == null or not body.is_in_group(MatchController.RUNNER_GROUP):
		return
	var forward: Vector3 = -body.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 1e-6:
		return
	forward = forward.normalized()
	var here: Vector3 = body.global_position
	for node: Node in body.get_tree().get_nodes_in_group(MatchController.RUNNER_GROUP):
		var rival: PlayerController = node as PlayerController
		if rival == null or rival == body:
			continue
		var offset: Vector3 = rival.global_position - here
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > SHOVE_RANGE_METRES or distance < 1e-3:
			continue
		if forward.dot(offset / distance) < SHOVE_FACING_DOT:
			continue
		command.shove_pressed = true
		_shove_rest = SHOVE_REST_SECONDS
		return
