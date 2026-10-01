extends "res://tools/capture/stages/polish_sigil.gd"

## polish_crack_run: shot 7 refilmed as shot 9 -- the 227 lava crack, bodies run up the lane
## one by one onto the real 212 crack and are thrown onto 227 and off it, as polish_sigil stages them.
## Ryan: "when they bounce on the demon pads they run up one by one and run into it; when they
## bounce on the crack they jump directly onto it and look like they're just flying."
##
## Capture: [code]--shot=s4_edge --stage=polish_crack_run --bots=3 --look=social --seconds=11.2[/code]
## (cut in 1.2 s, 10 s). Lens and bodies are polish_sigil's; only the beat moves: the first
## 227 launch lands at 7.28 s of the cut (L6's first word) after ~7 s of the crack alone.
##
## Dials (--set=): wait (driver seconds the first body holds, 6.10), gap (0.7), jitter (0.12),
## pov (the body --pov=runner rides, 0).


func cast(runners: Array[RunnerBrain]) -> bool:
	var count: int = mini(runners.size(), int(option("line", 3)))
	if count == 0:
		return false
	for index: int in count:
		if runners[index].controller == null:
			return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(clip._options.get("seed", 0)) * 31 + 9)
	var wait: float = float(option("wait", 6.10))
	var gap: float = float(option("gap", 0.7))
	var jitter: float = float(option("jitter", 0.12))
	for index: int in count:
		var hold: float = wait + gap * float(index) + (rng.randf_range(-jitter, jitter) if index > 0 else 0.0)
		drive(runners[index], steps_for(index, hold), index, "ClipCrackRunDriver%d" % index)
		_bodies.append(runners[index].controller)
	stage_body(_bodies[clampi(int(option("pov", 0)), 0, count - 1)])
	say("polish_crack_run: %d prisoners up the S4 lane" % _bodies.size())
	return true
