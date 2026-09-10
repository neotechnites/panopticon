class_name FxCameraKick
extends Node

## The one node allowed to move the camera for feedback, and the reason the rest
## of this layer can stay simple.
##
## Recoil, being shot and confirming a kill all want the camera. If each owned it
## the last writer of the frame would win and the other two would silently
## vanish, so instead they are three CHANNELS on this node and it composes them.
## Nothing else in [code]scripts/fx[/code] touches a [Camera3D].
##
## [b]How it avoids fighting [WeaponOptic][/b]
##
## The optic owns [member Camera3D.fov] and treats any outside write to that
## field as a new un-zoomed base -- write it once and the zoom is permanently
## corrupted. This node therefore never reads or writes [code]fov[/code] at all.
## It works entirely in [member Node3D.transform], which the optic never touches,
## so the two share a camera with no coordination and no ordering requirement.
##
## [b]How it avoids stealing aim[/b]
##
## Aim in PANOPTICON is the body's yaw plus the head's pitch, both written by
## [PlayerController]. This node writes neither. It writes the camera's LOCAL
## transform -- the constant offset the camera has under Head, which no gameplay
## code ever assigns -- as base times an offset, and every channel's offset is a
## pure function of elapsed time that reaches exactly zero. At rest the camera's
## transform is bit-identical to the base it started from, so the player is
## pointing exactly where they were pointing.
##
## The rifle does aim down this camera, so a kick in progress does move the shot
## line. That is harmless by construction rather than by luck: a shot is resolved
## synchronously inside [method Rifle.try_fire], before any frame of the kick it
## causes has been applied, and the next shot cannot happen for at least
## [member WeaponProfile.min_reload_seconds], which
## [member FeedbackProfile.recoil_attack_seconds] plus
## [member FeedbackProfile.recoil_recover_seconds] is required to stay under.
##
## [b]Framerate independence[/b]
##
## Every channel is [code]amount * f(elapsed)[/code] for a closed-form [code]f[/code],
## never a per-frame lerp towards a target. A fractional lerp is an exponential
## whose speed is the framerate's opinion; this form has the same value at the
## same wall-clock time whether it was reached in six steps or in sixty, and
## arrives at zero in exactly the configured number of seconds at any framerate.
## [WeaponOptic] makes the same argument about its own transition.
##
## [b]Headless[/b]
##
## The bot harness runs thousands of matches with no viewport. With
## [member headless_inert] left on, this node detects the headless display
## server, switches its process off and connects nothing, so a sweep pays
## nothing for feedback nobody is there to see.

## The camera to offset. Normally [code]Player/Head/Camera[/code]. Only its
## [member Node3D.transform] is touched, never its [member Camera3D.fov].
@export var camera: Camera3D

## Tunables. Without one the node does nothing and says so rather than falling
## back on invented numbers.
@export var profile: FeedbackProfile

## Go inert when there is no display server. Turn it off only in a test that
## needs the logic to actually run headless.
@export var headless_inert: bool = true

## Name the headless display driver reports. Not a tunable.
const HEADLESS_DISPLAY: String = "headless"

## Where the camera sits when nothing is kicking it. Re-adopted whenever somebody
## else writes the camera's transform, exactly as [WeaponOptic] re-adopts a
## foreign FOV -- ownership by last write, so a future node that repositions the
## camera is not fought.
var _base: Transform3D = Transform3D.IDENTITY

## The transform this node last wrote, read back off the camera. Anything else is
## an outside write. Read back rather than remembered because [Transform3D] is
## single-precision and a double written into it does not come out identical.
var _applied: Transform3D = Transform3D.IDENTITY
var _has_applied: bool = false

var _inert: bool = false

## Seconds since each channel was triggered; negative means idle.
var _recoil_t: float = -1.0
var _impact_t: float = -1.0
var _confirm_t: float = -1.0

var _recoil_scale: float = 1.0
var _impact_scale: float = 1.0
var _confirm_scale: float = 1.0

## Alternates +1/-1 so consecutive shots do not kick the same way. A counter and
## not an RNG, so a replay and a sweep produce identical camera paths.
var _shot_parity: float = 1.0

## The shot's direction of travel in the camera's local space, for the whip.
var _impact_dir: Vector3 = Vector3.ZERO


