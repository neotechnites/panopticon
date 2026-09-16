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
## --stage=NAME     staged action. A file tools/capture/stages/NAME.gd is a
##                  stage plugin and wins (see stages/README.md); otherwise one
##                  of the stages in stage_driver.gd: firefight (the tower snap-shoots),
##                  chainrun (one prisoner takes the S2 boulder chain),
##                  shovecatch / ghostcatch (a second prisoner, or a ghost, shoves
##                  the chain runner mid-jump into the lava), missstreak (a sloppy
##                  guard empties the rifle at a weaving runner), decoy (a
##                  hologram eats the shot), padflight (a demon pad flight, then
##                  the bot finds cover), lavadeath (a runner hops into S4 lava),
##                  ghostchase (a ghost runs a prisoner down the open S3 lane and
##                  shoves them: the catch, and the swap), ghostpack (the round's
##                  own pack leaves the line; one of them is ghosted behind it and
##                  its own brain hunts through the pack for a spot),
##                  shovecover (a runner crouched behind the pocket rock at 196
##                  deg is shoved up the lane into the open by another runner, and
##                  the tower, passive until then, opens up on them), shoveedge (a
##                  runner stood at the pit rim on the S3 deck is shoved over it
##                  from behind by another runner; shoveedge_look: the same, and
##                  they look back over their shoulder as it comes), shovelake (a runner on the lip
##                  of the S5 bank is shoved out over the lava lake by another)
## --track=victim   a flown shot keeps its lens on the staged victim instead of
##                  the path's look targets, and holds where it was looking once
##                  the victim leaves the deck (over the rim, or into the lava)
## --pov=runner     film down a bot-driven prisoner's own eyes, no path
## --hud=on         draw the match HUD over a POV clip (crosshair, readouts);
##                  off unless asked: a short wants the view, not the screen
## --hud=crosshair  the crosshair alone (Ryan: a guard POV keeps the crosshair)
## --set=K=V;K=V    a stage plugin's own dials (its file lists them), e.g.
##                  --set=shover_wait=5.0;victim=198.5,49.4
## --pads=off       every boost pad switched off (a thrown body over one is relaunched)
## --traps=off      every trap volume switched off
## --pov=guard      the same, down the eyes of whoever holds the tower
## --pov=ghost      the same, down the eyes of the staged ghost, through its catch
## --audio=near     only sounds made within AUDIO_NEAR_METRES of the camera
## --seed=N         match seed; 0 means entropy               (default 20260930)
## --bots=N         prisoners on the ring, plus one in the tower  (default 7)
## --map=ID         a MapCatalog id (bentham_ring, marble, forest); the match
##                  is filmed on it instead of the map the saved rules name
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
const STAGE_DRIVER := preload("res://tools/capture/stage_driver.gd")
const STAGE_LIB := preload("res://tools/capture/stages/lib.gd")
const STAGES_DIR: String = "res://tools/capture/stages/"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"

## Layer 2 is the owner-hidden layer every camera in the game clears; a camera
## that keeps it films the inside of somebody's head.
const CULL_MASK: int = 1048573

## How close a clip camera may be to something before it stops drawing it.
const NEAR_METRES: float = 0.05

## The watcher looks down the ring until the camera stops, then takes this long
## to come round onto it -- arriving as the pan settles, not before it starts.
const EYE_SWING_SECONDS: float = 1.6
const EYE_SETTLE_SECONDS: float = 0.2
## Where it is looking while the lap is still running: the far side of the ring.
const EYE_ELSEWHERE_DEGREES: float = 150.0

## The social grade: the shipped environment, lifted. Reinhard rolls the lava off
## rather than clipping it, so only the rock really moves.
## Exposure is kept close to the shipped value because the lava is emissive and
## exposure is the only one of these that touches it; the rock is lifted with
## ambient and a fill instead, which emissive surfaces never see.
const SOCIAL_EXPOSURE: float = 1.45
const SOCIAL_AMBIENT: float = 0.95
const SOCIAL_FILL_ENERGY: float = 0.55
## A POV clip rides the fill, so it sits much closer to everything it lights.
const POV_FILL_ENERGY: float = 0.4
const SOCIAL_FILL_RANGE: float = 22.0
const SOCIAL_FILL_COLOUR := Color(1.0, 0.63, 0.44)

## A clip hears what a body at the camera would hear and nothing else: the match
## bank's flat cues carry no distance at all, so an off-screen round resolving
## lands at full volume over a quiet shot.
const AUDIO_NEAR_METRES: float = 25.0
const AUDIO_MUTED_DB: float = -60.0

## The deck the prisoners run on; a POV body far off it is not standing on it.
const DECK_Y: float = 23.0
## A tracked victim this far under the deck, or inside the deck's inner radius,
## has gone over the rim: the lens stops following and the body falls out of frame.
const TRACK_BELOW_DECK_METRES: float = 1.0
const RIM_R_FALLBACK: float = 46.7

