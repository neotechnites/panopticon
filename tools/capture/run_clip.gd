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
## --look=social    lift the ring's own grade until rock reads on a phone
## --stage=NAME     staged action: firefight (the tower snap-shoots) or
##                  chainrun (one prisoner takes the S2 boulder chain)
## --pov=runner     film down a bot-driven prisoner's own eyes, HUD on, no path
## --audio=near     only sounds made within AUDIO_NEAR_METRES of the camera
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
const CHAIN_STAGE := preload("res://tools/capture/chain_stage.gd")
const MATCH_SCENE: String = "res://scenes/match/match.tscn"

## Layer 2 is the owner-hidden layer every camera in the game clears; a camera
## that keeps it films the inside of somebody's head.
const CULL_MASK: int = 1048573

## The social grade: the shipped environment, lifted. Reinhard rolls the lava off
## rather than clipping it, so only the rock really moves.
## Exposure is kept close to the shipped value because the lava is emissive and
## exposure is the only one of these that touches it; the rock is lifted with
## ambient and a fill instead, which emissive surfaces never see.
const SOCIAL_EXPOSURE: float = 1.45
const SOCIAL_AMBIENT: float = 0.95
const SOCIAL_FILL_ENERGY: float = 0.55
const SOCIAL_FILL_RANGE: float = 22.0
const SOCIAL_FILL_COLOUR := Color(1.0, 0.63, 0.44)

## A clip hears what a body at the camera would hear and nothing else: the match
## bank's flat cues carry no distance at all, so an off-screen round resolving
## lands at full volume over a quiet shot.
const AUDIO_NEAR_METRES: float = 25.0
const AUDIO_MUTED_DB: float = -60.0

## The deck the prisoners run on; a POV body far off it is not standing on it.
const DECK_Y: float = 23.0

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
var _stage: String = ""
var _pov: String = ""
var _pov_body: Node3D = null
var _fill: OmniLight3D = null
var _chain: Node = null
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
		"look": "",
		"stage": "",
		"pov": "",
		"audio": "",
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
	if _stage == "chainrun" and _chain == null and _elapsed > 0.5:
		_stage_chainrun()
	if _elapsed < _delay:
		_aim_camera(_key_start)
		return false
	if _pov == "runner":
		_ride_a_runner()
	else:
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
	_stage = String(_options.get("stage", ""))

	_pov = String(_options.get("pov", ""))
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
	if _pov == "":
		_camera = _make_camera()
		root.add_child(_camera)
		_camera.current = true

	if String(_options.get("look", "")) == "social":
		_light_for_social(match_root)
	_listen_to_audio()
	if String(_options.get("audio", "")) == "near":
		_keep_audio_near()

	# Before start_match, exactly as the sweep does it: the first seat is granted
	# from inside that call and a seat brain armed afterwards would miss it.
	# chainrun wants no seat at all: an unmanned tower never fires, so no round
	# ends and the staged body is still on the chain when the path finishes.
	if _stage != "chainrun":
		var seat: BotTowerSeat = BotTowerSeat.new()
		seat.name = "ClipTowerSeat"
		root.add_child(seat)
		seat.install(_controller, _shooter_profile(), seed_value)
	else:
		_disarm_traps(match_root, ^"Sections/S2_LavaShelf")
	# A clip outlives the match it is filming: a won match freezes every body,
	# and a frozen ring is not b-roll.
	_controller.match_won.connect(func(_winner: MatchParticipant) -> void: _controller.restart())
	_controller.start_match()

	if _pov == "":
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
	var silenced: Array[String] = [
		"SettingsBoot", "NetMatch", "HUD", "FeedbackRig", "SpectatorView", "SeatHandover",
		"FreeCamera", "DeathScreen", "RoundTransition", "ResultScreen", "PauseMenu",
	]
	if _pov == "runner":
		# A POV clip is a player's view: it wants the readouts and the camera kick,
		# and the spectator cut when the body it is riding is shot.
		for keep: String in ["HUD", "FeedbackRig", "SpectatorView"]:
			silenced.erase(keep)
	for path: String in silenced:
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
	var copy: ShooterProfile = profile.duplicate() as ShooterProfile
	if _stage == "firefight":
		# The shipped guard takes most of a clip to decide. This one does not:
		# it is the same brain with its patience removed, on a throwaway copy.
		copy.scan_yaw_rate = 2.4
		copy.reaction_seconds = 0.08
		copy.shot_confidence_threshold = 0.15
		copy.aim_error_degrees = 0.3
		copy.confident_range = 120.0
	return copy


