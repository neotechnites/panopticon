extends SceneTree

## Frame-cost profiler: runs a bots-only match in a window and logs Godot's
## performance monitors once a second.
##
##   godot --path . --script res://tools/perf/profile_match.gd -- \
##       --seconds=60 --runners=3 --view=runner --out=user://perf_run.csv
##
## Options: --seconds --runners --view=runner|tower|orbit --width --height
##          --warmup --out --label --vsync
##
## Writes a CSV of per-second samples plus a SUMMARY line with the mean and the
## worst 1% of frame times. Not headless: the point is the GPU.

const RULES_PATH: String = "res://resources/rules/default_match_rules.tres"
const SHOOTER_PROFILE_PATH: String = "res://scenes/bot/default_shooter_profile.tres"

var _options: Dictionary = {}
var _world: BotMatchWorld = null
var _seat: BotTowerSeat = null
var _camera: Camera3D = null
var _root: Node = null

var _started: bool = false
var _warmup_left: float = 0.0
var _elapsed: float = 0.0
var _limit: float = 60.0
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _rows: PackedStringArray = PackedStringArray()
var _bucket_start: float = 0.0
var _bucket_frames: int = 0
var _bucket: Dictionary = {}
var _last_usec: int = 0
var _out_path: String = "user://perf_run.csv"
var _orbit: float = 0.0
var _done: bool = false


func _initialize() -> void:
	_options = _parse({
		"seconds": 60.0,
		"runners": 3,
		"view": "runner",
		"width": 1920,
		"height": 1080,
		"warmup": 3.0,
		"out": "user://perf_run.csv",
		"label": "run",
		"vsync": 0,
		"static": 0,
		"disable": "",
		"stage": 3,
		"after": "",
	})
	_limit = float(_options["seconds"])
	_warmup_left = float(_options["warmup"])
	_out_path = String(_options["out"])

	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if int(_options["vsync"]) == 1 else DisplayServer.VSYNC_DISABLED
	)
	DisplayServer.window_set_size(Vector2i(int(_options["width"]), int(_options["height"])))


func _parse(defaults: Dictionary) -> Dictionary:
	var out: Dictionary = defaults.duplicate()
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			continue
		var body: String = argument.substr(2)
		var split: int = body.find("=")
		if split < 0:
			continue
		var key: String = body.substr(0, split)
		var raw: String = body.substr(split + 1)
		if not out.has(key):
			printerr("profile_match: unknown option --%s" % key)
			continue
		match typeof(defaults[key]):
			TYPE_INT:
				out[key] = int(raw)
			TYPE_FLOAT:
				out[key] = float(raw)
			_:
				out[key] = raw
	return out


func _build() -> void:
	_root = Node.new()
	_root.name = "PerfRun"
	root.add_child(_root)

	print("renderer=%s window=%s" % [
		RenderingServer.get_video_adapter_name(), str(DisplayServer.window_get_size()),
	])

	# A control run: the arena and a camera, no match, no bots. What is left is
	# the render cost of the map, and the difference is what the game costs.
	var mode: int = int(_options["static"])
	if mode > 0:
		var arena: Node3D = (load(BotMatchWorld.ARENA_SCENE_PATH) as PackedScene).instantiate() as Node3D
		_root.add_child(arena)
		if mode >= 2:
			var runner: PackedScene = load(BotMatchWorld.RUNNER_SCENE_PATH) as PackedScene
			for index: int in maxi(int(_options["runners"]), 1):
				var body: Node3D = runner.instantiate() as Node3D
				_root.add_child(body)
				body.global_position = Vector3(50.0 + float(index), 25.0, float(index) * 2.0)
			BotMatchWorld.silence_local_input(_root)
		if mode >= 3:
			_root.add_child((load(BotMatchWorld.RIFLE_SCENE_PATH) as PackedScene).instantiate())
		_apply_disables()
		_camera = Camera3D.new()
		_camera.far = 400.0
		_camera.fov = 75.0
		_root.add_child(_camera)
		_camera.make_current()
		_camera.global_position = Vector3(52.0, 25.5, 0.0)
		_camera.look_at(Vector3.ZERO, Vector3.UP)
		_options["view"] = "fixed"
		return

	var rules: MatchRules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
	rules.prisoner_count = maxi(int(_options["runners"]), 1)
	# A profiling run must not end in ten seconds because somebody reached the
	# pad; it has to keep the same bodies moving for the whole window.
	rules.rounds_to_win_match = 99
	rules.prisoner_lives = 99

	_world = BotMatchWorld.new()
	_root.add_child(_world)
	_world.build(rules)

	var controller: MatchController = _world.get_controller()

	var stage: int = int(_options["stage"])
	if stage >= 2:
		_seat = BotTowerSeat.new()
		_seat.name = "TowerSeat"
		_root.add_child(_seat)
		var shooter: ShooterProfile = (load(SHOOTER_PROFILE_PATH) as ShooterProfile).duplicate() as ShooterProfile
		_seat.install(controller, shooter, 20260930)

	if stage >= 3:
		controller.start_match()
		BotMatchWorld.silence_local_input(_world.get_runner_container())

	_apply_disables()
	_apply_after()

	_camera = Camera3D.new()
	_camera.name = "PerfCamera"
	_camera.far = 400.0
	_camera.fov = 75.0
	_root.add_child(_camera)
	_camera.make_current()


