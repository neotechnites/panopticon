extends SceneTree
## Pill-era seat recorder (runs at commit 00f0661d): one bot match through one body's own Head/Camera,
## events.jsonl + vis.jsonl + take.json in the sv3 design §1 schema. tools/content/sv3/pill.py drives it.
##
## godot --path <00f0661d checkout> --script res://tools/capture/pill_match.gd -- --seat=guard|runner:K
##   --seed=S --seconds=T --log=DIR [--sync=N] [--opening=seat|race]
## seat=guard follows the tower's holder (the TowerShooter's camera); runner:K is participant K's eyes.
## A dead pill despawns (hidden, no ragdoll at this commit): that despawn is logged as the `ragdoll` row.

const RULES_PATH: String = "res://resources/rules/default_match_rules.tres"
const SHOOTER_PROFILE_PATH: String = "res://scenes/bot/default_shooter_profile.tres"
const RIFLE_SCENE_PATH: String = "res://scenes/weapon/rifle.tscn"
const VIS_HZ: float = 10.0
const KILL_AFTER_HIT_S: float = 0.1
const EYE_FALLBACK: float = 1.65

var _opt: Dictionary = {"seat": "guard", "seed": 0, "seconds": 30.0, "log": "", "sync": 0, "opening": "seat"}
var _seat_spec: String = "guard"
var _seat_index: int = -1
var _seconds: float = 30.0
var _sync_frames: int = 0
var _sync_cover: CanvasLayer = null
var _built: bool = false
var _done: bool = false
var _elapsed: float = 0.0
var _world: BotMatchWorld = null
var _controller: MatchController = null
var _seat: BotTowerSeat = null
var _events: Array = []
var _vis: PackedStringArray = PackedStringArray()
var _vis_next: float = 0.0
var _was_running: Dictionary = {}
var _was_visible: Dictionary = {}
var _last_hit: Dictionary = {}
var _reasserted: int = 0
var _exit_code: int = 0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			_opt[arg.substr(2).get_slice("=", 0)] = arg.substr(2).get_slice("=", 1)
		elif arg.begins_with("--"):
			_opt[arg.substr(2)] = "1"
	_seat_spec = String(_opt["seat"])
	if _seat_spec.begins_with("runner:"):
		_seat_index = int(_seat_spec.substr(7))
	elif _seat_spec != "guard":
		_fail("pill_match: --seat must be guard or runner:K, got %s" % _seat_spec)
		return
	if _seat_spec == "guard" and String(_opt["opening"]) != "seat":
		_fail("pill_match: --seat=guard needs --opening=seat; a race has no guard until it is won.")
		return
	_seconds = maxf(float(_opt["seconds"]), 1.0)
	_sync_frames = int(_opt["sync"])
	if OS.has_feature("movie"):
		_fail("pill_match refuses Movie Maker: a take is a real-time screen recording.")
		return
	if _sync_frames > 0:
		_sync_cover = CanvasLayer.new()
		_sync_cover.layer = 128
		var white := ColorRect.new()
		white.color = Color.WHITE
		white.set_anchors_preset(Control.PRESET_FULL_RECT)
		RenderingServer.set_default_clear_color(Color.WHITE)
		_sync_cover.add_child(white)
		root.add_child(_sync_cover)
	physics_frame.connect(_physics_tick)


func _fail(msg: String) -> void:
	printerr(msg)
	_exit_code = 2
	_done = true


func _hold_window() -> void:
	var want := Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width")), int(ProjectSettings.get_setting("display/window/size/viewport_height")))
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_size() != want:
		DisplayServer.window_set_size(want)
		DisplayServer.window_set_position(Vector2i.ZERO)
	if _sync_cover != null and _sync_cover.get_child_count() > 0:
		var white: Control = _sync_cover.get_child(0) as Control
		white.position = Vector2.ZERO
		white.size = Vector2(want)


func _process(delta: float) -> bool:
	_hold_window()
	if _done:
		quit(_exit_code)
		return true
	if not _built:
		if _sync_frames > 0:
			_sync_frames -= 1
			return false
		_built = true
		_build()
		return false
	if _sync_cover != null:
		_sync_cover.free()
		_sync_cover = null
		RenderingServer.set_default_clear_color(Color.BLACK)
	_elapsed += delta
	_hold_the_seat()
	_vis_next -= delta
	if _vis_next <= 0.0:
		_vis_next = 1.0 / VIS_HZ
		_sample_vis()
	if _elapsed >= _seconds:
		_finish()
		_done = true
	return false


