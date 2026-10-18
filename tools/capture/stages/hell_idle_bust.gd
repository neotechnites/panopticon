extends "res://tools/capture/stages/stage.gd"

## hell_idle_bust: short 9 L5. Ryan: "so how did i fix it?" {bust shot of runner in hell idle animating}.
## [code]--shot=s1_cave --stage=hell_idle_bust --bots=1 --look=social --shimmer=0 --seed=20261017 --frame=810x1440 --seconds=5.5[/code], cut in 1.2 s for 3.0 s.

# One prisoner on bare S1 deck at 42 deg r 52 facing a lens 2.5 m back down the
# ring (39.25 deg r 52), the S1 spires at 48-58 deg behind him. probe --clear:
# 0-71 deg holds no pad or trap; --floor misses thin spires between its 2 deg
# rows, so the lens was swept: at 37.2 deg r 51 it sat in a spire (near 0.33,
# cover 1.00), 43.2 r 51 near 1.21 cover 0.60, 39.25 r 52 near 1.50 cover 0.00;
# --eye=39.25:52:1.5 --los to 42:52 at 1.0-1.5 m is open. 2.5 m keeps the lens
# clear of him (lens_clear wants 0.8 m, lens_cover counts within 2 m), so a 24 deg
# fov makes the bust: ~1.05 m tall, head to mid chest. He holds still, so the
# rig's shipped Idle (3 deg of spine breath over 3.2 s) is all that moves him.
# Dials (--set=): deg (42), r (52), dist (2.5), fov (24), above (0.05), aim (-0.15), drift (0.03).

## Where he stands: bare deck in the S1 pocket, spires behind him.
const BODY_DEG: float = 42.0
const BODY_R: float = 52.0
## Lens metres from him, back down the ring.
const CAM_DIST: float = 2.5
## Vertical fov: head to mid chest at 2.5 m.
const CAM_FOV: float = 24.0
## Lens height over the Head bone (eye height), and the aim point under it.
const CAM_ABOVE: float = 0.05
const AIM_BELOW: float = -0.15
## A handheld drift in metres, slow enough to read as a person holding it.
const DRIFT: float = 0.03

var _body: PlayerController = null
var _skeleton: Skeleton3D = null
var _head_bone: int = -1
var _anim: AnimationPlayer = null
var _idle: StringName = &"Idle"
var _cast_at: float = 0.0
var _reported: bool = false
var _checked: bool = false


func bots() -> int:
	return 1


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.is_empty() or runners[0].controller == null:
		return false
	var deg: float = float(option("deg", BODY_DEG))
	var r: float = float(option("r", BODY_R))
	var dist: float = float(option("dist", CAM_DIST))
	_body = runners[0].controller
	var at: Vector3 = LIB.ring_point(deg, r, 0.1)
	var lens_at: Vector3 = LIB.ring_point(deg - rad_to_deg(dist / r), r, 0.1)
	drive(runners[0], [
		{"do": "place", "at": at, "face": LIB.toward(at, lens_at)},
		{"do": "hold", "seconds": 60.0, "sway": 0.0},
	], 0)
	stage_body(_body)
	_cast_at = elapsed()
	_skeleton = LIB.find_kind(_body, "Skeleton3D") as Skeleton3D
	if _skeleton != null:
		_head_bone = _skeleton.find_bone("Head")
	var avatar: Node = LIB.find_kind(_body, "PrisonerAvatar")
	if avatar != null:
		_anim = avatar.get("animation") as AnimationPlayer
		_idle = StringName(avatar.get("idle_clip"))
	say("hell_idle_bust: %s at %.1f deg r %.1f, lens %.2f m out; head bone %d, anim %s" % [_body.name, deg, r, dist, _head_bone, _anim != null])
	return true


## The [event] idle line once he is placed and the rig's Idle is the clip running; a check at +2 s.
func tick(_delta: float) -> void:
	if _body == null or _anim == null:
		return
	var running: bool = _anim.is_playing() and _anim.current_animation == String(_idle)
	if not _reported and running and elapsed() - _cast_at > 0.05:
		_reported = true
		print("[event] %6.2f  idle  %s" % [elapsed(), _body.name])
	if not _checked and elapsed() - _cast_at > 2.0:
		_checked = true
		say("anim %s at %.2f s, playing %s, speed %.2f m/s; body %s lens %s" % [_anim.current_animation, _anim.current_animation_position, _anim.is_playing(), _body.velocity.length(), _body.global_position, camera().global_position])


## Eye height, 2.5 m off, a handheld drift on the position and the aim.
func lens(_delta: float) -> bool:
	if _body == null or not is_instance_valid(_body) or camera() == null:
		return false
	var deg: float = float(option("deg", BODY_DEG))
	var r: float = float(option("r", BODY_R))
	var dist: float = float(option("dist", CAM_DIST))
	var drift_m: float = float(option("drift", DRIFT))
	var head: Vector3 = _body.global_position + Vector3.UP * 1.5
	if _skeleton != null and _head_bone >= 0:
		head = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone)).origin
	var t: float = elapsed()
	var drift := Vector3(sin(t * 0.9) * drift_m, sin(t * 1.3 + 1.1) * drift_m * 0.6, sin(t * 0.7 + 2.0) * drift_m * 0.5)
	var sway := Vector3(sin(t * 0.6 + 0.4), sin(t * 1.1 + 2.3) * 0.7, 0.0) * drift_m * 0.5
	var eye: Vector3 = LIB.ring_point(deg - rad_to_deg(dist / r), r, 0.0)
	eye.y = head.y + float(option("above", CAM_ABOVE))
	camera().global_position = eye + drift
	camera().look_at(head + Vector3.UP * float(option("aim", AIM_BELOW)) + sway, Vector3.UP)
	camera().fov = float(option("fov", CAM_FOV))
	camera().current = true
	return true