## A body pressed into the pit wall is still "standing" and still "running"; it
## just never moves again. A clip drops one that has not travelled in this long.
const STUCK_SECONDS: float = 2.5
const STUCK_SPEED: float = 0.6
## The game's own camera kick, given to the ridden body: the shover's swing is
## felt by the human who swings it; a human who is shoved feels the launch and,
## in a clip, this -- the same whip, at the shove's own scale.
const FEEDBACK_PROFILE_PATH: String = "res://scenes/fx/default_feedback_profile.tres"
const POV_SHOVED_KICK_SCALE: float = 1.0

## The chase ghost runs this much faster than the prisoner it is after. The
## shipped ghost is three times faster and would be on them before a lens could
## settle; this closes the ten metres over about three seconds.
const CHASE_GHOST_SPEED_SCALE: float = 1.25
## ghostpack: how long the pack is given to leave the line before one of the
## prisoners behind it is ghosted and set on it.
const PACK_GHOST_SECONDS: float = 2.0

## The walkable band. The field is dealt sideways across the track and the far
## edge of the deal can land inside the pit wall, where a body sticks for good.
const LANE_BAND := Vector2(47.8, 56.8)

const EXIT_OK: int = 0
const EXIT_BROKEN: int = 2

var _options: Dictionary = {}
var _keys: Array = []
var _key_start: float = 0.0
var _key_span: float = 0.0
var _look_ahead: float = 0.0
var _look_ahead_until: float = 0.0
var _seconds: float = 0.0
var _delay: float = 0.0
var _elapsed: float = 0.0
var _camera: Camera3D = null
var _controller: MatchController = null
var _stage: String = ""
var _pov: String = ""
var _pov_body: Node3D = null
var _stuck_for: float = 0.0
var _seat: BotTowerSeat = null
var _fill: OmniLight3D = null
var _eye: Node3D = null
var _chain: Node = null
var _driver: Node = null
var _victim_driver: Node = null
var _victim_body: PlayerController = null
var _track: String = ""
var _tracked_look: Vector3 = Vector3.ZERO
var _tracking: bool = false
var _tracking_stopped: bool = false
var _ghost_body: PlayerController = null
var _pov_kick: FxCameraKick = null
var _arm_after_landing: bool = false
var _logged_shooter: TowerShooter = null
var _staged: PlayerController = null
## The stage plugin, when --stage names a file under tools/capture/stages/.
var _plugin: RefCounted = null
var _plugin_cast: bool = false
var _dials: Dictionary = {}
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
		"hud": "",
		"pads": "",
		"traps": "",
		"set": "",
		"track": "",
		"audio": "",
		"seed": BotHarness.DEFAULT_SEED,
		"bots": 7,
		"map": "",
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
	_log_the_rifle()
	if _wants_chain() and _chain == null and _elapsed > 0.5:
		_stage_chainrun()
	if _plugin != null:
		if not _plugin_cast and _elapsed > 0.6:
			_plugin_cast = _plugin.cast(_controller.get_live_runners())
		_plugin.tick(delta)
	elif STAGE_DRIVER.is_stage(_stage) and _driver == null and _elapsed > 0.6:
		_stage_driven()
	if _stage == "ghostpack" and _ghost_body == null and _elapsed > PACK_GHOST_SECONDS:
		_stage_ghostpack()
	_arm_the_tower_when_landed()
	if _elapsed < _delay:
		_aim_camera(_key_start)
		return false
	if _pov != "":
		_ride_a_body()
	else:
		if _plugin == null or not _plugin.lens(delta):
			var progress: float = clampf((_elapsed - _delay) / _seconds, 0.0, 1.0)
			_aim_camera(_key_start + progress * _key_span)
		_turn_the_eye(delta)
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
	_look_ahead = float(shot.get("look_ahead", 0.0))
	_look_ahead_until = float(shot.get("look_ahead_until", 0.0))
	_key_start = float(_keys[0]["t"])
	_key_span = float(_keys[_keys.size() - 1]["t"]) - _key_start
	_seconds = float(_options.get("seconds", 0.0))
	_seconds = maxf(_seconds, 0.1) if _seconds > 0.0 else float(shot["duration"])
	_delay = maxf(float(_options.get("delay", 0.0)), 0.0)
	_stage = String(_options.get("stage", ""))
	for dial: String in String(_options.get("set", "")).split(";", false):
		var eq: int = dial.find("=")
		if eq > 0:
			_dials[dial.substr(0, eq).strip_edges()] = dial.substr(eq + 1).strip_edges()
	_plugin = _load_stage(_stage)

	_pov = String(_options.get("pov", ""))
	_track = String(_options.get("track", ""))
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
	var bots: int = int(_options.get("bots", 7))
	if _plugin != null:
		bots = maxi(bots, _plugin.bots())
		if _plugin.needs_pov() != "" and _pov != _plugin.needs_pov():
			_fail("--stage=%s is filmed with --pov=%s." % [_stage, _plugin.needs_pov()])
			match_root.free()
			return
	_make_it_bots_only(match_root, bots)

	root.add_child(match_root)
	_park_the_human(match_root)
	if String(_options.get("pads", "")) == "off":
		print("[stage] %d boost pads disarmed" % STAGE_LIB.disarm_pads(match_root))
	if String(_options.get("traps", "")) == "off":
		print("[stage] %d traps disarmed" % STAGE_LIB.disarm_traps(match_root))
	if _pov == "":
		_camera = _make_camera()
		root.add_child(_camera)
		_camera.current = true

	if String(_options.get("look", "")) == "social":
		_light_for_social(match_root)
	_take_the_eye(match_root)
	_listen_to_audio()
	if String(_options.get("audio", "")) == "near":
		_keep_audio_near()

	# Before start_match, exactly as the sweep does it: the first seat is granted
	# from inside that call and a seat brain armed afterwards would miss it.
	# chainrun wants no seat at all: an unmanned tower never fires, so no round
	# ends and the staged body is still on the chain when the path finishes.
	if _stage != "chainrun":
		_seat = BotTowerSeat.new()
		_seat.name = "ClipTowerSeat"
		root.add_child(_seat)
		_seat.install(_controller, _shooter_profile(), seed_value)
	if _stage == "chainrun":
		_disarm_traps(^"Sections/S2_LavaShelf")
	elif _wants_chain():
		# Only the entry bank: the runner must reach the chain, and then must die.
		_disarm_traps(^"Sections/S2_LavaShelf", "TrapVolume")
	# A clip outlives the match it is filming: a won match freezes every body,
	# and a frozen ring is not b-roll.
	_controller.match_won.connect(func(_winner: MatchParticipant) -> void: _controller.restart())
	# A resolved ROUND freezes the ring just as a won match does, and a guard
	# clip is mostly rounds: without this the tower stops moving the moment the
	# last prisoner is converted and films a still life until the clip ends.
	_controller.round_resolved.connect(
		func(_outcome: MatchController.Outcome) -> void:
			_controller.start_round.call_deferred()
	)
	_log_events()
	if _plugin != null:
		_plugin.before_start()
	_controller.start_match()
	# A guard only exists in a round: the race has nobody in the tower, so a
	# POV clip that waits for one films an empty chamber for a minute, and a
	# runner filmed in the race is never shot at.
	if _stage == "decoy" or _stage == "ghostchase":
		_watch_the_deck(STAGE_DRIVER.HIDDEN_DEGREES - 16.0)
	elif _stage == "shovecover":
		# Where the shoved runner lands: the guard is already looking there.
		_watch_the_deck(STAGE_DRIVER.COVER_DEGREES + 11.0)
		_arm_the_tower_on_the_shove()
	if _pov != "" or _is_driven_stage():
		_controller.start_round()

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
	var map_id: String = String(_options.get("map", ""))
	if not map_id.is_empty():
		rules.map_id = StringName(map_id)
	if _plugin != null:
		_plugin.tune_rules(rules)
	elif _stage == "missstreak":
		# Fifteen misses fit in a clip only if the rifle comes back fast.
		rules.base_reload_seconds = 0.7
	elif _stage == "shovecover":
		# The first shot is at a body still in the air; the second has to land
		# before the beat is over.
		rules.base_reload_seconds = 0.9
	_controller.rules = rules

	# The placeholder music loop is still feeding the audio server when the
	# engine tears the tree down, which is reported as a leaked instance and
	# fails a smoke run. B-roll gets its music in the edit.
	var music: Node = match_root.get_node_or_null(^"Music")
	if music != null:
		music.free()

	# SettingsBoot writes the player's saved settings over the rules, which would
	# make the same seed film a different match on a different machine -- and,
	# deferred from its _ready, the saved brightness over the environment's
	# exposure, which flattened every lifted grade (a disabled node's _ready
	# still runs). It is freed, not disabled: a clip is filmed at the numbers
	# in its brief, never at one machine's settings.
	var settings_boot: Node = match_root.get_node_or_null(^"SettingsBoot")
	if settings_boot != null:
		settings_boot.free()
	var silenced: Array[String] = [
		"NetMatch", "HUD", "FeedbackRig", "SpectatorView", "SeatHandover",
		"FreeCamera", "DeathScreen", "RoundTransition", "ResultScreen", "PauseMenu",
	]
	if _pov != "":
		# A POV clip is a player's view: it wants the camera kick, and the
		# readouts only when asked for -- Ryan: no HUD elements on any shot.
		silenced.erase("FeedbackRig")
		if String(_options.get("hud", "")) == "on":
			silenced.erase("HUD")
		# --hud=crosshair leaves the HUD silenced (its _ready hides every panel
		# and, disabled, its tick never shows them again); the crosshair alone
		# is switched back on once a body is ridden (_wear_the_body).
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
	# The shipped 0.3 m near plane slices the rock open when a flown shot passes
	# close to it; a clip would rather see a wall than see through one.
	camera.near = NEAR_METRES
	# The fov is the VERTICAL one: a portrait take (1080x1920) composes for the
	# height, and a key's fov reads the same on a phone as it did when it was
	# framed. (52 deg across a 9:16 frame is 82 deg tall.)
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	return camera


