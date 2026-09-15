extends RefCounted

## The base of a stage plugin: one beat of staged action for a clip, kept in
## its own file under tools/capture/stages/ and loaded by run_clip.gd when
## [code]--stage=NAME[/code] names it (a plugin wins over a stage of the same
## name in stage_driver.steps_for). Override what the beat needs; the rest is
## inert.
##
## The clip hands itself in as [member clip]: the SceneTree running
## run_clip.gd, whose root, [code]_controller[/code], [code]_seat[/code],
## [code]_camera[/code], [code]_options[/code] and helpers are the plugin's to
## use. Bodies are placed by explicit ring-polar positions and driven by
## stage_driver.gd steps; nothing here is reachable from a match.
##
## Order of calls: [method bots] and [method needs_pov] before the scene is
## built; [method tune_rules] on the private rules copy; [method tune_shooter]
## on the seat's private profile; [method before_start] with the scene in the
## tree, before start_match; then every frame from 0.6 s [method cast] until it
## returns true, and [method tick]; [method lens] every frame the clip is not
## riding a body; [method on_shove], [method on_shot], [method on_hit],
## [method on_out] as the match reports them.

const LIB := preload("res://tools/capture/stages/lib.gd")
const DRIVER := preload("res://tools/capture/stage_driver.gd")

var clip: SceneTree = null
## The drivers this stage made, in the order it made them.
var drivers: Array = []


## Prisoners the beat needs (plus one in the tower). --bots below this is raised to it.
func bots() -> int:
	return 2


## "guard", "runner" or "" when the beat only works down one set of eyes.
func needs_pov() -> String:
	return ""


## Retune the match's private rules copy (reload, shove impulse, ghosts off).
func tune_rules(_rules: MatchRules) -> void:
	pass


## Retune the tower seat's private profile. Default: a tower that watches and
## never fires, so the staged bodies finish their beat.
func tune_shooter(profile: ShooterProfile) -> void:
	LIB.dead_shooter(profile)


## The scene is in the tree, the match not yet started: watch points, disarming.
func before_start() -> void:
	pass


## Hand out the drivers. Called each frame from 0.6 s until it returns true.
func cast(_runners: Array[RunnerBrain]) -> bool:
	return true


## Every frame after the world exists.
func tick(_delta: float) -> void:
	pass


## A lens of the stage's own (a chase, a tracking dolly). Return true when the
## camera was placed; false lets the shot path fly it.
func lens(_delta: float) -> bool:
	return false


func on_shove(_shover: MatchParticipant, _victim: MatchParticipant) -> void:
	pass


func on_shot(_confidence: float) -> void:
	pass


func on_hit(_collider: Node3D) -> void:
	pass


func on_out(_participant: MatchParticipant) -> void:
	pass


# --- Helpers every stage reaches for ------------------------------------------

## A driver on [param runner], seeded per index so a group never syncs.
func drive(runner: RunnerBrain, steps: Array, index: int = 0, driver_name: String = "") -> Node:
	var driver: Node = DRIVER.new()
	driver.name = driver_name if driver_name != "" else "ClipStageDriver%d" % drivers.size()
	clip.root.add_child(driver)
	driver.install(runner.controller, runner, steps, controller())
	driver.seed_with(int(clip._options.get("seed", 0)), index)
	drivers.append(driver)
	return driver


func controller() -> MatchController:
	return clip._controller


func seat() -> BotTowerSeat:
	return clip._seat


func camera() -> Camera3D:
	return clip._camera


func elapsed() -> float:
	return clip._elapsed


## A dial from --set=key=value;..., or the clip's own option of that name.
func option(key: String, fallback: Variant) -> Variant:
	if clip._dials.has(key):
		var raw: String = String(clip._dials[key])
		match typeof(fallback):
			TYPE_INT:
				return int(raw)
			TYPE_FLOAT:
				return float(raw)
			TYPE_BOOL:
				return raw == "true" or raw == "1" or raw == "yes"
			_:
				return raw
	var value: Variant = clip._options.get(key, fallback)
	return fallback if value == null or str(value) == "" else value


## The body --pov=runner rides and --track=victim follows.
func stage_body(body: PlayerController) -> void:
	clip._staged = body


func victim_body(body: PlayerController) -> void:
	clip._victim_body = body


## Raise a flag on every driver: a "wait_flag" step on it finishes.
func flag_all(flag_name: String) -> void:
	for driver: Node in drivers:
		if is_instance_valid(driver):
			driver.flag(flag_name)


func say(message: String) -> void:
	print("[stage] %6.2f  %s" % [clip._elapsed, message])