func _build() -> void:
	var seed_value: int = int(_opt["seed"])
	if seed_value != 0:
		seed(seed_value)
	var rules: MatchRules = (load(RULES_PATH) as MatchRules).duplicate() as MatchRules
	rules.open_with_race = String(_opt["opening"]) == "race"
	rules.opening_seat_index = 0
	if rules.ai_runner_profile != null and seed_value != 0:
		# The runners' perception RNG is seeded too, so two seats of one seed are one match.
		rules.ai_runner_profile = rules.ai_runner_profile.duplicate() as RunnerProfile
		rules.ai_runner_profile.perception_seed = seed_value
	_world = BotMatchWorld.new()
	root.add_child(_world)
	_world.build(rules)
	# BotMatchWorld zeroes the tracer for headless sweeps; a filmed shot needs the shipped one back.
	var fresh: Rifle = (load(RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	_world.get_rifle().profile = fresh.profile
	fresh.free()
	_controller = _world.get_controller()
	if _seat_index >= rules.get_participant_count() or _seat_index < -1:
		_fail("pill_match: %s is not in a %d-body match." % [_seat_spec, rules.get_participant_count()])
		return
	_seat = BotTowerSeat.new()
	_seat.name = "PillTowerSeat"
	root.add_child(_seat)
	_seat.install(_controller, (load(SHOOTER_PROFILE_PATH) as ShooterProfile).duplicate() as ShooterProfile, seed_value)
	_hook_events()
	_controller.match_won.connect(func(_w: MatchParticipant) -> void: _controller.restart())
	_controller.start_match()
	BotMatchWorld.silence_local_input(_world.get_runner_container())
	for participant: MatchParticipant in _controller.get_participants():
		_was_running[participant.index] = participant.is_running
		_was_visible[participant.index] = participant.body != null and participant.body.visible
	var log_dir: String = String(_opt["log"])
	if not log_dir.is_empty() and not DirAccess.dir_exists_absolute(log_dir):
		DirAccess.make_dir_recursive_absolute(log_dir)
	print("[match] pill seat %s bots %d seed %d opening %s for %.0f s; log %s" % [_seat_spec, _controller.get_participants().size(), seed_value, _opt["opening"], _seconds, log_dir if not log_dir.is_empty() else "(stdout only)"])


func _id_of(participant: MatchParticipant) -> String:
	if participant == null:
		return ""
	return "guard" if participant.is_shooter else "runner:%d" % participant.index


func _seat_participant() -> MatchParticipant:
	if _seat_index < 0:
		return _controller.get_seat_participant()
	for participant: MatchParticipant in _controller.get_participants():
		if participant.index == _seat_index:
			return participant
	return null


func _eye_of(body: PlayerController) -> Camera3D:
	return body.get_node_or_null(^"Head/Camera") as Camera3D if body != null else null


func _eye_height(body: PlayerController) -> float:
	var head: Node3D = body.get_node_or_null(^"Head") as Node3D
	return head.position.y if head != null else EYE_FALLBACK


## The seat body's own camera is current, every frame; nothing else ever gets the screen.
func _hold_the_seat() -> void:
	var participant: MatchParticipant = _seat_participant()
	var eye: Camera3D = _eye_of(participant.body) if participant != null else null
	if eye == null:
		return
	if root.get_camera_3d() != eye:
		eye.current = true
		_reasserted += 1
		print("[seat] %6.2f eye of %s re-asserted" % [_elapsed, _id_of(participant)])


func _ev(name: String, fields: Dictionary = {}) -> Dictionary:
	var row: Dictionary = {"t": snappedf(_elapsed, 0.01), "ev": name}
	row.merge(fields)
	_events.append(row)
	print("[ev] %s" % JSON.stringify(row))
	return row


func _hook_events() -> void:
	var rifle: Rifle = _world.get_rifle()
	rifle.fired.connect(func(_o: Vector3, _e: Vector3) -> void: _ev("shot", {"by": _id_of(_controller.get_seat_participant())}))
	rifle.target_hit.connect(
		func(collider: Node3D, at: Vector3, _n: Vector3) -> void:
			var victim: MatchParticipant = _controller.resolve_participant(collider)
			var by: String = _id_of(_controller.get_seat_participant())
			if victim == null:
				_ev("shot_result", {"by": by, "result": "miss"})
				return
			var share: float = (at.y - victim.body.global_position.y) / maxf(_eye_height(victim.body), 0.1)
			_last_hit[victim.index] = _elapsed
			_ev("shot_result", {"by": by, "result": "hit", "victim": "runner:%d" % victim.index, "part": "head" if share > 0.85 else ("torso" if share > 0.45 else "legs")})
	)
	rifle.missed.connect(func(_e: Vector3) -> void: _ev("shot_result", {"by": _id_of(_controller.get_seat_participant()), "result": "miss"}))
	_controller.race_started.connect(func() -> void: _ev("race_start"))
	# Default rules at this commit: a shot runner becomes a ghost; a ghost that catches a runner trades places with it.
	_controller.ghost_caught.connect(
		func(ghost: MatchParticipant, caught: MatchParticipant) -> void:
			_ev("kill", {"by": "runner:%d" % ghost.index, "victim": "runner:%d" % caught.index, "cause": "ghost"})
			_ev("ragdoll", {"body": "runner:%d" % caught.index})
			_was_running[caught.index] = false
			_was_running[ghost.index] = true
			_was_visible[caught.index] = false
	)
	_controller.seat_changed.connect(
		func(participant: MatchParticipant, turns: int) -> void:
			if _controller.get_phase() == MatchController.Phase.RACE:
				_ev("race_won", {"body": "runner:%d" % participant.index})
			_ev("seat", {"body": "runner:%d" % participant.index, "turn": turns})
	)
	_controller.round_started.connect(func() -> void: _ev("round_start", {"n": _controller.get_round_number()}))
	_controller.round_resolved.connect(func(_o: MatchController.Outcome) -> void: _ev("round_end", {"n": _controller.get_round_number()}))
	_controller.match_started.connect(
		func(_count: int) -> void:
			for participant: MatchParticipant in _controller.get_participants():
				var optic: WeaponOptic = participant.body.get_node_or_null(^"Optic") as WeaponOptic if participant.body != null else null
				if optic != null:
					optic.zoom_requested.connect(func(zoomed: bool) -> void: _ev("scoped", {"by": _id_of(participant), "on": zoomed}))
	)


## The controller has no per-body death signal at this commit: a runner that stops running mid-round was
## killed (shot if a hit landed on it within 0.1 s, else the pit); in the race it is out. Hidden = despawned.
func _physics_tick() -> void:
	if _controller == null or _done:
		return
	for participant: MatchParticipant in _controller.get_participants():
		var running: bool = participant.is_running
		var visible: bool = participant.body != null and participant.body.visible
		var id: String = "runner:%d" % participant.index
		if bool(_was_running.get(participant.index, false)) and not running and not participant.is_shooter:
			var shot: bool = _elapsed - float(_last_hit.get(participant.index, -100.0)) <= KILL_AFTER_HIT_S
			if _controller.get_phase() == MatchController.Phase.RACE:
				_ev("out", {"body": id, "cause": "pit"})
			else:
				_ev("kill", {"by": _id_of(_controller.get_seat_participant()) if shot else "", "victim": id, "cause": "shot" if shot else "pit"})
				if not visible or participant.is_ghost:
					_ev("ragdoll", {"body": id})
		elif bool(_was_visible.get(participant.index, true)) and not visible and not running and not participant.is_shooter:
			_ev("ragdoll", {"body": id})
		_was_running[participant.index] = running
		_was_visible[participant.index] = visible


func _state_of(participant: MatchParticipant) -> String:
	if participant.is_ghost:
		return "ghost"
	if participant.is_shooter:
		return "guard"
	if not participant.is_running:
		return "dead"
	if participant.brain != null and participant.brain.get_state() == RingRunner.State.HOLD:
		return "cover"
	return "run"


## One vis.jsonl row: what the seat camera can see of every body (design §1).
func _sample_vis() -> void:
	var cam: Camera3D = root.get_camera_3d()
	if cam == null:
		return
	var seat_participant: MatchParticipant = _seat_participant()
	var seat_body: PlayerController = seat_participant.body if seat_participant != null else null
	var through_eye: bool = seat_body != null and cam == _eye_of(seat_body)
	var size: Vector2 = root.get_visible_rect().size
	var forward: Vector3 = -cam.global_basis.z
	var optic: WeaponOptic = seat_body.get_node_or_null(^"Optic") as WeaponOptic if through_eye else null
	var row: Dictionary = {
		"t": snappedf(_elapsed, 0.1), "cam": _seat_spec if through_eye else "other",
		"yaw": snappedf(rad_to_deg(atan2(-forward.x, -forward.z)), 0.1), "pitch": snappedf(rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))), 0.1),
		"scoped": optic != null and optic.is_zoom_requested(), "bodies": [],
	}
	var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
	for participant: MatchParticipant in _controller.get_participants():
		var body: PlayerController = participant.body
		if body == null:
			continue
		var eye_y: float = maxf(_eye_height(body), 0.1)
		var chest: Vector3 = body.global_position + Vector3.UP * eye_y * 0.75
		var in_frustum: bool = body.visible and not (through_eye and body == seat_body) and cam.is_position_in_frustum(chest)
		var occ: bool = false
		if in_frustum:
			var query := PhysicsRayQueryParameters3D.create(cam.global_position, chest, 0xFFFFFFFF)
			if through_eye:
				query.exclude = [seat_body.get_rid()]
			var hit: Dictionary = space.intersect_ray(query)
			occ = hit.is_empty() or (hit["collider"] as Node) != body
		# Screen space only for a body in the frustum: unproject behind the camera is garbage (audit 6).
		var head: Vector2 = cam.unproject_position(body.global_position + Vector3.UP * (eye_y + 0.15)) if in_frustum else Vector2.ZERO
		var feet: Vector2 = cam.unproject_position(body.global_position) if in_frustum else Vector2.ZERO
		var at: Vector2 = cam.unproject_position(chest) if in_frustum else Vector2.ZERO
		row["bodies"].append({
			"id": _id_of(participant), "on": in_frustum and not occ,
			"h": snappedf(absf(head.y - feet.y) / maxf(size.y, 1.0), 0.001) if in_frustum else 0.0,
			"x": snappedf(at.x / maxf(size.x, 1.0), 0.001) if in_frustum else 0.0, "y": snappedf(at.y / maxf(size.y, 1.0), 0.001) if in_frustum else 0.0,
			"d": snappedf(cam.global_position.distance_to(chest), 0.1), "occ": occ, "state": _state_of(participant),
		})
	_vis.append(JSON.stringify(row))