## Lift the ring's own environment until rock reads on a phone: more exposure and
## ambient, plus a warm fill riding the camera. The shipped resource is untouched.
func _light_for_social(match_root: Node) -> void:
	var world: WorldEnvironment = _find_node(match_root, "WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		var env: Environment = world.environment.duplicate() as Environment
		env.tonemap_exposure = SOCIAL_EXPOSURE
		env.ambient_light_energy = SOCIAL_AMBIENT
		world.environment = env
	_fill = OmniLight3D.new()
	_fill.name = "ClipFill"
	_fill.light_color = SOCIAL_FILL_COLOUR
	_fill.light_energy = SOCIAL_FILL_ENERGY
	_fill.omni_range = SOCIAL_FILL_RANGE
	_fill.omni_attenuation = 0.7
	_fill.shadow_enabled = false
	# In a POV clip there is no clip camera to hang it on; it follows the body
	# being ridden instead, which _ride_a_runner reparents it to.
	if _camera != null:
		_camera.add_child(_fill)
	else:
		root.add_child(_fill)


## Put the first living prisoner on the S2 chain instead of on the lane.
func _stage_chainrun() -> void:
	var runners: Array[RingRunner] = _controller.get_live_runners()
	if runners.is_empty() or runners[0].controller == null:
		return
	_chain = CHAIN_STAGE.new()
	_chain.name = "ClipChainStage"
	root.add_child(_chain)
	_chain.install(runners[0].controller, runners[0])


## Stop the lava under [param section] killing the staged body mid-leap.
func _disarm_traps(match_root: Node, section: NodePath) -> void:
	var node: Node = match_root.get_node_or_null(section)
	if node == null:
		return
	for child: Node in node.get_children():
		var area: Area3D = child as Area3D
		if area != null:
			area.monitoring = false


## The first node called [param wanted] anywhere under [param from].
func _find_node(from: Node, wanted: String) -> Node:
	var pending: Array[Node] = [from]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.name == wanted:
			return node
		for child: Node in node.get_children():
			pending.append(child)
	return null


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
	print("look %s, stage %s" % [
		_options.get("look", "") if String(_options.get("look", "")) != "" else "shipped",
		_stage if _stage != "" else "none",
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


# --- Riding a body ------------------------------------------------------------

## Keep the view down some living prisoner's own camera, changing body when the
## one being ridden is taken. The body's camera is never written to: only made
## current, which is what [FxSpectatorView] does for a dead player.
func _ride_a_runner() -> void:
	# A shot prisoner is not freed, it is buried a hundred metres under the deck,
	# so "still valid" is not "still worth watching": the same standing test that
	# picks a body has to keep deciding whether to stay on it.
	if _pov_body != null and is_instance_valid(_pov_body) and _is_standing(_pov_body):
		var riding: Camera3D = _pov_body.get_node_or_null(^"Head/Camera") as Camera3D
		if riding == null:
			riding = _pov_body.get_node_or_null(^"Camera") as Camera3D
		if riding != null and riding.current:
			return
	for runner: RingRunner in _controller.get_live_runners():
		var body: Node3D = runner.controller
		if body == null:
			continue
		if not _is_standing(body):
			continue
		var camera: Camera3D = body.get_node_or_null(^"Head/Camera") as Camera3D
		if camera == null:
			camera = body.get_node_or_null(^"Camera") as Camera3D
		if camera == null:
			continue
		camera.current = true
		_pov_body = body
		_wear_the_body(body)
		return


## First-person body rules, as the human's body already has them: a runner's
## avatar sits on visual layer 3 so every other camera sees it, and that is the
## one layer its own camera does not clear. Put it back on the owner-hidden
## layer and [PrisonerAvatar] does the rest -- head and spine collapsed, the
## first-person layer added -- with no change to the avatar itself.
## True while [param body] is on the deck rather than buried under it.
func _is_standing(body: Node3D) -> bool:
	return absf(body.global_position.y - DECK_Y) <= 6.0


func _wear_the_body(body: Node3D) -> void:
	var avatar: Node = body.get_node_or_null(^"Avatar")
	if avatar != null and avatar.get("visual_layers") != null:
		avatar.set("visual_layers", 2)
	if _fill != null:
		var head: Node = body.get_node_or_null(^"Head")
		if head != null and _fill.get_parent() != head:
			_fill.reparent(head, false)
			_fill.position = Vector3.ZERO


# --- Audio --------------------------------------------------------------------

## Print every cue the match posts, so a clip's soundtrack can be read off the log.
func _listen_to_audio() -> void:
	var director: AudioDirector = AudioDirector.instance()
	if director == null:
		return
	director.event_played.connect(
		func(event: StringName, positional: bool) -> void:
			print("[audio] %6.2f  %s  %s" % [_elapsed, event, "3d" if positional else "flat"])
	)


## Give the director a private bank that only carries near sound: flat cues are
## muted outright and positional ones stop reaching past [constant AUDIO_NEAR_METRES].
func _keep_audio_near() -> void:
	var director: AudioDirector = AudioDirector.instance()
	if director == null:
		return
	for which: StringName in [&"bank", &"crushed_bank"]:
		var bank: AudioBank = director.get(which) as AudioBank
		if bank == null:
			continue
		var copy: AudioBank = bank.duplicate(true) as AudioBank
		for cue: AudioCue in copy.cues:
			if cue == null:
				continue
			if cue.positional:
				cue.max_distance = AUDIO_NEAR_METRES
				cue.unit_size = minf(cue.unit_size, 6.0)
			else:
				cue.volume_db = AUDIO_MUTED_DB
		copy.rebuild_index()
		director.set(which, copy)
