class_name RifleRecoil
extends Node

## Kicks [code]Rifle/ViewModel[/code] when a shot actually resolves, and brings
## it back.
##
## [b]Why this exists next to the already-shipped camera recoil[/b]
##
## [FxWeaponFeel] and [FxCameraKick] already give the shooter's aim a kick, and
## it is deliberately tiny and required to finish long before the reload does,
## so a player can never feel it move their crosshair. This is a separate,
## additive thing: it moves the MESH hanging in the corner of the shooter's own
## screen, which is free to kick as hard and as slowly as [WeaponProfile] says
## without any of that budget, because it never reads
## [member Rifle.aim_source] and never writes anywhere near it -- see
## [method Rifle._resolve_shot], which this node does not touch at all.
##
## [b]Structure[/b]
##
## Listens to [signal Rifle.fired], never [Input], so a bot-driven guard's shot
## kicks the model exactly as a human's does -- mirrors the seam
## [WeaponInput] and [method Rifle.try_fire] already draw between deciding to
## shoot and the weapon having shot. [member view_model] is animated by writing
## its LOCAL [member Node3D.transform] as its own authored rest transform
## composed with an offset that is a closed-form function of elapsed time --
## never a per-frame lerp toward a target, the same argument
## [FxCameraKick._envelope] makes -- so the return is frame-rate independent and
## lands on exactly the rest transform, however many shots have fired, rather
## than merely near it. [code]Muzzle[/code] is a child of [member view_model],
## not of this node, so it rides the kick and settles with it automatically;
## nothing here touches it directly.
##
## Every number lives on [member Rifle.profile]'s Recoil group. A profile with
## [method WeaponProfile.has_recoil] false leaves the view model exactly on its
## authored transform forever, which is what makes a disabled kick free rather
## than a code path that happens to move nothing.

## The weapon to listen to.
@export var rifle: Rifle

## The node to kick: [code]Rifle/ViewModel[/code]. Its transform at
## [method _ready] is remembered as the rest pose everything decays back to.
@export var view_model: Node3D

## Optional. When set, the BASE this node kicks away from and recovers to on
## every tick is [method RifleAds.get_current_base_pose] instead of the fixed
## authored rest transform below -- so a shot fired while aimed recoils from
## the aimed pose, and one fired at the hip recoils from the hip, with no
## change to the kick math itself. See [method _current_base].
##
## This is also what keeps the two systems from ever fighting over
## [member view_model]: [RifleAds] never writes that node's transform, only
## answers what the current base is, and this node stays the sole writer.
##
## Left null, behaviour is exactly what it always was: the base is the fixed
## transform captured at [method _ready].
@export var pose_source: RifleAds

## The view model's authored local transform, captured once at [method _ready].
## The base this recovers to when [member pose_source] is null, and always the
## value [method get_rest_transform] reports whether or not one is set --
## never a value re-derived from wherever the model happens to be, so many
## shots in a row cannot drift the rifle off its scene-authored position.
var _rest: Transform3D = Transform3D.IDENTITY
var _has_rest: bool = false

## Seconds since the current kick started; negative means no kick is running.
var _t: float = -1.0

## The profile the running kick was played with, captured at the moment of the
## shot so a rules-supplied profile swapped mid-kick cannot retune a kick that
## is already in flight.
var _kick_profile: WeaponProfile = null


func _ready() -> void:
	if rifle == null:
		push_error("RifleRecoil has no Rifle to listen to; the view model will not kick.")
		set_process(false)
		return
	if view_model == null:
		push_error("RifleRecoil has no ViewModel to kick.")
		set_process(false)
		return
	_rest = view_model.transform
	_has_rest = true
	rifle.fired.connect(_on_fired)
	_check_recovery_fits()


## Render-tick driven, like [FxCameraKick]: a purely visual animation stepped
## once per drawn frame reads smoothly at any refresh rate, and nothing about its
## correctness depends on which clock drives it -- see [method tick].
func _process(delta: float) -> void:
	tick(delta)


## Advance the kick by [param delta] seconds and write the resulting transform.
##
## Public, and the only thing [method _process] calls, exactly so a test can
## [code]set_process(false)[/code] and drive this directly with fixed deltas --
## the same seam [method Rifle.tick] and [method FxCameraKick.tick] offer.
##
## [b]Unconditional now.[/b] With no [member pose_source] this only ever
## reapplies the same fixed [member _rest] -- a harmless no-op write, and belt
## and braces against the model ever being left stranded off it, exactly as
## before. With one set, the base itself moves every tick a zoom is
## transitioning even while no kick is running, so a tick that only wrote while
## a kick was live would leave the raise and lower frozen mid-air the instant a
## shot's kick finished. Mirrors [method WeaponOptic.tick], which applies every
## tick for the identical reason.
func tick(delta: float) -> void:
	if not _has_rest or view_model == null:
		return
	if _t >= 0.0:
		_t = _advance(_t, delta, _kick_profile.get_recoil_duration())
	_apply()


# --- Public API -----------------------------------------------------------------

