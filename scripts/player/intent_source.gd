class_name IntentSource
extends Node

## Base class for anything that can drive a [PlayerController].
##
## Subclasses override [method poll] and return a filled-in [MoveIntent].
## [HumanIntentSource] reads the keyboard and mouse; [BotIntentSource] is
## written to directly by AI. The controller cannot tell the difference, which
## is the whole point: headless bot matches exercise the exact physics a human
## plays.
##
## The controller takes commands through [method next_command], which turns the
## levels a source reports into the edges of one consecutive stream.

## Reused every tick so polling never allocates.
var _intent: MoveIntent = MoveIntent.new()

## Set by the owning [PlayerController] at ready, so sources can read tunables
## (mouse sensitivity, for instance) from the same profile the physics uses.
var profile: MovementProfile = null

## The tick this machine draws other bodies at, stamped on each command (see
## [member MoveIntent.view_time]); unset means the live world. Set by [PlayerNetLink].
var view_clock: Callable

## The buttons of the last command handed out, which this one's edges are taken against.
var _last_buttons: int = 0


## Called once by the controller before the first poll.
func configure(movement_profile: MovementProfile) -> void:
	profile = movement_profile


## Produce this tick's levels. The returned object is owned by the source and
## is valid until the next call; copy it if you need to keep it.
func poll(_delta: float) -> MoveIntent:
	_intent.clear()
	return _intent


## How many commands the body runs this tick: one from a device, 0-2 from the wire.
func commands_due() -> int:
	return 1


## The next command to run, with its edges against the one before it.
func next_command(delta: float) -> MoveIntent:
	var command: MoveIntent = poll(delta)
	command.derive_edges(_last_buttons)
	_last_buttons = command.buttons
	command.view_time = view_clock.call() if view_clock.is_valid() else MoveIntent.LIVE_WORLD
	return command


## Take the next command's edges against nothing, as a stream that starts with it will.
func rebase_edges() -> void:
	_last_buttons = 0