## Engine-side bisect: things a script disable cannot reach.
func _apply_after() -> void:
	var what: String = String(_options["after"])
	if what.is_empty():
		return
	var counts: Dictionary = {}
	var pending: Array[Node] = [root]
	var doomed: Array[Node] = []
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			pending.append(child)
		if what.contains("stopanim") and node is AnimationMixer:
			(node as AnimationMixer).active = false
			counts["anim"] = int(counts.get("anim", 0)) + 1
		if what.contains("freeagents") and node is NavigationAgent3D:
			doomed.append(node)
			counts["agent"] = int(counts.get("agent", 0)) + 1
		if what.contains("freeregion") and node is NavigationRegion3D:
			doomed.append(node)
			counts["region"] = int(counts.get("region", 0)) + 1
		if what.contains("hidebodies") and node is PlayerController:
			(node as Node3D).visible = false
			counts["hidden"] = int(counts.get("hidden", 0)) + 1
		if what.contains("freebodies") and node is PlayerController:
			doomed.append(node)
			counts["freed"] = int(counts.get("freed", 0)) + 1
		if what.contains("noshadow") and node is Light3D:
			(node as Light3D).shadow_enabled = false
			counts["unshadowed"] = int(counts.get("unshadowed", 0)) + 1
		if what.contains("nolights") and node is Light3D:
			doomed.append(node)
			counts["light"] = int(counts.get("light", 0)) + 1
		if what.contains("freemap") and node is MeshInstance3D:
			(node as MeshInstance3D).visible = false
			counts["mesh_hidden"] = int(counts.get("mesh_hidden", 0)) + 1
		if what.contains("freeskel") and node is Skeleton3D:
			doomed.append(node)
			counts["skel"] = int(counts.get("skel", 0)) + 1
	for node: Node in doomed:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	print("after=%s %s" % [what, str(counts)])


## Switch named subsystems off so a run can be bisected: --disable=traps,brains.
func _apply_disables() -> void:
	var wanted: PackedStringArray = String(_options["disable"]).split(",", false)
	if wanted.is_empty():
		return
	var counts: Dictionary = {}
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			pending.append(child)
		var kind: String = ""
		if node is TrapVolume:
			kind = "traps"
		elif node is RingRunner or node is TowerShooter:
			kind = "brains"
		elif node is PlayerController:
			kind = "bodies"
		elif node is MatchController:
			kind = "controller"
		elif node.get_class() == "Area3D":
			kind = "areas"
		elif node.get_script() != null:
			kind = "scripted"
		if kind.is_empty() or not wanted.has(kind):
			continue
		if kind == "scripted" and (node is Camera3D or node == self):
			continue
		node.set_process(false)
		node.set_physics_process(false)
		counts[kind] = int(counts.get(kind, 0)) + 1
	print("disabled=%s" % str(counts))


func _process(delta: float) -> bool:
	if _done:
		return true
	if not _started:
		_started = true
		_build()
		_last_usec = Time.get_ticks_usec()
		return false

	# Re-asserted every frame: starting a match instantiates the settings store,
	# which pushes the player's saved vsync and would pin the measurement to the
	# refresh rate instead of reporting what a frame costs.
	if int(_options["vsync"]) == 0 and DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var now: int = Time.get_ticks_usec()
	var frame_ms: float = float(now - _last_usec) / 1000.0
	_last_usec = now

	_aim_camera(delta)

	if _warmup_left > 0.0:
		_warmup_left -= delta
		return false

	_elapsed += delta
	_frame_ms.append(frame_ms)
	_bucket_frames += 1
	_accumulate()

	if _elapsed - _bucket_start >= 1.0:
		_flush_bucket()

	if _elapsed >= _limit:
		if _bucket_frames > 0:
			_flush_bucket()
		_write()
		_done = true
		quit(0)
		return true
	return false