## A private copy of the tuned shooter profile, for the same reason
## [BotMatchRunner] takes one: [BotTowerSeat] writes a seed into it per body.
func _shooter_profile() -> ShooterProfile:
	var profile: ShooterProfile = load(BotMatchRunner.SHOOTER_PROFILE_PATH) as ShooterProfile
	var copy: ShooterProfile = profile.duplicate() as ShooterProfile
	if _plugin != null:
		_plugin.tune_shooter(copy)
	elif _stage == "firefight" or _stage == "decoy":
		_make_it_quick(copy)
	elif _stage == "missstreak":
		# Quick to fire and bad at it.
		copy.scan_yaw_rate = 2.4
		copy.reaction_seconds = 0.05
		copy.reaction_floor_seconds = 0.02
		copy.shot_confidence_threshold = 0.0
		copy.sure_shot_confidence = 0.0
		copy.aim_error_degrees = 6.0
		copy.aim_error_resample_seconds = 0.15
		copy.aim_tolerance_degrees = 45.0
		copy.confident_range = 120.0
	elif _is_driven_stage():
		# The tower watches and never fires: the staged body finishes its beat.
		copy.shot_confidence_threshold = 1.0
		copy.sure_shot_confidence = 1.0
	return copy


## The shipped guard takes most of a clip to decide. This one does not: it is
## the same brain with its patience removed, on a throwaway copy.
func _make_it_quick(copy: ShooterProfile) -> void:
	copy.scan_yaw_rate = 2.4
	copy.reaction_seconds = 0.08
	copy.shot_confidence_threshold = 0.15
	copy.aim_error_degrees = 0.3
	copy.confident_range = 120.0
	# A hologram is only a clip if the guard falls for it.
	copy.decoy_suspicion_seconds = 0.0