func _ready() -> void:
	if headless_inert and DisplayServer.get_name() == HEADLESS_DISPLAY:
		_inert = true
		set_process(false)
		return
	if profile == null:
		push_error("FxCameraKick has no FeedbackProfile; the camera will not move.")
		_inert = true
		set_process(false)
		return
	if camera == null:
		push_error("FxCameraKick has no Camera3D to drive.")
		_inert = true
		set_process(false)
		return
	_base = camera.transform
	_applied = _base
	_has_applied = true


## The kick runs on the render tick, not the physics tick, for the same reason
## [method WeaponOptic._process] does: it is a rendered quantity, and a 60 Hz
## ramp on a 144 Hz display is visibly stepped. Nothing about determinism is lost
## -- see the class description on framerate independence.
func _process(delta: float) -> void:
	tick(delta)


## Advance every channel by [param delta] seconds and write the resulting
## transform.
##
## Public because a harness may want to drive it itself: call
## [code]set_process(false)[/code] and step this with a fixed delta. Mirrors
## [method Rifle.tick] and [method WeaponOptic.tick].
func tick(delta: float) -> void:
	if _inert or camera == null or profile == null:
		return

	_sync_base()

	var was_active: bool = is_active()
	if was_active:
		_recoil_t = _advance(_recoil_t, delta, profile.get_recoil_duration())
		_impact_t = _advance(_impact_t, delta, profile.impact_recover_seconds)
		_confirm_t = _advance(_confirm_t, delta, profile.confirm_punch_seconds)
		_apply()
	elif _has_applied and not _applied.is_equal_approx(_base):
		# Everything expired between ticks. Settle exactly onto the base once,
		# then stop writing entirely until something triggers again.
		_apply()


# --- Public API ---------------------------------------------------------------

## Kick for a shot. [param scale] multiplies every recoil amount, so a future
## weapon can borrow the same curve at a different weight.
##
## Restarts the channel rather than stacking, which is free here: the rifle is
## single-shot and cannot produce two kicks inside one reload.
func fire_recoil(scale: float = 1.0) -> void:
	if not _can_run() or not profile.weapon_recoil_enabled:
		return
	_recoil_t = 0.0
	_recoil_scale = scale
	_shot_parity = -_shot_parity


## Whip for a hit taken. [param world_direction] is the direction the shot was
## TRAVELLING in world space, so the view snaps the way the head would have gone.
## Pass [constant Vector3.ZERO] if it is not known and a default whip is used.
func strike(world_direction: Vector3, scale: float = 1.0) -> void:
	if not _can_run() or not profile.impact_shake_enabled:
		return
	_impact_t = 0.0
	_impact_scale = scale
	_impact_dir = to_camera_local(world_direction)


## Punch for a confirmed kill. Translation only: see
## [member FeedbackProfile.confirm_punch_enabled].
func confirm(scale: float = 1.0) -> void:
	if not _can_run() or not profile.confirm_punch_enabled:
		return
	_confirm_t = 0.0
	_confirm_scale = scale


## Drop every channel and put the camera back on its base immediately. For a
## respawn or a round reset, so a kick cannot survive across a life.
func clear() -> void:
	_recoil_t = -1.0
	_impact_t = -1.0
	_confirm_t = -1.0
	if camera != null and _has_applied:
		camera.transform = _base
		_applied = camera.transform


## True while any channel is still running.
func is_active() -> bool:
	return _recoil_t >= 0.0 or _impact_t >= 0.0 or _confirm_t >= 0.0


## True when the camera is sitting exactly on its base with nothing running. The
## assertion a test makes to prove the kick gave the aim back.
func is_at_rest() -> bool:
	if is_active():
		return false
	if camera == null:
		return true
	return camera.transform.is_equal_approx(_base)


## The camera's un-kicked local transform, for tests and for anything that needs
## to know where the camera really is.
func get_base_transform() -> Transform3D:
	return _base


## Current angular offset in radians as pitch, yaw, roll. Exposed so a headless
## check can watch the kick decay without a viewport to look at.
func get_rotation_offset() -> Vector3:
	if camera == null:
		return Vector3.ZERO
	return (_base.basis.inverse() * camera.transform.basis).get_euler()


## Current positional offset in metres, in the camera's own axes.
func get_position_offset() -> Vector3:
	if camera == null:
		return Vector3.ZERO
	return _base.basis.inverse() * (camera.transform.origin - _base.origin)


## True when the node decided to do nothing at all this run -- no display server,
## or a missing profile or camera.
func is_inert() -> bool:
	return _inert


## Convert a world-space direction into the camera's local axes. Used by
## [FxHitReaction] so it does not need a camera reference of its own.
func to_camera_local(world_direction: Vector3) -> Vector3:
	if camera == null or world_direction.length_squared() <= 0.0:
		return Vector3.ZERO
	return camera.global_transform.basis.inverse() * world_direction.normalized()


