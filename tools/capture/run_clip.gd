extends SceneTree

## PANOPTICON's b-roll runner: a bots-only match, filmed along a named path.
##
## [codeblock]
## godot --path . --script res://tools/capture/run_clip.gd -- \
##     --shot=s2_chain --seconds=8 --seed=20260930 --bots=7 --out=<dir>
## [/codeblock]
##
## Options, all optional but [code]--shot[/code]:
##
## [codeblock]
## --shot=NAME      a path from tools/capture/shot_paths.gd  (required)
## --seconds=F      how long to fly it; 0 means the shot's own duration
## --delay=F        seconds held on the first key first, so the match catches up
## --seed=N         match seed; 0 means entropy               (default 20260930)
## --bots=N         prisoners on the ring, plus one in the tower  (default 7)
## --out=DIR        directory the clip is destined for; created if missing
## [/codeblock]
##
## The whole path always plays, stretched or squeezed to [code]--seconds[/code],
## so a three second smoke run covers the same ground the full take does.
##
## [b]Frames come from Godot, not from here[/b]
##
## Add [code]--write-movie out.avi --fixed-fps 60[/code] and the engine writes
## every frame; without them this simply plays, which is what makes the headless
## smoke test on the Mac free. Movie Maker needs a window, so a real take runs on
## the PC.
##
## [b]Why the shipped match scene is reconfigured rather than rebuilt[/b]
##
## [BotMatchWorld] composes a headless match from parts and deliberately leaves
## the HUD, the feedback rig and the lights of the match scene out; b-roll wants
## exactly those. So this loads [code]scenes/match/match.tscn[/code] and, before
## it enters the tree, takes the human out of the roster
## ([member MatchController.player] null, so every participant is AI), parks the
## body its NodePaths still point at, and disables the layers that exist for a
## human. [BotTowerSeat] then does here what it does for a sweep: without a
## brain behind the seat an all-AI tower never fires and no round can end.

const SHOTS := preload("res://tools/capture/shot_paths.gd")
const MATCH_SCENE: String = "res://scenes/match/match.tscn"

## Layer 2 is the owner-hidden layer every camera in the game clears; a camera
## that keeps it films the inside of somebody's head.
const CULL_MASK: int = 1048573

const EXIT_OK: int = 0
const EXIT_BROKEN: int = 2

var _options: Dictionary = {}
var _keys: Array = []
var _key_start: float = 0.0
var _key_span: float = 0.0
var _seconds: float = 0.0
var _delay: float = 0.0
var _elapsed: float = 0.0
var _camera: Camera3D = null
var _controller: MatchController = null
var _built: bool = false
var _done: bool = false
var _exit_code: int = EXIT_OK


func _initialize() -> void:
	# The project stretches canvas_items, which pins the root viewport at the
	# authored 1600x900 whatever --resolution asks the window for -- and Movie
	# Maker records the VIEWPORT. Disabling the stretch lets --resolution decide
	# the recorded size. No UI is drawn in a clip, so nothing is scaled by it.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_options = BotHarness.parse_arguments({
		"shot": "",
		"seconds": 0.0,
		"delay": 0.0,
		"seed": BotHarness.DEFAULT_SEED,
		"bots": 7,
		"out": "",
	})


## The world is built on the first iteration rather than in
## [method _initialize], where nothing is in the tree yet and every
## global_position reads back as the origin.
func _process(delta: float) -> bool:
	if _done:
		quit(_exit_code)
		return true
	if not _built:
		_built = true
		_build()
		return false

	_elapsed += delta
	if _elapsed < _delay:
		_aim_camera(_key_start)
		return false
	var progress: float = clampf((_elapsed - _delay) / _seconds, 0.0, 1.0)
	_aim_camera(_key_start + progress * _key_span)
	if _elapsed >= _delay + _seconds:
		_hush()
		_done = true
	return false


# --- Setup --------------------------------------------------------------------

func _build() -> void:
	if bool(_options.get("_error", false)):
		_fail("Bad command line; nothing was filmed.")
		return

	var shot: Dictionary = SHOTS.get_shot(String(_options.get("shot", "")))
	if shot.is_empty():
		_fail(
			"Unknown --shot=%s; the shots are %s."
			% [_options.get("shot", ""), ", ".join(SHOTS.names())]
		)
		return
	_keys = shot["keys"]
	_key_start = float(_keys[0]["t"])
	_key_span = float(_keys[_keys.size() - 1]["t"]) - _key_start
	_seconds = float(_options.get("seconds", 0.0))
	_seconds = maxf(_seconds, 0.1) if _seconds > 0.0 else float(shot["duration"])
	_delay = maxf(float(_options.get("delay", 0.0)), 0.0)

	var seed_value: int = int(_options.get("seed", 0))
	if seed_value != 0:
		seed(seed_value)

	var packed: PackedScene = load(MATCH_SCENE) as PackedScene
	if packed == null:
		_fail("Cannot load %s; there is no match to film." % MATCH_SCENE)
		return
	var match_root: Node = packed.instantiate()

	_controller = match_root.get_node_or_null(^"MatchController") as MatchController
	if _controller == null:
		_fail("%s has no MatchController; nothing would play." % MATCH_SCENE)
		match_root.free()
		return
	_make_it_bots_only(match_root, int(_options.get("bots", 7)))

	root.add_child(match_root)
	_park_the_human(match_root)
	_camera = _make_camera()
	root.add_child(_camera)
	_camera.current = true

	# Before start_match, exactly as the sweep does it: the first seat is granted
	# from inside that call and a seat brain armed afterwards would miss it.
	var seat: BotTowerSeat = BotTowerSeat.new()
	seat.name = "ClipTowerSeat"
	root.add_child(seat)
	seat.install(_controller, _shooter_profile(), seed_value)
	# A clip outlives the match it is filming: a won match freezes every body,
	# and a frozen ring is not b-roll.
	_controller.match_won.connect(func(_winner: MatchParticipant) -> void: _controller.restart())
	_controller.start_match()

	_aim_camera(_key_start)
	_announce(shot)


