@tool
class_name LavaEmbers
extends Node3D
## Hell's embers and ash rising off the lava: a ring over the sea, points on the rivers and falls.
## Builds its CPUParticles3D at ready (shows in the editor too); tune the exports on this node.

## Ember count multiplier; 0 turns the embers off.
@export_range(0.0, 4.0, 0.05) var density: float = 1.0:
	set(value):
		density = value
		_rebuild()
## Rise speed multiplier (also scales the swirl).
@export_range(0.1, 4.0, 0.05) var speed: float = 1.0:
	set(value):
		speed = value
		_rebuild()
## Ash fleck count multiplier; 0 turns the ash off.
@export_range(0.0, 4.0, 0.05) var ash: float = 1.0:
	set(value):
		ash = value
		_rebuild()
## Ember quad size in metres.
@export_range(0.02, 0.6, 0.01) var ember_size: float = 0.28:
	set(value):
		ember_size = value
		_rebuild()
## Sea emitter: centre height, inner and outer radius round the tower.
@export var sea_y: float = -10.6
@export var sea_inner: float = 13.0
@export var sea_outer: float = 44.0
## World points on the S2/S4/S5 rivers and falls, sampled from the LavaRiver surfaces.
@export var river_points: PackedVector3Array = PackedVector3Array()

const SEA_EMBERS: int = 100
const RIVER_EMBERS: int = 60
const ASH_FLECKS: int = 26


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child: Node in get_children():
		if child.has_meta(&"lava_embers"):
			remove_child(child)
			child.queue_free()
	var ember_mat: StandardMaterial3D = _material(true)
	var ash_mat: StandardMaterial3D = _material(false)
	var sea: CPUParticles3D = _emitter(&"SeaEmbers", SEA_EMBERS * density, 11.0, ember_mat, ember_size)
	_ring(sea)
	_ember_motion(sea, 1.6, 3.4)
	if not river_points.is_empty():
		var river: CPUParticles3D = _emitter(&"RiverEmbers", RIVER_EMBERS * density, 6.0, ember_mat, ember_size)
		river.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
		river.emission_points = river_points
		_ember_motion(river, 1.2, 2.6)
	var flecks: CPUParticles3D = _emitter(&"Ash", ASH_FLECKS * ash, 16.0, ash_mat, ember_size * 1.3)
	_ring(flecks)
	flecks.direction = Vector3.UP
	flecks.spread = 25.0
	flecks.initial_velocity_min = 0.8 * speed
	flecks.initial_velocity_max = 1.8 * speed
	flecks.gravity = Vector3(0.0, 0.25 * speed, 0.0)
	flecks.tangential_accel_min = 0.05 * speed
	flecks.tangential_accel_max = 0.2 * speed
	flecks.damping_min = 0.05
	flecks.damping_max = 0.15
	flecks.angular_velocity_min = -90.0
	flecks.angular_velocity_max = 90.0
	flecks.color_ramp = _ramp(PackedFloat32Array([0.0, 0.1, 0.75, 1.0]), [
		Color(0.22, 0.2, 0.19, 0.0), Color(0.22, 0.2, 0.19, 0.85),
		Color(0.3, 0.28, 0.27, 0.6), Color(0.3, 0.28, 0.27, 0.0)])


func _emitter(node_name: StringName, count: float, life: float, mat: StandardMaterial3D, size: float) -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	p.name = node_name
	p.set_meta(&"lava_embers", true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.local_coords = false
	p.amount = maxi(1, roundi(count))
	p.emitting = count > 0.0
	p.visible = count > 0.0
	p.lifetime = life / speed
	p.preprocess = p.lifetime
	p.randomness = 0.6
	p.lifetime_randomness = 0.4
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	p.mesh = quad
	add_child(p)
	return p


func _ring(p: CPUParticles3D) -> void:
	p.position = Vector3(0.0, sea_y, 0.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_height = 0.6
	p.emission_ring_radius = sea_outer
	p.emission_ring_inner_radius = sea_inner


# Rise, a gentle swirl round the tower, flicker and fade.
func _ember_motion(p: CPUParticles3D, v_min: float, v_max: float) -> void:
	p.direction = Vector3.UP
	p.spread = 20.0
	p.initial_velocity_min = v_min * speed
	p.initial_velocity_max = v_max * speed
	p.gravity = Vector3(0.0, 0.2 * speed, 0.0)
	p.tangential_accel_min = 0.1 * speed
	p.tangential_accel_max = 0.3 * speed
	p.damping_min = 0.0
	p.damping_max = 0.2
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color_initial_ramp = _ramp(PackedFloat32Array([0.0, 1.0]), [Color(1.0, 0.45, 0.08), Color(1.0, 0.85, 0.4)])
	p.color_ramp = _ramp(PackedFloat32Array([0.0, 0.06, 0.2, 0.3, 0.45, 0.55, 0.7, 0.85, 1.0]), [
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.9), Color(0.9, 0.6, 0.5, 0.45), Color(0.8, 0.4, 0.3, 0.6),
		Color(0.6, 0.2, 0.1, 0.0)])


func _ramp(offsets: PackedFloat32Array, colors: Array) -> Gradient:
	var g: Gradient = Gradient.new()
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	return g


# Unshaded billboard dot; embers blend additive, ash blends over.
func _material(glow: bool) -> StandardMaterial3D:
	var dot: Gradient = _ramp(PackedFloat32Array([0.0, 0.35, 1.0]),
		[Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = dot
	tex.width = 16
	tex.height = 16
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if glow else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = glow
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(2.0, 2.0, 2.0, 1.0) if glow else Color(1, 1, 1, 1)
	m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	return m