# --- Internals ----------------------------------------------------------------

func _can_run() -> bool:
	return not _inert and profile != null and profile.enabled and camera != null


## Move one channel's clock on, returning -1.0 once it has expired.
func _advance(elapsed: float, delta: float, duration: float) -> float:
	if elapsed < 0.0:
		return -1.0
	var next: float = elapsed + delta
	return -1.0 if next >= duration else next


## Adopt the camera's transform as the new base whenever somebody else wrote it.
##
## The same reconciliation [method WeaponOptic._sync_base_fov] performs on the
## FOV, for the same reason: this node owns the camera's local transform only in
## the sense that it remembers exactly what it put there, and any value that is
## not that is somebody else's intent.
func _sync_base() -> void:
	if not _has_applied:
		_base = camera.transform
		_applied = _base
		_has_applied = true
		return
	if camera.transform.is_equal_approx(_applied):
		return
	_base = camera.transform
	_applied = _base
	_recoil_t = -1.0
	_impact_t = -1.0
	_confirm_t = -1.0


## Sum every live channel and write the result.
func _apply() -> void:
	var euler: Vector3 = Vector3.ZERO
	var offset: Vector3 = Vector3.ZERO

	if _recoil_t >= 0.0:
		var weight: float = _recoil_scale * _envelope(
			_recoil_t,
			profile.recoil_attack_seconds,
			profile.recoil_recover_seconds,
			profile.recoil_fade_exponent,
		)
		# +X pitches the camera up, which is the direction a muzzle goes.
		euler.x += deg_to_rad(profile.recoil_pitch_degrees) * weight
		euler.y += deg_to_rad(profile.recoil_yaw_degrees) * weight * _shot_parity
		euler.z += deg_to_rad(profile.recoil_roll_degrees) * weight * _shot_parity
		# +Z is behind the camera: the shove is backwards, into the shoulder.
		offset.z += profile.recoil_punch_metres * weight

	if _impact_t >= 0.0:
		var decay: float = _impact_scale * _envelope(
			_impact_t, 0.0, profile.impact_recover_seconds, profile.impact_fade_exponent
		)
		# A decaying oscillation rather than a single swing: a head struck hard
		# rebounds, and one swing back to centre reads as a camera lerp.
		var swing: float = decay * cos(TAU * profile.impact_frequency_hz * _impact_t)
		var lateral: Vector2 = Vector2(_impact_dir.x, _impact_dir.y)
		# A shot straight down the view axis has no lateral component at all and
		# would otherwise produce no whip whatsoever, which is the one outcome a
		# hit reaction may never have. Fall back to a fixed off-axis direction.
		lateral = lateral.normalized() if lateral.length() > 0.001 else Vector2(0.94, 0.34)
		# Struck from the left, the shot travels rightwards in local +X, and the
		# view must turn right -- which is a NEGATIVE yaw about +Y.
		euler.y -= deg_to_rad(profile.impact_yaw_degrees) * swing * lateral.x
		euler.x += deg_to_rad(profile.impact_pitch_degrees) * swing * lateral.y
		euler.z -= deg_to_rad(profile.impact_roll_degrees) * swing * lateral.x
		# The shove follows the bullet, and does not oscillate: you go one way.
		offset += _impact_dir * profile.impact_punch_metres * decay

	if _confirm_t >= 0.0:
		var punch: float = _confirm_scale * _envelope(
			_confirm_t, 0.0, profile.confirm_punch_seconds, 2.0
		)
		# Translation only. See FeedbackProfile.confirm_punch_enabled.
		offset.z += profile.confirm_punch_metres * punch

	# Composed as base * offset, so an idle frame writes the base back exactly:
	# Basis.from_euler(ZERO) is the identity and a multiply by it is lossless.
	camera.transform = Transform3D(
		_base.basis * Basis.from_euler(euler), _base.origin + _base.basis * offset
	)
	# Read back, so single-precision rounding cannot masquerade as an outside
	# write on the next tick. See _sync_base.
	_applied = camera.transform


## Rise to 1.0 over [param attack], then fall to exactly 0.0 over [param recover].
##
## A closed-form function of elapsed time and nothing else, which is the whole
## framerate-independence argument: sampled at any two framerates it returns the
## same value for the same [param elapsed], and it is exactly zero at and beyond
## [code]attack + recover[/code].
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
