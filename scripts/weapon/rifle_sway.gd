class_name RifleSway
extends Node

## A slow figure-eight drift of the guard's aim while the scope is up.
##
## [b]It moves the shot, not a picture of the shot.[/b] Hits are resolved on the
## authority in [method Rifle._resolve_shot], from the global basis of
## [member Rifle.aim_source] -- the holder's [code]Head/Camera[/code]. A sway
## drawn as a screen overlay would therefore be a lie: the crosshair would wander
## and the ray would not. So this node writes the aim node's own transform, which
## is the same object the ray is taken from, and every machine gets the drift for
## free in the same place -- the authority in the shot it resolves, the holder in
## the view they aim with.
##
## The rifle rides along. [member Rifle] and the camera are both children of the
## holder's Head, so the same rotation applied to both keeps the barrel pointing
## where the crosshair does.
##
## Amplitude 0 -- the shipped [member MatchRules.scope_sway_degrees] -- returns
## on the first branch and writes nothing at all.

## The weapon whose [member Rifle.rules] this reads. Normally the parent.
@export var rifle: Rifle

## The optic whose progress says whether the scope is up. Wired at runtime by
## [method MatchController._attach_rifle], exactly as [member RifleAds.optic] is
## and for the same reason: the optic lives on the holder's head.
@export var optic: WeaponOptic

## The node the shot is cast from -- the holder's camera. Wired at runtime beside
## [member Rifle.aim_source] and cleared when the rifle is stowed. Null means no
## drift and no writes.
var aim_node: Node3D = null

## The aim node's transform before any drift was written into it, and the node it
## was read from. Restored whenever the drift stops or the seat changes.
var _rest: Transform3D = Transform3D.IDENTITY
var _rest_node: Node3D = null

## Seconds the scope has been up. The settle runs off this, so lowering the
## scope and raising it again starts the drift over.
var _elapsed: float = 0.0

## The drift written this tick: x yaw, y pitch, both radians.
var _offset: Vector2 = Vector2.ZERO


func _physics_process(delta: float) -> void:
	tick(delta)


## Advance the drift and write it. Public so a headless test drives it without a
## physics clock, the same way [method Rifle.tick] is.
func tick(delta: float) -> void:
	var node: Node3D = aim_node
	if node == null or not is_instance_valid(node):
		_release()
		return
	if node != _rest_node:
		_release()
		_rest_node = node
		_rest = node.transform

	var rules: MatchRules = rifle.rules if rifle != null else null
	var amplitude: float = 0.0 if rules == null else rules.scope_sway_degrees
	var progress: float = 0.0 if optic == null else optic.get_shaped_progress()
	if amplitude <= 0.0 or progress <= 0.0:
		_elapsed = 0.0
		_write(Vector2.ZERO)
		return

	_elapsed += delta
	# A settle of 0 never decays, which is what makes the amplitude the only dial
	# until somebody wants breath-holding out of it.
	var settle: float = rules.scope_sway_settle_seconds
	var decay: float = 1.0 if settle <= 0.0 else clampf(1.0 - _elapsed / settle, 0.0, 1.0)
	# Scaled by the raise as well, so the drift arrives with the scope rather than
	# snapping on the tick the button went down.
	var peak: float = deg_to_rad(amplitude) * progress * decay
	# A 1:2 Lissajous is the figure eight: one horizontal sweep per two vertical.
	var w: float = TAU * rules.scope_sway_hz * _elapsed
	_write(Vector2(peak * sin(w), peak * 0.5 * sin(2.0 * w)))


## The drift currently written, in radians: x yaw, y pitch. Zero when the scope
## is down. The seam a test asserts against.
func get_offset() -> Vector2:
	return _offset


## Put the aim node back the way it was found and forget it. Idempotent.
func release() -> void:
	_release()


func _write(offset: Vector2) -> void:
	if offset == _offset and offset == Vector2.ZERO:
		return
	_offset = offset
	var drift: Basis = Basis.from_euler(Vector3(offset.y, offset.x, 0.0))
	if _rest_node != null and is_instance_valid(_rest_node):
		_rest_node.transform = Transform3D(_rest.basis * drift, _rest.origin)
	# The gun turns with the view: both hang off the holder's Head, so one
	# rotation on each keeps the barrel and the crosshair agreeing.
	if rifle != null:
		rifle.transform = Transform3D(drift, Vector3.ZERO)


func _release() -> void:
	if _rest_node != null and is_instance_valid(_rest_node):
		_rest_node.transform = _rest
	if rifle != null and _offset != Vector2.ZERO:
		rifle.transform = Transform3D.IDENTITY
	_rest_node = null
	_offset = Vector2.ZERO
	_elapsed = 0.0
