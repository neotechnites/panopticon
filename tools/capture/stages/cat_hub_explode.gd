extends "res://tools/capture/stages/stage.gd"

## cat_hub_explode: down the player's eyes from the hub spawn, walk to a cat, shove = pick it up, pet it 4 times
## over a second, hold half a second, shove = throw it; HubCat explodes 0.5 s after the throw.
##
## Ryan (2026-10-21, task #688): "ok now get a clip in the hub, of a player who spawns in, grabs a cat, pets it like
## 4 times over the course of a second, waits half a second, then throws it, the video ends when the explosion does"
##
## [code]--shot=s3_open_lane --stage=cat_hub_explode --bots=1 --seed=20261021[/code]; cat_cozy's code with new dials.
## Probed by numbers (hub.tscn): HubSpawns/Spawn1 at (32.82, 0.25, -3.45) faces -x (yaw 96 deg); Cat6 at
## (19.70, 0.35, -3.47) is 13.1 m dead ahead on that line, so the walk is straight and the throw goes on at -x.
## Pets are the game's own E (HubCat._input with an interact action) at pickup + lead + i * span / 3, i = 0..3; the
## throw flag rises `wait` s after the 4th. Dials (--set=): spawn (Spawn1), cat (Cat6), stop (2.0), pace (1.0),
## lead (0.2), span (1.0), wait (0.45: the throw lands 0.5 s after the 4th pet), carry_down (-6: eyes 6 deg up while carrying, the throw's aim).
## Events: pickup / pet <n> / throw / explode <cat> in_frame|off_frame / boom_end, for the brief's expect: lines.

const PETS: int = 4

var _cat: RigidBody3D = null
var _state: int = 0
var _picked_at: float = -1.0
var _pets: int = 0
var _thrown: bool = false
var _boom_at: float = -1.0
var _blast: Node3D = null


func bots() -> int:
	return 1


func scene() -> String:
	return "res://hub/hub.tscn"


## HubCat parents its hearts and the blast to current_scene; a capture's SceneTree has none until it is named.
func before_start() -> void:
	if clip.current_scene == null:
		clip.current_scene = controller().get_parent()


func cast(_runners: Array[RunnerBrain]) -> bool:
	var body: PlayerController = controller().player
	_cat = LIB.find_node(clip.root, String(option("cat", "Cat6"))) as RigidBody3D
	var spawn: Node3D = LIB.find_node(clip.root, String(option("spawn", "Spawn1"))) as Node3D
	if body == null or _cat == null or spawn == null:
		return false
	var at: Vector3 = _cat.global_position
	var start: Vector3 = spawn.global_position
	var toward: Vector3 = Vector3(at.x - start.x, 0.0, at.z - start.z).normalized()
	var stop: Vector3 = at - toward * float(option("stop", 2.0))
	stop.y = start.y
	var look: Vector3 = at + Vector3.UP * 0.2
	var carry: float = float(option("carry_down", -6.0))
	var steps: Array = [
		{"do": "place", "at": start, "face": toward},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 360.0, "gain": 10.0},
		{"do": "hold", "seconds": 0.35, "look_at": look},
		{"do": "run", "to": stop, "speed": float(option("pace", 1.0)), "within": 0.25, "timeout": 6.0, "look_at": look},
		{"do": "hesitate", "seconds": 0.15, "look_at": look},
		{"do": "shove", "victim": _cat},
		{"do": "wait_flag", "flag": "throw", "timeout": 4.0, "look_down": carry},
		{"do": "shove"},
		{"do": "hold", "seconds": 3.0, "look_down": carry},
	]
	var driver: Node = DRIVER.new()
	driver.name = "ClipStageDriver0"
	clip.root.add_child(driver)
	driver.install(body, null, steps, controller())
	driver.seed_with(int(clip._options.get("seed", 0)), 0)
	drivers.append(driver)
	stage_body(body)
	say("cat %s at %v; spawn %v, stop %v (%.1f m walk)" % [_cat.name, at, start, stop, start.distance_to(stop)])
	return true


func tick(_delta: float) -> void:
	if _cat == null or not is_instance_valid(_cat):
		return
	_pet_on_time()
	_watch_the_blast()
	var now: int = int(_cat.get("_state"))
	if now == _state:
		return
	var kind: String = ["land", "pickup", "throw"][now]
	if kind == "land" and bool(_cat.get("_gone")):
		kind = "explode"
	if kind == "pickup":
		_picked_at = elapsed()
	if kind == "explode":
		_boom_at = elapsed()
		_blast = _find_blast()
		var where: Vector3 = _blast.global_position if _blast != null else _cat.global_position
		print("[event] %6.2f  explode  %s %s at %v" % [elapsed(), _cat.name, "in_frame" if _in_frame(where) else "off_frame", where])
	else:
		print("[event] %6.2f  %s  %s at %v" % [elapsed(), kind, _cat.name, _cat.global_position])
	_state = now


## E on the carried cat at pickup + lead + i * span / 3; the throw flag `wait` s after the last.
func _pet_on_time() -> void:
	if _picked_at < 0.0 or _thrown:
		return
	var lead: float = float(option("lead", 0.2))
	var span: float = float(option("span", 1.0))
	var since: float = elapsed() - _picked_at
	if _pets < PETS and since >= lead + span * float(_pets) / float(PETS - 1):
		var press: InputEventAction = InputEventAction.new()
		press.action = &"interact"
		press.pressed = true
		_cat.call("_input", press)
		_pets += 1
		var hearts: int = _hearts_in_frame()
		print("[event] %6.2f  pet  %s n%d hearts_in_frame%d" % [elapsed(), _cat.name, _pets, hearts])
	if _pets >= PETS and since >= lead + span + float(option("wait", 0.45)):
		_thrown = true
		flag_all("throw")


func _watch_the_blast() -> void:
	if _boom_at < 0.0:
		return
	if _blast == null or not is_instance_valid(_blast) or not _blast.is_inside_tree():
		print("[event] %6.2f  boom_end  %s (%.2f s after the explosion)" % [elapsed(), _cat.name, elapsed() - _boom_at])
		_boom_at = -1.0


func _find_blast() -> Node3D:
	for child: Node in clip.current_scene.get_children():
		if child is AnimatedSprite3D:
			return child as Node3D
	return null


func _hearts_in_frame() -> int:
	var seen: int = 0
	for child: Node in clip.current_scene.get_children():
		if child is Sprite3D and not (child is AnimatedSprite3D) and _in_frame((child as Node3D).global_position):
			seen += 1
	return seen


## True when [param point] is inside the take's frame (--frame aspect) through the current camera.
func _in_frame(point: Vector3) -> bool:
	var cam: Camera3D = clip.root.get_viewport().get_camera_3d()
	if cam == null:
		return false
	var local: Vector3 = cam.global_transform.affine_inverse() * point
	if local.z >= -0.05:
		return false
	var asked: PackedStringArray = String(clip._options.get("frame", "")).split("x")
	var aspect: float = 9.0 / 16.0
	if asked.size() == 2 and asked[1].to_float() > 0.0:
		aspect = asked[0].to_float() / asked[1].to_float()
	var half: float = tan(deg_to_rad(cam.fov) * 0.5)
	var half_v: float = half if cam.keep_aspect == Camera3D.KEEP_HEIGHT else half / aspect
	var half_h: float = half_v * aspect
	return absf(local.x / -local.z) <= half_h and absf(local.y / -local.z) <= half_v
