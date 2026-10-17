extends "res://tools/capture/stages/stage.gd"

## rs_live: a normal match, the shipped bot guard (TowerShooter) shooting at bullet speed; nothing staged.
## No hit marker; see on_shot for the scope's hold.
## Dials: speed (195, rules.guard_projectile_speed), hold (1.6), flight (0.45), follow (5: how fast the scope eases after the body), lift (1, the guard_alone grade), clear (0.74), old (0),
## ride (a runner's name: --pov=runner stays on that body), beat (the finale's kill beat, shipped 2.0),
## ahead and sure (the bot's cover look-ahead and sure-shot confidence; shipped 0.35, 0.9),
## tower_fov (0: off; the ridden runner's lens fov inside the tower until he holds it, so the shove shows the guard whole).

var _guard: PlayerController = null
var _held: float = 0.0
var _held_shooter: TowerShooter = null
var _fallen: PlayerController = null
var _base_fov: float = 0.0


## --bots sets the ring (shorts cap at 4 players with the guard).
func bots() -> int:
	return 0


## Any eyes: the guard's scope for the kills, a runner's (--pov=runner) for a finale played out.
func needs_pov() -> String:
	return ""


func tune_rules(rules: MatchRules) -> void:
	rules.guard_projectile_speed = float(option("speed", 195.0))
	rules.guard_hit_marker = false
	rules.kill_beat_seconds = float(option("beat", rules.kill_beat_seconds))


## The shipped profile unless ahead/sure are set: the base would stand the tower down.
func tune_shooter(profile: ShooterProfile) -> void:
	profile.cover_lookahead_seconds = float(option("ahead", profile.cover_lookahead_seconds))
	profile.sure_shot_confidence = float(option("sure", profile.sure_shot_confidence))


func before_start() -> void:
	if int(option("lift", 1)) == 1:
		var world: WorldEnvironment = LIB.find_node(clip.root, "WorldEnvironment") as WorldEnvironment
		if world != null and world.environment != null:
			var env: Environment = world.environment.duplicate() as Environment
			env.tonemap_exposure = 3.8
			env.ambient_light_energy = 3.6
			world.environment = env


## old=1: every runner's death ragdoll off, so a kill plays the pre-ragdoll "Death" clip.
func cast(runners: Array[RunnerBrain]) -> bool:
	var ride: String = String(option("ride", ""))
	for brain: RunnerBrain in runners:
		if brain.controller != null and brain.controller.name == ride:
			stage_body(brain.controller)
			say("rs_live: riding %s" % ride)
	if int(option("old", 0)) == 1:
		for brain: RunnerBrain in runners:
			for avatar: Node in brain.controller.find_children("*", "PrisonerAvatar", true, false):
				avatar.set(&"_ragdoll", null)
		say("rs_live: ragdoll off, the old death clip")
	return true


## Down the guard's eyes the scope stays where it fired until the round lands (the brain would swing onto
## the next runner mid-flight); a kill holds it `hold` s more so the death plays out in frame.
func on_shot(_confidence: float) -> void:
	var shooter: TowerShooter = seat().get_active_shooter() if seat() != null else null
	if shooter != null and clip._pov == "guard":
		shooter.set_physics_process(false)
		_held_shooter = shooter
		_held = float(option("flight", 0.45))


func on_hit(collider: Node3D) -> void:
	if collider is PlayerController and _held_shooter != null:
		_held = float(option("hold", 1.6))
		_fallen = collider as PlayerController


## Through a kill's hold the scope eases after the body (its ragdoll's pelvis), as a player watches it go down.
func _watch_the_fall(delta: float) -> void:
	var avatar: PrisonerAvatar = PrisonerAvatar.of(_fallen)
	var body: PlayerController = _held_shooter.controller
	if avatar == null or body == null or body.head == null:
		return
	var to: Vector3 = avatar.drawn_centre() - body.head.global_position
	var view: Vector2 = body.get_view_angles()
	var want := Vector2(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	var ease: float = 1.0 - exp(-delta * float(option("follow", 5.0)))
	var turn := Vector2(angle_difference(view.x, want.x), want.y - view.y) * ease
	_held_shooter.input.command.look_delta = Vector2(-turn.x, turn.y if body.profile.invert_look_y else -turn.y)


func tick(delta: float) -> void:
	_widen_in_the_tower()
	if _held > 0.0:
		_held -= delta
		if _fallen != null and is_instance_valid(_fallen) and _held_shooter != null:
			_watch_the_fall(delta)
		# The seat reports no shooter while its brain is off, so the held one is kept here.
		if _held <= 0.0 and _held_shooter != null and is_instance_valid(_held_shooter):
			_held_shooter.input.command.look_delta = Vector2.ZERO
			_held_shooter.set_physics_process(true)
			_held_shooter = null
			_fallen = null
	if OS.has_environment("STAGE_DEBUG") and _guard != null and Engine.get_physics_frames() % 6 == 0:
		var av: PrisonerAvatar = PrisonerAvatar.of(_guard)
		if av != null and av._ragdoll != null and av._ragdoll.is_active():
			var c: Vector3 = av.drawn_centre()
			say("thrown at r %.1f y %.1f" % [Vector2(c.x, c.z).length(), c.y])
	if _guard != null or seat() == null:
		return
	var shooter: TowerShooter = seat().get_active_shooter()
	if shooter == null or shooter.controller == null:
		return
	_guard = shooter.controller
	LIB.open_the_scope(_guard, float(option("clear", 0.74)))
	say("rs_live: bot guard %s, projectile %.0f m/s" % [_guard.name, controller().rules.guard_projectile_speed])


## tower_fov: the ridden runner's eye widens once he is in the tower room (r < 15) and still a prisoner.
func _widen_in_the_tower() -> void:
	var fov: float = float(option("tower_fov", 0.0))
	var body: PlayerController = clip._pov_body as PlayerController
	if fov <= 0.0 or clip._pov != "runner" or body == null or not is_instance_valid(body):
		return
	var eye: Camera3D = clip._eye_of(body)
	var inside: bool = Vector2(body.global_position.x, body.global_position.z).length() < 15.0
	if eye == null:
		return
	if inside and not body.is_in_group(MatchController.GUARD_GROUP):
		if _base_fov <= 0.0:
			_base_fov = eye.fov
		eye.fov = fov
	elif _base_fov > 0.0:
		eye.fov = _base_fov
		_base_fov = -1.0