## Take the human out of the roster and switch off the layers that serve one.
##
## Called before the scene enters the tree, so [MatchController] arms its first
## match already knowing there is nobody at the keyboard.
func _make_it_bots_only(match_root: Node, bots: int) -> void:
	_controller.auto_start = false
	# Null player means _build_participants fills every slot with AI.
	_controller.player = null
	# A private copy: the .tres is one shared instance and --bots must not
	# retune the rules the next thing in this process reads.
	var rules: MatchRules = _controller.get_rules().duplicate() as MatchRules
	rules.prisoner_count = maxi(bots, 1)
	_controller.rules = rules

	# The placeholder music loop is still feeding the audio server when the
	# engine tears the tree down, which is reported as a leaked instance and
	# fails a smoke run. B-roll gets its music in the edit.
	var music: Node = match_root.get_node_or_null(^"Music")
	if music != null:
		music.free()

	# SettingsBoot writes the player's saved settings over the rules, which would
	# make the same seed film a different match on a different machine.
	for path: String in [
		"SettingsBoot", "NetMatch", "HUD", "FeedbackRig", "SpectatorView", "SeatHandover",
		"FreeCamera", "DeathScreen", "RoundTransition", "ResultScreen", "PauseMenu",
	]:
		var node: Node = match_root.get_node_or_null(NodePath(path))
		if node == null:
			continue
		node.process_mode = Node.PROCESS_MODE_DISABLED
		var canvas: CanvasLayer = node as CanvasLayer
		if canvas != null:
			canvas.visible = false

	# Before the scene enters the tree, so no _ready of a human input node ever
	# reaches a mouse: the sweep's own switch, pointed at a match scene.
	BotMatchWorld.silence_local_input(match_root)


## Put the human body out of the world it is no longer playing in.
##
## It is not freed: the rifle hangs off its head until the match reparents it,
## and half the scene's NodePaths still point at it.
func _park_the_human(match_root: Node) -> void:
	var player: Node3D = match_root.get_node_or_null(^"Player") as Node3D
	if player == null:
		return
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(0.0, 400.0, 0.0)
	var camera: Camera3D = player.get_node_or_null(^"Head/Camera") as Camera3D
	if camera != null:
		camera.current = false


func _make_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "ClipCamera"
	camera.cull_mask = CULL_MASK
	camera.far = 400.0
	return camera


## A private copy of the tuned shooter profile, for the same reason
## [BotMatchRunner] takes one: [BotTowerSeat] writes a seed into it per body.
func _shooter_profile() -> ShooterProfile:
	var profile: ShooterProfile = load(BotMatchRunner.SHOOTER_PROFILE_PATH) as ShooterProfile
	return profile.duplicate() as ShooterProfile


# --- Flying it ----------------------------------------------------------------

## Put the camera where the path says it is at path time [param path_time].
func _aim_camera(path_time: float) -> void:
	var pose: Dictionary = SHOTS.sample(_keys, path_time)
	var position: Vector3 = pose["pos"]
	var target: Vector3 = pose["look"]
	_camera.global_position = position
	if position.distance_squared_to(target) > 0.0001:
		_camera.look_at(target, Vector3.UP)
	_camera.fov = float(pose["fov"])
	# Re-asserted rather than assumed: the match scene carries three other
	# cameras that can claim the viewport, and a clip filmed from one of them is
	# a clip nobody can tell is wrong until it is watched.
	if not _camera.current:
		_camera.current = true


# --- Reporting ----------------------------------------------------------------

func _announce(shot: Dictionary) -> void:
	var out_dir: String = String(_options.get("out", ""))
	if not out_dir.is_empty() and not DirAccess.dir_exists_absolute(out_dir):
		DirAccess.make_dir_recursive_absolute(out_dir)
	var recording: bool = OS.has_feature("movie")
	print("shot %s: %.1f s (after %.1f s held) over %d keys, %d bots, seed %d%s" % [
		shot["name"],
		_seconds,
		_delay,
		_keys.size(),
		int(_options.get("bots", 7)),
		int(_options.get("seed", 0)),
		"" if recording else "  (playing only; no --write-movie)",
	])
	if not out_dir.is_empty():
		print("clip: %s" % out_dir.path_join("%s.avi" % shot["name"]))


## Stop every voice before the engine tears the tree down: a stream still
## feeding the audio server at cleanup is reported as a leaked instance.
func _hush() -> void:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child: Node in node.get_children():
			pending.append(child)
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			node.call(&"stop")


func _fail(message: String) -> void:
	printerr(message)
	_exit_code = EXIT_BROKEN
	_done = true
