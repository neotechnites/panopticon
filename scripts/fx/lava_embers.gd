@tool
class_name LavaEmbers
extends Node3D
## Hell's sparks and ash: short hot streaks gusting up off the sea, rivers and falls; dark flakes tumbling down.
## Builds its GPUParticles3D at ready (shows in the editor too); tune the exports on this node.

## Spark count multiplier; 0 turns the sparks off.
@export_range(0.0, 4.0, 0.05) var density: float = 1.0:
	set(value):
		density = value
		_rebuild()
## Updraft speed multiplier (sparks and ash both).
@export_range(0.1, 4.0, 0.05) var speed: float = 1.0:
	set(value):
		speed = value
		_rebuild()
## Ash flake count multiplier; 0 turns the ash off.
@export_range(0.0, 4.0, 0.05) var ash: float = 1.0:
	set(value):
		ash = value
		_rebuild()
## River and fall spark streak length in metres (they fly beside the runners).
@export_range(0.02, 1.0, 0.01) var ember_size: float = 0.22:
	set(value):
		ember_size = value
		_rebuild()
## Sea spark streak length in metres (seen 30 m down the pit).
@export_range(0.05, 2.0, 0.01) var sea_ember_size: float = 0.45:
	set(value):
		sea_ember_size = value
		_rebuild()
## Sea emitter: centre height, inner and outer radius round the tower.
@export var sea_y: float = -10.6
@export var sea_inner: float = 13.0
@export var sea_outer: float = 44.0
## World points on the S2/S4/S5 rivers and falls, sampled from the LavaRiver surfaces.
@export var river_points: PackedVector3Array = PackedVector3Array()

const SEA_SPARKS: int = 45
const RIVER_SPARKS: int = 24
const ASH_FLAKES: int = 70
## Streak width as a fraction of its length.
const STREAK_WIDTH: float = 0.12
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
	var spark_mat: StandardMaterial3D = _spark_material()
	var sea: ParticleProcessMaterial = _spark_motion(7.0, 12.0)
	_ring(sea, 0.6, sea_y)
	_emitter(&"SeaSparks", SEA_SPARKS * density, 2.6, sea, spark_mat,
		Vector2(sea_ember_size * STREAK_WIDTH, sea_ember_size))
	if not river_points.is_empty():
		var river: ParticleProcessMaterial = _spark_motion(3.0, 6.0)
		river.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
		river.emission_point_texture = _points_texture(river_points)
		river.emission_point_count = river_points.size()
		_emitter(&"RiverSparks", RIVER_SPARKS * density, 1.4, river, spark_mat,
			Vector2(ember_size * STREAK_WIDTH, ember_size))
	# Ash fills the pit and the ring, sinking and swirling on the gusts.
	var flakes: ParticleProcessMaterial = ParticleProcessMaterial.new()
	_ring(flakes, 36.0, 12.0)
	flakes.emission_ring_inner_radius = 10.0
	flakes.emission_ring_radius = 58.0
	flakes.direction = Vector3(1.0, 0.0, 0.0)
	flakes.spread = 180.0
	flakes.initial_velocity_min = 0.1
	flakes.initial_velocity_max = 0.5 * speed
	flakes.gravity = Vector3(0.0, -0.18 * speed, 0.0)
	flakes.damping_min = 0.3
	flakes.damping_max = 0.6
	_turbulence(flakes, 1.2, 0.6)
	flakes.angle_min = -180.0
	flakes.angle_max = 180.0
	flakes.angular_velocity_min = -160.0
	flakes.angular_velocity_max = 160.0
	flakes.scale_min = 0.5
	flakes.scale_max = 1.3
	flakes.lifetime_randomness = 0.3
	flakes.color_ramp = _ramp(PackedFloat32Array([0.0, 0.15, 0.85, 1.0]), [
		Color(0.16, 0.14, 0.13, 0.0), Color(0.16, 0.14, 0.13, 0.9),
		Color(0.22, 0.2, 0.19, 0.8), Color(0.22, 0.2, 0.19, 0.0)])
	_emitter(&"Ash", ASH_FLAKES * ash, 14.0, flakes, _ash_material(), Vector2(0.09, 0.07))


func _emitter(node_name: StringName, count: float, life: float, process: ParticleProcessMaterial,
		mat: StandardMaterial3D, size: Vector2) -> void:
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
	quad.size = size
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)


func _ring(m: ParticleProcessMaterial, height: float, y: float) -> void:
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_shape_offset = Vector3(0.0, y, 0.0)
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_height = height
	m.emission_ring_radius = sea_outer
	m.emission_ring_inner_radius = sea_inner


func _turbulence(m: ParticleProcessMaterial, strength: float, gust: float) -> void:
	m.turbulence_enabled = true
	m.turbulence_noise_strength = strength
	m.turbulence_noise_scale = 6.0
	m.turbulence_noise_speed = Vector3(0.6, 0.3, 0.0) * gust * speed
	m.turbulence_noise_speed_random = 0.4
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.25


# Fast, gusty spark: velocity-aligned streak, white-yellow cooling through orange to dark, flickering out.
func _spark_motion(v_min: float, v_max: float) -> ParticleProcessMaterial:
	var m: ParticleProcessMaterial = ParticleProcessMaterial.new()
	m.particle_flag_align_y = true
	m.direction = Vector3.UP
	m.spread = 30.0
	m.initial_velocity_min = v_min * speed
	m.initial_velocity_max = v_max * speed
	m.gravity = Vector3(0.0, -1.5, 0.0)
	m.damping_min = 0.5
	m.damping_max = 2.0
	_turbulence(m, 2.5, 1.5)
	m.scale_min = 0.6
	m.scale_max = 1.2
	m.scale_curve = _shrink()
	m.lifetime_randomness = 0.6
	m.color_ramp = _ramp(PackedFloat32Array([0.0, 0.1, 0.25, 0.35, 0.5, 0.6, 0.8, 1.0]), [
		Color(1.0, 0.98, 0.85, 1.0), Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.6, 0.15, 0.6),
		Color(1.0, 0.55, 0.1, 1.0), Color(0.95, 0.35, 0.05, 0.5), Color(0.9, 0.3, 0.04, 0.85),
		Color(0.5, 0.1, 0.02, 0.4), Color(0.2, 0.03, 0.0, 0.0)])
	return m


func _shrink() -> CurveTexture:
	var c: Curve = Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.3))
	var tex: CurveTexture = CurveTexture.new()
	tex.curve = c
	return tex


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


# Additive, unshaded streak; fixed-Y billboard so the long axis follows the spark's velocity.
func _spark_material() -> StandardMaterial3D:
	var m: StandardMaterial3D = _soft_material(true)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.8, 1.8, 1.8, 1.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	return m


# Alpha-blended dark flake, camera-facing, tumbling by particle angle.
func _ash_material() -> StandardMaterial3D:
	var m: StandardMaterial3D = _soft_material(false)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_color = Color(1, 1, 1, 1)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return m


func _soft_material(glow: bool) -> StandardMaterial3D:
	var edge: Gradient = Gradient.new()
	edge.offsets = PackedFloat32Array([0.0, 0.6, 1.0]) if glow else PackedFloat32Array([0.0, 0.8, 1.0])
	edge.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = edge
	tex.width = 16
	tex.height = 16
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = glow
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.billboard_keep_scale = true
	return m
