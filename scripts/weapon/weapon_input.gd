class_name WeaponInput
extends Node

## Turns a device into [method Rifle.trigger] for a rifle no body holds: a held rifle fires on its
## holder's commands ([method MatchController._step_command]), and its device trigger is switched off.
##
## This is the only script in the weapon that is allowed to touch [Input], and
## it is deliberately the thinnest thing in the directory: it holds no state
## about the weapon, makes no decision about whether a shot is a good idea, and
## contains no fallback behaviour if the rifle refuses. Delete it and the rifle
## still works; a bot AI drives the identical [method Rifle.try_fire] with no
## input layer at all, which is what makes headless bot matches exercise the
## real weapon.
##
## Mirrors [HumanIntentSource]'s role on the movement side.
##
## [b]Charged shots[/b]
##
## When [member WeaponProfile.charge_enabled] is on, the trigger means "hold to
## aim, release to fire" instead of "fire". This node still makes no decision
## about it: it reports press and release to the weapon and the weapon decides
## what a press and a release are worth. Which design is in play is a fact about
## the [WeaponProfile], never about the input, which is what keeps a bot calling
## [method Rifle.try_fire] and a human holding a mouse button playing the same
## weapon.

## The weapon this device drives.
@export var weapon: Rifle

## Grab the mouse as soon as this node is ready. Off by default, because the
## player scene's [HumanIntentSource] already owns the cursor and two nodes
## fighting over [member Input.mouse_mode] is a bug that only shows up on the
## frame a menu opens.
@export var capture_mouse_on_ready: bool = false

## Whether this device is currently being read. Mirrors what
## [method set_active] was last told, rather than being re-derived from
## [method Node.is_processing], so it stays the honest answer even for a node
## that has been paused for some unrelated reason.
##
## True by default, matching a freshly loaded node's own processing state: a
## bare [code]weapons/rifle.tscn[/code] with no match controller around
## it is a human's rifle.
var _active: bool = true


func _ready() -> void:
	WeaponActions.ensure_registered()
	if weapon == null:
		push_error("WeaponInput has no Rifle to drive; input will be ignored.")
		_active = false
		set_process(false)
		return
	if capture_mouse_on_ready:
		MouseFocus.set_play_wants(true)


## Polled rather than event-driven, matching [HumanIntentSource]: the rifle reads the button's state
## each frame, so a press across a reload needs no memory here.
func _process(_delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		# The cursor is loose, so the player is in a menu or has released the
		# window. Clicks there are not shots.
		return
	weapon.trigger(
		Input.is_action_just_pressed(WeaponActions.FIRE),
		Input.is_action_pressed(WeaponActions.FIRE),
		Input.is_action_just_released(WeaponActions.FIRE),
	)


## Enable or disable reading this device. A disabled source simply stops asking
## the rifle to fire; it does not touch the rifle's state, so a reload in
## progress continues to run out.
##
## A hold in progress IS dropped, because the trigger is about to stop being
## read and a charge that kept building while nobody was pressing anything would
## be a shot the player never took.
func set_active(active: bool) -> void:
	_active = active and weapon != null
	set_process(_active)
	if not active and weapon != null:
		weapon.cancel_charge()


## True while this device drives its rifle. [code]characters/bots/tower_shooter.tscn[/code] silences
## its copy with [member Node.process_mode] instead, so [method Node.can_process] counts too.
func is_active() -> bool:
	return _active and can_process()
