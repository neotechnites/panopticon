extends Node3D

## Capture-only: one map with a knot of runners dressed as a match dresses them, for fit stills.
## A camera near the tower axis is given the scope's lens; any other keeps its own.

const AVATAR: PackedScene = preload("res://characters/player/prisoner_avatar.tscn")
const PALETTE: RunnerPalette = preload("res://match/rules/default_runner_palette.tres")
## Per runner: metres along the lane, metres outward, degrees turned, clip, seconds into it.
const CAST: Array = [
	[0.0, -1.0, 200.0, &"Run", 0.10],
	[0.9, 0.9, 20.0, &"Run", 0.42],
	[1.9, -0.2, 95.0, &"Aim", 0.0],
	[4.2, 1.3, 310.0, &"Run", 0.25],
	[7.5, -1.4, 180.0, &"Jump", 0.12],
]

@export_file("*.tscn") var map_scene: String = ""
@export var bearing_degrees: float = 90.0
@export var radius: float = 52.0
@export var spread: float = 1.0
@export var scope_fov: float = 20.0
@export var tower_radius: float = 12.0

var _arena: Node = null
var _own_fov: float = 0.0


func _ready() -> void:
	_arena = (load(map_scene) as PackedScene).instantiate()
	add_child(_arena)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var light: CharacterLight = CharacterLight.for_arena(_arena)
	for index: int in CAST.size():
		_stand(index, light)


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	if _own_fov <= 0.0:
		_own_fov = camera.fov
	var in_tower: bool = Vector2(camera.global_position.x, camera.global_position.z).length() < tower_radius
	camera.fov = scope_fov if in_tower else _own_fov


func _stand(index: int, light: CharacterLight) -> void:
	var row: Array = CAST[index]
	var angle: float = deg_to_rad(bearing_degrees) + float(row[0]) / radius
	var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
	var feet: Vector3 = out * (radius + float(row[1]) * spread) + Vector3.UP * 40.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(feet, feet + Vector3.DOWN * 40.0)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	feet.y = hit.position.y if hit.has("position") else 23.0
	var holder: Node3D = Node3D.new()
	add_child(holder)
	holder.global_position = feet
	holder.rotation.y = -angle + deg_to_rad(float(row[2]))
	var avatar: PrisonerAvatar = AVATAR.instantiate() as PrisonerAvatar
	holder.add_child(avatar)
	avatar.set_process(false)
	avatar.animation.play(row[3])
	avatar.animation.seek(float(row[4]), true)
	avatar.animation.pause()
	_dress(avatar.mesh, PALETTE.color_for_index(index), light)


## MatchController._tinted_material and _fade_body, for a body no match owns.
func _dress(mesh: MeshInstance3D, colour: Color, light: CharacterLight) -> void:
	var shirt: int = MatchController.shirt_surface_of(mesh)
	for surface: int in mesh.mesh.get_surface_count():
		var material: BaseMaterial3D = mesh.mesh.surface_get_material(surface) as BaseMaterial3D
		if surface == shirt:
			material = material.duplicate() as BaseMaterial3D
			material.albedo_color = MatchController.tint_color(colour)
			material.emission_enabled = true
			material.emission = Color(colour.r, colour.g, colour.b, 1.0)
			material.emission_energy_multiplier = 0.9
		var lit: Material = light.apply(material)
		if surface == shirt or lit != material:
			mesh.set_surface_override_material(surface, lit)
