class_name CharacterRig
extends Node3D
## The players' own key and fill, on the body layers only, turned with the viewing camera.
## The map's lights still reach the bodies; this makes sure the side seen always shows its planes.

const NAME: StringName = &"CharacterRig"
## [member PrisonerAvatar.visual_layers]' two values: the owner-hidden layer 2 and the AI's layer 3.
const BODY_LAYERS: int = 2 | 4
## Toward the key, in the camera's frame: above and to the left of the viewer.
const KEY_FROM: Vector3 = Vector3(-0.6, 0.4, 0.69)
## Toward the fill: to the viewer's right, low.
const FILL_FROM: Vector3 = Vector3(0.75, 0.15, 0.64)


## How much of the fit's hue the key and fill carry: the map's own lights bring the rest, so skin keeps its pink.
const TINT: float = 0.5


## Hang the key and fill in [param fit]'s colours.
func dress(fit: CharacterFit) -> void:
	name = NAME
	_hang(fit.light, KEY_FROM)
	_hang(fit.shade, FILL_FROM)


func _hang(colour: Color, from: Vector3) -> void:
	var lamp: DirectionalLight3D = DirectionalLight3D.new()
	var level: float = maxf(colour.r, maxf(colour.g, colour.b))
	lamp.light_color = Color.WHITE.lerp(Color(colour.r / level, colour.g / level, colour.b / level), TINT)
	lamp.light_energy = level
	lamp.light_cull_mask = BODY_LAYERS
	lamp.shadow_enabled = false
	lamp.basis = Basis.looking_at(-from.normalized(), Vector3.UP)
	add_child(lamp)


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		global_basis = camera.global_basis
