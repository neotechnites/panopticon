extends Node3D

## Capture-only: three live [PrisonerAvatar]s wearing the shipped runner
## palette's shirt tint, painted with the SAME maths
## [method MatchController._tinted_material] uses at runtime -- so a still of
## this scene shows the real in-game colour, not a stand-in swatch.
##
## Not part of any match. Built for the shirt-tone pass so Ryan can see the
## darkened, desaturated palette on the model before it ships.

const PALETTE_PATH: String = "res://match/rules/default_runner_palette.tres"
const AVATAR_SCENE: String = "res://characters/player/prisoner_avatar.tscn"
const SPACING: float = 2.2
const COUNT: int = 3


func _ready() -> void:
	var palette: RunnerPalette = load(PALETTE_PATH) as RunnerPalette
	var packed: PackedScene = load(AVATAR_SCENE) as PackedScene
	for i: int in COUNT:
		var avatar: PrisonerAvatar = packed.instantiate() as PrisonerAvatar
		add_child(avatar)
		avatar.global_position = Vector3((i - (COUNT - 1) / 2.0) * SPACING, 0.0, 0.0)
		_paint_shirt(avatar.mesh, palette.color_for_index(i))


## Mirrors [method MatchController._tinted_material] for the shirt case: a
## duplicate of the model's own material with [param colour] as albedo,
## self-lit so it reads the same as it does in the arena's red light.
func _paint_shirt(mesh: MeshInstance3D, colour: Color) -> void:
	if mesh == null or mesh.mesh == null:
		return
	var index: int = maxi(MatchController.shirt_surface_of(mesh), 0)
	var authored: Material = mesh.mesh.surface_get_material(index)
	var material: BaseMaterial3D
	if authored is BaseMaterial3D:
		material = (authored as BaseMaterial3D).duplicate() as BaseMaterial3D
	else:
		material = StandardMaterial3D.new()
	material.albedo_color = MatchController.tint_color(colour)
	material.emission_enabled = true
	material.emission = Color(colour.r, colour.g, colour.b, 1.0)
	material.emission_energy_multiplier = 0.9
	mesh.set_surface_override_material(index, material)