## shovecover: the tower watches and never fires while the shover crosses the
## open deck to the cover. The shove stands the victim up (their driver moves
## off the crouch), and once they have landed, upright in the open, the tower
## turns quick and dead accurate: one shot, and it is the kill. Ryan on the
## first cut: "just a shot that misses, then another shot that hits, with
## them crouching".
func _arm_the_tower_on_the_shove() -> void:
	var stand := func(_shover: MatchParticipant, _victim: MatchParticipant) -> void:
		if _victim_driver != null:
			_victim_driver.advance()
		_arm_after_landing = true
	_controller.participant_shoved.connect(stand, CONNECT_ONE_SHOT)


## The shoved runner is back on the deck and standing: now the tower may fire.
func _arm_the_tower_when_landed() -> void:
	if not _arm_after_landing or _seat == null or _victim_body == null or not is_instance_valid(_victim_body):
		return
	if not _victim_body.is_on_floor() or _victim_body.get_horizontal_speed() > 1.0:
		return
	var shooter: TowerShooter = _seat.get_active_shooter()
	if shooter == null or shooter.profile == null:
		return
	var quick: ShooterProfile = shooter.profile.duplicate() as ShooterProfile
	_make_it_quick(quick)
	# One shot, the kill: no aim error, and no firing before the aim is on them.
	quick.aim_error_degrees = 0.0
	quick.shot_confidence_threshold = 0.85
	quick.sure_shot_confidence = 0.85
	shooter.profile = quick
	_arm_after_landing = false
	print("[stage] %s: victim landed standing; tower armed" % _stage)


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
	# being ridden instead, which _ride_a_body reparents it to.
	if _camera != null:
		_camera.add_child(_fill)
	else:
		root.add_child(_fill)


func _wants_chain() -> bool:
	return _stage == "chainrun" or _stage == "shovecatch" or _stage == "ghostcatch"


## Put the first living prisoner on the S2 chain instead of on the lane.
func _stage_chainrun() -> void:
	var runners: Array[RunnerBrain] = _controller.get_live_runners()
	if runners.is_empty() or runners[0].controller == null:
		return
	_chain = CHAIN_STAGE.new()
	_chain.name = "ClipChainStage"
	root.add_child(_chain)
	_chain.install(runners[0].controller, runners[0])


## A stage that plays inside a round with a tower that watches and never fires.
func _is_driven_stage() -> bool:
	return _plugin != null or STAGE_DRIVER.is_stage(_stage) or _stage == "ghostpack"


## The stage plugin called [param stage_name] under tools/capture/stages/, or null.
func _load_stage(stage_name: String) -> RefCounted:
	if stage_name.is_empty() or stage_name == "stage" or stage_name == "lib" or stage_name == "guard_hand":
		return null
	var path: String = STAGES_DIR + stage_name + ".gd"
	if not ResourceLoader.exists(path):
		return null
	var script: GDScript = load(path) as GDScript
	if script == null:
		_fail("%s would not load." % path)
		return null
	var plugin: RefCounted = script.new() as RefCounted
	if plugin == null or not plugin.has_method("cast"):
		_fail("%s is not a stage (it must extend tools/capture/stages/stage.gd)." % path)
		return null
	plugin.set("clip", self)
	print("[stage] plugin %s" % path)
	return plugin


