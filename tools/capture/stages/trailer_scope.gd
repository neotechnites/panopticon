extends "res://tools/capture/stages/scope_hunt.gd"

## trailer_scope: scope_hunt opened wide. The guard POV starts unscoped over the
## ring and the scope zooms in at [code]zoom_at[/code]; then scope_hunt's hand.
## Reveal trailer shots 1, 5, 9. Dials: scope_hunt's, plus zoom_at (1.7 s).


func tick(delta: float) -> void:
	super.tick(delta)
	if _hand == null or _guard == null:
		return
	var zoomed: bool = elapsed() >= float(option("zoom_at", 1.7))
	_hand.hold_scope = zoomed
	if not zoomed:
		var optic: WeaponOptic = _guard.get_node_or_null(^"Optic") as WeaponOptic
		if optic != null:
			optic.set_zoomed(false)
