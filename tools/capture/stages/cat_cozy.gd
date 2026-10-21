extends "res://tools/capture/stages/stage.gd"

## cat_cozy: down the player's eyes in the hub, walk up to a cat, shove = pick it up, look at it, shove = huck it.
##
## Ryan (2026-10-20, task #687): "run the short pipeline on the pickup ad throw the cat short, the "can i be
## considered a cozy game now" is just a caption on the screen." Idea #41: "at the end he chucks the cat and it cuts".
##
## [code]--shot=s3_open_lane --stage=cat_cozy --bots=1 --seed=20261020[/code] (the shot path is unused: the eye is the body's).
## Probed headless (hub.tscn, 2026-10-20): Cat1 at (-26.96, 0, 13.15), bearing 154 r 30.0, floor 0.00 flat for 8 m
## every way; at 1.2 m up clear 20.0 m toward 150 deg (the walk in) and 28.8-30 m toward 300-30 deg (the throw, at
## the tower). The W05 ice dais (162 deg r 36) is 5.1 m off the start, behind the eye; HubLobby is off for the take.
## The body starts `back` m out from the cat on the line from the tower, faces it, walks to `stop` m (shove reach
## 3.0 m, facing cone 60 deg), shoves (HubCat lifts it to the face), holds `hold` s shuffling, eases `look_around` deg
## (left) over it, turns `turn` deg right while lifting the eyes to `lift` deg up, and shoves again (HubCat: 20 m/s along the look + 4 up).
##
## In hell (v2, Ryan 22:45: "can you do it in the hell map now instead of the hub?"): --set=at=45:50 with --pov=runner
## spawns hub/props/cat/cat.tscn there on the deck (probe_ring: 0-71 deg pad- and trap-free; floor +-0.08 m at 40-50 deg
## r 47-55; boulders at 25 deg r 53 and 35 deg r 51 stay clear), the runner walks in from r 56 and hucks it over the pit.
## Dials (--set=): at (deg:r, "" = the hub), cat (Cat1), back (7.0), stop (1.2), pace (0.4), hold (0.5), look_around (-12), turn (30), lift (6).
## Take 1 (hold 1.7 s, still) froze the gate for 1.0 s: the held look keeps moving.
## Events: [event] pickup / throw / land <cat>, for the brief's expect: lines.

const CAT_SCENE := preload("res://hub/props/cat/cat.tscn")
## Hub Cat1's yaw off its outward line, so a spawned cat stands to the eye as Cat1 did.
const CAT_YAW_OFF_OUT: float = 202.9

var _cat: RigidBody3D = null
var _state: int = 0


func _in_hell() -> bool:
	return String(option("at", "")) != ""


func bots() -> int:
	return 1


func needs_pov() -> String:
	return "runner" if _in_hell() else ""


func scene() -> String:
	return "" if _in_hell() else "res://hub/hub.tscn"


func before_start() -> void:
	if not _in_hell():
		return
	var spot: PackedStringArray = String(option("at", "")).split(":")
	var at: Vector3 = LIB.ring_point(float(spot[0]), float(spot[1]))
	var out: Vector3 = Vector3(at.x, 0.0, at.z).normalized()
	_cat = CAT_SCENE.instantiate() as RigidBody3D
	_cat.name = "Cat1"
	controller().get_parent().add_child(_cat)
	_cat.global_transform = Transform3D(Basis(Vector3.UP, atan2(out.x, out.z) + deg_to_rad(CAT_YAW_OFF_OUT)), at)
	say("cat spawned at %v" % at)


func cast(runners: Array[RunnerBrain]) -> bool:
	if _in_hell() and (runners.is_empty() or runners[0].controller == null):
		return false
	var body: PlayerController = runners[0].controller if _in_hell() else controller().player
	if not _in_hell():
		_cat = LIB.find_node(clip.root, String(option("cat", "Cat1"))) as RigidBody3D
	if body == null or _cat == null:
		return false
	var at: Vector3 = _cat.global_position
	var out: Vector3 = Vector3(at.x, 0.0, at.z).normalized()
	var start: Vector3 = at + out * float(option("back", 7.0))
	var stop: Vector3 = at + out * float(option("stop", 1.2))
	var look: Vector3 = at + Vector3.UP * 0.2
	var lift: float = -float(option("lift", 6.0))
	var steps: Array = [
		{"do": "place", "at": start, "face": -out},
		{"do": "human", "on": true},
		{"do": "steer", "on": true, "rate": 360.0, "gain": 10.0},
		{"do": "hold", "seconds": 0.5, "look_at": look},
		{"do": "run", "to": stop, "speed": float(option("pace", 0.4)), "within": 0.25, "timeout": 6.0, "look_at": look},
		{"do": "hesitate", "seconds": 0.25, "look_at": look},
		{"do": "shove"},
		{"do": "hold", "seconds": float(option("hold", 0.5)), "look_down": 14.0, "fidget": true},
		{"do": "glance", "right": float(option("look_around", -12.0)), "seconds": 0.7, "smooth": true, "look_down": 8.0},
		{"do": "glance", "right": float(option("turn", 30.0)), "seconds": 0.55, "smooth": true, "look_down": lift},
		{"do": "hold", "seconds": 0.2, "look_down": lift},
		{"do": "shove"},
		{"do": "hold", "seconds": 3.0, "look_down": lift},
	]
	if _in_hell():
		drive(runners[0], steps)
	else:
		var driver: Node = DRIVER.new()
		driver.name = "ClipStageDriver0"
		clip.root.add_child(driver)
		driver.install(body, null, steps, controller())
		driver.seed_with(int(clip._options.get("seed", 0)), 0)
		drivers.append(driver)
	stage_body(body)
	say("cat %s at %v; start %v, stop %v" % [_cat.name, at, start, stop])
	return true


func tick(_delta: float) -> void:
	if _cat == null or not is_instance_valid(_cat):
		return
	var now: int = int(_cat.get("_state"))
	if now == _state:
		return
	var kind: String = ["land", "pickup", "throw"][now]
	print("[event] %6.2f  %s  %s at %v" % [elapsed(), kind, _cat.name, _cat.global_position])
	_state = now
