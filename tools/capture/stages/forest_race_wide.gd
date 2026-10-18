extends "res://tools/capture/stages/forest_race.gd"

## forest_race_wide: short 9 L4's second shot. Ryan on v6: "the running in the forest is too long, and we need to break
## it up with a second shot. dealers choice"; on v9 another runner's eyes was "the exact same footage with the fucking
## guys moved around". The same race (seed 20261017) off a reverse dolly: the lens runs the lane `lead` deg ahead of the
## leader on the bots' own line, `lens_h` m up, looking back down the lane at the whole field running at it through the trunks.
## [code]--stage=forest_race_wide --shot=s3_open_lane --map=forest --bots=3 --shimmer=0 --look=social --seed=20261017[/code]
## Dials (--set=): lead (8.0 deg ahead of the leader), lens_h (2.6 m over the deck), lens_out (0.0 m outside the line: at 0.8
## the OUT trunks at r 53.8 passed 0.4 m off the lens and its fill turned them orange), fov (66, vertical), smooth (8.0),
## aim_up (0.9 m over the pack's feet), fill (0.3: the clip's warm fill rides this lens, so it is turned down off 0.55).

var _focus: Vector3 = Vector3.ZERO
var _cam_deg: float = 0.0
var _lens_set: bool = false


func lens(delta: float) -> bool:
	if camera() == null or not _started:
		return false
	var centre: Vector3 = Vector3.ZERO
	var count: int = 0
	var bodies: Array[Vector3] = []
	for p: MatchParticipant in controller().get_participants():
		if p.body == null or not p.is_running or not LIB.on_deck(p.body):
			continue
		centre += p.body.global_position
		count += 1
		bodies.append(p.body.global_position)
	if count == 0:
		return false
	centre /= float(count)
	# The leader: the body furthest up the course from the pack's middle (the pack never spans a half ring).
	var mid_deg: float = LIB.bearing_of(centre)
	var ahead: float = -180.0
	for at: Vector3 in bodies:
		ahead = maxf(ahead, fposmod(LIB.bearing_of(at) - mid_deg + 180.0, 360.0) - 180.0)
	var want_deg: float = mid_deg + ahead + float(option("lead", 8.0))
	var k: float = 1.0 - exp(-float(option("smooth", 8.0)) * delta)
	if not _lens_set:
		_lens_set = true
		_focus = centre
		_cam_deg = want_deg
	_focus = _focus.lerp(centre, k)
	_cam_deg += (fposmod(want_deg - _cam_deg + 180.0, 360.0) - 180.0) * k
	var r: float = _line_radius(_cam_deg) + float(option("lens_out", 0.0))
	camera().global_position = LIB.ring_point(_cam_deg, r, float(option("lens_h", 2.6)))
	camera().look_at(_focus + Vector3.UP * float(option("aim_up", 0.9)), Vector3.UP)
	camera().fov = float(option("fov", 66.0))
	camera().current = true
	var fill: OmniLight3D = camera().get_node_or_null(^"ClipFill") as OmniLight3D
	if fill != null:
		fill.light_energy = float(option("fill", 0.3))
	return true


## The bots' line's radius at a bearing (LINE legs lerped), so the dolly runs the ground the racers run.
func _line_radius(deg: float) -> float:
	var d: float = fposmod(deg, 360.0)
	if d <= LINE[0].x:
		return LINE[0].y
	for index: int in range(1, LINE.size()):
		if d <= LINE[index].x:
			var a: Vector3 = LINE[index - 1]
			var b: Vector3 = LINE[index]
			return lerpf(a.y, b.y, (d - a.x) / maxf(b.x - a.x, 0.001))
	return LINE[LINE.size() - 1].y
