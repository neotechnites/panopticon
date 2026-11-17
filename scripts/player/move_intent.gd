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

## Absolute view (yaw, head pitch) in radians, from the machine that owns it; the wire's
## form of aim, as Quake's usercmd angles. Applied instead of [member look_delta] when set.
var view_angles: Vector2 = Vector2.ZERO
var view_absolute: bool = false

## The authority tick of the world the sender was drawing when it made this intent, or -1;
## what the authority rewinds other bodies to for its shot (Source's lag compensation).
var view_tick: int = -1

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
## 1-5 picks that power directly this tick (test keys); 0 = none.
var ability_slot: int = 0
## True on the tick E was pressed: lights a held cat grenade.
var cook_pressed: bool = false

## True on the tick shove was tapped. Resolved by the authority; see
## [method MatchController.apply_shove].
var shove_pressed: bool = false
## True on the tick the emote key was tapped; toggles the emote.
var emote_pressed: bool = false
## True on the tick the alternate emote key was tapped; toggles the emote with the alternate object.
var emote_alt_pressed: bool = false
## Wire only: running counts of the one-tick keys below (3 bits each), written by [PlayerNetLink]
## so a press outlives a lost packet; and the slot of the newest power press (0 = the picked power).
var press_counts: int = 0
var press_slot: int = 0
## True while the scope is asked up. Ignored by movement; the host drives the seat's optic with it.
var aim_held: bool = false
## Dev: hold for 300% ground speed. Local only; never on the wire.
var turbo_held: bool = false
## Dev: invincible to the rifle. Local only.
var godmode: bool = false


## Zero every field. Call before refilling, so a source can never leak a stale
## edge into the next tick.
func clear() -> void:
	move_direction = Vector2.ZERO
	look_delta = Vector2.ZERO
	view_angles = Vector2.ZERO
	view_absolute = false
	view_tick = -1
	jump_pressed = false
	jump_held = false
	slide_pressed = false
	slide_held = false
	fire_pressed = false
	fire_held = false
	ability_pressed = false
	ability_held = false
	ability_slot = 0
	cook_pressed = false
	shove_pressed = false
	emote_pressed = false
	emote_alt_pressed = false
	press_counts = 0
	press_slot = 0
	aim_held = false
	turbo_held = false
	godmode = false


## Drop every one-tick key: what a body out of the world sends, so no press waits for its return.
func clear_presses() -> void:
	ability_pressed = false
	ability_slot = 0
	cook_pressed = false
	shove_pressed = false
	emote_pressed = false
	emote_alt_pressed = false


## Clamp [member move_direction] to the unit disc.
func normalise() -> void:
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()


## Copy another intent's values into this one, without reallocating.
func copy_from(other: MoveIntent) -> void:
	move_direction = other.move_direction
	look_delta = other.look_delta
	view_angles = other.view_angles
	view_absolute = other.view_absolute
	view_tick = other.view_tick
	jump_pressed = other.jump_pressed
	jump_held = other.jump_held
	slide_pressed = other.slide_pressed
	slide_held = other.slide_held
	fire_pressed = other.fire_pressed
	fire_held = other.fire_held
	ability_pressed = other.ability_pressed
	ability_held = other.ability_held
	ability_slot = other.ability_slot
	cook_pressed = other.cook_pressed
	shove_pressed = other.shove_pressed
	emote_pressed = other.emote_pressed
	emote_alt_pressed = other.emote_alt_pressed
	press_counts = other.press_counts
	press_slot = other.press_slot
	aim_held = other.aim_held
	turbo_held = other.turbo_held
	godmode = other.godmode


# --- Press counts ---------------------------------------------------------------

## The keys [member press_counts] counts, in bit order.
enum Press { POWER, COOK, SHOVE, EMOTE, EMOTE_ALT }
const PRESS_KEYS: int = 5
const PRESS_BITS: int = 3
const PRESS_MODULUS: int = 1 << PRESS_BITS
const PRESS_COUNTS_MASK: int = (1 << (PRESS_KEYS * PRESS_BITS)) - 1


## How many times [param key] has been pressed, modulo [constant PRESS_MODULUS].
static func press_count(counts: int, key: int) -> int:
	return (counts >> (key * PRESS_BITS)) & (PRESS_MODULUS - 1)


## [param counts] with one more press of [param key].
static func press_added(counts: int, key: int) -> int:
	var shift: int = key * PRESS_BITS
	var next: int = (press_count(counts, key) + 1) & (PRESS_MODULUS - 1)
	return (counts & ~((PRESS_MODULUS - 1) << shift)) | (next << shift)


## Whether this intent presses [param key] on this tick.
func presses(key: int) -> bool:
	match key:
		Press.POWER:
			return ability_pressed or ability_slot > 0
		Press.COOK:
			return cook_pressed
		Press.SHOVE:
			return shove_pressed
		Press.EMOTE:
			return emote_pressed
		Press.EMOTE_ALT:
			return emote_alt_pressed
	return false