## Play the kick directly, using [param profile]'s numbers. For a test, and for
## anything that wants to preview the feel without a shot to cause it.
##
## A no-op for a profile with [method WeaponProfile.has_recoil] false, which is
## what makes a zeroed recoil free: nothing here starts a clock that would spend
## every frame computing an offset of zero.
func kick(profile: WeaponProfile) -> void:
	if profile == null or not profile.has_recoil():
		return
	_kick_profile = profile
	_t = 0.0


## True when the view model is sitting exactly on its current base -- the
## authored rest transform, or [member pose_source]'s live hip/aim blend when
## one is set -- with nothing running. The assertion a test makes to prove the
## kick gave the model back, whether that model was aimed or at the hip.
func is_at_rest() -> bool:
	if _t >= 0.0:
		return false
	if view_model == null:
		return true
	return view_model.transform.is_equal_approx(_current_base())


## The view model's authored rest transform, for tests.
func get_rest_transform() -> Transform3D:
	return _rest


# --- Signals ----------------------------------------------------------------

func _on_fired(_origin: Vector3, _end_point: Vector3) -> void:
	if rifle.profile != null:
		kick(rifle.profile)


# --- Internals ------------------------------------------------------------------

func _apply() -> void:
	var weight: float = 0.0
	if _t >= 0.0:
		weight = _envelope(
			_t,
			_kick_profile.recoil_kick_seconds,
			_kick_profile.recoil_recover_seconds,
			_kick_profile.recoil_fade_exponent,
		)

	var euler: Vector3 = Vector3.ZERO
	var offset: Vector3 = Vector3.ZERO
	if weight > 0.0:
		# +X tilts local -Z (forward) upward -- the muzzle rises. Mirrors
		# FxCameraKick's own "+X pitches up" convention.
		euler.x = deg_to_rad(_kick_profile.recoil_kick_pitch_degrees) * weight
		# +Z is behind the model: the shove is backwards, into the shoulder.
		offset.z = _kick_profile.recoil_kick_distance * weight

	# The base is the fixed authored rest transform, or -- with a pose_source
	# set -- wherever RifleAds says the hip/aim blend currently sits. Either
	# way the kick composes on top of it exactly as before: rotation on the
	# RIGHT of the base basis, so it turns in the view model's own already
	# tilted, already scaled (and, while aiming, already re-aimed) axes, and
	# Basis.from_euler being a pure rotation cannot change how long those axes
	# are. Translation goes through the rotation-only part of that basis
	# instead, so recoil_kick_distance means real metres of travel rather than
	# some fraction of it the current scale happens to imply.
	var base: Transform3D = _current_base()
	var base_rotation: Basis = base.basis.orthonormalized()
	view_model.transform = Transform3D(
		base.basis * Basis.from_euler(euler),
		base.origin + base_rotation * offset,
	)


## The base this node kicks away from and recovers to right now: the live
## hip/aim blend from [member pose_source] when one is set, otherwise the fixed
## transform captured at [method _ready]. The only place either is chosen --
## [method _apply] and [method is_at_rest] both go through this rather than
## picking between [member _rest] and [member pose_source] themselves.
func _current_base() -> Transform3D:
	if pose_source != null:
		return pose_source.get_current_base_pose()
	return _rest


## Move the kick's clock on, returning -1.0 once it has fully expired.
func _advance(elapsed: float, delta: float, duration: float) -> float:
	var next: float = elapsed + delta
	return -1.0 if next >= duration else next


## Rise to 1.0 over [param attack], then fall to exactly 0.0 over [param recover].
## A closed-form function of elapsed time and nothing else -- mirrors
## [method FxCameraKick._envelope] -- so recovery is frame-rate independent and
## reaches exactly zero at [code]attack + recover[/code] rather than merely
## approaching it.
func _envelope(elapsed: float, attack: float, recover: float, exponent: float) -> float:
	if elapsed < 0.0:
		return 0.0
	if attack > 0.0:
		if elapsed < attack:
			return elapsed / attack
	elif elapsed <= 0.0:
		return 1.0
	if recover <= 0.0:
		return 0.0
	var fallen: float = (elapsed - attack) / recover
	if fallen >= 1.0:
		return 0.0
	return pow(1.0 - fallen, exponent)


## Warn if the kick can still be running when the weapon comes off reload.
##
## Not a correctness problem -- the shot line is never touched, so a kick in
## flight cannot displace a shot -- but a rifle visibly still settling from the
## last shot the instant it is ready to fire again reads as broken. Checked
## against the weapon's floor reload, the shortest the reload can ever become,
## exactly as [method FxWeaponFeel._check_recovery_fits] checks its own kick.
func _check_recovery_fits() -> void:
	if rifle.profile == null or not rifle.profile.has_recoil():
		return
	var kick_duration: float = rifle.profile.get_recoil_duration()
	var soonest_shot: float = rifle.profile.get_cycle_seconds(rifle.get_reload_floor_seconds())
	if kick_duration > soonest_shot:
		push_warning(
			(
				"RifleRecoil: the view-model kick lasts %.3fs but the rifle can fire again "
				+ "after %.3fs. Lower recoil_kick_seconds/recoil_recover_seconds or the model "
				+ "will still be settling when the next shot is taken."
			)
			% [kick_duration, soonest_shot]
		)
