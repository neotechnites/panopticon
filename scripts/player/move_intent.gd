class_name MoveIntent
extends RefCounted

## The complete description of what a body is trying to do this tick.
##
## This is the seam between INPUT and MOVEMENT. [PlayerController] applies
## physics to a [MoveIntent] and never reads the keyboard or mouse itself, so a
## bot drives the identical controller by filling in the identical struct. If
## you find yourself calling [Input] from the controller, the seam has leaked.

## Desired move direction in the body's local space: x is right, y is forward.
## Length is clamped to 1.0 by [method normalise]; a shorter vector is a valid
## partial input (analogue stick, or a bot easing off).
var move_direction: Vector2 = Vector2.ZERO

## Rotation requested this tick, in radians: x turns (yaw), y pitches. Already
## scaled by sensitivity -- the controller applies it verbatim.
var look_delta: Vector2 = Vector2.ZERO

## True on the tick jump was first requested. Edge-triggered; feeds the jump
## buffer.
var jump_pressed: bool = false

## True for as long as jump is held. Drives auto bunny hopping.
var jump_held: bool = false

## True on the tick slide was first requested. Edge-triggered; feeds the slide
## buffer, so a press made just before touchdown still opens a slide on landing.
##
## [PlayerController] latches the rising edge itself rather than trusting this
## field to be one tick wide, so a source that reports the button as a level --
## a reused struct handed to [method PlayerController.set_intent], say -- opens
## exactly one slide per press like every other source.
var slide_pressed: bool = false

## True for as long as slide is held. A slide ends early when this goes false,
## unless [member MovementProfile.slide_requires_hold] is off.
var slide_held: bool = false

## Trigger. Ignored by movement; the net layer carries it to the rifle.
var fire_pressed: bool = false
var fire_held: bool = false

## The runner's power. Edge on the press; the level lets Armor Lock end on release.
var ability_pressed: bool = false
var ability_held: bool = false


## Zero every field. Call before refilling, so a source can never leak a stale
## edge into the next tick.
func clear() -> void:
	move_direction = Vector2.ZERO
	look_delta = Vector2.ZERO
	jump_pressed = false
	jump_held = false
	slide_pressed = false
	slide_held = false
	fire_pressed = false
	fire_held = false
	ability_pressed = false
	ability_held = false


## Clamp [member move_direction] to the unit disc.
func normalise() -> void:
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()


## Copy another intent's values into this one, without reallocating.
func copy_from(other: MoveIntent) -> void:
	move_direction = other.move_direction
	look_delta = other.look_delta
	jump_pressed = other.jump_pressed
	jump_held = other.jump_held
	slide_pressed = other.slide_pressed
	slide_held = other.slide_held
	fire_pressed = other.fire_pressed
	fire_held = other.fire_held
	ability_pressed = other.ability_pressed
	ability_held = other.ability_held