func _finish() -> void:
	var counts: Dictionary = {}
	for row: Dictionary in _events:
		counts[row["ev"]] = int(counts.get(row["ev"], 0)) + 1
	var summary: PackedStringArray = PackedStringArray()
	for name: String in counts:
		summary.append("%s %d" % [name, counts[name]])
	print("[match] %.1f s, %d vis rows, eye re-asserted %d times; events: %s" % [_elapsed, _vis.size(), _reasserted, ", ".join(summary) if not summary.is_empty() else "none"])
	var log_dir: String = String(_opt["log"])
	if log_dir.is_empty():
		return
	var events: PackedStringArray = PackedStringArray()
	for row: Dictionary in _events:
		events.append(JSON.stringify(row))
	_write(log_dir.path_join("events.jsonl"), "\n".join(events) + "\n")
	_write(log_dir.path_join("vis.jsonl"), "\n".join(_vis) + "\n")
	var commit: Array = []
	OS.execute("git", ["rev-parse", "--short", "HEAD"], commit)
	var take: Dictionary = {
		"args": OS.get_cmdline_user_args(), "commit": String(commit[0]).strip_edges() if not commit.is_empty() else "",
		"source": "match", "seed": int(_opt["seed"]), "map": "pill", "opening": _opt["opening"], "seat": _seat_spec,
		"sync_frames": int(_opt["sync"]), "t0": 0.0, "duration": snappedf(_elapsed, 0.01), "tape": "",
		"old": false, "kill": "", "events": counts,
		"files": {"events": log_dir.path_join("events.jsonl"), "vis": log_dir.path_join("vis.jsonl")},
	}
	_write(log_dir.path_join("take.json"), JSON.stringify(take, "  "))
	print("[match] wrote %s/{events.jsonl,vis.jsonl,take.json}" % log_dir)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("[match] cannot write %s" % path)
		return
	file.store_string(text)
	file.close()
