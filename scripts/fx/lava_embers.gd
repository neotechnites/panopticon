@tool
class_name LavaEmbers
extends Node3D
## Hell's ash: black flakes rising off every lava surface (sea, rivers, shelf, falls) on a gusty updraft, plus a few sparks.
## Builds its GPUParticles3D at ready (shows in the editor too); tune the exports on this node.

## Spark count multiplier; 0 turns the sparks off.
@export_range(0.0, 4.0, 0.05) var density: float = 1.0:
	set(value):
		density = value
		_rebuild()
## Updraft speed multiplier (ash and sparks).
@export_range(0.1, 4.0, 0.05) var speed: float = 1.0:
	set(value):
		speed = value
		_rebuild()
## Ash flake count multiplier; 0 turns the ash off.
@export_range(0.0, 4.0, 0.05) var ash: float = 1.0:
	set(value):
		ash = value
		_rebuild()
## Ash flake size in metres off the rivers, shelf and falls (seen 5-15 m from the deck).
@export_range(0.02, 1.0, 0.01) var ember_size: float = 0.3:
	set(value):
		ember_size = value
		_rebuild()
## Ash flake size in metres off the sea (seen from the tower and down the pit).
@export_range(0.05, 2.0, 0.01) var sea_ember_size: float = 0.55:
	set(value):
		sea_ember_size = value
		_rebuild()
## Sea emitter: centre height, inner and outer radius round the tower.
@export var sea_y: float = -10.6
@export var sea_inner: float = 13.0
@export var sea_outer: float = 44.0
## World points on the S2/S4/S5 deck rivers and the S5 shelf, every 2 m, from the LavaRiver surfaces.
@export var river_points: PackedVector3Array = PackedVector3Array()
## World points on the S4/S5 lava falls, every 3.5 m, from the LavaRiver surfaces.
@export var fall_points: PackedVector3Array = PackedVector3Array()

const SEA_ASH: int = 700
const RIVER_ASH: int = 1000
const FALL_ASH: int = 300
const SPARKS: int = 30
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
	var flake: StandardMaterial3D = _ash_material()
	var sea: ParticleProcessMaterial = _ash_motion(2.0, 3.5, 2.0)
	_ring(sea)
	_emitter(&"SeaAsh", SEA_ASH * ash, 13.0, sea, flake, sea_ember_size)
	if not river_points.is_empty():
		var river: ParticleProcessMaterial = _ash_motion(0.6, 1.4, 0.8)
		_points(river, river_points)
		_emitter(&"RiverAsh", RIVER_ASH * ash, 7.0, river, flake, ember_size)
	if not fall_points.is_empty():
		var fall: ParticleProcessMaterial = _ash_motion(0.8, 1.8, 1.0)
		_points(fall, fall_points)
		_emitter(&"FallAsh", FALL_ASH * ash, 8.0, fall, flake, ember_size)
	var sparks: ParticleProcessMaterial = _spark_motion()
	var all_points: PackedVector3Array = river_points + fall_points
	if all_points.is_empty():
		_ring(sparks)
	else:
		_points(sparks, all_points)
	_emitter(&"Sparks", SPARKS * density, 1.6, sparks, _spark_material(), ember_size * 0.5)


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
	p.randomness = 0.8
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


func _points(m: ParticleProcessMaterial, points: PackedVector3Array) -> void:
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	m.emission_point_texture = _points_texture(points)
	m.emission_point_count = points.size()


# Black flakes on the updraft: rise, slow and spread, tumble, veer on random-signed gusts.
func _ash_motion(v_min: float, v_max: float, gust: float) -> ParticleProcessMaterial:
	var m: ParticleProcessMaterial = ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 25.0
	m.initial_velocity_min = v_min * speed
	m.initial_velocity_max = v_max * speed
	m.gravity = Vector3(0.0, 0.15 * speed, 0.0)
	m.damping_min = 0.05 * speed
	m.damping_max = 0.25 * speed
	m.tangential_accel_min = -0.4 * gust * speed
	m.tangential_accel_max = 0.4 * gust * speed
	m.radial_accel_min = -0.2 * gust * speed
	m.radial_accel_max = 0.3 * gust * speed
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -220.0
	m.angular_velocity_max = 220.0
	m.scale_min = 0.5
	m.scale_max = 1.3
	m.lifetime_randomness = 0.4
	m.color_initial_ramp = _ramp(PackedFloat32Array([0.0, 1.0]), [Color(0.03, 0.025, 0.02), Color(0.14, 0.12, 0.11)])
	m.color_ramp = _ramp(PackedFloat32Array([0.0, 0.08, 0.75, 1.0]), [
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
	return m


# A few hot sparks: fast, short, white-yellow cooling to dark.
func _spark_motion() -> ParticleProcessMaterial:
	var m: ParticleProcessMaterial = ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 35.0
	m.initial_velocity_min = 3.0 * speed
	m.initial_velocity_max = 6.0 * speed
	m.gravity = Vector3(0.0, 0.5, 0.0)
	m.tangential_accel_min = -1.0 * speed
	m.tangential_accel_max = 1.0 * speed
	m.scale_min = 0.6
	m.scale_max = 1.2
	m.lifetime_randomness = 0.6
	m.color_ramp = _ramp(PackedFloat32Array([0.0, 0.15, 0.3, 0.45, 0.6, 1.0]), [
		Color(1.0, 0.98, 0.8, 1.0), Color(1.0, 0.8, 0.35, 1.0), Color(1.0, 0.5, 0.1, 0.5),
		Color(1.0, 0.45, 0.08, 0.9), Color(0.7, 0.2, 0.03, 0.6), Color(0.2, 0.03, 0.0, 0.0)])
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


# An irregular flake: a jagged polygon whose radius wanders round the circle, hard-edged.
func _flake_texture() -> ImageTexture:
	const N: int = 24
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var radii: PackedFloat32Array = PackedFloat32Array()
	radii.resize(8)
	for i: int in 8:
		radii[i] = rng.randf_range(0.35, 1.0)
	var img: Image = Image.create_empty(N, N, false, Image.FORMAT_RGBA8)
	var c: float = (N - 1) * 0.5
	for y: int in N:
		for x: int in N:
			var d: Vector2 = Vector2(x - c, y - c) / c
			var a: float = fposmod(d.angle() / TAU, 1.0) * 8.0
			var i0: int = int(a) % 8
			var r: float = lerpf(radii[i0], radii[(i0 + 1) % 8], a - floorf(a))
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if d.length() <= r else 0.0))
	return ImageTexture.create_from_image(img)


func _ash_material() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _flake_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	return m


func _spark_material() -> StandardMaterial3D:
	var dot: Gradient = Gradient.new()
	dot.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	dot.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = dot
	tex.width = 16
	tex.height = 16
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(2.0, 2.0, 2.0, 1.0)
	m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	return m
