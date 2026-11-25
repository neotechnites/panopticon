class_name BodyMaterial
extends RefCounted
## The one owner of a body mesh's materials: each surface derived from the authored one, the shirt tint,
## its alpha (a ghost) and a whole-body fade (active camo), so none of them overwrites another.

const META: StringName = &"body_material"
const FADED_FROM: StringName = &"body_material_faded_from"

## Faded duplicates, one per base material and alpha; each holds its base, so an id is never reused.
static var _faded_cache: Dictionary[String, Material] = {}

## The shirt's material (the whole mesh's on a body with no shirt); null wears the authored one.
var tint: Material = null
## How the standing map lights the body; null leaves materials as they are.
var light: CharacterLight = null
## Whole-body opacity on top of the tint's own alpha.
var fade: float = 1.0

var _mesh: MeshInstance3D = null
var _authored_override: Material = null


## [param mesh]'s look, made the first time it is asked for.
static func of(mesh: MeshInstance3D) -> BodyMaterial:
	if mesh.has_meta(META):
		return mesh.get_meta(META) as BodyMaterial
	var look: BodyMaterial = BodyMaterial.new()
	look._mesh = mesh
	look._authored_override = mesh.material_override
	mesh.set_meta(META, look)
	return look


## Wear [param material] on the shirt, lit by [param with_light].
func paint(material: Material, with_light: CharacterLight) -> void:
	tint = material
	light = with_light
	dress(_mesh, fade)


## Draw the whole body at [param alpha] (1.0 is opaque), the colours untouched.
func set_fade(alpha: float) -> void:
	if alpha == fade:
		return
	fade = alpha
	dress(_mesh, fade)


## The material the body wears before any fade: the tint, or the authored whole-mesh one.
func worn() -> Material:
	if tint != null:
		return tint
	return _authored_override if MatchController.shirt_surface_of(_mesh) < 0 else null


## Dress [param target] (this mesh, or one drawing the same model) in this look at [param alpha].
func dress(target: MeshInstance3D, alpha: float) -> void:
	if target == null or target.mesh == null:
		return
	var shirt: int = MatchController.shirt_surface_of(target)
	var whole: Material = tint if tint != null else _authored_override
	if whole != null and (shirt < 0 or tint == null):
		target.material_override = _faded(whole, alpha)
		return
	target.material_override = null
	var body_alpha: float = _alpha_of(tint) * alpha
	for index: int in target.mesh.get_surface_count():
		var authored: Material = target.mesh.surface_get_material(index)
		var drawn: Material
		if index == shirt and tint != null:
			drawn = _lit(_faded(tint, alpha))
		else:
			drawn = _lit(_faded(authored, body_alpha))
		target.set_surface_override_material(index, null if drawn == authored else drawn)


func _lit(material: Material) -> Material:
	return material if light == null else light.apply(material)


static func _alpha_of(material: Material) -> float:
	var albedo: BaseMaterial3D = material as BaseMaterial3D
	return 1.0 if albedo == null else albedo.albedo_color.a


## [param base] with its alpha scaled by [param alpha]; [param base] itself when opaque.
static func _faded(base: Material, alpha: float) -> Material:
	if alpha >= 1.0:
		return base
	if base != null and not base is BaseMaterial3D:
		return base
	var key: String = "%d|%.3f" % [0 if base == null else base.get_instance_id(), alpha]
	if _faded_cache.has(key):
		return _faded_cache[key]
	var material: BaseMaterial3D
	if base == null:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		material = base.duplicate() as BaseMaterial3D
		material.set_meta(FADED_FROM, base)
	material.albedo_color.a *= alpha
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_faded_cache[key] = material
	return material
