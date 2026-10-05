extends "res://tools/capture/stages/trailer_finish.gd"

## trailer_finish on --map=marble: a runner POV sprints the corridor (+bearing) from 320 deg into
## the portal at 345, is armed in the tower and shoots the guard. Dials: from (320,52.4), pace (1.0).

## The collider dais under the guard's seat (marble_tower_build.py DAIS_H, DAIS_R): world top, height, reach.
const DAIS_TOP_Y: float = 27.65
const DAIS_HEIGHT: float = 0.6
const DAIS_RADIUS: float = 2.3
const TOWER_COLLIDER: StringName = &"MarbleTowerCollision"


func cast(runners: Array[RunnerBrain]) -> bool:
	if runners.size() < 2 or runners[0].controller == null or runners[1].controller == null:
		return false
	var from: Vector3 = LIB.polar(String(option("from", "320,52.4")), LIB.ring_point(320.0, 52.4))
	var pace: float = float(option("pace", 1.0))
	_runner = runners[0].controller
	# Six steps so the lane into the portal is index 5, the step trailer_finish's tick arms on.
	_driver = drive(runners[0], [
		{"do": "place", "at": from + Vector3.UP * 0.1, "face": LIB.tangent_at(LIB.bearing_of(from))},
		{"do": "human", "on": true},
		{"do": "hold", "seconds": 0.2},
		{"do": "lane", "to": LIB.bearing_of(from) + 2.0, "r": 52.3, "speed": pace, "timeout": 2.0},
		{"do": "lane", "to": LIB.bearing_of(from) + 5.0, "r": 52.1, "speed": pace, "weave": 0.05, "period": 1.2, "timeout": 2.0},
		{"do": "lane", "to": PORTAL_DEG + 3.0, "r": PORTAL_R, "speed": pace, "timeout": 8.0,
			"glances": [{"t": 0.0, "right": 0.0, "pitch": -1.0}, {"t": 0.45, "right": 18.0, "pitch": 5.0}, {"t": 0.85, "right": 2.0, "pitch": 0.0}]},
		{"do": "hold", "seconds": 60.0},
	], 0, "ClipFinishDriver")
	drive(runners[1], [
		{"do": "place", "at": LIB.ring_point(250.0, 52.0, 0.1), "face": LIB.tangent_at(250.0)},
		{"do": "hold", "seconds": 60.0},
	], 1, "ClipParkedDriver")
	LIB.hide_from_the_rifle(runners[1].controller)
	stage_body(_runner)
	say("trailer_finish_marble: %s runs from %.1f deg into the portal" % [_runner.name, LIB.bearing_of(from)])
	return true


## Flat floor for this shot only (map unchanged): the tower's collider still carries a 0.6 m dais the drawn floor
## does not, and the guard stood on it in mid-air. Its top comes down onto the room floor.
func before_start() -> void:
	super.before_start()
	var lowered: int = 0
	# Both tower slots (Rock, RockArches) carry the collider; found by its own name, not the HUD's "Tower" label.
	for node: Node in clip.root.find_children("CollisionShape3D", "CollisionShape3D", true, false):
		if node.get_parent().name != TOWER_COLLIDER:
			continue
		var holder: CollisionShape3D = node as CollisionShape3D
		var shape: ConcavePolygonShape3D = holder.shape as ConcavePolygonShape3D
		if shape == null:
			continue
		var at: Transform3D = holder.global_transform
		var down: Vector3 = at.basis.inverse() * (Vector3.DOWN * DAIS_HEIGHT)
		var faces: PackedVector3Array = shape.get_faces()
		var flat: PackedVector3Array = PackedVector3Array()
		for corner: int in range(0, faces.size() - 2, 3):
			var triangle: Array[Vector3] = [faces[corner], faces[corner + 1], faces[corner + 2]]
			for index: int in 3:
				var world: Vector3 = at * triangle[index]
				if absf(world.y - DAIS_TOP_Y) < 0.05 and Vector2(world.x, world.z).length() <= DAIS_RADIUS:
					triangle[index] += down
					lowered += 1
			# The dais's side band is now flat on itself: dropped, not left as slivers.
			if (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).length() > 0.0001:
				flat.append_array(PackedVector3Array(triangle))
		shape.set_faces(flat)
	say("trailer_finish_marble: the collider's dais lowered onto the room floor (%d corners)" % lowered)