## Hand one prisoner to the stage driver; the chain stages hand it the second one.
func _stage_driven() -> void:
	var runners: Array[RunnerBrain] = _controller.get_live_runners()
	if _stage == "ghostchase":
		_stage_ghostchase(runners)
		return
	if _stage in ["shovecover", "shoveedge", "shoveedge_look", "shovelake"]:
		_stage_pair(runners)
		return
	var wanted: int = 1 if _wants_chain() else 0
	if runners.size() <= wanted or runners[wanted].controller == null:
		return
	var runner: RunnerBrain = runners[wanted]
	var victim: PlayerController = runners[0].controller if _wants_chain() else null
	_victim_body = victim
	if _stage == "ghostcatch":
		_make_a_ghost(runner)
	_driver = STAGE_DRIVER.new()
	_driver.name = "ClipStageDriver"
	root.add_child(_driver)
	_driver.install(runner.controller, runner, STAGE_DRIVER.steps_for(_stage, victim))
	_staged = runner.controller
	print("[stage] %s drives %s" % [_stage, runner.controller.name])


## Two prisoners on the open S3 lane: the first runs it, the second is made a
## ghost ten metres behind and runs the first down. The shove is the catch; the
## swap is the match's own (see MatchController._swap_with_ghost), and once the
## bodies have traded roles both go back to their brains.
func _stage_ghostchase(runners: Array[RunnerBrain]) -> void:
	if runners.size() < 2 or runners[0].controller == null or runners[1].controller == null:
		return
	var victim: RunnerBrain = runners[0]
	var ghost: RunnerBrain = runners[1]
	_victim_driver = STAGE_DRIVER.new()
	_victim_driver.name = "ClipVictimDriver"
	root.add_child(_victim_driver)
	_victim_driver.install(victim.controller, victim, STAGE_DRIVER.steps_for("ghostchase_victim", null))
	_staged = victim.controller
	_make_a_ghost(ghost)
	ghost.controller.speed_scale = CHASE_GHOST_SPEED_SCALE
	_driver = STAGE_DRIVER.new()
	_driver.name = "ClipStageDriver"
	root.add_child(_driver)
	_driver.install(ghost.controller, ghost, STAGE_DRIVER.steps_for(_stage, victim.controller))
	_ghost_body = ghost.controller
	# The caught prisoner is a ghost on the start line three seconds from now;
	# its own brain, not the lane run, is what it should wake up to.
	_controller.ghost_caught.connect(
		func(_ghost: MatchParticipant, _caught: MatchParticipant) -> void:
			if _victim_driver != null:
				_victim_driver.release()
	)
	print("[stage] %s: %s runs, %s hunts" % [_stage, victim.controller.name, ghost.controller.name])


## Two prisoners, both driven: the first is the victim (placed by the stage's
## _victim steps and ridden by --pov=runner), the second the one who shoves.
## Neither goes back to its brain: the beat is the whole clip.
func _stage_pair(runners: Array[RunnerBrain]) -> void:
	if runners.size() < 2 or runners[0].controller == null or runners[1].controller == null:
		return
	var victim: RunnerBrain = runners[0]
	var shover: RunnerBrain = runners[1]
	_victim_driver = STAGE_DRIVER.new()
	_victim_driver.name = "ClipVictimDriver"
	root.add_child(_victim_driver)
	_victim_driver.install(victim.controller, victim, STAGE_DRIVER.steps_for(_stage + "_victim", null))
	_staged = victim.controller
	_victim_body = victim.controller
	_driver = STAGE_DRIVER.new()
	_driver.name = "ClipStageDriver"
	root.add_child(_driver)
	_driver.install(shover.controller, shover, STAGE_DRIVER.steps_for(_stage, victim.controller))
	print("[stage] %s: %s is shoved by %s" % [_stage, victim.controller.name, shover.controller.name])


## Ghost the prisoner at the back of the pack and let its own brain hunt: the
## shipped chase, at the shipped three times pace, through the round's own field.
func _stage_ghostpack() -> void:
	var runners: Array[RunnerBrain] = _controller.get_live_runners()
	if runners.size() < 2:
		return
	var hindmost: RunnerBrain = runners[runners.size() - 1]
	if hindmost.controller == null:
		return
	_make_a_ghost(hindmost)
	_ghost_body = hindmost.controller
	print("[stage] %s: %s ghosted behind %d runners" % [_stage, hindmost.controller.name, runners.size() - 1])


## Give the tower a watch point on the open S3 deck, which the shipped guard only
## catches at the edge of its S2 sweep; the hologram has to be looked at to be shot.
func _watch_the_deck(degrees: float) -> void:
	var marker := Marker3D.new()
	marker.name = "ClipWatch"
	marker.add_to_group(TowerShooter.WATCH_GROUP)
	root.add_child(marker)
	# First in tree order is first on the guard's scan: it looks here before the ring's own points.
	root.move_child(marker, 0)
	marker.global_position = SHOTS.ring_point(degrees, 52.0, 1.0)


## Turn [param runner]'s participant into a ghost that is in the world now, not
## in three seconds on the start line.
func _make_a_ghost(runner: RunnerBrain) -> void:
	for participant: MatchParticipant in _controller.get_participants():
		if participant.brain != runner:
			continue
		_controller._make_ghost(participant)
		participant.respawn_hold_remaining = 0.0
		_controller._finish_respawn(participant)
		participant.ghost_grace_remaining = 0.0
		return


