extends "res://tools/capture/stages/guard_alone.gd"

## rs_snipe: guard_alone with a plan of beats, for the ragdoll short. --set=plan=0m,1m,0m,2h (runner index, m = miss, h = hit);
## old=1 switches the death ragdoll off on every runner, so a kill plays the pre-ragdoll "Death" clip.

var _plan: PackedStringArray = []


func before_start() -> void:
	super.before_start()
	_plan = String(option("plan", "")).split(",", false)


func cast(runners: Array[RunnerBrain]) -> bool:
	if not super.cast(runners):
		return false
	if int(option("old", 0)) == 1:
		for brain: RunnerBrain in runners:
			for avatar: Node in brain.controller.find_children("*", "PrisonerAvatar", true, false):
				avatar.set(&"_ragdoll", null)
		say("rs_snipe: ragdoll off, the old death clip")
	return true


func tick(delta: float) -> void:
	var fresh: bool = _hand == null
	super.tick(delta)
	if not fresh or _hand == null or _plan.is_empty():
		return
	var beat: float = float(option("beat", 1.7))
	var fire_at: float = float(option("fire_at", 1.25))
	var miss_by: float = float(option("miss_by", 1.3))
	_hand.beats.clear()
	for step: String in _plan:
		var index: int = int(step.substr(0, step.length() - 1))
		var entry: Dictionary = {"body": _bodies[index], "seconds": beat, "fire_at": fire_at, "watch": true}
		if step.ends_with("m"):
			entry["miss_by"] = miss_by
		_hand.beats.append(entry)
	say("rs_snipe: plan %s" % ",".join(_plan))
