class_name WeaponOptic
extends Node

## Drives a [Camera3D]'s field of view so the tower can pick a runner out of the
## ring.
##
## The arena is roughly 120 m across. Unzoomed, a runner on the far arc is a few
## pixels of grey against grey, and the rifle's one shot is a guess. This node
## is the whole answer to that, and it is deliberately nothing more than a
## number moving: no overlay, no vignette, no lens, no shader. The game is
## greybox and the FOV change alone is the mechanic.
##
## [b]Structure[/b]
##
## Decision and act are separate, exactly as in [Rifle] and [PlayerController].
## This node never touches [Input]; it exposes [method zoom_in] and
## [method zoom_out], and a thin [ZoomInput] calls them from a device. A bot
## calls the identical methods, so a headless bot match exercises the real
## optic -- the real transition clock, the real sensitivity multiplier -- and
## not a simulation of it. If you find yourself reading the mouse in this file,
## the seam has leaked.
##
## It is also strictly additive: it takes a camera by reference and drives it.
## Nothing in [PlayerController], [Rifle] or any scene needs to know it exists,
## and deleting it leaves both working.
##
## Every number lives in [ZoomProfile]. There are no optics constants here
## beyond the engine's own hard limits on a valid FOV.
##
## [b]The two things this class exists to get right[/b]
##
## 1. The zoom is RELATIVE. [member base_fov] is read off the camera and
##    re-read whenever anything else writes to it, so a player's display-FOV
##    setting keeps working while aiming instead of being silently overruled.
##    See [method _sync_base_fov].
## 2. Mouse sensitivity is SCALED. At an unchanged sensitivity, the same mouse
##    movement sweeps 1/zoom_factor as much of the visible field once zoomed,
##    which makes a scope unusable. See [member sensitivity_multiplier] for the
##    one line that consumes it.

## Godot's valid range for [member Camera3D.fov]. Not tunables: outside these
## the engine rejects the value, so the zoomed FOV is clamped into them.
const MIN_FOV: float = 1.0
const MAX_FOV: float = 179.0

## Emitted whenever the field of view actually changes, on any tick of a
## transition. Carries the live [member sensitivity_multiplier] alongside it,
## because in practice every listener that wants one wants the other.
##
## Prefer this to polling if you cache the multiplier; poll
## [member sensitivity_multiplier] directly if you read it per tick anyway.
signal fov_changed(fov: float, sensitivity_multiplier: float)

## Emitted when the optic is ASKED to zoom in or out -- on the tick the request
## lands, not when the transition finishes. The hook for anything that reacts to
## the intent to aim: a breath-hold, a bot's own bookkeeping, a stance change.
signal zoom_requested(zoomed_in: bool)

## Emitted when a transition finishes, carrying where it settled. Fires once per
## arrival, never on a tick that merely continues a transition.
signal zoom_settled(zoomed_in: bool)

## The camera this optic drives. Normally the player's [Camera3D] under the Head
## node of [code]scenes/player/player.tscn[/code].
##
## The optic owns only this camera's [member Camera3D.fov], and only while it is
## set: anything else may write that field at any time and the optic will treat
## the new value as the base to zoom from, rather than fighting it.
@export var camera: Camera3D

## Tunables. Without one the optic cannot zoom and says so rather than falling
## back on invented numbers.
@export var profile: ZoomProfile

## The un-zoomed field of view, in degrees: the camera's own value, which is
## whatever the player's display-FOV setting last put there.
##
## Tracked rather than cached once. Read-only from outside.
var base_fov: float = 0.0

