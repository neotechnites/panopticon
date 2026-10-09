extends MultiMeshInstance3D
## The bay's fish: schools and singles swimming loose loops (beach_fish_paths.gd) under the surface, one
## MultiMesh, one draw call. They turn now and then and scatter from a runner wading close. No collision.

const Paths := preload("res://maps/beach/fish/beach_fish_paths.gd")
const SEA_Y := 22.6                 # beach_sea.gdshaderinc SEA_Y
const RUNNER_GROUP := &"prisoners"
const SCARE_RADIUS := 5.0           # metres from a wading runner that a school swims off
const SCARE_PUSH := 3.0             # how far it swims off
const TOP_CLEAR := 0.15             # a fish never breaks the surface

var _schools: Array[Dictionary] = []
var _runners: Array[Node] = []
var _runner_poll := 0.0
var _time := 0.0
var _buffer := PackedFloat32Array()     # every fish's 3x4 transform and custom data, sent once a frame


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 52817
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	mm.mesh = quad
	var total := 0
	for row: Array in Paths.SCHOOLS:
		total += int(row[1])
	mm.instance_count = total
	multimesh = mm
	_buffer.resize(total * 16)
	var first := 0
	for row: Array in Paths.SCHOOLS:
		var flat: Array = row[3]
		var pts := PackedVector3Array()
		for i in range(0, flat.size(), 3):
			pts.append(Vector3(flat[i], flat[i + 1], flat[i + 2]))
		var lengths := PackedFloat32Array([0.0])
		for i in pts.size():
			lengths.append(lengths[i] + pts[i].distance_to(pts[(i + 1) % pts.size()]))
		var n: int = row[1]
		var fish: Array[Dictionary] = []
		for k in n:
			fish.append({
				"offset": Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.15, 0.15), -1.0 * k) if n > 1 else Vector3.ZERO,
				"phase": rng.randf() * TAU,
				"heading": Vector3.RIGHT,
				"pos": Vector3.INF,
			})
		_schools.append({
			"species": float(row[0]), "length": float(row[2]), "points": pts, "lengths": lengths,
			"s": rng.randf() * lengths[lengths.size() - 1], "dir": 1.0 if rng.randf() < 0.5 else -1.0,
			"speed": rng.randf_range(0.7, 1.4), "turn_in": rng.randf_range(12.0, 40.0),
			"flee": Vector3.ZERO, "first": first, "fish": fish, "phase": rng.randf() * TAU,
		})
		first += n


func _process(delta: float) -> void:
	_time += delta
	_runner_poll -= delta
	if _runner_poll <= 0.0:
		_runner_poll = 0.5
		_runners = get_tree().get_nodes_in_group(RUNNER_GROUP)
	for school in _schools:
		_swim(school, delta)
	multimesh.buffer = _buffer


func _swim(school: Dictionary, delta: float) -> void:
	var total: float = school.lengths[school.lengths.size() - 1]
	school.turn_in -= delta
	if school.turn_in <= 0.0:
		school.dir = -school.dir
		school.turn_in = randf_range(15.0, 45.0)
	var centre := _at(school, school.s)
	var push := Vector3.ZERO
	for r in _runners:
		var body := r as Node3D
		if body == null or body.global_position.y > SEA_Y + 1.2:
			continue                                   # only a runner in the water
		var away := centre - body.global_position
		away.y = 0.0
		var d := away.length()
		if d < SCARE_RADIUS and d > 0.01:
			push += away / d * (1.0 - d / SCARE_RADIUS) * SCARE_PUSH
	var scared := push.length_squared() > 0.01
	school.flee = school.flee.lerp(push.limit_length(SCARE_PUSH), clampf(delta * (3.0 if scared else 0.4), 0.0, 1.0))
	var speed: float = school.speed * (1.0 + 0.3 * sin(_time * 0.37 + school.phase)) * (2.2 if scared else 1.0)
	school.s = fposmod(school.s + speed * school.dir * delta, total)
	var ahead := _at(school, fposmod(school.s + 0.5 * school.dir, total))
	var along := (ahead - _at(school, school.s)).normalized()
	var across := along.cross(Vector3.UP).normalized()
	var fish: Array = school.fish
	for k in fish.size():
		var f: Dictionary = fish[k]
		var o: Vector3 = f.offset
		var ph: float = f.phase
		var p := _at(school, fposmod(school.s + o.z * school.dir, total)) + across * (o.x + 0.15 * sin(_time * 1.3 + ph))
		p.y += o.y + 0.05 * sin(_time * 0.9 + ph)
		p += school.flee
		p.y = minf(p.y, SEA_Y - TOP_CLEAR)
		var prev: Vector3 = f.pos
		var h: Vector3 = f.heading
		if prev != Vector3.INF and prev.distance_squared_to(p) > 1e-6:
			h = h.slerp((p - prev).normalized(), clampf(delta * 5.0, 0.0, 1.0)).normalized()
		f.heading = h
		f.pos = p
		var side := h.cross(Vector3.UP)
		if side.length_squared() < 1e-4:
			side = Vector3.FORWARD
		side = side.normalized()
		var up := side.cross(h)
		var b: int = (school.first + k) * 16
		_buffer[b] = h.x; _buffer[b + 1] = up.x; _buffer[b + 2] = side.x; _buffer[b + 3] = p.x
		_buffer[b + 4] = h.y; _buffer[b + 5] = up.y; _buffer[b + 6] = side.y; _buffer[b + 7] = p.y
		_buffer[b + 8] = h.z; _buffer[b + 9] = up.z; _buffer[b + 10] = side.z; _buffer[b + 11] = p.z
		_buffer[b + 12] = school.species; _buffer[b + 13] = ph / TAU; _buffer[b + 14] = school.length; _buffer[b + 15] = 0.0


func _at(school: Dictionary, s: float) -> Vector3:
	var pts: PackedVector3Array = school.points
	var lengths: PackedFloat32Array = school.lengths
	var i := lengths.bsearch(s, true) - 1
	i = clampi(i, 0, pts.size() - 1)
	var span := lengths[i + 1] - lengths[i]
	var t := (s - lengths[i]) / span if span > 0.0 else 0.0
	return pts[i].lerp(pts[(i + 1) % pts.size()], t)
