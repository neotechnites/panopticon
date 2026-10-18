extends "res://tools/capture/stages/stage.gd"

## pill_era: the c4943a47 pill greybox, filmed only at ref how-started-era-c4943a47 (that ref's own run_clip.gd; this
## file is its catalogue card). Guard and three pills: --pov=guard the tower player scoped, the hand (guard_hand's spring,
## ported) drops two pills (2.07, 4.63) and tracks the third; --pov=runner the spared pill's eyes, same match.
## [code]--stage=pill_era --shot=guard_scope --pov=guard|runner --fov=28 --seed=20261017[/code]
## The spared pill (r 51.0) is driven by the steps below, never his brain; his head eases onto the nearest mate.

const ERA_REF: String = "how-started-era-c4943a47"
const SPARE_STEPS: Array = [
	{"do": "hold", "seconds": 1.0},
	{"do": "lane", "weave": 0.5, "period": 1.4, "lookahead": 4.0, "gain": 4.0, "max_yaw_rate": 2.5},
]


func cast(_runners: Array[RunnerBrain]) -> bool:
	push_error("pill_era runs only at ref %s (its own run_clip.gd); an entry carries ref: %s" % [ERA_REF, ERA_REF])
	clip.quit(2)
	return false
