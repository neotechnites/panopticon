@tool
class_name LavaEmbers
extends Node3D
## Hell's embers and ash rising off the lava: a ring over the sea, points on the rivers and falls.
## Builds its GPUParticles3D at ready (shows in the editor too); tune the exports on this node.

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

const SEA_EMBERS: int = 120
const RIVER_EMBERS: int = 60
const ASH_FLECKS: int = 26
## Every particle stays inside this box round the ring (node space): the pit, the deck and above.
const BOUNDS: AABB = AABB(Vector3(-64.0, -14.0, -64.0), Vector3(128.0, 74.0, 128.0))


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
	var sea: ParticleProcessMaterial = _ember_motion(2.2, 4.2)
	_ring(sea)
	_emitter(&"SeaEmbers", SEA_EMBERS * density, 11.0, sea, ember_mat, ember_size)
	if not river_points.is_empty():
		var river: ParticleProcessMaterial = _ember_motion(1.2, 2.6)
		river.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
		river.emission_point_texture = _points_texture(river_points)
		river.emission_point_count = river_points.size()
		_emitter(&"RiverEmbers", RIVER_EMBERS * density, 6.0, river, ember_mat, ember_size)
	var flecks: ParticleProcessMaterial = ParticleProcessMaterial.new()
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
	flecks.lifetime_randomness = 0.4
	flecks.color_ramp = _ramp(PackedFloat32Array([0.0, 0.1, 0.75, 1.0]), [
		Color(0.22, 0.2, 0.19, 0.0), Color(0.22, 0.2, 0.19, 0.85),
		Color(0.3, 0.28, 0.27, 0.6), Color(0.3, 0.28, 0.27, 0.0)])
	_emitter(&"Ash", ASH_FLECKS * ash, 16.0, flecks, _material(false), ember_size * 1.3)


func _emitter(node_name: StringName, count: float, life: float, process: ParticleProcessMaterial,
		mat: StandardMaterial3D, size: float) -> void:
	var p: GPUParticles3D = GPUParticles3D.new()
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
	p.visibility_aabb = BOUNDS
	p.process_material = process
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)


func _ring(m: ParticleProcessMaterial) -> void:
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_shape_offset = Vector3(0.0, sea_y, 0.0)
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_height = 0.6
	m.emission_ring_radius = sea_outer
	m.emission_ring_inner_radius = sea_inner


# Rise, a gentle swirl round the tower, flicker and fade.
func _ember_motion(v_min: float, v_max: float) -> ParticleProcessMaterial:
	var m: ParticleProcessMaterial = ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 20.0
	m.initial_velocity_min = v_min * speed
	m.initial_velocity_max = v_max * speed
	m.gravity = Vector3(0.0, 0.4 * speed, 0.0)
	m.tangential_accel_min = 0.1 * speed
	m.tangential_accel_max = 0.3 * speed
	m.damping_min = 0.0
	m.damping_max = 0.2
	m.scale_min = 0.5
	m.scale_max = 1.2
	m.lifetime_randomness = 0.4
	m.color_initial_ramp = _ramp(PackedFloat32Array([0.0, 1.0]), [Color(1.0, 0.6, 0.15), Color(1.0, 0.95, 0.55)])
	m.color_ramp = _ramp(PackedFloat32Array([0.0, 0.06, 0.2, 0.3, 0.45, 0.55, 0.7, 0.85, 1.0]), [
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.9), Color(0.9, 0.6, 0.5, 0.45), Color(0.8, 0.4, 0.3, 0.6),
		Color(0.6, 0.2, 0.1, 0.0)])
	return m


func _ramp(offsets: PackedFloat32Array, colors: Array) -> GradientTexture1D:
	var g: Gradient = Gradient.new()
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = g
	return tex


# One texel per emission point, xyz in rgb.
func _points_texture(points: PackedVector3Array) -> ImageTexture:
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(points.size() * 3)
	for i: int in points.size():
		data[i * 3] = points[i].x
		data[i * 3 + 1] = points[i].y
		data[i * 3 + 2] = points[i].z
	var img: Image = Image.create_from_data(points.size(), 1, false, Image.FORMAT_RGBF, data.to_byte_array())
	return ImageTexture.create_from_image(img)


# Unshaded billboard dot; embers blend additive, ash blends over.
func _material(glow: bool) -> StandardMaterial3D:
	var dot: Gradient = Gradient.new()
	dot.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	dot.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
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