## Multiplier a look delta should be scaled by, to keep a given mouse movement
## sweeping the same fraction of the VISIBLE field at any zoom. 1.0 unzoomed,
## falling towards [member ZoomProfile.zoom_factor] as the view narrows.
##
## [b]How to consume it[/b] -- one line, in
## [method HumanIntentSource.poll], where the look delta is built:
## [codeblock]
## _intent.look_delta = _look_pixels * profile.mouse_sensitivity * optic.sensitivity_multiplier
## [/codeblock]
## with [code]optic[/code] an exported [WeaponOptic] on that node, and the
## multiplier treated as 1.0 when it is null so an un-scoped body is unaffected.
## It is dimensionless and the delta is already in radians, so the order of the
## two scalars does not matter and nothing else in the look path changes.
##
## It belongs there rather than in [method PlayerController._apply_look] because
## it is a property of the DEVICE's mapping, not of the body: a bot's look delta
## is computed from a world-space aim target and must not be scaled at all, and
## putting it in the controller would scale both.
var sensitivity_multiplier: float = 1.0

## Transition state, 0.0 at hipfire and 1.0 at full zoom. Moved at a constant
## rate towards [member _target] -- see [method tick].
var _progress: float = 0.0

## Where [member _progress] is heading: 0.0 or 1.0, never anything else.
var _target: float = 0.0

## The FOV this node last wrote, read back off the camera. Anything else on the
## camera's [member Camera3D.fov] is an outside write. See [method _sync_base_fov].
var _applied_fov: float = -1.0


func _ready() -> void:
	if profile == null:
		push_error("WeaponOptic has no ZoomProfile; the optic cannot zoom.")
		set_process(false)
		return
	if camera == null:
		push_error("WeaponOptic has no Camera3D to drive; the optic cannot zoom.")
		set_process(false)
		return
	_sync_base_fov()
	_apply()


## The transition runs on the render tick, not the physics tick, because the FOV
## is a rendered quantity: on a 144 Hz display a 60 Hz ramp is visibly stepped
## over a quarter of a second. This costs nothing in determinism -- the
## transition is time-based (see [method tick]), so it passes through the same
## states in the same wall-clock time at any framerate, and the aim multiplier
## a physics tick reads is at most one render frame old.
func _process(delta: float) -> void:
	tick(delta)


## Advance the transition by [param delta] seconds and write the resulting FOV.
##
## Public because a harness may want to drive it itself: call
## [code]set_process(false)[/code] and step this with a fixed delta to replay a
## match deterministically or to run a zoom sweep far faster than real time.
## [method _process] is only a caller of this. Mirrors [method Rifle.tick].
##
## The interpolation is a constant RATE towards the target -- delta divided by
## the transition time -- and never a fixed fraction of the remaining distance
## per frame. A fractional lerp is an exponential whose speed is the framerate's
## opinion: the same zoom would take longer on a slower machine and never
## actually arrive. This form arrives, in exactly
## [member ZoomProfile.transition_seconds], at any framerate.
func tick(delta: float) -> void:
	if profile == null or camera == null:
		return

	_sync_base_fov()

	if not is_equal_approx(_progress, _target):
		var step: float = (
			1.0
			if profile.transition_seconds <= 0.0
			else delta / profile.transition_seconds
		)
		_progress = move_toward(_progress, _target, step)
		if is_equal_approx(_progress, _target):
			_progress = _target
			_apply()
			zoom_settled.emit(_target > 0.0)
			return

	_apply()


# --- Public API ---------------------------------------------------------------

## Begin zooming in. Idempotent: calling it while already zoomed or zooming in
## does nothing, so a bot may call it every tick it wants the scope.
##
## The single entry point for the decision to aim, and the seam between DECISION
## and ACT. A human holds a button and [ZoomInput] calls this; a bot decides it
## wants a better look and calls this. Neither the transition below nor the
## sensitivity it reports can tell which.
func zoom_in() -> void:
	set_zoomed(true)


## Begin zooming back out. Idempotent, for the same reason as [method zoom_in].
func zoom_out() -> void:
	set_zoomed(false)


## Zoom in or out. The form a hold-style input drives directly, by passing the
## button's current state every frame.
func set_zoomed(zoomed_in: bool) -> void:
	var next: float = 1.0 if zoomed_in else 0.0
	if is_equal_approx(next, _target):
		return
	_target = next
	zoom_requested.emit(zoomed_in)