## Stop the lava under [param section] killing the staged body mid-leap; [param only]
## names one trap to disarm, or every one when empty.
func _disarm_traps(section: NodePath, only: String = "") -> void:
	var node: Node = _controller.arena.get_node_or_null(section) if _controller.arena != null else null
	if node == null:
		printerr("No %s under the arena; nothing disarmed." % section)
		return
	for child: Node in node.get_children():
		var area: Area3D = child as Area3D
		if area != null and (only.is_empty() or child.name == only):
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
	# A flown shot points down its own velocity: the lens leads the path by
	# look_ahead seconds until look_ahead_until, and only then reads a key's
	# look target -- which is what lets one path fly a lap and then turn.
	if _look_ahead > 0.0 and path_time < _look_ahead_until:
		var ahead: Vector3 = SHOTS.sample(_keys, path_time + _look_ahead)["pos"]
		if position.distance_squared_to(ahead) > 0.0004:
			target = ahead
	if _track == "victim":
		target = _tracked_target(target)
	_camera.global_position = position
	if position.distance_squared_to(target) > 0.0001:
		_camera.look_at(target, Vector3.UP)
	var roll: float = float(pose.get("roll", 0.0))
	if not is_zero_approx(roll):
		_camera.rotate_object_local(Vector3(0.0, 0.0, 1.0), deg_to_rad(roll))
	_camera.fov = float(pose["fov"])
	# Re-asserted rather than assumed: the match scene carries three other
	# cameras that can claim the viewport, and a clip filmed from one of them is
	# a clip nobody can tell is wrong until it is watched.
	if not _camera.current:
		_camera.current = true


## Where a tracking shot looks: the staged victim's chest while it is on the
## deck, then the last place it was seen -- the lens holds where the body went
## over the rim or under the lava, and the body falls out of the frame rather
## than being chased down by it.
func _tracked_target(path_target: Vector3) -> Vector3:
	if _victim_body != null and is_instance_valid(_victim_body) and not _tracking_stopped:
		var at: Vector3 = _victim_body.global_position
		var participant: MatchParticipant = _controller.resolve_participant(_victim_body)
		if at.y < DECK_Y - TRACK_BELOW_DECK_METRES or Vector2(at.x, at.z).length() < _rim_r():
			_tracking_stopped = true
		elif participant != null and participant.is_running:
			_tracked_look = at + Vector3.UP * 0.9
			_tracking = true
	return _tracked_look if _tracking else path_target


## The deck's inner radius, read off the map's own route data.
func _rim_r() -> float:
	var level: Node = _controller.arena.get_node_or_null(^"Route/Level1") if _controller.arena != null else null
	return float(level.get("inner_radius")) if level != null else RIM_R_FALLBACK


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


## Print the tower's shots once a brain holds the rifle; a take is judged off the log.
func _log_the_rifle() -> void:
	if _seat == null:
		return
	var shooter: TowerShooter = _seat.get_active_shooter()
	if shooter == null or shooter == _logged_shooter:
		return
	_logged_shooter = shooter
	shooter.shot_taken.connect(
		func(confidence: float) -> void:
			print("[event] %6.2f  shot  confidence %.2f" % [_elapsed, confidence])
			if _plugin != null:
				_plugin.on_shot(confidence)
			_flag_the_drivers("shot")
	)


## Print the match's beats, so a take can be judged off its log.
func _log_events() -> void:
	_controller.participant_shoved.connect(
		func(shover: MatchParticipant, victim: MatchParticipant) -> void:
			var at: Vector3 = victim.body.global_position
			print("[event] %6.2f  shove  %s -> %s at %.1f deg r %.1f" % [
				_elapsed, shover.body.name, victim.body.name,
				fposmod(rad_to_deg(atan2(at.z, at.x)), 360.0), Vector2(at.x, at.z).length(),
			])
			if _pov != "" and victim.body == _pov_body:
				_kick_the_ridden_camera(-shover.body.global_transform.basis.z)
			if _plugin != null:
				_plugin.on_shove(shover, victim)
			_flag_the_drivers("shove")
	)
	if _controller.rifle != null:
		_controller.rifle.target_hit.connect(
			func(collider: Node3D, _at: Vector3, _n: Vector3) -> void:
				print("[event] %6.2f  hit  %s" % [_elapsed, collider.name if collider != null else "?"])
				if _plugin != null:
					_plugin.on_hit(collider)
				_flag_the_drivers("hit")
		)
		_controller.rifle.missed.connect(
			func(_end: Vector3) -> void:
				print("[event] %6.2f  miss" % _elapsed)
				_flag_the_drivers("miss")
		)
	_controller.participant_converted.connect(
		func(participant: MatchParticipant) -> void:
			var at: Vector3 = participant.body.global_position
			print("[event] %6.2f  out  %s  %s at %.1f deg r %.1f" % [
				_elapsed, participant.body.name, participant.death_cause,
				fposmod(rad_to_deg(atan2(at.z, at.x)), 360.0), Vector2(at.x, at.z).length(),
			])
			if _plugin != null:
				_plugin.on_out(participant)
	)
	_controller.ghost_caught.connect(
		func(ghost: MatchParticipant, caught: MatchParticipant) -> void:
			print("[event] %6.2f  catch  %s took %s" % [_elapsed, ghost.body.name, caught.body.name])
	)
	_controller.runner_ghosted.connect(
		func(participant: MatchParticipant) -> void:
			print("[event] %6.2f  ghosted  %s" % [_elapsed, participant.body.name])
	)
	# The finish: in the race, the first body through the portal takes the tower.
	_controller.seat_changed.connect(
		func(participant: MatchParticipant, turns: int) -> void:
			print("[event] %6.2f  seat  %s  turn %d" % [_elapsed, participant.body.name, turns])
	)


