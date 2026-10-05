extends "res://tools/capture/stages/stage.gd"

## alive: proof clips of the procedural body layers on the flat S3 lane. --shot=s3_face_side --stage=alive --set=beat=NAME (;layers=off for the clip alone).
## Beats: sprint, look, drop, shove, miss (three rounds past a standing runner), slope (ramp, platform, steps), guard (add --pov=guard), pack (--bots=7).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")
## The flat S3 lane; the miss beat plays at 276 deg, where the tower sees the deck.
const DEG: float = 160.0
const MISS_DEG: float = 276.0
const RADIUS: float = 52.0
const SPARE_DEG: float = 8.0
const LENS_EASE: float = 0.06
## The ramp prop: rise and run of the slope, the platform, then steps down.
const RAMP_RISE: float = 1.5
const RAMP_RUN: float = 3.7
const PLATFORM: float = 2.0
const STEP_RISE: float = 0.1
const STEP_RUN: float = 0.3
const PROP_WIDTH: float = 2.4

var _beat: String = "sprint"
var _deg: float = DEG
var _body: PlayerController = null
var _other: PlayerController = null
var _centre: Vector3 = Vector3.ZERO
var _along: Vector3 = Vector3.ZERO
var _out: Vector3 = Vector3.ZERO
var _focus: Vector3 = Vector3.ZERO
var _lens_set: bool = false
var _guard: PlayerController = null
var _hand: Node = null
var _shots_fired: int = 0
## --set=layers=off films the clip alone, for a before and after.
var _layers_on: bool = true


func bots() -> int:
	return 2


func tune_rules(rules: MatchRules) -> void:
	rules.base_reload_seconds = 1.0


