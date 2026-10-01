extends "res://tools/capture/stages/pack_sniped.gd"

## trailer_victim: pack_sniped down the eyes of the runner a step behind the one
## who is dropped; after the hit the POV pulls up and looks at the tower.
## Reveal trailer shot 2. Dials: pack_sniped's, plus up_right (78), up_pitch (13).

var _looked: bool = false


func on_hit(_collider: Node3D) -> void:
	if _looked:
		return
	var pov_index: int = int(option("pov_index", 3))
	if pov_index >= drivers.size() or not is_instance_valid(drivers[pov_index]):
		return
	_looked = true
	# The tower is inward, which is to the right on this lane.
	drivers[pov_index].retarget([
		{"do": "hold", "seconds": 0.3},
		{"do": "glance", "right": float(option("up_right", 78.0)), "pitch": float(option("up_pitch", 13.0)), "seconds": 0.6},
		{"do": "hold", "seconds": 60.0},
	])
	say("hit: the POV looks up at the tower")
