class_name IntentSource
extends Node

## Base class for anything that can drive a [PlayerController].
##
## Subclasses override [method poll] and return a filled-in [MoveIntent].
## [HumanIntentSource] reads the keyboard and mouse; [BotIntentSource] is
## written to directly by AI. The controller cannot tell the difference, which
## is the whole point: headless bot matches exercise the exact physics a human
## plays.

## Reused every tick so polling never allocates.
var _intent: MoveIntent = MoveIntent.new()

## Set by the owning [PlayerController] at ready, so sources can read tunables
## (mouse sensitivity, for instance) from the same profile the physics uses.
var profile: MovementProfile = null


## Called once by the controller before the first poll.
func configure(movement_profile: MovementProfile) -> void:
	profile = movement_profile


## Produce this tick's intent. The returned object is owned by the source and
## is valid until the next call; copy it if you need to keep it.
func poll(_delta: float) -> MoveIntent:
	_intent.clear()
	return _intent