## Raise [param flag_name] on every stage driver in the tree: a "wait_flag"
## step finishes on it (the flinch when the one beside us drops).
func _flag_the_drivers(flag_name: String) -> void:
	for node: Node in root.get_children():
		if node.has_method("flag") and node.has_method("is_done"):
			node.flag(flag_name)


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

## Keep the view down a living body's own camera, changing body when the one
## being ridden is taken. The body's camera is never written to: only made
## current, which is what [FxSpectatorView] does for a dead player.
func _ride_a_body() -> void:
	# A shot prisoner is not freed, it is buried a hundred metres under the deck,
	# so "still valid" is not "still worth watching": the same standing test that
	# picks a body has to keep deciding whether to stay on it.
	# The staged body is the one the shot is about: move onto it the moment
	# it exists, whichever prisoner the clip was riding until then.
	if _pov == "runner" and _staged != null and is_instance_valid(_staged) and _pov_body != _staged:
		if _is_standing(_staged) and _eye_of(_staged) != null:
			_pov_body = null
	if _pov_body != null and is_instance_valid(_pov_body) and (_is_standing(_pov_body) or _still_in_it(_pov_body)):
		var riding: Camera3D = _eye_of(_pov_body)
		if riding != null and riding.current and not _is_stuck(_pov_body):
			_hand_over_the_scope(_pov_body)
			return
	if _pov == "guard":
		_ride_the_guard()
		return
	if _pov == "ghost":
		_ride_the_ghost()
		return
	for participant: MatchParticipant in _wanted_participants():
		var body: PlayerController = participant.body
		if body == null or not _is_standing(body):
			continue
		if body == _pov_body:
			continue
		var camera: Camera3D = _eye_of(body)
		if camera == null:
			continue
		camera.current = true
		_pov_body = body
		_wear_the_body(body)
		_stuck_for = 0.0
		print("[pov] %5.2f ride %s at %v" % [_elapsed, body.name, body.global_position])
		return


## Ride the body the tower's brain is actually aiming.
##
## [method MatchController.get_seat_participant] answers nothing in a bots-only
## match, so the seat is found from the other end: [TowerShooter] holds the
## [PlayerController] it drives, and that controller's head camera IS the aim --
## the brain writes look intent into it every tick, so ADS, the scope, the recoil
## kick and the reload all reach the lens for real.
func _ride_the_guard() -> void:
	if _seat == null:
		return
	var shooter: TowerShooter = _seat.get_active_shooter()
	if shooter == null:
		return
	var body: PlayerController = shooter.controller
	if body == null:
		return
	var camera: Camera3D = _eye_of(body)
	if camera == null:
		return
	camera.current = true
	_pov_body = body
	_wear_the_body(body)
	print("[pov] %5.2f guard %s at %v" % [_elapsed, body.name, body.global_position])


## Ride the staged ghost, and stay on that body through the catch: it is a
## prisoner afterwards, and the lens that saw the shove sees what it bought.
func _ride_the_ghost() -> void:
	if _ghost_body == null or not is_instance_valid(_ghost_body):
		return
	var camera: Camera3D = _eye_of(_ghost_body)
	if camera == null:
		return
	camera.current = true
	_pov_body = _ghost_body
	_wear_the_body(_ghost_body)
	print("[pov] %5.2f ghost %s at %v" % [_elapsed, _ghost_body.name, _ghost_body.global_position])


## The participants this clip is willing to ride, best first.
func _wanted_participants() -> Array[MatchParticipant]:
	var running: Array[MatchParticipant] = []
	for participant: MatchParticipant in _controller.get_participants():
		if not participant.is_running or participant.is_ghost or participant.body == null:
			continue
		if not _on_the_lane(participant.body):
			continue
		running.append(participant)
	# The one already going fastest: a body wedged in the pit wall reads as
	# running for the whole match and is the last thing worth filming.
	running.sort_custom(
		func(a: MatchParticipant, b: MatchParticipant) -> bool:
			if a.body == _staged or b.body == _staged:
				return a.body == _staged
			return a.body.get_horizontal_speed() > b.body.get_horizontal_speed()
	)
	return running


## True while [param body] is on the walkable band rather than inside a wall.
func _on_the_lane(body: Node3D) -> bool:
	var radius: float = Vector2(body.global_position.x, body.global_position.z).length()
	return radius >= LANE_BAND.x and radius <= LANE_BAND.y


