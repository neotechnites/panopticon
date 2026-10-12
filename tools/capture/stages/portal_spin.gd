extends "res://tools/capture/stages/stage.gd"

## portal_spin: the finish portal's swirl for the portal_spin short (brief tools/content/projects/portal_spin.md).
## --set=mode=zoom|wave|dial|orbit; dial: spin_at=T turns the spin dial 0 -> 0.8 rad/s live at take T.

const PORTAL_SHADER: String = "res://maps/bentham_ring/materials/portal_wave.gdshader"
const DIAL_SHADER: String = "res://tools/capture/stages/portal_spin_dial.gdshader"
## The shipped spin, rad/s (portal_wave.gdshader WAVE_SPIN).
const SPIN: float = 0.8
## Godot's editor viewport grey, near enough.
const EDITOR_GREY := Color(0.27, 0.27, 0.29)
## v4 (Ryan): the hell portal wears the other maps' spiral swirl, in hell's colours, for this short only.
const SWIRL_PATH: String = "res://tools/content/projects/portal_spin/hell_swirl.png"

var _mode: String = "zoom"
var _portal: MeshInstance3D = null
var _centre: Vector3 = Vector3.ZERO
var _normal: Vector3 = Vector3.FORWARD
var _radius: float = 2.0
var _dials: Array[ShaderMaterial] = []
var _spin_at: float = -1.0


func bots() -> int:
	return 1


func before_start() -> void:
	_mode = String(option("mode", "zoom"))
	_spin_at = float(option("spin_at", -1.0))
	for node: Node in LIB._walk(clip.root):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for s: int in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(s) as ShaderMaterial
			if mat != null and mat.shader != null and mat.shader.resource_path == PORTAL_SHADER:
				_portal = mesh
				var worn: ShaderMaterial = _dial_copy(mat) if _mode == "dial" else mat.duplicate() as ShaderMaterial
				if bool(option("swirl", true)):
					var tex := ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(SWIRL_PATH)))
					worn.set_shader_parameter(&"albedo_texture", tex)
					worn.set_shader_parameter(&"emission_texture", tex)
				mesh.set_surface_override_material(s, worn)
	if _portal == null:
		say("no portal found")
		return
	var local: AABB = _portal.get_aabb()
	var box: AABB = _portal.global_transform * local
	_centre = box.get_center()
	# The sheet's thinnest local axis is its normal; it faces back down the ring (bearing falling), where the runners come from.
	var axis: int = 0 if local.size.x <= minf(local.size.y, local.size.z) else (1 if local.size.y <= local.size.z else 2)
	_normal = _portal.global_transform.basis[axis]
	_normal = Vector3(_normal.x, 0.0, _normal.z).normalized()
	if _normal.dot(-LIB.tangent_at(LIB.bearing_of(_centre))) < 0.0:
		_normal = -_normal
	var size: Vector3 = local.size
	_radius = maxf(size.y, maxf(size.x, size.z)) * 0.5
	say("portal %s centre %s size %s normal %s" % [_portal.get_path(), _centre, size, _normal])
	if _mode == "dial":
		_editor_view()


## A copy of the portal's material on the dial shader, every parameter carried over.
func _dial_copy(mat: ShaderMaterial) -> ShaderMaterial:
	var copy := ShaderMaterial.new()
	copy.shader = load(DIAL_SHADER) as Shader
	for u: Dictionary in mat.shader.get_shader_uniform_list():
		copy.set_shader_parameter(u["name"], mat.get_shader_parameter(u["name"]))
	copy.set_shader_parameter(&"spin_angle", 0.0)
	_dials.append(copy)
	return copy


## Only the portal on the editor's flat grey: no map, no bodies, no fog, no post.
func _editor_view() -> void:
	var keep: Array[Node] = []
	var n: Node = _portal
	while n != null:
		keep.append(n)
		n = n.get_parent()
	for node: Node in LIB._walk(clip.root):
		var vis := node as VisualInstance3D
		if vis != null and vis != _portal and not keep.has(vis) and not (vis is Light3D):
			vis.visible = false
		if node is CanvasLayer and node.name != "ClipSync":
			(node as CanvasLayer).visible = false
		var env_node := node as WorldEnvironment
		if env_node != null and env_node.environment != null:
			var env: Environment = env_node.environment.duplicate()
			env.background_mode = Environment.BG_COLOR
			env.background_color = EDITOR_GREY
			env.fog_enabled = false
			env.volumetric_fog_enabled = false
			env.glow_enabled = false
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.6, 0.6, 0.6)
			env.tonemap_exposure = 1.0
			env_node.environment = env


## Every prisoner is parked across the ring, out of every portal frame, before the cut.
func cast(runners: Array[RunnerBrain]) -> bool:
	for i: int in runners.size():
		var at: Vector3 = LIB.ring_point(160.0 + 6.0 * i, 50.0, 0.1)
		drive(runners[i], [{"do": "place", "at": at, "face": LIB.tangent_at(160.0)}, {"do": "hold", "seconds": 120.0}], i)
	return true


func tick(_delta: float) -> void:
	if _dials.is_empty() or _spin_at < 0.0:
		return
	var angle: float = maxf(elapsed() - _spin_at, 0.0) * SPIN
	for d: ShaderMaterial in _dials:
		d.set_shader_parameter(&"spin_angle", angle)


func lens(_delta: float) -> bool:
	if _portal == null:
		return false
	var cam: Camera3D = camera()
	var t: float = elapsed()
	var side: Vector3 = _normal.cross(Vector3.UP).normalized()
	var pos: Vector3
	var look: Vector3 = _centre
	match _mode:
		"zoom":
			# A slow push straight in, from the whole arch to the swirl filling the frame.
			var u: float = smoothstep(0.0, 1.0, clampf((t - 0.6) / float(option("push", 9.0)), 0.0, 1.0))
			var far: float = float(option("far", 13.0))
			var near: float = float(option("near", 6.5))
			# v5: from L4's side and height, so the wave's bulge off the disc reads while it spins.
			pos = _centre + _normal * lerpf(far, near, u) + Vector3.UP * lerpf(1.8, 1.2, u) + side * lerpf(3.4, 2.4, u)
			look = _centre + Vector3.DOWN * 0.4
		"wave":
			# Over the end of the S5 lava lake (292-338 deg), looking down past it: the lava wave and the swirl in one frame.
			var u2: float = clampf((t - 0.6) / 10.0, 0.0, 1.0)
			pos = _centre + _normal * float(option("dist", 9.0)) + side * lerpf(3.2, 2.2, u2) + Vector3.UP * float(option("rise", 1.8))
			look = _centre + Vector3.DOWN * float(option("drop", 1.5))
		"dial":
			# Straight on, the swirl centred: the editor's viewport on one mesh.
			pos = _centre + _normal * float(option("dist", 9.0)) + Vector3.UP * float(option("lift", 1.0))
			look = _centre + Vector3.UP * float(option("lift", 1.0))
		_:
			# orbit: a slow arc across the front of the portal.
			var a: float = deg_to_rad(lerpf(-28.0, 18.0, clampf((t - 0.6) / 9.0, 0.0, 1.0)))
			var dir: Vector3 = (_normal * cos(a) + side * sin(a)).normalized()
			pos = _centre + dir * float(option("dist", 8.0)) + Vector3.UP * 0.4
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = float(option("fov", 60.0))
	if not cam.current:
		cam.current = true
	return true
