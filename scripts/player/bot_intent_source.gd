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


func poll(_delta: float) -> MoveIntent:
	command.normalise()
	_intent.copy_from(command)
	command.jump_pressed = false
	command.slide_pressed = false
	command.look_delta = Vector2.ZERO
	return _intent