## True once the body being ridden has stopped travelling for good.
func _is_stuck(body: PlayerController) -> bool:
	if _pov == "guard" or body == _staged or body == _ghost_body:
		return false
	if body.get_horizontal_speed() > STUCK_SPEED or not _on_the_lane(body):
		_stuck_for = 0.0
		return not _on_the_lane(body)
	_stuck_for += root.get_process_delta_time()
	return _stuck_for >= STUCK_SECONDS


## True while the staged victim is off the deck but not yet out: shoved over
## the rim it falls thirty metres, and that fall is the shot.
func _still_in_it(body: PlayerController) -> bool:
	if body != _staged or body != _victim_body:
		return false
	var participant: MatchParticipant = _controller.resolve_participant(body)
	return participant != null and participant.is_running


func _eye_of(body: Node3D) -> Camera3D:
	return body.get_node_or_null(^"Head/Camera") as Camera3D


## True while [param body] is on the deck or in the tower, not buried under them.
func _is_standing(body: Node3D) -> bool:
	return absf(body.global_position.y - DECK_Y) <= 6.0


## Tell the game this bot is the body being looked out of.
##
## The one call that matters: [PrisonerAvatar] then collapses this body's head,
## spine and raised arms exactly as it does the local player's, leaves every
## other body whole, and [MatchHud] draws this seat's readout.
func _wear_the_body(body: PlayerController) -> void:
	PrisonerAvatar.set_viewed_body(body)
	_hand_over_the_scope(body)
	if String(_options.get("hud", "")) == "crosshair" and STAGE_LIB.show_only_the_crosshair(root):
		print("[pov] crosshair on, rest of the HUD off")
	# No fill on a ridden body. Hung at the eye it sits inside the body's own
	# capsule and washes the whole frame to a flat gradient; the ambient lift in
	# _light_for_social is what a POV clip gets instead.
	if _fill != null:
		_fill.light_energy = 0.0


## Whip the ridden body's camera the way the game whips a player's: an
## [FxCameraKick] on its own camera, with the shipped feedback profile.
func _kick_the_ridden_camera(direction: Vector3) -> void:
	var eye: Camera3D = _eye_of(_pov_body)
	if eye == null:
		return
	if _pov_kick == null or _pov_kick.camera != eye:
		if _pov_kick != null:
			_pov_kick.queue_free()
		_pov_kick = FxCameraKick.new()
		_pov_kick.name = "ClipPovKick"
		_pov_kick.camera = eye
		_pov_kick.profile = load(FEEDBACK_PROFILE_PATH) as FeedbackProfile
		root.add_child(_pov_kick)
	_pov_kick.strike(direction, POV_SHOVED_KICK_SCALE)
	print("[pov] %5.2f kick" % _elapsed)


## Draw the scope for the guard being ridden.
##
## [ScopeVignette] only paints for the person holding the rifle at this keyboard,
## which in a bots-only match is nobody. The rifle is reparented onto whoever
## takes the tower, so it is looked up under the body rather than kept in a path.
func _hand_over_the_scope(body: Node) -> void:
	if _pov != "guard":
		return
	var rifle: Rifle = _find_kind(body, "Rifle") as Rifle
	if rifle == null:
		return
	var vignette: ScopeVignette = rifle.get_node_or_null(^"ScopeVignette") as ScopeVignette
	if vignette != null:
		vignette.set_local_holder(true)


## The first node under [param from] whose class is [param wanted].
func _find_kind(from: Node, wanted: String) -> Node:
	var pending: Array[Node] = [from]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.is_class(wanted) or node.get_script() != null and node.get_class() == wanted:
			return node
		if node.get_script() != null and String(node.get_script().get_global_name()) == wanted:
			return node
		for child: Node in node.get_children():
			pending.append(child)
	return null


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


# --- The watcher --------------------------------------------------------------

## Take the tower's eye off its own poll.
##
## [method WatchingEye._process] points the pupil at whatever camera is current,
## every frame, which means a clip finds it already staring before the shot has
## turned onto it. Driven from here it can be looking somewhere else first.
func _take_the_eye(match_root: Node) -> void:
	_eye = _find_node(match_root, "Watcher") as Node3D
	if _eye == null or not _eye.has_method("turn_toward"):
		_eye = null
		return
	_eye.process_mode = Node.PROCESS_MODE_DISABLED


## Look down the ring, then come round onto the camera as the pan settles.
func _turn_the_eye(delta: float) -> void:
	if _eye == null or _camera == null:
		return
	var swing_start: float = _seconds - EYE_SWING_SECONDS - EYE_SETTLE_SECONDS
	var swing: float = clampf((_elapsed - _delay - swing_start) / EYE_SWING_SECONDS, 0.0, 1.0)
	var elsewhere: Vector3 = SHOTS.ring_point(EYE_ELSEWHERE_DEGREES, 52.0, 1.0)
	var looked_at: Vector3 = elsewhere.lerp(_camera.global_position, smoothstep(0.0, 1.0, swing))
	_eye.call(&"turn_toward", _eye.call(&"gaze_direction_for", looked_at), delta)
