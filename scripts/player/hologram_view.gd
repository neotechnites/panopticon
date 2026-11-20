class_name HologramView
extends Node3D

## A hologram as every machine draws it (DESIGN 9): the runner model in its owner's colours, running
## at the speed its pose moves. No collider and no physics; the host's decoy body is what shots hit.

const MODEL: PackedScene = preload("res://characters/models/prisoner2.glb")
## Visual layer 3: never anybody's own viewpoint, so every camera draws it (as a runner's avatar).
const VISUAL_LAYERS: int = 4
const RUN_CLIP: StringName = &"Run"
const AIR_CLIP: StringName = &"Jump"
## Below this ground speed it stands; above this fall speed it is airborne.
const STAND_SPEED: float = 0.5
const AIR_SPEED: float = 1.0

var mesh: MeshInstance3D = null
var _animation: AnimationPlayer = null
## Ground speed the run cycle is authored at, strides a second, and its fastest playback.
var _reference_speed: float = 11.0
var _strides: float = 2.8
var _max_scale: float = 1.6
var _clip: StringName = &""
var _velocity: Vector3 = Vector3.ZERO


## A view of [param owner_body]'s hologram, wearing what its avatar wears.
static func build(owner_body: PlayerController) -> HologramView:
	var view: HologramView = HologramView.new()
	view.name = "Hologram"
	var model: Node3D = MODEL.instantiate() as Node3D
	# The model's toes point down +Z and a body runs down -Z (characters/player/prisoner_avatar.tscn).
	model.rotation.y = PI
	view.add_child(model)
	view.mesh = model.get_node_or_null(^"Armature/Skeleton3D/Runner") as MeshInstance3D
	view._animation = model.get_node_or_null(^"AnimationPlayer") as AnimationPlayer
	var avatar: PrisonerAvatar = PrisonerAvatar.of(owner_body) if owner_body != null else null
	if avatar != null:
		view._strides = avatar.run_strides_per_second
		view._max_scale = avatar.max_playback_scale
		if avatar.mesh != null and view.mesh != null:
			view.mesh.material_override = avatar.mesh.material_override
			var count: int = mini(avatar.mesh.get_surface_override_material_count(), view.mesh.get_surface_override_material_count())
			for index: int in count:
				view.mesh.set_surface_override_material(index, avatar.mesh.get_surface_override_material(index))
	if owner_body != null and owner_body.profile != null:
		view._reference_speed = owner_body.profile.ground_speed
	if view.mesh != null:
		view.mesh.layers = VISUAL_LAYERS
	if view._animation != null:
		view._keep_clips()
	return view


## Only the clips it plays: what an avatar adds to the model's shared library drives nodes this has not.
func _keep_clips() -> void:
	var library: AnimationLibrary = AnimationLibrary.new()
	for clip: StringName in [RUN_CLIP, AIR_CLIP]:
		if _animation.has_animation(clip):
			library.add_animation(clip, _animation.get_animation(clip))
	for library_name: StringName in _animation.get_animation_library_list():
		_animation.remove_animation_library(library_name)
	_animation.add_animation_library(&"", library)
	if library.has_animation(RUN_CLIP):
		library.get_animation(RUN_CLIP).loop_mode = Animation.LOOP_LINEAR


## Stand it at [param at] facing [param yaw], moving at [param velocity]; the clip follows the motion.
func pose(at: Vector3, yaw: float, velocity: Vector3) -> void:
	global_position = at
	rotation = Vector3(0.0, yaw, 0.0)
	_velocity = velocity
	if _animation == null:
		return
	var ground: float = Vector2(velocity.x, velocity.z).length()
	if absf(velocity.y) > AIR_SPEED and _animation.has_animation(AIR_CLIP):
		_play(AIR_CLIP, 1.0)
	elif ground > STAND_SPEED:
		var run_rate: float = _strides * _animation.get_animation(RUN_CLIP).length
		_play(RUN_CLIP, minf(ground / maxf(_reference_speed, 0.01), _max_scale) * run_rate)
	else:
		_play(RUN_CLIP, 0.0)


## The clip being drawn and how fast it plays: for tests.
func get_clip() -> StringName:
	return _clip if _animation != null and _animation.speed_scale > 0.0 else &""


func get_velocity() -> Vector3:
	return _velocity


func _play(clip: StringName, speed: float) -> void:
	if _clip != clip:
		_clip = clip
		_animation.play(clip, 0.1)
	_animation.speed_scale = speed
