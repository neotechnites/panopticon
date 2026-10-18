extends "res://tools/capture/stages/stage.gd"

## death_void: short 4 M2. Ryan: "shot of the animation in a grey space jsut playing" (the old death clip, ragdoll off).
## [code]--stage=death_void --shot=s3_open_lane --bots=1 --seed=20261017[/code]; [event] death at die_at, the clip plays once and lies.

# One prisoner on the flat clear deck at 195 deg r 52 (melee.gd's probe_ring --clear: r 47.5-56.5 from 179 to 210).
# Every mesh but his is hidden, lights but the sun off; a grey background and an invisible floor that only
# catches his shadow, so there is no horizon and only the shadow grounds him.
# The lens 4.6 m off, 1.0 m up, fov 40: 3.3 m of frame height, 1.9 m across the portrait width; he faces 35 deg off
# the lens so the backward fall runs away from it, not across the frame.
# Dials (--set=): deg (195), r (52), die_at (1.6 s, the death clip starts), dist (4.6), cam_h (1.0), fov (40), turn (35), grey (0.5).

const BODY_DEG: float = 195.0
const BODY_R: float = 52.0

var _body: PlayerController = null
var _avatar: PrisonerAvatar = null
var _died: bool = false
var _lens_at: Vector3 = Vector3.ZERO
var _look_at: Vector3 = Vector3.ZERO
var _floor: MeshInstance3D = null


func bots() -> int:
	return 1


func before_start() -> void:
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
	# Grey from the first frame: a real-time take's clock reaches the cast late, so nothing waits for it.
	var deg: float = float(option("deg", BODY_DEG))
	var r: float = float(option("r", BODY_R))
	_lens_at = LIB.ring_point(deg - rad_to_deg(float(option("dist", 4.6)) / r), r, float(option("cam_h", 1.0)))
	_look_at = LIB.ring_point(deg, r, 0.75)
	_grey_the_world()


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.is_empty() or runners[0].controller == null:
		return false
	var deg: float = float(option("deg", BODY_DEG))
	var r: float = float(option("r", BODY_R))
	var at: Vector3 = LIB.ring_point(deg, r, 0.1)
	var dist: float = float(option("dist", 4.6))
	var face: Vector3 = LIB.toward(at, _lens_at).rotated(Vector3.UP, deg_to_rad(float(option("turn", 35.0))))
	_body = runners[0].controller
	_avatar = PrisonerAvatar.of(_body)
	if _avatar != null:
		_avatar.set(&"_ragdoll", null)
	drive(runners[0], [
		{"do": "place", "at": at, "face": face},
		{"do": "hold", "seconds": 60.0, "sway": 0.0, "period": 3.1},
	], 0)
	for node: Node in clip.root.find_children("*", "GeometryInstance3D", true, false):
		if node != _floor and not _body.is_ancestor_of(node):
			(node as GeometryInstance3D).visible = false
	say("death_void: %s at %.1f deg r %.1f, lens %.1f m off, ragdoll %s" % [_body.name, deg, r, dist, "off" if _avatar != null else "?"])
	return true


func tick(_delta: float) -> void:
	if _died or _avatar == null or elapsed() < float(option("die_at", 1.6)):
		return
	_died = true
	_avatar.call(&"_on_body_died")
	print("[event] %6.2f  death  %s" % [elapsed(), _body.name])


func lens(_delta: float) -> bool:
	if camera() == null or _lens_at == Vector3.ZERO:
		return false
	camera().global_position = _lens_at
	camera().look_at(_look_at, Vector3.UP)
	camera().fov = float(option("fov", 40.0))
	camera().current = true
	return true


## Hide every mesh but the players', every light but the sun; a grey background and a shadow-catching floor.
func _grey_the_world() -> void:
	var shade: float = float(option("grey", 0.5))
	var players: Array[Node] = clip.root.find_children("*", "PlayerController", true, false)
	for node: Node in clip.root.find_children("*", "GeometryInstance3D", true, false):
		if not players.any(func(p: Node) -> bool: return p.is_ancestor_of(node)):
			(node as GeometryInstance3D).visible = false
	for node: Node in clip.root.find_children("*", "Light3D", true, false):
		if not node is DirectionalLight3D:
			(node as Light3D).visible = false
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(shade, shade, shade)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.62)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world: WorldEnvironment = LIB.find_kind(clip.root, "WorldEnvironment") as WorldEnvironment
	if world != null:
		world.environment = env
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	floor_mesh.mesh = plane
	# Shadow only: clear where lit (the grey background shows), darker under his shadow.
	var catcher := StandardMaterial3D.new()
	catcher.albedo_color = Color(0.0, 0.0, 0.0, 0.45)
	catcher.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	catcher.shadow_to_opacity = true
	floor_mesh.material_override = catcher
	clip.root.add_child(floor_mesh)
	_floor = floor_mesh
	floor_mesh.global_position = LIB.ring_point(float(option("deg", BODY_DEG)), float(option("r", BODY_R)), 0.01)