func before_start() -> void:
	_beat = String(option("beat", "sprint"))
	_deg = float(option("deg", MISS_DEG if _beat == "miss" else DEG))
	_centre = LIB.ring_point(_deg, RADIUS, 0.1)
	_along = LIB.tangent_at(_deg)
	_out = LIB.radial_at(_deg)
	LIB.disarm_pads(clip.root)
	LIB.disarm_traps(clip.root)
	# No fill light on the deck: lift the grade so a body reads.
	var world: WorldEnvironment = LIB.find_node(clip.root, "WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		var env: Environment = world.environment.duplicate() as Environment
		env.tonemap_exposure = 3.8
		env.ambient_light_energy = 3.6
		world.environment = env
	if _beat == "slope":
		_build_ramp()
	_layers_on = String(option("layers", "on")) != "off"


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2 or runners[0].controller == null or runners[1].controller == null:
		return false
	_body = runners[0].controller
	_other = runners[1].controller
	var spare: Array = [{"do": "place", "at": LIB.ring_point(SPARE_DEG, 50.0, 0.1)}, {"do": "hold", "seconds": 90.0}]
	var steps: Array = []
	var c: Vector3 = _centre
	match _beat:
		"sprint":
			steps = [
				{"do": "place", "at": c - _along * 8.0, "face": _along}, {"do": "hold", "seconds": 1.2},
				{"do": "run", "to": c + _along * 6.0, "within": 0.5}, {"do": "hold", "seconds": 1.0},
				{"do": "turn", "degrees": 180.0, "seconds": 0.3}, {"do": "hold", "seconds": 0.5},
				{"do": "run", "to": c - _along * 6.0, "within": 0.5}, {"do": "hold", "seconds": 0.7},
				{"do": "turn", "degrees": -180.0, "seconds": 0.25},
				{"do": "run", "to": c + _along * 7.0, "weave": 1.0, "period": 0.9, "within": 0.6}, {"do": "hold", "seconds": 60.0},
			]
		"look":
			steps = [
				{"do": "place", "at": c, "face": -_out}, {"do": "hold", "seconds": 1.4},
				{"do": "glance", "right": 45.0, "seconds": 0.3}, {"do": "hold", "seconds": 0.8},
				{"do": "glance", "right": -105.0, "pitch": 18.0, "seconds": 0.45}, {"do": "hold", "seconds": 0.9},
				{"do": "glance", "right": 60.0, "pitch": -60.0, "seconds": 0.4}, {"do": "hold", "seconds": 0.9},
				{"do": "glance", "pitch": 95.0, "seconds": 0.45}, {"do": "hold", "seconds": 0.8},
				{"do": "glance", "right": 170.0, "pitch": -50.0, "seconds": 0.45}, {"do": "hold", "seconds": 1.0},
				{"do": "glance", "right": -170.0, "seconds": 0.5}, {"do": "hold", "seconds": 60.0},
			]
		"drop":
			steps = [
				{"do": "place", "at": c - _along * 2.0 + Vector3.UP * 3.5, "face": _along}, {"do": "hold", "seconds": 2.0},
				{"do": "leap", "to": c + _along * 3.0, "speed": 7.0}, {"do": "land"}, {"do": "hold", "seconds": 1.2},
				{"do": "place", "at": c + Vector3.UP * 6.0, "face": -_out}, {"do": "hold", "seconds": 60.0},
			]
		"shove":
			steps = [
				{"do": "place", "at": c, "face": _along}, {"do": "hold", "seconds": 0.5},
				{"do": "wait_launch", "timeout": 6.0}, {"do": "land"}, {"do": "hold", "seconds": 0.8},
				{"do": "chase", "victim": _other, "range": 2.4, "timeout": 6.0}, {"do": "hold", "seconds": 60.0},
			]
			spare = [
				{"do": "place", "at": c - _along * 2.2, "face": _along}, {"do": "hold", "seconds": 2.0},
				{"do": "shove", "face": _along}, {"do": "face_hold", "victim": _body, "seconds": 8.0},
				{"do": "land"}, {"do": "hold", "seconds": 60.0},
			]
		"miss":
			steps = [{"do": "place", "at": c, "face": -_out}, {"do": "hold", "seconds": 90.0}]
		"slope":
			var foot: Vector3 = c - _along * 6.0
			var top: Vector3 = c - _along * 6.0 + _along * (1.5 + RAMP_RUN + PLATFORM * 0.5)
			var far: Vector3 = top + _along * (PLATFORM * 0.5 + STEP_RUN * RAMP_RISE / STEP_RISE + 2.0)
			steps = [
				{"do": "place", "at": foot, "face": _along}, {"do": "hold", "seconds": 1.0},
				{"do": "run", "to": top - _along * (PLATFORM * 0.5 + RAMP_RUN * 0.5), "speed": 0.3, "within": 0.25},
				{"do": "turn", "degrees": 90.0, "seconds": 0.4}, {"do": "hold", "seconds": 1.6},
				{"do": "turn", "degrees": -90.0, "seconds": 0.4},
				{"do": "run", "to": top, "speed": 0.3, "within": 0.3}, {"do": "hold", "seconds": 0.8},
				{"do": "run", "to": far, "speed": 0.3, "within": 0.4, "timeout": 14.0}, {"do": "hold", "seconds": 0.6},
				{"do": "turn", "degrees": 180.0, "seconds": 0.35},
				{"do": "run", "to": foot, "speed": 1.0, "within": 0.6}, {"do": "hold", "seconds": 60.0},
			]
		_:
			steps = [{"do": "place", "at": c, "face": -_out}, {"do": "hold", "seconds": 90.0}]
	if _beat == "pack":
		# Everyone sprinting lanes side by side and turning at the ends, for the view from the tower.
		for index: int in runners.size():
			var lane: Vector3 = c + _out * (float(index) - 0.5 * float(runners.size() - 1)) * 1.3
			var laps: Array = [{"do": "place", "at": lane - _along * 8.0, "face": _along}, {"do": "hold", "seconds": 1.0 + 0.15 * float(index)}]
			for _lap: int in 8:
				laps.append({"do": "run", "to": lane + _along * 8.0, "within": 0.6})
				laps.append({"do": "turn", "degrees": 180.0, "seconds": 0.3})
				laps.append({"do": "run", "to": lane - _along * 8.0, "within": 0.6})
				laps.append({"do": "turn", "degrees": -180.0, "seconds": 0.3})
			drive(runners[index], laps, index)
		stage_body(_body)
		return true
	drive(runners[0], steps, 0)
	drive(runners[1], spare, 1)
	for index: int in range(2, runners.size()):
		drive(runners[index], [{"do": "place", "at": LIB.ring_point(SPARE_DEG + 3.0 * float(index), 50.0, 0.1)}, {"do": "hold", "seconds": 90.0}], index)
	if not _layers_on:
		for layer: Node in clip.root.find_children("*", "SkeletonModifier3D", true, false):
			if &"enabled" in layer and layer.has_method(&"bind_body"):
				layer.set(&"enabled", false)
	stage_body(_body)
	say("alive: beat %s at %.0f deg r %.0f" % [_beat, _deg, RADIUS])
	return true


func tick(_delta: float) -> void:
	if _beat != "miss" and _beat != "guard":
		return
	if _guard == null:
		var shooter: TowerShooter = LIB.stand_down(seat())
		if shooter == null or shooter.controller == null:
			return
		_guard = shooter.controller
	if _beat == "guard":
		_sweep()
	elif _body != null:
		_near_misses()


## Three rounds past the standing runner: beside the chest, the other side, over the head.
func _near_misses() -> void:
	var marks: Array[Vector3] = [_along * 0.7 + Vector3.UP * 1.2, _along * 0.45 + Vector3.UP * 1.6, _along * 0.15 + Vector3.UP * 2.15]
	if _shots_fired >= marks.size() or elapsed() < 2.5 + 1.8 * float(_shots_fired):
		return
	var rifle: Rifle = controller().rifle
	if rifle == null or not rifle.can_fire():
		return
	var eye: Node3D = _guard.get_node_or_null(^"Head/Camera") as Node3D
	var d: Vector3 = _body.global_position + marks[_shots_fired] - eye.global_position
	_guard.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	_guard.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
	_guard.set(&"_pitch", _guard.head.rotation.x)
	say("round %d %s" % [_shots_fired, "fired" if rifle.try_fire() else "refused"])
	_shots_fired += 1


## The guard's head as a hand, swept round the ring, down to the foot of the tower and up past the horizon.
func _sweep() -> void:
	if _hand != null:
		return
	_hand = GUARD_HAND.new()
	_hand.name = "ClipGuardHand"
	clip.root.add_child(_hand)
	_hand.install(_guard, controller(), elapsed())
	_hand.hold_scope = false
	_hand.park = LIB.ring_point(_deg, RADIUS, 1.0)
	_hand.start_at = 1.5
	_hand.beats = [
		{"at": LIB.ring_point(_deg + 55.0, RADIUS, 1.0), "seconds": 1.4},
		{"at": LIB.ring_point(_deg - 40.0, RADIUS, 1.0), "seconds": 1.6},
		{"at": LIB.ring_point(_deg, 7.0, 0.0), "seconds": 1.5},
		{"at": LIB.ring_point(_deg + 20.0, 30.0, 45.0), "seconds": 1.6},
		{"at": LIB.ring_point(_deg - 20.0, 12.0, 0.0), "seconds": 1.4},
		{"at": LIB.ring_point(_deg, RADIUS, 1.0), "seconds": 3.0},
	]


func lens(delta: float) -> bool:
	if camera() == null:
		return false
	var offset: Vector3 = -_out * 4.2 + Vector3.UP * 1.3
	var height: float = 1.0
	var fov: float = 50.0
	var target: Node3D = _body
	match _beat:
		"look":
			offset = -_out * 2.6 + _along * 0.8 + Vector3.UP * 1.45
			height = 1.15
		"miss":
			offset = -_out * 2.4 - _along * 2.0 + Vector3.UP * 1.3
			height = 1.0
		"drop":
			offset = -_out * 4.2 + _along * 1.0 + Vector3.UP * 1.3
			fov = 55.0
		"shove":
			offset = -_out * 4.3 + _along * 3.0 + Vector3.UP * 1.4
			fov = 60.0
		"slope":
			offset = -_out * 4.0 + Vector3.UP * 0.9
			height = 0.7
			fov = 45.0
		"pack":
			camera().global_position = _centre - _out * 4.6 + Vector3.UP * 11.0
			camera().look_at(_centre + _out * 1.5, Vector3.UP)
			camera().fov = 62.0
			camera().current = true
			return true
		"guard":
			target = _guard
			offset = (_out * 2.6 + _along * 1.3) + Vector3.UP * 1.7
			height = 1.3
	if target == null or not is_instance_valid(target):
		return false
	var at: Vector3 = target.global_position + Vector3.UP * height
	if _beat == "drop":
		at.y = _centre.y + 1.3
	if not _lens_set:
		_lens_set = true
		_focus = at
	_focus = _focus.lerp(at, 1.0 - exp(-delta / LENS_EASE))
	camera().global_position = _focus + offset - Vector3.UP * height
	camera().look_at(_focus, Vector3.UP)
	camera().fov = fov
	camera().current = true
	return true


## A ramp up, a platform and steps down, along the ring from 6 m short of the centre: test ground for the feet.
func _build_ramp() -> void:
	var prop: StaticBody3D = StaticBody3D.new()
	prop.name = "ClipRamp"
	clip.root.add_child(prop)
	var start: Vector3 = _centre - _along * 4.5 - Vector3.UP * 0.1
	prop.global_transform = Transform3D(Basis(_along, Vector3.UP, _along.cross(Vector3.UP)), start)
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.albedo_color = Color(0.2, 0.18, 0.16)
	var slope: float = atan2(RAMP_RISE, RAMP_RUN)
	var length: float = Vector2(RAMP_RISE, RAMP_RUN).length()
	_add_box(prop, paint, Vector3(length, 0.3, PROP_WIDTH),
		Transform3D(Basis(Vector3.BACK, slope), Vector3(RAMP_RUN * 0.5, RAMP_RISE * 0.5, 0.0) - Basis(Vector3.BACK, slope) * Vector3(0.0, 0.15, 0.0)))
	_add_box(prop, paint, Vector3(PLATFORM, RAMP_RISE, PROP_WIDTH), Transform3D(Basis.IDENTITY, Vector3(RAMP_RUN + PLATFORM * 0.5, RAMP_RISE * 0.5, 0.0)))
	var count: int = int(round(RAMP_RISE / STEP_RISE))
	for i: int in count - 1:
		var tall: float = RAMP_RISE - STEP_RISE * float(i + 1)
		_add_box(prop, paint, Vector3(STEP_RUN, tall, PROP_WIDTH),
			Transform3D(Basis.IDENTITY, Vector3(RAMP_RUN + PLATFORM + STEP_RUN * (float(i) + 0.5), tall * 0.5, 0.0)))


func _add_box(prop: StaticBody3D, paint: Material, size: Vector3, at: Transform3D) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = at
	prop.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var form: BoxMesh = BoxMesh.new()
	form.size = size
	mesh.mesh = form
	mesh.material_override = paint
	mesh.transform = at
	prop.add_child(mesh)