## Put the camera where a player actually is: behind a running bot, in the
## tower's seat, or orbiting the rim for a whole-arena worst case.
func _aim_camera(delta: float) -> void:
	if _camera == null:
		return
	match String(_options["view"]):
		"tower":
			_camera.global_position = Vector3(0.0, 27.3, 0.0)
			_orbit += delta * 0.6
			_camera.look_at(Vector3(cos(_orbit) * 52.0, 24.0, sin(_orbit) * 52.0), Vector3.UP)
		"orbit":
			_orbit += delta * 0.35
			_camera.global_position = Vector3(cos(_orbit) * 78.0, 38.0, sin(_orbit) * 78.0)
			_camera.look_at(Vector3(0.0, 24.0, 0.0), Vector3.UP)
		_:
			var body: Node3D = _first_body()
			if body == null:
				_camera.global_position = Vector3(52.0, 25.5, 0.0)
				_camera.look_at(Vector3.ZERO, Vector3.UP)
				return
			var pos: Vector3 = body.global_position + Vector3(0.0, 1.6, 0.0)
			var flat: Vector3 = Vector3(-pos.z, 0.0, pos.x).normalized()
			_camera.global_position = pos - flat * 3.5 + Vector3(0.0, 0.8, 0.0)
			_camera.look_at(pos + flat * 12.0, Vector3.UP)


func _first_body() -> Node3D:
	if _world == null:
		return null
	var controller: MatchController = _world.get_controller()
	for participant: MatchParticipant in controller.get_participants():
		if participant.body != null and is_instance_valid(participant.body):
			return participant.body
	return null


const MONITORS: Array[String] = [
	"process", "physics", "navigation", "draw_calls", "primitives", "objects_drawn",
	"nodes", "objects", "phys_active", "phys_pairs", "mem_static", "vram",
]


func _accumulate() -> void:
	_add("process", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_add("physics", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_add("navigation", Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0)
	_add("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_add("primitives", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_add("objects_drawn", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_add("nodes", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_add("objects", Performance.get_monitor(Performance.OBJECT_COUNT))
	_add("phys_active", Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	_add("phys_pairs", Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	_add("mem_static", Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	_add("vram", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)


func _add(key: String, value: float) -> void:
	_bucket[key] = float(_bucket.get(key, 0.0)) + value


func _flush_bucket() -> void:
	var n: float = float(maxi(_bucket_frames, 1))
	var frames_here: int = _bucket_frames
	var slice_ms: float = 0.0
	var worst: float = 0.0
	var from: int = maxi(_frame_ms.size() - frames_here, 0)
	for i: int in range(from, _frame_ms.size()):
		slice_ms += _frame_ms[i]
		worst = maxf(worst, _frame_ms[i])
	if _rows.is_empty():
		print("env max_fps=%d phys_hz=%d time_scale=%.2f vsync=%d shadows=%d" % [
			Engine.max_fps, Engine.physics_ticks_per_second, Engine.time_scale,
			int(DisplayServer.window_get_vsync_mode()), _count_shadow_lights(),
		])
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%.1f" % _elapsed)
	parts.append(str(frames_here))
	parts.append("%.3f" % (slice_ms / n))
	parts.append("%.3f" % worst)
	for key: String in MONITORS:
		parts.append("%.3f" % (float(_bucket.get(key, 0.0)) / n))
	_rows.append(",".join(parts))
	_bucket.clear()
	_bucket_frames = 0
	_bucket_start = _elapsed


func _count_shadow_lights() -> int:
	var n: int = 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			pending.append(child)
		var light: Light3D = node as Light3D
		if light != null and light.shadow_enabled and light.visible:
			n += 1
	return n


func _write() -> void:
	var header: PackedStringArray = PackedStringArray(["t", "frames", "frame_ms", "worst_ms"])
	for key: String in MONITORS:
		header.append(key)

	var sorted: Array[float] = []
	for value: float in _frame_ms:
		sorted.append(value)
	sorted.sort()
	var count: int = sorted.size()
	var total: float = 0.0
	for value: float in sorted:
		total += value
	var mean: float = total / float(maxi(count, 1))
	var p50: float = sorted[count / 2] if count > 0 else 0.0
	var p99: float = sorted[mini(int(float(count) * 0.99), count - 1)] if count > 0 else 0.0
	# The worst 1% as players feel it: the MEAN of the slowest hundredth, not a
	# single spike that one stall can author.
	var tail_from: int = maxi(int(float(count) * 0.99), 0)
	var tail: float = 0.0
	for i: int in range(tail_from, count):
		tail += sorted[i]
	var worst1: float = tail / float(maxi(count - tail_from, 1))

	var summary: String = (
		"SUMMARY label=%s view=%s runners=%d frames=%d seconds=%.1f"
		+ " mean_ms=%.3f (%.1f fps) median_ms=%.3f p99_ms=%.3f worst1pct_ms=%.3f (%.1f fps)"
	) % [
		String(_options["label"]), String(_options["view"]), int(_options["runners"]),
		count, _elapsed, mean, 1000.0 / maxf(mean, 0.001), p50, p99,
		worst1, 1000.0 / maxf(worst1, 0.001),
	]

	var body: String = ",".join(header) + "\n" + "\n".join(_rows) + "\n" + summary + "\n"
	var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if file != null:
		file.store_string(body)
		file.close()
	print(body)
