extends "res://tools/capture/stages/scope_hunt.gd"

## forest_hunt: scope_hunt on the green forest at the map's own lighting (--set=lift=0). For ragdoll_vnext's L5 montage.


func tune_rules(rules: MatchRules) -> void:
	super.tune_rules(rules)
	rules.map_id = &"forest"
