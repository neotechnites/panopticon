extends RefCounted

## A run as legs along the ring, each with its own radius, pace and glances, the way a player picks a line:
## lane steps whose joins carry the head (stage_driver "carry"), so a change of line is never a one-tick snap.


## [param legs]: [{"to": deg, "r": m, "speed": 0..1, "weave", "period", "glances", "strafes", "flinch_on", ...}] in order.
static func steps(legs: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in legs:
		var leg: Dictionary = entry.duplicate()
		leg["do"] = "lane"
		leg["carry"] = true
		if not leg.has("glances"):
			leg["glances"] = [{"t": 0.0, "right": 0.0, "pitch": -1.0}]
		if not leg.has("timeout"):
			leg["timeout"] = 30.0
		out.append(leg)
	return out
