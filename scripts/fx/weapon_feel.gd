class_name FxWeaponFeel
extends Node

## Gives the rifle's single shot some weight, without ever taking the aim away.
##
## [b]The constraint that shapes the whole component[/b]
##
## PANOPTICON is a game about one careful shot. A rifle whose recoil moves where
## you are pointing turns that into a game about recovering from your own weapon,
## which is a different and worse game. So the kick here is required to give the
## aim back exactly, and the requirement is met structurally rather than by
## tuning:
##
## 1. The kick is applied to the camera's LOCAL transform by [FxCameraKick], not
##    to the body's yaw or the head's pitch. Nothing the player aimed is written
##    to at all.
## 2. Every channel of that kick is a closed-form function of elapsed time that
##    reaches exactly zero, so the camera settles bit-identically onto the
##    transform it started from rather than approximately near it.
## 3. The shot is resolved synchronously inside [method Rifle.try_fire], before
##    the first frame of the kick it causes exists, so a shot is never displaced
##    by its own recoil.
## 4. The whole kick is required to finish before the weapon can fire again --
##    see [method _check_recovery_fits] -- so a shot is never displaced by the
##    previous one either.
##
## Point 4 is the only one that can be broken by tuning, so it is checked at
## startup and complained about loudly.
##
## [b]Why so little of it[/b]
##
## The default kick is under two degrees. A single-shot rifle with a
## multi-second reload gets its weight from the silence that follows it, not from
## how far the screen moves; the kick's job is only to mark the instant the
## trigger broke, and a large one on a weapon that fires once every few seconds
## reads as the camera being broken rather than as force.
##
## Attach as a plain [Node] anywhere, pointed at the rifle and at the seat
## holder's [FxCameraKick].

## The weapon to listen to. A node reference rather than a path resolved once, so
## it survives [MatchController] reparenting the rifle onto a new seat holder.
@export var rifle: Rifle

## Where the kick is played. Without one this component does nothing, which is
## the honest degradation: there is no second place to put recoil.
@export var camera_kick: FxCameraKick

## This rig's own body, when it has one. There is exactly ONE rifle in a match and
## it is reparented onto whoever holds the tower, so every listener in the game
## hears every shot -- including the shots an AI seat holder takes. Set this to
## the body this rig belongs to and the rifle kicks this camera only while
## [member Rifle.shooter_body] is that body, which is precisely
## [MatchController]'s own record of who is holding the weapon.
##
## Leave it null and every shot by anyone counts, which is right for a weapon
## test scene with one shooter in it and wrong for a match.
@export var owner_body: CollisionObject3D

## Tunables.
@export var profile: FeedbackProfile

## Scales every recoil amount for this weapon. Exists so a second weapon can
## borrow the same curve at a different weight without a second profile.
@export_range(0.0, 4.0, 0.05) var recoil_scale: float = 1.0

## Go inert when there is no display server.
@export var headless_inert: bool = true

const HEADLESS_DISPLAY: String = "headless"

var _inert: bool = false


func _ready() -> void:
	if headless_inert and DisplayServer.get_name() == HEADLESS_DISPLAY:
		_inert = true
		return
	if profile == null:
		push_error("FxWeaponFeel has no FeedbackProfile; the rifle will not kick.")
		_inert = true
		return
	if rifle == null:
		push_error("FxWeaponFeel has no Rifle to listen to.")
		_inert = true
		return
	rifle.fired.connect(_on_fired)
	_check_recovery_fits()


# --- Public API ---------------------------------------------------------------

## Play the recoil directly, bypassing the weapon. For a test, and for a future
## networked client shown another player's shot.
func kick() -> void:
	if _inert or profile == null or not profile.enabled or camera_kick == null:
		return
	camera_kick.fire_recoil(recoil_scale)


## True when the shot that just happened was this rig's own. See
## [member owner_body].
func is_holding_the_rifle() -> bool:
	return owner_body == null or (rifle != null and rifle.shooter_body == owner_body)


func is_inert() -> bool:
	return _inert


# --- Signals ------------------------------------------------------------------

func _on_fired(_origin: Vector3, _end_point: Vector3) -> void:
	if not is_holding_the_rifle():
		return
	kick()


# --- Validation ---------------------------------------------------------------

## Complain if the kick can still be running when the weapon comes off reload.
##
## This is the one way the aim guarantee in the class description can be broken,
## and it is broken by editing a number rather than by editing code, so it is
## checked where the numbers are read rather than trusted to a comment. The bound
## is the weapon's FLOOR, not its current reload: match progression shortens the
## reload as the match runs and the floor is the shortest it can ever become.
func _check_recovery_fits() -> void:
	if rifle.profile == null:
		return
	var kick_duration: float = profile.get_recoil_duration()
	var soonest_shot: float = rifle.profile.shot_duration + rifle.get_reload_floor_seconds()
	if kick_duration > soonest_shot:
		push_warning(
			(
				"FxWeaponFeel: recoil lasts %.3fs but the rifle can fire again after %.3fs. "
				+ "Lower recoil_attack_seconds/recoil_recover_seconds or the kick will move a shot."
			)
			% [kick_duration, soonest_shot]
		)