## Flip the current request. The form a toggle-style input drives.
func toggle_zoom() -> void:
	set_zoomed(not is_zoom_requested())


## True when the optic has been asked to zoom in, whether or not the transition
## has finished. The honest answer to "is the player aiming", which is what a
## readiness tell or a bot's planner wants.
func is_zoom_requested() -> bool:
	return _target > 0.0


## True once the transition has actually arrived at full zoom.
func is_fully_zoomed() -> bool:
	return is_equal_approx(_progress, 1.0)


## True while the FOV is still moving.
func is_transitioning() -> bool:
	return not is_equal_approx(_progress, _target)


## Transition state from 0.0 (hipfire) to 1.0 (full zoom).
func get_zoom_progress() -> float:
	return _progress


## The field of view the optic is currently asking the camera for, in degrees.
func get_current_fov() -> float:
	return lerpf(base_fov, get_zoomed_fov(), _progress)


## The field of view at full zoom, in degrees: the live base scaled by
## [member ZoomProfile.zoom_factor] and clamped to what the engine accepts.
## Changes the moment the base does.
func get_zoomed_fov() -> float:
	if profile == null:
		return base_fov
	return clampf(base_fov * profile.zoom_factor, MIN_FOV, MAX_FOV)


## Drop to hipfire immediately, with no transition. For a respawn or a round
## reset, so a zoom cannot survive across a life; not for normal play, where the
## transition time is the point.
##
## Emits [signal zoom_requested] if the optic was aiming, but never
## [signal zoom_settled] -- nothing settled, the state was overwritten.
func reset_zoom() -> void:
	set_zoomed(false)
	_progress = 0.0
	_apply()


# --- Internals ----------------------------------------------------------------

## Adopt the camera's FOV as the new base whenever somebody else has written it.
##
## This is what makes the zoom relative in practice rather than only in
## principle. The settings screen owns the display FOV and writes it straight
## onto the camera, knowing nothing about optics; this node owns the same field
## while aiming. The two are reconciled by ownership of the last write: the
## optic remembers exactly what it put there, and any value that is not that is
## somebody else's intent, which is by definition the un-zoomed base.
##
## Comparison is against the value READ BACK after the write, not the value
## sent, because [member Camera3D.fov] is single-precision and a double written
## into it does not come out bit-identical -- comparing against the sent value
## would read the engine's own rounding as an outside edit on every single tick.
func _sync_base_fov() -> void:
	var current: float = camera.fov
	if _applied_fov >= 0.0 and is_equal_approx(current, _applied_fov):
		return
	base_fov = clampf(current, MIN_FOV, MAX_FOV)


## Write the FOV for the current progress and republish the aim multiplier.
func _apply() -> void:
	if camera == null:
		return
	var fov: float = clampf(get_current_fov(), MIN_FOV, MAX_FOV)
	var multiplier: float = _compute_sensitivity_multiplier(fov)
	var changed: bool = not is_equal_approx(fov, _applied_fov)

	camera.fov = fov
	# Read back, so single-precision rounding cannot masquerade as an outside
	# write on the next tick. See _sync_base_fov.
	_applied_fov = camera.fov
	sensitivity_multiplier = multiplier

	if changed:
		fov_changed.emit(_applied_fov, multiplier)


## The ratio of visible field, raised to the compensation exponent.
##
## The reasoning, which is the whole of requirement 2: a mouse movement produces
## a fixed angle of rotation. Zoomed to half the FOV, that same angle is half
## the screen instead of a quarter, so the crosshair travels twice as far across
## what the player can see. Scaling the delta by the FOV ratio cancels that
## exactly, and a scope that does not do it is unusable at any sensitivity the
## player would want unzoomed.
func _compute_sensitivity_multiplier(fov: float) -> float:
	if profile == null or base_fov <= 0.0:
		return 1.0
	var ratio: float = fov / base_fov
	if is_equal_approx(profile.sensitivity_compensation, 1.0):
		return ratio
	return pow(ratio, profile.sensitivity_compensation)
