class_name WeaponInput
extends Node

## Turns a device into calls to [method Rifle.try_fire].
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

## When true, holding the trigger fires again the moment the rifle is ready.
##
## On by default, and it is not a convenience. The reload is measured in
## seconds, so requiring a fresh click on the exact frame the weapon comes back
## would tax reaction time on a beat the player has been watching count down for
## two seconds -- a dexterity test the design never asked for. The interesting
## decision is *whether* to spend the shot and *where* to be pointing, not
## whether you can click on cue. Turn it off for a variant that wants the
## opposite.
@export var allow_held_fire: bool = true

## Grab the mouse as soon as this node is ready. Off by default, because the
## player scene's [HumanIntentSource] already owns the cursor and two nodes
## fighting over [member Input.mouse_mode] is a bug that only shows up on the
## frame a menu opens.
@export var capture_mouse_on_ready: bool = false


func _ready() -> void:
	WeaponActions.ensure_registered()
	if weapon == null:
		push_error("WeaponInput has no Rifle to drive; input will be ignored.")
		set_process(false)
		return
	if capture_mouse_on_ready:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Polled rather than event-driven, matching [HumanIntentSource]. An event
## handler would have to remember an unconsumed press across the whole reload to
## support [member allow_held_fire]; polling the button's current state each
## frame needs no memory at all and cannot desynchronise from the device.
func _process(_delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		# The cursor is loose, so the player is in a menu or has released the
		# window. Clicks there are not shots.
		return
	if _is_charged_weapon():
		_drive_charge()
		return
	var wants_fire: bool = (
		Input.is_action_pressed(WeaponActions.FIRE)
		if allow_held_fire
		else Input.is_action_just_pressed(WeaponActions.FIRE)
	)
	if wants_fire:
		weapon.try_fire()


## Enable or disable reading this device. A disabled source simply stops asking
## the rifle to fire; it does not touch the rifle's state, so a reload in
## progress continues to run out.
##
## A hold in progress IS dropped, because the trigger is about to stop being
## read and a charge that kept building while nobody was pressing anything would
## be a shot the player never took.
func set_active(active: bool) -> void:
	set_process(active and weapon != null)
	if not active and weapon != null:
		weapon.cancel_charge()


## Whether the weapon in hand charges rather than fires on press. A fact about
## the profile, read every frame because a sweep can hand the same rifle a
## different profile between rounds.
func _is_charged_weapon() -> bool:
	return weapon.profile != null and weapon.profile.charge_enabled


## Press starts the hold, release takes the shot.
##
## [member allow_held_fire] is deliberately ignored here. Its whole purpose is
## to spare the player a reaction test on the frame the reload ends, and a
## charged weapon has no such frame: the trigger is already down, the charge is
## already building, and the shot goes when the player decides it goes.
func _drive_charge() -> void:
	if Input.is_action_just_pressed(WeaponActions.FIRE):
		weapon.begin_charge()
	elif Input.is_action_just_released(WeaponActions.FIRE):
		weapon.release_charge()
