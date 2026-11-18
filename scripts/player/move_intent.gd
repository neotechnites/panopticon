class_name MoveIntent
extends RefCounted

## One command: everything a body is trying to do for one tick (Quake's usercmd).
##
## This is the seam between INPUT and MOVEMENT. [PlayerController] applies
## physics to a [MoveIntent] and never reads the keyboard or mouse itself, so a
## bot drives the identical controller by filling in the identical struct. If
## you find yourself calling [Input] from the controller, the seam has leaked.
##
## Buttons are LEVELS ([member buttons]); the edges ([member pressed],
## [member released]) are derived from consecutive commands by [method IntentSource.next_command]
## and never sent. A source may report a one-tick tap by setting a [code]*_pressed[/code]
## flag: it counts as the key held for that command.

## The buttons, one bit each, in wire order.
const JUMP: int = 1 << 0
const SLIDE: int = 1 << 1
const FIRE: int = 1 << 2
const AIM: int = 1 << 3
const SHOVE: int = 1 << 4
const COOK: int = 1 << 5
const EMOTE: int = 1 << 6
const EMOTE_ALT: int = 1 << 7
const POWER: int = 1 << 8
## Power keys 1-5 pick that power outright: bit [code]POWER_1 << (n - 1)[/code].
const POWER_1: int = 1 << 9
const POWER_SLOTS: int = 5
const ALL_POWER_KEYS: int = POWER | (((1 << POWER_SLOTS) - 1) * POWER_1)
const BUTTON_MASK: int = (1 << 14) - 1

## Desired move direction in the body's local space: x is right, y is forward.
## Length is clamped to 1.0 by [method normalise]; a shorter vector is a valid
## partial input (analogue stick, or a bot easing off).
var move_direction: Vector2 = Vector2.ZERO

## Rotation requested this tick, in radians: x turns (yaw), y pitches. Already
## scaled by sensitivity -- the controller applies it verbatim. Never on the wire.
var look_delta: Vector2 = Vector2.ZERO

## Absolute view (yaw, head pitch) in radians, from the machine that owns it; the wire's
## form of aim, as Quake's usercmd angles. Applied instead of [member look_delta] when set.
var view_angles: Vector2 = Vector2.ZERO
var view_absolute: bool = false

## A [member view_time] naming no drawn world: the shot is traced against the live one.
const LIVE_WORLD: float = -INF

## The authority tick (fractional) the sender was drawing other bodies at, or [constant LIVE_WORLD]:
## what the authority rewinds them to for this command's shot (Source's lag compensation).
var view_time: float = LIVE_WORLD

## Levels: which buttons are down for this command.
var buttons: int = 0
## Edges against the previous command of the same stream: went down, went up.
var pressed: int = 0
var released: int = 0

## Dev: hold for 300% ground speed. Local only; never on the wire.
var turbo_held: bool = false
## Dev: invincible to the rifle. Local only.
var godmode: bool = false

var jump_held: bool:
	get:
		return (buttons & JUMP) != 0
	set(on):
		buttons = _with(buttons, JUMP, on)
var jump_pressed: bool:
	get:
		return (pressed & JUMP) != 0
	set(on):
		pressed = _with(pressed, JUMP, on)
var slide_held: bool:
	get:
		return (buttons & SLIDE) != 0
	set(on):
		buttons = _with(buttons, SLIDE, on)
var slide_pressed: bool:
	get:
		return (pressed & SLIDE) != 0
	set(on):
		pressed = _with(pressed, SLIDE, on)
## Trigger. Ignored by movement; the seat's weapon gate reads it.
var fire_held: bool:
	get:
		return (buttons & FIRE) != 0
	set(on):
		buttons = _with(buttons, FIRE, on)
var fire_pressed: bool:
	get:
		return (pressed & FIRE) != 0
	set(on):
		pressed = _with(pressed, FIRE, on)
## True while the scope is asked up. Ignored by movement; the host drives the seat's optic with it.
var aim_held: bool:
	get:
		return (buttons & AIM) != 0
	set(on):
		buttons = _with(buttons, AIM, on)
## Shove, resolved by the authority; see [method MatchController.apply_shove].
var shove_pressed: bool:
	get:
		return (pressed & SHOVE) != 0
	set(on):
		pressed = _with(pressed, SHOVE, on)
## Lights a held cat grenade.
var cook_pressed: bool:
	get:
		return (pressed & COOK) != 0
	set(on):
		pressed = _with(pressed, COOK, on)
## Toggles the emote; the alternate key toggles it with the alternate object.
var emote_pressed: bool:
	get:
		return (pressed & EMOTE) != 0
	set(on):
		pressed = _with(pressed, EMOTE, on)
var emote_alt_pressed: bool:
	get:
		return (pressed & EMOTE_ALT) != 0
	set(on):
		pressed = _with(pressed, EMOTE_ALT, on)
## The runner's power key (the rules' pick). The level is any power key, so Armor Lock ends on release.
var ability_pressed: bool:
	get:
		return (pressed & POWER) != 0
	set(on):
		pressed = _with(pressed, POWER, on)
var ability_held: bool:
	get:
		return (buttons & ALL_POWER_KEYS) != 0
	set(on):
		buttons = buttons | POWER if on else buttons & ~ALL_POWER_KEYS
## The power key 1-5 that went down on this command (the lowest, if several), or 0 for none.
var ability_slot: int:
	get:
		for slot: int in POWER_SLOTS:
			if (pressed & (POWER_1 << slot)) != 0:
				return slot + 1
		return 0
	set(slot):
		pressed &= ~(ALL_POWER_KEYS & ~POWER)
		if slot >= 1 and slot <= POWER_SLOTS:
			pressed |= POWER_1 << (slot - 1)


## Zero every field. Call before refilling, so a source can never leak a stale
## edge into the next tick.
func clear() -> void:
	move_direction = Vector2.ZERO
	look_delta = Vector2.ZERO
	view_angles = Vector2.ZERO
	view_absolute = false
	view_time = LIVE_WORLD
	buttons = 0
	pressed = 0
	released = 0
	turbo_held = false
	godmode = false


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
	view_time = other.view_time
	buttons = other.buttons
	pressed = other.pressed
	released = other.released
	turbo_held = other.turbo_held
	godmode = other.godmode


## Take the edges this command makes after [param previous_buttons]; taps count as held first.
func derive_edges(previous_buttons: int) -> void:
	buttons = (buttons | pressed) & BUTTON_MASK
	pressed = buttons & ~previous_buttons
	released = previous_buttons & ~buttons


static func _with(mask: int, bit: int, on: bool) -> int:
	return mask | bit if on else mask & ~bit
